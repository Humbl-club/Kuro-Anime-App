#!/usr/bin/env bash
# Daily AnimeThemes theme pass (series_enrichment_worker.py --themes) for launchd
# (com.kuro.series-enrichment, see install_series_enrichment_launchd.sh).
# Sweeps the anime catalogue by id: SERIES_THEMES_PASSES passes of <=500 titles each
# (25 AniList ids per AnimeThemes request, <=90 requests/min, paced by the worker).
# The id cursor lives in $REPORT_DIR/themes-cursor and wraps to 0 when a pass finds no titles.
# Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment (plist only, never the repo).
# Never prints credentials: the worker emits summary JSON only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kuro_project_root.sh
source "$SCRIPT_DIR/kuro_project_root.sh"
ROOT="$(kuro_resolve_project_root)"
REPORT_DIR="${SERIES_ENRICHMENT_REPORTS_DIR:-$ROOT/reports/series-enrichment}"
mkdir -p "$REPORT_DIR"

PASSES="${SERIES_THEMES_PASSES:-4}"
LIMIT="${SERIES_THEMES_LIMIT:-500}"
PYTHON="${KURO_PYTHON:-/usr/bin/python3}"
LOG_FILE="$REPORT_DIR/worker.log"
CURSOR_FILE="$REPORT_DIR/themes-cursor"
STATUS_FILE="$REPORT_DIR/latest-status.json"
LOCK_DIR="$REPORT_DIR/.worker.lock"

log_line() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >>"$LOG_FILE" 2>&1
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  lock_pid=""
  if [[ -f "$LOCK_DIR/pid" ]]; then
    lock_pid="$(tr -dc '0-9' <"$LOCK_DIR/pid" | head -c 20 || true)"
  fi
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    log_line "worker already running (pid=$lock_pid), skipping overlap"
    exit 0
  fi
  log_line "stale lock removed"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
fi
printf '%s' "$$" >"$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  log_line "missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY; nothing done"
  exit 1
fi

cursor=""
if [[ -f "$CURSOR_FILE" ]]; then
  cursor="$(tr -dc '0-9' <"$CURSOR_FILE" | head -c 20 || true)"
fi
cursor="${cursor:-0}"
log_line "starting theme pass: passes=$PASSES limit=$LIMIT after_id=$cursor"

status="success"
for ((pass = 1; pass <= PASSES; pass++)); do
  if ! summary="$("$PYTHON" "$ROOT/scripts/series_enrichment_worker.py" --apply --allow-hosted --themes \
      --limit "$LIMIT" --after-id "$cursor" 2>>"$LOG_FILE")"; then
    status="error"
    log_line "pass $pass failed (after_id=$cursor); cursor kept for the next run"
    break
  fi
  log_line "pass $pass after_id=$cursor: $summary"
  next="$(printf '%s' "$summary" | "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin).get("next_after_id") or "")')"
  if [[ -z "$next" ]]; then
    cursor=0
    log_line "catalogue sweep complete; cursor wrapped to 0"
    break
  fi
  cursor="$next"
done

printf '%s' "$cursor" >"$CURSOR_FILE"
printf '{"finished_at":"%s","status":"%s","next_after_id":%s}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" "$cursor" >"$STATUS_FILE"
log_line "theme pass finished: status=$status next_after_id=$cursor"
[[ "$status" == "success" ]]
