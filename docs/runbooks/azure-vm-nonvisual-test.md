# Azure VM Nonvisual Miloco Test Runbook

用途：让 Agent 快速连接 Azure Windows VM，非视觉化部署、验证、排障 easy-miloco，避免每次重新摸索 Run Command、用户上下文、WSL 的边界。

## 结论

- Azure `az vm run-command invoke` 是首选控制通道，适合查状态、传脚本、创建计划任务。
- Run Command 在 Windows VM 内以 `NT AUTHORITY\SYSTEM` 运行。SYSTEM 不能直接跑 WSL，会遇到 `WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED`。
- 需要跑 WSL / Miloco / OpenClaw 时，用 Run Command 创建一个以真实 Windows 用户运行的计划任务，再读回输出文件。
- 不要用 Run Command 扛长流程。任何可能超过 60 秒的部署、安装、卸载、验收任务，都必须先启动 VM 内后台 job，再轮询 `status.json` 和日志 tail。
- 轮询时每 30-60 秒向用户报告当前状态、最近日志和已耗时。不要让用户盯着空白等待。
- 每次 VM 测试或远程执行结束后，必须及时 deallocate VM，除非用户明确要求保留运行。
- 复杂命令不要塞进一行远程命令。优先上传脚本文件，再执行脚本。
- VM 输出可能被 Azure 截断。长日志要写到 `C:\easy-miloco-runcommand\...\output.txt`，再按需读取 tail 或关键段。

## 本地私密配置

不要把 VM 密码提交到仓库。推荐在本地创建：

```text
.local-secrets/azure-vm.env
```

内容示例：

```text
RESOURCE_GROUP=rg-name
VM_NAME=vm-name
VM_USER=azureuser
VM_PASSWORD=replace-with-local-password
```

`.local-secrets/` 必须保持 ignored。

## 第 0 步：登录 Azure

```powershell
az login
az account show
```

如果浏览器显示已经登录 Microsoft Azure Cross-platform Command Line Interface，可以关闭浏览器窗口，回到终端继续。

VM 不在运行态时先启动：

```powershell
$env:HTTPS_PROXY = 'http://127.0.0.1:7897'
$env:HTTP_PROXY = 'http://127.0.0.1:7897'
az vm start --resource-group <rg> --name <vm> --output none
```

GitHub 或 Azure 网络慢时，先走本机 Clash 7897 代理，不要干等。

## 第 1 层：Run Command 控制面

脚本：

```text
docs/scripts/azure-vm-run-command.ps1
```

烟测：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-run-command.ps1 `
  -CredentialFile .local-secrets\azure-vm.env `
  -Command 'hostname; whoami'
```

期望看到：

```text
<vm-hostname>
nt authority\system
```

如果返回 VM 必须 running，先 `az vm start`。

## 第 2 层：真实用户上下文

脚本：

```text
docs/scripts/azure-vm-user-powershell.ps1
```

用途：通过 Run Command 创建一次性计划任务，以 `VM_USER` 身份运行 PowerShell。用于 WSL、用户目录、Downloads、浏览器下载包等场景。

烟测：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-user-powershell.ps1 `
  -CredentialFile .local-secrets\azure-vm.env `
  -Command 'whoami; hostname; Get-Date -Format o' `
  -TimeoutSeconds 180
```

期望看到：

```text
<vm-hostname>\<vm-user>
<vm-hostname>
<timestamp>
```

## 第 3 层：WSL 脚本执行

脚本：

```text
docs/scripts/azure-vm-wsl-script.ps1
```

用途：把本地 `.sh` 传到 VM，再以真实 Windows 用户启动 WSL 执行。脚本会自动去掉 CRLF，避免 Windows 写入的 shell 脚本在 Linux 里坏掉。

建议先写一个本地临时脚本，不要把复杂 bash 放进 PowerShell 字符串：

```powershell
$tmp = Join-Path $env:TEMP 'miloco-wsl-smoke.sh'
@'
#!/usr/bin/env bash
set +e
whoami
echo "HOME=$HOME"
command -v miloco-cli || true
'@ | Set-Content -Encoding utf8 -LiteralPath $tmp

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-wsl-script.ps1 `
  -CredentialFile .local-secrets\azure-vm.env `
  -ScriptPath $tmp `
  -TimeoutSeconds 240
```

期望看到 WSL 用户、HOME 和 `miloco-cli` 路径。

## 长任务规则：后台 job + 轮询

超过 60 秒的任务不要用 `azure-vm-user-powershell.ps1` 阻塞等待。固定做法：

优先用统一入口，它会自动 start、提交 job、轮询，并在结束或报错时 deallocate VM：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-run-job-and-deallocate.ps1 `
  -CredentialFile .local-secrets\azure-vm.env `
  -JobName release-deploy-20260625 `
  -ScriptPath .local-secrets\vm-release-deploy-test.ps1
```

只有在需要调试底层机制时，才拆开使用下面三个脚本：

1. 用 `azure-vm-start-user-job.ps1` 启动 VM 内后台 job。
2. 记录返回的 `job`、`status`、`stdout` 路径。
3. 每 30-60 秒用 `azure-vm-job-status.ps1` 读取状态和日志 tail。
4. `state=completed` 且 `exit_code=0` 才算通过。
5. 结束后用 `azure-vm-deallocate.ps1` 关机释放。

