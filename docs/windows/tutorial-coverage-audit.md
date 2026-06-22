# Windows 部署教程覆盖审计

> 审计日期：2026-06-22
> 目的：确认 [Windows部署教程-Agent一键版](agent-install.md) 和 [Windows部署教程-人工手动版](manual-install.md) 是否覆盖“任意 Windows 电脑”部署 Miloco 时的主要状态分支。
> 结论：教程已覆盖基础部署、常见 Windows/WSL 差异、网络/代理、OpenClaw、后授权和满血验收；WIN-home01 已用用户提供的小米 OAuth payload 和 MiMo Key 完成满血闭环。

## 覆盖矩阵

| 场景 | Agent 一键版 | 人工手动版 | 辅助文档 | 当前状态 |
| --- | --- | --- | --- | --- |
| 没有 WSL | “没有 WSL 时”给出 `wsl --install` 和 DISM 兜底 | 第 1 节给出 `wsl --install` 和 DISM 兜底 | [Windows部署决策树](decision-tree.md)、[Windows部署故障排除矩阵](troubleshooting.md) | 已覆盖 |
| 已有同名 Ubuntu | 自动识别 `ERROR_ALREADY_EXISTS`，不重复安装 | 提示直接 `wsl -d Ubuntu-24.04` | [Windows部署故障排除矩阵](troubleshooting.md) | 已覆盖 |
| WSL1 | 要求检查 `wsl -l -v` 并转换 WSL2 | 给出 `wsl --set-version` | [Windows部署决策树](decision-tree.md) | 已覆盖 |
| SSH 用户看不到 distro | 输入清单明确 WSL 属于 Windows 用户 | 故障矩阵解释用户归属 | [Windows部署故障排除矩阵](troubleshooting.md) | 已覆盖 |
| 摄像头本地流 | 要求 mirrored networking + Hyper-V 入站 Allow | 第 2 节写 `.wslconfig` 和防火墙 | [Windows部署预检与验收清单](preflight-checklist.md) | 已覆盖 |
| 中国大陆网络慢 | 要求不关 TUN，使用显式代理变量 | 第 3 节写 `http_proxy` 等变量 | [Windows部署故障排除矩阵](troubleshooting.md) | 已覆盖 |
| `uv` 长下载 | 自动修复策略要求看 `ps`/`ss`/`du` | 第 4 节同样给出观察命令 | [Windows部署决策树](decision-tree.md) | 已覆盖 |
| 1810 端口冲突 | 自动改未占用端口并同步 `server.url` | 第 5 节给出 JSON 改法 | [Windows部署故障排除矩阵](troubleshooting.md) | 已覆盖 |
| WSL 无 Linux Node | 自动用户目录安装 Node | 第 6 节给出 Node tarball 方案 | [Windows部署故障排除矩阵](troubleshooting.md) | 已覆盖 |
| OpenClaw gateway 缺失 | 安装 CLI/Gateway 并验证插件 loaded | 第 6/7 节手动安装和验证 | [Windows部署决策树](decision-tree.md) | 已覆盖 |
| 官方 Agent 三步 | 写明 `--agent-prepare`、收集账号/Key、`--agent-finish --account-auth ... --omni-api-key ...` | 第 7/8 节区分带参/不带参 finish | [官方部署流程对齐核查](upstream-deploy-alignment.md) | 已覆盖 |
| 小米 OAuth 未提供 | 标记只能基础就绪，等待用户 | 第 8/9 节回到授权 | [WIN-home01授权阶段用户操作卡片](win-home01-auth-card.md) | 已覆盖，但依赖用户 |
| MiMo API Key 未提供 | 标记只能基础就绪，等待用户 | 第 8/9 节回到模型配置 | [WIN-home01授权阶段用户操作卡片](win-home01-auth-card.md) | 已覆盖，但依赖用户 |
| 多家庭/多摄像头 | Finish 支持 `HomeId` / `CameraDids` | 手动版提示 home/camera 命令 | [WIN-home01后授权收尾Runbook](win-home01-post-auth-runbook.md) | 已覆盖 |
| 生成报告交付排障 | `-Action Report` | 第 1 节和总入口提示报告 | [scripts/README](../scripts/README.md) | 已覆盖 |
| 满血验收 | 要求账号、Key、设备、摄像头、日志同时通过 | 第 9 节同样要求 | [Windows满血验收证据清单](full-validation-evidence.md) | 已覆盖 |

## 交付边界

以下情况不能被教程或 Agent 自动绕过：

- 小米 OAuth 必须用户登录并复制 payload。
- MiMo API Key 必须用户从平台获取。
- 多家庭、多摄像头时，用户可能需要选择目标 home 和摄像头 did。
- 摄像头本地流需要目标 Windows/WSL 与摄像头所在局域网实际可达；异地部署只能控制云端设备，不能默认承担本地摄像头持续感知。

## WIN-home01 当前审计结论

WIN-home01 已覆盖并通过：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
FULL_READY=yes
PreflightExitCode=0
ValidateExitCode=0
```

WIN-home01 满血证据：

```text
account.is_bound=true
model.omni.model=mimo-v2.5
model.omni.base_url=https://token-plan-sgp.xiaomimimo.com/v1
device_rows=127
camera.did=<camera-did-desk>
camera.in_use=true
camera.connected=true
WARN_COUNT=0
FAIL_COUNT=0
```

当前不是教程缺口；后授权实测暴露出的验证脚本假阴性已经修正：大设备列表超时放宽到 45 秒，历史 Key 缺失日志不再计入当前 warning。

## 维护规则

- 如果新增一个 Windows 实机坑位，先判断它属于“新场景”还是已有矩阵中的具体例子。
- 新场景必须同时更新本页、[Windows部署决策树](decision-tree.md)、[Windows部署故障排除矩阵](troubleshooting.md)，必要时更新 Agent/人工教程。
- 如果只是 WIN-home01 的特例，优先追加到 [WIN-home01部署实录](win-home01-log.md)，不要直接写成通用步骤。
