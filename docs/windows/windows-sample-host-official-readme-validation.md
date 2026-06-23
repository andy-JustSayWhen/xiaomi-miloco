# <windows-sample-host> 官方 README 特性验收

- 目标机：`<windows-sample-host> / <tailscale-ip>`
- 验证方式：`Computer Use plugin -> 网易 UU 远程 -> <windows-sample-host>`
- 说明：本轮没有使用 SSH；只用远程桌面和网页 UI 做验收。
- 时间：`2026-06-22 11:23`

## 结论先行

当前能确认的只有“页面可达、部分 UI 可读、摄像头实时画面可见”。
OpenClaw 代理主模型未配置成功，Miloco 模型页测试连接也返回 `API Key 无效或无权限`，所以 README 里要求的真实技能调用、任务类动作、通知类动作，本轮还不能算已通过。

## P0 OpenClaw 先补漏

| 项目 | 结果 | 证据 | 备注 |
|---|---|---|---|
| Gateway 页面可达 | 通过 | 打开 `http://127.0.0.1:18789/#token=<AGENT_WEBHOOK_BEARER>` 后进入 `Main Session` 聊天页 | 说明 tokenized 登录入口可用 |
| Miloco 插件/技能可见 | 通过 | `代理 -> 技能` 页能看到 `miloco-devices`、`miloco-perception`、`miloco-miot-identity`、`miloco-miot-admin`、`miloco-create-task`、`miloco-terminate-task`、`miloco-notify` 等 | 技能列表可见且处于启用状态 |
| OpenClaw Agent 模型配置 | 失败 | `代理 -> 概览` 显示 `Primary model (default): Not set`；聊天页底部显示 `gpt-5.5 openai Off` | 说明当前 agent 主模型未真正配置到可用态 |
| OpenClaw 实际对话 | 失败 | 聊天泡泡报错：`Agent failed before reply: No API key found for provider "openai"` | 当前无法进入真实回复链路 |

## P1 README 列出的技能

README / 插件里列到的技能在 UI 上能看到，但本轮没有成功触发实际调用。

- `miloco-devices`：未验证调用
- `miloco-perception`：未验证调用
- `miloco-miot-identity`：未验证调用
- `miloco-miot-admin`：未验证调用
- `miloco-create-task`：未验证调用
- `miloco-terminate-task`：未验证调用
- `miloco-notify`：未验证调用

补充说明：

- 技能“可见”不等于技能“已调用”。
- 由于 OpenClaw 代理模型当前不可用，本轮没有进入到真正的技能执行阶段。

## P2 README 六大核心特性

| 特性 | 结果 | 证据 | 备注 |
|---|---|---|---|
| 通用常识 | 只做了只读替代验证 | Miloco 概览页能看到<room-bedroom>实时画面卡片，可直接观察画面内容 | 未人为制造危险场景 |
| 身份识别 | 未验证 | 本轮没有完成可用的身份识别调用 | 需要可工作的 OpenClaw agent |
| 家庭记忆 | 未验证 | 本轮没有完成记忆写入/回读 | 需要可工作的 OpenClaw agent |
| 家庭任务 | 未验证 | 本轮没有完成创建/暂停/删除任务 | 需要可工作的 OpenClaw agent |
| 主动智能 | 未验证 | 本轮没有完成基于偏好/任务/画面生成主动建议 | 需要可工作的 OpenClaw agent |
| 家庭面板 | 通过（只读） | `概览`、`设备`、`家庭`、`日志`、`模型` 页都能打开并截图 | 属于 UI 可达性和只读核验 |

## P3 Quick Start 三步

### 1) 模型配置

- Miloco `模型` 页能打开新增表单。
- 已尝试输入：
  - `Base URL`: `https://token-plan-sgp.xiaomimimo.com/v1`
  - `API Key`: 用户提供的 MiMo Key
  - `模型`: 目标为 `mimo-v2.5`
- 点击 `测试连接` 后返回：`API Key 无效或无权限`
- 结论：本轮没有得到可用的 Miloco 视觉模型配置。

### 1.1 token plan 直连复核

