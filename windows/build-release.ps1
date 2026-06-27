param(
  [string]$Version = "v0.2",
  [string]$ArtifactVersion = "",
  [ValidateSet("stable", "preview")]
  [string]$Channel = "stable",
  [string]$BuildDistro = "Ubuntu-24.04",
  [string]$ReusePayloadZip = "",
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
$script:ReusePayloadTemp = ""
$script:ReusePayloadRoot = ""

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

function Resolve-PathStrict {
  param([string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) {
    return (Resolve-Path -LiteralPath $Path).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $RepoRoot $Path)).Path
}

function Initialize-ReusedPayload {
  if ([string]::IsNullOrWhiteSpace($ReusePayloadZip)) {
    return
  }

  Write-Step "Reuse existing package payload"
  $sourceZip = Resolve-PathStrict $ReusePayloadZip
  Require-File $sourceZip

  $script:ReusePayloadTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("easy-miloco-payload-reuse-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $script:ReusePayloadTemp | Out-Null
  Expand-Archive -LiteralPath $sourceZip -DestinationPath $script:ReusePayloadTemp -Force

  $candidateRoots = @($script:ReusePayloadTemp)
  $candidateRoots += @(Get-ChildItem -LiteralPath $script:ReusePayloadTemp -Directory -Force | ForEach-Object { $_.FullName })
  $root = $candidateRoots | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_ "manifest.json")) -and
    (Test-Path -LiteralPath (Join-Path $_ "payload\install.sh")) -and
    (Get-ChildItem -LiteralPath (Join-Path $_ "payload") -Filter "miloco-linux-x86_64-*.tar.gz" -ErrorAction SilentlyContinue | Select-Object -First 1)
  } | Select-Object -First 1

  if (-not $root) {
    throw "Reusable payload not found in: $sourceZip"
  }

  $script:ReusePayloadRoot = $root
  Write-Host ("  source_zip: {0}" -f $sourceZip)
  Write-Host ("  payload_root: {0}" -f $script:ReusePayloadRoot)
}

function Clear-ReusedPayload {
  if (-not [string]::IsNullOrWhiteSpace($script:ReusePayloadTemp)) {
    Remove-Item -Recurse -Force -LiteralPath $script:ReusePayloadTemp -ErrorAction SilentlyContinue
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
  if (-not [string]::IsNullOrWhiteSpace($ReusePayloadZip)) {
    Write-Step "Skip build"
    Write-Host "Reusing payload from existing release zip; only Windows package files/docs will be refreshed."
    return
  }

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
  New-Item -ItemType Directory -Force -Path (Join-Path $PackageRoot "scripts\windows\models") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $PackageRoot "scripts\windows\templates") | Out-Null

  $payloadSourceRoot = if ([string]::IsNullOrWhiteSpace($script:ReusePayloadRoot)) { $RepoRoot } else { $script:ReusePayloadRoot }
  $payloadDistRoot = if ([string]::IsNullOrWhiteSpace($script:ReusePayloadRoot)) { Join-Path $RepoRoot "dist" } else { Join-Path $script:ReusePayloadRoot "payload" }
  $distManifest = if ([string]::IsNullOrWhiteSpace($script:ReusePayloadRoot)) { Join-Path $RepoRoot "dist\manifest.json" } else { Join-Path $payloadSourceRoot "manifest.json" }
  $installSh = if ([string]::IsNullOrWhiteSpace($script:ReusePayloadRoot)) { Join-Path $RepoRoot "dist\install.sh" } else { Join-Path $payloadDistRoot "install.sh" }
  Require-File $distManifest
  Require-File $installSh

  $linuxBundle = Get-ChildItem -LiteralPath $payloadDistRoot -Filter "miloco-linux-x86_64-*.tar.gz" | Select-Object -First 1
  if (-not $linuxBundle) {
    throw "miloco-linux-x86_64-*.tar.gz not found in payload source. Build artifacts are incomplete."
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
  Get-ChildItem -LiteralPath (Join-Path $RepoRoot "backend\miloco\src\miloco\perception\models") -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PackageRoot "scripts\windows\models\$($_.Name)") -Force
  }
  Copy-Utf8NoBomLfFile -Source (Join-Path $RepoRoot "windows\package\templates\install-launcher.bat.tpl") -Destination (Join-Path $PackageRoot "scripts\windows\templates\install-launcher.bat.tpl")
  Copy-Utf8BomFile -Source (Join-Path $RepoRoot "windows\package\templates\miloco-console.ps1.tpl") -Destination (Join-Path $PackageRoot "scripts\windows\templates\miloco-console.ps1.tpl")
  Copy-Utf8BomFile -Source (Join-Path $RepoRoot "windows\package\templates\openclaw-launcher.ps1.tpl") -Destination (Join-Path $PackageRoot "scripts\windows\templates\openclaw-launcher.ps1.tpl")
  
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
    "4. 安装向导会继续往下走；需要你处理时，会用中文说明下一步。",
    "5. 基础服务安装完成后，安装器会自动打开小米账号授权页；你登录授权后，把页面返回的授权码粘贴回安装窗口。",
    "6. 如果还没有自己的大模型 API，可以按安装器给出的 Xiaomi MIMO、Agnes、商汤科技链接申请；拿到 Key 后把 API Key、Base URL 和模型名粘贴回安装窗口，脚本会自动写入配置。",
    "",
    "## WSL / Ubuntu 说明",
    "",
    "已有可用 Ubuntu WSL2 时会复用；没有可用 Ubuntu 时，安装器会尝试安装 Ubuntu 24.04。",
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
    "## 维护者卸载测试",
    "",
    "普通用户通常不需要执行。维护者需要在同一台电脑反复验证安装包时，可在解压目录运行：",
    "",
    "``````powershell",
    ".\install.ps1 -Action Uninstall",
    "``````",
    "",
    "## 版本来源",
    "",
    "GitHub Release 是版本基准。夸克网盘只作为 GitHub 下载较慢时的人工同步副本。"
  ) -join [Environment]::NewLine
  $packageReadme | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PackageRoot "README.md")

  $releaseNotes = @(
    "# easy-miloco $Version Release Notes",
    "",
    "## Scope",
    "",
    "- Windows one-click deployment package refresh.",
    "- Desktop console menu now provides an explicit message-channel entry for Feishu, WeChat, and other channels.",
    "- Message-channel entry opens the shared OpenClaw setup guide or shows the one-sentence agent handoff prompt.",
    "- Desktop console menu still exposes restart OpenClaw, restart Miloco, restart both, stop services, and stop WSL.",
    "- Includes root ``install.bat`` and ``install.ps1``, Miloco Linux x86_64 local bundle, Windows diagnostics scripts, and docs.",
    "- Target OS: Windows 11 22H2+.",
    "",
    "## Included",
    "",
    "- Camera LAN override protection: do not mark LAN online when the SDK LAN table has no hit.",
    "- Camera unsupported-perception triage: distinguish denylist false blocks from LAN/PPCS/Wi-Fi/video-data-plane failures.",
    "- Camera denylist quick fix: includes Agent guide plus a double-click Windows wrapper for confirmed false-blocked camera models.",
    "- Verified camera model support updates for chuangmi.camera.021a04 and chuangmi.camera.036a02.",
    "- docs/: install, cameras, FAQ, Windows runbooks, and sanitized sample-host case notes.",
    "- Release package layout: extract and double-click root ``install.bat``.",
    "",
    "## Maintainer Note",
    "",
    "After publishing GitHub Release, manually upload the same zip and release notes to the Quark drive mirror."
  ) -join [Environment]::NewLine
  $releaseNotes | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PackageRoot "release-notes.md")
}

