# 测试指南

## 测试原则

按改动面选择最小但有效的测试集：

- Python 后端或 MIoT：跑 backend workspace pytest。
- CLI 命令：跑 CLI pytest，必要时补后端相关测试。
- Web：先 typecheck，再 vitest，再 build。
- OpenClaw 插件：先 TypeScript check，再 vitest，再 build。
- 安装和发布路径：至少跑 `bash scripts/install.sh -h`，重大改动再跑 dev build 或安装烟测。

## 本地测试矩阵

### 后端和 MIoT

```bash
cd C:/Users/17239/Desktop/xiaomi-miloco/backend
uv sync --all-packages
uv run pytest -v
uv run ruff check .
```

可选：

```bash
uv run task check
uv run task lint
```

关注点：

- `backend/miloco/tests` 覆盖主服务、感知、规则、任务、身份、SSE、配置、repo。
- `backend/miot/tests` 覆盖 MIoT client、cloud、camera、LAN、MIPS、spec。
- 音视频相关测试可能依赖 ffmpeg 或平台能力，CI 会安装 ffmpeg。

### CLI

```bash
cd C:/Users/17239/Desktop/xiaomi-miloco/cli
uv sync
uv run pytest -v
```

关注点：

- 命令注册和参数。
- config/env override。
- doctor 对 WSL、网络、服务状态的诊断。
- client 和输出格式。

### Web

```bash
cd C:/Users/17239/Desktop/xiaomi-miloco/web
pnpm install --frozen-lockfile
pnpm typecheck
pnpm test
pnpm build
```

关注点：

- API 契约和 `apiFetch` 错误处理。
- i18n、时间格式、性能图表数据桶。
- build 是否能生成生产产物。

### OpenClaw 插件

```bash
cd C:/Users/17239/Desktop/xiaomi-miloco/plugins/openclaw
pnpm install --frozen-lockfile
pnpm check
pnpm test
pnpm build
```

关注点：

- plugin config schema。
- hooks/prompt/trace。
- backend service client。
- home-profile habit suggestion。
- tool 和 webhook 行为。

## CI 对齐

CI workflow：`.github/workflows/ci.yml`

CI 作业：

- `workflow-sanity`：检查 workflow YAML 不含 tab 缩进。
- `backend-test`：`cd backend && uv sync --all-packages && uv run pytest -v`。
- `cli-test`：`cd cli && uv sync && uv run pytest -v`。
- `plugin-test`：`cd plugins/openclaw && pnpm install --frozen-lockfile && pnpm test`。
- `web-test`：`pnpm typecheck`、`pnpm test`、`pnpm build`。
- `lint`：backend 环境跑 ruff，插件跑 `pnpm check`。

安装烟测 workflow：`.github/workflows/install-smoke.yml`

- 在干净 Ubuntu 容器中跑 `bash scripts/install.sh -h`。
- 只验证 bootstrap 和入口，不覆盖账号绑定、模型配置、模型下载等交互阶段。

## 改动到测试的映射

| 改动区域 | 必跑 | 视情况加跑 |
| --- | --- | --- |
| `backend/miloco/src/miloco/main.py`、middleware、路由 | backend pytest | Web build，CLI 相关命令 |
| 感知 pipeline、identity、omni | backend pytest | 选跑对应 `backend/miloco/tests/perception` 子目录 |
| SQLite repo、schema、配置 | backend pytest | CLI config 或 Web API 测试 |
| `backend/miot` | backend pytest | 真实设备 smoke，由人工或本机环境验证 |
| `cli/src/miloco_cli` | CLI pytest | 后端服务 smoke |
| `web/src` | Web typecheck/test/build | 后端 API smoke |
| `plugins/openclaw/src` | plugin check/test/build | OpenClaw gateway 手动验证 |
| `scripts/install*`、`scripts/build.sh` | `bash scripts/install.sh -h` | `bash scripts/install.sh --dev` 或 release smoke |
| `.github`、`.ci` | 本地等价命令 | workflow 手动触发 |

## 部署验收 smoke

在已安装环境：

```bash
miloco-cli service start
miloco-cli service status
miloco-cli doctor
miloco-cli config show
miloco-cli account status
```

浏览器：

- 打开 `http://127.0.0.1:1810/`。
- 验证模型页、账号绑定页、概览页能加载。
- 有摄像头时，验证开启感知后的实时画面和事件流。

OpenClaw：

- 确认插件安装。
- `openclaw gateway restart` 后发起一次设备查询或通知相关能力。
