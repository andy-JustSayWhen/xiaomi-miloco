# Known Issues

这里沉淀部署、更新、回滚和运行过程中的常见问题。Agent 排障时应先查本文件；如果遇到新问题，修复后补充到这里。

## 低版本 Windows 的兼容边界

现象：

- 摄像头实时流不稳定。
- WSL mirrored networking 不可用或行为不一致。
- Hyper-V 防火墙相关命令不可用。

原因：

- Windows v0.1 完整体验只保证 Windows 11 22H2+。

处理：

- 低于该版本可以尝试基础服务，但不承诺摄像头实时流、持续感知和 OpenClaw/Miloco 联动稳定。

## 夸克网盘副本不能作为版本基准

现象：

- 用户拿到夸克网盘下载链接，误以为它是独立版本源。

原因：

- 本项目版本基准只认 GitHub Release。夸克网盘只是人工同步副本。

处理：

- 下载后必须校验 SHA256。
- release notes 和 manifest 以 GitHub Release 为准。
