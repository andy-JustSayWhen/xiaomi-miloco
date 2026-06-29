# Windows 部署资料包版本说明

> 更新日期：2026-06-29
> 用途：说明当前 Windows release 包的版本口径和生成规则。
> 关联：[Windows部署资料包发布清单](release-package.md)

## 当前版本口径

资料包名称：

```text
easy-miloco-v0.5-windows.zip
```

GitHub Release 是唯一版本基准。夸克网盘只作为下载较慢时的人工同步副本。

## 包内文档规则

包内文档可以记录：

- 教程、runbook、故障矩阵和验收清单。
- 包内目录结构。
- PowerShell / Bash 脚本语法烟测结果。
- 本机或 VM 部署验收结论。

包内文档不应写死本次解压的临时目录 GUID；临时解压目录每次不同，不是资料包稳定性证据。

## 当前包内组成

```text
easy-miloco-v0.5-windows.zip
├── README.md
├── install.bat
├── install.ps1
├── manifest.json
├── release-notes.md
├── docs/
├── payload/
└── scripts/windows/
```

## 烟测顺序

1. 解压 zip。
2. 确认解压根目录第一层存在 `install.bat`。
3. 对 PowerShell 脚本做解析检查。
4. 对 Bash 脚本执行 `bash -n`。
5. 至少完成一次本机非视觉安装测试和一次用户视角视觉安装测试。

## 发布判断

只有同时满足以下条件，才把资料包视为可分发：

- `install.bat` 双击入口位于解压根目录。
- `install.ps1` 和 workflow 脚本 PowerShell 解析通过。
- `wsl-miloco-validate.sh` 和 `wsl-post-auth-finish.sh` `bash -n` 通过。
- 本机 release 包部署测试通过，且测试后完成卸载复核。
- 发布清单、验收记录和 README 目录树已更新。
