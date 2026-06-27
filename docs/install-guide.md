---
name: install-miloco
description: Miloco 一键部署引导，当用户说“安装 Miloco”“部署 Miloco”“一键部署 Miloco”时激活。
metadata:
  author: andy-JustSayWhen
  version: "0.2"
  date: 2026-06-24
---

# Miloco 一键部署指南

## 目标

你正在帮助用户在当前 Windows 电脑上一键部署这个 fork：

```text
https://github.com/andy-JustSayWhen/easy-miloco
```

普通用户没有发布权限，不要尝试推送、打 tag、发布 GitHub Release 或制作更新包。你的任务是安装、配置、验证、诊断和修复。

## 优先路径

1. 打开 GitHub Release：

   ```text
   https://github.com/andy-JustSayWhen/easy-miloco/releases
   ```

2. 根据系统类型，下载最新版 `.zip` 一键部署包，文件名通常类似：

   ```text
   easy-miloco-v0.2-windows.zip
   ```

3. 如果 GitHub 下载慢，询问用户是否有维护者提供的夸克网盘副本。夸克网盘只是下载副本，GitHub Release 才是版本基准。

4. 解压后，双击解压目录根部的：

   ```text
   install.bat
   ```

5. 安装完成后验证桌面入口、后端服务和页面可用性：

   ```text
   Miloco 控制台.bat
   ```

   该桌面脚本由 `install.ps1` 自动生成。菜单包含重启 OpenClaw 面板、重启 Miloco 面板、重启 Miloco + OpenClaw、关闭 OpenClaw + Miloco、关闭 WSL、接入消息渠道。

维护者需要手动运行或做卸载复测时，再使用 `install.ps1`。

## 如果还没有可用 Release

如果 Release 页面没有 Windows 一键部署包，不要假装已经可以一键安装。请 clone 仓库并读取：

```text
docs/AGENT.md
docs/index.md
docs/runbooks/
docs/faq/known-issues.md
```

然后明确告诉用户：当前仓库需要先制作或等待 Windows 一键 release 包。只有仓库维护者明确要求“制作更新包”“打包更新吧”“发版”时，才进入 `docs/runbooks/make-release-package.md`。

## Windows 兼容边界

Windows v0.2 仅对 Windows 11 22H2 及以上版本提供完整一键部署保证。低于该版本可能能运行基础能力，但不保证 WSL mirrored networking、Hyper-V 防火墙、摄像头局域网流、OpenClaw/Miloco 联动稳定可用。

## 排障原则

遇到问题时，不要盲目重装。先生成诊断报告，再按层定位：

```text
Windows 宿主机
兼容 Ubuntu WSL2
Miloco backend
Miloco WebUI
OpenClaw Gateway
OpenClaw 插件/技能
小米账号
MiMo 模型配置
米家设备和摄像头局域网流
```

优先参考：

```text
docs/AGENT.md
docs/faq/known-issues.md
docs/runbooks/
```

如果当前是在维护者本地仓库中，修复完成后把新增问题、解决办法和成功经验沉淀回 `docs/faq/known-issues.md` 或对应 runbook。
