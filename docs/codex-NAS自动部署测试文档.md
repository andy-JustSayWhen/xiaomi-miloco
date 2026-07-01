# codex-NAS 自动部署测试文档

本文记录 Codex 通过 UGREEN NAS 图形界面做 NAS 镜像部署测试时的最短路径、确认点和本轮观察。这里不保存 API Key、Token、密码或私有配置值；本机测试密钥只放 ignored 的 `env/`。

## 固定前置

- 本机仓库：`/Users/mac/Desktop/easy-miloco`
- 分支：`NAS`
- 本机私有测试配置：`env/nas-test.env`
- UGREEN NAS App：`/Applications/UGREEN NAS.app`
- NAS 文件管理器路径：`共享文件夹 > docker`
- Docker Compose 模板：`nas/docker/compose.ugreen-template.yaml`
- NAS 数据目录按模板使用：`/volume1/docker/miloco`

## 本轮清理记录

时间：2026-07-02

1. Docker 项目中存在旧 `miloco` 项目。
2. 使用 UGREEN Docker 项目接口删除旧项目，首次清理时使用 `delImages=true`，确认本地 `easy-miloco-nas` 镜像已消失。
3. 删除 Docker 项目后，`/volume1/docker/miloco` 目录仍可能保留旧 `docker-compose.yaml`；这会让后续测试误以为配置已更新。
4. 使用文件管理接口删除 `/volume1/docker/miloco`，再检查 `HasYAMLFile` 为空，确认旧 Compose 文件已清除。

## 本轮部署记录

时间：2026-07-02

### SWR 镜像发布

1. `ef47c4e` 的自动构建只推到了 GHCR/Docker Hub；Actions 日志显示 `HUAWEI_SWR_*` secrets 为空，SWR 被跳过。
2. 已从华为 SWR 控制台长期登录指令拆出 `HUAWEI_SWR_REGISTRY`、`HUAWEI_SWR_NAMESPACE`、`HUAWEI_SWR_REPOSITORY`、`HUAWEI_SWR_USERNAME`、`HUAWEI_SWR_PASSWORD`，保存到 ignored 的 `env/huawei-swr.env`，并写入 GitHub Actions Secrets。
3. 首次重新触发 run `28544387096` 失败：SWR 拒绝 buildx 默认 manifest，报 `Invalid image, fail to parse 'manifest.json'`。
4. 修复 workflow：GHCR/Docker Hub 继续用 `docker/build-push-action`，SWR 单独用普通 `docker build --platform linux/amd64` 和 `docker push`。
5. 修复后 run `28544550660` 成功，整轮耗时 `3m2s`；SWR 步骤中 `v0.5` 和 `latest` 都返回 digest，确认镜像已推到华为 SWR。

### UGREEN 冷拉部署

1. 使用当前 `env/ugreen-compose.yaml` 从空目录创建 `miloco` 项目。
2. 镜像源：`swr.cn-north-4.myhuaweicloud.com/easy-miloco/easy-miloco-nas:v0.5`。
3. 从创建请求发出到镜像出现在 NAS 本地镜像列表：`87.0s`。
4. 从创建请求发出到项目显示 running 且 `1/1`：`92.4s`。
5. 本轮总耗时：`92.5s`；其中冷拉约占 `87.0s`，拉完到项目 running 约 `5.4s`。
6. 项目 running 后，`1810` / `18789` 并不一定立刻可访问；首次访问曾出现 `ERR_CONNECTION_REFUSED`，稍后端口恢复。
7. Miloco 面板可打开，显示米家未连接和家里暂无摄像头；未见模型“未配置”占位。
8. OpenClaw 自动打开聊天页，模型栏显示 `mimo-v2.5-pro · Off`；发送“请用一句话回复：部署测试。”后约 `11.8s` 完成回复。

### 新镜像回归复测

