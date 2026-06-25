param(
  [string]$ResourceGroup = "",
  [string]$VmName = "",
  [string]$VmUser = "",
  [string]$VmPassword = "",
  [string]$CredentialFile = "",
  [string]$ScriptPath = "",
  [string]$Command = "",
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-MaybeRelativePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ([IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  $candidate = Join-Path (Get-RepoRoot) $Path
  if (Test-Path -LiteralPath $candidate) {
    return $candidate
  }
  return (Join-Path (Get-Location) $Path)
}

function Read-KeyValueFile {
  param([string]$Path)
  $map = @{}
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $map
  }
  $resolved = Resolve-MaybeRelativePath $Path
  if (-not (Test-Path -LiteralPath $resolved)) {
    return $map
  }
  foreach ($line in Get-Content -LiteralPath $resolved -Encoding UTF8) {
    if ($line -match '^\s*([A-Za-z0-9_.-]+)\s*[:=]\s*(.+?)\s*$') {
      $map[$matches[1].ToUpperInvariant()] = $matches[2]
    }
  }
  return $map
}

if (-not [string]::IsNullOrWhiteSpace($CredentialFile)) {
  $cred = Read-KeyValueFile $CredentialFile
  if ([string]::IsNullOrWhiteSpace($ResourceGroup) -and $cred.ContainsKey("RESOURCE_GROUP")) {
    $ResourceGroup = $cred["RESOURCE_GROUP"]
  }
  if ([string]::IsNullOrWhiteSpace($VmName) -and $cred.ContainsKey("VM_NAME")) {
    $VmName = $cred["VM_NAME"]
  }
  if ([string]::IsNullOrWhiteSpace($VmUser) -and $cred.ContainsKey("VM_USER")) {
    $VmUser = $cred["VM_USER"]
  }
  if ([string]::IsNullOrWhiteSpace($VmPassword) -and $cred.ContainsKey("VM_PASSWORD")) {
    $VmPassword = $cred["VM_PASSWORD"]
  }
}

if ([string]::IsNullOrWhiteSpace($VmUser) -or [string]::IsNullOrWhiteSpace($VmPassword)) {
  throw "VmUser and VmPassword are required for scheduled user-context execution."
}
if ([string]::IsNullOrWhiteSpace($ScriptPath) -and [string]::IsNullOrWhiteSpace($Command)) {
  throw "Pass either -ScriptPath or -Command."
}

if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
  $resolvedScript = Resolve-Path -LiteralPath (Resolve-MaybeRelativePath $ScriptPath)
  $payload = Get-Content -LiteralPath $resolvedScript -Raw -Encoding UTF8
} else {
  $payload = $Command
}

$runCommand = Join-Path $PSScriptRoot "azure-vm-run-command.ps1"
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$remoteRoot = "C:\easy-miloco-runcommand\usercmd-$runId"
$remoteInner = "$remoteRoot\run-as-user.ps1"
$remoteOut = "$remoteRoot\stdout.txt"
$remoteDone = "$remoteRoot\done.txt"
$task = "EasyMilocoUserCommand"
$inner = @"
`$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new(`$false) } catch {}
try { Start-Transcript -LiteralPath '$remoteOut' -Force | Out-Null } catch {}
$payload
try { Stop-Transcript | Out-Null } catch {}
'done' | Set-Content -LiteralPath '$remoteDone' -Encoding UTF8
"@
$innerB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($inner))
$safeUser = $VmUser.Replace("'", "''")
$safePass = $VmPassword.Replace("'", "''")

$remote = @"
`$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new(`$false) } catch {}
`$user = '$safeUser'
`$pass = '$safePass'
`$root = '$remoteRoot'
`$inner = '$remoteInner'
`$out = '$remoteOut'
`$done = '$remoteDone'
`$task = '$task'
New-Item -ItemType Directory -Force -Path `$root | Out-Null
`$innerText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$innerB64'))
[IO.File]::WriteAllText(`$inner, `$innerText, [Text.UTF8Encoding]::new(`$true))
schtasks.exe /End /TN `$task 2>`$null | Out-Null
schtasks.exe /Delete /TN `$task /F 2>`$null | Out-Null
`$start = (Get-Date).AddMinutes(1).ToString("HH:mm")
`$tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + `$inner + '"'
`$create = & schtasks.exe /Create /TN `$task /TR `$tr /SC ONCE /ST `$start /RU `$user /RP `$pass /RL HIGHEST /F 2>&1
if (`$LASTEXITCODE -ne 0) {
  "schtasks create failed:"
  `$create
  exit 2
}
& schtasks.exe /Run /TN `$task | Out-Null
`$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt `$deadline -and -not (Test-Path -LiteralPath `$done)) {
  Start-Sleep -Seconds 5
}
if (Test-Path -LiteralPath `$out) {
  Get-Content -LiteralPath `$out -Encoding UTF8
} else {
  "missing output: `$out"
  schtasks.exe /Query /TN `$task /V /FO LIST 2>&1
  exit 124
}
"@

& $runCommand -ResourceGroup $ResourceGroup -VmName $VmName -CredentialFile $CredentialFile -Command $remote
