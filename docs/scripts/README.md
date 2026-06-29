# docs/scripts

这里保留 release 包和维护者验证会实际复用的脚本。不要在本目录放实机日志、账号信息、token、API Key 或远程主机专属命令记录。

## Windows

- `windows-preflight.ps1`：Windows 宿主预检。
- `win-miloco-workflow.ps1`：Windows/WSL 部署工作流入口。
- `wsl-post-auth-finish.sh`：WSL 内账号授权、模型配置和后授权收尾。
- `wsl-miloco-validate.sh`：WSL 内基础/满血验收。
- `windows-release-validate.ps1`：Windows release 包结构和运行态验证。
- `fix-camera-denylist.ps1` / `fix-camera-denylist.bat`：摄像头 denylist 快速修复入口。

## macOS

- `macos-preflight.sh`：macOS 懒人包预检。
- `macos-post-auth-finish.sh`：macOS 后授权收尾。
- `macos-miloco-validate.sh`：macOS 基础/满血验收。

## NAS

- `../nas/docker-deploy.md`：NAS Docker 部署说明。
- `../../nas/docker/manage.sh`：NAS Docker 控制入口，提供启动、重启、日志、状态和验收。

## Release

- `publish-github-release-asset.ps1`：替换 GitHub Release 资产并校验。
