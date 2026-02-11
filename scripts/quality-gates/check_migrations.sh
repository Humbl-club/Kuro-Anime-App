#!/usr/bin/env bash
# Quality gate: Migration hygiene
# - Verify no untracked SQL files in supabase/migrations/ (compare against git)
# - Generate/verify checksums file supabase/migrations/.checksums
# - Warn if applied migrations have been modified
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"
CHECKSUMS_FILE="$MIGRATIONS_DIR/.checksums"

echo "=== Migration Hygiene Check ==="
echo ""

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "FAIL: $MIGRATIONS_DIR does not exist"
  exit 1
fi

EXIT_CODE=0
WARNINGS=0
ALLOW_UNTRACKED="${MIGRATIONS_ALLOW_UNTRACKED:-0}"

# ── 1) Check for untracked SQL files ─────────────────────────────────────────
echo "Checking for untracked migration files..."
cd "$ROOT_DIR"

UNTRACKED=$(git ls-files --others --exclude-standard -- "supabase/migrations/*.sql" 2>/dev/null || true)
if [[ -n "$UNTRACKED" ]]; then
  if [[ "$ALLOW_UNTRACKED" == "1" ]]; then
    echo "WARNING: Untracked SQL files in supabase/migrations/:"
    echo "$UNTRACKED" | while read -r f; do echo "  - $f"; done
    echo "  MIGRATIONS_ALLOW_UNTRACKED=1 set, continuing."
    WARNINGS=$((WARNINGS + 1))
  else
    echo "FAIL: Untracked SQL files in supabase/migrations/:"
    echo "$UNTRACKED" | while read -r f; do echo "  - $f"; done
    echo "  Commit migration files (or set MIGRATIONS_ALLOW_UNTRACKED=1 for local dev)."
    EXIT_CODE=1
  fi
fi

# ── 2) Check for modified (staged or unstaged) migration files ────────────────
echo "Checking for modified migration files..."
MODIFIED=$(git diff --name-only -- "supabase/migrations/*.sql" 2>/dev/null || true)
STAGED=$(git diff --cached --name-only -- "supabase/migrations/*.sql" 2>/dev/null || true)

ALL_MODIFIED=$(echo -e "$MODIFIED\n$STAGED" | sort -u | grep -v '^$' || true)
if [[ -n "$ALL_MODIFIED" ]]; then
  echo "WARNING: Modified migration files (may have been applied already):"
  echo "$ALL_MODIFIED" | while read -r f; do echo "  - $f"; done
  WARNINGS=$((WARNINGS + 1))
fi

# ── 3) Generate/verify checksums ─────────────────────────────────────────────
echo "Verifying migration checksums..."

# Generate current checksums
CURRENT_CHECKSUMS=$(find "$MIGRATIONS_DIR" -name "*.sql" -type f | sort | while read -r f; do
  shasum -a 256 "$f" | awk '{print $1 "  " FILENAME}' FILENAME="$(basename "$f")"
done)

if [[ -f "$CHECKSUMS_FILE" ]]; then
  # Compare against stored checksums
  STORED=$(cat "$CHECKSUMS_FILE")
  CHANGED=0

  while IFS= read -r line; do
    HASH=$(echo "$line" | awk '{print $1}')
    FILE=$(echo "$line" | awk '{print $2}')
    # Find this file in current checksums
    CURRENT_HASH=$(echo "$CURRENT_CHECKSUMS" | grep "  ${FILE}$" | awk '{print $1}' || true)
    if [[ -n "$CURRENT_HASH" && "$CURRENT_HASH" != "$HASH" ]]; then
      echo "WARNING: Checksum changed for $FILE (was applied with different content)"
      CHANGED=$((CHANGED + 1))
    fi
  done <<< "$STORED"

  # Check for new files not in the checksums
  while IFS= read -r line; do
    FILE=$(echo "$line" | awk '{print $2}')
    if ! grep -q "  ${FILE}$" "$CHECKSUMS_FILE" 2>/dev/null; then
      echo "  New migration (not in checksums): $FILE"
    fi
  done <<< "$CURRENT_CHECKSUMS"

  if [[ $CHANGED -gt 0 ]]; then
    echo "WARNING: $CHANGED migration(s) modified since last checksum."
    WARNINGS=$((WARNINGS + 1))
  fi
else
  echo "  No .checksums file found."
  echo "  Run with --update to generate: $0 --update"
fi

# Only write checksums when --update flag is passed (never mutate working tree by default)
if [[ "${1:-}" == "--update" ]]; then
  echo "$CURRENT_CHECKSUMS" > "$CHECKSUMS_FILE"
  echo "  Checksums written to $CHECKSUMS_FILE"
fi

# ── 4) Count migrations ──────────────────────────────────────────────────────
MIGRATION_COUNT=$(find "$MIGRATIONS_DIR" -name "*.sql" -type f | wc -l | tr -d ' ')
echo ""
echo "Total migration files: $MIGRATION_COUNT"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "--- Migration Hygiene Summary ---"
echo "Warnings: $WARNINGS"

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "HARD FAIL: Migration hygiene check failed."
  exit 1
fi

if [[ $WARNINGS -gt 0 ]]; then
  echo "Completed with $WARNINGS warning(s)."
else
  echo "Migration hygiene PASSED."
fi

exit 0
