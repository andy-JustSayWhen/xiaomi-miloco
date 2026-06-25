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

### 2026-06-25 23:55 复测补充

第二轮 release 包重新下载为 `easy-miloco-v0.2-windows (8).zip`，解压后运行 `install.bat`。

本轮通过项：

- 安装器完成旧版检测、恢复包导出、旧版卸载、新版安装。
- `[9/12]` OpenClaw CLI / Gateway / `miloco-openclaw-plugin` 自检通过。
- `[10/12]` 桌面 `Miloco 控制台.bat`、`miloco-console.ps1`、`OpenClaw 对话入口.lnk` 创建成功。
- Miloco WebUI 可打开，模型 API 连通性测试成功，约 `6.4s` 返回。
- 模型 `mimo-v2.5` 已保存并启用。
- 小米账号 OAuth 回调 URL 可被 WebUI 接收，家庭选择可完成。
- 概览顶部最终显示 `andy的家`、`mtdjb`、`127`，说明账号、家庭和设备总量已落盘。

本轮问题：

- 家庭选择后概览/设备页长时间停在“正在读取”，约 1 分钟后才恢复到绑定状态；记录为体验问题，暂未判定为安装阻断。
- `OpenClaw 对话入口` 仍打开到 Gateway 登录页，token 字段为空。说明仅从 `~/.openclaw/miloco/config.json::agent.auth_bearer` 和 `~/.openclaw/openclaw.json::gateway.auth` 读 token 仍不可靠。

本轮迭代：

- `windows/package/install.ps1` 的桌面入口改为优先调用 `openclaw dashboard --no-open`，使用 OpenClaw 官方 CLI 生成当前 dashboard URL；只有 CLI 未返回 token URL 时，才回退到本地配置读取。

### 2026-06-25 远程 release 第三轮复测补充

第三轮 release 包重新下载为 `easy-miloco-v0.2-windows (9).zip`，解压后运行 `install.bat`。

本轮通过项：

- 安装器再次完成已有安装检测、恢复包导出、旧版卸载、新版安装。
- `[9/12]` OpenClaw CLI / Gateway / `miloco-openclaw-plugin` 自检通过。
- `[10/12]` 桌面 `Miloco 控制台.bat`、`miloco-console.ps1`、`OpenClaw 对话入口.lnk` 创建成功。
- 安装流程可到达完成页，说明 release 包主体安装路径仍可走通。

本轮问题：

- `OpenClaw 对话入口` 仍打开到 Gateway 登录页，token 字段为空，页面提示需要认证。说明仅调用 `openclaw dashboard --no-open` 仍不足以保证桌面入口拿到可用 token。
- 本轮未重新配置小米账号和大模型 API；原因是当前阻塞集中在 OpenClaw 桌面入口认证，安装器完整重装后进入未配置状态属于预期。

本轮迭代：

- `windows/package/install.ps1` 的桌面入口在 `dashboard --no-open` 和本地配置读取都拿不到 token 时，增加 `openclaw doctor generate-token` 兜底。
- 新逻辑会同时解析 `doctor generate-token` 的 stdout、带 token 的 dashboard URL，以及生成后写入的 OpenClaw/Miloco 配置，再拼接 `#token=` 打开 OpenClaw。
- 修复后自动重打 release 并替换 GitHub Release 资产，远程 Windows 直接下载最新包继续测试。

### 2026-06-26 远程 release 第四轮复测补充

第四轮 release 包重新下载为 `easy-miloco-v0.2-windows (10).zip`，解压后运行 `install.bat`。

本轮通过项：

- 安装器完成已有安装检测、Agent 恢复包导出、旧版卸载、新版安装。
- `[9/12]` OpenClaw CLI / Gateway / `miloco-openclaw-plugin` 自检通过。
- `[10/12]` 桌面 `Miloco 控制台.bat`、`miloco-console.ps1`、`OpenClaw 对话入口.lnk` 创建成功。
- `[11/12]` 部署报告生成完成。
- 通过桌面 `OpenClaw 对话入口` 打开 Gateway 页面时，网关令牌输入框已自动填入，说明 token 自动生成和传递不再是空值。

