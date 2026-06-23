param(
  [ValidateSet("Prepare", "Report", "BindUrl", "Finish", "Validate")]
  [string]$Action = "Prepare",
  [string]$Distro = "Ubuntu-24.04",
  [int]$MilocoPort = 1886,
  [int]$OpenClawPort = 18789,
  [string]$AuthPayload = "",
  [string]$MimoApiKey = "",
  [string]$OmniModel = "xiaomi/mimo-v2.5",
  [string]$OmniBaseUrl = "https://api.xiaomimimo.com/v1",
  [string]$HomeId = "",
  [string]$CameraDids = "",
  [switch]$InstallWsl
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestPath = Join-Path $PackageRoot "manifest.json"
$PayloadDir = Join-Path $PackageRoot "payload"
$WindowsScriptsDir = Join-Path $PackageRoot "scripts\windows"
$Workflow = Join-Path $WindowsScriptsDir "win-miloco-workflow.ps1"
$InstallSh = Join-Path $PayloadDir "install.sh"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host ("== {0} ==" -f $Message) -ForegroundColor Cyan
}

function Fail {
  param([string]$Message)
  Write-Host ("[FAIL] {0}" -f $Message) -ForegroundColor Red
  exit 1
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    Fail "Required file not found: $Path"
  }
}

function ConvertTo-WslPath {
  param([string]$WindowsPath)
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  if ($full -match "^([A-Za-z]):\\(.*)$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2].Replace("\", "/")
    return "/mnt/$drive/$rest"
  }
  throw "Only drive-letter Windows paths can be converted to WSL paths: $WindowsPath"
}

function Ensure-Wsl {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "wsl.exe not found. Enable WSL first, then rerun install.ps1."
  }

  $list = (& wsl.exe -l -v 2>&1 | Out-String) -replace "`0", ""
  if ($list -match [regex]::Escape($Distro)) {
    return
  }

  if ($InstallWsl) {
    Write-Step "Install WSL distro"
    & wsl.exe --install -d $Distro
    Write-Host "If Windows asks for restart or first-time Ubuntu user setup, finish that first, then rerun install.ps1."
    exit $LASTEXITCODE
  }

  Fail "$Distro not found. Rerun with -InstallWsl, or install it manually with: wsl --install -d $Distro"
}

function Invoke-WslBash {
  param([string]$Script)

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Script)
  $b64 = [Convert]::ToBase64String($bytes)
  & wsl.exe -d $Distro -- bash -lc "echo '$b64' | base64 -d | bash"
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

function Get-PowerShellExe {
  $candidate = Join-Path $PSHOME "powershell.exe"
  if (Test-Path -LiteralPath $candidate) { return $candidate }
  $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if ($pwsh) { return $pwsh.Source }
  return "powershell.exe"
}

function Install-DesktopLauncher {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
    Write-Host "[WARN] Desktop folder not found; skipped Miloco desktop launcher."
    return
  }

  $launcherName = [string][char]0x4E00 + [string][char]0x952E + [string][char]0x542F + [string][char]0x52A8 + " Miloco.bat"
  $launcher = Join-Path $desktop $launcherName
  $bat = @'
@echo off
setlocal
chcp 65001 >nul

set "DISTRO=__DISTRO__"
set "MILOCO_PORT=__MILOCO_PORT__"
set "OPENCLAW_PORT=__OPENCLAW_PORT__"

:main_menu
cls
echo ========================================
echo          Miloco / OpenClaw Menu
echo ========================================
echo.
echo   1. Start OpenClaw panel
echo   2. Start Miloco panel
echo   3. Stop services
echo   0. Exit
echo.
choice /c 1230 /n /m "Select [1/2/3/0]: "

if errorlevel 4 goto exit
if errorlevel 3 goto stop_menu
if errorlevel 2 goto start_miloco
if errorlevel 1 goto start_openclaw

