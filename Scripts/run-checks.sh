#!/bin/bash
# Builds each check in Tests/ against Bow's model and budget sources as a macOS
# executable and runs it, several at a time. Usage: Scripts/run-checks.sh [CheckName ...]
set -uo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${TMPDIR:-/tmp}/bow-checks"
JOBS="${JOBS:-4}"
mkdir -p "$BUILD_DIR" "$BUILD_DIR/ModuleCache"

# Build from a snapshot, so edits made while checks run can't break the build mid-way.
SNAPSHOT="$BUILD_DIR/src"
rm -rf "$SNAPSHOT"
mkdir -p "$SNAPSHOT"
cp -R App Tests "$SNAPSHOT/"
cd "$SNAPSHOT"

# Everything the ledger needs, minus UIKit-only files and the iOS-only background refresh,
# which Tests/Support stands in for.
SOURCES=()
while IFS= read -r file; do
  [ "$file" = App/Import/SimpleFINBackgroundRefresh.swift ] && continue
  grep -q "import UIKit" "$file" || SOURCES+=("$file")
done < <(ls App/Budget/*.swift App/Models/*.swift App/Import/*.swift App/Demo/*.swift Tests/Support/*.swift)

if [ $# -gt 0 ]; then
  CHECKS=()
  for name in "$@"; do CHECKS+=("Tests/${name%.swift}.swift"); done
else
  CHECKS=(Tests/*.swift)
fi

run_check() {
  local check=$1 name output
  name=$(basename "$check" .swift)
  rm -f "$BUILD_DIR/$name.result"
  if ! xcrun swiftc -module-cache-path "$BUILD_DIR/ModuleCache" -parse-as-library -swift-version 5 -target arm64-apple-macos27.0 \
      -module-name BowChecks "${SOURCES[@]}" "$check" -o "$BUILD_DIR/$name" 2> "$BUILD_DIR/$name.log"; then
    { echo "BUILD FAILED  $name"; grep -E "error:" "$BUILD_DIR/$name.log" | head -10; } > "$BUILD_DIR/$name.result"
    return
  fi
  # A failed precondition must exit, not wait on Swift's interactive backtracer.
  if output=$(SWIFT_BACKTRACE=enable=no perl -e 'alarm 120; exec @ARGV' "$BUILD_DIR/$name" 2>&1); then
    echo "passed        $name" > "$BUILD_DIR/$name.result"
  else
    { echo "FAILED        $name"; echo "$output" | tail -5; } > "$BUILD_DIR/$name.result"
  fi
}

for check in "${CHECKS[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do sleep 0.5; done
  run_check "$check" &
done
wait

failed=0
for check in "${CHECKS[@]}"; do
  name=$(basename "$check" .swift)
  cat "$BUILD_DIR/$name.result"
  grep -q "^passed" "$BUILD_DIR/$name.result" || failed=$((failed + 1))
done

echo
if [ "$failed" -gt 0 ]; then
  echo "$failed check(s) failed"
  exit 1
fi
echo "All checks passed"
