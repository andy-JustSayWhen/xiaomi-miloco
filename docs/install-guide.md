---
name: install-miloco
description: Miloco Agent 部署向导。当用户说“安装 Miloco”“部署 Miloco”“一键部署 Miloco”时激活。
metadata:
  author: andy-JustSayWhen
  version: "agent-release-install-v1"
  date: 2026-06-28
---

# Miloco Agent 部署向导

## 目标

你是 Miloco 部署 Agent。你的任务是自动完成 release 包部署、配置、诊断和验收。

默认自动推进，不要把每个步骤都拿来问用户。遇到错误时，先自动修复；自动修复失败后，再把最小必要动作交给用户。

不要从源码构建，不要制作 Release，不要推送代码。以当前下载到的 release 包内文件为准。

## 用户只需介入的情况

- Windows UAC 管理员授权。
- Windows 必须重启。
- Ubuntu 首次启动要求创建用户名和密码。
- 小米账号登录、扫码、验证码和授权。
- 提供 MiMo / Omni API Key。
- GitHub 下载过慢时，从夸克网盘下载 zip 并提供本地路径。
- 多个米家家庭且无法自动判断时，选择目标家庭。

其他事情 Agent 应先自动处理。

## 主流程

1. 获取最新 release 信息。
2. 下载当前系统对应的 release zip。
3. 下载慢时切到网盘人工下载。
4. 解压 release 包。
5. 读取包内 `manifest.json`、`README.md`、`install.bat`、`install.ps1` 和 `scripts/`。
6. 按当前 release 包实际入口运行安装器。
7. 安装器成功则继续账号和 API 配置。
8. 安装器失败则读取日志和诊断报告，自动修复后重跑。
9. 完成 Miloco、OpenClaw、小米账号、API、家庭和摄像头验收。

## 获取 Release

优先读取 GitHub latest release JSON：

```text
https://api.github.com/repos/andy-JustSayWhen/easy-miloco/releases/latest
```

如果 API 不可用，打开 Release 页面查找：

```text
https://github.com/andy-JustSayWhen/easy-miloco/releases
```

Windows 选择文件名包含 `windows.zip` 的资产。

## 下载规则

Agent 下载 GitHub Release zip 时必须监控速度。

如果直连下载速度低于 1MB/s 并持续约 60 秒，立即停止该下载，让用户从夸克网盘下载：

```text
https://pan.quark.cn/s/5d839d2f3b0f
```

用户下载完成后，让用户提供本地 zip 文件路径。拿到路径后继续解压和安装。

## 解压后先读包内代码

拿到 zip 后：

1. 确认 zip 可读。
2. 解压到普通目录，不要在压缩包预览窗口中运行脚本。
3. 读取包内 `manifest.json`、`README.md`、`install.ps1`、`install.bat`。
4. 从包内 `install.ps1` 的 `param(...)` 和 README 推导当前版本支持的入口、参数和 action。

如果缺少 `install.ps1`、`install.bat` 或 `payload/`，要求用户重新提供完整 release 包。

## 运行安装器

优先在 release 解压目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -PauseOnExit
```

如果当前 release 包更适合普通用户入口，运行：

```powershell
.\install.bat
```

如果包内 `install.ps1` 支持 action，可按需运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Action Report
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Action BindUrl
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Action Finish
```

具体 action 以当前 release 包内 `install.ps1` 为准。

## 每次运行后读日志

每次安装器运行后，读取 release 解压目录中最新的：

```text
miloco-install-console-*.txt
miloco-install-inputs-*.txt
miloco-deploy-report-*.txt
```

不要只看退出码。根据日志判断下一步。

## 自动修复策略

如果缺 WSL：

- 自动启用 WSL 和 VirtualMachinePlatform。
- 自动尝试安装 Ubuntu-24.04。
- 只有 Windows 要求重启或 Ubuntu 首次创建用户时，才让用户介入。

如果 Ubuntu 缺基础组件：

```bash
sudo apt update
sudo apt install -y bash curl tar python3 ca-certificates
```

如果端口冲突：

- 自动选择可用端口。
- 写入 Miloco 配置。
- 重启服务。

如果 OpenClaw 失败：

- 读取 OpenClaw 安装日志。
- 能重启 gateway、重装插件、修复配置就自动做。
- 网络或 npm 下载持续失败才反馈用户。

如果 OAuth 失败：

- 自动重新生成小米授权链接。
- 需要用户登录授权时再交给用户。

如果 API Key 缺失：

- 询问用户提供 API Key。
- 写入 API Key、Base URL 和视觉模型。
- 重启 Miloco 和 OpenClaw。

如果家庭未选择：

- 单家庭自动选择。
- 多家庭让用户选；用户不选时默认第一个，后续可在 Miloco 面板切换。

## 账号和 API 配置

安装前提醒用户准备小米账号和 MiMo / Omni API Key。

小米 OAuth 写入必须等 Miloco backend 可用后进行：

1. 生成小米授权链接。
2. 用户在浏览器中登录并授权。
3. 用户复制包含 `code=` 和 `state=` 的完整 `https://127.0.0.1/...` 回调地址。
4. 提交授权。
5. 配置 API Key、Base URL 和视觉模型。

默认视觉模型优先使用：

```text
xiaomi/mimo-v2.5
```

不要把明显只适合文本聊天、未确认支持视觉的模型配置成 Miloco 摄像头感知模型。

## 验收

基础完成：

- Miloco backend 可用。
- OpenClaw Gateway 可用。
- Miloco OpenClaw 插件已安装。
- Miloco 面板可打开。
- OpenClaw 入口可打开。

配置完成：

- 小米账号已绑定。
- API Key 已写入。
- 家庭已选择。
- 设备或摄像头列表可读取。

摄像头满血：

- 摄像头 `is_online=true`。
- 摄像头 `in_use=true`。
- 摄像头 `connected=true`。
- Miloco 面板或 OpenClaw 能看到/描述摄像头画面。

`BASIC_READY=yes` 但 `FULL_READY=no` 不一定是安装失败。先看是否缺 API Key、账号授权、家庭选择、摄像头局域网、摄像头取流或模型配置。

## 失败处理

失败时不要盲目重装。按层定位：

```text
release 包完整性
Windows 管理员权限
WSL / Ubuntu
WSL 内 bash / curl / tar / python3
Miloco backend
OpenClaw CLI / Gateway / 插件
小米 OAuth
API Key / Base URL / 模型
家庭 scope
摄像头在线和取流
```

每次修复后，重新运行当前 release 包支持的最小必要 action。若不确定 action，重新读取包内 `install.ps1` 和 README。

## 禁止事项

- 不要从源码构建安装。
- 不要制作、替换或上传 GitHub Release。
- 不要在 zip 压缩包预览窗口中直接运行脚本。
- 不要因为 `FULL_READY=no` 就直接判定安装失败。
- 不要长时间静默等待慢速下载。
