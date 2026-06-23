# 部署指南

## 支持环境

Miloco 面向 macOS 和 Linux。Windows 原生安装当前不支持，Windows 机器应在 WSL 内安装和运行。

如果要在 WSL 中拉取局域网摄像头流，需要额外处理 WSL 网络：

- `%USERPROFILE%\.wslconfig` 中启用 mirrored networking。
- 管理员 PowerShell 放行 Hyper-V 防火墙入站。
- 安装后用 `miloco-cli doctor` 验证。

## 异地部署能力边界

可以在“非家庭局域网”的机器上部署 Miloco，但能力会分层：

- 设备列表、设备属性查询、设备控制、手动场景触发等 MIoT 能力走小米账号和 MIoT cloud API。只要机器能访问互联网、账号已绑定、目标家庭在 Miloco 允许的 home 范围内，就可以操作该家庭下支持云端控制的设备。
- 实时摄像头画面、摄像头音视频流、基于摄像头的持续感知和习惯/行为统计，默认要求部署机器能和摄像头建立本地流连接。源码里摄像头感知筛选默认要求 `lan_online`，README 也明确“right now at home”画面是从 LAN 拉摄像头流。
- 因此，小区 2 的电脑可以远程控制小区 1 的米家设备，但不能直接承担小区 1 家里的摄像头实时感知，除非把两边网络打通到等价局域网，例如 VPN、站点到站点组网、Tailscale 子网路由、路由器 VPN 或其他能让摄像头本地流到达部署机器的方案。

实操判断：

```bash
miloco-cli account bind
miloco-cli scope home list --pretty
miloco-cli scope home switch <home_id>
miloco-cli device list
miloco-cli device control <did> --set <iid> <value>
miloco-cli scope camera list --pretty
```

如果设备控制正常但 `scope camera list` 里的 `is_online` 或 `connected` 不成立，通常就是异地部署缺少摄像头本地网络可达性，而不是账号绑定失败。

## 安装方式

Windows 用户先从 [Windows部署总入口](index.md) 开始。该入口会引导选择 Agent 一键版或人工手动版，并说明如何生成诊断报告、完成后授权收尾和满血验收。

如果要确认教程是否偏离官方 README / installer 流程，见 [官方部署流程对齐核查](upstream-deploy-alignment.md)。

## 实机部署实录

- [Windows 部署总入口](index.md)：Windows 玩家第一入口，串联诊断报告、Agent/人工教程、决策树、后授权收尾和满血验收。
- [官方部署流程对齐核查](upstream-deploy-alignment.md)：把 README、`scripts/install-guide.md`、installer 参数和 <windows-sample-host> 实机适配逐项对齐。
- [<windows-sample-host> 部署实录](windows-sample-host-log.md)：远程 Windows 电脑通过 WSL 部署 Miloco 的实时记录，包含 `wsl --install` 粘贴错误、发行版已存在、下一步进入 WSL 安装等处理。
- [Windows 部署预检与验收清单](preflight-checklist.md)：部署前/部署后逐项打勾，区分基础安装和满血验收。
- [Windows 满血验收证据清单](full-validation-evidence.md)：定义最终交付时哪些输出能证明满血完成，哪些只是基础就绪。
- [Windows 部署决策树](decision-tree.md)：按当前状态选择下一条命令，覆盖 WSL、网络、端口、OpenClaw、账号、Key、设备和摄像头分支。
- [Windows 部署故障排除矩阵](troubleshooting.md)：按报错或现象查定位命令、根因、修复和验收。
- [Windows 部署教程覆盖审计](tutorial-coverage-audit.md)：确认 Agent/人工教程是否覆盖任意 Windows 部署主要分支。
- [Windows 部署资料包发布清单](release-package.md)：列出可分发资料包、脚本 SHA256、复制命令和验收口径。
- [Windows 部署教程：独立分发版](standalone-package.md)：脱离 Obsidian 也能阅读的一页式完整教程。
- [Agent 一键部署提示词](agent-prompt.md)：可复制给具备 SSH 能力的 Agent 的完整提示词。
- [Windows 部署教程：Agent 一键版](agent-install.md)：把 SSH、WSL、Miloco、OpenClaw、插件安装和验证交给 Agent 的复用模板。
- [Windows 部署教程：人工手动版](manual-install.md)：人工一步步在 Windows + WSL 中完成部署的命令清单。
- [<windows-sample-host> 授权阶段用户操作卡片](windows-sample-host-auth-card.md)：用户回来后只需照做的小米 OAuth 和 MiMo API Key 提供清单。
- [<windows-sample-host> 后授权收尾 Runbook](windows-sample-host-post-auth-runbook.md)：收到小米 OAuth 授权码和 MiMo API Key 后，把 <windows-sample-host> 推进到满血验收的执行清单。
- [Windows 后授权失败排障与交付审计](post-auth-troubleshooting.md)：`Finish` 没有一次性跑到 `FULL_READY=yes` 时按层级排障，并定义最终交付审计证据。
- [Windows 部署预检与验收脚本](../scripts/README.md)：把 Windows 预检、WSL 服务验收、基础/满血状态判断做成可复制运行的脚本。

