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

function Check-Prerequisites {
  $failed = $false

  # 1. 操作系统版本：Windows 11 22H2+ (build >= 22621)
  $build = [System.Environment]::OSVersion.Version.Build
  if ($build -lt 22621) {
    Write-Host "[FAIL] 当前 Windows 版本过低 (Build $build)，需要 Windows 11 22H2+ (Build 22621+)。" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK] Windows Build $build" -ForegroundColor Green
  }

  # 2. 管理员权限
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "[FAIL] 需要管理员权限。请右键 install.bat → '以管理员身份运行'。" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK] 管理员权限" -ForegroundColor Green
  }

  # 3. 网络与 GitHub 加速测速
  Write-Host "正在检测网络与代理加速测速..." -ForegroundColor Gray
  $endpoints = @(
    @{ Name = "直连"; Url = "https://github.com"; Prefix = "" },
    @{ Name = "gh-proxy.org"; Url = "https://v4.gh-proxy.org"; Prefix = "https://v4.gh-proxy.org/" },
    @{ Name = "gitwarp.com"; Url = "https://www.gitwarp.com"; Prefix = "https://www.gitwarp.com/" }
  )

  $fastest = $null
  $minTime = [int]::MaxValue

  foreach ($ep in $endpoints) {
    try {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $request = [System.Net.WebRequest]::Create($ep.Url)
      $request.Timeout = 3000
      $request.Method = "HEAD"
      $response = $request.GetResponse()
      $sw.Stop()
      $response.Close()
      if ($sw.ElapsedMilliseconds -lt $minTime) {
        $minTime = $sw.ElapsedMilliseconds
        $fastest = $ep
      }
    } catch {}
  }

  if ($fastest) {
    Write-Host ("[OK] 网络连通。选中最快节点: {0} ({1}ms)" -f $fastest.Name, $minTime) -ForegroundColor Green
    $global:GITHUB_PROXY_PREFIX = $fastest.Prefix
  } else {
    Write-Host "[WARN] 无法连接到 GitHub 及任何加速节点，后续下载可能会失败。" -ForegroundColor Yellow
    $global:GITHUB_PROXY_PREFIX = ""
  }

  if ($failed) {
    Write-Host ""
    Write-Host "请修复以上问题后重新运行 install.bat。" -ForegroundColor Yellow
    exit 1
  }
  Write-Host ""
}

function Ensure-Wsl {
  # 1. wsl.exe 不存在
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "[INFO] 未检测到 WSL (wsl.exe)，正在尝试自动安装..." -ForegroundColor Cyan
    & wsl.exe --install -d $Distro
    if ($LASTEXITCODE -ne 0) {
       Write-Host "[FAIL] WSL 安装失败。请检查主板 BIOS 是否已开启 CPU 虚拟化，并确保网络畅通。" -ForegroundColor Red
       exit 1
    }
    Write-Host "[WARN] WSL 安装已完成，请重启电脑后再次运行 install.bat 以继续。" -ForegroundColor Yellow
    exit 1
  }

  # 2. wsl.exe 存在但内部损坏 — 用 try/catch 捕获
  $list = $null
  try {
    $list = (& wsl.exe -l -v 2>&1 | Out-String) -replace "`0", ""
  } catch {
    $list = $null
  }

  # wsl.exe -l -v 返回非零退出码或空输出 → WSL 组件异常
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($list)) {
    Write-Host "[INFO] WSL 组件异常，正在尝试自动修复更新..." -ForegroundColor Cyan
    & wsl.exe --update
    & wsl.exe --install -d $Distro
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[FAIL] WSL 自动修复失败。请打开微软商店手动更新 WSL，或检查 BIOS 虚拟化设置。" -ForegroundColor Red
      exit 1
    }
    Write-Host "[WARN] 修复完成，可能需要重启电脑。请重启后再次运行 install.bat。" -ForegroundColor Yellow
    exit 1
  }

  # 3. WSL 正常，检查发行版
  if ($list -match [regex]::Escape($Distro)) {
    return
  }

  Write-Host "[INFO] 发现 WSL，但缺少 $Distro 发行版。正在自动安装..." -ForegroundColor Cyan
  & wsl.exe --install -d $Distro
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] 发行版安装失败。请检查网络连接或尝试重启电脑。" -ForegroundColor Red
    exit 1
  }
  Write-Host "[WARN] 发行版安装完成！如果 Windows 提示需要重启或创建 Ubuntu 默认用户，请先完成操作，然后再重新运行 install.bat。" -ForegroundColor Yellow
  exit 1
}

