# Windows 部署预检与验收脚本

用途：把 Windows + WSL 部署 Miloco 时容易漏掉的检查项脚本化。脚本只做读取和探测，不会修改系统配置。

## 文件

- `windows-preflight.ps1`：在目标 Windows 上运行，检查 WSL、发行版、`.wslconfig`、Windows 端口保留、Hyper-V 防火墙、SSH、代理端口、Miloco/OpenClaw 本机 HTTP 可达性。
- `wsl-miloco-validate.sh`：在目标 WSL Ubuntu 内运行，检查 Miloco 服务、health、OpenClaw Gateway、OpenClaw 插件、小米账号绑定、MiMo/Omni API Key、设备列表和摄像头 scope。
- `wsl-post-auth-finish.sh`：拿到小米 OAuth payload 和 MiMo API Key 后，一次性完成账号授权、模型配置、服务重启、设备/摄像头检查和最终验收。
- `win-miloco-workflow.ps1`：Windows 统一入口，按 `-Action` 编排宿主预检、WSL 验收、生成授权链接和后授权收尾。

## 推荐统一入口

在目标 Windows PowerShell 中执行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action AllBasic -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789
```

常用动作：

```powershell
# 生成完整诊断报告，适合发给 Agent 或人工排查
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Report

# 只做 Windows 宿主预检
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Preflight

# 只做 WSL/Miloco/OpenClaw 验收
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Validate

# 生成小米账号绑定链接
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action BindUrl

# 收到授权 payload 和 MiMo Key 后一键收尾
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Finish -AuthPayload '<小米 OAuth payload>' -MimoApiKey '<MiMo API Key>' -OmniModel '<Omni model>' -OmniBaseUrl '<Omni Base URL>'
```

`OmniModel` / `OmniBaseUrl` 可省略，省略时使用官方默认 `xiaomi/mimo-v2.5` / `https://api.xiaomimimo.com/v1`。如果用户提供的 Base URL 在 `/v1/models` 中只列出 `mimo-v2.5`，则显式传 `-OmniModel mimo-v2.5`。

`-Action Report` 默认写到 Windows 临时目录，文件名形如 `miloco-deploy-report-YYYYMMDD-HHMMSS.txt`。可指定路径：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Report -ReportPath C:\Users\<user>\Desktop\miloco-report.txt
```

## Windows 侧运行

在目标 Windows PowerShell 中执行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\windows-preflight.ps1 -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789
```

需要机器可读输出时：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\windows-preflight.ps1 -Json
```

输出里的 `BASIC_READY_FROM_WINDOWS=yes` 只说明 Windows 本机能访问 Miloco 和 OpenClaw 端口，不代表小米账号、设备、摄像头、模型 Key 已完成。

## WSL 侧运行

在目标 WSL Ubuntu 内执行：

```bash
MILOCO_PORT=18860 OPENCLAW_PORT=18789 bash ./wsl-miloco-validate.sh
```

默认退出码规则：

- `0`：基础服务验收通过。即使账号或 API Key 还缺失，也会用 `FULL_READY=no` 表示。
- `2`：基础服务失败，例如 Miloco health、OpenClaw Gateway 或插件不可用。
- `3`：只有加 `--strict-full` 时才会出现，表示满血验收失败。

满血验收：

```bash
MILOCO_PORT=18860 OPENCLAW_PORT=18789 bash ./wsl-miloco-validate.sh --strict-full
```

## 后授权一键收尾

先生成新的小米账号绑定入口：

```bash
bash ./wsl-post-auth-finish.sh --print-bind-url
```

用户完成登录后，复制回调页面里的授权 payload，再执行：

```bash
MILOCO_AUTH_PAYLOAD='<小米 OAuth payload>' \
MIMO_API_KEY='<MiMo API Key>' \
bash ./wsl-post-auth-finish.sh
```

如果有多个家庭，指定目标家庭：

```bash
MILOCO_AUTH_PAYLOAD='<小米 OAuth payload>' \
MIMO_API_KEY='<MiMo API Key>' \
MILOCO_HOME_ID='<home_id>' \
bash ./wsl-post-auth-finish.sh
```

如果已经知道要启用的摄像头 did：

```bash
MILOCO_AUTH_PAYLOAD='<小米 OAuth payload>' \
MIMO_API_KEY='<MiMo API Key>' \
MILOCO_CAMERA_DIDS='<did1> <did2>' \
bash ./wsl-post-auth-finish.sh
```

脚本默认会调用 `wsl-miloco-validate.sh --strict-full`，因此账号、Key、设备、摄像头 scope 任一缺失都会以非 0 退出。只想先完成写入并看基础服务，可加 `--no-strict-full`。

## 远程 SSH 运行范式

把脚本传到目标 Windows 临时目录：

```powershell
scp .\win-miloco-workflow.ps1 .\windows-preflight.ps1 .\wsl-miloco-validate.sh .\wsl-post-auth-finish.sh <windows-user>@<target-ip>:C:/Users/<user>/AppData/Local/Temp/
```

推荐先跑统一入口：

```powershell
ssh <windows-user>@<target-ip> "powershell.exe -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action AllBasic -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789"
```

生成诊断报告：

```powershell
ssh <windows-user>@<target-ip> "powershell.exe -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Report -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789 -ReportPath C:\Users\<user>\AppData\Local\Temp\miloco-report.txt"
scp <windows-user>@<target-ip>:C:/Users/<user>/AppData/Local/Temp/miloco-report.txt .
```

运行 Windows 侧预检：

```powershell
ssh <windows-user>@<target-ip> "powershell.exe -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\windows-preflight.ps1 -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789"
```

运行 WSL 侧验收：

```powershell
ssh <windows-user>@<target-ip> "wsl.exe -d Ubuntu-24.04 -- bash /mnt/c/Users/<user>/AppData/Local/Temp/wsl-miloco-validate.sh"
```

生成授权入口：

```powershell
ssh <windows-user>@<target-ip> "powershell.exe -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action BindUrl -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789"
```

远程命令复杂时，优先上传脚本再执行，不要把大量 `&&`、管道、`$HOME` 变量直接塞进 Windows OpenSSH 的命令字符串。

## 判断口径

基础就绪：

- Miloco 后端 `/health` 返回 `{"status":"ok"}`。
- OpenClaw Gateway running 且 HTTP 可达。
- `miloco-openclaw-plugin` 已加载。

满血就绪：

- `miloco-cli account status` 显示 `is_bound=true`。
- `model.omni.api_key` 非空。
- `miloco-cli device list` 能列出设备。
- `miloco-cli scope camera list --pretty` 能列出摄像头 scope，并按需要 enable 目标摄像头。
