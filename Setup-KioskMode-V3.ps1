#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Kiosk Modu Otomatik Kurulum Scripti (V3)
.DESCRIPTION
    Bu script; kiosk kullanicisi olusturma, uygulama otomatik baslatma,
    gorev cubugu gizleme, bildirim kapatma, kenar hareketleri engelleme,
    kullanici bazli kisitlama ve SRP kurulumu islemlerini otomatik yapar.
    Tum kisitlamalar HKCU bazli uygulanir -- admin hesabi etkilenmez.
.PARAMETER AppPath
    Kiosk olarak calistirilacak uygulamanin tam yolu (zorunlu)
    Ornek: C:\Kiosk\uygulama.exe
.PARAMETER AppArgs
    Uygulamaya verilecek argumanlar (istege bagli)
    Ornek: --fullscreen
.PARAMETER KioskUser
    Olusturulacak kiosk kullanicisinin adi (varsayilan: Kiosk)
.PARAMETER KioskPassword
    Kiosk kullanicisinin sifresi (bos birakilirsa otomatik giris aktif olur)
.PARAMETER AutoLogon
    Bilgisayar acildiginda Kiosk kullanicisiyla otomatik giris yapilsin mi?
.PARAMETER SkipRestrictions
    Kullanici kisitlamalarini ve SRP adimini atla
.EXAMPLE
    .\Setup-KioskMode.ps1 -AppPath "C:\Kiosk\uygulama.exe" -AutoLogon
.EXAMPLE
    .\Setup-KioskMode.ps1 -AppPath "C:\Kiosk\uygulama.exe" -AppArgs "--fullscreen" -KioskPassword "1234" -AutoLogon
.NOTES
    - Yonetici haklariyla calistirilmalidir.
    - Script sonunda bilgisayari yeniden baslatin.
    - Geri almak icin Undo-KioskMode.ps1 scriptini calistirin.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AppPath,

    [string]$AppArgs = "",

    [string]$KioskUser = "Kiosk",

    [string]$KioskPassword = "",

    [switch]$AutoLogon,

    [switch]$SkipRestrictions
)

# ---------------------------------------------
# LOG SISTEMI + YARDIMCI FONKSIYONLAR
# ---------------------------------------------

$script:LogPath = "C:\Kiosk\kiosk-setup.log"
$script:HasManualAction = $false

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","OK","WARN","FAIL","FIX","MANUAL")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    $dir = Split-Path $script:LogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Add-Content -Path $script:LogPath -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Write-Step {
    param([string]$Text)
    Write-Host "`n[$([char]0x25B6)] $Text" -ForegroundColor Cyan
    Write-Log $Text "INFO"
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
    Write-Log $Text "OK"
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [!!] $Text" -ForegroundColor Yellow
    Write-Log $Text "WARN"
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [XX] $Text" -ForegroundColor Red
    Write-Log $Text "FAIL"
}

function Write-ManualAction {
    param([string]$Text)
    Write-Host "  [MANUAL] $Text" -ForegroundColor Magenta
    Write-Log $Text "MANUAL"
    $script:HasManualAction = $true
}

function Invoke-WithAutoFix {
    param(
        [string]$StepName,
        [scriptblock]$Action,
        [hashtable]$AutoFixes = @{}
    )
    try {
        & $Action
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Fail "$StepName basarisiz: $errorMsg"

        $fixed = $false
        foreach ($pattern in $AutoFixes.Keys) {
            if ($errorMsg -match $pattern) {
                Write-Log "Otomatik duzeltme deneniyor: $pattern" "FIX"
                Write-Host "  [FIX] Otomatik duzeltme deneniyor..." -ForegroundColor DarkYellow
                try {
                    & $AutoFixes[$pattern]
                    Write-OK "$StepName otomatik duzeltildi"
                    Write-Log "$StepName otomatik duzeltildi" "FIX"
                    $fixed = $true
                    break
                } catch {
                    Write-Fail "Otomatik duzeltme de basarisiz: $($_.Exception.Message)"
                }
            }
        }

        if (-not $fixed) {
            Write-ManualAction "$StepName icin manuel mudahale gerekiyor. Detay: $errorMsg"
        }
        return $fixed
    }
}

function Ensure-RegistryPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWord"
    )
    Ensure-RegistryPath $Path
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Write-OK "Registry: $Name = $Value ($Path)"
}

function Apply-HKCURestrictions {
    param([string]$HiveBase)

    $explorerPolicy = "$HiveBase\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $systemPolicy   = "$HiveBase\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    $cmdPolicy      = "$HiveBase\Software\Policies\Microsoft\Windows\System"
    $notifPolicy    = "$HiveBase\Software\Policies\Microsoft\Windows\Explorer"
    $disallowPath   = "$explorerPolicy\DisallowRun"

    # Kiosk kullanicisina Ozel Kabuk tanimla (Custom User Shell) -- explorer.exe devre disi kalir
    $winlogonPath = "$HiveBase\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Ensure-RegistryPath $winlogonPath
    Set-ItemProperty -Path $winlogonPath -Name "Shell" -Value "cmd.exe /c exit" -Type String -Force
    Write-OK "Custom User Shell (HKCU) atandi: cmd.exe /c exit"

    # Gorev Yoneticisini devre disi birak
    Ensure-RegistryPath $systemPolicy
    Set-ItemProperty -Path $systemPolicy -Name "DisableTaskMgr" -Value 1 -Type DWord -Force

    # Denetim Masasi / Ayarlar erisimini engelle
    Ensure-RegistryPath $explorerPolicy
    Set-ItemProperty -Path $explorerPolicy -Name "NoControlPanel" -Value 1 -Type DWord -Force

    # Calistir komutunu gizle
    Set-ItemProperty -Path $explorerPolicy -Name "NoRun" -Value 1 -Type DWord -Force

    # DisallowRun aktif et
    Set-ItemProperty -Path $explorerPolicy -Name "DisallowRun" -Value 1 -Type DWord -Force

    # Engellenen uygulamalar listesi
    Ensure-RegistryPath $disallowPath
    Set-ItemProperty -Path $disallowPath -Name "1" -Value "powershell.exe"   -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "2" -Value "powershell_ise.exe" -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "3" -Value "cmd.exe"          -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "4" -Value "regedit.exe"      -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "5" -Value "mmc.exe"          -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "6" -Value "wscript.exe"      -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "7" -Value "cscript.exe"      -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "8" -Value "mshta.exe"        -Type String -Force
    Set-ItemProperty -Path $disallowPath -Name "9" -Value "pwsh.exe"          -Type String -Force

    # Komut istemi devre disi
    Ensure-RegistryPath $cmdPolicy
    Set-ItemProperty -Path $cmdPolicy -Name "DisableCMD" -Value 1 -Type DWord -Force

    # Bildirim merkezini kapat
    Ensure-RegistryPath $notifPolicy
    Set-ItemProperty -Path $notifPolicy -Name "DisableNotificationCenter" -Value 1 -Type DWord -Force

    # Windows Hata Raporlama (WerFault) penceresini kapat
    $werPath = "$HiveBase\Software\Microsoft\Windows\Windows Error Reporting"
    Ensure-RegistryPath $werPath
    Set-ItemProperty -Path $werPath -Name "DontShowUI" -Value 1 -Type DWord -Force

    # Gorev cubugunu otomatik gizle (StuckRects3)
    $stuckRectsPath = "$HiveBase\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    if (Test-Path $stuckRectsPath) {
        $stuckRects = (Get-ItemProperty -Path $stuckRectsPath).Settings
        if ($stuckRects -and $stuckRects.Length -ge 9) {
            $stuckRects[8] = 0x01
            Set-ItemProperty -Path $stuckRectsPath -Name "Settings" -Value $stuckRects
        }
    }
}

