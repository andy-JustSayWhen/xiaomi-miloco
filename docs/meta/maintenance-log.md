# 维护日志

## 2026-06-23 整合 Obsidian easy-miloco 有效内容

目的：

- 将 Obsidian `easy-miloco` 笔记中仍有复用价值的部署、摄像头排障和 SSH 命令传输经验合并回仓库 `docs/`。
- 保留仓库版文档已有的脱敏和 Markdown 链接整理，不用 Obsidian 原文覆盖。
- 不迁入缓存、下载包、`.env` 和重复资料包内容。

新增：

- `docs/windows/ssh-command-transfer.md`
- `docs/windows/reports/windows-sample-host-20260623-camera-wifi-root-cause.md`
- `docs/runbooks/nas01-openclaw-miloco-install.md`

更新：

- `docs/windows/camera-runbook.md`
- `docs/windows/index.md`
- `docs/index.md`
- `docs/meta/source-map.md`
- `docs/meta/maintenance-log.md`

## 2026-06-23 新增性能报告与 WebUI 规格复盘

目的：

- 把每次后端运行性能报告、侧边栏“性能”入口、报告 API 和日志打包行为沉淀成可维护规格。
- 明确新“性能”tab 展示历史运行报告，旧 `#perf` 仍作为实时调试视图保留。

新增：

- `docs/runbooks/performance-report-webui-spec.md`

同步更新：

- `docs/index.md`
- `docs/meta/source-map.md`
- `docs/meta/maintenance-log.md`

## 2026-06-22 初始化

目标：把空的 Obsidian 目录初始化为可持续维护的 Miloco 教程库，服务后续部署和测试。

已完成：

- 建立根索引 `index.md` 和维护规则 `AGENT.md`。
- 建立 `00-meta`、`01-overview`、`02-deploy`、`03-test`、`04-runbooks` 五个一级目录。
- 沉淀源码地图、系统架构、部署指南、测试指南、变更和排障手册。
- 明确 Obsidian 目录不是源码目录，源码修改只发生在 `C:\Users\<user>\Desktop\xiaomi-miloco`。

依据：

- CodeGraph 索引健康：566 个文件，Python/TypeScript/TSX/YAML/JavaScript 多语言项目。
- 已读根 README、backend/cli/web/plugin README、各端 `pyproject.toml`/`package.json`、CI workflow、安装脚本和关键入口源码。
- 目标目录原有 `.env` 与 `.npm-cache`，本次保留不动。

后续维护要求：

- 改部署，更新 `02-deploy/deployment-guide.md`。
- 改测试或 CI，更新 `03-test/test-guide.md`。
- 改入口、模块边界或关键路径，更新 `00-meta/source-map.md` 和 `01-overview/system-architecture.md`。

## 2026-06-22 补充异地部署边界

问题：用户询问人在小区 2、家庭 01 在小区 1，能否在小区 2 的电脑部署后访问家庭 01 设备。

结论：

- MIoT 设备列表、查询、控制和场景触发走小米账号和 MIoT cloud API，可以异地使用。
- 摄像头实时流和基于摄像头的持续感知默认依赖 LAN，本机不在家庭局域网时不可直接使用，除非通过 VPN 或等价组网打通本地流。

依据：

- README 明确 dashboard live view 从 LAN 拉摄像头流。
- 后端 `set_device_properties`、`call_device_action` 注释为通过 MIoT cloud API。
- 感知摄像头筛选默认 `require_lan=True`，并同时要求 `online` 和 `lan_online`。

## 2026-06-22 新增 <windows-sample-host> 部署实录

问题：用户开始在远程 Windows 电脑 `<windows-sample-host>` 部署 Miloco，需要把官方部署步骤、实际执行命令、踩坑和解决办法实时沉淀到 Obsidian。

已完成：

- 新增 `02-deploy/<windows-sample-host>部署实录.md`。
- 在 `02-deploy/deployment-guide.md` 增加实机部署实录入口。
- 在 `index.md` 的阅读顺序和目录地图中登记新文档。
- 在全局 `00 目录树.md` 的 `easy-miloco/` 清单中登记新文档。

依据：

- Miloco README 和 `scripts/install.ps1` 明确 Windows 原生安装不支持，应在 WSL 内运行。
- 用户在 `<windows-sample-host>` 上实际遇到 `Wsl/E_INVALIDARG` 和 `ERROR_ALREADY_EXISTS`，当前判断为命令粘贴重复以及 `Ubuntu-24.04` 已存在。

后续维护要求：

- 后续每个部署命令、报错和修复结果继续追加到 `<windows-sample-host>部署实录.md`。
- 可复用排障结论再抽象回 `deployment-guide.md` 或 `04-runbooks/change-and-debug-runbook.md`。

## 2026-06-22 <windows-sample-host> 基础部署完成

结果：

- `<windows-sample-host>` 的 WSL `Ubuntu-24.04` 内已安装 Miloco。
- Miloco 后端运行在 `http://127.0.0.1:1886/`，`/health` 返回 `{"status":"ok"}`。
- OpenClaw Gateway 运行在 `http://127.0.0.1:18789/`，systemd user 服务已 enabled/running。
- `miloco-openclaw-plugin` 已安装、启用、加载，`openclaw plugins doctor` 无插件问题。
- Windows 侧 `curl.exe` 可访问 Miloco health 和 OpenClaw Dashboard。

