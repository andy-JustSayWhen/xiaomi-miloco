#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MILOCO_PORT="${MILOCO_PORT:-1810}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"
EXISTING_RESTORE_PACK_PATH=""
ACTION="interactive"
AGENT_MODE=0
INSTALL_ARGS=()
MILOCO_AUTH_PAYLOAD_ARG=""
MIMO_API_KEY_ARG=""
OMNI_MODEL_ARG=""
OMNI_BASE_URL_ARG=""

usage() {
  cat <<'EOF'
Usage: ./install.command [action] [options]

Actions:
  --agent-prepare       Agent mode: backup old install, install base components, start services, validate, no prompt pause
  --agent-finish        Agent mode: apply account/model config, finish plugin/services, validate, no prompt pause
  --validate            Run macOS validation only
  --uninstall           Uninstall Miloco components using payload installer, then clean macOS desktop/service entries

Options:
  --account-auth TEXT   Xiaomi OAuth authorization code or full callback URL
  --omni-api-key TEXT   Omni / MiMo API key
  --omni-base-url URL   OpenAI-compatible base URL
  --omni-model TEXT     Vision/multimodal model name
  --miloco-port PORT    Default: 1810
  --openclaw-port PORT  Default: 18789
  --delete-home         Forwarded to payload uninstall
  --keep-home           Forwarded to payload uninstall
  --lang LANG           Forwarded to payload installer
  -h, --help            Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agent-prepare)
      ACTION="agent-prepare"
      AGENT_MODE=1
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --agent-finish)
      ACTION="agent-finish"
      AGENT_MODE=1
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --validate)
      ACTION="validate"
      AGENT_MODE=1
      shift
      ;;
    --uninstall)
      ACTION="uninstall"
      AGENT_MODE=1
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --account-auth)
      MILOCO_AUTH_PAYLOAD_ARG="$2"
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --omni-api-key)
      MIMO_API_KEY_ARG="$2"
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --omni-model)
      OMNI_MODEL_ARG="$2"
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --omni-base-url)
      OMNI_BASE_URL_ARG="$2"
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --miloco-port)
      MILOCO_PORT="$2"
      shift 2
      ;;
    --openclaw-port)
      OPENCLAW_PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --delete-home|--keep-home|--lang|--dev)
      if [ "$1" = "--lang" ]; then
        INSTALL_ARGS+=("$1" "$2")
        shift 2
      else
        INSTALL_ARGS+=("$1")
        shift
      fi
      ;;
    *)
      INSTALL_ARGS+=("$1")
      shift
      ;;
  esac
done

say_step() {
  printf '\n== %s ==\n' "$1"
}

