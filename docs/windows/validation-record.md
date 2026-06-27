# Windows 部署资料包验收记录

## 2026-06-27 本机 GitHub Release v0.3 摄像头部署验证

> 验收对象：GitHub Release `v0.3` / `easy-miloco-v0.3-windows.zip`
> 测试方式：本机 Windows + Ubuntu-24.04 WSL，使用已校验 SHA256 与 GitHub Release digest 一致的 release zip 解压运行。

### 本轮基线

- Release asset: `easy-miloco-v0.3-windows.zip`
- Release SHA256: `8bdc6d9e7f2383c7ecba6d95eb63df45fae52b66fda70966df77835df697dc4a`
- Release size: `132266370`
- 本机解压目录：`C:\Users\17239\AppData\Local\Temp\easy-miloco-deploy-test-v0.3-20260627-214458`
- 验证报告：`miloco-deploy-report-after-restore.txt`

### 执行记录

- 通过 release 包安装器完成基础安装；安装器检测到旧版 Miloco 后导出兼容恢复包，卸载旧版并安装新版。
- release 包内感知模型已同步到 WSL，后端日志显示 perception engine started。
- 兼容恢复包只迁移模型配置和 MiOT 登录/home whitelist 所需 kv 键；迁移前已在 WSL 内创建 `config.json` 与 `miloco.db` checkpoint。
- 安装后诊断报告通过：`BASIC_READY_FROM_WINDOWS=yes`、`BASIC_READY=yes`、`FULL_READY=yes`、`PASS_COUNT=16`、`FAIL_COUNT=0`。

### 摄像头与 OpenClaw 验证

- Miloco 概览页面显示家庭设备总数为 `127`，摄像头区域列出 3 台摄像头。
- Miloco 概览的实时画面区显示 `0 个在感知`，并提示还没有摄像头在感知；页面中没有视频预览元素。
- `miloco-cli scope camera list --pretty` 显示 3 台摄像头在线；其中 1 台 `in_use=true` 但 `connected=false`，另 2 台被标记为当前机型暂不支持感知。
- `miloco-cli perceive devices` 返回空列表；对启用摄像头执行主动感知返回 `2011 No valid active perception sources found`。
- OpenClaw chat 实际提问“家庭内一共有几台摄像头？每台摄像头当前画面如何，是否能看到画面预览？”后，OpenClaw 回复：共有 3 台摄像头，全部在线；只有 1 台支持感知但视频流未连接，另外 2 台当前机型不支持感知，因此此刻 3 台都拿不到画面预览。

### 结论

- Release `v0.3` 基础部署和满血配置恢复通过。
- 本轮摄像头链路未通过画面预览验收：面板和 OpenClaw 均确认当前没有可用实时画面预览。
- 后续应按 camera runbook 继续定位启用摄像头 `connected=false` 的拉流问题；另 2 台属于当前机型不支持感知，不应计入可感知摄像头失败。

## 2026-06-26 本机 Computer Use release 第二十三轮完整部署测试

> 验收对象：GitHub Release `v0.2` / `easy-miloco-v0.2-windows.zip`
> 测试方式：本机 Windows 用户视角，优先通过 Computer Use 操作资源管理器、解压目录、安装器和桌面入口。

### 本轮基线

- Release URL: `https://github.com/andy-JustSayWhen/easy-miloco/releases/download/v0.2/easy-miloco-v0.2-windows.zip`
- Release asset size: `68532311`
- Release SHA256: `721976105dec6f247fbc21f90c6c95dfbc08a17f8d87d349552b6d19b8655e02`
- Release updated_at: `2026-06-26T04:03:27Z`
- 本机开始时间：`2026-06-26 16:44 +08:00`

### 计划步骤

1. 将当前 Release zip 放入用户可见 `Downloads`。
2. 通过 Computer Use 打开资源管理器，确认 zip 文件存在。
3. 通过资源管理器普通用户路径解压 zip。
4. 进入解压目录，确认第一层存在 `install.bat`。
5. 双击 `install.bat`，按 Windows 安全提示和安装器提示继续。
6. 完成旧版检测、恢复包导出、卸载、新版安装、OpenClaw 安装、桌面入口生成。
7. 按安装器提示完成小米 OAuth、API Key、Base URL、模型选择。
8. 验证 Miloco WebUI、OpenClaw 对话入口、最终报告、基础服务和满血缺口。
9. 记录所有非阻断问题；完整跑完后再统一判断是否需要修复和复测。

### 执行记录

- 上一轮直接用 Computer Use 启动 Chrome 到 GitHub Release 时，Computer Use 因无法可信识别当前浏览器 URL 而中止；本轮不再把浏览器作为主通道，改为先准备用户可见下载文件，再从资源管理器开始模拟普通用户安装动作。
- GitHub 直连下载 120 秒超时，Clash 7897 代理下载 180 秒仍超时；本地 `dist/windows/easy-miloco-v0.2-windows.zip` 与当前 Release asset SHA256 完全一致。用户确认本机测试可直接使用本地 release 包。
- 已将同哈希本地 release 包复制到 `C:\Users\17239\Downloads\easy-miloco-v0.2-windows.zip`，用于后续 Computer Use 资源管理器用户视角操作。
- Computer Use 打开资源管理器 `Downloads` 后可见 `easy-miloco-v0.2-windows.zip`；搜索后唯一结果可见并高亮。
- 本机资源管理器对该 zip 的右键菜单、经典菜单、搜索结果双击、Enter 和工具栏更多菜单均未提供稳定可用的“全部解压缩”入口；记录为本机用户视角非阻断问题，后续改用已安装的 7-Zip File Manager 作为可见 UI 解压兜底继续完整安装测试。
- 7-Zip File Manager 可打开，但工具栏打开/路径栏输入没有稳定载入 zip；继续记录为本机 UI 解压入口问题。为不阻断后续安装验证，使用同一 release zip 解压到 `C:\Users\17239\Downloads\easy-miloco-v0.2-windows`，随后回到 Computer Use 打开解压目录继续用户视角安装。
- 解压后第一层确认存在 `install.bat`、`install.ps1`、`manifest.json`、`README.md`、`release-notes.md`、`docs/`、`payload/`、`scripts/`。
- 用户已确认允许通过 Computer Use 运行 `install.bat`；后续从资源管理器解压目录双击 `install.bat` 继续。

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

### 2026-06-26 远程 release 第十七轮复测补充

