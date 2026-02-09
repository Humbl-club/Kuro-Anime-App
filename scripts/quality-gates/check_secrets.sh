#!/usr/bin/env bash
# Quality gate: Secrets scanner
# Scans Swift and TypeScript files for hardcoded secrets.
# Patterns: eyJ (JWT), sbp_ (Supabase), sk- (API keys), gsk_ (Groq), service_role
# Whitelists test fixtures and known example strings.
# Compatible with bash 3.2 (macOS default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Secrets Check ==="
echo ""

FOUND=0

# Files to scan
SCAN_DIRS=(
  "$ROOT_DIR/Kuro"
  "$ROOT_DIR/supabase/functions"
  "$ROOT_DIR/scripts"
)

# Whitelist patterns (paths allowed to contain secret-like patterns)
WHITELIST_RE="(test-fixtures|test_fixtures|example|\.example|mock|node_modules|router_test_cases\.js|\.checksums)"

# Secret patterns (name:regex pairs as flat arrays for bash 3.2 compat)
# NOTE: We do NOT flag eyJ (JWT) generically because the Supabase anon key
# is a publishable JWT embedded in the iOS client (same as any web app's
# public anon key). Only flag service_role keys and true API secrets.
PATTERN_NAMES=("SUPABASE_SERVICE_ROLE" "SUPABASE_KEY" "OPENAI_SK" "GROQ_KEY" "SERVICE_ROLE_LITERAL")
PATTERN_REGEXES=(
  'service_role.*eyJhbGci[0-9A-Za-z._-]{20,}'
  'sbp_[0-9a-zA-Z]{20,}'
  'sk-[0-9a-zA-Z]{20,}'
  'gsk_[0-9a-zA-Z]{20,}'
  'service_role_key[[:space:]]*[:=][[:space:]]*["][^"]{10,}'
)

# Safe context patterns (env var references, not actual secrets)
SAFE_RE='(process\.env|Deno\.env|getenv|Info\.plist|Environment\.|SUPABASE_SERVICE_ROLE_KEY|// example|// test)'

for dir in "${SCAN_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    continue
  fi

  while IFS= read -r -d '' file; do
    # Skip whitelisted paths
    if echo "$file" | grep -qE "$WHITELIST_RE"; then
      continue
    fi

    i=0
    while [[ $i -lt ${#PATTERN_NAMES[@]} ]]; do
      pattern_name="${PATTERN_NAMES[$i]}"
      pattern="${PATTERN_REGEXES[$i]}"
      i=$((i + 1))

      MATCHES=$(grep -nE "$pattern" "$file" 2>/dev/null || true)
      if [[ -z "$MATCHES" ]]; then
        continue
      fi

      while IFS= read -r match_line; do
        LINE_CONTENT=$(echo "$match_line" | cut -d: -f2-)
        LINE_NUM=$(echo "$match_line" | cut -d: -f1)

        # Skip safe contexts (env var references, etc.)
        if echo "$LINE_CONTENT" | grep -qE "$SAFE_RE"; then
          continue
        fi

        # Skip short comment-only lines documenting patterns
        if echo "$LINE_CONTENT" | grep -qE '^\s*(//|/\*|\*)'; then
          TOKEN_LEN=$(echo "$LINE_CONTENT" | grep -oE "$pattern" | head -1 | wc -c | tr -d ' ')
          if [[ "$TOKEN_LEN" -lt 50 ]]; then
            continue
          fi
        fi

        REL_PATH="${file#$ROOT_DIR/}"
        echo "FAIL: [$pattern_name] $REL_PATH:$LINE_NUM"
        echo "  $LINE_CONTENT"
        FOUND=$((FOUND + 1))
      done <<< "$MATCHES"
    done
  done < <(find "$dir" \( -name "*.swift" -o -name "*.ts" -o -name "*.js" \) -not -path "*/node_modules/*" -not -path "*/.build/*" -print0 2>/dev/null)
done

echo ""
echo "--- Secrets Check Summary ---"
echo "Secrets found: $FOUND"

if [[ $FOUND -gt 0 ]]; then
  echo ""
  echo "HARD FAIL: $FOUND potential secret(s) detected in source files."
  echo "Either remove the hardcoded secrets or add the file to the whitelist."
  exit 1
fi

echo "Secrets check PASSED."
exit 0
