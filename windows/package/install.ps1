param(
  [ValidateSet("Prepare", "Report", "BindUrl", "Finish", "Validate", "Uninstall")]
  [string]$Action = "Prepare",
  [string]$Distro = "Ubuntu-24.04",
  [int]$MilocoPort = 18860,
  [int]$OpenClawPort = 18789,
  [string]$AuthPayload = "",
  [string]$MimoApiKey = "",
  [string]$OmniModel = "xiaomi/mimo-v2.5",
  [string]$OmniBaseUrl = "https://api.xiaomimimo.com/v1",
  [string]$HomeId = "",
  [string]$CameraDids = "",
  [switch]$InstallWsl,
  [switch]$PauseOnExit
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
try {
  if ([Console]::BufferHeight -lt 3000) {
    [Console]::BufferHeight = 3000
  }
  if ([Console]::BufferWidth -lt 100) {
    [Console]::BufferWidth = 100
  }
} catch {
  # Some hosted consoles do not allow resizing the buffer.
}

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestPath = Join-Path $PackageRoot "manifest.json"
$PayloadDir = Join-Path $PackageRoot "payload"
$WindowsScriptsDir = Join-Path $PackageRoot "scripts\windows"
$Workflow = Join-Path $WindowsScriptsDir "win-miloco-workflow.ps1"
$InstallSh = Join-Path $PayloadDir "install.sh"
$script:PhaseIndex = 0
$script:PhaseTotal = 10
$script:ResolvedDistro = ""
$script:ResolvedDistroInfo = $null
$script:MilocoPort = $MilocoPort
$script:ExistingRestorePackPath = ""
$script:WslExe = ""
$script:ConsoleLogPath = ""
$script:InputLogPath = ""
$script:TranscriptStarted = $false

function Exit-Installer {
  param([int]$Code = 0)

  if ($PauseOnExit) {
    Write-Host ""
    if ($Code -eq 0) {
      Write-Host "安装向导已完成。你可以先按上面的中文提示继续下一步。" -ForegroundColor Green
    } else {
      Write-Host "安装向导已暂停。请先按上面的中文提示处理问题。" -ForegroundColor Yellow
    }
    Read-Host "按回车关闭窗口"
  }
  if ($script:TranscriptStarted) {
    try {
      Stop-Transcript | Out-Null
    } catch {
    }
  }
  exit $Code
}

function Write-Banner {
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "        easy-miloco Windows 安装向导" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "正在自动检查和安装，请不要关闭窗口。" -ForegroundColor White
  Write-Host "能自动处理的步骤会自动处理；需要你参与时，我会停下来说明下一步。" -ForegroundColor White
}

function Write-Step {
  param([string]$Message)
  $script:PhaseIndex += 1
  Write-Host ""
  Write-Host ("[{0}/{1}] {2}" -f $script:PhaseIndex, $script:PhaseTotal, $Message) -ForegroundColor Cyan
}

function Write-Ok {
  param([string]$Message)
  Write-Host ("[OK] {0}" -f $Message) -ForegroundColor Green
}

function Write-Info {
  param([string]$Message)
  Write-Host ("[正在处理] {0}" -f $Message) -ForegroundColor Cyan
}

function Write-Warn {
  param([string]$Message)
  Write-Host ("[需要注意] {0}" -f $Message) -ForegroundColor Yellow
}

function Start-InstallerLog {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $script:ConsoleLogPath = Join-Path $PackageRoot ("miloco-install-console-{0}.txt" -f $stamp)
  $script:InputLogPath = Join-Path $PackageRoot ("miloco-install-inputs-{0}.txt" -f $stamp)
  try {
    Set-Content -Encoding utf8 -LiteralPath $script:InputLogPath -Value @(
      "easy-miloco installer input log",
      ("StartTime={0}" -f (Get-Date -Format "s")),
      ""
    )
  } catch {
    $script:InputLogPath = ""
  }
  try {
    Start-Transcript -LiteralPath $script:ConsoleLogPath -Force | Out-Null
    $script:TranscriptStarted = $true
    Write-Host ("[说明] 本次安装窗口日志会保存到：{0}" -f $script:ConsoleLogPath) -ForegroundColor Gray
    if (-not [string]::IsNullOrWhiteSpace($script:InputLogPath)) {
      Write-Host ("[说明] 本次安装交互输入会保存到：{0}" -f $script:InputLogPath) -ForegroundColor Gray
    }
  } catch {
    $script:TranscriptStarted = $false
    Write-Warn ("无法启动安装窗口日志记录：{0}" -f $_.Exception.Message)
  }
}

function Read-InstallerInput {
  param([string]$Prompt)

  $value = Read-Host $Prompt
  if ($null -eq $value) {
    $value = ""
  }
  if (-not [string]::IsNullOrWhiteSpace($script:InputLogPath)) {
    try {
      Add-Content -Encoding utf8 -LiteralPath $script:InputLogPath -Value ("[INPUT] {0}: {1}" -f $Prompt, $value)
    } catch {
    }
  }
  return $value
}

function Fail {
  param([string]$Message)
  Write-Host ""
  Write-Host ("[失败] {0}" -f $Message) -ForegroundColor Red
  Write-Host ""
  Write-Host "请先按上面的提示处理，然后重新双击 install.bat。" -ForegroundColor Yellow
  Exit-Installer 1
}

function Stop-ForUser {
  param(
    [string]$Title,
    [string[]]$Lines,
    [int]$ExitCode = 1,
    [switch]$OfferRestart
  )

  Write-Host ""
  Write-Host ("[安装暂停] {0}" -f $Title) -ForegroundColor Yellow
  foreach ($line in $Lines) {
    Write-Host $line -ForegroundColor Yellow
  }
  Write-Host ""
  if ($OfferRestart) {
    $answer = Read-InstallerInput "请重启电脑后再次运行安装。回复 y 立即重启，直接按回车则先关闭窗口"
    if ($answer.Trim() -ieq "y") {
      Write-Host ""
      Write-Info "正在重启 Windows。重启后请重新双击 install.bat。"
      & shutdown.exe /r /t 0
      if ($LASTEXITCODE -ne 0) {
        Write-Warn "自动重启命令没有成功执行。请手动重启 Windows。"
      } else {
        exit $ExitCode
      }
    } else {
      exit $ExitCode
    }
  }
  Exit-Installer $ExitCode
}

function Get-ReportTroubleshootingLines {
  param([string]$ReportPath)

  $lines = New-Object System.Collections.Generic.List[string]
  $followUpLines = New-Object System.Collections.Generic.List[string]
  if (-not (Test-Path -LiteralPath $ReportPath)) {
    $lines.Add("诊断报告没有生成成功，请把安装窗口截图发给维护者。") | Out-Null
    return $lines.ToArray()
  }

  $text = Get-Content -Encoding utf8 -LiteralPath $ReportPath -Raw
  if ($text -match 'server":\s*\{\s*"url":\s*"http://127\.0\.0\.1:(\d+)"' -and [int]$Matches[1] -ne $script:MilocoPort) {
    $lines.Add(("检测到 Miloco 仍在使用旧端口 {0}，但本安装包这次分配的是端口 {1}。安装器下次会继续先停止旧进程、重写配置、再等待新端口启动。" -f $Matches[1], $script:MilocoPort)) | Out-Null
  }
  if ($text -match '\[FAIL\]\s+miloco\.health') {
    $lines.Add(("Miloco 面板后端还没有在 http://127.0.0.1:{0}/health 正常响应。" -f $script:MilocoPort)) | Out-Null
  }
  if ($text -match '\[FAIL\]\s+openclaw\.miloco_plugin|Plugin not found:\s*miloco-openclaw-plugin') {
    $lines.Add("OpenClaw 已安装并运行，但 Miloco 插件还没有正确加载。安装器下次会继续自动安装本包自带的插件。") | Out-Null
  }
  if ($text -match 'access token is empty|is_bound"\s*:\s*false') {
    $followUpLines.Add("小米账号还没有完成授权。基础服务正常后，需要继续按提示完成小米账号绑定。") | Out-Null
  }
  if ($text -match 'API Key 未配置|miloco\.omni_api_key|api_key.*empty') {
    $followUpLines.Add("MiMo API Key 还没有配置。基础服务正常后，需要继续填写 MiMo API Key。") | Out-Null
  }

  if ($lines.Count -eq 0) {
    if ($followUpLines.Count -gt 0) {
      $lines.Add("基础服务已经通过，下面是后续需要你手动完成的配置。") | Out-Null
    } else {
      $lines.Add("自动诊断发现服务还没到可用状态，但没有识别到常见原因。") | Out-Null
    }
  } elseif ($followUpLines.Count -gt 0) {
    $lines.Add("下面这些是基础服务正常后再做的配置，不是当前安装失败的主要原因：") | Out-Null
  }
  foreach ($followUpLine in $followUpLines) {
    $lines.Add($followUpLine) | Out-Null
  }
  $lines.Add("请先不要反复覆盖安装，把下面这个诊断报告发给维护者排查。") | Out-Null
  $lines.Add(("诊断报告位置：{0}" -f $ReportPath)) | Out-Null
  return $lines.ToArray()
}

function Test-ReportAllowsPostAuthSetup {
  param([string]$ReportPath)

  if (-not (Test-Path -LiteralPath $ReportPath)) {
    return $false
  }

  $text = Get-Content -Encoding utf8 -LiteralPath $ReportPath -Raw
  $hasBlockingFailure =
    ($text -match 'BASIC_READY\s*=\s*no') -or
    ($text -match 'BASIC_READY_FROM_WINDOWS\s*=\s*no') -or
    ($text -match '\[FAIL\]\s+miloco\.health') -or
    ($text -match '\[FAIL\]\s+openclaw\.miloco_plugin') -or
    ($text -match '\[FAIL\]\s+openclaw\.gateway_http') -or
    ($text -match '\[FAIL\]\s+windows\.miloco_http') -or
    ($text -match '\[FAIL\]\s+windows\.openclaw_gateway')
  if ($hasBlockingFailure) {
    return $false
  }

  $hasPostAuthGap =
    ($text -match 'FULL_READY\s*=\s*no') -or
    ($text -match 'access token is empty|is_bound"\s*:\s*false') -or
    ($text -match 'API Key 未配置|miloco\.omni_api_key|api_key.*empty') -or
    ($text -match 'MiMo API Key') -or
    ($text -match 'MiMo CA')
  return $hasPostAuthGap
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    Fail "安装包缺少必要文件：$Path。请重新下载完整的 zip 包，不要只复制其中一部分文件。"
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

function ConvertTo-VersionOrNull {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }
  $clean = ($Value.Trim() -replace "[^0-9.].*$", "")
  try {
    return [version]$clean
  } catch {
    return $null
  }
}

function Test-VersionAtLeast {
  param(
    [string]$Actual,
    [string]$Minimum
  )
  $actualVersion = ConvertTo-VersionOrNull $Actual
  $minimumVersion = ConvertTo-VersionOrNull $Minimum
  return ($null -ne $actualVersion -and $null -ne $minimumVersion -and $actualVersion -ge $minimumVersion)
}

function Get-WslDistroRows {
  param([string]$RawList)

  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($line in (($RawList -replace "`0", "") -split "`r?`n")) {
    $text = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    if ($text -match "^(NAME|名称)\s+") { continue }
    $text = ($text -replace "^\*\s*", "").Trim()
    if ($text -match "^(.+?)\s{2,}.+?\s+(\d+)\s*$") {
      $rows.Add([pscustomobject]@{
        Name = $Matches[1].Trim()
        WslVersion = [int]$Matches[2]
        Raw = $line
      }) | Out-Null
    }
  }
  return @($rows.ToArray())
}

function Get-WslExePath {
  if (-not [string]::IsNullOrWhiteSpace($script:WslExe) -and (Test-Path -LiteralPath $script:WslExe)) {
    return $script:WslExe
  }

  $candidates = New-Object System.Collections.Generic.List[string]
  $cmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
  if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
    $candidates.Add($cmd.Source) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($env:WINDIR)) {
    $candidates.Add((Join-Path $env:WINDIR "System32\wsl.exe")) | Out-Null
    $candidates.Add((Join-Path $env:WINDIR "Sysnative\wsl.exe")) | Out-Null
  }

  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      $script:WslExe = $candidate
      return $candidate
    }
  }
  return ""
}

function Test-WindowsOptionalFeatureEnabled {
  param([string]$FeatureName)

  try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
    return ($feature.State -eq "Enabled")
  } catch {
    return $false
  }
}

