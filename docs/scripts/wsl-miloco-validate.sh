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
    fold -s -w 96 |
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
  service_status="$(run_capture 10 miloco-cli service status)"
  if printf '%s' "$service_status" | grep -Eiq '"running"[[:space:]]*:[[:space:]]*true|running=true|url=http'; then
    pass "miloco.service_status" "$service_status"
  else
    fail "miloco.service_status" "$service_status" "Run: miloco-cli service start"
  fi
fi

if command -v curl >/dev/null 2>&1; then
  health="$(run_capture 8 curl -fsS "http://127.0.0.1:${MILOCO_PORT}/health")"
  if printf '%s' "$health" | grep -q '"status":"ok"'; then
    pass "miloco.health" "$health"
  else
    fail "miloco.health" "$health" "Check server.url/server.port and service logs."
  fi
fi

if command -v openclaw >/dev/null 2>&1; then
  gateway_status="$(run_capture 10 openclaw gateway status)"
  if printf '%s' "$gateway_status" | grep -Eiq 'runtime.*running|connectivity.*ok|running'; then
    pass "openclaw.gateway_status" "$gateway_status"
  else
    fail "openclaw.gateway_status" "$gateway_status" "Run: openclaw gateway start or inspect the user systemd service."
  fi

  plugin_status="$(run_capture 10 openclaw plugins inspect miloco-openclaw-plugin)"
  if printf '%s' "$plugin_status" | grep -Eiq 'Status:[[:space:]]*loaded|loaded'; then
    pass "openclaw.miloco_plugin" "$(printf '%s\n' "$plugin_status" | grep -Ei 'Status:|Name:|Version:' | sed -n '1,8p')"
  else
    fail "openclaw.miloco_plugin" "$plugin_status" "Install/enable the miloco-openclaw-plugin, then restart gateway."
  fi
fi

if command -v curl >/dev/null 2>&1; then
  gateway_http="$(run_capture 8 curl -fsS "http://127.0.0.1:${OPENCLAW_PORT}/")"
  if [ $? -eq 0 ] && [ -n "$gateway_http" ]; then
    pass "openclaw.gateway_http" "http://127.0.0.1:${OPENCLAW_PORT}/ responded."
  else
    fail "openclaw.gateway_http" "$gateway_http" "Check openclaw gateway status and port."
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
