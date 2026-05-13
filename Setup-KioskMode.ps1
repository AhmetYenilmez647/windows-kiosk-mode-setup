#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Kiosk Modu Otomatik Kurulum Scripti
.DESCRIPTION
    Bu script; kiosk kullanıcısı olusturma, uygulama otomatik baslatma,
    gorev cubugu gizleme, bildirim kapatma, kenar hareketleri engelleme,
    grup ilkesi kisitlama ve watchdog kurulumu islemlerini otomatik yapar.
.PARAMETER AppPath
    Kiosk olarak calistirilacak uygulamanin tam yolu (zorunlu)
    Ornek: C:\Kiosk\uygulama.exe
.PARAMETER AppArgs
    Uygulamaya verilecek argümanlar (isteğe bağlı)
    Ornek: --fullscreen
.PARAMETER KioskUser
    Olusturulacak kiosk kullanicisinin adi (varsayilan: Kiosk)
.PARAMETER KioskPassword
    Kiosk kullanicisinin sifresi (bos birakilirsa otomatik giris aktif olur)
.PARAMETER AutoLogon
    Bilgisayar acildiginda Kiosk kullanicisiyla otomatik giris yapilsin mi?
.PARAMETER SkipGroupPolicy
    Grup ilkesi adimini atla (gpedit.msc olmayan surumlerde kullan)
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

    [switch]$SkipGroupPolicy
)

# ─────────────────────────────────────────────
# YARDIMCI FONKSIYONLAR
# ─────────────────────────────────────────────

function Write-Step {
    param([string]$Text)
    Write-Host "`n[$([char]0x25B6)] $Text" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [!!] $Text" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [XX] $Text" -ForegroundColor Red
}

function Ensure-RegistryPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-OK "Registry anahtari olusturuldu: $Path"
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

# ─────────────────────────────────────────────
# ON KONTROLLER
# ─────────────────────────────────────────────

Write-Host ""
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host "   WINDOWS KIOSK MODU KURULUM SCRIPTI" -ForegroundColor Magenta
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host ""

# Yönetici kontrolü
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "Bu script yonetici haklariyla calistirilmalidir!"
    Write-Host "  Powershell'i sag tiklayip 'Yonetici olarak calistir' secin." -ForegroundColor Yellow
    exit 1
}

# Uygulama yolu kontrolü
if (-not (Test-Path $AppPath)) {
    Write-Warn "Uygulama dosyasi simdi mevcut degil: $AppPath"
    Write-Warn "Script devam edecek, ancak uygulamayi belirtilen konuma kopyalayin."
}

$AppDir = Split-Path $AppPath -Parent
$AppExe = Split-Path $AppPath -Leaf

# Kiosk klasörü oluştur
$KioskDir = "C:\Kiosk"
if (-not (Test-Path $KioskDir)) {
    New-Item -Path $KioskDir -ItemType Directory -Force | Out-Null
    Write-OK "Kiosk klasoru olusturuldu: $KioskDir"
}

# ─────────────────────────────────────────────
# ADIM 1: KIOSK KULLANICISI OLUSTUR
# ─────────────────────────────────────────────

Write-Step "ADIM 1: Kiosk kullanicisi olusturuluyor..."