1. `0a2058c` 推送后，GitHub Actions run `28547124904` 成功，耗时 `2m42s`，重新发布 GHCR / Docker Hub / 华为 SWR 镜像。
2. 从零清理：删除 `miloco` 项目、关联镜像和 `/volume1/docker/miloco` 后，确认本地镜像不存在、旧 Compose 文件不存在。
3. 再次使用 SWR `v0.5` 冷拉：镜像出现在 NAS 本地镜像列表用时 `118.1s`；项目 running 用时 `122.3s`。
4. running 后两个 Web 端口又等待 `108.7s` 才都可访问；从创建项目到 `1810` / `18789` 都能打开，用户可感知总耗时约 `231.1s`。
5. Miloco 面板首页打开正常，显示米家未连接、设备为空；模型页显示 `xiaomi/mimo-v2.5`、Base URL 和已遮蔽 API Key，未再出现“未配置”占位。
6. Miloco 模型页在视觉上有一处小问题：列表行里的“当前模型”和“删除”靠得较近，自动化读取时像“当前模型删除”；不影响配置生效，但后续 UI 可优化间距。
7. OpenClaw 使用 MIMO 时显示 `mimo-v2.5-pro · Off`，发送“请用一句话回复：新镜像部署测试。”约 `18.2s` 回复。

## UI 操作注意

- 项目运行中时，“删除”菜单项不可用，需要先点“停止”。
- 删除项目弹窗默认不删除镜像；为了测真实首次拉取耗时，必须勾选“同时删除关联的镜像”。
- 删除项目不会自动删除 `/volume1/docker/miloco` 目录；从零测试前必须额外删目录，否则会残留旧 YAML。
- Docker 镜像页默认落在“镜像仓库”，确认本地残留要切到“本地镜像”。
- 搜索框过滤不是瞬时的，输入后要等列表变为空或出现匹配项。
- Compose 粘贴前必须确认系统剪贴板内容；错误粘贴时编辑器会显示 `Incorrect type. Expected "Compose Specification".`
- UGREEN 的部署弹窗会显示进度，但尾部可能长时间不刷新；不要在 1 分钟内贸然取消。
- UGREEN 从本地文件导入 YAML 偶发超时或沿用上一份内容；切换供应商测试时，更稳的方式是导入后检查编辑器里的 `OPENCLAW_CHAT_*` 行，必要时直接在编辑器内覆盖 YAML。
- 复用旧项目路径时，UGREEN 可能提示路径已存在；需要确认“导入该配置/覆盖”后再部署，否则按钮状态和实际 Compose 内容容易不同步。
- 旧镜像里 OpenClaw 请打开根地址 `http://<NAS-IP>:18789/`；直接打开历史里的 `/chat?session=main` 深链可能缺少当前 token，出现“认证不匹配”或“无法连接”。当前源码已补 `/chat` 深链自动加 token，发布新镜像后应复测。
- OpenClaw 会话会记住旧模型；换供应商重新部署后，应点“+ 新会话”确认新默认模型，不要只看旧 `main` 会话底部模型栏。
- OpenClaw 模型栏里的 `Off` / `Adaptive` 是思考/推理模式状态，不是“模型关闭”或“未配置”。
- UGREEN 显示 Docker 项目 running 后，容器内部服务可能还有二阶段启动；本轮多次观察到 `1810` / `18789` 在 `66.5s`、`78.6s`、`82.6s`、`82.7s` 后才全部恢复。
- OpenClaw 新会话按钮点击后可能仍出现 `GatewayRequestError: unknown parent session: agent:main:main` 的历史提示，但新对话仍可继续发送；普通用户会被这个英文错误干扰。
- UGREEN App 存在状态不同步：项目列表可显示 `miloco` running，但详情页或无障碍树仍残留“未运行/处理中”。测试时以项目列表、端口探测和页面打开结果综合判断，不只看单个详情面板。

## LLM 供应商切换测试

时间：2026-07-02

本轮从 CC Switch 本地数据库提取了 DeepSeek、MiniMax、商汤科技三组配置，并保存到 ignored 的 `env/llm-providers.env`。文档不记录 Key。

本机直连探测结果：

- DeepSeek：`https://api.deepseek.com/anthropic` 对应模型 `deepseek-v4-flash`，OpenClaw 走 Anthropic messages 形状可用。
- MiniMax：`https://api.minimaxi.com/anthropic` 对应模型 `MiniMax-M3`，OpenClaw 走 Anthropic messages 形状可用。
- 商汤科技/SenseNova：`https://token.sensenova.cn/v1` 对应模型 `deepseek-v4-flash`；`/v1/messages` 用 `Authorization: Bearer` 可用，但 `x-api-key` 返回 401；`/v1/chat/completions` 可用。

NAS 只换 YAML、不拉新镜像的结果：