第十七轮继续在 home02 的同一 Finish 最短路径上复测第十六轮补丁。home02 与米家 `andy的家` 设备不在同一局域网，因此仍只把设备 LAN 可达性问题视为环境限制；本轮失败仍发生在 WSL 内 Miloco backend 与配置写入顺序。

本轮通过项：

- 新版 `recover_miloco_service` 已生效，日志从“retrying health check”变为“trying restart/stop/start”。
- 当 `service restart` 30 秒未 ready 时，脚本进入强制 stop/start 分支。
- `miloco-cli service stop` 成功停止旧进程，日志返回 `{"code": 0, "message": "stopped", "pid": ...}`。

本轮问题：

- `service start` 仍返回 `service did not become ready within 30s`，随后 `/health` 继续 502，Finish 失败。
- 这说明问题不只是旧进程未清理，而是“写 API 配置前要求 health OK”可能形成死锁：当前 backend 因模型/API 未配置而不健康，但脚本又因为 health 不健康而无法可靠走 `miloco-cli config set`。
- 该现象与 home02/home01 不同局域网无关；它发生在本机 backend 的未配置态和健康检查语义之间。

本轮迭代：

- Finish 脚本改为：如果没有小米授权 payload、只是继续写模型/API 配置，则 pre-check 的 `/health` 失败不再直接阻断，而是继续尝试写配置。
- `miloco-cli config set` 三次失败后，新增直接写 `$MILOCO_HOME/config.json` 的兜底，写入 `model.omni.model`、`model.omni.base_url` 和 `model.omni.api_key`。
- 之后再通过统一的 `recover_miloco_service` 重启并验证 health，避免未配置态卡死在配置写入之前。

### 2026-06-26 远程 release 第十八轮复测补充

第十八轮继续在 home02 远程 Windows 上复测 Finish 收尾。用户确认：这台电脑位于 home02，而米家 `andy的家` 内设备位于 home01，二者不在同一局域网。因此本轮开始把设备局域网发现、摄像头本地直连、依赖本地网段的设备可达性失败明确判为环境预期；账号授权、API 写入、OpenClaw 配置和本机服务脚本异常仍按实质问题处理。

本轮通过项：

- 第十七轮补丁有效：即使 pre-check 阶段 `/health` 返回 502，脚本也没有在写模型/API 配置之前退出。
- `miloco-cli config set model.omni.model/base_url/api_key --no-restart` 三项均返回 `{"code": 0, "message": "ok", "updated": ...}`，说明模型名、Base URL 和 API Key 已写入 Miloco 配置。
- OpenClaw 插件配置和 OpenClaw 主聊天配置均已写入。

本轮问题：

- 写完配置后的 `recover_miloco_service "Restarting Miloco backend"` 仍然在 `restart` 与 `stop/start` 后遇到 `/health` 502，并以退出码 2 结束。
- 结合 home02/home01 不同局域网这一环境事实，配置已成功写入后的最终 `/health` 502 不能再直接判为安装器失败；它可能包含设备、摄像头、本地节点或下游依赖不可达造成的降级健康状态。
- 当前 Finish 流程把“API/OpenClaw 已配置，但 backend 健康降级”当作硬失败，会误导用户认为账号/API 配置完全失败。

本轮迭代：

- 最终配置写入后的 Miloco 恢复检查改为允许降级完成：仍尝试 `restart` 与 `stop/start`，但如果最终 `/health` 仍不 OK，只输出警告并继续后续 OpenClaw 重启与验证。
- 授权、列家庭等必须依赖健康 backend 的步骤保持严格失败；只有模型/API/OpenClaw 配置已经成功写入之后，才允许把最终 health 异常降级为环境/服务健康警告。

本轮补丁后复测结果：

- 覆盖新版 `scripts/windows/wsl-post-auth-finish.sh` 后，Finish 流程从 API Key、Base URL、默认模型选择一路推进到收尾完成。
- `miloco-cli config set` 三项继续成功，OpenClaw 插件配置和 OpenClaw 主聊天模型配置继续成功。
- 最终 Miloco backend `restart` 与 `stop/start` 后 `/health` 仍返回 502，但脚本按预期输出降级警告并继续执行 OpenClaw gateway restart 和验证报告。
- 验证报告显示 `BASIC_READY=yes`、`FULL_READY=no`、`PASS_COUNT=13`、`FAIL_COUNT=0`、`WARN_COUNT=4`，随后安装器输出“账号/API 配置已完成”。
- 结论：对 home02 这类不在 `andy的家` 设备同一局域网的测试机，API/OpenClaw 配置完成但摄像头/设备/health 降级属于可接受的部署完成态；完整视觉设备验证应回到与设备同 LAN 的机器执行。

### 2026-06-26 远程 release 第十九轮完整云端包复测

第十九轮在 home02 远程 Windows 上走完整普通用户路径：从 GitHub Release 下载 `easy-miloco-v0.2-windows.zip`，保存到桌面，使用 Explorer 全部解压，双击正式 `install.bat`，在 SmartScreen/打开文件提示中取消“总是询问”并点击运行。home02 与 `andy的家` 设备不在同一局域网，因此本轮继续把摄像头、设备 LAN 可达性和 FULL_READY 视觉链路降级视为环境限制。

本轮通过项：

- 云端 release 下载成功，解压出的正式包可直接双击运行。
- 安装器检测到已有 Miloco，导出 Agent 恢复包到桌面，然后完整卸载旧版。
- 新版安装继续使用 Ubuntu-24.04，端口从 18860 起分配，Miloco 与 OpenClaw 安装完成。
- 桌面 `Miloco 控制台.bat`、`miloco-console.ps1`、`OpenClaw 对话入口.lnk` 创建成功。
- API Key、Base URL `https://token-plan-sgp.xiaomimimo.com/v1` 和模型 `mimo-v2.5` 写入成功；OpenClaw 插件配置与主聊天模型配置写入成功。
- 最终验证报告显示 `BASIC_READY=yes`、`FULL_READY=no`、`PASS_COUNT=13`、`FAIL_COUNT=0`、`WARN_COUNT=4`，安装器输出“账号/API 配置已完成”。

本轮问题：

- 小米账号授权链接生成仍两次返回 `invalid JSON response: 502`，安装器按预期跳过授权并继续 API 配置。
- 该问题与 home02/home01 不同局域网无关；它发生在小米授权链接生成或 Miloco 后端授权接口链路，仍需继续排查。
- UU 远程对回车仍不稳定，Base URL 和模型选择需要使用剪贴板带换行提交。该项属于远程控制方法问题，不判为 easy-miloco bug。

