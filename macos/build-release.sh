#!/usr/bin/env bash
set -euo pipefail

export COPYFILE_DISABLE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_ROOT="$REPO_ROOT/dist"
DIST_DIR="$DIST_ROOT/macos"
STAGE_ROOT="$DIST_ROOT/stage"
VERSION="v0.1"
ARTIFACT_VERSION=""
ARCH="$(uname -m)"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: macos/build-release.sh [options]

Options:
  --version <vX>              Package version, default v0.1
  --artifact-version <ver>    Runtime artifact version, default date
  --arch <arm64|x86_64>       macOS target architecture, default current arch
  --skip-build                Reuse existing dist/install.sh and darwin bundle
  -h, --help                  Show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --artifact-version) ARTIFACT_VERSION="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[FAIL] unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$ARCH" in
  arm64|x86_64) ;;
  *) printf '[FAIL] unsupported arch: %s\n' "$ARCH" >&2; exit 2 ;;
esac

if [ -z "$ARTIFACT_VERSION" ]; then
  raw="${VERSION#v}"
  if printf '%s' "$raw" | grep -Eq '^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}([-.][0-9A-Za-z.]+)?$'; then
    ARTIFACT_VERSION="$raw"
  else
    ARTIFACT_VERSION="$(date '+%Y.%-m.%-d')"
  fi
fi

PACKAGE_NAME="easy-miloco-${VERSION}-macos-${ARCH}"
PACKAGE_ROOT="$STAGE_ROOT/$PACKAGE_NAME"
ZIP_PATH="$DIST_DIR/$PACKAGE_NAME.zip"
BUNDLE_KEY="darwin-$ARCH"
BUNDLE_GLOB="miloco-${BUNDLE_KEY}-*.tar.gz"

log() { printf '[macos-build] %s\n' "$*"; }
need_file() { [ -f "$1" ] || { printf '[FAIL] missing file: %s\n' "$1" >&2; exit 3; }; }

if [ "$SKIP_BUILD" -eq 0 ]; then
  log "building runtime artifacts version=$ARTIFACT_VERSION"
  bash "$REPO_ROOT/scripts/build.sh" --version "$ARTIFACT_VERSION"
else
  log "skip build; reuse dist artifacts"
fi

need_file "$DIST_ROOT/install.sh"
need_file "$DIST_ROOT/manifest.json"
bundle="$(find "$DIST_ROOT" -maxdepth 1 -type f -name "$BUNDLE_GLOB" | head -n 1)"
[ -n "$bundle" ] || { printf '[FAIL] missing bundle: dist/%s\n' "$BUNDLE_GLOB" >&2; exit 3; }

rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/payload" "$PACKAGE_ROOT/scripts/macos/templates" "$DIST_DIR"

cp "$REPO_ROOT/macos/package/install.command" "$PACKAGE_ROOT/install.command"
chmod +x "$PACKAGE_ROOT/install.command"
cp "$DIST_ROOT/install.sh" "$PACKAGE_ROOT/payload/install.sh"
chmod +x "$PACKAGE_ROOT/payload/install.sh"
cp "$bundle" "$PACKAGE_ROOT/payload/$(basename "$bundle")"
cp "$DIST_ROOT/manifest.json" "$PACKAGE_ROOT/manifest.json"
cp "$REPO_ROOT/docs/scripts/macos-preflight.sh" "$PACKAGE_ROOT/scripts/macos/macos-preflight.sh"
cp "$REPO_ROOT/docs/scripts/macos-miloco-validate.sh" "$PACKAGE_ROOT/scripts/macos/macos-miloco-validate.sh"
cp "$REPO_ROOT/docs/scripts/macos-post-auth-finish.sh" "$PACKAGE_ROOT/scripts/macos/macos-post-auth-finish.sh"
cp "$REPO_ROOT/macos/package/templates/miloco-console.command.tpl" "$PACKAGE_ROOT/scripts/macos/templates/miloco-console.command.tpl"
cp "$REPO_ROOT/macos/package/templates/openclaw-launcher.command.tpl" "$PACKAGE_ROOT/scripts/macos/templates/openclaw-launcher.command.tpl"
chmod +x "$PACKAGE_ROOT/scripts/macos/"*.sh

cp -R "$REPO_ROOT/docs" "$PACKAGE_ROOT/docs"
rm -rf "$PACKAGE_ROOT/docs/windows/reports"

