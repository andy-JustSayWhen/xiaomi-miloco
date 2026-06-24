param(
  [string]$Distro = "Ubuntu-24.04",
  [int]$MilocoPort = 1886,
  [int]$OpenClawPort = 18789,
  [string]$ProxyUrl = "http://127.0.0.1:7897",
  [switch]$Strict,
  [switch]$Json
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$Checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
  param(
    [string]$Name,
    [ValidateSet("PASS", "WARN", "FAIL", "INFO")]
    [string]$Status,
    [string]$Detail = "",
    [string]$Hint = ""
  )

  $Checks.Add([pscustomobject]@{
    name = $Name
    status = $Status
    detail = $Detail
    hint = $Hint
  }) | Out-Null
}

function Run-Text {
  param([string[]]$Command)
  try {
    $arguments = @($Command | Select-Object -Skip 1)
    $output = & $Command[0] @arguments 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_.Exception.Message
      } else {
        $_.ToString()
      }
    }
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return [pscustomobject]@{
      ok = ($code -eq 0)
      code = $code
      text = (($output | Out-String).Trim())
    }
  } catch {
    return [pscustomobject]@{
      ok = $false
      code = -1
      text = $_.Exception.Message
    }
  }
}

function Write-WrappedText {
  param(
    [string]$Text,
    [string]$Indent = "    ",
    [int]$Width = 96,
    [int]$MaxLines = 24
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return
  }

  $logicalLines = @(
    ($Text -replace "`r", "") -split "`n" |
      ForEach-Object { ($_ -replace "\s+", " ").Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  $shown = 0
  foreach ($line in $logicalLines) {
    if ($shown -ge $MaxLines) {
      break
    }
    $remaining = $line
    while ($remaining.Length -gt $Width) {
      $cut = $remaining.LastIndexOf(" ", [Math]::Min($Width, $remaining.Length - 1))
      if ($cut -lt 24) { $cut = [Math]::Min($Width, $remaining.Length) }
      Write-Host ($Indent + $remaining.Substring(0, $cut).Trim())
      $remaining = $remaining.Substring($cut).Trim()
    }
    if ($remaining.Length -gt 0) {
      Write-Host ($Indent + $remaining)
    }
    $shown += 1
  }
  if ($logicalLines.Count -gt $MaxLines) {
    Write-Host ($Indent + "... ($($logicalLines.Count - $MaxLines) line(s) omitted)")
  }
}

function Write-CheckField {
  param(
    [string]$Label,
    [string]$Text,
    [int]$MaxLines = 24
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return
  }

  Write-Host ("  {0}:" -f $Label)
  Write-WrappedText -Text $Text -Indent "    " -MaxLines $MaxLines
}

function Test-PortExcluded {
  param([int]$Port)

  $result = Run-Text @("netsh.exe", "interface", "ipv4", "show", "excludedportrange", "protocol=tcp")
  if (-not $result.ok -or [string]::IsNullOrWhiteSpace($result.text)) {
    Add-Check "windows.excluded_port_range" "WARN" $result.text "Could not read excluded TCP ranges."
    return
  }

  $matched = @()
  foreach ($line in ($result.text -split "`r?`n")) {
    if ($line -match "^\s*(\d+)\s+(\d+)\s*$") {
      $start = [int]$Matches[1]
      $end = [int]$Matches[2]
      if ($Port -ge $start -and $Port -le $end) {
        $matched += "$start-$end"
      }
    }
  }

  if ($matched.Count -gt 0) {
    Add-Check "windows.port.$Port" "WARN" "Port $Port is in excluded range(s): $($matched -join ', ')." "Use another Miloco port and set server.url."
  } else {
    Add-Check "windows.port.$Port" "PASS" "Port $Port is not in Windows excluded TCP ranges."
  }
}

function Test-Http {
  param(
    [string]$Name,
    [string]$Url,
    [string]$Expected = ""
  )

  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) {
    Add-Check $Name "WARN" "curl.exe not found." "Install or enable Windows curl.exe for endpoint checks."
    return $false
  }

  $result = Run-Text @("curl.exe", "-fsS", "--max-time", "8", $Url)
  if ($result.ok -and ($Expected -eq "" -or $result.text -match [regex]::Escape($Expected))) {
    if ($Expected -eq "") {
      Add-Check $Name "PASS" "HTTP response ok ($($result.text.Length) chars)."
    } elseif ($result.text.Length -gt 500) {
      Add-Check $Name "PASS" ($result.text.Substring(0, 500) + "...")
    } else {
      Add-Check $Name "PASS" $result.text
    }
    return $true
  }

  Add-Check $Name "WARN" $result.text "This is expected before services are installed or started."
  return $false
}

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os) {
  Add-Check "windows.os" "INFO" "$($os.Caption) $($os.Version), build $($os.BuildNumber), arch=$env:PROCESSOR_ARCHITECTURE, user=$env:USERNAME"
}

