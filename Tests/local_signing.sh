#!/bin/bash
set -eu
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/bin" "$test_dir/config"
cat > "$test_dir/bin/swift" <<'STUB'
#!/bin/sh
printf 'BUILD_STARTED\n'
exit 88
STUB
chmod +x "$test_dir/bin/swift"
set +e
output=$(PATH="$test_dir/bin:$PATH" SNAPX_SIGNING_CONFIG_DIR="$test_dir/config" bash Scripts/build_app.sh arm64 2>&1)
result=$?
set -e
if [[ "$result" == 0 || "$output" == *BUILD_STARTED* || "$output" != *setup_local_signing* ]]; then
  printf 'FAIL: missing identity must stop before building and explain setup\n%s\n' "$output"
  exit 1
fi
printf 'PASS: missing identity fails before building\n'
