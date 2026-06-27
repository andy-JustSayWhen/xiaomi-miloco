# OpenClaw 消息渠道接入步骤

引用本文：

```text
https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/message-channel/docs/message-channel-setup-guide.md
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

```bash
openclaw channels add
```

回车后，选择一个消息渠道，按交互式菜单完成配置。

## 6. 重启 Gateway

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

## 7. 验证频道状态

命令格式：

```bash
openclaw channels status --channel <渠道id> --json --probe --timeout 15000
```

通过标准：

```text
configured=true
running=true
probe.ok=true
```

## 8. 真实收发测试

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

## 9. 绑定 Miloco 通知频道

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

## 10. 排查命令

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

## 11. 完成标准

```text
openclaw channels list 能看到该渠道
openclaw channels status --channel <渠道id> --json --probe 通过
聊天软件发消息后 bot 能回复
Miloco 通知测试消息能发到该渠道
```