function Invoke-WslBash {
  param([string]$Script)

  $Script = $Script -replace "`r`n", "`n"
  $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $wslTmp = "/tmp/miloco-$id.sh"

  # Write script to a Windows temp file, then copy into WSL via /mnt path
  $winTmp = Join-Path ([System.IO.Path]::GetTempPath()) "miloco-$id.sh"
  [System.IO.File]::WriteAllText($winTmp, $Script, [System.Text.UTF8Encoding]::new($false))
  $wslMnt = ConvertTo-WslPath $winTmp

  & wsl.exe -d $Distro -- bash -lc "cp '${wslMnt}' '${wslTmp}' && bash '${wslTmp}'; rc=`$?; rm -f '${wslTmp}'; exit `$rc"
  $code = $LASTEXITCODE
  Remove-Item -LiteralPath $winTmp -ErrorAction SilentlyContinue
  if ($code -ne 0) {
    exit $code
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

  $launcherName = "Miloco " + [string][char]0x63A7 + [string][char]0x5236 + [string][char]0x53F0 + ".bat"
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
echo        Miloco / OpenClaw 控制台
echo ========================================
echo.
echo   1. 重启 OpenClaw 面板
echo   2. 重启 Miloco 面板
echo   3. 重启 Miloco + OpenClaw
echo   4. 关闭 OpenClaw + Miloco
echo   5. 关闭 WSL
echo   0. 退出
echo.
choice /c 123450 /n /m "请选择 [1/2/3/4/5/0]: "

if errorlevel 6 goto exit
if errorlevel 5 goto stop_wsl
if errorlevel 4 goto stop_services
if errorlevel 3 goto restart_all
if errorlevel 2 goto restart_miloco
if errorlevel 1 goto restart_openclaw

:restart_openclaw
echo.
echo 正在重启 OpenClaw 面板...
wsl.exe -d "%DISTRO%" -- bash -lc "export PATH=""$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH""; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true"
if errorlevel 1 goto wsl_failed
call :open_port "%OPENCLAW_PORT%"
goto pause_main

:restart_miloco
echo.
echo 正在重启 Miloco 面板...
wsl.exe -d "%DISTRO%" -- bash -lc "export PATH=""$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH""; miloco-cli service restart >/tmp/miloco-desktop-restart.log 2>&1 || true"
if errorlevel 1 goto wsl_failed
call :open_port "%MILOCO_PORT%"
goto pause_main

:restart_all
echo.
echo 正在重启 Miloco + OpenClaw...
wsl.exe -d "%DISTRO%" -- bash -lc "export PATH=""$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH""; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; miloco-cli service restart >/tmp/miloco-desktop-restart.log 2>&1 || true; openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true"
if errorlevel 1 goto wsl_failed
call :open_port "%MILOCO_PORT%"
call :open_port "%OPENCLAW_PORT%"
goto pause_main

:open_port
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$port=[int]'%~1'; $deadline=(Get-Date).AddSeconds(60); while((Get-Date) -lt $deadline){ $tcp=New-Object Net.Sockets.TcpClient; try { $iar=$tcp.BeginConnect('127.0.0.1',$port,$null,$null); if($iar.AsyncWaitHandle.WaitOne(1000)){ $tcp.EndConnect($iar); break } } catch {} finally { $tcp.Close() }; Start-Sleep -Seconds 1 }; Start-Process ('http://127.0.0.1:'+$port+'/')"
exit /b 0

:stop_services
call :stop_miloco_stack
goto pause_main

:stop_wsl
call :stop_miloco_stack
echo 正在关闭 WSL: %DISTRO%
wsl.exe --terminate "%DISTRO%"
goto pause_main

:stop_miloco_stack
echo.
echo 正在关闭 OpenClaw + Miloco...
schtasks /End /TN MilocoWSLKeeper >nul 2>nul
wsl.exe -d "%DISTRO%" -- bash -lc "set +e; export PATH=""$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH""; systemctl --user disable --now openclaw-gateway.service >/tmp/openclaw-desktop-stop.log 2>&1 || true; rm -f ""$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service"" 2>/dev/null || true; systemctl --user daemon-reload >/dev/null 2>&1 || true; miloco-cli service stop >/tmp/miloco-desktop-stop.log 2>&1 || true; supervisorctl -c ""$HOME/.openclaw/miloco/supervisord.conf"" shutdown >/tmp/miloco-desktop-supervisor-stop.log 2>&1 || true; pkill -TERM -f ""[w]indows-keeper.sh"" 2>/dev/null || true; pkill -TERM -f ""[w]sl-miloco-keeper.sh"" 2>/dev/null || true; pkill -TERM -f ""/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main"" 2>/dev/null || true; pkill -TERM -f ""[o]penclaw/dist/index.js gateway --port"" 2>/dev/null || true; sleep 2; pkill -KILL -f ""/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main"" 2>/dev/null || true; pkill -KILL -f ""[o]penclaw/dist/index.js gateway --port"" 2>/dev/null || true"
echo 关闭命令已发送。
exit /b 0

:wsl_failed
echo 调用 WSL 失败，请检查 WSL 发行版: %DISTRO%
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
  [System.IO.File]::WriteAllText($launcher, $bat, [System.Text.UTF8Encoding]::new($false))
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
  Check-Prerequisites
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
export GITHUB_PROXY_PREFIX="$global:GITHUB_PROXY_PREFIX"
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
