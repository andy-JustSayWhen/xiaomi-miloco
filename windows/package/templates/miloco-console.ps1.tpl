$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$script:Distro = "__DISTRO__"
$script:MilocoPort = __MILOCO_PORT__
$script:OpenClawPort = __OPENCLAW_PORT__
$script:OpenClawInfoPath = "__OPENCLAW_INFO_PATH__"
$script:WslExe = Join-Path $env:WINDIR "System32\wsl.exe"
if (-not (Test-Path -LiteralPath $script:WslExe)) {
  $script:WslExe = "wsl.exe"
}

function Test-Distro {
  & $script:WslExe -d $script:Distro -- true > $null 2> $null
  if ($LASTEXITCODE -eq 0) {
    return $true
  }

  Write-Host ""
  Write-Host ("找不到安装时使用的 WSL 发行版：{0}" -f $script:Distro) -ForegroundColor Yellow
  Write-Host "当前可用发行版：" -ForegroundColor Yellow
  & $script:WslExe -l -v
  return $false
}

function Invoke-WslBash {
  param([string]$Command)

  if (-not (Test-Distro)) {
    return $false
  }

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  & $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash"
  if ($LASTEXITCODE -ne 0) {
    Write-Host ("调用 WSL 失败，退出码：{0}" -f $LASTEXITCODE) -ForegroundColor Red
    return $false
  }
  return $true
}

function Invoke-WslText {
  param([string]$Command)

  if (-not (Test-Distro)) {
    return @()
  }

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  return @(& $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash" 2>$null)
}

function Write-Status {
  param([string]$Message)

  Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message) -ForegroundColor Cyan
}

function Write-ActionOk {
  param([string]$Message)

  Write-Host ("[OK] {0}" -f $Message) -ForegroundColor Green
}

function Prompt-Line {
  param([string]$Prompt)

  [Console]::Write($Prompt)
  return [Console]::ReadLine()
}

function Pause-ReturnToMenu {
  param(
    [string[]]$Lines = @("按回车返回菜单...")
  )

  Write-Host ""
  foreach ($line in $Lines) {
    Write-Host $line -ForegroundColor Yellow
  }
  [void](Prompt-Line "")
}

function Test-TcpPort {
  param([int]$Port)

  $tcp = New-Object Net.Sockets.TcpClient
  try {
    $iar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(1000)) {
      $tcp.EndConnect($iar)
      return $true
    }
  } catch {
  } finally {
    $tcp.Close()
  }
  return $false
}

function Test-MilocoHealthReady {
  param([int]$Port)

  try {
    $resp = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/health" -f $Port) -Method Get -TimeoutSec 3
    if ($resp -and $resp.status -eq "ok") {
      return $true
    }
  } catch {
  }
  return $false
}

function Test-WslMilocoHealthReady {
  param([int]$Port)

  $cmd = 'curl -fsS --max-time 3 "http://127.0.0.1:__PORT__/health" 2>/dev/null | grep -q "\"status\"[[:space:]]*:[[:space:]]*\"ok\""'
  $cmd = $cmd.Replace("__PORT__", [string]$Port)
  return (Invoke-WslBash $cmd)
}

function Get-ClipboardOpenClawUrl {
  param([int]$Port)

  try {
    $clip = Get-Clipboard -Raw
    if (-not [string]::IsNullOrWhiteSpace($clip)) {
      foreach ($line in ($clip -split "`r?`n")) {
        $match = [regex]::Match([string]$line, ('https?://127\.0\.0\.1:{0}[^\s"''<>]*' -f $Port))
        if ($match.Success) {
          return $match.Value.Trim()
        }
      }
    }
  } catch {
  }
  return ""
}

