#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MILOCO_PORT="${MILOCO_PORT:-1810}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

say_step() {
  printf '\n== %s ==\n' "$1"
}

fail() {
  printf '\n[FAIL] %s\n' "$1" >&2
  printf 'Press Enter to close this window.\n' >&2
  read -r _ || true
  exit 1
}

need_file() {
  [ -f "$1" ] || fail "Missing required file: $1"
}

find_bundle() {
  arch="$(uname -m)"
  case "$arch" in
    arm64) pattern="miloco-darwin-arm64-" ;;
    x86_64) pattern="miloco-darwin-x86_64-" ;;
    *) fail "Unsupported macOS architecture: $arch" ;;
  esac
  find "$ROOT/payload" -maxdepth 1 -type f -name "${pattern}*.tar.gz" | head -n 1
}

remove_quarantine_if_present() {
  if command -v xattr >/dev/null 2>&1 && xattr -r "$ROOT" 2>/dev/null | grep -q 'com.apple.quarantine'; then
    say_step "Removing macOS quarantine flag"
    xattr -dr com.apple.quarantine "$ROOT" 2>/dev/null || true
  fi
}

ensure_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$HOME/.openclaw/bin"
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    say_step "Installing OpenClaw CLI with npm"
    npm_prefix="$HOME/.openclaw/tools/npm-openclaw"
    mkdir -p "$npm_prefix"
    if npm install --prefix "$npm_prefix" openclaw@latest; then
      if [ -x "$npm_prefix/node_modules/.bin/openclaw" ]; then
        ln -sf "$npm_prefix/node_modules/.bin/openclaw" "$HOME/.openclaw/bin/openclaw"
        hash -r || true
        command -v openclaw >/dev/null 2>&1 && return 0
      fi
    fi
    printf '[WARN] npm OpenClaw install failed; falling back to official installer.\n' >&2
  fi
  say_step "Installing OpenClaw CLI"
  if ! command -v curl >/dev/null 2>&1; then
    fail "curl is required to install OpenClaw."
  fi
  tmp="/tmp/openclaw-install-cli-$$.sh"
  if ! curl -fsSL https://openclaw.ai/install-cli.sh -o "$tmp"; then
    fail "Failed to download https://openclaw.ai/install-cli.sh"
  fi
  if ! bash "$tmp" --prefix "$HOME/.openclaw"; then
    fail "OpenClaw CLI installer failed."
  fi
  rm -f "$tmp"
  hash -r || true
  command -v openclaw >/dev/null 2>&1 || fail "openclaw is still not available after install."
}

prime_payload_cache() {
  bundle="$1"
  version="$(awk -F'"' '/"version"[[:space:]]*:/ {print $4; exit}' "$ROOT/manifest.json")"
  [ -n "$version" ] || version="0.0.0"
  cache="${MILOCO_HOME:-$HOME/.openclaw/miloco}/.install-cache/$version"
  say_step "Preparing local Miloco payload"
  rm -rf "$cache"
  mkdir -p "$cache"
  tar -xzf "$bundle" -C "$cache"
}

start_openclaw_gateway() {
  openclaw gateway status >/tmp/easy-miloco-macos-openclaw-status.log 2>&1 || true
  if grep -Eiq 'not installed|Service unit not found|LaunchAgent not installed' /tmp/easy-miloco-macos-openclaw-status.log; then
    openclaw gateway install >/tmp/easy-miloco-macos-openclaw-install.log 2>&1 || true
  fi
  openclaw gateway restart >/tmp/easy-miloco-macos-openclaw-restart.log 2>&1 \
    || openclaw gateway start >/tmp/easy-miloco-macos-openclaw-start.log 2>&1 \
    || true
}

