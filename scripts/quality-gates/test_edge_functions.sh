#!/usr/bin/env bash
# Quality gate "edge-functions-exec": runs every offline Deno test suite under supabase/functions
# Set KURO_EDGE_TEST_DIRS to a validated comma-separated set for affected checks.
# Unset keeps the broad diagnostic; empty/invalid/zero-test selection fails.
# Production handlers/rules use controlled fakes; no Supabase or Groq calls.
#
# F49: the business-critical handler suites (concierge-apply, concierge-undo, delete-account,
# concierge-parse, concierge-recommend, the shared limiter/alias modules) are part of the standard
# gate path, so a regression there fails `run_all.sh`.
#
# Hard failures: deno missing; any suite failing; a directory that contains *_test.ts files but ran
# zero tests (exit 0 with zero tests is NOT evidence); a total of zero tests.
# What it does NOT verify: PostgreSQL transaction behavior (scripts/db/run_local_db_tests.sh, a
# separately labeled local-database gate), live Supabase/Auth/Storage/Realtime, or deployed parity.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNCTIONS_DIR="$ROOT_DIR/supabase/functions"

echo "=== Edge function suites (production handlers/rules, offline) ==="
echo ""

if ! command -v deno &>/dev/null; then
  echo "FAIL: deno is not installed (required to execute the production edge-function modules)"
  exit 1
fi

cd "$FUNCTIONS_DIR"
total=0
failed_dirs=0
empty_dirs=0
suite_count=0
selector="${KURO_EDGE_TEST_DIRS-}"
if [[ "${KURO_EDGE_TEST_DIRS+x}" == "x" ]]; then
  if [[ ! "$selector" =~ ^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$ ]]; then echo "FAIL: empty/invalid edge directory selection"; exit 1; fi
  IFS=',' read -r -a selected_dirs <<< "$selector"
  for selected in "${selected_dirs[@]}"; do
    if [[ ! "$selected" =~ ^[A-Za-z0-9_-]+$ || ! -d "$selected" ]]; then
      echo "FAIL: invalid edge directory selection: $selected"; exit 1
    fi
    if [[ ! -f "$selected/index.ts" ]] && ! find "$selected" -name '*_test.ts' -print -quit | grep -q .; then
      echo "FAIL: selected directory has no entrypoint or tests: $selected"; exit 1
    fi
  done
else
  selected_dirs=()
  while IFS= read -r dir; do selected_dirs+=("$dir"); done < <(find . -name '*_test.ts' -not -path '*/node_modules/*' -print | sed -E 's#^\./##; s#/[^/]+$##' | sort -u)
fi

# One deno invocation per directory that has test files, so a silent zero is attributable.
for dir in "${selected_dirs[@]}"; do
  if [[ -f "$dir/index.ts" ]]; then
    if ! deno check "$dir/index.ts"; then
      echo "FAIL: $dir entrypoint typecheck"; failed_dirs=$((failed_dirs + 1))
    fi
  fi
  if ! find "$dir" -name '*_test.ts' -print -quit | grep -q .; then
    echo "TYPECHECK ONLY: $dir has no test suite; no behavioral proof claimed"
    continue
  fi
  suite_count=$((suite_count + 1))
  echo "--- deno test $dir"
  out="$(NO_COLOR=1 deno test --no-prompt "$dir" 2>&1)"
  code=$?
  printf '%s\n' "$out" | tail -4
  summary="$(printf '%s\n' "$out" | grep -E '^(ok|FAILED) \| [0-9]+ passed' | tail -1)"
  passed="$(printf '%s\n' "$summary" | sed -E 's/^[A-Z a-z]+ \| ([0-9]+) passed.*/\1/')"
  failed="$(printf '%s\n' "$summary" | sed -E 's/.*\| ([0-9]+) failed.*/\1/')"
  [[ "$passed" =~ ^[0-9]+$ ]] || passed=0
  [[ "$failed" =~ ^[0-9]+$ ]] || failed=0
  if [[ $code -ne 0 || $failed -ne 0 ]]; then
    echo "FAIL: $dir (exit $code, $failed failed)"
    failed_dirs=$((failed_dirs + 1))
  elif [[ $passed -eq 0 ]]; then
    echo "FAIL: $dir contains test files but executed ZERO tests"
    empty_dirs=$((empty_dirs + 1))
  fi
  total=$((total + passed))
done

echo ""
echo "suites: $suite_count, tests passed: $total, failing suites: $failed_dirs, empty suites: $empty_dirs"

if [[ $suite_count -eq 0 || $total -eq 0 ]]; then
  echo "HARD FAIL: no edge-function tests were executed."
  exit 1
fi
if [[ $failed_dirs -ne 0 || $empty_dirs -ne 0 ]]; then
  echo "HARD FAIL: edge-function suites failed or ran zero tests."
  exit 1
fi
echo "Edge function suites PASSED."
