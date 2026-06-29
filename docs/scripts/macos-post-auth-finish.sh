#!/usr/bin/env bash
set -euo pipefail

MILOCO_PORT="${MILOCO_PORT:-1810}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
OMNI_MODEL="${OMNI_MODEL:-}"
OMNI_BASE_URL="${OMNI_BASE_URL:-}"
STRICT_FULL=1
PRINT_BIND_URL=0
AUTHORIZE_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --print-bind-url) PRINT_BIND_URL=1; shift ;;
    --authorize-only) AUTHORIZE_ONLY=1; shift ;;
    --no-strict-full) STRICT_FULL=0; shift ;;
    --miloco-port) MILOCO_PORT="$2"; shift 2 ;;
    --openclaw-port) OPENCLAW_PORT="$2"; shift 2 ;;
    -h|--help)
      printf 'Usage: MILOCO_AUTH_PAYLOAD=... MIMO_API_KEY=... bash macos-post-auth-finish.sh\n'
      exit 0
      ;;
    *) printf '[FAIL] unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"

if [ "$PRINT_BIND_URL" -eq 1 ]; then
  miloco-cli account bind --no-wait
  exit 0
fi

if [ -n "${MILOCO_AUTH_PAYLOAD:-}" ]; then
  miloco-cli account authorize "$MILOCO_AUTH_PAYLOAD"
elif [ "$AUTHORIZE_ONLY" -eq 1 ]; then
  printf '[FAIL] MILOCO_AUTH_PAYLOAD is required for --authorize-only.\n' >&2
  exit 2
fi

if [ "$AUTHORIZE_ONLY" -eq 1 ]; then
  miloco-cli account status
  exit 0
fi

pairs=()
[ -n "${MIMO_API_KEY:-}" ] && pairs+=(model.omni.api_key "$MIMO_API_KEY")
[ -n "$OMNI_MODEL" ] && pairs+=(model.omni.model "$OMNI_MODEL")
[ -n "$OMNI_BASE_URL" ] && pairs+=(model.omni.base_url "$OMNI_BASE_URL")
if [ "${#pairs[@]}" -gt 0 ]; then
  miloco-cli config set "${pairs[@]}" --no-restart
fi

python3 - <<'PY'
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

home = Path.home()
miloco_config = home / ".openclaw" / "miloco" / "config.json"
openclaw_config = home / ".openclaw" / "openclaw.json"

if not miloco_config.exists():
    raise SystemExit(0)

miloco = json.loads(miloco_config.read_text(encoding="utf-8"))
omni = miloco.get("model", {}).get("omni", {})
omni_model = str(omni.get("model") or "").strip()
omni_base_url = str(omni.get("base_url") or "").strip()
api_key = str(omni.get("api_key") or "")
if not omni_model or not omni_base_url or not api_key:
    raise SystemExit(0)

data = json.loads(openclaw_config.read_text(encoding="utf-8")) if openclaw_config.exists() else {}

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

model_id = normalize_model_id(omni_model)
provider_id = infer_provider_id(omni_base_url, model_id)
chat_ref = f"{provider_id}/{model_id}"

plugins = data.setdefault("plugins", {}).setdefault("entries", {})
entry = plugins.setdefault("miloco-openclaw-plugin", {})
config = entry.setdefault("config", {})
config["omni_model"] = omni_model
config["omni_base_url"] = omni_base_url
config["omni_api_key"] = api_key

defaults = as_dict(as_dict(data, "agents"), "defaults")
as_dict(defaults, "model")["primary"] = chat_ref
agent_row = as_dict(as_dict(defaults, "models"), chat_ref)
as_dict(agent_row, "params").setdefault("maxTokens", 8192)

models = as_dict(data, "models")
models.setdefault("mode", "merge")
provider = as_dict(as_dict(models, "providers"), provider_id)
provider["baseUrl"] = omni_base_url
provider["apiKey"] = api_key
provider["api"] = "openai-completions"
provider.setdefault("timeoutSeconds", 300)
provider.setdefault("contextWindow", 1000000)
provider.setdefault("contextTokens", 1000000)
rows = provider.get("models")
if not isinstance(rows, list):
    rows = []
if not any(isinstance(row, dict) and row.get("id") == model_id for row in rows):
    rows.append({"id": model_id, "name": model_id})
for row in rows:
    if isinstance(row, dict) and row.get("id") == model_id:
        row.setdefault("input", ["text", "image"])
        row.setdefault("contextWindow", 1000000)
        row.setdefault("contextTokens", 1000000)
        row.setdefault("maxTokens", 8192)
provider["models"] = rows

openclaw_config.parent.mkdir(parents=True, exist_ok=True)
backup = None
if openclaw_config.exists():
    backup = openclaw_config.with_name(openclaw_config.name + ".bak.easy-miloco-post-auth-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(openclaw_config, backup)
openclaw_config.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
validated = subprocess.run(["openclaw", "config", "validate"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
if validated.returncode != 0:
    if backup is not None:
        shutil.copy2(backup, openclaw_config)
    print(validated.stdout)
    raise SystemExit(2)
print(f"[OK] OpenClaw chat model configured: primary={chat_ref}")
PY

miloco-cli service restart || miloco-cli service start || true
openclaw gateway restart || openclaw gateway start || true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validate="$script_dir/macos-miloco-validate.sh"
if [ "$STRICT_FULL" -eq 1 ]; then
  bash "$validate" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT" --strict-full
else
  bash "$validate" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT"
fi