function Invoke-DistroProbe {
  param([string]$Name)

  $probe = @'
set +e
read_os_value() {
  key="$1"
  if [ -r /etc/os-release ]; then
    grep -E "^${key}=" /etc/os-release | head -n 1 | cut -d= -f2- | sed 's/^"//; s/"$//'
  fi
}

printf 'BASH_OK=yes\n'
printf 'ID=%s\n' "$(read_os_value ID)"
printf 'VERSION_ID=%s\n' "$(read_os_value VERSION_ID)"
printf 'PRETTY_NAME=%s\n' "$(read_os_value PRETTY_NAME)"

glibc=""
if command -v getconf >/dev/null 2>&1; then
  glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
fi
if [ -z "$glibc" ]; then
  glibc="$(ldd --version 2>&1 | sed -n '1s/.* //p')"
fi
printf 'GLIBC_VERSION=%s\n' "$glibc"

printf 'ARCH=%s\n' "$(uname -m 2>/dev/null)"
command -v curl >/dev/null 2>&1 && printf 'CURL_OK=yes\n' || printf 'CURL_OK=no\n'
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user show-environment >/dev/null 2>&1 && printf 'SYSTEMD_USER_OK=yes\n' || printf 'SYSTEMD_USER_OK=no\n'
else
printf 'SYSTEMD_USER_OK=no\n'
fi
'@

  $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $winTmp = Join-Path ([System.IO.Path]::GetTempPath()) "miloco-distro-probe-$id.sh"
  $wslTmp = "/tmp/miloco-distro-probe-$id.sh"
  [System.IO.File]::WriteAllText($winTmp, ($probe -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
  $wslMnt = ConvertTo-WslPath $winTmp
  $wslExe = Get-WslExePath
  if ([string]::IsNullOrWhiteSpace($wslExe)) {
    throw "没有找到 wsl.exe。"
  }
  try {
    $output = & $wslExe -d $Name -- bash -lc "cp '${wslMnt}' '${wslTmp}' && bash '${wslTmp}'; rc=`$?; rm -f '${wslTmp}'; exit `$rc" 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_.Exception.Message
      } else {
        $_.ToString()
      }
    }
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  } finally {
    Remove-Item -LiteralPath $winTmp -ErrorAction SilentlyContinue
  }
  $values = @{}
  foreach ($line in (($output | Out-String).Trim() -split "`r?`n")) {
    if ($line -match "^([A-Z_]+)=(.*)$") {
      $values[$Matches[1]] = $Matches[2].Trim()
    }
  }
  return [pscustomobject]@{
    Name = $Name
    Code = $code
    Values = $values
    Raw = (($output | Out-String).Trim())
  }
}

function Test-DistroCapability {
  param(
    [object]$Row,
    [object]$Probe
  )

  $values = $Probe.Values
  $reasons = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]

  $isUbuntu = ($values["ID"] -eq "ubuntu" -or $Row.Name -match "(?i)ubuntu")
  if (-not $isUbuntu) {
    $reasons.Add("不是 Ubuntu 发行版") | Out-Null
  }
  if ($Row.WslVersion -ne 2) {
    $reasons.Add("WSL version 不是 2") | Out-Null
  }
  if ($Probe.Code -ne 0 -or $values["BASH_OK"] -ne "yes") {
    $reasons.Add("bash 无法运行") | Out-Null
  }

  $arch = $values["ARCH"]
  if ($arch -notin @("x86_64", "aarch64")) {
    $reasons.Add("CPU 架构不是 x86_64/aarch64：$arch") | Out-Null
  }

  $glibc = $values["GLIBC_VERSION"]
  if (-not (Test-VersionAtLeast $glibc "2.28")) {
    $reasons.Add("glibc 低于 2.28：$glibc") | Out-Null
  }

  $ubuntuVersion = $values["VERSION_ID"]
  if (-not (Test-VersionAtLeast $ubuntuVersion "20.04")) {
    $reasons.Add("Ubuntu 版本低于 20.04：$ubuntuVersion") | Out-Null
  } elseif (-not (Test-VersionAtLeast $ubuntuVersion "22.04")) {
    $warnings.Add("Ubuntu $ubuntuVersion 理论可用，但低于推荐版本 22.04。") | Out-Null
  }

  if ($values["CURL_OK"] -ne "yes") {
    $reasons.Add("curl 不可用") | Out-Null
  }
  if ($values["SYSTEMD_USER_OK"] -ne "yes") {
    $reasons.Add("systemd user 命令不可用") | Out-Null
  }

  $rank = 99
  if ($reasons.Count -eq 0) {
    if (Test-VersionAtLeast $ubuntuVersion "24.04") {
      $rank = 1
    } elseif (Test-VersionAtLeast $ubuntuVersion "22.04") {
      $rank = 2
    } elseif (Test-VersionAtLeast $ubuntuVersion "20.04") {
      $rank = 3
    }
  }

  return [pscustomobject]@{
    Name = $Row.Name
    WslVersion = $Row.WslVersion
    UbuntuVersion = $ubuntuVersion
    PrettyName = $values["PRETTY_NAME"]
    GlibcVersion = $glibc
    Arch = $arch
    Eligible = ($reasons.Count -eq 0)
    Rank = $rank
    PreferredName = if ($Row.Name -eq $Distro) { 0 } else { 1 }
    Reasons = @($reasons)
    Warnings = @($warnings)
    Probe = $Probe
  }
}

function Resolve-WslDistro {
  param([bool]$InstallIfMissing = $true)

  if (-not [string]::IsNullOrWhiteSpace($script:ResolvedDistro)) {
    return $script:ResolvedDistro
  }

  ## WSL 检测：优先找真实 wsl.exe 路径，避免 PATH 异常导致误判。
  $wslExe = Get-WslExePath
  if ([string]::IsNullOrWhiteSpace($wslExe)) {
    $wslFeatureEnabled = Test-WindowsOptionalFeatureEnabled "Microsoft-Windows-Subsystem-Linux"
    $vmFeatureEnabled = Test-WindowsOptionalFeatureEnabled "VirtualMachinePlatform"
    if ($wslFeatureEnabled -and $vmFeatureEnabled) {
      Stop-ForUser "Windows WSL 组件看起来已启用，但没有找到 wsl.exe。" @(
        "这不是 Miloco 卸载造成的，也不是需要重复重启的正常更新步骤。",
        "请确认 Windows 系统目录里存在 C:\Windows\System32\wsl.exe。",
        "如果刚升级或刚安装过 WSL，请重启 Windows 后再双击 install.bat。",
        "如果重启后仍出现此提示，请把安装窗口截图发给维护者。"
      )
    }

    Write-Info "没有检测到 WSL 命令，正在尝试启用 Windows 的 WSL 组件。"
    & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    $wslFeatureCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    $vmFeatureCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($wslFeatureCode -ne 0 -or $vmFeatureCode -ne 0) {
      Stop-ForUser "WSL 组件启用失败。" @(
        "这通常不是安装包坏了，而是 Windows 系统组件没有成功打开。",
        "请确认当前窗口是管理员权限，并检查 BIOS/任务管理器里 CPU 虚拟化是否已开启。",
        "处理好后重新双击 install.bat。"
      )
    }
    $script:WslExe = ""
    $wslExe = Get-WslExePath
    if (-not [string]::IsNullOrWhiteSpace($wslExe)) {
      Write-Ok ("WSL 命令：已找到 {0}。" -f $wslExe)
    }
    Stop-ForUser "WSL 组件已启用，需要重启电脑。" @(
      "请现在重启 Windows。",
      "重启后重新双击 install.bat，安装会自动继续。"
    ) -OfferRestart
  }

  ## WSL 真实注册名列表：读取 wsl.exe -l -v，不再只相信默认名字 Ubuntu-24.04。
  $list = $null
  try {
    $list = (& $wslExe -l -v 2>&1 | Out-String) -replace "`0", ""
  } catch {
    $list = $null
  }

  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($list)) {
    Write-Info "WSL 命令存在，但当前状态异常，正在尝试自动更新和修复。"
    & $wslExe --update
    $updateCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    Start-Sleep -Seconds 2
    try {
      $list = (& $wslExe -l -v 2>&1 | Out-String) -replace "`0", ""
    } catch {
      $list = $null
    }
    $listCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

    if (($listCode -ne 0 -or [string]::IsNullOrWhiteSpace($list)) -and $InstallIfMissing) {
      Write-Info "WSL 更新后仍没有返回发行版列表，正在尝试安装 Ubuntu-24.04。"
      & $wslExe --install -d $Distro
      $installCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
      Start-Sleep -Seconds 2
      try {
        $list = (& $wslExe -l -v 2>&1 | Out-String) -replace "`0", ""
      } catch {
        $list = $null
      }
      $listCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
      if ($installCode -ne 0 -and ($listCode -ne 0 -or [string]::IsNullOrWhiteSpace($list))) {
        Stop-ForUser "WSL 自动修复失败。" @(
          "请先确认 Windows 已开启 CPU 虚拟化。",
          "然后打开 Microsoft Store 更新 WSL，或在管理员 PowerShell 里运行：wsl --update",
          "处理好后重新双击 install.bat。"
        )
      }
    }

    if ($listCode -ne 0 -or [string]::IsNullOrWhiteSpace($list)) {
      if ($updateCode -ne 0) {
        Write-Warn ("wsl --update 退出码：{0}" -f $updateCode)
      }
      Stop-ForUser "WSL 自动修复失败。" @(
        "请先确认 Windows 已开启 CPU 虚拟化。",
        "然后打开 Microsoft Store 更新 WSL，或在管理员 PowerShell 里运行：wsl --update",
        "处理好后重新双击 install.bat。"
      )
    }
    Write-Ok "WSL 自动修复后已恢复可用，继续安装。"
  }

  $rows = @(Get-WslDistroRows $list)
  $evaluations = New-Object System.Collections.Generic.List[object]
  foreach ($row in $rows) {
    ## Ubuntu 能力检测：进入真实注册名，读取 /etc/os-release、glibc、架构、curl、systemd user。
    $probe = Invoke-DistroProbe $row.Name
    $evaluations.Add((Test-DistroCapability -Row $row -Probe $probe)) | Out-Null
  }

  $eligible = @($evaluations | Where-Object { $_.Eligible } | Sort-Object Rank, PreferredName, @{ Expression = { ConvertTo-VersionOrNull $_.UbuntuVersion }; Descending = $true }, Name)
  if ($eligible.Count -gt 0) {
    $selected = $eligible[0]
    $script:ResolvedDistro = $selected.Name
    $script:ResolvedDistroInfo = $selected
    Write-Ok ("WSL Ubuntu：使用真实注册名 {0}（{1}，glibc {2}，{3}）。" -f $selected.Name, $selected.PrettyName, $selected.GlibcVersion, $selected.Arch)
    foreach ($warning in $selected.Warnings) {
      Write-Warn $warning
    }
    return $script:ResolvedDistro
  }

  if ($evaluations.Count -gt 0) {
    Write-Warn "没有找到满足最低能力要求的 Ubuntu 发行版。"
    foreach ($item in $evaluations) {
      $reasonText = if ($item.Reasons.Count -gt 0) { $item.Reasons -join "；" } else { "未知原因" }
      Write-Host ("  {0}: {1}" -f $item.Name, $reasonText) -ForegroundColor Yellow
    }
  }

  ## Ubuntu 自动安装：只有没有可用 Ubuntu 时，才默认安装 Ubuntu-24.04。
  if ($InstallIfMissing) {
    Write-Info "没有可用的 Ubuntu 发行版，正在默认安装 Ubuntu-24.04。"
    & $wslExe --install -d $Distro
    if ($LASTEXITCODE -ne 0) {
      Stop-ForUser "Ubuntu 自动安装失败。" @(
        "请检查网络是否可访问 Microsoft Store / WSL 下载源。",
        "如果 Windows 提示需要先重启，请先重启。",
        "处理好后重新双击 install.bat。"
      )
    }
    Stop-ForUser "$Distro 已开始安装。" @(
      "如果 Windows 弹出 Ubuntu 窗口，请按提示创建 Ubuntu 用户名和密码。",
      "如果 Windows 提示需要重启，请先重启。",
      "完成后重新双击 install.bat，安装会自动继续。"
    ) -OfferRestart
  }

  Fail "没有找到可用的 Ubuntu WSL 发行版。请先安装 Ubuntu 24.04，或重新双击 install.bat 让安装器自动安装。"
}

function Get-ResolvedDistro {
  if ([string]::IsNullOrWhiteSpace($script:ResolvedDistro)) {
    Resolve-WslDistro -InstallIfMissing $false | Out-Null
  }
  return $script:ResolvedDistro
}

function Check-Prerequisites {
  $failed = $false
  $blockers = New-Object System.Collections.Generic.List[string]

  $build = [System.Environment]::OSVersion.Version.Build
  if ($build -lt 22621) {
    Write-Host ("[失败] 操作系统版本：当前 Windows Build {0}，需要 Windows 11 22H2+，也就是 Build 22621 或更高。" -f $build) -ForegroundColor Red
    $blockers.Add("请先升级 Windows。升级后重新双击 install.bat。") | Out-Null
    $failed = $true
  } else {
    Write-Ok "操作系统版本：Windows Build $build，满足 Windows 11 22H2+ 要求。"
  }

  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "[失败] 管理员权限：当前窗口不是管理员模式。" -ForegroundColor Red
    $blockers.Add("请关闭这个窗口，重新双击 install.bat，并在弹出的管理员权限窗口里选择同意。") | Out-Null
    $failed = $true
  } else {
    Write-Ok "管理员权限：已获得。"
  }

  Write-Info "正在检测 GitHub 下载网络和加速节点。"
  $endpoints = @(
    @{ Name = "直连"; Url = "https://github.com"; Prefix = "" },
    @{ Name = "gh-proxy.org"; Url = "https://v4.gh-proxy.org"; Prefix = "https://v4.gh-proxy.org/" },
    @{ Name = "gitwarp.com"; Url = "https://www.gitwarp.com"; Prefix = "https://www.gitwarp.com/" }
  )

  $fastest = $null
  $minTime = [int]::MaxValue

  foreach ($ep in $endpoints) {
    try {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $request = [System.Net.WebRequest]::Create($ep.Url)
      $request.Timeout = 3000
      $request.Method = "HEAD"
      $response = $request.GetResponse()
      $sw.Stop()
      $response.Close()
      if ($sw.ElapsedMilliseconds -lt $minTime) {
        $minTime = $sw.ElapsedMilliseconds
        $fastest = $ep
      }
    } catch {}
  }

  if ($fastest) {
    Write-Ok ("下载网络：已连通，当前最快节点是 {0}，耗时约 {1}ms。" -f $fastest.Name, $minTime)
    $global:GITHUB_PROXY_PREFIX = $fastest.Prefix
  } else {
    Write-Warn "没有连通 GitHub 或加速节点。安装包里已有 Miloco 主程序，但 OpenClaw/Node 等依赖后续可能下载失败。"
    Write-Host "建议：如果后面卡在下载，请换网络，或按 README 的下载加速说明处理。" -ForegroundColor Yellow
    $global:GITHUB_PROXY_PREFIX = ""
  }

  if ($failed) {
    Stop-ForUser "环境依赖没有通过。" $blockers.ToArray()
  }
}

