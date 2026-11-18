# W6 evidence (2026-11-18, lane worktree on origin/kuro/tracker-gaps b5b049e)

Local checks only. Nothing applied, deployed or called hosted. Reviewed membership is empty in production
(repository evidence, not queried), so W6 is visually inert until owner decision D-G.

## Scenario to test to result
| Scenario (W6-grouping.feature) | Test | Result |
|---|---|---|
| Seasons share a row | `SeriesListGroupingTests/reviewedContinuityMembersShareOneRow` | pass (swift test) |
| Relation without continuity not merged | `unreviewedRelationsStayOwnRows`, `onlyVerifiedApprovedSameMediumMembershipJoins` | pass |
| Re-rating a finished season | `activeMemberDecidesGroupStatus`, `groupStatusFallsBackWithoutActiveMember`, `advanceTargetIsAlwaysTheAnchor` | pass |
| +1 advances the season I'm on | `advanceTargetsActiveMember` | pass |
| Grouping is display only | `groupingNeverChangesEntries` | pass |
| Expanding a series | `SeriesGroupingFolioTests/expandShowsEverySeasonWithOwnStatus` (retagged, see deviations) | pass (KuroTests) |
| Turning grouping off | `SeriesGroupingCollectionTests/groupSeasonsSwitchIsRememberedPerAccount` | pass |
| Large library fast | `groupingTwoThousandEntriesWithinBudget` (host release median 2.69 ms; BASELINE.md) | pass |
| Reviewed membership read through an index | `supabase/tests/rls/111_series_membership_read.sql` | pass, 21 assertions (local DB harness) |
| Membership read in Browse budget | profile `collection-series-membership` (browse, 750 ms, 1 rps) | `blocked`: no owner-approved `--qualify` run and no published member ids |
| Flag off sends nothing | `SeriesGroupingCollectionTests/flagOffSendsNoRequest` (positive control `addingATitleReadsItsMembershipOnceWhenOn`) | pass |

Other pins: `SeriesMembershipReaderTests` (6), `memberHydrationFromPreviousAccountIsDropped`,
`membershipReadNeverSendsPreviousAccountsIdsWithNewCredentials`, `selectedSeasonOfGroupIsWrittenByBatch`,
`prepareRunsAgainWhenLibraryLoads`, `groupRowRendersAtLargestTypeSize`.

## Commands and outcomes
- `cd Packages/KuroModules && swift test` -> pass; KuroLibrary suite run with 168 tests (10 in SeriesListGroupingTests).
- Red before green: SeriesListGroupingTests failed to compile with the source removed
  (`cannot find type 'SeriesMembership' in scope`); reader tests failed to compile before `import KuroLibrary` was added.
- Non-vacuity: `proposedBudget = .microseconds(1)` -> `Expectation failed: median <= SeriesListGrouping.proposedBudget`
  (reverted). SQL: removing `s.continuity = 'verified'` from the filter query -> `TEST FAIL ... (expected 296, got 298)`
  (restored). `--exclude-migration 20261007040000_series_home_foundation_v1.sql` -> test BLOCKED, not run, not PASS.
- `LC_ALL=en_US.UTF-8 KURO_DB_PORT=54360 bash scripts/db/run_local_db_tests.sh --only 111_series,112_library_2000`
  -> 111: 21 assertions, 112: 7 assertions, `TESTS : 2 test files, 28 assertions passed ... PASS`.
- `xcodebuild ... -destination id=<own iPhone 17 Pro, iOS 26.2> test -parallel-testing-enabled NO -only-testing:KuroTests`
  -> `Test run with 1288 tests in 197 suites passed`, `** TEST SUCCEEDED **`.
- Gates: check_architecture, check_navigation, check_branded_states pass; check_bdd_traceability exits 0
  (86 scenarios, 52 resolved, 0 unresolved; W6 all 11 resolved); `test_load_profiles.sh` 66 pass, 0 fail.

## SQL finding
`series`, `series_sections`, `series_entry_spans` get table-level WRITE grants from Supabase default privileges
(the migration grants SELECT and revokes nothing); only RLS (select-only policy, no write policy) keeps clients from
writing. Test 111 therefore asserts behaviour as anon/authenticated (insert denied 42501, update/delete touch 0 rows)
instead of `has_table_privilege`. Not a W6 change; flagged for the Identity/DB owner.

## Not proven here
Real PostgREST (the `!hint!inner` embed form) is unproven locally: the stub server only records the request. Simulator
baseline of the 2,000-entry budget; manual simulator walk with a fixture membership; hosted/TestFlight behaviour.

## Open questions
Q1 (spec section 1 vs section 3 gate): W6 ships dark at 0 %. D-G: who reviews membership (open). Outcome metric for the
learning goal has no named event, denominator or reviewer (no telemetry added).
