@echo off
:: build.bat — Compiles DolbyAutoSwitch EXEs using the .NET Framework CSC
:: compiler that ships with every Windows 10/11 machine.
:: Run this ONCE on your Windows machine. No Visual Studio needed.
:: Output: Install-DolbyAutoSwitch.exe  +  Uninstall-DolbyAutoSwitch.exe

setlocal EnableDelayedExpansion
cd /d "%~dp0"

echo.
echo  DolbyAutoSwitch ^| Build
echo  ────────────────────────────────
echo.

:: ── Find csc.exe (C# compiler from .NET Framework) ──────────────────────────
set "CSC="
for %%v in (4.0 3.5 2.0) do (
    if not defined CSC (
        for /f "delims=" %%p in ('dir /b /s "%windir%\Microsoft.NET\Framework64\v%%v*\csc.exe" 2^>nul') do (
            set "CSC=%%p"
        )
    )
)
:: Fallback to 32-bit Framework
if not defined CSC (
    for %%v in (4.0 3.5) do (
        if not defined CSC (
            for /f "delims=" %%p in ('dir /b /s "%windir%\Microsoft.NET\Framework\v%%v*\csc.exe" 2^>nul') do (
                set "CSC=%%p"
            )
        )
    )
)

if not defined CSC (
    echo  [ERROR] Could not find csc.exe — .NET Framework 4.0+ required.
    echo  It should be at: C:\Windows\Microsoft.NET\Framework64\v4.x.x\csc.exe
    pause
    exit /b 1
)
echo  [OK] Compiler: %CSC%
echo.

:: ── Build Installer EXE ──────────────────────────────────────────────────────
echo  Building Install-DolbyAutoSwitch.exe ...
"%CSC%" ^
    /target:winexe ^
    /platform:x64 ^
    /optimize+ ^
    /out:"..\Install-DolbyAutoSwitch.exe" ^
    /win32icon:"..\dolby_auto_switch.ico" ^
    /win32manifest:"app.manifest" ^
    /reference:System.Windows.Forms.dll ^
    /reference:System.Drawing.dll ^
    "Installer.cs"

if errorlevel 1 (
    echo  [ERROR] Installer build failed. See output above.
    pause
    exit /b 1
)
echo  [OK] Install-DolbyAutoSwitch.exe
echo.

:: ── Build Uninstaller EXE ────────────────────────────────────────────────────
echo  Building Uninstall-DolbyAutoSwitch.exe ...
"%CSC%" ^
    /target:winexe ^
    /platform:x64 ^
    /optimize+ ^
    /out:"..\Uninstall-DolbyAutoSwitch.exe" ^
    /win32icon:"..\dolby_auto_switch.ico" ^
    /win32manifest:"app.manifest" ^
    /reference:System.Windows.Forms.dll ^
    /reference:System.Drawing.dll ^
    "Uninstaller.cs"

if errorlevel 1 (
    echo  [ERROR] Uninstaller build failed. See output above.
    pause
    exit /b 1
)
echo  [OK] Uninstall-DolbyAutoSwitch.exe
echo.
echo  ────────────────────────────────
echo  Build complete!
echo.
echo  Files ready in the parent folder:
echo    Install-DolbyAutoSwitch.exe
echo    Uninstall-DolbyAutoSwitch.exe
echo.
echo  Next step: double-click Install-DolbyAutoSwitch.exe
echo.
pause
