#!/usr/bin/env bash
set -euo pipefail

MILOCO_PORT="__MILOCO_PORT__"
OPENCLAW_PORT="__OPENCLAW_PORT__"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

menu() {
  clear
  printf 'Miloco Console\n'
  printf '1. Open Miloco dashboard\n'
  printf '2. Restart Miloco\n'
  printf '3. Restart OpenClaw\n'
  printf '4. Restart both\n'
  printf '5. Stop services\n'
  printf '6. Show status\n'
  printf '0. Exit\n'
  printf '> '
}

while true; do
  menu
  read -r choice || exit 0
  case "$choice" in
    1) open "http://127.0.0.1:$MILOCO_PORT/" || true ;;
    2) miloco-cli service restart || miloco-cli service start ;;
    3) openclaw gateway status >/tmp/easy-miloco-openclaw-console-status.log 2>&1 || true; grep -Eiq 'not installed|Service unit not found|LaunchAgent not installed' /tmp/easy-miloco-openclaw-console-status.log && openclaw gateway install || true; openclaw gateway restart || openclaw gateway start ;;
    4) openclaw gateway status >/tmp/easy-miloco-openclaw-console-status.log 2>&1 || true; grep -Eiq 'not installed|Service unit not found|LaunchAgent not installed' /tmp/easy-miloco-openclaw-console-status.log && openclaw gateway install || true; openclaw gateway restart || openclaw gateway start; miloco-cli service restart || miloco-cli service start ;;
    5) miloco-cli service stop || true; openclaw gateway stop || true ;;
    6) miloco-cli service status || true; openclaw gateway status || true; printf 'Press Enter...\n'; read -r _ || true ;;
    0) exit 0 ;;
    *) printf 'Unknown choice.\n'; sleep 1 ;;
  esac
done
