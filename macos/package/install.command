#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MILOCO_PORT="${MILOCO_PORT:-18860}"
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
openclaw gateway restart >/tmp/easy-miloco-macos-openclaw-restart.log 2>&1 || openclaw gateway start >/tmp/easy-miloco-macos-openclaw-start.log 2>&1 || true

install_desktop_helpers

say_step "Validating"
if bash "$ROOT/scripts/macos/macos-miloco-validate.sh" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT"; then
  printf '\n[OK] easy-miloco macOS setup finished.\n'
  printf 'Miloco: http://127.0.0.1:%s/\n' "$MILOCO_PORT"
else
  printf '\n[WARN] Setup finished but validation reported issues.\n' >&2
  printf 'Check: /tmp/easy-miloco-macos-service-start.log and ~/.openclaw/miloco/log/\n' >&2
fi

printf '\nPress Enter to close this window.\n'
read -r _ || true
