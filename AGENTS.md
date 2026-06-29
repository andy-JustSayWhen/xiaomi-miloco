# easy-miloco Agent 规则

## 每一轮的第一步
- 本分支 main 是发布主线，允许处理跨平台安装、发版、文档、后端、前端、CLI 和插件相关维护；高风险或大范围重构应先新建专题分支。
- 在规划、编辑、测试或回答任何与本仓库有关的问题之前，先阅读本文件。
- 如果对话是恢复、压缩或中断后继续的，或者任务感觉不清晰，继续前再次阅读本文件。
- 如果用户指令与本文件冲突，询问用户而不是武断处理；
- 当用户让你记住任何东西，你都必须保存为文档并在本文件中引用，仅在上下文中临时存储是极易丢失的。记忆文档请落盘到C:\Users\17239\Desktop\easy-miloco\docs\memorys\，然后在本文件的<## 引用的记忆>中添加引用
- 在修改代码前，阅读 `README.md` 的 `### 目录树` 小节；除非确有必要，不要新增顶层目录。

## 网络规则
- 如果上传/下载或 git 网络操作很慢，应当使用本地 Clash 代理 `http://127.0.0.1:7897`，若Clash未运行，你应当先主动打开该App，否则代理是无效的。
- 下载或上传一旦速率低于1mb/s,持续1分钟以上，必须告知用户，不得无限黑盒处理。通常是用户的Clash节点、系统代理/TUN模式等导致的。一般换Clash配置文件并退出TUN模式可以解决


## Git 规则

- 修改代码前，先检查 `git status`。
- 提交小而有用的检查点。提交频率应优先保证可回滚安全，而不是追求提交记录整洁。

- Release 打包应默认在 Windows 侧复用现有 `payload/` 重新打包；只有在确实需要重建 Linux 运行时包时，才使用 GitHub Actions、Docker、Linux 机器或 WSL。
- 替换 GitHub Release 资产时，固定使用 `docs/scripts/publish-github-release-asset.ps1 -Replace` 作为发布路径。不要手写不同形式的 `gh release upload` 命令；该脚本必须完成上传、校验大小/摘要，并在不匹配时明确失败。
- `.local-secrets/`、`.codegraph/`、`.codex/`、`dist/`、缓存和生成的依赖目录必须保持忽略状态。


## VM测试规则
- 对 Azure VM 或其他远程部署测试，不要静默运行长时间阻塞命令。如果某个 VM 步骤可能超过 60 秒，优先使用 `docs/scripts/azure-vm-run-job-and-deallocate.ps1`；它会启动/提交/轮询任务，并在 `finally` 中释放 VM。默认模式每 20 秒轮询小型 `status.json`，只每隔几轮拉取一次 stdout 尾部。根据 runner 日志，每 30-60 秒向用户报告一次进度。
- 每次 Azure VM 测试或远程执行会话结束后，除非用户明确要求保持运行，否则及时使用 `docs/scripts/azure-vm-deallocate.ps1` 停止/释放 VM。
- 永远不要提交本地秘密、凭据、Azure VM 密码、包含私密数据的诊断报告、`node_modules`、构建缓存或临时 VM 传输文件。
- 在 Release、VM 或远程 Windows 部署测试期间，不要在遇到第一个非阻塞问题时立刻停止并打补丁。先在相关验证文档中记录问题、证据、截图/日志路径和受影响步骤，然后继续完成剩余计划步骤。
- 每轮本地部署测试结束后，立即清理该轮测试的所有产物、包括下载的文件、测试产生的目录、打开chrome、WSL等App，或者其他相关服务/进程。

- 不要让浏览器标签页、文件管理器窗口堆积，一旦没用，立刻关闭，别占用多余系统资源

## 脚本编码规则

- 在编写或编辑脚本前，尤其是 Windows `.bat` / `.ps1` 文件，或任何会打印中文文本的脚本，先参考并遵守Obsidian当前仓库中的AI 写脚本前的编码规范提示词.md`


## 引用的记忆
- [2026-06-27 AGENTS.md 重读记忆](docs/memorys/2026-06-27-agents-reread.md)
- [2026-06-29 macOS 可视化部署工作流记忆](docs/memorys/2026-06-29-macos-visual-deployment-workflow.md)

## 用户手册与知识库
- 在这里读取和维护用户手册C:\Users\17239\Desktop\easy-miloco\docs
- 在这里读取和维护技术知识库C:\Users\17239\Desktop\easy-miloco\knowledge
