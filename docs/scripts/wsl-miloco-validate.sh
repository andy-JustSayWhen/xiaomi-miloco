#!/usr/bin/env bash
set -u

MILOCO_PORT="${MILOCO_PORT:-18860}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
MILOCO_HOME="${MILOCO_HOME:-$HOME/.openclaw/miloco}"
STRICT_FULL=0

for arg in "$@"; do
  case "$arg" in
    --strict-full) STRICT_FULL=1 ;;
    --help|-h)
      cat <<'USAGE'
Usage:
  MILOCO_PORT=18860 OPENCLAW_PORT=18789 bash wsl-miloco-validate.sh [--strict-full]

Exit codes:
  0: basic service checks passed, even if full account/model readiness is missing
  2: basic service checks failed
  3: --strict-full was set and full readiness failed
USAGE
      exit 0
      ;;
  esac
done

export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
BASIC_READY=yes
FULL_READY=yes

print_field() {
  local label="$1"
  local text="${2:-}"
  local max_lines="${3:-24}"
  local line_count

  [ -z "$text" ] && return
  printf '  %s:\n' "$label"
  line_count="$(printf '%s\n' "$text" | sed 's/\r//g' | awk 'NF { c++ } END { print c + 0 }')"
  printf '%s\n' "$text" |
    sed 's/\r//g' |
    sed 's/[[:space:]][[:space:]]*/ /g' |
    sed 's/^ //; s/ $//' |
    awk 'NF { print }' |
    head -n "$max_lines" |
    fold -s -w 72 |
    sed 's/^/    /'
  if [ "${line_count:-0}" -gt "$max_lines" ]; then
    printf '    ... (%s line(s) omitted)\n' "$((line_count - max_lines))"
  fi
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$1"
  print_field "detail" "${2:-}"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[WARN] %s\n' "$1"
  print_field "detail" "${2:-}"
  print_field "hint" "${3:-}" 8
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  BASIC_READY=no
  printf '[FAIL] %s\n' "$1"
  print_field "detail" "${2:-}"
  print_field "hint" "${3:-}" 8
}

mark_full_missing() {
  FULL_READY=no
}

run_capture() {
  local timeout_seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" "$@" 2>&1
  else
    "$@" 2>&1
  fi
}

printf '== WSL Miloco validation ==\n'
printf 'generated_at=%s\n' "$(date -Is 2>/dev/null || date)"
printf 'user=%s home=%s\n' "$(id -un 2>/dev/null || whoami)" "$HOME"

if [ -r /etc/os-release ]; then
  os_line="$(grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release | tr '\n' ' ' | sed 's/"//g')"
  pass "wsl.os" "$os_line arch=$(uname -m)"
else
  warn "wsl.os" "/etc/os-release not found."
fi

if command -v ip >/dev/null 2>&1; then
  ip_br="$(ip -br addr 2>/dev/null | sed -n '1,12p')"
  pass "wsl.network_interfaces" "$ip_br"
else
  warn "wsl.network_interfaces" "ip command not found."
fi

for cmd in curl miloco-cli openclaw; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "cmd.$cmd" "$(command -v "$cmd")"
  else
    fail "cmd.$cmd" "$cmd not found in PATH." "Check install logs and PATH."
  fi
done

if command -v miloco-cli >/dev/null 2>&1; then
  service_status=""
  service_status_ok=0
  service_attempt=0
  for service_attempt in $(seq 1 30); do
    service_status="$(run_capture 10 miloco-cli service status)"
    if printf '%s' "$service_status" | grep -Eiq '"running"[[:space:]]*:[[:space:]]*true|running=true|url=http'; then
      service_status_ok=1
      break
    fi
    sleep 1
  done
  if [ "$service_status_ok" -eq 1 ]; then
    pass "miloco.service_status" "attempt=${service_attempt} ${service_status}"
  else
    fail "miloco.service_status" "$service_status" "Run: miloco-cli service start"
  fi
fi