# ---------------------------------------------
# ON KONTROLLER
# ---------------------------------------------

# Parametre temizleme (Girislerdeki olasi bosluklari, cift ve tek tirnaklari temizler)
$AppPath = $AppPath.Trim().Trim('"').Trim("'")
$AppArgs = $AppArgs.Trim().Trim('"').Trim("'")
$KioskUser = $KioskUser.Trim().Trim('"').Trim("'")

Write-Host ""
Write-Host "==============================================" -ForegroundColor Magenta
Write-Host "   WINDOWS KIOSK MODU KURULUM SCRIPTI (V3)" -ForegroundColor Magenta
Write-Host "==============================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "========== KIOSK KURULUM BASLATILDI ==========" "INFO"
Write-Log "AppPath: $AppPath | KioskUser: $KioskUser | AutoLogon: $AutoLogon" "INFO"

# Yonetici kontrolu
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "Bu script yonetici haklariyla calistirilmalidir!"
    Write-Host "  Powershell'i sag tiklayip 'Yonetici olarak calistir' secin." -ForegroundColor Yellow
    exit 1
}

# AppPath tam yol kontrolu (#10)
if (-not [System.IO.Path]::IsPathRooted($AppPath)) {
    Write-Fail "AppPath tam yol olmalidir! Ornek: C:\Kiosk\uygulama.exe"
    Write-Fail "Girilen deger: $AppPath"
    exit 1
}

# Uygulama yolu kontrolu
if (-not (Test-Path $AppPath)) {
    Write-Warn "Uygulama dosyasi simdi mevcut degil: $AppPath"
    Write-Warn "Script devam edecek, ancak uygulamayi belirtilen konuma kopyalayin."
}

$AppDir = Split-Path $AppPath -Parent

# Kiosk klasoru olustur
$KioskDir = "C:\Kiosk"
if (-not (Test-Path $KioskDir)) {
    New-Item -Path $KioskDir -ItemType Directory -Force | Out-Null
    Write-OK "Kiosk klasoru olusturuldu: $KioskDir"
}

# ---------------------------------------------
# ADIM 1: KIOSK KULLANICISI OLUSTUR
# ---------------------------------------------

Write-Step "ADIM 1: Kiosk kullanicisi olusturuluyor..."

# Scripti calistiran kullanicinin kiosk kullanicisi olmadigini dogrula
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
if ($currentUser -eq $KioskUser) {
    Write-Fail "Bu script $KioskUser kullanicisiyla calistirilamaz!"
    Write-Fail "Admin hesabindan calistirin. Ctrl+Alt+Del > Kullanici Degistir."
    exit 1
}

