# Huawei SWR Docker Image Runbook

用途：给维护者和 Agent 使用，说明如何把 NAS Docker 镜像自动上传到华为云 SWR，并维护公开给国内 NAS 用户拉取的镜像。

本文不保存华为云账号、AK/SK、登录密码、临时登录指令或 GitHub Secrets 值。

## 项目约定

当前国内 NAS 用户优先拉取：

```text
swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5
```

固定参数：

```text
SWR_REGION=cn-north-4
SWR_REGISTRY=swr.cn-north-4.myhuaweicloud.com
SWR_NAMESPACE=easy-miloco
SWR_REPOSITORY=easy-miloco-nas
SWR_IMAGE=swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas
```

普通用户 YAML 只写普通 tag，不写 digest：

```yaml
image: swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5
```

digest 只用于维护者校验镜像内容，不放进面向普通 NAS 用户的一键 YAML。

## 基础版边界

华为云官方当前口径：

- SWR 基础版免费，企业版收费。
- 基础版计费项包含存储空间和流量费用，目前均免费提供。
- 基础版支持镜像上传、下载、删除等生命周期管理。

维护者仍应在华为云费用中心查看账单，并设置预算或余额提醒。不要开启企业版、VPC 终端节点、OBS 企业仓库等付费链路，除非用户明确要求。

## 首次配置

在华为云控制台完成一次性设置：

1. 区域切到 `华北-北京四`。
2. 进入 `容器镜像服务 SWR`。
3. 创建组织 `easy-miloco`。
4. 创建或推送后生成仓库 `easy-miloco-nas`。
5. 仓库必须配置为普通用户可拉取的公开镜像；如果是私有仓库，普通 NAS 用户会被迫登录，不符合一键部署目标。
6. 在 SWR `总览 -> 登录指令` 复制登录指令。长期自动化只把登录指令拆出的用户名和密码放进 GitHub Secrets。

GitHub 仓库 Secrets 建议：

```text
HUAWEI_SWR_REGISTRY=swr.cn-north-4.myhuaweicloud.com
HUAWEI_SWR_NAMESPACE=easy-miloco
HUAWEI_SWR_REPOSITORY=easy-miloco-nas
HUAWEI_SWR_USERNAME=<从SWR登录指令中取得>
HUAWEI_SWR_PASSWORD=<从SWR登录指令中取得>
```

不要把完整 `docker login` 命令写进公开文档、issue、PR、commit message 或 workflow 日志。

## GitHub Actions 自动上传

当前 NAS 镜像 workflow 是 `.github/workflows/nas-docker-image.yml`。它默认推送 GHCR/Docker Hub；当仓库同时配置 `HUAWEI_SWR_*` Secrets 时，会把同一镜像额外推送到华为 SWR。

必须同时存在：

```text
HUAWEI_SWR_REGISTRY
HUAWEI_SWR_NAMESPACE
HUAWEI_SWR_REPOSITORY
HUAWEI_SWR_USERNAME
HUAWEI_SWR_PASSWORD
```

工作流会先解析 tag。如果 `HUAWEI_SWR_REGISTRY`、`HUAWEI_SWR_NAMESPACE`、`HUAWEI_SWR_REPOSITORY`、`HUAWEI_SWR_USERNAME`、`HUAWEI_SWR_PASSWORD` 缺任意一个，`swr_enabled=false`，SWR 登录与推送都会跳过。

SWR 登录步骤只在 `swr_enabled=true` 时执行：

```yaml
- uses: docker/login-action@v3
  if: steps.image_tags.outputs.swr_enabled == 'true'
  with:
    registry: ${{ secrets.HUAWEI_SWR_REGISTRY }}
    username: ${{ secrets.HUAWEI_SWR_USERNAME }}
    password: ${{ secrets.HUAWEI_SWR_PASSWORD }}
```

SWR tags 由 `Resolve image tags` 步骤追加到 `docker/build-push-action`：

```yaml
${{ secrets.HUAWEI_SWR_REGISTRY }}/${{ secrets.HUAWEI_SWR_NAMESPACE }}/${{ secrets.HUAWEI_SWR_REPOSITORY }}:${{ inputs.version || 'v0.5' }}
${{ secrets.HUAWEI_SWR_REGISTRY }}/${{ secrets.HUAWEI_SWR_NAMESPACE }}/${{ secrets.HUAWEI_SWR_REPOSITORY }}:latest
```

触发方式：

```bash
gh workflow run nas-docker-image.yml -r NAS -f version=v0.5
```

完成后必须验证：

```bash
docker manifest inspect swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5 >/dev/null
docker pull swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5
```

如果本机没有 Docker，就在 GitHub Actions 日志中确认 `push` 成功，并在 NAS 或临时 Linux 机器上跑一次 `docker pull`。

## 手动补推

只有在 Actions 未接入 SWR、或需要临时回填历史镜像时才手动补推。

