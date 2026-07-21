using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

internal static class WishPetsNativeSetup
{
    private const string AppName = "wish pets";
    private const string AppFolderName = "wish pets";
    private const string SetupMutexName = "Global\\WishPetsNativeSetup";

    [STAThread]
    private static void Main(string[] args)
    {
        bool hasSetupLock = false;
        string tempRoot = null;
        Mutex setupMutex = null;

        try
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            setupMutex = new Mutex(true, SetupMutexName, out hasSetupLock);
            if (!hasSetupLock)
            {
                MessageBox.Show("wish pets setup is already running.", AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            bool silent = args != null && Array.Exists(args, arg => string.Equals(arg, "/silent", StringComparison.OrdinalIgnoreCase));
            string installDir = ResolveInstallDir(args);
            if (!silent)
            {
                installDir = ChooseInstallDir(installDir);
                if (installDir == null) return;
            }

            installDir = Path.GetFullPath(Environment.ExpandEnvironmentVariables(installDir));
            ValidateInstallDir(installDir);

            string installParent = Path.GetDirectoryName(installDir);
            if (string.IsNullOrEmpty(installParent))
            {
                throw new InvalidOperationException("Please choose a valid install folder.");
            }
            Directory.CreateDirectory(installParent);

            tempRoot = Path.Combine(installParent, ".wish-pets-setup-" + Guid.NewGuid().ToString("N"));
            string stagingDir = Path.Combine(tempRoot, "staging");
            Directory.CreateDirectory(stagingDir);

            string payloadPath = Path.Combine(Path.GetTempPath(), "wish-pets-native-payload-" + Guid.NewGuid().ToString("N") + ".zip");
            using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (input == null) throw new InvalidOperationException("Installer payload is missing.");
                using (var output = File.Create(payloadPath))
                {
                    input.CopyTo(output);
                }
            }

            ZipFile.ExtractToDirectory(payloadPath, stagingDir);
            TryDeleteFile(payloadPath);

            PrepareInstallDir(installDir, silent);
            Directory.Move(stagingDir, installDir);

            string launcher = Path.Combine(installDir, "WishPets.exe");
            string icon = Path.Combine(installDir, "build", "icon.ico");
            CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "wish pets.lnk"), launcher, icon);

            string startMenuDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "wish pets");
            Directory.CreateDirectory(startMenuDir);
            CreateShortcut(Path.Combine(startMenuDir, "wish pets.lnk"), launcher, icon);

            if (!silent)
            {
                Process.Start(new ProcessStartInfo { FileName = launcher, WorkingDirectory = installDir, UseShellExecute = true });
                MessageBox.Show("wish pets has been installed to:\n" + installDir, AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            if (tempRoot != null && Directory.Exists(tempRoot))
            {
                try { Directory.Delete(tempRoot, true); } catch { }
            }
            if (setupMutex != null)
            {
                if (hasSetupLock) setupMutex.ReleaseMutex();
                setupMutex.Dispose();
            }
        }
    }

    private static string ResolveInstallDir(string[] args)
    {
        string defaultDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            AppFolderName
        );

        if (args == null) return defaultDir;
        foreach (string arg in args)
        {
            if (arg == null) continue;
            if (arg.StartsWith("/dir=", StringComparison.OrdinalIgnoreCase))
            {
                return TrimQuotes(arg.Substring(5));
            }
            if (arg.StartsWith("/installDir=", StringComparison.OrdinalIgnoreCase))
            {
                return TrimQuotes(arg.Substring(12));
            }
        }
        return defaultDir;
    }

    private static string ChooseInstallDir(string defaultDir)
    {
        DialogResult start = MessageBox.Show(
            "This setup will install wish pets. You can choose where the app files are stored next.",
            AppName,
            MessageBoxButtons.OKCancel,
            MessageBoxIcon.Information
        );
        if (start != DialogResult.OK) return null;

        using (var dialog = new FolderBrowserDialog())
        {
            dialog.Description = "Choose the folder where wish pets will be installed.";
            dialog.SelectedPath = defaultDir;
            dialog.ShowNewFolderButton = true;
            return dialog.ShowDialog() == DialogResult.OK ? dialog.SelectedPath : null;
        }
    }

    private static void PrepareInstallDir(string installDir, bool silent)
    {
        if (!Directory.Exists(installDir)) return;

        bool isExistingInstall =
            File.Exists(Path.Combine(installDir, "WishPets.exe")) ||
            File.Exists(Path.Combine(installDir, "Run-RegionPetTrial.ps1")) ||
            File.Exists(Path.Combine(installDir, "wish-pets-assets.pak"));

        bool hasFiles = Directory.EnumerateFileSystemEntries(installDir).Any();
        if (hasFiles && !isExistingInstall)
        {
            throw new InvalidOperationException("The selected folder is not empty and does not look like an existing wish pets installation. Please choose an empty folder or the previous wish pets folder.");
        }

        if (!silent && isExistingInstall)
        {
            DialogResult answer = MessageBox.Show(
                "wish pets is already installed in this folder. Reinstall and replace the existing app files?",
                AppName,
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question
            );
            if (answer != DialogResult.Yes) throw new OperationCanceledException("Installation canceled.");
        }

        try
        {
            Directory.Delete(installDir, true);
        }
        catch (Exception ex)
        {
            throw new IOException("Could not replace the existing wish pets installation. Please quit wish pets first, then run setup again.\n\n" + ex.Message, ex);
        }
    }

    private static void ValidateInstallDir(string installDir)
    {
        string root = Path.GetPathRoot(installDir);
        if (string.Equals(root, installDir, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Please choose a folder, not a drive root.");
        }
    }

    private static string TrimQuotes(string value)
    {
        return (value ?? "").Trim().Trim('"');
    }

    private static void TryDeleteFile(string path)
    {
        if (string.IsNullOrEmpty(path)) return;
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch
        {
        }
    }

    private static void CreateShortcut(string shortcutPath, string targetPath, string iconPath)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null) return;

        object shell = Activator.CreateInstance(shellType);
        object shortcut = shellType.InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { shortcutPath });
        Type shortcutType = shortcut.GetType();
        shortcutType.InvokeMember("TargetPath", System.Reflection.BindingFlags.SetProperty, null, shortcut, new object[] { targetPath });
        shortcutType.InvokeMember("WorkingDirectory", System.Reflection.BindingFlags.SetProperty, null, shortcut, new object[] { Path.GetDirectoryName(targetPath) });
        shortcutType.InvokeMember("IconLocation", System.Reflection.BindingFlags.SetProperty, null, shortcut, new object[] { iconPath });
        shortcutType.InvokeMember("Save", System.Reflection.BindingFlags.InvokeMethod, null, shortcut, null);

        Marshal.FinalReleaseComObject(shortcut);
        Marshal.FinalReleaseComObject(shell);
    }
}
