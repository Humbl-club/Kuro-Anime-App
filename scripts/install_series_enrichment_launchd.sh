#!/usr/bin/env bash
# Installs com.kuro.series-enrichment: a daily AnimeThemes theme pass (run_series_enrichment.sh).
# Credentials go only into the plist under ~/Library/LaunchAgents (chmod 600), never the repo.
# Schedule: daily at SERIES_ENRICHMENT_HOUR:SERIES_ENRICHMENT_MINUTE local time (default 05:20).
# No RunAtLoad and no kickstart: installing does not start a run.
set -euo pipefail

LABEL="com.kuro.series-enrichment"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kuro_project_root.sh
source "$SCRIPT_DIR/kuro_project_root.sh"
ROOT="$(kuro_resolve_project_root)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPORT_DIR="$ROOT/reports/series-enrichment"
mkdir -p "$HOME/Library/LaunchAgents" "$REPORT_DIR"
source "$ROOT/scripts/lib/load_project_public_env.sh"
load_project_public_env || true

read_existing_env() {
  local key="$1"
  if [[ -f "$PLIST" ]]; then
    /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$key" "$PLIST" 2>/dev/null || true
  fi
}

SUPABASE_URL_VALUE="${SUPABASE_URL:-$(read_existing_env SUPABASE_URL)}"
SUPABASE_SERVICE_ROLE_KEY_VALUE="${SUPABASE_SERVICE_ROLE_KEY:-$(read_existing_env SUPABASE_SERVICE_ROLE_KEY)}"
PASSES_VALUE="${SERIES_THEMES_PASSES:-$(read_existing_env SERIES_THEMES_PASSES)}"
PASSES_VALUE="${PASSES_VALUE:-4}"
HOUR_VALUE="${SERIES_ENRICHMENT_HOUR:-5}"
MINUTE_VALUE="${SERIES_ENRICHMENT_MINUTE:-20}"

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_SERVICE_ROLE_KEY_VALUE" ]]; then
  echo "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY."
  echo "Export both vars, then run this installer again."
  exit 1
fi

umask 077
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
    <string>$ROOT/scripts/run_series_enrichment.sh</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>KURO_PROJECT_ROOT</key>
    <string>$ROOT</string>
    <key>SUPABASE_URL</key>
    <string>$SUPABASE_URL_VALUE</string>
    <key>SUPABASE_SERVICE_ROLE_KEY</key>
    <string>$SUPABASE_SERVICE_ROLE_KEY_VALUE</string>
    <key>SERIES_THEMES_PASSES</key>
    <string>$PASSES_VALUE</string>
  </dict>

  <key>RunAtLoad</key>
  <false/>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>$HOUR_VALUE</integer>
    <key>Minute</key>
    <integer>$MINUTE_VALUE</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>$REPORT_DIR/launchd.out.log</string>

  <key>StandardErrorPath</key>
  <string>$REPORT_DIR/launchd.err.log</string>
</dict>
</plist>
PLIST
chmod 600 "$PLIST"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"

echo "Installed $LABEL (daily at $(printf '%02d:%02d' "$HOUR_VALUE" "$MINUTE_VALUE") local time)"
echo "Plist: $PLIST"
echo "Logs: $REPORT_DIR/worker.log, launchd.out.log, launchd.err.log"
