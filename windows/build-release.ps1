param(
  [string]$Version = "v0.2",
  [string]$ArtifactVersion = "",
  [ValidateSet("stable", "preview")]
  [string]$Channel = "stable",
  [string]$BuildDistro = "Ubuntu-24.04",
  [switch]$SkipBuild,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$DistRoot = Join-Path $RepoRoot "dist"
$DistDir = Join-Path $DistRoot "windows"
$StageRoot = Join-Path $DistRoot "stage"
$ReleaseRawVersion = $Version.TrimStart("v")
if ([string]::IsNullOrWhiteSpace($ArtifactVersion)) {
  if ($ReleaseRawVersion -match "^\d{4}\.\d{1,2}\.\d{1,2}([-.][0-9A-Za-z.]+)?$") {
    $ArtifactVersion = $ReleaseRawVersion
  } else {
    $ArtifactVersion = Get-Date -Format "yyyy.M.d"
  }
}
$PackageName = "easy-miloco-$Version-windows"
$PackageRoot = Join-Path $StageRoot $PackageName
$ZipPath = Join-Path $DistDir "$PackageName.zip"
$ShaPath = "$ZipPath.sha256"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host ("== {0} ==" -f $Message) -ForegroundColor Cyan
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required file not found: $Path"
  }
}

function ConvertTo-WslPath {
  param([string]$WindowsPath)
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  if ($full -match "^([A-Za-z]):\\(.*)$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2].Replace("\", "/")
    return "/mnt/$drive/$rest"
  }
  throw "Only drive-letter Windows paths can be converted to WSL paths: $WindowsPath"
}

function Invoke-RepoBuild {
  if ($SkipBuild) {
    Write-Step "Skip build"
    return
  }

  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe not found. Run scripts/build.sh on Linux manually, then rerun with -SkipBuild."
  }

  Write-Step "Build upstream artifacts"
  $wslRepo = ConvertTo-WslPath $RepoRoot
  $tmpDir = Join-Path $RepoRoot ".codex\tmp"
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  $tmpScript = Join-Path $tmpDir "build-release-$ArtifactVersion.sh"
  $scriptLines = @(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    'export PATH="$HOME/.local/node-v26.3.1-linux-x64/bin:$HOME/.local/bin:$PATH"',
    "cd '$wslRepo'",
    "tr -d '\r' < scripts/build.sh > scripts/.build-release-build.sh",
    "chmod +x scripts/.build-release-build.sh",
    "trap 'rm -f scripts/.build-release-build.sh' EXIT",
    "bash scripts/.build-release-build.sh --version '$ArtifactVersion'"
  )
  [System.IO.File]::WriteAllText(
    $tmpScript,
    (($scriptLines -join "`n") + "`n"),
    [System.Text.Encoding]::ASCII
  )
  $wslScript = ConvertTo-WslPath $tmpScript
  try {
    & wsl.exe -d $BuildDistro -- bash $wslScript
    if ($LASTEXITCODE -ne 0) {
      throw "scripts/build.sh failed with exit code $LASTEXITCODE"
    }
  } finally {
    Remove-Item -Force -LiteralPath $tmpScript -ErrorAction SilentlyContinue
  }
}

