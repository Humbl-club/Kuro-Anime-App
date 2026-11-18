# W9 tags, custom lists and manual order: evidence (2026-11-18)

Status: implemented and locally verified on branch `worktree-agent-aa1bd7d7c70c149ac` (from `kuro/tracker-gaps` at `e4c9fe6`). The migration is **prepared, NOT applied**. The flag `library_organise_v1` is at 0 % (D-H default (a)): nothing is sent while it is off and the UI is hidden. Nothing here proves hosted behaviour.

Migration: `supabase/prepared-migrations/20261118120000_library_tags_custom_lists_v1.sql`, sha256 `a3a9104d267ff29bcc7e7f9a84970f44457e4ff446aeca90d777e9c37a3ace64` (recompute with `shasum -a 256` before approval: any later edit changes it).

## Scenario to test (feature `W9-lists.feature`)
| Scenario | Test | Result |
|---|---|---|
| Tags are private and bounded | `supabase/tests/rls/107_library_tags.sql` | PASS, 37 assertions |
| Filter Collection by tag | `LibraryTagsStoreTests/filterByTagShowsOnlyTaggedEntries` (2,000 entries, tagged titles beyond page one) | pass |
| Saving tags sends only what changed | `LibraryTagsStoreTests/organiseSaveSendsOnlyTheDelta` | pass |
| Custom lists private, bounded, mixed-medium | `rls/108_custom_lists.sql` | PASS, 60 assertions |
| Dragging writes one item row | `CustomListOrderTests/moveWritesOnePositionAndKeepsOrder` and the 108 ctid assertion `a move writes one item row` = 1 | pass |
| Imported custom lists become Kuro lists | `CustomListsStoreTests/importedCustomListNamesCanSeedLists` | pass |
| Two devices never overwrite each other | `concurrency/108_organisation_two_devices.sql` (same user, two dblink sessions) | PASS, 19 assertions |
| Stale reorder reloads, retry only on request | `CustomListsStoreTests/staleReorderReloadsAndRetriesOnlyOnRequest` | pass |
| Lists keep titles removed from the library | `CustomListsStoreTests/exportListsKeepManualOrderEmptyListsAndRemovedTitles` | pass |
| Account deletion removes tags and lists | `rls/108_custom_lists_account_deletion.sql` (+ `rls/50_account_deletion_fk_and_rpc.sql` reviewed CASCADE set) | PASS, 5 and 23 assertions |
| Collection within budget | `scripts/load/profiles/collection-with-tags-and-lists.js` (offline tests only; live qualification run NOT done) | blocked until a qualification-mode run exists |
| Tags / lists silent while the switch is off | `LibraryTagsStoreTests/flagOffSendsNoRequest`, `CustomListsStoreTests/flagOffSendsNoRequest` | pass |
| Never sent as the next account | `OrganiseCredentialLeaseTests/preDispatchSwitchSendsNoOrganiseRequestAsB` (9 request families) | pass |

## Red evidence
- DB: `--only 107_library_tags,50_account_deletion --exclude-migration 20261118120000_library_tags_custom_lists_v1.sql` -> `FAIL 107_library_tags.sql after 2 assertions ... function public.apply_title_organisation_delta_v1(unknown, integer, text[], unknown, unknown, unknown) does not exist`. 50 stays PASS in that run: its W9 CASCADE entries are conditional on the tables existing (the `feature_flag_overrides` pattern), so it cannot go red without the migration.
- DB: `--only 108_custom_lists,108_custom_list_limit_race,108_organisation_two_devices --exclude-migration ...` -> `FAIL 108_custom_lists_account_deletion.sql after 0 assertions ... function public.create_custom_list_v1(unknown) does not exist` and the same for `108_custom_lists.sql`; `TESTS: 4 test files, 0 assertions passed -> FAIL`.
- Package: `swift test --filter CustomListOrderTests` before the implementation: `cannot find type 'CustomListSlot' in scope`.
- Load profile: `node --test scripts/load/profiles/collection-with-tags-and-lists.test.js` before the profile: `Cannot find module './collection-with-tags-and-lists'`.
- App-side tasks (W9.4 to W9.7): tests were written after the implementation draft; no red run was recorded for them.

## Green evidence
- DB `--only 107_library_tags,108_custom_lists,108_custom_lists_account_deletion,108_custom_list_limit_race,108_organisation_two_devices,50_account_deletion`: 6 files, 152 assertions, `PASS (executed tests only)`, exit 4 (the pre-existing BLOCKED scope of 50 only).
- Red half in the deployed-chain fixture: `--exclude-pending --only 107_library_tags,108_custom_lists` -> 107, 108_custom_lists and 108_custom_lists_account_deletion all FAIL at the first W9 call (`function public.create_custom_list_v1(unknown) does not exist`); `TESTS: 3 test files, 2 assertions passed -> FAIL`.
- Full DB harness: 65 test files, 1,846 assertions passed; the only failing test file is `113_search_hidden_adult_count.sql` (W4: `count SQL uses a Bitmap Index Scan ... never a Seq Scan`), which passes alone (27 assertions) and fails identically in a full run with this migration excluded (1,719 assertions): not caused by W9.
- Package: `cd Packages/KuroModules && swift test` -> every run passed (12, 24, 174 and 9 tests); `CustomListOrderTests` 6 tests.
- KuroTests (own simulator, `-parallel-testing-enabled NO`): focused `LibraryTagsStoreTests` (7), `CustomListsStoreTests` (11), `OrganiseCredentialLeaseTests` (9 cases), `OrganiseRenderTests` (5, EN and DE at accessibility5), `CompositionGraphTests`, `LibraryExportFlowTests`, `NavigationEvidenceTests`, `JourneyPolicyTests`; full `KuroTests`: `Test run with 1323 tests in 203 suites passed`, `** TEST SUCCEEDED **`.
- Release: `xcodebuild -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build` -> `** BUILD SUCCEEDED **`.
- Gates: `check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh` ok; `check_bdd_traceability.sh` exit 0 (86 scenarios, 66 resolved, 0 unresolved; W9 has none pending); `test_load_profiles.sh` 77 tests pass; `deno test supabase/functions/delete-account/` 39 pass (unchanged function).

## Not run
- The W9.6 non-vacuity check (temporarily replacing the lease in `CustomListsStore.create`) was refused by the permission classifier, so it was not run. `OrganiseCredentialLeaseTests` is therefore unproven against a lease-free `create`.
- No hosted call, no live qualification run, no migration applied.

## Owner checklist (release switches)
1. Approve `20261118120000_library_tags_custom_lists_v1.sql` by name and checksum (`shasum -a 256`).
2. Apply it in one transaction; record it in history.
3. Re-run 107/108 checks read-only against the live database.
4. Run the load qualification in qualification mode with the `collection-with-tags-and-lists` profile on the populated fixture (D-H).
5. Then raise `library_organise_v1`. Until then the owners report `.unavailable` and the UI stays hidden.
