# Windows Kiosk Mode Setup

Automated PowerShell script to turn any Windows 10/11 PC into a secure single-app kiosk — without requiring Enterprise/Education edition, Intune, or third-party software.

> **Türkçe:** Herhangi bir Windows 10/11 bilgisayarı tek uygulama çalıştıran güvenli bir kiosk'a dönüştüren PowerShell scripti. Enterprise/Education sürümü, Intune veya üçüncü parti yazılım gerektirmez.

## Features

- **Single-app lockdown** — Launches your app at logon with a 30-second watchdog (auto-restart if closed)
- **User isolation** — All restrictions apply only to the kiosk user; admin accounts are never affected
- **Software Restriction Policies (SRP)** — Process-level blocking of cmd, PowerShell, regedit, Task Manager, mmc, wscript, cscript, mshta (admin exempt via `PolicyScope=1`)
- **HKCU-based restrictions** — DisallowRun, disable Task Manager, hide Run dialog, block Control Panel/Settings, disable Notification Center
- **WerFault suppression** — Crash dialogs are silently dismissed so the watchdog can restart the app cleanly
- **Explorer shell removal** — Explorer is killed and not restarted for the kiosk user, blocking Start menu, Win+R, Win+E, and taskbar access
- **Auto-logon** — Optional automatic login at boot
- **Edge swipe disabled** — Prevents swipe gestures from opening system UI
- **Self-healing error system** — Automatically attempts to fix errors; logs manual intervention steps when it can't
- **Full undo script** — One command to completely reverse all changes
- **Idempotent** — Safe to run multiple times

## Security Layers

| Layer | What it does | Scope |
|-------|-------------|-------|
| SRP (Safer\CodeIdentifiers) | Blocks exe execution at OS level | Standard users only (admin exempt) |
| DisallowRun | Blocks exe launch via Explorer shell | Kiosk HKCU only |
| DisableCMD / DisableTaskMgr | Disables cmd.exe and Task Manager | Kiosk HKCU only |
| NoRun / NoControlPanel | Hides Run dialog and Settings | Kiosk HKCU only |
| Explorer killed | No shell = no Start menu, no file browser | Kiosk session only |
| WerFault DontShowUI | Suppresses crash dialogs | Kiosk HKCU only |
| EdgeUI AllowEdgeSwipe=0 | Disables edge swipe gestures | System-wide |

## Requirements

- Windows 10 / 11 (Home, Pro, Enterprise — any edition)
- PowerShell 5.1+ (built-in)
- Administrator privileges

## Quick Start

### Setup

Open PowerShell **as Administrator** and run:

```powershell
& "C:\path\to\Setup-KioskMode.ps1" -AppPath "C:\MyApp\app.exe" -AutoLogon
```

### Examples

```powershell
# Basic kiosk (passwordless, auto-logon)
& ".\Setup-KioskMode.ps1" -AppPath "D:\Kiosk\myapp.exe" -AutoLogon

# With app arguments
& ".\Setup-KioskMode.ps1" -AppPath "C:\Kiosk\browser.exe" -AppArgs "--kiosk --fullscreen" -AutoLogon

# Custom user name and password
& ".\Setup-KioskMode.ps1" -AppPath "E:\App\pos.exe" -KioskUser "POS" -KioskPassword "1234" -AutoLogon

# Skip restrictions (for testing)
& ".\Setup-KioskMode.ps1" -AppPath "C:\Kiosk\app.exe" -SkipRestrictions -AutoLogon
```

### Undo

```powershell
& "C:\Kiosk\Undo-KioskMode.ps1"
```

A copy of the undo script is also saved next to the setup script.

### Emergency Recovery

If the kiosk user is locked and you need to regain control:

1. Press `Ctrl+Alt+Del`
2. Click **Switch User**
3. Log in with your admin account
4. Run the undo script as Administrator

> `Ctrl+Alt+Del` is handled by the Windows kernel (winlogon.exe) and **cannot be disabled** by any script, policy, or registry setting. This is your guaranteed escape route.

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-AppPath` | Yes | — | Full path to the kiosk application exe |
| `-AppArgs` | No | `""` | Arguments to pass to the application |
| `-KioskUser` | No | `Kiosk` | Name of the kiosk user account to create |
| `-KioskPassword` | No | `""` | Password for the kiosk user (empty = passwordless) |
| `-AutoLogon` | No | `$false` | Enable automatic login at boot |
| `-SkipRestrictions` | No | `$false` | Skip HKCU restrictions and SRP setup |

## How It Works

```
Boot → AutoLogon → Kiosk user session
  → Task Scheduler: AtLogOn trigger
    → App launches immediately
    → 30s repetition = watchdog (restarts if closed)
  → FirstLogon task (SYSTEM): applies HKCU restrictions via HKU\<SID>
    → Kills explorer.exe (no shell)
    → Self-deletes after success
```

### Safety Checks

- Prevents running the script from the kiosk user account
- Prevents using an existing admin account name as kiosk user
- Removes kiosk user from Administrators group if found
- Checks Task Scheduler service status and auto-starts if stopped
- Validates AppPath is a full/absolute path

## Files Created

| File | Purpose |
|------|---------|
| `C:\Kiosk\kiosk-setup.log` | Setup log with all operations and errors |
| `C:\Kiosk\Undo-KioskMode.ps1` | Undo script (also copied next to setup script) |
| `C:\Kiosk\FirstLogon.ps1` | One-time restriction script (auto-deletes after first logon) |

## Log System

All operations are logged to `C:\Kiosk\kiosk-setup.log` with these levels:

| Level | Meaning |
|-------|---------|
| `[INFO]` | Step started |
| `[OK]` | Step completed successfully |
| `[WARN]` | Non-critical warning |
| `[FAIL]` | Step failed |
| `[FIX]` | Auto-fix attempted |
| `[MANUAL]` | Manual intervention required — check the log |

If any `[MANUAL]` entries exist, a red warning is displayed at the end of setup with the log file path.

## V1 Compatibility

If you previously used V1 of this script, V2 automatically:
- Removes old `KioskWatchdog` scheduled task
- Removes old `watchdog.bat` file
- Cleans up V1 HKLM policy remnants during undo

## License

MIT License — free to use, modify, and distribute.

## Contributing

Issues and pull requests are welcome. If you found a bug or have a suggestion, please open an issue.

---

*Bu proje, Windows kiosk kurulumunda yaşanan yaygın sorunları çözmek için geliştirilmiştir. Kurumsal yazılım veya özel Windows sürümü gerektirmeden, herhangi bir Windows bilgisayarını güvenli kiosk moduna dönüştürür.*
