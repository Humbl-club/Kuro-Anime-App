#!/usr/bin/env bash
# Quality gate: Run Kuro iOS unit tests on the simulator.
set -euo pipefail

SCHEME="Kuro"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/ios_verify_helpers.sh"
cd "$ROOT_DIR"

echo "[ios-test] Running unit tests..."

DEST="$(kuro_ios_destination)"
REPORT_DIR="${KURO_IOS_UNIT_REPORT_DIR:-$ROOT_DIR/.codex-artifacts/native-unit}"
mkdir -p "$REPORT_DIR"
RUN_DIR="$(mktemp -d "$REPORT_DIR/unit-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
LOG="$RUN_DIR/tests.log"
RESULT="$RUN_DIR/tests.xcresult"

echo "[ios-test] Using destination: $DEST"
echo "[ios-test] Evidence: $RUN_DIR"
set +e
xcodebuild -project Kuro.xcodeproj -scheme "$SCHEME" -destination "$DEST" \
  test -only-testing:KuroTests -resultBundlePath "$RESULT" 2>&1 | tee "$LOG"
RUN_STATUS=("${PIPESTATUS[@]}")
set -e
if [[ "${RUN_STATUS[0]}" -ne 0 || "${RUN_STATUS[1]}" -ne 0 ]]; then
  echo "[ios-test] FAIL (xcodebuild or log recording failed; see $LOG)"
  exit 1
fi

if ! kuro_verify_selected_ios_tests "$LOG" --any; then
  echo "[ios-test] FAIL (no selected cases executed; see $LOG)"
  exit 1
fi
echo "[ios-test] PASS (selected cases executed)"
exit 0
