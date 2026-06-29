# Miloco 一键部署路由

本地 `.md` 是唯一源文件；raw URL 只是 GitHub 根据当前分支文件生成的读取入口，不单独维护。

Agent 先判断目标系统，然后只读对应子指南。

| 目标系统 | 本地源文件 | raw URL |
| --- | --- | --- |
| Windows | `docs/windows/agent-install.md` | [打开](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/main/docs/windows/agent-install.md) |
| macOS | `docs/macos/agent-install.md` | [打开](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/main/docs/macos/agent-install.md) |
| Linux / NAS | `docs/nas/index.md`，通过后 Agent 读 `docs/nas/agent-install.md`，用户读 `docs/nas/docker-deploy.md` | [硬门槛](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/NAS/docs/nas/index.md) / [Agent](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/NAS/docs/nas/agent-install.md) / [Docker](https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/NAS/docs/nas/docker-deploy.md) |

硬规则：

- Windows 必须走 WSL2，不要在 Windows 原生安装 Miloco。
- macOS 直接使用 darwin runtime，绝对不要使用 WSL。
- NAS 必须先过 `docs/nas/index.md` 的硬门槛；不满足系统/架构/glibc 条件时停止。
- 不要混用不同系统的脚本、日志路径和验收命令。
- 按子指南验收；`FULL_READY=no` 不等于安装失败，必须说明缺口。
