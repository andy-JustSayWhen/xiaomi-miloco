# macOS 懒人包验证记录

## 2026-06-29 v0.1 arm64 自动化 + 可视化回归

分支：`macOS`

产物：

```text
dist/macos/easy-miloco-v0.1-macos-arm64.zip
```

SHA-256：

```text
15776e90e8fd4693215fdff6623f5b5d41e15c19c3cf60471eea480411264ec0
```

### 自动化部署测试

执行路径：

```text
1. 解压 zip 到 /tmp/easy-miloco-auto-test。
2. 运行 install.command --agent-prepare。
3. 使用既有恢复包补齐模型 Key / Base URL / model 后运行 macos-post-auth-finish.sh --no-strict-full。
4. 测试结束后停止 Miloco、卸载 OpenClaw Gateway、删除 ~/.openclaw/miloco、桌面入口和临时解包目录。
```

结果：

```text
INSTALL_EXIT=0
FINISH_MODEL_EXIT=0
BASIC_READY=yes
FAIL_COUNT=0
```

通过项：

```text
- 检测到已有 OpenClaw Miloco 插件残留时，安装器先导出桌面 Agent 恢复包，再卸载旧版，再继续安装。
- preflight 通过，1810/18789 端口在安装前为空。
- Miloco 服务启动，/health 返回 {"status":"ok"}，面板 HTTP 200。
- OpenClaw Gateway 以 LaunchAgent 方式启动，Connectivity probe ok。
- 桌面入口创建成功：
  ~/Desktop/Miloco Console.command
  ~/Desktop/OpenClaw Chat.command
  ~/Desktop/OpenClaw-login-info.txt
- OpenClaw 打开地址带 #token=，不再停在登录页。
- OpenClaw 主聊天模型同步为 mimo/mimo-v2.5，provider/baseUrl/apiKey/modelRow 均 configured。
```

自动化轮边界：

```text
本轮 --agent-prepare 未输入小米 OAuth payload，因此账号、设备、摄像头满血不在自动化轮完成。
模型配置可从本机恢复包补齐，但账号授权必须在可视化轮真实走浏览器 OAuth。
```

### 可视化部署测试

执行路径：

```text
1. Finder 打开 dist/macos。
2. 图形界面解压 easy-miloco-v0.1-macos-arm64.zip。
3. 从解压目录打开 install.command，Terminal 真实交互安装。
4. 浏览器自动打开小米 OAuth 页面，点击确认授权。
5. 浏览器跳到 https://127.0.0.1/?code=...&state=... 报错地址后，把完整地址栏粘回 Terminal。
6. 选择家庭 andy的家。
7. 模型配置页显示 Windows 同源的三个推荐入口；已有 Key 直接回车后，依次粘贴 API Key、Base URL，模型列表默认选择 mimo-v2.5。
8. 安装结束后自动打开 Miloco 面板和 OpenClaw Chat。
9. 测试结束后停止服务、卸载 LaunchAgent、删除 ~/.openclaw/miloco、桌面入口、解包目录并关闭本地页面。
```

验证结果：

```text
BASIC_READY=yes
FULL_READY=no
WARN_COUNT=1
FAIL_COUNT=0
FULL_FAIL_COUNT=1
```

通过项：

```text
- OAuth 两种提示口径实际可用：浏览器跳到 https://127.0.0.1/?code=...&state=... 后，粘贴完整地址栏可成功授权。
- 家庭切换到 andy的家。
- 模型 Key、Base URL、mimo-v2.5 配置成功。
- 最终 Terminal 屏幕显示桌面入口、Miloco 面板地址、OpenClaw Chat 使用方式和 OpenClaw-login-info.txt。
- Chrome 自动打开 OpenClaw Chat，不再显示登录页；URL 中 token 被页面吸收。
- Miloco 概述页显示 andy的家、127 件设备、实时画面区域，实时画面显示 2 个在感知，并可见两路画面。
```

摄像头证据：

```text
miloco-cli scope camera list --pretty:
- 1039007350 / 摄像头 客厅 / 客厅 / is_online=true / in_use=true / connected=true
- 450305034 / 床边置物架 / 主卧 / is_online=true / in_use=true / connected=true
- 1146439633 / 主卧 电脑桌上 / 主卧 / is_online=true / in_use=true / connected=false

miloco-cli perceive devices --pretty:
- 1039007350 / 摄像头 客厅 / camera / online=true
- 450305034 / 床边置物架 / camera / online=true
- 1146439633 / 主卧 电脑桌上 / camera / online=true

Miloco 面板口径：
- 家庭：andy的家
- 设备：127 件
- 实时画面：2 个在感知
- 可见画面：客厅、主卧床边视角
```

