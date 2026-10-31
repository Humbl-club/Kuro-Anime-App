#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kuro_project_root.sh
source "$SCRIPT_DIR/kuro_project_root.sh"

# Complete Supabase pair from one source only: both variables already in the
# environment, else both keys in MEDIA_RELATIONS_CONFIG, else one fallback plist
# that contains both. Never pair a URL from one file with a key from another.
MEDIA_RELATIONS_CONFIG="${MEDIA_RELATIONS_CONFIG:-$HOME/Library/LaunchAgents/com.kuro.media-relations.plist}"

kuro_media_relations_read_plist() {
  local plist="$1"
  local key="$2"
  local value
  [[ -f "$plist" ]] || return 1
  value="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$key" "$plist" 2>/dev/null || true)"
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

kuro_media_relations_read_env_file() {
  local file="$1"
  local key="$2"
  local line k v
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%$'\r'}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    if [[ "$line" == export\ * ]]; then
      line="${line#export }"
      line="${line#"${line%%[![:space:]]*}"}"
    fi
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"
    k="${k%"${k##*[![:space:]]}"}"
    [[ "$k" == "$key" ]] || continue
    v="${line#*=}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    v="${v%$'\r'}"
    if [[ "$v" == \"*\" && "$v" == *\" ]]; then
      v="${v:1:${#v}-2}"
    elif [[ "$v" == \'*\' && "$v" == *\' ]]; then
      v="${v:1:${#v}-2}"
    fi
    printf '%s' "$v"
    return 0
  done < "$file"
  return 1
}

kuro_media_relations_read_own() {
  local key="$1"
  local config="${MEDIA_RELATIONS_CONFIG:-}"
  [[ -n "$config" && -f "$config" ]] || return 1
  case "$config" in
    *.plist)
      kuro_media_relations_read_plist "$config" "$key"
      ;;
    *)
      kuro_media_relations_read_env_file "$config" "$key"
      ;;
  esac
}

kuro_media_relations_fallback_plists() {
  if [[ -n "${MEDIA_RELATIONS_FALLBACK_PLISTS+x}" ]]; then
    local part
    local IFS=':'
    for part in ${MEDIA_RELATIONS_FALLBACK_PLISTS}; do
      [[ -n "$part" ]] && printf '%s\n' "$part"
    done
    return 0
  fi
  printf '%s\n' \
    "$HOME/Library/LaunchAgents/com.kuro.catalog-safety.plist" \
    "$HOME/Library/LaunchAgents/com.kuro.synopsis-enrichment.plist" \
    "$HOME/Library/LaunchAgents/com.kuro.provider-availability.plist"
}

kuro_media_relations_fail_incomplete() {
  local missing_list="$1"
  local source_label="$2"
  echo "Missing ${missing_list}. ${source_label} has an incomplete Supabase pair, so the other setting was not taken from a different source." >&2
  exit 1
}

# Complete pair only, in order:
# 1. both variables already in the environment
# 2. else both keys present in MEDIA_RELATIONS_CONFIG
# 3. else the first fallback plist that contains both
kuro_media_relations_resolve_settings() {
  local env_url="${SUPABASE_URL:-}"
  local env_key="${SUPABASE_SERVICE_ROLE_KEY:-}"
  if [[ -n "$env_url" && -n "$env_key" ]]; then
    return 0
  fi
  if [[ -n "$env_url" || -n "$env_key" ]]; then
    local missing=()
    [[ -z "$env_url" ]] && missing+=(SUPABASE_URL)
    [[ -z "$env_key" ]] && missing+=(SUPABASE_SERVICE_ROLE_KEY)
    kuro_media_relations_fail_incomplete "${missing[*]}" "The environment"
  fi

  local config="${MEDIA_RELATIONS_CONFIG:-}"
  if [[ -n "$config" && -f "$config" ]]; then
    local own_url="" own_key=""
    own_url="$(kuro_media_relations_read_own SUPABASE_URL || true)"
    own_key="$(kuro_media_relations_read_own SUPABASE_SERVICE_ROLE_KEY || true)"
    if [[ -n "$own_url" && -n "$own_key" ]]; then
      export SUPABASE_URL="$own_url"
      export SUPABASE_SERVICE_ROLE_KEY="$own_key"
      return 0
    fi
    if [[ -n "$own_url" || -n "$own_key" ]]; then
      local missing=()
      [[ -z "$own_url" ]] && missing+=(SUPABASE_URL)
      [[ -z "$own_key" ]] && missing+=(SUPABASE_SERVICE_ROLE_KEY)
      kuro_media_relations_fail_incomplete "${missing[*]}" "The media-relations config"
    fi
  fi

  local plist url key
  while IFS= read -r plist; do
    [[ -n "$plist" && -f "$plist" ]] || continue
    url="$(kuro_media_relations_read_plist "$plist" SUPABASE_URL || true)"
    key="$(kuro_media_relations_read_plist "$plist" SUPABASE_SERVICE_ROLE_KEY || true)"
    if [[ -n "$url" && -n "$key" ]]; then
      export SUPABASE_URL="$url"
      export SUPABASE_SERVICE_ROLE_KEY="$key"
      return 0
    fi
  done < <(kuro_media_relations_fallback_plists)
}

kuro_media_relations_require_settings() {
  local missing=()
  [[ -z "${SUPABASE_URL:-}" ]] && missing+=(SUPABASE_URL)
  [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]] && missing+=(SUPABASE_SERVICE_ROLE_KEY)
  if ((${#missing[@]})); then
    echo "Missing ${missing[*]}. Set both in the environment, or provide both in the media-relations config (MEDIA_RELATIONS_CONFIG; default ~/Library/LaunchAgents/com.kuro.media-relations.plist), or in one fallback plist that contains both." >&2
    exit 1
  fi
}

if [[ "${KURO_MEDIA_RELATIONS_SOURCE_ONLY:-}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

ROOT="$(kuro_resolve_project_root)"
REPORT_DIR="${MEDIA_RELATIONS_REPORTS_DIR:-$ROOT/reports/media-relations}"

kuro_media_relations_resolve_settings
if [[ -z "${SUPABASE_URL:-}" && -f "$ROOT/scripts/lib/load_project_public_env.sh" ]]; then
  # Public project URL only. Never reads a service-role credential.
  # shellcheck source=lib/load_project_public_env.sh
  source "$ROOT/scripts/lib/load_project_public_env.sh"
  load_project_public_env || true
fi
kuro_media_relations_require_settings

mkdir -p "$REPORT_DIR"
export SUPABASE_URL
export SUPABASE_SERVICE_ROLE_KEY
export MEDIA_RELATIONS_REPORTS_DIR="$REPORT_DIR"
export MEDIA_RELATIONS_MODE="${MEDIA_RELATIONS_MODE:-queue}"
export MEDIA_RELATIONS_TOP_COUNT="${MEDIA_RELATIONS_TOP_COUNT:-500}"
export MEDIA_RELATIONS_QUEUE_LIMIT="${MEDIA_RELATIONS_QUEUE_LIMIT:-40}"
export MEDIA_RELATIONS_REPORT_SAMPLE_SIZE="${MEDIA_RELATIONS_REPORT_SAMPLE_SIZE:-500}"
export MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT="${MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT:-30}"
export ANILIST_BATCH_SIZE="${ANILIST_BATCH_SIZE:-10}"
export ANILIST_REQUEST_DELAY_MS="${ANILIST_REQUEST_DELAY_MS:-350}"
export ANILIST_TIMEOUT_MS="${ANILIST_TIMEOUT_MS:-20000}"

LOG_FILE="$REPORT_DIR/worker.log"
LOCK_DIR="$REPORT_DIR/.worker.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_STARTED_FILE="$LOCK_DIR/started_at_unix"
LOCK_TTL_SECONDS="${MEDIA_RELATIONS_LOCK_TTL_SECONDS:-21600}"
WORKER="$ROOT/scripts/media_relations_worker.js"
RUN_STATE_FILE="$REPORT_DIR/latest-run.json"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"

if [[ -z "$NODE_BIN" && -x /usr/local/bin/node ]]; then
  NODE_BIN="/usr/local/bin/node"
fi

if [[ -z "$NODE_BIN" ]]; then
  echo "Missing node runtime. Install Node or set NODE_BIN." >&2
  exit 1
fi

log_line() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >>"$LOG_FILE" 2>&1
}

write_lock_metadata() {
  printf '%s' "$$" >"$LOCK_PID_FILE"
  date +%s >"$LOCK_STARTED_FILE"
}

write_run_state() {
  local state="$1"
  local detail="${2:-}"
  python3 - "$RUN_STATE_FILE" "$state" "$MEDIA_RELATIONS_MODE" "$detail" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

path, state, mode, detail = sys.argv[1:5]
payload = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh) or {}
    except Exception:
        payload = {}

now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
payload["mode"] = mode
payload["state"] = state
payload["pid"] = os.getppid()
if state == "running":
    payload["started_at"] = now
    payload.pop("completed_at", None)
    payload.pop("error", None)
elif state == "completed":
    payload["completed_at"] = now
    payload.pop("error", None)
elif state == "error":
    payload["completed_at"] = now
    if detail:
        payload["error"] = detail
elif detail:
    payload["detail"] = detail

with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
PY
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

  if [[ -n "$lock_pid" ]]; then
    log_line "recovering dead lock from pid=$lock_pid"
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      write_lock_metadata
      return 0
    fi
    log_line "lock acquire retry failed after dead-pid recovery, skipping overlap"
    return 1
  fi

  local lock_started=""
  if [[ -f "$LOCK_STARTED_FILE" ]]; then
    lock_started="$(tr -dc '0-9' <"$LOCK_STARTED_FILE" | head -c 20 || true)"
  fi
  if [[ -z "$lock_started" ]]; then
    lock_started="$(stat -f %m "$LOCK_DIR" 2>/dev/null || true)"
  fi

  if [[ -z "$lock_started" ]]; then
    log_line "recovering malformed lock with no pid or start time"
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      write_lock_metadata
      return 0
    fi
    log_line "lock acquire retry failed after malformed-lock recovery, skipping overlap"
    return 1
  fi

  local now_epoch
  now_epoch="$(date +%s)"
  local lock_age=$(( now_epoch - lock_started ))
  if (( lock_age < LOCK_TTL_SECONDS )); then
    log_line "recovering malformed lock by ttl fallback (age=${lock_age}s, pid missing)"
  else
    log_line "stale lock detected via ttl fallback (age=${lock_age}s), removing and retrying lock acquire"
  fi

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
on_exit() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    log_line "media relations worker failed (exit=${exit_code})"
    write_run_state "error" "worker exited with code ${exit_code}"
  fi
  rm -f "$LOCK_PID_FILE" "$LOCK_STARTED_FILE"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap on_exit EXIT

{
  write_run_state "running"
  log_line "starting media relations worker (mode=${MEDIA_RELATIONS_MODE})"
  "$NODE_BIN" "$WORKER"
  log_line "media relations worker completed"
  write_run_state "completed"
} >>"$LOG_FILE" 2>&1