为了排除 UI 表单误填造成的假阴性，直接请求两个 token plan 的 `/v1/models`：

| 账号 | Base URL | 连通性 | 模型列表 |
|---|---|---|---|
| 账号02-国际 | `https://token-plan-sgp.xiaomimimo.com/v1` | 通过 | `mimo-v2-omni`、`mimo-v2-pro`、`mimo-v2-tts`、`mimo-v2.5`、`mimo-v2.5-asr`、`mimo-v2.5-pro`、`mimo-v2.5-tts`、`mimo-v2.5-tts-voiceclone`、`mimo-v2.5-tts-voicedesign` |
| 账号01-国内 | `https://token-plan-cn.xiaomimimo.com/v1` | 通过 | `mimo-v2-omni`、`mimo-v2-pro`、`mimo-v2-tts`、`mimo-v2.5`、`mimo-v2.5-asr`、`mimo-v2.5-pro`、`mimo-v2.5-tts`、`mimo-v2.5-tts-voiceclone`、`mimo-v2.5-tts-voicedesign` |

补充判断：

- 两个 token 都能拿到同样的 9 个模型，说明 token plan 本身连通。
- 国际 token 按你的要求优先复核，结果可用。
- 之前 Miloco UI 的 `测试连接` 失败，不能直接等价为 token 无效；那次更像是表单输入被误写到了错误字段，属于 UI 假阴性。

### 2) 小米账号

- 本轮没有用 CLI 复核 `account status`。
- 只从 UI 侧确认到 Miloco 主页面和设备页可达，不能把它等价为 `is_bound=true`。

### 3) 摄像头感知

- Miloco 概览页能看到 `LIVE` 画面卡片。
- 当前确认到的画面标题：`<camera-desk> · <room-bedroom>`
- Miloco 设备页显示：`127 devices`、`13 rooms`

### 命令证据状态

本轮按“无 SSH、仅 Computer Use”执行，以下 CLI 命令没有在远端终端里重跑：

```bash
miloco-cli account status
miloco-cli config get model.omni.model
miloco-cli config get model.omni.base_url
miloco-cli device list
miloco-cli scope camera list --pretty
miloco-cli person list
miloco-cli rule list
miloco-cli service logs --tail 200
openclaw gateway status
openclaw plugins inspect miloco-openclaw-plugin
```

## 证据摘录

```text
OpenClaw agent overview:
Primary model (default): Not set
Runtime: codex
Skills Filter: all skills

OpenClaw chat error:
Agent failed before reply: No API key found for provider "openai"

Miloco model page test:
API Key 无效或无权限

Miloco dashboard:
127 devices
13 rooms
<camera-desk> · <room-bedroom>
LIVE
```

## 最终分类

### 已实测通过

- OpenClaw Gateway 页面可达，tokenized 入口能进入会话页。
- OpenClaw 技能页可见，Miloco 相关技能名称能被确认出来。
- Miloco 概览页、设备页、模型页、日志页都能打开。
- Miloco 概览页确认到至少 1 个 live camera 画面：`<camera-desk> · <room-bedroom>`。
- 账号01-国内和账号02-国际的 token plan `/v1/models` 都可连通，且返回同一组 9 个模型。

### 只做了只读 / 安全替代验证

- 摄像头/房间总览的 UI 盘点。
- 实时画面查看和画面标题核验。
- 设备页、模型页、日志页的只读核验。
- 未制造危险场景、未触发真实家电控制。

### 未验证或需要用户授权

- OpenClaw 的 `miloco-*` 技能实际调用。
- `miloco-create-task` / `miloco-terminate-task` 的真实任务生命周期。
- `miloco-notify` 的真实通知发送。
- 身份识别、家庭记忆、主动智能的真实写入/回读。
- 远端 CLI 证据复核。
- 需要可用模型认证才能继续的聊天/技能链路。

## 回链

- [<windows-sample-host>部署实录.md](windows-sample-host-log.md)
- [reports/windows-sample-host-20260622-112310-readme-feature-acceptance.txt](reports/windows-sample-host-20260622-112310-readme-feature-acceptance.txt)