关键修复：

- 默认 `1810` 位于 <windows-sample-host> Windows TCP excluded port range `1786-1885` 内，改 Miloco `server.url=http://127.0.0.1:1886`。
- WSL 内无 Linux `node` 且不能免密 sudo，改为用户目录安装 Node，再安装 OpenClaw CLI/Gateway。
- 复杂 WSL 命令避免直接嵌套在 Windows OpenSSH 字符串里，改用上传脚本后执行。

已沉淀：

- 更新 `02-deploy/<windows-sample-host>部署实录.md` 至最终验证状态。
- 新增 `02-deploy/Windows部署教程-Agent一键版.md`。
- 新增 `02-deploy/Windows部署教程-人工手动版.md`。
- 更新 `02-deploy/deployment-guide.md`、`index.md` 和全局 `00 目录树.md`。

待用户醒后：

- 绑定小米账号。
- 配置 MiMo / Omni API Key。
- 根据设备列表开启摄像头感知范围。

## 2026-06-22 满血部署缺口复核

复核结果：

- Miloco 后端仍在线：`http://127.0.0.1:1886/health` 返回 `{"status":"ok"}`。
- OpenClaw Gateway 仍在线：`http://127.0.0.1:18789/`，systemd user enabled/running。
- `miloco-openclaw-plugin` 仍为 `Status: loaded`。
- `miloco-cli account status` 返回 `is_bound=false`。
- `model.omni.api_key` 为空。
- `miloco-cli device list` 当前只有 TSV 表头，`scope camera list` 返回空数组；后端日志显示 `access token is empty`。

结论：

- 当前状态是“基础服务 + OpenClaw 插件就绪”。
- 满血部署还需要用户提供小米账号 OAuth 授权码和 MiMo API Key。

文档更新：

- `deployment-guide.md` 新增“基础安装与满血安装的分界”。
- `Windows部署教程-Agent一键版.md` 新增用户介入节点与满血验收。
- `Windows部署教程-人工手动版.md` 新增设备列表/摄像头/模型 Key 的满血验收和常见误判。
- `常用SSH信息/<windows-sample-host>` 增补 Miloco/OpenClaw 服务入口、配置路径和 token。

## 2026-06-22 新增 Windows 部署入口清单和 Agent 提示词

目的：把 <windows-sample-host> 的实战经验沉淀成任何 Windows 玩家可照做的入口文档。

新增：

- `02-deploy/Windows部署预检与验收清单.md`
- `02-deploy/Agent一键部署提示词.md`

同步更新：

- `index.md`
- `02-deploy/deployment-guide.md`
- 全局 `00 目录树.md`

补强点：

- 明确官方 Agent 三步流程。
- 明确不要关闭 Clash Verge TUN，网络问题优先使用代理环境变量和镜像。
- 明确基础安装与满血安装验收差异。
- 明确 `device list` 当前版本不使用 `--pretty`。
- 明确账号未绑定和 API Key 未配置的日志特征。

## 2026-06-22 新增 <windows-sample-host> 后授权收尾 Runbook

新增：

- `02-deploy/<windows-sample-host>后授权收尾Runbook.md`

目的：

- 收到小米 OAuth 授权码和 MiMo API Key 后，按固定清单完成账号绑定、模型配置、服务重启、设备刷新、摄像头开启和满血验收。

依据：

- 当前 CLI help 验证了 `account authorize PAYLOAD`、`config set`、`scope home list/switch`、`scope camera list/enable` 的参数形态。
- 远端复核显示 Miloco 仍 running，health 正常，账号未绑定，`model.omni.api_key` 为空。

同步更新：

- `index.md`
- `02-deploy/deployment-guide.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增 Windows 部署故障排除矩阵

新增：

- `02-deploy/Windows部署故障排除矩阵.md`

目的：

- 把 <windows-sample-host> 实战中出现的 WSL、SSH、代理、端口、OpenClaw、账号、模型和摄像头问题整理成按现象查询的排障矩阵。
- 避免用户只看长教程时无法快速从报错定位修复路径。

同步更新：

- `index.md`
- `02-deploy/deployment-guide.md`
- 全局 `00 目录树.md`

远端状态：

- Miloco health 正常。
- OpenClaw gateway running。
- 小米账号仍未绑定。
- MiMo API Key 仍为空。

## 2026-06-22 新增 Windows/WSL 预检验收脚本

新增：

- `02-deploy/scripts/README.md`
- `02-deploy/scripts/windows-preflight.ps1`
- `02-deploy/scripts/wsl-miloco-validate.sh`

目的：

- 将 Windows + WSL 部署 Miloco 的宿主预检、WSL 服务验收、OpenClaw 插件检查、账号/模型/设备/摄像头满血判断脚本化。
- 让其他 Windows 玩家可以复制脚本直接采集环境证据，而不是只靠人工照教程逐条判断。

<windows-sample-host> 实跑结果：

- Windows 侧：`BASIC_READY_FROM_WINDOWS=yes`，`FAIL_COUNT=0`，`WARN_COUNT=0`。
- WSL 侧：`BASIC_READY=yes`，`FULL_READY=no`，`PASS_COUNT=11`，`WARN_COUNT=5`，`FAIL_COUNT=0`。
- 满血缺口仍为小米账号未绑定、MiMo/Omni API Key 为空、设备列表只有表头、摄像头 scope 为空。

同步更新：

- `index.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署预检与验收清单.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 10:00 <windows-sample-host> MiMo 视觉模型配置

