# NAS Docker 部署

本文是 NAS 的 Docker Compose 部署说明。先确认 [index.md](index.md) 的硬门槛；不满足系统、架构、网络条件时不要继续。

## 能不能 YAML 一键部署

可以，但分两档：

| 档位 | 条件 | 结果 |
| --- | --- | --- |
| 基础一键 | 只运行 `compose.yaml` | 自动创建容器、下载安装器、安装 Miloco/OpenClaw、启动基础服务 |
| 完整一键 | `.env` 已有 `MILOCO_ACCOUNT_AUTH`、`OMNI_API_KEY`、`OMNI_BASE_URL`、`OMNI_MODEL` | 自动完成账号、模型、插件、服务启动和基础验收 |

YAML 不能公开内置小米账号授权和模型 API Key；这些只能由用户或 Agent 写入本机 `.env`。

## 文件

部署文件在仓库：

```text
nas/docker/
├── .env.example
├── Dockerfile
├── README.md
├── compose.yaml
├── entrypoint.sh
└── manage.sh
```

## 推荐命令

```bash
cd nas/docker
./manage.sh start
./manage.sh logs
```

当前 v0.5 release 尚未包含独立 NAS zip。入口脚本会优先找 NAS zip；`x86_64/amd64` NAS 可临时回退 Windows 包内的 Linux payload。`aarch64/arm64` NAS 需要发布包含 `linux-aarch64` runtime 的 NAS zip，或在 `.env` 里填写 `MILOCO_RELEASE_ZIP_URL`。

访问：

- Miloco 面板：`http://<NAS-IP>:1810/`
- OpenClaw 对话：`http://<NAS-IP>:18789/`

## 网络规则

默认使用：

```yaml
network_mode: host
```

这是摄像头场景的默认选择。不要先改成 bridge 网络；如果改成 bridge 后摄像头实时画面或持续感知不可用，先恢复 host 网络再排查。

Miloco 后端在容器内默认监听 `0.0.0.0:1810`；OpenClaw 默认 `OPENCLAW_BIND=lan`。如果只允许 NAS 本机访问，把 `.env` 里的 `OPENCLAW_BIND` 改成 `loopback`。

## 数据和隐私

- 持久目录：`nas/docker/data/`
- 本机环境变量：`nas/docker/.env`
- 不提交 `.env`、`data/`、授权 payload、API Key、日志和个人环境信息。

## 常用控制

```bash
./manage.sh urls
./manage.sh status
./manage.sh logs
./manage.sh validate
./manage.sh restart
./manage.sh stop
```

补齐 `.env` 后，执行 `./manage.sh restart`。入口脚本有安装标记，不会在普通重启时无脑重复安装。

`./manage.sh urls` 会优先从容器里的 OpenClaw 生成可直接打开的登录入口；如果 OpenClaw 还没启动，才显示普通地址。

更新或卸载前：

```bash
./manage.sh backup
./manage.sh update
./manage.sh uninstall
```
