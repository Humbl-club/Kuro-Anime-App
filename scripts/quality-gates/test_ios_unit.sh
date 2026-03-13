#!/usr/bin/env bash
# Quality gate: Run Kuro iOS unit tests on the simulator.
set -euo pipefail

SCHEME="Kuro"
PRIMARY_DEST="platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2"

pick_fallback_destination() {
  xcrun simctl list devices available | \
    awk -F '[()]' '
      /iPhone 17 Pro/ { os = section }
      /^-- iOS / { section = $0; gsub(/^-- iOS /, "", section); gsub(/ --$/, "", section) }
      /iPhone 17 Pro/ && /Shutdown|Booted/ { print "platform=iOS Simulator,name=iPhone 17 Pro,OS=" section; exit }
      /iPhone 17/ && /Shutdown|Booted/ && fallback == "" { fallback = "platform=iOS Simulator,name=iPhone 17,OS=" section }
      END { if (fallback != "") print fallback }
    '
}

echo "[ios-test] Running unit tests..."

DEST="$PRIMARY_DEST"
if ! xcrun simctl list devices available | grep -Fq "iPhone 17 Pro"; then
  FALLBACK_DEST="$(pick_fallback_destination)"
  if [[ -n "${FALLBACK_DEST:-}" ]]; then
    DEST="$FALLBACK_DEST"
  fi
fi

echo "[ios-test] Using destination: $DEST"
if xcodebuild -scheme "$SCHEME" -destination "$DEST" test -only-testing:KuroTests; then
  echo "[ios-test] PASS"
  exit 0
fi

echo "[ios-test] FAIL"
exit 1
