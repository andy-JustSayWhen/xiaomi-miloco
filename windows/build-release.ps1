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

function Copy-Utf8BomFile {
  param(
    [string]$Source,
    [string]$Destination
  )

  $text = [System.IO.File]::ReadAllText($Source, [System.Text.UTF8Encoding]::new($false, $true))
  [System.IO.File]::WriteAllText($Destination, $text, [System.Text.UTF8Encoding]::new($true))
}

function Copy-Utf8NoBomLfFile {
  param(
    [string]$Source,
    [string]$Destination
  )

  $text = [System.IO.File]::ReadAllText($Source, [System.Text.UTF8Encoding]::new($false, $true))
  $text = ($text -replace "`r`n", "`n") -replace "`r", "`n"
  [System.IO.File]::WriteAllText($Destination, $text, [System.Text.UTF8Encoding]::new($false))
}

function Normalize-ShellScripts {
  param([string]$Root)

  Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.sh" | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.UTF8Encoding]::new($false, $true))
    $text = ($text -replace "`r`n", "`n") -replace "`r", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $text, [System.Text.UTF8Encoding]::new($false))
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

  Copy-Item -LiteralPath (Join-Path $RepoRoot "windows\package\install.bat") -Destination (Join-Path $PackageRoot "install.bat") -Force
  Copy-Utf8BomFile -Source (Join-Path $RepoRoot "windows\package\install.ps1") -Destination (Join-Path $PackageRoot "install.ps1")
  $installShDst = Join-Path $PackageRoot "payload\install.sh"
  Copy-Utf8NoBomLfFile -Source $installSh -Destination $installShDst
  Copy-Item -LiteralPath $linuxBundle.FullName -Destination (Join-Path $PackageRoot "payload\$($linuxBundle.Name)") -Force

  $manifest = Get-Content -Encoding utf8 -LiteralPath $distManifest -Raw | ConvertFrom-Json
  $manifest | Add-Member -NotePropertyName package -NotePropertyValue @{
    name = $PackageName
    channel = $Channel
    repository = "https://github.com/andy-JustSayWhen/easy-miloco"
  } -Force
  $manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PackageRoot "manifest.json")

  Copy-Utf8BomFile -Source (Join-Path $RepoRoot "docs\scripts\win-miloco-workflow.ps1") -Destination (Join-Path $PackageRoot "scripts\windows\win-miloco-workflow.ps1")
  Copy-Utf8BomFile -Source (Join-Path $RepoRoot "docs\scripts\windows-preflight.ps1") -Destination (Join-Path $PackageRoot "scripts\windows\windows-preflight.ps1")
  
  $validateSrc = Join-Path $RepoRoot "docs\scripts\wsl-miloco-validate.sh"
  $validateDst = Join-Path $PackageRoot "scripts\windows\wsl-miloco-validate.sh"
  Copy-Utf8NoBomLfFile -Source $validateSrc -Destination $validateDst

  $finishSrc = Join-Path $RepoRoot "docs\scripts\wsl-post-auth-finish.sh"
  $finishDst = Join-Path $PackageRoot "scripts\windows\wsl-post-auth-finish.sh"
  Copy-Utf8NoBomLfFile -Source $finishSrc -Destination $finishDst

  Copy-Item -Recurse -LiteralPath (Join-Path $RepoRoot "docs") -Destination (Join-Path $PackageRoot "docs") -Force
  Normalize-ShellScripts -Root $PackageRoot

  $packageReadme = @(
    "# easy-miloco $Version",
    "",
    "## 用户安装方式",
    "",
    "1. 解压这个文件夹。",
    "2. 双击根目录里的 ``install.bat``。",
    "3. 如果 Windows 弹出管理员权限窗口，请选择同意。",
    "4. 安装向导会自动检查环境、自动安装能自动安装的依赖；需要你处理时，会用中文说明下一步。",
    "",
    "## WSL / Ubuntu 说明",
    "",
    "安装器不会把 Ubuntu-24.04 当成唯一可用名字。它会先检测已有 Ubuntu WSL2 的真实注册名和基础能力；只要 WSL version 2、glibc >= 2.28、CPU 架构是 x86_64/aarch64，并且 bash、curl、systemd user 命令可用，就会复用该发行版。",
    "",
    "Ubuntu 22.04 及以上推荐；Ubuntu 20.04 可以继续但会提示风险；没有任何可用 Ubuntu 时，安装器才会默认安装 Ubuntu-24.04。",
    "",
    "## 高级备用方式",
    "",
    "普通用户不需要运行下面的命令。只有在 bat 被安全软件拦截、或维护者要求你手动运行时，才打开管理员 PowerShell 执行：",
    "",
    "``````powershell",
    "Set-ExecutionPolicy -Scope Process Bypass -Force",
    ".\install.ps1",
    "``````",
    "",
    "## 下载校验",
    "",
    "GitHub Release 是版本基准。夸克网盘只是下载副本；从网盘下载后，请用同名 ``.sha256`` 文件核对。"
  ) -join [Environment]::NewLine
  $packageReadme | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PackageRoot "README.md")

  $releaseNotes = @(
    "# easy-miloco $Version Release Notes",
    "",
    "## Scope",
    "",
    "- Windows one-click deployment package refresh.",
    "- Desktop console menu now exposes restart OpenClaw, restart Miloco, restart both, stop services, and stop WSL.",
    "- Includes root ``install.bat`` and ``install.ps1``, Miloco Linux x86_64 local bundle, Windows diagnostics scripts, docs, and SHA256.",
    "- Target OS: Windows 11 22H2+.",
    "",
    "## Included",
    "",
    "- Camera LAN override protection: do not mark LAN online when the SDK LAN table has no hit.",
    "- docs/ knowledge base: install, cameras, FAQ, Windows runbooks, and sanitized sample-host case notes.",
    "- Release package layout: extract and double-click root ``install.bat``.",
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
    Require-File (Join-Path $root "install.bat")
    Require-File (Join-Path $root "install.ps1")
    Require-File (Join-Path $root "manifest.json")
    Require-File (Join-Path $root "SHA256SUMS.txt")
    Require-File (Join-Path $root "payload\install.sh")
    Require-File (Join-Path $root "docs\AGENT.md")
    $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "install.ps1") -Raw))
    $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "scripts\windows\win-miloco-workflow.ps1") -Raw))

    $installBatBytes = [System.IO.File]::ReadAllBytes((Join-Path $root "install.bat"))
    if (@($installBatBytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
      throw "install.bat must be ASCII-only."
    }

    $installPs1 = Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "install.ps1") -Raw
    $launcherBatMatch = [regex]::Match($installPs1, "(?s)\`$bat\s*=\s*@'\r?\n(?<bat>.*?)\r?\n'@")
    if (-not $launcherBatMatch.Success) {
      throw "Miloco desktop launcher bat template not found."
    }
    if ([regex]::Matches($launcherBatMatch.Groups["bat"].Value, "[^\x00-\x7F]").Count -ne 0) {
      throw "Generated Miloco desktop launcher bat template must be ASCII-only."
    }

    $consolePs1Match = [regex]::Match($installPs1, "(?s)\`$ps1\s*=\s*@'\r?\n(?<ps1>.*?)\r?\n'@")
    if (-not $consolePs1Match.Success) {
      throw "Miloco desktop console ps1 template not found."
    }
    $consolePs1 = $consolePs1Match.Groups["ps1"].Value.Replace("__DISTRO__", "Ubuntu-24.04").Replace("__MILOCO_PORT__", "1886").Replace("__OPENCLAW_PORT__", "18789")
    $null = [scriptblock]::Create($consolePs1)

    $shellScripts = Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.sh"
    foreach ($scriptPath in $shellScripts) {
      $bytes = [System.IO.File]::ReadAllBytes($scriptPath.FullName)
      for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
        if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) {
          throw "Shell script must use LF line endings: $($scriptPath.FullName)"
        }
      }
    }
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
