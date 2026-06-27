@echo off
setlocal
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%POWERSHELL%" goto have_powershell
where powershell.exe >nul 2>nul || goto powershell_missing
set "POWERSHELL=powershell.exe"
:have_powershell
set "SCRIPT=%~dp0miloco-console.ps1"

if not exist "%SCRIPT%" goto missing_script
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %errorlevel%

:missing_script
set "MILOCO_MSG_B64=5om+5LiN5YiwIG1pbG9jby1jb25zb2xlLnBzMeOAgg=="
call :say
set "MILOCO_MSG_B64=6K+36YeN5paw6L+Q6KGMIGluc3RhbGwuYmF077yM6K6p5a6J6KOF5Zmo6YeN5paw5Yib5bu65qGM6Z2i5o6n5Yi25Y+w44CC"
call :say
echo.
set "MILOCO_MSG_B64=5oyJ5Zue6L2m57un57ut44CC"
call :wait
exit /b 1

:powershell_missing
echo PowerShell is not available. Cannot continue.
echo.
pause
exit /b 1

:say
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "$OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); Write-Host ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:MILOCO_MSG_B64)))"
exit /b 0

:wait
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "$OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $null = Read-Host ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:MILOCO_MSG_B64)))"
exit /b 0