# KioskUser adinin mevcut bir admin hesabiyla cakismadigini dogrula
$adminMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Name.Split('\')[-1] }
if ($adminMembers -contains $KioskUser) {
    $existingKiosk = Get-LocalUser -Name $KioskUser -ErrorAction SilentlyContinue
    if (-not $existingKiosk) {
        Write-Fail "'$KioskUser' adi zaten bir Administrator hesabina ait!"
        Write-Fail "Farkli bir kiosk kullanici adi secin. Ornek: -KioskUser ""KioskApp"""
        exit 1
    }
}

$existingUser = Get-LocalUser -Name $KioskUser -ErrorAction SilentlyContinue
if ($existingUser) {
    Write-Warn "Kullanici zaten mevcut: $KioskUser (atlaniyor)"

    # Kiosk kullanicisi Administrators grubundaysa cikar (guvenlik onlemi)
    $isAdmin = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match "\\$KioskUser$" }
    if ($isAdmin) {
        Remove-LocalGroupMember -Group "Administrators" -Member $KioskUser -ErrorAction SilentlyContinue
        if ($?) {
            Write-OK "Kiosk kullanicisi Administrators grubundan cikarildi (guvenlik onlemi)"
        } else {
            Write-Warn "Kiosk kullanicisi Administrators grubundan cikarilamadi -- manuel kontrol edin"
        }
    }
} else {
    Invoke-WithAutoFix -StepName "Kullanici olusturma" -Action {
        if ($KioskPassword -eq "") {
            $securePass = [System.Security.SecureString]::new()
            New-LocalUser -Name $KioskUser `
                          -Password $securePass `
                          -FullName "Kiosk Kullanicisi" `
                          -Description "Kiosk modu icin kisitli kullanici" `
                          -PasswordNeverExpires `
                          -UserMayNotChangePassword | Out-Null
        } else {
            $securePass = ConvertTo-SecureString $KioskPassword -AsPlainText -Force
            New-LocalUser -Name $KioskUser `
                          -Password $securePass `
                          -FullName "Kiosk Kullanicisi" `
                          -Description "Kiosk modu icin kisitli kullanici" `
                          -PasswordNeverExpires `
                          -UserMayNotChangePassword | Out-Null
        }
        Add-LocalGroupMember -Group "Users" -Member $KioskUser -ErrorAction SilentlyContinue
        Write-OK "Kullanici olusturuldu: $KioskUser (Standart)"
    } -AutoFixes @{
        "already exists|zaten mevcut" = {
            Remove-LocalUser -Name $KioskUser -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            if ($KioskPassword -eq "") {
                $securePass = [System.Security.SecureString]::new()
            } else {
                $securePass = ConvertTo-SecureString $KioskPassword -AsPlainText -Force
            }
            New-LocalUser -Name $KioskUser -Password $securePass `
                          -FullName "Kiosk Kullanicisi" `
                          -Description "Kiosk modu icin kisitli kullanici" `
                          -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
            Add-LocalGroupMember -Group "Users" -Member $KioskUser -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------
# ADIM 2: GOREV ZAMANLAYICI (Tek gorev, dahili watchdog)
# ---------------------------------------------
# Watchdog bat dosyasi KALDIRILDI (#2,#7,#8)
# Yerine: AtLogOn tetikleyicisi + 30s tekrar = hem aninda baslatma hem watchdog

Write-Step "ADIM 2: Gorev Zamanlayici gorevi kuruluyor..."

# Gorev Zamanlayici servisinin calistigini dogrula
$schedService = Get-Service -Name "Schedule" -ErrorAction SilentlyContinue
if (-not $schedService) {
    Write-Fail "Gorev Zamanlayici servisi bulunamadi!"
    Write-ManualAction "Task Scheduler servisi sistemde yok. Kiosk uygulamasi otomatik baslatilamaz."
} elseif ($schedService.Status -ne "Running") {
    Write-Warn "Gorev Zamanlayici servisi calismiyordu, baslatiliyor..."
    try {
        Set-Service -Name "Schedule" -StartupType Automatic -ErrorAction Stop
        Start-Service -Name "Schedule" -ErrorAction Stop
        Write-OK "Gorev Zamanlayici servisi baslatildi ve otomatik baslama ayarlandi"
    } catch {
        Write-Fail "Gorev Zamanlayici servisi baslatilamadi: $($_.Exception.Message)"
        Write-ManualAction "Task Scheduler servisi manuel olarak baslatilmali: services.msc > Task Scheduler > Start"
    }
}

Invoke-WithAutoFix -StepName "KioskApp gorevi olusturma" -Action {
    $appAction  = New-ScheduledTaskAction -Execute $AppPath -Argument $AppArgs -WorkingDirectory $AppDir
    $appTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser

    $tempTrigger = New-ScheduledTaskTrigger -Once -At "00:00" `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 9999)
    $appTrigger.Repetition = $tempTrigger.Repetition

    $appSettings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([System.TimeSpan]::Zero)
    $appPrincipal = New-ScheduledTaskPrincipal -UserId $KioskUser -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask `
        -TaskName "KioskApp" `
        -Action $appAction `
        -Trigger $appTrigger `
        -Settings $appSettings `
        -Principal $appPrincipal `
        -Force | Out-Null

    Write-OK "Gorev olusturuldu: KioskApp (AtLogOn + 1-dakika tekrar watchdog)"
} -AutoFixes @{
    "already exists|access|denied|erisim" = {
        Unregister-ScheduledTask -TaskName "KioskApp" -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $appAction  = New-ScheduledTaskAction -Execute $AppPath -Argument $AppArgs -WorkingDirectory $AppDir
        $appTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser
        $tempTrigger = New-ScheduledTaskTrigger -Once -At "00:00" `
            -RepetitionInterval (New-TimeSpan -Minutes 1) `
            -RepetitionDuration (New-TimeSpan -Days 9999)
        $appTrigger.Repetition = $tempTrigger.Repetition
        $appSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit ([System.TimeSpan]::Zero)
        $appPrincipal = New-ScheduledTaskPrincipal -UserId $KioskUser -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName "KioskApp" -Action $appAction -Trigger $appTrigger `
            -Settings $appSettings -Principal $appPrincipal -Force | Out-Null
    }
}

# KioskShellKiller Gorevi (Masaustunu / explorer.exe'yi surekli sonlandirir)
Invoke-WithAutoFix -StepName "KioskShellKiller gorevi olusturma" -Action {
    $skAction  = New-ScheduledTaskAction -Execute "taskkill.exe" -Argument "/F /IM explorer.exe"
    $skTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser

    $tempTrigger = New-ScheduledTaskTrigger -Once -At "00:00" `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 9999)
    $skTrigger.Repetition = $tempTrigger.Repetition

    $skSettings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([System.TimeSpan]::Zero)
    $skPrincipal = New-ScheduledTaskPrincipal -UserId $KioskUser -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask `
        -TaskName "KioskShellKiller" `
        -Action $skAction `
        -Trigger $skTrigger `
        -Settings $skSettings `
        -Principal $skPrincipal `
        -Force | Out-Null

    Write-OK "Gorev olusturuldu: KioskShellKiller (AtLogOn + 1-dakika tekrar)"
} -AutoFixes @{
    "already exists|access|denied|erisim" = {
        Unregister-ScheduledTask -TaskName "KioskShellKiller" -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $skAction  = New-ScheduledTaskAction -Execute "taskkill.exe" -Argument "/F /IM explorer.exe"
        $skTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser
        $tempTrigger = New-ScheduledTaskTrigger -Once -At "00:00" `
            -RepetitionInterval (New-TimeSpan -Minutes 1) `
            -RepetitionDuration (New-TimeSpan -Days 9999)
        $skTrigger.Repetition = $tempTrigger.Repetition
        $skSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit ([System.TimeSpan]::Zero)
        $skPrincipal = New-ScheduledTaskPrincipal -UserId $KioskUser -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName "KioskShellKiller" -Action $skAction -Trigger $skTrigger `
            -Settings $skSettings -Principal $skPrincipal -Force | Out-Null
    }
}

# Eski KioskWatchdog varsa temizle
Unregister-ScheduledTask -TaskName "KioskWatchdog" -Confirm:$false -ErrorAction SilentlyContinue
$oldWatchdog = "C:\Kiosk\watchdog.bat"
if (Test-Path $oldWatchdog) {
    Remove-Item -Path $oldWatchdog -Force -ErrorAction SilentlyContinue
    Write-OK "Eski watchdog.bat temizlendi"
}

# ---------------------------------------------
# ADIM 3: KAYIT DEFTERI AYARLARI (SISTEM GENELI)
# ---------------------------------------------

Write-Step "ADIM 3: Sistem geneli registry ayarlari yapiliyor..."

Set-RegValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI" `
    -Name "AllowEdgeSwipe" `
    -Value 0

Write-OK "Kenar kaydir hareketi devre disi birakildi"

# ---------------------------------------------
# ADIM 4: KIOSK KULLANICISI HKCU KISITLAMALARI
# ---------------------------------------------
# Tum kisitlamalar HKCU bazli -- admin hesabi ETKiLENMEZ (#1,#3,#4)
# Hive yuklenebilirse dogrudan yaz, yuklenemezse FirstLogon gorevi olustur

if (-not $SkipRestrictions) {
    Write-Step "ADIM 4: Kiosk kullanicisi HKCU kisitlamalari uygulaniyor..."

    $kioskSID = $null
    try {
        $kioskSID = (Get-LocalUser -Name $KioskUser).SID.Value
        Write-OK "Kiosk kullanici SID: $kioskSID"
    } catch {
        Write-Fail "Kiosk kullanici SID alinamadi: $_"
    }

    $hivePath = "C:\Users\$KioskUser\NTUSER.DAT"
    $hiveLoaded = $false
    $hkuBase = "Registry::HKEY_USERS\KioskTemp"

    if (Test-Path $hivePath) {
        # Hive yuklu olabilir, once unload dene
        reg unload "HKU\KioskTemp" 2>$null | Out-Null
        Start-Sleep -Milliseconds 300

        $regLoadResult = reg load "HKU\KioskTemp" $hivePath 2>&1
        if ($LASTEXITCODE -eq 0) {
            $hiveLoaded = $true
            Write-OK "Kiosk hive yuklendi"
        } else {
            Write-Warn "Hive yuklenemedi (oturum acik olabilir): $regLoadResult"
        }
    } else {
        Write-Warn "Kiosk profili henuz olusturulmamis -- FirstLogon gorevi olusturulacak."
    }

    if ($hiveLoaded) {
        Invoke-WithAutoFix -StepName "HKCU kisitlamalari uygulama" -Action {
            Apply-HKCURestrictions -HiveBase $hkuBase
            Write-OK "HKCU kisitlamalari dogrudan hive uzerinden uygulandi"
        } -AutoFixes @{
            ".*" = {
                Write-ManualAction "HKCU kisitlamalari hive uzerinden yazilamadi. Kiosk kullanicisi ilk oturum actiktan sonra FirstLogon gorevi ile uygulanacak."
            }
        }

        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        reg unload "HKU\KioskTemp" | Out-Null
        Write-OK "Kiosk hive kaydedildi ve kaldirildi"
    } else {
        if (-not $kioskSID) {
            Write-ManualAction "Kiosk SID alinamadigi icin FirstLogon gorevi olusturulamiyor. Cozum: Kiosk kullanicisini silip scripti tekrar calistirin."
        } else {
        Write-Warn "Hive yuklenemedi, FirstLogon gorevi olusturuluyor..."

        # FirstLogon.ps1 -- SYSTEM olarak calisir, ilk oturumda HKCU kisitlamalarini uygular
        # Kullanici oturum actiysa hive zaten HKU\<SID> altinda mount edilmis olur
        # reg load KULLANILMAZ -- dosya kilitli olur. Dogrudan HKU\<SID> uzerinden yazilir.
        $firstLogonPath = "$KioskDir\FirstLogon.ps1"
        $firstLogonContent = @(
    "",
    "`$kioskUser = `"$KioskUser`"",
    "`$kioskSID  = `"$kioskSID`"",
    "",
    "Start-Sleep -Seconds 10",
    "",
    "# Kullanici oturum actiysa hive zaten HKU\<SID> altinda yuklu",
    "`$hkuBase = `"Registry::HKEY_USERS\`$kioskSID`"",
    "",
    "# SID altinda hive yuklu mu kontrol et",
    "if (-not (Test-Path `$hkuBase)) {",
    "    # Oturum henuz tam acilmamis olabilir, biraz daha bekle",
    "    Start-Sleep -Seconds 10",
    "    if (-not (Test-Path `$hkuBase)) { exit 1 }",
    "}",
    "",
    "# --- HKCU kisitlamalari ---",
    "`$explorerPolicy = `"`$hkuBase\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer`"",
    "`$systemPolicy   = `"`$hkuBase\Software\Microsoft\Windows\CurrentVersion\Policies\System`"",
    "`$cmdPolicy      = `"`$hkuBase\Software\Policies\Microsoft\Windows\System`"",
    "`$notifPolicy    = `"`$hkuBase\Software\Policies\Microsoft\Windows\Explorer`"",
    "`$disallowPath   = `"`$explorerPolicy\DisallowRun`"",
    "",
    "# Kiosk kullanicisina Ozel Kabuk tanimla (explorer.exe devre disi kalir)",
    "`$winlogonPath = `"`$hkuBase\Software\Microsoft\Windows NT\CurrentVersion\Winlogon`"",
    "New-Item -Path `$winlogonPath -Force | Out-Null",
    "Set-ItemProperty -Path `$winlogonPath -Name `"Shell`" -Value `"cmd.exe /c exit`" -Type String -Force",
    "",
    "New-Item -Path `$systemPolicy -Force | Out-Null",
    "Set-ItemProperty -Path `$systemPolicy -Name `"DisableTaskMgr`" -Value 1 -Type DWord -Force",
    "",
    "New-Item -Path `$explorerPolicy -Force | Out-Null",
    "Set-ItemProperty -Path `$explorerPolicy -Name `"NoControlPanel`" -Value 1 -Type DWord -Force",
    "Set-ItemProperty -Path `$explorerPolicy -Name `"NoRun`" -Value 1 -Type DWord -Force",
    "Set-ItemProperty -Path `$explorerPolicy -Name `"DisallowRun`" -Value 1 -Type DWord -Force",
    "",
    "New-Item -Path `$disallowPath -Force | Out-Null",
    "Set-ItemProperty -Path `$disallowPath -Name `"1`" -Value `"powershell.exe`"   -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"2`" -Value `"powershell_ise.exe`" -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"3`" -Value `"cmd.exe`"          -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"4`" -Value `"regedit.exe`"      -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"5`" -Value `"mmc.exe`"          -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"6`" -Value `"wscript.exe`"      -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"7`" -Value `"cscript.exe`"      -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"8`" -Value `"mshta.exe`"        -Type String -Force",
    "Set-ItemProperty -Path `$disallowPath -Name `"9`" -Value `"pwsh.exe`"          -Type String -Force",
    "",
    "New-Item -Path `$cmdPolicy -Force | Out-Null",
    "Set-ItemProperty -Path `$cmdPolicy -Name `"DisableCMD`" -Value 1 -Type DWord -Force",
    "",
    "New-Item -Path `$notifPolicy -Force | Out-Null",
    "Set-ItemProperty -Path `$notifPolicy -Name `"DisableNotificationCenter`" -Value 1 -Type DWord -Force",
    "",
    "# Windows Hata Raporlama (WerFault) penceresini kapat",
    "`$werPath = `"`$hkuBase\Software\Microsoft\Windows\Windows Error Reporting`"",
    "New-Item -Path `$werPath -Force | Out-Null",
    "Set-ItemProperty -Path `$werPath -Name `"DontShowUI`" -Value 1 -Type DWord -Force",
    "",
    "`$stuckRectsPath = `"`$hkuBase\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3`"",
    "if (Test-Path `$stuckRectsPath) {",
    "    `$sr = (Get-ItemProperty -Path `$stuckRectsPath).Settings",
    "    if (`$sr -and `$sr.Length -ge 9) {",
    "        `$sr[8] = 0x01",
    "        Set-ItemProperty -Path `$stuckRectsPath -Name `"Settings`" -Value `$sr",
    "    }",
    "}",
    "",
    "# Kiosk kullanicisinin Explorer'ini kapat (kisitlamalar etkili olsun, shell gereksiz)",
    "taskkill /FI `"USERNAME eq `$kioskUser`" /IM explorer.exe /F 2>`$null",
    "",
    "# Kendini temizle",
    "Remove-Item -Path `"$firstLogonPath`" -Force -ErrorAction SilentlyContinue",
    "Unregister-ScheduledTask -TaskName `"KioskFirstLogon`" -Confirm:`$false -ErrorAction SilentlyContinue"
) -join "`r`n"

        Set-Content -Path $firstLogonPath -Value $firstLogonContent -Encoding UTF8
        Write-OK "FirstLogon scripti olusturuldu: $firstLogonPath"

        Invoke-WithAutoFix -StepName "FirstLogon gorevi olusturma" -Action {
            $flAction  = New-ScheduledTaskAction `
                -Execute "powershell.exe" `
                -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$firstLogonPath`""
            $flTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser
            $flSettings = New-ScheduledTaskSettingsSet `
                -MultipleInstances IgnoreNew `
                -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
            $flPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

            Register-ScheduledTask `
                -TaskName "KioskFirstLogon" `
                -Action $flAction `
                -Trigger $flTrigger `
                -Settings $flSettings `
                -Principal $flPrincipal `
                -Force | Out-Null

            Write-OK "FirstLogon gorevi olusturuldu (SYSTEM olarak calisacak, ilk oturumda tetiklenecek)"
        } -AutoFixes @{
            "already exists|access|denied" = {
                Unregister-ScheduledTask -TaskName "KioskFirstLogon" -Confirm:$false -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                $flAction  = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$firstLogonPath`""
                $flTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser
                $flSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
                $flPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                Register-ScheduledTask -TaskName "KioskFirstLogon" -Action $flAction -Trigger $flTrigger `
                    -Settings $flSettings -Principal $flPrincipal -Force | Out-Null
            }
        }
        } # $kioskSID null guard sonu
    }

    # ---------------------------------------------
    # ADIM 5: SOFTWARE RESTRICTION POLICIES (SRP)
    # ---------------------------------------------
    # SRP islem duzeyinde engeller -- DisallowRun'dan daha guclu (#5)
    # PolicyScope=1 ile admin kullanicilari MUAF tutulur

    Write-Step "ADIM 5: Software Restriction Policies (SRP) kurulumu..."

    Invoke-WithAutoFix -StepName "SRP kurulumu" -Action {
        $srpBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"

        Ensure-RegistryPath $srpBase
        Set-ItemProperty -Path $srpBase -Name "DefaultLevel"      -Value 262144 -Type DWord -Force
        Set-ItemProperty -Path $srpBase -Name "TransparentEnabled" -Value 1      -Type DWord -Force
        Set-ItemProperty -Path $srpBase -Name "PolicyScope"        -Value 1      -Type DWord -Force
        Write-OK "SRP varsayilan seviye: Unrestricted, PolicyScope: Yalnizca standart kullanicilar"

        $srpDisallowedPath = "$srpBase\0\Paths"
        Ensure-RegistryPath $srpDisallowedPath

        $blockedApps = @(
            @{ Guid = "{191cd7fa-f240-4a17-8986-94d480a6c8ca}"; Path = "%SystemRoot%\System32\cmd.exe" },
            @{ Guid = "{282cd7fa-f240-4a17-8986-94d480a6c8cb}"; Path = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" },
            @{ Guid = "{393cd7fa-f240-4a17-8986-94d480a6c8cc}"; Path = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell_ise.exe" },
            @{ Guid = "{4a4cd7fa-f240-4a17-8986-94d480a6c8cd}"; Path = "%SystemRoot%\regedit.exe" },
            @{ Guid = "{5b5cd7fa-f240-4a17-8986-94d480a6c8ce}"; Path = "%SystemRoot%\System32\mmc.exe" },
            @{ Guid = "{6c6cd7fa-f240-4a17-8986-94d480a6c8cf}"; Path = "%SystemRoot%\System32\wscript.exe" },
            @{ Guid = "{7d7cd7fa-f240-4a17-8986-94d480a6c8d0}"; Path = "%SystemRoot%\System32\cscript.exe" },
            @{ Guid = "{8e8cd7fa-f240-4a17-8986-94d480a6c8d1}"; Path = "%SystemRoot%\System32\mshta.exe" },
            @{ Guid = "{9f9cd7fa-f240-4a17-8986-94d480a6c8d2}"; Path = "%SystemRoot%\System32\Taskmgr.exe" },
            @{ Guid = "{a10cd7fa-f240-4a17-8986-94d480a6c8d3}"; Path = "%ProgramFiles%\PowerShell\*\pwsh.exe" },
            @{ Guid = "{a11cd7fa-f240-4a17-8986-94d480a6c8d4}"; Path = "%ProgramFiles(x86)%\PowerShell\*\pwsh.exe" },
            @{ Guid = "{b20cd7fa-f240-4a17-8986-94d480a6c8d5}"; Path = "%SystemRoot%\SysWOW64\cmd.exe" },
            @{ Guid = "{b21cd7fa-f240-4a17-8986-94d480a6c8d6}"; Path = "%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" },
            @{ Guid = "{b22cd7fa-f240-4a17-8986-94d480a6c8d7}"; Path = "%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell_ise.exe" },
            @{ Guid = "{b23cd7fa-f240-4a17-8986-94d480a6c8d8}"; Path = "%SystemRoot%\SysWOW64\mmc.exe" },
            @{ Guid = "{b24cd7fa-f240-4a17-8986-94d480a6c8d9}"; Path = "%SystemRoot%\SysWOW64\wscript.exe" },
            @{ Guid = "{b25cd7fa-f240-4a17-8986-94d480a6c8da}"; Path = "%SystemRoot%\SysWOW64\cscript.exe" },
            @{ Guid = "{b26cd7fa-f240-4a17-8986-94d480a6c8db}"; Path = "%SystemRoot%\SysWOW64\mshta.exe" }
        )

        foreach ($app in $blockedApps) {
            $rulePath = "$srpDisallowedPath\$($app.Guid)"
            Ensure-RegistryPath $rulePath
            Set-ItemProperty -Path $rulePath -Name "ItemData"   -Value $app.Path -Type ExpandString -Force
            Set-ItemProperty -Path $rulePath -Name "SaferFlags" -Value 0         -Type DWord        -Force
        }

        Write-OK "SRP kurallari olusturuldu: $($blockedApps.Count) uygulama engellendi (admin muaf)"
    } -AutoFixes @{
        "access|denied|erisim|yetki" = {
            Write-ManualAction "SRP registry anahtarlarina yazma yetkisi yok. Cozum: Script'i Administrator olarak calistirin veya grup ilkesi SRP'yi engelliyor olabilir."
        }
    }

} else {
    Write-Warn "ADIM 4-5: Kullanici kisitlamalari ve SRP atlaniyor (-SkipRestrictions)"
}

# ---------------------------------------------
# ADIM 6: OTOMATIK OTURUM ACMA
# ---------------------------------------------

if ($AutoLogon) {
    Write-Step "ADIM 6: Otomatik oturum acma yapilandiriliyor..."

    Invoke-WithAutoFix -StepName "Otomatik oturum acma" -Action {
        $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

        Set-RegValue -Path $winlogonPath -Name "AutoAdminLogon"    -Value "1"                -Type String
        Set-RegValue -Path $winlogonPath -Name "DefaultUserName"   -Value $KioskUser         -Type String
        Set-RegValue -Path $winlogonPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME   -Type String

        if ($KioskPassword -eq "") {
            Remove-ItemProperty -Path $winlogonPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
            Write-OK "Otomatik oturum acma aktif edildi: $KioskUser (sifresiz)"
        } else {
            Set-RegValue -Path $winlogonPath -Name "DefaultPassword" -Value $KioskPassword -Type String
            Write-OK "Otomatik oturum acma aktif edildi: $KioskUser"
            Write-Warn "GUVENLIK UYARISI: Sifre registry'de duz metin olarak saklanmaktadir!"
            Write-Warn "Onerilen: Sysinternals Autologon.exe ile LSA Secrets sifrelemesi kullanin."
            Write-Warn "Indirme: https://learn.microsoft.com/en-us/sysinternals/downloads/autologon"
        }
    } -AutoFixes @{
        "access|denied|erisim|yetki" = {
            Write-ManualAction "Winlogon registry anahtarina yazma yetkisi yok. Cozum: Script'i Administrator olarak calistirin."
        }
    }
} else {
    Write-Host "`n  [--] Otomatik oturum acma yapilandirilmadi (-AutoLogon parametresi verilmedi)" -ForegroundColor DarkGray
}

# ---------------------------------------------
# ADIM 7: GERI ALMA SCRIPTI OLUSTUR
# ---------------------------------------------

Write-Step "ADIM 7: Geri alma (Undo) scripti olusturuluyor..."

$undoScriptPath = "$KioskDir\Undo-KioskMode.ps1"
$undoContent = @(
    "#Requires -RunAsAdministrator",
    "<#",
    ".SYNOPSIS",
    "    Kiosk modunu geri alir (Undo)",
    ".DESCRIPTION",
    "    Setup-KioskMode V3 tarafindan yapilan tum degisiklikleri geri alir.",
    "#>",
    "",
    "Write-Host `"Kiosk modu geri aliniyor...`" -ForegroundColor Yellow",
    "",
    "# --- Gorev Zamanlayici gorevlerini sil ---",
    "Unregister-ScheduledTask -TaskName `"KioskApp`"         -Confirm:`$false -ErrorAction SilentlyContinue",
    "Unregister-ScheduledTask -TaskName `"KioskShellKiller`" -Confirm:`$false -ErrorAction SilentlyContinue",
    "Unregister-ScheduledTask -TaskName `"KioskWatchdog`"    -Confirm:`$false -ErrorAction SilentlyContinue",
    "Unregister-ScheduledTask -TaskName `"KioskFirstLogon`"  -Confirm:`$false -ErrorAction SilentlyContinue",
    "Write-Host `"[OK] Gorev Zamanlayici gorevleri silindi`" -ForegroundColor Green",
    "",
    "# --- FirstLogon ve eski watchdog dosyalarini temizle ---",
    "Remove-Item -Path `"C:\Kiosk\FirstLogon.ps1`" -Force -ErrorAction SilentlyContinue",
    "Remove-Item -Path `"C:\Kiosk\watchdog.bat`"   -Force -ErrorAction SilentlyContinue",
    "Write-Host `"[OK] Yardimci script dosyalari temizlendi`" -ForegroundColor Green",
    "",
    "# --- Otomatik oturum acmayi kapat ---",
    "`$winlogonPath = `"HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`"",
    "Set-ItemProperty -Path `$winlogonPath -Name `"AutoAdminLogon`" -Value `"0`" -ErrorAction SilentlyContinue",
    "Remove-ItemProperty -Path `$winlogonPath -Name `"DefaultPassword`"   -ErrorAction SilentlyContinue",
    "Remove-ItemProperty -Path `$winlogonPath -Name `"DefaultUserName`"   -ErrorAction SilentlyContinue",
    "Remove-ItemProperty -Path `$winlogonPath -Name `"DefaultDomainName`" -ErrorAction SilentlyContinue",
    "Write-Host `"[OK] Otomatik oturum acma devre disi birakildi`" -ForegroundColor Green",
    "",
    "# --- Kenar kaydirma geri ac ---",
    "Remove-ItemProperty -Path `"HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI`" -Name `"AllowEdgeSwipe`" -ErrorAction SilentlyContinue",
    "Write-Host `"[OK] Kenar kaydir hareketi geri acildi`" -ForegroundColor Green",
    "",
    "# --- SRP temizle (#5) ---",
    "Remove-Item -Path `"HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer`" -Recurse -Force -ErrorAction SilentlyContinue",
    "Write-Host `"[OK] Software Restriction Policies temizlendi`" -ForegroundColor Green",
    "",
    "# --- V1 HKLM policy kalintilari temizle (eski kurulumlarla uyum) ---",
    "`$v1ExplorerPolicies = `"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer`"",
    "Remove-ItemProperty -Path `$v1ExplorerPolicies -Name `"NoControlPanel`" -ErrorAction SilentlyContinue",
    "Remove-ItemProperty -Path `$v1ExplorerPolicies -Name `"NoRun`"          -ErrorAction SilentlyContinue",
    "Remove-ItemProperty -Path `$v1ExplorerPolicies -Name `"DisallowRun`"    -ErrorAction SilentlyContinue",
    "Remove-Item -Path `"`$v1ExplorerPolicies\DisallowRun`" -Recurse -ErrorAction SilentlyContinue",
    "",
    "`$v1SystemPolicies = `"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`"",
    "Remove-ItemProperty -Path `$v1SystemPolicies -Name `"DisableTaskMgr`" -ErrorAction SilentlyContinue",
    "",
    "`$v1CmdPolicy = `"HKLM:\SOFTWARE\Policies\Microsoft\Windows\System`"",
    "Remove-ItemProperty -Path `$v1CmdPolicy -Name `"DisableCMD`" -ErrorAction SilentlyContinue",
    "",
    "Write-Host `"[OK] V1 HKLM policy kalintilari temizlendi (varsa)`" -ForegroundColor Green",
    "",
    "# --- Kiosk kullanicisi HKCU kisitlamalarini temizle (#9) ---",
    "`$kioskUser = `"$KioskUser`"",
    "`$hivePath = `"C:\Users\`$kioskUser\NTUSER.DAT`"",
    "`$hkuCleaned = `$false",
    "",
    "# Once SID uzerinden dene (oturum aciksa hive zaten HKU\<SID> altinda yuklu)",
    "`$kioskSIDObj = (Get-LocalUser -Name `$kioskUser -ErrorAction SilentlyContinue).SID",
    "if (`$kioskSIDObj) {",
    "    `$sidPath = `"Registry::HKEY_USERS\`$(`$kioskSIDObj.Value)`"",
    "    if (Test-Path `$sidPath) {",
    "        `$hkuBase = `$sidPath",
    "        `$hkuCleaned = `$true",
    "    }",
    "}",
    "",
    "# SID yoksa veya oturum kapali ise reg load dene",
    "if (-not `$hkuCleaned -and (Test-Path `$hivePath)) {",
    "    reg load `"HKU\KioskTemp`" `$hivePath 2>`$null",
    "    if (`$LASTEXITCODE -eq 0) {",
    "        `$hkuBase = `"Registry::HKEY_USERS\KioskTemp`"",
    "        `$hkuCleaned = `$true",
    "    } else {",
    "        Write-Host `"[!!] Kiosk hive yuklenemedi (oturum acik olabilir, kapattiktan sonra tekrar deneyin)`" -ForegroundColor Yellow",
    "    }",
    "}",
    "",
    "if (`$hkuCleaned) {",
    "    # Kisitlamalari kaldir",
    "    `$explorerPolicy = `"`$hkuBase\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer`"",
    "    Remove-ItemProperty -Path `$explorerPolicy -Name `"NoControlPanel`" -ErrorAction SilentlyContinue",
    "    Remove-ItemProperty -Path `$explorerPolicy -Name `"NoRun`"          -ErrorAction SilentlyContinue",
    "    Remove-ItemProperty -Path `$explorerPolicy -Name `"DisallowRun`"    -ErrorAction SilentlyContinue",
    "    Remove-Item -Path `"`$explorerPolicy\DisallowRun`" -Recurse -ErrorAction SilentlyContinue",
    "",
    "    `$systemPolicy = `"`$hkuBase\Software\Microsoft\Windows\CurrentVersion\Policies\System`"",
    "    Remove-ItemProperty -Path `$systemPolicy -Name `"DisableTaskMgr`" -ErrorAction SilentlyContinue",
    "",
    "    `$cmdPolicy = `"`$hkuBase\Software\Policies\Microsoft\Windows\System`"",
    "    Remove-ItemProperty -Path `$cmdPolicy -Name `"DisableCMD`" -ErrorAction SilentlyContinue",
    "",
    "    # DisableNotificationCenter temizle (#9)",
    "    `$notifPolicy = `"`$hkuBase\Software\Policies\Microsoft\Windows\Explorer`"",
    "    Remove-ItemProperty -Path `$notifPolicy -Name `"DisableNotificationCenter`" -ErrorAction SilentlyContinue",
    "",
    "    # WerFault (DontShowUI) temizle",
    "    `$werPath = `"`$hkuBase\Software\Microsoft\Windows\Windows Error Reporting`"",
    "    Remove-ItemProperty -Path `$werPath -Name `"DontShowUI`" -ErrorAction SilentlyContinue",
    "",
    "    # Custom User Shell temizle (explorer.exe geri donsun)",
    "    `$winlogonPath = `"`$hkuBase\Software\Microsoft\Windows NT\CurrentVersion\Winlogon`"",
    "    Remove-ItemProperty -Path `$winlogonPath -Name `"Shell`" -ErrorAction SilentlyContinue",
    "",
    "    # StuckRects3 gorev cubugunu gorunur yap (#9)",
    "    `$stuckRectsPath = `"`$hkuBase\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3`"",
    "    if (Test-Path `$stuckRectsPath) {",
    "        `$sr = (Get-ItemProperty -Path `$stuckRectsPath).Settings",
    "        if (`$sr -and `$sr.Length -ge 9) {",
    "            `$sr[8] = 0x03",
    "            Set-ItemProperty -Path `$stuckRectsPath -Name `"Settings`" -Value `$sr",
    "        }",
    "    }",
    "",
    "    # reg load ile yuklendiyse unload yap (SID uzerinden yazdiysa gerek yok)",
    "    if (`$hkuBase -eq `"Registry::HKEY_USERS\KioskTemp`") {",
    "        [gc]::Collect()",
    "        Start-Sleep -Milliseconds 500",
    "        reg unload `"HKU\KioskTemp`" | Out-Null",
    "    }",
    "",
    "    Write-Host `"[OK] Kiosk kullanicisi HKCU kisitlamalari temizlendi`" -ForegroundColor Green",
    "} elseif (-not `$kioskSIDObj) {",
    "    Write-Host `"[!!] Kiosk kullanicisi bulunamadi, HKCU temizligi atlaniyor`" -ForegroundColor Yellow",
    "} else {",
    "    Write-Host `"[!!] Kiosk profili bulunamadi, HKCU temizligi atlaniyor`" -ForegroundColor Yellow",
    "}",
    "",
    "# --- Kiosk kullanicisini sil (onay iste) ---",
    "`$confirm = Read-Host `"Kiosk kullanicisini ($KioskUser) silmek istiyor musunuz? (E/H)`"",
    "if (`$confirm -eq `"E`" -or `$confirm -eq `"e`") {",
    "    Remove-LocalUser -Name `"$KioskUser`" -ErrorAction SilentlyContinue",
    "    Write-Host `"[OK] Kiosk kullanicisi silindi`" -ForegroundColor Green",
    "}",
    "",
    "Write-Host `"`nGeri alma tamamlandi. Lutfen bilgisayari yeniden baslatin.`" -ForegroundColor Cyan"
) -join "`r`n"

