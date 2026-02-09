#!/usr/bin/env bash
# Quality gate: iOS build check
# Runs xcodebuild for the Kuro scheme targeting iOS Simulator.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== iOS Build Check ==="
echo ""

if ! command -v xcodebuild &>/dev/null; then
  echo "FAIL: xcodebuild is not installed (Xcode required)"
  exit 1
fi

PROJECT="$ROOT_DIR/Kuro.xcodeproj"
if [[ ! -d "$PROJECT" ]]; then
  echo "FAIL: $PROJECT not found"
  exit 1
fi

echo "Building Kuro (iOS Simulator, iPhone 17 Pro)..."
echo ""

xcodebuild \
  -project "$PROJECT" \
  -scheme Kuro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build \
  2>&1

BUILD_EXIT=$?

echo ""
if [[ $BUILD_EXIT -ne 0 ]]; then
  echo "HARD FAIL: iOS build failed (exit code $BUILD_EXIT)."
  exit $BUILD_EXIT
fi

echo "iOS build PASSED."
exit 0
