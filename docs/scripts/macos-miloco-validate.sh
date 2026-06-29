#!/usr/bin/env bash
set -u

MILOCO_PORT="${MILOCO_PORT:-1810}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
STRICT_FULL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --miloco-port) MILOCO_PORT="$2"; shift 2 ;;
    --openclaw-port) OPENCLAW_PORT="$2"; shift 2 ;;
    --strict-full) STRICT_FULL=1; shift ;;
    -h|--help)
      printf 'Usage: bash macos-miloco-validate.sh [--strict-full] [--miloco-port PORT] [--openclaw-port PORT]\n'
      exit 0
      ;;
    *) printf '[FAIL] unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

fail_count=0
warn_count=0
full_fail=0

pass() { printf '[PASS] %s %s\n' "$1" "${2:-}"; }
warn() { warn_count=$((warn_count + 1)); printf '[WARN] %s %s\n' "$1" "${2:-}"; }
fail() { fail_count=$((fail_count + 1)); printf '[FAIL] %s %s\n' "$1" "${2:-}"; }
full_missing() { full_fail=$((full_fail + 1)); warn "$1" "$2"; }

printf '== easy-miloco macOS validation ==\n'

if command -v miloco-cli >/dev/null 2>&1; then
  pass miloco.cli "$(command -v miloco-cli)"
else
  fail miloco.cli "not found"
fi

service_status="$(miloco-cli service status 2>&1 || true)"
if printf '%s' "$service_status" | grep -Eiq '"running"[[:space:]]*:[[:space:]]*true|running[=:]true|url=http'; then
  pass miloco.service_status "$service_status"
else
  fail miloco.service_status "$service_status"
fi

health_body="/tmp/easy-miloco-health-body.txt"
health_code="$(curl -sS --max-time 3 -o "$health_body" -w "%{http_code}" "http://127.0.0.1:$MILOCO_PORT/health" 2>/tmp/easy-miloco-health.err || true)"
health_text="$(cat "$health_body" 2>/dev/null || true)"
if [ "$health_code" = "200" ] && printf '%s' "$health_text" | grep -q '"status":"ok"'; then
  pass miloco.health "$health_text"
else
  fail miloco.health "HTTP $health_code $health_text"
fi

dashboard_code="$(curl -sS --max-time 3 -o /tmp/easy-miloco-dashboard.html -w "%{http_code}" "http://127.0.0.1:$MILOCO_PORT/" 2>/dev/null || true)"
[ "$dashboard_code" = "200" ] && pass miloco.dashboard "HTTP 200" || warn miloco.dashboard "HTTP $dashboard_code"

if command -v openclaw >/dev/null 2>&1; then
  pass openclaw.cli "$(openclaw --version 2>/dev/null | head -n 1)"
  gateway_status="$(openclaw gateway status 2>&1 || true)"
  if printf '%s' "$gateway_status" | grep -Eiq 'Connectivity probe:[[:space:]]*ok|Runtime:[[:space:]]*running|Listening:' \
    && ! printf '%s' "$gateway_status" | grep -Eiq 'not installed|Service unit not found|Connectivity probe:[[:space:]]*failed'; then
    pass openclaw.gateway "$gateway_status"
  else
    fail openclaw.gateway "$gateway_status"
  fi
  plugin_status="$(openclaw plugins inspect miloco-openclaw-plugin 2>&1 || openclaw plugins list 2>&1 || true)"
  if printf '%s' "$plugin_status" | grep -q 'miloco'; then
    pass openclaw.plugin "miloco plugin visible"
  else
    fail openclaw.plugin "$plugin_status"
  fi
else
  fail openclaw.cli "not found"
fi

account_status="$(miloco-cli account status 2>&1 || true)"
if printf '%s' "$account_status" | grep -Eiq '"is_bound"[[:space:]]*:[[:space:]]*true|is_bound[=:]true'; then
  pass miloco.account "bound"
else
  full_missing miloco.account "not bound"
fi

api_key="$(miloco-cli config get model.omni.api_key --value-only 2>/dev/null || true)"
if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
  pass miloco.model_key "configured"
else
  full_missing miloco.model_key "missing"
fi

openclaw_model_status="$(
python3 - <<'PY' 2>&1
import json
from pathlib import Path

path = Path.home() / ".openclaw" / "openclaw.json"
if not path.exists():
    print("openclaw.json missing")
    raise SystemExit(1)

data = json.loads(path.read_text(encoding="utf-8"))
primary = data.get("agents", {}).get("defaults", {}).get("model", {}).get("primary") or ""
if "/" not in primary:
    print(f"primary={primary or '<empty>'}")
    raise SystemExit(1)

provider_id, model_id = primary.split("/", 1)
providers = data.get("models", {}).get("providers", {})
provider = providers.get(provider_id) if isinstance(providers, dict) else None
if not isinstance(provider, dict):
    print(f"primary={primary} provider={provider_id} missing")
    raise SystemExit(1)

base_url = provider.get("baseUrl") or provider.get("baseURL") or ""
api_key = provider.get("apiKey") or ""
api = provider.get("api") or ""
rows = provider.get("models")
has_model_row = any(isinstance(row, dict) and row.get("id") == model_id for row in rows) if isinstance(rows, list) else False

print(f"primary={primary}")
print(f"provider={provider_id}")
print(f"api={api or '<empty>'}")
print(f"baseUrl={'configured' if isinstance(base_url, str) and base_url else 'empty'}")
print(f"apiKey={'configured' if isinstance(api_key, str) and api_key else 'empty'}")
print(f"modelRow={'configured' if has_model_row else 'missing'}")

if not base_url or not api_key or not has_model_row:
    raise SystemExit(1)
PY
)"
if [ $? -eq 0 ]; then
  pass openclaw.main_chat_model "$openclaw_model_status"
else
  full_missing openclaw.main_chat_model "$openclaw_model_status"
fi

device_list="$(miloco-cli device list 2>&1 || true)"
if printf '%s' "$device_list" | awk 'END { exit NR > 1 ? 0 : 1 }'; then
  pass miloco.devices "device list has rows"
else
  full_missing miloco.devices "no device rows"
fi

camera_list="$(miloco-cli scope camera list --pretty 2>&1 || miloco-cli scope camera list 2>&1 || true)"
if printf '%s' "$camera_list" | grep -Eiq 'did|camera|in_use|connected'; then
  pass miloco.cameras "camera scope visible"
else
  warn miloco.cameras "no camera scope evidence"
fi

basic_ready=no
full_ready=no
[ "$fail_count" -eq 0 ] && basic_ready=yes
[ "$fail_count" -eq 0 ] && [ "$full_fail" -eq 0 ] && full_ready=yes

printf 'BASIC_READY=%s\n' "$basic_ready"
printf 'FULL_READY=%s\n' "$full_ready"
printf 'WARN_COUNT=%s\n' "$warn_count"
printf 'FAIL_COUNT=%s\n' "$fail_count"
printf 'FULL_FAIL_COUNT=%s\n' "$full_fail"

if [ "$fail_count" -ne 0 ]; then
  exit 2
fi
if [ "$STRICT_FULL" -eq 1 ] && [ "$full_fail" -ne 0 ]; then
  exit 3
fi
exit 0
