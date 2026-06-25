param(
  [string]$ResourceGroup = "",
  [string]$VmName = "",
  [string]$VmUser = "",
  [string]$VmPassword = "",
  [string]$CredentialFile = "",
  [string]$JobName = "",
  [Parameter(Mandatory = $true)]
  [string]$ScriptPath,
  [int]$PollSeconds = 45,
  [int]$TailLines = 180,
  [int]$StatusTimeoutSeconds = 120,
  [int]$StatusMaxFailures = 5,
  [switch]$NoStart,
  [switch]$NoDeallocate
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

function Write-Log {
  param([string]$Message)
  Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

if (-not [string]::IsNullOrWhiteSpace($CredentialFile)) {
  $cred = Read-KeyValueFile $CredentialFile
  if ([string]::IsNullOrWhiteSpace($ResourceGroup) -and $cred.ContainsKey("RESOURCE_GROUP")) { $ResourceGroup = $cred["RESOURCE_GROUP"] }
  if ([string]::IsNullOrWhiteSpace($VmName) -and $cred.ContainsKey("VM_NAME")) { $VmName = $cred["VM_NAME"] }
  if ([string]::IsNullOrWhiteSpace($VmUser) -and $cred.ContainsKey("VM_USER")) { $VmUser = $cred["VM_USER"] }
  if ([string]::IsNullOrWhiteSpace($VmPassword) -and $cred.ContainsKey("VM_PASSWORD")) { $VmPassword = $cred["VM_PASSWORD"] }
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($VmName)) {
  throw "ResourceGroup and VmName are required."
}
if ([string]::IsNullOrWhiteSpace($VmUser) -or [string]::IsNullOrWhiteSpace($VmPassword)) {
  throw "VmUser and VmPassword are required."
}
if ([string]::IsNullOrWhiteSpace($JobName)) {
  $JobName = "easy-miloco-" + (Get-Date -Format "yyyyMMdd-HHmmss")
}
if ($JobName -notmatch '^[A-Za-z0-9_.-]+$') {
  throw "JobName may only contain letters, numbers, dot, underscore, and dash."
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

$startJob = Join-Path $PSScriptRoot "azure-vm-start-user-job.ps1"
$jobStatus = Join-Path $PSScriptRoot "azure-vm-job-status.ps1"
$deallocate = Join-Path $PSScriptRoot "azure-vm-deallocate.ps1"
$resolvedScript = Resolve-MaybeRelativePath $ScriptPath
$startedAt = Get-Date
$lastOutput = ""
$exitCode = 1
$statusFailures = 0

try {
  if (-not $NoStart) {
    Write-Log ("Starting VM {0}/{1}" -f $ResourceGroup, $VmName)
    & $az.Source "vm" "start" "--resource-group" $ResourceGroup "--name" $VmName "--output" "none"
    if ($LASTEXITCODE -ne 0) {
      throw "az vm start failed with exit code $LASTEXITCODE"
    }
  }

  Write-Log ("Submitting job {0}" -f $JobName)
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startJob `
    -ResourceGroup $ResourceGroup `
    -VmName $VmName `
    -VmUser $VmUser `
    -VmPassword $VmPassword `
    -CredentialFile $CredentialFile `
    -JobName $JobName `
    -ScriptPath $resolvedScript
  if ($LASTEXITCODE -ne 0) {
    throw "azure-vm-start-user-job failed with exit code $LASTEXITCODE"
  }

  while ($true) {
    Start-Sleep -Seconds $PollSeconds
    $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
    Write-Log ("Polling job {0}, elapsed={1}s" -f $JobName, $elapsed)

    $tmpOut = Join-Path $env:TEMP ("easy-miloco-status-out-" + [guid]::NewGuid().ToString("N") + ".txt")
    $tmpErr = Join-Path $env:TEMP ("easy-miloco-status-err-" + [guid]::NewGuid().ToString("N") + ".txt")
    $statusCode = 1
    $oldPythonIoEncoding = $env:PYTHONIOENCODING
    $oldPythonUtf8 = $env:PYTHONUTF8
    try {
      $env:PYTHONIOENCODING = "utf-8"
      $env:PYTHONUTF8 = "1"
      $statusArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $jobStatus,
        "-ResourceGroup", $ResourceGroup,
        "-VmName", $VmName,
        "-CredentialFile", $CredentialFile,
        "-JobName", $JobName,
        "-TailLines", [string]$TailLines
      )
      $statusProcess = Start-Process -FilePath powershell.exe -ArgumentList $statusArgs -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -PassThru -WindowStyle Hidden
      if (-not $statusProcess.WaitForExit($StatusTimeoutSeconds * 1000)) {
        try { Stop-Process -Id $statusProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
        $statusCode = 124
        $lastOutput = "status query timed out after ${StatusTimeoutSeconds}s"
      } else {
        $statusCode = if ($null -eq $statusProcess.ExitCode) { 0 } else { [int]$statusProcess.ExitCode }
        $stdoutText = if (Test-Path -LiteralPath $tmpOut) { Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 } else { "" }
        $stderrText = if (Test-Path -LiteralPath $tmpErr) { Get-Content -LiteralPath $tmpErr -Raw -Encoding UTF8 } else { "" }
        $lastOutput = ($stdoutText, $stderrText | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
      }
    } finally {
      $env:PYTHONIOENCODING = $oldPythonIoEncoding
      $env:PYTHONUTF8 = $oldPythonUtf8
      Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
    }
    Write-Host $lastOutput
    if ($lastOutput -match 'RESULT=PASS') {
      $exitCode = 0
      break
    }
    if ($lastOutput -match 'RESULT=(UNINSTALL_FAILED|PREPARE_FAILED|VALIDATE_FAILED)') {
      $exitCode = 1
      break
    }
    $state = ""
    $match = [regex]::Match($lastOutput, '"state"\s*:\s*"([^"]+)"')
    if ($match.Success) { $state = $match.Groups[1].Value }
    $exitMatch = [regex]::Match($lastOutput, '"exit_code"\s*:\s*(-?\d+)')
    if ($exitMatch.Success) { $exitCode = [int]$exitMatch.Groups[1].Value }

    if ($statusCode -ne 0 -and [string]::IsNullOrWhiteSpace($state)) {
      $statusFailures += 1
      Write-Log ("Status query failed with exit code {0}; consecutive_failures={1}/{2}" -f $statusCode, $statusFailures, $StatusMaxFailures)
      if ($statusFailures -ge $StatusMaxFailures) {
        throw "azure-vm-job-status failed $statusFailures times in a row."
      }
      continue
    }
    $statusFailures = 0

    if ($state -eq "completed" -or $state -eq "failed") {
      break
    }
  }
} finally {
  if (-not $NoDeallocate) {
    Write-Log ("Deallocating VM {0}/{1}" -f $ResourceGroup, $VmName)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deallocate `
      -ResourceGroup $ResourceGroup `
      -VmName $VmName `
      -CredentialFile $CredentialFile
  }
}

if ($exitCode -ne 0) {
  throw "VM job $JobName failed with exit code $exitCode"
}
Write-Log ("VM job {0} completed successfully" -f $JobName)
