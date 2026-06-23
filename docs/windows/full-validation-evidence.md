# Windows 满血验收证据清单

用途：部署交付时逐项确认哪些证据已经证明“满血完成”。本页不替代 [Windows部署总入口](index.md) 和 [Windows部署预检与验收清单](preflight-checklist.md)，只定义交付证据标准。

## 0. 结论分级

| 结论 | 必须满足 | 不能缺 |
| --- | --- | --- |
| 基础服务就绪 | Windows 可访问 Miloco/OpenClaw；WSL 内 Miloco/OpenClaw/插件通过 | 账号、Key、设备、摄像头可以暂缺 |
| 满血就绪 | 基础服务就绪 + 小米账号绑定 + MiMo/Omni Key + 设备列表 + 摄像头 scope | 任一缺失都不能叫满血 |
| 不可交付 | Miloco health 不通、OpenClaw 插件未 loaded、服务无法从 Windows 访问 | 先修基础链路 |

## 1. 推荐证据包

先生成报告：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Report -Distro Ubuntu-24.04 -MilocoPort <miloco_port> -OpenClawPort 18789 -ReportPath C:\Users\<user>\Desktop\miloco-report.txt
```

完整交付至少附：

- `miloco-report.txt`
- `miloco-cli account status`
- `miloco-cli device list`
- `miloco-cli scope camera list --pretty`
- 最后 100 行后端日志：`tail -n 100 ~/.openclaw/miloco/log/miloco-backend.log`

## 2. 基础服务证据

### Windows 宿主

报告中必须有：

```text
BASIC_READY_FROM_WINDOWS=yes
[PASS] windows.miloco_health
[PASS] windows.openclaw_gateway
FAIL_COUNT=0
```

含义：

- Windows 宿主能访问 Miloco health。
- Windows 宿主能访问 OpenClaw Dashboard。
- 端口、WSL、代理、防火墙没有基础失败项。

### WSL 内部

报告中必须有：

```text
[PASS] cmd.miloco-cli
[PASS] cmd.openclaw
[PASS] miloco.service_status
[PASS] miloco.health
[PASS] openclaw.gateway_status
[PASS] openclaw.miloco_plugin
BASIC_READY=yes
FAIL_COUNT=0
```

含义：

- Miloco CLI 和 OpenClaw CLI 都在正确 WSL 用户 PATH 中。
- Miloco backend running。
- OpenClaw Gateway running。
- `miloco-openclaw-plugin` 已加载。

## 3. 满血证据

### 小米账号

命令：

```bash
miloco-cli account status
```

必须证明：

```text
is_bound=true
```

不能接受：

```text
is_bound=false
```

### MiMo / Omni API Key

命令：

```bash
miloco-cli config get model.omni.api_key --value-only
miloco-cli config get model.omni.model --value-only
miloco-cli config get model.omni.base_url --value-only
```

必须证明：

- `model.omni.api_key` 非空。
- `model.omni.model` 是预期视觉模型，例如官方默认 `xiaomi/mimo-v2.5`，或某些 endpoint `/v1/models` 返回的 `mimo-v2.5`。
- `model.omni.base_url` 是预期地址，例如官方默认 `https://api.xiaomimimo.com/v1`，或用户提供的兼容 OpenAI `/v1` endpoint。

不能接受：

```text
empty
null
```

### 设备列表

命令：

```bash
miloco-cli device list
```

必须证明：

- 输出不只有表头。
- 至少有一行设备。

不能接受：

```text
# did|device_name|room|category|online
```

如果只有表头，优先查账号绑定、token、home 选择，而不是重装。

### 摄像头 scope

命令：

```bash
miloco-cli scope camera list --pretty
```

必须证明：

- 能列出目标摄像头。
- 需要感知的摄像头 `in_use=true`。
- 摄像头在线状态和连接状态符合本次部署目标。

不能接受：

```json
{"code":0,"message":"ok","data":[]}
```

如果为空，先确认设备列表、home、摄像头在线和 LAN/mirrored networking。

### 后端日志

命令：

```bash
tail -n 100 ~/.openclaw/miloco/log/miloco-backend.log
```

不能出现：

```text
access token is empty
多模态大模型 API Key 未配置
```

出现上述日志时，说明账号或 Key 仍未完成，不能判定满血。

## 4. 假阳性输出

以下输出只能证明基础链路，不等于满血：

```text
{"status":"ok"}
Runtime: running
Connectivity probe: ok
Status: loaded
BASIC_READY=yes
BASIC_READY_FROM_WINDOWS=yes
```

以下输出直接证明未满血：

```text
FULL_READY=no
is_bound=false
model.omni_api_key empty
device list 只有表头
camera data=[]
access token is empty
多模态大模型 API Key 未配置
```

## 5. 交付模板

```markdown
## Miloco Windows 部署验收

- Windows 宿主：BASIC_READY_FROM_WINDOWS=<yes/no>
- WSL 基础服务：BASIC_READY=<yes/no>
- 满血状态：FULL_READY=<yes/no>
- Miloco URL：
- OpenClaw URL：
- 小米账号：is_bound=<true/false>
- MiMo/Omni Key：<configured/empty>
- 设备数量：
- 摄像头数量：
- 已启用摄像头 did：
- 关键日志缺口：<none/access token/API Key/camera>
- 报告文件：
```

## 6. <windows-sample-host> 当前证据

当前报告：

```text
reports/windows-sample-host-20260622-102255-full-ready.txt
```

已证明：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
FULL_READY=yes
PreflightExitCode=0
ValidateExitCode=0
PASS_COUNT=16
WARN_COUNT=0
FAIL_COUNT=0
```

满血证据：

```text
miloco.account is_bound=true
miloco.omni_api_key configured
miloco.devices 127 device row(s)
miloco.cameras <camera-did-desk> / <camera-desk> / in_use=true / connected=true
miloco.logs_known_gaps No recent known-gap strings found in active Miloco logs
```

结论：

- <windows-sample-host> 可以交付为“Miloco Windows 满血部署完成”。
- 首次 `Finish` 后如果遇到短暂 `supervisor_state=STARTING`，先等待并复核，不要重装。
