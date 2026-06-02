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

### Option A: Interactive Launcher (Recommended)

Right-click `Kiosk-Launcher.bat` → **Run as Administrator**. The launcher guides you through setup with 5 deployment scenarios:

| Scenario | Description |
|----------|-------------|
| **1. Passwordless Auto-Login** | Boots directly into app, no password, full restrictions |
| **2. Password Auto-Login** | Boots directly into app, password-protected account |
| **3. Password Manual Login** | Stops at lock screen, requires password to enter kiosk |
| **4. Passwordless Manual Login** | Stops at lock screen, click kiosk user to enter |
| **5. Developer / Test Mode** | Auto-login with NO restrictions (for testing) |

### Option B: Direct PowerShell

Open PowerShell **as Administrator** and run:

```powershell
& "C:\path\to\Setup-KioskMode-V3.ps1" -AppPath "C:\MyApp\app.exe" -AutoLogon
```

### Examples

```powershell
# Basic kiosk (passwordless, auto-logon)
& ".\Setup-KioskMode-V3.ps1" -AppPath "D:\Kiosk\myapp.exe" -AutoLogon

# With app arguments
& ".\Setup-KioskMode-V3.ps1" -AppPath "C:\Kiosk\browser.exe" -AppArgs "--kiosk --fullscreen" -AutoLogon

# Custom user name and password
& ".\Setup-KioskMode-V3.ps1" -AppPath "E:\App\pos.exe" -KioskUser "POS" -KioskPassword "1234" -AutoLogon

# Multiple kiosks on same machine
& ".\Setup-KioskMode-V3.ps1" -AppPath "C:\Kiosk\app1.exe" -KioskUser "Kiosk1" -AutoLogon
& ".\Setup-KioskMode-V3.ps1" -AppPath "C:\Kiosk\app2.exe" -KioskUser "Kiosk2" -AutoLogon

# Skip restrictions (for testing)
& ".\Setup-KioskMode-V3.ps1" -AppPath "C:\Kiosk\app.exe" -SkipRestrictions -AutoLogon
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

## Repository Files

| File | Description |
|------|-------------|
| `Setup-KioskMode-V3.ps1` | **Current** — LF-safe kiosk setup script (Custom shell + KioskShellKiller task) |
| `Kiosk-Launcher.bat` | Interactive launcher for V1, V2, and V3 with version selection |
| `Setup-KioskMode-V2.ps1` | Previous version (HKCU restrictions + backported KioskShellKiller task) |
| `Setup-KioskMode.ps1` | V1 — Legacy (HKLM-based, affects all users, unsupported) |
| `.gitattributes` | Enforces CRLF line endings for .ps1/.bat files |

## Files Created During Setup

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

## Version History (V1 vs V2 vs V3)

### V3 (Current — `Setup-KioskMode-V3.ps1`)
- **Shell Bypassing & Shell Killer:** Bypasses explorer shell loading completely via HKCU `Winlogon\Shell` registry configurations (`cmd.exe /c exit`). Also registers a secondary `KioskShellKiller` scheduled task watchdog to kill explorer.exe every 1 minute.
- **Line Ending Robustness:** Replaced PowerShell here-strings (`@"..."@`) with string arrays (`@(...) -join "`r`n"`). This completely eliminates `TerminatorExpectedAtEndOfString` errors when users download the script via GitHub's "Raw" button (which defaults to Unix LF line endings) or clone on systems with `core.autocrlf=false`.
- **Interactive Launcher:** Updated `Kiosk-Launcher.bat` to support version selection (V1, V2, V3) with detailed guides, input trimming (quotes/spaces), and local file checks.

### V2 (`Setup-KioskMode-V2.ps1`)
- **Safe Admin Restrictions (HKCU):** Moved all restrictions from `HKLM` to `HKCU`. Now restrictions *only* affect the Kiosk user. Your admin accounts are completely untouched.
- **KioskShellKiller Watchdog:** Backported the same 1-minute `KioskShellKiller` scheduled task watchdog from V3 to kill explorer.exe at logon.
- **Log System:** Added comprehensive logging (`kiosk-setup.log`).
- **Software Restriction Policies (SRP):** Added process-level blocking with `PolicyScope=1` (Admins exempt).
- **Internal Watchdog:** Removed the external `watchdog.bat` file. The watchdog is now an internal Task Scheduler loop (repeats every 1 minute to avoid XML errors).

### V1 (`Setup-KioskMode.ps1`)
- *Legacy script (Deprecated / Unsupported):* Used HKLM (affected all users), had external batch watchdogs, and lacked detailed logging. V2's undo script cleans up V1 remnants automatically.

## License

MIT License — free to use, modify, and distribute.

## Contributing

Issues and pull requests are welcome. If you found a bug or have a suggestion, please open an issue.

---

*Bu proje, Windows kiosk kurulumunda yaşanan yaygın sorunları çözmek için geliştirilmiştir. Kurumsal yazılım veya özel Windows sürümü gerektirmeden, herhangi bir Windows bilgisayarını güvenli kiosk moduna dönüştürür.*
