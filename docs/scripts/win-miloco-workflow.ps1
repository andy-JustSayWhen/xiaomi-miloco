param(
  [ValidateSet("Preflight", "Validate", "BindUrl", "Finish", "AllBasic", "Report")]
  [string]$Action = "AllBasic",
  [string]$Distro = "Ubuntu-24.04",
  [int]$MilocoPort = 1886,
  [int]$OpenClawPort = 18789,
  [string]$ProxyUrl = "http://127.0.0.1:7897",
  [string]$AuthPayload = "",
  [string]$MimoApiKey = "",
  [string]$OmniModel = "xiaomi/mimo-v2.5",
  [string]$OmniBaseUrl = "https://api.xiaomimimo.com/v1",
  [string]$HomeId = "",
  [string]$CameraDids = "",
  [string]$ReportPath = "",
  [switch]$StrictFull,
  [switch]$NoStrictFull,
  [switch]$Json,
  [switch]$ShowCommand
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WorkflowExitCode = 0

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host ("== {0} ==" -f $Message)
}

function ConvertTo-WslPath {
  param([string]$WindowsPath)
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  if ($full -match "^([A-Za-z]):\\(.*)$") {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2].Replace("\", "/")
    return "/mnt/$drive/$rest"
  } else {
    throw "Only drive-letter Windows paths can be converted to WSL paths: $WindowsPath"
  }
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required script not found: $Path"
  }
}

function Invoke-WindowsPreflight {
  $script = Join-Path $ScriptDir "windows-preflight.ps1"
  Require-File $script
  Write-Step "Windows preflight"
  $preflightParams = @{
    Distro = $Distro
    MilocoPort = $MilocoPort
    OpenClawPort = $OpenClawPort
    ProxyUrl = $ProxyUrl
  }
  if ($Json) { $preflightParams.Json = $true }
  & $script @preflightParams
  $script:WorkflowExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
}

function Invoke-WslScript {
  param(
    [string]$ScriptName,
    [string[]]$ExtraArgs = @(),
    [hashtable]$EnvVars = @()
  )

  $script = Join-Path $ScriptDir $ScriptName
  Require-File $script
  $wslScript = ConvertTo-WslPath $script

  $wslArgs = @("-d", $Distro, "--")
  if ($EnvVars.Count -gt 0) {
    $wslArgs += "env"
    foreach ($key in $EnvVars.Keys) {
      if (-not [string]::IsNullOrWhiteSpace([string]$EnvVars[$key])) {
        $wslArgs += ("{0}={1}" -f $key, $EnvVars[$key])
      }
    }
  }
  $wslArgs += @("bash", $wslScript)
  $wslArgs += $ExtraArgs

  if ($ShowCommand) {
    Write-Host ("wsl.exe {0}" -f ($wslArgs -join " "))
  }
  & wsl.exe @wslArgs
  $script:WorkflowExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
}

function Invoke-WslValidate {
  Write-Step "WSL Miloco validation"
  $extra = @()
  if ($StrictFull) { $extra += "--strict-full" }
  Invoke-WslScript -ScriptName "wsl-miloco-validate.sh" -ExtraArgs $extra -EnvVars @{
    MILOCO_PORT = [string]$MilocoPort
    OPENCLAW_PORT = [string]$OpenClawPort
  }
}

function Invoke-BindUrl {
  Write-Step "Generate Xiaomi OAuth bind URL"
  $extra = @("--print-bind-url")
  Invoke-WslScript -ScriptName "wsl-post-auth-finish.sh" -ExtraArgs $extra -EnvVars @{}
}

function Invoke-Finish {
  if ([string]::IsNullOrWhiteSpace($MimoApiKey)) {
    throw "Finish requires -MimoApiKey."
  }

  $extra = @()
  if ($NoStrictFull) {
    $extra += "--no-strict-full"
  }

  $envVars = @{
    MILOCO_PORT = [string]$MilocoPort
    OPENCLAW_PORT = [string]$OpenClawPort
    MIMO_API_KEY = $MimoApiKey
    OMNI_MODEL = $OmniModel
    OMNI_BASE_URL = $OmniBaseUrl
    MILOCO_AUTH_PAYLOAD = $AuthPayload
    MILOCO_HOME_ID = $HomeId
    MILOCO_CAMERA_DIDS = $CameraDids
  }

  Write-Step "Post-auth finish"
  Invoke-WslScript -ScriptName "wsl-post-auth-finish.sh" -ExtraArgs $extra -EnvVars $envVars
}