fail() {
  printf '\n[FAIL] %s\n' "$1" >&2
  if [ "$AGENT_MODE" -eq 0 ]; then
    printf '按回车关闭这个窗口。\n' >&2
    read -r _ || true
  fi
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

detect_existing_install() {
  detected="no"
  miloco_cli="no"
  openclaw_cli="no"
  miloco_home="no"
  miloco_service="no"
  miloco_health="no"
  openclaw_http="no"
  miloco_plugin="no"
  miloco_url=""

  command -v miloco-cli >/dev/null 2>&1 && miloco_cli="yes"
  command -v openclaw >/dev/null 2>&1 && openclaw_cli="yes"
  [ -d "$HOME/.openclaw/miloco" ] && miloco_home="yes"

  if [ "$miloco_cli" = "yes" ]; then
    status="$(miloco-cli service status 2>/dev/null || true)"
    printf '%s' "$status" | grep -Eiq 'running|true|url=http' && miloco_service="yes"
    miloco_url="$(miloco-cli config get server.url --value-only 2>/dev/null || true)"
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 2 "http://127.0.0.1:$MILOCO_PORT/health" >/dev/null 2>&1 && miloco_health="yes"
    openclaw_code="$(curl -sS -o /tmp/easy-miloco-openclaw-probe-body -w "%{http_code}" --max-time 2 "http://127.0.0.1:$OPENCLAW_PORT/" 2>/tmp/easy-miloco-openclaw-probe-err || true)"
    rm -f /tmp/easy-miloco-openclaw-probe-body /tmp/easy-miloco-openclaw-probe-err 2>/dev/null || true
    printf '%s' "$openclaw_code" | grep -Eq '^[234][0-9][0-9]$' && openclaw_http="yes"
  fi

  if [ "$openclaw_cli" = "yes" ]; then
    openclaw plugins inspect miloco-openclaw-plugin 2>/dev/null | grep -Eiq 'Status:[[:space:]]*loaded|loaded|miloco' && miloco_plugin="yes"
  fi

  for signal in "$miloco_cli" "$miloco_home" "$miloco_service" "$miloco_health" "$miloco_plugin"; do
    if [ "$signal" = "yes" ]; then
      detected="yes"
      break
    fi
  done

  printf 'DETECTED=%s\n' "$detected"
  printf 'MILOCO_CLI=%s\n' "$miloco_cli"
  printf 'OPENCLAW_CLI=%s\n' "$openclaw_cli"
  printf 'MILOCO_HOME=%s\n' "$miloco_home"
  printf 'MILOCO_SERVICE=%s\n' "$miloco_service"
  printf 'MILOCO_HEALTH=%s\n' "$miloco_health"
  printf 'OPENCLAW_HTTP=%s\n' "$openclaw_http"
  printf 'MILOCO_PLUGIN=%s\n' "$miloco_plugin"
  printf 'MILOCO_URL=%s\n' "$miloco_url"
}

stop_existing_services_for_backup() {
  launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist" >/tmp/easy-miloco-macos-openclaw-bootout.log 2>&1 || true
  launchctl unload "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist" >/tmp/easy-miloco-macos-openclaw-unload.log 2>&1 || true
  supervisorctl -c "$HOME/.openclaw/miloco/supervisord.conf" shutdown >/tmp/easy-miloco-macos-supervisor-stop.log 2>&1 || true
  pkill -TERM -f "/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
  pkill -TERM -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true
  sleep 1
  pkill -KILL -f "/.local/share/uv/tools/miloco/bin/[p]ython -m miloco.main" 2>/dev/null || true
  pkill -KILL -f "[o]penclaw/dist/index.js gateway --port" 2>/dev/null || true
}

export_existing_restore_pack() {
  say_step "Backing up existing Miloco"

  desktop="$HOME/Desktop"
  if [ ! -d "$desktop" ]; then
    fail "Cannot find Desktop. Existing Miloco backup must be written before uninstall."
  fi

  stop_existing_services_for_backup

  export EXPORT_DESKTOP="$desktop"
  export MILOCO_HOME_DIR="$HOME/.openclaw/miloco"
  backup_output="$(python3 - <<'PY'
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path

desktop = Path(os.environ["EXPORT_DESKTOP"])
home = Path(os.environ["MILOCO_HOME_DIR"])
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

agent_text = """# Miloco Agent 恢复说明

这是 Agent 恢复包，不是直接覆盖包。请先读取 manifest.json，确认 schema_version / assets / restore_contract，再创建导入前 checkpoint。

恢复原则：

1. 不要把数据库、身份库、配置文件原样覆盖到当前安装。
2. 先生成差异计划，向用户确认高风险项。
3. 模型配置、家庭成员、家庭档案、家庭任务要分阶段恢复。
4. 家庭任务优先恢复为 disabled 或 draft，用户确认后再启用。
5. 通知动作、设备、摄像头、账号登录态要按当前机器重新映射。
6. 发生错误时按导入日志回滚。
"""

def ensure_agents(zip_path: Path) -> None:
    tmp = zip_path.with_suffix(zip_path.suffix + ".agents.tmp")
    with zipfile.ZipFile(zip_path, "r") as zin, zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
        for info in zin.infolist():
            if info.filename == "AGENTS.md":
                continue
            zout.writestr(info, zin.read(info.filename))
        zout.writestr("AGENTS.md", agent_text)
    tmp.replace(zip_path)

def add_file(zf: zipfile.ZipFile, src: Path, arc: str) -> bool:
    if src.exists() and src.is_file():
        zf.write(src, arc)
        return True
    return False

def add_tree(zf: zipfile.ZipFile, src: Path, arc_root: str) -> int:
    count = 0
    if not src.exists() or not src.is_dir():
        return count
    excluded = {"log", "logs", "snapshots", "images", "miot_cache", ".install-cache", "packs"}
    for path in sorted(p for p in src.rglob("*") if p.is_file()):
        rel = path.relative_to(src)
        if any(part in excluded for part in rel.parts):
            continue
        zf.write(path, f"{arc_root}/{rel.as_posix()}")
        count += 1
    return count

def fallback_pack() -> tuple[Path, str]:
    filename = f"miloco-agent-restore-pack-{stamp}-{uuid.uuid4().hex[:8]}-compat.zip"
    path = Path(tempfile.gettempdir()) / filename
    assets = []
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.writestr("AGENTS.md", agent_text)
        zf.writestr("RESTORE.md", agent_text)
        if add_file(zf, home / "config.json", "raw/config.json"):
            assets.append("model_config")
        if add_tree(zf, home / "home-profile", "raw/home-profile"):
            assets.append("home_profile")
        if add_tree(zf, home / "identity-lib", "raw/identity-lib"):
            assets.append("members")
        db = home / "miloco.db"
        if db.exists():
            try:
                snapshot = Path(tempfile.gettempdir()) / f"miloco-db-{uuid.uuid4().hex[:8]}.db"
                src = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
                dst = sqlite3.connect(snapshot)
                src.backup(dst)
                src.close()
                dst.close()
                zf.write(snapshot, "raw/miloco.db")
                snapshot.unlink(missing_ok=True)
            except Exception:
                zf.write(db, "raw/miloco.db")
            assets.extend(["members", "tasks"])
        manifest = {
            "kind": "miloco-agent-restore-pack",
            "schema_version": 1,
            "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "source": {
                "app": "easy-miloco",
                "platform": "macos",
                "miloco_home_hint": str(home),
                "export_mode": "compat_raw_snapshot",
            },
            "assets": sorted(set(assets)),
            "restore_contract": "agent_restore_v1",
            "notes": [
                "This compatibility pack was created because the old installed Miloco did not expose the logical backup exporter.",
                "Agent must inspect and migrate; do not copy raw files over the new installation.",
            ],
        }
        zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    return path, "compat_raw_snapshot"

def logical_pack() -> tuple[Path, str]:
    candidates = [
        Path.home() / ".local/share/uv/tools/miloco/bin/python",
        Path.home() / ".local/share/uv/tools/miloco-cli/bin/python",
    ]
    commands = [[str(path), "-c", "from miloco.admin.backup_export import build_agent_restore_pack; r=build_agent_restore_pack(); print(r.path)"] for path in candidates if path.is_file()]
    commands.append(["python3", "-c", "from miloco.admin.backup_export import build_agent_restore_pack; r=build_agent_restore_pack(); print(r.path)"])
    errors = []
    for cmd in commands:
        try:
            result = subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=60)
            path = Path(result.stdout.strip().splitlines()[-1])
            if path.is_file():
                ensure_agents(path)
                return path, "logical_export"
        except Exception as exc:
            errors.append(f"{cmd[0]}: {exc}")
    raise RuntimeError("; ".join(errors))

