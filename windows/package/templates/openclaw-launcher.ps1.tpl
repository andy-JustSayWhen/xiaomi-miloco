$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$script:Distro = "__DISTRO__"
$script:OpenClawPort = __OPENCLAW_PORT__
$script:OpenClawInfoPath = "__OPENCLAW_INFO_PATH__"
$script:WslExe = Join-Path $env:WINDIR "System32\wsl.exe"
if (-not (Test-Path -LiteralPath $script:WslExe)) {
  $script:WslExe = "wsl.exe"
}

function Invoke-WslBash {
  param([string]$Command)

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  & $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash" > $null 2> $null
  return ($LASTEXITCODE -eq 0)
}

function Invoke-WslText {
  param([string]$Command)

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  return @(& $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash" 2>$null)
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

$cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || true; openclaw gateway start >/tmp/openclaw-desktop-start.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true'
[void](Invoke-WslBash $cmd)
$ready = $false
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
  if (Test-TcpPort $script:OpenClawPort) {
    $ready = $true
    break
  }
  Start-Sleep -Seconds 1
}
$info = Get-OpenClawLaunchInfo $script:OpenClawPort
Write-OpenClawInfoFile $info
if ($ready -and (Wait-OpenClawReady 45)) {
  Start-Process $info.LaunchUrl
} else {
  $shell = New-Object -ComObject WScript.Shell
  $message = if (Wait-OpenClawReady 5) {
    "OpenClaw 已在 WSL 内启动，但 Windows 当前访问不到 127.0.0.1:" + $script:OpenClawPort + "。请先双击桌面的 Miloco 控制台查看提示，或检查 WSL / Hyper-V 访问链路。"
  } else {
    "OpenClaw 暂未就绪。请先双击桌面的 Miloco 控制台选择 3，或查看：" + $script:OpenClawInfoPath
  }
  [void]$shell.Popup($message, 12, "Miloco / OpenClaw", 48)
}
