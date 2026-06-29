# Miloco 一键部署路由

本地 `.md` 是唯一源文件；raw URL 只是 GitHub 根据当前分支文件生成的读取入口，不单独维护。

Agent 先判断目标系统，然后只读对应子指南。

| 目标系统 | 本地源文件 | raw URL |
| --- | --- | --- |
| Windows | `docs/windows/agent-install.md` | [打开](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/macOS/docs/windows/agent-install.md) |
| macOS | `docs/macos/agent-install.md` | [打开](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/macOS/docs/macos/agent-install.md) |
| Linux / NAS | `docs/runbooks/nas01-openclaw-miloco-install.md` | [打开](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/macOS/docs/runbooks/nas01-openclaw-miloco-install.md) |

硬规则：

- Windows 必须走 WSL2，不要在 Windows 原生安装 Miloco。
- macOS 直接使用 darwin runtime，绝对不要使用 WSL。
- 不要混用不同系统的脚本、日志路径和验收命令。
- 按子指南验收；`FULL_READY=no` 不等于安装失败，必须说明缺口。