try:
    src, mode = logical_pack()
except Exception:
    src, mode = fallback_pack()

target = desktop / src.name
shutil.copy2(src, target)
if not target.is_file() or target.stat().st_size <= 0:
    print("BACKUP_ERROR=empty backup", file=sys.stderr)
    sys.exit(2)
print(f"BACKUP_MODE={mode}")
print(f"BACKUP_FILENAME={target.name}")
print(f"BACKUP_PATH={target}")
PY
)" || fail "Existing Miloco backup failed. Installation stopped to avoid deleting user data."

  backup_filename="$(printf '%s\n' "$backup_output" | awk -F= '/^BACKUP_FILENAME=/{print $2; exit}')"
  backup_mode="$(printf '%s\n' "$backup_output" | awk -F= '/^BACKUP_MODE=/{print $2; exit}')"
  backup_path="$desktop/$backup_filename"
  if [ -z "$backup_filename" ] || [ ! -f "$backup_path" ]; then
    printf '%s\n' "$backup_output" >&2
    fail "Existing Miloco backup did not produce a desktop ZIP. Installation stopped."
  fi
  EXISTING_RESTORE_PACK_PATH="$backup_path"
  printf '[OK] Existing Miloco backup: %s (mode: %s)\n' "$backup_path" "${backup_mode:-unknown}"
}

