#!/usr/bin/env bash
set -u

MILOCO_PORT="${MILOCO_PORT:-18860}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
MILOCO_HOME="${MILOCO_HOME:-$HOME/.openclaw/miloco}"
MILOCO_AUTH_PAYLOAD="${MILOCO_AUTH_PAYLOAD:-}"
MIMO_API_KEY="${MIMO_API_KEY:-}"
OMNI_MODEL="${OMNI_MODEL:-xiaomi/mimo-v2.5}"
OMNI_BASE_URL="${OMNI_BASE_URL:-https://api.xiaomimimo.com/v1}"
MILOCO_HOME_ID="${MILOCO_HOME_ID:-}"
MILOCO_CAMERA_DIDS="${MILOCO_CAMERA_DIDS:-}"
PRINT_BIND_URL=0
DRY_RUN=0
STRICT_FULL=1

usage() {
  cat <<'USAGE'
Usage:
  bash wsl-post-auth-finish.sh --print-bind-url
  MILOCO_AUTH_PAYLOAD='<payload>' MIMO_API_KEY='<key>' bash wsl-post-auth-finish.sh

Environment variables:
  MILOCO_AUTH_PAYLOAD   Xiaomi OAuth callback payload copied from the bind page
  MIMO_API_KEY          MiMo / Omni API key
  OMNI_MODEL            Default: xiaomi/mimo-v2.5
  OMNI_BASE_URL         Default: https://api.xiaomimimo.com/v1
  MILOCO_HOME_ID        Optional home_id to switch after account binding
  MILOCO_CAMERA_DIDS    Optional whitespace-separated camera did list to enable
  MILOCO_PORT           Default: 18860
  OPENCLAW_PORT         Default: 18789

Options:
  --print-bind-url      Print a fresh Xiaomi account bind URL and exit
  --dry-run             Show what would run without changing account/config/services
  --no-strict-full      Do not fail the final validation when full readiness is still missing
  --help, -h            Show this help

Exit codes:
  0: finished successfully
  2: missing required inputs or basic command failure
  3: final full validation failed
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --print-bind-url) PRINT_BIND_URL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --no-strict-full) STRICT_FULL=0 ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S 2>/dev/null || date)" "$*"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing command: %s\n' "$1" >&2
    exit 2
  fi
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY_RUN] %s\n' "$*"
  else
    "$@"
  fi
}

need_cmd curl
need_cmd miloco-cli

if [ "$PRINT_BIND_URL" -eq 1 ]; then
  log "Generating Xiaomi account bind URL"
  miloco-cli account bind --no-wait
  exit $?
fi

need_cmd openclaw

log "Pre-checking Miloco service"
miloco-cli service status || {
  log "Miloco service status failed; trying restart"
  run_cmd miloco-cli service restart
}

health="$(curl -fsS --max-time 10 "http://127.0.0.1:${MILOCO_PORT}/health" 2>&1 || true)"
if ! printf '%s' "$health" | grep -q '"status":"ok"'; then
  printf 'Miloco health check failed on port %s: %s\n' "$MILOCO_PORT" "$health" >&2
  exit 2
fi
log "Miloco health ok on port ${MILOCO_PORT}"

account_before="$(miloco-cli account status 2>&1 || true)"
if printf '%s' "$account_before" | grep -Eq '"is_bound"[[:space:]]*:[[:space:]]*true'; then
  log "Xiaomi account is already bound; authorization step will be skipped"
else
  if [ -z "$MILOCO_AUTH_PAYLOAD" ]; then
    printf 'Missing MILOCO_AUTH_PAYLOAD and account is not bound.\n' >&2
    printf 'Run: bash wsl-post-auth-finish.sh --print-bind-url\n' >&2
    exit 2
  fi
  log "Authorizing Xiaomi account"
  run_cmd miloco-cli account authorize --pretty "$MILOCO_AUTH_PAYLOAD"
fi

if [ -z "$MIMO_API_KEY" ]; then
  printf 'Missing MIMO_API_KEY.\n' >&2
  exit 2
fi

log "Writing Omni model config: model=${OMNI_MODEL}, base_url=${OMNI_BASE_URL}, api_key_length=${#MIMO_API_KEY}"
run_cmd miloco-cli config set \
  model.omni.model "$OMNI_MODEL" \
  model.omni.base_url "$OMNI_BASE_URL" \
  model.omni.api_key "$MIMO_API_KEY" \
  --no-restart

if [ -n "$MILOCO_HOME_ID" ]; then
  log "Switching Miloco home: ${MILOCO_HOME_ID}"
  run_cmd miloco-cli scope home switch --pretty "$MILOCO_HOME_ID"
fi

log "Restarting Miloco backend"
run_cmd miloco-cli service restart

log "Restarting OpenClaw gateway"
run_cmd openclaw gateway restart

log "Account status"
miloco-cli account status || true

log "Current homes"
miloco-cli scope home list --pretty || true

log "Device list"
miloco-cli device list || true

log "Camera scope"
miloco-cli scope camera list --pretty || true

if [ -n "$MILOCO_CAMERA_DIDS" ]; then
  log "Enabling camera dids: ${MILOCO_CAMERA_DIDS}"
  # shellcheck disable=SC2086
  run_cmd miloco-cli scope camera enable --pretty $MILOCO_CAMERA_DIDS
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
validator="${script_dir}/wsl-miloco-validate.sh"
if [ -x "$validator" ] || [ -f "$validator" ]; then
  log "Running final validation"
  if [ "$STRICT_FULL" -eq 1 ]; then
    MILOCO_PORT="$MILOCO_PORT" OPENCLAW_PORT="$OPENCLAW_PORT" bash "$validator" --strict-full
    final_code=$?
  else
    MILOCO_PORT="$MILOCO_PORT" OPENCLAW_PORT="$OPENCLAW_PORT" bash "$validator"
    final_code=$?
  fi
  if [ "$final_code" -ne 0 ]; then
    exit "$final_code"
  fi
else
  log "Validation script not found at ${validator}; skipping final validation"
fi

log "Post-auth finish completed"
exit 0
