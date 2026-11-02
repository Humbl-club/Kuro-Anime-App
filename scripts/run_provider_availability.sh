#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kuro_project_root.sh
source "$SCRIPT_DIR/kuro_project_root.sh"
ROOT="$(kuro_resolve_project_root)"
REPORT_DIR="${PROVIDER_AVAILABILITY_REPORTS_DIR:-$ROOT/reports/provider-availability}"
mkdir -p "$REPORT_DIR"

export PROVIDER_AVAILABILITY_REPORTS_DIR="$REPORT_DIR"
export PROVIDER_AVAILABILITY_BATCH_SIZE="${PROVIDER_AVAILABILITY_BATCH_SIZE:-100}"
export PROVIDER_AVAILABILITY_STALE_DAYS="${PROVIDER_AVAILABILITY_STALE_DAYS:-30}"
export PROVIDER_AVAILABILITY_GRACE_DAYS="${PROVIDER_AVAILABILITY_GRACE_DAYS:-90}"
export PROVIDER_AVAILABILITY_TIME_BUDGET_MS="${PROVIDER_AVAILABILITY_TIME_BUDGET_MS:-45000}"

LOG_FILE="$REPORT_DIR/worker.log"
WORKER_BIN="$REPORT_DIR/provider_availability_worker"
LOCK_DIR="$REPORT_DIR/.worker.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_STARTED_FILE="$LOCK_DIR/started_at_unix"
LOCK_TTL_SECONDS="${PROVIDER_AVAILABILITY_LOCK_TTL_SECONDS:-7200}"

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
  log_line "starting provider availability worker"
  PROVIDER_AVAILABILITY_SOURCES=(
    "$ROOT/scripts/provider_availability_matching.swift"
    "$ROOT/scripts/provider_availability_run.swift"
    "$ROOT/scripts/provider_availability_worker.swift"
  )
  needs_build=0
  if [[ ! -x "$WORKER_BIN" ]]; then
    needs_build=1
  else
    for src in "${PROVIDER_AVAILABILITY_SOURCES[@]}"; do
      if [[ "$src" -nt "$WORKER_BIN" ]]; then
        needs_build=1
      fi
    done
  fi
  if [[ "$needs_build" -eq 1 ]]; then
    if [[ -n "${KURO_SWIFTC:-}" ]]; then
      "$KURO_SWIFTC" -parse-as-library "${PROVIDER_AVAILABILITY_SOURCES[@]}" -o "$WORKER_BIN"
    else
      /usr/bin/xcrun swiftc -parse-as-library "${PROVIDER_AVAILABILITY_SOURCES[@]}" -o "$WORKER_BIN"
    fi
  fi
  "$WORKER_BIN"
  log_line "provider availability worker completed"
} >>"$LOG_FILE" 2>&1
