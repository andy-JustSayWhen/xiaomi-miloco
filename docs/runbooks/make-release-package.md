# Make Release Package Runbook

用途：维护者专用。当仓库维护者说“制作更新包”“打包更新吧”“发一个新版本”时，Agent 按本 runbook 执行。普通部署用户没有资格更新本仓库或发布 release，不应使用本 runbook。

## 目标

根据当前仓库代码生成新的 release 更新包，并完成：

- 构建
- 自测
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
manifest.json
release-notes.md
```

## 自测要求

Agent 需要至少完成：

- 解压 zip。
- PowerShell 脚本语法检查。
- Bash 脚本语法检查。
- 检查 `README.md`、`manifest.json`、`docs/AGENT.md` 是否存在。

## 发布提醒

GitHub Release 是唯一版本基准。发布 GitHub Release 后，Agent 必须提醒维护者：

```text
请把本次 GitHub Release 的同名 zip 和 release-notes 手动上传到夸克网盘副本。GitHub Release 仍是唯一版本基准。
```

## GitHub Release 资产替换

替换 Release 资产前必须得到用户明确确认，例如用户说“发版替换”。确认后只允许使用固定脚本：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\publish-github-release-asset.ps1 `
  -Repo andy-JustSayWhen/easy-miloco `
  -Tag v0.2 `
  -AssetPath .\dist\windows\easy-miloco-v0.2-windows.zip `
  -Replace
```

不允许临场手搓不同 `gh release upload` 命令。该脚本会统一完成：

- 检查 `gh auth status`。
- 默认设置 Clash 代理 `http://127.0.0.1:7897`。
- 上传超时控制和固定次数重试。
- 上传后读取 Release 资产。
- 校验远端 size 与本地文件一致。
- 校验远端 `sha256:` digest 与本地 SHA256 一致。
- 不一致时直接失败。

只核对当前 Release 资产是否等于本地 zip，不上传：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\docs\scripts\publish-github-release-asset.ps1 `
  -Repo andy-JustSayWhen/easy-miloco `
  -Tag v0.2 `
  -AssetPath .\dist\windows\easy-miloco-v0.2-windows.zip `
  -VerifyOnly
```
