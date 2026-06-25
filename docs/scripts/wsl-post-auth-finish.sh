#!/usr/bin/env bash
set -u

MILOCO_PORT="${MILOCO_PORT:-18860}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
MILOCO_HOME="${MILOCO_HOME:-$HOME/.openclaw/miloco}"
MILOCO_AUTH_PAYLOAD="${MILOCO_AUTH_PAYLOAD:-}"
MIMO_API_KEY="${MIMO_API_KEY:-}"
OMNI_MODEL="${OMNI_MODEL:-xiaomi/mimo-v2.5}"
OMNI_BASE_URL="${OMNI_BASE_URL:-https://api.xiaomimimo.com/v1}"
OPENCLAW_CHAT_MODEL="${OPENCLAW_CHAT_MODEL:-}"
MILOCO_HOME_ID="${MILOCO_HOME_ID:-}"
MILOCO_CAMERA_DIDS="${MILOCO_CAMERA_DIDS:-}"
PRINT_BIND_URL=0
AUTHORIZE_ONLY=0
LIST_HOMES_JSON=0
DRY_RUN=0
STRICT_FULL=1

usage() {
  cat <<'USAGE'
Usage:
  bash wsl-post-auth-finish.sh --print-bind-url
  MILOCO_AUTH_PAYLOAD='<payload>' bash wsl-post-auth-finish.sh --authorize-only
  bash wsl-post-auth-finish.sh --list-homes-json
  MILOCO_AUTH_PAYLOAD='<payload>' MIMO_API_KEY='<key>' bash wsl-post-auth-finish.sh

Environment variables:
  MILOCO_AUTH_PAYLOAD   Xiaomi OAuth callback payload copied from the bind page
  MIMO_API_KEY          MiMo / Omni API key
  OMNI_MODEL            Default: xiaomi/mimo-v2.5
  OMNI_BASE_URL         Default: https://api.xiaomimimo.com/v1
  OPENCLAW_CHAT_MODEL   Optional OpenClaw main chat model; defaults to OMNI_MODEL
  MILOCO_HOME_ID        Optional home_id to switch after account binding
  MILOCO_CAMERA_DIDS    Optional whitespace-separated camera did list to enable
  MILOCO_PORT           Default: 18860
  OPENCLAW_PORT         Default: 18789

Options:
  --print-bind-url      Print a fresh Xiaomi account bind URL and exit
  --authorize-only      Submit Xiaomi OAuth payload, then print homes and exit
  --list-homes-json     Print the current home list as compact JSON and exit
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
    --authorize-only) AUTHORIZE_ONLY=1 ;;
    --list-homes-json) LIST_HOMES_JSON=1 ;;
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

run_checked_json() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY_RUN] %s\n' "$*"
    return 0
  fi
  output="$("$@" 2>&1)"
  status=$?
  printf '%s\n' "$output"
  if [ "$status" -ne 0 ]; then
    return "$status"
  fi
  if printf '%s' "$output" | grep -Eq '"error"[[:space:]]*:'; then
    return 2
  fi
  return 0
}

run_checked_json_retry() {
  attempts="$1"
  shift
  i=1
  while [ "$i" -le "$attempts" ]; do
    if run_checked_json "$@"; then
      return 0
    fi
    status=$?
    if [ "$i" -ge "$attempts" ]; then
      return "$status"
    fi
    log "Command failed with exit code ${status}; rechecking Miloco health and retrying (${i}/${attempts})"
    wait_miloco_health 5 || true
    sleep 2
    i=$((i + 1))
  done
  return 2
}

