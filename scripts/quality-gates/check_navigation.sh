#!/usr/bin/env bash
# Quality gate: navigation contract (docs/superpowers/specs/2026-11-02-navigation-contract-design.md §5).
# Pages open inside journeys (Kuro/Views/Routing/JourneyHost.swift); this gate lists every place in
# Kuro/** that still breaks the contract, as <file>:<line>: <code>:
#   1. a `.sheet(` whose content (that line + the next 6) builds a page (title / club / person / studio
#      detail) without the journey host: open it with `routes.openMedia/openClub/openPage(...)` instead;
#   2. a hidden navigation bar or back button (`.navigationBarBackButtonHidden(true)`,
#      `.toolbar(.hidden, for: .navigationBar)`, `.navigationBarHidden(true)`) in a file that never
#      applies the journey chrome (`.kuroJourneyChrome(`) or the pop enabler (`KuroInteractivePopEnabler`):
#      without them edge swipe-back dies (N2);
#   3. a `NavigationLink` that does not push a value, or a `navigationDestination` that is not
#      `for: JourneyPage.self`: every push goes through `JourneyPage`.
# Comment lines (//, ///) are ignored, the same way check_branded_states.sh ignores them. The routing
# files themselves (Kuro/Views/Routing/) are the allowed implementation.
# run_all.sh registers this gate as REPORTED (WARN, `:0` in GATES) while the navigation lanes migrate
# the remaining screens; it becomes blocking once the offenders reach 0.
# Extra .swift paths, if passed, are scanned too, so a scratch copy can prove the rule:
#   check_navigation.sh path/to/scratch.swift
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ALLOWED_DIR="Kuro/Views/Routing/"
PAGE_VIEWS='(AnimeDetailView|MangaDetailView|AnimeDetailPage|MangaDetailPage|MediaDetailSheet|AnimeDetailLoaderView|MangaDetailLoaderView|ClubDetailView|CharacterDetailSheet|StaffDetailSheet|StudioDetailSheet|AuthorDetailSheet)[(]'

echo "=== Navigation contract (journeys, swipe-back, typed pushes) ==="

files="$( { find Kuro -name '*.swift' -type f; for extra in "$@"; do echo "$extra"; done; } | sort -u | grep -v "^${ALLOWED_DIR}" )"

offenders=""

# 1. A page built inside `.sheet(` content (line + 6 following lines), without JourneyHost.
sheet_hits="$(printf '%s\n' "$files" | while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  awk -v file="$f" -v pages="$PAGE_VIEWS" '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        line = lines[i]
        if (line ~ /^[[:space:]]*\/\//) continue
        if (line !~ /\.sheet\(/) continue
        window = ""
        for (j = i; j <= i + 6 && j <= NR; j++) {
          if (lines[j] ~ /^[[:space:]]*\/\//) continue
          window = window "\n" lines[j]
        }
        if (window ~ pages && window !~ /JourneyHost\(/) {
          sub(/^[[:space:]]+/, "", line)
          printf "%s:%d: [sheet builds a page] %s\n", file, i, line
        }
      }
    }' "$f"
done)"
offenders+="$sheet_hits"$'\n'

# 2. Hidden bars / back buttons in files without the chrome or the pop enabler.
bar_hits="$(printf '%s\n' "$files" | while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if grep -Eq 'kuroJourneyChrome\(|KuroInteractivePopEnabler' "$f"; then continue; fi
  grep -nE '\.navigationBarBackButtonHidden\(true\)|\.toolbar\(\.hidden, for: \.navigationBar\)|\.navigationBarHidden\(true\)' "$f" \
    | grep -Ev '^[0-9]+:[[:space:]]*//' \
    | sed -E "s|^([0-9]+):[[:space:]]*|$f:\1: [hidden bar without chrome] |"
done)"
offenders+="$bar_hits"$'\n'

# 3. Pushes that are not JourneyPage values.
link_hits="$(printf '%s\n' "$files" | while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  grep -nE 'NavigationLink[[:space:]]*(\(|\{)|\.navigationDestination\(' "$f" \
    | grep -Ev '^[0-9]+:[[:space:]]*//' \
    | grep -Ev 'NavigationLink\(value:|navigationDestination\(for: JourneyPage\.self' \
    | sed -E "s|^([0-9]+):[[:space:]]*|$f:\1: [push not via JourneyPage] |"
done)"
offenders+="$link_hits"$'\n'

offenders="$(printf '%s\n' "$offenders" | grep -v '^$' || true)"

if [[ -n "$offenders" ]]; then
  count="$(printf '%s\n' "$offenders" | wc -l | tr -d ' ')"
  nfiles="$(printf '%s\n' "$offenders" | cut -d: -f1 | sort -u | wc -l | tr -d ' ')"
  echo "FAIL: $count navigation-contract offender(s) in $nfiles file(s):"
  printf '%s\n' "$offenders" | sed -E 's/^/    /'
  echo "Open pages with routes.openMedia/openClub/openPage (journeys), draw back/close with"
  echo ".kuroJourneyChrome(title:collapseProgress:material:), push only JourneyPage values (Kuro/Views/Routing/)."
  exit 1
fi

echo "ok:   no navigation-contract offenders outside $ALLOWED_DIR"
exit 0
