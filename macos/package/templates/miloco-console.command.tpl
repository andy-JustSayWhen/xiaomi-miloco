#!/usr/bin/env bash
set -euo pipefail

MILOCO_PORT="__MILOCO_PORT__"
OPENCLAW_PORT="__OPENCLAW_PORT__"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

menu() {
  clear
  printf 'Miloco Console\n'
  printf '1. Open Miloco dashboard\n'
  printf '2. Open OpenClaw Chat\n'
  printf '3. Open both panels\n'
  printf '4. Restart Miloco\n'
  printf '5. Restart OpenClaw\n'
  printf '6. Restart both\n'
  printf '7. Stop services\n'
  printf '8. Show status\n'
  printf '9. Show logs\n'
  printf '10. How to use\n'
  printf '0. Exit\n'
  printf '> '
}

open_openclaw() {
  url="$(openclaw dashboard --no-open --yes 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n 1 || true)"
  [ -n "$url" ] || url="http://127.0.0.1:$OPENCLAW_PORT/"
  open "$url" || true
  printf 'OpenClaw: %s\n' "$url"
}

restart_openclaw() {
  openclaw gateway status >/tmp/easy-miloco-openclaw-console-status.log 2>&1 || true
  grep -Eiq 'not installed|Service unit not found|LaunchAgent not installed' /tmp/easy-miloco-openclaw-console-status.log && openclaw gateway install || true
  openclaw gateway restart || openclaw gateway start
}

pause() {
  printf 'Press Enter...\n'
  read -r _ || true
}

while true; do
  menu
  read -r choice || exit 0
  case "$choice" in
    1) open "http://127.0.0.1:$MILOCO_PORT/" || true ;;
    2) open_openclaw; pause ;;
    3) open "http://127.0.0.1:$MILOCO_PORT/" || true; open_openclaw; pause ;;
    4) miloco-cli service restart || miloco-cli service start; pause ;;
    5) restart_openclaw; pause ;;
    6) restart_openclaw; miloco-cli service restart || miloco-cli service start; pause ;;
    7) miloco-cli service stop || true; openclaw gateway stop || true; pause ;;
    8) miloco-cli service status || true; openclaw gateway status || true; pause ;;
    9) printf 'Miloco logs: %s\n' "$HOME/.openclaw/miloco/log/"; printf 'OpenClaw log: %s\n' "$HOME/Library/Logs/openclaw/gateway.log"; open "$HOME/.openclaw/miloco/log/" || true; pause ;;
    10) printf 'How to use:\n'; printf '1. Open Miloco dashboard to inspect devices, cameras, perception status, and settings.\n'; printf '2. Open OpenClaw Chat to ask the assistant about the home.\n'; printf '3. Try asking: 家里有几个摄像头？画面如何？\n'; pause ;;
    0) exit 0 ;;
    *) printf 'Unknown choice.\n'; sleep 1 ;;
  esac
done
