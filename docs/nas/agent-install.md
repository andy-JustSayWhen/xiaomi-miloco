# NAS Agent Docker 部署

本文是 NAS 子指南。Agent 从 `docs/install-guide.md` 路由到 NAS 后，先读 [index.md](index.md) 的硬门槛；满足后按本文执行 Docker Compose 部署。

## 硬规则

1. 默认使用 Docker Compose bridge 网络并映射 `1810`、`18789`，让 NAS 面板快速访问能列出 Miloco 面板和 OpenClaw 对话页。
2. 先预检，再启动；不要重复开多个安装容器。
3. 不把 `.env`、授权 payload、API Key、日志、`data/`、`backups/` 写进 git。
4. 账号授权和模型配置缺失时，只能报告基础安装就绪，不能报告 FULL_READY。
5. 每次更新或卸载前先执行 `./manage.sh backup`。
6. 默认使用在线镜像；不要让普通 NAS 用户现场 build。只有维护者调试才设置 `EASY_MILOCO_BUILD=1`。

## 文件入口

```text
nas/docker/
├── .env.example
├── compose.build.yaml
├── Dockerfile
├── README.md
├── compose.yaml
├── entrypoint.sh
└── manage.sh
```

## Agent 执行流程

```bash
cd nas/docker
./manage.sh preflight
cp -n .env.example .env
```

如果 Docker socket 权限不足，`manage.sh` 会自动尝试 `sudo docker`。Agent 有可用 SSH 密码时直接输入，不要让部署卡在权限提示。

如果用户已经提供模型和账号授权，写入 `.env`：

```text
MILOCO_ACCOUNT_AUTH=<小米授权 payload>
OMNI_API_KEY=<API Key>
OMNI_BASE_URL=<Base URL>
OMNI_MODEL=<模型名>
```

启动：

```bash
./manage.sh start
./manage.sh logs
```

如果镜像拉取卡住，停止当前 compose 进程并清理本轮测试产物，不要重复开多个构建。处理顺序：

```bash
# 国内 x86_64 NAS 推荐：华为 SWR
EASY_MILOCO_IMAGE=swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5 ./manage.sh start

# Docker Hub 官方发布源
EASY_MILOCO_IMAGE=docker.io/andywu114/easy-miloco-nas:v0.5 ./manage.sh start

# 毫秒镜像 Docker Hub 通道，当前链路不稳定，仅作备用
EASY_MILOCO_IMAGE=docker.1ms.run/andywu114/easy-miloco-nas:v0.5 ./manage.sh start

# 如果有可达镜像仓库或内网镜像
EASY_MILOCO_IMAGE=<registry>/<repo>/easy-miloco-nas:v0.5 ./manage.sh start

# 只有维护者调试才允许现场构建
EASY_MILOCO_BUILD=1 ./manage.sh start
```

验收：

```bash
./manage.sh status
./manage.sh validate
./manage.sh urls
```

`./manage.sh urls` 必须作为交付地址来源；裸 `18789` 是公开代理入口，应自动跳转到带 token 的 OpenClaw 对话页，避免让用户猜登录凭证。

如果 `docker compose pull` 成功但日志仍出现旧的 `WSL Miloco validation`、`OpenClaw 直达: http://172...` 或模型缺失，说明 NAS 镜像源命中了旧 tag 缓存。立即切换到上面的 digest 镜像，不要继续重复拉裸 `v0.5` tag。

容器列表中应看到容器名 `miloco`；快速访问里应出现两个端口：

- `1810`：Miloco 面板
- `18789`：OpenClaw 对话页

NAS 默认 `OPENCLAW_BIND=auto`、`OPENCLAW_AUTH=token`、`OPENCLAW_INTERNAL_PORT=18790`。公开端口 `18789` 由容器内代理接管，自动跳转到带 token 的 OpenClaw 对话页；不要把 `18790` 映射给普通用户。局域网 HTTP 部署必须确认 OpenClaw Control UI 已配置 `allowInsecureAuth`、`dangerouslyDisableDeviceAuth` 和 Host header 同源回退，否则浏览器会停在安全上下文/设备身份页面。

## 交付口径

必须报告：

- Miloco 面板地址
- OpenClaw 对话地址
- `BASIC_READY` / `FULL_READY`
- 如果 `FULL_READY=no`，列出缺口：账号、模型、设备、摄像头、OpenClaw 插件中的哪一项缺失
- 日志入口：`./manage.sh logs`
- 控制入口：`./manage.sh restart`、`./manage.sh stop`、`./manage.sh update`

## 当前 v0.5 限制

当前公开 v0.5 release 尚未包含独立 NAS zip。入口脚本会优先找 NAS zip；`x86_64/amd64` NAS 可临时回退 Windows 包内的 Linux payload。`aarch64/arm64` NAS 需要发布包含 `linux-aarch64` runtime 的 NAS zip，或在 `.env` 里填写 `MILOCO_RELEASE_ZIP_URL`。
