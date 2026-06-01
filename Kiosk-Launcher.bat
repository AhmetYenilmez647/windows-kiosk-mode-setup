@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title Kiosk Mode V3 - Kurulum Yardimcisi

:: ─────────────────────────────────────────────
:: YONETICI KONTROLU
:: ─────────────────────────────────────────────
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  [HATA] Bu dosya Yonetici haklariyla calistirilmalidir!
    echo         Sag tiklayin ^> "Yonetici olarak calistir" secin.
    echo.
    pause
    exit /b 1
)

:: ─────────────────────────────────────────────
:: V3 SCRIPT KONTROLU
:: ─────────────────────────────────────────────
if not exist "%~dp0Setup-KioskMode-V3.ps1" (
    echo.
    echo  [HATA] Setup-KioskMode-V3.ps1 bulunamadi!
    echo         Bu dosya, Kiosk-Launcher.bat ile ayni klasorde olmalidir.
    echo         Aranan konum: %~dp0
    echo.
    pause
    exit /b 1
)

:: ─────────────────────────────────────────────
:: BASLIK
:: ─────────────────────────────────────────────
echo.
echo  ====================================================
echo       KIOSK MODE V3 - KURULUM YARDIMCISI
echo  ====================================================
echo.
echo  Bu yardimci, Setup-KioskMode-V3.ps1 scriptini
echo  sizin icin dogru parametrelerle baslatir.
echo.

:: ─────────────────────────────────────────────
:: [1/4] UYGULAMA BILGILERI
:: ─────────────────────────────────────────────
echo  ----------------------------------------------------
echo  [1/4] UYGULAMA BILGILERI
echo  ----------------------------------------------------
echo.
set /p "AppPath=  Uygulamanin TAM YOLUNU girin (ornek: C:\Kiosk\app.exe): "

if "!AppPath!"=="" (
    echo.
    echo  [HATA] Uygulama yolu bos birakilamaz!
    pause
    exit /b 1
)

echo !AppPath! | findstr /C:":" >nul 2>&1
if !errorLevel! neq 0 (
    echo.
    echo  [HATA] Tam yol girmelisiniz! Ornek: C:\Kiosk\app.exe
    echo         Girilen: !AppPath!
    pause
    exit /b 1
)

echo.
set /p "AppArgs=  Uygulama argumanlari (ornek: --fullscreen) [bos birakilabilir]: "
echo.

:: ─────────────────────────────────────────────
:: [2/4] KIOSK KULLANICI ADI
:: ─────────────────────────────────────────────
echo  ----------------------------------------------------
echo  [2/4] KIOSK KULLANICI ADI
echo  ----------------------------------------------------
echo.
echo  Birden fazla kiosk kurulumu yapacaksaniz farkli isimler
echo  kullanabilirsiniz (ornek: Kiosk1, Kiosk2, POS, Muhasebe).
echo.
set /p "KioskUser=  Kullanici adi [bos=Kiosk]: "
if "!KioskUser!"=="" set "KioskUser=Kiosk"

echo !KioskUser! | findstr /C:" " >nul 2>&1
if !errorLevel! equ 0 (
    echo.
    echo  [HATA] Kullanici adi bosluk iceremez!
    echo         Girilen: !KioskUser!
    pause
    exit /b 1
)
echo.

:: ─────────────────────────────────────────────
:: [3/4] SENARYO SECIMI
:: ─────────────────────────────────────────────
echo  ----------------------------------------------------
echo  [3/4] KURULUM SENARYOSU SECIN
echo  ----------------------------------------------------
echo.
echo  [1] Sifresiz Otomatik Giris (Onerilen)
echo      Bilgisayar acilinca direkt uygulamaya girer.
echo      Sifre sorulmaz, tam kisitlama uygulanir.
echo.
echo  [2] Sifreli Otomatik Giris
echo      Bilgisayar acilinca direkt uygulamaya girer.
echo      Kiosk hesabi sifre korunmalidir.
echo.
echo  [3] Sifreli Manuel Giris
echo      Windows kilit ekraninda durur, sifre girilmesi gerekir.
echo      Yetkisiz fiziksel erisimi engeller.
echo.
echo  [4] Sifresiz Manuel Giris
echo      Windows kilit ekraninda durur ama sifre gerekmez.
echo      Kiosk kullanicisini secmek yeterlidir.
echo.
echo  [5] Gelistirici / Test Modu
echo      Otomatik giris yapar ama kisitlama UYGULAMAZ.
echo      Gorev Yoneticisi, CMD, PowerShell acik kalir.
echo.
echo  ----------------------------------------------------
set "Scenario="
set /p "Scenario=  Seciminiz (1-5): "