install_desktop_helpers() {
  desktop="$HOME/Desktop"
  [ -d "$desktop" ] || return 0
  console="$desktop/Miloco Console.command"
  openclaw_entry="$desktop/OpenClaw Chat.command"
  info="$desktop/OpenClaw-login-info.txt"

  sed \
    -e "s#__MILOCO_PORT__#$MILOCO_PORT#g" \
    -e "s#__OPENCLAW_PORT__#$OPENCLAW_PORT#g" \
    "$ROOT/scripts/macos/templates/miloco-console.command.tpl" > "$console"
  chmod +x "$console"

  sed \
    -e "s#__OPENCLAW_PORT__#$OPENCLAW_PORT#g" \
    "$ROOT/scripts/macos/templates/openclaw-launcher.command.tpl" > "$openclaw_entry"
  chmod +x "$openclaw_entry"

  token="$(openclaw config get gateway.auth.token 2>/dev/null || true)"
  {
    printf 'Miloco URL: http://127.0.0.1:%s/\n' "$MILOCO_PORT"
    printf 'OpenClaw URL: http://127.0.0.1:%s/\n' "$OPENCLAW_PORT"
    printf 'OpenClaw token: %s\n' "$token"
    printf 'Recommended: double-click OpenClaw Chat.command, then open Miloco dashboard.\n'
  } > "$info"

  printf '[OK] Desktop shortcuts created:\n'
  printf '  %s\n' "$console"
  printf '  %s\n' "$openclaw_entry"
  printf '  %s\n' "$info"
}

open_dashboards() {
  miloco_url="http://127.0.0.1:$MILOCO_PORT/"
  openclaw_url="$(openclaw dashboard --no-open --yes 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n 1 || true)"
  [ -n "$openclaw_url" ] || openclaw_url="http://127.0.0.1:$OPENCLAW_PORT/"

  printf '[OK] Opening Miloco dashboard: %s\n' "$miloco_url"
  open "$miloco_url" >/tmp/easy-miloco-open-miloco.log 2>&1 || true
  printf '[OK] Opening OpenClaw dashboard: %s\n' "$openclaw_url"
  open "$openclaw_url" >/tmp/easy-miloco-open-openclaw.log 2>&1 || true
}

say_step "Checking package"
need_file "$ROOT/manifest.json"
need_file "$ROOT/payload/install.sh"
need_file "$ROOT/scripts/macos/macos-preflight.sh"
need_file "$ROOT/scripts/macos/macos-miloco-validate.sh"
bundle="$(find_bundle)"
[ -n "$bundle" ] || fail "No matching macOS payload found in payload/."

remove_quarantine_if_present

say_step "Running preflight"
bash "$ROOT/scripts/macos/macos-preflight.sh" --package-root "$ROOT" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT"

ensure_openclaw
prime_payload_cache "$bundle"

say_step "Installing Miloco"
bash "$ROOT/payload/install.sh" "$@"

say_step "Starting services"
miloco-cli service start >/tmp/easy-miloco-macos-service-start.log 2>&1 || miloco-cli service restart >/tmp/easy-miloco-macos-service-restart.log 2>&1 || true
start_openclaw_gateway

install_desktop_helpers

say_step "Validating"
validation_log="/tmp/easy-miloco-macos-validation.log"
set +e
bash "$ROOT/scripts/macos/macos-miloco-validate.sh" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT" | tee "$validation_log"
validation_code="${PIPESTATUS[0]}"
set -e
basic_ready="$(awk -F= '/^BASIC_READY=/{print $2}' "$validation_log" | tail -n 1)"
full_ready="$(awk -F= '/^FULL_READY=/{print $2}' "$validation_log" | tail -n 1)"

say_step "Opening dashboards"
open_dashboards

if [ "$validation_code" -eq 0 ] && [ "$full_ready" = "yes" ]; then
  printf '\n[OK] easy-miloco macOS full setup finished.\n'
elif [ "$validation_code" -eq 0 ] && [ "$basic_ready" = "yes" ]; then
  printf '\n[WARN] easy-miloco macOS basic setup finished, but full readiness is not complete.\n' >&2
  printf 'This usually means account, model, device rows, or camera scope still needs attention.\n' >&2
else
  printf '\n[WARN] Setup finished but validation reported issues.\n' >&2
fi
printf 'Miloco: http://127.0.0.1:%s/\n' "$MILOCO_PORT"
printf 'OpenClaw: http://127.0.0.1:%s/\n' "$OPENCLAW_PORT"
printf 'Desktop console: %s\n' "$HOME/Desktop/Miloco Console.command"
printf 'Logs:\n'
printf '  %s\n' "$validation_log"
printf '  /tmp/easy-miloco-macos-service-start.log\n'
printf '  %s\n' "$HOME/.openclaw/miloco/log/"
printf '  %s\n' "$HOME/Library/Logs/openclaw/gateway.log"

printf '\nPress Enter to close this window.\n'
read -r _ || true
