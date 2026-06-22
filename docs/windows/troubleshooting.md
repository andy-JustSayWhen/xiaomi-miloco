# Windows 部署故障排除矩阵

用途：Windows + WSL 部署 Miloco 时，按现象快速定位根因和修复动作。

## 1. WSL 安装和用户归属

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| `Wsl/E_INVALIDARG` | 查看原始命令 | 常见于复制时把两段 `wsl --install` 粘在一起 | 只执行一次 `wsl --install -d Ubuntu-24.04` | `wsl -l -v` 能列出发行版 |
| 正确命令仍提示 `--install` 无效 | `wsl.exe --help` | Windows/WSL 组件较旧，不支持新安装参数 | 管理员 PowerShell 用 DISM 启用 WSL 与 VirtualMachinePlatform，设置默认 WSL2，重启后再安装 Ubuntu | `wsl -l -v` 可用且发行版 VERSION=2 |
| `ERROR_ALREADY_EXISTS` | `wsl -l -v` | 发行版已存在 | 不重复安装，直接 `wsl -d Ubuntu-24.04` | 能进入 Ubuntu shell |
| SSH 到管理员账号看不到 WSL distro | `wsl -l -v` 分别在不同 Windows 用户下执行 | WSL 发行版属于另一个 Windows 用户 | 使用拥有 distro 的 Windows 用户做部署；管理员账号只做防火墙/系统设置 | `wsl.exe -d Ubuntu-24.04 -- whoami` 返回目标 Linux 用户 |
| `sudo: a password is required` | `sudo -n true` | WSL 用户不是免密 sudo | 避免 apt 路径，优先用户目录安装 Node/工具；确需系统设置时让用户输入 sudo 密码 | 用户目录命令可运行 |

## 2. 网络、代理和下载

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| GitHub 443 超时 | `curl -I https://github.com/` | 中国大陆网络或 DNS/代理未走通 | 显式设置 `http_proxy/https_proxy/all_proxy=http://127.0.0.1:7897` | `curl -I https://github.com/` 返回 HTTP 响应 |
| OpenClaw 脚本打不开 | `curl -I https://openclaw.ai/install-cli.sh` | 代理/DNS 问题 | 同上；不要关闭 Clash Verge TUN | `HTTP/2 200` 或 `HTTP/1.1 200` |
| `uv tool install` 长时间无输出 | `ps -ef`, `ss -tpn`, `du -sh ~/.cache/uv` | 正在下载大型依赖，或网络卡住 | 缓存增长就继续等；缓存不动再排查代理 | `miloco-cli` 最终出现在 `~/.local/bin` |
| NPM/OpenClaw 安装慢 | `npm config get proxy`, `curl -I registry.npmjs.org` | npm 下载走直连 | 使用代理环境变量；必要时用户目录安装 Node，避免系统 apt | `openclaw --version` 可用 |

## 3. Windows 端口和 WSL mirrored

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| Miloco 后端反复重启 | `tail -n 100 ~/.openclaw/miloco/log/miloco-backend.log` | 后端 bind 失败 | 看具体错误 | `miloco-cli service status` running |
| `address already in use ('127.0.0.1', 1810)` | Windows: `netsh interface ipv4 show excludedportrange protocol=tcp` | 默认 `1810` 落入 Windows excluded port range 或被进程占用 | 改 `~/.openclaw/miloco/config.json` 的 `server.port` 和 `server.url`，例如 `1886` | `curl http://127.0.0.1:1886/health` 返回 ok |
| Windows 浏览器打不开 WSL 服务 | Windows: `curl.exe -fsS http://127.0.0.1:<port>/health` | mirrored/端口/服务状态问题 | 先确认 WSL 内 health，再确认 Windows 侧端口 | Windows 侧 `curl.exe` 成功 |
| 摄像头实时流打不开 | `miloco-cli doctor` | WSL NAT 或 Hyper-V 防火墙入站阻断 | `.wslconfig` 设置 `networkingMode=mirrored`，Hyper-V 防火墙 DefaultInboundAction=Allow | `doctor` WSL 网络通过，Windows 管理员确认 Allow |

## 4. Miloco 服务和配置

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| `miloco-cli` 找不到 | `which miloco-cli` | `~/.local/bin` 未进 PATH 或安装未完成 | `export PATH="$HOME/.local/bin:$PATH"`；必要时重跑 installer | `miloco-cli --help` 可用 |
| `service status` running=false | `miloco-cli service logs` | 后端启动失败 | 先看日志，不盲目重装 | `service status` running=true |
| health 不通 | `curl -v http://127.0.0.1:<port>/health` | 端口错、服务未启动、配置 url 不一致 | 查 `miloco-cli config show` 中 `server.url` | health 返回 `{"status":"ok"}` |
| `doctor` 提示 iptables 权限不足 | `sudo -n true` | 普通用户无权限读取 iptables | 作为 warning 记录；不等同于失败 | 其它网络项通过 |

## 5. OpenClaw 和插件

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| `openclaw` 找不到 | `which openclaw` | OpenClaw CLI 未安装或 PATH 未包含 `~/.openclaw/bin` | 安装 OpenClaw CLI，`export PATH="$HOME/.openclaw/bin:$PATH"` | `openclaw --version` |
| Gateway 未运行 | `openclaw gateway status` | systemd user service 未安装/未启动 | `openclaw gateway --dev --bind loopback --port 18789 install --port 18789`; `openclaw gateway start` | `Connectivity probe: ok` |
| 插件未加载 | `openclaw plugins inspect miloco-openclaw-plugin` | `--agent-finish` 未完成或 gateway 未重启 | 重跑 `bash /tmp/miloco-install.sh --agent-finish`，再 `openclaw gateway restart` | `Status: loaded` |
| 插件 doctor 有问题 | `openclaw plugins doctor` | 插件配置/注册不完整 | 按 doctor 输出修复；必要时重装插件 | `No plugin issues detected` |