:start_openclaw
echo.
echo Starting OpenClaw panel...
wsl.exe -d "%DISTRO%" -- bash -lc "export PATH=""$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH""; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; openclaw gateway start >/tmp/openclaw-desktop-start.log 2>&1 || systemctl --user start openclaw-gateway.service >/tmp/openclaw-desktop-start-systemd.log 2>&1 || true"
if errorlevel 1 goto wsl_failed
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$port=[int]$env:OPENCLAW_PORT; $deadline=(Get-Date).AddSeconds(60); while((Get-Date) -lt $deadline){ $tcp=New-Object Net.Sockets.TcpClient; try { $iar=$tcp.BeginConnect('127.0.0.1',$port,$null,$null); if($iar.AsyncWaitHandle.WaitOne(1000)){ $tcp.EndConnect($iar); break } } catch {} finally { $tcp.Close() }; Start-Sleep -Seconds 1 }; Start-Process ('http://127.0.0.1:'+$port+'/')"
goto pause_main

:start_miloco
echo.
echo Starting Miloco panel...
wsl.exe -d "%DISTRO%" -- bash -lc "export PATH=""$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH""; miloco-cli service start >/tmp/miloco-desktop-start.log 2>&1 || true"
if errorlevel 1 goto wsl_failed
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$port=[int]$env:MILOCO_PORT; $deadline=(Get-Date).AddSeconds(60); while((Get-Date) -lt $deadline){ $tcp=New-Object Net.Sockets.TcpClient; try { $iar=$tcp.BeginConnect('127.0.0.1',$port,$null,$null); if($iar.AsyncWaitHandle.WaitOne(1000)){ $tcp.EndConnect($iar); break } } catch {} finally { $tcp.Close() }; Start-Sleep -Seconds 1 }; Start-Process ('http://127.0.0.1:'+$port+'/')"
goto pause_main

:stop_menu
cls
echo ========================================
echo              Stop Services
echo ========================================
echo.
echo   1. Stop Miloco services
echo   2. Stop Miloco services and WSL
echo   0. Back
echo.
choice /c 120 /n /m "Select [1/2/0]: "

if errorlevel 3 goto main_menu
if errorlevel 2 goto stop_with_wsl
if errorlevel 1 goto stop_services

:stop_services
call :stop_miloco_stack
goto pause_main

:stop_with_wsl
call :stop_miloco_stack
echo Terminating WSL: %DISTRO%
wsl.exe --terminate "%DISTRO%"
goto pause_main

:stop_miloco_stack
echo.
echo Stopping Miloco / OpenClaw services...
schtasks /End /TN MilocoWSLKeeper >nul 2>nul
wsl.exe -d "%DISTRO%" -- bash -lc "set +e; export PATH=""$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH""; systemctl --user disable --now openclaw-gateway.service >/tmp/openclaw-desktop-stop.log 2>&1 || true; rm -f ""$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service"" 2>/dev/null || true; systemctl --user daemon-reload >/dev/null 2>&1 || true; miloco-cli service stop >/tmp/miloco-desktop-stop.log 2>&1 || true; supervisorctl -c ""$HOME/.openclaw/miloco/supervisord.conf"" shutdown >/tmp/miloco-desktop-supervisor-stop.log 2>&1 || true; pkill -TERM -f ""[w]indows-keeper.sh"" 2>/dev/null || true; pkill -TERM -f ""[w]sl-miloco-keeper.sh"" 2>/dev/null || true; pkill -TERM -f ""/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main"" 2>/dev/null || true; pkill -TERM -f ""[o]penclaw/dist/index.js gateway --port"" 2>/dev/null || true; sleep 2; pkill -KILL -f ""/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main"" 2>/dev/null || true; pkill -KILL -f ""[o]penclaw/dist/index.js gateway --port"" 2>/dev/null || true"
echo Stop command sent.
exit /b 0

:wsl_failed
echo Failed to invoke WSL. Please check WSL distro: %DISTRO%
goto pause_main

:pause_main
echo.
pause
goto main_menu

