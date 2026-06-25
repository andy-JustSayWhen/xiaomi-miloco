[CmdletBinding()]
param(
  [string]$Owner = "",
  [string]$Repo = "andy-JustSayWhen/easy-miloco",
  [string]$Tag = "v0.2",
  [string]$AssetPath = "dist/windows/easy-miloco-v0.2-windows.zip",
  [string]$ProxyUrl = "http://127.0.0.1:7897",
  [int]$UploadTimeoutSeconds = 240,
  [int]$MaxAttempts = 2,
  [switch]$Replace,
  [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if (-not [string]::IsNullOrWhiteSpace($Owner) -and $Repo -notmatch "/") {
  $Repo = ("{0}/{1}" -f $Owner.Trim(), $Repo.Trim())
}

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-RepoPath {
  param([string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) {
    return (Resolve-Path -LiteralPath $Path).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path (Get-RepoRoot) $Path)).Path
}

function Invoke-GhJson {
  param([string[]]$Arguments)
  $output = & gh @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw ("gh failed: gh {0}`n{1}" -f ($Arguments -join " "), ($output -join "`n"))
  }
  return (($output -join "`n") | ConvertFrom-Json)
}

function Invoke-GhWithTimeout {
  param(
    [string[]]$Arguments,
    [int]$TimeoutSeconds
  )

  $job = Start-Job -ScriptBlock {
    param([string[]]$GhArguments)
    $output = & gh @GhArguments 2>&1
    [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = ($output -join "`n")
    }
  } -ArgumentList (,$Arguments)

  $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
  if (-not $completed) {
    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    throw ("gh timed out after {0}s: gh {1}" -f $TimeoutSeconds, ($Arguments -join " "))
  }

  $result = Receive-Job -Job $job
  Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
  if ($result.ExitCode -ne 0) {
    throw ("gh failed with exit code {0}: gh {1}`n{2}" -f $result.ExitCode, ($Arguments -join " "), $result.Output)
  }
  return $result.Output
}

function Get-ReleaseAsset {
  param(
    [string]$RepoName,
    [string]$ReleaseTag,
    [string]$AssetName
  )
  $release = Invoke-GhJson @("release", "view", $ReleaseTag, "--repo", $RepoName, "--json", "assets,tagName,url")
  $asset = @($release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1)
  return [pscustomobject]@{
    Release = $release
    Asset = if ($asset.Count -gt 0) { $asset[0] } else { $null }
  }
}

function Test-ReleaseAssetMatches {
  param(
    [object]$Asset,
    [int64]$ExpectedSize,
    [string]$ExpectedSha256
  )
  if (-not $Asset) {
    return $false
  }
  if ([int64]$Asset.size -ne $ExpectedSize) {
    return $false
  }
  $digest = [string]$Asset.digest
  if ($digest -notmatch '^sha256:(.+)$') {
    return $false
  }
  return ($matches[1].ToLowerInvariant() -eq $ExpectedSha256)
}

$assetFullPath = Resolve-RepoPath $AssetPath
$assetName = Split-Path -Leaf $assetFullPath
$assetItem = Get-Item -LiteralPath $assetFullPath
$localSize = [int64]$assetItem.Length
$localSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assetFullPath).Hash.ToLowerInvariant()

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
  throw "GitHub CLI gh not found."
}

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  throw "gh auth status failed. Run gh auth login first."
}

if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
  $env:HTTPS_PROXY = $ProxyUrl
  $env:HTTP_PROXY = $ProxyUrl
}

Write-Host "Release asset target"
Write-Host ("  repo: {0}" -f $Repo)
Write-Host ("  tag: {0}" -f $Tag)
Write-Host ("  asset: {0}" -f $assetName)
Write-Host ("  local_size: {0}" -f $localSize)
Write-Host ("  local_sha256: {0}" -f $localSha256)

$current = Get-ReleaseAsset -RepoName $Repo -ReleaseTag $Tag -AssetName $assetName

if ($VerifyOnly) {
  if (-not $current.Asset) {
    throw "Release asset not found: $assetName"
  }
} else {
  if ($current.Asset -and -not $Replace) {
    throw "Release asset already exists. Re-run with -Replace to replace it through the fixed release publish path."
  }

  $uploadArgs = @("release", "upload", $Tag, $assetFullPath, "--repo", $Repo)
  if ($Replace) {
    $uploadArgs += "--clobber"
  }

  $attempt = 1
  while ($true) {
    try {
      Write-Host ("Uploading asset, attempt {0}/{1}..." -f $attempt, $MaxAttempts)
      Invoke-GhWithTimeout -Arguments $uploadArgs -TimeoutSeconds $UploadTimeoutSeconds | Write-Host
      break
    } catch {
      Write-Warning $_.Exception.Message
      try {
        $maybeUploaded = Get-ReleaseAsset -RepoName $Repo -ReleaseTag $Tag -AssetName $assetName
        if (Test-ReleaseAssetMatches -Asset $maybeUploaded.Asset -ExpectedSize $localSize -ExpectedSha256 $localSha256) {
          Write-Host "Upload command did not return cleanly, but remote asset already matches local file."
          break
        }
      } catch {
        Write-Warning ("Post-timeout asset verification failed: {0}" -f $_.Exception.Message)
      }
      if ($attempt -ge $MaxAttempts) {
        throw
      }
      Start-Sleep -Seconds ([Math]::Min(20 * $attempt, 60))
      $attempt += 1
    }
  }

  $current = Get-ReleaseAsset -RepoName $Repo -ReleaseTag $Tag -AssetName $assetName
  if (-not $current.Asset) {
    throw "Upload finished, but release asset was not found during verification."
  }
}

$remoteSize = [int64]$current.Asset.size
$remoteDigest = [string]$current.Asset.digest
if ($remoteSize -ne $localSize) {
  throw ("Release asset size mismatch. local={0}, remote={1}" -f $localSize, $remoteSize)
}

if ($remoteDigest -match '^sha256:(.+)$') {
  $remoteSha256 = $matches[1].ToLowerInvariant()
  if ($remoteSha256 -ne $localSha256) {
    throw ("Release asset digest mismatch. local={0}, remote={1}" -f $localSha256, $remoteSha256)
  }
} else {
  Write-Warning "GitHub did not return a sha256 digest; size verification passed."
}

Write-Host "Release asset verified"
Write-Host ("  url: {0}" -f $current.Asset.url)
Write-Host ("  remote_size: {0}" -f $remoteSize)
Write-Host ("  remote_digest: {0}" -f $remoteDigest)
Write-Host ("  updated_at: {0}" -f $current.Asset.updatedAt)
