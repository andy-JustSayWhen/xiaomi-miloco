# easy-miloco Docs

这是本 fork 的文档总入口。文档围绕三件事长期维护：

- 快速部署：让普通用户和 Agent 都能按文档完成一键部署、更新和回滚。
- 源码优化：记录本 fork 相对官方仓库做过哪些代码和实现调整。
- 使用教程：面向小白，长期更新 Miloco 系列教程、常见问题和成功经验。

## 用户入口

- 一键部署：[install-guide.md](install-guide.md)
- 摄像头支持和排障：[cameras.md](cameras.md)
- 常见问题：[faq/known-issues.md](faq/known-issues.md)

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
