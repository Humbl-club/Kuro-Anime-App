#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$AGENTS_DIR"

CI_LABEL="com.kuro.local-ci"
CI_PLIST="$AGENTS_DIR/$CI_LABEL.plist"
CI_INTERVAL="${CI_INTERVAL_SECONDS:-21600}" # 6h default

CD_LABEL="com.kuro.local-cd"
CD_PLIST="$AGENTS_DIR/$CD_LABEL.plist"
CD_ENABLED=0
CD_HOUR="${CD_HOUR:-3}"
CD_MINUTE="${CD_MINUTE:-30}"

usage() {
  cat <<'EOF'
Usage: scripts/install_local_cicd_launchd.sh [options]

Options:
  --with-cd         Also install nightly CD launch agent.
  --ci-interval N   CI interval in seconds (default 21600).
  --cd-hour N       Nightly CD hour (0-23, default 3).
  --cd-minute N     Nightly CD minute (0-59, default 30).
  --uninstall       Remove existing CI/CD launch agents.
  -h, --help        Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --with-cd)
      CD_ENABLED=1
      ;;
    --ci-interval)
      CI_INTERVAL="${2:-21600}"
      shift
      ;;
    --cd-hour)
      CD_HOUR="${2:-3}"
      shift
      ;;
    --cd-minute)
      CD_MINUTE="${2:-30}"
      shift
      ;;
    --uninstall)
      launchctl bootout "gui/$(id -u)/$CI_LABEL" >/dev/null 2>&1 || true
      launchctl bootout "gui/$(id -u)/$CD_LABEL" >/dev/null 2>&1 || true
      rm -f "$CI_PLIST" "$CD_PLIST"
      echo "[local-cicd] removed launch agents"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[local-cicd] ERROR: unknown option '$1'" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

cat >"$CI_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$CI_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>cd $ROOT_DIR && $ROOT_DIR/scripts/run_local_ci_logged.sh</string>
  </array>
  <key>StartInterval</key><integer>$CI_INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$ROOT_DIR/reports/local-cicd/launchd-ci.out.log</string>
  <key>StandardErrorPath</key><string>$ROOT_DIR/reports/local-cicd/launchd-ci.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$CI_LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$CI_PLIST"
launchctl enable "gui/$(id -u)/$CI_LABEL"
launchctl kickstart -k "gui/$(id -u)/$CI_LABEL"

echo "[local-cicd] installed CI agent: $CI_PLIST (every ${CI_INTERVAL}s)"

if [[ "$CD_ENABLED" == "1" ]]; then
  cat >"$CD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$CD_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>cd $ROOT_DIR && DEPLOY_SUPABASE=1 DEPLOY_TESTFLIGHT=0 $ROOT_DIR/scripts/run_local_cd_logged.sh --supabase-only</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>$CD_HOUR</integer>
    <key>Minute</key><integer>$CD_MINUTE</integer>
  </dict>
  <key>StandardOutPath</key><string>$ROOT_DIR/reports/local-cicd/launchd-cd.out.log</string>
  <key>StandardErrorPath</key><string>$ROOT_DIR/reports/local-cicd/launchd-cd.err.log</string>
</dict>
</plist>
PLIST

  launchctl bootout "gui/$(id -u)/$CD_LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$CD_PLIST"
  launchctl enable "gui/$(id -u)/$CD_LABEL"
  echo "[local-cicd] installed CD agent: $CD_PLIST (daily ${CD_HOUR}:${CD_MINUTE})"
fi

echo "[local-cicd] logs: $ROOT_DIR/reports/local-cicd"