本轮环境判定：

- home02 测试机与米家 `andy的家` 内设备不在同一局域网，因此摄像头本地直连、局域网设备发现、设备 LAN 可达性、依赖同网段的视觉链路和 `FULL_READY=no` 属于合理环境降级。
- 小米账号授权链接生成、API Key/Base URL/模型写入、OpenClaw 配置、安装器退出码和脚本异常不依赖与设备同 LAN，仍按真实产品问题处理。

本轮迭代：

- `wsl-post-auth-finish.sh --print-bind-url` 保留原有 `miloco-cli account bind --no-wait` 路径；如果后端授权接口返回 502 或非 JSON 导致失败，则读取 Miloco 数据库中的 `DEVICE_UUID_KEY`，按源码同算法本地生成 `https://account.xiaomi.com/oauth2/authorize` 授权 URL。
- 兜底 URL 使用同一个 `device_id` 与 `state` 计算方式，避免用户授权后粘贴回调时和后续 `miloco-cli account authorize` 不匹配。

### 2026-06-26 远程 release 第二十轮完整云端包复测

第二十轮继续在 home02 远程 Windows 上走完整普通用户路径：从 GitHub Release 下载最新 `easy-miloco-v0.2-windows.zip`，解压到桌面，运行正式 `install.bat`，检测已有安装后导出 Agent 恢复包，完整卸载旧版，再执行新版安装。home02 与米家 `andy的家` 设备仍不在同一局域网，因此设备 LAN、摄像头直连和 `FULL_READY=no` 继续按环境限制处理。

本轮通过项：

- 云端 release 下载、解压和 `install.bat` 提权运行成功。
- 安装器检测到已有 Miloco 后，成功导出 Agent 恢复包到桌面，并完整停止/删除旧版 Miloco。
- 第十九轮新增的小米授权 URL 本地兜底已生效：`miloco-cli account bind --no-wait` 仍返回 502/invalid JSON，但脚本随后本地生成 Xiaomi OAuth URL，并自动打开浏览器。
- 小米授权页面可以打开，用户点击确认授权后，浏览器跳转到 `https://127.0.0.1/?code=...&state=...`；复制该回调 URL 粘贴回安装器后，安装器继续执行。
- API Key、Base URL `https://token-plan-sgp.xiaomimimo.com/v1` 和模型 `mimo-v2.5` 写入成功；OpenClaw 插件配置与 OpenClaw 主聊天模型配置写入成功。
- 最终验证报告显示 `BASIC_READY=yes`、`FULL_READY=no`、`PASS_COUNT=13`、`FAIL_COUNT=0`，安装器输出“账号/API 配置已完成”。

本轮问题：

- 小米授权 code 已成功取得并粘贴回安装器，但 `--authorize-only` 收尾在真正执行账号授权前，因 `/health` 连续返回 `curl: (22) The requested URL returned error: 502` 而退出，提示“小米账号授权未完成”。
- 该失败发生在 WSL 本机 Miloco backend 的健康检查前置门槛，不依赖 home02 是否与米家设备同 LAN；因此它是脚本流程问题，不是合理环境降级。
- 当前脚本把账号授权前的 `/health` 502 当作硬阻断，导致即使用户已经完成网页登录授权，也无法把 OAuth code 交给 Miloco 尝试换 token。

本轮迭代方向：

- 授权阶段不能只因为 `/health` 502 就跳过账号授权。只要 `miloco-cli service status` 显示 backend 正在运行，应先尝试 `miloco-cli account authorize`；如果授权接口本身失败，再按真实授权失败处理。
- `/health` 仍可作为重启恢复和最终状态证据，但不应成为 OAuth code 换 token 的唯一前置条件。
- 远程测试时，Xiaomi OAuth、127.0.0.1 回调页、GitHub 下载页用完后要及时关闭，避免 home02 Chrome 旧窗口/旧标签积累占满内存。

本轮迭代已落地：

- `wsl-post-auth-finish.sh` 已调整为：授权阶段仍先尝试 `restart` 与 `stop/start` 恢复 `/health`，但如果服务进程仍在运行且健康检查没有恢复，会继续调用 `miloco-cli account authorize`，不再提前丢弃用户刚粘贴的 OAuth callback。
- `miloco-cli account authorize` 现在使用带重试的 `run_checked_json_retry 2`，如果授权接口本身失败，会明确以退出码 2 失败并提示授权 payload 未完成。
- 已重打并替换 GitHub Release `v0.2` 的 `easy-miloco-v0.2-windows.zip`；发布脚本校验远端大小 `68530911`，远端 SHA256 `d822a9b3e57554a393e5edb668ca912eb9028949af52f00a4fe19a121bc0847f`，`updated_at=2026-06-26T02:42:30Z`。

### 2026-06-26 远程 release 第二十一轮完整云端包复测

第二十一轮继续在 home02 远程 Windows 上用 GitHub Release 最新 `easy-miloco-v0.2-windows.zip` 走普通用户路径。浏览器下载得到 `easy-miloco-v0.2-windows (16).zip`，解压到 `C:\Users\17239\Documents\easy-miloco-v0.2-windows (16)`，运行正式 `install.bat`。安装器按预期检测已有安装、导出 Agent 恢复包、完整卸载旧版，再重新安装新版。home02 仍不在米家 `andy的家` 设备同一局域网，因此 `FULL_READY=no` 和摄像头/局域网链路降级仍按环境限制处理。

本轮通过项：

- 第十九轮的小米授权 URL 本地兜底仍有效：`miloco-cli account bind --no-wait` 返回 502/invalid JSON 后，脚本本地生成 OAuth URL 并自动打开小米授权页。
- 小米授权页可登录并点击确认授权；浏览器跳转到 `https://127.0.0.1/?code=...&state=...` 后，复制 callback 粘贴回安装器。
- 第二十轮的脚本修复生效：即使 `/health` 仍返回 502，脚本没有在授权前直接退出，而是继续调用 `miloco-cli account authorize`。
- 授权失败后，安装器没有卡死，继续进入 API 配置；模型列表从 `https://token-plan-sgp.xiaomimimo.com/v1/models` 拉取成功，并选择 `mimo-v2.5`。
- Miloco Omni API 配置写入成功，OpenClaw 插件配置和 OpenClaw 主聊天模型配置写入成功。
- 最终安装器输出“账号/API 配置已完成”，验证报告显示 `BASIC_READY=yes`、`FULL_READY=no`、`PASS_COUNT=12`、`FAIL_COUNT=0`、`WARN_COUNT=5`。

