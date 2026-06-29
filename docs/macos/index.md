# macOS 部署入口

macOS 直接使用 darwin runtime，不走 WSL。

## 入口

- Agent 一键部署：[agent-install.md](agent-install.md)
- Agent 一句话提示：[agent-prompt.md](agent-prompt.md)
- 懒人包打包脚本：[../../macos/build-release.sh](../../macos/build-release.sh)
- 包内预检脚本：[../scripts/macos-preflight.sh](../scripts/macos-preflight.sh)
- 包内验收脚本：[../scripts/macos-miloco-validate.sh](../scripts/macos-miloco-validate.sh)
- 后授权收尾脚本：[../scripts/macos-post-auth-finish.sh](../scripts/macos-post-auth-finish.sh)

## 维护原则

- 同时支持 Agent 一句话部署和用户双击 `install.command` 交互式部署。
- 公开 docs 只保留当前使用指南；验证原始日志和用户环境记录放到本机私有位置。
