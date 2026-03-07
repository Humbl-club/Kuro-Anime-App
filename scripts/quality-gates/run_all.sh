#!/usr/bin/env bash
# Quality gate: Run all gates, print summary table, exit 1 if any hard-fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Gate definitions: name, script, is_blocking (1=hard-fail, 0=warning-only)
declare -a GATES=(
  "secrets:check_secrets.sh:1"
  "migrations:check_migrations.sh:1"
  "concierge-corpora:test_concierge_corpora.sh:1"
  "router-tests:test_router_offline.sh:1"
  "rails-audit:audit_rails.sh:1"
  "docs-current-state:check_docs_current_state.sh:1"
  "ios-build:build_ios.sh:1"
)

# Optionally skip slow gates
SKIP_IOS="${SKIP_IOS_BUILD:-0}"
SKIP_RAILS="${SKIP_RAILS_AUDIT:-0}"

declare -a RESULTS=()
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

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
echo "========================================"

if [[ $FAILED -gt 0 ]]; then
  echo ""
  echo "QUALITY GATES FAILED: $FAILED gate(s) did not pass."
  exit 1
fi

echo ""
echo "All quality gates PASSED."
exit 0
