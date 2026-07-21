param(
  [string]$PetId = "yushi",
  [double]$Scale = 0.6,
  [int]$AlphaThreshold = 4,
  [int]$RegionAlphaThreshold = 12,
  [int]$EdgePadding = 2,
  [int]$DurationSeconds = 0,
  [switch]$ShowAllPets
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath ".").Path
$settingsPath = Join-Path $PSScriptRoot "settings.json"

if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
  $ps = (Get-Process -Id $PID).Path
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-STA",
    "-File", $PSCommandPath,
    "-PetId", $PetId,
    "-Scale", $Scale,
    "-AlphaThreshold", $AlphaThreshold,
    "-RegionAlphaThreshold", $RegionAlphaThreshold,
    "-EdgePadding", $EdgePadding,
    "-DurationSeconds", $DurationSeconds
  )
  if ($ShowAllPets) {
    $args += "-ShowAllPets"
  }
  Start-Process -FilePath $ps -ArgumentList $args
  exit
}

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Web.Extensions,System.IO.Compression,System.IO.Compression.FileSystem -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class RegionPetTrial
{
    private const int RGN_OR = 2;
    private const int WS_EX_LAYERED = 0x00080000;
    private const int ULW_ALPHA = 0x00000002;
    private const byte AC_SRC_OVER = 0x00;
    private const byte AC_SRC_ALPHA = 0x01;
    private const string AppMutexName = "Global\\WishPetsNativeApp";
    private static System.Threading.Mutex appMutex;

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;

        public POINT(int x, int y)
        {
            X = x;
            Y = y;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE
    {
        public int Width;
        public int Height;

        public SIZE(int width, int height)
        {
            Width = width;
            Height = height;
        }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct BLENDFUNCTION
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [DllImport("user32.dll")]
    private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect);

    [DllImport("gdi32.dll")]
    private static extern int CombineRgn(IntPtr hrgnDest, IntPtr hrgnSrc1, IntPtr hrgnSrc2, int fnCombineMode);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(
        IntPtr hwnd,
        IntPtr hdcDst,
        ref POINT pptDst,
        ref SIZE psize,
        IntPtr hdcSrc,
        ref POINT pptSrc,
        int crKey,
        ref BLENDFUNCTION pblend,
        int dwFlags
    );

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr hDC);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);

    public static void Run(string repoRoot, string settingsPath, string petId, double scale, int alphaThreshold, int regionAlphaThreshold, int edgePadding, int durationSeconds, bool showAllPets)
    {
        bool createdNew;
        appMutex = new System.Threading.Mutex(true, AppMutexName, out createdNew);
        if (!createdNew)
        {
            appMutex.Dispose();
            appMutex = null;
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        try
        {
            using (var manager = new PetManager(repoRoot, settingsPath, petId, scale, alphaThreshold, regionAlphaThreshold, edgePadding, durationSeconds, showAllPets))
            {
                manager.Start();
                Application.Run();
            }
        }
        finally
        {
            appMutex.ReleaseMutex();
            appMutex.Dispose();
            appMutex = null;
        }
    }

    private sealed class PetDefinition
    {
        public string Id;
        public string Name;
        public string SpritePath;
        public string SpriteEntry;
        public string[] BubbleLines;
        public Color Primary;
        public Color Accent;
    }

    private sealed class PetSettings
    {
        public string DisplayName;
        public List<string> BubbleLines = new List<string>();
        public double Scale = 0.6;
        public int X = int.MinValue;
        public int Y = int.MinValue;
    }

    private sealed class AppSettings
    {
        public bool AlwaysOnTop = true;
        public bool BubblesEnabled = true;
        public bool PatrolMode = false;
        public List<string> ActivePetIds = new List<string>();
        public Dictionary<string, PetSettings> Pets = new Dictionary<string, PetSettings>();
    }

    private sealed class ActionSpec
    {
        public readonly string Name;
        public readonly string Label;
        public readonly int Row;
        public readonly int Frames;
        public readonly int Fps;

        public ActionSpec(string name, string label, int row, int frames, int fps)
        {
            Name = name;
            Label = label;
            Row = row;
            Frames = frames;
            Fps = fps;
        }
    }

    private sealed class FrameData
    {
        public Rectangle SourceBounds;
        public Bitmap Bitmap;
        public Size Size;
    }

    private sealed class PetManager : IDisposable
    {
        private readonly string repoRoot;
        private readonly string settingsPath;
        private readonly string requestedPetId;
        private readonly double requestedScale;
        private readonly int alphaThreshold;
        private readonly int regionAlphaThreshold;
        private readonly int edgePadding;
        private readonly int durationSeconds;
        private readonly bool showAllPets;
        private readonly Dictionary<string, PetDefinition> petMap;
        private readonly Dictionary<string, PetRegionForm> windows = new Dictionary<string, PetRegionForm>();
        private readonly JavaScriptSerializer serializer = new JavaScriptSerializer();

        private AppSettings settings;
        private NotifyIcon notifyIcon;
        private Icon trayIcon;
        private ControlPanel controlPanel;
        private bool hiddenByUser;

        public PetManager(string repoRoot, string settingsPath, string requestedPetId, double requestedScale, int alphaThreshold, int regionAlphaThreshold, int edgePadding, int durationSeconds, bool showAllPets)
        {
            this.repoRoot = repoRoot;
            this.settingsPath = settingsPath;
            this.requestedPetId = requestedPetId;
            this.requestedScale = requestedScale;
            this.alphaThreshold = Math.Max(1, Math.Min(255, alphaThreshold));
            this.regionAlphaThreshold = Math.Max(1, Math.Min(255, regionAlphaThreshold));
            this.edgePadding = Math.Max(0, Math.Min(32, edgePadding));
            this.durationSeconds = durationSeconds;
            this.showAllPets = showAllPets;
            this.petMap = BuildPetCatalog(repoRoot).ToDictionary(pet => pet.Id, pet => pet);
        }

        public IEnumerable<PetDefinition> Pets
        {
            get { return petMap.Values.OrderBy(pet => pet.Id, StringComparer.OrdinalIgnoreCase); }
        }

        public AppSettings Settings
        {
            get { return settings; }
        }

        public void Start()
        {
            settings = LoadSettings();
            if (showAllPets)
            {
                settings.ActivePetIds = Pets.Select(pet => pet.Id).ToList();
            }
            else if (!settings.ActivePetIds.Any())
            {
                settings.ActivePetIds.Add(petMap.ContainsKey(requestedPetId) ? requestedPetId : "yushi");
            }

            if (petMap.ContainsKey(requestedPetId))
            {
                EnsurePetSettings(requestedPetId).Scale = ClampScale(requestedScale);
            }

            foreach (var petId in settings.ActivePetIds.ToList())
            {
                ShowPet(petId);
            }

            CreateTray();

            if (durationSeconds > 0)
            {
                var closeTimer = new Timer();
                closeTimer.Interval = durationSeconds * 1000;
                closeTimer.Tick += delegate {
                    closeTimer.Stop();
                    closeTimer.Dispose();
                    Application.Exit();
                };
                closeTimer.Start();
            }

            SaveSettings();
        }

        public void Dispose()
        {
            SaveSettings();
            if (controlPanel != null) controlPanel.Dispose();
            foreach (var window in windows.Values.ToList()) window.ForceClose();
            windows.Clear();
            if (notifyIcon != null)
            {
                notifyIcon.Visible = false;
                notifyIcon.Dispose();
            }
            if (trayIcon != null) trayIcon.Dispose();
        }

        public PetSettings EnsurePetSettings(string petId)
        {
            PetSettings petSettings;
            if (!settings.Pets.TryGetValue(petId, out petSettings) || petSettings == null)
            {
                petSettings = new PetSettings();
                settings.Pets[petId] = petSettings;
            }

            petSettings.Scale = ClampScale(petSettings.Scale);
            return petSettings;
        }

        public string GetDisplayName(PetDefinition pet)
        {
            var petSettings = EnsurePetSettings(pet.Id);
            var custom = (petSettings.DisplayName ?? "").Trim();
            return custom.Length > 0 ? custom : pet.Name;
        }

        public List<string> GetBubbleLines(PetDefinition pet)
        {
            var petSettings = EnsurePetSettings(pet.Id);
            return petSettings.BubbleLines != null && petSettings.BubbleLines.Count > 0
                ? petSettings.BubbleLines
                : pet.BubbleLines.ToList();
        }

        public bool IsActive(string petId)
        {
            return settings.ActivePetIds.Contains(petId);
        }

        public void ShowPet(string petId)
        {
            hiddenByUser = false;
            PetDefinition pet;
            if (!petMap.TryGetValue(petId, out pet)) return;

            var petSettings = EnsurePetSettings(petId);
            if (!settings.ActivePetIds.Contains(petId)) settings.ActivePetIds.Add(petId);

            PetRegionForm existing;
            if (windows.TryGetValue(petId, out existing) && !existing.IsDisposed)
            {
                existing.Show();
                existing.Activate();
                return;
            }

            var index = settings.ActivePetIds.IndexOf(petId);
            var window = new PetRegionForm(this, pet, petSettings, alphaThreshold, regionAlphaThreshold, edgePadding, index);
            windows[petId] = window;
            window.FormClosed += delegate {
                windows.Remove(petId);
                RefreshTrayMenu();
            };
            window.Show();
            RefreshTrayMenu();
            SaveSettings();
        }

        public void HidePet(string petId)
        {
            settings.ActivePetIds.Remove(petId);
            PetRegionForm window;
            if (windows.TryGetValue(petId, out window))
            {
                window.ForceClose();
                windows.Remove(petId);
            }
            RefreshTrayMenu();
            SaveSettings();
        }

        public void ShowAllPets()
        {
            hiddenByUser = false;
            foreach (var pet in Pets) ShowPet(pet.Id);
        }

        public void HideAllPets()
        {
            hiddenByUser = true;
            settings.ActivePetIds.Clear();
            foreach (var window in windows.Values.ToList()) window.ForceClose();
            windows.Clear();
            RefreshTrayMenu();
            SaveSettings();
        }

        public void RestoreDefaultPetIfHidden()
        {
            if (!hiddenByUser || settings.ActivePetIds.Any()) return;
            ShowPet(petMap.ContainsKey("yushi") ? "yushi" : Pets.First().Id);
        }

        public void ResetPositions()
        {
            int index = 0;
            foreach (var pet in Pets)
            {
                var petSettings = EnsurePetSettings(pet.Id);
                var point = DefaultBottomCenter(index);
                petSettings.X = point.X;
                petSettings.Y = point.Y;
                PetRegionForm window;
                if (windows.TryGetValue(pet.Id, out window)) window.MoveToBottomCenter(point);
                index++;
            }
            SaveSettings();
        }

        public void SetAlwaysOnTop(bool enabled)
        {
            settings.AlwaysOnTop = enabled;
            foreach (var window in windows.Values) window.TopMost = enabled;
            RefreshTrayMenu();
            SaveSettings();
        }

        public void SetBubblesEnabled(bool enabled)
        {
            settings.BubblesEnabled = enabled;
            foreach (var window in windows.Values) window.RefreshCurrentScene();
            RefreshTrayMenu();
            SaveSettings();
        }

        public void SetPatrolMode(bool enabled)
        {
            settings.PatrolMode = enabled;
            foreach (var window in windows.Values) window.ApplyPatrolMode();
            RefreshTrayMenu();
            SaveSettings();
        }

        public void OpenControlPanel(PetRegionForm selectedWindow)
        {
            if (controlPanel == null || controlPanel.IsDisposed)
            {
                controlPanel = new ControlPanel(this);
            }

            controlPanel.SetSelectedPet(selectedWindow == null ? null : selectedWindow.PetId);
            controlPanel.Show();
            controlPanel.Activate();
        }

        public void SavePet(PetDefinition pet, string displayName, List<string> bubbleLines)
        {
            var petSettings = EnsurePetSettings(pet.Id);
            petSettings.DisplayName = (displayName ?? "").Trim();
            petSettings.BubbleLines = bubbleLines
                .Select(line => (line ?? "").Trim())
                .Where(line => line.Length > 0)
                .ToList();

            PetRegionForm window;
            if (windows.TryGetValue(pet.Id, out window))
            {
                window.ResetBubbleRotation();
                window.RefreshCurrentScene();
            }
            SaveSettings();
        }

        public void SetPetAction(string petId, string actionName)
        {
            PetRegionForm window;
            if (windows.TryGetValue(petId, out window))
            {
                window.ActivateAction(actionName);
            }
        }

        public void SaveSettings()
        {
            if (settings == null) return;
            try
            {
                var json = serializer.Serialize(settings);
                File.WriteAllText(settingsPath, PrettyJson(json));
            }
            catch
            {
                // The pet should keep running even if settings cannot be written.
            }
        }

        public Bitmap LoadSpriteBitmap(PetDefinition pet)
        {
            string pakPath = Path.Combine(repoRoot, "wish-pets-assets.pak");
            if (File.Exists(pakPath))
            {
                using (var archive = ZipFile.OpenRead(pakPath))
                {
                    var entry = archive.GetEntry(pet.SpriteEntry.Replace("\\", "/"));
                    if (entry == null) entry = archive.GetEntry(pet.SpriteEntry.Replace("/", "\\"));
                    if (entry == null) throw new FileNotFoundException("Sprite entry not found in asset pack: " + pet.SpriteEntry);

                    using (var stream = entry.Open())
                    using (var bitmap = new Bitmap(stream))
                    {
                        return new Bitmap(bitmap);
                    }
                }
            }

            if (!File.Exists(pet.SpritePath))
            {
                throw new FileNotFoundException("Sprite sheet not found: " + pet.SpritePath);
            }
            return new Bitmap(pet.SpritePath);
        }

        public Point DefaultBottomCenter(int index)
        {
            var work = Screen.PrimaryScreen.WorkingArea;
            int column = Math.Max(0, index) % 4;
            int row = Math.Max(0, index) / 4;
            return new Point(work.Right - 80 - column * 96, work.Bottom - 52 - row * 84);
        }

        private AppSettings LoadSettings()
        {
            try
            {
                if (File.Exists(settingsPath))
                {
                    var loaded = serializer.Deserialize<AppSettings>(File.ReadAllText(settingsPath));
                    if (loaded != null)
                    {
                        if (loaded.ActivePetIds == null) loaded.ActivePetIds = new List<string>();
                        if (loaded.Pets == null) loaded.Pets = new Dictionary<string, PetSettings>();
                        loaded.ActivePetIds = loaded.ActivePetIds.Where(id => petMap.ContainsKey(id)).Distinct().ToList();
                        return loaded;
                    }
                }
            }
            catch
            {
            }

            var fallback = new AppSettings();
            fallback.ActivePetIds.Add(petMap.ContainsKey("yushi") ? "yushi" : petMap.Keys.OrderBy(id => id).First());
            return fallback;
        }

        private void CreateTray()
        {
            notifyIcon = new NotifyIcon();
            notifyIcon.Text = "wish pets";
            trayIcon = LoadTrayIcon();
            notifyIcon.Icon = trayIcon ?? SystemIcons.Application;
            notifyIcon.Visible = true;
            notifyIcon.DoubleClick += delegate {
                RestoreDefaultPetIfHidden();
                OpenControlPanel(windows.Values.FirstOrDefault());
            };
            RefreshTrayMenu();
        }

        private Icon LoadTrayIcon()
        {
            string iconPath = Path.Combine(repoRoot, "build", "icon.ico");
            if (!File.Exists(iconPath)) return null;
            try
            {
                using (var icon = new Icon(iconPath))
                {
                    return (Icon)icon.Clone();
                }
            }
            catch
            {
                return null;
            }
        }

        private void RefreshTrayMenu()
        {
            if (notifyIcon == null) return;

            var menu = new ContextMenuStrip();
            menu.Items.Add("Control Panel", null, delegate { OpenControlPanel(windows.Values.FirstOrDefault()); });
            menu.Items.Add("Show Yushi", null, delegate { ShowPet(petMap.ContainsKey("yushi") ? "yushi" : Pets.First().Id); });
            menu.Items.Add("Show All Pets", null, delegate { ShowAllPets(); });
            menu.Items.Add("Hide All Pets", null, delegate { HideAllPets(); });
            menu.Items.Add(new ToolStripSeparator());

            var choose = new ToolStripMenuItem("Choose Pet");
            foreach (var pet in Pets)
            {
                var item = new ToolStripMenuItem(GetDisplayName(pet));
                item.Checked = IsActive(pet.Id);
                item.CheckOnClick = true;
                item.Tag = pet.Id;
                item.Click += delegate(object sender, EventArgs e) {
                    var clicked = (ToolStripMenuItem)sender;
                    var id = (string)clicked.Tag;
                    if (clicked.Checked) ShowPet(id);
                    else HidePet(id);
                };
                choose.DropDownItems.Add(item);
            }
            menu.Items.Add(choose);

            var bubbles = new ToolStripMenuItem("Show Bubbles");
            bubbles.Checked = settings.BubblesEnabled;
            bubbles.CheckOnClick = true;
            bubbles.Click += delegate { SetBubblesEnabled(bubbles.Checked); };
            menu.Items.Add(bubbles);

            var topMost = new ToolStripMenuItem("Always On Top");
            topMost.Checked = settings.AlwaysOnTop;
            topMost.CheckOnClick = true;
            topMost.Click += delegate { SetAlwaysOnTop(topMost.Checked); };
            menu.Items.Add(topMost);

            var patrol = new ToolStripMenuItem("Patrol Mode");
            patrol.Checked = settings.PatrolMode;
            patrol.CheckOnClick = true;
            patrol.Click += delegate { SetPatrolMode(patrol.Checked); };
            menu.Items.Add(patrol);

            menu.Items.Add("Reset Positions", null, delegate { ResetPositions(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit", null, delegate { Application.Exit(); });
            notifyIcon.ContextMenuStrip = menu;
        }

        private double ClampScale(double value)
        {
            if (Double.IsNaN(value) || Double.IsInfinity(value)) return 0.6;
            return Math.Min(0.6, Math.Max(0.25, value));
        }

        private string PrettyJson(string compact)
        {
            return compact;
        }

        private static IEnumerable<PetDefinition> BuildPetCatalog(string repoRoot)
        {
            return new PetDefinition[] {
                Pet(repoRoot, "jaehee", "Jaehee", "jaehee\\spritesheet.png", new string[] { "Jaehee is here.", "Let's keep it light.", "One tiny win at a time." }, "#eef8ff", "#2d5f82"),
                Pet(repoRoot, "kuri", "Kuri", "kuri\\spritesheet.png", new string[] { "Kuri checked in.", "Soft focus mode.", "A small hop helps." }, "#fff5e8", "#7c5421"),
                Pet(repoRoot, "ryo", "Ryo", "ryo\\spritesheet.png", new string[] { "Ryo is ready.", "Keep the rhythm tidy.", "We can do this." }, "#f3fff2", "#326934"),
                Pet(repoRoot, "sakupang", "Sakupang", "sakupang\\spritesheet.png", new string[] { "Sakupang bounced in.", "Bright desk energy.", "Let's make it neat." }, "#fff0f5", "#8e3858"),
                Pet(repoRoot, "sioning", "Sioning", "sioning\\spritesheet.png", new string[] { "Sioning is on duty.", "Slow and steady counts.", "Tiny paws, clear plan." }, "#f7f1ff", "#5a4382"),
                Pet(repoRoot, "yushi", "Yushi", "yushi\\spritesheet.png", new string[] { "Yushi is here.", "Wish mode on.", "Let's finish one clean loop." }, "#f0fbfa", "#2d6f68")
            }.Where(pet => File.Exists(Path.Combine(repoRoot, "wish-pets-assets.pak")) || File.Exists(pet.SpritePath));
        }

        private static PetDefinition Pet(string repoRoot, string id, string name, string relativePath, string[] bubbleLines, string primary, string accent)
        {
            return new PetDefinition {
                Id = id,
                Name = name,
                SpritePath = Path.Combine(repoRoot, relativePath),
                SpriteEntry = relativePath.Replace("\\", "/"),
                BubbleLines = bubbleLines,
                Primary = ColorTranslator.FromHtml(primary),
                Accent = ColorTranslator.FromHtml(accent)
            };
        }
    }

    private sealed class ControlPanel : Form
    {
        private readonly PetManager manager;
        private readonly ComboBox petCombo = new ComboBox();
        private readonly CheckedListBox activeList = new CheckedListBox();
        private readonly TextBox nameBox = new TextBox();
        private readonly TextBox bubbleBox = new TextBox();
        private readonly CheckBox bubblesCheck = new CheckBox();
        private readonly CheckBox topMostCheck = new CheckBox();
        private readonly CheckBox patrolCheck = new CheckBox();
        private readonly FlowLayoutPanel actionPanel = new FlowLayoutPanel();
        private bool rendering;

        public ControlPanel(PetManager manager)
        {
            this.manager = manager;
            Text = "wish pets Region Controls";
            StartPosition = FormStartPosition.CenterScreen;
            Size = new Size(520, 600);
            MinimumSize = new Size(460, 520);
            Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Regular, GraphicsUnit.Point);

            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.ColumnCount = 1;
            root.RowCount = 8;
            root.Padding = new Padding(12);
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 126));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(root);

            root.Controls.Add(new Label { Text = "Active Pets", AutoSize = true, Font = new Font(Font, FontStyle.Bold) }, 0, 0);
            activeList.Dock = DockStyle.Fill;
            activeList.CheckOnClick = true;
            activeList.ItemCheck += OnActiveItemCheck;
            root.Controls.Add(activeList, 0, 1);

            root.Controls.Add(new Label { Text = "Edit Pet", AutoSize = true, Margin = new Padding(0, 10, 0, 4), Font = new Font(Font, FontStyle.Bold) }, 0, 2);
            petCombo.DropDownStyle = ComboBoxStyle.DropDownList;
            petCombo.SelectedIndexChanged += delegate { RenderPetEditor(); };
            root.Controls.Add(petCombo, 0, 3);

            var editor = new TableLayoutPanel();
            editor.Dock = DockStyle.Fill;
            editor.ColumnCount = 1;
            editor.RowCount = 4;
            editor.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            editor.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            editor.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            editor.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.Controls.Add(editor, 0, 4);

            editor.Controls.Add(new Label { Text = "Name", AutoSize = true, Margin = new Padding(0, 8, 0, 2) }, 0, 0);
            nameBox.Dock = DockStyle.Top;
            editor.Controls.Add(nameBox, 0, 1);
            editor.Controls.Add(new Label { Text = "Bubble Lines (one per line)", AutoSize = true, Margin = new Padding(0, 8, 0, 2) }, 0, 2);
            bubbleBox.Multiline = true;
            bubbleBox.ScrollBars = ScrollBars.Vertical;
            bubbleBox.Dock = DockStyle.Fill;
            editor.Controls.Add(bubbleBox, 0, 3);

            actionPanel.Dock = DockStyle.Top;
            actionPanel.AutoSize = true;
            actionPanel.WrapContents = true;
            root.Controls.Add(actionPanel, 0, 5);

            var globalPanel = new FlowLayoutPanel();
            globalPanel.Dock = DockStyle.Top;
            globalPanel.AutoSize = true;
            bubblesCheck.Text = "Show Bubbles";
            bubblesCheck.AutoSize = true;
            bubblesCheck.CheckedChanged += delegate {
                if (!rendering) manager.SetBubblesEnabled(bubblesCheck.Checked);
            };
            topMostCheck.Text = "Always On Top";
            topMostCheck.AutoSize = true;
            topMostCheck.CheckedChanged += delegate {
                if (!rendering) manager.SetAlwaysOnTop(topMostCheck.Checked);
            };
            patrolCheck.Text = "Patrol Mode";
            patrolCheck.AutoSize = true;
            patrolCheck.CheckedChanged += delegate {
                if (!rendering) manager.SetPatrolMode(patrolCheck.Checked);
            };
            globalPanel.Controls.Add(bubblesCheck);
            globalPanel.Controls.Add(topMostCheck);
            globalPanel.Controls.Add(patrolCheck);
            root.Controls.Add(globalPanel, 0, 6);

            var bottom = new FlowLayoutPanel();
            bottom.Dock = DockStyle.Top;
            bottom.AutoSize = true;
            bottom.FlowDirection = FlowDirection.RightToLeft;
            var close = new Button { Text = "Close Panel", AutoSize = true };
            close.Click += delegate { Hide(); };
            var quit = new Button { Text = "Quit", AutoSize = true };
            quit.Click += delegate { Application.Exit(); };
            var reset = new Button { Text = "Reset Positions", AutoSize = true };
            reset.Click += delegate { manager.ResetPositions(); };
            var save = new Button { Text = "Save Pet Text", AutoSize = true };
            save.Click += delegate { SavePetText(); };
            bottom.Controls.Add(close);
            bottom.Controls.Add(quit);
            bottom.Controls.Add(reset);
            bottom.Controls.Add(save);
            root.Controls.Add(bottom, 0, 7);

            Render();
        }

        public void SetSelectedPet(string petId)
        {
            Render();
            if (petId == null) return;
            for (int i = 0; i < petCombo.Items.Count; i++)
            {
                var item = (PetComboItem)petCombo.Items[i];
                if (item.Pet.Id == petId)
                {
                    petCombo.SelectedIndex = i;
                    return;
                }
            }
        }

        private void Render()
        {
            rendering = true;
            activeList.Items.Clear();
            petCombo.Items.Clear();
            foreach (var pet in manager.Pets)
            {
                activeList.Items.Add(new PetComboItem(pet, manager.GetDisplayName(pet)), manager.IsActive(pet.Id));
                petCombo.Items.Add(new PetComboItem(pet, manager.GetDisplayName(pet)));
            }
            if (petCombo.Items.Count > 0 && petCombo.SelectedIndex < 0) petCombo.SelectedIndex = 0;
            bubblesCheck.Checked = manager.Settings.BubblesEnabled;
            topMostCheck.Checked = manager.Settings.AlwaysOnTop;
            patrolCheck.Checked = manager.Settings.PatrolMode;
            rendering = false;
            RenderPetEditor();
        }

        private void RenderPetEditor()
        {
            var pet = SelectedPet();
            if (pet == null) return;
            rendering = true;
            nameBox.Text = manager.GetDisplayName(pet);
            bubbleBox.Lines = manager.GetBubbleLines(pet).ToArray();
            actionPanel.Controls.Clear();
            foreach (var action in PetRegionForm.Actions)
            {
                var button = new Button { Text = action.Label, Tag = action.Name, AutoSize = true };
                button.Click += delegate(object sender, EventArgs e) {
                    manager.SetPetAction(pet.Id, (string)((Button)sender).Tag);
                };
                actionPanel.Controls.Add(button);
            }
            rendering = false;
        }

        private PetDefinition SelectedPet()
        {
            var item = petCombo.SelectedItem as PetComboItem;
            return item == null ? null : item.Pet;
        }

        private void SavePetText()
        {
            var pet = SelectedPet();
            if (pet == null) return;
            manager.SavePet(pet, nameBox.Text, bubbleBox.Lines.ToList());
            Render();
        }

        private void OnActiveItemCheck(object sender, ItemCheckEventArgs e)
        {
            if (rendering) return;
            BeginInvoke((Action)delegate {
                var item = activeList.Items[e.Index] as PetComboItem;
                if (item == null) return;
                if (activeList.GetItemChecked(e.Index)) manager.ShowPet(item.Pet.Id);
                else manager.HidePet(item.Pet.Id);
                Render();
            });
        }

        private sealed class PetComboItem
        {
            public readonly PetDefinition Pet;
            private readonly string label;

            public PetComboItem(PetDefinition pet, string label)
            {
                Pet = pet;
                this.label = label;
            }

            public override string ToString()
            {
                return label;
            }
        }
    }

    private sealed class PetRegionForm : Form
    {
        public static readonly ActionSpec[] Actions = new ActionSpec[] {
            new ActionSpec("idle", "Idle", 0, 6, 4),
            new ActionSpec("running-right", "Right", 1, 8, 10),
            new ActionSpec("running-left", "Left", 2, 8, 10),
            new ActionSpec("waving", "Wave", 3, 4, 6),
            new ActionSpec("jumping", "Jump", 4, 5, 7),
            new ActionSpec("failed", "Fail", 5, 8, 8),
            new ActionSpec("waiting", "Wait", 6, 6, 4),
            new ActionSpec("running", "Busy", 7, 6, 8),
            new ActionSpec("review", "Review", 8, 6, 5)
        };

        private const int CellWidth = 192;
        private const int CellHeight = 208;

        private readonly PetManager manager;
        private readonly PetDefinition pet;
        private readonly PetSettings petSettings;
        private readonly Bitmap sheet;
        private readonly int alphaThreshold;
        private readonly int regionAlphaThreshold;
        private readonly int edgePadding;
        private readonly Dictionary<string, FrameData[]> cache = new Dictionary<string, FrameData[]>();
        private readonly Timer timer = new Timer();
        private readonly Timer bubbleTimer = new Timer();
        private readonly Timer actionResetTimer = new Timer();
        private readonly Timer patrolTimer = new Timer();
        private readonly Timer patrolMoveTimer = new Timer();
        private readonly Random random = new Random();

        private int actionIndex = 0;
        private int frameIndex = 0;
        private int bubbleIndex = 0;
        private int patrolStepsRemaining = 0;
        private int patrolStepX = 0;
        private Point bottomCenter;
        private Point dragStartCursor;
        private Point dragStartBottomCenter;
        private bool dragging;
        private bool dragMoved;
        private bool forceClosing;
        private FrameData currentFrame;
        private Bitmap currentSceneBitmap;

        public PetRegionForm(PetManager manager, PetDefinition pet, PetSettings petSettings, int alphaThreshold, int regionAlphaThreshold, int edgePadding, int defaultIndex)
        {
            this.manager = manager;
            this.pet = pet;
            this.petSettings = petSettings;
            this.sheet = manager.LoadSpriteBitmap(pet);
            this.alphaThreshold = alphaThreshold;
            this.regionAlphaThreshold = regionAlphaThreshold;
            this.edgePadding = edgePadding;

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            TopMost = manager.Settings.AlwaysOnTop;
            KeyPreview = true;
            Text = "wish pets - " + pet.Name;

            bottomCenter = petSettings.X == int.MinValue || petSettings.Y == int.MinValue
                ? manager.DefaultBottomCenter(defaultIndex)
                : new Point(petSettings.X, petSettings.Y);

            timer.Tick += delegate { AdvanceFrame(); };
            bubbleTimer.Interval = 7000;
            bubbleTimer.Tick += delegate { CycleBubble(1); };
            actionResetTimer.Tick += delegate {
                actionResetTimer.Stop();
                if (!dragging && patrolStepsRemaining <= 0) SetActionByName("idle");
            };
            patrolTimer.Tick += delegate { BeginPatrolStep(); };
            patrolMoveTimer.Interval = 33;
            patrolMoveTimer.Tick += delegate { ContinuePatrolStep(); };
            MouseDown += OnMouseDown;
            MouseMove += OnMouseMove;
            MouseUp += OnMouseUp;
            MouseWheel += OnMouseWheel;
            DoubleClick += delegate { manager.OpenControlPanel(this); };
            KeyDown += OnKeyDown;
        }

        public string PetId
        {
            get { return pet.Id; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ExStyle |= WS_EX_LAYERED;
                return cp;
            }
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            ApplyCurrentFrame();
            StartTimerForAction();
            ResetBubbleRotation();
            ApplyPatrolMode();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            petSettings.X = bottomCenter.X;
            petSettings.Y = bottomCenter.Y;
            manager.SaveSettings();
            if (!forceClosing && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                manager.HidePet(pet.Id);
            }
            base.OnFormClosing(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                timer.Dispose();
                bubbleTimer.Dispose();
                actionResetTimer.Dispose();
                patrolTimer.Dispose();
                patrolMoveTimer.Dispose();
                foreach (var frames in cache.Values)
                {
                    foreach (var frame in frames)
                    {
                        if (frame.Bitmap != null) frame.Bitmap.Dispose();
                    }
                }
                if (currentSceneBitmap != null) currentSceneBitmap.Dispose();
                sheet.Dispose();
            }
            base.Dispose(disposing);
        }

        public void ForceClose()
        {
            forceClosing = true;
            Close();
        }

        public void MoveToBottomCenter(Point point)
        {
            bottomCenter = point;
            RefreshCurrentScene();
        }

        public void ActivateAction(string actionName)
        {
            SetActionByName(actionName);
            CycleBubble(1);
            if (actionName == "jumping") ScheduleIdleReset(950);
        }

        public void ResetBubbleRotation()
        {
            bubbleIndex = 0;
            bubbleTimer.Stop();
            if (manager.Settings.BubblesEnabled) bubbleTimer.Start();
        }

        public void RefreshCurrentScene()
        {
            if (currentFrame == null) return;
            if (currentSceneBitmap != null)
            {
                currentSceneBitmap.Dispose();
                currentSceneBitmap = null;
            }

            currentSceneBitmap = ComposeSceneFrame(currentFrame.Bitmap, Actions[actionIndex].Name);
            Size = currentSceneBitmap.Size;
            PlaceWindowForCurrentFrame();
            IntPtr region = BuildRegionFromBitmap(currentSceneBitmap);
            SetWindowRgn(Handle, region, true);
            UpdateLayeredBitmap(currentSceneBitmap);
        }

        public void ApplyPatrolMode()
        {
            patrolTimer.Stop();
            patrolMoveTimer.Stop();
            patrolStepsRemaining = 0;
            if (manager.Settings.PatrolMode)
            {
                ScheduleNextPatrol();
            }
            else if (!dragging)
            {
                SetActionByName("idle");
            }
        }

        private void OnMouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                manager.OpenControlPanel(this);
                return;
            }
            if (e.Button != MouseButtons.Left) return;
            dragging = true;
            dragMoved = false;
            actionResetTimer.Stop();
            patrolMoveTimer.Stop();
            dragStartCursor = Cursor.Position;
            dragStartBottomCenter = bottomCenter;
        }

        private void OnMouseMove(object sender, MouseEventArgs e)
        {
            if (!dragging) return;
            var cursor = Cursor.Position;
            bottomCenter = new Point(
                dragStartBottomCenter.X + cursor.X - dragStartCursor.X,
                dragStartBottomCenter.Y + cursor.Y - dragStartCursor.Y
            );
            dragMoved = Math.Abs(cursor.X - dragStartCursor.X) > 3 || Math.Abs(cursor.Y - dragStartCursor.Y) > 3;
            petSettings.X = bottomCenter.X;
            petSettings.Y = bottomCenter.Y;

            int dx = cursor.X - dragStartCursor.X;
            if (dx > 3) SetActionByName("running-right");
            else if (dx < -3) SetActionByName("running-left");
            else RefreshCurrentScene();
        }

        private void OnMouseUp(object sender, MouseEventArgs e)
        {
            if (!dragging) return;
            dragging = false;
            manager.SaveSettings();
            if (dragMoved)
            {
                SetActionByName("idle");
                if (manager.Settings.PatrolMode) ScheduleNextPatrol();
                return;
            }

            SetActionByName("jumping");
            CycleBubble(1);
            ScheduleIdleReset(950);
        }

        private void OnMouseWheel(object sender, MouseEventArgs e)
        {
            double step = e.Delta > 0 ? 0.05 : -0.05;
            petSettings.Scale = Math.Min(0.6, Math.Max(0.25, petSettings.Scale + step));
            ClearFrameCache();
            ApplyCurrentFrame();
            manager.SaveSettings();
        }

        private void OnKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                Application.Exit();
                return;
            }
            if (e.KeyCode == Keys.Space)
            {
                SetAction((actionIndex + 1) % Actions.Length);
                return;
            }
            if (e.KeyCode >= Keys.D1 && e.KeyCode <= Keys.D9)
            {
                SetAction((int)e.KeyCode - (int)Keys.D1);
            }
        }

        private void SetAction(int nextIndex)
        {
            if (nextIndex < 0 || nextIndex >= Actions.Length) return;
            actionResetTimer.Stop();
            if (actionIndex == nextIndex)
            {
                RefreshCurrentScene();
                return;
            }
            actionIndex = nextIndex;
            frameIndex = 0;
            ApplyCurrentFrame();
            StartTimerForAction();
        }

        private void SetActionByName(string actionName)
        {
            for (int i = 0; i < Actions.Length; i++)
            {
                if (Actions[i].Name == actionName)
                {
                    SetAction(i);
                    return;
                }
            }
        }

        private void StartTimerForAction()
        {
            timer.Stop();
            timer.Interval = Math.Max(16, 1000 / Actions[actionIndex].Fps);
            timer.Start();
        }

        private void AdvanceFrame()
        {
            frameIndex = (frameIndex + 1) % Actions[actionIndex].Frames;
            ApplyCurrentFrame();
        }

        private void ApplyCurrentFrame()
        {
            var frames = GetFrames(Actions[actionIndex]);
            currentFrame = frames[frameIndex % frames.Length];
            RefreshCurrentScene();
        }

        private void PlaceWindowForCurrentFrame()
        {
            if (currentSceneBitmap == null) return;
            Location = new Point(
                bottomCenter.X - currentSceneBitmap.Width / 2,
                bottomCenter.Y - currentSceneBitmap.Height - JumpLift()
            );
        }

        private FrameData[] GetFrames(ActionSpec action)
        {
            if (cache.ContainsKey(action.Name)) return cache[action.Name];

            var frames = new FrameData[action.Frames];
            for (int i = 0; i < action.Frames; i++)
            {
                frames[i] = BuildFrame(action.Row, i);
            }
            cache[action.Name] = frames;
            return frames;
        }

        private FrameData BuildFrame(int row, int column)
        {
            var cell = new Rectangle(column * CellWidth, row * CellHeight, CellWidth, CellHeight);
            var bounds = FindOpaqueBounds(cell);
            if (bounds.Width <= 0 || bounds.Height <= 0) bounds = cell;

            double scale = petSettings.Scale;
            if (Actions[actionIndex].Name == "jumping") scale = Math.Min(scale, petSettings.Scale * 0.9);
            int outWidth = Math.Max(1, (int)Math.Ceiling(bounds.Width * scale));
            int outHeight = Math.Max(1, (int)Math.Ceiling(bounds.Height * scale));

            var bitmap = new Bitmap(outWidth, outHeight, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bitmap))
            {
                g.Clear(Color.Transparent);
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
                g.DrawImage(sheet, new Rectangle(0, 0, outWidth, outHeight), bounds, GraphicsUnit.Pixel);
            }

            return new FrameData {
                SourceBounds = bounds,
                Bitmap = bitmap,
                Size = new Size(outWidth, outHeight)
            };
        }

        private Rectangle FindOpaqueBounds(Rectangle cell)
        {
            int minX = cell.Right;
            int minY = cell.Bottom;
            int maxX = cell.Left - 1;
            int maxY = cell.Top - 1;

            for (int y = cell.Top; y < cell.Bottom; y++)
            {
                for (int x = cell.Left; x < cell.Right; x++)
                {
                    if (sheet.GetPixel(x, y).A < alphaThreshold) continue;
                    if (x < minX) minX = x;
                    if (y < minY) minY = y;
                    if (x > maxX) maxX = x;
                    if (y > maxY) maxY = y;
                }
            }

            if (maxX < minX || maxY < minY) return Rectangle.Empty;
            return Rectangle.FromLTRB(
                Math.Max(cell.Left, minX - edgePadding),
                Math.Max(cell.Top, minY - edgePadding),
                Math.Min(cell.Right, maxX + 1 + edgePadding),
                Math.Min(cell.Bottom, maxY + 1 + edgePadding)
            );
        }

        private Bitmap ComposeSceneFrame(Bitmap petBitmap, string actionName)
        {
            int gap = ScaleInt(10);
            int padX = ScaleInt(14);
            int padY = ScaleInt(9);
            int bubbleWidth = manager.Settings.BubblesEnabled ? Math.Max(ScaleInt(72), MeasureBubbleWidth(padX)) : 0;
            int bubbleHeight = manager.Settings.BubblesEnabled ? Math.Max(ScaleInt(36), ScaleInt(26) + padY * 2) : 0;
            int tailHeight = manager.Settings.BubblesEnabled ? ScaleInt(9) : 0;
            int sceneWidth = Math.Max(petBitmap.Width, bubbleWidth + ScaleInt(18));
            int sceneHeight = bubbleHeight + tailHeight + (manager.Settings.BubblesEnabled ? gap : 0) + petBitmap.Height;

            var scene = new Bitmap(sceneWidth, sceneHeight, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(scene))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
                g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

                int petX = (sceneWidth - petBitmap.Width) / 2;
                int petY = manager.Settings.BubblesEnabled ? bubbleHeight + tailHeight + gap : 0;
                g.DrawImage(petBitmap, petX, petY, petBitmap.Width, petBitmap.Height);
                if (manager.Settings.BubblesEnabled)
                {
                    int bubbleX = Math.Max(0, petX + petBitmap.Width - bubbleWidth);
                    DrawBubble(g, new Rectangle(bubbleX, 0, bubbleWidth, bubbleHeight), padX, petX + petBitmap.Width / 2, bubbleHeight);
                }
            }

            return CropToAlphaBounds(scene);
        }

        private int MeasureBubbleWidth(int padX)
        {
            using (var bitmap = new Bitmap(1, 1))
            using (var g = Graphics.FromImage(bitmap))
            using (var font = BubbleFont())
            {
                return (int)Math.Ceiling(g.MeasureString(CurrentBubbleText(), font).Width) + padX * 2;
            }
        }

        private void DrawBubble(Graphics g, Rectangle rect, int padX, int tailTargetX, int tailTopY)
        {
            using (var path = RoundedRect(rect, ScaleInt(12)))
            using (var fill = new SolidBrush(Color.FromArgb(240, 255, 255, 255)))
            using (var border = new Pen(Color.FromArgb(215, pet.Accent), Math.Max(1.0f, (float)(1.5 * petSettings.Scale))))
            {
                g.FillPath(fill, path);
                g.DrawPath(border, path);
            }

            int tailX = Math.Max(rect.Left + ScaleInt(16), Math.Min(rect.Right - ScaleInt(16), tailTargetX));
            Point[] tail = new Point[] {
                new Point(tailX - ScaleInt(6), rect.Bottom - 1),
                new Point(tailX + ScaleInt(5), rect.Bottom - 1),
                new Point(tailX - ScaleInt(1), tailTopY + ScaleInt(7))
            };
            using (var fill = new SolidBrush(Color.FromArgb(240, 255, 255, 255)))
            using (var border = new Pen(Color.FromArgb(215, pet.Accent), Math.Max(1.0f, (float)(1.5 * petSettings.Scale))))
            {
                g.FillPolygon(fill, tail);
                g.DrawPolygon(border, tail);
            }

            using (var font = BubbleFont())
            using (var brush = new SolidBrush(Color.FromArgb(245, 31, 35, 42)))
            using (var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                g.DrawString(CurrentBubbleText(), font, brush, rect, format);
            }
        }

        private Font BubbleFont()
        {
            return new Font("Microsoft YaHei UI", Math.Max(8.0f, (float)(11.5 * petSettings.Scale)), FontStyle.Bold, GraphicsUnit.Point);
        }

        private string CurrentBubbleText()
        {
            var lines = manager.GetBubbleLines(pet);
            if (lines.Count == 0) return manager.GetDisplayName(pet);
            bubbleIndex = Math.Max(0, Math.Min(bubbleIndex, lines.Count - 1));
            return lines[bubbleIndex];
        }

        private void CycleBubble(int step)
        {
            var lines = manager.GetBubbleLines(pet);
            if (lines.Count == 0) return;
            bubbleIndex = (bubbleIndex + step + lines.Count) % lines.Count;
            RefreshCurrentScene();
        }

        private void ScheduleIdleReset(int milliseconds)
        {
            actionResetTimer.Stop();
            actionResetTimer.Interval = Math.Max(200, milliseconds);
            actionResetTimer.Start();
        }

        private int JumpLift()
        {
            if (Actions[actionIndex].Name != "jumping") return 0;
            int frames = Math.Max(1, Actions[actionIndex].Frames - 1);
            double progress = Math.Max(0.0, Math.Min(1.0, frameIndex / (double)frames));
            return (int)Math.Round(Math.Sin(progress * Math.PI) * ScaleInt(32));
        }

        private void ScheduleNextPatrol()
        {
            patrolTimer.Stop();
            if (!manager.Settings.PatrolMode) return;
            patrolTimer.Interval = random.Next(2800, 6500);
            patrolTimer.Start();
        }

        private void BeginPatrolStep()
        {
            patrolTimer.Stop();
            if (!manager.Settings.PatrolMode || dragging || actionIndex != 0) {
                ScheduleNextPatrol();
                return;
            }

            var work = Screen.FromPoint(bottomCenter).WorkingArea;
            int direction = random.Next(0, 2) == 0 ? -1 : 1;
            if (bottomCenter.X < work.Left + 120) direction = 1;
            if (bottomCenter.X > work.Right - 120) direction = -1;

            patrolStepX = direction * Math.Max(1, ScaleInt(3));
            patrolStepsRemaining = random.Next(28, 54);
            SetActionByName(direction < 0 ? "running-left" : "running-right");
            patrolMoveTimer.Start();
        }

        private void ContinuePatrolStep()
        {
            if (dragging || patrolStepsRemaining <= 0)
            {
                patrolMoveTimer.Stop();
                patrolStepsRemaining = 0;
                if (!dragging) SetActionByName("idle");
                ScheduleNextPatrol();
                return;
            }

            var work = Screen.FromPoint(bottomCenter).WorkingArea;
            bottomCenter = new Point(
                Math.Max(work.Left + 24, Math.Min(work.Right - 24, bottomCenter.X + patrolStepX)),
                bottomCenter.Y
            );
            petSettings.X = bottomCenter.X;
            petSettings.Y = bottomCenter.Y;
            patrolStepsRemaining--;
            RefreshCurrentScene();
        }

        private System.Drawing.Drawing2D.GraphicsPath RoundedRect(Rectangle rect, int radius)
        {
            int diameter = Math.Max(1, radius * 2);
            var path = new System.Drawing.Drawing2D.GraphicsPath();
            path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private Bitmap CropToAlphaBounds(Bitmap source)
        {
            Rectangle bounds = FindBitmapAlphaBounds(source);
            if (bounds.Width <= 0 || bounds.Height <= 0) return source;

            var cropped = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(cropped))
            {
                g.Clear(Color.Transparent);
                g.DrawImage(source, new Rectangle(0, 0, cropped.Width, cropped.Height), bounds, GraphicsUnit.Pixel);
            }
            source.Dispose();
            return cropped;
        }

        private Rectangle FindBitmapAlphaBounds(Bitmap bitmap)
        {
            int minX = bitmap.Width;
            int minY = bitmap.Height;
            int maxX = -1;
            int maxY = -1;

            for (int y = 0; y < bitmap.Height; y++)
            {
                for (int x = 0; x < bitmap.Width; x++)
                {
                    if (bitmap.GetPixel(x, y).A < alphaThreshold) continue;
                    if (x < minX) minX = x;
                    if (y < minY) minY = y;
                    if (x > maxX) maxX = x;
                    if (y > maxY) maxY = y;
                }
            }

            if (maxX < minX || maxY < minY) return Rectangle.Empty;
            return Rectangle.FromLTRB(minX, minY, maxX + 1, maxY + 1);
        }

        private IntPtr BuildRegionFromBitmap(Bitmap bitmap)
        {
            IntPtr result = CreateRectRgn(0, 0, 0, 0);
            bool hasPixels = false;

            for (int y = 0; y < bitmap.Height; y++)
            {
                int x = 0;
                while (x < bitmap.Width)
                {
                    while (x < bitmap.Width && bitmap.GetPixel(x, y).A < regionAlphaThreshold) x++;
                    if (x >= bitmap.Width) break;
                    int startX = x;
                    while (x < bitmap.Width && bitmap.GetPixel(x, y).A >= regionAlphaThreshold) x++;
                    IntPtr run = CreateRectRgn(startX, y, x, y + 1);
                    CombineRgn(result, result, run, RGN_OR);
                    DeleteObject(run);
                    hasPixels = true;
                }
            }

            if (!hasPixels)
            {
                DeleteObject(result);
                result = CreateRectRgn(0, 0, bitmap.Width, bitmap.Height);
            }

            return result;
        }

        private void UpdateLayeredBitmap(Bitmap bitmap)
        {
            IntPtr screenDc = IntPtr.Zero;
            IntPtr memoryDc = IntPtr.Zero;
            IntPtr hBitmap = IntPtr.Zero;
            IntPtr oldBitmap = IntPtr.Zero;

            try
            {
                screenDc = GetDC(IntPtr.Zero);
                memoryDc = CreateCompatibleDC(screenDc);
                hBitmap = bitmap.GetHbitmap(Color.FromArgb(0));
                oldBitmap = SelectObject(memoryDc, hBitmap);

                var destination = new POINT(Location.X, Location.Y);
                var size = new SIZE(bitmap.Width, bitmap.Height);
                var source = new POINT(0, 0);
                var blend = new BLENDFUNCTION {
                    BlendOp = AC_SRC_OVER,
                    BlendFlags = 0,
                    SourceConstantAlpha = 255,
                    AlphaFormat = AC_SRC_ALPHA
                };

                UpdateLayeredWindow(Handle, screenDc, ref destination, ref size, memoryDc, ref source, 0, ref blend, ULW_ALPHA);
            }
            finally
            {
                if (oldBitmap != IntPtr.Zero) SelectObject(memoryDc, oldBitmap);
                if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
                if (memoryDc != IntPtr.Zero) DeleteDC(memoryDc);
                if (screenDc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, screenDc);
            }
        }

        private void ClearFrameCache()
        {
            foreach (var frames in cache.Values)
            {
                foreach (var frame in frames)
                {
                    if (frame.Bitmap != null) frame.Bitmap.Dispose();
                }
            }
            cache.Clear();
        }

        private int ScaleInt(int value)
        {
            return Math.Max(1, (int)Math.Round(value * petSettings.Scale));
        }
    }
}
"@

[RegionPetTrial]::Run($repoRoot, $settingsPath, $PetId, $Scale, $AlphaThreshold, $RegionAlphaThreshold, $EdgePadding, $DurationSeconds, [bool]$ShowAllPets)
