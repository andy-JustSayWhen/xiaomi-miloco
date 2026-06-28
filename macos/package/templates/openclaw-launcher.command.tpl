#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_PORT="__OPENCLAW_PORT__"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

openclaw gateway restart >/tmp/easy-miloco-openclaw-launcher.log 2>&1 || openclaw gateway start >>/tmp/easy-miloco-openclaw-launcher.log 2>&1 || true
url="$(openclaw dashboard --no-open --yes 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n 1 || true)"
if [ -z "$url" ]; then
  url="http://127.0.0.1:$OPENCLAW_PORT/"
fi
open "$url" || true
printf 'OpenClaw: %s\n' "$url"
printf 'Press Enter to close this window.\n'
read -r _ || true
