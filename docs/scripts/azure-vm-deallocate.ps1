param(
  [string]$ResourceGroup = "",
  [string]$VmName = "",
  [string]$CredentialFile = "",
  [string]$ProxyUrl = "http://127.0.0.1:7897"
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
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($VmName)) {
  throw "ResourceGroup and VmName are required."
}

if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
  $env:HTTPS_PROXY = $ProxyUrl
  $env:HTTP_PROXY = $ProxyUrl
}

az vm deallocate --resource-group $ResourceGroup --name $VmName --output none
$status = az vm get-instance-view --resource-group $ResourceGroup --name $VmName --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
"VM_STATUS=$status"