结果：

- 配置 Miloco `model.omni.model=mimo-v2.5`。
- 配置 Miloco `model.omni.base_url=https://token-plan-sgp.xiaomimimo.com/v1`。
- 写入 Miloco `model.omni.api_key=<MIMO_API_KEY>`。
- 验证 `/v1/models` 包含 `mimo-v2.5` 和 `mimo-v2.5-pro`；其中 `mimo-v2.5` 用于视觉，`mimo-v2.5-pro` 不用于 `model.omni`。
- 重启 Miloco 后远端验收：`BASIC_READY=yes`、`FULL_READY=no`、`FAIL_COUNT=0`、`miloco.omni_api_key=PASS configured`。
- 生成报告 `02-deploy/reports/windows-sample-host-20260622-100030-model-configured.txt`。
- 小米 OAuth 授权链接已通过 PowerShell `-EncodedCommand` 尝试拉起，直接 `Start-Process '<url>'` 会被 `&` 拆坏。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>部署完成度审计.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`
- `02-deploy/<windows-sample-host>后授权收尾Runbook.md`
- `02-deploy/scripts/win-miloco-workflow.ps1`
- `常用SSH信息/<windows-sample-host>/README.md`
- `常用SSH信息/<windows-sample-host>/connection.yaml`
- 全局 `00 目录树.md`

资料包：

- 已重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`。
- 新 zip SHA256：`BD751CD9DD1CB948C02F1D5B98F126A2734DAFFAEFDABDA6641D732D990099AC`。
- 验收通过：`SHA_TOTAL=22`，`SHA_FAIL=0`，`FILE_COUNT=23`，`DOC_COUNT=16`，`SCRIPT_COUNT=5`。
- `win-miloco-workflow.ps1` SHA256：`491F198F0AAC57851A53FCF5CF63648593A6B91FF1913F11D13B11A48598A02F`。

## 2026-06-22 10:11 <windows-sample-host> OAuth 入口兜底

结果：

- 刷新小米 OAuth URL。
- 已通过 PowerShell `-EncodedCommand` 拉起授权页，避免 URL 中 `&` 被 Windows OpenSSH shell 拆分。
- 已在 <windows-sample-host> 桌面创建：
  - `C:\Users\<user>\Desktop\miloco-xiaomi-oauth.url`
  - `C:\Users\<user>\Desktop\miloco-xiaomi-oauth.txt`
- 生成报告 `02-deploy/reports/windows-sample-host-20260622-101157-oauth-ready.txt`。
- 复核状态：`BASIC_READY=yes`、`FULL_READY=no`、`FAIL_COUNT=0`、`miloco.omni_api_key=PASS configured`、`account.is_bound=false`。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`
- 全局 `00 目录树.md`

## 2026-06-22 04:58 官方对齐复核后重建资料包

结果：

- 复核当前源码仓库官方入口：`README.zh.md`、`scripts/install-guide.md`、`knowledge/06-dev-guide/dev-guide.md`、`knowledge/06-dev-guide/troubleshooting.md`。
- 更新 `02-deploy/官方部署流程对齐核查.md` 到 04:57 报告。
- 更新 `02-deploy/<windows-sample-host>部署完成度审计.md` 的当前报告引用到 `reports/windows-sample-host-20260622-045716-report.txt`。
- 重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`。
- 新 zip SHA256：`8D8B6137B17718CC9F5ED160A30E0E38A59FBBBCEF0E5FA98997FD9E84DBC63E`。
- 验收通过：`SHA_TOTAL=22`，`SHA_FAIL=0`，`FILE_COUNT=23`，`DOC_COUNT=16`，`SCRIPT_COUNT=5`。

同步更新：

- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/Windows部署资料包验收记录.md`
- `02-deploy/<windows-sample-host>部署实录.md`

## 2026-06-22 05:03 <windows-sample-host> 授权前无变化复核

结果：

- 生成报告 `02-deploy/reports/windows-sample-host-20260622-050326-report.txt`。
- 远端仍为 `BASIC_READY=yes`，`FULL_READY=no`，`FAIL_COUNT=0`。
- Miloco/OpenClaw/OpenClaw 插件基础链路稳定。
- 小米账号仍未绑定，MiMo/Omni API Key 仍为空。
- 因状态无实质变化，本轮不重建分发资料包。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增后授权一键收尾脚本

新增：

- `02-deploy/scripts/wsl-post-auth-finish.sh`

目的：

- 收到小米 OAuth payload 和 MiMo API Key 后，用一个脚本完成账号授权、Omni 模型配置、Miloco/OpenClaw 重启、家庭/设备/摄像头检查和满血验收。
- 减少远程 SSH 中复杂引号、管道、环境变量嵌套造成的执行错误。

<windows-sample-host> 实跑：

- 已上传到 `C:\Users\<user>\AppData\Local\Temp\wsl-post-auth-finish.sh`。
- `--help` 执行正常。
- `--print-bind-url` 已生成最新小米 OAuth 绑定链接。

最新绑定链接：

```text
<XIAOMI_OAUTH_URL>
```

同步更新：

- `02-deploy/scripts/README.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署预检与验收清单.md`
- `02-deploy/<windows-sample-host>后授权收尾Runbook.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增 Windows 统一入口脚本