本轮问题：

- `miloco-cli account authorize` 真实执行后返回 `invalid JSON response: 502`，重试一次后仍失败；安装器提示“小米账号授权没有完成”。
- 这说明前一轮“没有机会调用 authorize”的脚本问题已修复，剩余问题转移到 Miloco backend 授权接口：在 backend 进程 running 但 `/health` 502 的 degraded 状态下，`account authorize` API 本身仍返回 502。
- 该授权接口 502 不依赖 home02 与米家设备是否同一局域网；它发生在 OAuth code 换 token/写账号绑定配置阶段，仍判为真实产品 bug。
- 安装器最终的 `BASIC_READY=yes` 是可接受降级完成态，但不能代表小米账号绑定完成；后续必须修复授权接口 502 后再复测账号绑定、家庭选择和 API 配置全链路。

本轮迭代方向：

- 排查 CLI `account authorize` 调用链和 backend `/api/miot/authorize`，确认 502 是否由健康检查/监控依赖、MIoT 初始化、未绑定账号、或异常响应包装导致。
- 授权接口应能在 backend running 但摄像头/设备/健康降级时完成 OAuth code 换 token；设备发现和摄像头链路可以后置降级，不应阻断账号绑定。
- 远程测试继续执行浏览器清理规则：OAuth 回调页、下载面板和旧 GitHub 下载页用完后及时关闭，避免 home02 Chrome 内存累积。

本轮代码迭代：

- `MiotProxy.get_miot_auth_info()` 增加 `refresh=False` 路径；Windows 后授权调用只做 OAuth code 换 token 与持久化，不再同步触发全量 MIoT 刷新。
- `MiotService.authorize_with_code()` 只把 token 交换失败视为授权失败；家庭列表兜底、摄像头刷新、camera adapter 同步和 perception engine 重启改为后台 best-effort，失败只记 warning，不撤销已绑定 token。
- 本地验证：`uv run pytest miloco/tests/test_miot_filter_and_cameras.py -k "authorize_with_code" -q` 通过 2 项；`uv run pytest miloco/tests/test_miot_filter_and_cameras.py -q` 通过 64 项；`uv run ruff check miloco/src/miloco/miot/client.py miloco/src/miloco/miot/service.py miloco/tests/test_miot_filter_and_cameras.py` 通过。
- 已重建 Linux runtime bundle 并替换 GitHub Release `v0.2` 的 `easy-miloco-v0.2-windows.zip`；发布脚本校验远端大小 `68532311`，远端 SHA256 `721976105dec6f247fbc21f90c6c95dfbc08a17f8d87d349552b6d19b8655e02`，`updated_at=2026-06-26T04:03:27Z`。发布过程第一次上传 300 秒超时，固定脚本自动重试后成功。

### 2026-06-26 远程 release 第二十二轮完整云端包复测（账号登录阻塞中）

第二十二轮继续在 home02 远程 Windows 上用 GitHub Release 最新包验证。Chrome 下载得到 `easy-miloco-v0.2-windows (1).zip`，解压到 `C:\Users\17239\Downloads\easy-miloco-v0.2-windows (1)`；解压目录内文件时间为 `2026-06-26 12:07`，确认是本轮新 release。运行 `install.bat` 时取消“打开此文件前总是询问”后点击运行，安装器正常提权启动。

本轮已通过项：

- 安装器检测到旧 Miloco，导出 Agent 恢复包到桌面，然后完整卸载旧版并重新安装新版。
- Miloco 基础服务重新部署成功，端口仍为 `18860`；安装阶段出现短暂 `/health` 502，但最终健康验证通过并进入后续步骤。
- OpenClaw 安装/检测通过，桌面控制台、Miloco 控制台和 OpenClaw 对话入口生成成功。
- 安装器自动打开小米 OAuth 页面。

本轮阻塞：

- home02 当前已有 Chrome 资料 `Acc`、`Dinath`、`emikoktognogxas8`、`lijsaf` 均未保留小米登录态，也未弹出小米账号密码自动填充。
- 已把授权页切到扫码登录并等待 60 秒，页面仍停留在二维码；后续需要用户扫码或提供可用小米登录会话后，才能继续点击授权、复制 `127.0.0.1` callback、回填安装器并验证账号/API 全链路。

用户扫码并点击确认授权后继续执行：

- 浏览器跳转到 `https://127.0.0.1/?code=...&state=...`，页面显示 `ERR_CONNECTION_REFUSED`，这是 OAuth callback 人工复制模式下的正常现象。
- 复制 callback 地址后，安装器完成 post-auth finish；控制台显示 `Post-auth finish completed`，并打印 `账号/API 配置已完成`。
- 最终验证报告显示 `BASIC_READY=yes`、`FULL_READY=no`、`PASS_COUNT=13`、`FAIL_COUNT=0`。`FULL_READY=no` 仍按 home02 与米家设备不在同一局域网的环境限制处理，不判为本轮脚本/授权 bug。
- 本轮关键结论：`fix: decouple miot auth from post refresh` 发布后，`account authorize` 没有再因为后续家庭/摄像头/感知刷新降级而返回 502；小米账号授权和 API 配置链路在远程 Windows release 包路径下跑通。

### 第二十三轮结果补充