remove_existing_install() {
  say_step "清理旧版 Miloco"

  stop_existing_services_for_backup

  if command -v openclaw >/dev/null 2>&1; then
    printf 'y\n' | openclaw plugins uninstall miloco-openclaw-plugin >/tmp/easy-miloco-macos-plugin-uninstall.log 2>&1 || true
  fi
  if command -v uv >/dev/null 2>&1; then
    uv tool uninstall miloco-cli >/tmp/easy-miloco-macos-miloco-cli-uninstall.log 2>&1 || true
    uv tool uninstall miloco >/tmp/easy-miloco-macos-miloco-uninstall.log 2>&1 || true
    uv tool uninstall supervisor >/tmp/easy-miloco-macos-supervisor-uninstall.log 2>&1 || true
  fi

  rm -rf "$HOME/.openclaw/miloco"
  rm -f \
    "$HOME/Desktop/Miloco Console.command" \
    "$HOME/Desktop/OpenClaw Chat.command" \
    "$HOME/Desktop/OpenClaw-login-info.txt" \
    "$HOME/Desktop/Miloco 控制台.command" \
    "$HOME/Desktop/米Miloco控制台.command" \
    "$HOME/Desktop/OpenClaw 对话.command" \
    "$HOME/Desktop/OpenClaw 登录信息.txt" \
    2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist" 2>/dev/null || true
  rm -f /tmp/easy-miloco-macos-service-start.log /tmp/easy-miloco-macos-service-restart.log 2>/dev/null || true

  printf '[OK] 旧版 Miloco 已清理。备份保留在：%s\n' "$EXISTING_RESTORE_PACK_PATH"
}

