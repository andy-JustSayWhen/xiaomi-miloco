@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorLevel% == 0 goto run

echo [INFO] 正在请求管理员权限，请在弹出的窗口中选择“是”...
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if %errorlevel% neq 0 pause