新增：

- `02-deploy/scripts/win-miloco-workflow.ps1`

目的：

- 将 Windows 宿主预检、WSL/Miloco/OpenClaw 验收、小米 OAuth 链接生成、后授权收尾统一到一个 PowerShell 入口。
- 让 Agent 一键版和人工手动版都能用同一套 `-Action` 口径执行。

<windows-sample-host> 实跑：

- 已上传到 `C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1`。
- `-Action AllBasic` 返回 `BASIC_READY_FROM_WINDOWS=yes`、`BASIC_READY=yes`、`FULL_READY=no`。
- `-Action BindUrl` 成功生成小米 OAuth 授权链接。

本次修正：

- 避免在 PowerShell 脚本中把 `$args` 当普通变量使用。
- 避免把子脚本 stdout 捕获进变量导致 WSL 验收输出消失。
- 避免数组字面量在函数参数绑定时被错绑到下一个参数。

同步更新：

- `02-deploy/scripts/README.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署预检与验收清单.md`
- `02-deploy/Windows部署教程-Agent一键版.md`
- `02-deploy/Windows部署教程-人工手动版.md`
- `02-deploy/Agent一键部署提示词.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增 Windows 部署决策树

新增：

- `02-deploy/Windows部署决策树.md`

目的：

- 将 <windows-sample-host> 的实战路径抽象成 Windows 玩家可按状态选择下一步的部署决策树。
- 覆盖 WSL、WSL2、mirrored networking、代理、官方 installer、端口冲突、OpenClaw、账号、MiMo Key、设备和摄像头分支。
- 与 `Windows部署故障排除矩阵.md` 分工：决策树负责“下一步跑什么”，矩阵负责“看到具体报错怎么修”。

同步更新：

- `index.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署教程-Agent一键版.md`
- `02-deploy/Windows部署教程-人工手动版.md`
- `02-deploy/Agent一键部署提示词.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增满血验收证据清单

新增：

- `02-deploy/Windows满血验收证据清单.md`

目的：

- 定义最终交付时的证据标准。
- 区分基础服务就绪和满血就绪。
- 排除常见假阳性：`health ok`、`Runtime: running`、`Status: loaded`、`BASIC_READY=yes` 不能单独证明满血。

<windows-sample-host> 当前证据：

- 已证明：`BASIC_READY_FROM_WINDOWS=yes`、`BASIC_READY=yes`
- 未证明：`FULL_READY=yes`
- 当前缺口：`is_bound=false`、`model.omni_api_key empty`、设备列表只有表头、摄像头 `data=[]`

同步更新：

- `index.md`
- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署教程-Agent一键版.md`
- `02-deploy/Windows部署教程-人工手动版.md`
- `02-deploy/Agent一键部署提示词.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增一键诊断报告

更新：

- `02-deploy/scripts/win-miloco-workflow.ps1` 新增 `-Action Report`
- 新增报告目录：`02-deploy/reports/`
- 新增报告留档：`02-deploy/reports/windows-sample-host-20260622-035220-report.txt`

目的：

- 用一个命令采集 Windows 宿主预检、WSL/Miloco/OpenClaw 验收和汇总退出码。
- 让其他 Windows 玩家遇到部署问题时，可以直接把报告发给 Agent 或人工排查。

<windows-sample-host> 实跑结果：

- `BASIC_READY_FROM_WINDOWS=yes`
- `BASIC_READY=yes`
- `FULL_READY=no`
- `PreflightExitCode=0`
- `ValidateExitCode=0`

实现修正：

- `Start-Transcript` 对 WSL/native 子进程输出记录不完整。
- `Tee-Object` 在 Windows PowerShell 5 中追加文件会混入 UTF-16LE，导致 OB 中出现 NUL 字符。
- 最终改为子进程输出逐行 `Write-Host`，并用 `Out-File -Encoding UTF8 -Append` 写入报告。
- OB 留档报告已确认可检索关键状态行，编码正常。

同步更新：

- `02-deploy/scripts/README.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署决策树.md`
- `02-deploy/Windows部署教程-Agent一键版.md`
- `02-deploy/Windows部署教程-人工手动版.md`
- `02-deploy/Agent一键部署提示词.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增 Windows 部署总入口

新增：

- `02-deploy/Windows部署总入口.md`

目的：

- 为第一次部署 Windows 部署 Miloco 的用户提供“先看这里”的入口页。
- 串联诊断报告、Agent 一键版、人工手动版、决策树、故障矩阵、后授权收尾和最终满血验收。
- 明确 `BASIC_READY` 和 `FULL_READY` 的区别，减少误判部署完成。

同步更新：

- `index.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署教程-Agent一键版.md`
- `02-deploy/Windows部署教程-人工手动版.md`
- `02-deploy/Agent一键部署提示词.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增官方部署流程对齐核查

