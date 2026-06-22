param(
  [ValidateSet("Prepare", "Report", "BindUrl", "Finish", "Validate")]
  [string]$Action = "Prepare",
  [string]$Distro = "Ubuntu-24.04",
  [int]$MilocoPort = 1886,
  [int]$OpenClawPort = 18789,
  [string]$AuthPayload = "",
  [string]$MimoApiKey = "",
  [string]$OmniModel = "xiaomi/mimo-v2.5",
  [string]$OmniBaseUrl = "https://api.xiaomimimo.com/v1",
  [string]$HomeId = "",
  [string]$CameraDids = "",
  [switch]$InstallWsl
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestPath = Join-Path $PackageRoot "manifest.json"
$PayloadDir = Join-Path $PackageRoot "payload"
$WindowsScriptsDir = Join-Path $PackageRoot "scripts\windows"
$Workflow = Join-Path $WindowsScriptsDir "win-miloco-workflow.ps1"
$InstallSh = Join-Path $PayloadDir "install.sh"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host ("== {0} ==" -f $Message) -ForegroundColor Cyan
}

function Fail {
  param([string]$Message)
  Write-Host ("[FAIL] {0}" -f $Message) -ForegroundColor Red
  exit 1
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    Fail "Required file not found: $Path"
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

function Ensure-Wsl {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "wsl.exe not found. Enable WSL first, then rerun install.ps1."
  }

  $list = (& wsl.exe -l -v 2>&1 | Out-String) -replace "`0", ""
  if ($list -match [regex]::Escape($Distro)) {
    return
  }

  if ($InstallWsl) {
    Write-Step "Install WSL distro"
    & wsl.exe --install -d $Distro
    Write-Host "If Windows asks for restart or first-time Ubuntu user setup, finish that first, then rerun install.ps1."
    exit $LASTEXITCODE
  }

  Fail "$Distro not found. Rerun with -InstallWsl, or install it manually with: wsl --install -d $Distro"
}

function Invoke-WslBash {
  param([string]$Script)

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Script)
  $b64 = [Convert]::ToBase64String($bytes)
  & wsl.exe -d $Distro -- bash -lc "echo '$b64' | base64 -d | bash"
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

function Get-PowerShellExe {
  $candidate = Join-Path $PSHOME "powershell.exe"
  if (Test-Path -LiteralPath $candidate) { return $candidate }
  $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if ($pwsh) { return $pwsh.Source }
  return "powershell.exe"
}

function Invoke-Workflow {
  param([string]$WorkflowAction)

  Require-File $Workflow
  $args = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $Workflow,
    "-Action", $WorkflowAction,
    "-Distro", $Distro,
    "-MilocoPort", [string]$MilocoPort,
    "-OpenClawPort", [string]$OpenClawPort
  )

  if ($WorkflowAction -eq "Finish") {
    $args += @(
      "-AuthPayload", $AuthPayload,
      "-MimoApiKey", $MimoApiKey,
      "-OmniModel", $OmniModel,
      "-OmniBaseUrl", $OmniBaseUrl,
      "-HomeId", $HomeId,
      "-CameraDids", $CameraDids
    )
  }

  $powershellExe = Get-PowerShellExe
  & $powershellExe @args
  exit $LASTEXITCODE
}

function Invoke-Prepare {
  Require-File $ManifestPath
  Require-File $InstallSh
  Ensure-Wsl

  $manifest = Get-Content -Encoding utf8 -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  $version = [string]$manifest.version
  if ([string]::IsNullOrWhiteSpace($version)) {
    Fail "manifest.json missing version."
  }

  $bundle = Get-ChildItem -LiteralPath $PayloadDir -Filter "miloco-linux-x86_64-*.tar.gz" | Select-Object -First 1
  if (-not $bundle) {
    Fail "payload/miloco-linux-x86_64-*.tar.gz not found. Rebuild the release package."
  }

  $wslBundle = ConvertTo-WslPath $bundle.FullName
  $wslInstallSh = ConvertTo-WslPath $InstallSh

  Write-Step "Prime local Miloco bundle in WSL"
  $prime = @"
set -euo pipefail
export MILOCO_HOME="\${MILOCO_HOME:-\$HOME/.openclaw/miloco}"
cache="\$MILOCO_HOME/.install-cache/$version"
mkdir -p "\$cache"
if ! ls "\$cache"/miloco-*.whl >/dev/null 2>&1 || ! ls "\$cache"/miloco_cli-*.whl >/dev/null 2>&1 || ! ls "\$cache"/*.tgz >/dev/null 2>&1; then
  rm -rf "\$cache"
  mkdir -p "\$cache"
  tar -xzf "$wslBundle" -C "\$cache"
fi
"@
  Invoke-WslBash $prime

  Write-Step "Install Miloco in WSL"
  $install = @"
set -euo pipefail
export PATH="\$HOME/.local/bin:\$PATH"
bash "$wslInstallSh" --agent-prepare
miloco-cli service start || true
"@
  Invoke-WslBash $install

  Write-Step "Generate deployment report"
  $powershellExe = Get-PowerShellExe
  & $powershellExe -ExecutionPolicy Bypass -File $Workflow -Action Report -Distro $Distro -MilocoPort $MilocoPort -OpenClawPort $OpenClawPort
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

  Write-Host ""
  Write-Host "Next steps:"
  Write-Host "1. Run: .\install.ps1 -Action BindUrl"
  Write-Host "2. Complete Xiaomi OAuth in the browser."
  Write-Host "3. Run: .\install.ps1 -Action Finish -AuthPayload '<payload>' -MimoApiKey '<key>'"
  exit $code
}

switch ($Action) {
  "Prepare" { Invoke-Prepare }
  "Report" { Invoke-Workflow "Report" }
  "BindUrl" { Invoke-Workflow "BindUrl" }
  "Finish" { Invoke-Workflow "Finish" }
  "Validate" { Invoke-Workflow "Validate" }
}
