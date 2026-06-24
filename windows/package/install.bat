@echo off
chcp 65001 >nul
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%POWERSHELL%" goto have_powershell
where powershell.exe >nul 2>nul || goto powershell_missing
set "POWERSHELL=powershell.exe"
:have_powershell
set "INSTALL_BAT=%~f0"
set "INSTALL_DIR=%~dp0"

if not exist "%INSTALL_DIR%install.ps1" goto package_missing
if not exist "%INSTALL_DIR%manifest.json" goto package_missing
if not exist "%INSTALL_DIR%payload\install.sh" goto package_missing
if not exist "%INSTALL_DIR%scripts\windows\win-miloco-workflow.ps1" goto package_missing

net session >nul 2>&1
if %errorLevel% == 0 goto run

set "MILOCO_MSG_B64=5q2j5Zyo6K+35rGC566h55CG5ZGY5p2D6ZmQ77yM6K+35Zyo5by55Ye655qEIFdpbmRvd3Mg5p2D6ZmQ56qX5Y+j6YeM6YCJ5oup4oCc5piv4oCd44CC"
call :say
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:INSTALL_BAT -WorkingDirectory $env:INSTALL_DIR -Verb RunAs; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
if %errorLevel% neq 0 goto elevate_failed
exit /b

:run
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -PauseOnExit
exit /b %errorlevel%

:package_missing
echo.
set "MILOCO_MSG_B64=6L+Z5Liq5paH5Lu25aS55LiN5YOP5a6M5pW06Kej5Y6L5ZCO55qEIGVhc3ktbWlsb2NvIOWuieijheWMheOAgg=="
call :say
echo.
set "MILOCO_MSG_B64=6K+35LiN6KaB55u05o6l5ZyoIHppcCDljovnvKnljIXnqpflj6Pph4zov5DooYwgaW5zdGFsbC5iYXTjgII="
call :say
set "MILOCO_MSG_B64=6K+35YWI5oqK5pW05LiqIHppcCDop6PljovliLDmma7pgJrmlofku7blpLnvvIzlho3lj4zlh7vph4zpnaLnmoQgaW5zdGFsbC5iYXTjgII="
call :say
echo.
set "MILOCO_MSG_B64=5oyJ5Zue6L2m57un57ut44CC"
call :wait
exit /b 1

:elevate_failed
echo.
set "MILOCO_MSG_B64=6K+35rGC566h55CG5ZGY5p2D6ZmQ5aSx6LSl44CC"
call :say
set "MILOCO_MSG_B64=6K+35Y+z6ZSuIGluc3RhbGwuYmF077yM6YCJ5oup4oCc5Lul566h55CG5ZGY6Lqr5Lu96L+Q6KGM4oCd44CC"
call :say
echo.
set "MILOCO_MSG_B64=5oyJ5Zue6L2m57un57ut44CC"
call :wait
exit /b 1

:powershell_missing
echo.
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