Set-Content -Path $undoScriptPath -Value $undoContent -Encoding UTF8
Write-OK "Geri alma scripti olusturuldu: $undoScriptPath"

$setupDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$undoCopyPath = Join-Path $setupDir "Undo-KioskMode.ps1"
if ($undoCopyPath -ne $undoScriptPath) {
    Copy-Item -Path $undoScriptPath -Destination $undoCopyPath -Force
    Write-OK "Geri alma scripti kopyalandi: $undoCopyPath"
}

# ---------------------------------------------
# OZET
# ---------------------------------------------

Write-Host ""
Write-Host "==============================================" -ForegroundColor Magenta
Write-Host "   KURULUM TAMAMLANDI (V3)" -ForegroundColor Magenta
Write-Host "==============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Kiosk Kullanicisi : $KioskUser" -ForegroundColor White
Write-Host "  Uygulama          : $AppPath" -ForegroundColor White
Write-Host "  Geri alma scripti : $undoScriptPath" -ForegroundColor White
Write-Host ""
Write-Host "  YAPILAN ISLEMLER:" -ForegroundColor Cyan
Write-Host "  [+] Kiosk kullanicisi olusturuldu/kontrol edildi" -ForegroundColor Green
Write-Host "  [+] KioskApp gorevi kuruldu (AtLogOn + 30s tekrar watchdog)" -ForegroundColor Green
Write-Host "  [+] Kenar kaydir hareketi devre disi birakildi" -ForegroundColor Green
if (-not $SkipRestrictions) {
    Write-Host "  [+] HKCU kisitlamalari uygulandi (sadece kiosk kullanicisi)" -ForegroundColor Green
    Write-Host "  [+] SRP kurallari olusturuldu (admin muaf)" -ForegroundColor Green
    Write-Host "  [+] Engellenenler: cmd, powershell, pwsh, regedit, mmc, wscript, cscript, mshta, taskmgr" -ForegroundColor Green
}
if ($AutoLogon) {
    Write-Host "  [+] Otomatik oturum acma aktif edildi" -ForegroundColor Green
}
Write-Host ""
Write-Host "  GUVENLIK NOTU:" -ForegroundColor Yellow
Write-Host "  Admin hesabiniz hicbir kisitlamadan ETKiLENMEZ." -ForegroundColor Yellow
Write-Host "  Tum kisitlamalar yalnizca $KioskUser kullanicisina uygulanir." -ForegroundColor Yellow
Write-Host ""
Write-Host "  SONRAKI ADIMLAR:" -ForegroundColor Yellow
Write-Host "  1. Uygulamayi su konuma kopyalayin: $AppPath" -ForegroundColor Yellow
Write-Host "  2. Bilgisayari YENIDEN BASLATIN" -ForegroundColor Yellow
Write-Host "  3. Kiosk kullanicisi oturum actiktan sonra ayarlar tam etkin olur" -ForegroundColor Yellow
Write-Host "  4. Yonetici erisimi: Ctrl+Alt+Del > Kullanici Degistir" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Geri almak icin: $undoScriptPath" -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------
# LOG OZETI
# ---------------------------------------------

