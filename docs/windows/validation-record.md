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

### 2026-06-26 远程 release 第八轮复测补充

第八轮继续使用 GitHub Release 当前 `v0.2` 资产，远程机器为 home02。测试前提：home02 与米家 `andy的家` 设备不在同一局域网，因此局域网设备发现、摄像头本地直连、设备本地可达性失败不能直接判为部署 bug；账号授权、API 配置、Miloco/OpenClaw 本机服务可达性仍必须通过。

本轮通过项：

- `install.bat` 可从解压目录直接双击运行，并完成已有安装检测、Agent 恢复包导出、旧版卸载、新版安装。
- `[8/12]` Miloco 后端启动并通过健康检查，报告中可见 `running: true` 和 `server.url=http://127.0.0.1:18860`。
- `[9/12]` OpenClaw CLI、Gateway status、`miloco-openclaw-plugin` 检查通过，报告中可见 Gateway runtime running、Connectivity probe ok、插件 loaded。
- 安装器完成到结束提示，没有因 home02 与设备不在同一局域网而中断。

本轮问题：

- 报告出现唯一硬失败：`[FAIL] openclaw.gateway_http`。结合同一报告里的 `Connectivity probe: ok`、`Listening: 127.0.0.1:18789` 和插件 loaded，该失败更像验收脚本用 `curl -fsS http://127.0.0.1:18789/` 把 OpenClaw token/auth 所需的 401/403 响应误判为网关不可达，而不是 home02 与米家设备不在同一局域网导致。
- 安装器授权输入为空时会直接返回，不再继续 API 配置。这会把小米账号授权和大模型 API 配置绑死；在远程键盘链路不稳定、用户已有账号只想配置 API、或暂时跳过授权但仍想配置 OpenClaw 主聊天模型时，体验不合理。

本轮迭代：

- OpenClaw HTTP 验收改为判断本机端口是否有 HTTP 响应；`2xx/3xx/4xx` 都证明 Gateway 可达，只有连接失败、超时或 `5xx` 才作为失败。
- 授权和 API 配置交互解耦：授权码为空时继续进入 API 配置；后端收尾脚本也支持未绑定账号时先写入 Miloco 视觉模型、Miloco OpenClaw 插件和 OpenClaw 主聊天模型。

### 2026-06-26 远程 release 第九轮复测补充

第九轮继续使用 GitHub Release 当前 `v0.2` 资产，远程机器仍为 home02。测试前提同第八轮：home02 与米家 `andy的家` 设备不在同一局域网，因此局域网设备发现、摄像头本地直连、设备本地可达性失败应先判为环境合理现象；账号授权、API 配置、Miloco/OpenClaw 本机服务可达性仍必须通过。

本轮通过项：

- 通过远程 Edge 下载 release zip，浏览器下载拦截选择保留后可继续。
- Windows 安全提示中取消“打开此文件前总是询问”并点击运行后，`install.bat` 可自动提权并启动安装。
- 安装器完成已有安装检测、Agent 恢复包导出、旧版卸载和新版安装。
- `[8/12]` Miloco 后端在端口 `18860` 启动并通过健康检查。
- `[9/12]` OpenClaw CLI、Gateway 命令、`miloco-openclaw-plugin` 检查通过。
- `[10/12]` 桌面入口创建成功。
- `[11/12]` 安装诊断报告生成完成；控制台未再显示第八轮的 `openclaw.gateway_http` 硬失败。

本轮测试环境问题：

- Windows 资源管理器的“全部解压”向导在 UU 远程中多次无法稳定响应最终提取按钮。改用打开 zip、全选复制内容、进入新建文件夹后粘贴的方式可以继续测试。该问题属于远程 GUI 控制/Windows 壳层交互不稳定，不判为 easy-miloco bug。

本轮问题：

- 安装结尾显示“小米账号：N/A”和“MiMo API：N/A”，但浏览器地址栏已经停在 `https://127.0.0.1/?code=...&state=...` 这类 OAuth 回调 URL。说明用户完成授权后，回调 URL 没有被安装器自动消费，安装流程也没有继续引导用户把回调 URL 粘贴回脚本。
- 该问题与 home02 和 `andy的家` 设备不在同一局域网无关；它发生在账号授权和本机安装交互层，应判为部署流程问题。
- API 配置也没有在结尾完成，导致本轮仍未满足“账号授权和 API 配置完整进行”的验收目标。

本轮迭代：

- `windows/package/install.ps1` 的小米账号授权输入改为显式等待：直接回车不再跳过账号授权，而是提示继续等待浏览器跳到 `127.0.0.1` 后复制地址栏。
- 如需跳过账号授权，必须输入 `skip`、`s` 或 `跳过`，然后继续 API 配置。
- 输入校验同时支持完整 `code=`/`state=` 回调地址和已经转换好的 base64 授权 payload，避免破坏高级兜底路径。