$existingUser = Get-LocalUser -Name $KioskUser -ErrorAction SilentlyContinue
if ($existingUser) {
    Write-Warn "Kullanici zaten mevcut: $KioskUser (atlanıyor)"
} else {
    try {
        if ($KioskPassword -eq "") {
            # Şifresiz kullanıcı
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
        # Standart kullanıcı (Users grubuna ekle, Administrators'a ekleme)
        Add-LocalGroupMember -Group "Users" -Member $KioskUser -ErrorAction SilentlyContinue
        Write-OK "Kullanici olusturuldu: $KioskUser (Standart)"
    } catch {
        Write-Fail "Kullanici olusturulamadi: $_"
    }
}

# ─────────────────────────────────────────────
# ADIM 2: WATCHDOG SCRIPT'I OLUSTUR
# ─────────────────────────────────────────────

Write-Step "ADIM 2: Watchdog scripti olusturuluyor..."

$watchdogPath = "$KioskDir\watchdog.bat"
$watchdogContent = @"
@echo off
:loop
tasklist /FI "IMAGENAME eq $AppExe" 2>NUL | find /I /N "$AppExe">NUL
if "%ERRORLEVEL%"=="1" (
    echo Uygulama baslatiliyor: %TIME%
    start "" "$AppPath" $AppArgs
)
timeout /t 5 >nul
goto loop
"@

Set-Content -Path $watchdogPath -Value $watchdogContent -Encoding ASCII
Write-OK "Watchdog olusturuldu: $watchdogPath"

# ─────────────────────────────────────────────
# ADIM 3: GOREV ZAMANLAYICI GOREVLERI
# ─────────────────────────────────────────────

Write-Step "ADIM 3: Gorev Zamanlayici gorevleri kuruluyor..."

# Görev 1: Ana uygulama
try {
    $appAction  = New-ScheduledTaskAction -Execute $AppPath -Argument $AppArgs -WorkingDirectory $AppDir
    $appTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser
    $appSettings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Seconds 10) `
        -ExecutionTimeLimit ([System.TimeSpan]::Zero)
    $appPrincipal = New-ScheduledTaskPrincipal -UserId $KioskUser -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask `
        -TaskName "KioskApp" `
        -Action $appAction `
        -Trigger $appTrigger `
        -Settings $appSettings `
        -Principal $appPrincipal `
        -Force | Out-Null

    Write-OK "Gorev olusturuldu: KioskApp"
} catch {
    Write-Fail "KioskApp gorevi olusturulamadi: $_"
}

# Görev 2: Watchdog
try {
    $wdAction  = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$watchdogPath`""
    $wdTrigger = New-ScheduledTaskTrigger -AtLogOn -User $KioskUser
    $wdSettings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([System.TimeSpan]::Zero)
    $wdPrincipal = New-ScheduledTaskPrincipal -UserId $KioskUser -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask `
        -TaskName "KioskWatchdog" `
        -Action $wdAction `
        -Trigger $wdTrigger `
        -Settings $wdSettings `
        -Principal $wdPrincipal `
        -Force | Out-Null

    Write-OK "Gorev olusturuldu: KioskWatchdog"
} catch {
    Write-Fail "KioskWatchdog gorevi olusturulamadi: $_"
}

# ─────────────────────────────────────────────
# ADIM 4: KAYIT DEFTERI AYARLARI (SISTEM GENELI)
# ─────────────────────────────────────────────

Write-Step "ADIM 4: Sistem geneli registry ayarlari yapiliyor..."

# Kenar kaydırma hareketlerini kapat (HKLM - tüm kullanıcılar)
Set-RegValue `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI" `
    -Name "AllowEdgeSwipe" `
    -Value 0

Write-OK "Kenar kaydir hareketi devre disi birakildi"

# ─────────────────────────────────────────────
# ADIM 5: KIOSK KULLANICISI REGISTRY AYARLARI
# ─────────────────────────────────────────────

Write-Step "ADIM 5: Kiosk kullanicisi registry ayarlari yapiliyor..."

# Kiosk kullanıcısının SID'ini bul
try {
    $kioskSID = (Get-LocalUser -Name $KioskUser).SID.Value
    Write-OK "Kiosk kullanici SID: $kioskSID"

    # Kiosk kullanıcısının hive'ını yükle (oturum açık değilse)
    $kioskProfilePath = "C:\Users\$KioskUser"
    $hivePath = "$kioskProfilePath\NTUSER.DAT"

    # Kullanıcı profili oluşturmak için bir kez oturum açılması gerekir
    # Biz HKU'ya yükleme yaparak ayarları uygulayabiliriz
    $hiveLoaded = $false

    if (Test-Path $hivePath) {
        $regLoadResult = reg load "HKU\KioskTemp" $hivePath 2>&1
        if ($LASTEXITCODE -eq 0) {
            $hiveLoaded = $true
            Write-OK "Kiosk hive yuklendi"
        } else {
            Write-Warn "Hive yuklenemedi (kullanici hic oturum acmamis olabilir): $regLoadResult"
            Write-Warn "Kiosk kullanicisi ilk kez oturum actiktan sonra bu ayarlar uygulanacak"
        }
    } else {
        Write-Warn "Kiosk profili henuz olusturulmamis. Ilk oturumdan sonra manuel uygulama gerekebilir."
        Write-Warn "Profil yolu: $kioskProfilePath"
    }

    if ($hiveLoaded) {
        # Bildirim merkezini kapat
        Set-RegValue `
            -Path "HKU:\KioskTemp\Software\Policies\Microsoft\Windows\Explorer" `
            -Name "DisableNotificationCenter" `
            -Value 1

        # Görev çubuğunu otomatik gizle
        $stuckRectsPath = "HKU:\KioskTemp\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
        if (Test-Path $stuckRectsPath) {
            $stuckRects = (Get-ItemProperty -Path $stuckRectsPath).Settings
            if ($stuckRects -and $stuckRects.Length -ge 9) {
                # Byte 8 = 0x03 (görünür) veya 0x01 (otomatik gizle)
                $stuckRects[8] = 0x01
                Set-ItemProperty -Path $stuckRectsPath -Name "Settings" -Value $stuckRects
                Write-OK "Gorev cubugu otomatik gizle aktif edildi"
            }
        }

        # Hive'ı kaydet ve kaldır
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        reg unload "HKU\KioskTemp" | Out-Null
        Write-OK "Kiosk hive kaydedildi ve kaldirildi"
    }
} catch {
    Write-Warn "Kiosk registry ayarlari uygulanamadi: $_"
    Write-Warn "Kiosk kullanicisiyla ilk oturumdan sonra manuel uygulama gerekebilir."
}

