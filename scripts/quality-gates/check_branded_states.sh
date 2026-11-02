#!/usr/bin/env bash
# Quality gate: branded states (prototype-fidelity plan Task 3, spec §5.4).
# Every loading state in the app (Kuro/**, including the launch and auth bootstrap in KuroApp.swift)
# uses the branded family in Kuro/Views/Shared/KuroBrandedStates.swift (KuroLoadingView, KuroBusyMark,
# KuroSkeleton, KuroErrorView, KuroOfflineView, KuroEmptyView). This gate fails on any `ProgressView(`
# in Kuro/** outside that file and lists every offender as <file>:<line>: <code>.
# Comment lines (//, ///) are ignored, the same way check_architecture.sh ignores them.
# run_all.sh registers this gate as blocking (`:1` in GATES) since prototype-fidelity Task 10 drove the
# offenders to 0; it was REPORTED (WARN) while the Phase 2 screen lanes replaced their own spinners.
# Extra .swift paths, if passed, are scanned too, so a scratch copy can prove the rule:
#   check_branded_states.sh path/to/scratch.swift
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ALLOWED="Kuro/Views/Shared/KuroBrandedStates.swift"

echo "=== Branded states (no stray ProgressView in Kuro/) ==="

if command -v rg &>/dev/null; then
  matches="$(rg -n --no-heading 'ProgressView\(' Kuro "$@" --glob '*.swift' || true)"
else
  matches="$(grep -rn --include='*.swift' 'ProgressView(' Kuro "$@" || true)"
fi

offenders="$(printf '%s\n' "$matches" \
  | grep -v '^$' \
  | grep -v "^${ALLOWED}:" \
  | grep -Ev '^[^:]+:[0-9]+:[[:space:]]*//' || true)"

if [[ -n "$offenders" ]]; then
  count="$(printf '%s\n' "$offenders" | wc -l | tr -d ' ')"
  files="$(printf '%s\n' "$offenders" | cut -d: -f1 | sort -u | wc -l | tr -d ' ')"
  echo "FAIL: $count ProgressView( use(s) in $files file(s) outside $ALLOWED:"
  printf '%s\n' "$offenders" | sed -E 's/^([^:]+:[0-9]+):[[:space:]]*/    \1: /'
  echo "Replace each with a branded state (KuroLoadingView, KuroBusyMark, KuroSkeleton) from $ALLOWED."
  exit 1
fi

echo "ok:   no ProgressView( outside $ALLOWED"
exit 0
