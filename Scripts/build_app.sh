#!/bin/bash

set -euo pipefail

# Usage: build_app.sh [arm64|x86_64|universal]
# Default: universal

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="SnapX"
OUTPUT_DIR="$PROJECT_ROOT/Build"
INFO_PLIST_TEMPLATE="$PROJECT_ROOT/Packaging/$APP_NAME-Info.plist"
APP_ICON="$PROJECT_ROOT/Packaging/AppIcon.icns"
ARCH="${1:-universal}"

# Local builds must keep the same certificate. CI may explicitly request ad-hoc signing.
SIGNING_MODE="${SNAPX_SIGNING_MODE:-local}"
SIGNING_DIR="${SNAPX_SIGNING_CONFIG_DIR:-$HOME/Library/Application Support/SnapX/Signing}"
case "$SIGNING_MODE" in
  local)
    if [[ ! -f "$SIGNING_DIR/identity.sha1" ]]; then
      echo "Run bash Scripts/setup_local_signing.sh once before building." >&2
      exit 1
    fi
    SIGNING_IDENTITY="$(cat "$SIGNING_DIR/identity.sha1")"
    if [[ ! "$SIGNING_IDENTITY" =~ ^[A-Fa-f0-9]{40}$ ]] ||
       ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
      echo "The pinned SnapX Dev signing identity is unavailable. Restore it in Keychain Access." >&2
      exit 1
    fi
    ;;
  adhoc) SIGNING_IDENTITY="-" ;;
  *) echo "Unknown SNAPX_SIGNING_MODE: $SIGNING_MODE" >&2; exit 1 ;;
esac

# The current Command Line Tools SDK lacks SwiftUI macro plugins; prefer full Xcode when available.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

build_app_bundle() {
  local arch="$1"
  local binary="$2"
  local app_bundle="$OUTPUT_DIR/$APP_NAME-${arch}.app"
  local contents="$app_bundle/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"

  rm -rf "$app_bundle"
  mkdir -p "$macos" "$resources"

  cp "$binary" "$macos/$APP_NAME"
  cp "$INFO_PLIST_TEMPLATE" "$contents/Info.plist"
  [[ -f "$APP_ICON" ]] && cp "$APP_ICON" "$resources/AppIcon.icns"
  for wav in "$PROJECT_ROOT/Packaging/"*.wav; do
    [[ -f "$wav" ]] && cp "$wav" "$resources/"
  done

  chmod +x "$macos/$APP_NAME"

  # Sign with the pinned certificate, never silently fall back to an ad-hoc signature.
  codesign --force --sign "$SIGNING_IDENTITY" "$app_bundle" >/dev/null
  codesign --verify --deep --strict "$app_bundle"

  echo "$app_bundle"
}

mkdir -p "$OUTPUT_DIR"

case "$ARCH" in
  arm64)
    echo "Building for arm64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch arm64
    BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch arm64)/$APP_NAME"
    build_app_bundle "arm64" "$BIN"
    ;;

  x86_64)
    echo "Building for x86_64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch x86_64
    BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch x86_64)/$APP_NAME"
    build_app_bundle "x86_64" "$BIN"
    ;;

  universal)
    echo "Building for arm64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch arm64
    ARM64_BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch arm64)/$APP_NAME"
    # Some Swift build systems share output paths across architectures. Preserve this slice now.
    ARM64_SLICE="$OUTPUT_DIR/$APP_NAME-arm64"
    cp "$ARM64_BIN" "$ARM64_SLICE"

    echo "Building for x86_64..."
    swift build -c release --package-path "$PROJECT_ROOT" --arch x86_64
    X86_64_BIN="$(swift build -c release --show-bin-path --package-path "$PROJECT_ROOT" --arch x86_64)/$APP_NAME"
    X86_64_SLICE="$OUTPUT_DIR/$APP_NAME-x86_64"
    cp "$X86_64_BIN" "$X86_64_SLICE"

    UNIVERSAL_BIN="$OUTPUT_DIR/$APP_NAME-universal"
    lipo -create "$ARM64_SLICE" "$X86_64_SLICE" -output "$UNIVERSAL_BIN"
    build_app_bundle "universal" "$UNIVERSAL_BIN"
    ;;

  *)
    echo "Usage: build_app.sh [arm64|x86_64|universal]" >&2
    exit 1
    ;;
esac
