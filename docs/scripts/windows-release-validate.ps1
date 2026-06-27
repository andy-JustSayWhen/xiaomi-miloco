param(
  [string]$PackagePath = "",
  [string]$Distro = "Ubuntu-24.04",
  [int]$MilocoPort = 18860,
  [int]$OpenClawPort = 18789,
  [switch]$SkipInstallerSmoke,
  [switch]$SkipRuntime
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$script:Checks = New-Object System.Collections.Generic.List[object]
$script:ExpandedTemp = ""

function Add-Check {
  param(
    [string]$Name,
    [ValidateSet("PASS", "WARN", "FAIL", "INFO")]
    [string]$Status,
    [string]$Detail = ""
  )

  $script:Checks.Add([pscustomobject]@{
    name = $Name
    status = $Status
    detail = $Detail
  }) | Out-Null
}

function Write-Section {
  param([string]$Title)
  Write-Host ""
  Write-Host ("== {0} ==" -f $Title) -ForegroundColor Cyan
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required file not found: $Path"
  }
}

function Get-DefaultPackagePath {
  $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $dir = Join-Path $repoRoot "dist\windows\easy-miloco-v0.2-windows"
  if (Test-Path -LiteralPath $dir) {
    return $dir
  }
  return (Join-Path $repoRoot "dist\windows\easy-miloco-v0.2-windows.zip")
}

function Resolve-PackageRoot {
  param([string]$InputPath)

  if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Get-DefaultPackagePath
  }

  $resolved = (Resolve-Path -LiteralPath $InputPath).Path
  if ((Get-Item -LiteralPath $resolved).PSIsContainer) {
    return $resolved
  }

  if ([IO.Path]::GetExtension($resolved) -ne ".zip") {
    throw "PackagePath must be a release directory or zip: $resolved"
  }

  $script:ExpandedTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("easy-miloco-release-validate-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $script:ExpandedTemp | Out-Null
  Expand-Archive -LiteralPath $resolved -DestinationPath $script:ExpandedTemp -Force
  return $script:ExpandedTemp
}

function Assert-AsciiOnly {
  param([string]$Path, [string]$Label)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if (@($bytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
    throw "$Label must be ASCII-only: $Path"
  }
}

function Assert-LfOnly {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
    if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) {
      throw "Shell script must use LF line endings: $Path"
    }
  }
}

function Run-Text {
  param([string]$FilePath, [string[]]$Arguments = @())
  try {
    $output = & $FilePath @Arguments 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_.Exception.Message
      } else {
        $_.ToString()
      }
    }
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return [pscustomobject]@{
      Code = $code
      Text = (($output | Out-String).Trim())
    }
  } catch {
    return [pscustomobject]@{
      Code = -1
      Text = $_.Exception.Message
    }
  }
}

function Test-PackageStructure {
  param([string]$Root)

  Write-Section "Package structure"
  foreach ($path in @(
    "install.bat",
    "install.ps1",
    "manifest.json",
    "payload\install.sh",
    "scripts\windows\win-miloco-workflow.ps1",
    "scripts\windows\windows-preflight.ps1",
    "scripts\windows\templates\install-launcher.bat.tpl",
    "scripts\windows\templates\miloco-console.ps1.tpl",
    "scripts\windows\templates\openclaw-launcher.ps1.tpl",
    "docs\AGENT.md"
  )) {
    Require-File (Join-Path $Root $path)
  }
  Assert-AsciiOnly -Path (Join-Path $Root "install.bat") -Label "install.bat"
  Assert-AsciiOnly -Path (Join-Path $Root "scripts\windows\templates\install-launcher.bat.tpl") -Label "install-launcher.bat.tpl"
  Assert-LfOnly -Path (Join-Path $Root "payload\install.sh")
  Assert-LfOnly -Path (Join-Path $Root "scripts\windows\wsl-miloco-validate.sh")
  Assert-LfOnly -Path (Join-Path $Root "scripts\windows\wsl-post-auth-finish.sh")

  $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $Root "install.ps1") -Raw))
  $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $Root "scripts\windows\win-miloco-workflow.ps1") -Raw))
  $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $Root "scripts\windows\windows-preflight.ps1") -Raw))

  $consoleTpl = Get-Content -Encoding utf8 -LiteralPath (Join-Path $Root "scripts\windows\templates\miloco-console.ps1.tpl") -Raw
  $consoleTpl = $consoleTpl.Replace("__DISTRO__", "Ubuntu-24.04").Replace("__MILOCO_PORT__", "18860").Replace("__OPENCLAW_PORT__", "18789").Replace("__OPENCLAW_INFO_PATH__", "C:\OpenClaw-login-info.txt")
  $null = [scriptblock]::Create($consoleTpl)

  $openClawTpl = Get-Content -Encoding utf8 -LiteralPath (Join-Path $Root "scripts\windows\templates\openclaw-launcher.ps1.tpl") -Raw
  $openClawTpl = $openClawTpl.Replace("__DISTRO__", "Ubuntu-24.04").Replace("__OPENCLAW_PORT__", "18789").Replace("__OPENCLAW_INFO_PATH__", "C:\OpenClaw-login-info.txt")
  $null = [scriptblock]::Create($openClawTpl)

  Add-Check "package.structure" "PASS" $Root
}

