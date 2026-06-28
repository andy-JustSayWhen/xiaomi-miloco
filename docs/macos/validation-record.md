# macOS 懒人包验证记录

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
