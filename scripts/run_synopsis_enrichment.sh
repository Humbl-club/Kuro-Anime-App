#!/usr/bin/env bash
set -euo pipefail

ROOT="/Applications/Kuro"
REPORT_DIR="${SYNOPSIS_REPORTS_DIR:-$ROOT/reports/synopsis-enrichment}"
mkdir -p "$REPORT_DIR"

export SYNOPSIS_REPORTS_DIR="$REPORT_DIR"
export SYNOPSIS_BATCH_SIZE="${SYNOPSIS_BATCH_SIZE:-25}"
export SYNOPSIS_MEDIA_TYPES="${SYNOPSIS_MEDIA_TYPES:-ANIME,MANGA}"
export SYNOPSIS_MIN_CHARS="${SYNOPSIS_MIN_CHARS:-140}"
export SYNOPSIS_MAX_CHARS="${SYNOPSIS_MAX_CHARS:-420}"
export SYNOPSIS_MIN_SENTENCES="${SYNOPSIS_MIN_SENTENCES:-3}"
export SYNOPSIS_MAX_SENTENCES="${SYNOPSIS_MAX_SENTENCES:-4}"
export SYNOPSIS_MIN_SOURCE_CHARS="${SYNOPSIS_MIN_SOURCE_CHARS:-110}"

LOG_FILE="$REPORT_DIR/worker.log"
WORKER_BIN="$REPORT_DIR/synopsis_enrichment_worker"
LOCK_DIR="$REPORT_DIR/.worker.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_STARTED_FILE="$LOCK_DIR/started_at_unix"
LOCK_TTL_SECONDS="${SYNOPSIS_LOCK_TTL_SECONDS:-1800}"

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
  log_line "starting synopsis enrichment worker"
  if [[ ! -x "$WORKER_BIN" || "$ROOT/scripts/synopsis_enrichment_worker.swift" -nt "$WORKER_BIN" ]]; then
    /usr/bin/xcrun swiftc -parse-as-library "$ROOT/scripts/synopsis_enrichment_worker.swift" -o "$WORKER_BIN"
  fi
  "$WORKER_BIN"
  log_line "synopsis enrichment worker completed"
} >>"$LOG_FILE" 2>&1