if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
  Add-Check "windows.wsl_command" "PASS" "wsl.exe is available."
  $wslList = Run-Text @("wsl.exe", "-l", "-v")
  if ($wslList.ok) {
    $plain = $wslList.text -replace "`0", ""
    if ($plain -match [regex]::Escape($Distro)) {
      if ($plain -match ([regex]::Escape($Distro) + "\s+\S+\s+2")) {
        Add-Check "windows.wsl_distro" "PASS" "$Distro exists and is WSL2."
      } else {
        Add-Check "windows.wsl_distro" "WARN" "$Distro exists but WSL2 was not confirmed. Raw: $plain" "Run: wsl --set-version $Distro 2"
      }
    } else {
      Add-Check "windows.wsl_distro" "WARN" "$Distro not found. Raw: $plain" "Install it with: wsl --install -d $Distro"
    }
  } else {
    Add-Check "windows.wsl_list" "WARN" $wslList.text "Run wsl.exe manually to see the local error."
  }
} else {
  Add-Check "windows.wsl_command" "FAIL" "wsl.exe is not available." "Enable WSL and Virtual Machine Platform."
}

$wslConfig = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path -LiteralPath $wslConfig) {
  $content = Get-Content -LiteralPath $wslConfig -Raw -ErrorAction SilentlyContinue
  if ($content -match "(?im)^\s*networkingMode\s*=\s*mirrored\s*$") {
    Add-Check "windows.wslconfig.mirrored" "PASS" "$wslConfig contains networkingMode=mirrored."
  } else {
    Add-Check "windows.wslconfig.mirrored" "WARN" "$wslConfig exists but mirrored networking was not found." "Add [wsl2] networkingMode=mirrored, then run wsl --shutdown."
  }
} else {
  Add-Check "windows.wslconfig.mirrored" "WARN" "$wslConfig not found." "Create it if camera/LAN streaming must work from WSL."
}

Test-PortExcluded -Port $MilocoPort

$hvCmd = Get-Command Get-NetFirewallHyperVVMSetting -ErrorAction SilentlyContinue
if ($hvCmd) {
  try {
    $settings = Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -ErrorAction Stop
    $deny = @($settings | Where-Object { $_.DefaultInboundAction -ne 1 -and $_.DefaultInboundAction -ne "Allow" })
    if ($deny.Count -eq 0) {
      Add-Check "windows.hyperv_firewall" "PASS" "All visible Hyper-V VM firewall settings allow inbound by default."
    } else {
      Add-Check "windows.hyperv_firewall" "WARN" (($deny | Select-Object -First 5 | Format-Table -AutoSize | Out-String).Trim()) "Run an elevated PowerShell check and allow inbound for WSL if needed."
    }
  } catch {
    Add-Check "windows.hyperv_firewall" "WARN" $_.Exception.Message "Run from an elevated PowerShell session for a definitive check."
  }
} else {
  Add-Check "windows.hyperv_firewall" "INFO" "Get-NetFirewallHyperVVMSetting is not available on this Windows build."
}

if (Get-Command ssh.exe -ErrorAction SilentlyContinue) {
  Add-Check "windows.ssh_client" "PASS" "ssh.exe is available."
} else {
  Add-Check "windows.ssh_client" "WARN" "ssh.exe not found." "Install OpenSSH Client if remote Agent deployment is required."
}

if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
  try {
    $proxyUri = [Uri]$ProxyUrl
    $proxyOk = Test-NetConnection -ComputerName $proxyUri.Host -Port $proxyUri.Port -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($proxyOk) {
      Add-Check "windows.proxy" "PASS" "$ProxyUrl is reachable."
    } else {
      Add-Check "windows.proxy" "INFO" "$ProxyUrl is not reachable." "Only required when GitHub or Python package downloads need a local proxy."
    }
  } catch {
    Add-Check "windows.proxy" "INFO" "ProxyUrl could not be parsed: $ProxyUrl"
  }
}

$milocoOk = Test-Http -Name "windows.miloco_health" -Url "http://127.0.0.1:$MilocoPort/health" -Expected '"status":"ok"'
$openclawOk = Test-Http -Name "windows.openclaw_gateway" -Url "http://127.0.0.1:$OpenClawPort/"

$basicReady = ($milocoOk -and $openclawOk)

$summary = [pscustomobject]@{
  generated_at = (Get-Date).ToString("s")
  distro = $Distro
  miloco_port = $MilocoPort
  openclaw_port = $OpenClawPort
  basic_ready_from_windows = $basicReady
  fail_count = @($Checks | Where-Object status -eq "FAIL").Count
  warn_count = @($Checks | Where-Object status -eq "WARN").Count
  checks = $Checks
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 6
} else {
  Write-Host "== Windows Miloco preflight =="
  foreach ($check in $Checks) {
    Write-Host ("[{0}] {1}" -f $check.status, $check.name)
    Write-CheckField -Label "detail" -Text $check.detail
    Write-CheckField -Label "hint" -Text $check.hint -MaxLines 8
  }
  Write-Host ("BASIC_READY_FROM_WINDOWS={0}" -f ($(if ($basicReady) { "yes" } else { "no" })))
  Write-Host ("FAIL_COUNT={0}" -f $summary.fail_count)
  Write-Host ("WARN_COUNT={0}" -f $summary.warn_count)
}

if ($Strict -and $summary.fail_count -gt 0) {
  exit 2
}

exit 0