if command -v curl >/dev/null 2>&1; then
  health=""
  health_code=""
  health_err=""
  health_ok=0
  health_degraded=0
  health_attempt=0
  health_body_file="${TMPDIR:-/tmp}/miloco-health-validate-body.$$"
  health_err_file="${TMPDIR:-/tmp}/miloco-health-validate-curl.$$"
  for health_attempt in $(seq 1 20); do
    health_code="$(curl -sS --max-time 3 -o "$health_body_file" -w "%{http_code}" "http://127.0.0.1:${MILOCO_PORT}/health" 2>"$health_err_file" || true)"
    health="$(cat "$health_body_file" 2>/dev/null || true)"
    health_err="$(cat "$health_err_file" 2>/dev/null || true)"
    if [ "$health_code" = "200" ] && printf '%s' "$health" | grep -q '"status":"ok"'; then
      health_ok=1
      break
    fi
    if [ "$health_code" = "503" ] && printf '%s' "$health" | grep -Eq '"status":"(unhealthy|unknown)"'; then
      health_degraded=1
    fi
    sleep 1
  done
  rm -f "$health_body_file" "$health_err_file" 2>/dev/null || true
  if [ "$health_ok" -eq 1 ]; then
    pass "miloco.health" "attempt=${health_attempt} ${health}"
  elif [ "$health_degraded" -eq 1 ] && [ "$STRICT_FULL" -eq 0 ]; then
    mark_full_missing
    warn "miloco.health" "HTTP ${health_code} ${health}" "Miloco API is reachable, but /health is not ok yet. Continue basic setup and inspect node diagnostics after account/API key configuration."
  elif [ "$STRICT_FULL" -eq 0 ] && [ "${service_status_ok:-0}" -eq 1 ] && { [ "$health_code" = "502" ] || [ "$health_code" = "503" ]; }; then
    mark_full_missing
    warn "miloco.health" "HTTP ${health_code} ${health} ${health_err}" "Miloco service is running and the port is listening, but /health is still warming up. Continue basic setup, then rerun validation after account/API configuration."
  else
    fail "miloco.health" "HTTP ${health_code} ${health} ${health_err}" "Miloco did not answer /health with status ok within 20 seconds. Check server.url/server.port and service logs."
  fi
fi

if command -v openclaw >/dev/null 2>&1; then
  gateway_status="$(run_capture 10 openclaw gateway status)"
  if printf '%s' "$gateway_status" | grep -Eiq 'runtime.*running|connectivity.*ok|running'; then
    gateway_status_ok=1
    pass "openclaw.gateway_status" "$gateway_status"
  else
    gateway_status_ok=0
    fail "openclaw.gateway_status" "$gateway_status" "Run: openclaw gateway start or inspect the user systemd service."
  fi

  plugin_status="$(run_capture 10 openclaw plugins inspect miloco-openclaw-plugin)"
  if printf '%s' "$plugin_status" | grep -Eiq 'Status:[[:space:]]*loaded|loaded'; then
    pass "openclaw.miloco_plugin" "$(printf '%s\n' "$plugin_status" | grep -Ei 'Status:|Name:|Version:' | sed -n '1,8p')"
  else
    fail "openclaw.miloco_plugin" "$plugin_status" "Install/enable the miloco-openclaw-plugin, then restart gateway."
  fi

  openclaw_model_status="$(python3 - <<'PY' 2>&1
import json
from pathlib import Path

path = Path.home() / ".openclaw" / "openclaw.json"
if not path.exists():
    print("openclaw.json missing")
    raise SystemExit(1)

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"openclaw.json unreadable: {exc}")
    raise SystemExit(1)

agents = data.get("agents") if isinstance(data, dict) else {}
defaults = agents.get("defaults") if isinstance(agents, dict) else {}
model = defaults.get("model") if isinstance(defaults, dict) else {}
primary = model.get("primary") if isinstance(model, dict) else ""
if not isinstance(primary, str) or "/" not in primary:
    print(f"primary={primary or '<empty>'}")
    raise SystemExit(1)

provider_id, model_id = primary.split("/", 1)
models = data.get("models") if isinstance(data, dict) else {}
providers = models.get("providers") if isinstance(models, dict) else {}
provider = providers.get(provider_id) if isinstance(providers, dict) else {}
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
    pass "openclaw.main_chat_model" "$openclaw_model_status"
  else
    mark_full_missing
    warn "openclaw.main_chat_model" "$openclaw_model_status" "Set agents.defaults.model.primary plus models.providers.<provider>.baseUrl/apiKey/models[] in ~/.openclaw/openclaw.json."
  fi
fi

