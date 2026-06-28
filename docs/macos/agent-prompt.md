# macOS Agent 一句话部署提示词

把下面整段复制给 Agent。适用前提：用户已经解压 easy-miloco macOS 懒人包，Agent 可以在这台 Mac 上执行 shell 命令。

```text
你现在接管这台 macOS 电脑的 easy-miloco 部署。目标是基于当前已解压的 easy-miloco macOS 懒人包完成部署，并给出 BASIC_READY / FULL_READY 验收结果。

硬性规则：
1. 这是 macOS，绝对不要使用 WSL。
2. 先定位懒人包根目录，根目录必须包含 install.command、manifest.json、payload/install.sh、payload/miloco-darwin-*.tar.gz、scripts/macos/。
3. 先运行预检：
   bash scripts/macos/macos-preflight.sh --package-root .
4. 优先使用懒人包入口：
   ./install.command
   如果当前 Agent 环境不能交互双击，就手动执行同等步骤：
   - 读取 manifest.json 的 version。
   - 把 payload/miloco-darwin-*.tar.gz 解压到 ~/.openclaw/miloco/.install-cache/<version>/。
   - 确保 PATH 包含 ~/.openclaw/bin、~/.local/bin、~/.cargo/bin、~/.local/share/uv/tools/supervisor/bin。
   - 如果没有 openclaw，下载并执行 https://openclaw.ai/install-cli.sh。
   - 运行 bash payload/install.sh --agent-prepare。
5. 解析 --agent-prepare 输出的 AGENT_JSON。先处理小米账号授权，再处理 Omni 模型配置，不要同时问两个问题。
6. 用户提供小米 OAuth payload 后，使用 --agent-finish 或 scripts/macos/macos-post-auth-finish.sh 收尾。
7. 收尾后运行：
   bash scripts/macos/macos-miloco-validate.sh --strict-full
8. 不能只以服务启动作为完成。必须报告 Miloco URL、OpenClaw URL、账号状态、模型 Key 状态、设备列表状态、摄像头 scope 状态。
9. 摄像头异常不要重装，按“云端设备 -> LAN -> scope -> stream connected -> engine active_sources -> OpenClaw 视觉推理”分层定位。
10. 下载或安装超过 1 分钟无输出时，先检查进程和日志，不要重复启动多个安装器。

交付格式：
- Miloco URL
- OpenClaw URL
- BASIC_READY / FULL_READY
- 如果 FULL_READY=no，列出缺口
- 关键日志路径
```
