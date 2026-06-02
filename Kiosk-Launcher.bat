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
echo  ======================================================================
echo                 KIOSK MODE DETAYLI KURULUM YARDIMCISI
echo  ======================================================================
echo.
echo  Bu yardimci, sectiginiz Setup-KioskMode betigini (.ps1)
echo  sizin icin dogru parametrelerle otomatik olarak baslatir.
echo.

rem ====================================================
rem [0/4] SURUM SECIMI
rem ====================================================
echo  ----------------------------------------------------------------------
echo  [0/4] SCRIPT SURUMU SECIN
echo  ----------------------------------------------------------------------
echo.
echo  [1] V1 - Setup-KioskMode.ps1 (Eski / Onerilmez)
echo      * KISITLAMALARI SISTEM GENELI (HKLM) UYGULAR.
echo      * Admin hesabinizi da kilitler! Geri almak zor olabilir.
echo      * Sadece Windows Home olmayan (Pro/Ent), gpedit.msc iceren cok
echo        eski sistemlerde son care olarak tercih edilmelidir.
echo.
echo  [2] V2 - Setup-KioskMode-V2.ps1 (Kullaniciya Ozel / Guvenli)
echo      * Kisitlamalari sadece Kiosk kullanicisina (HKCU) uygular.
echo      * Admin/Yonetici hesabi kısıtlamalardan ETKILENMEZ.
echo      * Windows Masaustu (explorer.exe) yuklenir ancak CMD, Regedit,
echo        Gorev Yonetici gibi kritik sistem araclari engellenir.
echo.
echo  [3] V3 - Setup-KioskMode-V3.ps1 (En Yeni / EN GUVENLI VE ONERILEN)
echo      * Kisitlamalari sadece Kiosk kullanicisina (HKCU) uygular.
echo      * Masaustu (explorer.exe) tamamen devre disi birakilir.
echo      * Bilgisayar acildiginda kullanici masaustunu veya baslat menusunu
echo        goremez, doğrudan siyah bir ekran uzerinde uygulamaniz calisir.
echo.
echo  ----------------------------------------------------------------------
echo  CRITICAL: Sectiginiz script dosyasinin (.ps1) bu baslaticiyla (.bat)
echo            ayni klasorde bulundugundan emin olun!
echo  ----------------------------------------------------------------------
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
    echo         Dosyanin indirildiginden ve bu baslaticiyla ayni klasorde
    echo         oldugundan emin olun.
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
echo  ----------------------------------------------------------------------
echo  [1/4] UYGULAMA BILGILERI
echo  ----------------------------------------------------------------------
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
echo  Uygulama baslatilirken gonderilecek argumanlari yazabilirsiniz.
echo  ----------------------------------------------------------------------
echo  Yaygin kullanilan parametre ornekleri:
echo   * Edge / Google Chrome web kiosk modu icin:
echo     --kiosk --fullscreen --disable-pinch-gesture --no-first-run
echo   * Genel uygulamalarda tam ekran modunu zorlamak icin:
echo     -fullscreen  veya  --fullscreen
echo   * Klasik Internet Explorer tarayicisi icin:
echo     -k
echo  ----------------------------------------------------------------------
set "AppArgs="
set /p "AppArgs=  Argumanlari girin [bos birakilabilir]: "
echo.

rem ====================================================
rem [2/4] KIOSK KULLANICI ADI
rem ====================================================
echo  ----------------------------------------------------------------------
echo  [2/4] KIOSK KULLANICI ADI
echo  ----------------------------------------------------------------------
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
echo  ----------------------------------------------------------------------
echo  [3/4] KURULUM SENARYOSU SECIN
echo  ----------------------------------------------------------------------
echo.
echo  [1] Sifresiz Otomatik Giris (Onerilen)
echo      Bilgisayar acilinca direkt kiosk kullanicisi oturum acar.
echo      Sifre sorulmaz, tam kisitlama uygulanir, sistem doğrudan kilitlenir.
echo.
echo  [2] Sifreli Otomatik Giris
echo      Bilgisayar acilinca direkt kiosk oturumu acilir ve uygulamaya girer.
echo      Fakat kiosk hesabi bir sifreyle korunur (sifre registry dosyasinda
echo      saklanir, guvenlik riskini degerlendirin).
echo.
echo  [3] Sifreli Manuel Giris
echo      Windows kilit ekraninda durur. Kiosk oturumunun acilmasi icin
echo      belirlediginiz sifrenin girilmesi gerekir. Yetkisiz fiziksel
echo      erisimleri engellemede etkilidir.
echo.
echo  [4] Sifresiz Manuel Giris
echo      Windows kilit ekraninda durur ancak sifre sormaz. Listeden kiosk
echo      kullanicisina tiklamak oturum acilmasi ve uygulamanin baslamasi icin
echo      yeterlidir.
echo.
echo  [5] Gelistirici / Test Modu
echo      Otomatik giris yapar ancak sistem/kullanici kisitlamalarini UYGULAMAZ.
echo      Gorev Yonetici, CMD, PowerShell acik kalir. Uygulamanin kiosk
echo      ortamindaki davranisini rahatca kontrol etmek icin idealdir.
echo.
echo  ----------------------------------------------------------------------
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
echo  [OK] Secilen Senaryo: !ScenarioName!

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
echo  ================================================================------
echo  [4/4] KURULUM OZETI
echo  ================================================================------
echo.
echo   Script Dosyasi: !SCRIPT_FILE!
echo   Surum Bilgisi : !VER_NAME!
echo   Uygulama Yolu : !AppPath!
if not "!AppArgs!"=="" echo   Argumanlar    : !AppArgs!
echo   Kullanici Adi : !KioskUser!
echo   Senaryo       : !ScenarioName!
echo.
echo  ================================================================------
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
echo  ================================================================------
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
echo  ================================================================------
echo  Script tamamlandi. Detaylar icin yukariyi inceleyin.
echo  ================================================================------
echo.
pause
