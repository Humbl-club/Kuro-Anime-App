#!/usr/bin/env bash
# Quality gate "router-rules-exec": executes the PRODUCTION concierge-recommend routing chain
# (supabase/functions/concierge-recommend/router.ts, the module index.ts deploys) against the
# 75 offline cases in router_test_cases.js, the 22 production-only German alternatives, and the
# defaultModes() fallback characterisation. Offline: no network, no Supabase, no Groq.
#
# What it does NOT verify: the live search_titles outcome (faked: only real catalog titles are
# confident) and the live concierge_config (a migration-chain replay fixture stands in).
# Requires deno (replaces the former node-run copy of the router logic).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_FILE="$ROOT_DIR/supabase/functions/concierge-recommend/router_test.ts"

echo "=== Router rules execution (production router.ts, offline cases) ==="
echo ""

if ! command -v deno &>/dev/null; then
  echo "FAIL: deno is not installed (required to execute the production router module)"
  exit 1
fi

if [[ ! -f "$TEST_FILE" ]]; then
  echo "FAIL: $TEST_FILE not found"
  exit 1
fi

cd "$ROOT_DIR"
set +e
deno test --no-prompt "$TEST_FILE"
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 ]]; then
  echo ""
  echo "HARD FAIL: production router rules disagree with the offline cases."
  exit 1
fi

echo "Router rules execution PASSED (production router.ts)."
exit 0
