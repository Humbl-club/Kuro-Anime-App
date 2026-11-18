#!/usr/bin/env bash
# Quality gate: Gherkin scenario -> test traceability (tracker gaps). Same command as the Python checker;
# `--accepted <WS>` and `--record-template <WS>` pass through.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$#" -eq 0 ]; then echo "=== BDD traceability ==="; fi  # no banner for --record-template: its stdout is JSON
python3 "$SCRIPT_DIR/check_bdd_traceability.py" "$@"
exit $?