function Get-WindowsExcludedTcpRanges {
  $ranges = New-Object System.Collections.Generic.List[object]
  $result = & netsh.exe interface ipv4 show excludedportrange protocol=tcp 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
      $_.Exception.Message
    } else {
      $_.ToString()
    }
  }
  foreach ($line in $result) {
    if ($line -match "^\s*(\d+)\s+(\d+)\b") {
      $ranges.Add([pscustomobject]@{
        start = [int]$Matches[1]
        end = [int]$Matches[2]
      }) | Out-Null
    }
  }
  return $ranges.ToArray()
}

function Test-PortInRanges {
  param(
    [int]$Port,
    [object[]]$Ranges
  )

  foreach ($range in $Ranges) {
    if ($Port -ge $range.start -and $Port -le $range.end) {
      return $true
    }
  }
  return $false
}

function Test-LocalTcpPortOpen {
  param([int]$Port)

  $tcp = New-Object Net.Sockets.TcpClient
  try {
    $iar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne(250)) {
      return $false
    }
    $tcp.EndConnect($iar)
    return $true
  } catch {
    return $false
  } finally {
    $tcp.Close()
  }
}

function Get-PortFromUrl {
  param([string]$Url)

  if ([string]::IsNullOrWhiteSpace($Url)) {
    return $null
  }
  try {
    $uri = [Uri]$Url
    if ($uri.Port -gt 0) {
      return [int]$uri.Port
    }
  } catch {}
  return $null
}

function Test-WslPortListening {
  param([int]$Port)

  $script = @'
set +e
port="__PORT__"
if command -v ss >/dev/null 2>&1; then
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:|\\.)${port}$" && echo yes || echo no
else
  echo unknown
fi
exit 0
'@
  $script = $script.Replace("__PORT__", [string]$Port)
  $result = Invoke-WslBashText $script
  return (($result.text -split "`r?`n" | Select-Object -Last 1).Trim())
}

function Resolve-MilocoPort {
  param([object]$ExistingStatus)

  Write-Info ("正在选择 Miloco 本地端口，优先从 {0} 开始。" -f $script:MilocoPort)
  $excludedRanges = Get-WindowsExcludedTcpRanges
  $existingPort = $null
  if ($ExistingStatus -and $ExistingStatus.values.ContainsKey("MILOCO_URL")) {
    $existingPort = Get-PortFromUrl $ExistingStatus.values["MILOCO_URL"]
  }

  $startPort = [Math]::Max(1024, [int]$script:MilocoPort)
  $endPort = [Math]::Min(49151, $startPort + 199)
  for ($port = $startPort; $port -le $endPort; $port++) {
    if (Test-PortInRanges -Port $port -Ranges $excludedRanges) {
      continue
    }

    $windowsOpen = Test-LocalTcpPortOpen -Port $port
    $wslListening = Test-WslPortListening -Port $port
    $ownedByExistingMiloco = ($null -ne $existingPort -and $existingPort -eq $port)
    if (($windowsOpen -or $wslListening -eq "yes") -and -not $ownedByExistingMiloco) {
      continue
    }

    $script:MilocoPort = $port
    if ($port -eq $startPort) {
      Write-Ok ("Miloco 本地端口：使用 {0}。" -f $port)
    } else {
      Write-Ok ("Miloco 本地端口：{0} 不可用，已自动改用 {1}。" -f $startPort, $port)
    }
    return $port
  }

  Stop-ForUser "没有找到可用的 Miloco 本地端口。" @(
    ("安装器已从 {0} 到 {1} 自动尝试端口，但都不可用。" -f $startPort, $endPort),
    "这通常说明本机端口被其他程序大量占用，或 Windows 端口保留范围异常。",
    "请把这个窗口截图发给维护者，不要反复重装。"
  )
}

function Ensure-Wsl {
  Resolve-WslDistro -InstallIfMissing $true | Out-Null
}

function Invoke-WslBash {
  param([string]$Script)

  $Script = $Script -replace "`r`n", "`n"
  $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $wslTmp = "/tmp/miloco-$id.sh"

  # Write script to a Windows temp file, then copy into WSL via /mnt path
  $winTmp = Join-Path ([System.IO.Path]::GetTempPath()) "miloco-$id.sh"
  [System.IO.File]::WriteAllText($winTmp, $Script, [System.Text.UTF8Encoding]::new($false))
  $wslMnt = ConvertTo-WslPath $winTmp
  $resolvedDistro = Get-ResolvedDistro
  $wslExe = Get-WslExePath
  if ([string]::IsNullOrWhiteSpace($wslExe)) {
    Fail "没有找到 wsl.exe，无法进入 Ubuntu 执行安装步骤。请重启 Windows 后重新双击 install.bat。"
  }

  try {
    & $wslExe -d $resolvedDistro -- cp $wslMnt $wslTmp
    $copyCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($copyCode -ne 0) {
      Fail "无法把临时脚本复制到 WSL，退出码 $copyCode。请把窗口内容发给维护者。"
    }

    & $wslExe -d $resolvedDistro -- bash $wslTmp
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($code -ne 0) {
      Fail "WSL 内命令执行失败，退出码 $code。上方通常有具体错误，请把窗口内容或诊断报告发给维护者。"
    }
  } finally {
    & $wslExe -d $resolvedDistro -- rm -f $wslTmp *> $null
    Remove-Item -LiteralPath $winTmp -ErrorAction SilentlyContinue
  }
}

function Invoke-WslBashText {
  param([string]$Script)

  $Script = $Script -replace "`r`n", "`n"
  $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $wslTmp = "/tmp/miloco-probe-$id.sh"
  $winTmp = Join-Path ([System.IO.Path]::GetTempPath()) "miloco-probe-$id.sh"
  [System.IO.File]::WriteAllText($winTmp, $Script, [System.Text.UTF8Encoding]::new($false))
  $wslMnt = ConvertTo-WslPath $winTmp
  $resolvedDistro = Get-ResolvedDistro
  $wslExe = Get-WslExePath
  if ([string]::IsNullOrWhiteSpace($wslExe)) {
    return [pscustomobject]@{
      code = 127
      text = "没有找到 wsl.exe，无法进入 Ubuntu 执行安装步骤。"
    }
  }

  $copyOutput = & $wslExe -d $resolvedDistro -- cp $wslMnt $wslTmp 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
      $_.Exception.Message
    } else {
      $_.ToString()
    }
  }
  $copyCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  if ($copyCode -ne 0) {
    Remove-Item -LiteralPath $winTmp -ErrorAction SilentlyContinue
    return [pscustomobject]@{
      code = $copyCode
      text = (($copyOutput | Out-String).Trim())
    }
  }

  try {
    $output = & $wslExe -d $resolvedDistro -- bash $wslTmp 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_.Exception.Message
      } else {
        $_.ToString()
      }
    }
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  } finally {
    & $wslExe -d $resolvedDistro -- rm -f $wslTmp *> $null
    Remove-Item -LiteralPath $winTmp -ErrorAction SilentlyContinue
  }
  return [pscustomobject]@{
    code = $code
    text = (($output | Out-String).Trim())
  }
}

function Get-ExistingInstallStatus {
  $probe = @'
set +e
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
kv() { printf '%s=%s\n' "$1" "$2"; }
has_cmd() { command -v "$1" >/dev/null 2>&1 && printf yes || printf no; }

kv MILOCO_CLI "$(has_cmd miloco-cli)"
kv OPENCLAW_CLI "$(has_cmd openclaw)"
[ -d "$HOME/.openclaw/miloco" ] && kv MILOCO_HOME yes || kv MILOCO_HOME no

if command -v miloco-cli >/dev/null 2>&1; then
  status="$(miloco-cli service status 2>/dev/null)"
  printf '%s' "$status" | grep -Eiq 'running|true|url=http' && kv MILOCO_SERVICE yes || kv MILOCO_SERVICE no
  current_url="$(miloco-cli config get server.url --value-only 2>/dev/null || true)"
  [ -n "$current_url" ] && kv MILOCO_URL "$current_url" || kv MILOCO_URL ""
else
  kv MILOCO_SERVICE no
  kv MILOCO_URL ""
fi

if command -v curl >/dev/null 2>&1; then
  curl -fsS --max-time 2 "http://127.0.0.1:__MILOCO_PORT__/health" >/dev/null 2>&1 && kv MILOCO_HEALTH yes || kv MILOCO_HEALTH no
  curl -fsS --max-time 2 "http://127.0.0.1:__OPENCLAW_PORT__/" >/dev/null 2>&1 && kv OPENCLAW_HTTP yes || kv OPENCLAW_HTTP no
else
  kv MILOCO_HEALTH no
  kv OPENCLAW_HTTP no
fi

if command -v openclaw >/dev/null 2>&1; then
  openclaw plugins inspect miloco-openclaw-plugin 2>/dev/null | grep -Eiq 'Status:[[:space:]]*loaded|loaded' && kv MILOCO_PLUGIN yes || kv MILOCO_PLUGIN no
else
  kv MILOCO_PLUGIN no
fi
exit 0
'@
  $probe = $probe.Replace("__MILOCO_PORT__", [string]$script:MilocoPort).Replace("__OPENCLAW_PORT__", [string]$OpenClawPort)
  $result = Invoke-WslBashText $probe
  $values = @{}
  foreach ($line in ($result.text -split "`r?`n")) {
    if ($line -match "^([A-Z_]+)=(.*)$") {
      $values[$Matches[1]] = $Matches[2].Trim()
    }
  }

  $signals = @("MILOCO_CLI", "MILOCO_HOME", "MILOCO_SERVICE", "MILOCO_HEALTH", "MILOCO_PLUGIN")
  $detected = $false
  foreach ($signal in $signals) {
    if ($values[$signal] -eq "yes") {
      $detected = $true
      break
    }
  }

  return [pscustomobject]@{
    detected = $detected
    values = $values
    raw = $result.text
  }
}

function Export-ExistingRestorePackToDesktop {
  param([object]$Status)

  Write-Step "停止旧服务并导出 Agent 恢复 ZIP"

  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
    Stop-ForUser "无法找到当前用户桌面，已停止旧版迁移。" @(
      "安装器需要先把旧版用户配置导出为恢复 ZIP，再删除旧版。",
      "请确认当前 Windows 用户有可用桌面目录后重新运行 install.bat。"
    ) 70
  }

  $wslDesktop = ConvertTo-WslPath $desktop
  $exportScript = @'
set +e
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export EXPORT_DESKTOP="__WSL_DESKTOP__"

systemctl --user stop openclaw-gateway.service >/tmp/miloco-migration-openclaw-stop.log 2>&1 || true
supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-migration-supervisor-stop.log 2>&1 || true
pkill -TERM -f "[w]indows-keeper.sh" 2>/dev/null || true
pkill -TERM -f "[w]sl-miloco-keeper.sh" 2>/dev/null || true
pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
pkill -TERM -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true
sleep 1
pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
pkill -KILL -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true

python3 - <<'PY'
import json
import os
import shutil
import sqlite3
import tempfile
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path

desktop = Path(os.environ["EXPORT_DESKTOP"])
desktop.mkdir(parents=True, exist_ok=True)
home = Path.home() / ".openclaw" / "miloco"
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

agent_text = """# Miloco Agent 恢复说明

这是 Agent 恢复包，不是直接覆盖包。请先读取 manifest.json，确认 schema_version / assets / restore_contract，再创建导入前 checkpoint。

恢复原则：

1. 不要把数据库、身份库、配置文件原样覆盖到当前安装。
2. 先生成差异计划，向用户确认高风险项。
3. 模型配置、家庭成员、家庭档案、家庭任务要分阶段恢复。
4. 家庭任务优先恢复为 disabled 或 draft，用户确认后再启用。
5. 通知动作、设备、摄像头、账号登录态要按当前机器重新映射。
6. 发生错误时按导入日志回滚。
"""

def ensure_agents(zip_path: Path) -> None:
    tmp = zip_path.with_suffix(zip_path.suffix + ".agents.tmp")
    with zipfile.ZipFile(zip_path, "r") as zin, zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
        for info in zin.infolist():
            if info.filename == "AGENTS.md":
                continue
            zout.writestr(info, zin.read(info.filename))
        zout.writestr("AGENTS.md", agent_text)
    tmp.replace(zip_path)