:exit
endlocal
exit /b 0
'@
  $bat = $bat.Replace("__DISTRO__", $Distro).Replace("__MILOCO_PORT__", [string]$MilocoPort).Replace("__OPENCLAW_PORT__", [string]$OpenClawPort)
  Set-Content -Encoding utf8 -LiteralPath $launcher -Value $bat
  Write-Host "Desktop launcher created: $launcher"
}

function Invoke-Workflow {
  param([string]$WorkflowAction)

  Require-File $Workflow
  $args = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $Workflow,
    "-Action", $WorkflowAction,
    "-Distro", $Distro,
    "-MilocoPort", [string]$MilocoPort,
    "-OpenClawPort", [string]$OpenClawPort
  )

  if ($WorkflowAction -eq "Finish") {
    $args += @(
      "-AuthPayload", $AuthPayload,
      "-MimoApiKey", $MimoApiKey,
      "-OmniModel", $OmniModel,
      "-OmniBaseUrl", $OmniBaseUrl,
      "-HomeId", $HomeId,
      "-CameraDids", $CameraDids
    )
  }

  $powershellExe = Get-PowerShellExe
  & $powershellExe @args
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  if ($code -eq 0 -and $WorkflowAction -eq "Finish") {
    Install-DesktopLauncher
  }
  exit $code
}

function Invoke-Prepare {
  Require-File $ManifestPath
  Require-File $InstallSh
  Ensure-Wsl

  $manifest = Get-Content -Encoding utf8 -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  $version = [string]$manifest.version
  if ([string]::IsNullOrWhiteSpace($version)) {
    Fail "manifest.json missing version."
  }

  $bundle = Get-ChildItem -LiteralPath $PayloadDir -Filter "miloco-linux-x86_64-*.tar.gz" | Select-Object -First 1
  if (-not $bundle) {
    Fail "payload/miloco-linux-x86_64-*.tar.gz not found. Rebuild the release package."
  }

  $wslBundle = ConvertTo-WslPath $bundle.FullName
  $wslInstallSh = ConvertTo-WslPath $InstallSh

  Write-Step "Prime local Miloco bundle in WSL"
  $prime = @"
set -euo pipefail
export MILOCO_HOME="\${MILOCO_HOME:-\$HOME/.openclaw/miloco}"
cache="\$MILOCO_HOME/.install-cache/$version"
mkdir -p "\$cache"
if ! ls "\$cache"/miloco-*.whl >/dev/null 2>&1 || ! ls "\$cache"/miloco_cli-*.whl >/dev/null 2>&1 || ! ls "\$cache"/*.tgz >/dev/null 2>&1; then
  rm -rf "\$cache"
  mkdir -p "\$cache"
  tar -xzf "$wslBundle" -C "\$cache"
fi
"@
  Invoke-WslBash $prime

  Write-Step "Install Miloco in WSL"
  $install = @"
set -euo pipefail
export PATH="\$HOME/.local/bin:\$PATH"
bash "$wslInstallSh" --agent-prepare
miloco-cli service start || true
"@
  Invoke-WslBash $install
  Install-DesktopLauncher

  Write-Step "Generate deployment report"
  $powershellExe = Get-PowerShellExe
  & $powershellExe -ExecutionPolicy Bypass -File $Workflow -Action Report -Distro $Distro -MilocoPort $MilocoPort -OpenClawPort $OpenClawPort
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

  Write-Host ""
  Write-Host "Next steps:"
  Write-Host "1. Run: .\install.ps1 -Action BindUrl"
  Write-Host "2. Complete Xiaomi OAuth in the browser."
  Write-Host "3. Run: .\install.ps1 -Action Finish -AuthPayload '<payload>' -MimoApiKey '<key>'"
  exit $code
}

switch ($Action) {
  "Prepare" { Invoke-Prepare }
  "Report" { Invoke-Workflow "Report" }
  "BindUrl" { Invoke-Workflow "BindUrl" }
  "Finish" { Invoke-Workflow "Finish" }
  "Validate" { Invoke-Workflow "Validate" }
}
