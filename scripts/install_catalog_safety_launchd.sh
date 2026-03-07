#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kuro.catalog-safety"
ROOT="/Applications/Kuro"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPORT_DIR="$ROOT/reports/catalog-safety"
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
CATALOG_SAFETY_BATCH_SIZE_VALUE="${CATALOG_SAFETY_BATCH_SIZE:-$(read_existing_env CATALOG_SAFETY_BATCH_SIZE)}"
CATALOG_SAFETY_BATCH_SIZE_VALUE="${CATALOG_SAFETY_BATCH_SIZE_VALUE:-200}"
CATALOG_SAFETY_MEDIA_TYPES_VALUE="${CATALOG_SAFETY_MEDIA_TYPES:-$(read_existing_env CATALOG_SAFETY_MEDIA_TYPES)}"
CATALOG_SAFETY_MEDIA_TYPES_VALUE="${CATALOG_SAFETY_MEDIA_TYPES_VALUE:-ANIME,MANGA}"
CATALOG_SAFETY_REPORTS_DIR_VALUE="${CATALOG_SAFETY_REPORTS_DIR:-$(read_existing_env CATALOG_SAFETY_REPORTS_DIR)}"
CATALOG_SAFETY_REPORTS_DIR_VALUE="${CATALOG_SAFETY_REPORTS_DIR_VALUE:-$REPORT_DIR}"
CATALOG_SAFETY_OPEN_GAPS_LIMIT_VALUE="${CATALOG_SAFETY_OPEN_GAPS_LIMIT:-$(read_existing_env CATALOG_SAFETY_OPEN_GAPS_LIMIT)}"
CATALOG_SAFETY_OPEN_GAPS_LIMIT_VALUE="${CATALOG_SAFETY_OPEN_GAPS_LIMIT_VALUE:-400}"
CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE_VALUE="${CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE:-$(read_existing_env CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE)}"
CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE_VALUE="${CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE_VALUE:-0.78}"
CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE_VALUE="${CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE:-$(read_existing_env CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE)}"
CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE_VALUE="${CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE_VALUE:-0.70}"
CATALOG_SAFETY_START_INTERVAL_VALUE="${CATALOG_SAFETY_START_INTERVAL_SECONDS:-$(read_existing_start_interval)}"
CATALOG_SAFETY_START_INTERVAL_VALUE="${CATALOG_SAFETY_START_INTERVAL_VALUE:-600}"

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
    <string>$ROOT/scripts/run_catalog_safety.sh</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>SUPABASE_URL</key>
    <string>$SUPABASE_URL_VALUE</string>
    <key>SUPABASE_SERVICE_ROLE_KEY</key>
    <string>$SUPABASE_SERVICE_ROLE_KEY_VALUE</string>
    <key>CATALOG_SAFETY_BATCH_SIZE</key>
    <string>$CATALOG_SAFETY_BATCH_SIZE_VALUE</string>
    <key>CATALOG_SAFETY_MEDIA_TYPES</key>
    <string>$CATALOG_SAFETY_MEDIA_TYPES_VALUE</string>
    <key>CATALOG_SAFETY_REPORTS_DIR</key>
    <string>$CATALOG_SAFETY_REPORTS_DIR_VALUE</string>
    <key>CATALOG_SAFETY_OPEN_GAPS_LIMIT</key>
    <string>$CATALOG_SAFETY_OPEN_GAPS_LIMIT_VALUE</string>
    <key>CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE</key>
    <string>$CATALOG_SAFETY_MODEL_BLOCKED_CONFIDENCE_VALUE</string>
    <key>CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE</key>
    <string>$CATALOG_SAFETY_MODEL_SAFE_CONFIDENCE_VALUE</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>StartInterval</key>
  <integer>$CATALOG_SAFETY_START_INTERVAL_VALUE</integer>

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
