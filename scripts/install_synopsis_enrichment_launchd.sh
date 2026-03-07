#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kuro.synopsis-enrichment"
ROOT="/Applications/Kuro"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPORT_DIR="$ROOT/reports/synopsis-enrichment"
mkdir -p "$HOME/Library/LaunchAgents" "$REPORT_DIR"
source "$ROOT/scripts/lib/load_project_public_env.sh"
load_project_public_env || true

read_existing_env() {
  local key="$1"
  if [[ -f "$PLIST" ]]; then
    /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$key" "$PLIST" 2>/dev/null || true
  fi
}

read_existing_start_interval() {
  if [[ -f "$PLIST" ]]; then
    /usr/libexec/PlistBuddy -c "Print :StartInterval" "$PLIST" 2>/dev/null || true
  fi
}

SUPABASE_URL_VALUE="${SUPABASE_URL:-$(read_existing_env SUPABASE_URL)}"
SUPABASE_SERVICE_ROLE_KEY_VALUE="${SUPABASE_SERVICE_ROLE_KEY:-$(read_existing_env SUPABASE_SERVICE_ROLE_KEY)}"
SYNOPSIS_BATCH_SIZE_VALUE="${SYNOPSIS_BATCH_SIZE:-$(read_existing_env SYNOPSIS_BATCH_SIZE)}"
SYNOPSIS_BATCH_SIZE_VALUE="${SYNOPSIS_BATCH_SIZE_VALUE:-100}"
SYNOPSIS_MEDIA_TYPES_VALUE="${SYNOPSIS_MEDIA_TYPES:-$(read_existing_env SYNOPSIS_MEDIA_TYPES)}"
SYNOPSIS_MEDIA_TYPES_VALUE="${SYNOPSIS_MEDIA_TYPES_VALUE:-ANIME,MANGA}"
SYNOPSIS_REPORTS_DIR_VALUE="${SYNOPSIS_REPORTS_DIR:-$(read_existing_env SYNOPSIS_REPORTS_DIR)}"
SYNOPSIS_REPORTS_DIR_VALUE="${SYNOPSIS_REPORTS_DIR_VALUE:-$REPORT_DIR}"
SYNOPSIS_MIN_CHARS_VALUE="${SYNOPSIS_MIN_CHARS:-$(read_existing_env SYNOPSIS_MIN_CHARS)}"
SYNOPSIS_MIN_CHARS_VALUE="${SYNOPSIS_MIN_CHARS_VALUE:-140}"
SYNOPSIS_MAX_CHARS_VALUE="${SYNOPSIS_MAX_CHARS:-$(read_existing_env SYNOPSIS_MAX_CHARS)}"
SYNOPSIS_MAX_CHARS_VALUE="${SYNOPSIS_MAX_CHARS_VALUE:-420}"
SYNOPSIS_MIN_SENTENCES_VALUE="${SYNOPSIS_MIN_SENTENCES:-$(read_existing_env SYNOPSIS_MIN_SENTENCES)}"
SYNOPSIS_MIN_SENTENCES_VALUE="${SYNOPSIS_MIN_SENTENCES_VALUE:-3}"
SYNOPSIS_MAX_SENTENCES_VALUE="${SYNOPSIS_MAX_SENTENCES:-$(read_existing_env SYNOPSIS_MAX_SENTENCES)}"
SYNOPSIS_MAX_SENTENCES_VALUE="${SYNOPSIS_MAX_SENTENCES_VALUE:-4}"
SYNOPSIS_MIN_SOURCE_CHARS_VALUE="${SYNOPSIS_MIN_SOURCE_CHARS:-$(read_existing_env SYNOPSIS_MIN_SOURCE_CHARS)}"
SYNOPSIS_MIN_SOURCE_CHARS_VALUE="${SYNOPSIS_MIN_SOURCE_CHARS_VALUE:-110}"
SYNOPSIS_START_INTERVAL_VALUE="${SYNOPSIS_START_INTERVAL_SECONDS:-$(read_existing_start_interval)}"
SYNOPSIS_START_INTERVAL_VALUE="${SYNOPSIS_START_INTERVAL_VALUE:-240}"

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_SERVICE_ROLE_KEY_VALUE" ]]; then
  echo "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY."
  echo "Export both vars, then run this installer again."
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
    <string>$ROOT/scripts/run_synopsis_enrichment.sh</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>SUPABASE_URL</key>
    <string>$SUPABASE_URL_VALUE</string>
    <key>SUPABASE_SERVICE_ROLE_KEY</key>
    <string>$SUPABASE_SERVICE_ROLE_KEY_VALUE</string>
    <key>SYNOPSIS_BATCH_SIZE</key>
    <string>$SYNOPSIS_BATCH_SIZE_VALUE</string>
    <key>SYNOPSIS_MEDIA_TYPES</key>
    <string>$SYNOPSIS_MEDIA_TYPES_VALUE</string>
    <key>SYNOPSIS_REPORTS_DIR</key>
    <string>$SYNOPSIS_REPORTS_DIR_VALUE</string>
    <key>SYNOPSIS_MIN_CHARS</key>
    <string>$SYNOPSIS_MIN_CHARS_VALUE</string>
    <key>SYNOPSIS_MAX_CHARS</key>
    <string>$SYNOPSIS_MAX_CHARS_VALUE</string>
    <key>SYNOPSIS_MIN_SENTENCES</key>
    <string>$SYNOPSIS_MIN_SENTENCES_VALUE</string>
    <key>SYNOPSIS_MAX_SENTENCES</key>
    <string>$SYNOPSIS_MAX_SENTENCES_VALUE</string>
    <key>SYNOPSIS_MIN_SOURCE_CHARS</key>
    <string>$SYNOPSIS_MIN_SOURCE_CHARS_VALUE</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>StartInterval</key>
  <integer>$SYNOPSIS_START_INTERVAL_VALUE</integer>

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
