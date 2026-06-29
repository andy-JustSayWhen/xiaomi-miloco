# Miloco 一键部署路由

Agent 先判断目标系统，然后只读对应子指南。

| 目标系统 | 子指南 raw URL | 入口类型 |
| --- | --- | --- |
| Windows | [docs/windows/agent-install.md](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/macOS/docs/windows/agent-install.md) | Windows + WSL2 Agent 自动部署 |
| macOS | [docs/macos/agent-install.md](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/macOS/docs/macos/agent-install.md) | macOS Agent 自动部署 |
| Linux / NAS | [docs/runbooks/nas01-openclaw-miloco-install.md](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/macOS/docs/runbooks/nas01-openclaw-miloco-install.md) | NAS/Linux 经验复盘，非一键包 |

硬规则：

- Windows 必须走 WSL2，不要在 Windows 原生安装 Miloco。
- macOS 直接使用 darwin runtime，绝对不要使用 WSL。
- 不要混用不同系统的脚本、日志路径和验收命令。
- 按子指南验收；`FULL_READY=no` 不等于安装失败，必须说明缺口。
