# wish pets Windows Region Trial

This is a standalone Windows-native experiment for per-frame pet-shaped windows.
It does not change the Electron app.

Run from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\region-trial\Run-RegionPetTrial.ps1
```

Show every available pet:

```powershell
powershell -ExecutionPolicy Bypass -File .\region-trial\Run-RegionPetTrial.ps1 -ShowAllPets
```

Build the Windows setup package:

```powershell
powershell -ExecutionPolicy Bypass -File .\region-trial\package\Build-NativeWinSetup.ps1
```

The generated installer is written to `dist/WishPets-Setup-1.0.1.exe`.
Packaged pet sprites are stored in a single `wish-pets-assets.pak` file in the
installed app directory instead of exposed as individual PNG folders.

The script defaults to `yushi/spritesheet.png`, scans each animation
frame's alpha channel, crops to the visible pixels, converts the visible pixels
into a Win32 region, and applies that region with `SetWindowRgn`. The window is
resized and re-shaped every frame.

Rendering uses a true layered window via `UpdateLayeredWindow`, not a magenta
`TransparencyKey`. This matters for antialiased pet edges: semi-transparent
pixels keep their real alpha instead of blending against a fake transparent
background color.

The trial also composites the speech bubble into the same alpha bitmap as the
pet. After compositing, the whole scene is cropped back to visible pixels before
the window region is applied. There is intentionally no shadow tray under the
pet.

Controls:

- Drag the pet body to move it. Dragging right switches to `running-right`;
  dragging left switches to `running-left`; releasing returns to `idle`.
- Click a pet to play one `jumping` action. During `jumping`, the whole shaped
  window moves upward and falls back down to mimic a hop.
- Scroll the mouse wheel over a pet to scale it between 25% and 60%.
- Right-click or double-click a pet to open the native control panel.
- Press `1` through `9` to switch actions.
- Press `Space` to cycle actions.
- Press `Esc` to quit.

Native control panel and tray coverage:

- Show or hide individual pets, or show/hide all pets.
- Edit each pet's display name.
- Edit each pet's bubble lines, one line per row.
- Trigger pet actions with buttons.
- Toggle all bubbles.
- Toggle always-on-top.
- Toggle patrol mode. While enabled, each idle pet periodically walks left or
  right across the desktop and then returns to idle.
- Reset pet positions.

Settings are saved to `region-trial/settings.json`.

Notes:

- The trial uses PNG because `System.Drawing` on Windows can load it reliably.
- The main mac packaging keeps only `spritesheet.webp`; the local PNGs are
  intentionally ignored by git.
- Every frame builds a fresh Win32 region. `SetWindowRgn` transfers ownership of
  the region to Windows, so cached region handles should not be reused.
- `-AlphaThreshold` controls frame bounds detection. It defaults low so faint
  antialias pixels do not get clipped.
- `-RegionAlphaThreshold` controls the clickable/visible window shape. Lower it
  if the outline is clipped; raise it if faint alpha noise creates stray pixels.
- `-EdgePadding` adds a tiny transparent crop margin around each frame to avoid
  shaving off soft antialias edges.
- `-Scale` defaults to `1.0` and is clamped at `1.0`, so the pet is rendered at
  the source atlas size for sharper edges and details.
