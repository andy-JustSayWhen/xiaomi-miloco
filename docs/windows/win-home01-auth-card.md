# WIN-home01 授权阶段用户操作卡片

> 用途：记录 WIN-home01 授权阶段用户曾需要亲自完成的小米账号授权动作；当前作为历史操作卡片留档。
> 当前状态：`BASIC_READY_FROM_WINDOWS=yes`、`BASIC_READY=yes`、`FULL_READY=yes`
> 最近复核：2026-06-22 10:22

## 当前结论

此卡片中的用户动作已经完成。

最终 payload 已收到并执行后授权收尾，WIN-home01 已通过满血验收：

```text
account.is_bound=true
device_rows=127
camera.did=<camera-did-desk>
camera.in_use=true
camera.connected=true
PASS_COUNT=16
WARN_COUNT=0
FAIL_COUNT=0
```

## 你现在只需要做一件事

### 1. 完成小米账号 OAuth 授权

打开下面链接：

```text
https://account.xiaomi.com/oauth2/authorize?redirect_uri=https%3A%2F%2Fmico.api.mijia.tech%2Flogin_redirect&client_id=2882303761520431603&response_type=code&device_id=mico.4010007daa7043c18e101c053be2f57f&state=864dcbd558ff9c17d916c9e7d4f9ce194c6ac41c&skip_confirm=False
```

该链接最近一次由 WIN-home01 于 `2026-06-22 10:11` 重新生成，并已尝试在 WIN01 默认浏览器拉起。

WIN01 桌面也已放置兜底入口：

```text
C:\Users\<user>\Desktop\miloco-xiaomi-oauth.url
C:\Users\<user>\Desktop\miloco-xiaomi-oauth.txt
```

登录小米账号并完成授权后，把页面返回的 OAuth payload / 授权码完整复制给 Agent。

WIN-home01 本次实际收到的 payload：

```text
<XIAOMI_OAUTH_PAYLOAD>
```

如果链接过期，让 Agent 重新运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action BindUrl -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

### 2. 已配置 MiMo 视觉模型

Miloco 当前模型配置：

```text
model.omni.model=mimo-v2.5
model.omni.base_url=https://token-plan-sgp.xiaomimimo.com/v1
```

说明：`mimo-v2.5` 支持视觉，适合 Miloco 感知链路；`mimo-v2.5-pro` 不支持视觉，不要配置到 `model.omni.model`。

API Key 已写入 WIN01 Miloco 配置。

## Agent 收到后执行

优先执行统一入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\<user>\AppData\Local\Temp\win-miloco-workflow.ps1 -Action Finish -AuthPayload '<小米 OAuth payload>' -MimoApiKey '<MiMo API Key>' -OmniModel 'mimo-v2.5' -OmniBaseUrl 'https://token-plan-sgp.xiaomimimo.com/v1' -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

如需指定家庭或直接开启摄像头：

```powershell
-HomeId '<home_id>' -CameraDids '<did1> <did2>'
```

## 满血完成标准

执行完成后必须看到：

```text
BASIC_READY_FROM_WINDOWS=yes
BASIC_READY=yes
FULL_READY=yes
```

并且手动证据满足：

```bash
miloco-cli account status                 # is_bound=true
miloco-cli config get model.omni.api_key --value-only
miloco-cli device list                    # 表头后有设备行
miloco-cli scope camera list --pretty     # 能列出摄像头，目标摄像头 in_use=true
```

日志中不应再出现：

```text
access token is empty
多模态大模型 API Key 未配置
```

## 当前不要误判

这些只代表基础链路正常，不代表满血：

- `curl http://127.0.0.1:1886/health` 返回 `{"status":"ok"}`。
- OpenClaw Gateway `Connectivity probe: ok`。
- `miloco-openclaw-plugin` 为 `Status: loaded`。
- `BASIC_READY=yes`。

历史上真正缺口只有：

- 小米账号 OAuth payload。
