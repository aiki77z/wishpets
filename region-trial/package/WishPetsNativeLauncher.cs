using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class WishPetsNativeLauncher
{
    private const string AppName = "wish pets";

    [STAThread]
    private static void Main(string[] args)
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(baseDir, "Run-RegionPetTrial.ps1");
        if (!File.Exists(scriptPath))
        {
            MessageBox.Show("Run-RegionPetTrial.ps1 was not found next to the launcher.", AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        string extraArgs = args == null || args.Length == 0 ? "" : " " + string.Join(" ", Array.ConvertAll(args, Quote));
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File " + Quote(scriptPath) + extraArgs,
            WorkingDirectory = baseDir,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        try
        {
            Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static string Quote(string value)
    {
        return "\"" + (value ?? "").Replace("\"", "\\\"") + "\"";
    }
}
