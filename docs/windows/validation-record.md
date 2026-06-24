# Windows 部署资料包验收记录

## 2026-06-24 本机 release 包复测

> 验收对象：`dist/windows/easy-miloco-v0.2-windows.zip`
> zip SHA256：`0f35b56fd478f1064b79608cbc9e19ed68c6c5b576402070a2dc762dae4e6487`
> 测试机：本机 Windows 11，WSL 注册名 `Ubuntu-24.04`

### 本轮发现并修复

- Windows 默认“全部解压缩”会把原先的 zip 解成 `easy-miloco-v0.2-windows\easy-miloco-v0.2-windows\install.bat` 双层目录，普通用户打开第一层看不到 `install.bat`。已改为压缩包根目录直接放安装包内容，解压后第一层即有 `install.bat`。
- 测试前需要可重复完整卸载。已新增 `install.ps1 -Action Uninstall`，清理 Windows 计划任务、桌面入口、WSL 内 Miloco 工具、Miloco home、OpenClaw Miloco 插件，并关闭该 WSL 会话。
- 仅存在 OpenClaw CLI 时不再触发“已有 Miloco 安装痕迹”确认，避免干净 Miloco 环境被误判后卡在 C/Q 输入。
- WSL 验证脚本的 `miloco.health` 增加最多 20 秒短重试，避免服务刚报告 running 但应用尚未 ready 时误报失败。

### 非视觉部署测试

流程：

```text
Expand-Archive dist/windows/easy-miloco-v0.2-windows.zip
install.ps1 -Action Uninstall
管理员模式运行 install.ps1
```

结果：

```text
install.bat 位于解压根目录：PASS
UninstallExit=0
ValidateExitCode=0
BASIC_READY=yes
FULL_READY=no
FAIL_COUNT=0
报告：C:\Users\17239\AppData\Local\Temp\easy-miloco-nonvisual-flat-20260624-130120\miloco-deploy-report-20260624-130311.txt
```

`FULL_READY=no` 符合本阶段边界：小米账号授权、MiMo API Key、摄像头选择仍是后续手动步骤。

### @电脑视觉部署测试

流程：

```text
桌面测试目录放入 release zip
文件资源管理器打开 zip
点击“全部解压缩”
确认解压后第一层包含 install.bat
双击 install.bat
通过 UAC 后安装自动完成基础阶段
```

结果：

```text
解压后第一层 install.bat 可见：PASS
Miloco service running=true
Miloco health={"status":"ok"}
OpenClaw Miloco plugin Status=loaded Version=2026.6.24
ValidateExitCode=0
BASIC_READY=yes
FULL_READY=no
FAIL_COUNT=0
报告：C:\Users\17239\Desktop\easy-miloco-visual-test\easy-miloco-v0.2-windows\miloco-deploy-report-20260624-130841.txt
```

### 测试后卸载确认

每次安装测试后均执行 `install.ps1 -Action Uninstall`。最终状态：

```text
UNINSTALL_EXIT=0
MILOCO_CLI=no
MILOCO_HOME=no
MILOCO_PLUGIN=no
HEALTH_18860=no
```

> 验收日期：2026-06-22 10:22
> 验收对象：`packages/easy-miloco-v0.1-windows.zip`
> 关联：[Windows部署资料包发布清单](release-package.md)、[Windows部署资料包版本说明](release-notes-template.md)、[Windows部署教程-独立分发版](standalone-package.md)

## 验收结论

分发包可解压，包内 `SHA256SUMS.txt` 全部通过，脚本语法烟测通过。

资料包完整性和脚本语法通过；<windows-sample-host> 实机也已经完成后授权收尾并通过满血验收。

zip SHA256：

```text
见包外 easy-miloco-v0.1-windows.zip.sha256
```

包外校验文件：

```text
packages/easy-miloco-v0.1-windows.zip.sha256
```

hash 自引用规则见 [Windows部署资料包版本说明](release-notes-template.md)。

## 解压校验

临时解压路径：

```text
C:\Users\<user>\AppData\Local\Temp\miloco-win-package-verify-<guid>\easy-miloco-v0.1-windows
```

说明：临时路径每次验收都会变化，不能作为资料包内容稳定性判断；以 `SHA_TOTAL`、`SHA_FAIL`、脚本语法烟测和 zip SHA256 为准。

结果：

```text
SHA_TOTAL=22
SHA_FAIL=0
FILE_COUNT=23
DOC_COUNT=16
SCRIPT_COUNT=5
```

目录：

```text
docs/
scripts/
README.md
SHA256SUMS.txt
```

## 脚本语法烟测

PowerShell 解析：

```text
PS_PARSE_PASS windows-preflight.ps1
PS_PARSE_PASS win-miloco-workflow.ps1
```

Bash 解析：

```text
BASH_PARSE_PASS wsl-miloco-validate.sh
BASH_PARSE_PASS wsl-post-auth-finish.sh
```

## 复核命令

```powershell
$zip = 'E:\BaiduSyncdisk\obsidian repo\default\App学习笔记\easy-miloco\02-deploy\packages\easy-miloco-v0.1-windows.zip'
$dest = Join-Path $env:TEMP ('miloco-win-package-verify-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dest | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $dest
```

校验 `SHA256SUMS.txt`：

```powershell
$root = Join-Path $dest 'easy-miloco-v0.1-windows'
$sumFile = Join-Path $root 'SHA256SUMS.txt'
Get-Content -Encoding UTF8 -LiteralPath $sumFile | ForEach-Object {
  $parts = $_ -split '  ', 2
  $expected = $parts[0].Trim()
  $rel = $parts[1].Trim()
  $path = Join-Path $root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
  if ($actual -ne $expected) { "HASH_FAIL $rel" }
}
```

脚本语法：

```powershell
$files = @(
  "$root\scripts\windows-preflight.ps1",
  "$root\scripts\win-miloco-workflow.ps1"
)
foreach ($f in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { $errors } else { "PASS $f" }
}
```

```powershell
wsl.exe -- bash -n /mnt/c/path/to/scripts/wsl-miloco-validate.sh
wsl.exe -- bash -n /mnt/c/path/to/scripts/wsl-post-auth-finish.sh
```

## 当前部署状态

<windows-sample-host> 最新已验证：

```text
Miloco running=true
health={"status":"ok"}
account.is_bound=true
model.omni.model=mimo-v2.5
model.omni.base_url=https://token-plan-sgp.xiaomimimo.com/v1
model.omni.api_key=configured
device_rows=127
camera.did=<camera-did-desk>
camera.in_use=true
camera.connected=true
FULL_READY=yes
```

后续维护：

- 定期运行 `win-miloco-workflow.ps1 -Action Validate`。
- 如果摄像头或账号变化，按 [Windows后授权失败排障与交付审计](post-auth-troubleshooting.md) 分层排查，不要直接重装。
