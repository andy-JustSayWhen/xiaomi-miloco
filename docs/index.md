# easy-miloco Docs

这是本 fork 的文档总入口。这里的文档服务两类读者：

- 用户：安装、更新、回滚、诊断和常见问题。
- Agent：自动部署、自动打包、排障和经验沉淀。

## Agent 入口

Agent 必须先读：

- [install-guide.md](install-guide.md)
- [AGENT.md](AGENT.md)

常见任务：

- 部署当前机器：先读 [AGENT.md](AGENT.md)，再按平台进入对应 runbook。
- 制作更新包：维护者专用，读 [runbooks/make-release-package.md](runbooks/make-release-package.md)。
- 排查问题：先生成诊断报告，再查 [faq/known-issues.md](faq/known-issues.md) 和 `runbooks/`。

## Windows v0.1

Windows v0.1 目标是先把 Windows 11 22H2+ 的一键部署、更新、回滚和诊断跑通。低于该版本的 Windows 不提供完整兼容保证。

计划文档：

- `windows/compatibility.md`
- `windows/update-and-rollback.md`
- `windows/differences-from-upstream.md`

这些文件会在 v0.1 installer 实现过程中补齐。