if command -v curl >/dev/null 2>&1; then
  gateway_http_code=""
  gateway_http_body=""
  gateway_http_err=""
  for gateway_attempt in $(seq 1 20); do
    body_file="/tmp/miloco-openclaw-gateway-body.$$"
    err_file="/tmp/miloco-openclaw-gateway-err.$$"
    gateway_http_code="$(curl -sS -o "$body_file" -w "%{http_code}" --max-time 3 "http://127.0.0.1:${OPENCLAW_PORT}/" 2>"$err_file" || true)"
    gateway_http_body="$(head -c 500 "$body_file" 2>/dev/null || true)"
    gateway_http_err="$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$body_file" "$err_file" 2>/dev/null || true
    if printf '%s' "$gateway_http_code" | grep -Eq '^[234][0-9][0-9]$'; then
      break
    fi
    sleep 1
  done
  if printf '%s' "$gateway_http_code" | grep -Eq '^[234][0-9][0-9]$'; then
    pass "openclaw.gateway_http" "http://127.0.0.1:${OPENCLAW_PORT}/ responded with HTTP ${gateway_http_code}."
  elif [ "${gateway_status_ok:-0}" -eq 1 ]; then
    mark_full_missing
    warn "openclaw.gateway_http" "HTTP ${gateway_http_code} ${gateway_http_body} ${gateway_http_err}" "OpenClaw gateway status is running, but root HTTP probe did not respond in time. Continue setup and use OpenClaw dashboard shortcut after configuration."
  else
    fail "openclaw.gateway_http" "HTTP ${gateway_http_code} ${gateway_http_body} ${gateway_http_err}" "Check openclaw gateway status and port."
  fi
fi

if command -v miloco-cli >/dev/null 2>&1; then
  account_status="$(run_capture 10 miloco-cli account status)"
  if printf '%s' "$account_status" | grep -Eq '"is_bound"[[:space:]]*:[[:space:]]*true'; then
    pass "miloco.account" "$account_status"
  else
    mark_full_missing
    warn "miloco.account" "$account_status" "Finish Xiaomi OAuth authorization: miloco-cli account bind/authorize."
  fi

  api_key="$(run_capture 10 miloco-cli config get model.omni.api_key --value-only | tr -d '\r\n[:space:]')"
  if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
    pass "miloco.omni_api_key" "configured"
  else
    mark_full_missing
    warn "miloco.omni_api_key" "empty" "Set model.omni.api_key and restart Miloco."
  fi

  devices="$(run_capture 45 miloco-cli device list)"
  device_rows="$(printf '%s\n' "$devices" | grep -Ev '^[[:space:]]*$|^#' | wc -l | tr -d ' ')"
  if [ "${device_rows:-0}" -gt 0 ]; then
    pass "miloco.devices" "$device_rows device row(s)."
  else
    mark_full_missing
    warn "miloco.devices" "$devices" "Expected before Xiaomi account is bound; after binding, device rows should appear."
  fi

  cameras="$(run_capture 15 miloco-cli scope camera list --pretty)"
  if printf '%s' "$cameras" | grep -Eiq '"error"|cannot connect|connection refused'; then
    mark_full_missing
    warn "miloco.cameras" "$cameras" "Miloco backend is not reachable. Start Miloco first, then check camera scope."
  elif printf '%s' "$cameras" | grep -Eq '"data"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]|\[\s*\]'; then
    mark_full_missing
    warn "miloco.cameras" "$cameras" "Camera scope is empty. Bind account, select home, then enable target cameras."
  elif [ -n "$cameras" ]; then
    pass "miloco.cameras" "$(printf '%s' "$cameras" | head -c 500)"
  else
    mark_full_missing
    warn "miloco.cameras" "empty output" "Check account binding and logs."
  fi
fi

if [ -d "$MILOCO_HOME" ]; then
  pass "miloco.home" "$MILOCO_HOME"
  backend_log="$MILOCO_HOME/log/miloco-backend.log"
  if [ -r "$backend_log" ]; then
    log_hits="$(tail -n 400 "$backend_log" 2>/dev/null | grep -Eih 'access token is empty|API Key.*未配置|api key.*not configured' | tail -n 8 || true)"
  else
    log_hits="$(find "$MILOCO_HOME" -maxdepth 4 -type f \( -name '*.log' -o -name '*.txt' \) -print0 2>/dev/null | xargs -0 grep -Eih 'access token is empty|API Key.*未配置|api key.*not configured' 2>/dev/null | tail -n 8 || true)"
  fi
  if [ -n "$log_hits" ]; then
    warn "miloco.logs_known_gaps" "$log_hits" "Recent known-gap strings usually mean Xiaomi OAuth or Omni API key is still missing."
  else
    pass "miloco.logs_known_gaps" "No recent known-gap strings found in active Miloco logs."
  fi
else
  warn "miloco.home" "$MILOCO_HOME not found."
fi

printf 'BASIC_READY=%s\n' "$BASIC_READY"
printf 'FULL_READY=%s\n' "$FULL_READY"
printf 'PASS_COUNT=%s\n' "$PASS_COUNT"
printf 'WARN_COUNT=%s\n' "$WARN_COUNT"
printf 'FAIL_COUNT=%s\n' "$FAIL_COUNT"

if [ "$BASIC_READY" != "yes" ]; then
  exit 2
fi

if [ "$STRICT_FULL" -eq 1 ] && [ "$FULL_READY" != "yes" ]; then
  exit 3
fi

exit 0