print_bind_url() {
  log "Generating Xiaomi account bind URL"
  if miloco-cli account bind --no-wait; then
    return 0
  fi

  status=$?
  log "miloco-cli account bind failed with exit code ${status}; generating the URL locally"
  python3 - <<'PY'
import hashlib
import json
import os
import sqlite3
import sys
import time
import uuid as uuidlib
from pathlib import Path
from urllib.parse import urlencode

PROJECT_CODE = "mico"
OAUTH2_CLIENT_ID = "2882303761520431603"
OAUTH2_AUTH_URL = "https://account.xiaomi.com/oauth2/authorize"

def read_json(path):
    try:
        if path.is_file():
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return {}

def section_value(data, section, key, default):
    value = data.get(section)
    if isinstance(value, dict):
        value = value.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return default

miloco_home = Path(os.environ.get("MILOCO_HOME", "~/.openclaw/miloco")).expanduser()
config = read_json(miloco_home / "config.json")

storage = os.environ.get("MILOCO_DIRECTORIES__STORAGE") or section_value(
    config, "directories", "storage", "."
)
workspace = Path(storage).expanduser()
if not workspace.is_absolute():
    workspace = miloco_home if str(workspace) in ("", ".") else miloco_home / workspace

database_path = os.environ.get("MILOCO_DATABASE__PATH") or section_value(
    config, "database", "path", "miloco.db"
)
db_path = Path(database_path).expanduser()
if not db_path.is_absolute():
    db_path = workspace / db_path

redirect_uri = os.environ.get("MILOCO_MIOT__OAUTH_REDIRECT_URI") or section_value(
    config, "miot", "oauth_redirect_uri", "https://127.0.0.1"
)

try:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), timeout=10)
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS kv (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key TEXT UNIQUE NOT NULL,
                value TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_kv_key ON kv(key)")
        row = conn.execute(
            "SELECT value FROM kv WHERE key = ?",
            ("DEVICE_UUID_KEY",),
        ).fetchone()
        device_uuid = row[0] if row and row[0] else None
        if not device_uuid:
            device_uuid = uuidlib.uuid4().hex
            now_ms = int(time.time() * 1000)
            conn.execute(
                """
                INSERT INTO kv (key, value, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updated_at = excluded.updated_at
                """,
                ("DEVICE_UUID_KEY", device_uuid, now_ms, now_ms),
            )
            conn.commit()
    finally:
        conn.close()
except Exception as exc:
    print(f"[FAIL] Could not read or create Miloco DEVICE_UUID_KEY: {exc}", file=sys.stderr)
    raise SystemExit(2)

device_id = f"{PROJECT_CODE}.{device_uuid}"
state = hashlib.sha1(f"d={device_id}".encode("utf-8")).hexdigest()
params = {
    "redirect_uri": redirect_uri,
    "client_id": OAUTH2_CLIENT_ID,
    "response_type": "code",
    "device_id": device_id,
    "state": state,
    "skip_confirm": False,
}
url = f"{OAUTH2_AUTH_URL}?{urlencode(params)}"
print("Xiaomi account bind URL (local fallback):")
print(url)
print("[OK] Generated Xiaomi account bind URL locally.")
PY
}

wait_miloco_health() {
  attempts="${1:-30}"
  i=1
  while [ "$i" -le "$attempts" ]; do
    health="$(curl -fsS --max-time 3 "http://127.0.0.1:${MILOCO_PORT}/health" 2>&1 || true)"
    if printf '%s' "$health" | grep -q '"status":"ok"'; then
      log "Miloco health ok on port ${MILOCO_PORT}"
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  printf 'Miloco health check failed on port %s: %s\n' "$MILOCO_PORT" "$health" >&2
  return 2
}

recover_miloco_service() {
  reason="${1:-Recovering Miloco backend}"
  allow_degraded="${2:-0}"
  log "$reason"
  if run_checked_json miloco-cli service restart; then
    if wait_miloco_health 30; then
      return 0
    fi
    log "Miloco restart completed but health is still not ok; trying stop/start"
  else
    log "Miloco restart reported an error; trying stop/start"
  fi

  run_checked_json miloco-cli service stop || true
  sleep 2
  run_checked_json miloco-cli service start || true
  if wait_miloco_health 45; then
    return 0
  fi
  if [ "$allow_degraded" -eq 1 ]; then
    log "Miloco health is still not ok after restart/start; continuing because account/model/OpenClaw config has been written. This can be expected when cameras, devices, or local LAN nodes are unreachable from this computer."
    return 0
  fi
  return 2
}

write_miloco_model_config() {
  log "Writing Omni model config: model=${OMNI_MODEL}, base_url=${OMNI_BASE_URL}, api_key_length=${#MIMO_API_KEY}"
  if run_checked_json_retry 3 miloco-cli config set \
      model.omni.model "$OMNI_MODEL" \
      model.omni.base_url "$OMNI_BASE_URL" \
      model.omni.api_key "$MIMO_API_KEY" \
      --no-restart; then
    return 0
  fi

  log "miloco-cli config set failed after retries; writing ${MILOCO_HOME}/config.json directly"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY_RUN] direct write model.omni.* to %s/config.json\n' "$MILOCO_HOME"
    return 0
  fi

  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ.get("MILOCO_HOME", "~/.openclaw/miloco")).expanduser() / "config.json"
try:
    data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
except (json.JSONDecodeError, OSError):
    data = {}
