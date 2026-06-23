# Make Release Package Runbook

用途：维护者专用。当仓库维护者说“制作更新包”“打包更新吧”“发一个新版本”时，Agent 按本 runbook 执行。普通部署用户没有资格更新本仓库或发布 release，不应使用本 runbook。

## 目标

根据当前仓库代码生成新的 release 更新包，并完成：

- 构建
- 自测
- SHA256
- release notes
- 发布清单
- 夸克网盘副本同步提醒

## 前置检查

1. 读取 [../AGENT.md](../AGENT.md)。
2. 检查 git 状态，识别已有未提交改动。
3. 确认目标版本号。如果用户没有给版本号，先从当前计划版本 `v0.2` 开始；用户已明确要求版本号时，按用户要求执行。
4. 检查 release builder 是否存在：

```powershell
Test-Path .\windows\build-release.ps1
```

如果不存在，先实现 `windows/build-release.ps1` 和 `windows/` 打包结构，不要假装已能打包。

## 计划中的标准命令

当前 Windows 包应能用一个命令生成：

```powershell
.\windows\build-release.ps1 -Version v0.2 -Channel stable
```

Dry run：

```powershell
.\windows\build-release.ps1 -Version v0.2 -Channel stable -DryRun
```

## 打包产物

标准产物应放在：

```text
dist/windows/
```

至少包含：

```text
easy-miloco-v0.2-windows.zip
easy-miloco-v0.2-windows.zip.sha256
manifest.json
release-notes.md
```

## 自测要求

Agent 需要至少完成：

- 解压 zip。
- 校验 `SHA256SUMS.txt`。
- PowerShell 脚本语法检查。
- Bash 脚本语法检查。
- 检查 `README.md`、`manifest.json`、`docs/AGENT.md` 是否存在。

## 发布提醒

GitHub Release 是唯一版本基准。发布 GitHub Release 后，Agent 必须提醒维护者：

```text
请把本次 GitHub Release 的同名 zip、sha256、release-notes 手动上传到夸克网盘副本，并确保用户下载副本后仍按 SHA256 校验。
```
