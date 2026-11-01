#!/usr/bin/env bash
# Quality gate: Run all gates, print summary table, exit 1 if any hard-fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Gate definitions: name, script, is_blocking (1=hard-fail, 0=warning-only)
# A warning-only gate still runs and prints its findings; a non-zero exit is recorded as WARN in the
# summary (its own count) and never fails the run on its own.
declare -a GATES=(
  "secrets:check_secrets.sh:1"
  "migrations:check_migrations.sh:1"
  "corpora-shape+exec:test_concierge_corpora.sh:1"   # shape check + corpora executed through production parser/router rules (deno)
  "router-rules-exec:test_router_offline.sh:1"       # production router.ts vs 73 offline cases (deno)
  "edge-functions-exec:test_edge_functions.sh:1"     # every offline deno suite: apply/undo/delete-account/parse/recommend/shared (F49)
  "local-db:../db/run_local_db_tests.sh:1"           # local PostgreSQL authorization/transaction tests (fixture, not a migration replay); BLOCKED when no local PostgreSQL
  "live-services:check_live_services.sh:1"            # pinned real service/deployment evidence, never a fixture substitute
  "rails-audit:audit_rails.sh:1"
  "docs-current-state:check_docs_current_state.sh:1"
  "swift-packages:test_packages.sh:1"                # Packages/KuroModules swift test (host, no network)
  "architecture:check_architecture.sh:1"             # retired facade, flags injection, SDK imports, tracking-table/writer boundaries (rg)
  "branded-states:check_branded_states.sh:0"         # no stray ProgressView( in Kuro/ (prototype-fidelity Task 3); REPORTED (WARN) until Phase 3 flips it to :1
  "ios-build:build_ios.sh:1"
  "ios-test:test_ios_unit.sh:1"
)

# Optionally skip slow gates
SKIP_IOS="${SKIP_IOS_BUILD:-0}"
SKIP_RAILS="${SKIP_RAILS_AUDIT:-0}"
SKIP_IOS_TEST="${SKIP_IOS_TEST:-0}"
SKIP_LOCAL_DB="${SKIP_LOCAL_DB:-0}"

declare -a RESULTS=()
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
BLOCKED=0
WARNED=0

echo "========================================"
echo "  Kuro Quality Gates"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

for gate_def in "${GATES[@]}"; do
  IFS=':' read -r name script blocking <<< "$gate_def"

  # Skip conditions
  if [[ "$name" == "ios-build" && "$SKIP_IOS" == "1" ]]; then
    echo "--- [$name] SKIPPED (SKIP_IOS_BUILD=1) ---"
    echo ""
    RESULTS+=("$name:SKIP")
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  if [[ "$name" == "rails-audit" && "$SKIP_RAILS" == "1" ]]; then
    echo "--- [$name] SKIPPED (SKIP_RAILS_AUDIT=1) ---"
    echo ""
    RESULTS+=("$name:SKIP")
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  if [[ "$name" == "ios-test" && "$SKIP_IOS_TEST" == "1" ]]; then
    echo "--- [$name] SKIPPED (SKIP_IOS_TEST=1) ---"
    echo ""
    RESULTS+=("$name:SKIP")
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [[ "$name" == "local-db" ]]; then
    if [[ "$SKIP_LOCAL_DB" == "1" ]]; then
      echo "--- [$name] SKIPPED (SKIP_LOCAL_DB=1) ---"
      echo ""
      RESULTS+=("$name:SKIP")
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    if ! command -v initdb &>/dev/null && [[ ! -x /opt/homebrew/opt/postgresql@17/bin/initdb ]]; then
      echo "--- [$name] BLOCKED: no local PostgreSQL (initdb) available; the database transaction/authorization checks did NOT run ---"
      echo "    recovery: install PostgreSQL 17 (brew install postgresql@17) and rerun, or set SKIP_LOCAL_DB=1 to record it as skipped"
      echo ""
      RESULTS+=("$name:BLOCKED")
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
  fi

  TOTAL=$((TOTAL + 1))
  echo "--- [$name] Running $script ---"

  GATE_SCRIPT="$SCRIPT_DIR/$script"
  if [[ ! -f "$GATE_SCRIPT" ]]; then
    echo "  ERROR: $GATE_SCRIPT not found"
    RESULTS+=("$name:FAIL")
    FAILED=$((FAILED + 1))
    echo ""
    continue
  fi

  set +e
  bash "$GATE_SCRIPT"
  GATE_EXIT=$?
  set -e

  if [[ $GATE_EXIT -eq 0 ]]; then
    RESULTS+=("$name:PASS")
    PASSED=$((PASSED + 1))
  elif [[ ( "$name" == "local-db" || "$name" == "live-services" ) && $GATE_EXIT -eq 4 ]]; then
    # The DB harness exits 4 when every runnable test passed but some objects/stacks were unavailable
    # (BLOCKED items need a real Supabase stack or fixture objects): reported as BLOCKED, never PASS.
    echo "  $name: mandatory evidence remains BLOCKED (see this gate's output)"
    RESULTS+=("$name:BLOCKED")
    BLOCKED=$((BLOCKED + 1))
    TOTAL=$((TOTAL - 1))
  elif [[ "$blocking" == "0" ]]; then
    # Warning-only gate: its findings are reported above, recorded as WARN, never a hard failure.
    echo "  $name: reported findings (warning-only gate, exit $GATE_EXIT)"
    RESULTS+=("$name:WARN")
    WARNED=$((WARNED + 1))
  else
    RESULTS+=("$name:FAIL")
    FAILED=$((FAILED + 1))
  fi

  echo ""
done

# ── Summary table ─────────────────────────────────────────────────────────────
echo "========================================"
echo "  Summary"
echo "========================================"
printf "  %-20s %s\n" "Gate" "Result"
printf "  %-20s %s\n" "----" "------"
for result in "${RESULTS[@]}"; do
  IFS=':' read -r name status <<< "$result"
  printf "  %-20s %s\n" "$name" "$status"
done
echo ""
echo "  Total:   $TOTAL"
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo "  Blocked: $BLOCKED"
echo "  Warned:  $WARNED (warning-only gates with findings; not failures)"
echo "========================================"

if [[ $FAILED -gt 0 ]]; then
  echo ""
  echo "QUALITY GATES FAILED: $FAILED gate(s) did not pass."
  exit 1
fi

echo ""
if [[ $SKIPPED -gt 0 || $BLOCKED -gt 0 ]]; then
  echo "All EXECUTED quality gates passed; $SKIPPED skipped and $BLOCKED blocked gate(s) did NOT run (see the summary). Not a complete verification."
  if [[ "${KURO_ALLOW_PARTIAL_VERIFY:-0}" == "1" ]]; then
    echo "Developer partial mode: PARTIAL result, not release qualification."
    exit 0
  fi
  exit 4
fi
if [[ $WARNED -gt 0 ]]; then
  echo "All quality gates PASSED; $WARNED warning-only gate(s) reported findings (WARN in the summary)."
else
  echo "All quality gates PASSED."
fi
exit 0
