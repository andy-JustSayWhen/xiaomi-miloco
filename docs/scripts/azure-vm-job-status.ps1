param(
  [string]$ResourceGroup = "",
  [string]$VmName = "",
  [string]$CredentialFile = "",
  [Parameter(Mandatory = $true)]
  [string]$JobName,
  [int]$TailLines = 80
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if ($JobName -notmatch '^[A-Za-z0-9_.-]+$') {
  throw "JobName may only contain letters, numbers, dot, underscore, and dash."
}

$runCommand = Join-Path $PSScriptRoot "azure-vm-run-command.ps1"
$safeJobName = $JobName.Replace("'", "''")
$remote = @"
`$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new(`$false) } catch {}
`$jobName = '$safeJobName'
`$root = Join-Path 'C:\easy-miloco-runcommand' `$jobName
`$statusPath = Join-Path `$root 'status.json'
`$stdoutPath = Join-Path `$root 'stdout.txt'
if (Test-Path -LiteralPath `$statusPath) {
  Get-Content -LiteralPath `$statusPath -Encoding UTF8
} else {
  [pscustomobject]@{
    job = `$jobName
    state = 'missing'
    exit_code = -1
    message = 'status file not found'
    updated_at = (Get-Date).ToString('o')
    stdout = `$stdoutPath
  } | ConvertTo-Json -Depth 4
}
if (Test-Path -LiteralPath `$stdoutPath) {
  '--- stdout tail ---'
  Get-Content -LiteralPath `$stdoutPath -Encoding UTF8 -Tail $TailLines
} else {
  '--- stdout tail ---'
  'stdout not found'
}
"@

& $runCommand -ResourceGroup $ResourceGroup -VmName $VmName -CredentialFile $CredentialFile -Command $remote
