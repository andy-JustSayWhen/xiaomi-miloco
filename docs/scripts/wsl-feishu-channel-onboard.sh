#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_PATH="${OPENCLAW_PATH:-$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH}"
export PATH="$OPENCLAW_PATH"

DO_INSTALL=0
DO_AUTH=0
DO_BIND=0
DO_VALIDATE=0
DO_STATUS=0
JSON_OUTPUT=0
INTERACTIVE=0
FEISHU_OPEN_ID="${FEISHU_OPEN_ID:-}"
TEST_MESSAGE="${TEST_MESSAGE:-Miloco Feishu channel test succeeded.}"

usage() {
  cat <<'EOF'
Usage:
  wsl-feishu-channel-onboard.sh [--interactive] [--install] [--auth] [--bind] [--validate] [--status] [--json]

Examples:
  bash docs/scripts/wsl-feishu-channel-onboard.sh --interactive --install --auth --bind --validate
  FEISHU_OPEN_ID=<open_id> bash docs/scripts/wsl-feishu-channel-onboard.sh --bind --validate
  bash docs/scripts/wsl-feishu-channel-onboard.sh --status --json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) DO_INSTALL=1 ;;
    --auth|--login) DO_AUTH=1 ;;
    --bind|--bind-notify) DO_BIND=1 ;;
    --validate) DO_VALIDATE=1 ;;
    --status) DO_STATUS=1 ;;
    --json) JSON_OUTPUT=1 ;;
    --interactive) INTERACTIVE=1 ;;
    --open-id)
      shift
      FEISHU_OPEN_ID="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ $DO_INSTALL -eq 0 && $DO_AUTH -eq 0 && $DO_BIND -eq 0 && $DO_VALIDATE -eq 0 && $DO_STATUS -eq 0 ]]; then
  DO_STATUS=1
fi

log() {
  if [[ $JSON_OUTPUT -eq 0 ]]; then
    printf '\n== %s ==\n' "$1"
  fi
}

note() {
  if [[ $JSON_OUTPUT -eq 0 ]]; then
    printf '%s\n' "$1"
  fi
}

warn() {
  printf '[WARN] %s\n' "$1" >&2
}

require_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    echo "openclaw CLI was not found in PATH." >&2
    echo "PATH=$PATH" >&2
    exit 3
  fi
}

restart_gateway() {
  log "Restart OpenClaw gateway"
  systemctl --user unmask openclaw-gateway.service >/dev/null 2>&1 || true
  systemctl --user enable openclaw-gateway.service >/dev/null 2>&1 || true
  openclaw gateway restart >/tmp/openclaw-feishu-restart.log 2>&1 || \
    systemctl --user restart openclaw-gateway.service >/tmp/openclaw-feishu-restart-systemd.log 2>&1 || true
  openclaw gateway status >/tmp/openclaw-feishu-status.log 2>&1 || true
  note "Gateway restart command sent. Logs: /tmp/openclaw-feishu-restart.log, /tmp/openclaw-feishu-status.log"
}

plugin_installed() {
  openclaw plugins inspect feishu >/tmp/openclaw-feishu-plugin-inspect.log 2>&1
}

install_feishu_plugin() {
  require_openclaw
  log "Install Feishu channel plugin"
  if plugin_installed; then
    note "Feishu plugin is already installed."
  else
    note "Installing clawhub:@openclaw/feishu ..."
    openclaw plugins install clawhub:@openclaw/feishu
  fi
  openclaw plugins enable feishu >/tmp/openclaw-feishu-enable.log 2>&1 || true
  restart_gateway
}

auth_feishu_channel() {
  require_openclaw
  log "Feishu channel login"
  note "An OpenClaw Feishu login or app registration flow will start now."
  note "If a URL appears, open it, finish authorization in Feishu, then return to this terminal."
  note "If the command says the channel is already configured, continue with validation."
  openclaw channels login --channel feishu || {
    warn "openclaw channels login failed or is unsupported by this OpenClaw version."
    warn "Try the Feishu plugin's own onboarding command if OpenClaw prints one, then rerun this script with --validate --bind."
    return 1
  }
  restart_gateway
}

status_json() {
  python3 - "$FEISHU_OPEN_ID" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

target = sys.argv[1].strip()
home = Path.home()
openclaw_config = home / ".openclaw" / "openclaw.json"
session_store = home / ".openclaw" / "agents" / "main" / "sessions" / "sessions.json"

def read_json(path):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}

def run(args):
    try:
        p = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        return {"code": p.returncode, "stdout": p.stdout, "stderr": p.stderr}
    except Exception as exc:
        return {"code": 127, "stdout": "", "stderr": str(exc)}

config = read_json(openclaw_config)
sessions = read_json(session_store)
channels = config.get("channels") if isinstance(config, dict) else {}
feishu = channels.get("feishu") if isinstance(channels, dict) else {}
plugins = config.get("plugins") if isinstance(config, dict) else {}
entries = plugins.get("entries") if isinstance(plugins, dict) else {}
miloco = entries.get("miloco-openclaw-plugin") if isinstance(entries, dict) else {}
miloco_cfg = miloco.get("config") if isinstance(miloco, dict) else {}
notify_key = miloco_cfg.get("notifySessionKey") if isinstance(miloco_cfg, dict) else ""
notify_entry = sessions.get(notify_key) if isinstance(sessions, dict) and notify_key else None
latest_feishu = ""
for key, value in sessions.items() if isinstance(sessions, dict) else []:
    if isinstance(value, dict) and value.get("lastChannel") == "feishu" and value.get("lastTo"):
        latest_feishu = key

plugin = run(["openclaw", "plugins", "inspect", "feishu"])
channel = run(["openclaw", "channels", "status", "--channel", "feishu", "--json", "--probe", "--timeout", "15000"])
channel_json = {}
try:
    channel_json = json.loads(channel["stdout"]) if channel["stdout"].strip() else {}