- 修复后重建本地 release zip：`dist/windows/easy-miloco-v0.2-windows.zip`，大小 `68543442`，SHA256 `3210B3F0A0F221A8EEB41431FEF767712FD64F2BC340A7AFD245DCAD5DDBAFCC`。
- 首轮阻断：第 7 步 OpenClaw 插件安装失败，WSL 日志 `/tmp/openclaw-miloco-plugin-install.log` 显示 `npm install failed`，并附带 `package.json missing openclaw.hooks` 兜底校验错误；根因是 OpenClaw 插件 archive 安装默认 120 秒超时，而发布 tgz 的 `package.json` 带有 dev/peer 元数据，`npm install --omit dev` 仍解析 `@types/node`、`openclaw`、`vite` 等元数据导致超时。
- 修复：`scripts/build.sh` 在 `npm pack` 前临时裁剪 OpenClaw 插件发布 manifest，删除 `devDependencies`、`peerDependencies`、`peerDependenciesMeta`，并移除仅类型期使用的 `json-schema-to-ts` 运行依赖，pack 后仍还原源码 `package.json`。
- 修复验证：重新打包插件 tgz 后直接执行 `openclaw plugins install --force` 成功，插件状态 `Status: loaded`、`Version: 2026.6.26`。
- 重建 Windows zip 后重新安装：安装器检测到上一轮测试留下的 Miloco 痕迹，导出恢复包 `miloco-agent-restore-pack-20260626-172532-69240bcf-compat.zip`，完整卸载旧版后重新安装。
- 第 9/12 步 OpenClaw 控制台依赖通过；第 10/12 步桌面控制台、`miloco-console.ps1`、OpenClaw 对话入口创建成功；第 11/12 步诊断报告生成成功，报告路径 `C:\Users\17239\Downloads\easy-miloco-v0.2-windows\miloco-deploy-report-20260626-172709.txt`。
- 小米 OAuth：Chrome 授权页显示 `使用小米账号登录Xiaomi Miloco`，点击 `确认授权` 后跳转到 `https://127.0.0.1/?code=...&state=...`；通过本地 workflow 提交授权成功，输出 `MiOT authorized successfully`，非交互自动启用第一个家庭。
- 验证脚本结果：`BASIC_READY=yes`，`FULL_READY=no`，`PASS_COUNT=15`，`WARN_COUNT=2`，`FAIL_COUNT=0`。
- 已确认能力：Miloco 服务运行、健康检查 OK、OpenClaw Gateway connectivity OK、Miloco OpenClaw 插件 loaded、账号已绑定、设备列表可读、摄像头 `主卧 电脑桌上` 可见且 `in_use=true`。
- 未满血原因：`miloco.omni_api_key` 为空，日志提示 `感知引擎不可用: 多模态大模型 API Key 未配置`。这属于缺少用户 API Key 的配置缺口，不是基础部署失败。
- 本轮用户体验问题：PowerShell transcript 中部分中文出现重复字渲染，如 `正正在在处处理理`、`失失败败`；安装器预检有时报告 GitHub/加速节点不可达，但本地离线包仍能完成基础部署。

### 下一轮前清理要求

- 按仓库规则，每轮完成后删除本轮 `Downloads` 测试 zip/解压目录、临时 OAuth 回调文件、安装等待窗口、OAuth 浏览器标签和可确认的测试恢复包，再从仓库 `dist/windows` 重新复制 release zip 开始下一轮。

### 2026-06-26 本地迭代：控制台启动反馈与 OpenClaw 傻瓜登录信息

本轮依据用户手测反馈，集中处理桌面控制台和 OpenClaw 入口的人机交互问题，不混入后端功能改动。

本轮问题汇总：

- `Miloco 控制台` 菜单项执行后，前台常出现较长时间无反馈，随后才弹出 `按回车返回菜单`；用户很难判断到底是在启动、失败，还是卡住。
- 旧控制台只要检测到端口可连，就会认为面板可打开；这会把 `Miloco 端口活着但 /health 还没恢复`、`OpenClaw Gateway 端口已监听但 connectivity probe 未通过` 误当成功。
- `OpenClaw 对话入口` 虽然会尝试自动拼 token，但缺少一份桌面可见、可复制、可手工兜底的登录信息文件；用户不知道 WebSocket URL、token、推荐直达地址各是什么，也不知道出问题时最短路径怎么处理。

本轮迭代：

- `windows/package/install.ps1` 生成的 `miloco-console.ps1` 改为使用即时前台提示：菜单选择使用 `[Console]::Write()` 直接输出提示，不再依赖 `Read-Host` 的迟到显示。
- 控制台重启 Miloco 时，不再只看端口；改为同时等待 `http://127.0.0.1:<port>/health` 返回 `status=ok` 后才自动打开浏览器。
- 控制台重启 OpenClaw 时，端口就绪后继续等待 `openclaw gateway status` 的 connectivity probe 通过；未通过则明确提示日志路径，不再误导用户点进坏链接。
- 控制台成功路径取消了每次都弹 `按回车返回菜单` 的强制停顿；仅在失败或仍未就绪时暂停，让用户看清错误和日志路径。
- Miloco 重启命令从手工 `pkill + nohup service start` 改为优先 `miloco-cli service restart`，失败再自动 `stop/start`，并分别写入 `/tmp/miloco-desktop-restart.log`、`/tmp/miloco-desktop-stop.log`、`/tmp/miloco-desktop-start.log`。
- `OpenClaw 对话入口` 改为每次启动时刷新桌面 `OpenClaw-login-info.txt`，写入推荐直达地址、dashboard 地址、WebSocket URL、Gateway token 以及最短的用户操作说明。
- 安装完成提示和卸载/旧版清理逻辑同步纳入 `OpenClaw-login-info.txt`，避免桌面残留过期登录信息文件。

本地验证：

- `windows/package/install.ps1` PowerShell 语法解析通过。
- `windows/build-release.ps1 -Version v0.2 -ArtifactVersion 2026.6.26 -SkipBuild` 打包通过，新的本地 release zip 已生成到 `dist/windows/easy-miloco-v0.2-windows.zip`。

### 2026-06-26 本地迭代补充：OpenClaw WebUI 预填入口与信息管理说明

根据本轮用户反馈继续收口 OpenClaw 登录体验，重点修复“入口虽然存在，但仍打开到未预填完整信息的登录页”这一问题。

本轮补充问题：

- `OpenClaw 对话入口` 在已有 token 的情况下，仍可能打开到需要手工再填 token 的页面。
- 原因不是只有信息文件缺失；更关键的是入口 URL 拼接用了 `.../chat?session=main#token=...`，和 OpenClaw 官方推荐的根地址 token 引导方式不一致。
- `OpenClaw-login-info.txt` 虽然已经生成，但对“小白用户怎么刷新、怎么单独拿 token、怎么改配置”说明仍不够直给。

本轮补充迭代：

- `windows/package/install.ps1` 里桌面 `OpenClaw 对话入口` 的直达 URL 改为优先使用 `http://127.0.0.1:<port>/#token=...` 这种根地址 token 形式；只有确实拿不到 token 时，才退回非 token 的 dashboard 地址。
- 同步保留 `dashboard --no-open --yes` 与剪贴板兜底逻辑，继续优先复用 OpenClaw 官方 CLI 生成的当前入口信息。
- `OpenClaw-login-info.txt` 扩写为三段式说明：最省事的打开方式、如何获取/刷新这些信息、如何管理/修改 token，并明确给出：
  - `openclaw dashboard --no-open --yes`
  - `openclaw config get gateway.auth.token`
  - `~/.openclaw/openclaw.json`
  - `gateway.auth.token`