prepare_existing_install_for_clean_install() {
  status_file="/tmp/easy-miloco-macos-existing-status.env"
  detect_existing_install > "$status_file"
  detected="$(awk -F= '/^DETECTED=/{print $2; exit}' "$status_file")"
  if [ "$detected" != "yes" ]; then
    printf '[OK] No existing Miloco installation detected.\n'
    return 0
  fi

  say_step "Existing Miloco detected"
  printf 'Current detection result:\n'
  awk -F= '/^[A-Z_]+=/{printf "  %s: %s\n", $1, $2}' "$status_file"
  printf '\nInstaller will first export a desktop Agent restore ZIP, then fully remove the old Miloco installation, then continue with the new install.\n'
  printf 'Do not delete the restore ZIP.\n'

  export_existing_restore_pack
  remove_existing_install
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

configure_openclaw_chat_model() {
  say_step "配置 OpenClaw 聊天模型"
  if ! command -v python3 >/dev/null 2>&1 || ! command -v openclaw >/dev/null 2>&1; then
    printf '[WARN] Cannot configure OpenClaw chat model: python3 or openclaw is missing.\n' >&2
    return 0
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
    print("[WARN] Miloco config not found; skip OpenClaw chat model config.")
    raise SystemExit(0)

miloco = json.loads(miloco_config.read_text(encoding="utf-8"))
omni = miloco.get("model", {}).get("omni", {})
omni_model = str(omni.get("model") or "").strip()
omni_base_url = str(omni.get("base_url") or "").strip()
api_key = str(omni.get("api_key") or "")
if not omni_model or not omni_base_url or not api_key:
    print("[WARN] Miloco Omni model config is incomplete; skip OpenClaw chat model config.")
    raise SystemExit(0)

if openclaw_config.exists():
    data = json.loads(openclaw_config.read_text(encoding="utf-8"))
else:
    data = {}

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

chat_model_id = normalize_model_id(omni_model)
provider_id = infer_provider_id(omni_base_url, chat_model_id)
chat_ref = f"{provider_id}/{chat_model_id}"

plugins = data.setdefault("plugins", {}).setdefault("entries", {})
entry = plugins.setdefault("miloco-openclaw-plugin", {})
config = entry.setdefault("config", {})
config["omni_model"] = omni_model
config["omni_base_url"] = omni_base_url
config["omni_api_key"] = api_key

defaults = as_dict(as_dict(data, "agents"), "defaults")
as_dict(defaults, "model")["primary"] = chat_ref
agent_row = as_dict(as_dict(defaults, "models"), chat_ref)
params = as_dict(agent_row, "params")
params.setdefault("maxTokens", 8192)
if provider_id == "mimo" and chat_model_id in {"mimo-v2.5-pro", "mimo-v2-pro", "mimo-v2.6-pro"}:
    extra_body = as_dict(params, "extraBody")
    extra_body.setdefault("thinking", {"type": "enabled"})
    extra_body.setdefault("reasoning_effort", "high")

models = as_dict(data, "models")
models.setdefault("mode", "merge")
provider = as_dict(as_dict(models, "providers"), provider_id)
provider["baseUrl"] = omni_base_url
provider["apiKey"] = api_key
provider["api"] = "openai-completions"
provider.setdefault("timeoutSeconds", 300)
provider.setdefault("contextWindow", 1000000)
provider.setdefault("contextTokens", 1000000)
provider_models = provider.get("models")
if not isinstance(provider_models, list):
    provider_models = []
if not any(isinstance(row, dict) and row.get("id") == chat_model_id for row in provider_models):
    provider_models.append({"id": chat_model_id, "name": chat_model_id})
for row in provider_models:
    if isinstance(row, dict) and row.get("id") == chat_model_id:
        row.setdefault("input", ["text", "image"])
        row.setdefault("contextWindow", 1000000)
        row.setdefault("contextTokens", 1000000)
        row.setdefault("maxTokens", 8192)
provider["models"] = provider_models

openclaw_config.parent.mkdir(parents=True, exist_ok=True)
backup = None
if openclaw_config.exists():
    backup = openclaw_config.with_name(openclaw_config.name + ".bak.easy-miloco-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(openclaw_config, backup)
openclaw_config.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

validated = subprocess.run(["openclaw", "config", "validate"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
if validated.returncode != 0:
    if backup is not None:
        shutil.copy2(backup, openclaw_config)
    print("[FAIL] OpenClaw config validation failed; restored previous config.")
    print(validated.stdout)
    raise SystemExit(2)
print(f"[OK] OpenClaw chat model configured: primary={chat_ref}")
PY
}

read_openclaw_token() {
  python3 - <<'PY' 2>/dev/null || true
import json
from pathlib import Path
home = Path.home()

def read_json(path):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return {}

def text(value):
    return value.strip() if isinstance(value, str) else ""

miloco = read_json(home / ".openclaw" / "miloco" / "config.json")
openclaw = read_json(home / ".openclaw" / "openclaw.json")
candidates = []
agent = miloco.get("agent") if isinstance(miloco, dict) else {}
if isinstance(agent, dict):
    candidates.append(agent.get("auth_bearer"))
gateway = openclaw.get("gateway") if isinstance(openclaw, dict) else {}
auth = gateway.get("auth") if isinstance(gateway, dict) else {}
if isinstance(auth, dict):
    candidates.extend([auth.get("token"), auth.get("password"), auth.get("bearer")])
for candidate in candidates:
    token = text(candidate)
    if token:
        print(token)
        break
PY
}

url_encode() {
  value="$1"
  VALUE="$value" python3 - <<'PY' 2>/dev/null || true
import os
from urllib.parse import quote
print(quote(os.environ.get("VALUE", ""), safe=""))
PY
}

openclaw_autologin_url() {
  token="$(read_openclaw_token)"
  if [ -n "$token" ]; then
    encoded_token="$(url_encode "$token")"
    if [ -n "$encoded_token" ]; then
      printf 'http://127.0.0.1:%s/#token=%s\n' "$OPENCLAW_PORT" "$encoded_token"
      return 0
    fi
  fi

  dashboard_url="$(openclaw dashboard --no-open --yes 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n 1 || true)"
  if printf '%s' "$dashboard_url" | grep -Eq '(^|[#?&])token='; then
    printf '%s\n' "$dashboard_url"
    return 0
  fi
  printf 'http://127.0.0.1:%s/\n' "$OPENCLAW_PORT"
}

write_openclaw_info_file() {
  info="$1"
  token="$(read_openclaw_token)"
  launch_url="$(openclaw_autologin_url)"
  token_value="$token"
  [ -n "$token_value" ] || token_value="(empty)"
  {
    printf 'OpenClaw 登录信息\n'
    printf '\n'
    printf '推荐直接打开: %s\n' "$launch_url"
    printf '仪表板地址: http://127.0.0.1:%s/\n' "$OPENCLAW_PORT"
    printf 'WebSocket URL: ws://127.0.0.1:%s\n' "$OPENCLAW_PORT"
    printf 'Gateway Token: %s\n' "$token_value"
    printf '\n'
    printf '最省事的用法：\n'
    printf '1. 直接双击桌面的 OpenClaw 对话.command；它会刷新本文件，并用带 token 的直达地址打开。\n'
    printf '2. 如果页面仍提示登录，把上面的“推荐直接打开”整段复制到浏览器地址栏。\n'
    printf '3. 如果页面里 token 仍为空，把上面的 Gateway Token 整段粘贴进去。\n'
    printf '\n'
    printf '如何获取 / 刷新这些信息：\n'
    printf '4. 重新双击 OpenClaw 对话.command。\n'
    printf '5. 或在终端运行：openclaw dashboard --no-open --yes\n'
    printf '6. 只想看 token，可运行：openclaw config get gateway.auth.token\n'
    printf '\n'
    printf '如何管理 / 修改：\n'
    printf '7. 当前配置文件：~/.openclaw/openclaw.json\n'
    printf '8. 重点字段：gateway.auth.token\n'
    printf '9. 改完后重开 OpenClaw 对话.command，或重新运行 dashboard 命令刷新。\n'
    printf '\n'
    printf '这份文件会在每次打开 OpenClaw 对话.command 时自动刷新。\n'
  } > "$info"
}

install_desktop_helpers() {
  desktop="$HOME/Desktop"
  [ -d "$desktop" ] || return 0
  console="$desktop/米Miloco控制台.command"
  openclaw_entry="$desktop/OpenClaw 对话.command"
  info="$desktop/OpenClaw 登录信息.txt"

  sed \
    -e "s#__MILOCO_PORT__#$MILOCO_PORT#g" \
    -e "s#__OPENCLAW_PORT__#$OPENCLAW_PORT#g" \
    -e "s#__OPENCLAW_INFO_PATH__#$info#g" \
    "$ROOT/scripts/macos/templates/miloco-console.command.tpl" > "$console"
  chmod +x "$console"

  sed \
    -e "s#__OPENCLAW_PORT__#$OPENCLAW_PORT#g" \
    -e "s#__OPENCLAW_INFO_PATH__#$info#g" \
    "$ROOT/scripts/macos/templates/openclaw-launcher.command.tpl" > "$openclaw_entry"
  chmod +x "$openclaw_entry"

  write_openclaw_info_file "$info"

  printf '[OK] 桌面入口已创建：\n'
  printf '  %s\n' "$console"
  printf '  %s\n' "$openclaw_entry"
  printf '  %s\n' "$info"
}

open_dashboards() {
  miloco_url="http://127.0.0.1:$MILOCO_PORT/"
  openclaw_url="$(openclaw_autologin_url)"

  printf '[OK] Opening Miloco dashboard: %s\n' "$miloco_url"
  open "$miloco_url" >/tmp/easy-miloco-open-miloco.log 2>&1 || true
  printf '[OK] Opening OpenClaw with auto-login: %s\n' "$openclaw_url"
  open "$openclaw_url" >/tmp/easy-miloco-open-openclaw.log 2>&1 || true
}

print_validation_summary() {
  validation_code="$1"
  basic_ready="$2"
  full_ready="$3"
  validation_log="$4"

  if [ "$validation_code" -eq 0 ] && [ "$full_ready" = "yes" ]; then
    printf '[OK] Validation passed: BASIC_READY=yes, FULL_READY=yes\n'
  elif [ "$validation_code" -eq 0 ] && [ "$basic_ready" = "yes" ]; then
    printf '[WARN] Basic validation passed, but full readiness is incomplete.\n' >&2
    printf '       Usually account, model, device rows, or camera scope still needs attention.\n' >&2
  else
    printf '[WARN] Validation reported issues. Full log: %s\n' "$validation_log" >&2
  fi
}

print_final_usage_screen() {
  validation_code="$1"
  basic_ready="$2"
  full_ready="$3"
  validation_log="$4"

  printf '\033c'
  printf '========================================\n'
  printf '  easy-miloco macOS 安装完成\n'
  printf '========================================\n\n'

  if [ "$validation_code" -eq 0 ] && [ "$full_ready" = "yes" ]; then
    printf '状态：已完成，Miloco 和 OpenClaw 均已就绪。\n\n'
  elif [ "$validation_code" -eq 0 ] && [ "$basic_ready" = "yes" ]; then
    printf '状态：基础安装完成，但满血验收未全部通过。\n'
    printf '请先打开下面的面板检查账号、模型、设备或摄像头范围。\n\n'
  else
    printf '状态：安装流程已结束，但验证发现问题。\n'
    printf '请把下面的日志路径发给 Agent 继续排查。\n\n'
  fi

  printf '【快速使用】\n'
  printf '1. miloco控制台。用途：查看状态、重启/关闭服务、打开日志。路径：桌面/米Miloco控制台.command\n'
  printf '2. openclaw聊天页。用途：日常使用miloco，自然语言聊天即可。路径：桌面/OpenClaw 对话.command\n\n'

  printf '【故障备用】\n'
  printf '桌面快捷方式打不开时，再把下面信息发给 Agent 排查；平时不用输入网址。\n'
  printf 'Miloco 面板备用地址： http://127.0.0.1:%s/\n' "$MILOCO_PORT"
  printf 'OpenClaw 登录信息：%s\n\n' "$HOME/Desktop/OpenClaw 登录信息.txt"

  printf '日志位置：\n'
  printf '  安装验证：%s\n' "$validation_log"
  printf '  Miloco 后端：%s\n' "$HOME/.openclaw/miloco/log/"
  printf '  OpenClaw：/tmp/openclaw/\n'
  printf '  OpenClaw 登录信息：%s\n' "$HOME/Desktop/OpenClaw 登录信息.txt"

  if [ -n "$EXISTING_RESTORE_PACK_PATH" ]; then
    printf '\n旧版已先备份再卸载，恢复包在：\n'
    printf '  %s\n' "$EXISTING_RESTORE_PACK_PATH"
  fi
}

validate_installation() {
  say_step "验证安装结果"
  validation_log="/tmp/easy-miloco-macos-validation.log"
  set +e
  bash "$ROOT/scripts/macos/macos-miloco-validate.sh" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT" >"$validation_log" 2>&1
  validation_code="$?"
  set -e
  basic_ready="$(awk -F= '/^BASIC_READY=/{print $2}' "$validation_log" | tail -n 1)"
  full_ready="$(awk -F= '/^FULL_READY=/{print $2}' "$validation_log" | tail -n 1)"
  print_validation_summary "$validation_code" "$basic_ready" "$full_ready" "$validation_log"
  if [ "$AGENT_MODE" -eq 1 ]; then
    cat "$validation_log"
  fi
}

finish_macos_package() {
  say_step "启动服务"
  miloco-cli service start >/tmp/easy-miloco-macos-service-start.log 2>&1 || miloco-cli service restart >/tmp/easy-miloco-macos-service-restart.log 2>&1 || true
  start_openclaw_gateway
  configure_openclaw_chat_model
  start_openclaw_gateway
  install_desktop_helpers
  validate_installation
}

say_step "检查安装包"
need_file "$ROOT/manifest.json"
need_file "$ROOT/payload/install.sh"
need_file "$ROOT/scripts/macos/macos-preflight.sh"
need_file "$ROOT/scripts/macos/macos-miloco-validate.sh"
bundle="$(find_bundle)"
[ -n "$bundle" ] || fail "No matching macOS payload found in payload/."

remove_quarantine_if_present

case "$ACTION" in
  validate)
    validate_installation
    exit 0
    ;;
  uninstall)
    say_step "卸载 Miloco"
    bash "$ROOT/payload/install.sh" "${INSTALL_ARGS[@]}"
    remove_existing_install
    printf '[OK] macOS Miloco uninstall finished.\n'
    exit 0
    ;;
  agent-finish)
    say_step "完成 Agent 授权和模型配置"
    bash "$ROOT/payload/install.sh" "${INSTALL_ARGS[@]}"
    if [ -n "$MILOCO_AUTH_PAYLOAD_ARG" ] || [ -n "$MIMO_API_KEY_ARG" ] || [ -n "$OMNI_MODEL_ARG" ] || [ -n "$OMNI_BASE_URL_ARG" ]; then
      MILOCO_AUTH_PAYLOAD="$MILOCO_AUTH_PAYLOAD_ARG" \
      MIMO_API_KEY="$MIMO_API_KEY_ARG" \
      OMNI_MODEL="$OMNI_MODEL_ARG" \
      OMNI_BASE_URL="$OMNI_BASE_URL_ARG" \
      bash "$ROOT/scripts/macos/macos-post-auth-finish.sh" --no-strict-full --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT" || true
    fi
    finish_macos_package
    exit 0
    ;;
  interactive|agent-prepare)
    ;;
  *)
    fail "Unknown action: $ACTION"
    ;;