### 方式一：OpenClaw Agent 安装

把安装指令交给 OpenClaw Agent，由它走 `scripts/install-guide.md`。

适用：希望 Agent 引导账号绑定、模型配置、插件安装。

### 方式二：Release 一行安装

```bash
curl -LsSf https://github.com/<person-a>-JustSayWhen/easy-miloco/releases/latest/download/install.sh | bash
```

`install.sh` 只负责引导 uv 和 Python，然后执行 `scripts/install.py`。核心安装流程在 Python 脚本内，包括环境检查、包安装、临时服务初始化、小米账号绑定、模型配置、感知模型下载和 OpenClaw 插件安装。

### 方式三：源码开发安装

```bash
cd /path/to/xiaomi-miloco
bash scripts/install.sh --dev
```

`--dev` 会从源码构建本地产物，再安装。构建顺序里 Web 必须早于后端 wheel，因为 Web 产物会进入后端静态资源包。

## 启动和停止

推荐通过 CLI 管 daemon：

```bash
miloco-cli service start
miloco-cli service status
miloco-cli service logs -f
miloco-cli service stop
```

前台调试后端：

```bash
cd C:/Users/<user>/Desktop/xiaomi-miloco/backend
uv sync --all-packages
uv run miloco-backend
```

服务默认地址：

```text
http://127.0.0.1:1810/
```

如果 Windows `netsh interface ipv4 show excludedportrange protocol=tcp` 显示 `1810` 落在 excluded port range 内，WSL mirrored 下后端可能无法绑定默认端口。此时可改 `~/.openclaw/miloco/config.json`：

```json
{
  "server": {
    "port": 1886,
    "url": "http://127.0.0.1:1886"
  }
}
```

然后执行：

```bash
miloco-cli service restart
curl -fsS http://127.0.0.1:1886/health
```

## 初始配置

常见顺序：

1. 配置 Omni 模型 API key。
2. 绑定小米账号。
3. 开启需要感知的摄像头。
4. 重启 OpenClaw gateway 让插件生效。

CLI 示例：

```bash
miloco-cli config set model.omni.api_key sk-xxx
miloco-cli account bind
miloco-cli scope camera enable <did>
openclaw gateway restart
```

## 基础安装与满血安装的分界

基础安装完成的证据：

```bash
miloco-cli service status
curl -fsS http://127.0.0.1:<miloco_port>/health
openclaw gateway status
openclaw plugins inspect miloco-openclaw-plugin
```

满血安装还必须满足：

```bash
miloco-cli account status          # data.is_bound=true
miloco-cli config get model.omni.api_key --value-only
miloco-cli device list             # 不只有表头，能列出米家设备
miloco-cli scope camera list --pretty
```

如果后端日志出现：

```text
Failed to refresh cameras: access token is empty
Failed to refresh devices: access token is empty
```

说明小米账号未绑定或 token 不可用；这不是网络问题，先完成 `miloco-cli account bind` / `authorize`。

如果日志出现：

```text
感知引擎不可用: 多模态大模型 API Key 未配置
```

说明 MiMo / Omni API Key 未配置；先设置 `model.omni.api_key` 并重启服务。

