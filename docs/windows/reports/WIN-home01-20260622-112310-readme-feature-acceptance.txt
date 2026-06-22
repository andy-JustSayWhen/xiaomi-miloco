WIN-home01 README 特性验收原始记录
时间：2026-06-22 11:23
方式：Computer Use plugin -> 网易 UU 远程 -> WIN-home01

回链：
[WIN-home01官方README特性验收.md](../win-home01-official-readme-validation.md)
[WIN-home01部署实录.md](../win-home01-log.md)

一、P0 OpenClaw

1. Gateway 登录
- 打开 `http://127.0.0.1:18789/#token=<AGENT_WEBHOOK_BEARER>`
- 页面进入 `Main Session`

2. Miloco 技能可见
- `miloco-devices`
- `miloco-perception`
- `miloco-miot-identity`
- `miloco-miot-admin`
- `miloco-create-task`
- `miloco-terminate-task`
- `miloco-notify`

3. Agent 模型配置
- `代理 -> 概览`
- `Primary model (default): Not set`
- `Runtime: codex`
- 聊天页底部：`gpt-5.5 openai Off`
- 聊天错误：`Agent failed before reply: No API key found for provider "openai"`

二、Miloco 模型页

- 表单可打开
- `Base URL`: `https://token-plan-sgp.xiaomimimo.com/v1`
- `API Key`: `<MIMO_API_KEY>`
- `模型`: 目标值为 `mimo-v2.5`
- 点击 `测试连接` 后返回：`API Key 无效或无权限`
- 因此本轮没有得到可用的视觉模型配置

三、token plan 直连复核

- `https://token-plan-sgp.xiaomimimo.com/v1/models`
  - 通过
  - 模型列表：`mimo-v2-omni`, `mimo-v2-pro`, `mimo-v2-tts`, `mimo-v2.5`, `mimo-v2.5-asr`, `mimo-v2.5-pro`, `mimo-v2.5-tts`, `mimo-v2.5-tts-voiceclone`, `mimo-v2.5-tts-voicedesign`
- `https://token-plan-cn.xiaomimimo.com/v1/models`
  - 通过
  - 模型列表：同上

- 结论：两个 token plan 都连通，且模型列表一致
- 之前 Miloco UI 的失败更像是表单字段误填导致的假阴性，不能直接当成 token 无效

四、Miloco 面板

- 概览页能看到 live camera 卡片
- 确认到的画面标题：`主卧 电脑桌上 · 主卧`
- 设备页显示：`127 devices`、`13 rooms`

五、最终判断

- OpenClaw 技能“可见”但“不可调用”
- Miloco UI“可达”但“模型链路未真正跑通”
- 本轮只能做只读 / 安全替代验证
- 需要真实 agent 调用的 README 项目未通过
- token plan 直连本身已通过，国际 token 优先可用