# ─────────────────────────────────────────────
# ADIM 6: GRUP ILKESI KISITLAMALARI
# ─────────────────────────────────────────────

if (-not $SkipGroupPolicy) {
    Write-Step "ADIM 6: Grup ilkesi kisitlamalari uygulanıyor..."

    # gpedit.msc var mı kontrol et
    $gpeditExists = Test-Path "$env:SystemRoot\System32\gpedit.msc"

    if ($gpeditExists) {
        # Registry tabanlı grup ilkesi (LGPO alternatif yöntemi)
        # Bu değerler gpedit.msc ile aynı sonucu verir

        # Görev Yöneticisini kaldır (Kiosk kullanıcısı için HKCU bazlı - hive üzerinden)
        # HKLM policy olarak da uygulanabilir
        Set-RegValue `
            -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -Name "DisableTaskMgr" `
            -Value 1

        Write-OK "Gorev Yoneticisi devre disi birakildi (tum kullanicilar)"
        Write-Warn "Not: Bu ayar yonetici hesabini da etkiler. Yonetici olarak girissonrasi kaldirabilirsiniz."

        # Denetim Masası / Ayarlar erişimini engelle
        Set-RegValue `
            -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
            -Name "NoControlPanel" `
            -Value 1

        Write-OK "Denetim Masasi/Ayarlar erisimi engellendi"

        # Çalıştır komutunu gizle
        Set-RegValue `
            -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
            -Name "NoRun" `
            -Value 1

        Write-OK "'Calistir' komutu gizlendi"

        # Komut istemi devre dışı
        Set-RegValue `
            -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
            -Name "DisableCMD" `
            -Value 1

        Write-OK "Komut istemi devre disi birakildi"

        # PowerShell erişimi kısıtla
        Set-RegValue `
            -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
            -Name "DisallowRun" `
            -Value 1

        Ensure-RegistryPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun"
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun" `
            -Name "1" -Value "powershell.exe" -Type String -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun" `
            -Name "2" -Value "powershell_ise.exe" -Type String -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun" `
            -Name "3" -Value "cmd.exe" -Type String -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun" `
            -Name "4" -Value "regedit.exe" -Type String -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun" `
            -Name "5" -Value "mmc.exe" -Type String -Force

        Write-OK "Tehlikeli uygulamalar (cmd, regedit, powershell vb.) engellendi"

    } else {
        Write-Warn "gpedit.msc bulunamadi (Home surumu?). Grup ilkesi adimi atlaniyor."
        Write-Warn "-SkipGroupPolicy parametresiyle bu uyariyi susturabilirsiniz."
    }
} else {
    Write-Warn "ADIM 6: Grup ilkesi adimi atlanıyor (-SkipGroupPolicy)"
}

# ─────────────────────────────────────────────
# ADIM 7: OTOMATIK OTURUM ACMA
# ─────────────────────────────────────────────

