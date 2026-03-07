#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Current-State Docs Check ==="
echo ""

python3 "$SCRIPT_DIR/check_docs_current_state.py"

echo ""
echo "Current-state docs PASSED."