def add_file(zf: zipfile.ZipFile, src: Path, arc: str) -> bool:
    if src.exists() and src.is_file():
        zf.write(src, arc)
        return True
    return False

def add_tree(zf: zipfile.ZipFile, src: Path, arc_root: str) -> int:
    count = 0
    if not src.exists() or not src.is_dir():
        return count
    for path in sorted(p for p in src.rglob("*") if p.is_file()):
        if any(part in {"log", "logs", "snapshots", "images", "miot_cache", ".install-cache", "packs"} for part in path.relative_to(src).parts):
            continue
        zf.write(path, f"{arc_root}/{path.relative_to(src).as_posix()}")
        count += 1
    return count

def fallback_pack() -> tuple[Path, str]:
    filename = f"miloco-agent-restore-pack-{stamp}-{uuid.uuid4().hex[:8]}-compat.zip"
    path = Path(tempfile.gettempdir()) / filename
    assets = []
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.writestr("AGENTS.md", agent_text)
        zf.writestr("RESTORE.md", agent_text)
        if add_file(zf, home / "config.json", "raw/config.json"):
            assets.append("model_config")
        if add_tree(zf, home / "home-profile", "raw/home-profile"):
            assets.append("home_profile")
        if add_tree(zf, home / "identity-lib", "raw/identity-lib"):
            assets.append("members")
        db = home / "miloco.db"
        if db.exists():
            try:
                snapshot = Path(tempfile.gettempdir()) / f"miloco-db-{uuid.uuid4().hex[:8]}.db"
                src = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
                dst = sqlite3.connect(snapshot)
                src.backup(dst)
                src.close()
                dst.close()
                zf.write(snapshot, "raw/miloco.db")
                snapshot.unlink(missing_ok=True)
            except Exception:
                zf.write(db, "raw/miloco.db")
            assets.extend(["members", "tasks"])
        manifest = {
            "kind": "miloco-agent-restore-pack",
            "schema_version": 1,
            "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "source": {
                "app": "easy-miloco",
                "miloco_home_hint": str(home),
                "export_mode": "compat_raw_snapshot"
            },
            "assets": sorted(set(assets)),
            "restore_contract": "agent_restore_v1",
            "notes": [
                "This compatibility pack was created because the old installed Miloco did not expose the logical backup exporter.",
                "Agent must inspect and migrate; do not copy raw files over the new installation."
            ]
        }
        zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    return path, "compat_raw_snapshot"

try:
    from miloco.admin.backup_export import build_agent_restore_pack
    result = build_agent_restore_pack()
    src = Path(result.path)
    ensure_agents(src)
    mode = "logical_export"
except Exception as exc:
    src, mode = fallback_pack()

target = desktop / src.name
shutil.copy2(src, target)
print(f"BACKUP_MODE={mode}")
print(f"BACKUP_FILENAME={target.name}")
print(f"BACKUP_WSL_PATH={target}")
PY
exit $?
'@
  $exportScript = $exportScript.Replace("__WSL_DESKTOP__", $wslDesktop)
  $result = Invoke-WslBashText $exportScript
  if ($result.code -ne 0) {
    Stop-ForUser "旧版用户配置备份失败，已停止安装。" @(
      "为了避免误删用户配置，安装器没有继续卸载旧版。",
      "请把下面输出发给维护者排查：",
      $result.text
    ) $result.code
  }

  $filename = ""
  $mode = "unknown"
  foreach ($line in ($result.text -split "`r?`n")) {
    if ($line -match "^BACKUP_FILENAME=(.+)$") { $filename = $Matches[1].Trim() }
    if ($line -match "^BACKUP_MODE=(.+)$") { $mode = $Matches[1].Trim() }
  }
  if ([string]::IsNullOrWhiteSpace($filename)) {
    Stop-ForUser "旧版用户配置备份没有返回 ZIP 文件名，已停止安装。" @(
      "为了避免误删用户配置，安装器没有继续卸载旧版。",
      "WSL 输出：",
      $result.text
    ) 71
  }

  $backupPath = Join-Path $desktop $filename
  if (-not (Test-Path -LiteralPath $backupPath)) {
    Stop-ForUser "旧版用户配置备份没有出现在桌面，已停止安装。" @(
      ("预期路径：{0}" -f $backupPath),
      "为了避免误删用户配置，安装器没有继续卸载旧版。"
    ) 72
  }

  $script:ExistingRestorePackPath = $backupPath
  Write-Ok ("旧版用户配置备份：已导出到 {0}（模式：{1}）。" -f $backupPath, $mode)
  return $backupPath
}

