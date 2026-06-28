#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MILOCO_PORT="${MILOCO_PORT:-1810}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"
EXISTING_RESTORE_PACK_PATH=""

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
  say_step "Removing existing Miloco"

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
  rm -f "$HOME/Desktop/Miloco Console.command" "$HOME/Desktop/OpenClaw Chat.command" "$HOME/Desktop/OpenClaw-login-info.txt" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist" 2>/dev/null || true
  rm -f /tmp/easy-miloco-macos-service-start.log /tmp/easy-miloco-macos-service-restart.log 2>/dev/null || true

  printf '[OK] Existing Miloco removed. Backup preserved at: %s\n' "$EXISTING_RESTORE_PACK_PATH"
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
    printf 'How to use:\n'
    printf '1. Double-click OpenClaw Chat.command to talk to the assistant.\n'
    printf '2. Double-click Miloco Console.command to open/restart/status Miloco and OpenClaw.\n'
    printf '3. Ask OpenClaw: 家里有几个摄像头？画面如何？\n'
    printf '4. Open Miloco dashboard to inspect devices, cameras, perception, and settings.\n'
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

prepare_existing_install_for_clean_install

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
printf 'Desktop OpenClaw chat: %s\n' "$HOME/Desktop/OpenClaw Chat.command"
printf 'Desktop login/info file: %s\n' "$HOME/Desktop/OpenClaw-login-info.txt"
if [ -n "$EXISTING_RESTORE_PACK_PATH" ]; then
  printf '\n[IMPORTANT] Existing Miloco was detected and backed up before uninstall:\n'
  printf '  %s\n' "$EXISTING_RESTORE_PACK_PATH"
  printf 'This ZIP contains recoverable assets such as model config, home profile, identity data, and tasks when present.\n'
  printf 'To restore old config, give this ZIP path to local OpenClaw and ask it to follow AGENTS.md inside the ZIP.\n'
fi
printf '\nHow to use:\n'
printf '  1. Miloco dashboard is for devices, cameras, perception status, and settings.\n'
printf '  2. OpenClaw Chat is for asking the assistant about the home.\n'
printf '  3. Try asking: 家里有几个摄像头？画面如何？\n'
printf '  4. Miloco Console.command can open panels, restart services, stop services, and show status.\n'
printf 'Logs:\n'
printf '  %s\n' "$validation_log"
printf '  /tmp/easy-miloco-macos-service-start.log\n'
printf '  %s\n' "$HOME/.openclaw/miloco/log/"
printf '  %s\n' "$HOME/Library/Logs/openclaw/gateway.log"

printf '\nPress Enter to close this window.\n'
read -r _ || true
