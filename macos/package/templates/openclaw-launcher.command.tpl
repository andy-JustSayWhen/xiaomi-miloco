#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_PORT="__OPENCLAW_PORT__"
OPENCLAW_INFO_PATH="__OPENCLAW_INFO_PATH__"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

read_openclaw_token() {
  python3 - <<'PY' 2>/dev/null || true
import json
from pathlib import Path
home = Path.home()

def read_json(path):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}

def text(value):
    return value.strip() if isinstance(value, str) else ""

miloco = read_json(home / ".openclaw" / "miloco" / "config.json")
openclaw = read_json(home / ".openclaw" / "openclaw.json")
candidates = []
agent = miloco.get("agent") if isinstance(miloco, dict) else {}
if isinstance(agent, dict):
    candidates.append(agent.get("auth_bearer"))
gateway = openclaw.get("gateway") if isinstance(openclaw, dict) else {}
auth = gateway.get("auth") if isinstance(gateway, dict) else {}
if isinstance(auth, dict):
    candidates.extend([auth.get("token"), auth.get("password"), auth.get("bearer")])
for candidate in candidates:
    token = text(candidate)
    if token:
        print(token)
        break
PY
}

url_encode() {
  value="$1"
  VALUE="$value" python3 - <<'PY' 2>/dev/null || true
import os
from urllib.parse import quote
print(quote(os.environ.get("VALUE", ""), safe=""))
PY
}

openclaw_autologin_url() {
  token="$(read_openclaw_token)"
  if [ -n "$token" ]; then
    encoded_token="$(url_encode "$token")"
    if [ -n "$encoded_token" ]; then
      printf 'http://127.0.0.1:%s/#token=%s\n' "$OPENCLAW_PORT" "$encoded_token"
      return 0
    fi
  fi
  dashboard_url="$(openclaw dashboard --no-open --yes 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n 1 || true)"
  if printf '%s' "$dashboard_url" | grep -Eq '(^|[#?&])token='; then
    printf '%s\n' "$dashboard_url"
    return 0
  fi
  printf 'http://127.0.0.1:%s/\n' "$OPENCLAW_PORT"
}

write_openclaw_info_file() {
  token="$(read_openclaw_token)"
  launch_url="$(openclaw_autologin_url)"
  token_value="$token"
  [ -n "$token_value" ] || token_value="(empty)"
  {
    printf 'OpenClaw 登录信息\n\n'
    printf '推荐直接打开: %s\n' "$launch_url"
    printf '仪表板地址: http://127.0.0.1:%s/\n' "$OPENCLAW_PORT"
    printf 'WebSocket URL: ws://127.0.0.1:%s\n' "$OPENCLAW_PORT"
    printf 'Gateway Token: %s\n\n' "$token_value"
    printf '最省事的用法：\n'
    printf '1. 直接双击桌面的 OpenClaw Chat.command；它会刷新本文件，并用带 token 的直达地址打开。\n'
    printf '2. 如果页面仍提示登录，把上面的“推荐直接打开”整段复制到浏览器地址栏。\n'
    printf '3. 如果页面里 token 仍为空，把上面的 Gateway Token 整段粘贴进去。\n\n'
    printf '如何获取 / 刷新这些信息：\n'
    printf '4. 重新双击 OpenClaw Chat.command。\n'
    printf '5. 或在终端运行：openclaw dashboard --no-open --yes\n'
    printf '6. 只想看 token，可运行：openclaw config get gateway.auth.token\n\n'
    printf '如何管理 / 修改：\n'
    printf '7. 当前配置文件：~/.openclaw/openclaw.json\n'
    printf '8. 重点字段：gateway.auth.token\n'
    printf '9. 改完后重开 OpenClaw Chat.command，或重新运行 dashboard 命令刷新。\n\n'
    printf '这份文件会在每次打开 OpenClaw Chat.command 时自动刷新。\n'
  } > "$OPENCLAW_INFO_PATH"
}

openclaw gateway status >/tmp/easy-miloco-openclaw-launcher-status.log 2>&1 || true
grep -Eiq 'not installed|Service unit not found|LaunchAgent not installed' /tmp/easy-miloco-openclaw-launcher-status.log && openclaw gateway install >>/tmp/easy-miloco-openclaw-launcher.log 2>&1 || true
openclaw gateway restart >/tmp/easy-miloco-openclaw-launcher.log 2>&1 || openclaw gateway start >>/tmp/easy-miloco-openclaw-launcher.log 2>&1 || true
write_openclaw_info_file
url="$(openclaw_autologin_url)"
open "$url" || true
printf 'OpenClaw: %s\n' "$url"
printf 'Login info: %s\n' "$OPENCLAW_INFO_PATH"
printf 'Press Enter to close this window.\n'
read -r _ || true
