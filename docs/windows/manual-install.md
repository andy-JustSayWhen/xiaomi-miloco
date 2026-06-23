# Windows 部署教程：人工手动版

Miloco 当前不支持 Windows 原生安装。Windows 电脑应在 WSL2 Ubuntu 内安装 Miloco，再用 OpenClaw Gateway 接入 Agent。

如果不确定自己处在哪一步，先看 [Windows部署决策树](decision-tree.md)；看到具体报错再查 [Windows部署故障排除矩阵](troubleshooting.md)。
第一次部署先看 [Windows部署总入口](index.md)。
官方流程核对见 [官方部署流程对齐核查](upstream-deploy-alignment.md)。
最终交付前按 [Windows满血验收证据清单](full-validation-evidence.md) 核对证据。

## 1. 准备 WSL

如果你已经拿到了本教程的 `scripts/` 文件夹，可以先用统一入口做自动检查：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action AllBasic -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

它不会替代下面的安装步骤，只会把 Windows 宿主预检和 WSL 验收一次跑完。没有安装 Miloco 前出现 Miloco/OpenClaw 端口不可达是正常现象。

如果要把状态发给别人排查，生成报告：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Report -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

在 Windows PowerShell 执行：

```powershell
wsl --install -d Ubuntu-24.04
wsl -l -v
```

如果正确命令仍提示 `--install` 不是有效参数，说明 Windows/WSL 组件较旧，先用管理员 PowerShell 启用组件：

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
wsl --set-default-version 2
```

重启 Windows 后，再安装 Ubuntu。不要把这一步和重复粘贴命令混淆；如果命令里出现两段 `wsl --install`，先修正粘贴错误。

如果显示 `ERROR_ALREADY_EXISTS`，说明发行版已存在，不要重复安装，直接进入：

```powershell
wsl -d Ubuntu-24.04
```

如果 `VERSION` 不是 `2`：

```powershell
wsl --set-version Ubuntu-24.04 2
```

## 2. 配置 WSL mirrored networking

编辑 Windows 用户目录下的：

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

管理员 PowerShell 检查 Hyper-V 防火墙：

```powershell
Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' |
  Select-Object Name,DefaultInboundAction
```

如果不是 `Allow`：

```powershell
Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
```

## 3. 设置网络代理

如果 GitHub/PyPI/NPM 访问慢或超时，在 WSL 中准备代理变量：

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

## 4. 安装 Miloco

推荐先下载脚本，便于重跑：

```bash
curl -LsSf -o /tmp/miloco-install.sh \
  https://github.com/<person-a>-JustSayWhen/easy-miloco/releases/latest/download/install.sh
```

执行 Agent prepare：

```bash
export PATH="$HOME/.local/bin:$PATH"
bash /tmp/miloco-install.sh --agent-prepare
```

如果下载依赖很久没有输出，不要马上中断，另开终端检查：

```bash
ps -ef | grep -E 'miloco|install|uv'
ss -tpn
du -sh ~/.cache/uv ~/.local/share/uv/tools/miloco
```

缓存持续增长通常表示仍在下载大型依赖。

## 5. 处理 1810 端口冲突

如果日志出现：

```text
error while attempting to bind on address ('127.0.0.1', 1810): address already in use
```

在 Windows PowerShell 查端口排除范围：

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
```

如果 `1810` 落在排除范围内，改 Miloco 端口，例如 `1886`：

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
```

验证：

```bash
miloco-cli service status
curl -fsS http://127.0.0.1:1886/health
```

## 6. 安装 OpenClaw

如果 WSL 内没有 Linux `node`，且不能 sudo，可以装到用户目录：

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

## 7. 完成 Miloco OpenClaw 插件安装

```bash
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$PATH"
bash /tmp/miloco-install.sh --agent-finish
openclaw gateway restart
```

如果此时已经拿到小米 OAuth payload 和 MiMo API Key，也可以按官方 agent finish 一次性传入：

```bash
bash /tmp/miloco-install.sh --agent-finish \
  --account-auth '<小米 OAuth payload>' \
  --omni-api-key '<MiMo API Key>'
```

没有这两项时，`--agent-finish` 会跳过账号和模型配置，只能得到基础服务和插件就绪。

验证插件：

```bash
openclaw plugins list
openclaw plugins inspect miloco-openclaw-plugin
openclaw plugins doctor
```

期望：

```text
Miloco enabled
Status: loaded
No plugin issues detected.
```

## 8. 配置账号和模型

如果使用脚本入口，先生成授权链接：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action BindUrl -Distro Ubuntu-24.04
```

拿到授权 payload 和 MiMo API Key 后：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Finish -AuthPayload '<小米 OAuth payload>' -MimoApiKey '<MiMo API Key>' -OmniModel '<Omni model>' -OmniBaseUrl '<Omni Base URL>' -Distro Ubuntu-24.04 -MilocoPort <miloco_port> -OpenClawPort 18789
```

手动命令如下。

绑定小米账号：

```bash
miloco-cli account bind --no-wait
miloco-cli account authorize <授权码>
```

配置 MiMo API Key：

```bash
miloco-cli config set model.omni.api_key <MiMo API Key> --no-restart
miloco-cli service restart
openclaw gateway restart
```

## 9. 最终验收

基础服务验收：

```bash
miloco-cli service status
curl -fsS http://127.0.0.1:<miloco_port>/health
miloco-cli doctor
openclaw gateway status
openclaw plugins inspect miloco-openclaw-plugin
```

满血能力验收：

```bash
miloco-cli account status          # data.is_bound=true
miloco-cli config get model.omni.api_key --value-only
miloco-cli device list             # 输出 did|device_name|room|category|online 表头后应有设备行
miloco-cli scope camera list --pretty
```

如果 `device list` 只有：

```text
# did|device_name|room|category|online
```

并且日志出现 `access token is empty`，说明小米账号未绑定，不要继续排查网络，先回到第 8 步完成账号授权。

如果日志出现“多模态大模型 API Key 未配置”，说明 MiMo / Omni API Key 还没写入，不要把它当成感知模型下载失败。

Windows 浏览器打开：

```text
http://127.0.0.1:<miloco_port>/
http://127.0.0.1:18789/
```

如果使用了 <windows-sample-host> 这类端口冲突机器，`<miloco_port>` 是 `1886`；无冲突时通常是默认 `1810`。
