#!/usr/bin/env bash
# Quality gate "load-profiles": runs every offline load-harness test (scripts/load/*.test.js) and
# every per-profile test (scripts/load/profiles/*.test.js, when the folder has any).
# Offline: no network, no Supabase, no credentials, no accounts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Load profiles (offline node tests) ==="
echo ""

if ! command -v node &>/dev/null; then
  echo "SKIP: node is not installed"
  exit 0
fi

cd "$ROOT_DIR" || exit 1
shopt -s nullglob
FILES=(scripts/load/*.test.js scripts/load/profiles/*.test.js)
shopt -u nullglob

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "FAIL: no load tests found"
  exit 1
fi

node --test "${FILES[@]}"
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  echo ""
  echo "HARD FAIL: offline load-harness tests failed."
  exit 1
fi

echo "Load profiles gate PASSED (${#FILES[@]} test files)."
exit 0