```bash
VERSION=v0.5
SRC=docker.io/andywu114/easy-miloco-nas:${VERSION}
DST=swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:${VERSION}

docker pull "${SRC}"
docker tag "${SRC}" "${DST}"
docker login swr.cn-north-4.myhuaweicloud.com
docker push "${DST}"

docker tag "${SRC}" swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:latest
docker push swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:latest
```

`docker login` 使用 SWR 控制台给出的登录指令。不要在公开终端记录、文档或 PR 中贴出密码。

## 版本管理

原则：

1. 面向用户的 YAML 固定到版本 tag，例如 `v0.5`，不要用 `latest`。
2. `latest` 只给维护者快速冒烟或手动排障使用。
3. 如果同一个版本 tag 被重新构建并覆盖，必须重新做冷拉取测试，因为 NAS 端可能命中旧缓存。
4. 如果用户已经拿到旧镜像，排障时先让用户删除旧容器和旧镜像，再重新部署。
5. 新版本发布后，更新 `nas/docker/compose.ugreen-template.yaml`、`docs/nas/docker-deploy.md` 和 `nas/docker/README.md` 中的 SWR tag。

建议保留：

```text
latest
当前公开版本，例如 v0.5
上一个公开版本，例如 v0.4
```

删除旧 tag 前，确认没有文档、release note 或用户模板还指向它。

## 管理与清理

控制台路径：

```text
华为云控制台 -> 容器镜像服务 SWR -> 我的镜像 -> easy-miloco/easy-miloco-nas
```

常规检查：

- 镜像是否公开。
- `v0.5` 和 `latest` 是否存在。
- 更新时间是否匹配最近一次 Actions。
- 镜像大小是否明显异常。
- 费用中心是否出现 SWR 相关扣费。

华为云基础版有镜像仓库和镜像版本数量配额。官方文档当前写明：单个租户可推送的镜像配额为 500 个，镜像版本配额为 300 个。不要无限保留实验 tag。

## 拉取耗时验证

每次更新 SWR 镜像后，至少做一次冷拉取记录：

```bash
IMAGE=swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5

docker rm -f miloco 2>/dev/null || true
docker rmi "${IMAGE}" 2>/dev/null || true

start=$(date +%s)
docker pull "${IMAGE}"
end=$(date +%s)
echo "pull_seconds=$((end - start))"
```

记录内容：

```text
NAS型号/系统：
网络位置：
镜像：
是否冷拉取：
耗时：
是否需要登录：
是否报错：
```

目标是普通用户无需登录、无需 digest、直接用 YAML 拉取成功。

## 常见问题

### `denied: You may not login yet`

常见原因是没有执行 `docker login`，或登录的 registry 与 push 的 registry 不一致。必须确认登录域名就是：

```text
swr.cn-north-4.myhuaweicloud.com
```

### 控制台看不到推送后的镜像

先确认区域是否是 `华北-北京四`，组织是否是 `easy-miloco`，仓库名是否是 `easy-miloco-nas`。然后刷新 `我的镜像` 页面。

### 页面上传失败或很慢

不要用页面上传维护 NAS 镜像。官方文档说明页面上传更适合小镜像，且有文件数量和大小限制。NAS 镜像应走 Docker 客户端或 GitHub Actions 的 `docker push`。

### 用户 NAS 仍然拉取很慢

先确认 YAML 不是 Docker Hub 或旧镜像源：

```text
swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5
```

再让用户删除旧容器、旧镜像后重试。不要让普通用户改成 digest；digest 不能加速，只会提高 NAS 图形界面部署复杂度。

## Agent 操作清单

收到“更新 NAS 镜像”“上传到华为 SWR”“SWR 镜像管理”这类任务时：

1. 先读 `docs/AGENT.md` 和本文。
2. 检查 `.github/workflows/nas-docker-image.yml` 是否保留可选 SWR 登录和 SWR tags。
3. 检查 `nas/docker/compose.ugreen-template.yaml` 是否使用普通 SWR tag。
4. 不读取、不打印、不提交任何 SWR 登录密码。
5. 触发 Actions 或手动补推。
6. 验证 `docker manifest inspect` 和至少一次 `docker pull`。
7. 如 tag 更新，同步更新 NAS 文档和模板。
8. 报告最终镜像地址、验证方式和拉取耗时。

## 官方参考

- [推送镜像到镜像仓库](https://support.huaweicloud.com/usermanual-swr/swr_01_0011.html)
- [使用docker命令迁移镜像至SWR](https://support.huaweicloud.com/bestpractice-swr/swr_bestpractice_0012.html)
- [什么是容器镜像服务](https://support.huaweicloud.com/productdesc-swr/swr_03_0001.html)
- [查询镜像仓库列表 API](https://support.huaweicloud.com/api-swr/swr_02_0034.html)