if ($AutoLogon) {
    Write-Step "ADIM 7: Otomatik oturum acma yapılandırılıyor..."

    $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

    Set-RegValue -Path $winlogonPath -Name "AutoAdminLogon"   -Value "1"         -Type String
    Set-RegValue -Path $winlogonPath -Name "DefaultUserName"  -Value $KioskUser  -Type String
    Set-RegValue -Path $winlogonPath -Name "DefaultPassword"  -Value $KioskPassword -Type String
    Set-RegValue -Path $winlogonPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String

    Write-OK "Otomatik oturum acma aktif edildi: $KioskUser"

    if ($KioskPassword -eq "") {
        Write-Warn "Sifre bos! Güvenlik riskini degerlendirin."
    }
} else {
    Write-Host "`n  [--] Otomatik oturum acma yapılandırılmadı (-AutoLogon parametresi verilmedi)" -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────
# ADIM 8: GERI ALMA SCRIPTI OLUSTUR
# ─────────────────────────────────────────────

Write-Step "ADIM 8: Geri alma (Undo) scripti olusturuluyor..."

$undoScriptPath = "$KioskDir\Undo-KioskMode.ps1"
$undoContent = @"
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Kiosk modunu geri alir (Undo)
.DESCRIPTION
    Setup-KioskMode.ps1 tarafindan yapilan tum degisiklikleri geri alir.
#>

Write-Host "Kiosk modu geri aliniyor..." -ForegroundColor Yellow

# Gorev Zamanlayici gorevlerini sil
Unregister-ScheduledTask -TaskName "KioskApp"      -Confirm:`$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "KioskWatchdog" -Confirm:`$false -ErrorAction SilentlyContinue
Write-Host "[OK] Gorev Zamanlayici gorevleri silindi" -ForegroundColor Green

# Otomatik oturum acmayi kapat
`$winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path `$winlogonPath -Name "AutoAdminLogon" -Value "0" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path `$winlogonPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
Write-Host "[OK] Otomatik oturum acma devre disi birakildi" -ForegroundColor Green

# Kenar kaydırma geri aç
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EdgeUI" -Name "AllowEdgeSwipe" -ErrorAction SilentlyContinue
Write-Host "[OK] Kenar kaydir hareketi geri acildi" -ForegroundColor Green

# Grup ilkesi kisitlamalarını kaldır
`$explorerPolicies = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
Remove-ItemProperty -Path `$explorerPolicies -Name "NoControlPanel" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path `$explorerPolicies -Name "NoRun"           -ErrorAction SilentlyContinue
Remove-ItemProperty -Path `$explorerPolicies -Name "DisallowRun"     -ErrorAction SilentlyContinue
Remove-Item -Path "`$explorerPolicies\DisallowRun" -Recurse -ErrorAction SilentlyContinue

`$systemPolicies = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Remove-ItemProperty -Path `$systemPolicies -Name "DisableTaskMgr" -ErrorAction SilentlyContinue

`$cmdPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
Remove-ItemProperty -Path `$cmdPolicy -Name "DisableCMD" -ErrorAction SilentlyContinue

Write-Host "[OK] Grup ilkesi kisitlamalari kaldirildi" -ForegroundColor Green

# Kiosk kullanıcısını sil (onay iste)
`$confirm = Read-Host "Kiosk kullanicisini ($KioskUser) silmek istiyor musunuz? (E/H)"
if (`$confirm -eq "E" -or `$confirm -eq "e") {
    Remove-LocalUser -Name "$KioskUser" -ErrorAction SilentlyContinue
    Write-Host "[OK] Kiosk kullanicisi silindi" -ForegroundColor Green
}

Write-Host "`nGeri alma tamamlandi. Lutfen bilgisayari yeniden baslatin." -ForegroundColor Cyan
"@

Set-Content -Path $undoScriptPath -Value $undoContent -Encoding UTF8
Write-OK "Geri alma scripti olusturuldu: $undoScriptPath"

# ─────────────────────────────────────────────
# OZET
# ─────────────────────────────────────────────

Write-Host ""
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host "   KURULUM TAMAMLANDI" -ForegroundColor Magenta
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Kiosk Kullanicisi : $KioskUser" -ForegroundColor White
Write-Host "  Uygulama          : $AppPath" -ForegroundColor White
Write-Host "  Watchdog          : $watchdogPath" -ForegroundColor White
Write-Host "  Geri alma scripti : $undoScriptPath" -ForegroundColor White
Write-Host ""
Write-Host "  YAPILAN ISLEMLER:" -ForegroundColor Cyan
Write-Host "  [+] Kiosk kullanicisi olusturuldu/kontrol edildi" -ForegroundColor Green
Write-Host "  [+] Gorev Zamanlayici gorevleri kuruldu (KioskApp + KioskWatchdog)" -ForegroundColor Green
Write-Host "  [+] Watchdog batch scripti olusturuldu" -ForegroundColor Green
Write-Host "  [+] Kenar kaydir hareketi devre disi birakildi" -ForegroundColor Green
if (-not $SkipGroupPolicy) {
    Write-Host "  [+] Gorev Yoneticisi, CMD, Regedit, Ayarlar engellendi" -ForegroundColor Green
}
if ($AutoLogon) {
    Write-Host "  [+] Otomatik oturum acma aktif edildi" -ForegroundColor Green
}
Write-Host ""
Write-Host "  SONRAKI ADIMLAR:" -ForegroundColor Yellow
Write-Host "  1. Uygulamayi su konuma kopyalayin: $AppPath" -ForegroundColor Yellow
Write-Host "  2. Bilgisayari YENIDEN BASLATIN" -ForegroundColor Yellow
Write-Host "  3. Kiosk kullanicisi oturum actiktan sonra ayarlar tam etkin olur" -ForegroundColor Yellow
Write-Host "  4. Yonetici erisimi: Ctrl+Alt+Del > Kullanici Degistir" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Geri almak icin: $undoScriptPath" -ForegroundColor DarkGray
Write-Host ""

$restart = Read-Host "Bilgisayari simdi yeniden baslatmak istiyor musunuz? (E/H)"
if ($restart -eq "E" -or $restart -eq "e") {
    Write-Host "Yeniden baslatiliyor..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    Restart-Computer -Force
}
