#!/usr/bin/env bash
set -euo pipefail

MILOCO_PORT="${MILOCO_PORT:-1810}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
OMNI_MODEL="${OMNI_MODEL:-xiaomi/mimo-v2.5}"
OMNI_BASE_URL="${OMNI_BASE_URL:-https://api.xiaomimimo.com/v1}"
STRICT_FULL=1
PRINT_BIND_URL=0
AUTHORIZE_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --print-bind-url) PRINT_BIND_URL=1; shift ;;
    --authorize-only) AUTHORIZE_ONLY=1; shift ;;
    --no-strict-full) STRICT_FULL=0; shift ;;
    --miloco-port) MILOCO_PORT="$2"; shift 2 ;;
    --openclaw-port) OPENCLAW_PORT="$2"; shift 2 ;;
    -h|--help)
      printf 'Usage: MILOCO_AUTH_PAYLOAD=... MIMO_API_KEY=... bash macos-post-auth-finish.sh\n'
      exit 0
      ;;
    *) printf '[FAIL] unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

if [ "$PRINT_BIND_URL" -eq 1 ]; then
  miloco-cli account bind --no-wait
  exit 0
fi

if [ -n "${MILOCO_AUTH_PAYLOAD:-}" ]; then
  miloco-cli account authorize "$MILOCO_AUTH_PAYLOAD"
elif [ "$AUTHORIZE_ONLY" -eq 1 ]; then
  printf '[FAIL] MILOCO_AUTH_PAYLOAD is required for --authorize-only.\n' >&2
  exit 2
fi

if [ "$AUTHORIZE_ONLY" -eq 1 ]; then
  miloco-cli account status
  exit 0
fi

pairs=()
[ -n "${MIMO_API_KEY:-}" ] && pairs+=(model.omni.api_key "$MIMO_API_KEY")
[ -n "$OMNI_MODEL" ] && pairs+=(model.omni.model "$OMNI_MODEL")
[ -n "$OMNI_BASE_URL" ] && pairs+=(model.omni.base_url "$OMNI_BASE_URL")
if [ "${#pairs[@]}" -gt 0 ]; then
  miloco-cli config set "${pairs[@]}" --no-restart
fi

miloco-cli service restart || miloco-cli service start
openclaw gateway restart || openclaw gateway start || true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validate="$script_dir/macos-miloco-validate.sh"
if [ "$STRICT_FULL" -eq 1 ]; then
  bash "$validate" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT" --strict-full
else
  bash "$validate" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT"
fi
