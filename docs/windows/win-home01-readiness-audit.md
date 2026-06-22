# WIN-home01 部署完成度审计

> 审计日期：2026-06-22 04:45，最新复核：2026-06-22 10:22
> 用途：按原目标逐项审计 WIN-home01 当前 Miloco 部署、教程资料包和剩余缺口；避免把“基础服务就绪”误判为“满血完成”。
> 关联：[WIN-home01部署实录](win-home01-log.md)、[Windows满血验收证据清单](full-validation-evidence.md)、[Windows后授权失败排障与交付审计](post-auth-troubleshooting.md)

## 结论

WIN-home01 已达到“Miloco 满血部署完成”。

最终证据：

- `BASIC_READY=yes`
- `FULL_READY=yes`
- `PASS_COUNT=16`
- `WARN_COUNT=0`
- `FAIL_COUNT=0`
- 小米账号 `is_bound=true`
- 设备列表 127 行
- 摄像头 `<camera-did-desk> / 主卧 电脑桌上` 在线、`in_use=true`、`connected=true`
- MiMo 视觉模型 `mimo-v2.5` 调用 `https://token-plan-sgp.xiaomimimo.com/v1/chat/completions` 返回 200，并产生 `realtime_perceive` 画面描述

## 目标要求审计

| 要求 | 当前证据 | 结论 |
| --- | --- | --- |
| 按官方说明部署 Miloco | 已对齐官方 installer 主线；官方 `--agent-finish --account-auth --omni-api-key` 已纳入教程和后授权脚本；后授权收尾已实机闭环 | 已完成 |
| 远程接管 WIN-home01 | SSH `<windows-user>@<tailscale-ip>` 可用；WSL distro `Ubuntu-24.04` 属于正确 Windows 用户 | 已完成 |
| Miloco 后端运行 | `miloco-cli service status` 返回 `running=true`，`server.url=http://127.0.0.1:1886` | 已完成 |
| Windows/WSL health | health 返回 `{"status":"ok"}`；报告中 `BASIC_READY_FROM_WINDOWS=yes`、`BASIC_READY=yes` | 已完成 |
| OpenClaw Gateway | `openclaw gateway status` 显示 `Connectivity probe: ok` | 已完成 |
| Miloco OpenClaw 插件 | `openclaw plugins inspect miloco-openclaw-plugin` 显示 `Status: loaded` | 已完成 |
| 小米账号绑定 | `miloco-cli account status` 返回 `is_bound=true`，uid `250115363`，nickname `mdidb` | 已完成 |
| MiMo/Omni API Key | `miloco.omni_api_key=PASS configured`；`model.omni.model=mimo-v2.5`；`model.omni.base_url=https://token-plan-sgp.xiaomimimo.com/v1` | 已完成 |
| 设备列表 | `miloco-cli device list` 返回 127 行设备 | 已完成 |
| 摄像头 scope 和感知 | `scope camera list` 返回 `<camera-did-desk> / 主卧 电脑桌上`，`in_use=true`，`connected=true`；日志有 `realtime_perceive` 成功输出 | 已完成 |
| 任意 Windows 用户教程 | 已形成 Agent 一键版、人工手动版、决策树、故障矩阵、后授权失败排障、满血证据清单，并用 WIN-home01 后授权实测闭环修正验证脚本 | 已完成 |
| 资料包可分发 | zip SHA256、包内 SHA、脚本语法烟测均通过 | 已完成 |

## 当前证据

WIN-home01 远程复核：

```text
report=reports/WIN-home01-20260622-102255-full-ready.txt
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
FULL_READY=yes
PreflightExitCode=0
ValidateExitCode=0
miloco.running=true
server.url=http://127.0.0.1:1886
account.is_bound=true
max_enabled_cameras=4
model.omni.model=mimo-v2.5
model.omni.base_url=https://token-plan-sgp.xiaomimimo.com/v1
model.omni.api_key=configured
device_rows=127
camera.did=<camera-did-desk>
camera.name=主卧 电脑桌上
camera.in_use=true
camera.connected=true
```

资料包验收：

```text
zip SHA256=见 [Windows部署资料包发布清单](release-package.md) 和 [Windows部署资料包验收记录](validation-record.md)
SHA_TOTAL=22
SHA_FAIL=0
DOC_COUNT=16
SCRIPT_COUNT=5
PS_PARSE_PASS windows-preflight.ps1
PS_PARSE_PASS win-miloco-workflow.ps1
BASH_PARSE_PASS wsl-miloco-validate.sh
BASH_PARSE_PASS wsl-post-auth-finish.sh
```

最终满血报告：

```text
reports/WIN-home01-20260622-102255-full-ready.txt
```

## 满血完成判定

后授权完成后，必须能同时证明：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
FULL_READY=yes
```

并满足：

- `miloco-cli account status` 显示 `is_bound=true`。
- `miloco-cli config get model.omni.api_key --value-only` 非空。
- `miloco-cli device list` 表头后有设备行。
- `miloco-cli scope camera list --pretty` 能列出目标摄像头。
- 需要感知的摄像头 `in_use=true`。
- 后端日志不再新出现 `access token is empty` 和 `多模态大模型 API Key 未配置`。

## 后续维护口径

同类 Windows 机器收到用户提供的 OAuth payload / 授权码后，优先执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Finish -AuthPayload '<小米 OAuth payload>' -MimoApiKey '<MiMo API Key>' -OmniModel 'mimo-v2.5' -OmniBaseUrl 'https://token-plan-sgp.xiaomimimo.com/v1' -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

如果 `Finish` 第一次没有得到 `FULL_READY=yes`，不要重装。先等待 Miloco 重启完成，再按 [Windows后授权失败排障与交付审计](post-auth-troubleshooting.md) 分层排查。
