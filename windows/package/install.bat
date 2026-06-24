@echo off
chcp 65001 >nul
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "INSTALL_BAT=%~f0"
set "INSTALL_DIR=%~dp0"

if not exist "%INSTALL_DIR%install.ps1" goto package_missing
if not exist "%INSTALL_DIR%manifest.json" goto package_missing
if not exist "%INSTALL_DIR%payload\install.sh" goto package_missing
if not exist "%INSTALL_DIR%scripts\windows\win-miloco-workflow.ps1" goto package_missing

net session >nul 2>&1
if %errorLevel% == 0 goto run

echo [INFO] Requesting administrator permission...
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:INSTALL_BAT -WorkingDirectory $env:INSTALL_DIR -Verb RunAs; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
if %errorLevel% neq 0 goto elevate_failed
exit /b

:run
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -PauseOnExit
exit /b %errorlevel%

:package_missing
echo.
echo [ERROR] This does not look like a fully extracted easy-miloco package.
echo.
echo Please do NOT run install.bat directly inside the zip window.
echo Extract the whole zip to a normal folder first, then double-click install.bat there.
echo.
pause
exit /b 1

:elevate_failed
echo.
echo [ERROR] Failed to request administrator permission.
echo Please right-click install.bat and choose Run as administrator.
echo.
pause
exit /b 1
