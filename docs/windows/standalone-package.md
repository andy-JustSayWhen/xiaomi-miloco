# Xiaomi Miloco Windows 部署教程：独立分发版

> 版本日期：2026-06-22
> 适用对象：任意 Windows 电脑部署 Xiaomi Miloco。
> 核心原则：Miloco 当前不支持 Windows 原生安装，Windows 必须在 WSL2 Ubuntu 内安装和运行。

## 0. 你要准备什么

必需：

- Windows 10/11。
- WSL2 Ubuntu，推荐 `Ubuntu-24.04`。
- 小米账号，且该账号已接入米家设备。
- MiMo API Key，用于 `model.omni.api_key`。
- 可访问 GitHub、PyPI、Node/OpenClaw 下载源的网络。中国大陆网络建议显式代理，例如 `http://127.0.0.1:7897`。

建议：

- 如果要用摄像头实时流和持续感知，启用 WSL mirrored networking，并允许 Hyper-V 防火墙入站。
- 不要通过关闭 Clash Verge / TUN 解决下载问题；优先用 `http_proxy` / `https_proxy` / `all_proxy`。

## 1. 两条部署路径

### 路径 A：Agent 一键部署

适合有 Codex/Claude/OpenClaw Agent，并且 Agent 能 SSH 到目标 Windows。

给 Agent 的关键要求：

```text
1. 不在 Windows 原生安装 Miloco，只在 WSL 内安装。
2. 先检查 wsl -l -v、WSL2、.wslconfig mirrored networking、Hyper-V 防火墙。
3. 使用官方 installer 的 agent 流程：
   - install.sh --agent-prepare
   - 收集小米 OAuth payload 和 MiMo API Key
   - install.sh --agent-finish --account-auth ... --omni-api-key ...
4. 如果默认 1810 端口被 Windows excluded port range 占用，改未占用端口，例如 1886，并同步 server.url。
5. 安装并启动 OpenClaw Gateway，确认 miloco-openclaw-plugin loaded。
6. 最终必须验证 FULL_READY=yes；health ok 只代表基础服务正常。
```

如果已经拿到本资料包的 `scripts/` 文件夹，Agent 优先运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Report -Distro Ubuntu-24.04 -MilocoPort <miloco_port> -OpenClawPort 18789
```

收到小米 OAuth payload 和 MiMo API Key 后：

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Finish -AuthPayload '<小米 OAuth payload>' -MimoApiKey '<MiMo API Key>' -OmniModel '<Omni model>' -OmniBaseUrl '<Omni Base URL>' -Distro Ubuntu-24.04 -MilocoPort <miloco_port> -OpenClawPort 18789
```

### 路径 B：人工手动部署

适合没有 Agent，用户自己在 Windows 和 WSL 里执行命令。

从第 2 节开始逐步执行。

## 2. 准备 WSL2 Ubuntu

Windows PowerShell：

```powershell
wsl --install -d Ubuntu-24.04
wsl -l -v
```

如果显示 `ERROR_ALREADY_EXISTS`，说明已经安装过，不要重复安装：

```powershell
wsl -d Ubuntu-24.04
```

如果 `VERSION` 不是 `2`：

```powershell
wsl --set-version Ubuntu-24.04 2
```

如果正确的 `wsl --install -d Ubuntu-24.04` 仍提示 `--install` 无效，管理员 PowerShell：

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --set-default-version 2
```

重启 Windows 后再安装 Ubuntu。

## 3. 配置摄像头本地流网络

如果要使用摄像头实时画面和持续感知，在 Windows 用户目录创建或编辑：

```text
%USERPROFILE%\.wslconfig
```

写入：

```ini
[wsl2]
networkingMode=mirrored
```

重启 WSL：

```powershell
wsl --shutdown
```

管理员 PowerShell 放行 Hyper-V 入站：

```powershell
Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
```

## 4. 在 WSL 内准备网络代理

进入 WSL：

```powershell
wsl -d Ubuntu-24.04
```

如果 GitHub / PyPI / OpenClaw 慢或超时：

```bash
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export all_proxy=http://127.0.0.1:7897
```

测试：

```bash
curl -I https://github.com/
curl -I https://openclaw.ai/install-cli.sh
```

## 5. 官方 Miloco 安装

推荐先保存官方脚本，便于重跑：

```bash
curl -LsSf -o /tmp/miloco-install.sh \
  https://github.com/<person-a>-JustSayWhen/easy-miloco/releases/latest/download/install.sh
chmod +x /tmp/miloco-install.sh
export PATH="$HOME/.local/bin:$PATH"
```

先执行官方 prepare：

```bash
bash /tmp/miloco-install.sh --agent-prepare
```

如果 `uv tool install` 很久没有输出，不要重复启动安装。另开终端检查：

```bash
ps -ef | grep -E 'miloco|install|uv'
ss -tpn
du -sh ~/.cache/uv ~/.local/share/uv/tools/miloco
```

缓存增长通常表示仍在下载或解析依赖。

## 6. 处理 1810 端口冲突

如果 Miloco 日志出现：

```text
address already in use ('127.0.0.1', 1810)
```

Windows PowerShell 查端口保留：

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
```

如果 `1810` 落入保留范围，在 WSL 内改到未占用端口，例如 `1886`：