if not isinstance(data, dict):
    data = {}
model = data.setdefault("model", {})
if not isinstance(model, dict):
    model = {}
    data["model"] = model
omni = model.setdefault("omni", {})
if not isinstance(omni, dict):
    omni = {}
    model["omni"] = omni
omni["model"] = os.environ["OMNI_MODEL"]
omni["base_url"] = os.environ["OMNI_BASE_URL"]
omni["api_key"] = os.environ["MIMO_API_KEY"]
path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_suffix(".tmp")
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
tmp.replace(path)
print(f"[OK] Miloco model config written directly; path={path}")
PY
}

need_cmd curl
need_cmd miloco-cli

if [ "$PRINT_BIND_URL" -eq 1 ]; then
  print_bind_url
  exit $?
fi

need_cmd openclaw

log "Pre-checking Miloco service"
service_status="$(miloco-cli service status 2>&1 || true)"
printf '%s\n' "$service_status"
if ! printf '%s' "$service_status" | grep -Eq '"running"[[:space:]]*:[[:space:]]*true'; then
  if ! recover_miloco_service "Miloco service is not running; trying restart/stop/start"; then
    exit 2
  fi
fi

if ! wait_miloco_health 10; then
  if [ -n "$MILOCO_AUTH_PAYLOAD" ] || [ "$AUTHORIZE_ONLY" -eq 1 ] || [ "$LIST_HOMES_JSON" -eq 1 ]; then
    if ! recover_miloco_service "Miloco service is running but health is not ok; trying restart/stop/start"; then
      exit 2
    fi
  else
    log "Miloco health is not ok before model/API config; continuing so config can be written and backend can recover after restart"
  fi
fi

if [ "$LIST_HOMES_JSON" -eq 1 ]; then
  if ! wait_miloco_health 10; then
    if ! recover_miloco_service "Miloco service is not healthy before listing homes; trying restart/stop/start"; then
      exit 2
    fi
  fi
  miloco-cli scope home list
  exit $?
fi

if [ "$AUTHORIZE_ONLY" -eq 1 ] || [ -n "$MILOCO_AUTH_PAYLOAD" ]; then
  if ! wait_miloco_health 10; then
    if ! recover_miloco_service "Miloco service is not healthy before Xiaomi authorization; trying restart/stop/start"; then
      exit 2
    fi
  fi
fi

account_before="$(miloco-cli account status 2>&1 || true)"
if printf '%s' "$account_before" | grep -Eq '"is_bound"[[:space:]]*:[[:space:]]*true'; then
  log "Xiaomi account is already bound; authorization step will be skipped"
else
  if [ -z "$MILOCO_AUTH_PAYLOAD" ]; then
    if [ "$AUTHORIZE_ONLY" -eq 1 ]; then
      printf 'Missing MILOCO_AUTH_PAYLOAD and account is not bound.\n' >&2
      printf 'Run: bash wsl-post-auth-finish.sh --print-bind-url\n' >&2
      exit 2
    fi
    log "Xiaomi account is not bound and no auth payload was provided; continuing with model/API config only"
  fi
  if [ -n "$MILOCO_AUTH_PAYLOAD" ]; then
    log "Authorizing Xiaomi account"
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[DRY_RUN] miloco-cli account authorize <payload>\n'
    else
      run_checked_json miloco-cli account authorize "$MILOCO_AUTH_PAYLOAD" </dev/null
    fi
  fi
fi

if [ "$AUTHORIZE_ONLY" -eq 1 ]; then
  log "Current homes after authorization"
  miloco-cli scope home list
  exit $?
fi

if [ -z "$MIMO_API_KEY" ]; then
  printf 'Missing MIMO_API_KEY.\n' >&2
  exit 2
fi

if ! write_miloco_model_config; then
  printf 'Failed to write Miloco Omni model config.\n' >&2
  exit 2
fi

log "Writing OpenClaw Miloco plugin and main chat model config"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '[DRY_RUN] update ~/.openclaw/openclaw.json plugin miloco-openclaw-plugin omni_* and OpenClaw main chat model config\n'
else
  python3 - <<'PY'
import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

path = Path.home() / ".openclaw" / "openclaw.json"
path.parent.mkdir(parents=True, exist_ok=True)

if path.exists():
    data = json.loads(path.read_text(encoding="utf-8"))
else:
    data = {}

