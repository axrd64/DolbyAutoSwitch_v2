# DolbyAutoSwitch

Automatically enables and disables Dolby Atmos effects on your Lenovo ThinkPad
based on active audio output. No configuration needed — fully automatic.

You can either build it yourself on your own computer or download the release installer.

**Logic:** Internal speakers → Dolby ON. Any external device (Bluetooth, USB, 3.5mm) → Dolby OFF.

---

## Files

```
DolbyAutoSwitch/
├── Install-DolbyAutoSwitch.exe      ← double-click to install (built from src/)
├── Uninstall-DolbyAutoSwitch.exe    ← standalone uninstaller (built from src/)
├── DolbyAutoSwitch.ps1              ← background watcher (do not move after install)
├── Uninstall-DolbyAutoSwitch.ps1    ← PS1 fallback uninstaller
├── dolby_auto_switch.ico            ← icon — replace this to customize
└── src/
    ├── Installer.cs                 ← C# source for installer EXE
    ├── Uninstaller.cs               ← C# source for uninstaller EXE
    ├── app.manifest                 ← UAC elevation manifest
    └── build.bat                    ← compiles both EXEs (run on Windows)
```

---

## Step 1 — Build the EXEs (one time)

The EXEs are compiled on your own machine using the C# compiler built into
Windows. No Visual Studio, no downloads needed.

1. Open the `src\` folder
2. Double-click `build.bat`
3. Two EXEs appear in the parent folder: `Install-DolbyAutoSwitch.exe` and
   `Uninstall-DolbyAutoSwitch.exe`

---

## Step 2 — Install

Double-click `Install-DolbyAutoSwitch.exe`. Windows will ask for admin
permission (UAC prompt) — click Yes. A confirmation dialog appears, click Yes
to install.

What happens:
- Files copied to `C:\ProgramData\DolbyAutoSwitch\`
- Task Scheduler entry created (runs at every login, hidden)
- Entry added to **Settings → Apps** with uninstall support
- Tray icon appears near the clock immediately

---

## Custom Icon

Replace `dolby_auto_switch.ico` with any `.ico` file **before running build.bat**.
The same file is embedded into both EXEs and used for the tray icon and the
Apps list entry.

Recommended `.ico` sizes: 16×16, 32×32, 48×48, 256×256.
Free `.ico` makers: https://icoconvert.com — or use any image editor.

After install, you can also swap the icon at:
`C:\ProgramData\DolbyAutoSwitch\dolby_auto_switch.ico`
then restart the task in Task Scheduler.

---

## Uninstall

Any of these work:
- **Settings → Apps → DolbyAutoSwitch → Uninstall**
- Right-click the tray icon → **Uninstall DolbyAutoSwitch**
- Double-click `Uninstall-DolbyAutoSwitch.exe` directly

The uninstaller restores Dolby effects to ON before removing anything.

---

## Logs

`C:\ProgramData\DolbyAutoSwitch\DolbyAutoSwitch.log` — auto-rotated at 2 MB.