cat > "$PACKAGE_ROOT/README.md" <<EOF
# easy-miloco ${VERSION} macOS ${ARCH}

## 懒人安装

1. 双击解压这个 zip。
2. 打开解压后的文件夹。
3. 双击 \`install.command\`。
4. 按窗口提示完成米家授权和模型 API 配置。

如果 macOS 提示文件被阻止，打开“终端”执行：

\`\`\`bash
xattr -dr com.apple.quarantine "$PACKAGE_NAME"
chmod +x "$PACKAGE_NAME/install.command"
\`\`\`

## Agent 安装

打开 \`agent-prompt.md\`，复制给 Agent，让 Agent 按提示执行。

## 常用地址

- Miloco: http://127.0.0.1:1810/
- OpenClaw: http://127.0.0.1:18789/
EOF

cat > "$PACKAGE_ROOT/release-notes.md" <<EOF
# easy-miloco ${VERSION} macOS ${ARCH} Release Notes

- Adds lazy double-click macOS installation via \`install.command\`.
- Bundles local \`${BUNDLE_KEY}\` Miloco runtime payload.
- Adds macOS preflight, validation, and post-auth finish scripts.
- Adds Agent one-prompt installation handoff.
EOF

cp "$REPO_ROOT/docs/macos/agent-prompt.md" "$PACKAGE_ROOT/agent-prompt.md"

python3 - "$PACKAGE_ROOT/manifest.json" "$PACKAGE_NAME" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["package"] = {
    "name": sys.argv[2],
    "channel": "stable",
    "repository": "https://github.com/andy-JustSayWhen/easy-miloco",
    "target": "macos",
}
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

find "$PACKAGE_ROOT" -name '.DS_Store' -delete
find "$PACKAGE_ROOT" -name '._*' -delete
find "$PACKAGE_ROOT" -type f \( -name '*.sh' -o -name '*.command' -o -name '*.tpl' \) -exec perl -0pi -e 's/\r\n?/\n/g' {} \;
chmod +x "$PACKAGE_ROOT/install.command" "$PACKAGE_ROOT/payload/install.sh" "$PACKAGE_ROOT/scripts/macos/"*.sh

log "validating package structure"
need_file "$PACKAGE_ROOT/install.command"
need_file "$PACKAGE_ROOT/agent-prompt.md"
need_file "$PACKAGE_ROOT/payload/install.sh"
need_file "$PACKAGE_ROOT/payload/$(basename "$bundle")"
need_file "$PACKAGE_ROOT/scripts/macos/macos-preflight.sh"
need_file "$PACKAGE_ROOT/scripts/macos/macos-miloco-validate.sh"
need_file "$PACKAGE_ROOT/scripts/macos/macos-post-auth-finish.sh"

if find "$PACKAGE_ROOT" \( -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' \) | grep -q .; then
  printf '[FAIL] package contains macOS metadata files\n' >&2
  exit 4
fi

rm -f "$ZIP_PATH"
python3 - "$PACKAGE_ROOT" "$ZIP_PATH" <<'PY'
import os, stat, sys, zipfile
from pathlib import Path
root = Path(sys.argv[1])
zip_path = Path(sys.argv[2])
base = root.parent
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(base).as_posix()
        if path.is_dir():
            continue
        st = path.stat()
        info = zipfile.ZipInfo(rel)
        info.create_system = 3
        info.external_attr = (st.st_mode & 0xFFFF) << 16
        with path.open("rb") as f:
            zf.writestr(info, f.read(), compress_type=zipfile.ZIP_DEFLATED)
PY

python3 - "$ZIP_PATH" <<'PY'
import sys, zipfile
from pathlib import Path
zip_path = Path(sys.argv[1])
with zipfile.ZipFile(zip_path) as zf:
    names = set(zf.namelist())
    root = sorted({n.split('/')[0] for n in names if n})[0]
    required = [
        f"{root}/install.command",
        f"{root}/agent-prompt.md",
        f"{root}/manifest.json",
        f"{root}/payload/install.sh",
        f"{root}/scripts/macos/macos-preflight.sh",
        f"{root}/scripts/macos/macos-miloco-validate.sh",
        f"{root}/scripts/macos/macos-post-auth-finish.sh",
    ]
    missing = [x for x in required if x not in names]
    if missing:
        raise SystemExit(f"missing in zip: {missing}")
print(zip_path)
PY

log "created $ZIP_PATH"
