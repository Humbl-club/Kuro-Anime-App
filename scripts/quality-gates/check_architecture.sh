#!/usr/bin/env bash
# Quality gate: architecture boundaries (docs/plans/2026-10-05-modular-architecture-plan.md, gates G3/G7).
# Source checks only (rg). What the COMPILER already enforces is not repeated here:
#   - the local package target graph is acyclic and targets only import their declared dependencies
#     (SwiftPM; run by scripts/quality-gates/test_packages.sh);
#   - MemberImportVisibility is on, so a file must import the module that declares what it uses.
# What this script checks (each is a HARD failure):
#   1  No code references SupabaseService (the retired facade) in Kuro/ or KuroTests/.
#   2  No code reads FeatureFlags.shared (flags are injected by composition).
#   3  No view imports an SDK module (Supabase, PostgREST, Realtime, Auth, Functions, Storage).
#   4  The tracking tables are named only in the Library transport and the Library realtime owner.
#   5  The local package stays SDK-free and UI-free (no Supabase/SwiftUI/UIKit imports in Packages/*/Sources).
#   6  The tracking write mapping lives only in LibraryActions: the retired facade writers are not redefined
#      outside it, and no view (or ContentView) writes the Library store directly.
#   7  Views do not touch the Supabase client: Kuro/Views and ContentView.swift must not construct
#      SupabaseClient, and must not call client.auth / client.database / client.functions / client.channel
#      (optional chaining client?.… is the same call). Composition constructs the one client; capability
#      owners make those calls. This is one representative edge, not a general architecture compiler.
# Comment lines (//, ///) are ignored; a line that merely contains "://" is NOT treated as a comment.
# Extra .swift paths, if passed, are scanned by rule 7 only so a scratch copy can prove the rule:
#   check_architecture.sh path/to/scratch.swift
# The default invocation passes no extras and scans only the app.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
# Drop matches on comment lines only: "<file>:<line>:<indent>//..."
strip_comments() { grep -Ev '^[^:]+:[0-9]+:[[:space:]]*//' || true; }
section() { echo "--- $1"; }
report() {  # report <label> <matches>
  if [[ -n "$2" ]]; then echo "FAIL: $1"; printf '%s\n' "$2" | sed 's/^/    /'; fail=1; else echo "ok:   $1"; fi
}

echo "=== Architecture boundaries ==="

section "1 retired facade"
report "no SupabaseService references in code (Kuro/, KuroTests/)" \
  "$(rg -n 'SupabaseService|supabaseService' Kuro KuroTests --glob '*.swift' | strip_comments)"

section "2 flags injection"
report "no FeatureFlags.shared reads" \
  "$(rg -n 'FeatureFlags\.shared' Kuro KuroTests --glob '*.swift' | strip_comments)"

section "3 SDK imports in views"
report "no SDK import in Kuro/Views or ContentView.swift" \
  "$(rg -n '^import (Supabase|PostgREST|Realtime|Auth|Functions|Storage|Helpers)\b' Kuro/Views Kuro/ContentView.swift --glob '*.swift')"

section "4 tracking tables"
report "anime_user_lists/manga_user_lists/user_lists named only in the Library transport and realtime owner" \
  "$(rg -n 'anime_user_lists|manga_user_lists|"user_lists"' Kuro --glob '*.swift' --glob '!Kuro/Composition/PostgrestLibraryTransport.swift' --glob '!Kuro/Library/LibraryRealtime.swift' | strip_comments)"

section "5 package purity"
if [[ -d Packages ]]; then
  report "no Supabase/SwiftUI/UIKit imports in Packages/*/Sources" \
    "$(rg -n '^import (Supabase|PostgREST|Realtime|Auth|Functions|Storage|SwiftUI|UIKit)\b' Packages --glob '*/Sources/**/*.swift')"
else
  echo "skip: no Packages directory"
fi

section "6 tracking writes"
report "retired facade writers not defined outside Kuro/Library/LibraryActions.swift (views excluded: private UI handlers may share a name)" \
  "$(rg -n 'func (upsertUserListEntry|addToList|incrementProgress|setUserProgress|setUserVerdict|toggleInCollection|toggleFavorite)\b' Kuro --glob '*.swift' --glob '!Kuro/Library/LibraryActions.swift' --glob '!Kuro/Views/**' | strip_comments)"
report "no direct LibraryStore writes in views (all view writes go through LibraryActions)" \
  "$(rg -n '\blibrary\.(save|apply|remove|undo)\(' Kuro/Views Kuro/ContentView.swift --glob '*.swift' | strip_comments)"

section "7 view client boundary"
# Extra arguments are scratch copies for this rule only. Unset on the normal gate run.
view_paths=(Kuro/Views Kuro/ContentView.swift)
if [[ $# -gt 0 ]]; then
  view_paths+=("$@")
fi
report "no SupabaseClient construction or client.auth/database/functions/channel call in Kuro/Views or ContentView.swift" \
  "$(rg -n 'SupabaseClient[[:space:]]*\(|\bclient\??\.(auth|database|functions|channel)\b' "${view_paths[@]}" --glob '*.swift' | strip_comments)"

echo
if [[ $fail -ne 0 ]]; then
  echo "Architecture boundaries FAILED."
  exit 1
fi
echo "Architecture boundaries PASSED."