esac

prepare_existing_install_for_clean_install

say_step "运行安装前检查"
bash "$ROOT/scripts/macos/macos-preflight.sh" --package-root "$ROOT" --miloco-port "$MILOCO_PORT" --openclaw-port "$OPENCLAW_PORT"

ensure_openclaw
prime_payload_cache "$bundle"

say_step "安装基础组件"
if [ "$AGENT_MODE" -eq 0 ]; then
  printf '提示：下面会出现内层安装器的“基础安装流程完成”。那不是整个懒人包结束。\n'
  printf '看到它以后请继续等待，懒人包还会自动启动服务、创建桌面入口、验证并打开页面。\n\n'
fi
bash "$ROOT/payload/install.sh" "${INSTALL_ARGS[@]}"

say_step "继续完成 macOS 懒人包"
if [ "$AGENT_MODE" -eq 0 ]; then
  printf '基础组件已装完。正在自动启动服务、配置 OpenClaw、创建桌面入口，请不要关闭窗口。\n'
fi

finish_macos_package

if [ "$AGENT_MODE" -eq 0 ]; then
  say_step "打开面板"
  open_dashboards
  print_final_usage_screen "$validation_code" "$basic_ready" "$full_ready" "$validation_log"
  printf '\n按回车关闭这个窗口。\n'
  read -r _ || true
else
  printf '[OK] easy-miloco macOS agent action finished: %s\n' "$ACTION"
  printf 'Miloco: http://127.0.0.1:%s/\n' "$MILOCO_PORT"
  printf 'OpenClaw: http://127.0.0.1:%s/\n' "$OPENCLAW_PORT"
  printf 'Desktop console: %s\n' "$HOME/Desktop/米Miloco控制台.command"
  printf 'OpenClaw chat: %s\n' "$HOME/Desktop/OpenClaw 对话.command"
  printf 'Validation log: %s\n' "$validation_log"
fi
