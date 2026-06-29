# NAS Docker 部署

默认使用 Docker Compose 和 host 网络。摄像头场景不要优先改成 bridge 网络，否则容器可能访问不到家庭局域网摄像头。

## 硬门槛

- NAS 能运行 Docker 或 Container Manager。
- CPU 是 `x86_64/amd64` 或 `aarch64/arm64`。
- 容器镜像基于 Debian bookworm，满足 Miloco Linux runtime 的 `glibc >= 2.28` 要求。
- NAS 和摄像头在同一可达局域网。

## 一键启动

```bash
cd nas/docker
./manage.sh start
./manage.sh logs
```

默认使用在线镜像，不在 NAS 上现场构建：

```bash
./manage.sh start
```

维护者调试才使用：

```bash
EASY_MILOCO_BUILD=1 ./manage.sh start
```

如果 Docker socket 权限不足，`manage.sh` 会自动尝试 `sudo docker`，按提示输入 NAS 用户密码即可。

如果 `.env` 里已经有 `MILOCO_ACCOUNT_AUTH`、`OMNI_API_KEY`、`OMNI_BASE_URL`、`OMNI_MODEL`，容器会自动跑完整安装并启动服务。

如果这些值为空，容器只完成基础安装和服务启动；补齐 `.env` 后执行：

```bash
./manage.sh restart
```

当前 v0.5 release 尚未包含独立 NAS zip。入口脚本会优先找 NAS zip；`x86_64/amd64` NAS 可临时回退 Windows 包内的 Linux payload。`aarch64/arm64` NAS 需要后续发布包含 `linux-aarch64` runtime 的 NAS zip，或在 `.env` 里指定 `MILOCO_RELEASE_ZIP_URL`。

## 访问

在 NAS 本机：

- Miloco 面板：`http://127.0.0.1:1810/`
- OpenClaw 对话：`http://127.0.0.1:18789/`

在其他电脑或手机上，把 `127.0.0.1` 换成 NAS 的局域网 IP。

也可以直接运行：

```bash
./manage.sh urls
```

`./manage.sh urls` 会优先从容器里的 OpenClaw 生成可直接打开的登录入口；如果 OpenClaw 还没启动，才显示普通地址。

## 数据目录

所有运行数据放在：

```text
nas/docker/data/
```

不要把 `data/`、`.env`、日志、授权 payload、API Key 提交到 git。

## 常用命令

```bash
./manage.sh status
./manage.sh logs
./manage.sh validate
./manage.sh restart
./manage.sh stop
```

需要重新执行安装流程：

```bash
MILOCO_FORCE_INSTALL=1 ./manage.sh start
```

更新前先备份：

```bash
./manage.sh update
```
