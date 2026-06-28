#!/usr/bin/env bash
set -u

PACKAGE_ROOT=""
MILOCO_PORT="${MILOCO_PORT:-18860}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"

while [ $# -gt 0 ]; do
  case "$1" in
    --package-root) PACKAGE_ROOT="$2"; shift 2 ;;
    --miloco-port) MILOCO_PORT="$2"; shift 2 ;;
    --openclaw-port) OPENCLAW_PORT="$2"; shift 2 ;;
    -h|--help)
      printf 'Usage: bash macos-preflight.sh [--package-root PATH] [--miloco-port PORT] [--openclaw-port PORT]\n'
      exit 0
      ;;
    *) printf '[FAIL] unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

fail_count=0
warn_count=0

pass() { printf '[PASS] %s %s\n' "$1" "${2:-}"; }
warn() { warn_count=$((warn_count + 1)); printf '[WARN] %s %s\n' "$1" "${2:-}"; }
fail() { fail_count=$((fail_count + 1)); printf '[FAIL] %s %s\n' "$1" "${2:-}"; }

require_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "cmd.$1" "$(command -v "$1")"
  else
    fail "cmd.$1" "not found"
  fi
}

printf '== easy-miloco macOS preflight ==\n'

system="$(uname -s 2>/dev/null || true)"
arch="$(uname -m 2>/dev/null || true)"
[ "$system" = "Darwin" ] && pass os "Darwin arch=$arch" || fail os "expected Darwin, got $system"
case "$arch" in
  arm64|x86_64) pass arch "$arch" ;;
  *) fail arch "$arch" ;;
esac

if command -v sw_vers >/dev/null 2>&1; then
  version="$(sw_vers -productVersion 2>/dev/null || true)"
  major="${version%%.*}"
  if [ "${major:-0}" -ge 12 ] 2>/dev/null; then
    pass macos.version "$version"
  else
    warn macos.version "$version"
  fi
fi

require_cmd bash
require_cmd curl
require_cmd tar
require_cmd lsof

if command -v python3 >/dev/null 2>&1; then
  pass cmd.python3 "$(command -v python3)"
else
  warn cmd.python3 "not found; uv will install a managed Python for Miloco"
fi

if command -v uv >/dev/null 2>&1 || [ -x "$HOME/.local/bin/uv" ] || [ -x "$HOME/.cargo/bin/uv" ]; then
  pass cmd.uv "available"
else
  warn cmd.uv "not found; installer will try to install it"
fi

if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  pass node "$(node --version 2>/dev/null) npm=$(npm --version 2>/dev/null)"
else
  warn node "node/npm not found; OpenClaw installer may install or require them"
fi

if command -v openclaw >/dev/null 2>&1; then
  pass openclaw "$(openclaw --version 2>/dev/null | head -n 1)"
else
  warn openclaw "not found; lazy installer will try to install it"
fi

for port in "$MILOCO_PORT" "$OPENCLAW_PORT"; do
  if lsof -ti "tcp:$port" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "port.$port" "already listening"
  else
    pass "port.$port" "free"
  fi
done

if [ -n "$PACKAGE_ROOT" ]; then
  [ -f "$PACKAGE_ROOT/manifest.json" ] && pass package.manifest || fail package.manifest "missing"
  [ -f "$PACKAGE_ROOT/payload/install.sh" ] && pass package.install_sh || fail package.install_sh "missing"
  case "$arch" in
    arm64) pattern="miloco-darwin-arm64-" ;;
    x86_64) pattern="miloco-darwin-x86_64-" ;;
    *) pattern="miloco-darwin-" ;;
  esac
  if find "$PACKAGE_ROOT/payload" -maxdepth 1 -type f -name "${pattern}*.tar.gz" | grep -q .; then
    pass package.bundle "$pattern"
  else
    fail package.bundle "missing $pattern*.tar.gz"
  fi
  if command -v xattr >/dev/null 2>&1 && xattr -r "$PACKAGE_ROOT" 2>/dev/null | grep -q 'com.apple.quarantine'; then
    warn package.quarantine "run: xattr -dr com.apple.quarantine \"$PACKAGE_ROOT\""
  else
    pass package.quarantine "clear"
  fi
fi

printf 'WARN_COUNT=%s\n' "$warn_count"
printf 'FAIL_COUNT=%s\n' "$fail_count"
[ "$fail_count" -eq 0 ] || exit 2