### 2026-06-26 远程 release 第十轮复测补充

第十轮继续使用 GitHub Release 当前 `v0.2` 资产。测试准备阶段确认：Edge 下载拦截需要先选择保留；Windows 资源管理器手工复制 zip 内容在 UU 远程下容易焦点错位，改用系统“全部解压缩”向导后可成功解压。

本轮通过项：

- 解压后的普通文件夹可直接双击 `install.bat` 运行，安全提示按既定流程取消“打开此文件前总是询问”后可继续。
- 安装器完成旧版检测、Agent 恢复包导出、旧版卸载、新版解压、Miloco 启动、OpenClaw 插件检查和桌面入口创建。
- Miloco WSL 内健康检查通过，OpenClaw Gateway status 显示 running/listening/connectivity ok，`miloco-openclaw-plugin` loaded。

本轮问题：

- 安装器在 `[11/12]` 诊断报告后仍暂停，没有进入账号授权/API 配置。
- 报告中 OpenClaw Gateway status 已证明 `127.0.0.1:18789` running/listening/connectivity ok，但 `openclaw.gateway_http` 仍可因根路径 HTTP 探测连接失败被判为 hard fail。
- Windows 侧 `miloco_http` / 端口转发类检查偶发失败时，不应阻断 post-auth，因为账号授权和 API 写入走 WSL 内 Miloco/OpenClaw，本轮 WSL 内 Miloco health 已经通过。
- 这些问题与 home02 和 `andy的家` 不在同一局域网无关；它们都发生在本机报告判定和 post-auth 入口条件。

本轮迭代：

- `windows/package/install.ps1` 的 post-auth 阻断条件收窄为只看 WSL 内 `[FAIL] miloco.health`；Windows 侧端口转发检查失败继续作为报告诊断项，不再阻断账号/API 配置。
- `docs/scripts/wsl-miloco-validate.sh` 在 `openclaw gateway status` 已通过时，把根路径 HTTP 探测失败降级为 WARN，不再作为 hard fail。

### 2026-06-26 远程 release 第十一轮复测补充

第十一轮继续使用 GitHub Release 当前 `v0.2` 资产。为避开 Edge 临时缓存路径的解压异常，测试准备改为先把下载面板里的 zip 复制到桌面，再从桌面执行“全部解压缩”。

本轮通过项：

- 最新 release 可重新下载、保留、复制到桌面并解压。
- 解压目录 `easy-miloco-v0.2-windows (12)` 可运行 `install.bat`。
- 安装器完成旧版检测、恢复包导出、旧版卸载、新版解压、Miloco health、OpenClaw gateway/plugin、桌面入口创建和诊断报告生成。
- 第十轮的报告阻断问题已缓解：console transcript 出现“接下来可以继续完成账号授权和大模型 API 配置”，说明 post-auth 入口已被调用。

本轮问题：

- 生成小米账号授权链接时，`BindUrl` 返回上游错误：`invalid JSON response 502`。
- 该错误被 PowerShell 当前的 Stop 策略提升为终止错误，导致 post-auth 流程直接结束，没有继续进入 API 配置。
- 这不是 home02 与 `andy的家` 不在同一局域网导致；它发生在调用小米账号授权链接接口阶段，属于上游不稳定加脚本容错不足。

本轮迭代：

- `windows/package/install.ps1` 的 `BindUrl` 调用改为走 `Invoke-WorkflowCapture`，捕获错误输出和退出码，不让 PowerShell 直接终止。
- 授权链接生成失败时自动重试一次；仍失败则明确提示本次跳过小米账号授权，但继续进入 API 配置。

### 2026-06-26 远程 release 第十二轮复测补充

第十二轮使用已发布的 `v0.2` release 资产，通过 UU 远程文件传输把 zip 覆盖到 home02 桌面后，从真实 Windows 资源管理器运行解压目录 `easy-miloco-v0.2-windows (12)` 内的 `install.bat`。home02 与米家 `andy的家` 设备不在同一局域网，因此本轮继续把局域网设备发现、摄像头本地直连和设备 LAN 可达性失败判为环境合理现象，不作为安装器 bug。

本轮通过项：

- UU 文件传输可把本机 `dist/windows/easy-miloco-v0.2-windows.zip` 发送到远端桌面；同名文件存在时选择“替换”后可继续。
- 安装器完成旧版检测、Agent 恢复包导出、旧版卸载、新版安装、Miloco 启动、OpenClaw gateway/plugin 检查、桌面入口创建和诊断报告生成。
- Miloco 启动期曾出现一次 HTTP 502，但脚本继续轮询后拿到 `Miloco health ok`；这属于启动期暂态现象，不阻断安装。
- post-auth 入口确实被调用，console log 出现“接下来可以继续完成账号授权和大模型 API 配置”。

