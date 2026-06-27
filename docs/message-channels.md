# Miloco 消息渠道接入

## 一句话交给任意 Agent

让 Agent 在 Miloco 所在 WSL 里执行：

```bash
bash docs/scripts/message-channel-router.sh feishu --interactive --install --auth --bind --validate
```

这句话只进入消息渠道路由，不改 Miloco 核心代码。当前路由支持 `feishu`，后续新增渠道时，只需要在 `docs/scripts/message-channel-router.sh` 增加分支，并把具体接入流程放到独立脚本。

## 桌面控制台入口

Windows 一键包生成的 `Miloco 控制台.bat` 会出现菜单项：

```text
6. 接入飞书消息渠道
```

选择后进入交互式流程：

1. 检测 OpenClaw / Feishu channel 状态。
2. 安装并启用 `clawhub:@openclaw/feishu`。
3. 触发 OpenClaw Feishu 登录或授权流程。
4. 绑定 Miloco 主动通知到 Feishu session。
5. 验证 Feishu channel probe 和测试消息发送。

如果脚本找不到 Feishu session，会提示先从飞书客户端给 bot 发一条消息，或粘贴已知的 Feishu `open_id` 后继续绑定。
