param(
  [string]$ResourceGroup = "",
  [string]$VmName = "",
  [string]$VmUser = "",
  [string]$VmPassword = "",
  [string]$CredentialFile = "",
  [string]$JobName = "",
  [string]$ScriptPath = "",
  [string]$Command = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-MaybeRelativePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  if ([IO.Path]::IsPathRooted($Path)) { return $Path }
  $candidate = Join-Path (Get-RepoRoot) $Path
  if (Test-Path -LiteralPath $candidate) { return $candidate }
  return (Join-Path (Get-Location) $Path)
}

function Read-KeyValueFile {
  param([string]$Path)
  $map = @{}
  if ([string]::IsNullOrWhiteSpace($Path)) { return $map }
  $resolved = Resolve-MaybeRelativePath $Path
  if (-not (Test-Path -LiteralPath $resolved)) { return $map }
  foreach ($line in Get-Content -LiteralPath $resolved -Encoding UTF8) {
    if ($line -match '^\s*([A-Za-z0-9_.-]+)\s*[:=]\s*(.+?)\s*$') {
      $map[$matches[1].ToUpperInvariant()] = $matches[2]
    }
  }
  return $map
}

if (-not [string]::IsNullOrWhiteSpace($CredentialFile)) {
  $cred = Read-KeyValueFile $CredentialFile
  if ([string]::IsNullOrWhiteSpace($ResourceGroup) -and $cred.ContainsKey("RESOURCE_GROUP")) { $ResourceGroup = $cred["RESOURCE_GROUP"] }
  if ([string]::IsNullOrWhiteSpace($VmName) -and $cred.ContainsKey("VM_NAME")) { $VmName = $cred["VM_NAME"] }
  if ([string]::IsNullOrWhiteSpace($VmUser) -and $cred.ContainsKey("VM_USER")) { $VmUser = $cred["VM_USER"] }
  if ([string]::IsNullOrWhiteSpace($VmPassword) -and $cred.ContainsKey("VM_PASSWORD")) { $VmPassword = $cred["VM_PASSWORD"] }
}

if ([string]::IsNullOrWhiteSpace($VmUser) -or [string]::IsNullOrWhiteSpace($VmPassword)) {
  throw "VmUser and VmPassword are required."
}
if ([string]::IsNullOrWhiteSpace($ScriptPath) -and [string]::IsNullOrWhiteSpace($Command)) {
  throw "Pass either -ScriptPath or -Command."
}
if ([string]::IsNullOrWhiteSpace($JobName)) {
  $JobName = "easy-miloco-" + (Get-Date -Format "yyyyMMdd-HHmmss")
}
if ($JobName -notmatch '^[A-Za-z0-9_.-]+$') {
  throw "JobName may only contain letters, numbers, dot, underscore, and dash."
}

if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
  $resolvedScript = Resolve-Path -LiteralPath (Resolve-MaybeRelativePath $ScriptPath)
  $payload = Get-Content -LiteralPath $resolvedScript -Raw -Encoding UTF8
} else {
  $payload = $Command
}

$runCommand = Join-Path $PSScriptRoot "azure-vm-run-command.ps1"
$payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$safeUser = $VmUser.Replace("'", "''")
$safePass = $VmPassword.Replace("'", "''")
$safeJobName = $JobName.Replace("'", "''")

$remote = @"
`$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new(`$false) } catch {}
`$user = '$safeUser'
`$pass = '$safePass'
`$jobName = '$safeJobName'
`$root = Join-Path 'C:\easy-miloco-runcommand' `$jobName
`$runner = Join-Path `$root 'runner.ps1'
`$payloadPath = Join-Path `$root 'payload.ps1'
`$statusPath = Join-Path `$root 'status.json'
`$stdoutPath = Join-Path `$root 'stdout.txt'
`$task = 'EasyMilocoJob-' + `$jobName
New-Item -ItemType Directory -Force -Path `$root | Out-Null
`$payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payloadB64'))
[IO.File]::WriteAllText(`$payloadPath, `$payload, [Text.UTF8Encoding]::new(`$true))
`$runnerText = @'
param(
  [string]$JobName,
  [string]$PayloadPath,
  [string]$StatusPath,
  [string]$StdoutPath
)
`$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new(`$false) } catch {}
function Write-Status {
  param([string]`$State, [int]`$ExitCode = -1, [string]`$Message = "")
  [pscustomobject]@{
    job = `$JobName
    state = `$State
    exit_code = `$ExitCode
    message = `$Message
    updated_at = (Get-Date).ToString("o")
    stdout = `$StdoutPath
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath `$StatusPath -Encoding UTF8
}
Write-Status -State "running" -Message "started"
try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$PayloadPath *> `$StdoutPath
  `$code = if (`$null -eq `$LASTEXITCODE) { 0 } else { `$LASTEXITCODE }
  if (`$code -eq 0) {
    Write-Status -State "completed" -ExitCode `$code -Message "completed"
  } else {
    Write-Status -State "failed" -ExitCode `$code -Message "failed"
  }
  exit `$code
} catch {
  `$message = `$_.Exception.Message
  Add-Content -LiteralPath `$StdoutPath -Encoding UTF8 -Value ("ERROR: " + `$message)
  Write-Status -State "failed" -ExitCode 1 -Message `$message
  exit 1
}
'@
[IO.File]::WriteAllText(`$runner, `$runnerText, [Text.UTF8Encoding]::new(`$true))
[pscustomobject]@{
  job = `$jobName
  state = 'queued'
  exit_code = -1
  message = 'scheduled'
  updated_at = (Get-Date).ToString('o')
  stdout = `$stdoutPath
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath `$statusPath -Encoding UTF8
schtasks.exe /End /TN `$task 2>`$null | Out-Null
schtasks.exe /Delete /TN `$task /F 2>`$null | Out-Null
`$start = (Get-Date).AddMinutes(1).ToString("HH:mm")
`$tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + `$runner + '" -JobName "' + `$jobName + '" -PayloadPath "' + `$payloadPath + '" -StatusPath "' + `$statusPath + '" -StdoutPath "' + `$stdoutPath + '"'
`$create = & schtasks.exe /Create /TN `$task /TR `$tr /SC ONCE /ST `$start /RU `$user /RP `$pass /RL HIGHEST /F 2>&1
if (`$LASTEXITCODE -ne 0) {
  "schtasks create failed:"
  `$create
  exit 2
}
& schtasks.exe /Run /TN `$task | Out-Null
[pscustomobject]@{
  job = `$jobName
  root = `$root
  status = `$statusPath
  stdout = `$stdoutPath
  task = `$task
} | ConvertTo-Json -Depth 4
"@

& $runCommand -ResourceGroup $ResourceGroup -VmName $VmName -CredentialFile $CredentialFile -Command $remote