set "USE_PASSWORD=0"
set "USE_AUTOLOGON=0"
set "USE_SKIP=0"
set "ScenarioName="

if "!Scenario!"=="1" (
    set "USE_AUTOLOGON=1"
    set "ScenarioName=Sifresiz Otomatik Giris"
) else if "!Scenario!"=="2" (
    set "USE_PASSWORD=1"
    set "USE_AUTOLOGON=1"
    set "ScenarioName=Sifreli Otomatik Giris"
) else if "!Scenario!"=="3" (
    set "USE_PASSWORD=1"
    set "ScenarioName=Sifreli Manuel Giris"
) else if "!Scenario!"=="4" (
    set "ScenarioName=Sifresiz Manuel Giris"
) else if "!Scenario!"=="5" (
    set "USE_AUTOLOGON=1"
    set "USE_SKIP=1"
    set "ScenarioName=Gelistirici / Test Modu"
) else (
    echo.
    echo  [HATA] Gecersiz secim: !Scenario!
    echo         Lutfen 1, 2, 3, 4 veya 5 girin.
    pause
    exit /b 1
)

echo.
echo  [OK] Secilen: !ScenarioName!

:: Sifre sor (sadece gerekiyorsa)
set "KioskPwd="
if "!USE_PASSWORD!"=="1" (
    echo.
    set /p "KioskPwd=  Kiosk kullanicisi icin sifre belirleyin: "
    if "!KioskPwd!"=="" (
        echo  [HATA] Bu senaryo icin sifre zorunludur!
        pause
        exit /b 1
    )
)

:: ─────────────────────────────────────────────
:: [4/4] OZET VE ONAY
:: ─────────────────────────────────────────────
echo.
echo  ====================================================
echo  [4/4] KURULUM OZETI
echo  ====================================================
echo.
echo   Script    : Setup-KioskMode-V3.ps1
echo   Uygulama  : !AppPath!
if not "!AppArgs!"=="" echo   Argumanlar: !AppArgs!
echo   Kullanici : !KioskUser!
echo   Senaryo   : !ScenarioName!
echo.
echo  ====================================================
echo.
set /p "Confirm=  Kurulumu baslatmak istiyor musunuz? (E/H): "

if /i not "!Confirm!"=="E" (
    echo.
    echo  Kurulum iptal edildi.
    pause
    exit /b 0
)

echo.
echo  Kurulum baslatiliyor...
echo  ====================================================
echo.

:: ─────────────────────────────────────────────
:: POWERSHELL KOMUTU OLUSTUR VE CALISTIR
:: ─────────────────────────────────────────────
set "PS_CMD=& \"%~dp0Setup-KioskMode-V3.ps1\" -AppPath \"!AppPath!\" -KioskUser \"!KioskUser!\""

if not "!AppArgs!"=="" (
    set "PS_CMD=!PS_CMD! -AppArgs \"!AppArgs!\""
)

if "!USE_PASSWORD!"=="1" (
    set "PS_CMD=!PS_CMD! -KioskPassword \"!KioskPwd!\""
)

if "!USE_AUTOLOGON!"=="1" (
    set "PS_CMD=!PS_CMD! -AutoLogon"
)

if "!USE_SKIP!"=="1" (
    set "PS_CMD=!PS_CMD! -SkipRestrictions"
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "!PS_CMD!"

echo.
echo  ====================================================
echo  Script tamamlandi. Detaylar icin yukariyi inceleyin.
echo  ====================================================
echo.
pause
