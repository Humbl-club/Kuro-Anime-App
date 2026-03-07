#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kuro.media-relations"
ROOT="/Applications/Kuro"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPORT_DIR="$ROOT/reports/media-relations"
mkdir -p "$HOME/Library/LaunchAgents" "$REPORT_DIR"
source "$ROOT/scripts/lib/load_project_public_env.sh"
load_project_public_env || true

read_existing_env() {
  local key="$1"
  if [[ -f "$PLIST" ]]; then
    local value
    value="$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$key" "$PLIST" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  fi
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
}

read_existing_start_interval() {
  if [[ -f "$PLIST" ]]; then
    /usr/libexec/PlistBuddy -c "Print :StartInterval" "$PLIST" 2>/dev/null || true
  fi
}

SUPABASE_URL_VALUE="${SUPABASE_URL:-$(read_existing_env SUPABASE_URL)}"
SUPABASE_SERVICE_ROLE_KEY_VALUE="${SUPABASE_SERVICE_ROLE_KEY:-$(read_existing_env SUPABASE_SERVICE_ROLE_KEY)}"
MEDIA_RELATIONS_MODE_VALUE="${MEDIA_RELATIONS_MODE:-$(read_existing_env MEDIA_RELATIONS_MODE)}"
MEDIA_RELATIONS_MODE_VALUE="${MEDIA_RELATIONS_MODE_VALUE:-queue}"
MEDIA_RELATIONS_TOP_COUNT_VALUE="${MEDIA_RELATIONS_TOP_COUNT:-$(read_existing_env MEDIA_RELATIONS_TOP_COUNT)}"
MEDIA_RELATIONS_TOP_COUNT_VALUE="${MEDIA_RELATIONS_TOP_COUNT_VALUE:-500}"
MEDIA_RELATIONS_QUEUE_LIMIT_VALUE="${MEDIA_RELATIONS_QUEUE_LIMIT:-$(read_existing_env MEDIA_RELATIONS_QUEUE_LIMIT)}"
MEDIA_RELATIONS_QUEUE_LIMIT_VALUE="${MEDIA_RELATIONS_QUEUE_LIMIT_VALUE:-40}"
MEDIA_RELATIONS_REPORT_SAMPLE_SIZE_VALUE="${MEDIA_RELATIONS_REPORT_SAMPLE_SIZE:-$(read_existing_env MEDIA_RELATIONS_REPORT_SAMPLE_SIZE)}"
MEDIA_RELATIONS_REPORT_SAMPLE_SIZE_VALUE="${MEDIA_RELATIONS_REPORT_SAMPLE_SIZE_VALUE:-500}"
MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT_VALUE="${MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT:-$(read_existing_env MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT)}"
MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT_VALUE="${MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT_VALUE:-30}"
ANILIST_BATCH_SIZE_VALUE="${ANILIST_BATCH_SIZE:-$(read_existing_env ANILIST_BATCH_SIZE)}"
ANILIST_BATCH_SIZE_VALUE="${ANILIST_BATCH_SIZE_VALUE:-10}"
ANILIST_REQUEST_DELAY_MS_VALUE="${ANILIST_REQUEST_DELAY_MS:-$(read_existing_env ANILIST_REQUEST_DELAY_MS)}"
ANILIST_REQUEST_DELAY_MS_VALUE="${ANILIST_REQUEST_DELAY_MS_VALUE:-350}"
ANILIST_TIMEOUT_MS_VALUE="${ANILIST_TIMEOUT_MS:-$(read_existing_env ANILIST_TIMEOUT_MS)}"
ANILIST_TIMEOUT_MS_VALUE="${ANILIST_TIMEOUT_MS_VALUE:-20000}"
MEDIA_RELATIONS_REPORTS_DIR_VALUE="${MEDIA_RELATIONS_REPORTS_DIR:-$(read_existing_env MEDIA_RELATIONS_REPORTS_DIR)}"
MEDIA_RELATIONS_REPORTS_DIR_VALUE="${MEDIA_RELATIONS_REPORTS_DIR_VALUE:-$REPORT_DIR}"
MEDIA_RELATIONS_START_INTERVAL_VALUE="${MEDIA_RELATIONS_START_INTERVAL_SECONDS:-$(read_existing_start_interval)}"
MEDIA_RELATIONS_START_INTERVAL_VALUE="${MEDIA_RELATIONS_START_INTERVAL_VALUE:-900}"

if [[ -z "$SUPABASE_SERVICE_ROLE_KEY_VALUE" ]]; then
  echo "Missing SUPABASE_SERVICE_ROLE_KEY. Export it and rerun this installer." >&2
  exit 1
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/scripts/run_media_relations_refresh.sh</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>SUPABASE_URL</key>
    <string>$SUPABASE_URL_VALUE</string>
    <key>SUPABASE_SERVICE_ROLE_KEY</key>
    <string>$SUPABASE_SERVICE_ROLE_KEY_VALUE</string>
    <key>MEDIA_RELATIONS_MODE</key>
    <string>$MEDIA_RELATIONS_MODE_VALUE</string>
    <key>MEDIA_RELATIONS_TOP_COUNT</key>
    <string>$MEDIA_RELATIONS_TOP_COUNT_VALUE</string>
    <key>MEDIA_RELATIONS_QUEUE_LIMIT</key>
    <string>$MEDIA_RELATIONS_QUEUE_LIMIT_VALUE</string>
    <key>MEDIA_RELATIONS_REPORT_SAMPLE_SIZE</key>
    <string>$MEDIA_RELATIONS_REPORT_SAMPLE_SIZE_VALUE</string>
    <key>MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT</key>
    <string>$MEDIA_RELATIONS_REPORT_TOP_MISSING_LIMIT_VALUE</string>
    <key>ANILIST_BATCH_SIZE</key>
    <string>$ANILIST_BATCH_SIZE_VALUE</string>
    <key>ANILIST_REQUEST_DELAY_MS</key>
    <string>$ANILIST_REQUEST_DELAY_MS_VALUE</string>
    <key>ANILIST_TIMEOUT_MS</key>
    <string>$ANILIST_TIMEOUT_MS_VALUE</string>
    <key>MEDIA_RELATIONS_REPORTS_DIR</key>
    <string>$MEDIA_RELATIONS_REPORTS_DIR_VALUE</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>StartInterval</key>
  <integer>$MEDIA_RELATIONS_START_INTERVAL_VALUE</integer>

  <key>StandardOutPath</key>
  <string>$REPORT_DIR/launchd.out.log</string>

  <key>StandardErrorPath</key>
  <string>$REPORT_DIR/launchd.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
echo "Plist: $PLIST"
echo "Logs: $REPORT_DIR/launchd.out.log and $REPORT_DIR/launchd.err.log"