## 脚本化预检和验收

脚本入口：

- `02-deploy/scripts/win-miloco-workflow.ps1`
- `02-deploy/scripts/windows-preflight.ps1`
- `02-deploy/scripts/wsl-miloco-validate.sh`
- `02-deploy/scripts/wsl-post-auth-finish.sh`
- [脚本说明](../scripts/README.md)
- [资料包发布清单](release-package.md)
- [资料包验收记录](validation-record.md)
- [后授权失败排障与交付审计](post-auth-troubleshooting.md)

推荐统一入口：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action AllBasic -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action Report
powershell.exe -ExecutionPolicy Bypass -File .\win-miloco-workflow.ps1 -Action BindUrl
```

目标 Windows 侧预检：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\windows-preflight.ps1 -Distro Ubuntu-24.04 -MilocoPort 1886 -OpenClawPort 18789
```

目标 WSL 侧验收：

```bash
MILOCO_PORT=1886 OPENCLAW_PORT=18789 bash ./wsl-miloco-validate.sh
```

判断口径：

- `BASIC_READY=yes`：Miloco health、OpenClaw Gateway、OpenClaw 插件基础链路可用。
- `FULL_READY=yes`：在基础链路外，小米账号已绑定、MiMo/Omni API Key 已配置、设备和摄像头 scope 可见。
- `FULL_READY=no` 且基础检查通过时，不要判定为部署失败；它通常表示还等用户完成小米 OAuth 授权或提供 MiMo API Key。

后授权一键收尾：

```bash
bash ./wsl-post-auth-finish.sh --print-bind-url
MILOCO_AUTH_PAYLOAD='<小米 OAuth payload>' MIMO_API_KEY='<MiMo API Key>' bash ./wsl-post-auth-finish.sh
```

这个脚本会执行账号授权、`model.omni.*` 写入、Miloco/OpenClaw 重启、设备/摄像头检查，并调用 `wsl-miloco-validate.sh --strict-full` 做最终验收。

配置源：

- 运行时配置：`$MILOCO_HOME/config.json`
- 默认 home：`~/.openclaw/miloco`
- 默认值源码：`backend/miloco/src/miloco/config/settings.yaml`
- 加载和覆盖逻辑：`backend/miloco/src/miloco/config/settings.py`

## Web 面板部署模型

生产模型是单端口：用户访问 `http://<host>:1810/`，后端返回 SPA。

关键点：

- Web 构建产物由后端静态资源路由提供。
- 根页面由后端注入 `window.__MILOCO_TOKEN__`。
- 前端 API client 自动把 token 作为 Bearer header。
- `/api/*` 和 `/health` 不走 SPA fallback。
- 跨网访问时不要让 1810 直接裸露到公网，应加反向代理、TLS 和认证。

开发时如果改 Web：

```bash
cd C:/Users/<user>/Desktop/xiaomi-miloco/web
pnpm install --frozen-lockfile
pnpm typecheck
pnpm test
pnpm build
```

常规调试仍以 backend 1810 为主。`vite.config.ts` 保留了 dev server proxy 能力，但当前 README 明确常规入口是后端同端口。

## OpenClaw 插件部署

插件源码位于 `plugins/openclaw`，安装包作为 Miloco release 的一部分安装，也可在开发构建中从本地 `.tgz` 安装。

插件要求后端已启动：

```bash
miloco-cli service start
```

开发验证：

```bash
cd C:/Users/<user>/Desktop/xiaomi-miloco/plugins/openclaw
pnpm install --frozen-lockfile
pnpm check
pnpm test
pnpm build
```

安装后通常需要：

```bash
openclaw gateway restart
```

## 部署前检查清单

- `miloco-cli service status` 显示服务正常。
- `miloco-cli doctor` 没有关键失败项。
- `http://127.0.0.1:<miloco_port>/health` 可访问；默认 `1810`，端口冲突机器可用 `1886`。
- Web 面板能打开并完成模型、账号、摄像头三项配置。
- OpenClaw 插件已安装，gateway 已重启。
- 如果暴露 LAN，确认 LAN 是可信网络；如果跨网，确认反代层有 TLS 和认证。
