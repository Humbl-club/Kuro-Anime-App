#!/usr/bin/env bash
# Quality gate: Concierge bilingual corpora integrity checks
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CORPUS_DIR="$ROOT_DIR/tests/concierge-corpora"

echo "=== Concierge Corpora Integrity ==="
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

if errors:
    print("FAIL:")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print("PASS: corpora files are present and structurally valid.")
PY

echo ""
echo "Concierge corpora integrity PASSED."
exit 0