function Remove-ExistingMilocoInstall {
  Write-Step "完整卸载和删除旧版 Miloco"

  & cmd.exe /d /c "schtasks.exe /End /TN MilocoWSLKeeper >nul 2>nul" | Out-Null
  & cmd.exe /d /c "schtasks.exe /Delete /TN MilocoWSLKeeper /F >nul 2>nul" | Out-Null

  $desktop = [Environment]::GetFolderPath("Desktop")
  $desktopConsoleName = "Miloco " + [string][char]0x63A7 + [string][char]0x5236 + [string][char]0x53F0 + ".bat"
  foreach ($path in @(
    (Join-Path $desktop $desktopConsoleName),
    (Join-Path $desktop "miloco-console.ps1"),
    (Join-Path $desktop "miloco-xiaomi-oauth.url"),
    (Join-Path $desktop "miloco-xiaomi-oauth.txt")
  )) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    $full = [System.IO.Path]::GetFullPath($path)
    $desktopRoot = ([System.IO.Path]::GetFullPath($desktop)).TrimEnd("\") + "\"
    if ($full.StartsWith($desktopRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    }
  }

  $cleanup = @'
set +e
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
systemctl --user disable --now openclaw-gateway.service >/tmp/openclaw-uninstall-stop.log 2>&1 || true
rm -f "$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service" 2>/dev/null || true
systemctl --user daemon-reload >/dev/null 2>&1 || true
supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-uninstall-supervisor-stop.log 2>&1 || true
pkill -TERM -f "[w]indows-keeper.sh" 2>/dev/null || true
pkill -TERM -f "[w]sl-miloco-keeper.sh" 2>/dev/null || true
pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
pkill -TERM -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true
sleep 1
pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
pkill -KILL -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true
if command -v openclaw >/dev/null 2>&1; then
  printf 'y\n' | openclaw plugins uninstall miloco-openclaw-plugin >/tmp/openclaw-miloco-plugin-uninstall.log 2>&1 || true
fi
if command -v uv >/dev/null 2>&1; then
  uv tool uninstall miloco-cli >/tmp/miloco-cli-uninstall.log 2>&1 || true
  uv tool uninstall miloco >/tmp/miloco-uninstall.log 2>&1 || true
  uv tool uninstall supervisor >/tmp/miloco-supervisor-uninstall.log 2>&1 || true
fi
rm -rf "$HOME/.openclaw/miloco"
rm -f /tmp/miloco-* /tmp/openclaw-miloco-plugin-uninstall.log /tmp/openclaw-uninstall-stop.log 2>/dev/null || true
exit 0
'@
  Invoke-WslBash $cleanup
  $resolvedDistro = Get-ResolvedDistro
  $wslExe = Get-WslExePath
  if (-not [string]::IsNullOrWhiteSpace($wslExe)) {
    & $wslExe --terminate $resolvedDistro *> $null
  }
  Write-Ok ("旧版 Miloco：已完整卸载并关闭 {0} WSL 会话。" -f $resolvedDistro)
}

function Prepare-ExistingInstallForCleanInstall {
  param([object]$Status)

  if (-not $Status.detected) {
    Write-Ok "没有发现已有 Miloco 安装痕迹。"
    return $false
  }

  if ($script:PhaseTotal -lt 12) {
    $script:PhaseTotal = 12
  }

  Write-Host ""
  Write-Host "[需要迁移] 检测到这台电脑上已经有 Miloco 安装痕迹。" -ForegroundColor Yellow
  Write-Host "当前检测结果：" -ForegroundColor Yellow
  foreach ($name in @("MILOCO_CLI", "OPENCLAW_CLI", "MILOCO_HOME", "MILOCO_SERVICE", "MILOCO_HEALTH", "OPENCLAW_HTTP", "MILOCO_PLUGIN", "MILOCO_URL")) {
    $value = if ($Status.values.ContainsKey($name)) { $Status.values[$name] } else { "unknown" }
    Write-Host ("  {0}: {1}" -f $name, $value) -ForegroundColor Yellow
  }
  Write-Host ""
  Write-Host "安装器将先停止旧服务，把可恢复的用户配置导出为桌面 ZIP，然后完整卸载旧版，再执行新版安装。" -ForegroundColor Yellow
  Write-Host "这个 ZIP 很重要，请不要删除。" -ForegroundColor Yellow

  Export-ExistingRestorePackToDesktop $Status | Out-Null
  Remove-ExistingMilocoInstall
  return $true
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

function Install-DesktopLauncher {
  $resolvedDistro = Get-ResolvedDistro
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
    Write-Warn "没有找到桌面文件夹，已跳过创建桌面控制台。"
    return
  }

  $launcherName = "Miloco " + [string][char]0x63A7 + [string][char]0x5236 + [string][char]0x53F0 + ".bat"
  $launcher = Join-Path $desktop $launcherName
  $psLauncher = Join-Path $desktop "miloco-console.ps1"
  $openClawShortcutName = "OpenClaw " + [string][char]0x5BF9 + [string][char]0x8BDD + [string][char]0x5165 + [string][char]0x53E3 + ".lnk"
  $openClawShortcut = Join-Path $desktop $openClawShortcutName
  $openClawPsLauncher = Join-Path $desktop "miloco-openclaw.ps1"
  $bat = @'
@echo off
setlocal
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%POWERSHELL%" goto have_powershell
where powershell.exe >nul 2>nul || goto powershell_missing
set "POWERSHELL=powershell.exe"
:have_powershell
set "SCRIPT=%~dp0miloco-console.ps1"

if not exist "%SCRIPT%" goto missing_script
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b %errorlevel%

:missing_script
set "MILOCO_MSG_B64=5om+5LiN5YiwIG1pbG9jby1jb25zb2xlLnBzMeOAgg=="
call :say
set "MILOCO_MSG_B64=6K+36YeN5paw6L+Q6KGMIGluc3RhbGwuYmF077yM6K6p5a6J6KOF5Zmo6YeN5paw5Yib5bu65qGM6Z2i5o6n5Yi25Y+w44CC"
call :say
echo.
set "MILOCO_MSG_B64=5oyJ5Zue6L2m57un57ut44CC"
call :wait
exit /b 1

:powershell_missing
echo PowerShell is not available. Cannot continue.
echo.
pause
exit /b 1

:say
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "$OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); Write-Host ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:MILOCO_MSG_B64)))"
exit /b 0

:wait
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "$OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $null = Read-Host ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:MILOCO_MSG_B64)))"
exit /b 0
'@
  $ps1 = @'
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$script:Distro = "__DISTRO__"
$script:MilocoPort = __MILOCO_PORT__
$script:OpenClawPort = __OPENCLAW_PORT__
$script:WslExe = Join-Path $env:WINDIR "System32\wsl.exe"
if (-not (Test-Path -LiteralPath $script:WslExe)) {
  $script:WslExe = "wsl.exe"
}

function Test-Distro {
  & $script:WslExe -d $script:Distro -- true > $null 2> $null
  if ($LASTEXITCODE -eq 0) {
    return $true
  }

  Write-Host ""
  Write-Host ("找不到安装时使用的 WSL 发行版：{0}" -f $script:Distro) -ForegroundColor Yellow
  Write-Host "当前可用发行版：" -ForegroundColor Yellow
  & $script:WslExe -l -v
  return $false
}

function Invoke-WslBash {
  param([string]$Command)

  if (-not (Test-Distro)) {
    return $false
  }

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  & $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash"
  if ($LASTEXITCODE -ne 0) {
    Write-Host ("调用 WSL 失败，退出码：{0}" -f $LASTEXITCODE) -ForegroundColor Red
    return $false
  }
  return $true
}

function Invoke-WslText {
  param([string]$Command)

  if (-not (Test-Distro)) {
    return @()
  }

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  return @(& $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash" 2>$null)
}

function Get-OpenClawDashboardUrl {
  param([int]$Port)

  $url = "http://127.0.0.1:{0}/" -f $Port
  $dashboardUrl = ""
  try {
    $cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; openclaw dashboard --no-open 2>/tmp/openclaw-dashboard-url.err || true'
    foreach ($line in (Invoke-WslText $cmd)) {
      $match = [regex]::Match([string]$line, 'https?://[^\s"''<>]+')
      if ($match.Success) {
        $candidate = $match.Value.Trim()
        if ($candidate -match '(^|[#?&])token=') {
          return $candidate
        }
        if (-not $dashboardUrl) {
          $dashboardUrl = $candidate
        }
      }
    }
  } catch {
    $dashboardUrl = ""
  }

  $token = ""
  try {
    $py = @"
import json
from pathlib import Path

def read_json(path):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}

def text(value):
    return value.strip() if isinstance(value, str) else ""

home = Path.home()
miloco = read_json(home / ".openclaw" / "miloco" / "config.json")
openclaw = read_json(home / ".openclaw" / "openclaw.json")
candidates = []
agent = miloco.get("agent") if isinstance(miloco, dict) else {}
if isinstance(agent, dict):
    candidates.append(agent.get("auth_bearer"))
gateway = openclaw.get("gateway") if isinstance(openclaw, dict) else {}
auth = gateway.get("auth") if isinstance(gateway, dict) else {}
if isinstance(auth, dict):
    candidates.extend([auth.get("token"), auth.get("password"), auth.get("bearer")])
for candidate in candidates:
    value = text(candidate)
    if value:
        print(value)
        raise SystemExit(0)
"@
    $token = (& $script:WslExe -d $script:Distro -- python3 -c $py 2>$null | Select-Object -First 1)
  } catch {
    $token = ""
  }
  if ($token) {
    return ("{0}#token={1}" -f $url, [Uri]::EscapeDataString($token.Trim()))
  }
  if ($dashboardUrl) {
    return $dashboardUrl
  }
  return $url
}

function Open-WhenReady {
  param(
    [int]$Port,
    [switch]$OpenClaw
  )

  $deadline = (Get-Date).AddSeconds(60)
  $ready = $false
  while ((Get-Date) -lt $deadline) {
    $tcp = New-Object Net.Sockets.TcpClient
    try {
      $iar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
      if ($iar.AsyncWaitHandle.WaitOne(1000)) {
        $tcp.EndConnect($iar)
        $ready = $true
        break
      }
    } catch {
    } finally {
      $tcp.Close()
    }
    Start-Sleep -Seconds 1
  }
  if ($ready) {
    if ($OpenClaw) {
      Start-Process (Get-OpenClawDashboardUrl $Port)
    } else {
      Start-Process ("http://127.0.0.1:{0}/" -f $Port)
    }
    return
  }

  Write-Host ("端口 {0} 在 60 秒内还没有响应，所以暂时没有自动打开浏览器。" -f $Port) -ForegroundColor Yellow
  Write-Host "这通常表示服务还在启动、启动失败，或端口被占用。" -ForegroundColor Yellow
  Write-Host "可查看 WSL 内日志：" -ForegroundColor Yellow
  Write-Host "  /tmp/miloco-desktop-start.log" -ForegroundColor Yellow
  Write-Host "  /tmp/openclaw-desktop-restart.log" -ForegroundColor Yellow
}

function Get-MilocoPortConfigCommand {
  $py = @"
import json
from pathlib import Path

port = $script:MilocoPort
path = Path.home() / ".openclaw" / "miloco" / "config.json"
data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
server = data.setdefault("server", {})
server["url"] = f"http://127.0.0.1:{port}"
server["port"] = port
tmp = path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
tmp.replace(path)
"@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
  return "python3 -c `"import base64; exec(base64.b64decode('$encoded').decode('utf-8'))`" >/tmp/miloco-desktop-config-json.log 2>&1"
}

function Restart-OpenClaw {
  Write-Host ""
  Write-Host "正在重启 OpenClaw 面板..."
  $cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true'
  if (Invoke-WslBash $cmd) {
    Open-WhenReady $script:OpenClawPort -OpenClaw
  }
}

function Restart-Miloco {
  Write-Host ""
  Write-Host "正在重启 Miloco 面板..."
  $configCmd = Get-MilocoPortConfigCommand
  $cmd = 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; ' + $configCmd + ' || exit 44; supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-desktop-supervisor-stop.log 2>&1 || true; pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; sleep 1; pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; nohup miloco-cli service start >/tmp/miloco-desktop-start.log 2>&1 &'
  if (Invoke-WslBash $cmd) {
    Open-WhenReady $script:MilocoPort
  }
}

function Restart-All {
  Write-Host ""
  Write-Host "正在重启 Miloco + OpenClaw..."
  $configCmd = Get-MilocoPortConfigCommand
  $cmd = 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; ' + $configCmd + ' || exit 44; supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-desktop-supervisor-stop.log 2>&1 || true; pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; sleep 1; pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; nohup miloco-cli service start >/tmp/miloco-desktop-start.log 2>&1 & openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true'
  if (Invoke-WslBash $cmd) {
    Open-WhenReady $script:MilocoPort
    Open-WhenReady $script:OpenClawPort -OpenClaw
  }
}

function Stop-Services {
  Write-Host ""
  Write-Host "正在关闭 OpenClaw + Miloco..."
  & schtasks.exe /End /TN MilocoWSLKeeper > $null 2> $null
  $cmd = 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user disable --now openclaw-gateway.service >/tmp/openclaw-desktop-stop.log 2>&1 || true; rm -f "$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service" 2>/dev/null || true; systemctl --user daemon-reload >/dev/null 2>&1 || true; supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-desktop-supervisor-stop.log 2>&1 || true; pkill -TERM -f "[w]indows-keeper.sh" 2>/dev/null || true; pkill -TERM -f "[w]sl-miloco-keeper.sh" 2>/dev/null || true; pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; pkill -TERM -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true; sleep 2; pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true; pkill -KILL -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true'
  [void](Invoke-WslBash $cmd)
  Write-Host "关闭命令已发送。"
}

function Stop-Wsl {
  Stop-Services
  Write-Host ("正在关闭 WSL：{0}" -f $script:Distro)
  & $script:WslExe --terminate $script:Distro
}

function Show-Menu {
  Clear-Host
  Write-Host "========================================"
  Write-Host "       Miloco / OpenClaw 控制台"
  Write-Host "========================================"
  Write-Host ""
  Write-Host "  1. 重启 OpenClaw 面板"
  Write-Host "  2. 重启 Miloco 面板"
  Write-Host "  3. 重启 Miloco + OpenClaw"
  Write-Host "  4. 关闭 OpenClaw + Miloco"
  Write-Host "  5. 关闭 WSL"
  Write-Host "  0. 退出"
  Write-Host ""
  Write-Host "说明："
  Write-Host "  1. 打开或刷新 OpenClaw 对话入口。适合日常和 Agent 对话、验证 Miloco 插件是否生效。"
  Write-Host "  2. 打开或刷新 Miloco 管理面板。适合日常查看设备、摄像头、账号、模型和家庭配置。"
  Write-Host "  3. 一次性拉起整套服务，并打开两个面板。首次安装后、电脑重启后，优先选这个。"
  Write-Host "  4. 停止两个服务，但保留 WSL。适合今天不用了、想释放后台资源，或准备重新启动服务。"
  Write-Host "  5. 停止服务并关闭本次安装使用的 WSL。适合彻底退出、电脑卡顿、网络或端口异常时重置环境。"
  Write-Host "  0. 只关闭当前脚本，不影响已经运行的 Miloco 和 OpenClaw 服务。"
  Write-Host ""
}

while ($true) {
  Show-Menu
  if (-not (Test-Distro)) {
    Write-Host ""
    Read-Host "按回车返回菜单"
    continue
  }

  $choice = (Read-Host "请选择 [1/2/3/4/5/0]").Trim()
  switch ($choice) {
    "1" { Restart-OpenClaw; Read-Host "按回车返回菜单" | Out-Null }
    "2" { Restart-Miloco; Read-Host "按回车返回菜单" | Out-Null }
    "3" { Restart-All; Read-Host "按回车返回菜单" | Out-Null }
    "4" { Stop-Services; Read-Host "按回车返回菜单" | Out-Null }
    "5" { Stop-Wsl; Read-Host "按回车返回菜单" | Out-Null }
    "0" { exit 0 }
    default {
      Write-Host "请输入 1、2、3、4、5 或 0。" -ForegroundColor Yellow
      Start-Sleep -Seconds 1
    }
  }
}
'@
  $openClawPs1 = @'
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$script:Distro = "__DISTRO__"
$script:OpenClawPort = __OPENCLAW_PORT__
$script:WslExe = Join-Path $env:WINDIR "System32\wsl.exe"
if (-not (Test-Path -LiteralPath $script:WslExe)) {
  $script:WslExe = "wsl.exe"
}

function Invoke-WslBash {
  param([string]$Command)

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  & $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash" > $null 2> $null
  return ($LASTEXITCODE -eq 0)
}

function Invoke-WslText {
  param([string]$Command)

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  return @(& $script:WslExe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash" 2>$null)
}

function Get-OpenClawDashboardUrl {
  param([int]$Port)

  $url = "http://127.0.0.1:{0}/" -f $Port
  $dashboardUrl = ""
  try {
    $cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; openclaw dashboard --no-open 2>/tmp/openclaw-dashboard-url.err || true'
    foreach ($line in (Invoke-WslText $cmd)) {
      $match = [regex]::Match([string]$line, 'https?://[^\s"''<>]+')
      if ($match.Success) {
        $candidate = $match.Value.Trim()
        if ($candidate -match '(^|[#?&])token=') {
          return $candidate
        }
        if (-not $dashboardUrl) {
          $dashboardUrl = $candidate
        }
      }
    }
  } catch {
    $dashboardUrl = ""
  }

  $token = ""
  try {
    $py = @"
import json
from pathlib import Path

def read_json(path):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}

def text(value):
    return value.strip() if isinstance(value, str) else ""

home = Path.home()
miloco = read_json(home / ".openclaw" / "miloco" / "config.json")
openclaw = read_json(home / ".openclaw" / "openclaw.json")
candidates = []
agent = miloco.get("agent") if isinstance(miloco, dict) else {}
if isinstance(agent, dict):
    candidates.append(agent.get("auth_bearer"))
gateway = openclaw.get("gateway") if isinstance(openclaw, dict) else {}
auth = gateway.get("auth") if isinstance(gateway, dict) else {}
if isinstance(auth, dict):
    candidates.extend([auth.get("token"), auth.get("password"), auth.get("bearer")])
for candidate in candidates:
    value = text(candidate)
    if value:
        print(value)
        raise SystemExit(0)
"@
    $token = (& $script:WslExe -d $script:Distro -- python3 -c $py 2>$null | Select-Object -First 1)
  } catch {
    $token = ""
  }
  if ($token) {
    return ("{0}#token={1}" -f $url, [Uri]::EscapeDataString($token.Trim()))
  }
  if ($dashboardUrl) {
    return $dashboardUrl
  }
  return $url
}

function Wait-Port {
  param(
    [int]$Port,
    [int]$Seconds = 60
  )

  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $tcp = New-Object Net.Sockets.TcpClient
    try {
      $iar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
      if ($iar.AsyncWaitHandle.WaitOne(1000)) {
        $tcp.EndConnect($iar)
        return $true
      }
    } catch {
    } finally {
      $tcp.Close()
    }
    Start-Sleep -Seconds 1
  }
  return $false
}

$cmd = 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true; systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true; openclaw gateway restart >/tmp/openclaw-desktop-restart.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-desktop-restart-systemd.log 2>&1 || true'
[void](Invoke-WslBash $cmd)
if (Wait-Port $script:OpenClawPort 60) {
  Start-Process (Get-OpenClawDashboardUrl $script:OpenClawPort)
} else {
  $shell = New-Object -ComObject WScript.Shell
  [void]$shell.Popup("OpenClaw 端口暂未响应。请稍后再双击这个入口，或打开 Miloco 控制台选择 3 重启整套服务。", 12, "Miloco / OpenClaw", 48)
}
'@
  $ps1 = $ps1.Replace("__DISTRO__", $resolvedDistro).Replace("__MILOCO_PORT__", [string]$script:MilocoPort).Replace("__OPENCLAW_PORT__", [string]$OpenClawPort)
  $openClawPs1 = $openClawPs1.Replace("__DISTRO__", $resolvedDistro).Replace("__OPENCLAW_PORT__", [string]$OpenClawPort)
  [System.IO.File]::WriteAllText($launcher, $bat, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($psLauncher, $ps1, [System.Text.UTF8Encoding]::new($true))
  [System.IO.File]::WriteAllText($openClawPsLauncher, $openClawPs1, [System.Text.UTF8Encoding]::new($true))
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($openClawShortcut)
    $shortcut.TargetPath = Get-PowerShellExe
    $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $openClawPsLauncher)
    $shortcut.WorkingDirectory = $desktop
    $shortcut.IconLocation = "shell32.dll,220"
    $shortcut.Save()
  } catch {
    Write-Warn ("创建 OpenClaw 对话入口快捷方式失败：{0}" -f $_.Exception.Message)
  }
  Write-Host "桌面控制台入口已创建：$launcher"
  Write-Host "桌面控制台脚本已创建：$psLauncher"
  Write-Host "OpenClaw 对话入口已创建：$openClawShortcut"
}

function Start-UserUrl {
  param(
    [string]$Url,
    [string]$Label = "网页"
  )

  if ([string]::IsNullOrWhiteSpace($Url)) {
    return
  }
  try {
    Start-Process -FilePath $Url
    Write-Ok ("已自动打开{0}：{1}" -f $Label, $Url)
  } catch {
    Write-Warn ("没有自动打开{0}。请手动复制打开：{1}" -f $Label, $Url)
  }
}

function ConvertTo-MilocoAuthPayload {
  param([string]$UserInput)

  $value = $UserInput.Trim()
  if ([string]::IsNullOrWhiteSpace($value)) {
    return ""
  }
  $codeMatch = [regex]::Match($value, '(?:[?&]|\b)code=([^&\s]+)')
  $stateMatch = [regex]::Match($value, '(?:[?&]|\b)state=([^&\s]+)')
  if ($codeMatch.Success -and $stateMatch.Success) {
    $code = [System.Uri]::UnescapeDataString($codeMatch.Groups[1].Value)
    $state = [System.Uri]::UnescapeDataString($stateMatch.Groups[1].Value)
    $json = @{ code = $code; state = $state } | ConvertTo-Json -Compress
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
  }
  return $value
}

function Get-OpenAiModelIds {
  param(
    [string]$BaseUrl,
    [string]$ApiKey
  )

  $base = $BaseUrl.Trim().TrimEnd("/")
  if ([string]::IsNullOrWhiteSpace($base) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
    return @()
  }
  $modelsUrl = $base + "/models"
  try {
    $headers = @{ Authorization = "Bearer $ApiKey" }
    $resp = Invoke-RestMethod -Method Get -Uri $modelsUrl -Headers $headers -TimeoutSec 20
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($resp.data)) {
      if ($item -and -not [string]::IsNullOrWhiteSpace([string]$item.id)) {
        $ids.Add([string]$item.id) | Out-Null
      }
    }
    return @($ids.ToArray() | Sort-Object -Unique)
  } catch {
    Write-Warn ("模型列表获取失败：{0}" -f $_.Exception.Message)
    Write-Warn ("已尝试接口：{0}" -f $modelsUrl)
    return @()
  }
}

function Select-OmniModel {
  param(
    [string]$BaseUrl,
    [string]$ApiKey,
    [string]$DefaultModel
  )

  Write-Host ""
  Write-Host "下面选择的是 Miloco 摄像头视觉理解/家庭感知模型，不是 OpenClaw 主聊天模型。" -ForegroundColor Cyan
  Write-Host "请选择支持视觉/多模态的模型；例如 Xiaomi MIMO 里应优先用 mimo-v2.5，不要把不支持视觉的 mimo-v2.5-pro 配到这里。" -ForegroundColor Yellow
  $modelIds = @(Get-OpenAiModelIds -BaseUrl $BaseUrl -ApiKey $ApiKey)
  if ($modelIds.Count -eq 0) {
    $manual = (Read-InstallerInput ("没有拿到模型列表。请粘贴视觉模型名；直接回车使用 {0}" -f $DefaultModel)).Trim()
    if ([string]::IsNullOrWhiteSpace($manual)) {
      return $DefaultModel
    }
    return $manual
  }

  $preferred = $DefaultModel
  if ($modelIds -contains "mimo-v2.5") {
    $preferred = "mimo-v2.5"
  } elseif ($modelIds -contains "xiaomi/mimo-v2.5") {
    $preferred = "xiaomi/mimo-v2.5"
  }
  Write-Host ""
  Write-Host ("已通过 {0}/models 获取到可用模型：" -f $BaseUrl.Trim().TrimEnd("/")) -ForegroundColor Green
  for ($i = 0; $i -lt $modelIds.Count; $i++) {
    $mark = ""
    if ($modelIds[$i] -eq $preferred) {
      $mark = "  推荐用于视觉"
    } elseif ($modelIds[$i] -match 'pro$') {
      $mark = "  通常更适合 OpenClaw 主聊天，未必支持视觉"
    }
    Write-Host ("  {0}. {1}{2}" -f ($i + 1), $modelIds[$i], $mark)
  }
  while ($true) {
    $choice = (Read-InstallerInput ("请输入模型编号；直接回车使用 {0}" -f $preferred)).Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) {
      return $preferred
    }
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $modelIds.Count) {
      return $modelIds[$idx - 1]
    }
    if ($modelIds -contains $choice) {
      return $choice
    }
    Write-Warn "输入无效，请输入列表编号，或直接回车使用推荐模型。"
  }
}

function Get-HomeListFromWorkflowOutput {
  param([string[]]$OutputLines)

  $homes = New-Object System.Collections.Generic.List[object]
  foreach ($line in $OutputLines) {
    $trimmed = $line.Trim()
    if (-not $trimmed.StartsWith("{")) {
      continue
    }
    try {
      $obj = $trimmed | ConvertFrom-Json
      if ($obj -and $obj.data) {
        foreach ($item in @($obj.data)) {
          if ($item -and -not [string]::IsNullOrWhiteSpace([string]$item.home_id)) {
            $homes.Add($item) | Out-Null
          }
        }
      }
    } catch {
    }
  }
  return @($homes.ToArray())
}

function Invoke-WorkflowCapture {
  param(
    [string]$WorkflowAction,
    [string]$CaptureAuthPayload = ""
  )

  Require-File $Workflow
  $resolvedDistro = Get-ResolvedDistro
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $Workflow,
    "-Action", $WorkflowAction,
    "-Distro", $resolvedDistro,
    "-MilocoPort", [string]$script:MilocoPort,
    "-OpenClawPort", [string]$OpenClawPort
  )
  if (-not [string]::IsNullOrWhiteSpace($CaptureAuthPayload)) {
    $args += @("-AuthPayload", $CaptureAuthPayload)
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $powershellExe = Get-PowerShellExe
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    & $powershellExe @args 2>&1 | ForEach-Object {
      $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
      Write-Host $line
      $lines.Add($line) | Out-Null
    }
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  return [pscustomobject]@{
    Code = $code
    Lines = @($lines.ToArray())
  }
}

function Select-MilocoHome {
  param([object[]]$Homes)

  $homeList = @($Homes | Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.home_id) })
  if ($homeList.Count -eq 0) {
    Write-Warn "暂未获取到家庭列表。稍后可在 Miloco 面板或重新运行 install.ps1 -Action Finish 后选择。"
    return ""
  }
  if ($homeList.Count -eq 1) {
    $homeId = [string]$homeList[0].home_id
    $homeName = if ([string]::IsNullOrWhiteSpace([string]$homeList[0].home_name)) { $homeId } else { [string]$homeList[0].home_name }
    Write-Ok ("已自动选择唯一家庭：{0}  {1}" -f $homeId, $homeName)
    return $homeId
  }

  Write-Host ""
  Write-Host "检测到多个米家家庭，请选择 Miloco 要接入的家庭。" -ForegroundColor Cyan
  Write-Host "这里只会选择一个家庭；以后也可以在 Miloco 面板或控制台里切换。" -ForegroundColor Yellow
  for ($i = 0; $i -lt $homeList.Count; $i++) {
    $homeId = [string]$homeList[$i].home_id
    $homeName = if ([string]::IsNullOrWhiteSpace([string]$homeList[$i].home_name)) { "(未命名家庭)" } else { [string]$homeList[$i].home_name }
    Write-Host ("  {0}. {1}  {2}" -f ($i + 1), $homeId, $homeName)
  }
  while ($true) {
    $choice = (Read-InstallerInput "请输入家庭编号；直接回车使用第 1 个家庭").Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) {
      return [string]$homeList[0].home_id
    }
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $homeList.Count) {
      return [string]$homeList[$idx - 1].home_id
    }
    $byId = $homeList | Where-Object { [string]$_.home_id -eq $choice } | Select-Object -First 1
    if ($byId) {
      return [string]$byId.home_id
    }
    Write-Warn "输入无效，请输入列表编号，或直接回车使用第 1 个家庭。"
  }
}

function Invoke-FinishWorkflowOnce {
  param(
    [string]$FinishAuthPayload,
    [string]$FinishMimoApiKey,
    [string]$FinishOmniModel,
    [string]$FinishOmniBaseUrl,
    [string]$FinishHomeId = "",
    [switch]$NoStrictFull
  )

  Require-File $Workflow
  $resolvedDistro = Get-ResolvedDistro
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $Workflow,
    "-Action", "Finish",
    "-Distro", $resolvedDistro,
    "-MilocoPort", [string]$script:MilocoPort,
    "-OpenClawPort", [string]$OpenClawPort,
    "-AuthPayload", $FinishAuthPayload,
    "-MimoApiKey", $FinishMimoApiKey,
    "-OmniModel", $FinishOmniModel,
    "-OmniBaseUrl", $FinishOmniBaseUrl
  )
  $homeToUse = if (-not [string]::IsNullOrWhiteSpace($FinishHomeId)) { $FinishHomeId } else { $HomeId }
  if (-not [string]::IsNullOrWhiteSpace($homeToUse)) {
    $args += @("-HomeId", $homeToUse)
  }
  if (-not [string]::IsNullOrWhiteSpace($CameraDids)) {
    $args += @("-CameraDids", $CameraDids)
  }
  if ($NoStrictFull) {
    $args += "-NoStrictFull"
  }

  $powershellExe = Get-PowerShellExe
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    & $powershellExe @args 2>&1 | ForEach-Object {
      $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
      Write-Host $line
    }
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  if ($code -eq 0) {
    Install-DesktopLauncher
  }
  return $code
}

function Invoke-InteractivePostAuthSetup {
  param([switch]$FromFinishAction)

  Require-File $Workflow
  $powershellExe = Get-PowerShellExe
  $resolvedDistro = Get-ResolvedDistro

  Write-Host ""
  Write-Host "接下来可以继续完成账号授权和大模型 API 配置。" -ForegroundColor Cyan
  Write-Host "如果你现在还没有 API Key，可以直接按回车跳过，稍后再运行 install.ps1 -Action Finish。" -ForegroundColor Yellow
  Write-Host ""

  Write-Info "正在生成小米账号授权链接。"
  $bindOutput = & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $Workflow -Action BindUrl -Distro $resolvedDistro -MilocoPort $script:MilocoPort -OpenClawPort $OpenClawPort 2>&1 | ForEach-Object {
    $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
    Write-Host $line
    $line
  }
  $bindCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  $bindText = ($bindOutput -join "`n")
  $oauthMatch = [regex]::Match($bindText, 'https://account\.xiaomi\.com/oauth2/authorize[^\s"<>]+')
  if ($bindCode -eq 0 -and $oauthMatch.Success) {
    Start-UserUrl -Url $oauthMatch.Value -Label "小米账号授权页"
  } elseif ($bindCode -ne 0) {
    Write-Warn "小米账号授权链接暂时没有生成成功。你可以稍后重新运行 install.ps1 -Action BindUrl。"
  } else {
    Write-Warn "授权链接已生成但没有被自动识别。请从上方输出中复制 https://account.xiaomi.com 开头的链接手动打开。"
  }

  Write-Host ""
  Write-Host "请在浏览器里完成小米账号登录和授权。" -ForegroundColor Yellow
  Write-Host "如果页面显示 正在排队中，请先等待；这表示小米账号页面在限流，不是安装器卡住。" -ForegroundColor Yellow
  Write-Host "排队页地址里通常没有 code=，不要把这个地址粘贴回安装窗口。" -ForegroundColor Yellow
  Write-Host "不要点击退出这次排队；它可能把页面带到小米官网，和本次授权无关。" -ForegroundColor Yellow
  Write-Host "如果长时间不动，可以直接关闭这个浏览器标签页，回到安装窗口重新生成授权页。" -ForegroundColor Yellow
  Write-Host "如果浏览器跳到 https://127.0.0.1/ 后显示无法访问，这是正常现象。" -ForegroundColor Yellow
  Write-Host "请复制浏览器地址栏里包含 code= 和 state= 的完整地址，粘贴回这里。" -ForegroundColor Yellow
  $interactiveAuthPayload = (Read-InstallerInput "授权完成后，粘贴授权码或完整回调地址；暂时没有就直接回车跳过").Trim()
  if ([string]::IsNullOrWhiteSpace($interactiveAuthPayload)) {
    Write-Warn "已跳过小米账号授权收尾。基础服务仍可用，稍后可以重新运行 install.ps1 -Action Finish。"
    if ($FromFinishAction) {
      return 1
    }
    return 0
  }
  $interactiveAuthPayload = ConvertTo-MilocoAuthPayload $interactiveAuthPayload

  Write-Host ""
  Write-Info "正在提交小米账号授权，并获取可选择的家庭列表。"
  $authorizeResult = Invoke-WorkflowCapture -WorkflowAction "AuthorizeOnly" -CaptureAuthPayload $interactiveAuthPayload
  if ($authorizeResult.Code -ne 0) {
    Write-Warn ("小米账号授权没有完成，退出码：{0}。请保留窗口输出继续排查。" -f $authorizeResult.Code)
    if ($FromFinishAction) {
      return $authorizeResult.Code
    }
    return 0
  }
  $homes = @(Get-HomeListFromWorkflowOutput -OutputLines $authorizeResult.Lines)
  if ($homes.Count -eq 0) {
    Write-Info "授权已提交，正在重新读取家庭列表。"
    $homeResult = Invoke-WorkflowCapture -WorkflowAction "ListHomes"
    if ($homeResult.Code -eq 0) {
      $homes = @(Get-HomeListFromWorkflowOutput -OutputLines $homeResult.Lines)
    }
  }
  $selectedHomeId = Select-MilocoHome -Homes $homes

  Write-Host ""
  Write-Host "提示：如果您没有自己的大模型API，可以申请下述任意的免费试用API。" -ForegroundColor Yellow
  $apiOptions = @(
    @{ Id = "01"; ShortId = "1"; Name = "Xiaomi MIMO"; Url = "https://platform.xiaomimimo.com?ref=QHSHXL"; BaseUrl = "https://api.xiaomimimo.com/v1"; Model = "xiaomi/mimo-v2.5" },
    @{ Id = "02"; ShortId = "2"; Name = "Agnes"; Url = "https://platform.agnes-ai.com/settings/apiKeys"; BaseUrl = ""; Model = "" },
    @{ Id = "03"; ShortId = "3"; Name = "商汤科技"; Url = "https://platform.sensenova.cn/console/keys"; BaseUrl = ""; Model = "" }
  )
  foreach ($option in $apiOptions) {
    Write-Host ("{0} [{1}] {2}" -f $option.Id, $option.Name, $option.Url)
  }
  $apiChoice = (Read-InstallerInput "如需打开申请页面，请输入 01/02/03；已有 Key 直接回车").Trim()
  $selectedApi = $apiOptions | Where-Object { $_.Id -eq $apiChoice -or $_.ShortId -eq $apiChoice } | Select-Object -First 1
  if ($selectedApi) {
    Start-UserUrl -Url $selectedApi.Url -Label ($selectedApi.Name + " API 申请页")
  }

  Write-Host ""
  $interactiveApiKey = (Read-InstallerInput "请粘贴 API Key；暂时没有就直接回车跳过").Trim()
  if ([string]::IsNullOrWhiteSpace($interactiveApiKey)) {
    Write-Warn "已跳过 API 配置。稍后拿到 Key 后可以重新运行 install.ps1 -Action Finish。"
    if ($FromFinishAction) {
      return 1
    }
    return 0
  }

  $defaultBaseUrl = if ($selectedApi) { $selectedApi.BaseUrl } else { $OmniBaseUrl }
  $defaultModel = if ($selectedApi -and -not [string]::IsNullOrWhiteSpace($selectedApi.Model)) { $selectedApi.Model } else { $OmniModel }
  if ([string]::IsNullOrWhiteSpace($defaultBaseUrl)) {
    $interactiveBaseUrl = (Read-InstallerInput "请粘贴 Base URL，例如 https://.../v1；此项不能为空").Trim()
  } else {
    $interactiveBaseUrl = (Read-InstallerInput ("请粘贴 Base URL；直接回车使用 {0}" -f $defaultBaseUrl)).Trim()
  }
  if ([string]::IsNullOrWhiteSpace($interactiveBaseUrl) -and -not [string]::IsNullOrWhiteSpace($defaultBaseUrl)) {
    $interactiveBaseUrl = $defaultBaseUrl
  }
  if ([string]::IsNullOrWhiteSpace($interactiveBaseUrl)) {
    Write-Warn "Base URL 为空，已跳过 API 配置。"
    if ($FromFinishAction) {
      return 1
    }
    return 0
  }
  $interactiveModel = Select-OmniModel -BaseUrl $interactiveBaseUrl -ApiKey $interactiveApiKey -DefaultModel $defaultModel

  Write-Host ""
  Write-Info "正在写入小米账号授权和大模型 API 配置。"
  $finishCode = Invoke-FinishWorkflowOnce -FinishAuthPayload $interactiveAuthPayload -FinishMimoApiKey $interactiveApiKey -FinishOmniModel $interactiveModel -FinishOmniBaseUrl $interactiveBaseUrl -FinishHomeId $selectedHomeId -NoStrictFull
  if ($finishCode -eq 0) {
    Write-Ok "账号授权和 API 配置已执行完成。"
    Write-Host ""
    Write-Host "说明：刚才配置的是 Miloco 摄像头视觉理解/家庭感知模型，并同步给 Miloco OpenClaw 插件使用。" -ForegroundColor Cyan
    Write-Host "OpenClaw 主聊天模型是另一套配置；如果 OpenClaw 聊天提示没有 provider API Key，需要在 OpenClaw 的模型/代理设置里继续配置主聊天 LLM。" -ForegroundColor Yellow
    Write-Host "推荐思路：Miloco 视觉用支持视觉的模型，例如 mimo-v2.5；OpenClaw 主聊天可用更强的文本模型，例如 mimo-v2.5-pro。" -ForegroundColor Yellow
  } else {
    Write-Warn ("账号/API 收尾没有完全成功，退出码：{0}。请保留窗口输出或诊断报告继续排查。" -f $finishCode)
  }
  return $finishCode
}

function Invoke-Workflow {
  param([string]$WorkflowAction)

  Require-File $Workflow
  $resolvedDistro = Get-ResolvedDistro
  if ($WorkflowAction -eq "Finish" -and [string]::IsNullOrWhiteSpace($MimoApiKey)) {
    $interactiveCode = Invoke-InteractivePostAuthSetup -FromFinishAction
    exit $interactiveCode
  }
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $Workflow,
    "-Action", $WorkflowAction,
    "-Distro", $resolvedDistro,
    "-MilocoPort", [string]$script:MilocoPort,
    "-OpenClawPort", [string]$OpenClawPort
  )

  if ($WorkflowAction -eq "Report") {
    $reportPath = Join-Path $PackageRoot ("miloco-deploy-report-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    $args += @("-ReportPath", $reportPath)
  }

  if ($WorkflowAction -eq "Finish") {
    $args += @(
      "-MimoApiKey", $MimoApiKey,
      "-OmniModel", $OmniModel,
      "-OmniBaseUrl", $OmniBaseUrl
    )
    if (-not [string]::IsNullOrWhiteSpace($AuthPayload)) {
      $args += @("-AuthPayload", $AuthPayload)
    }
    if (-not [string]::IsNullOrWhiteSpace($HomeId)) {
      $args += @("-HomeId", $HomeId)
    }
    if (-not [string]::IsNullOrWhiteSpace($CameraDids)) {
      $args += @("-CameraDids", $CameraDids)
    }
  }

  $powershellExe = Get-PowerShellExe
  & $powershellExe @args
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  if ($code -eq 0 -and $WorkflowAction -eq "Finish") {
    Install-DesktopLauncher
  }
  exit $code
}

function Invoke-Prepare {
  Write-Banner

  Write-Step "检查安装包文件是否完整"
  Require-File $ManifestPath
  Require-File $InstallSh
  Require-File $Workflow
  Write-Ok "安装包文件：已找到 install.ps1、manifest.json、payload 和诊断脚本。"

  Write-Step "检查 README 中列出的 Windows 环境依赖"
  Check-Prerequisites
  Write-Host "[说明] Python / Node / uv：不需要你提前安装，后续安装器会自动准备。" -ForegroundColor Gray
  Write-Host "[说明] OpenClaw：不需要你提前安装，后续安装器会自动安装或启动。" -ForegroundColor Gray
  Write-Host "[说明] 小米账号和大模型 API：基础服务完成后，脚本会打开授权页并等你粘贴授权码和 API 信息。" -ForegroundColor Gray
  Write-Host "[说明] 米家摄像头：脚本不能代替你在米家 App 里绑定摄像头；基础配置完成后再选择要启用的摄像头。" -ForegroundColor Gray

  Write-Step "检查和准备 WSL2 / Ubuntu"
  Ensure-Wsl
  if ($InstallWsl) {
    Write-Ok "WSL2 / Ubuntu 环境已准备好。"
    Exit-Installer 0
  }

  Write-Step "检测是否已经安装过 Miloco"
  $existingStatus = Get-ExistingInstallStatus
  $migratedExisting = Prepare-ExistingInstallForCleanInstall $existingStatus
  if ($migratedExisting) {
    Resolve-MilocoPort $null | Out-Null
  } else {
    Resolve-MilocoPort $existingStatus | Out-Null
  }

  $manifest = Get-Content -Encoding utf8 -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  $version = [string]$manifest.version
  if ([string]::IsNullOrWhiteSpace($version)) {
    Fail "manifest.json 里缺少版本号。请重新下载完整 zip 包。"
  }

  $bundle = Get-ChildItem -LiteralPath $PayloadDir -Filter "miloco-linux-x86_64-*.tar.gz" | Select-Object -First 1
  if (-not $bundle) {
    Fail "payload 文件夹里没有找到 Miloco 离线安装包。请重新下载完整 zip 包。"
  }

  $wslBundle = ConvertTo-WslPath $bundle.FullName
  $wslInstallSh = ConvertTo-WslPath $InstallSh

  Write-Step "把 Miloco 离线安装包放入 WSL 缓存"
  $prime = @'
set -euo pipefail
export MILOCO_HOME="${MILOCO_HOME:-$HOME/.openclaw/miloco}"
cache="$MILOCO_HOME/.install-cache/__VERSION__"
mkdir -p "$cache"
rm -rf "$cache"
mkdir -p "$cache"
tar -xzf "__WSL_BUNDLE__" -C "$cache"
'@
  $prime = $prime.Replace("__VERSION__", $version).Replace("__WSL_BUNDLE__", $wslBundle)
  Invoke-WslBash $prime
  Write-Ok "Miloco 离线安装包：已准备。"

  Write-Step "安装并启动 Miloco 基础服务"
  $install = @'
set -euo pipefail
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"
export GITHUB_PROXY_PREFIX="__GITHUB_PROXY_PREFIX__"
printf '[正在处理] 正在安装 Miloco 主程序和命令行工具，这一步可能需要几分钟...\n'
if ! bash "__WSL_INSTALL_SH__" --agent-prepare >/tmp/miloco-agent-prepare.log 2>&1; then
  printf '[失败] Miloco 主程序安装失败。\n' >&2
  printf '详细日志在 WSL 内：/tmp/miloco-agent-prepare.log\n' >&2
  exit 43
fi
hash -r
if ! command -v miloco-cli >/dev/null 2>&1; then
  printf '[失败] Miloco 安装命令执行完成，但 miloco-cli 仍然不可用。\n' >&2
  printf '详细日志在 WSL 内：/tmp/miloco-agent-prepare.log\n' >&2
  exit 42
fi
printf '[正在处理] 正在把 Miloco 服务地址设置为 http://127.0.0.1:__MILOCO_PORT__ ...\n'
supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-windows-supervisor-stop.log 2>&1 || true
pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
sleep 2
pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
if ! python3 - <<'PY' >/tmp/miloco-windows-config-port.log 2>&1
import json
from pathlib import Path

port = __MILOCO_PORT__
path = Path.home() / ".openclaw" / "miloco" / "config.json"
data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
server = data.setdefault("server", {})
server["url"] = f"http://127.0.0.1:{port}"
server["port"] = port
tmp = path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
tmp.replace(path)
print(f"server.url=http://127.0.0.1:{port}")
print(f"server.port={port}")
PY
then
  printf '[失败] Miloco 服务地址和监听端口配置写入失败。\n' >&2
  printf '详细日志在 WSL 内：/tmp/miloco-windows-config-port.log\n' >&2
  exit 44
fi
read -r actual_url actual_port <<EOF
$(python3 - <<'PY'
import json
from pathlib import Path

path = Path.home() / ".openclaw" / "miloco" / "config.json"
data = json.loads(path.read_text(encoding="utf-8"))
server = data.get("server", {})
print(server.get("url", ""), server.get("port", ""))
PY
)
EOF
if [ "$actual_url" != "http://127.0.0.1:__MILOCO_PORT__" ] || [ "$actual_port" != "__MILOCO_PORT__" ]; then
  printf '[失败] Miloco 服务地址或监听端口配置没有生效。当前 url=%s port=%s\n' "$actual_url" "$actual_port" >&2
  exit 45
fi
set +e
miloco-cli service start >/tmp/miloco-windows-service-start.log 2>&1
start_rc=$?
set -e

health_body=/tmp/miloco-windows-health-body.txt
health_err=/tmp/miloco-windows-health-curl.err
last_running_status=""
for i in $(seq 1 90); do
  http_code="$(curl -sS --max-time 2 -o "$health_body" -w "%{http_code}" "http://127.0.0.1:__MILOCO_PORT__/health" 2>"$health_err" || true)"
  body="$(cat "$health_body" 2>/dev/null || true)"
  if [ "$http_code" = "200" ] && printf '%s' "$body" | grep -q '"status":"ok"'; then
    printf '[OK] Miloco 后端已在端口 __MILOCO_PORT__ 启动。\n'
    exit 0
  fi
  last_running_status="$(miloco-cli service status 2>/dev/null || true)"
  if printf '%s' "$last_running_status" | grep -Eq '"running"[[:space:]]*:[[:space:]]*true'; then
    if [ "$http_code" = "502" ] || [ "$http_code" = "503" ]; then
      if [ "$i" -ge 45 ]; then
        printf '[警告] Miloco 进程和端口已启动，但 /health 暂时返回 HTTP %s。\n' "$http_code" >&2
        printf '[说明] 这通常是首次启动、设备扫描或内部节点还在预热；安装器会继续完成基础部署，后续诊断报告会继续检查。\n' >&2
        printf '[诊断] miloco-cli service status：%s\n' "$last_running_status" >&2
        exit 0
      fi
    fi
  fi
  if [ "$http_code" = "503" ] && printf '%s' "$body" | grep -Eq '"status":"(unhealthy|unknown)"'; then
    printf '[警告] Miloco 后端 API 已经启动，但 /health 还不是 ok：%s\n' "$body" >&2
    printf '[说明] 这通常表示内部节点还没满足条件或启动期自检未通过；安装器会继续完成基础部署，后续诊断报告会继续检查。\n' >&2
    exit 0
  fi
  sleep 1
done

printf '[失败] Miloco 后端没有在端口 __MILOCO_PORT__ 正常响应。\n' >&2
printf 'miloco-cli service start 退出码：%s\n' "$start_rc" >&2
printf '最后一次 /health HTTP 状态：%s\n' "${http_code:-none}" >&2
if [ -s "$health_body" ]; then
  printf '最后一次 /health 响应：\n' >&2
  tail -n 20 "$health_body" >&2 || true
fi
if [ -s "$health_err" ]; then
  printf '最后一次 curl 错误：\n' >&2
  tail -n 20 "$health_err" >&2 || true
fi
printf '\n[诊断] miloco-cli service status：\n' >&2
miloco-cli service status >&2 || true
printf '\n[诊断] supervisor 状态：\n' >&2
supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" status >&2 || true
printf '\n[诊断] WSL 端口监听：\n' >&2
ss -tlnp "sport = :__MILOCO_PORT__" >&2 || true
printf '\n[诊断] /tmp/miloco-windows-service-start.log 尾部：\n' >&2
tail -n 80 /tmp/miloco-windows-service-start.log >&2 || true
printf '\n[诊断] ~/.openclaw/miloco/log/miloco-backend.log 尾部：\n' >&2
tail -n 120 "$HOME/.openclaw/miloco/log/miloco-backend.log" >&2 || true
printf '详细日志在 WSL 内：/tmp/miloco-windows-service-start.log 和 ~/.openclaw/miloco/log/miloco-backend.log\n' >&2
exit 47
'@
  $install = $install.Replace("__GITHUB_PROXY_PREFIX__", [string]$global:GITHUB_PROXY_PREFIX).Replace("__WSL_INSTALL_SH__", $wslInstallSh).Replace("__MILOCO_PORT__", [string]$script:MilocoPort)
  Invoke-WslBash $install
  Write-Ok "Miloco 基础安装命令已执行完成。"

  Write-Step "检查和安装 OpenClaw 控制台依赖"
  $openclaw = @'
set -euo pipefail
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"
cache="$HOME/.openclaw/miloco/.install-cache/__VERSION__"
if ! command -v openclaw >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    printf '[失败] 需要安装 OpenClaw，但 WSL 内没有 curl。\n' >&2
    exit 51
  fi
  printf '[正在处理] 未检测到 openclaw，正在安装 OpenClaw CLI...\n'
  if ! curl -fsSL https://openclaw.ai/install-cli.sh -o /tmp/openclaw-install-cli.sh; then
    printf '[失败] 下载 OpenClaw 安装脚本失败。\n' >&2
    printf '请检查网络是否能访问 https://openclaw.ai/install-cli.sh，或换网络/代理后重新双击 install.bat。\n' >&2
    exit 53
  fi
  if ! bash /tmp/openclaw-install-cli.sh --prefix "$HOME/.openclaw" >/tmp/openclaw-install-cli.log 2>&1; then
    printf '[失败] OpenClaw CLI 安装脚本执行失败。\n' >&2
    printf '详细日志在 WSL 内：/tmp/openclaw-install-cli.log\n' >&2
    printf '请处理网络或 Node/OpenClaw 安装问题后重新双击 install.bat。\n' >&2
    exit 54
  fi
  printf '[OK] OpenClaw CLI 安装完成。\n'
fi
hash -r
if ! command -v openclaw >/dev/null 2>&1; then
  printf '[失败] OpenClaw CLI 安装后仍不可用。\n' >&2
  printf '请检查网络是否能访问 https://openclaw.ai/install-cli.sh。\n' >&2
  exit 52
fi
plugin_pkg=""
if [ -d "$cache" ]; then
  plugin_pkg="$(find "$cache" -maxdepth 1 -type f -name '*.tgz' | head -n 1)"
fi
if [ -z "$plugin_pkg" ]; then
  printf '[失败] 安装包缓存里没有找到 Miloco OpenClaw 插件文件。\n' >&2
  printf '请重新下载完整 zip 包后再运行 install.bat。\n' >&2
  exit 55
fi
openclaw plugins install --force "$plugin_pkg" >/tmp/openclaw-miloco-plugin-install.log 2>&1 || {
  printf '[失败] Miloco OpenClaw 插件安装失败。\n' >&2
  printf '详细日志在 WSL 内：/tmp/openclaw-miloco-plugin-install.log\n' >&2
  exit 56
}
openclaw gateway --dev --bind loopback --port "__OPENCLAW_PORT__" install --port "__OPENCLAW_PORT__" >/tmp/openclaw-windows-install.log 2>&1 || true
openclaw gateway restart >/tmp/openclaw-windows-restart.log 2>&1 || openclaw gateway start >/tmp/openclaw-windows-start.log 2>&1 || systemctl --user restart openclaw-gateway.service >/tmp/openclaw-windows-systemd-restart.log 2>&1 || true
'@
  $openclaw = $openclaw.Replace("__OPENCLAW_PORT__", [string]$OpenClawPort).Replace("__VERSION__", $version)
  Invoke-WslBash $openclaw
  Write-Ok "OpenClaw CLI 已可用，Gateway 启动命令已执行。"

  Write-Step "创建桌面控制台"
  Install-DesktopLauncher
  Write-Ok "桌面控制台已准备好，后续可用于重启或关闭 Miloco/OpenClaw。"

  Write-Step "生成安装诊断报告"
  $powershellExe = Get-PowerShellExe
  $resolvedDistro = Get-ResolvedDistro
  $reportPath = Join-Path $PackageRoot ("miloco-deploy-report-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
  & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $Workflow -Action Report -Distro $resolvedDistro -MilocoPort $script:MilocoPort -OpenClawPort $OpenClawPort -ReportPath $reportPath
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

  $continueToPostAuth = $false
  if ($code -ne 0) {
    $continueToPostAuth = Test-ReportAllowsPostAuthSetup $reportPath
    if ($continueToPostAuth) {
      Write-Warn "基础服务已经完成，但账号授权或 API 配置还没有完成。安装器将继续进入后配置流程。"
    } else {
      $diagnosticLines = Get-ReportTroubleshootingLines $reportPath
      Stop-ForUser "安装命令已经执行完成，但 Miloco/OpenClaw 面板还没有通过自动检查。" $diagnosticLines $code
    }
  }

  Write-Step "安装完成，提示验证和使用入口"
  Write-Host ""
  $desktopConsoleName = "Miloco " + [string][char]0x63A7 + [string][char]0x5236 + [string][char]0x53F0 + ".bat"
  $desktopConsole = Join-Path ([Environment]::GetFolderPath("Desktop")) $desktopConsoleName
  $openClawShortcutName = "OpenClaw " + [string][char]0x5BF9 + [string][char]0x8BDD + [string][char]0x5165 + [string][char]0x53E3 + ".lnk"
  $openClawShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) $openClawShortcutName
  Write-Host "[OK] easy-miloco 基础安装已经完成。" -ForegroundColor Green
  Write-Host ""
  Write-Host "从现在开始，你可以用下面这些桌面入口验证和使用 Miloco：" -ForegroundColor Cyan
  Write-Host ("  {0}" -f $desktopConsole) -ForegroundColor White
  Write-Host ("  {0}" -f $openClawShortcut) -ForegroundColor White
  Write-Host ""
  Write-Host "建议先双击 Miloco 控制台，然后选择："
  Write-Host "  3. 重启 Miloco + OpenClaw    一次性拉起整套服务"
  Write-Host "  2. 重启 Miloco 面板          打开 Miloco 面板"
  Write-Host "  1. 重启 OpenClaw 面板        打开 OpenClaw 面板"
  Write-Host ""
  Write-Host ("Miloco 面板地址：   http://127.0.0.1:{0}/" -f $script:MilocoPort)
  Write-Host "OpenClaw 入口：     请用桌面的 OpenClaw 对话入口；不要直接打开裸端口地址。"
  Write-Host ("本次诊断报告：      {0}" -f $reportPath)
  if (-not [string]::IsNullOrWhiteSpace($script:ExistingRestorePackPath)) {
    Write-Host ""
    Write-Host "[重要] 检测到旧版安装，安装器已把旧版用户配置导出为恢复 ZIP：" -ForegroundColor Yellow
    Write-Host ("  {0}" -f $script:ExistingRestorePackPath) -ForegroundColor White
    Write-Host "这个 ZIP 内包含家庭档案、成员/身份库、家庭任务、模型配置等可恢复资产。" -ForegroundColor Yellow
    Write-Host "如果需要恢复旧配置，请复制上面这个 ZIP 文件路径，发给本机 OpenClaw，命令它按照 ZIP 内 AGENTS.md 尝试恢复，以确保最大兼容性。" -ForegroundColor Yellow
  }
  $postAuthCode = Invoke-InteractivePostAuthSetup
  Write-Host ""
  if ($postAuthCode -eq 0) {
    Write-Host "[OK] 自动安装阶段完成。" -ForegroundColor Green
  } else {
    Write-Warn "基础安装已完成，但账号/API 收尾还需要继续处理。"
  }
  Exit-Installer 0
}

function Invoke-Uninstall {
  $script:PhaseIndex = 0
  $script:PhaseTotal = 4
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "        easy-miloco Windows 卸载向导" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan

  Write-Step "停止 Windows 侧后台任务"
  & cmd.exe /d /c "schtasks.exe /End /TN MilocoWSLKeeper >nul 2>nul" | Out-Null
  & cmd.exe /d /c "schtasks.exe /Delete /TN MilocoWSLKeeper /F >nul 2>nul" | Out-Null
  Write-Ok "Windows 计划任务：已尝试停止并删除。"

  Write-Step "删除桌面控制台入口"
  $desktop = [Environment]::GetFolderPath("Desktop")
  $desktopConsoleName = "Miloco " + [string][char]0x63A7 + [string][char]0x5236 + [string][char]0x53F0 + ".bat"
  $openClawShortcutName = "OpenClaw " + [string][char]0x5BF9 + [string][char]0x8BDD + [string][char]0x5165 + [string][char]0x53E3 + ".lnk"
  foreach ($path in @(
    (Join-Path $desktop $desktopConsoleName),
    (Join-Path $desktop "miloco-console.ps1"),
    (Join-Path $desktop $openClawShortcutName),
    (Join-Path $desktop "miloco-openclaw.ps1"),
    (Join-Path $desktop "miloco-xiaomi-oauth.url"),
    (Join-Path $desktop "miloco-xiaomi-oauth.txt")
  )) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    $full = [System.IO.Path]::GetFullPath($path)
    $desktopRoot = ([System.IO.Path]::GetFullPath($desktop)).TrimEnd("\") + "\"
    if ($full.StartsWith($desktopRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    }
  }
  Write-Ok "桌面入口：已删除 Miloco 相关文件。"

  Write-Step "卸载 WSL 内 Miloco 组件"
  $wslExe = Get-WslExePath
  if ([string]::IsNullOrWhiteSpace($wslExe)) {
    Write-Warn "没有检测到 WSL 命令，跳过 WSL 内卸载。"
  } else {
    $list = (& $wslExe -l -v 2>&1 | Out-String) -replace "`0", ""
    $rows = @(Get-WslDistroRows $list)
    $selected = $rows | Where-Object { $_.Name -eq $Distro } | Select-Object -First 1
    if (-not $selected) {
      $selected = $rows | Where-Object { $_.Name -match "(?i)ubuntu" } | Select-Object -First 1
    }
    if (-not $selected) {
      Write-Warn "没有找到 Ubuntu WSL 发行版，跳过 WSL 内卸载。"
    } else {
      $script:ResolvedDistro = $selected.Name
      $uninstall = @'
set +e
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
systemctl --user disable --now openclaw-gateway.service >/tmp/openclaw-uninstall-stop.log 2>&1 || true
rm -f "$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service" 2>/dev/null || true
systemctl --user daemon-reload >/dev/null 2>&1 || true
supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/miloco-uninstall-supervisor-stop.log 2>&1 || true
pkill -TERM -f "[w]indows-keeper.sh" 2>/dev/null || true
pkill -TERM -f "[w]sl-miloco-keeper.sh" 2>/dev/null || true
pkill -TERM -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
pkill -TERM -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true
sleep 1
pkill -KILL -f "/home/.*/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
pkill -KILL -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true
if command -v openclaw >/dev/null 2>&1; then
  printf 'y\n' | openclaw plugins uninstall miloco-openclaw-plugin >/tmp/openclaw-miloco-plugin-uninstall.log 2>&1 || true
fi
if command -v uv >/dev/null 2>&1; then
  uv tool uninstall miloco-cli >/tmp/miloco-cli-uninstall.log 2>&1 || true
  uv tool uninstall miloco >/tmp/miloco-uninstall.log 2>&1 || true
  uv tool uninstall supervisor >/tmp/miloco-supervisor-uninstall.log 2>&1 || true
fi
rm -rf "$HOME/.openclaw/miloco"
rm -f /tmp/miloco-* /tmp/openclaw-miloco-plugin-uninstall.log /tmp/openclaw-uninstall-stop.log 2>/dev/null || true
exit 0
'@
      Invoke-WslBash $uninstall
      & $wslExe --terminate $script:ResolvedDistro *> $null
      Write-Ok ("WSL 内 Miloco：已从 {0} 卸载并关闭该 WSL 会话。" -f $script:ResolvedDistro)
    }
  }

  Write-Step "卸载完成"
  Write-Ok "Miloco/OpenClaw 插件、Miloco 数据目录、后台任务和桌面入口已完成清理。"
  Exit-Installer 0
}

Start-InstallerLog

switch ($Action) {
  "Prepare" { Invoke-Prepare }
  "Report" { Invoke-Workflow "Report" }
  "BindUrl" { Invoke-Workflow "BindUrl" }
  "Finish" { Invoke-Workflow "Finish" }
  "Validate" { Invoke-Workflow "Validate" }
  "Uninstall" { Invoke-Uninstall }
}