function Get-OpenClawLaunchInfo {
  param([int]$Port)

  $baseUrl = "http://127.0.0.1:{0}" -f $Port
  $dashboardFallback = "{0}/" -f $baseUrl
  $dashboardUrl = ""
  $clipboardUrl = ""
  try {
    $cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; openclaw dashboard --no-open --yes 2>/tmp/openclaw-dashboard-url.err || true'
    foreach ($line in (Invoke-WslText $cmd)) {
      $match = [regex]::Match([string]$line, 'https?://[^\s"''<>]+')
      if ($match.Success) {
        $candidate = $match.Value.Trim()
        if ($candidate -match '(^|[#?&])token=') {
          $tokenFromUrl = ""
          $tokenMatch = [regex]::Match($candidate, '(?i)(?:[#?&]token=)([^&]+)')
          if ($tokenMatch.Success) {
            try { $tokenFromUrl = [Uri]::UnescapeDataString($tokenMatch.Groups[1].Value) } catch { $tokenFromUrl = $tokenMatch.Groups[1].Value }
          }
          return [pscustomobject]@{
            LaunchUrl     = $candidate
            DashboardUrl  = $candidate
            Token         = $tokenFromUrl
            WsUrl         = ("ws://127.0.0.1:{0}" -f $Port)
            BaseUrl       = $dashboardFallback
            ChatUrl       = ("{0}/chat?session=main" -f $baseUrl)
          }
        }
        if (-not $dashboardUrl) {
          $dashboardUrl = $candidate
        }
      }
    }
  } catch {
    $dashboardUrl = ""
  }
  $clipboardUrl = Get-ClipboardOpenClawUrl $Port

  $token = ""
  try {
    $py = @"
import json
from pathlib import Path

def read_json(path):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}

def text(value):
    return value.strip() if isinstance(value, str) else ""

home = Path.home()
miloco = read_json(home / ".openclaw" / "miloco" / "config.json")
openclaw = read_json(home / ".openclaw" / "openclaw.json")
candidates = []
agent = miloco.get("agent") if isinstance(miloco, dict) else {}
if isinstance(agent, dict):
    candidates.append(agent.get("auth_bearer"))
gateway = openclaw.get("gateway") if isinstance(openclaw, dict) else {}
auth = gateway.get("auth") if isinstance(gateway, dict) else {}
if isinstance(auth, dict):
    candidates.extend([auth.get("token"), auth.get("password"), auth.get("bearer")])
for candidate in candidates:
    value = text(candidate)
    if value:
        print(value)
        raise SystemExit(0)
"@
    $token = (& $script:WslExe -d $script:Distro -- python3 -c $py 2>$null | Select-Object -First 1)
  } catch {
    $token = ""
  }
  if ($clipboardUrl) {
    if (-not $dashboardUrl) {
      $dashboardUrl = $clipboardUrl
    }
    if (-not $token) {
      $tokenMatch = [regex]::Match($clipboardUrl, '(?i)(?:[#?&]token=)([^&]+)')
      if ($tokenMatch.Success) {
        try { $token = [Uri]::UnescapeDataString($tokenMatch.Groups[1].Value) } catch { $token = $tokenMatch.Groups[1].Value }
      }
    }
  }
  $chatUrl = "{0}/chat?session=main" -f $baseUrl
  $launchUrl = if ($clipboardUrl) { $clipboardUrl } elseif ($dashboardUrl) { $dashboardUrl } else { $dashboardFallback }
  if ($token) {
    $encodedToken = [Uri]::EscapeDataString($token.Trim())
    $launchUrl = "{0}#token={1}" -f $dashboardFallback.TrimEnd('/'), $encodedToken
  }
  return [pscustomobject]@{
    LaunchUrl     = $launchUrl
    DashboardUrl  = $(if ($dashboardUrl) { $dashboardUrl } else { $dashboardFallback })
    Token         = $token.Trim()
    WsUrl         = ("ws://127.0.0.1:{0}" -f $Port)
    BaseUrl       = $dashboardFallback
    ChatUrl       = $chatUrl
  }
}