## 6. 小米账号、设备和摄像头

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| `account status` is_bound=false | `miloco-cli account status` | 未完成 OAuth 授权 | `miloco-cli account bind --no-wait`，用户登录后 `account authorize <授权码>` | `is_bound=true` |
| 授权码失败 | `miloco-cli account authorize --pretty <payload>` | 授权码过期、复制不完整、服务未运行 | 重新生成链接；确认服务 running | `account status` 变 true |
| `device list` 只有表头 | `miloco-cli device list`; 后端日志 | access token 为空或 home 未选 | 先绑定账号；再 `scope home list/switch` | TSV 表头后有设备行 |
| `scope camera list` 空 | `miloco-cli scope camera list --pretty` | 账号未绑定、无摄像头、home 错误、摄像头不在线 | 先设备列表，再 home，再摄像头列表 | 摄像头列表出现 did |
| 需要开启摄像头感知 | `miloco-cli scope camera list --pretty` | 摄像头 `in_use=false` | `miloco-cli scope camera enable --pretty <did...>` | 目标 did `in_use=true` |


## 6.5 摄像头专项快速分流

摄像头问题不要只看 WebUI 或单个 `is_online` 字段，优先按 [摄像头问题快速定位与修复Runbook](camera-runbook.md) 的六层模型定位：米家云端设备 → LAN 可达 → Miloco scope → 视频流连接 → 感知引擎 → OpenClaw 视觉推理。

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| 米家在线但 Miloco 显示离线 | `/api/miot/home` 对比 `/api/miot/scope/cameras`，再 `ping -I <iface> <camera_ip>` | `lan_online` 滞后或 SDK 状态未刷新 | 让云端在线摄像头进入 tentative stream 重连，并给失败订阅加退避；不要仅凭 `lan_online=false` 过滤 | 目标 did `connected=true` 且进入 active_sources |
| OpenClaw 能看画面但 WebUI 仍离线 | `/api/perception/devices`、`/api/perception/engine/status` | UI/在线口径弱于真实 stream 状态 | 以 `connected` 和 active_sources 修正在线口径，再刷新 UI | API、WebUI、OpenClaw 三方一致 |
| 左上角 `Nodes: <camera> failed` | `/api/monitor/nodes`、后端日志 | 旧节点失败未清理、流订阅失败或音频解码失败 | 先确认 video stream；若 audio G711A 解码风暴，默认禁用 audio stream | 无持续 failed，OpenClaw 逐个 did 能描述画面 |
| 三台摄像头只接入两台 | scope list + engine active_sources 逐个 did 对比 | 单台未启用、LAN 状态滞后、流订阅失败 | 逐 did 查 `is_online/in_use/connected/active_sources`，不要用总数判断 | 所有目标 did 全部通过 |
## 7. MiMo / Omni 模型

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| 日志“多模态大模型 API Key 未配置” | `tail -n 100 ~/.openclaw/miloco/log/miloco-backend.log` | `model.omni.api_key` 为空 | `miloco-cli config set model.omni.api_key <key> --no-restart`; `miloco-cli service restart` | 日志不再出现该缺口 |
| 模型配置错误 | `miloco-cli config show` | model/base_url/key 填错 | 一次性写入 `model.omni.model`、`model.omni.base_url`、`model.omni.api_key` | config show 正确 |
| 感知仍不可用 | 后端日志、面板模型页 | API Key 无效或服务端返回错误 | 换正确 Key，确认 MiMo 平台可用额度 | 感知请求不再报认证错误 |

## 8. SSH 和远程执行

| 现象 | 定位命令 | 根因 | 修复 | 验收 |
| --- | --- | --- | --- | --- |
| WSL 命令里的 `&&`/管道被 Windows 解析 | 看错误如 `'ls' 不是内部或外部命令` | Windows OpenSSH 默认 shell 先解析 | 简单命令直接 `wsl.exe -- cmd`；复杂脚本上传后 `bash script.sh` | Linux 命令在 WSL 内执行 |
| `$HOME` 被当字面字符串 | 看到路径 `$HOME/.local/...` | 多层引号转义错误 | 上传 bash 脚本或在 WSL 内生成脚本 | 路径为 `/home/<user>/...` |
| bash 脚本首行异常 | `﻿#!/usr/bin/env` | PowerShell 写入 BOM/CRLF | 用无 BOM/LF 写脚本，或 WSL 内生成 | 脚本正常执行 |

## 9. 何时不要继续重装

以下情况不要立刻重装：

- `uv` 还在下载且缓存增长。
- Miloco 基础服务 running，但账号/模型缺失。
- `device list` 空但 `account.is_bound=false`。
- `doctor` 只有 iptables 权限 warning。

先按矩阵定位根因；重装只用于安装产物损坏、版本不一致或官方 installer 明确失败的场景。

## 10. 后授权 Finish 失败时

收到小米 OAuth payload 和 MiMo API Key 后，如果 `win-miloco-workflow.ps1 -Action Finish` 或 `wsl-post-auth-finish.sh` 没有直接得到 `FULL_READY=yes`，不要把它合并成“安装失败”。按 [Windows后授权失败排障与交付审计](post-auth-troubleshooting.md) 分层判断：

- 基础服务层：Miloco health、OpenClaw Gateway、插件状态。
- 账号层：`account.is_bound=true`。
- 模型层：`model.omni.api_key` 非空且服务重启后日志不再报 Key 缺失。
- 设备层：`device list` 有设备行。
- 摄像头层：`scope camera list` 有目标摄像头且需要感知的摄像头 `in_use=true`。

只有这些都通过，才算满血交付。
