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

#### 下载加速

如遇 GitHub 下载缓慢，可尝试以下方式：

1. **配置 GitHub 加速代理**
   - 可选网站：[gh-proxy.com](https://gh-proxy.com/) 或 [gitwarp.com](https://www.gitwarp.com/)
   - 使用方法：打开上述任一网站，按页面提示操作（也可自行搜索或问 AI）

2. **从网盘下载**
   - [夸克网盘备份](https://pan.quark.cn/s/22f5fb48488d)
   - 网盘为下载副本，版本基准仍以 GitHub Release 为准

## 环境依赖

下载 release 包后，用户可能遇到以下依赖或系统能力要求：

| 依赖                    | 是否需要 | 原因                                                                                                                         |
| ----------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 操作系统                | 必须     | Windows 建议 Windows 11 22H2+；低于该版本不保证完整兼容。macOS、Linux 后续按对应一键包说明执行                               |
| WSL2                    | 必须     | Miloco 当前不作为 Windows 原生后端运行，通过 WSL2 承载 Linux 后端                                                            |
| Ubuntu 24.04 WSL        | 必须     | 当前 Windows 部署默认使用 Ubuntu-24.04，便于统一脚本、路径和排障                                                             |
| 管理员权限              | 必须     | 首次安装可能需要启用 WSL、VirtualMachinePlatform、Hyper-V 防火墙入站规则                                                     |
| 网络访问 GitHub Release | 必须     | 官方版本基准和更新包以 GitHub Release 为准                                                                                   |
| 夸克网盘                | 可选     | 中国大陆用户 GitHub 下载慢时使用副本；仍需 SHA256 校验                                                                       |
| 小米账号                | 必须     | 用于绑定米家设备、读取家庭和设备列表                                                                                         |
| MiMo API Key            | 必须     | 用于 Miloco 视觉/多模态感知推理                                                                                              |
| 米家摄像头              | 必须     | 用于让 Miloco 获取家中画面并做视觉理解；摄像头需已绑定米家 App，且在米家 App 里能正常打开画面。支持型号见`docs/cameras.md` |
| OpenClaw                | 必须     | Miloco 以 OpenClaw 插件/技能形式接入 Agent 对话和自动化                                                                      |
| Python / Node / uv      | 可选     | 用户无需预装，一键包会自动准备；如果自动安装失败，诊断报告会指出失败层                                                       |

兼容声明：

Miloco for Windows v0.2 仅对 Windows 11 22H2 及以上版本提供完整一键部署保证。低于该版本的 Windows 可能可以运行基础服务，但不保证摄像头实时流、WSL mirrored networking、Hyper-V 防火墙、OpenClaw/Miloco 联动稳定可用。

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
easy-miloco-v0.2-<system>/
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

## 差异对比

本节从用户视角列功能，并用代码/脚本/文档说明实现差异。官方列依据 Xiaomi Miloco 官方 README、`plugins/openclaw/README.md` 和官方仓库主线；当前仓库列依据本仓库当前 `main`。

| 功能                              | 官方仓库 | 当前仓库 | 差异点                                                                                                                                    |
| --------------------------------- | -------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 通用常识危险识别                  | ☑️     | ☑️     | 核心感知与 Agent 规则链路沿用官方：摄像头输入进入感知流水线，DYNAMIC 规则经 OpenClaw Agent 执行。                                         |
| 身份识别                          | ☑️     | ☑️     | 沿用官方`person`、identity engine、tier_a/tier_c 样本库；当前仓库补充启动时 tier_a ReID embedding 幂等 backfill。                       |
| 家庭记忆                          | ☑️     | ☑️     | 沿用官方 home profile 注入；当前仓库补充跨平台文件锁兜底，减少 Windows/WSL 场景对 Unix-only`fcntl` 的依赖。                             |
| 家庭任务                          | ☑️     | ☑️     | 沿用官方`task` + `task_record` + OpenClaw cron/skill 编排；当前仓库保留 task 终止审计和跨日 rollover 兜底。                           |
| 主动智能                          | ☑️     | ☑️     | 核心仍是感知事件/规则/任务投递到 OpenClaw；当前仓库增强 dispatcher 与观测数据，便于排查主动推送。                                         |
| 家庭面板                          | ☑️     | ☑️     | 官方提供 Web dashboard；当前仓库把构建产物纳入后端 static 托管，并新增性能报告入口。                                                      |
| 米家设备查询与控制                | ☑️     | ☑️     | 官方通过`miloco-devices` skill、CLI 和后端 MIoT service；当前仓库保持 Cloud/LAN 双路径与 scope 校验。                                   |
| 小米账号绑定                      | ☑️     | ☑️     | 官方 CLI/面板绑定；当前仓库增加 Windows 部署脚本里的 OAuth 引导与后授权收尾 runbook。                                                     |
| 模型配置与用量查看                | ☑️     | ☑️     | 官方面板模型页和 admin cost；当前仓库新增运行级性能报告，与 token/trace 观测分开。                                                        |
| 摄像头感知开关                    | ☑️     | ☑️     | 官方通过 camera scope 启用指定摄像头；当前仓库修正 cloud/lan/connected 三类在线证据，减少假离线。                                         |
| 实时摄像头观看                    | ☑️     | ☑️     | 官方 WebSocket + jMuxer；当前仓库增加最后订阅者断开后的延迟 teardown，避免刷新面板导致频繁冷启动。                                        |
| 按需视觉感知                      | ☑️     | ☑️     | 官方依赖当前 active source；当前仓库在 OpenClaw 请求时刷新摄像头元数据并短等目标源/缓冲，降低首次请求失败。                               |
| 摄像头音频参与感知                | ☑️     | ❌       | 官方以视频与声音为全模态入口；当前仓库默认不订阅摄像头音频解码流，优先保证视频感知稳定，避免部分设备音频流拖垮后端。                      |
| OpenClaw 插件                     | ☑️     | ☑️     | 官方注册 service、hooks、webhooks、tools；当前仓库保持同样插件面，并补充大量部署/排障文档。                                               |
| `miloco-devices` skill          | ☑️     | ☑️     | 两边均支持设备查询、属性读取、控制和场景触发。                                                                                            |
| `miloco-perception` skill       | ☑️     | ☑️     | 两边均支持视觉感知；当前仓库在摄像头冷启动、LAN hint 和首帧等待上更保守。                                                                 |
| `miloco-miot-identity` skill    | ☑️     | ☑️     | 两边均支持成员/宠物身份管理；当前仓库保留与家庭档案联动清理。                                                                             |
| `miloco-miot-admin` skill       | ☑️     | ☑️     | 两边均支持系统状态和用量查询；当前仓库另加性能报告 API 与 Web 页面。                                                                      |
| `miloco-create-task` skill      | ☑️     | ☑️     | 两边均支持任务创建、列表、日志、启停和更新。                                                                                              |
| `miloco-terminate-task` skill   | ☑️     | ☑️     | 两边均支持终止任务；当前仓库强调审计快照、级联清理和 cron pending 清理。                                                                  |
| `miloco-notify` skill           | ☑️     | ☑️     | 两边均支持感知异常分级和通知；当前仓库文档补充通知渠道排障路径。                                                                          |
| `miloco-cli` 服务/设备/配置管理 | ☑️     | ☑️     | 官方 CLI 提供 service、account、config、device、scope 等命令；当前仓库保留并补充 Windows/WSL 验收脚本。                                   |
| macOS/Linux 安装                  | ☑️     | ☑️     | 官方主线是`install.sh`；当前仓库仍保留官方脚本和源码构建路径。                                                                          |
| Windows WSL 安装                  | ☑️     | ☑️     | 官方说明 Windows 需 WSL；当前仓库增加 Windows 一键包、预检、安装、后授权、验收和故障矩阵。                                                |
| Windows 原生后端                  | ❌       | ❌       | 两边都不支持 Windows 原生后端；当前仓库明确用 WSL2 承载 Linux 后端。                                                                      |
| 一键部署 zip 包                   | ❌       | ☑️     | 当前仓库新增`windows/package/install.ps1`、manifest、payload 和 release 包文档，面向普通用户双击安装。                                  |
| 桌面控制台菜单                    | ❌       | ☑️     | 当前仓库生成`Miloco 控制台.bat`，提供重启 OpenClaw、重启 Miloco、整套重启、关闭服务、关闭 WSL。                                         |
| Windows 诊断/验收脚本             | ❌       | ☑️     | 当前仓库新增`docs/scripts/*` 和 `windows-preflight`/`wsl-miloco-validate`/`win-miloco-workflow`，区分 BASIC_READY 与 FULL_READY。 |
| 国内下载副本与校验                | ❌       | ☑️     | 当前仓库文档支持 GitHub Release 为基准、夸克网盘作副本、用户按 SHA256 校验。                                                              |
| 教程、FAQ、runbook                | ❌       | ☑️     | 当前仓库新增`docs/`，覆盖一键部署、Windows、摄像头、SSH 命令传输、NAS 安装、性能报告等复用经验。                                        |
| 性能报告 WebUI                    | ❌       | ☑️     | 当前仓库新增`performance_report.py`、`performance_report_router.py` 和 `PerformanceReportsPage.tsx`，展示每次后端运行报告。         |
| Agent 可读备份恢复包              | ❌       | ☑️     | 当前仓库新增`backup_export.py`、`BackupPage.tsx` 和 `/admin/backup/export`，导出家庭档案、成员、任务、模型配置的逻辑恢复 zip。      |
| 摄像头 Wi-Fi/首帧排障规则         | ❌       | ☑️     | 当前仓库把 Game/5G Wi-Fi、坏 LAN override、无首帧 cooldown、误删 OAuth 等实战规则沉淀到`docs/windows/camera-runbook.md`。               |

## 其他

本仓库遵循以下原则：

- GitHub Release 是唯一版本基准。
- Release 包是构建产物，不手工修改。
- 用户问题优先通过诊断报告定位，不盲目重装。
- 更新前只备份本项目相关状态，不默认导出整个 WSL。
- 失败经验和成功经验必须沉淀到 `docs/faq/known-issues.md` 或对应 runbook。
- v0.2 先保证 Windows 11 22H2+；macOS、NAS、云服务器在 Windows 路线稳定后再展开。