OpenClaw Chat 问答证据：

```text
提问：家里有几个摄像头？画面如何？

回复摘要：
- 回答家里一共有 3 个摄像头。
- 列出摄像头 客厅、床边置物架、主卧 电脑桌上。
- 描述客厅画面：无人，沙发、抱枕、熊猫玩偶、茶几纸巾盒等。
- 描述主卧床边视角：电脑显示器亮着，桌面有白色小风扇，房间无人。
- 描述主卧电脑桌视角：同一房间另一个角度，能看到键盘、鼠标、风扇、衣柜和收纳区。
```

发现的问题：

```text
1. macos-miloco-validate.sh 的 miloco.devices 仍报 no device rows，但 Miloco 面板实际显示 127 件设备，说明 device list 验证口径或命令输出解析需要修正。
2. scope camera 显示第三台 主卧 电脑桌上 connected=false，Miloco 面板实时画面也只显示 2 个在感知；但 OpenClaw Chat 回复把第三台也说成“画面正常”。这属于 OpenClaw 摄像头画面口径缺陷，不能算满血通过。
3. Computer Use 直接读取 Finder 超时，最终使用 Finder/open/AppleScript + 截图完成真实可视化路径。该问题属于测试控制工具限制，不是安装包功能问题。
```

清理结果：

```text
- 1810 无监听。
- 18789 无监听。
- Miloco/OpenClaw/install.command/macos-miloco-validate 无残留进程。
- 桌面 Miloco Console.command、OpenClaw Chat.command、OpenClaw-login-info.txt 已删除。
- dist/macos 解包目录 easy-miloco-v0.1-macos-arm64 已删除。
- 保留正式 zip 与历史 Agent 恢复包作为发布和恢复证据。
```

## 2026-06-29 v0.1 arm64 小白用户路径复测

分支：`macOS`

产物：

```text
dist/macos/easy-miloco-v0.1-macos-arm64.zip
```

SHA-256：

```text
648f97b0db4be0040672de1588abfcf2cfd8d438ef41eed82ab79bc69e4b8354
```

本轮测试目标：

```text
模拟普通 macOS 用户：解压 zip，双击 install.command，按窗口提示完成部署。
```

环境限制：

```text
本轮执行可视化鼠标测试时，macOS 屏幕处于锁屏界面。Computer Use 无法读取或操作 Chrome/Finder/Terminal 的真实窗口，因此米家 OAuth 页面无法通过鼠标点击确认，也无法读取浏览器地址栏回调。
```

已完成的真实安装验证：

```text
1. 使用当前 zip 解包后运行 install.command。
2. 安装器检测到旧版 Miloco：
   MILOCO_CLI=yes
   OPENCLAW_CLI=yes
   MILOCO_HOME=yes
   MILOCO_SERVICE=yes
   MILOCO_HEALTH=yes
   OPENCLAW_HTTP=yes
   MILOCO_PLUGIN=yes
3. 旧版迁移流程真实通过：
   - 先导出桌面 Agent 恢复 ZIP
   - 再卸载旧版 Miloco
   - 卸载后 preflight 看到 1810/18789 均 free
4. 新版基础安装通过：
   - miloco.service_status running
   - miloco.health {"status":"ok"}
   - miloco.dashboard HTTP 200
   - openclaw.gateway LaunchAgent loaded
   - openclaw.plugin miloco plugin visible
   - model_key configured
   - BASIC_READY=yes
   - FAIL_COUNT=0
```

未完成项：

```text
1. 米家 OAuth 未完成：原因是屏幕锁定，无法点击浏览器授权页面。
2. 因账号未绑定，device rows 和 camera scope 不能 full ready。
3. OpenClaw agent 对话未完成：当前 OpenClaw agent 缺可用模型认证；cc-switch 中 DeepSeek Codex 配置存在 API key，但 OpenClaw model registry 不识别 deepseek-v4-flash。
```

小白用户路径发现的问题：

```text
问题：macOS 原生 ditto 解压 zip 后，install.command / install.sh / macos-*.sh 执行位丢失，双击 install.command 可能失败。
原因：Python zipfile 写包时只写了权限位 0755，没有写 Unix file type；ditto 不按 unzip 的方式使用该权限元数据。
修复：macos/build-release.sh 写 ZipInfo 时设置 create_system=3，并把完整 st_mode 低 16 位写入 external_attr。
```

修复后验证：

