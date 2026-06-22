# 米家摄像头支持说明

Miloco 的摄像头能力依赖米家摄像头。摄像头需要先绑定到米家 App，并且在米家 App 中能正常打开画面。

## 状态分层

排障时不要只看“在线/离线”一个词，至少分四层：

| 层级 | 含义 | 典型来源 |
| --- | --- | --- |
| 云端在线 | 米家云端认为设备在线 | MIoT 设备列表、米家 App |
| 局域网在线 | SDK 在局域网表中发现设备和 IP | `lan_online`、`local_ip`、LAN table |
| 流连接成功 | Miloco 后端已经拿到摄像头帧 | `connected`、`active_sources`、frame count |
| Agent 可用 | OpenClaw 对话能基于画面回答问题 | OpenClaw 聊天页视觉问答 |

WebUI 中“实时画面能看到”说明流连接可能成功；Minicloud 或 Miloco 设备列表显示“离线”可能只是局域网状态层没有同步，不能直接等同于 OpenClaw 不能看画面。

## 当前验证记录

| 摄像头 | 当前结论 | 说明 |
| --- | --- | --- |
| 客厅摄像头 | 已验证可用 | WebUI 可见实时画面，OpenClaw 可基于画面回答。 |
| 主卧电脑桌上 | 间歇可用 | 曾在 WIN-home01 上成功出帧并被 OpenClaw 描述画面；后续出现 LAN 表无命中、旧 IP 不可达的问题。 |
| 主卧床边置物架 | 已修复过离线误报路径，仍需现场观察 | 曾出现 WebUI 能看到画面但左上角报错、Minicloud 显示离线。修复方向是区分 `online`、`lan_online`、`connected`，避免 UI 只按单一状态误判。 |

## 过期 LAN override

本 fork 曾为摄像头加入 `camera_lan_overrides.json`，用于在 SDK 能识别设备但 IP 缺失时补齐 IP。后续排查发现：如果 SDK 的局域网表完全没有命中该摄像头，仍强行把 override IP 写成 `lan_online=True`，会造成旧 IP 被误当成可用，WebUI 和 Agent 判断失真。

当前修复策略：

- override IP 仍会被 ping，用于快速探测。
- SDK 局域网表没有命中时，不再强行把摄像头标记为 `lan_online=True`。
- 日志会记录 `Camera LAN override ignored because SDK LAN table has no hit`。
- 相关测试覆盖在 `backend/miloco/tests/test_miot_filter_and_cameras.py`。

## MICAM / go2rtc 参考结论

`miiot/micam` 和 go2rtc 的小米摄像头方案对理解“小米摄像头可能需要云端鉴权、P2P、局域网地址和流会话协同”有参考价值，但当前没有把它们作为 Miloco 原生出帧链路的替代实现。Miloco 当前仍以官方 MIoT SDK 摄像头能力为主，go2rtc 探针只作为外部诊断辅助。

## 模型能力提醒

- `mimo-v2.5` 支持视觉，适合摄像头画面理解。
- `mimo-v2.5-pro` 文本能力更强，但不支持视觉；不能直接用于需要看画面的摄像头推理。

## 新增摄像头记录要求

新增摄像头记录时，至少写清：

- 米家 App 中显示的设备名称。
- 设备型号或产品型号。
- 是否能在 Miloco 面板看到实时画面。
- 是否能在 OpenClaw 对话中被 Miloco 用于视觉理解。
- 如果失败，写明失败层级、错误现象、定位证据和解决办法。
