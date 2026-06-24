# Windows 部署资料包版本说明

> 生成日期：2026-06-22
> 用途：说明 `easy-miloco-v0.1-windows.zip` 的版本口径和生成规则。
> 关联：[Windows部署资料包发布清单](release-package.md)、[Windows部署资料包验收记录](validation-record.md)

## 当前版本口径

资料包名称：

```text
easy-miloco-v0.1-windows.zip
```

GitHub Release 是唯一版本基准。夸克网盘只作为下载较慢时的人工同步副本。

## 包内文档规则

包内文档可以记录：

- 教程、Runbook、故障矩阵和验收清单。
- 包内文件数量。
- PowerShell / Bash 脚本语法烟测结果。

包内文档不应写死本次解压的临时目录 GUID；临时解压目录每次不同，不是资料包稳定性证据。

## 当前包内组成

目录结构：

```text
easy-miloco-v0.1-windows/
├── README.md
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

## 烟测顺序

1. 解压 zip。
2. 对 PowerShell 脚本做解析检查。
3. 对 Bash 脚本执行 `bash -n`。
4. 在目标 Windows 上运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\win-miloco-workflow.ps1 -Action Report
```

## 发布判断

只有同时满足以下条件，才把资料包视为可分发：

- `win-miloco-workflow.ps1` 和 `windows-preflight.ps1` PowerShell 解析通过。
- `wsl-miloco-validate.sh` 和 `wsl-post-auth-finish.sh` `bash -n` 通过。
- 发布清单、验收记录和全局目录树已更新。

这只证明资料包可以分发，不证明 <windows-sample-host> 已经满血完成。<windows-sample-host> 满血仍以 [<windows-sample-host>部署完成度审计](windows-sample-host-readiness-audit.md) 和 [Windows满血验收证据清单](full-validation-evidence.md) 为准。