```text
ditto -x -k dist/macos/easy-miloco-v0.1-macos-arm64.zip /tmp/easy-miloco-ditto-fixed

结果：
-rwxr-xr-x install.command
-rwxr-xr-x payload/install.sh
-rwxr-xr-x scripts/macos/macos-preflight.sh

包内元数据：
install.command create_system=3 attr=0o100755
payload/install.sh create_system=3 attr=0o100755
```

本轮测试后清理：

```text
Miloco 服务、Miloco uv tools、Miloco 数据目录、OpenClaw Miloco 插件、桌面入口、临时解包目录均已清理。
旧版迁移导出的恢复 ZIP 保留在桌面作为证据。
```

## 2026-06-29 v0.1 arm64 本机安装/卸载验证

分支：`macOS`

产物：

```text
dist/macos/easy-miloco-v0.1-macos-arm64.zip
```

包大小：

```text
65M
```

SHA-256：

```text
73e9eaad426f4d3f3c42dd68a21627d98ef3baa50185a4ac951eefb9ae91a5d3
```

构建命令：

```bash
PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" macos/build-release.sh
```

包内关键文件已验证存在：

```text
install.command
agent-prompt.md
manifest.json
payload/install.sh
payload/miloco-darwin-arm64-2026.6.29.tar.gz
scripts/macos/macos-preflight.sh
scripts/macos/macos-miloco-validate.sh
scripts/macos/macos-post-auth-finish.sh
```

真实安装测试：

```text
测试前清理：删除 ~/.openclaw、~/Library/LaunchAgents/ai.openclaw.gateway.plist、桌面入口，确认 1810/18789 未监听。
执行：./install.command --agent-prepare
结果：BASIC_READY=yes，FAIL_COUNT=0，FULL_READY=no。
日志：/tmp/easy-miloco-macos-agent-prepare-final.log
```

关键通过项：

```text
[PASS] port.1810 free
[PASS] port.18789 free
[PASS] miloco.service_status server.url=http://127.0.0.1:1810
[PASS] miloco.health {"status":"ok"}
[PASS] miloco.dashboard HTTP 200
[PASS] openclaw.cli OpenClaw 2026.6.10 (aa69b12)
[PASS] openclaw.gateway LaunchAgent loaded, Connectivity probe: ok
[PASS] openclaw.plugin miloco plugin visible
BASIC_READY=yes
FAIL_COUNT=0
```

Agent 一句话部署 finish 测试：

```text
执行：./install.command --agent-finish
结果：BASIC_READY=yes，FAIL_COUNT=0，FULL_READY=no。
日志：/tmp/easy-miloco-macos-agent-finish-final.log
finish 已完成：本地感知模型解压、OpenClaw 插件安装、tools.alsoAllow 注册、会话访问权限开启。
```

FULL_READY 边界：

```text
FULL_READY=no 是预期结果。本机测试未提供真实小米账号、模型 API key 和米家设备，因此保留：
[WARN] miloco.account not bound
[WARN] miloco.model_key missing
[WARN] miloco.devices no device rows
[WARN] miloco.cameras no camera scope evidence
```

卸载清理验证：

```text
执行：miloco-cli service stop；openclaw gateway stop/uninstall；payload/install.sh --uninstall --delete-home；删除 ~/.openclaw、LaunchAgent plist、桌面入口。
结果：
miloco_home=no
openclaw_home=no
gateway_plist=no
desktop_helpers=0
ports=none
commands=none
```

本轮修正：

```text
1. macOS 默认 Miloco 端口从 18860 改为后端实际监听的 1810。
2. install.command 在已有 node/npm 时优先 npm 安装 OpenClaw 到 ~/.openclaw，避免官方脚本下载 Node 大包卡住；无 node/npm 时仍回退官方 install-cli。
3. OpenClaw gateway 首次启动会解析 status 文本，发现 LaunchAgent 未安装时先 gateway install，再 restart/start。
4. validation 不再用 Dashboard URL 文本误判 gateway 成功，必须看到 Runtime running、Listening 或 Connectivity probe: ok，且不能包含 not installed/failed。
```

## 2026-06-28 v0.1 arm64 本地打包验证

分支：`macOS`

产物：

```text
dist/macos/easy-miloco-v0.1-macos-arm64.zip
```

包大小：

```text
65M
```

SHA-256：

```text
97abd80bc6fdeffda93e0609b0343a966025860da30d5a63ee44eff5fc897f44
```

验证摘要：

```text
仅完成构建、包结构、SHA、预检和 Agent 提示词入包验证。
未执行完整 install.command。
FAIL_COUNT=0
```