示例：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-start-user-job.ps1 `
  -CredentialFile .local-secrets\azure-vm.env `
  -JobName release-prepare-20260625 `
  -ScriptPath .local-secrets\vm-release-prepare.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-job-status.ps1 `
  -CredentialFile .local-secrets\azure-vm.env `
  -JobName release-prepare-20260625 `
  -TailLines 120
```

如果上一步是部署测试，最后必须执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-deallocate.ps1 `
  -CredentialFile .local-secrets\azure-vm.env
```

经验教训：一次 19 秒的远端下载/解压/卸载动作，曾因为阻塞等待 Azure Run Command 回传而让用户等了 16 分钟。以后 Run Command 只做控制面启动/查询，不做长流程承载。

## 快速验证 Miloco

只跑 WSL 满血验收：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\azure-vm-wsl-script.ps1 `
  -CredentialFile .local-secrets\azure-vm.env `
  -ScriptPath .\docs\scripts\wsl-miloco-validate.sh `
  -TimeoutSeconds 600
```

通过口径：

```text
BASIC_READY=yes
FULL_READY=yes
FAIL_COUNT=0
EXIT_CODE=0
```

如果 `miloco.service_status` 显示 `STARTING`，新版 `wsl-miloco-validate.sh` 会等待 supervisor 进入 `RUNNING`。不要把短暂 `STARTING` 当成安装失败。

## 快速复跑后授权收尾

如果 VM 上已经有账号授权 payload、API Key、Base URL，可在 VM 内用用户上下文脚本读取本地输入日志，再跑 `win-miloco-workflow.ps1 -Action Finish`。注意不要把 API Key 打印出来。

推荐模式：

1. 用 `azure-vm-user-powershell.ps1` 下载当前 `main.zip` 或 release zip。
2. 解压后复制 `docs/scripts/win-miloco-workflow.ps1`、`wsl-post-auth-finish.sh`、`wsl-miloco-validate.sh` 到同一目录。
3. 从 VM 本地输入日志提取 API Key 和 Base URL，只打印 Key 长度。
4. 执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File <scripts-dir>\win-miloco-workflow.ps1 `
  -Action Finish `
  -Distro Ubuntu-24.04 `
  -MilocoPort 18860 `
  -OpenClawPort 18789 `
  -MimoApiKey <api-key> `
  -OmniModel mimo-v2.5 `
  -OmniBaseUrl <base-url> `
  -HomeId <home-id>
```

通过口径：

```text
Post-auth finish completed
WORKFLOW_LASTEXIT=0
BASIC_READY=yes
FULL_READY=yes
```

## 快速验证 Release 包

在 VM 用户上下文下载 GitHub Release：

```powershell
$url = 'https://github.com/andy-JustSayWhen/easy-miloco/releases/download/v0.2/easy-miloco-v0.2-windows.zip'
$work = 'C:\easy-miloco-runcommand\release-probe-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force -Path $work | Out-Null
$zip = Join-Path $work 'release.zip'
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $work 'release') -Force
Get-Item -LiteralPath $zip | Select-Object FullName,Length
```

然后检查包内脚本：

```powershell
$pkg = Get-ChildItem -LiteralPath (Join-Path $work 'release') -Directory |
  Where-Object { Test-Path (Join-Path $_.FullName 'install.ps1') } |
  Select-Object -First 1

$null = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $pkg.FullName 'install.ps1')))
```

完整 GUI 流程仍需要用户完成 OAuth 登录和 API Key 输入。非视觉自动化适合验证脚本、服务、收尾和验收，不适合替用户完成小米网页登录。

## 常见坑

| 现象 | 判断 | 处理 |
| --- | --- | --- |
| `WSL_E_LOCAL_SYSTEM_NOT_SUPPORTED` | 用 SYSTEM 直接跑了 WSL | 改用 `azure-vm-user-powershell.ps1` 或 `azure-vm-wsl-script.ps1` |
| Run Command 输出不完整 | Azure 输出截断 | 远端写文件，再读取 tail 或关键段 |
| bash 报引号 EOF | PowerShell/bash 双层引号坏了 | 上传脚本文件执行，不拼超长一行命令 |
| bash 找不到脚本但路径看似正确 | CRLF 混入 shell | 用 `tr -d "\015"` 或 `azure-vm-wsl-script.ps1` |
| `service status` 是 `STARTING` 但 health 后续 OK | supervisor startsecs 窗口 | 等待 10-30 秒再判定 |
| post-auth 中间出现 cannot connect，最后验证 OK | 重启后查询太早 | 以最终 `wsl-miloco-validate.sh` 为准；新版 post-auth 已加等待 |

## 发版替换后检查

替换 GitHub Release 资产后，立刻查资产大小和 digest：

```powershell
$env:HTTPS_PROXY = 'http://127.0.0.1:7897'
$env:HTTP_PROXY = 'http://127.0.0.1:7897'
gh release view v0.2 --repo andy-JustSayWhen/easy-miloco --json assets,tagName,url |
  ConvertFrom-Json |
  ConvertTo-Json -Depth 8
```

本轮成功口径示例：

```text
asset name=easy-miloco-v0.2-windows.zip
size=68482050
state=uploaded
```

GitHub Release 是唯一版本基准。替换后如需国内分发，再手动同步同名 zip 到网盘副本。