Write-Log "========== KIOSK KURULUM TAMAMLANDI ==========" "INFO"

if ($script:HasManualAction) {
    Write-Host "  +======================================================+" -ForegroundColor Red
    Write-Host "  |  DIKKAT: Bazi adimlar manuel mudahale gerektiriyor! |" -ForegroundColor Red
    Write-Host "  +======================================================+" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Log dosyasini inceleyin: $($script:LogPath)" -ForegroundColor Red
    Write-Host "  [MANUAL] etiketli satirlari arayin." -ForegroundColor Red
    Write-Log "KURULUM TAMAMLANDI -- MANUEL MUDAHALE GEREKEN ADIMLAR VAR" "WARN"
} else {
    Write-Host "  Tum adimlar basariyla tamamlandi." -ForegroundColor Green
    Write-Log "KURULUM TAMAMLANDI -- TUM ADIMLAR BASARILI" "OK"
}

Write-Host "  Log dosyasi: $($script:LogPath)" -ForegroundColor DarkGray
Write-Host ""

$restart = Read-Host "Bilgisayari simdi yeniden baslatmak istiyor musunuz? (E/H)"
if ($restart -eq "E" -or $restart -eq "e") {
    Write-Host "Yeniden baslatiliyor..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    Restart-Computer -Force
}