新增：

- `02-deploy/官方部署流程对齐核查.md`

目的：

- 回到源码仓库核查 README、`scripts/install-guide.md`、`scripts/install.sh`、`scripts/install.py`、`scripts/install.ps1`，确认 Windows 教程和 <windows-sample-host> 实机路径没有偏离官方流程。
- 把官方默认流程和 <windows-sample-host> 的 Windows/WSL 适配拆开记录，避免后续把端口 `1886`、用户目录 Node、外层验收脚本等实机 workaround 写成官方默认步骤。

核查结论：

- 官方仍要求 Windows 在 WSL 内安装，不支持原生 Windows。
- 官方 Agent 流程仍是 `--agent-prepare` → 用户按顺序提供账号授权和模型 API Key → `--agent-finish`。
- 当前 <windows-sample-host> 是基础服务和 OpenClaw 插件就绪，仍等待小米 OAuth payload 和 MiMo API Key 才能进入满血验收。

同步更新：

- `index.md`
- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署教程-Agent一键版.md`
- `02-deploy/Windows部署教程-人工手动版.md`
- `02-deploy/Agent一键部署提示词.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 04:04 <windows-sample-host> 状态复核

执行：

- `win-miloco-workflow.ps1 -Action AllBasic`
- `win-miloco-workflow.ps1 -Action BindUrl`

结果：

- Windows 侧：`BASIC_READY_FROM_WINDOWS=yes`，`FAIL_COUNT=0`，`WARN_COUNT=0`。
- WSL 侧：`BASIC_READY=yes`，`FULL_READY=no`，`PASS_COUNT=11`，`WARN_COUNT=5`，`FAIL_COUNT=0`。
- Miloco 仍运行在 `http://127.0.0.1:1886/`。
- OpenClaw Gateway 仍 running，`miloco-openclaw-plugin` 仍 loaded。
- 当前缺口仍是小米账号未绑定、MiMo/Omni API Key 为空、设备列表只有表头、摄像头 scope 为空。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`

## 2026-06-22 新增 <windows-sample-host> 授权阶段用户操作卡片

新增：

- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`

目的：

- 在基础服务已经就绪、等待用户授权的状态下，给用户一个最短可执行入口。
- 明确用户只需要提供小米 OAuth payload 和 MiMo API Key。
- 明确 Agent 收到后执行 `win-miloco-workflow.ps1 -Action Finish`，并以 `FULL_READY=yes` 作为满血交付标准。

同步更新：

- `index.md`
- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 补强任意 Windows 场景教程

更新：

- `02-deploy/Windows部署教程-Agent一键版.md`
- `02-deploy/Windows部署教程-人工手动版.md`
- `02-deploy/Windows部署决策树.md`
- `02-deploy/Windows部署故障排除矩阵.md`
- `02-deploy/scripts/README.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`
- `02-deploy/<windows-sample-host>部署实录.md`

目的：

- 让教程覆盖没有 WSL、旧系统 `wsl --install` 不支持、SSH 用户和 WSL 用户归属不一致、账号/Key 未提供只能基础就绪等常见 Windows 情况。
- 明确官方 `--agent-finish` 满血路径应带 `--account-auth` 和 `--omni-api-key`。
- 修正远程复制脚本时的 Windows OpenSSH `scp` 路径写法。

<windows-sample-host> 04:09 复核：

- `BASIC_READY_FROM_WINDOWS=yes`
- `BASIC_READY=yes`
- `FULL_READY=no`
- 当前仍等待小米 OAuth payload 和 MiMo API Key。

## 2026-06-22 04:10 新增 <windows-sample-host> 诊断报告留档

新增：

- `02-deploy/reports/windows-sample-host-20260622-041058-report.txt`

结果：

- `GeneratedAt=2026-06-22T04:10:58`
- `BASIC_READY_FROM_WINDOWS=yes`
- `BASIC_READY=yes`
- `FULL_READY=no`
- `PreflightExitCode=0`
- `ValidateExitCode=0`

说明：

- 报告已确认可检索关键状态行。
- 文件头为 UTF-8 BOM，未出现 Windows PowerShell 5 追加导致的 UTF-16/NUL 混写问题。
- 状态仍是基础就绪，等待小米 OAuth payload 和 MiMo API Key。

同步更新：

- `02-deploy/Windows部署总入口.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`
- `02-deploy/<windows-sample-host>部署实录.md`

## 2026-06-22 新增 Windows 部署教程覆盖审计

新增：

- `02-deploy/Windows部署教程覆盖审计.md`

目的：

- 将 Agent 一键版和人工手动版对主要 Windows 部署场景的覆盖情况显式列成矩阵。
- 作为后续发布/分享教程前的质量门：新增实机坑位时必须判断是否要同步更新教程、决策树、故障矩阵。

结论：

- 主要分支已覆盖：无 WSL、旧 WSL、已有发行版、WSL1、SSH 用户归属、mirrored networking、代理、长下载、1810 端口冲突、OpenClaw、账号/Key、家庭/摄像头、诊断报告和满血验收。
- 当前 <windows-sample-host> 未满血是等待用户提供小米 OAuth payload 和 MiMo API Key，不是教程缺口。

同步更新：