function Test-InstallerSmoke {
  param([string]$Root)

  Write-Section "Installer smoke"
  $before = @{}
  Get-ChildItem -LiteralPath $Root -Filter "miloco-install-console-*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
    $before[$_.Name] = $true
  }
  $powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $proc = Start-Process -FilePath $powershellExe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "install.ps1"), "-PauseOnExit") -WorkingDirectory $Root -PassThru -WindowStyle Hidden
  $latest = ""
  $hit = $false
  try {
    for ($i = 0; $i -lt 10; $i++) {
      Start-Sleep -Seconds 6
      $logs = Get-ChildItem -LiteralPath $Root -Filter "miloco-install-console-*.txt" -ErrorAction SilentlyContinue |
        Where-Object { -not $before.ContainsKey($_.Name) } |
        Sort-Object LastWriteTime -Descending
      if ($logs) {
        $latest = $logs[0].FullName
        $text = Get-Content -LiteralPath $latest -Raw -ErrorAction SilentlyContinue
        if ($text -match "\[2/10\]" -or $text -match "\[3/10\]" -or $text -match "环境依赖没有通过" -or $text -match "检查和准备 WSL2 / Ubuntu") {
          $hit = $true
          break
        }
      }
      if ($proc.HasExited) {
        break
      }
    }
  } finally {
    if (-not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($latest)) {
    Add-Check "installer.log" "INFO" $latest
  }

  if ($hit) {
    Add-Check "installer.smoke" "PASS" "Installer reached expected banner/step output without early crash."
    return
  }

  if ($proc.HasExited) {
    Add-Check "installer.smoke" "FAIL" ("Installer exited early with code {0}." -f $proc.ExitCode)
  } else {
    Add-Check "installer.smoke" "WARN" "Installer did not prove expected progress within timeout."
  }
}

