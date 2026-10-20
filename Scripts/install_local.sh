#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCH="${1:-$(uname -m)}"
TARGET=/Applications/SnapX.app
SIGNING_DIR="${SNAPX_SIGNING_CONFIG_DIR:-$HOME/Library/Application Support/SnapX/Signing}"

# Do not terminate the app: screenshot editor windows may contain unsaved work.
if pgrep -x SnapX >/dev/null; then
  echo '请先保存截图并从菜单栏退出 SnapX，再运行本脚本。' >&2
  exit 1
fi
SNAPX_SIGNING_MODE=local bash "$SCRIPT_DIR/build_app.sh" "$ARCH"
APP="$PROJECT_ROOT/Build/SnapX-${ARCH}.app"
IDENTITY="$(cat "$SIGNING_DIR/identity.sha1")"
REQUIREMENT="identifier \"com.wuqicheng.snapboard\" and certificate leaf = H\"$IDENTITY\""
codesign --verify --deep --strict -R "=$REQUIREMENT" "$APP"
if pgrep -x SnapX >/dev/null; then
  echo '构建期间 SnapX 已启动，请退出后再安装。' >&2
  exit 1
fi
# Stage on the destination filesystem and preserve the previous complete app for rollback.
STAGING=$(mktemp -d /Applications/.SnapX-install.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/SnapX.app"
codesign --verify --deep --strict -R "=$REQUIREMENT" "$STAGING/SnapX.app"
BACKUP="$HOME/Library/Application Support/SnapX/InstallBackups/$(date +%Y%m%d-%H%M%S)-$$"
if [[ -e "$TARGET" ]]; then
  mkdir -p "$BACKUP"
  ditto "$TARGET" "$BACKUP/SnapX.app"
  mv "$TARGET" "$STAGING/previous.app"
fi
if ! mv "$STAGING/SnapX.app" "$TARGET"; then
  [[ ! -e "$STAGING/previous.app" ]] || mv "$STAGING/previous.app" "$TARGET"
  exit 1
fi
codesign --verify --deep --strict -R "=$REQUIREMENT" "$TARGET"
echo "已安装固定签名版：$TARGET"
[[ ! -d "$BACKUP" ]] || echo "旧版备份：$BACKUP/SnapX.app"
open "$TARGET"
