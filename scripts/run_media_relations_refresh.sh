#!/usr/bin/env bash
set -euo pipefail

ROOT="/Applications/Kuro"
REPORT_DIR="${MEDIA_RELATIONS_REPORTS_DIR:-$ROOT/reports/media-relations}"
mkdir -p "$REPORT_DIR"

read_existing_env() {
  local key="$1"
  local plists=(
    "$HOME/Library/LaunchAgents/com.kuro.catalog-safety.plist"
    "$HOME/Library/LaunchAgents/com.kuro.synopsis-enrichment.plist"
    "$HOME/Library/LaunchAgents/com.kuro.provider-availability.plist"
  )
  local plist
  for plist in "${plists[@]}"; do
    if [[ -f "$plist" ]]; then
      local value
      value="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$key" "$plist" 2>/dev/null || true)"
      if [[ -n "$value" ]]; then
        printf '%s' "$value"
        return 0
      fi
    fi
  done
  return 1
}

export SUPABASE_URL="${SUPABASE_URL:-$(read_existing_env SUPABASE_URL || true)}"
export SUPABASE_SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-$(read_existing_env SUPABASE_SERVICE_ROLE_KEY || true)}"
export MEDIA_RELATIONS_REPORTS_DIR="$REPORT_DIR"
export MEDIA_RELATIONS_MODE="${MEDIA_RELATIONS_MODE:-queue}"
export MEDIA_RELATIONS_TOP_COUNT="${MEDIA_RELATIONS_TOP_COUNT:-500}"
export MEDIA_RELATIONS_QUEUE_LIMIT="${MEDIA_RELATIONS_QUEUE_LIMIT:-40}"
export MEDIA_RELATIONS_REPORT_SAMPLE_SIZE="${MEDIA_RELATIONS_REPORT_SAMPLE_SIZE:-500}"
export MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT="${MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT:-30}"
export ANILIST_BATCH_SIZE="${ANILIST_BATCH_SIZE:-10}"
export ANILIST_REQUEST_DELAY_MS="${ANILIST_REQUEST_DELAY_MS:-350}"
export ANILIST_TIMEOUT_MS="${ANILIST_TIMEOUT_MS:-20000}"

if [[ -z "${SUPABASE_SERVICE_ROLE_KEY}" ]]; then
  echo "Missing SUPABASE_SERVICE_ROLE_KEY. Export it or install another Kuro launchd pipeline first." >&2
  exit 1
fi

LOG_FILE="$REPORT_DIR/worker.log"
LOCK_DIR="$REPORT_DIR/.worker.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_STARTED_FILE="$LOCK_DIR/started_at_unix"
LOCK_TTL_SECONDS="${MEDIA_RELATIONS_LOCK_TTL_SECONDS:-21600}"
WORKER="$ROOT/scripts/media_relations_worker.js"

log_line() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >>"$LOG_FILE" 2>&1
}

write_lock_metadata() {
  printf '%s' "$$" >"$LOCK_PID_FILE"
  date +%s >"$LOCK_STARTED_FILE"
}

try_acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    write_lock_metadata
    return 0
  fi

  local lock_pid=""
  if [[ -f "$LOCK_PID_FILE" ]]; then
    lock_pid="$(tr -dc '0-9' <"$LOCK_PID_FILE" | head -c 20 || true)"
  fi
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    log_line "worker already running (pid=$lock_pid), skipping overlap"
    return 1
  fi

  local lock_started=0
  if [[ -f "$LOCK_STARTED_FILE" ]]; then
    lock_started="$(tr -dc '0-9' <"$LOCK_STARTED_FILE" | head -c 20 || true)"
  fi
  if [[ -z "$lock_started" ]]; then
    lock_started="$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)"
  fi

  local now_epoch
  now_epoch="$(date +%s)"
  local lock_age=$(( now_epoch - lock_started ))
  if (( lock_age < LOCK_TTL_SECONDS )); then
    log_line "lock exists without active pid but age=${lock_age}s (< ttl=${LOCK_TTL_SECONDS}s); keeping lock"
    return 1
  fi

  log_line "stale lock detected (age=${lock_age}s), removing and retrying lock acquire"
  rm -rf "$LOCK_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    write_lock_metadata
    return 0
  fi

  log_line "lock acquire retry failed after stale lock cleanup, skipping overlap"
  return 1
}

if ! try_acquire_lock; then
  exit 0
fi
trap 'rm -f "$LOCK_PID_FILE" "$LOCK_STARTED_FILE"; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

{
  log_line "starting media relations worker (mode=${MEDIA_RELATIONS_MODE})"
  node "$WORKER"
  log_line "media relations worker completed"
} >>"$LOG_FILE" 2>&1
