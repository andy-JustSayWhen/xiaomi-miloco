param(
  [string]$ResourceGroup = "",
  [string]$VmName = "",
  [string]$VmUser = "",
  [string]$VmPassword = "",
  [string]$CredentialFile = "",
  [string]$Distro = "Ubuntu-24.04",
  [Parameter(Mandatory = $true)]
  [string]$ScriptPath,
  [string[]]$ScriptArgs = @(),
  [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Resolve-MaybeRelativePath {
  param([string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
  $candidate = Join-Path $repoRoot $Path
  if (Test-Path -LiteralPath $candidate) {
    return $candidate
  }
  return (Join-Path (Get-Location) $Path)
}

$userRunner = Join-Path $PSScriptRoot "azure-vm-user-powershell.ps1"
$scriptFull = Resolve-Path -LiteralPath (Resolve-MaybeRelativePath $ScriptPath)
$scriptB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($scriptFull))
$argsJson = ConvertTo-Json -Compress -InputObject @($ScriptArgs)
$argsB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($argsJson))
$safeDistro = $Distro.Replace("'", "''")

$remote = @"
`$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new(`$false) } catch {}
`$work = 'C:\easy-miloco-runcommand\wsl-script-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force -Path `$work | Out-Null
`$scriptPath = Join-Path `$work 'script.sh'
`$runnerPath = Join-Path `$work 'runner.sh'
`$outPath = Join-Path `$work 'output.txt'
[IO.File]::WriteAllBytes(`$scriptPath, [Convert]::FromBase64String('$scriptB64'))
`$argsJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$argsB64'))
`$scriptArgs = ConvertFrom-Json `$argsJson
if (`$null -eq `$scriptArgs) { `$scriptArgs = @() }
`$drive = `$scriptPath.Substring(0, 1).ToLowerInvariant()
`$rest = `$scriptPath.Substring(3).Replace('\', '/')
`$wslScript = '/mnt/' + `$drive + '/' + `$rest
`$quotedArgs = @()
foreach (`$arg in @(`$scriptArgs)) {
  `$quotedArgs += "'" + ([string]`$arg).Replace("'", "'\''") + "'"
}
`$runLine = 'tr -d "\015" < "' + `$wslScript + '" > "`$tmp"; bash "`$tmp" ' + (`$quotedArgs -join ' ')
`$runner = @(
  '#!/usr/bin/env bash',
  'set +e',
  'export PATH="`$HOME/.openclaw/bin:`$HOME/.local/bin:`$PATH"',
  'export MILOCO_PORT=18860',
  'tmp="/tmp/easy-miloco-vm-script-`$`$.sh"',
  `$runLine,
  'code=`$?',
  'rm -f "`$tmp"',
  'echo "EXIT_CODE=`$code"',
  'exit `$code'
) -join "`n"
[IO.File]::WriteAllText(`$runnerPath, `$runner + "`n", [Text.UTF8Encoding]::new(`$false))
`$drive2 = `$runnerPath.Substring(0, 1).ToLowerInvariant()
`$rest2 = `$runnerPath.Substring(3).Replace('\', '/')
`$wslRunner = '/mnt/' + `$drive2 + '/' + `$rest2
Write-Output ('WORK_DIR=' + `$work)
& wsl.exe -d '$safeDistro' -- bash `$wslRunner 2>&1 |
  Tee-Object -FilePath `$outPath
Write-Output ('POWERSHELL_LASTEXIT=' + `$LASTEXITCODE)
Write-Output ('OUTPUT_FILE=' + `$outPath)
exit `$LASTEXITCODE
"@

& $userRunner `
  -ResourceGroup $ResourceGroup `
  -VmName $VmName `
  -VmUser $VmUser `
  -VmPassword $VmPassword `
  -CredentialFile $CredentialFile `
  -Command $remote `
  -TimeoutSeconds $TimeoutSeconds
