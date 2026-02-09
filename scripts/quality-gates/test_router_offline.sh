#!/usr/bin/env bash
# Quality gate: Offline router tests
# Runs router_test_cases.js which tests scoreMode/mapStrongGenreToModeId logic
# without hitting the network.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Router Offline Tests ==="
echo ""

if ! command -v node &>/dev/null; then
  echo "FAIL: node is not installed"
  exit 1
fi

TEST_FILE="$SCRIPT_DIR/router_test_cases.js"
if [[ ! -f "$TEST_FILE" ]]; then
  echo "FAIL: $TEST_FILE not found"
  exit 1
fi

node "$TEST_FILE"
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  echo ""
  echo "HARD FAIL: Router offline tests failed."
  exit 1
fi

echo "Router offline tests PASSED."
exit 0