本轮问题：

- `BindUrl` 上游仍返回 `invalid JSON response: 502`。
- 虽然第十一轮已经把外层改为 `Invoke-WorkflowCapture`，但该函数内部仍使用 `& powershell.exe ... 2>&1 | ForEach-Object`。在 Windows PowerShell 5.1 下，子进程 stderr 可被包装成 terminating error，导致外层循环来不及把它转换成 `Code=1`，安装器仍然直接结束，没有进入 API 配置。
- 这不是 home02 与 `andy的家` 不在同一局域网造成；它发生在小米授权链接生成接口和 Windows PowerShell 错误捕获层，属于脚本容错 bug。

本轮迭代：

- `windows/package/install.ps1` 的 `Invoke-WorkflowCapture` 增加 `try/catch`，把子进程 stderr 触发的 terminating error 写入输出行并返回非零退出码。
- 这样 `BindUrl` 502 会走外层重试；两次失败后应提示跳过小米账号授权，并继续进入 API Key / Base URL / 模型选择配置。

### 2026-06-26 远程 release 第十三轮复测补充

第十三轮继续在 home02 远程 Windows 上运行已替换的 release 脚本。home02 与米家 `andy的家` 设备不在同一局域网，因此本轮仍把局域网设备发现、摄像头本地直连和设备 LAN 可达性失败判为环境合理现象，不作为安装器 bug。

本轮通过项：

- 第十二轮的 `Invoke-WorkflowCapture` 容错修复有效：`BindUrl` 两次返回 `invalid JSON response: 502` 后，安装器没有直接退出，而是明确提示本次跳过小米账号授权并继续进入 API 配置。
- 使用剪贴板粘贴 API Key 和 Base URL 的方式在 UU 远程中有效；模型列表可以拉取成功，并可直接回车选择推荐模型 `mimo-v2.5`。

本轮问题：

- API 写入阶段报错：`Missing an argument for parameter 'MimoApiKey'`，随后显示账号/API 收尾没有完全成功。
- 该问题与 home02 和 `andy的家` 不在同一局域网无关；它发生在 Windows 安装器调用 `win-miloco-workflow.ps1 -Action Finish` 的参数传递层。
- 初步判断为 `Invoke-FinishWorkflowOnce` 无条件传递空的 `-AuthPayload ""`，在 Windows PowerShell 5.1 调用子进程时空字符串参数可能被丢弃并导致后续具名参数错位；同时该函数尚未像 `Invoke-WorkflowCapture` 一样捕获子进程 stderr 触发的 terminating error。

本轮迭代：

- `Invoke-FinishWorkflowOnce` 改为只在授权 payload 非空时传递 `-AuthPayload`，并在调用前校验 API Key、模型名和 Base URL 不能为空。
- `Invoke-FinishWorkflowOnce` 增加与 `Invoke-WorkflowCapture` 一致的 `try/catch`，确保子进程错误会被记录并转换为非零退出码，而不是直接打断安装器。

### 2026-06-26 远程 release 第十四轮复测补充

第十四轮在 home02 远程 Windows 上把最新 `install.ps1` 覆盖进 release 解压目录后继续跑完整安装。home02 与米家 `andy的家` 设备不在同一局域网，因此本轮继续把局域网设备发现、摄像头本地直连、Host LAN 显示 N/A 判为环境合理现象，不作为安装器 bug。

本轮通过项：

- 旧版检测、Agent 恢复包导出、旧版卸载、新版安装、Miloco health、OpenClaw 依赖检查、桌面入口创建和诊断报告生成均完成。
- `BindUrl` 两次返回 502 后安装器继续进入 API 配置，未再被小米授权链接接口阻断。
- API Key、Base URL 和模型选择完成，`Post-auth finish` 进入 Miloco 服务检查；本轮没有再出现 `Missing an argument for parameter 'MimoApiKey'`，说明第十三轮参数传递修复有效。
- UU 远程下普通回车仍可能不响应；把剪贴板内容设置为换行再粘贴，可以稳定提交 Base URL 和模型默认选项。该问题属于远程交互方法问题，不判为 easy-miloco bug。

本轮问题：

- `Post-auth finish` 写入配置阶段出现 `curl: (22) The requested URL returned error: 502`，随后安装器提示账号/API 设置没有完全成功，退出码为 2。
- 该问题与 home02 和 `andy的家` 不在同一局域网无关；它发生在本机 WSL 内 `miloco-cli config set` 调用 Miloco 配置接口阶段，应按部署脚本容错问题处理。
- `wsl-post-auth-finish.sh` 当前对 `miloco-cli config set` 没有重试，而且脚本不是 `set -e`，关键配置写入失败后仍可能继续执行后续 OpenClaw 配置和验证，导致用户只看到笼统的收尾失败。

