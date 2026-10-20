#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_ROOT/Build/SnapX-arm64.app}"
SIGNING_DIR="${SNAPX_SIGNING_CONFIG_DIR:-$HOME/Library/Application Support/SnapX/Signing}"
IDENTITY="$(cat "$SIGNING_DIR/identity.sha1")"
REQUIREMENT="identifier \"com.wuqicheng.snapboard\" and certificate leaf = H\"$IDENTITY\""
VERIFY_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_DIR"' EXIT
codesign --verify --deep --strict -R "=$REQUIREMENT" "$APP"
ditto "$APP" "$VERIFY_DIR/SnapX.app"
/usr/libexec/PlistBuddy -c 'Add :SnapXSigningVerificationBuild bool true' "$VERIFY_DIR/SnapX.app/Contents/Info.plist"
codesign --force --sign "$IDENTITY" "$VERIFY_DIR/SnapX.app"
codesign --verify --deep --strict -R "=$REQUIREMENT" "$VERIFY_DIR/SnapX.app"
original_requirement=$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')
changed_requirement=$(codesign -d -r- "$VERIFY_DIR/SnapX.app" 2>&1 | sed -n 's/^designated => //p')
original_hash=$(codesign -d --verbose=4 "$APP" 2>&1 | sed -n 's/^CDHash=//p')
changed_hash=$(codesign -d --verbose=4 "$VERIFY_DIR/SnapX.app" 2>&1 | sed -n 's/^CDHash=//p')
[[ -n "$original_requirement" && "$original_requirement" == "$changed_requirement" ]]
[[ -n "$original_hash" && -n "$changed_hash" && "$original_hash" != "$changed_hash" ]]
echo 'PASS: changed app content has a different hash but the same signing identity requirement.'
