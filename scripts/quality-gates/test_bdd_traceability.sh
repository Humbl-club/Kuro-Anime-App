#!/usr/bin/env bash
# Blocking self-test gate for the BDD traceability checker.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "=== BDD traceability self-test ==="
python3 "$SCRIPT_DIR/test_check_bdd_traceability.py"
exit $?
