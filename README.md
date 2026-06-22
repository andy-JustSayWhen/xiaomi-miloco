# easy-miloco

本仓库 fork 自 Xiaomi Miloco 官方仓库，核心功能随官方异步更新。本仓库做的工作主要为：1. 提供一键部署包，适配 Windows、macOS、NAS 和云服务器；2. 提供教程。面向小白，长期更新 miloco 系列教程；3. 其他见 [项目说明](#项目说明)。

## 一键部署

### Agent 全自动

把下面这句话丢给 Agent，让 Agent 全程代劳：

```text
请为我一键部署 Miloco，按照：https://github.com/andy-JustSayWhen/easy-miloco/blob/main/docs/install-guide.md
```

### 用户自己动

打开 [GitHub Release](https://github.com/andy-JustSayWhen/easy-miloco/releases)，根据系统类型，下载对应的 `.zip` 一键部署包。下载后，解压，双击文件夹根目录内的 `install.ps1`。

## 环境依赖

下载 release 包后，用户可能遇到以下依赖或系统能力要求：

| 依赖 | 是否需要 | 原因 |
| --- | --- | --- |
| 操作系统 | 必须 | Windows 建议 Windows 11 22H2+；低于该版本不保证完整兼容。macOS、Linux 后续按对应一键包说明执行 |
| WSL2 | 必须 | Miloco 当前不作为 Windows 原生后端运行，通过 WSL2 承载 Linux 后端 |
| Ubuntu 24.04 WSL | 必须 | 当前 Windows 部署默认使用 Ubuntu-24.04，便于统一脚本、路径和排障 |
| 管理员权限 | 必须 | 首次安装可能需要启用 WSL、VirtualMachinePlatform、Hyper-V 防火墙入站规则 |
| 网络访问 GitHub Release | 必须 | 官方版本基准和更新包以 GitHub Release 为准 |
| 夸克网盘 | 可选 | 中国大陆用户 GitHub 下载慢时使用副本；仍需 SHA256 校验 |
| 小米账号 | 必须 | 用于绑定米家设备、读取家庭和设备列表 |
| MiMo API Key | 必须 | 用于 Miloco 视觉/多模态感知推理 |
| 米家摄像头 | 必须 | 用于让 Miloco 获取家中画面并做视觉理解；摄像头需已绑定米家 App，且在米家 App 里能正常打开画面。支持型号见 `docs/cameras.md` |
| OpenClaw | 必须 | Miloco 以 OpenClaw 插件/技能形式接入 Agent 对话和自动化 |
| Python / Node / uv | 可选 | 用户无需预装，一键包会自动准备；如果自动安装失败，诊断报告会指出失败层 |

兼容声明：

Miloco for Windows v0.1 仅对 Windows 11 22H2 及以上版本提供完整一键部署保证。低于该版本的 Windows 可能可以运行基础服务，但不保证摄像头实时流、WSL mirrored networking、Hyper-V 防火墙、OpenClaw/Miloco 联动稳定可用。

## 项目说明

### 目录树

仓库目录树：

```text
.
├── backend/              # Miloco 后端
├── cli/                  # miloco-cli
├── plugins/              # OpenClaw 插件和 skills
├── web/                  # Miloco WebUI
├── scripts/              # 官方安装/构建脚本
├── windows/              # 本 fork 新增：一键部署包源码、打包、更新、回滚
├── docs/                 # 本 fork 新增：教程、部署指南、FAQ、runbook、release 说明
├── knowledge/            # 项目知识库
├── README.md
└── LICENSE.md
```

Release 包目录树示例：

```text
easy-miloco-v0.1-<system>/
├── README.md
├── install.ps1
├── manifest.json
├── release-notes.md
├── SHA256SUMS.txt
├── bin/
├── scripts/
│   ├── windows/
│   └── wsl/
├── assets/
├── docs/
└── payload/
```

### 差异对比

本节按三个层次对比：先看代码层面，再看实现方式，最后看用户视角。对比项不是按目录树机械罗列，而是只列会影响功能、部署、分发、排障或用户使用路径的差异。

#### 代码层面

| 对比项 | 与官方一致 | 本仓库变化 | 证据 |
| --- | --- | --- | --- |
| 大部分核心代码 | ☑️ | `cli/`、`plugins/`、WebUI 产品代码未作为当前差异重点改写 | `git diff` 未显示这些目录的产品代码差异 |
| 摄像头在线判定 | ❌ | 云端在线但 `lan_online` 陈旧为 false 时，允许先尝试连接；已有本地视频流时优先认为摄像头在线 | `backend/miloco/src/miloco/perception/collect/camera_adapter.py`、`backend/miloco/src/miloco/miot/service.py` |
| 按需视觉感知 | ❌ | OpenClaw 请求摄像头画面时，会刷新摄像头在线元数据，并等待目标画面源短时间重连和缓冲 | `backend/miloco/src/miloco/perception/service.py` |
| 摄像头音频流 | ❌ | 默认不订阅摄像头音频解码流，避免部分设备的音频帧影响后端稳定性；当前家庭视觉感知优先依赖视频帧 | `backend/miloco/src/miloco/perception/collect/camera_adapter.py` |
| 摄像头测试 | ❌ | 增加/调整 stale LAN、已连接摄像头、按需重连、关闭音频订阅等测试 | `backend/miloco/tests/perception/`、`backend/miloco/tests/test_miot_filter_and_cameras.py` |

#### 实现方式

| 对比项 | 与官方一致 | 本仓库做法 | 状态 |
| --- | --- | --- | --- |
| Agent 安装入口 | ❌ | README 保留一句话入口，真实指南放在 `docs/install-guide.md`；`scripts/install-guide.md` 仅保留官方路径习惯的兼容入口 | 已落盘 |
| Windows 部署路线 | ❌ | 不做 Windows 原生后端；Windows 通过 WSL2 承载 Miloco 后端，并由一键包隐藏复杂步骤 | 规划中 |
| 一键部署包 | ❌ | 普通用户从 GitHub Release 下载对应系统 `.zip`，解压后双击根目录 `install.ps1` | v0.1 待实现 |
| 更新与回滚 | ❌ | 以 GitHub Release 为唯一版本基准；更新前只备份本项目相关状态，失败或后悔时一键回滚 | v0.1 待实现 |
| 国内下载副本 | ❌ | GitHub Release 仍是版本基准；维护者可同步夸克网盘副本，用户下载后校验 SHA256 | v0.1 待实现 |
| 教程、FAQ 与 runbook 文档 | ❌ | 新增 `docs/AGENT.md`、`docs/faq/`、`docs/runbooks/`，面向小白长期维护 miloco 系列教程，并让 Agent 能按文档部署和诊断 | 文档骨架已落盘 |

#### 用户视角

| 用户关心的问题 | 官方仓库 | 本仓库目标 | 状态 |
| --- | --- | --- | --- |
| 怎么安装 | 按官方安装方式执行，Windows 需用户理解 WSL | 复制一句话给 Agent，或下载 `.zip` 后双击安装入口 | 文档已写，包待实现 |
| 摄像头为什么离线 | 更依赖 MiOT 返回的在线和 LAN 状态 | 对已连接或可尝试连接的摄像头减少“假离线”判断 | 代码已改 |
| OpenClaw 能不能看到摄像头画面 | 取决于摄像头源是否已经活跃 | 请求时主动刷新并等待画面源准备，降低第一次请求失败率 | 代码已改 |
| 出问题怎么处理 | 用户需要看日志和命令排查 | 通过诊断报告、FAQ 和 runbook 分层处理，并把新问题沉淀回 docs | 文档骨架已落盘 |
| 能不能更新/回滚 | 官方未提供本 fork 的懒人包更新/回滚体验 | 显示更新说明，用户确认后更新；失败或后悔可回滚 | v0.1 待实现 |

### 其他

本仓库遵循以下原则：

- GitHub Release 是唯一版本基准。
- Release 包是构建产物，不手工修改。
- 用户问题优先通过诊断报告定位，不盲目重装。
- 更新前只备份本项目相关状态，不默认导出整个 WSL。
- 失败经验和成功经验必须沉淀到 `docs/faq/known-issues.md` 或对应 runbook。
- v0.1 先保证 Windows 11 22H2+；macOS、NAS、云服务器在 Windows 路线稳定后再展开。
