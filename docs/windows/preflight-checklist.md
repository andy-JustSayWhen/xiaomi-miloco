# Windows 部署预检与验收清单

用途：在 Windows + WSL 部署 Miloco 前后，快速判断环境是否适合“满血运行”。

## 0. 官方前提

官方说明的关键约束：

- Windows 原生不支持，必须在 WSL 内安装。
- 推荐 WSL2。
- 摄像头本地流需要 WSL mirrored networking 和 Hyper-V 防火墙入站放行。
- 满血使用需要小米账号和多模态大模型 API Key，默认推荐小米 MiMo。
- Agent 安装官方流程是 `--agent-prepare` → 询问账号/模型 → `--agent-finish --account-auth ... --omni-api-key ...`。缺账号或 Key 时只能基础就绪。

## 0.1 自动化脚本入口

脚本说明：[Windows 部署预检与验收脚本](../scripts/README.md)

推荐统一入口：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action AllBasic -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

Windows 侧预检：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\windows-preflight.ps1 -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

WSL 侧验收：

```bash
MILOCO_PORT=1886 OPENCLAW_PORT=18789 bash ./wsl-miloco-validate.sh
```

后授权一键收尾：

```bash
bash ./wsl-post-auth-finish.sh --print-bind-url
MILOCO_AUTH_PAYLOAD='<小米 OAuth payload>' MIMO_API_KEY='<MiMo API Key>' bash ./wsl-post-auth-finish.sh
```

输出口径：

- `BASIC_READY_FROM_WINDOWS=yes`：Windows 宿主可访问 Miloco/OpenClaw 本机端口。
- `BASIC_READY=yes`：WSL 内 Miloco/OpenClaw/插件基础链路通过。
- `FULL_READY=yes`：小米账号、MiMo/Omni API Key、设备列表、摄像头 scope 都通过。

## 1. Windows 侧预检

```powershell
wsl -l -v
```

通过标准：

- 存在目标发行版，例如 `Ubuntu-24.04`。
- `VERSION` 为 `2`。

如果发行版已存在，不要再次 `wsl --install`；直接进入：

```powershell
wsl -d Ubuntu-24.04
```

如果没有发行版：

```powershell
wsl --install -d Ubuntu-24.04
```

如果正确命令仍提示 `--install` 无效，使用管理员 PowerShell 启用旧系统组件：

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --set-default-version 2
```

重启 Windows 后再安装 Ubuntu。

检查端口保留：

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
```

判断：

- 如果 `1810` 不在任何范围内，Miloco 默认端口通常可用。
- 如果 `1810` 落入 excluded range，提前规划备用端口，例如 `1886`。

检查 Hyper-V 防火墙：

```powershell
Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' |
  Select-Object Name,DefaultInboundAction
```

通过标准：

```text
DefaultInboundAction = Allow
```

修复：

```powershell
Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
```

## 2. WSL 网络预检

Windows `%USERPROFILE%\.wslconfig`：

```ini
[wsl2]
networkingMode=mirrored
```

重启：

```powershell
wsl --shutdown
```

WSL 内确认：

```bash
cat /etc/os-release
uname -m
curl -I https://github.com/
curl -I https://openclaw.ai/install-cli.sh
```

如果直连 GitHub 超时，设置代理：

```bash
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export all_proxy=http://127.0.0.1:7897
```

不要关闭 Clash Verge TUN；优先用显式代理环境变量解决下载问题。

## 3. 安装中观察项

Miloco 官方 prepare：

```bash
curl -LsSf https://github.com/andy-JustSayWhen/easy-miloco/releases/latest/download/install.sh | bash -s -- --agent-prepare
```

长时间无输出时，不要重复启动安装。另开终端查：

```bash
ps -ef | grep -E 'miloco|install|uv'
ss -tpn
du -sh ~/.cache/uv ~/.local/share/uv/tools/miloco
```

判断：

- `~/.cache/uv` 持续增长：仍在下载/解析依赖。
- `miloco-cli` 已落盘：可进入服务验证。
- 缓存长时间不动且没有网络连接：再排查代理或 PyPI 连接。

## 4. 基础安装验收

```bash
miloco-cli service status
curl -fsS http://127.0.0.1:<miloco_port>/health
openclaw gateway status
openclaw plugins inspect miloco-openclaw-plugin
openclaw plugins doctor
```

通过标准：

- Miloco `running=true`。
- health 返回 `{"status":"ok"}`。
- OpenClaw gateway `Runtime: running`，`Connectivity probe: ok`。
- `miloco-openclaw-plugin` 为 `Status: loaded`。
- `openclaw plugins doctor` 无插件问题。

Windows 侧也要测：

```powershell
curl.exe -fsS http://127.0.0.1:<miloco_port>/health
curl.exe -I http://127.0.0.1:18789/
```

## 5. 满血能力验收

账号：

```bash
miloco-cli account status
```

通过标准：

```json
{"is_bound": true}
```

模型：

```bash
miloco-cli config get model.omni.api_key --value-only
```

通过标准：

- 有非空 API Key。
- `miloco-cli config show` 中 `model.omni.model` 和 `base_url` 合理。

设备：

```bash
miloco-cli device list
```

通过标准：

- TSV 表头后有设备行。

摄像头：

```bash
miloco-cli scope camera list --pretty
```

通过标准：

- 能列出可管理摄像头。
- 需要感知的摄像头已 enable。

日志：

```bash
tail -n 100 ~/.openclaw/miloco/log/miloco-backend.log
```

不能出现的关键缺口：

```text
access token is empty
多模态大模型 API Key 未配置
```

## 6. 满血失败快速判定

| 现象 | 判定 | 下一步 |
| --- | --- | --- |
| `device list` 只有表头 | 小米账号未绑定或 token 不可用 | `miloco-cli account bind --no-wait` 后 `authorize` |
| `scope camera list` 空 | 账号未绑定、无摄像头、或摄像头不在可访问家庭 | 先验证账号和 `device list` |
| 日志 `API Key 未配置` | MiMo/Omni key 为空 | `miloco-cli config set model.omni.api_key ...` |
| `1810` bind 失败 | Windows 端口保留或占用 | 改 `server.port/server.url` |
| `doctor` 查不到 Hyper-V 防火墙 | WSL 内无法调用 Windows PowerShell 或权限不足 | Windows 管理员 PowerShell 手动查 |

## 7. WIN-home01 当前基线

本次实测基线：

- Miloco：`http://127.0.0.1:1886/`
- OpenClaw：`http://127.0.0.1:18789/`
- `1810` 不可用原因：Windows excluded port range 包含 `1786-1885`
- 当前状态：小米账号已绑定，MiMo API Key 已配置，设备和摄像头感知已通过
- 脚本化验收：Windows 侧 `BASIC_READY_FROM_WINDOWS=yes`，WSL 侧 `BASIC_READY=yes`、`FULL_READY=yes`
- 最终报告：`reports/WIN-home01-20260622-102255-full-ready.txt`