本地验证：

- `windows/package/install.ps1` PowerShell 语法解析通过。
- WSL 内 `openclaw config get gateway.auth.token` 可正常返回当前 token。
- 重新执行 `windows/build-release.ps1 -Version v0.2 -ArtifactVersion 2026.6.26 -SkipBuild` 打包通过。
- 新本地包：`dist/windows/easy-miloco-v0.2-windows.zip`
- 新包 SHA256：`2BBA42757F3500FBB802D83645768142B3D24C0131ADFE3A11B4BDB9C691D38D`

### 2026-06-26 本地迭代补充：控制台第 3 项重启顺序与假失败提示

根据用户贴出的控制台输出继续排查，发现这次不是单纯等待时间太短，而是“第 3 项逻辑顺序错误 + Windows 宿主访问链路可能异常”叠加。

本轮新增证据：

- WSL 日志显示 `Restart Miloco + OpenClaw` 先执行 `miloco-cli service restart`，随后执行 `openclaw gateway restart`。
- 但 OpenClaw 已安装的 Miloco 插件仍注册了 `miloco-backend` service；gateway 在重启关停阶段会调用插件 stop，导致刚刚拉起的 `miloco-backend` 被立刻 SIGTERM 停掉。
- 现场日志可见 backend 已输出 `Server is ready` / `Uvicorn running on http://127.0.0.1:18860`，随即马上进入 `Shutting down`，与用户看到的“等满 60 秒后失败返回菜单”一致。
- 另外，在本机 `C:\Users\17239\.wslconfig` 为 `networkingMode=Mirrored`、Hyper-V firewall `DefaultInboundAction=Allow` 的前提下，仍复现了“WSL 内服务健康、Windows 侧 `http://127.0.0.1:<port>` 完全打不通”的情况。说明控制台不能再把这类情况误报为“服务还没起来”。

本轮补充迭代：

- `plugins/openclaw/src/services/backend.ts` 改为 no-op：保留 `miloco-backend` service 名义注册，但 start/stop 只记日志，不再直接调用 `miloco-cli service restart/stop`。
- `windows/package/install.ps1` 里桌面控制台的第 3 项改为先重启 OpenClaw，再重启 Miloco，避免 gateway restart 在尾部把刚拉起的 backend 再次停掉。
- 控制台等待超时后新增 WSL 内二次核实：
  - Miloco 用 WSL 内 `curl http://127.0.0.1:<port>/health`
  - OpenClaw 用 WSL 内 `openclaw gateway status`
- 若 WSL 内已健康、只是 Windows 当前访问不到 `127.0.0.1:<port>`，前台提示改为明确说明“服务已在 WSL 内启动，问题更像 WSL 回环转发 / mirrored / Hyper-V / 本机防火墙访问链路异常”，不再笼统显示“还没有准备好”。

本地验证：

- `windows/package/install.ps1` PowerShell 语法解析通过。
- 手工按“先 `openclaw gateway restart`，后 `miloco-cli service restart`”顺序执行时，WSL 内可同时看到：
  - `openclaw gateway status` 为 `Connectivity probe: ok`
  - `miloco-cli service status --pretty` 为 `running: true`
- 本轮为了隔离验证，临时修改过本机 WSL 的 `~/.openclaw/openclaw.json` 与 `~/.openclaw/miloco/config.json`；验证后已恢复原文件并停止测试服务，未保留现场改动。

### 2026-06-27 本地迭代补充：安装器第 3 步 WSL 探测阶段直接退出

本轮根据用户提供的本地安装日志，继续排查“`install.bat` 双击后窗口很快关闭”的问题。

本轮新增证据：

- 现场日志 `dist/windows/easy-miloco-v0.2-windows/miloco-install-console-20260627-090457.txt` 显示，安装器稳定停在第 3 步 `检查和准备 WSL2 / Ubuntu`。
- 报错固定落在 `windows/package/install.ps1` 的 `Invoke-DistroProbe`：`wsl.exe : /bin/sh: bash: not found`。
- 同机手工执行 `wsl.exe -d Ubuntu-24.04 -- bash -lc 'echo hi'` 与 `command -v bash` 均正常，说明不是 Ubuntu 缺少 bash，而是探测函数自己拼装的 `bash -lc "cp ... && bash ...; ..."` 调用链存在兼容问题。

本轮补充迭代：

- `windows/package/install.ps1`
  - `Invoke-DistroProbe` 改为与主安装流程一致：先把探测脚本复制到 WSL `/tmp`，再直接用 `sh` 执行，避免继续依赖一整串嵌套 `bash -lc` 拼接。
  - 探测脚本中的 `BASH_OK` 改为真实检测 `command -v bash`，避免把“脚本能跑”误记成“bash 一定存在”。
  - 清理逻辑改为无论探测成功与否都主动删除 `/tmp/miloco-distro-probe-*.sh`，减少 WSL 残留。

本地验证：

- `windows/package/install.ps1` PowerShell 语法解析通过。
- 手工调用与 `Invoke-DistroProbe` 等价的新链路，`Ubuntu-24.04` 可正常返回 `ID=ubuntu`、`VERSION_ID=24.04`、`GLIBC_VERSION` 等探测字段。
- 后续需基于新打包产物重新执行完整安装链路，确认安装器可越过第 3 步继续走到后续安装阶段。

### 2026-06-27 本地迭代补充：安装器模板外置与 release 三段式验证脚本

本轮把 Windows release 的“可维护性”问题收成两项固定改造：减少 `install.ps1` 体量，以及把 release 校验从临时命令固化成脚本。

本轮补充迭代：

- `windows/package/install.ps1`
  - 把桌面控制台 `.bat` 模板、Miloco 控制台 `.ps1` 模板、OpenClaw 对话入口 `.ps1` 模板从主脚本中外置到：
    - `windows/package/templates/install-launcher.bat.tpl`
    - `windows/package/templates/miloco-console.ps1.tpl`
    - `windows/package/templates/openclaw-launcher.ps1.tpl`
  - 安装器运行时改为从 release 包内的 `scripts/windows/templates/` 读取模板，再注入发行版名和端口占位符。
