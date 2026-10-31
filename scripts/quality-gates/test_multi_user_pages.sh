#!/usr/bin/env bash
# Layer B — multi-user page orchestration (optional gate; not in run_all.sh).
# Runs MultiUserPageOrchestrationTests only. No production UI. No rag_assist_v1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

SCHEME="Kuro"
source "$SCRIPT_DIR/ios_verify_helpers.sh"
REPORT_DIR="${KURO_LEFTOVERS_REPORT_DIR:-$ROOT_DIR/reports/leftovers-verify}"
mkdir -p "$REPORT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"


DEST="$(kuro_ios_destination)"

echo "[multi-user-pages] destination: $DEST"
echo "[multi-user-pages] Not claiming G0-G7 or the 16 device journeys."

if xcodebuild -project Kuro.xcodeproj -scheme "$SCHEME" -destination "$DEST" \
  test -only-testing:KuroTests/MultiUserPageOrchestrationTests \
  -resultBundlePath "$REPORT_DIR/multi-user-pages-$STAMP.xcresult" \
  >"$REPORT_DIR/multi-user-pages-$STAMP.log" 2>&1; then
  kuro_verify_selected_ios_tests "$REPORT_DIR/multi-user-pages-$STAMP.log" MultiUserPageOrchestrationTests
  echo "[multi-user-pages] PASS (selected cases executed)"
  exit 0
fi

echo "[multi-user-pages] FAIL (see $REPORT_DIR/multi-user-pages-$STAMP.log)"
exit 1
