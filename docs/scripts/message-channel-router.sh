#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  message-channel-router.sh feishu [--interactive] [--install] [--auth] [--bind] [--validate] [--status] [--json]

One-line agent handoff:
  bash docs/scripts/message-channel-router.sh feishu --interactive --install --auth --bind --validate

Generic channel guide:
  https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/message-channel/docs/message-channels-agent-guide.md
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

channel="$1"
shift

case "$channel" in
  feishu|lark)
    exec bash "$ROOT_DIR/wsl-feishu-channel-onboard.sh" "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unsupported message channel: $channel" >&2
    echo "Supported channels: feishu" >&2
    echo "For other channels, follow: https://raw.githubusercontent.com/andy-JustSayWhen/easy-miloco/message-channel/docs/message-channels-agent-guide.md" >&2
    exit 2
    ;;
esac