function Test-RuntimeChecks {
  param([string]$Root)

  Write-Section "Runtime preflight"
  $preflight = Join-Path $Root "scripts\windows\windows-preflight.ps1"
  $workflow = Join-Path $Root "scripts\windows\win-miloco-workflow.ps1"
  $reportPath = Join-Path $Root ("release-runtime-report-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
  $powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

  $preflightResult = Run-Text -FilePath $powershellExe -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $preflight, "-Distro", $Distro, "-MilocoPort", [string]$MilocoPort, "-OpenClawPort", [string]$OpenClawPort)
  if ($preflightResult.Code -eq 0) {
    Add-Check "runtime.preflight" "PASS" "windows-preflight.ps1 passed."
  } else {
    Add-Check "runtime.preflight" "WARN" ("windows-preflight.ps1 exit={0}" -f $preflightResult.Code)
  }

  $reportResult = Run-Text -FilePath $powershellExe -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $workflow, "-Action", "Report", "-Distro", $Distro, "-MilocoPort", [string]$MilocoPort, "-OpenClawPort", [string]$OpenClawPort, "-ReportPath", $reportPath)
  if ($reportResult.Code -eq 0 -and (Test-Path -LiteralPath $reportPath)) {
    Add-Check "runtime.report" "PASS" $reportPath
  } else {
    Add-Check "runtime.report" "WARN" ("win-miloco-workflow Report exit={0}" -f $reportResult.Code)
  }

  Write-Section "OpenClaw session probe"
  $gateway = Run-Text -FilePath "wsl.exe" -Arguments @("-d", $Distro, "--", "bash", "-lc", 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; openclaw gateway status 2>/dev/null || true')
  if ($gateway.Text -match "Connectivity probe[:= ]+(ok|passed)|connectivity.*ok|probe.*ok") {
    Add-Check "openclaw.gateway" "PASS" "Gateway connectivity probe ok."
  } elseif ($gateway.Code -eq 0 -and -not [string]::IsNullOrWhiteSpace($gateway.Text)) {
    Add-Check "openclaw.gateway" "WARN" "Gateway command returned, but probe was not ok."
  } else {
    Add-Check "openclaw.gateway" "WARN" "Gateway status not available."
  }

  $dashboard = Run-Text -FilePath "wsl.exe" -Arguments @("-d", $Distro, "--", "bash", "-lc", 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; openclaw dashboard --no-open --yes 2>/dev/null || true')
  if ($dashboard.Text -match "https?://[^\s""'<>]+") {
    Add-Check "openclaw.dashboard_url" "PASS" $Matches[0]
  } else {
    Add-Check "openclaw.dashboard_url" "WARN" "Dashboard direct URL not returned."
  }

  $token = Run-Text -FilePath "wsl.exe" -Arguments @("-d", $Distro, "--", "bash", "-lc", 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; openclaw config get gateway.auth.token 2>/dev/null || true')
  if (-not [string]::IsNullOrWhiteSpace($token.Text)) {
    Add-Check "openclaw.gateway_token" "PASS" "Gateway token is present."
  } else {
    Add-Check "openclaw.gateway_token" "WARN" "Gateway token is empty or unavailable."
  }

  $httpDashboard = Run-Text -FilePath "curl.exe" -Arguments @("-sS", "-o", "NUL", "-w", "%{http_code}", "--max-time", "5", ("http://127.0.0.1:{0}/" -f $OpenClawPort))
  if ($httpDashboard.Text -match "^[234][0-9][0-9]$") {
    Add-Check "openclaw.http_dashboard" "PASS" ("HTTP {0}" -f $httpDashboard.Text)
  } else {
    Add-Check "openclaw.http_dashboard" "WARN" ("HTTP probe result: {0}" -f $httpDashboard.Text)
  }

  $httpChat = Run-Text -FilePath "curl.exe" -Arguments @("-sS", "-o", "NUL", "-w", "%{http_code}", "--max-time", "5", ("http://127.0.0.1:{0}/chat?session=main" -f $OpenClawPort))
  if ($httpChat.Text -match "^[234][0-9][0-9]$") {
    Add-Check "openclaw.chat_route" "PASS" ("HTTP {0}" -f $httpChat.Text)
  } else {
    Add-Check "openclaw.chat_route" "WARN" ("HTTP probe result: {0}" -f $httpChat.Text)
  }
}

function Write-Summary {
  Write-Section "Summary"
  foreach ($check in $script:Checks) {
    $color = switch ($check.status) {
      "PASS" { "Green" }
      "WARN" { "Yellow" }
      "FAIL" { "Red" }
      default { "Gray" }
    }
    Write-Host ("[{0}] {1}" -f $check.status, $check.name) -ForegroundColor $color
    if (-not [string]::IsNullOrWhiteSpace($check.detail)) {
      Write-Host ("  {0}" -f $check.detail)
    }
  }

  $fails = @($script:Checks | Where-Object { $_.status -eq "FAIL" }).Count
  $warns = @($script:Checks | Where-Object { $_.status -eq "WARN" }).Count
  Write-Host ""
  Write-Host ("FAIL={0} WARN={1}" -f $fails, $warns)
  if ($fails -gt 0) {
    exit 1
  }
}

$root = ""
try {
  $root = Resolve-PackageRoot -InputPath $PackagePath
  Test-PackageStructure -Root $root
  if (-not $SkipInstallerSmoke) {
    Test-InstallerSmoke -Root $root
  }
  if (-not $SkipRuntime) {
    Test-RuntimeChecks -Root $root
  }
  Write-Summary
} finally {
  if (-not [string]::IsNullOrWhiteSpace($script:ExpandedTemp)) {
    Remove-Item -Recurse -Force -LiteralPath $script:ExpandedTemp -ErrorAction SilentlyContinue
  }
}
