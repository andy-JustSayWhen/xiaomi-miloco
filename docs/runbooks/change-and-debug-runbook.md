# 变更和排障手册

## 先分层

遇到问题先判断它属于哪一层：

| 症状 | 优先检查 |
| --- | --- |
| 页面打不开 | 后端服务、1810 端口、SPA static、token 注入 |
| API 401 | `server.token`、前端 `window.__MILOCO_TOKEN__`、Bearer header |
| API 404 | 路由前缀、`/api/*` 是否被 SPA fallback 绕过 |
| 设备列表为空 | 小米账号绑定、MIoT token、MIoT refresh、网络 |
| 摄像头无画面 | WSL mirrored networking、Hyper-V 防火墙、摄像头局域网流、后端 WS |
| 感知不触发 | scope camera、感知配置、Gate、模型 key、日志 |
| Agent 没反应 | OpenClaw 插件安装、gateway restart、plugin config、webhook |
| CLI 无法连后端 | `$MILOCO_HOME/config.json`、server URL、服务状态 |

## 最小定位链

### 服务层

```bash
miloco-cli service status
miloco-cli service logs -f
miloco-cli doctor
```

如需前台看日志：

```bash
cd C:/Users/<user>/Desktop/xiaomi-miloco/backend
uv run miloco-backend
```

### Web 层

1. 打开 `http://127.0.0.1:1810/health`。
2. 打开 `http://127.0.0.1:1810/`。
3. 浏览器 Network 看 `/api/*` 是否带 Authorization。
4. 如果是静态资源 404，看 `web/dist` 和后端 static 打包路径。

### 配置层

```bash
miloco-cli config show
miloco-cli config get model.omni.api_key
```

源码默认值在 `backend/miloco/src/miloco/config/settings.yaml`，真实运行配置在 `$MILOCO_HOME/config.json`。

### OpenClaw 插件层

```bash
miloco-cli service start
openclaw gateway restart
```

检查：

- 插件是否安装。
- 插件配置是否覆盖了后端 URL 或 token。
- `/miloco/webhook` 是否能被 gateway 路由。
- Agent tool 名称是否在允许列表中。

## 改代码前的定位顺序

1. 用 CodeGraph 查入口、调用方、影响面。
2. 读最小源码文件，确认真实路径。
3. 找对应测试。
4. 做最小改动。
5. 跑与改动面匹配的测试。
6. 如果改了部署或测试方法，同步更新本 Obsidian。

## 常见设计约束

- 后端单 worker 是设计约束，不是待优化项。
- 后端 HTTP 是设计约束，TLS 放在反向代理层。
- Web 生产入口是后端同端口，不要默认恢复独立 mock 通道。
- Windows 原生安装不支持，Windows 部署路径应使用 WSL。
- 能拿到 SPA 根页面就能拿到后端 token，局域网暴露前要确认信任边界。

## 回滚和记录

任何修复后都记录：

- 症状是什么。
- 实际失败层是哪一层。
- 证据来自哪里：命令、日志、浏览器 Network、源码路径。
- 改了哪些源码文件或配置。
- 跑了哪些测试。
- 是否需要更新 `02-deploy` 或 `03-test`。

结构性经验写回本文件；一次性日志不进入 Obsidian。