```bash
python3 - <<'PY'
import json
from pathlib import Path

path = Path.home() / ".openclaw" / "miloco" / "config.json"
data = json.loads(path.read_text(encoding="utf-8"))
server = data.setdefault("server", {})
server["port"] = 1886
server["url"] = "http://127.0.0.1:1886"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

miloco-cli service restart
curl -fsS http://127.0.0.1:1886/health
```

没有冲突时通常使用默认端口 `1810`。

## 7. 安装 OpenClaw Gateway

如果 WSL 内没有 Linux `node`，且不能使用 sudo，可安装到用户目录：

```bash
mkdir -p "$HOME/.local/bin" "$HOME/.local/opt"
curl -fL -o /tmp/node-v24.12.0-linux-x64.tar.xz \
  https://nodejs.org/dist/v24.12.0/node-v24.12.0-linux-x64.tar.xz
tar -xJf /tmp/node-v24.12.0-linux-x64.tar.xz -C "$HOME/.local/opt"
ln -sfn "$HOME/.local/opt/node-v24.12.0-linux-x64/bin/node" "$HOME/.local/bin/node"
ln -sfn "$HOME/.local/opt/node-v24.12.0-linux-x64/bin/npm" "$HOME/.local/bin/npm"
ln -sfn "$HOME/.local/opt/node-v24.12.0-linux-x64/bin/npx" "$HOME/.local/bin/npx"
export PATH="$HOME/.local/bin:$PATH"
```

安装 OpenClaw CLI：

```bash
curl -fsSL https://openclaw.ai/install-cli.sh -o /tmp/openclaw-install-cli.sh
bash /tmp/openclaw-install-cli.sh --prefix "$HOME/.openclaw"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$PATH"
```

安装并启动 Gateway：

```bash
openclaw gateway --dev --bind loopback --port 18789 install --port 18789
openclaw gateway start
openclaw gateway status
```

## 8. 完成 Miloco OpenClaw 插件安装

如果已经拿到小米 OAuth payload 和 MiMo API Key，按官方满血形式执行：

```bash
bash /tmp/miloco-install.sh --agent-finish \
  --account-auth '<小米 OAuth payload>' \
  --omni-api-key '<MiMo API Key>'
```

如果还没拿到账号和 Key，也可以先完成插件基础安装：

```bash
bash /tmp/miloco-install.sh --agent-finish
openclaw gateway restart
```

注意：不带账号和 Key 的 `--agent-finish` 只能得到基础服务和插件就绪，不能算满血。

## 9. 授权和模型配置

生成小米 OAuth 链接：

```bash
miloco-cli account bind --no-wait
```

用户打开链接登录，复制 OAuth payload / 授权码后：

```bash
miloco-cli account authorize '<小米 OAuth payload>'
```

配置 MiMo API Key：

```bash
miloco-cli config set \
  model.omni.model '<视觉模型>' \
  model.omni.base_url '<Omni Base URL>' \
  model.omni.api_key '<MiMo API Key>' \
  --no-restart

miloco-cli service restart
openclaw gateway restart
```

如果使用资料包脚本，推荐统一收尾：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Finish -AuthPayload '<小米 OAuth payload>' -MimoApiKey '<MiMo API Key>' -OmniModel '<Omni model>' -OmniBaseUrl '<Omni Base URL>' -Distro Ubuntu-24.04 -MilocoPort <miloco_port> -OpenClawPort 18789
```

## 10. 满血验收

基础服务：

```bash
miloco-cli service status
curl -fsS http://127.0.0.1:<miloco_port>/health
openclaw gateway status
openclaw plugins inspect miloco-openclaw-plugin
openclaw plugins doctor
```

满血能力：

```bash
miloco-cli account status
miloco-cli config get model.omni.api_key --value-only
miloco-cli device list
miloco-cli scope camera list --pretty
tail -n 100 ~/.openclaw/miloco/log/miloco-backend.log
```

必须同时满足：

- `account status` 显示 `is_bound=true`。
- `model.omni.api_key` 非空。
- `device list` 表头后有设备行。
- `scope camera list` 能列出摄像头。
- 需要感知的摄像头 `in_use=true`。
- 日志不再出现 `access token is empty` 或 `多模态大模型 API Key 未配置`。

使用脚本时，最终应看到：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
FULL_READY=yes
```

## 11. 常见误判

| 现象 | 真实含义 |
| --- | --- |
| `health={"status":"ok"}` | 只说明后端活着，不代表账号、Key、设备、摄像头完成 |
| OpenClaw `Connectivity probe: ok` | 只说明 Gateway 正常 |
| 插件 `Status: loaded` | 只说明插件加载了 |
| `FULL_READY=no` | 不要重装，先看账号、Key、设备、摄像头具体缺口 |
| `device list` 只有表头 | 常见原因是小米账号未绑定或 token 不可用 |
| 日志 `多模态大模型 API Key 未配置` | MiMo API Key 没写入，不是安装失败 |

## 12. <windows-sample-host> 示例状态

<windows-sample-host> 当前已经达到：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
```

仍未达到：

```text
FULL_READY=yes
```

原因：

- 小米账号 OAuth payload 未提供。
- MiMo API Key 未提供。

收到这两项后执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Finish -AuthPayload '<小米 OAuth payload>' -MimoApiKey '<MiMo API Key>' -OmniModel 'mimo-v2.5' -OmniBaseUrl 'https://token-plan-sgp.xiaomimimo.com/v1' -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```
