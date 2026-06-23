# <windows-sample-host> 后授权收尾 Runbook

用途：当用户提供“小米 OAuth 授权码”和“MiMo API Key”后，按本 runbook 把 <windows-sample-host> 从“基础服务就绪”推进到“满血部署完成”。

## 当前基线

- Windows SSH 部署用户：`<windows-user>@<tailscale-ip>`
- WSL distro：`Ubuntu-24.04`
- WSL 用户：`<wsl-user>`
- Miloco URL：`http://127.0.0.1:1886/`
- Miloco health：`http://127.0.0.1:1886/health`
- OpenClaw Gateway：`http://127.0.0.1:18789/`
- Miloco home：`/home/<wsl-user>/.openclaw/miloco`
- OpenClaw home：`/home/<wsl-user>/.openclaw`

当前缺口：

- `miloco-cli account status` 返回 `is_bound=false`。
- `model.omni.api_key` 为空。
- `device list` 只有表头；日志中出现 `access token is empty`。

## 用户需要提供

1. 小米 OAuth 授权码：来自 `miloco-cli account bind --no-wait` 输出的登录链接。
2. MiMo API Key：用于 `model.omni.api_key`。
3. <windows-sample-host> 当前 MiMo endpoint：`https://token-plan-sgp.xiaomimimo.com/v1`。
4. <windows-sample-host> 当前视觉模型：`mimo-v2.5`。不要把 `model.omni.model` 配成 `mimo-v2.5-pro`，该模型不支持视觉。

如果授权链接过期，重新生成：

```bash
miloco-cli account bind --no-wait
```

本次已通过脚本生成的最新授权链接：

```text
<XIAOMI_OAUTH_URL>
```

## 优先路径：脚本一键收尾

脚本位置：

- 本地 OB：`02-deploy/scripts/wsl-post-auth-finish.sh`
- <windows-sample-host> 临时目录：`C:\Users\<user>\AppData\Local\Temp\wsl-post-auth-finish.sh`

2026-06-22 04:46 已核对 <windows-sample-host> 临时目录脚本与 OB 当前版本一致：

```text
2CD059D8C9C984B9E28FD6E1CB974E413CCEA9B1B02903925E27D03D608C42AD  win-miloco-workflow.ps1
57A7C8682A92DE25DB015C3A09449BA75B32342A96EA197ED31CE217374B75CD  windows-preflight.ps1
0427CEB37ACB32800140A8D2C342F6C54F112CF00772F22786662D509584A4EC  wsl-miloco-validate.sh
E96640EBE9E9579FB13D6014FB3AB571B4B95F098A75DAD5036AF64984E0A83F  wsl-post-auth-finish.sh
```

同轮远端 `win-miloco-workflow.ps1 -Action Validate` 返回：

```text
BASIC_READY=yes
FULL_READY=no
FAIL_COUNT=0
```

重新生成授权链接：

```powershell
$ssh='C:\Program Files\OpenSSH\ssh.exe'
& $ssh -i 'C:\Users\<user>\.ssh\id_ed25519' '<windows-user>@<tailscale-ip>' `
  'wsl.exe -d Ubuntu-24.04 -- bash /mnt/c/Users/<user>/AppData/Local/Temp/wsl-post-auth-finish.sh --print-bind-url'
```

收到授权 payload 和 MiMo API Key 后执行：

```powershell
$ssh='C:\Program Files\OpenSSH\ssh.exe'
& $ssh -i 'C:\Users\<user>\.ssh\id_ed25519' '<windows-user>@<tailscale-ip>' `
  'wsl.exe -d Ubuntu-24.04 -- env MILOCO_AUTH_PAYLOAD="<小米 OAuth payload>" MIMO_API_KEY="<MiMo API Key>" OMNI_MODEL="mimo-v2.5" OMNI_BASE_URL="https://token-plan-sgp.xiaomimimo.com/v1" bash /mnt/c/Users/<user>/AppData/Local/Temp/wsl-post-auth-finish.sh'
```

如果需要指定家庭或摄像头：

```powershell
$ssh='C:\Program Files\OpenSSH\ssh.exe'
& $ssh -i 'C:\Users\<user>\.ssh\id_ed25519' '<windows-user>@<tailscale-ip>' `
  'wsl.exe -d Ubuntu-24.04 -- env MILOCO_AUTH_PAYLOAD="<小米 OAuth payload>" MIMO_API_KEY="<MiMo API Key>" OMNI_MODEL="mimo-v2.5" OMNI_BASE_URL="https://token-plan-sgp.xiaomimimo.com/v1" MILOCO_HOME_ID="<home_id>" MILOCO_CAMERA_DIDS="<did1> <did2>" bash /mnt/c/Users/<user>/AppData/Local/Temp/wsl-post-auth-finish.sh'