function Write-OpenClawInfoFile {
  param([object]$Info)

  if ([string]::IsNullOrWhiteSpace($script:OpenClawInfoPath)) {
    return
  }

  $tokenValue = if ($Info -and $Info.Token) { $Info.Token } else { "(empty)" }
  $launchValue = if ($Info -and $Info.LaunchUrl) { $Info.LaunchUrl } else { ("http://127.0.0.1:{0}/chat?session=main" -f $script:OpenClawPort) }
  $dashboardValue = if ($Info -and $Info.DashboardUrl) { $Info.DashboardUrl } else { ("http://127.0.0.1:{0}/" -f $script:OpenClawPort) }
  $wsValue = if ($Info -and $Info.WsUrl) { $Info.WsUrl } else { ("ws://127.0.0.1:{0}" -f $script:OpenClawPort) }
  $lines = @(
    "OpenClaw 登录信息",
    "",
    ("推荐直接打开: {0}" -f $launchValue),
    ("仪表板地址: {0}" -f $dashboardValue),
    ("WebSocket URL: {0}" -f $wsValue),
    ("Gateway Token: {0}" -f $tokenValue),
    "",
    "最省事的用法：",
    "1. 直接双击桌面的 OpenClaw 对话入口；它会优先用带 token 的直达地址打开。",
    "2. 如果页面仍提示未连接，先双击桌面的 Miloco 控制台，选 3，等到服务完全拉起后再试。",
    "3. 还不行，就把上面的 推荐直接打开 地址 整段复制到浏览器地址栏。",
    "4. 如果页面里 token 仍为空，就把上面的 Gateway Token 整段粘贴进去。",
    "",
    "如何获取 / 刷新这些信息：",
    "5. 重新双击 OpenClaw 对话入口，或在 WSL 里运行：openclaw dashboard --no-open --yes",
    "6. 只想看 token，可在 WSL 里运行：openclaw config get gateway.auth.token",
    "",
    "如何管理 / 修改：",
    "7. 当前配置文件：~/.openclaw/openclaw.json",
    "8. 重点字段：gateway.auth.token",
    "9. 改完后重开 OpenClaw 对话入口，或重新运行上面的 dashboard 命令刷新。",
    "",
    "这份文件会在每次打开 OpenClaw 入口时自动刷新。"
  )
  [System.IO.File]::WriteAllText($script:OpenClawInfoPath, ($lines -join "`r`n"), [System.Text.UTF8Encoding]::new($true))
}

function Wait-OpenClawReady {
  param([int]$Seconds = 45)

  $cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; for i in $(seq 1 __SECONDS__); do openclaw gateway status >/tmp/openclaw-desktop-status.log 2>&1 || true; if grep -Eiq "Connectivity probe[:= ]+(ok|passed)|connectivity.*ok|probe.*ok" /tmp/openclaw-desktop-status.log; then exit 0; fi; sleep 1; done; exit 1'
  $cmd = $cmd.Replace("__SECONDS__", [string]$Seconds)
  return (Invoke-WslBash $cmd)
}

