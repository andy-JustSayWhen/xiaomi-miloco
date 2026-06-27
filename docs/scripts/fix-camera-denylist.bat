@echo off
chcp 65001 >nul
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%fix-camera-denylist.ps1"

if not exist "%PS1%" (
  echo [ERROR] Missing PowerShell script: "%PS1%"
  echo.
  pause
  exit /b 1
)

"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
  echo Finished. Review the messages above before closing this window.
) else (
  echo Failed. Review the messages above, then run this file again if needed.
)
echo.

if "%MILOCO_FIX_NO_PAUSE%"=="1" exit /b %EXIT_CODE%
pause
exit /b %EXIT_CODE%
