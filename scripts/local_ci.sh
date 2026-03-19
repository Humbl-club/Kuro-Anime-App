#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_SUPABASE_LINT="${RUN_SUPABASE_LINT:-1}"
RUN_IOS_BUILD="${RUN_IOS_BUILD:-1}"

log() {
  printf "\n[%s] %s\n" "local-ci" "$1"
}

warn() {
  printf "[local-ci] WARN: %s\n" "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[local-ci] ERROR: missing required command '$1'" >&2
    exit 1
  fi
}

require_cmd node

log "Install Node dependencies"
if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund
else
  npm install --no-audit --no-fund
fi

log "Syntax-check JavaScript tooling"
while IFS= read -r -d '' file; do
  node --check "$file"
done < <(find "$ROOT_DIR/scripts" -maxdepth 1 -type f -name "*.js" -print0 | sort -z)

manual_scripts=(
  "scripts/manual/test_bulk_import_anime.js"
  "scripts/manual/test_bulk_import_manga.js"
  "scripts/manual/test_bulk_import_manga_with_chapters.js"
  "scripts/manual/verify_supabase_connection.js"
)

for file in "${manual_scripts[@]}"; do
  if [[ -f "$ROOT_DIR/$file" ]]; then
    node --check "$ROOT_DIR/$file"
  fi
done

if [[ "$RUN_SUPABASE_LINT" == "1" ]]; then
  if command -v supabase >/dev/null 2>&1; then
    log "Run Supabase schema lint"
    supabase db lint --linked --workdir "$ROOT_DIR"
  else
    warn "Supabase CLI not found; skipping db lint"
  fi
else
  log "Skip Supabase lint (RUN_SUPABASE_LINT=$RUN_SUPABASE_LINT)"
fi

if [[ "$RUN_IOS_BUILD" == "1" ]]; then
  if [[ -x "$ROOT_DIR/scripts/quality-gates/run_all.sh" ]]; then
    log "Run quality gates (includes iOS build + tests)"
    "$ROOT_DIR/scripts/quality-gates/run_all.sh"
  elif command -v xcodebuild >/dev/null 2>&1; then
    log "Build iOS app (quality gates script not found, falling back)"
    xcodebuild -scheme Kuro -destination "generic/platform=iOS" build
  else
    warn "xcodebuild not found; skipping iOS build"
  fi
else
  log "Skip iOS build (RUN_IOS_BUILD=$RUN_IOS_BUILD)"
fi

log "CI finished successfully"