本轮问题：

- 点击 Gateway 页面“连接”后仍提示无法连接 Gateway。现象从“token 为空/需要认证”推进为“token 已填但 WebSocket/Gateway 连接不可用”。
- 说明桌面入口只等待 Windows 端口可达还不够；需要等待 `openclaw gateway status` 的 connectivity probe 通过，并且拼接 token 时不能丢弃 `openclaw dashboard --no-open` 返回的完整 dashboard URL。

本轮迭代：

- `windows/package/install.ps1` 拼 token 时改用 `dashboard --no-open` 返回的完整 URL 作为基准，只有没有 dashboard URL 时才回退裸 `http://127.0.0.1:<port>/`。
- 独立 `OpenClaw 对话入口` 不再只判断端口打开；重启/启动 Gateway 后等待 `openclaw gateway status` connectivity 通过，再打开浏览器。
- 控制台入口的 OpenClaw 打开路径同步增加 Gateway connectivity 检查，避免端口开但 WebSocket 不可用时误导用户。

### 2026-06-26 远程 release 第五轮复测补充

第五轮使用 GitHub Release 当前 `v0.2` 资产重新下载，release zip SHA256 为 `3fed5147322657206ee4ce1c8926b75b5fc4dc9cb12b90df5b3b4c09d314b0c6`。远程 Windows 通过 UU 远程控制模拟用户下载、解压、运行 `install.bat`，并在安全提示中取消每次询问后继续运行。

本轮通过项：

- 安装器完成已有安装检测、Agent 恢复包导出、旧版卸载、新版安装。
- `[8/12]` 依赖检查和 `[9/12]` OpenClaw CLI / Gateway / `miloco-openclaw-plugin` 自检通过。
- `[10/12]` 桌面入口创建成功，`[11/12]` 部署报告生成完成。
- 桌面 `OpenClaw 对话入口` 约 2 分钟后直接进入 `http://127.0.0.1:18789/chat?session=main`，未再停在 Gateway token 或连接错误页。
- Miloco WebUI 模型页用 `https://token-plan-sgp.xiaomimimo.com/v1` 和 `mimo-v2.5` 测试连接成功，返回约 `5981ms`，模型保存并启用。
- 小米 OAuth 页授权后跳到 `https://127.0.0.1/?code=...&state=...`，复制完整回调 URL 粘贴回 Miloco WebUI 可完成绑定。
- 家庭选择弹窗可确认 `andy的家`；随后概览显示 `andy的家`、账号 `mdidb`、`127 件设备`。
- 设备页可展开，显示 `127 devices` / `13 rooms`，可见设备列表和在线/离线状态。

本轮问题：

- OpenClaw 聊天页虽然能进入，但底部模型仍显示 `gpt-5.1 - openai - Medium`，说明安装器当前写入的是 Miloco 视觉模型和 Miloco OpenClaw 插件模型配置，没有同步写入 OpenClaw 主聊天 LLM。
- 这会导致普通用户以为 API 已完整配置，但 OpenClaw 主聊天仍可能因为默认 OpenAI provider 没有 API Key 而失败。旧验收报告也记录过同类错误：`Agent failed before reply: No API key found for provider "openai"`。

本轮迭代：

- `docs/scripts/wsl-post-auth-finish.sh` 在写入 `model.omni.*` 和 `miloco-openclaw-plugin.config.omni_*` 后，同步写入 `~/.openclaw/openclaw.json`：
  - `agents.defaults.model.primary`
  - `agents.defaults.models.<provider/model>`
  - `models.providers.<provider>.baseUrl/apiKey/api/models[]`
- 对 Xiaomi MIMO / token-plan endpoint，provider 默认写为 `mimo`；其它 OpenAI-compatible endpoint 默认写为 `miloco-llm`。
- 写入后运行 `openclaw config validate`；若验证失败，自动恢复旧 `openclaw.json`，避免 Gateway 因错误配置无法启动。
- `docs/scripts/wsl-miloco-validate.sh` 新增 `openclaw.main_chat_model` 检查，确认 primary、provider baseUrl、apiKey 和 model row 均已配置。
- `windows/package/install.ps1` 的完成提示改为说明 API 会同步写入 Miloco 视觉模型、Miloco OpenClaw 插件和 OpenClaw 主聊天模型，不再提示用户自行另配主聊天 LLM。
- 新增 `.gitattributes` 固定 `*.sh text eol=lf`，避免 Windows 工作区把 WSL shell 脚本转成 CRLF。

