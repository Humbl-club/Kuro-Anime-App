#!/usr/bin/env bash
# Quality gate: Gherkin scenario -> test traceability (tracker gaps). Same command as the Python checker;
# `--accepted <WS>` and `--record-template <WS>` pass through.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "=== BDD traceability ==="
python3 "$SCRIPT_DIR/check_bdd_traceability.py" "$@"
exit $?
