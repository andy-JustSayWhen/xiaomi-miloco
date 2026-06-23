# 源码地图

源码根目录：`C:\Users\<user>\Desktop\xiaomi-miloco`

本页只记录“去哪里看”和“改动后测什么”，不复制源码。

## 模块总览

| 模块 | 主要职责 | 关键路径 | 变更后优先验证 |
| --- | --- | --- | --- |
| 后端主服务 | FastAPI、SPA 托管、配置、鉴权、感知、规则、任务、档案、观测 | `backend/miloco/src/miloco` | `cd backend && uv run pytest -v` |
| MIoT SDK | 小米账号、设备、场景、局域网、MIPS、摄像头流 | `backend/miot/src/miot` | `cd backend && uv run pytest -v` |
| CLI | 服务管理、账号绑定、设备控制、配置、doctor、任务和身份命令 | `cli/src/miloco_cli` | `cd cli && uv run pytest -v` |
| Web 面板 | 家庭面板、API client、成员/设备/任务/用量/性能页面 | `web/src` | `cd web && pnpm typecheck && pnpm test && pnpm build` |
| OpenClaw 插件 | 注册 Agent hooks、services、webhooks、tools、home-profile 建议 | `plugins/openclaw/src` | `cd plugins/openclaw && pnpm check && pnpm test && pnpm build` |
| 安装和发布脚本 | 构建、安装、manifest、OpenClaw 配置、远端同步 | `scripts` | `bash scripts/install.sh -h`，必要时跑 dev build |
| CI 和安全扫描 | 测试矩阵、依赖准入、OpenGrep、CodeQL、release | `.github/workflows`、`.ci` | 与对应 workflow 命令对齐 |
| 项目内知识库 | 原仓库自带架构/设计/开发文档 | `knowledge` | 作为事实线索，不直接照搬到本 Obsidian |

## 后端主服务

入口：

- `backend/miloco/src/miloco/main.py`
- `backend/miloco/src/miloco/manager.py`
- console script：`miloco-backend = miloco.main:start_server`

关键事实：

- 后端是单实例 daemon。`start_server` 对 `workers != 1` 明确拒绝。
- 后端永远以 HTTP 启动。跨网 TLS 应在 nginx、Cloudflare Tunnel 等反向代理层终结。
- 默认服务入口是 `http://127.0.0.1:1810/`。
- SPA 根路由会把 `server.token` 注入 HTML，能访问根页面的网络位置等价于能拿到 API token。

关键子域：

- 配置：`config/settings.py`、`config/settings.yaml`
- SQLite 和仓储：`database/connector.py`、`database/*_repo.py`
- 感知：`perception/collect`、`perception/engine`、`perception/processor.py`
- MIoT 后端适配：`miot/service.py`、`miot/router.py`、`miot/ws.py`
- 人员和身份：`person/router.py`、`perception/engine/identity`
- 规则：`rule/router.py`、`rule/service.py`、`rule/runner.py`
- 任务和任务记录：`task`、`task_record`
- 家庭档案：`home_profile`
- 观测和健康：`observability`、`node_monitor`
- 每次运行性能报告：`observability/performance_report.py` 生成 Markdown；`observability/performance_report_router.py` 暴露 `/api/performance-reports`；Web 面板入口在 `web/src/components/PerformanceReportsPage.tsx`。

## MIoT SDK

入口和职责：

- `backend/miot/src/miot/client.py`：SDK client 聚合。
- `backend/miot/src/miot/cloud.py`：云端接口。
- `backend/miot/src/miot/lan.py`：局域网能力。
- `backend/miot/src/miot/camera.py`：摄像头相关能力。
- `backend/miot/src/miot/mips_cloud.py`、`mcp.py`：消息和协议集成。

原则：

- 外部 SDK、协议和云服务边界写入部署或 external-deps 类文档。
- Miloco 自己的调用方式和数据流写入 overview 或 runbook。

## CLI

入口：

- `cli/src/miloco_cli/main.py`
- console script：`miloco-cli = miloco_cli.main:main`

命令模块：

- `commands/service.py`：服务 start/stop/status/logs。
- `commands/account.py`：小米账号绑定。
- `commands/config.py`：配置读写。
- `commands/device.py`：设备列表和控制。
- `commands/doctor.py`：环境和网络诊断。
- `commands/identity.py`、`person.py`：人员和身份注册。
- `commands/rule.py`、`task.py`：规则和任务。

## Web

入口：

- `web/src/main.tsx`
- `web/src/App.tsx`
- API 统一出口：`web/src/api/index.ts`
- 实际 backend client：`web/src/api/real.ts`、`web/src/api/client.ts`
- Vite 配置：`web/vite.config.ts`

关键事实：

- 默认接后端，不保留 mock 数据通道。
- 生产面板由后端同端口提供。
- API token 来自后端 HTML 注入的 `window.__MILOCO_TOKEN__`，fetch 自动带 Bearer。
- `vite dev` 代理能力仍在配置里，但当前常规开发入口以 backend 1810 为准。

## OpenClaw 插件

入口：

- `plugins/openclaw/src/index.ts`
- `plugins/openclaw/openclaw.plugin.json`

注册面：

- hooks：`src/hooks/index.ts`、`src/hooks/prompt.ts`、`src/hooks/trace.ts`
- services：`src/services/index.ts`
- webhooks：`src/webhooks/index.ts`，路由 `/miloco/webhook`
- tools：`src/tools/notify.ts`
- home profile：`src/home-profile`
- 配置：`src/config.ts`、`src/miloco/config.ts`

Agent 侧能力以插件 README 和 manifest 为准，常见能力包括设备、感知、身份、管理、任务创建、任务终止、通知。