### 2026-06-26 远程 release 第六轮复测补充

第六轮使用 GitHub Release 当前 `v0.2` 资产重新下载为 `easy-miloco-v0.2-windows (11).zip`，解压到 `Documents\easy-miloco-v0.2-windows (11)` 后运行 `install.bat`。

本轮通过项：

- 安装器完成已有安装检测、Agent 恢复包导出到桌面、旧版完整卸载和新版安装。
- `[8/12]` Miloco 后端在端口 `18860` 启动成功。
- `[9/12]` OpenClaw CLI / Gateway / `miloco-openclaw-plugin` 自检通过。
- `[10/12]` 桌面入口创建成功。
- `[11/12]` 部署报告生成到 `Documents\easy-miloco-v0.2-windows (11)\miloco-deploy-report-20260626-005838.txt`。

本轮问题：

- 安装器在部署报告后提示“安装命令已经执行完成，但 Miloco/OpenClaw 面板还没有通过自动检查”，随后要求按回车关闭。
- 这会阻断后续小米账号授权和大模型 API 配置，即使 Miloco 后端已经可用。该阻断条件过严：OpenClaw Gateway 或 Windows 侧面板检查暂时不绿时，不应阻止用户完成 Miloco 账号/API 配置。

本轮迭代：

- `windows/package/install.ps1` 的 `Test-ReportAllowsPostAuthSetup` 改为只把 Miloco 后端不可用视为账号/API 配置前的硬阻断。
- 只要 `miloco.health`、`windows.miloco_http` 或 `MILOCO_HEALTH=yes` 表明 Miloco 可用，即允许继续进入小米账号授权和 API 配置。
- OpenClaw Gateway、OpenClaw 插件和 Windows OpenClaw 面板检查仍留在部署报告中作为诊断项，但不再阻断 post-auth 配置流程。

### 2026-06-26 远程 release 第七轮复测补充

第七轮使用 GitHub Release 当前 `v0.2` 资产重新下载，鼠标主导通过 UU 远程完成下载、保留、解压和运行 `install.bat`。

本轮通过项：

- 验证了远端 Windows 屏幕键盘可作为键盘链路兜底：屏幕键盘可以输入普通字母，且 `Ctrl` + `L` 可选中远端 Edge 地址栏。
- 验证了主控端剪贴板同步和远端右键粘贴可用：Edge 地址栏右键菜单出现“粘贴并转到 GitHub release zip”。
- 安装器完成已有安装检测、Agent 恢复包导出、旧版卸载和新版安装。
- `[8/12]` Miloco 后端在端口 `18860` 启动成功。
- `[9/12]` OpenClaw CLI / Gateway / `miloco-openclaw-plugin` 自检通过。
- `[10/12]` 桌面入口创建成功。
- `[11/12]` 部署报告生成完成。

本轮问题：

- 安装器仍在部署报告后提示“安装指令已经执行完成，但 Miloco/OpenClaw 面板还没有通过自动检查”，没有进入小米账号授权和 API 配置。
- 说明第六轮修复仍不够：`Test-ReportAllowsPostAuthSetup` 虽然不再把 OpenClaw 检查失败当硬阻断，但仍要求报告里出现可匹配的 post-auth 缺口关键词。远端报告中可见小米账号和 API 仍未配置，但关键词没有被函数识别，导致返回 false。

本轮迭代：

- `windows/package/install.ps1` 的 `Test-ReportAllowsPostAuthSetup` 改为：只要 Miloco 后端可用，且没有 `miloco.health` / `windows.miloco_http` 硬失败，就允许进入 post-auth 配置流程。
- 即使账号/API 已配置，交互流程也允许用户直接回车跳过；这比误阻断小米账号授权和 API 配置更安全。
