# easy-miloco Docs

这里是本 fork 的文档总入口。文档围绕三件事长期维护：

- 快速部署：提供一键部署包，让普通用户和 Agent 尽量少碰复杂依赖和配置。
- 源码优化：记录本 fork 相对官方仓库做过哪些代码和实现调整。
- 使用教程：面向小白，长期更新 miloco 系列教程、常见问题和成功经验。

## 用户入口

- 一键部署：[install-guide.md](install-guide.md)
- Windows 部署总入口：[windows/index.md](windows/index.md)
- 摄像头支持和排障：[cameras.md](cameras.md)
- 常见问题：[faq/known-issues.md](faq/known-issues.md)

## Agent 入口

Agent 必须先读：

- [AGENT.md](AGENT.md)
- [install-guide.md](install-guide.md)

常见任务：

- 部署当前机器：读 [windows/agent-install.md](windows/agent-install.md)，按预检、安装、授权、验收顺序推进。
- 手动排障：从 [windows/troubleshooting.md](windows/troubleshooting.md) 和 [faq/known-issues.md](faq/known-issues.md) 开始。
- 摄像头排障：读 [windows/camera-runbook.md](windows/camera-runbook.md) 和 [cameras.md](cameras.md)。
- 远程 Windows/WSL 排障命令传输：读 [windows/ssh-command-transfer.md](windows/ssh-command-transfer.md)。
- UU 远程用户视角测试：读 [windows/uu-remote-computer-use.md](windows/uu-remote-computer-use.md)，优先鼠标、右键粘贴和安全中转。
- 性能报告与面板入口：读 [runbooks/performance-report-webui-spec.md](runbooks/performance-report-webui-spec.md)。
- 制作更新包：维护者专用，读 [runbooks/make-release-package.md](runbooks/make-release-package.md)。
- Azure VM 非视觉部署和验证：读 [runbooks/azure-vm-nonvisual-test.md](runbooks/azure-vm-nonvisual-test.md)。
- NAS 类 Linux 主机安装复盘：读 [runbooks/nas01-openclaw-miloco-install.md](runbooks/nas01-openclaw-miloco-install.md)。

## 文档地图

| 目录 | 用途 |
| --- | --- |
| [windows/](windows/index.md) | Windows 安装、预检、故障、验收、<windows-sample-host> 实录 |
| [runbooks/](runbooks/change-and-debug-runbook.md) | 变更、排障、发版前检查 |
| [tests/](tests/test-guide.md) | 测试矩阵和验收清单 |
| [meta/](meta/source-map.md) | 源码地图和维护日志 |
| [scripts/](scripts/README.md) | 从 OB 迁入的预检与验收脚本 |
| [windows/reports/](windows/reports/) | <windows-sample-host> 部署和摄像头验收报告 |

## v0.2 边界

v0.2 先保证 Windows 11 22H2+ 的一键部署、更新、回滚和诊断路线。低于该版本的 Windows 可能可以运行基础服务，但不保证摄像头实时流、WSL 网络、Hyper-V 防火墙、OpenClaw/Miloco 联动稳定可用。
