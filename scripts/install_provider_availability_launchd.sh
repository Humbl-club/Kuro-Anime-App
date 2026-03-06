#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kuro.provider-availability"
ROOT="/Applications/Kuro"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPORT_DIR="$ROOT/reports/provider-availability"
mkdir -p "$HOME/Library/LaunchAgents" "$REPORT_DIR"

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
WATCHMODE_API_KEY_VALUE="${WATCHMODE_API_KEY:-$(read_existing_env WATCHMODE_API_KEY)}"
PROVIDER_AVAILABILITY_BATCH_SIZE_VALUE="${PROVIDER_AVAILABILITY_BATCH_SIZE:-$(read_existing_env PROVIDER_AVAILABILITY_BATCH_SIZE)}"
PROVIDER_AVAILABILITY_BATCH_SIZE_VALUE="${PROVIDER_AVAILABILITY_BATCH_SIZE_VALUE:-100}"
PROVIDER_AVAILABILITY_STALE_DAYS_VALUE="${PROVIDER_AVAILABILITY_STALE_DAYS:-$(read_existing_env PROVIDER_AVAILABILITY_STALE_DAYS)}"
PROVIDER_AVAILABILITY_STALE_DAYS_VALUE="${PROVIDER_AVAILABILITY_STALE_DAYS_VALUE:-30}"
PROVIDER_AVAILABILITY_GRACE_DAYS_VALUE="${PROVIDER_AVAILABILITY_GRACE_DAYS:-$(read_existing_env PROVIDER_AVAILABILITY_GRACE_DAYS)}"
PROVIDER_AVAILABILITY_GRACE_DAYS_VALUE="${PROVIDER_AVAILABILITY_GRACE_DAYS_VALUE:-90}"
PROVIDER_AVAILABILITY_TIME_BUDGET_MS_VALUE="${PROVIDER_AVAILABILITY_TIME_BUDGET_MS:-$(read_existing_env PROVIDER_AVAILABILITY_TIME_BUDGET_MS)}"
PROVIDER_AVAILABILITY_TIME_BUDGET_MS_VALUE="${PROVIDER_AVAILABILITY_TIME_BUDGET_MS_VALUE:-45000}"
PROVIDER_AVAILABILITY_REPORTS_DIR_VALUE="${PROVIDER_AVAILABILITY_REPORTS_DIR:-$(read_existing_env PROVIDER_AVAILABILITY_REPORTS_DIR)}"
PROVIDER_AVAILABILITY_REPORTS_DIR_VALUE="${PROVIDER_AVAILABILITY_REPORTS_DIR_VALUE:-$REPORT_DIR}"
PROVIDER_AVAILABILITY_START_INTERVAL_VALUE="${PROVIDER_AVAILABILITY_START_INTERVAL_SECONDS:-$(read_existing_start_interval)}"
PROVIDER_AVAILABILITY_START_INTERVAL_VALUE="${PROVIDER_AVAILABILITY_START_INTERVAL_VALUE:-600}"

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_SERVICE_ROLE_KEY_VALUE" || -z "$WATCHMODE_API_KEY_VALUE" ]]; then
  echo "Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or WATCHMODE_API_KEY."
  echo "Export them and rerun this installer."
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
    <string>$ROOT/scripts/run_provider_availability.sh</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>SUPABASE_URL</key>
    <string>$SUPABASE_URL_VALUE</string>
    <key>SUPABASE_SERVICE_ROLE_KEY</key>
    <string>$SUPABASE_SERVICE_ROLE_KEY_VALUE</string>
    <key>WATCHMODE_API_KEY</key>
    <string>$WATCHMODE_API_KEY_VALUE</string>
    <key>PROVIDER_AVAILABILITY_BATCH_SIZE</key>
    <string>$PROVIDER_AVAILABILITY_BATCH_SIZE_VALUE</string>
    <key>PROVIDER_AVAILABILITY_STALE_DAYS</key>
    <string>$PROVIDER_AVAILABILITY_STALE_DAYS_VALUE</string>
    <key>PROVIDER_AVAILABILITY_GRACE_DAYS</key>
    <string>$PROVIDER_AVAILABILITY_GRACE_DAYS_VALUE</string>
    <key>PROVIDER_AVAILABILITY_TIME_BUDGET_MS</key>
    <string>$PROVIDER_AVAILABILITY_TIME_BUDGET_MS_VALUE</string>
    <key>PROVIDER_AVAILABILITY_REPORTS_DIR</key>
    <string>$PROVIDER_AVAILABILITY_REPORTS_DIR_VALUE</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>StartInterval</key>
  <integer>$PROVIDER_AVAILABILITY_START_INTERVAL_VALUE</integer>

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
