# Miloco 一键部署总入口

本文件是给 Agent 读取的唯一总入口。README 里的一句话只指向这里；Agent 进入本文件后，必须先识别目标系统，再跳转到对应子指南，不要把 Windows、macOS、Linux/NAS 的步骤混在一起执行。

维护提醒：当前文档位于 `macOS` 开发分支，所以公开 raw URL 暂时指向 `macOS`。合并回 `main` 时，必须把 README、本文、`scripts/install-guide.md` 和 macOS 子指南里的 raw URL 统一改回 `main`。

## 给用户复制的一句话

```text
请为我一键部署 Miloco，按照：https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/macOS/docs/install-guide.md
```

## Agent 路由规则

先判断目标机器系统：

```text
Windows:  powershell.exe / cmd.exe 可用，Miloco 后端必须安装到 WSL2
macOS:    uname -s 返回 Darwin，Miloco 直接使用 darwin runtime，绝对不要使用 WSL
Linux/NAS: uname -s 返回 Linux，当前不走一键包，按官方 install.sh 和本仓库 NAS runbook 处理
```

然后只读对应子文档：

| 目标系统 | 子指南 | 入口类型 |
| --- | --- | --- |
| Windows | [windows/agent-install.md](windows/agent-install.md) | Windows + WSL2 Agent 自动部署 |
| macOS | [macos/agent-install.md](macos/agent-install.md) | macOS Agent 自动部署 |
| Linux/NAS | [runbooks/nas01-openclaw-miloco-install.md](runbooks/nas01-openclaw-miloco-install.md) | NAS/Linux 经验复盘，非一键包 |

## 通用原则

- 不要只看服务是否启动；最终必须区分 `BASIC_READY` 和 `FULL_READY`。
- 小米账号 OAuth 和 LLM API Key / Base URL 需要用户提供；Agent 负责生成链接、接收 payload、写入配置、验证连通性。
- 账号和模型配置按顺序处理：先小米账号，再模型配置。
- 下载低于 1MB/s 并持续约 60 秒时，停止当前下载，改让用户提供本地 release zip 路径或使用镜像/网盘副本。
- 遇到失败先读日志和诊断报告，不要盲目重装。
- 摄像头异常按“云端设备 -> LAN 可达 -> scope -> stream connected -> engine active_sources -> OpenClaw 视觉推理”分层定位。

## 交付最低标准

基础交付必须报告：

- Miloco 面板 URL。
- OpenClaw 聊天页 URL 或桌面入口。
- `BASIC_READY` / `FULL_READY`。
- 小米账号是否已绑定。
- 模型 Key、Base URL、模型名是否已配置。
- 设备列表是否有行。
- 摄像头 scope 是否可见。
- 关键日志路径。

满血交付还必须验证：

- Miloco 面板概述页能看到摄像头数量。
- OpenClaw 聊天页能自动登录。
- 在 OpenClaw 聊天中询问“家里有几个摄像头？画面如何？”，并记录回答是否能描述画面。

如果 `FULL_READY=no`，只能交付“基础安装完成，缺口如下”，不得宣称满血完成。