omni_model = os.environ.get("OMNI_MODEL", "").strip()
omni_base_url = os.environ.get("OMNI_BASE_URL", "").strip()
api_key = os.environ.get("MIMO_API_KEY", "")
chat_model = os.environ.get("OPENCLAW_CHAT_MODEL", "").strip() or omni_model

def as_dict(parent, key):
    value = parent.get(key)
    if not isinstance(value, dict):
        value = {}
        parent[key] = value
    return value

def normalize_model_id(value):
    value = (value or "").strip()
    if "/" not in value:
        return value
    prefix, rest = value.split("/", 1)
    if prefix in {"mimo", "xiaomi"}:
        return rest
    return value

def infer_provider_id(base_url, model):
    text = f"{base_url} {model}".lower()
    if "xiaomimimo" in text or "token-plan" in text or model.startswith(("mimo-", "mimo_")):
        return "mimo"
    return "miloco-llm"

provider_id = infer_provider_id(omni_base_url, normalize_model_id(chat_model))
chat_model_id = normalize_model_id(chat_model)
omni_model_id = normalize_model_id(omni_model)
chat_ref = f"{provider_id}/{chat_model_id}"

plugins = data.setdefault("plugins", {}).setdefault("entries", {})
entry = plugins.setdefault("miloco-openclaw-plugin", {})
config = entry.setdefault("config", {})
config["omni_model"] = omni_model
config["omni_base_url"] = omni_base_url
config["omni_api_key"] = api_key

agents = as_dict(data, "agents")
defaults = as_dict(agents, "defaults")
model_default = as_dict(defaults, "model")
model_default["primary"] = chat_ref

agent_models = as_dict(defaults, "models")
agent_row = as_dict(agent_models, chat_ref)
params = as_dict(agent_row, "params")
params.setdefault("maxTokens", 8192)
if provider_id == "mimo" and chat_model_id in {"mimo-v2.5-pro", "mimo-v2-pro", "mimo-v2.6-pro"}:
    extra_body = as_dict(params, "extraBody")
    extra_body.setdefault("thinking", {"type": "enabled"})
    extra_body.setdefault("reasoning_effort", "high")

models = as_dict(data, "models")
models.setdefault("mode", "merge")
providers = as_dict(models, "providers")
provider = as_dict(providers, provider_id)
provider["baseUrl"] = omni_base_url
provider["apiKey"] = api_key
provider["api"] = "openai-completions"
provider.setdefault("timeoutSeconds", 300)
provider.setdefault("contextWindow", 1000000)
provider.setdefault("contextTokens", 1000000)

provider_models = provider.get("models")
if not isinstance(provider_models, list):
    provider_models = []

def upsert_model_row(model_id, image):
    if not model_id:
        return
    for row in provider_models:
        if isinstance(row, dict) and row.get("id") == model_id:
            break
    else:
        row = {"id": model_id, "name": model_id}
        provider_models.append(row)
    row.setdefault("input", ["text", "image"] if image else ["text"])
    row.setdefault("contextWindow", 1000000)
    row.setdefault("contextTokens", 1000000)
    row.setdefault("maxTokens", 8192)

upsert_model_row(chat_model_id, False)
upsert_model_row(omni_model_id, True)
provider["models"] = provider_models

backup = path.with_name(path.name + ".bak.miloco-omni-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
if path.exists():
    shutil.copy2(path, backup)
else:
    backup = None
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

validated = subprocess.run(
    ["openclaw", "config", "validate"],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=30,
)
if validated.returncode != 0:
    if backup is not None:
        shutil.copy2(backup, path)
    print("[FAIL] OpenClaw config validation failed; restored previous config." if backup is not None else "[FAIL] OpenClaw config validation failed.")
    print(validated.stdout)
    raise SystemExit(2)

backup_note = str(backup) if backup is not None else "created-new-config"
print(f"[OK] OpenClaw plugin and main chat model config updated; primary={chat_ref}; backup={backup_note}")
PY
fi
log "OpenClaw main chat LLM now uses the same API credentials unless OPENCLAW_CHAT_MODEL overrides the model."

if [ -n "$MILOCO_HOME_ID" ]; then
  log "Switching Miloco home: ${MILOCO_HOME_ID}"
  run_checked_json miloco-cli scope home switch --pretty "$MILOCO_HOME_ID"
fi

if ! recover_miloco_service "Restarting Miloco backend" 1; then
  log "Miloco did not recover after restart/start"
  exit 2
fi

log "Restarting OpenClaw gateway"
run_cmd openclaw gateway restart

log "Waiting for Miloco backend after gateway restart"
wait_miloco_health 30 || true

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
