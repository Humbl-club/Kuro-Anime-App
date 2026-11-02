#!/usr/bin/env bash
# Quality gate "corpora-shape+exec": two separate checks over tests/concierge-corpora/*.json.
#   1. [corpora-shape]     structural validation only (files, JSON, required fields, minimum counts).
#   2. [corpora-execution] runs the cases through PRODUCTION rules with deno:
#        - parser_{en,de}.json (107) through concierge-parse rules.ts (splitItems + parseLine);
#        - router_{en,de}.json (67) through concierge-recommend router.ts (routePrimaryMode).
#      Each case is asserted against its INTENDED outcome. A parser case whose authored expectation was
#      adjudicated (F29) carries an `adjudication` block in the canonical fixture (decision
#      corrected-expectation | accepted-production, intended_slots / intended_ambiguity, rationale);
#      the authored expected_* stays untouched beside it. A genuine defect (intended outcome known,
#      production differs) is pinned in the test's KNOWN_DEFECTS / KNOWN_DIVERGENCES and printed, never
#      skipped or re-expected. expected_intent / expected_confidence_min are client-side (Swift), not asserted.
# Offline: no network, no Supabase, no Groq. Requires python3 (shape) and deno (execution).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CORPUS_DIR="$ROOT_DIR/tests/concierge-corpora"

echo "=== Concierge corpora: [corpora-shape] structural validation ==="
echo ""

if [[ ! -d "$CORPUS_DIR" ]]; then
  echo "FAIL: corpus directory not found: $CORPUS_DIR"
  exit 1
fi

python3 - "$CORPUS_DIR" <<'PY'
import json
import os
import sys

base = sys.argv[1]
required = {
    "parser_de.json": {"min": 40, "fields": ["id", "input", "expected_intent", "expected_slots"]},
    "parser_en.json": {"min": 40, "fields": ["id", "input", "expected_intent", "expected_slots"]},
    "router_de.json": {"min": 25, "fields": ["id", "input", "expected_mode"]},
    "router_en.json": {"min": 25, "fields": ["id", "input", "expected_mode"]},
}

errors = []
total = 0
adjudicated = 0

for filename, rule in required.items():
    path = os.path.join(base, filename)
    if not os.path.exists(path):
        errors.append(f"missing file: {filename}")
        continue

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        errors.append(f"invalid json in {filename}: {exc}")
        continue

    if not isinstance(data, list):
        errors.append(f"{filename}: root must be an array")
        continue

    total += len(data)
    if len(data) < rule["min"]:
        errors.append(f"{filename}: expected >= {rule['min']} cases, got {len(data)}")

    for i, row in enumerate(data, start=1):
        if not isinstance(row, dict):
            errors.append(f"{filename}#{i}: case must be an object")
            continue
        for field in rule["fields"]:
            if field not in row:
                errors.append(f"{filename}#{i}: missing field '{field}'")
            elif field in {"id", "input", "expected_intent", "expected_mode"} and not isinstance(row[field], str):
                errors.append(f"{filename}#{i}: field '{field}' must be a string")
        if "expected_slots" in row and not isinstance(row["expected_slots"], dict):
            errors.append(f"{filename}#{i}: 'expected_slots' must be an object")
        if "adjudication" in row:
            adj = row["adjudication"]
            if not isinstance(adj, dict):
                errors.append(f"{filename}#{i}: 'adjudication' must be an object")
            else:
                if adj.get("decision") not in {"corrected-expectation", "accepted-production"}:
                    errors.append(f"{filename}#{i}: adjudication.decision must be corrected-expectation or accepted-production")
                if not isinstance(adj.get("rationale"), str) or not adj["rationale"].strip():
                    errors.append(f"{filename}#{i}: adjudication.rationale must be a non-empty string")
                if "intended_slots" not in adj and "intended_ambiguity" not in adj:
                    errors.append(f"{filename}#{i}: adjudication needs intended_slots and/or intended_ambiguity")
                if "intended_slots" in adj and not isinstance(adj["intended_slots"], dict):
                    errors.append(f"{filename}#{i}: adjudication.intended_slots must be an object")
                adjudicated += 1

if errors:
    print("FAIL:")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print(f"PASS [corpora-shape]: 4 corpus files present and structurally valid ({total} cases, {adjudicated} with a well-formed adjudication). Shape only: nothing executed yet.")
PY

echo ""
echo "=== Concierge corpora: [corpora-execution] production parser + router rules ==="
echo ""

if ! command -v deno &>/dev/null; then
  echo "FAIL [corpora-execution]: deno is not installed (required to execute the production rule modules)"
  exit 1
fi

cd "$ROOT_DIR"
set +e
deno test --no-prompt \
  "$ROOT_DIR/supabase/functions/concierge-parse/rules_corpus_test.ts" \
  "$ROOT_DIR/supabase/functions/concierge-recommend/router_corpus_test.ts"
EXEC_EXIT=$?
set -e

if [[ $EXEC_EXIT -ne 0 ]]; then
  echo ""
  echo "HARD FAIL [corpora-execution]: production rules disagree with the intended outcome beyond the pinned known defects."
  exit 1
fi

echo ""
echo "Concierge corpora PASSED: [corpora-shape] + [corpora-execution] (production rules)."
exit 0
