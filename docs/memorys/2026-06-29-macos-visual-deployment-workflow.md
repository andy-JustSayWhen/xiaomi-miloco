# 2026-06-29 macOS 可视化部署工作流记忆

目的：后续做 macOS 懒人包、Agent 一句话部署或回归测试时，不要只跑 CLI 验证；必须按普通用户可视化路径完整走一遍，并保留能证明 Miloco 面板和 OpenClaw Chat 都可用的证据。

## 必走路径

1. 先用 Finder 打开 `dist/macos`，像小白用户一样解压 `easy-miloco-v0.1-macos-arm64.zip`。
2. 尽量通过 Finder 双击或菜单打开 `install.command`。如果自动化点击 Finder 选中不稳定，可以用 AppleScript 选中文件后走 Finder `File -> Open`，但记录这是自动化限制，不要把它当用户路径通过。
3. 安装器遇到旧版时必须先导出桌面 Agent 恢复包，再卸载旧版，再继续安装。
4. 小米授权必须自动拉起浏览器。授权后两种返回都要能处理：
   - 页面直接显示授权码：粘贴授权码。
   - 浏览器报错或跳到 `https://127.0.0.1/...`：粘贴完整地址栏 URL。
5. 模型配置必须询问用户是否已有 Key；没有时给 Windows v0.5 同源的三个推荐入口。已有 Key 时让用户直接粘贴 API Key、Base URL、模型名；Key 输入不要隐藏成 `***`，Base URL 不要预填。
6. 安装完成后必须生成并告知桌面入口：
   - `~/Desktop/Miloco Console.command`
   - `~/Desktop/OpenClaw Chat.command`
   - `~/Desktop/OpenClaw-login-info.txt`
7. 安装结束必须自动打开 Miloco 面板和 OpenClaw Chat，不能只打印“全部完成”。

## 满血可视化验收

基础脚本绿灯不够，必须人工/自动化看见以下页面事实：

1. Miloco 面板 `http://127.0.0.1:1810/` 概述页可打开。
2. 概述页能看到当前家庭、设备总数、实时画面区域。
3. 概述页要明确记录摄像头口径：
   - 摄像头总数来自 scope camera list / 面板所有摄像头。
   - “在感知”数量只是当前接入画面流数量，不等于总数。
   - 例：本机 `andy的家` 看到 3 台摄像头，其中 2 个在感知，`主卧 电脑桌上` 未接入画面流。
4. OpenClaw Chat 必须用一句话问：

   ```text
   家里有几个摄像头？画面如何？
   ```

5. 合格答案必须同时满足：
   - 回答总共有几台摄像头。
   - 说明几台当前接入画面流、几台未接入。
   - 能描述已接入摄像头看到的画面。
   - 不暴露“根据系统上下文”“应该回答”等提示词/推理痕迹。
   - 不再触发 `nodes camera_list` 的 `node required` 错误。

## 本次踩坑和固定处理

1. OpenClaw 主 Chat 默认模型可能仍指向 `openai/...`，即使 Miloco Omni 模型已配置也会报：

   ```text
   No API key found for provider "openai"
   ```

   安装器和 `macos-post-auth-finish.sh` 必须把 `~/.openclaw/miloco/config.json` 的 `model.omni` 同步到 `~/.openclaw/openclaw.json`：
   - `agents.defaults.model.primary`
   - `models.providers.<provider>.baseUrl`
   - `models.providers.<provider>.apiKey`
   - provider 的 model row

2. `openclaw config get gateway.auth.token` 可能输出 redacted token。桌面登录文件必须从 `~/.openclaw/openclaw.json` 读取真实 `gateway.auth.token`。
3. OpenClaw Chat 旧会话会污染结果。验证修复时用全新 session URL，例如：

   ```text
   http://127.0.0.1:18789/chat?session=agent%3Amain%3Amacos-visual-clean-<timestamp>&token=<token>
   ```

4. OpenClaw 插件 skill 源文件在 `plugins/skills/...`。`pnpm --dir plugins/openclaw build` 会从这里同步到 `plugins/openclaw/skills/...`，不要只改构建后的 `plugins/openclaw/skills`。
5. 摄像头数量口径：
   - 总数用 `miloco-cli scope camera list --pretty`。
   - 实时可查询源用 `miloco-cli perceive devices --pretty`。
   - 看画面用 `miloco-cli perceive query --source <did> ... --query "<问题>"`。
6. Miloco 面板已经有实时画面时，OpenClaw Chat 如果说“没有接入画面流”，优先查 prompt 注入和 skill 口径，而不是重装。
7. `openclaw gateway restart/status` 在 macOS LaunchAgent 下偶尔卡住。确认服务时可用：

   ```bash
   ps -axo pid,etime,command | rg "node .*openclaw.*gateway"
   lsof -nP -iTCP:18789 -sTCP:LISTEN
   ```

   测试后清理要用：

   ```bash
   launchctl bootout gui/$(id -u)/ai.openclaw.gateway || true
   launchctl remove ai.openclaw.gateway || true
   rm -f ~/Library/LaunchAgents/ai.openclaw.gateway.plist
   ```

## 回归命令

```bash
pnpm --dir plugins/openclaw exec tsc --noEmit
pnpm --dir plugins/openclaw exec vitest run --testTimeout=20000
PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH" bash macos/build-release.sh
bash -n macos/package/install.command docs/scripts/macos-post-auth-finish.sh docs/scripts/macos-miloco-validate.sh
```

包结构校验：

```bash
rm -rf /tmp/easy-miloco-verify
mkdir -p /tmp/easy-miloco-verify
ditto -x -k dist/macos/easy-miloco-v0.1-macos-arm64.zip /tmp/easy-miloco-verify
find /tmp/easy-miloco-verify -maxdepth 3 -type f \( -name 'install.command' -o -name 'install.sh' -o -name 'manifest.json' \) -exec ls -l {} \;
shasum -a 256 dist/macos/easy-miloco-v0.1-macos-arm64.zip
```

## 测试后清理

每轮本地部署测试后必须清理，不能留下服务和窗口：

```bash
miloco-cli service stop || true
openclaw gateway stop || true
openclaw gateway uninstall || true
bash scripts/install.sh --uninstall --delete-home || true
launchctl bootout gui/$(id -u)/ai.openclaw.gateway || true
launchctl remove ai.openclaw.gateway || true
rm -f ~/Library/LaunchAgents/ai.openclaw.gateway.plist
rm -rf ~/.openclaw/miloco
rm -f ~/Desktop/'Miloco Console.command' ~/Desktop/'OpenClaw Chat.command' ~/Desktop/'OpenClaw-login-info.txt'
rm -rf /tmp/easy-miloco-verify ~/Desktop/easy-miloco-v0.1-macos-arm64
lsof -nP -iTCP:1810 -sTCP:LISTEN || true
lsof -nP -iTCP:18789 -sTCP:LISTEN || true
```

如果 18789 又被拉起，说明 LaunchAgent 还在；先 bootout/remove，再 kill 残留 gateway 进程。
