@echo off
setlocal

REM ---------------------------------------------------------------------
REM  AlistClientN - build release arm64-v8a APK
REM  ASCII-only on purpose: a UTF-8 .bat containing CJK text is parsed as
REM  GBK by cmd.exe, which breaks quoting and kills the script instantly.
REM  All output is tee'd to build_log.txt next to this file.
REM ---------------------------------------------------------------------

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "LOG=%PROJECT_DIR%\build_log.txt"

call :main > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
type "%LOG%"
echo.
echo Exit code: %RC%
echo Full log: %LOG%
pause
exit /b %RC%

:main

set "FLUTTER_DIR=D:\flutter"
set "FLUTTER_BAT=%FLUTTER_DIR%\bin\flutter.bat"
set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"
set "GIT_DIR=C:\Users\Administrator.USER-20260705OC\.workbuddy\binaries\PortableGit\versions\1.2.0\cmd"
set "OUT_DIR=F:\apk"

echo ============================================================
echo  Project : %PROJECT_DIR%
echo  Flutter : %FLUTTER_BAT%
echo  JAVA    : %JAVA_HOME%
echo  Output  : %OUT_DIR%
echo ============================================================

if not exist "%FLUTTER_BAT%" (
    echo [FAIL] flutter.bat not found: %FLUTTER_BAT%
    echo        fix FLUTTER_DIR at the top of this script.
    exit /b 1
)
if not exist "%JAVA_HOME%\bin\java.exe" (
    echo [WARN] JAVA_HOME invalid, retrying C:\Program Files\Java\jdk-17
    set "JAVA_HOME=C:\Program Files\Java\jdk-17"
    if not exist "%JAVA_HOME%\bin\java.exe" (
        echo [FAIL] no JDK found. Fix JAVA_HOME in this script.
        exit /b 1
    )
)
if exist "%GIT_DIR%\git.exe" (
    set "PATH=%GIT_DIR%;%PATH%"
) else (
    echo [WARN] git.exe not found at %GIT_DIR%
    echo        the Flutter tool needs git on Windows.
)

cd /d "%PROJECT_DIR%"
if errorlevel 1 (
    echo [FAIL] cannot cd into %PROJECT_DIR%
    exit /b 1
)

findstr /C:"storeFile=" android\local.properties >nul
if errorlevel 1 (
    echo [WARN] no storeFile in android\local.properties - release falls back to the debug key.
) else (
    echo [ OK ] signing config found in android\local.properties
)

if exist build\app\outputs\flutter-apk rmdir /s /q build\app\outputs\flutter-apk

echo.
echo [ .. ] flutter build apk --release --target-platform android-arm64
call "%FLUTTER_BAT%" build apk --release --target-platform android-arm64
if errorlevel 1 (
    echo.
    echo [FAIL] build failed - see the Gradle error above.
    exit /b 1
)

set "SRC=build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
if not exist "%SRC%" set "SRC=build\app\outputs\flutter-apk\app-release.apk"
if not exist "%SRC%" (
    echo [FAIL] no APK produced. Listing build\app\outputs:
    if exist build\app\outputs dir /s /b build\app\outputs
    exit /b 1
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
set "DST=%OUT_DIR%\AlistClientN-1.4.4+111-arm64-v8a-release.apk"
copy /y "%SRC%" "%DST%"
if errorlevel 1 (
    echo [FAIL] copy failed: %SRC% to %DST%
    exit /b 1
)

echo.
echo ============================================================
echo  DONE: %DST%
echo ============================================================
dir "%DST%"
exit /b 0
