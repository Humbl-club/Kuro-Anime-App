# W2 export: evidence (2026-11-18)

Scope: everything below ran locally/offline. Nothing is deployed, no hosted call was made, the feature
stays behind `library_export_v1` at 0 %. Implemented and locally verified, NOT deployed, NOT device-accepted.

Tested commit: `a66328b79f09c70b90688f068ea21051e20e72a3` (clean tree when the runs below executed).
Acceptance record: `docs/tracker-gaps-2026-11/acceptance/W2.json`, logs under `acceptance/logs/W2-*.txt`.

## Runs (exact commands, exit codes, counts)

| id | command | exit | result |
|---|---|---|---|
| pkg-1 | `cd Packages/KuroModules && swift test` | 0 | Swift Testing runs 12 + 22 + 133 + 9 tests, all passed (XCTest "Executed 0 tests" lines are the empty XCTest bundles) |
| swift-1 | `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=2A1D0DFE-CE8D-4C90-B57B-CD025E16AF64' -parallel-testing-enabled NO -only-testing:KuroTests/LibraryExportFlowTests test` | 0 | `Test run with 33 tests in 1 suite passed`, `** TEST SUCCEEDED **` (own simulator "Kuro-Lane-W2", iPhone 17 Pro, iOS 26.2, created for this run and deleted afterwards) |
| sql-1 | `LC_ALL=en_US.UTF-8 KURO_DB_PORT=54345 bash scripts/db/run_local_db_tests.sh --only 110_export` | 0 | `PASS 110_export_identity_lookup_plan.sql 10 assertions, 0 blocked markers, 0 findings` |
| gates | `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 bash scripts/quality-gates/run_all.sh` | 4 | 14 passed, 0 failed, 2 skipped (iOS build/test, by the skip variables), 2 blocked (reported by the script as not run); exit 4 is the script's "executed gates passed but not a complete verification" code. Includes `bdd-traceability PASS` (now blocking), architecture, navigation, branded-states, docs-current-state, load-profiles |
| load-offline | `bash scripts/quality-gates/test_load_profiles.sh` | 0 | `# tests 52 / pass 52 / fail 0`, includes `export-mal-id-lookup is a Browse-class GET ...` and `combined workload names every profile with an explicit rate` |

Not run: the whole `KuroTests` target (only `LibraryExportFlowTests` on a simulator; the 13 scenarios'
Swift tags all live in that suite), `check_architecture.sh`/`check_navigation.sh`/`check_branded_states.sh`
individually (they ran inside run_all, PASS), UI tests, any `--qualify` load run.

## Red then green (Task 7 and 8)
- Load profile: `node --test scripts/load/profiles/export-mal-id-lookup.test.js` before the profile existed:
  `TypeError [Error]: Cannot read properties of undefined (reading 'budgetClass')`; after: `test_load_profiles.sh`
  52/52 pass (the frozen base-mix tests unchanged).
- SQL plan check: a plan check, not a red/green test (W2 changes no SQL). Its negative control is the
  red half: with the primary key dropped the plans become `Seq Scan` and no longer name `<medium>_pkey`
  (see `identity-lookup-plan.md`).
- Tasks 1 to 6 red/green excerpts are in the SDD task reports (`.superpowers/sdd/02-export/task-N-report.md`,
  not tracked). Task 5's red step was mutation-based, as the ledger notes.

## MAL element list (from the writer, `LibraryExportMAL.swift`)
Root `<myanimelist>`, header `<myinfo><user_export_type>`, then `<anime>` / `<manga>` entries with
`series_animedb_id`, `series_title`, `my_watched_episodes`, `my_start_date`, `my_finish_date`, `my_score`,
`my_status`, `my_comments`, `my_times_watched`, `my_rewatching` (anime) and `manga_mangadb_id`,
`manga_title`, `my_read_chapters`, `my_read_volumes`, `my_start_date`, `my_finish_date`, `my_score`,
`my_status`, `my_comments`, `my_times_read`, `my_rereadingg` (manga). This list is read from source, not
from a file exported by a real MyAnimeList account: the owner check of a real MAL manga export
(`manga_*` names, `my_rereadingg`) is still open. The Kuro parser accepts both `manga_*` and `series_*`.

## Baseline and plan check
`baseline.md` (2,000 titles, medians 0.037 / 0.032 / 0.064 s for MAL XML / CSV / JSON on a simulator) and
`identity-lookup-plan.md` (primary-key Index Scan for 500 ids, anon and authenticated, both media).

## Acceptance state
`bash scripts/quality-gates/check_bdd_traceability.sh --accepted W2` (on the tested commit plus the record):
```
W2: W2-export.feature: The id lookup stays inside the Browse budget: not accepted: blocked
NOT accepted W2: 12/13 pass, 1 findings
unresolved gate: @load:export-mal-id-lookup: needs an owner-approved --qualify run ...
exit=1
```
W2 is NOT accepted until a qualification run exists and this check exits 0.

## Open owner questions and manual checks
- I-3 (manual, before rollout): on a real device check that `ShareLink` shares the prepared files with
  complete file protection, and that dismissing the sheet (`onDisappear` -> `discardFiles()`) deletes the
  export folder. Not simulated here; no `owner` manual run is recorded.
- Owner-approved `--qualify` run of `tracker-gaps-combined` (600 s; `export-mal-id-lookup` 0.2 rps = 120
  completions, 40 per covered library size) is required for the `@load` scenario and for D-H (b).
- Confirm the 2 s per format gate proposed in `baseline.md`; a device baseline is missing.
- Owner check of one real MAL manga export file (element names).
- Legal page text (privacy list items) must be published together with the flag rollout.
- Deferred minors from the ledger remain (see the SDD ledger), none blocking.