- `index.md`
- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 轻量远端复核和引号坑再确认

结果：

- 多层 `wsl.exe ... bash -lc "cmd && cmd | cmd"` 通过 Windows OpenSSH 执行时再次出现解析不可靠，`miloco-cli` 只打印 help。
- 分条直跑确认 Miloco `running=true`，health 返回 `{"status":"ok"}`。
- `account.is_bound=false`，`model.omni.api_key` 仍为空。

结论：

- 远端服务稳定。
- 满血仍等待小米 OAuth payload 和 MiMo API Key。
- 复杂远程命令继续采用上传脚本执行，不把 `&&`、管道和多层引号塞进 Windows OpenSSH 命令字符串。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`

## 2026-06-22 新增 Windows 部署资料包发布清单

新增：

- `02-deploy/Windows部署资料包发布清单.md`

目的：

- 把可分发给其他玩家或 Agent 的 Windows 部署资料包列清楚。
- 记录脚本清单、语法校验、SHA256、复制命令、目标机验证命令和交付口径。

校验结果：

- `windows-preflight.ps1` PowerShell 解析通过。
- `win-miloco-workflow.ps1` PowerShell 解析通过。
- `wsl-miloco-validate.sh` `bash -n` 通过。
- `wsl-post-auth-finish.sh` `bash -n` 通过。

同步更新：

- `index.md`
- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增 Windows 部署教程独立分发版

新增：

- `02-deploy/Windows部署教程-独立分发版.md`

目的：

- 提供一份脱离 Obsidian 也能阅读的一页式完整教程。
- 覆盖 Agent 一键部署、人工手动部署、WSL 准备、网络代理、官方 installer、端口冲突、OpenClaw、账号/Key、满血验收和常见误判。

同步更新：

- `index.md`
- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 生成 Windows 部署 zip 分发包

新增：

- `02-deploy/packages/easy-miloco-v0.1-windows/`
- `02-deploy/packages/easy-miloco-v0.1-windows.zip`

结果：

- zip SHA256：`1631022C74B5F0A3EC092ECC441E6B0730F84F4C50C94DB8C365F84166BFB2B8`
- 包内包含 `README.md`、`SHA256SUMS.txt`、11 个 docs 文档和 5 个 scripts 文件。
- 包内 `SHA256SUMS.txt` 已生成。

同步更新：

- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增 Windows 部署资料包验收记录

新增：

- `02-deploy/Windows部署资料包验收记录.md`

验收结果：

- `packages/easy-miloco-v0.1-windows.zip` 可解压。
- 包内 `SHA256SUMS.txt` 全部通过：`SHA_TOTAL=17`，`SHA_FAIL=0`。
- 包内文件数：`FILE_COUNT=18`。
- `windows-preflight.ps1`、`win-miloco-workflow.ps1` PowerShell 解析通过。
- `wsl-miloco-validate.sh`、`wsl-post-auth-finish.sh` `bash -n` 通过。

结论：

- 分发包完整性和脚本基础语法已验收。
- 该验收不改变 <windows-sample-host> 运行状态；当前仍是 `BASIC_READY=yes`、`FULL_READY=no`，等待小米 OAuth payload 和 MiMo API Key。

同步更新：

- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 04:24 <windows-sample-host> 远程只读复核

结果：

- Miloco `running=true`，`server.url=http://127.0.0.1:1886`。
- health 返回 `{"status":"ok"}`。
- OpenClaw Gateway `Connectivity probe: ok`。
- `miloco-openclaw-plugin` 为 `Status: loaded`。
- 小米账号仍为 `is_bound=false`。
- `model.omni.api_key` 仍为空。
- 已重新生成小米 OAuth 链接，并同步到 `<windows-sample-host>授权阶段用户操作卡片.md`。

结论：

- <windows-sample-host> 基础链路稳定。
- 当前仍等待用户提供小米 OAuth payload 和 MiMo API Key 后进入后授权收尾。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`

## 2026-06-22 04:55 Windows 部署资料包补包与 checksum 编码修复

结果：

- 重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`，纳入 `Windows部署资料包版本说明.md` 和 `<windows-sample-host>后授权收尾Runbook.md`。
- 修复 `SHA256SUMS.txt` 使用 ASCII 导致中文文件名变成 `?` 的问题；改为 UTF-8 无 BOM和正斜杠相对路径。
- 新 zip SHA256：`D38EC45C032FE7293FBA4F5D685AC4F9E23D928EF90E8890CEE6486F93271963`。
- 验收通过：`SHA_TOTAL=22`，`SHA_FAIL=0`，`FILE_COUNT=23`，`DOC_COUNT=16`，`SCRIPT_COUNT=5`。
- PowerShell 与 Bash 脚本语法烟测全部通过。

同步更新：

- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/Windows部署资料包验收记录.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>部署完成度审计.md`

## 2026-06-22 04:57 <windows-sample-host> 授权前复核

结果：

- 生成最新报告 `02-deploy/reports/windows-sample-host-20260622-045716-report.txt`。
- 远端 Miloco/OpenClaw 仍基础可用：`BASIC_READY=yes`，`FAIL_COUNT=0`。
- 满血仍未完成：`FULL_READY=no`，小米账号 `is_bound=false`，`model.omni.api_key` 为空。
- 已刷新小米 OAuth 入口；下一步仍等待用户完成授权并提供 MiMo API Key。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 新增 <windows-sample-host> 部署完成度审计

新增：

- `02-deploy/<windows-sample-host>部署完成度审计.md`

目的：

- 按原目标逐项审计当前部署完成度、证据和剩余缺口。
- 明确当前只能证明基础服务和 OpenClaw 插件就绪，不能证明满血完成。
- 固化后续完成条件：小米账号绑定、MiMo/Omni Key、设备列表、摄像头 scope 和日志缺口全部通过。

同步更新：

- `02-deploy/Windows部署总入口.md`
- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- `index.md`
- 全局 `00 目录树.md`

## 2026-06-22 重建资料包以纳入部署完成度审计

结果：

- 重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`。
- 同步更新 `02-deploy/packages/easy-miloco-v0.1-windows.zip.sha256`。
- zip SHA256：`E49611FDB6CAB3071B221D86DD7AA1F71B85540106062165E83A29083EDAE173`。
- 包内 `SHA256SUMS.txt` 验收：`SHA_TOTAL=20`，`SHA_FAIL=0`。
- 包内文件数：`FILE_COUNT=21`，其中 `DOC_COUNT=14`，`SCRIPT_COUNT=5`。
- PowerShell 和 Bash 脚本语法烟测全部通过。

同步更新：

- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/Windows部署资料包验收记录.md`
- `02-deploy/<windows-sample-host>部署实录.md`

## 2026-06-22 04:43 生成 <windows-sample-host> 最新诊断报告

新增：

- `02-deploy/reports/windows-sample-host-20260622-044254-report.txt`

结果：

- `BASIC_READY_FROM_WINDOWS=yes`
- `BASIC_READY=yes`
- `FULL_READY=no`
- `PreflightExitCode=0`
- `ValidateExitCode=0`
- `PASS_COUNT=11`
- `WARN_COUNT=5`
- `FAIL_COUNT=0`

仍存在的满血缺口：

- 小米账号 `is_bound=false`。
- `model.omni.api_key` 为空。
- `device list` 只有表头。
- `scope camera list` 返回空数组。
- 日志仍有 `多模态大模型 API Key 未配置`。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>部署完成度审计.md`
- `02-deploy/Windows满血验收证据清单.md`

## 2026-06-22 04:46 <windows-sample-host> 临时脚本一致性核对

结果：

- `win-miloco-workflow.ps1`、`windows-preflight.ps1`、`wsl-miloco-validate.sh`、`wsl-post-auth-finish.sh` 在 OB 与 <windows-sample-host> 临时目录 SHA256 完全一致。
- 远端执行 `win-miloco-workflow.ps1 -Action Validate` 成功。
- 返回 `BASIC_READY=yes`、`FULL_READY=no`、`PASS_COUNT=11`、`WARN_COUNT=5`、`FAIL_COUNT=0`。

结论：

- 后授权收尾时可以直接调用 <windows-sample-host> 临时目录脚本，不需要先重传。
- 当前仍等待小米 OAuth payload 和 MiMo API Key。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>后授权收尾Runbook.md`

## 2026-06-22 重建资料包以纳入最新 Runbook

结果：

- 重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`。
- 同步更新 `02-deploy/packages/easy-miloco-v0.1-windows.zip.sha256`。
- zip SHA256：`4E90A27B6332FA8A8184A8C41877CE929A0F92200EAC9CB24E1F3A24A3FE6EB5`。
- 包内 `SHA256SUMS.txt` 验收：`SHA_TOTAL=21`，`SHA_FAIL=0`。
- 包内文件数：`FILE_COUNT=22`，其中 `DOC_COUNT=15`，`SCRIPT_COUNT=5`。
- PowerShell 和 Bash 脚本语法烟测全部通过。

同步更新：

- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/Windows部署资料包验收记录.md`
- `02-deploy/<windows-sample-host>部署实录.md`

## 2026-06-22 新增 Windows 后授权失败排障与交付审计

新增：

- `02-deploy/Windows后授权失败排障与交付审计.md`

目的：

- 将 `Finish` 后没有一次性达到 `FULL_READY=yes` 的情况拆成基础服务、OpenClaw、账号、模型、设备、摄像头、`in_use` 多层分支。
- 记录快速采证命令和最终满血交付审计证据。
- 避免把账号、Key、设备、摄像头缺口误判为安装失败。

依据：

- 本地官方 installer 支持 `--agent-finish --account-auth '<payload>' --omni-api-key '<key>'`。
- 默认模型配置为 `xiaomi/mimo-v2.5` 与 `https://api.xiaomimimo.com/v1`。

同步更新：

- `02-deploy/Windows部署总入口.md`
- `02-deploy/deployment-guide.md`
- `02-deploy/<windows-sample-host>后授权收尾Runbook.md`
- `02-deploy/Windows部署故障排除矩阵.md`
- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- `index.md`
- 全局 `00 目录树.md`

## 2026-06-22 重建资料包以纳入后授权失败排障文档

结果：

