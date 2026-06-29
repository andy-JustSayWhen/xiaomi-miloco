#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-easy-miloco-nas}"
SERVICE_NAME="${MILOCO_SERVICE_NAME:-miloco}"
DATA_DIR="$SCRIPT_DIR/data"
BACKUP_DIR="$SCRIPT_DIR/backups"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

log() {
  printf '[easy-miloco-nas] %s\n' "$*"
}

die() {
  printf '[easy-miloco-nas][FAIL] %s\n' "$*" >&2
  exit 1
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -p "$PROJECT_NAME" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -p "$PROJECT_NAME" "$@"
  else
    die "Docker Compose not found. Install Docker/Container Manager first."
  fi
}

ensure_env() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    log "Created .env from .env.example"
  fi
}

nas_ip_hint() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
  elif command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

env_value() {
  local key="$1"
  [ -f "$ENV_FILE" ] || return 1
  awk -F= -v k="$key" '
    $0 !~ /^[[:space:]]*#/ && $1 == k {
      sub(/^[^=]*=/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$ENV_FILE"
}

print_urls() {
  local host="${NAS_HOST:-$(nas_ip_hint)}"
  [ -n "$host" ] || host="<NAS-IP>"
  local miloco_port="${MILOCO_PORT:-1810}"
  local openclaw_port="${OPENCLAW_PORT:-18789}"

  miloco_port="$(env_value MILOCO_PORT || printf '%s' "$miloco_port")"
  openclaw_port="$(env_value OPENCLAW_PORT || printf '%s' "$openclaw_port")"

  local miloco_url="http://${host}:${miloco_port}/"
  local openclaw_url="http://${host}:${openclaw_port}/"
  local generated_openclaw_url=""
  if command -v docker >/dev/null 2>&1; then
    generated_openclaw_url="$(compose exec -T "$SERVICE_NAME" bash -lc 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:/root/.local/bin:$PATH"; timeout 10 openclaw dashboard --no-open --yes 2>/dev/null || true' 2>/dev/null | grep -Eo 'https?://[^[:space:]]+' | tail -n 1 || true)"
    if [ -n "$generated_openclaw_url" ]; then
      openclaw_url="$(printf '%s' "$generated_openclaw_url" | sed -E "s#://(127\\.0\\.0\\.1|localhost)(:[0-9]+)?/#://${host}\\2/#")"
    fi
  fi

  cat <<EOF
【快速使用】
1. Miloco 面板
   用途：查看 Miloco 状态、设备、摄像头和配置。
   地址：$miloco_url

2. OpenClaw 对话页
   用途：日常使用 Miloco，自然语言聊天即可。
   地址：$openclaw_url

3. 日志
   命令：./manage.sh logs

4. 控制服务
   启动：./manage.sh start
   重启：./manage.sh restart
   停止：./manage.sh stop
   验收：./manage.sh validate
EOF
}

preflight() {
  command -v docker >/dev/null 2>&1 || die "docker not found"
  compose version >/dev/null

  local arch
  arch="$(uname -m 2>/dev/null || true)"
  case "$arch" in
    x86_64|amd64|aarch64|arm64) ;;
    *) die "unsupported CPU arch: ${arch:-unknown}. Need x86_64/amd64/aarch64/arm64." ;;
  esac

  [ -f "$SCRIPT_DIR/compose.yaml" ] || die "compose.yaml missing"
  [ -f "$SCRIPT_DIR/Dockerfile" ] || die "Dockerfile missing"
  [ -f "$SCRIPT_DIR/entrypoint.sh" ] || die "entrypoint.sh missing"
  log "preflight ok: arch=$arch"
}

backup() {
  mkdir -p "$BACKUP_DIR"
  if [ ! -d "$DATA_DIR" ]; then
    log "No data directory yet; skip backup."
    return
  fi
  local ts out
  ts="$(date +%Y%m%d-%H%M%S)"
  out="$BACKUP_DIR/easy-miloco-nas-data-$ts.tar.gz"
  tar -czf "$out" -C "$SCRIPT_DIR" data
  log "Backup created: $out"
}

start() {
  preflight
  ensure_env
  compose up -d --build
  print_urls
}

restart() {
  ensure_env
  compose restart "$SERVICE_NAME"
  print_urls
}

stop() {
  compose down
}

status() {
  compose ps
  compose exec -T "$SERVICE_NAME" bash -lc 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:/root/.local/bin:$PATH"; printf "\n== Miloco ==\n"; miloco-cli service status 2>&1 || true; printf "\n== OpenClaw ==\n"; openclaw gateway status 2>&1 || true'
}

logs() {
  compose logs -f "$SERVICE_NAME"
}

validate() {
  compose exec -T "$SERVICE_NAME" bash -lc 'set +e; export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:/root/.local/bin:$PATH"; MILOCO_PORT="${MILOCO_PORT:-1810}" OPENCLAW_PORT="${OPENCLAW_PORT:-18789}" bash /data/wsl-miloco-validate.sh'
}

update() {
  preflight
  ensure_env
  backup
  compose pull || true
  compose up -d --build
  print_urls
}

uninstall() {
  compose down
  if [ "${1:-}" = "--delete-data" ]; then
    backup
    rm -rf "$DATA_DIR"
    log "Data deleted: $DATA_DIR"
  else
    log "Container removed. Data kept at: $DATA_DIR"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  ./manage.sh start          预检并启动 NAS Docker 部署
  ./manage.sh urls           显示 Miloco / OpenClaw 访问地址
  ./manage.sh status         查看容器、Miloco、OpenClaw 状态
  ./manage.sh logs           跟随安装和运行日志
  ./manage.sh validate       运行基础/满血验收
  ./manage.sh restart        重启服务
  ./manage.sh stop           停止并移除容器，保留 data/
  ./manage.sh update         备份 data/ 后更新/重建容器
  ./manage.sh backup         备份 data/
  ./manage.sh uninstall      移除容器，保留 data/
  ./manage.sh uninstall --delete-data
EOF
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  preflight) preflight "$@" ;;
  start|up) start "$@" ;;
  urls|open) print_urls "$@" ;;
  status|ps) status "$@" ;;
  logs|log) logs "$@" ;;
  validate|check) validate "$@" ;;
  restart) restart "$@" ;;
  stop|down) stop "$@" ;;
  update) update "$@" ;;
  backup) backup "$@" ;;
  uninstall|remove) uninstall "$@" ;;
  help|-h|--help) usage ;;
  *) usage; die "unknown command: $cmd" ;;
esac
