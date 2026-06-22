# AGENT.md

本文件是 Agent 操作本仓库时的总入口。收到用户类似“部署一下”“生成诊断报告”“修复 Windows 部署问题”的自然语言指令时，先读本文件，再执行对应 runbook。

制作更新包、打 tag、发布 GitHub Release 属于维护者任务。只有仓库维护者明确要求“制作更新包”“打包更新吧”“发版”时，才允许读取 `docs/runbooks/make-release-package.md` 并推进发布流程。

## 总规则

1. 先确认用户目标属于哪一类：部署、更新、回滚、制作 release 包、诊断、文档沉淀。
2. 不要盲目重装。优先生成诊断报告，按层判断问题出在 Windows、WSL、Miloco backend、OpenClaw Gateway、插件、账号、模型、设备还是摄像头。
3. 更新或修改前，先保护项目相关状态。默认只保护 Miloco/OpenClaw 相关状态，不导出整个 WSL。
4. GitHub Release 是唯一版本基准。夸克网盘只作为人工同步的下载副本，必须用 SHA256 校验。
5. 每次新增问题、修复路径或成功部署经验，都应沉淀到 `docs/faq/known-issues.md` 或对应 runbook。
6. 如果 README 指向的脚本或 runbook 还不存在，不要假装已经可用；应先创建缺失文件或明确报告当前缺口。

## 常见指令映射

| 用户说法 | Agent 应读 | Agent 应做 |
| --- | --- | --- |
| “部署一下” | 本文件、`docs/index.md`、平台 runbook | 预检、安装、配置、验收 |
| “打包更新吧” | 本文件、`docs/runbooks/make-release-package.md` | 维护者专用：构建 release 包、自测、生成 SHA256 和 release notes |
| “检查更新” | 更新 runbook | 读取 GitHub Release，展示更新说明，等待用户确认 |
| “回滚” | 回滚 runbook | 列出项目级快照，按用户选择恢复 |
| “出问题了” | FAQ 和诊断 runbook | 生成报告，按失败层修复 |

## 当前 v0.1 状态

当前仓库处于 Windows 一键部署 v0.1 规划/落地阶段。`docs/` 已作为 Agent 和用户的知识库入口；`windows/` installer、release builder、rollback 工具需要在后续任务中实现。

因此，Agent 在执行“制作更新包”时必须先检查：

```text
windows/build-release.ps1
windows/
docs/runbooks/make-release-package.md
```

如果 `windows/build-release.ps1` 尚不存在，则当前任务不是直接打包，而是先实现 release builder。

## 沉淀要求

完成任务后，如有以下任一情况，必须更新文档：

- 出现新的错误现象。
- 发现新的系统兼容边界。
- 发现新的下载、代理、端口、WSL、OpenClaw 或摄像头问题。
- 成功跑通一台新 Windows 机器。
- release 打包流程新增人工步骤，例如同步夸克网盘副本。

优先沉淀到：

```text
docs/faq/known-issues.md
docs/runbooks/
docs/releases/
```