本轮迭代：

- 为 `wsl-post-auth-finish.sh` 增加关键 JSON 命令重试包装。
- `miloco-cli config set` 写入模型/API 配置改为重试 3 次，失败间隔重新检查 Miloco health；重试耗尽后立即退出并给出明确错误，避免继续执行造成误导。

### 2026-06-26 远程 release 第十五轮复测补充

第十五轮改用最短 Finish 复测路径：在 home02 release 解压目录中临时覆盖 `wsl-post-auth-finish.sh` 和一个只调用 `install.ps1 -Action Finish` 的 `install.bat` wrapper，再用鼠标双击 wrapper 触发真实安装器交互。期间发现 UU 传 `.bat` 会先落成 `.downloading`，需要等待或避免依赖该中间状态；临时 `install.ps1` 若没有 UTF-8 BOM，会被 Windows PowerShell 5.1 按错误编码解析并出现中文乱码 ParserError。该编码错误来自临时测试文件生成方式，release zip 内 `install.ps1` 已反查为 UTF-8 BOM，不判为 release 包 bug。

本轮通过项：

- BOM 版临时 `install.ps1` 可以通过 wrapper 正常进入 `install.ps1 -Action Finish`。
- API Key、Base URL 和模型选择仍可完成；模型列表可从 `https://token-plan-sgp.xiaomimimo.com/v1/models` 拉取，默认 `mimo-v2.5` 可选择。

本轮问题：

- `Post-auth finish` 开始时 `miloco-cli service status` 显示 running，但随后 `/health` 连续返回 `curl: (22) The requested URL returned error: 502`，脚本直接退出，账号/API 收尾仍未完成。
- 该问题与 home02 和米家 `andy的家` 不在同一局域网无关；它发生在 WSL 内本机 Miloco backend 健康恢复阶段。
- Finish 流程当前只在 service status 非 running 时尝试 restart/start；如果 status running 但 health 502，则没有主动重启恢复。

本轮迭代：

- `wsl-post-auth-finish.sh` 的初始 health 检查改为：第一次 health 失败时先重启 Miloco backend，再等待 health 恢复；仍失败才退出。
- 这样可以覆盖 running 但 backend HTTP 层暂时 502 的状态，避免用户必须手动重启后再跑 Finish。

### 2026-06-26 远程 release 第十六轮复测补充

第十六轮继续在 home02 的同一 release 解压目录中复测 Finish 收尾。先修正第十五轮临时脚本覆盖路径错误：真实执行路径是 release 根目录下的 `scripts/windows/wsl-post-auth-finish.sh`，不是 `docs/scripts/wsl-post-auth-finish.sh`。home02 与米家 `andy的家` 设备不在同一局域网，因此设备 LAN 发现、摄像头直连和本地设备可达性失败仍判为环境合理现象；本轮失败发生在 WSL 内 Miloco backend 健康恢复阶段，不归因于局域网隔离。

本轮通过项：

- 覆盖到正确路径后，`Post-auth finish` 已运行新版脚本。
- API Key、指定 Base URL `https://token-plan-sgp.xiaomimimo.com/v1` 和默认模型 `mimo-v2.5` 均正确进入流程。
- 模型列表可从指定 Base URL 拉取成功。
- 第十五轮新增的 health 恢复逻辑被触发：`/health` 502 后脚本输出“service is running but health is not ok; restarting backend and retrying health check”。

本轮问题：

- `miloco-cli service restart` 返回 `service did not become ready within 30s`，随后 fallback 的 `miloco-cli service start` 返回 `already running`。
- 二次 `/health` 仍返回 `curl: (22) The requested URL returned error: 502`，Finish 退出码为 2，账号/API 收尾未完成。
- 这说明第十五轮补丁方向正确，但恢复动作不够强：`restart` 失败后只 `start`，没有先 `stop` 清理卡住的旧进程，遇到 `already running` 竞态时无法真正恢复 backend。
- UU/Computer Use 文本输入会复用剪贴板内容；本轮曾把 Base URL 误粘到 API Key 输入位。该问题属于远程交互方法问题，不判为 easy-miloco bug。后续远程输入 API/URL 前必须显式设置剪贴板，再用 Ctrl+V。

本轮迭代：

- 抽出 `recover_miloco_service`，统一处理 pre-check、初始 health 恢复和配置写入后的 Miloco 重启。
- 恢复策略改为：先 `miloco-cli service restart` 并等待 health；如果 restart 报错或 health 仍不 OK，则执行 `service stop`、短等、`service start`，最后用 `/health` 作为唯一通过标准。
- 三处原先重复的 `restart` 失败后直接 `start` 逻辑全部改为调用该恢复函数，避免以后只修一处造成行为不一致。
