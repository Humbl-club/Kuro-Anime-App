#!/usr/bin/env bash
# Layer A — leftovers verification (agent-runnable).
# Build + targeted KuroTests + offline Deno. Optional local DB scopes.
# Does NOT claim G0–G7, the 16 device journeys, or App Store readiness.
# Does NOT hit production UI and does NOT enable rag_assist_v1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

SCHEME="Kuro"
source "$SCRIPT_DIR/ios_verify_helpers.sh"
REPORT_DIR="${KURO_LEFTOVERS_REPORT_DIR:-$ROOT_DIR/reports/leftovers-verify}"
mkdir -p "$REPORT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SUMMARY="$REPORT_DIR/layer-a-$STAMP.summary.txt"


log() { echo "$*" | tee -a "$SUMMARY"; }

: >"$SUMMARY"
log "=== Layer A leftovers verify ($STAMP) ==="
log "Report: $SUMMARY"
log "Claims: none for G0-G7 / 16 journeys / App Store / rag_assist_v1"
log ""

FAIL=0
BLOCKED=0

# --- 1. Build ---
log "[1/5] iOS build"
if bash "$SCRIPT_DIR/build_ios.sh" >"$REPORT_DIR/build-$STAMP.log" 2>&1; then
  log "  PASS build"
else
  log "  FAIL build (see $REPORT_DIR/build-$STAMP.log)"
  FAIL=1
fi

# --- 2. Targeted KuroTests ---
DEST="$(kuro_ios_destination)"
log "[2/5] KuroTests leftovers filters (destination: $DEST)"

# Swift Testing: -only-testing takes the suite STRUCT name.
TEST_ARGS=(
  -only-testing:KuroTests/PrivateStateResetTests
  -only-testing:KuroTests/ImportReconcilerTests
  -only-testing:KuroTests/ClubErrorTests
  -only-testing:KuroTests/ClubsViewRulesTests
  -only-testing:KuroTests/ClubsRealtimeTests
  -only-testing:KuroTests/ConciergeRoutingTests
  -only-testing:KuroTests/MultiUserPageOrchestrationTests
)

if xcodebuild -project Kuro.xcodeproj -scheme "$SCHEME" -destination "$DEST" \
  test "${TEST_ARGS[@]}" \
  -resultBundlePath "$REPORT_DIR/leftovers-$STAMP.xcresult" \
  >"$REPORT_DIR/ios-test-$STAMP.log" 2>&1; then
  if kuro_verify_selected_ios_tests "$REPORT_DIR/ios-test-$STAMP.log"       PrivateStateResetTests ImportReconcilerTests ClubErrorTests ClubsViewRulesTests       ClubsRealtimeTests ConciergeRoutingTests MultiUserPageOrchestrationTests >>"$SUMMARY"; then
    log "  PASS targeted KuroTests (selected cases executed)"
  else
    log "  FAIL selected test execution counts"
    FAIL=1
  fi
else
  log "  FAIL targeted KuroTests (see $REPORT_DIR/ios-test-$STAMP.log)"
  FAIL=1
fi

# --- 3. retrieve-assist offline (flag stays off) ---
log "[3/5] deno concierge-retrieve-assist (offline; rag_assist_v1 not touched)"
if deno test --no-prompt supabase/functions/concierge-retrieve-assist/ \
  >"$REPORT_DIR/retrieve-assist-$STAMP.log" 2>&1; then
  log "  PASS retrieve-assist"
else
  log "  FAIL retrieve-assist (see $REPORT_DIR/retrieve-assist-$STAMP.log)"
  FAIL=1
fi

# --- 4. parser corpus ---
log "[4/5] deno concierge-parse rules corpus"
if deno test --no-prompt supabase/functions/concierge-parse/rules_corpus_test.ts \
  >"$REPORT_DIR/parser-corpus-$STAMP.log" 2>&1; then
  log "  PASS parser corpus"
else
  log "  FAIL parser corpus (see $REPORT_DIR/parser-corpus-$STAMP.log)"
  FAIL=1
fi

# --- 5. Optional local DB scopes ---
log "[5/5] local DB clubs privacy + import apply/undo (optional)"
if command -v initdb >/dev/null 2>&1 || [[ -x /opt/homebrew/opt/postgresql@17/bin/initdb ]]; then
  DB_OK=1
  for scope in 20_clubs 63_club_privacy 64_club_privacy 65_club_membership 66_club_realtime 70_import_apply; do
    if bash "$ROOT_DIR/scripts/db/run_local_db_tests.sh" --only "$scope" \
      --report-dir "$REPORT_DIR/db-$scope-$STAMP" \
      >"$REPORT_DIR/db-$scope-$STAMP.log" 2>&1; then
      log "  PASS db --only $scope"
    else
      code=$?
      if [[ $code -eq 4 ]]; then
        log "  BLOCKED db --only $scope (exit 4; not a pass)"
        BLOCKED=1
      else
        log "  FAIL db --only $scope (exit $code; see $REPORT_DIR/db-$scope-$STAMP.log)"
        FAIL=1
      fi
      DB_OK=0
    fi
  done
  [[ $DB_OK -eq 1 ]] || true
else
  log "  BLOCKED local DB (no initdb); not a pass"
  BLOCKED=1
fi

log ""
if [[ $FAIL -ne 0 ]]; then
  log "Layer A: FAIL"
  exit 1
fi
if [[ $BLOCKED -ne 0 ]]; then
  log "Layer A: PARTIAL; required scopes BLOCKED (not a pass)."
  if [[ "${KURO_ALLOW_PARTIAL_VERIFY:-0}" == "1" ]]; then
    log "Developer partial mode: returning 0; this result is not release qualification."
    exit 0
  fi
  exit 4
fi
log "Layer A: PASS (targeted leftovers only). Not a claim that G0-G7 or 16 journeys passed."
exit 0
