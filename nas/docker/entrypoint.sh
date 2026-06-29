#!/usr/bin/env bash
set -Eeuo pipefail

export HOME="${HOME:-/data}"
export MILOCO_HOME="${MILOCO_HOME:-/data/miloco}"
export MILOCO_PORT="${MILOCO_PORT:-1810}"
export OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-$OPENCLAW_PORT}"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

STATE_DIR="${EASY_MILOCO_STATE_DIR:-/data/.easy-miloco}"
RUNTIME_DIR="${EASY_MILOCO_RUNTIME_DIR:-/data/runtime}"
INSTALL_SH="${EASY_MILOCO_INSTALL_SH:-$RUNTIME_DIR/install.sh}"
INSTALL_URL="${MILOCO_INSTALL_URL:-}"
RELEASE_API="${MILOCO_RELEASE_API:-https://api.github.com/repos/andy-JustSayWhen/easy-miloco/releases/latest}"
RELEASE_ZIP_URL="${MILOCO_RELEASE_ZIP_URL:-}"
VALIDATE_URL="${MILOCO_VALIDATE_URL:-https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/main/docs/scripts/wsl-miloco-validate.sh}"
VALIDATE_SH="${EASY_MILOCO_VALIDATE_SH:-/data/wsl-miloco-validate.sh}"

log() {
  printf '[easy-miloco-nas] %s\n' "$*"
}

warn() {
  printf '[easy-miloco-nas][WARN] %s\n' "$*" >&2
}

stop_services() {
  set +e
  openclaw gateway stop >/dev/null 2>&1 || true
  miloco-cli service stop >/dev/null 2>&1 || true
}

trap 'stop_services; exit 0' INT TERM

need_download() {
  [ "${MILOCO_FORCE_INSTALL:-0}" = "1" ] && return 0
  [ ! -s "$INSTALL_SH" ] && return 0
  [ ! -s "$VALIDATE_SH" ] && return 0
  return 1
}

download_runtime_files() {
  mkdir -p "$(dirname "$INSTALL_SH")" "$STATE_DIR" "$MILOCO_HOME" "$RUNTIME_DIR"
  if need_download; then
    if [ -n "$INSTALL_URL" ]; then
      log "Downloading Miloco installer"
      curl -fL --retry 3 --connect-timeout 20 -o "$INSTALL_SH" "$INSTALL_URL"
    else
      download_release_payload
    fi
    chmod +x "$INSTALL_SH"

    log "Downloading validation script"
    curl -fL --retry 3 --connect-timeout 20 -o "$VALIDATE_SH" "$VALIDATE_URL"
    chmod +x "$VALIDATE_SH"
  fi
}

download_release_payload() {
  local zip_url="$RELEASE_ZIP_URL"
  local zip_path="$STATE_DIR/release.zip"

  if [ -z "$zip_url" ]; then
    zip_url="$(select_release_zip_url)"
  fi
  if [ -z "$zip_url" ]; then
    cat >&2 <<'EOF'
[easy-miloco-nas][FAIL] No usable release zip found.
Set MILOCO_RELEASE_ZIP_URL to a NAS release zip that contains payload/install.sh
and the matching linux runtime bundle for this CPU architecture.
EOF
    exit 1
  fi

  log "Downloading release payload: $zip_url"
  curl -fL --retry 3 --connect-timeout 20 -o "$zip_path" "$zip_url"
  rm -rf "$RUNTIME_DIR"
  mkdir -p "$RUNTIME_DIR"
  python3 - "$zip_path" "$RUNTIME_DIR" <<'PY'
import shutil
import sys
import zipfile
from pathlib import Path

zip_path = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
copied = 0

with zipfile.ZipFile(zip_path) as zf:
    for info in zf.infolist():
        if info.is_dir():
            continue
        name = info.filename.replace("\\", "/")
        parts = [p for p in name.split("/") if p]
        rel = None
        if "payload" in parts:
            idx = parts.index("payload")
            rel_parts = parts[idx + 1 :]
            if rel_parts:
                rel = Path(*rel_parts)
        elif parts[-1] in {"install.sh", "install.py", "manifest.json"} or parts[-1].startswith("miloco-"):
            rel = Path(parts[-1])
        if rel is None:
            continue
        target = out_dir / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(info) as src, target.open("wb") as dst:
            shutil.copyfileobj(src, dst)
        copied += 1

if not (out_dir / "install.sh").is_file():
    raise SystemExit("release zip does not contain payload/install.sh")
if not (out_dir / "manifest.json").is_file():
    raise SystemExit("release zip does not contain payload/manifest.json")
print(f"extracted {copied} payload file(s) to {out_dir}")
PY
}