- 重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`。
- 同步更新 `02-deploy/packages/easy-miloco-v0.1-windows.zip.sha256`。
- zip SHA256：`318CD97929B1121E18C37F43F61B21B5266011FF5076E54F72D1075CDD392817`。
- 包内 `SHA256SUMS.txt` 验收：`SHA_TOTAL=19`，`SHA_FAIL=0`。
- 包内文件数：`FILE_COUNT=20`，其中 `DOC_COUNT=13`，`SCRIPT_COUNT=5`。
- PowerShell 和 Bash 脚本语法烟测全部通过。

同步更新：

- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/Windows部署资料包验收记录.md`
- `02-deploy/<windows-sample-host>部署实录.md`

## 2026-06-22 04:37 <windows-sample-host> 授权入口刷新

结果：

- Miloco `running=true`，PID `5196`，`server.url=http://127.0.0.1:1886`。
- 小米账号仍为 `is_bound=false`，`max_enabled_cameras=4`。
- 已重新生成小米 OAuth 链接并同步到授权操作卡片。

结论：

- 基础服务仍正常。
- 仍等待用户完成 OAuth 授权并提供 MiMo API Key。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`

## 2026-06-22 04:26 重建 Windows 部署资料包

原因：

- 源文档新增了资料包验收记录和 04:24 <windows-sample-host> 远程复核内容，旧 zip 已落后。
- zip 自身 SHA256 不能写入包内副本，否则会形成自引用并改变 zip 哈希。

结果：

- 重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`。
- 新增 `02-deploy/packages/easy-miloco-v0.1-windows.zip.sha256`。
- zip SHA256：`4755FE974057AB57844AF91BD25ABE77740BB1A192EA12070DC10A74D6C6ABA1`。
- 包内 `SHA256SUMS.txt` 验收：`SHA_TOTAL=18`，`SHA_FAIL=0`。
- 包内文件数：`FILE_COUNT=19`，其中 `DOC_COUNT=12`，`SCRIPT_COUNT=5`。
- PowerShell 和 Bash 脚本语法烟测全部通过。

同步更新：

- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/Windows部署资料包验收记录.md`
- `02-deploy/<windows-sample-host>部署实录.md`
- 全局 `00 目录树.md`

## 2026-06-22 04:30 <windows-sample-host> 轻量远程复核

结果：

- Miloco `running=true`，PID `5196`，`server.url=http://127.0.0.1:1886`。
- health 返回 `{"status":"ok"}`。
- OpenClaw Gateway `Connectivity probe: ok`。
- 小米账号仍为 `is_bound=false`。
- `model.omni.api_key` 仍为空。

结论：

- 基础服务稳定。
- 当前部署仍停在后授权前，等待小米 OAuth payload 和 MiMo API Key。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`
## 2026-06-22 10:22 <windows-sample-host> 满血部署完成并重建资料包

结果：

- 收到小米 OAuth payload 并完成后授权收尾。
- <windows-sample-host> 最终验收通过：`BASIC_READY=yes`、`FULL_READY=yes`、`PASS_COUNT=16`、`WARN_COUNT=0`、`FAIL_COUNT=0`。
- 小米账号已绑定：`account.is_bound=true`，uid `250115363`，nickname `mdidb`。
- 设备列表返回 127 行。
- 摄像头 `<camera-did-desk> / <camera-desk>` 在线、`in_use=true`、`connected=true`。
- MiMo/Omni 使用 `mimo-v2.5` 和 `https://token-plan-sgp.xiaomimimo.com/v1`，日志中 `chat/completions` 返回 200 并产生 `realtime_perceive`。
- 修正 `wsl-miloco-validate.sh` 两个假阴性：设备列表超时放宽到 45 秒；历史 Key 缺失日志不再计入当前 warning。
- 重建 `02-deploy/packages/easy-miloco-v0.1-windows.zip`，zip SHA256：`E2C1D45AD4A9955A915C4310F0DBA089C113045987B22F8E4AF0D011E8A3F556`。
- 包内验收：`SHA_TOTAL=22`、`SHA_FAIL=0`、`FILE_COUNT=23`、`DOC_COUNT=16`、`SCRIPT_COUNT=5`，PowerShell/Bash 语法烟测全部通过。
- 10:28 追加严格满血复核：`wsl-miloco-validate.sh --strict-full` 退出码 0，`FULL_READY=yes`、`WARN_COUNT=0`、`FAIL_COUNT=0`。

同步更新：

- `02-deploy/<windows-sample-host>部署实录.md`
- `02-deploy/reports/windows-sample-host-20260622-102255-full-ready.txt`
- `02-deploy/reports/windows-sample-host-20260622-102854-strict-full.txt`
- `02-deploy/<windows-sample-host>部署完成度审计.md`
- `02-deploy/<windows-sample-host>授权阶段用户操作卡片.md`
- `02-deploy/Windows部署总入口.md`
- `02-deploy/Windows满血验收证据清单.md`
- `02-deploy/Windows部署教程覆盖审计.md`
- `02-deploy/官方部署流程对齐核查.md`
- `02-deploy/Windows部署预检与验收清单.md`
- `02-deploy/Windows部署资料包发布清单.md`
- `02-deploy/Windows部署资料包验收记录.md`
- `02-deploy/scripts/wsl-miloco-validate.sh`
- 全局 `00 目录树.md`