except Exception:
    channel_json = {}

result = {
    "openclawConfig": str(openclaw_config),
    "sessionStore": str(session_store),
    "feishuPluginInstalled": plugin["code"] == 0,
    "feishuChannelConfigured": bool(feishu) or bool(channel_json.get("configured")),
    "feishuChannelRunning": bool(channel_json.get("running")),
    "feishuProbeOk": bool((channel_json.get("probe") or {}).get("ok")) if isinstance(channel_json.get("probe"), dict) else False,
    "notifySessionKey": notify_key,
    "latestFeishuSessionKey": latest_feishu,
    "notifySessionValid": bool(isinstance(notify_entry, dict) and notify_entry.get("lastChannel") == "feishu" and notify_entry.get("lastTo")),
    "targetOpenIdKnown": bool(target or (isinstance(notify_entry, dict) and notify_entry.get("lastTo"))),
}
result["ready"] = bool(result["feishuPluginInstalled"] and result["feishuChannelConfigured"] and result["notifySessionValid"])
print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

print_status() {
  require_openclaw
  if [[ $JSON_OUTPUT -eq 1 ]]; then
    status_json
  else
    log "Feishu channel status"
    status_json
  fi
}

discover_feishu_open_id() {
  python3 <<'PY'
import json
from pathlib import Path

store = Path.home() / ".openclaw" / "agents" / "main" / "sessions" / "sessions.json"
try:
    data = json.loads(store.read_text(encoding="utf-8")) if store.exists() else {}
except Exception:
    data = {}
best = ""
best_ts = ""
if isinstance(data, dict):
    for _, entry in data.items():
        if isinstance(entry, dict) and entry.get("lastChannel") == "feishu" and entry.get("lastTo"):
            ts = str(entry.get("lastInteractionAt") or entry.get("updatedAt") or "")
            if not best or ts >= best_ts:
                best = str(entry.get("lastTo"))
                best_ts = ts
print(best)
PY
}

prompt_open_id_if_needed() {
  if [[ -n "$FEISHU_OPEN_ID" ]]; then
    return 0
  fi
  FEISHU_OPEN_ID="$(discover_feishu_open_id)"
  if [[ -n "$FEISHU_OPEN_ID" ]]; then
    note "Found Feishu open_id from the OpenClaw session store."
    return 0
  fi
  if [[ $INTERACTIVE -eq 1 ]]; then
    note "No Feishu session was found yet."
    note "Open Feishu, send one message to your OpenClaw bot, then paste your Feishu open_id if you already know it."
    read -r -p "Feishu open_id (leave empty to skip binding): " FEISHU_OPEN_ID
  fi
  [[ -n "$FEISHU_OPEN_ID" ]]
}

bind_notify_session() {
  require_openclaw
  log "Bind Miloco notifications to Feishu"
  if ! prompt_open_id_if_needed; then
    warn "No Feishu open_id is available. Send a message to the bot from Feishu, then rerun with --bind."
    return 4
  fi
  python3 - "$FEISHU_OPEN_ID" <<'PY'
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

open_id = sys.argv[1].strip()
home = Path.home()
config_path = home / ".openclaw" / "openclaw.json"
session_path = home / ".openclaw" / "agents" / "main" / "sessions" / "sessions.json"
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

def read_json(path):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}

def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)

config = read_json(config_path)
sessions = read_json(session_path)
if not isinstance(config, dict):
    config = {}
if not isinstance(sessions, dict):
    sessions = {}

if config_path.exists():
    shutil.copy2(config_path, config_path.with_name(config_path.name + f".bak.miloco-feishu-{stamp}"))
if session_path.exists():
    shutil.copy2(session_path, session_path.with_name(session_path.name + f".bak.miloco-feishu-{stamp}"))

session_key = f"agent:main:feishu:dm:{open_id}"
now = datetime.now(timezone.utc).isoformat()
entry = sessions.get(session_key)
if not isinstance(entry, dict):
    entry = {}
entry.update({
    "lastChannel": "feishu",
    "lastTo": open_id,
    "lastAccountId": entry.get("lastAccountId") or "default",
    "updatedAt": now,
    "lastInteractionAt": entry.get("lastInteractionAt") or now,
})
sessions[session_key] = entry

plugins = config.setdefault("plugins", {})
entries = plugins.setdefault("entries", {})
miloco = entries.setdefault("miloco-openclaw-plugin", {})
miloco_cfg = miloco.setdefault("config", {})
miloco_cfg["notifySessionKey"] = session_key

write_json(session_path, sessions)
write_json(config_path, config)
print(session_key)
PY
  restart_gateway
}

validate_feishu() {
  require_openclaw
  log "Validate Feishu channel"
  openclaw channels status --channel feishu --json --probe --timeout 15000
  if prompt_open_id_if_needed; then
    log "Send Feishu test message"
    openclaw message send --channel feishu --target "$FEISHU_OPEN_ID" --message "$TEST_MESSAGE" --json --verbose
  else
    warn "Skipped message send because no Feishu open_id is available."
  fi
  log "Validation hint"
  note "For inbound validation, send a message to the bot from Feishu and check that OpenClaw replies in the same conversation."
}

if [[ $DO_STATUS -eq 1 ]]; then
  print_status
fi
if [[ $DO_INSTALL -eq 1 ]]; then
  install_feishu_plugin
fi
if [[ $DO_AUTH -eq 1 ]]; then
  auth_feishu_channel
fi
if [[ $DO_BIND -eq 1 ]]; then
  bind_notify_session
fi
if [[ $DO_VALIDATE -eq 1 ]]; then
  validate_feishu
fi
