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
    [int]$ExitCode = 1
  )

  Write-Host ""
  Write-Host ("[安装暂停] {0}" -f $Title) -ForegroundColor Yellow
  foreach ($line in $Lines) {
    Write-Host $line -ForegroundColor Yellow
  }
  Write-Host ""
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
  try {
    $output = & wsl.exe -d $Name -- bash -lc "cp '${wslMnt}' '${wslTmp}' && bash '${wslTmp}'; rc=`$?; rm -f '${wslTmp}'; exit `$rc" 2>&1 | ForEach-Object {
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

  ## WSL 检测：检查 wsl.exe 是否存在。这里检测的是 WSL 命令，不是 Ubuntu 发行版。
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
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
    Stop-ForUser "WSL 组件已启用，需要重启电脑。" @(
      "请现在重启 Windows。",
      "重启后重新双击 install.bat，安装会自动继续。"
    )
  }

  ## WSL 真实注册名列表：读取 wsl.exe -l -v，不再只相信默认名字 Ubuntu-24.04。
  $list = $null
  try {
    $list = (& wsl.exe -l -v 2>&1 | Out-String) -replace "`0", ""
  } catch {
    $list = $null
  }

  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($list)) {
    Write-Info "WSL 命令存在，但当前状态异常，正在尝试自动更新和修复。"
    & wsl.exe --update
    if ($InstallIfMissing) {
      & wsl.exe --install -d $Distro
    }
    if ($LASTEXITCODE -ne 0) {
      Stop-ForUser "WSL 自动修复失败。" @(
        "请先确认 Windows 已开启 CPU 虚拟化。",
        "然后打开 Microsoft Store 更新 WSL，或在管理员 PowerShell 里运行：wsl --update",
        "处理好后重新双击 install.bat。"
      )
    }
    Stop-ForUser "WSL 已修复，可能需要重启电脑。" @(
      "请重启 Windows。",
      "重启后重新双击 install.bat，安装会自动继续。"
    )
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
    & wsl.exe --install -d $Distro
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
    )
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

  try {
    & wsl.exe -d $resolvedDistro -- cp $wslMnt $wslTmp
    $copyCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($copyCode -ne 0) {
      Fail "无法把临时脚本复制到 WSL，退出码 $copyCode。请把窗口内容发给维护者。"
    }

    & wsl.exe -d $resolvedDistro -- bash $wslTmp
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($code -ne 0) {
      Fail "WSL 内命令执行失败，退出码 $code。上方通常有具体错误，请把窗口内容或诊断报告发给维护者。"
    }
  } finally {
    & wsl.exe -d $resolvedDistro -- rm -f $wslTmp *> $null
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

  $copyOutput = & wsl.exe -d $resolvedDistro -- cp $wslMnt $wslTmp 2>&1 | ForEach-Object {
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
    $output = & wsl.exe -d $resolvedDistro -- bash $wslTmp 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_.Exception.Message
      } else {
        $_.ToString()
      }
    }
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  } finally {
    & wsl.exe -d $resolvedDistro -- rm -f $wslTmp *> $null
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

function Confirm-OverwriteExistingInstall {
  param([object]$Status)

  if (-not $Status.detected) {
    Write-Ok "没有发现已有 Miloco 安装痕迹。"
    return
  }

  Write-Host ""
  Write-Host "[需要确认] 检测到这台电脑上已经有 Miloco 安装痕迹。" -ForegroundColor Yellow
  Write-Host "当前检测结果：" -ForegroundColor Yellow
  foreach ($name in @("MILOCO_CLI", "OPENCLAW_CLI", "MILOCO_HOME", "MILOCO_SERVICE", "MILOCO_HEALTH", "OPENCLAW_HTTP", "MILOCO_PLUGIN", "MILOCO_URL")) {
    $value = if ($Status.values.ContainsKey($name)) { $Status.values[$name] } else { "unknown" }
    Write-Host ("  {0}: {1}" -f $name, $value) -ForegroundColor Yellow
  }
  Write-Host ""
  Write-Host "请选择下一步：" -ForegroundColor Yellow
  Write-Host "  C = 覆盖安装/修复：保留已有配置，重新执行安装和启动步骤。" -ForegroundColor Yellow
  Write-Host "  Q = 退出：不改动当前安装。" -ForegroundColor Yellow

  while ($true) {
    $choice = (Read-Host "请输入 C 或 Q").Trim().ToUpperInvariant()
    if ($choice -eq "C") {
      Write-Info "已选择覆盖安装/修复，继续执行。"
      return
    }
    if ($choice -eq "Q") {
      Stop-ForUser "已按你的选择退出。" @(
        "当前安装没有被改动。",
        "如果之后想重新安装，请再次双击 install.bat，并选择 C。"
      ) 0
    }
    Write-Host "请输入 C 或 Q。" -ForegroundColor Yellow
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

function Test-Distro {
  & wsl.exe -d $script:Distro -- true > $null 2> $null
  if ($LASTEXITCODE -eq 0) {
    return $true
  }

  Write-Host ""
  Write-Host ("找不到安装时使用的 WSL 发行版：{0}" -f $script:Distro) -ForegroundColor Yellow
  Write-Host "当前可用发行版：" -ForegroundColor Yellow
  & wsl.exe -l -v
  return $false
}

function Invoke-WslBash {
  param([string]$Command)

  if (-not (Test-Distro)) {
    return $false
  }

  $normalized = $Command -replace "`r`n", "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  & wsl.exe -d $script:Distro -- bash -lc "printf '%s' '$encoded' | base64 -d | bash"
  if ($LASTEXITCODE -ne 0) {
    Write-Host ("调用 WSL 失败，退出码：{0}" -f $LASTEXITCODE) -ForegroundColor Red
    return $false
  }
  return $true
}

function Open-WhenReady {
  param([int]$Port)

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
    Start-Process ("http://127.0.0.1:{0}/" -f $Port)
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
    Open-WhenReady $script:OpenClawPort
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
    Open-WhenReady $script:OpenClawPort
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
  & wsl.exe --terminate $script:Distro
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
  $ps1 = $ps1.Replace("__DISTRO__", $resolvedDistro).Replace("__MILOCO_PORT__", [string]$script:MilocoPort).Replace("__OPENCLAW_PORT__", [string]$OpenClawPort)
  [System.IO.File]::WriteAllText($launcher, $bat, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($psLauncher, $ps1, [System.Text.UTF8Encoding]::new($true))
  Write-Host "桌面控制台入口已创建：$launcher"
  Write-Host "桌面控制台脚本已创建：$psLauncher"
}

function Invoke-Workflow {
  param([string]$WorkflowAction)

  Require-File $Workflow
  $resolvedDistro = Get-ResolvedDistro
  if ($WorkflowAction -eq "Finish" -and [string]::IsNullOrWhiteSpace($MimoApiKey)) {
    Fail "完成授权配置需要 MiMo API Key。请先准备好 MiMo API Key，再运行：.\install.ps1 -Action Finish -AuthPayload '<小米授权内容>' -MimoApiKey '<你的 Key>'"
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
  Write-Host "[说明] 小米账号、MiMo API Key、米家摄像头：脚本不能代替你登录或准备，会在基础安装完成后提示下一步。" -ForegroundColor Gray

  Write-Step "检查和准备 WSL2 / Ubuntu"
  Ensure-Wsl
  if ($InstallWsl) {
    Write-Ok "WSL2 / Ubuntu 环境已准备好。"
    Exit-Installer 0
  }

  Write-Step "检测是否已经安装过 Miloco"
  $existingStatus = Get-ExistingInstallStatus
  Confirm-OverwriteExistingInstall $existingStatus
  Resolve-MilocoPort $existingStatus | Out-Null

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
if ! ls "$cache"/miloco-*.whl >/dev/null 2>&1 || ! ls "$cache"/miloco_cli-*.whl >/dev/null 2>&1 || ! ls "$cache"/*.tgz >/dev/null 2>&1; then
  rm -rf "$cache"
  mkdir -p "$cache"
  tar -xzf "__WSL_BUNDLE__" -C "$cache"
fi
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
for i in $(seq 1 90); do
  http_code="$(curl -sS --max-time 2 -o "$health_body" -w "%{http_code}" "http://127.0.0.1:__MILOCO_PORT__/health" 2>"$health_err" || true)"
  body="$(cat "$health_body" 2>/dev/null || true)"
  if [ "$http_code" = "200" ] && printf '%s' "$body" | grep -q '"status":"ok"'; then
    printf '[OK] Miloco 后端已在端口 __MILOCO_PORT__ 启动。\n'
    exit 0
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

  if ($code -ne 0) {
    $diagnosticLines = Get-ReportTroubleshootingLines $reportPath
    Stop-ForUser "安装命令已经执行完成，但 Miloco/OpenClaw 面板还没有通过自动检查。" $diagnosticLines $code
  }

  Write-Step "安装完成，提示验证和使用入口"
  Write-Host ""
  $desktopConsoleName = "Miloco " + [string][char]0x63A7 + [string][char]0x5236 + [string][char]0x53F0 + ".bat"
  $desktopConsole = Join-Path ([Environment]::GetFolderPath("Desktop")) $desktopConsoleName
  Write-Host "[OK] easy-miloco 基础安装已经完成。" -ForegroundColor Green
  Write-Host ""
  Write-Host "从现在开始，你可以用下面这个桌面脚本验证和使用 Miloco：" -ForegroundColor Cyan
  Write-Host ("  {0}" -f $desktopConsole) -ForegroundColor White
  Write-Host ""
  Write-Host "建议先双击它，然后选择："
  Write-Host "  3. 重启 Miloco + OpenClaw    一次性拉起整套服务"
  Write-Host "  2. 重启 Miloco 面板          打开 Miloco 面板"
  Write-Host "  1. 重启 OpenClaw 面板        打开 OpenClaw 面板"
  Write-Host ""
  Write-Host ("Miloco 面板地址：   http://127.0.0.1:{0}/" -f $script:MilocoPort)
  Write-Host ("OpenClaw 面板地址： http://127.0.0.1:{0}/" -f $OpenClawPort)
  Write-Host ("本次诊断报告：      {0}" -f $reportPath)
  Write-Host ""
  Write-Host "接下来还有几项内容不能由脚本代替你完成：" -ForegroundColor Yellow
  Write-Host "1. 小米账号授权：需要你在浏览器里登录小米账号并复制授权内容。"
  Write-Host "2. MiMo API Key：需要你自己准备并粘贴。"
  Write-Host "3. 米家摄像头：需要摄像头已绑定米家 App，且在米家 App 里能正常打开画面。"
  Write-Host ""
  Write-Info "正在尝试生成小米账号绑定链接。"
  & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $Workflow -Action BindUrl -Distro $resolvedDistro -MilocoPort $script:MilocoPort -OpenClawPort $OpenClawPort
  $bindCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  if ($bindCode -ne 0) {
    Write-Warn "绑定链接暂时没有生成成功。你可以稍后重新运行：.\install.ps1 -Action BindUrl"
  }

  Write-Host ""
  Write-Host "下一步：" -ForegroundColor Cyan
  Write-Host "1. 在浏览器完成小米账号授权。"
  Write-Host "2. 复制授权页面返回的内容。"
  Write-Host "3. 准备 MiMo API Key。"
  Write-Host "4. 在当前文件夹运行："
  Write-Host "   .\install.ps1 -Action Finish -AuthPayload '<小米授权内容>' -MimoApiKey '<MiMo API Key>'" -ForegroundColor White
  Write-Host ""
  Write-Host "[OK] 自动安装阶段完成。" -ForegroundColor Green
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
  Write-Ok "桌面入口：已删除 Miloco 相关文件。"

  Write-Step "卸载 WSL 内 Miloco 组件"
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Warn "没有检测到 WSL 命令，跳过 WSL 内卸载。"
  } else {
    $list = (& wsl.exe -l -v 2>&1 | Out-String) -replace "`0", ""
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
      & wsl.exe --terminate $script:ResolvedDistro *> $null
      Write-Ok ("WSL 内 Miloco：已从 {0} 卸载并关闭该 WSL 会话。" -f $script:ResolvedDistro)
    }
  }

  Write-Step "卸载完成"
  Write-Ok "Miloco/OpenClaw 插件、Miloco 数据目录、后台任务和桌面入口已完成清理。"
  Exit-Installer 0
}

switch ($Action) {
  "Prepare" { Invoke-Prepare }
  "Report" { Invoke-Workflow "Report" }
  "BindUrl" { Invoke-Workflow "BindUrl" }
  "Finish" { Invoke-Workflow "Finish" }
  "Validate" { Invoke-Workflow "Validate" }
  "Uninstall" { Invoke-Uninstall }
}
