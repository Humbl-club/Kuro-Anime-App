#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kuro.unified-dashboard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kuro_project_root.sh
source "$SCRIPT_DIR/kuro_project_root.sh"
ROOT="$(kuro_resolve_project_root)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPORT_DIR="$ROOT/reports/local-dashboard"
read_existing_env() {
  local key="$1"
  if [[ -f "$PLIST" ]]; then
    /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$key" "$PLIST" 2>/dev/null || true
  fi
}
PORT="${KURO_UNIFIED_DASHBOARD_PORT:-$(read_existing_env KURO_UNIFIED_DASHBOARD_PORT)}"
PORT="${PORT:-8791}"

mkdir -p "$HOME/Library/LaunchAgents" "$REPORT_DIR"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/node</string>
    <string>$ROOT/scripts/unified_local_dashboard_server.js</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>KURO_PROJECT_ROOT</key>
    <string>$ROOT</string>
    <key>KURO_UNIFIED_DASHBOARD_PORT</key>
    <string>$PORT</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$REPORT_DIR/dashboard.out.log</string>

  <key>StandardErrorPath</key>
  <string>$REPORT_DIR/dashboard.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
echo "Dashboard: http://127.0.0.1:$PORT"
echo "Plist: $PLIST"
