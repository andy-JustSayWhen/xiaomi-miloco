# WIN-home01 2026-06-23 摄像头 Wi-Fi 根因复盘

用途：沉淀单台摄像头“米家在线、Miloco 设备状态在线、但视频流长期 `connected=false`”的排障结论。

## 一句话结论

主卧摄像头最终恢复的关键动作，不是继续改 PIN、subtype、音频或防火墙，而是把摄像头统一换绑到普通 2.4G Wi-Fi。此前失败摄像头接在 Game/5G SSID，稳定摄像头接在普通 2.4G SSID。这个网络差异导致米家 App 能看到在线，但 Miloco 本地拉流/PPCS 数据面长期拿不到视频帧。

## 现象

换绑前：

| 摄像头角色 | Wi-Fi | 现象 |
| --- | --- | --- |
| 稳定主卧摄像头 | 普通 2.4G Wi-Fi | Miloco 可取流 |
| 失败主卧摄像头 | Game/5G Wi-Fi | 米家在线，但 Miloco `connected=false`，direct probe `raw=0 decoded=0` |
| 客厅摄像头 | 普通网络 | Miloco 可取流 |

换绑后：

- `miloco-cli scope camera list --pretty` 显示三台摄像头均 `is_online=true / in_use=true / connected=true`。
- 3 轮重启 `miloco-backend` 后，主卧两个摄像头均能恢复 `connected=true`。
- Miloco 后端日志出现失败摄像头的 realtime perception。
- OpenClaw 对“主卧有几个摄像头，画面是什么”能回答摄像头数量并描述画面内容。

## 已排除的非根因

| 排除项 | 证据 |
| --- | --- |
| PIN | 失败摄像头 PIN 已关闭，direct probe 使用 `pin=NO` 后问题仍存在 |
| 画质/subtype | LOW/HIGH 以及多个 raw subtype 均无帧 |
| 音频 | 关闭音频仍失败 |
| Windows 防火墙 | Domain/Private/Public 均 disabled 后仍失败 |
| WSL 全局网络 | 同一 WSL/Miloco 环境下其他摄像头可取流 |
| 状态误判 issue | 设备已经 `is_online=true`，失败在视频数据面 |

## 真正解决动作

1. 在米家 App 中把失败摄像头和其他摄像头统一接入普通 2.4G Wi-Fi，避免使用 Game/5G SSID、访客网络或可能做客户端隔离的 SSID。
2. 等摄像头重新上线后，重启 Miloco 后台。
3. 用 `miloco-cli scope camera list --pretty` 验证每台摄像头均 `connected=true`。
4. 重启 `miloco-backend` 3 次，确认每次最终都能恢复三台摄像头连接。
5. 用 OpenClaw 问答验收“主卧有几个摄像头，画面是什么”，确认 Agent 能基于画面回答。

## 代码侧辅助修复的作用

本轮代码修复提高了稳定性，但不是失败摄像头离线的根因：

- WebSocket 最后一个订阅者断开后，camera SDK 延迟 30 秒 teardown，减少前端刷新/切页导致的冷启动。
- LAN hint 存在时，首帧超时第一次先 rebuild stream manager，不立即进入 5 分钟 cooldown。
- 无 decoded 首帧时不再假标 `connected=true`，避免 UI 显示 LIVE 但实际黑屏。

这些修复让 Miloco 更稳、更不容易假在线；但最终让 `raw=0 decoded=0` 恢复出帧的关键动作，是把摄像头从 Game/5G Wi-Fi 换到普通 2.4G Wi-Fi。

## OpenClaw 验收注意

本轮曾出现摄像头已经恢复，但 OpenClaw 问答失败的情况。日志显示原因是模型额度耗尽，返回 `FailoverError: quota exhausted`。这不是摄像头错误，应先恢复或切换 OpenClaw 可用模型额度，再重测问答链路。

最终验收口径：

1. Miloco 摄像头后台重启 3 次验收通过。
2. 房间内目标摄像头均在线且可取流。
3. OpenClaw 能回答摄像头数量并描述画面。

## 后续遇到同类问题的优先级

| 现象 | 优先动作 |
| --- | --- |
| 米家在线，Miloco `connected=false`，且其他摄像头正常 | 先检查失败摄像头是否接在不同 SSID、5G/Game Wi-Fi、访客网络或隔离网络 |
| 单个 did `raw=0 decoded=0`，同主机其他 did 可出帧 | 不要先改 Miloco 全局逻辑，优先设备侧换普通 2.4G Wi-Fi、断电重启、固件更新 |
| 换绑普通 2.4G 后恢复 | 记录 SSID 差异为根因，并做 3 次后台重启 + OpenClaw 问答验收 |