function Open-WhenReady {
  param(
    [int]$Port,
    [switch]$OpenClaw
  )

  $label = if ($OpenClaw) { "OpenClaw" } else { "Miloco" }
  $deadline = (Get-Date).AddSeconds(60)
  $nextProgress = (Get-Date)
  while ((Get-Date) -lt $deadline) {
    if ($OpenClaw) {
      if (Test-TcpPort $Port) {
        Write-Status "OpenClaw 端口已响应，继续等待 Gateway 连通性。"
        if (Wait-OpenClawReady 45) {
          $info = Get-OpenClawLaunchInfo $Port
          Write-OpenClawInfoFile $info
          Start-Process $info.LaunchUrl
          Write-ActionOk "OpenClaw 已打开，登录信息也已写到桌面的 OpenClaw-login-info.txt。"
          return $true
        }
        Write-Host "OpenClaw 端口已响应，但 Gateway 连通性还没有通过。" -ForegroundColor Yellow
        Write-Host "可查看 WSL 内日志：" -ForegroundColor Yellow
        Write-Host "  /tmp/openclaw-desktop-restart.log" -ForegroundColor Yellow
        Write-Host "  /tmp/openclaw-desktop-status.log" -ForegroundColor Yellow
        Pause-ReturnToMenu
        return $false
      }
    } else {
      if ((Test-TcpPort $Port) -and (Test-MilocoHealthReady $Port)) {
        Start-Process ("http://127.0.0.1:{0}/" -f $Port)
        Write-ActionOk "Miloco 面板已打开。"
        return $true
      }
    }

    if ((Get-Date) -ge $nextProgress) {
      Write-Status ("正在等待 {0} 就绪..." -f $label)
      $nextProgress = (Get-Date).AddSeconds(10)
    }
    Start-Sleep -Seconds 1
  }

  if ($OpenClaw) {
    $info = Get-OpenClawLaunchInfo $Port
    Write-OpenClawInfoFile $info
  }
  $wslReady = if ($OpenClaw) { Wait-OpenClawReady 5 } else { Test-WslMilocoHealthReady $Port }
  if ($wslReady) {
    Write-Host ("{0} 已在 WSL 内启动，但 Windows 当前访问不到 http://127.0.0.1:{1} 。" -f $label, $Port) -ForegroundColor Yellow
    Write-Host "这次不是服务没起来，更像是 WSL 回环转发、mirrored 网络或 Hyper-V/本机防火墙拦截。" -ForegroundColor Yellow
    Write-Host "可先在 WSL 内确认服务状态，再检查 Windows 到 WSL 的访问链路。" -ForegroundColor Yellow
  } else {
    Write-Host ("{0} 在 60 秒内还没有准备好，所以暂时没有自动打开浏览器。" -f $label) -ForegroundColor Yellow
    Write-Host "这通常表示服务还在启动、启动失败，或端口被占用。" -ForegroundColor Yellow
  }
  Write-Host "可查看 WSL 内日志：" -ForegroundColor Yellow
  Write-Host "  /tmp/miloco-desktop-start.log" -ForegroundColor Yellow
  Write-Host "  /tmp/miloco-desktop-restart.log" -ForegroundColor Yellow
  Write-Host "  /tmp/openclaw-desktop-restart.log" -ForegroundColor Yellow
  Pause-ReturnToMenu
  return $false
}

