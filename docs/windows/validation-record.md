# Windows 部署资料包验收记录

## 2026-06-25 远程 Windows 视觉回归记录

> 验收对象：GitHub Release `v0.2` / `easy-miloco-v0.2-windows.zip`
> 测试方式：UU 远程模拟普通 Windows 用户下载、解压、双击 `install.bat`。

### 本轮规则调整

部署测试发现问题时，先记录证据并继续跑完原计划步骤；只有硬阻断才暂停。完整一轮结束后再汇总、迭代、重打包、重测。

### 已跑步骤

- 从 GitHub Release 下载 Windows zip，解压后运行 `install.bat`。
- 安装器检测到旧安装后导出 agent 恢复包、完整卸载旧版，再安装新版。
- Miloco WebUI 可打开，模型 API 配置完成，测试连接成功。
- 小米账号授权可复制完整 `https://127.0.0.1/?code=...&state=...` 回调 URL 到 WebUI；WebUI 不再报 base64 格式错误。
- 家庭选择完成后，设备页能加载家庭设备列表。

### 本轮发现

| 步骤 | 现象 | 是否阻断 | 证据/结论 |
| --- | --- | --- | --- |
| OpenClaw 入口 | 用户直接打开 `http://127.0.0.1:18789/` 会停在 OpenClaw Gateway token 登录页 | 阻断 OpenClaw 用户入口验证 | 裸端口需要 Gateway token；安装完成提示给裸地址会误导普通用户 |

### 本轮迭代

- `windows/package/install.ps1` 新增桌面 `OpenClaw 对话入口.lnk`，由隐藏 PowerShell 脚本优先读取 WSL 内 `agent.auth_bearer`，再兜底读取 OpenClaw `gateway.auth` token，以 `http://127.0.0.1:<port>/#token=<token>` 打开 OpenClaw。
- 安装完成提示改为引导用户使用桌面 OpenClaw 对话入口，不再展示裸 OpenClaw 端口地址。
- 卸载流程同步删除 `OpenClaw 对话入口.lnk` 和 `miloco-openclaw.ps1`。

### 当前 release 状态

```text
asset: easy-miloco-v0.2-windows.zip
size: 68503772
sha256: b60131c6df9c1bb1e56bfe4168c1a6bed6b632ab2c6972600da55a600d489494
updated_at: 2026-06-25T14:35:47Z
```

### 待重测

- 远程 Windows 重新下载最新 release 包，完整卸载旧版后安装。
- 验证桌面 `OpenClaw 对话入口.lnk` 可直接进入 OpenClaw，而不是 Gateway token 登录页。
- 验证 Miloco 设备页、模型配置、小米账号、家庭选择仍通过。
- 测试完成后关闭或释放测试机。

## 2026-06-24 本机 release 包复测

> 验收对象：`dist/windows/easy-miloco-v0.2-windows.zip`
> 测试机：本机 Windows 11，WSL 注册名 `Ubuntu-24.04`

### 本轮发现并修复

- Windows 默认“全部解压缩”会把原先的 zip 解成 `easy-miloco-v0.2-windows\easy-miloco-v0.2-windows\install.bat` 双层目录，普通用户打开第一层看不到 `install.bat`。已改为压缩包根目录直接放安装包内容，解压后第一层即有 `install.bat`。
- 测试前需要可重复完整卸载。已新增 `install.ps1 -Action Uninstall`，清理 Windows 计划任务、桌面入口、WSL 内 Miloco 工具、Miloco home、OpenClaw Miloco 插件，并关闭该 WSL 会话。
- 仅存在 OpenClaw CLI 时不再触发“已有 Miloco 安装痕迹”确认，避免干净 Miloco 环境被误判后卡在 C/Q 输入。
- WSL 验证脚本的 `miloco.health` 增加最多 20 秒短重试，避免服务刚报告 running 但应用尚未 ready 时误报失败。
- Release 包不再生成或发布 `.zip.sha256` / `SHA256SUMS.txt`，用户下载口径只保留 GitHub Release 为版本基准。

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

### Release 资产瘦身复核

用户下载路径不再发布或生成 checksum 附件。`windows/build-release.ps1 -Version v0.2 -Channel stable -SkipBuild` 已通过打包自测；新 zip 根目录和 `dist/windows/` 均不包含 `.zip.sha256` 或 `SHA256SUMS.txt`。GitHub Release `v0.2` 当前仅保留 `easy-miloco-v0.2-windows.zip` 一个资产。

> 验收日期：2026-06-22 10:22
> 验收对象：`packages/easy-miloco-v0.1-windows.zip`
> 关联：[Windows部署资料包发布清单](release-package.md)、[Windows部署资料包版本说明](release-notes-template.md)、[Windows部署教程-独立分发版](standalone-package.md)

## 验收结论

分发包可解压，脚本语法烟测通过。

资料包完整性和脚本语法通过；<windows-sample-host> 实机也已经完成后授权收尾并通过满血验收。

## 解压校验

临时解压路径：

```text
C:\Users\<user>\AppData\Local\Temp\miloco-win-package-verify-<guid>\easy-miloco-v0.1-windows
```

说明：临时路径每次验收都会变化，不能作为资料包内容稳定性证据；以解压结构和脚本语法烟测为准。

结果：

```text
FILE_COUNT=23
DOC_COUNT=16
SCRIPT_COUNT=5
```

目录：

```text
docs/
scripts/
README.md
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

## 2026-06-25 远程 Windows release 部署复测记录

测试对象：GitHub Release `v0.2` 的 `easy-miloco-v0.2-windows.zip`。

当前通过项：

- Release 包下载、解压、双击 `install.bat` 和管理员提权流程可走通。
- 安装器检测到已有 Miloco 后，已导出兼容恢复包到桌面，随后卸载旧版并安装新版。
- Miloco 基础服务、OpenClaw CLI/Gateway/plugin 自检通过。
- Miloco WebUI 可打开；大模型 API 配置页可用，连通性测试成功，模型保存后生效。
- 小米账号授权回调 URL 可粘贴回 WebUI；家庭选择可完成。
- 设备页成功加载家庭设备，测试家庭显示 `127 devices` / `13 rooms`。

阻塞项：

- 桌面 `OpenClaw 对话入口` 未完成免登录进入。实际打开后停在 OpenClaw Gateway 登录/连接页，地址栏为 `http://127.0.0.1:18789/chat?session=main`，页面 token 字段为空并显示无法连接。
- 期望行为：桌面入口应自动读取当前 OpenClaw/Miloco 认证 token，打开带认证信息的 OpenClaw 对话页，用户无需手动填写 token。

处置：

- 先记录本轮证据，再迭代入口脚本的 token 读取/兜底逻辑。
- 修复后重新打包替换 GitHub Release，并直接在远程 Windows 上下载运行新 release 复测，不再额外等待“运行”确认。
