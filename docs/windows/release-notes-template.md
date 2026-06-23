# Windows 部署资料包版本说明

> 生成日期：2026-06-22
> 用途：说明 `easy-miloco-v0.1-windows.zip` 的版本口径、生成规则、校验方式和 hash 自引用处理规则。
> 关联：[Windows部署资料包发布清单](release-package.md)、[Windows部署资料包验收记录](validation-record.md)

## 当前版本口径

资料包名称：

```text
easy-miloco-v0.1-windows.zip
```

包外校验文件：

```text
easy-miloco-v0.1-windows.zip.sha256
```

当前 zip SHA256 不写在本页正文里，以避免本页进入 zip 后形成自引用。校验时以包外 `.zip.sha256` 文件和 [Windows部署资料包发布清单](release-package.md)、[Windows部署资料包验收记录](validation-record.md) 的包外记录为准。

## 包内文档规则

包内文档可以记录：

- 教程、Runbook、故障矩阵和验收清单。
- 包内文件数量。
- 包内 `SHA256SUMS.txt` 的校验结果。
- PowerShell / Bash 脚本语法烟测结果。

包内文档不应写死：

- `easy-miloco-v0.1-windows.zip` 自身 SHA256。
- 本次解压的临时目录 GUID。

原因：

- 写入 zip 自身 SHA 会改变 zip 内容，导致 hash 自引用。
- 临时解压目录每次不同，不是资料包稳定性证据。

## 当前包内组成

目录结构：

```text
easy-miloco-v0.1-windows/
├── README.md
├── SHA256SUMS.txt
├── docs/
└── scripts/
```

`docs/` 包含：

- Windows 部署总入口。
- Agent 一键部署教程。
- 人工手动部署教程。
- 独立分发版完整教程。
- 决策树、故障矩阵、覆盖审计。
- 后授权失败排障与交付审计。
- <windows-sample-host> 部署完成度审计。
- <windows-sample-host> 后授权收尾 Runbook。
- 满血验收证据清单、预检与验收清单、官方流程对齐核查。
- 资料包发布清单、验收记录和本版本说明。

`scripts/` 包含：

- `win-miloco-workflow.ps1`
- `windows-preflight.ps1`
- `wsl-miloco-validate.sh`
- `wsl-post-auth-finish.sh`
- `README.md`

## 校验顺序

1. 校验 zip 自身：

```powershell
Get-FileHash -Algorithm SHA256 .\easy-miloco-v0.1-windows.zip
Get-Content .\easy-miloco-v0.1-windows.zip.sha256
```

2. 解压 zip。
3. 校验包内 `SHA256SUMS.txt`。
4. 对 PowerShell 脚本做解析检查。
5. 对 Bash 脚本执行 `bash -n`。
6. 在目标 Windows 上运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\win-miloco-workflow.ps1 -Action Report
```

## 发布判断

只有同时满足以下条件，才把资料包视为可分发：

- zip SHA256 与 `.zip.sha256` 一致。
- 包内 `SHA256SUMS.txt` 全部通过。
- `win-miloco-workflow.ps1` 和 `windows-preflight.ps1` PowerShell 解析通过。
- `wsl-miloco-validate.sh` 和 `wsl-post-auth-finish.sh` `bash -n` 通过。
- 发布清单、验收记录和全局目录树已更新。

这只证明资料包可以分发，不证明 <windows-sample-host> 已经满血完成。<windows-sample-host> 满血仍以 [<windows-sample-host>部署完成度审计](windows-sample-host-readiness-audit.md) 和 [Windows满血验收证据清单](full-validation-evidence.md) 为准。
