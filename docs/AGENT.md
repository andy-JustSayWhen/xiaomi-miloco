# AGENT.md

本文件是 Agent 操作本仓库时的文档入口。收到“部署一下”“检查更新”“回滚”“排查摄像头”“制作更新包”“发版”等自然语言任务时，先读本文件，再进入对应 runbook。

## 总规则

1. 先判断任务类型：部署、更新、回滚、诊断、摄像头排障、文档沉淀、制作 release 包。
2. 不要盲目重装。优先生成诊断报告，按 Windows、WSL、Miloco backend、Miloco WebUI、OpenClaw、账号、模型、设备、摄像头分层定位。
3. 更新或修复前，只保护 Miloco/OpenClaw 相关状态，不默认导出整个 WSL。
4. GitHub Release 是唯一版本基准。夸克网盘只作为人工同步的下载副本。
5. 新增问题、修复路径或成功部署经验后，更新 [faq/known-issues.md](faq/known-issues.md) 或对应 runbook。
6. 如果 README 指向的脚本或 runbook 不存在，先创建缺失文件或明确报告当前缺口，不要假装已经可用。
7. 部署测试遇到非阻断问题时，先记录到验证文档，继续走完原计划步骤；跑完整轮后统一汇总、迭代、重测，不要边测边改导致流程状态混乱。

## 常见指令映射

| 用户说法 | Agent 应读 | Agent 应做 |
| --- | --- | --- |
| “部署一下” | [install-guide.md](install-guide.md)、[windows/agent-install.md](windows/agent-install.md) | 预检、安装、配置、授权、验收 |
| “摄像头离线/看不到画面” | [cameras.md](cameras.md)、[windows/camera-runbook.md](windows/camera-runbook.md) | 区分云端在线、局域网在线、流连接、OpenClaw 视觉理解四层状态 |
| “检查更新” | [runbooks/make-release-package.md](runbooks/make-release-package.md) 的版本基准说明 | 读取 GitHub Release，展示更新说明，等待用户确认 |
| “回滚” | Windows 回滚 runbook，若缺失则先补齐 | 列出项目级快照，按用户选择恢复 |
| “制作更新包/打包更新/发版” | [runbooks/make-release-package.md](runbooks/make-release-package.md) | 维护者专用：构建 release 包、自测、生成 release notes |

## 文档沉淀要求

完成任务后，如有以下情况，必须更新文档：

- 出现新的错误现象。
- 发现新的系统兼容边界。
- 发现新的下载、代理、端口、WSL、OpenClaw 或摄像头问题。
- 成功跑通一台新的 Windows 机器。
- release 打包流程新增人工步骤，例如同步夸克网盘副本。

优先沉淀到：

```text
docs/faq/known-issues.md
docs/windows/
docs/runbooks/
docs/releases/
```

部署测试记录优先使用：

```text
docs/windows/validation-record.md
docs/tests/test-guide.md
docs/runbooks/azure-vm-nonvisual-test.md
```

## 公开仓库注意事项

公开 docs 不写入用户账号、密码、API Key、OAuth code、设备 PIN 等私密值。需要说明配置时，使用占位符和本机路径模板；私有实录可保留在用户自己的 OB 仓库。
