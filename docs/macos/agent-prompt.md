# macOS Agent 一句话部署提示词

把下面整段复制给 Agent。适用前提：Agent 可以在这台 Mac 上执行 shell 命令；如果用户已经下载 release zip，把路径一并提供。

```text
你现在接管这台 macOS 电脑的 easy-miloco 部署。先读取总入口：

https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/main/docs/install-guide.md

确认当前系统是 macOS 后，按总入口路由到 macOS Agent 子指南执行。目标是自动下载或使用我提供的 macOS release zip，完成部署，并给出 BASIC_READY / FULL_READY 验收结果。

硬性规则：
1. 这是 macOS，绝对不要使用 WSL。
2. 如果我提供了 zip，使用该 zip；否则从 GitHub Release 下载当前架构的 macOS zip。
3. 解压后先定位懒人包根目录，根目录必须包含 install.command、manifest.json、payload/install.sh、payload/miloco-darwin-*.tar.gz、scripts/macos/。
4. 先运行预检：
   bash scripts/macos/macos-preflight.sh --package-root .
5. Agent 自动部署必须使用懒人包的非交互入口，不要直接运行交互式 `./install.command`：
   ./install.command --agent-prepare
6. 先处理小米账号授权，再处理 Omni 模型配置，不要同时问两个问题。
7. 模型配置必须收集 API Key、Base URL、Model，不要只收 Key。
8. 用户提供小米 OAuth payload、API Key、Base URL、Model 后，使用懒人包收尾：
   ./install.command --agent-finish --account-auth '<授权码或完整回调 URL>' --omni-api-key '<API Key>' --omni-base-url '<Base URL>' --omni-model '<Model>'
9. 收尾后运行：
   ./install.command --validate
10. 不能只以服务启动作为完成。必须报告 Miloco URL、OpenClaw URL、账号状态、模型 Key/Base URL/Model 状态、设备列表状态、摄像头 scope 状态。
11. 必须打开 Miloco 面板和 OpenClaw 聊天页，问“家里有几个摄像头？画面如何？”。
12. 摄像头异常不要重装，按“云端设备 -> LAN -> scope -> stream connected -> engine active_sources -> OpenClaw 视觉推理”分层定位。
13. 下载或安装超过 1 分钟无输出时，先检查进程和日志，不要重复启动多个安装器。

交付格式：
- Miloco URL
- OpenClaw URL
- BASIC_READY / FULL_READY
- 如果 FULL_READY=no，列出缺口
- 关键日志路径
```