```

脚本动作：

- 授权小米账号。
- 一次性写入 `model.omni.model`、`model.omni.base_url`、`model.omni.api_key`。
- 重启 Miloco backend 和 OpenClaw Gateway。
- 输出家庭、设备、摄像头列表。
- 调用 `wsl-miloco-validate.sh --strict-full` 做满血验收。

下面的手动步骤用于脚本失败时兜底排障。若 `Finish` 已执行但没有得到 `FULL_READY=yes`，先看 [Windows后授权失败排障与交付审计](post-auth-troubleshooting.md) 按层级判断停在账号、模型、设备、摄像头还是 OpenClaw。

## 执行前复核

```powershell
$ssh='C:\Program Files\OpenSSH\ssh.exe'
& $ssh -i 'C:\Users\<user>\.ssh\id_ed25519' '<windows-user>@<tailscale-ip>' `
  'wsl.exe -d Ubuntu-24.04 -- env PATH=/home/<wsl-user>/.openclaw/bin:/home/<wsl-user>/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin miloco-cli service status'
```

WSL 内应返回：

```json
{"running": true, "server": {"url": "http://127.0.0.1:1886"}}
```

如果未运行：

```bash
miloco-cli service restart
```

## 1. 绑定小米账号

```bash
miloco-cli account authorize '<授权码>'
```

推荐带 `--pretty` 便于人工检查：

```bash
miloco-cli account authorize --pretty '<授权码>'
```

验证：

```bash
miloco-cli account status
```

通过标准：

```json
{"data": {"is_bound": true}}
```

如果失败：

- 重新执行 `miloco-cli account bind --no-wait` 获取新链接。
- 用户重新登录复制授权码。
- 确认服务仍在运行：`miloco-cli service status`。

## 2. 写入 MiMo API Key

默认配置：

- `model.omni.model = mimo-v2.5`
- `model.omni.base_url = https://token-plan-sgp.xiaomimimo.com/v1`

一次性写入：

```bash
miloco-cli config set \
  model.omni.model mimo-v2.5 \
  model.omni.base_url https://token-plan-sgp.xiaomimimo.com/v1 \
  model.omni.api_key '<MiMo API Key>' \
  --no-restart
```

验证：

```bash
miloco-cli config get model.omni.model --value-only
miloco-cli config get model.omni.base_url --value-only
miloco-cli config get model.omni.api_key --value-only
```

通过标准：

- model 是 `mimo-v2.5`。
- base_url 是 `https://token-plan-sgp.xiaomimimo.com/v1`。
- api_key 非空。

## 3. 重启 Miloco 和 OpenClaw

```bash
miloco-cli service restart
openclaw gateway restart
```

验证基础服务：

```bash
miloco-cli service status
curl -fsS http://127.0.0.1:1886/health
openclaw gateway status
openclaw plugins inspect miloco-openclaw-plugin
openclaw plugins doctor
```

通过标准：

- Miloco `running=true`。
- health 返回 `{"status":"ok"}`。
- OpenClaw `Connectivity probe: ok`。
- 插件 `Status: loaded`。
- 插件 doctor 无问题。

## 4. 刷新并检查米家设备

先看家庭：

```bash
miloco-cli scope home list --pretty
```

如果存在多个家庭，选择目标家庭：

```bash
miloco-cli scope home switch --pretty '<home_id>'
```

查看设备：

```bash
miloco-cli device list
```

通过标准：

- 输出 `# did|device_name|room|category|online` 表头后有设备行。

如果仍只有表头：

```bash
tail -n 120 ~/.openclaw/miloco/log/miloco-backend.log
```

重点看：

- 是否仍有 `access token is empty`。
- 是否账号已过期或授权失败。
- 是否选择了错误 home。

## 5. 检查摄像头感知范围

```bash
miloco-cli scope camera list --pretty
```

字段含义：

- `in_use`：是否已接入 Miloco 感知。
- `is_online`：米家设备在线。
- `connected`：视频流已连接。

开启摄像头感知：

```bash
miloco-cli scope camera enable --pretty '<did1>' '<did2>'
```

最多开启数量以 `miloco-cli account status` 的 `max_enabled_cameras` 为准。<windows-sample-host> 当前返回为 `4`。

## 6. 满血验收

```bash
miloco-cli account status
miloco-cli config get model.omni.api_key --value-only
miloco-cli device list
miloco-cli scope camera list --pretty
tail -n 100 ~/.openclaw/miloco/log/miloco-backend.log
```

满血通过标准：

- `account.status` 显示 `is_bound=true`。
- `model.omni.api_key` 非空。
- `device list` 有设备行。
- `scope camera list` 能列出摄像头；需要感知的摄像头 `in_use=true`。
- 日志中不再出现：

```text
access token is empty
多模态大模型 API Key 未配置
```

## 7. OB 回写

完成后更新：

- [<windows-sample-host>部署实录](windows-sample-host-log.md)
- [Windows部署预检与验收清单](preflight-checklist.md)
- `E:\BaiduSyncdisk\obsidian repo\default\常用SSH信息\<windows-sample-host>\README.md`
- `E:\BaiduSyncdisk\obsidian repo\default\常用SSH信息\<windows-sample-host>\connection.yaml`

至少记录：

- 绑定账号是否成功。
- API Key 是否写入成功。
- 当前 home、设备数量、摄像头数量。
- 开启了哪些摄像头 did。
- 最终健康检查输出。
