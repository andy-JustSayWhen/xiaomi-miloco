# Windows 部署资料包发布清单

> 更新日期：2026-06-24
> 用途：记录当前 Windows GitHub Release zip 的内容、生成方式和验收口径。
> 关联：[Windows部署总入口](index.md)、[Windows部署教程-独立分发版](standalone-package.md)、[Windows部署资料包验收记录](validation-record.md)

## 当前发布物

GitHub Release 是唯一版本基准。当前 Windows 一键包：

```text
dist/windows/easy-miloco-v0.2-windows.zip
```

普通用户拿到 zip 后，只需要解压并双击根目录的 `install.bat`。`install.ps1` 是 `install.bat` 调用的实现和维护者备用入口，不作为普通用户优先入口。

## 包内结构

```text
easy-miloco-v0.2-windows.zip
├── README.md
├── install.bat
├── install.ps1
├── manifest.json
├── release-notes.md
├── docs/
├── payload/
│   ├── install.sh
│   └── miloco-linux-x86_64-*.tar.gz
└── scripts/
    └── windows/
        ├── win-miloco-workflow.ps1
        ├── windows-preflight.ps1
        ├── wsl-miloco-validate.sh
        └── wsl-post-auth-finish.sh
```

包内不再生成 `.zip.sha256` 或 `SHA256SUMS.txt`。面向普通用户的下载口径只保留 GitHub Release 为版本基准。

## 构建命令

```powershell
.\windows\build-release.ps1 -Version v0.2 -Channel stable
```

已存在 Linux 构建产物、只重打 Windows release zip 时：

```powershell
.\windows\build-release.ps1 -Version v0.2 -Channel stable -SkipBuild
```

## 自测口径

构建脚本必须完成：

- zip 可解压。
- 解压根目录存在 `install.bat`、`install.ps1`、`manifest.json`、`payload/install.sh`、`docs/AGENT.md`。
- `install.bat` 保持 ASCII，避免双击入口乱码。
- `install.ps1`、桌面控制台模板、Windows workflow 脚本 PowerShell 解析通过。
- 包内 `.sh` 文件使用 LF 行尾。

本机复测和视觉部署记录见 [Windows部署资料包验收记录](validation-record.md)。

## 交付口径

可以对用户说：

```text
请从 GitHub Release 下载 easy-miloco-v0.2-windows.zip，解压后双击根目录 install.bat。安装器需要你处理时会用中文提示；安装完成后会在桌面生成 Miloco 控制台。
```
