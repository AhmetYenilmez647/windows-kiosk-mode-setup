@echo off
setlocal EnableDelayedExpansion
title Kiosk Mode Setup - Kurulum Yardimcisi

rem ====================================================
rem YONETICI KONTROLU VE KENDINI YUKSELTME
rem ====================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  ====================================================
    echo  Yonetime Erisimi Gerekiyor... Lutfen Onaylayin
    echo  ====================================================
    echo.
    powershell.exe -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b 0
)

rem ====================================================
rem BASLIK
rem ====================================================
echo.
echo  ====================================================
echo       KIOSK MODE DETAYLI KURULUM YARDIMCISI
echo  ====================================================
echo.
echo  Bu yardimci, seciceginiz Setup-KioskMode betigini
echo  sizin icin dogru parametrelerle baslatir.
echo.

rem ====================================================
rem [0/4] SURUM SECIMI
rem ====================================================
echo  ----------------------------------------------------
echo  [0/4] SCRIPT SURUMU SECIN
echo  ----------------------------------------------------
echo.
echo  [1] V1 - Setup-KioskMode.ps1 (Eski, HKLM bazli, tum kullanicilari etkiler)
echo  [2] V2 - Setup-KioskMode-V2.ps1 (Gelistirilmis kovan baglama, HKCU bazli)
echo  [3] V3 - Setup-KioskMode-V3.ps1 (En yeni, Custom Shell + explorer.exe kilidi)
echo.
set "VerChoice="
set /p "VerChoice=  Seciminiz (1-3) [bos=3]: "
if "!VerChoice!"=="" set "VerChoice=3"

set "SCRIPT_FILE="
set "VER_NAME="
if "!VerChoice!"=="1" (
    set "SCRIPT_FILE=Setup-KioskMode.ps1"
    set "VER_NAME=V1 (Setup-KioskMode.ps1)"
) else if "!VerChoice!"=="2" (
    set "SCRIPT_FILE=Setup-KioskMode-V2.ps1"
    set "VER_NAME=V2 (Setup-KioskMode-V2.ps1)"
) else if "!VerChoice!"=="3" (
    set "SCRIPT_FILE=Setup-KioskMode-V3.ps1"
    set "VER_NAME=V3 (Setup-KioskMode-V3.ps1)"
) else (
    echo.
    echo  [HATA] Gecersiz secim: !VerChoice!
    echo         Lutfen 1, 2 veya 3 girin.
    pause
    exit /b 1
)

rem Script kontrolu
if not exist "%~dp0!SCRIPT_FILE!" (
    echo.
    echo  [HATA] !SCRIPT_FILE! bulunamadi!
    echo         Bu dosya, Kiosk-Launcher.bat ile ayni klasorde olmalidir.
    echo         Aranan konum: %~dp0!SCRIPT_FILE!
    echo.
    pause
    exit /b 1
)

echo.
echo  [OK] Secilen Surum: !VER_NAME!
echo.

rem ====================================================
rem [1/4] UYGULAMA BILGILERI
rem ====================================================
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

echo !AppPath!| findstr /C:":" >nul 2>&1
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

rem ====================================================
rem [2/4] KIOSK KULLANICI ADI
rem ====================================================
echo  ----------------------------------------------------
echo  [2/4] KIOSK KULLANICI ADI
echo  ----------------------------------------------------
echo.
echo  Birden fazla kiosk kurulumu yapacaksaniz farkli isimler
echo  kullanabilirsiniz (ornek: Kiosk1, Kiosk2, POS, Muhasebe).
echo.
set /p "KioskUser=  Kullanici adi [bos=Kiosk]: "
if "!KioskUser!"=="" set "KioskUser=Kiosk"

echo !KioskUser!| findstr /C:" " >nul 2>&1
if !errorLevel! equ 0 (
    echo.
    echo  [HATA] Kullanici adi bosluk iceremez!
    echo         Girilen: !KioskUser!
    pause
    exit /b 1
)
echo.

rem ====================================================
rem [3/4] SENARYO SECIMI
rem ====================================================
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

rem Sifre sor (sadece gerekiyorsa)
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

rem ====================================================
rem [4/4] OZET VE ONAY
rem ====================================================
echo.
echo  ====================================================
echo  [4/4] KURULUM OZETI
echo  ====================================================
echo.
echo   Script    : !SCRIPT_FILE! (!VER_NAME!)
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

rem ====================================================
rem POWERSHELL KOMUTU OLUSTUR VE CALISTIR
rem ====================================================
set "PS_CMD=& \"%~dp0!SCRIPT_FILE!\" -AppPath \"!AppPath!\" -KioskUser \"!KioskUser!\""

if not "!AppArgs!"=="" (
    set "PS_CMD=!PS_CMD! -AppArgs \"!AppArgs!\""
)

if "!USE_PASSWORD!"=="1" (
    set "PS_CMD=!PS_CMD! -KioskPassword \"!KioskPwd!\""
)

if "!USE_AUTOLOGON!"=="1" (
    set "PS_CMD=!PS_CMD! -AutoLogon"
)

rem V1 scripti -SkipGroupPolicy kullanir, V2/V3 -SkipRestrictions kullanir
if "!USE_SKIP!"=="1" (
    if "!VerChoice!"=="1" (
        set "PS_CMD=!PS_CMD! -SkipGroupPolicy"
    ) else (
        set "PS_CMD=!PS_CMD! -SkipRestrictions"
    )
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "!PS_CMD!"

echo.
echo  ====================================================
echo  Script tamamlandi. Detaylar icin yukariyi inceleyin.
echo  ====================================================
echo.
pause