- DeepSeek：保留镜像，删除项目 `9.3s`，重建到 running `5.2s`；端口 `66.5s` 后全部恢复。OpenClaw 显示 `deepseek-v4-flash · Off`，发送 `请只回复：OK-DEEPSEEK`，约 `13.9s` 返回 `OK-DEEPSEEK`。
- MiniMax：保留镜像，删除项目 `7.3s`，重建到 running `4.7s`；端口 `78.6s` 后全部恢复。OpenClaw 显示 `MiniMax-M3 · Adaptive`，发送 `请只回复：OK-MINIMAX`，约 `19.5s` 返回 `OK-MINIMAX`。
- 商汤科技/SenseNova，自动推断旧逻辑：保留镜像，重建到 running `7.0s`；端口 `82.6s` 后全部恢复。OpenClaw 显示 `deepseek-v4-flash · Off`，但请求约 `107s` 后失败，页面显示 `LLM request failed`。
- 商汤科技/SenseNova，显式 `OPENCLAW_CHAT_API="openai-completions"`：保留镜像，重建到 running `5.2s`；端口 `82.7s` 后全部恢复。OpenClaw 发送 `请只回复：OK-SENSE`，约 `12.8s` 返回 `OK-SENSE`。

新镜像只换 YAML、不拉新镜像的结果：

- DeepSeek：保留镜像，删除项目 `8.4s`，重建到 running `5.2s`；端口 `84.6s` 后全部恢复。OpenClaw 显示 `deepseek-v4-flash · Off`，发送 `请只回复：OK-DEEPSEEK-NEW`，约 `11.8s` 返回。
- MiniMax：保留镜像，删除项目 `8.4s`，重建到 running `6.7s`；端口 `22.2s` 后全部恢复。OpenClaw 显示 `MiniMax-M3 · Adaptive`，发送 `请只回复：OK-MINIMAX-NEW`，约 `10.9s` 返回。
- 商汤科技/SenseNova，`OPENCLAW_CHAT_API` 留空自动推断：保留镜像，删除项目 `7.4s`，重建到 running `6.5s`；端口 `84.7s` 后全部恢复。OpenClaw 显示 `deepseek-v4-flash · Off`，发送 `请只回复：OK-SENSE-AUTO`，约 `10.1s` 返回。
- Chrome 本机扩展偶发对 `192.168.31.225:18789` 新标签报 `ERR_BLOCKED_BY_CLIENT`；重开同一地址可恢复，这不是 NAS 服务失败。
- 复测时直接打开 `/chat?session=main` 仍进入网关认证页，根地址 `/` 能自动带 token。已在源码修复代理逻辑：`/` 和裸 `/chat` 都会跳到带 `easy_miloco_token=1#token=...` 的地址，避免用户从历史记录进入认证页。

本轮代码侧处理：

- `OPENCLAW_CHAT_*` 与 `OMNI_*` 完全分离，不复用。
- 用户只需要提供模型名、Base URL、API Key；Provider 和 API 形状可自动推断。
- 增加 `OPENCLAW_CHAT_API` 作为排障字段，支持 `openai-completions`、`anthropic-messages`、`openai-responses`。
- DeepSeek/MiniMax 的 `/anthropic` URL 自动走 `anthropic-messages`。
- SenseNova 的 `https://token.sensenova.cn/v1` 自动走 `openai-completions`，避免 Anthropic adapter 使用 `x-api-key` 导致 401。

## 当前结论

- 首次部署真正耗时主要在 SWR 冷拉，本轮两次实测为 `87.0s` 和 `118.1s`；后续只换 YAML 不拉镜像时，Docker 项目重建本身约 `5-7s`。
- 小白用户最容易卡住的不是镜像拉取，而是项目 running 后 Web 端口还要 `22-109s` 才恢复；文档和 UI 提示都应明确“等 1-2 分钟再刷新”。
- OpenClaw provider 注释足够清楚的最低标准：只强调 `MODEL`、`BASE_URL`、`API_KEY` 三项必填；`PROVIDER` 和 `API` 是排障字段；`Off/Adaptive` 不是模型未配置。
- 当前代码已修正 SenseNova 自动 API 形状，并已修正 OpenClaw `/chat` 深链缺 token 的问题。旧镜像可用 workaround：商汤 YAML 显式写 `OPENCLAW_CHAT_API: "openai-completions"`，OpenClaw 从根地址 `http://<NAS-IP>:18789/` 进入。
