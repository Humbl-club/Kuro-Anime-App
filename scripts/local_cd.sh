#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEPLOY_SUPABASE="${DEPLOY_SUPABASE:-1}"
DEPLOY_TESTFLIGHT="${DEPLOY_TESTFLIGHT:-0}"
DEPLOY_FUNCTIONS="${DEPLOY_FUNCTIONS:-bulk-import-anime,bulk-import-manga,manga-chapter-enrich}"

usage() {
  cat <<'EOF'
Usage: scripts/local_cd.sh [options]

Options:
  --supabase-only        Deploy Supabase only.
  --testflight-only      Deploy TestFlight only.
  --functions <csv>      Comma-separated function slugs to deploy.
  --no-supabase          Skip Supabase deploy.
  --with-testflight      Enable TestFlight upload.
  -h, --help             Show this help.
EOF
}

log() {
  printf "\n[%s] %s\n" "local-cd" "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[local-cd] ERROR: missing required command '$1'" >&2
    exit 1
  fi
}

while (($#)); do
  case "$1" in
    --supabase-only)
      DEPLOY_SUPABASE=1
      DEPLOY_TESTFLIGHT=0
      ;;
    --testflight-only)
      DEPLOY_SUPABASE=0
      DEPLOY_TESTFLIGHT=1
      ;;
    --functions)
      DEPLOY_FUNCTIONS="${2:-}"
      shift
      ;;
    --no-supabase)
      DEPLOY_SUPABASE=0
      ;;
    --with-testflight)
      DEPLOY_TESTFLIGHT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[local-cd] ERROR: unknown option '$1'" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$DEPLOY_SUPABASE" == "1" ]]; then
  require_cmd supabase
  log "Push pending migrations"
  supabase db push --linked --workdir "$ROOT_DIR" --yes

  project_ref=""
  if [[ -f "$ROOT_DIR/supabase/.temp/project-ref" ]]; then
    project_ref="$(tr -d '\n' < "$ROOT_DIR/supabase/.temp/project-ref")"
  fi

  IFS=',' read -r -a functions <<<"$DEPLOY_FUNCTIONS"
  for fn in "${functions[@]}"; do
    fn="$(echo "$fn" | xargs)"
    [[ -z "$fn" ]] && continue
    log "Deploy function: $fn"
    if [[ -n "$project_ref" ]]; then
      supabase functions deploy "$fn" --workdir "$ROOT_DIR" --project-ref "$project_ref" --use-api
    else
      supabase functions deploy "$fn" --workdir "$ROOT_DIR" --use-api
    fi
  done
fi

if [[ "$DEPLOY_TESTFLIGHT" == "1" ]]; then
  require_cmd fastlane
  log "Upload iOS build to TestFlight"
  fastlane ios beta
fi

log "CD finished successfully"