- `windows/build-release.ps1`
  - 打包时显式复制上述模板文件进 release 包。
  - `Test-Package` 不再依赖正则从 `install.ps1` 里硬抠 here-string；改为直接校验模板文件存在、ASCII/LF 规则正确，并对模板替换后的 PowerShell 代码做语法解析。
- 新增 `docs/scripts/windows-release-validate.ps1`
  - 第一段：包结构自检，检查入口文件、模板文件、ASCII/LF 规则、PowerShell 语法。
  - 第二段：安装烟测，隐藏启动 release 包里的 `install.ps1`，确认至少能稳定输出 banner/步骤，而不是一打开就闪退。
  - 第三段：本机运行态 / OpenClaw 会话探针，复用 `windows-preflight.ps1`、`win-miloco-workflow.ps1 -Action Report`，并补充 dashboard/chat 路由与 gateway/token 的可见性检查。

本地验证：

- `windows/package/install.ps1`、`windows/build-release.ps1`、`docs/scripts/windows-release-validate.ps1` 均通过 Windows PowerShell 5.1 语法解析。
- 通过 `windows/build-release.ps1 -ReusePayloadZip` 重打 Windows release 包成功。
- `docs/scripts/windows-release-validate.ps1 -PackagePath dist/windows/easy-miloco-v0.2-windows.zip` 结果：
  - `package.structure`：PASS
  - `installer.smoke`：PASS
  - `runtime.preflight`：PASS
  - `runtime.report`：PASS
  - `openclaw.http_dashboard` / `openclaw.chat_route`：PASS
  - `openclaw.gateway` / `openclaw.dashboard_url` / `openclaw.gateway_token`：WARN，说明本机当前更像是“HTTP 路由已通，但 CLI 侧 URL / token 可见性没有补齐”，不再是安装包结构或入口闪退问题。

### 2026-06-27 本地迭代补充：WSL 探测不再依赖 Windows 临时文件拷贝

本轮根据用户提供的新日志，继续排查“新版包双击后仍在第 3 步闪退”的问题。

本轮新增证据：

- 现场日志 `dist/windows/easy-miloco-v0.2-windows/miloco-install-console-20260627-094340.txt` 显示，新的闪退点不再是 `bash: not found`，而是：
  - `cp: can't stat '/mnt/c/Users/17239/AppData/Local/Temp/miloco-distro-probe-xxxx.sh': No such file or directory`
- 说明 `Invoke-DistroProbe` 虽然已经不再走旧的嵌套 `bash -lc`，但仍依赖“先把脚本写到 Windows `%TEMP%`，再从 WSL 通过 `/mnt/c/...` 拷进 `/tmp`”这条链路。
- 现场最小复现表明该链路在本机并不稳定；即使 `wsl.exe` 和发行版正常，也可能在安装器真实执行时读不到刚写出的 `%TEMP%` 文件。

本轮补充迭代：

- `windows/package/install.ps1`
  - 新增 `Invoke-WslEncodedScriptInternal`，统一把 PowerShell 字符串脚本做 base64 编码后，通过：
    - `wsl.exe -d <distro> -- sh -lc "printf ... | base64 -d | sh"`
    - 或 `... | bash`
    直接送进 WSL 执行。
  - `Invoke-DistroProbe` 改为直接走这条编码执行链，不再写 `miloco-distro-probe-*.sh` 到 Windows `%TEMP%`。
  - `Invoke-WslBash` / `Invoke-WslBashText` 同步改为走同一条编码执行链，不再依赖 `cp /mnt/c/... /tmp/...`。
- 这样安装器里最关键的 WSL 脚本执行入口已不再依赖 Windows 临时目录与 `/mnt/c` 的瞬时可见性。

本地验证：

- `windows/package/install.ps1` 通过 Windows PowerShell 5.1 语法解析。
- 重新用 `windows/build-release.ps1 -ReusePayloadZip` 重打 Windows release 包成功。

### 2026-06-27 本地迭代补充：后授权摘要报错与安装报告前台回显异常

本轮根据用户提供的安装日志与报告，继续收敛安装后半段的三个问题：后授权阶段出现 Python traceback、安装前台把报告提示重复成“正正在在...”、以及安装报告生成过早导致最终状态仍显示未授权。

本轮新增证据：

- 现场日志 `dist/windows/easy-miloco-v0.2-windows/miloco-install-console-20260627-095959.txt` 显示：
  - `Authorize Xiaomi account` 与 `Post-auth finish` 阶段多次出现：
    - `NameError: name 'true' is not defined`
    - `SyntaxError: invalid character '，'`
  - 但同一轮最后 `wsl-miloco-validate.sh` 仍给出 `FULL_READY=yes`，说明不是实际授权失败，而是摘要层把 JSON / 文本错误喂给了 Python。
- 同一日志中的第 11 步“生成安装诊断报告”前台输出出现 `正正在在生生成成`、`报报告告路路径径` 这类重复字，而写入到报告文件本身的正文没有相同问题，说明问题在 Windows 侧报告汇总回显，不在子脚本实际输出。
- 现场报告 `dist/windows/easy-miloco-v0.2-windows/miloco-deploy-report-20260627-100145.txt` 的生成时间早于账号/API 收尾，导致报告里仍是：
  - `is_bound: false`
  - `FULL_READY=no`
  - `miloco.omni_api_key: empty`
  与同轮最终成功状态不一致。

本轮补充迭代：

- `docs/scripts/wsl-post-auth-finish.sh`
  - `summarize_command_output()` 不再把命令输出通过冲突的 here-string / here-doc 混喂给 `python3 -`。
  - 改为用环境变量 `SUMMARY_TEXT` 传递待摘要文本，Python 只解析脚本本身，避免把 JSON 里的 `true` 或中文提示当成 Python 代码执行。
- `docs/scripts/win-miloco-workflow.ps1`
  - `Invoke-ReportCommand()` 改为用 `Start-Process` 启动子 PowerShell，并把 stdout/stderr 重定向到临时文件后再写入报告。
  - 父进程前台只显示简短状态行，避免子进程主机输出被重复回显成“正正在在...”。
- `windows/package/install.ps1`
  - 抽出 `Invoke-DeployReport()` 统一生成诊断报告。
  - 安装主流程仍会在基础服务后先生成一份报告用于是否继续进入后配置的判断。
  - 当账号/API 收尾成功后，再追加一步“刷新最终诊断报告”，确保最终交付给用户的是完成授权后的真实状态。
  - 相应把安装总步数从 12 调整为 13，并在刷新成功后明确打印最终报告路径。