function Invoke-Report {
  $reportFile = $ReportPath
  if ([string]::IsNullOrWhiteSpace($reportFile)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportFile = Join-Path $env:TEMP "miloco-deploy-report-$stamp.txt"
  }

  $reportDir = Split-Path -Parent $reportFile
  if (-not [string]::IsNullOrWhiteSpace($reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
  }

  $powershellExe = Join-Path $PSHOME "powershell.exe"
  if (-not (Test-Path -LiteralPath $powershellExe)) {
    $powershellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  }

  $header = @(
    "Miloco Windows deployment report",
    ("GeneratedAt={0}" -f (Get-Date -Format "s")),
    ("Computer={0} User={1}" -f $env:COMPUTERNAME, $env:USERNAME),
    ("Distro={0} MilocoPort={1} OpenClawPort={2}" -f $Distro, $MilocoPort, $OpenClawPort),
    ""
  )
  $header | Set-Content -LiteralPath $reportFile -Encoding UTF8
  $header | ForEach-Object { Write-Host $_ }

  $preflightArgs = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $PSCommandPath,
    "-Action", "Preflight",
    "-Distro", $Distro,
    "-MilocoPort", [string]$MilocoPort,
    "-OpenClawPort", [string]$OpenClawPort,
    "-ProxyUrl", $ProxyUrl
  )
  if ($Json) { $preflightArgs += "-Json" }
  & $powershellExe @preflightArgs 2>&1 | ForEach-Object {
    $line = $_.ToString()
    Write-Host $line
    $line | Out-File -FilePath $reportFile -Encoding UTF8 -Append
  }
  $preflightCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

  $validateArgs = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $PSCommandPath,
    "-Action", "Validate",
    "-Distro", $Distro,
    "-MilocoPort", [string]$MilocoPort,
    "-OpenClawPort", [string]$OpenClawPort
  )
  if ($StrictFull) { $validateArgs += "-StrictFull" }
  & $powershellExe @validateArgs 2>&1 | ForEach-Object {
    $line = $_.ToString()
    Write-Host $line
    $line | Out-File -FilePath $reportFile -Encoding UTF8 -Append
  }
  $validateCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

  $summary = @(
    "",
    "== Report summary ==",
    ("PreflightExitCode={0}" -f $preflightCode),
    ("ValidateExitCode={0}" -f $validateCode),
    ("ReportPath={0}" -f $reportFile)
  )
  $summary | ForEach-Object {
    Write-Host $_
    $_ | Out-File -FilePath $reportFile -Encoding UTF8 -Append
  }

  if ($preflightCode -ne 0) {
    $script:WorkflowExitCode = $preflightCode
  } else {
    $script:WorkflowExitCode = $validateCode
  }

  Write-Host ("Report saved to: {0}" -f $reportFile)
}

try {
  switch ($Action) {
    "Preflight" {
      Invoke-WindowsPreflight
      exit $script:WorkflowExitCode
    }
    "Validate" {
      Invoke-WslValidate
      exit $script:WorkflowExitCode
    }
    "BindUrl" {
      Invoke-BindUrl
      exit $script:WorkflowExitCode
    }
    "Finish" {
      Invoke-Finish
      exit $script:WorkflowExitCode
    }
    "AllBasic" {
      Invoke-WindowsPreflight
      if ($script:WorkflowExitCode -ne 0) { exit $script:WorkflowExitCode }
      Invoke-WslValidate
      exit $script:WorkflowExitCode
    }
    "Report" {
      Invoke-Report
      exit $script:WorkflowExitCode
    }
  }
} catch {
  Write-Error $_.Exception.Message
  exit 2
}