function Compress-Package {
  Write-Step "Compress package"
  New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
  Remove-Item -Force -LiteralPath $ZipPath -ErrorAction SilentlyContinue
  Compress-Archive -Path (Join-Path $PackageRoot "*") -DestinationPath $ZipPath -Force
}

function Test-Package {
  Write-Step "Self-test package"
  Require-File $ZipPath
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("easy-miloco-release-check-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmp -Force
    $root = $tmp
    Require-File (Join-Path $root "install.bat")
    Require-File (Join-Path $root "install.ps1")
    Require-File (Join-Path $root "manifest.json")
    Require-File (Join-Path $root "payload\install.sh")
    Require-File (Join-Path $root "docs\AGENT.md")
    Require-File (Join-Path $root "scripts\windows\models\det_4C.onnx")
    Require-File (Join-Path $root "scripts\windows\models\human_body_reid_v2.onnx")
    Require-File (Join-Path $root "scripts\windows\models\bge-small-zh-v1.5-int8.onnx")
    Require-File (Join-Path $root "scripts\windows\models\bge-small-zh-v1.5-tokenizer.json")
    Require-File (Join-Path $root "scripts\windows\models\silero_vad.onnx")
    Require-File (Join-Path $root "scripts\windows\templates\install-launcher.bat.tpl")
    Require-File (Join-Path $root "scripts\windows\templates\miloco-console.ps1.tpl")
    Require-File (Join-Path $root "scripts\windows\templates\openclaw-launcher.ps1.tpl")
    $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "install.ps1") -Raw))
    $null = [scriptblock]::Create((Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "scripts\windows\win-miloco-workflow.ps1") -Raw))

    $installBatBytes = [System.IO.File]::ReadAllBytes((Join-Path $root "install.bat"))
    if (@($installBatBytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
      throw "install.bat must be ASCII-only."
    }

    $launcherBatTemplate = Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "scripts\windows\templates\install-launcher.bat.tpl") -Raw
    if ([regex]::Matches($launcherBatTemplate, "[^\x00-\x7F]").Count -ne 0) {
      throw "Generated Miloco desktop launcher bat template must be ASCII-only."
    }

    $consolePs1 = Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "scripts\windows\templates\miloco-console.ps1.tpl") -Raw
    $consolePs1 = $consolePs1.Replace("__DISTRO__", "Ubuntu-24.04").Replace("__MILOCO_PORT__", "18860").Replace("__OPENCLAW_PORT__", "18789").Replace("__OPENCLAW_INFO_PATH__", "C:\OpenClaw-login-info.txt")
    $null = [scriptblock]::Create($consolePs1)

    $openClawPs1 = Get-Content -Encoding utf8 -LiteralPath (Join-Path $root "scripts\windows\templates\openclaw-launcher.ps1.tpl") -Raw
    $openClawPs1 = $openClawPs1.Replace("__DISTRO__", "Ubuntu-24.04").Replace("__OPENCLAW_PORT__", "18789").Replace("__OPENCLAW_INFO_PATH__", "C:\OpenClaw-login-info.txt")
    $null = [scriptblock]::Create($openClawPs1)

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

try {
  Initialize-ReusedPayload
  Invoke-RepoBuild
  Copy-RequiredArtifacts
  Compress-Package
  Test-Package
} finally {
  Clear-ReusedPayload
}

Write-Host ""
Write-Host "Release package ready:"
Write-Host "  $ZipPath"
