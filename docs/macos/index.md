# macOS 部署总入口

当前状态：已有 macOS 一键包源码、双击入口、Agent 部署子指南和验证记录。

从这里开始：

- [macOS 部署教程：Agent 一键版](agent-install.md)
- [macOS 适配 Spec](macos-adaptation-spec.md)
- [macOS Agent 一句话部署提示词](agent-prompt.md)
- [macOS 懒人包验证记录](validation-record.md)
- 懒人包打包脚本：[../../macos/build-release.sh](../../macos/build-release.sh)
- 包内脚本：[../scripts/macos-preflight.sh](../scripts/macos-preflight.sh)、[../scripts/macos-miloco-validate.sh](../scripts/macos-miloco-validate.sh)、[../scripts/macos-post-auth-finish.sh](../scripts/macos-post-auth-finish.sh)

维护原则：

- macOS 直接使用 darwin runtime，不走 WSL。
- macOS 必须同时支持两种入口：Agent 一句话部署、懒人双击脚本后交互式部署。
- 第一版优先做 zip + `install.command`，暂不做 `.app` / DMG。
- 每次改 macOS 安装、打包、验收脚本后，同步更新本目录文档和验证记录。
- Agent 入口统一从 [../install-guide.md](../install-guide.md) 路由进来，不要让 README 直接指向 macOS 子文档。
