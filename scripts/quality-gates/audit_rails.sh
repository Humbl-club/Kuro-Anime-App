#!/usr/bin/env bash
# Quality gate: Curated rails audit
# Wraps node scripts/audit_curated_rails_quality.js
# Hard-fail on: adult content, overlap > 40%, rail size > 100 or < 5, score below floor, franchise duplicates
# Warning on: overlap > 15%, rail size near limits
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Rails Audit ==="
echo ""

# Check that node is available
if ! command -v node &>/dev/null; then
  echo "FAIL: node is not installed"
  exit 1
fi

# Check that the audit script exists
AUDIT_SCRIPT="$ROOT_DIR/scripts/audit_curated_rails_quality.js"
if [[ ! -f "$AUDIT_SCRIPT" ]]; then
  echo "FAIL: $AUDIT_SCRIPT not found"
  exit 1
fi

# Check that @supabase/supabase-js is available
if ! node -e "require('@supabase/supabase-js')" 2>/dev/null; then
  echo "FAIL: @supabase/supabase-js not installed. Run: npm install @supabase/supabase-js"
  exit 1
fi

# Run the audit in JSON mode for structured parsing.
# Some environments emit warnings before JSON; strip any non-JSON prefix.
RAW_OUTPUT=$(node "$AUDIT_SCRIPT" --json 2>&1) || true
JSON_OUTPUT=$(echo "$RAW_OUTPUT" | node -e "
  let buf = '';
  process.stdin.on('data', d => buf += d);
  process.stdin.on('end', () => {
    const start = buf.indexOf('{');
    if (start === -1) {
      process.stdout.write('');
      return;
    }
    process.stdout.write(buf.slice(start));
  });
")

# Parse the JSON output
VERDICT=$(echo "$JSON_OUTPUT" | node -e "
  const fs = require('fs');
  let buf = '';
  process.stdin.on('data', d => buf += d);
  process.stdin.on('end', () => {
    try {
      const r = JSON.parse(buf);
      console.log(r.verdict || 'UNKNOWN');
    } catch {
      console.log('PARSE_ERROR');
    }
  });
")

HARD_FAILURES=$(echo "$JSON_OUTPUT" | node -e "
  let buf = '';
  process.stdin.on('data', d => buf += d);
  process.stdin.on('end', () => {
    try {
      const r = JSON.parse(buf);
      console.log(r.hard_failures || 0);
    } catch {
      console.log(-1);
    }
  });
")

WARNINGS=$(echo "$JSON_OUTPUT" | node -e "
  let buf = '';
  process.stdin.on('data', d => buf += d);
  process.stdin.on('end', () => {
    try {
      const r = JSON.parse(buf);
      console.log(r.warnings_count || 0);
    } catch {
      console.log(-1);
    }
  });
")

if [[ -z "$JSON_OUTPUT" || "$VERDICT" == "PARSE_ERROR" ]]; then
  echo "FAIL: Could not parse audit output."
  echo "Raw output:"
  echo "$RAW_OUTPUT"
  exit 1
fi

# Also run in human-readable mode for the log
node "$AUDIT_SCRIPT" 2>&1 || true

echo ""
echo "--- Rails Audit Summary ---"
echo "Verdict:       $VERDICT"
echo "Hard failures: $HARD_FAILURES"
echo "Warnings:      $WARNINGS"

if [[ "$VERDICT" == "FAIL" ]]; then
  echo ""
  echo "HARD FAIL: Rails audit detected critical issues."
  exit 1
fi

if [[ "$WARNINGS" -gt 0 ]]; then
  echo ""
  echo "WARNING: $WARNINGS non-critical issues detected (see above)."
fi

echo ""
echo "Rails audit PASSED."
exit 0