function Get-MilocoPortConfigCommand {
  $py = @"
import json
from pathlib import Path

port = $script:MilocoPort
path = Path.home() / ".openclaw" / "miloco" / "config.json"
data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
server = data.setdefault("server", {})
server["url"] = f"http://127.0.0.1:{port}"
server["port"] = port
tmp = path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
tmp.replace(path)
"@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
  return "python3 -c `"import base64; exec(base64.b64decode('$encoded').decode('utf-8'))`" >/tmp/miloco-desktop-config-json.log 2>&1"
}

function Restart-OpenClaw {
  Write-Host ""
  Write-Status "正在重启 OpenClaw 面板..."
  $cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true'
  if (Invoke-WslBash $cmd) {
    return (Open-WhenReady $script:OpenClawPort -OpenClaw)
  }
  Pause-ReturnToMenu
  return $false
}

function Restart-Miloco {
  Write-Host ""
  Write-Status "正在重启 Miloco 面板..."
  $configCmd = Get-MilocoPortConfigCommand
  $cmd = 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; ' + $configCmd + ' || exit 44; miloco-cli service restart >/tmp/miloco-desktop-restart.log 2>&1 || { miloco-cli service stop >/tmp/miloco-desktop-stop.log 2>&1 || true; miloco-cli service start >/tmp/miloco-desktop-start.log 2>&1; }'
  if (Invoke-WslBash $cmd) {
    return (Open-WhenReady $script:MilocoPort)
  }
  Pause-ReturnToMenu
  return $false
}

function Restart-All {
  Write-Host ""
  Write-Status "正在重启 Miloco + OpenClaw..."
  $configCmd = Get-MilocoPortConfigCommand
  $cmd = 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; ' + $configCmd + ' || exit 44; openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true; miloco-cli service restart >/tmp/miloco-desktop-restart.log 2>&1 || { miloco-cli service stop >/tmp/miloco-desktop-stop.log 2>&1 || true; miloco-cli service start >/tmp/miloco-desktop-start.log 2>&1; }'
  if (Invoke-WslBash $cmd) {
    $openClawOk = Open-WhenReady $script:OpenClawPort -OpenClaw
    $milocoOk = Open-WhenReady $script:MilocoPort
    return ($milocoOk -and $openClawOk)
  }
  Pause-ReturnToMenu
  return $false
}

function Stop-Services {
  Write-Host ""
  Write-Host "正在关闭 OpenClaw + Miloco..."
  & schtasks.exe /End /TN MilocoWSLKeeper > $null 2> $null
  $cmd = 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user disable --now openclaw-gateway.service >/tmp/openclaw-desktop-stop.log 2>&1 || true; rm -f "$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service" 2>/dev/null || true; systemctl --user daemon-reload >/dev/null 2>&1 || true; supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-desktop-supervisor-stop.log 2>&1 || true; pkill -TERM -f "[w]indows-keeper.sh" 2>/dev/null || true; pkill -TERM -f "[w]sl-miloco-keeper.sh" 2>/dev/null || true; pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; pkill -TERM -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true; sleep 2; pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; pkill -KILL -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true'
  [void](Invoke-WslBash $cmd)
  Write-Host "关闭命令已发送。"
}

function Stop-Wsl {
  Stop-Services
  Write-Host ("正在关闭 WSL：{0}" -f $script:Distro)
  & $script:WslExe --terminate $script:Distro
}

function Show-Menu {
  Clear-Host
  Write-Host "========================================"
  Write-Host "       Miloco / OpenClaw 控制台"
  Write-Host "========================================"
  Write-Host ""
  Write-Host "  1. 重启 OpenClaw 面板"
  Write-Host "  2. 重启 Miloco 面板"
  Write-Host "  3. 重启 Miloco + OpenClaw"
  Write-Host "  4. 关闭 OpenClaw + Miloco"
  Write-Host "  5. 关闭 WSL"
  Write-Host "  0. 退出"
  Write-Host ""
  Write-Host "说明："
  Write-Host "  1. 打开或刷新 OpenClaw 对话入口，并刷新桌面的 OpenClaw-login-info.txt。"
  Write-Host "  2. 打开或刷新 Miloco 管理面板。适合日常查看设备、摄像头、账号、模型和家庭配置。"
  Write-Host "  3. 一次性拉起整套服务，并打开两个面板。首次安装后、电脑重启后，优先选这个。"
  Write-Host "  4. 停止两个服务，但保留 WSL。适合今天不用了、想释放后台资源，或准备重新启动服务。"
  Write-Host "  5. 停止服务并关闭本次安装使用的 WSL。适合彻底退出、电脑卡顿、网络或端口异常时重置环境。"
  Write-Host "  0. 只关闭当前脚本，不影响已经运行的 Miloco 和 OpenClaw 服务。"
  Write-Host ""
}

while ($true) {
  Show-Menu
  if (-not (Test-Distro)) {
    Write-Host ""
    Pause-ReturnToMenu
    continue
  }

  $choice = (Prompt-Line "请选择 [1/2/3/4/5/0]: ").Trim()
  switch ($choice) {
    "1" { [void](Restart-OpenClaw) }
    "2" { [void](Restart-Miloco) }
    "3" { [void](Restart-All) }
    "4" { Stop-Services }
    "5" { Stop-Wsl }
    "0" { exit 0 }
    default {
      Write-Host "请输入 1、2、3、4、5 或 0。" -ForegroundColor Yellow
      Start-Sleep -Seconds 1
    }
  }
}
