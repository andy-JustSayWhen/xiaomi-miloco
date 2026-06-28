# macOS 懒人包验证记录

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
