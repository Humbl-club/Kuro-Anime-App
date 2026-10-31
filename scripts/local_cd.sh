#!/usr/bin/env bash
set -euo pipefail

# DEPLOY_SUPABASE defaults to 0. A plain run does not db push or functions deploy.
# Set DEPLOY_SUPABASE=1, or pass --supabase-only, to deploy.
kuro_local_cd_apply_defaults() {
  DEPLOY_SUPABASE="${DEPLOY_SUPABASE:-0}"
  DEPLOY_TESTFLIGHT="${DEPLOY_TESTFLIGHT:-0}"
  DEPLOY_FUNCTIONS="${DEPLOY_FUNCTIONS:-bulk-import-anime,bulk-import-manga,manga-chapter-enrich}"
}

if [[ "${KURO_LOCAL_CD_SOURCE_DEFAULTS_ONLY:-}" == "1" ]]; then
  kuro_local_cd_apply_defaults
  return 0 2>/dev/null || exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kuro_project_root.sh
source "$SCRIPT_DIR/kuro_project_root.sh"
ROOT_DIR="$(kuro_resolve_project_root)"
cd "$ROOT_DIR"

kuro_local_cd_apply_defaults

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
      if (($# < 2)) || [[ "$2" == --* ]]; then
        echo "[local-cd] ERROR: --functions requires a value" >&2
        usage
        exit 1
      fi
      DEPLOY_FUNCTIONS="$2"
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

  functions=()
  if [[ -n "${DEPLOY_FUNCTIONS//[[:space:]]/}" ]]; then
    IFS=',' read -r -a functions <<<"$DEPLOY_FUNCTIONS"
  fi

  if ((${#functions[@]} == 0)); then
    log "Skip function deploy (no functions configured)"
  else
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
fi

if [[ "$DEPLOY_TESTFLIGHT" == "1" ]]; then
  require_cmd fastlane
  log "Upload iOS build to TestFlight"
  fastlane ios beta
fi

log "CD finished successfully"