function Copy-RequiredArtifacts {
  Write-Step "Prepare release package"
  Remove-Item -Recurse -Force -LiteralPath $PackageRoot -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $PackageRoot "payload") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $PackageRoot "scripts\windows") | Out-Null

  $distManifest = Join-Path $RepoRoot "dist\manifest.json"
  $installSh = Join-Path $RepoRoot "dist\install.sh"
  Require-File $distManifest
  Require-File $installSh

  $linuxBundle = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "dist") -Filter "miloco-linux-x86_64-*.tar.gz" | Select-Object -First 1
  if (-not $linuxBundle) {
    throw "dist/miloco-linux-x86_64-*.tar.gz not found. Build artifacts are incomplete."
  }

  Copy-Item -LiteralPath (Join-Path $RepoRoot "windows\package\install.ps1") -Destination (Join-Path $PackageRoot "install.ps1") -Force
  Copy-Item -LiteralPath $installSh -Destination (Join-Path $PackageRoot "payload\install.sh") -Force
  Copy-Item -LiteralPath $linuxBundle.FullName -Destination (Join-Path $PackageRoot "payload\$($linuxBundle.Name)") -Force

  $manifest = Get-Content -Encoding utf8 -LiteralPath $distManifest -Raw | ConvertFrom-Json
  $manifest | Add-Member -NotePropertyName package -NotePropertyValue @{
    name = $PackageName
    channel = $Channel
    repository = "https://github.com/andy-JustSayWhen/easy-miloco"
  } -Force
  $manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PackageRoot "manifest.json")

  Copy-Item -LiteralPath (Join-Path $RepoRoot "docs\scripts\win-miloco-workflow.ps1") -Destination (Join-Path $PackageRoot "scripts\windows\win-miloco-workflow.ps1") -Force
  Copy-Item -LiteralPath (Join-Path $RepoRoot "docs\scripts\windows-preflight.ps1") -Destination (Join-Path $PackageRoot "scripts\windows\windows-preflight.ps1") -Force
  Copy-Item -LiteralPath (Join-Path $RepoRoot "docs\scripts\wsl-miloco-validate.sh") -Destination (Join-Path $PackageRoot "scripts\windows\wsl-miloco-validate.sh") -Force
  Copy-Item -LiteralPath (Join-Path $RepoRoot "docs\scripts\wsl-post-auth-finish.sh") -Destination (Join-Path $PackageRoot "scripts\windows\wsl-post-auth-finish.sh") -Force

  Copy-Item -Recurse -LiteralPath (Join-Path $RepoRoot "docs") -Destination (Join-Path $PackageRoot "docs") -Force

  $packageReadme = @(
    "# easy-miloco $Version",
    "",
    "1. Extract this folder.",
    "2. Run ``install.ps1`` with PowerShell, or execute:",
    "",
    "``````powershell",
    "Set-ExecutionPolicy -Scope Process Bypass -Force",
    ".\install.ps1",
    "``````",
    "",
    "If Ubuntu WSL is not installed:",
    "",
    "``````powershell",
    ".\install.ps1 -InstallWsl",
    "``````",
    "",
    "GitHub Release is the version source of truth. Quark drive is only a mirror; verify the ``.sha256`` file after downloading a mirror copy."
  ) -join [Environment]::NewLine
  $packageReadme | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PackageRoot "README.md")

  $releaseNotes = @(
    "# easy-miloco $Version Release Notes",
    "",
    "## Scope",
    "",
    "- Windows one-click deployment package refresh.",
    "- Desktop console menu now exposes restart OpenClaw, restart Miloco, restart both, stop services, and stop WSL.",
    "- Includes root ``install.ps1``, Miloco Linux x86_64 local bundle, Windows diagnostics scripts, docs, and SHA256.",
    "- Target OS: Windows 11 22H2+.",
    "",
    "## Included",
    "",
    "- Camera LAN override protection: do not mark LAN online when the SDK LAN table has no hit.",
    "- docs/ knowledge base: install, cameras, FAQ, Windows runbooks, and sanitized sample-host case notes.",
    "- Release package layout: extract and run root ``install.ps1``.",
    "",
    "## Maintainer Note",
    "",
    "After publishing GitHub Release, manually upload the same zip, sha256, and release notes to the Quark drive mirror, then tell users to verify SHA256."
  ) -join [Environment]::NewLine
  $releaseNotes | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PackageRoot "release-notes.md")
}

function Write-Checksums {
  Write-Step "Write checksums"
  $files = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File
  $lines = foreach ($file in $files) {
    $rel = $file.FullName.Substring($PackageRoot.Length).TrimStart("\", "/")
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    "{0}  {1}" -f $hash, ($rel -replace "\\", "/")
  }
  $lines | Set-Content -Encoding ascii -LiteralPath (Join-Path $PackageRoot "SHA256SUMS.txt")
}

function Compress-Package {
  Write-Step "Compress package"
  New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
  Remove-Item -Force -LiteralPath $ZipPath, $ShaPath -ErrorAction SilentlyContinue
  Compress-Archive -LiteralPath $PackageRoot -DestinationPath $ZipPath -Force
  $zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToLowerInvariant()
  "$zipHash  $(Split-Path -Leaf $ZipPath)" | Set-Content -Encoding ascii -LiteralPath $ShaPath
}

function Test-Package {
  Write-Step "Self-test package"
  Require-File $ZipPath
  Require-File $ShaPath
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("easy-miloco-release-check-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmp -Force
    $root = Join-Path $tmp $PackageName
    Require-File (Join-Path $root "install.ps1")
    Require-File (Join-Path $root "manifest.json")
    Require-File (Join-Path $root "SHA256SUMS.txt")
    Require-File (Join-Path $root "payload\install.sh")
    Require-File (Join-Path $root "docs\AGENT.md")
    $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "install.ps1") -Raw))
    $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "scripts\windows\win-miloco-workflow.ps1") -Raw))
  } finally {
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
  }
}

if ($DryRun) {
  Write-Host "Would build package: $ZipPath"
  exit 0
}

Invoke-RepoBuild
Copy-RequiredArtifacts
Write-Checksums
Compress-Package
Test-Package

Write-Host ""
Write-Host "Release package ready:"
Write-Host "  $ZipPath"
Write-Host "  $ShaPath"
