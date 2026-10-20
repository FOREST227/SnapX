#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_TEMP=$(mktemp -d)
trap 'rm -rf "$TASK_TEMP"' EXIT
mkdir -p "$TASK_TEMP/project/Scripts" "$TASK_TEMP/project/Packaging" "$TASK_TEMP/tools" "$TASK_TEMP/shared-bin"
cp "$PROJECT_ROOT/Scripts/build_app.sh" "$TASK_TEMP/project/Scripts/"
printf '<plist><dict/></plist>\n' > "$TASK_TEMP/project/Packaging/SnapX-Info.plist"
cat > "$TASK_TEMP/tools/swift" <<'STUB'
#!/bin/bash
set -eu
if [[ " $* " == *' --show-bin-path '* ]]; then
  echo "$FAKE_BUILD_BIN"
  exit 0
fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --arch ]]; then printf '%s\n' "$2" > "$FAKE_BUILD_BIN/SnapX"; exit 0; fi
  shift
done
exit 1
STUB
cat > "$TASK_TEMP/tools/lipo" <<'STUB'
#!/bin/bash
set -eu
[[ "$1" == -create && "$4" == -output ]]
if [[ "$(cat "$2")" == "$(cat "$3")" ]]; then
  echo 'FAIL: architecture outputs were overwritten' >&2
  exit 1
fi
cat "$2" "$3" > "$5"
STUB
cat > "$TASK_TEMP/tools/codesign" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$TASK_TEMP/tools/"*
PATH="$TASK_TEMP/tools:$PATH" FAKE_BUILD_BIN="$TASK_TEMP/shared-bin" SNAPX_SIGNING_MODE=adhoc \
  bash "$TASK_TEMP/project/Scripts/build_app.sh" universal
[[ "$(cat "$TASK_TEMP/project/Build/SnapX-universal.app/Contents/MacOS/SnapX")" == $'arm64\nx86_64' ]]
echo 'PASS: universal packaging preserves both architectures even with shared build output paths'
