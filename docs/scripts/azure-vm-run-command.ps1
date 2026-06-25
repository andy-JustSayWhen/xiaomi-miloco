param(
  [string]$ResourceGroup = "",
  [string]$VmName = "",
  [string]$CredentialFile = "",
  [string]$ScriptPath = "",
  [string]$Command = "",
  [switch]$AsJson
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
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($VmName)) {
  throw "ResourceGroup and VmName are required. Pass parameters or provide a credential file."
}
if ([string]::IsNullOrWhiteSpace($ScriptPath) -and [string]::IsNullOrWhiteSpace($Command)) {
  throw "Pass either -ScriptPath or -Command."
}

$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) {
  $defaultAz = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
  if (Test-Path -LiteralPath $defaultAz) {
    $az = [pscustomobject]@{ Source = $defaultAz }
  }
}
if (-not $az) {
  throw "Azure CLI not found. Install Azure CLI, then run az login."
}

if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
  $resolvedScript = Resolve-Path -LiteralPath (Resolve-MaybeRelativePath $ScriptPath)
  $scriptText = Get-Content -LiteralPath $resolvedScript -Raw -Encoding UTF8
} else {
  $scriptText = $Command
}

$tmp = Join-Path $env:TEMP ("easy-miloco-runcommand-" + [guid]::NewGuid().ToString("N") + ".ps1")
try {
  [IO.File]::WriteAllText($tmp, $scriptText, [Text.UTF8Encoding]::new($true))
  $args = @(
    "vm", "run-command", "invoke",
    "--resource-group", $ResourceGroup,
    "--name", $VmName,
    "--command-id", "RunPowerShellScript",
    "--scripts", "@$tmp"
  )
  if ($AsJson) {
    $args += @("--output", "json")
  } else {
    $args += @("--query", "value[0].message", "--output", "tsv")
  }
  & $az.Source @args
  exit $LASTEXITCODE
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
