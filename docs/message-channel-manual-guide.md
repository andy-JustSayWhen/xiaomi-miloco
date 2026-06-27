# OpenClaw 消息渠道接入步骤

Agent 一句话：

```text
按 https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/message-channel/docs/message-channel-manual-guide.md 接入 <渠道名> OpenClaw 消息渠道。
```

## 1. 检查 WSL 发行版

命令格式：

```powershell
wsl -l -v
```

示例：

```powershell
wsl -l -v
```

示例输出：

```text
  NAME            STATE           VERSION
* Ubuntu-24.04    Running         2
```

## 2. 打开 OpenClaw 所在 WSL

命令格式：

```powershell
wsl -d <WSL发行版名称>
```

示例：

```powershell
wsl -d Ubuntu-24.04
```

## 3. 确认 OpenClaw 可用

命令格式：

```bash
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"
openclaw --version
openclaw gateway status
```

示例：

```bash
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"
openclaw --version
openclaw gateway status
```

应看到：

```text
Config (cli): ~/.openclaw/openclaw.json
Config (service): ~/.openclaw/openclaw.json
Connectivity probe: ok
```

## 4. 查看消息渠道

命令格式：

```bash
openclaw channels list --all
```

示例：

```bash
openclaw channels list --all
```

状态含义：

```text
configured  已配置
available   插件可用，未完成配置
installable 可安装或可接入
```

## 5. 打开官方交互式添加流程

命令格式：

```bash
openclaw channels add
```

示例：

```bash
openclaw channels add
```

在菜单里选择目标渠道，例如：

```text
Feishu / Lark
Telegram
QQ Bot
Slack
Discord
WhatsApp
```

按交互式菜单填写凭据或扫码授权。

## 6. 指定渠道添加

先查看当前版本支持的参数：

```bash
openclaw channels add --help
```

命令格式：

```bash
openclaw channels add --channel <渠道id>
```

示例：

```bash
openclaw channels add --channel feishu
```

```bash
openclaw channels add --channel telegram
```

```bash
openclaw channels add --channel qqbot
```

## 7. 渠道凭据示例

### 飞书 / Lark

```bash
openclaw channels add --channel feishu
```

如果菜单提示使用 login：

```bash
openclaw channels login --channel feishu
```

### Telegram

先在 Telegram 的 `@BotFather` 创建 bot，获取 bot token。

token 示例：

```text
123456789:ABCxxxxxxxxxxxxxxxx
```

然后执行：

```bash
openclaw channels add --channel telegram
```

按菜单粘贴 bot token。

### QQ Bot

准备 QQ 开放平台 Bot 的 AppID 和 AppSecret。

```bash
openclaw channels add --channel qqbot
```

按菜单填写 AppID / AppSecret。

如果当前版本提示 token 格式：

```bash
openclaw channels add --channel qqbot --token "AppID:AppSecret"
```

## 8. 重启 Gateway

命令格式：

```bash
openclaw gateway restart
```

示例：

```bash
openclaw gateway restart
```

确认：

```bash
openclaw gateway status
```

## 9. 验证频道状态

命令格式：

```bash
openclaw channels status --channel <渠道id> --json --probe --timeout 15000
```

示例：

```bash
openclaw channels status --channel feishu --json --probe --timeout 15000
```

```bash
openclaw channels status --channel telegram --json --probe --timeout 15000
```

```bash
openclaw channels status --channel qqbot --json --probe --timeout 15000
```

通过标准：

```text
configured=true
running=true
probe.ok=true
```

## 10. 真实收发测试

在目标聊天软件里给 bot 发：

```text
你好
```

如果出现配对码：

命令格式：

```bash
openclaw pairing list <渠道id>
openclaw pairing approve <渠道id> <配对码>
```

示例：

```bash
openclaw pairing list telegram
openclaw pairing approve telegram 123456
```

```bash
openclaw pairing list feishu
openclaw pairing approve feishu 123456
```

再次从聊天软件发消息，确认 bot 回复。

## 11. 绑定 Miloco 通知频道

在已打通的聊天软件对话里发送：

```text
绑定通知频道
```

然后发送测试指令：

```text
发送一条 Miloco 通知测试消息
```

通过标准：

```json
{"ok": true, "channel": "<渠道id>"}
```

## 12. 排查命令

查看已配置渠道：

```bash
openclaw channels list
```

查看全部渠道：

```bash
openclaw channels list --all
```

查看 Gateway：

```bash
openclaw gateway status
```

查看帮助：

```bash
openclaw channels --help
openclaw channels add --help
openclaw channels status --help
```

查看配置：

```bash
python3 -m json.tool ~/.openclaw/openclaw.json | less
```

备份配置：

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.channel-$(date +%Y%m%d-%H%M%S)
```

## 13. 完成标准

```text
openclaw channels list 能看到该渠道
openclaw channels status --channel <渠道id> --json --probe 通过
聊天软件发消息后 bot 能回复
Miloco 通知测试消息能发到该渠道
```