select_release_zip_url() {
  python3 - "$RELEASE_API" <<'PY'
import json
import platform
import sys
import urllib.request

api = sys.argv[1]
arch = platform.machine().lower()
with urllib.request.urlopen(api, timeout=20) as resp:
    data = json.load(resp)

assets = data.get("assets", [])
items = [
    (a.get("name") or "", a.get("browser_download_url") or "")
    for a in assets
]
items = [(name, url) for name, url in items if name.endswith(".zip") and url]

for name, url in items:
    low = name.lower()
    if "nas" in low:
        print(url)
        raise SystemExit(0)

if arch in {"x86_64", "amd64"}:
    for name, url in items:
        if "windows" in name.lower():
            print(url)
            raise SystemExit(0)

raise SystemExit(1)
PY
}

normalize_env() {
  if [ -z "${OMNI_API_KEY:-}" ] && [ -n "${MIMO_API_KEY:-}" ]; then
    export OMNI_API_KEY="$MIMO_API_KEY"
  fi
  export OMNI_MODEL="${OMNI_MODEL:-xiaomi/mimo-v2.5}"
}

run_agent_prepare_once() {
  if [ -f "$STATE_DIR/agent-prepare.done" ] && [ "${MILOCO_FORCE_INSTALL:-0}" != "1" ]; then
    return
  fi

  log "Running agent prepare"
  bash "$INSTALL_SH" --agent-prepare --lang zh
  date -Is >"$STATE_DIR/agent-prepare.done"
}

run_agent_finish_if_ready() {
  if [ -f "$STATE_DIR/agent-finish.done" ] && [ "${MILOCO_FORCE_INSTALL:-0}" != "1" ]; then
    return
  fi

  if [ -z "${MILOCO_ACCOUNT_AUTH:-}" ] || [ -z "${OMNI_API_KEY:-}" ] || [ -z "${OMNI_BASE_URL:-}" ] || [ -z "${OMNI_MODEL:-}" ]; then
    warn "Account/model env is incomplete; container will start basic services only."
    warn "Set MILOCO_ACCOUNT_AUTH, OMNI_API_KEY, OMNI_BASE_URL and OMNI_MODEL in .env, then restart the container."
    return
  fi

  log "Running agent finish"
  bash "$INSTALL_SH" \
    --agent-finish \
    --lang zh \
    --account-auth "$MILOCO_ACCOUNT_AUTH" \
    --omni-api-key "$OMNI_API_KEY" \
    --omni-base-url "$OMNI_BASE_URL" \
    --omni-model "$OMNI_MODEL"
  date -Is >"$STATE_DIR/agent-finish.done"
}

configure_runtime_ports() {
  if command -v miloco-cli >/dev/null 2>&1; then
    miloco-cli config set server.url "http://127.0.0.1:${MILOCO_PORT}" --no-restart >/dev/null 2>&1 || true
    miloco-cli config set agent.webhook_url "http://127.0.0.1:${OPENCLAW_PORT}/miloco/webhook" --no-restart >/dev/null 2>&1 || true
  fi
}

start_runtime() {
  log "Starting Miloco service"
  miloco-cli service start >/tmp/easy-miloco-service-start.log 2>&1 || miloco-cli service restart >/tmp/easy-miloco-service-restart.log 2>&1 || true

  log "Starting OpenClaw gateway"
  openclaw gateway --dev --bind loopback --port "$OPENCLAW_PORT" install --port "$OPENCLAW_PORT" >/tmp/easy-miloco-openclaw-install.log 2>&1 || true
  openclaw gateway restart >/tmp/easy-miloco-openclaw-restart.log 2>&1 || openclaw gateway start >/tmp/easy-miloco-openclaw-start.log 2>&1 || true
}

validate_runtime() {
  if [ -x "$VALIDATE_SH" ]; then
    MILOCO_PORT="$MILOCO_PORT" OPENCLAW_PORT="$OPENCLAW_PORT" bash "$VALIDATE_SH" || true
  fi
}

print_usage() {
  cat <<EOF

== easy-miloco NAS Docker ==
Miloco 面板:   http://127.0.0.1:${MILOCO_PORT}/
OpenClaw 对话: http://127.0.0.1:${OPENCLAW_PORT}/
配置目录:      ${MILOCO_HOME}
持久数据:      /data
运行载荷:      ${RUNTIME_DIR}

如果这是 NAS 主机，请把 127.0.0.1 替换为 NAS 的局域网 IP。
如果 FULL_READY 还不是 yes，补齐 .env 后执行: docker compose restart

EOF
}

keep_alive() {
  log "Container is ready; following logs."
  while true; do
    sleep 3600 &
    wait $!
  done
}

main() {
  mkdir -p "$STATE_DIR" "$MILOCO_HOME" "$HOME/.local/bin" "$HOME/.openclaw"
  normalize_env
  download_runtime_files
  run_agent_prepare_once
  run_agent_finish_if_ready
  configure_runtime_ports
  start_runtime
  validate_runtime
  print_usage
  keep_alive
}

main "$@"
