#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCH="${1:-$(uname -m)}"
TARGET=/Applications/SnapX.app
SIGNING_DIR="${SNAPX_SIGNING_CONFIG_DIR:-$HOME/Library/Application Support/SnapX/Signing}"

quit_running_snapx() {
  if ! pgrep -x SnapX >/dev/null; then
    return 0
  fi

  echo "正在关闭旧版 SnapX..."
  pkill -TERM -x SnapX 2>/dev/null || true

  local i=0
  while (( i < 30 )); do
    if ! pgrep -x SnapX >/dev/null; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done

  echo "旧版 SnapX 未在预期时间内退出，正在强制结束..."
  pkill -KILL -x SnapX 2>/dev/null || true

  i=0
  while (( i < 20 )); do
    if ! pgrep -x SnapX >/dev/null; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done

  echo "无法关闭正在运行的 SnapX，请手动退出后重试。" >&2
  return 1
}

SNAPX_SIGNING_MODE=local bash "$SCRIPT_DIR/build_app.sh" "$ARCH"
APP="$PROJECT_ROOT/Build/SnapX-${ARCH}.app"
IDENTITY="$(cat "$SIGNING_DIR/identity.sha1")"
REQUIREMENT="identifier \"com.wuqicheng.snapboard\" and certificate leaf = H\"$IDENTITY\""
codesign --verify --deep --strict -R "=$REQUIREMENT" "$APP"

# Stage on the destination filesystem and preserve the previous complete app for rollback.
STAGING=$(mktemp -d /Applications/.SnapX-install.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/SnapX.app"
codesign --verify --deep --strict -R "=$REQUIREMENT" "$STAGING/SnapX.app"

# Close any running instance right before swapping the bundle so failed builds leave it untouched.
quit_running_snapx

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
