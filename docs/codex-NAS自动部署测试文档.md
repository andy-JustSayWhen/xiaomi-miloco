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

1. 文件管理器打开 `共享文件夹 > docker`。
2. 当前列表共 11 项，未发现 `miloco` 目录，判定数据目录已不存在。
3. Docker > 项目页发现旧项目名为 `miloco-test`，不是 `miloco`。
4. `miloco-test` 处于运行中，先停止，等待状态变为未运行。
5. 通过更多操作删除 `miloco-test`，确认框中勾选“同时删除关联的镜像”。
6. 删除后项目页只剩 `firefox`、`moodist`、`metube`，旧项目消失。
7. Docker > 容器页未发现 `miloco` 或 `easy-miloco` 相关容器。
8. Docker > 镜像 > 本地镜像中搜索 `miloco`，结果为空，确认旧镜像已清除。

## 本轮部署记录

时间：2026-07-02

1. Docker > 项目 > 创建。
2. 项目名称填写 `miloco`。
3. 存放路径选择 `共享文件夹/docker/miloco`；该路径在创建页可直接选中。
4. Compose 内容不要依赖普通 `pbcopy`；本轮 `pbcopy` 在 Codex 环境里没有写入图形剪贴板，导致第一次粘贴成了聊天内容。
5. 改用 AppleScript 设置 macOS 图形剪贴板后再粘贴，确认 Compose 前几行是 `services:`、`miloco:` 和 SWR 镜像。
6. 部署日志显示镜像大小约 `395.9 MB`。
7. 拉取日志一开始很快到 `384.8 MB / 395.9 MB`，但尾部卡住了一段时间，用户视角容易误判为失败。
8. NAS 部署日志最终显示：
   - 镜像拉取：`82.7s`
   - 网络创建：`0.3s`
   - 容器创建：`0.5s`
9. 本地从点击“立即部署”到确认回到项目页的端到端耗时约 `150s`。
10. 回到 Docker > 项目页后，`miloco` 显示运行中，`1/1`。

## UI 操作注意

- 项目运行中时，“删除”菜单项不可用，需要先点“停止”。
- 删除项目弹窗默认不删除镜像；为了测真实首次拉取耗时，必须勾选“同时删除关联的镜像”。
- Docker 镜像页默认落在“镜像仓库”，确认本地残留要切到“本地镜像”。
- 搜索框过滤不是瞬时的，输入后要等列表变为空或出现匹配项。
- Compose 粘贴前必须确认系统剪贴板内容；错误粘贴时编辑器会显示 `Incorrect type. Expected "Compose Specification".`
- UGREEN 的部署弹窗会显示进度，但尾部可能长时间不刷新；不要在 1 分钟内贸然取消。
- UGREEN 从本地文件导入 YAML 偶发超时或沿用上一份内容；切换供应商测试时，更稳的方式是导入后检查编辑器里的 `OPENCLAW_CHAT_*` 行，必要时直接在编辑器内覆盖 YAML。
- 复用旧项目路径时，UGREEN 可能提示路径已存在；需要确认“导入该配置/覆盖”后再部署，否则按钮状态和实际 Compose 内容容易不同步。
- OpenClaw 请打开根地址 `http://<NAS-IP>:18789/`。直接打开历史里的 `/chat?session=main` 深链可能缺少当前 token，出现“认证不匹配”或“无法连接”。
- OpenClaw 会话会记住旧模型；换供应商重新部署后，应点“+ 新会话”确认新默认模型，不要只看旧 `main` 会话底部模型栏。

## LLM 供应商切换测试

时间：2026-07-02

本轮从 CC Switch 本地数据库提取了 DeepSeek、MiniMax、商汤科技三组配置，并保存到 ignored 的 `env/llm-providers.env`。文档不记录 Key。

本机直连探测结果：

- DeepSeek：`https://api.deepseek.com/anthropic/v1/messages` 返回 200，模型 `deepseek-v4-flash` 可用。
- MiniMax：`https://api.minimaxi.com/anthropic/v1/messages` 返回 200，模型 `MiniMax-M3` 可用。
- 商汤科技/SenseNova：`https://token.sensenova.cn/v1/messages` 返回 200，模型 `deepseek-v4-flash` 可用。

NAS 只换 YAML、不拉新镜像的结果：

- DeepSeek：UGREEN 部署日志无 Pull，只有网络和容器创建，Docker 创建阶段约 `0.3s`；OpenClaw 前端显示 `deepseek-v4-flash`，但对话失败，提示 provider 找不到该模型。本机直连同一组配置成功，因此判断为当前镜像里的 OpenClaw provider/API 形状处理不足，需要新 entrypoint 支持 `OPENCLAW_CHAT_API=anthropic-messages`。
- MiniMax：UGREEN 部署日志无 Pull，网络创建 `0.2s`，容器创建 `0.1s`，Docker 创建阶段约 `0.3s`；点击部署到确认完成约 `16s`。OpenClaw 打开根地址后显示 `MiniMax-M3 · Adaptive`，提示 `请只回复：OK-MINIMAX`，返回 `OK-MINIMAX`，前端感知耗时约 `2.3s`。
- 商汤科技/SenseNova：UGREEN 部署日志无 Pull，网络创建 `0.2s`，容器创建 `0.1s`，Docker 创建阶段约 `0.3s`；点击部署到确认完成约 `77s`，主要耗时在 UI 等待和确认。之后打开旧 `main` 会话仍显示上一轮 `MiniMax-M3`，并且删除/重建时 UGREEN 菜单坐标极不稳定；本轮未得到可信的前端新会话回复结果。直连 API 已确认可用，Compose 侧应显式填 `OPENCLAW_CHAT_API: "anthropic-messages"`。

本轮代码侧处理：

- `OPENCLAW_CHAT_*` 与 `OMNI_*` 完全分离，不复用。
- 用户只需要提供模型名、Base URL、API Key；Provider 和 API 形状可自动推断。
- 增加 `OPENCLAW_CHAT_API` 作为排障字段，支持 `openai-completions`、`anthropic-messages`、`openai-responses`。
- DeepSeek/MiniMax/SenseNova 的 `/anthropic` 或 SenseNova URL 会自动走 `anthropic-messages`。

## 下一步测试项

- 从 Docker > 项目创建新 Compose 项目。
- 粘贴由模板和 `env/nas-test.env` 生成的本机 Compose 内容。
- 从点击创建/部署开始计时，到项目显示运行中并可打开 WebUI 为止。
- 部署完成后打开：
  - Miloco 面板：`http://<NAS-IP>:1810/`
  - OpenClaw：`http://<NAS-IP>:18789/`
- 以小白用户视角检查：
  - 首屏是否能直接知道下一步该做什么。
  - Miloco 模型配置是否显示已配置或给出明确错误。
  - OpenClaw 是否能直接打开并正常回复。
  - 慢响应、空白页、占位符、报错文案是否会让用户卡住。
