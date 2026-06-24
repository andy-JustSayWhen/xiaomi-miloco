# Windows 部署资料包发布清单

> 生成日期：2026-06-22
> 用途：把 Windows 部署教程、脚本和验收材料作为一套可分发资料包交给其他玩家或 Agent。
> 关联：[Windows部署总入口](index.md)、[Windows部署教程-Agent一键版](agent-install.md)、[Windows部署教程-人工手动版](manual-install.md)、[Windows 部署预检与验收脚本](../scripts/README.md)

## 资料包内容

### 必读入口

| 文件 | 用途 |
| --- | --- |
| [Windows部署总入口](index.md) | 第一次部署从这里开始，选择 Agent 或人工路径 |
| [Windows部署教程-Agent一键版](agent-install.md) | 给 Agent/SSH 接管时使用 |
| [Windows部署教程-人工手动版](manual-install.md) | 普通用户手动执行时使用 |
| [Windows部署教程-独立分发版](standalone-package.md) | 脱离 Obsidian 也能阅读的一页式完整教程 |
| [Windows部署决策树](decision-tree.md) | 不确定下一步时按状态分支走 |
| [Windows部署故障排除矩阵](troubleshooting.md) | 已经看到报错时查根因和修复 |
| [Windows部署教程覆盖审计](tutorial-coverage-audit.md) | 发布前确认主要 Windows 场景是否已覆盖 |
| [Windows后授权失败排障与交付审计](post-auth-troubleshooting.md) | 后授权 `Finish` 没跑满时分层排障，最终交付前审计证据 |
| [<windows-sample-host>部署完成度审计](windows-sample-host-readiness-audit.md) | <windows-sample-host> 当前完成项、满血证据和踩坑闭环 |
| [Windows部署资料包版本说明](release-notes-template.md) | 资料包版本口径、生成规则和 hash 自引用处理 |

### 脚本目录

路径：

```text
02-deploy/scripts/
```

| 文件 | 用途 |
| --- | --- |
| `README.md` | 脚本使用说明 |
| `win-miloco-workflow.ps1` | Windows 统一入口，编排预检、验收、授权链接和收尾 |
| `windows-preflight.ps1` | Windows 侧 WSL、端口、防火墙、代理、HTTP 预检 |
| `wsl-miloco-validate.sh` | WSL 内 Miloco/OpenClaw/账号/模型/设备验收 |
| `wsl-post-auth-finish.sh` | 收到 OAuth payload 和 MiMo Key 后一键收尾 |

## 脚本校验

校验时间：2026-06-22 10:22

验收记录：[Windows部署资料包验收记录](validation-record.md)

语法检查：

```text
PASS windows-preflight.ps1
PASS win-miloco-workflow.ps1
PASS wsl-miloco-validate.sh
PASS wsl-post-auth-finish.sh
```

SHA256：

```text
57A7C8682A92DE25DB015C3A09449BA75B32342A96EA197ED31CE217374B75CD  windows-preflight.ps1
491F198F0AAC57851A53FCF5CF63648593A6B91FF1913F11D13B11A48598A02F  win-miloco-workflow.ps1
6D29E3E7ED1E7A394801EA82678A630132767EC5416033EC86BBEEC3D7354FB4  wsl-miloco-validate.sh
E96640EBE9E9579FB13D6014FB3AB571B4B95F098A75DAD5036AF64984E0A83F  wsl-post-auth-finish.sh
```

复核命令：

```powershell
# PowerShell 语法检查
$files = @('.\windows-preflight.ps1', '.\win-miloco-workflow.ps1')
foreach ($f in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { $errors } else { "PASS $f" }
}

# bash 语法检查
wsl.exe -- bash -n /mnt/c/path/to/wsl-miloco-validate.sh
wsl.exe -- bash -n /mnt/c/path/to/wsl-post-auth-finish.sh
```

## 复制到目标 Windows

已生成可分发压缩包：

```text
packages/easy-miloco-v0.1-windows.zip
packages/easy-miloco-v0.1-windows.zip.sha256
```

zip SHA256：

```text
见包外 easy-miloco-v0.1-windows.zip.sha256
```

说明：包外 OB 发布清单记录 zip 自身 SHA256。包内的本清单副本不写死 zip 自身 SHA256，以避免资料包自引用导致每次写入哈希都会改变 zip 哈希。

包内结构：

```text
easy-miloco-v0.1-windows/
├── README.md
├── SHA256SUMS.txt
├── docs/
│   ├── Windows部署教程-独立分发版.md
│   ├── Windows部署总入口.md
│   ├── Windows部署教程-Agent一键版.md
│   ├── Windows部署教程-人工手动版.md
│   ├── Windows部署决策树.md
│   ├── Windows部署故障排除矩阵.md
│   ├── Windows部署教程覆盖审计.md
│   ├── Windows部署资料包发布清单.md
│   ├── Windows部署资料包验收记录.md
│   ├── Windows部署资料包版本说明.md
│   ├── Windows后授权失败排障与交付审计.md
│   ├── <windows-sample-host>部署完成度审计.md
│   ├── <windows-sample-host>后授权收尾Runbook.md
│   ├── Windows部署预检与验收清单.md
│   ├── Windows满血验收证据清单.md
│   └── 官方部署流程对齐核查.md
└── scripts/
    ├── README.md
    ├── win-miloco-workflow.ps1
    ├── windows-preflight.ps1
    ├── wsl-miloco-validate.sh
    └── wsl-post-auth-finish.sh
```

包内计数：

```text
DOC_COUNT=16
SCRIPT_COUNT=5
FILE_COUNT=23
SHA_TOTAL=22
SHA_FAIL=0
```

远程 Windows OpenSSH 建议写法：

```powershell
scp .\win-miloco-workflow.ps1 .\windows-preflight.ps1 .\wsl-miloco-validate.sh .\wsl-post-auth-finish.sh <windows-user>@<target-ip>:C:/Users/<user>/AppData/Local/Temp/
```

不要写成：

```powershell
<windows-user>@<target-ip>:/C:/Users/<user>/AppData/Local/Temp/
```

后者在 Windows OpenSSH 场景下容易造成路径解释混乱。

## 目标机快速验证

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Report -Distro Ubuntu-24.04 -MilocoPort <miloco_port> -OpenClawPort 18789
```

基础通过标准：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
```

满血通过标准：

```text
FULL_READY=yes
```

如果 `FULL_READY=no`，先看输出中具体缺口。账号、Key、设备或摄像头缺失时不要重装。

## 资料包交付口径

可以对用户说：

```text
这套 Windows 部署资料分为 Agent 一键版和人工手动版。先从 Windows部署总入口开始；如果已经拿到 scripts 文件夹，先运行 win-miloco-workflow.ps1 -Action Report 生成诊断报告。基础服务通过不等于满血，最终必须看到 FULL_READY=yes。
```

## <windows-sample-host> 当前状态

最新报告：

```text
reports/windows-sample-host-20260622-102255-full-ready.txt
```

关键状态：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
FULL_READY=yes
```

满血证据：

- 小米账号 `is_bound=true`。
- 设备列表 127 行。
- 摄像头 `<camera-did-desk> / <camera-desk>` 在线、`in_use=true`、`connected=true`。
- MiMo/Omni 使用 `mimo-v2.5` + `https://token-plan-sgp.xiaomimimo.com/v1`。

后续维护复核：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Validate -Distro Ubuntu-24.04 -MilocoPort 18860 -OpenClawPort 18789
```
