# macOS 懒人包验证记录

## 2026-06-28 v0.1 arm64 本地打包验证

分支：`macOS`

产物：

```text
dist/macos/easy-miloco-v0.1-macos-arm64.zip
```

包大小：

```text
65M
```

SHA-256：

```text
97abd80bc6fdeffda93e0609b0343a966025860da30d5a63ee44eff5fc897f44
```

构建命令：

```bash
macos/build-release.sh --version v0.1 --artifact-version 2026.6.28 --arch arm64
```

复用 runtime 重打包命令：

```bash
macos/build-release.sh --version v0.1 --artifact-version 2026.6.28 --arch arm64 --skip-build
```

包内关键文件已验证存在：

```text
install.command
agent-prompt.md
manifest.json
payload/install.sh
payload/miloco-darwin-arm64-2026.6.28.tar.gz
scripts/macos/macos-preflight.sh
scripts/macos/macos-miloco-validate.sh
scripts/macos/macos-post-auth-finish.sh
```

包内元数据检查：

```text
BAD_META []
```

本机预检：

```text
[PASS] os Darwin arch=arm64
[PASS] arch arm64
[PASS] macos.version 14.6.1
[PASS] cmd.bash /bin/bash
[PASS] cmd.curl /usr/bin/curl
[PASS] cmd.tar /usr/bin/tar
[PASS] cmd.lsof /usr/sbin/lsof
[PASS] cmd.python3 /usr/local/bin/python3
[PASS] cmd.uv available
[PASS] node v24.12.0 npm=11.6.2
[WARN] openclaw not found; lazy installer will try to install it
[PASS] port.18860 free
[PASS] port.18789 free
[PASS] package.manifest
[PASS] package.install_sh
[PASS] package.bundle miloco-darwin-arm64-
[PASS] package.quarantine clear
WARN_COUNT=1
FAIL_COUNT=0
```

验证边界：

- 本轮已验证构建、包结构、SHA、预检和 Agent 提示词入包。
- 本轮未在当前 Mac 上执行完整 `install.command`，因为完整安装会修改本机 `~/.openclaw`、安装 OpenClaw CLI、安装 uv tools、启动 Miloco/OpenClaw 服务并进入账号/模型交互。
- 下一轮若要做真实安装验收，应使用干净 macOS 用户或测试机，执行 `install.command` 后再运行 `scripts/macos/macos-miloco-validate.sh --strict-full`。