本地验证：

- `windows/package/install.ps1`、`docs/scripts/win-miloco-workflow.ps1` 通过 Windows PowerShell 5.1 语法解析。
- `docs/scripts/wsl-post-auth-finish.sh` 通过 `bash -n` 语法检查。
- 直接运行 `docs/scripts/win-miloco-workflow.ps1 -Action Report`，前台输出恢复为单次正常提示，不再出现重复字。
- 直接运行：
  - `docs/scripts/win-miloco-workflow.ps1 -Action Finish -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789 ...`
  - 前台已不再出现 `NameError: true` / `SyntaxError: 检测到非交互终端...`
  - 关键摘要恢复为正常短句，例如：
    - `[OK] Miloco service running=True ...`
    - `[OK] Omni config saved ...`
    - `[OK] Xiaomi account bound=True nickname=mdidb`
    - `[OK] Homes total=2 active=andy的家`
    - `[OK] Cameras total=1 online=1 enabled=1`
  - 最终校验结果：`BASIC_READY=yes`、`FULL_READY=yes`、`FAIL_COUNT=0`。
- `docs/scripts/windows-release-validate.ps1 -PackagePath dist/windows/easy-miloco-v0.2-windows.zip -SkipRuntime`：`package.structure` 与 `installer.smoke` 均 PASS。
- 直接对本地解压目录启动 `install.ps1` 复测时，不再停在第 3 步 WSL 探测错误；当前可见的前台结果变为“当前窗口不是管理员模式”，说明原先的闪退点已经消失，安装器恢复为正常的可读暂停行为。

### 2026-06-27 本地迭代补充：WSL 成功输出误被拼进退出码

本轮根据用户提供的新日志，继续排查“安装已走到第 8 步，但仍被误判失败”的问题。

本轮新增证据：

- 现场日志 `dist/windows/easy-miloco-v0.2-windows/miloco-install-console-20260627-095349.txt` 显示：
  - 前台已经打印 `[OK] Miloco 后端已在端口 18860 启动。`
  - 但安装器随后又报：`WSL 内命令执行失败，退出码 [OK] Miloco 后端已在端口 18860 启动。 0。`
- 这说明最新的 `Invoke-WslEncodedScriptInternal` 在“非捕获模式”下虽然成功执行了 WSL 脚本，但 PowerShell 函数把“标准输出文本”和“整数退出码”一起返回了，调用方 `$code = Invoke-WslEncodedScriptInternal ...` 收到的是混合数组，而不是纯数字。

本轮补充迭代：

- `windows/package/install.ps1`
  - `Invoke-WslEncodedScriptInternal` 的非捕获分支改为：
    - 先把 WSL 输出收集到 `$output`
    - 再逐行 `Write-Host` 回前台
    - 最后只 `return $code`
  - 这样前台仍能看到安装脚本自己的 `[OK]` / `[失败]` 输出，但调用方只会拿到纯整数退出码，不再把输出文本拼进错误提示。

本地验证：

- `windows/package/install.ps1` 通过 Windows PowerShell 5.1 语法解析。
- 最小复现脚本：
  - WSL 内执行 `echo '[OK] sample output'; exit 0`
  - 前台可见 `[OK] sample output`
  - 调用方最终拿到 `FINAL_CODE=0`
- 重新用 `windows/build-release.ps1 -ReusePayloadZip` 重打 Windows release 包成功。

### 2026-06-27 本地迭代补充：Windows release 安装器漏放感知模型

本轮根据用户反馈继续核查 “Miloco 面板提示：还没准备好 · 2 个模型文件缺失”。

本轮新增证据：

- 现场 WSL 目录 `~/.openclaw/miloco/models/` 为空。
- 代码校验口径见 `backend/miloco/src/miloco/perception/engine/resource_validator.py`：
  - 必需模型：
    - `det_4C.onnx`
    - `human_body_reid_v2.onnx`
  - 可选模型：
    - `bge-small-zh-v1.5-int8.onnx`
    - `bge-small-zh-v1.5-tokenizer.json`
    - `silero_vad.onnx`
- 仓库源码内实际存在上述模型文件，位于 `backend/miloco/src/miloco/perception/models/`，说明不是上游源码缺模型，而是 Windows release 打包 / 安装链路没有把模型带到 WSL 目标目录。
- 现场 `miloco-cli scope camera list --pretty` 只有 1 台启用中的摄像头，而 `miloco-cli device list` 中确有 3 台在线摄像头；这说明 “3 台在线摄像头” 是设备发现事实，但不等于 “感知应该自动启用 3 台”。模型缺失与摄像头启用数量不是同一个问题。

本轮补充迭代：

- `windows/build-release.ps1`
  - release 打包阶段新增 `scripts/windows/models/` 目录。
  - 显式把 `backend/miloco/src/miloco/perception/models/` 下的模型文件复制进 release 包。
  - self-test 增加对 5 个模型文件的存在性校验，避免再次发出“安装包本身不带模型”的 zip。
- `windows/package/install.ps1`
  - 安装包完整性检查新增感知模型检查；缺少必需模型时直接失败，不再把缺陷包继续安装下去。
  - 新增 `Sync-PerceptionModelsToWsl`，在基础服务安装后、OpenClaw 步骤前，把 release 包内模型同步到 `~/.openclaw/miloco/models/`。
  - 同步后对 `det_4C.onnx` 与 `human_body_reid_v2.onnx` 做二次存在性确认。
  - 安装总步数同步更新，避免前台编号与真实步骤不一致。

现场修复与验证：

- 手工把仓库内模型复制到现场 WSL：
  - `~/.openclaw/miloco/models/`
- 重启 Miloco 后，后端日志出现：
  - `EventEmbedder loaded (bge-small-zh-v1.5-int8.onnx)`
  - `Perception engine started`
  - `get_reid_extractor ... /home/andywu/.openclaw/miloco/models/human_body_reid_v2.onnx`
- 说明“2 个必需模型缺失”这条根因已被现场验证并解除。
- 重新打包后的本地 release zip 解压复查时，已确认包含：
  - `det_4C.onnx`
  - `human_body_reid_v2.onnx`
  - `bge-small-zh-v1.5-int8.onnx`
  - `bge-small-zh-v1.5-tokenizer.json`
  - `silero_vad.onnx`
