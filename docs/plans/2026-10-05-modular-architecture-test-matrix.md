# Kuro modular architecture: G5 test-to-risk matrix

Companion to the [plan](2026-10-05-modular-architecture-plan.md) (§3 "Required risk-to-test matrix", §8 evidence rules) and the [execution ledger](2026-10-05-modular-architecture-execution-ledger.md). This document maps each §3 risk row to executed tests and evidence. It records no gate as passed: only the ledger records gate results.

- **Gate:** G5 (meaningful verification), test-to-risk part.
- **Prepared by:** Senior QA Engineer (verification agent). This agent was read-only on code and tests and was not the implementer of any production lane.
- **Source judged:** branch `kuro/taste-overhaul`, HEAD `471c609943d2374c6dda940aebdfde2fcb077d50`, dirty tree (about 20 D / 67 M / 135 ??), read on 2026-10-05 after 10:50.
- **Commands run for this document:** `cd Packages/KuroModules && swift test list`, `xcrun xcresulttool get test-results tests` on the existing final bundle, and `rg`/`sed` reads. No `xcodebuild`, simulator, deno or DB run was made.
- **Evidence identity warning:** the most recent full app run (`scratchpad/final/app-tests.xcresult`, 10:43, 275/275) predates the `Kuro/Taste/TasteStore.swift` edit at 10:47. `final/07-taste-fix.log` used a non-existent `-only-testing` type and executed **0 tests** (review-final, BLOCKING 1), so it is not evidence. Counts and statuses below must be re-recorded against the lead's frozen-tree re-run (§7).
- **Docs refresh after the final E8 lanes (2026-10-05, docs editor; no test run for this update):** row 13 moves from NOT COVERED to PARTIAL (pure `RoutePolicy` via `RoutingTests` only), and the new `RoutingTests`, `ConciergeRoutingTests`, `DetailProviderLinksTests` and `ImportReconcilerTests` pre-selection/auto-apply-plan cases are added to the rows they cover (sections 3 and 4). The tautological "Kuro App Tests" suite was deleted. Test totals: see the ledger final section. Every "not proven" statement below still stands.

## 1. Summary

The 17 rows have one primary status each.

| Status | Rows | Count |
| --- | --- | ---: |
| COVERED | 1 Stale account fetch, 2 Derived state, 3 Obsolete task cleanup, 5 Subscriptions/reminders, 7 Library fields, 8 Mutation sequencing, 11 Imports/assistant rules, 12 Catalog/paging, 15 Packages/build settings | 9 |
| PARTIAL | 4 Session entry points, 6 Deletion cleanup\*, 9 Adapter compatibility, 10 RLS and revocation\*, 13 Shared UI and navigation (pure route policy only), 14 Taste/device intelligence, 16 Edge/worker extraction, 17 Request/subscription regression | 8 |
| NOT COVERED | none (row 13 was NOT COVERED until the routes lane) | 0 |
| BLOCKED (whole row) | none | 0 |

\* These rows also have legs that are BLOCKED by the environment: Supabase Storage, GoTrue, Realtime and PostgREST, migrations that do not replay, and production parity.

**How a status was assigned.** The yardstick is the plan's "smallest sufficient check" column for that row.
- **COVERED:** that check executed on the integrated source, with its caveats disclosed.
- **PARTIAL:** some legs of the check executed.
- **NOT COVERED:** the check never ran, and no executed test reaches the component.
- **BLOCKED:** the check cannot run for a stated environment reason.

### Three most important gaps

1. **No UI, navigation or device behaviour was executed (row 13).**
   - Only the pure route policy (`RoutingTests`: route ids, slot update/dedupe, destination mapping) is unit-tested; the `.routePresenter()` wiring and the 16 device smoke journeys (`docs/modules/README.md`) were never run.
   - No save, detail or club route ran through the views.
   - No gesture arbitration, focus or selection, sheet timing, toast or visual composition was observed.
   - The only UI tests (`KuroUITests`) are sleep-based App Store screenshot flows. They launch against the configured production backend, so §3 rules them out as a baseline, and they were not run.
2. **Authorization is proven only on an audited local PostgreSQL fixture (row 10).**
   - This is not migration replay: 62 of 238 files fail in baseline-first mode.
   - Supabase Realtime, PostgREST, Storage and GoTrue are not exercised.
   - The fixture shows that revocation is not sticky: a removed member can rejoin with the same invite code (R5, open owner decision). That is a direct miss on "denied access remains denied after revocation".
   - The DB-level pending response/event scenario was never executed.
   - The R1–R3 fixes are prepared but not deployed.
3. **SDK-bound session legs are covered only by funnel entry tests (row 4).**
   - The uncovered legs are restore (`startLaunchRestore`), sign-up, Apple sign-in, same-user callback `setSession` and the SDK listener→`AuthEventKind` mapping.
   - No test would fail if one of them stopped calling the session funnel.
   - Only email sign-in, failed sign-in, sign-out, deletion and the foreign-user callback run through the real SDK client.

## 2. Legend

**How the test executes production code**
- **SDK-stub**: the real supabase-swift client and the real owner/store code. Every HTTP request is answered in-process by `KuroTests/StubPostgREST.swift` (a URLProtocol stub with no network). The answers are hand-written or SQL-derived fixtures, not live PostgREST.
- **Pkg**: a SwiftPM package test (`Packages/KuroModules`) of the real `LibraryStore`, `SupabaseLibraryBackend` or `AccountScopedLoads`. External outcomes come from a controlled backend or transport (`ControlledBackend`, `RecordingTransport`) that holds no policy.
- **Seam**: real owner code with a fake at an injected seam: `FakeLibraryBackend`, `FakeClubChannels`, `FakeUserListChannels`, `FakeNotificationCenter`, an injected `NotificationCenter` or an injected clock.
- **Deno**: the real edge handler or pure-rule module under `deno test`. Supabase is replaced by `_shared/test_fake_supabase.ts` or `delete-account/fake_backend.ts`, which model only boundary outcomes such as NOT NULL, CHECK, merge-upsert and RLS denial.
- **SQL**: `scripts/db/run_local_db_tests.sh`, a throwaway PostgreSQL 17 cluster built from the audited baseline-first fixture. Assertions run as `SET LOCAL ROLE authenticated` with `request.jwt.claims`. There is no PostgREST, Realtime or Storage.
- **Rule**: a pure production rule called directly, for example `ImportReconciler`, `TrackingDraft`, `AuthCallbackGuard`, `ClubDetailLifecycle`, `router.ts` or `rules.ts`.

**Kind of evidence**
- **RF**: red-first. The test was observed failing on the pre-repair code, then passing.
- **MC**: mutation-checked. A production guard was removed in a scratch window, the mapped test went red, and the code was restored. The scripts check that no `MUTATION` markers remain.
- **CF**: contract fixture, meaning exact request and response shapes.
- **INT**: integration across owners: the composition graph, the session funnel, sinks.
- **REG**: a regression or characterization pin with no red run.

Lane reports and reviews cited below live in the session scratchpad (`/private/tmp/claude-501/-Users-max-Kuro-Anime-App/ad3e7375-8f05-45ba-b10c-8ecffc929145/scratchpad/`) and are not part of the repo.

**Command shorthands**
- **`APP <Types>`** = `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:KuroTests/<Type> [-only-testing:KuroTests/<Type> …]`
  - `-only-testing` takes the **struct name**, not the file name or the suite title. A wrong name silently runs 0 tests, as `07-taste-fix` did.
- **`PKG <Type>`** = `cd Packages/KuroModules && swift test --filter <Type>`
- **`DENO <dir>`** = `cd supabase/functions/<dir> && deno test`
- **`SQL [--only <name>]`** = `bash scripts/db/run_local_db_tests.sh [--only <name>]`

## 3. Matrix

### Row 1: Stale account fetch (COVERED)
**Success parameter.** A cannot change B's data, lookups, error or loading state, or active handles. B starts its own work.

**Tests**
- **`StaleUserListsCompletionTests` › "A's late completion cannot change B's state; B runs its own fetch"** (`staleCompletionIsDropped`, success/failure).
  - Seam (`FakeLibraryBackend` with `ControlledResponses`) through the real composition graph and session funnel.
  - **RF:** `e1/red.xcresult` failed both outcomes on the pre-E1 code (A's rows and error landed in B; B never requested).
- **`LibraryStoreSequencingTests.accountSwitchMidFlight(previousAccountFails:)`, `resetInvalidatesWorkForTheSameContext`, `undoIsBoundToTheChangesAccount`**: Pkg. **MC:** M3, M18 and M19 (`e3/library-package-report.md` §7).
- **`LibraryStoreLoadStateTests.accountSwitchMidLoad`**: Pkg. **MC:** P1–P4 (E6c1 report).
- **Releases.** `ReleasesContractTests`:
  - "A -> B: A's late upcoming answer never lands…" (the funnel cancels the request);
  - "Stale guard: A's upcoming answer that arrives after B became current…" (delivered answer, success and failure).
  - SDK-stub. **MC:** E5b fix-round mutation, 4 guards → 4 tests red.
- **Social.** `SocialActivityContractTests`: A→B, the stale guard and late friends' activity. SDK-stub, **MC** (E5b).
- **Collection.** `CollectionContractTests`: A→B through the funnel (3 cases) and the stale guard ({feed, cards, manga} × {success, 503}). SDK-stub.
  - **RF:** `E5c-mutA` restored the pre-extraction guard and the tests went red.
  - **MC:** 17 of 18 mutants killed. The surviving M19/F is an equivalent defence in depth (review-e5a/review-collection §B).
- **Discovery.** `DiscoveryContractTests.lateAnswerOfEndedAccountIsDropped`: 6 surfaces × {none, switch, sign-out}. SDK-stub. **MC:** M1 turned 10 cases red.
- **Assistant.**
  - `ImportsContractTests`: parse cache; "A's apply/Undo finishing after B signed in…".
  - `ConciergeContractTests`: recommend cache.
  - `TasteContractTests`: "Personalised reads… A's answer arriving after B signed in is not handed out".
  - SDK-stub. **RF:** E6b red 3/3. **MC:** Run A and the r1 mutations.
- **Clubs and providers.**
  - `ClubsAccountTransitionTests` (2): **MC** (E6a).
  - `ProviderAvailabilityContractTests` › "Private: A's services… cleared on A -> B": **MC** (E5b test 5).

**Command**
- `APP StaleUserListsCompletionTests ReleasesContractTests SocialActivityContractTests CollectionContractTests DiscoveryContractTests ImportsContractTests ConciergeContractTests TasteContractTests ClubsAccountTransitionTests ProviderAvailabilityContractTests`
- `PKG LibraryStoreSequencingTests`
- `PKG LibraryStoreLoadStateTests`

**Not proven**
- These guards are pinned only via the cancel path, or not at all, because a deterministic test cannot reach the arrive-before-resume window:
  - `DiscoveryStore` bundle post-await guard (~:121). review-e5a round 2 asked for an owner-level test; it was not added.
  - `SearchStore` success-path and catch checks (~165/182/255/371).
  - `ClubsStore.fetchClubBundle` post-await `isCurrent`.
- Everything runs in-memory with the stub transport, not real network timing.

### Row 2: Derived state and private caches (COVERED)
**Success parameter.** No prior-account entry, badge, club projection, preference or private cache is read as B's state.

**Tests**
- **`PrivateStateResetTests` › "No private category or preference of A is visible after a transition"** (switch and sign-out).
  - It seeds every inventoried private category: Library projection, Collection pages/cursors/flags/error, upcoming/countdown/backoff, user-keyed Discover bundle, parse/recommend caches, club bundle, myClubs, unseen badge, friend counts, streaming services, club shared providers, scoped prefs and legacy keys.
  - The integration route is the real `AppComposition.testingGraph` and its funnel. Seam/INT.
- **`PrivateStateResetTests` › "Deleting an account removes its scoped preferences"**. This exercises the helper, not `deleteAccount` (review-e1, nit kept). `SessionSDKTests` covers the real deletion path.
- **`SessionEntryPointTests` › "A different user or a sign-out applies the same reset policy"** (4 entries).
- **`CompositionGraphTests` › "The session funnel clears exactly the graph's account-scoped owners…"** (production and testing graph): an exact membership and order check.
  - **MC:** E6c1 MA3/MB2 and E6c2 M2/M11 (owner unregistered → reset or LT-30 red); E5c mutD (Collection missing from the list → leak test red).
- **`TelemetryOwnerTests` › "LT-30: an ended account's queued events are dropped…"**. **RF:** `E6c2-red-telemetry` showed A's events sent after A ended. **MC:** M2, M14.
- **`ClubsViewRulesTests` › "An account transition changes every club's signal…"**. **RF:** E6a r1 (0→0). **MC:** `accountSignal` bump.
- **`DiscoveryContractTests`:** "Personalised bundle cache is keyed by user…" and "…is gone after A -> B".

**Command**
- `APP PrivateStateResetTests SessionEntryPointTests CompositionGraphTests TelemetryOwnerTests ClubsViewRulesTests DiscoveryContractTests`

**Not proven**
- View-held `@State` copies (club detail bundle and optimistic votes, reactions, sheet drafts) are assumed to unmount on the `isAuthenticated` flip. That is not tested, and no UI ran.
- No persisted private store other than `UserDefaults` exists to test.
- The public caches that intentionally survive (catalog and provider registry) are pinned by `CatalogCacheContractTests`/`ProviderAvailabilityContractTests`.

### Row 3: Obsolete task cleanup (COVERED)
**Success parameter.** An old completion cannot clear or cancel the new handle.

**Tests**
- **Pkg:**
  - `AccountScopedLoadsTests.predecessorCannotClearSuccessor`, `joinsOnlySameKeyAndContext`: **MC** M15/M16.
  - `runFreshStartsNewWorkAndBecomesJoinable`: **MC**, a joining `runFresh` hits the time limit.
- **`BannerCenterTests` › "Newest wins at once; a replaced message never clears its successor…"**: **MC** M4/M5 (E6c2).
- **`LibraryRealtimeTests`:**
  - "Old session's teardown never stops a new account's channel";
  - "Same user signs in again before the old teardown ran…".
  - Seam. **MC:** E6c1 MA4/MB4.
- **`ClubsRealtimeSerializationTests`** (3): re-subscribe waits for the pending teardown; two subscribes leave one channel; stop during subscribe. Seam. **RF:** E6a r1 red 7/7. **MC:** rounds A/B.
- **`CollectionContractTests`:** the "Latest wins…" tests (2) and "Library sink: a second change… cancels it (latest wins)". **MC** (E5c).
- **`LibraryFacadeTests`:**
  - "Cancelling a caller (e.g. the realtime debounce) never cancels the Library refresh it started";
  - "A refresh after a server-side write never joins a read that started before the write".
- **`TasteContractTests`:** the outbox supersede, stale-guard and foreground-drain tests. **MC:** E6b runs B–F.
- **`DetailProviderLinksTests`** › "A superseded (cancelled) resolution returns nil, so the page never publishes it over the newer run's links" (detail lane, D3).

**Command**
- `PKG AccountScopedLoadsTests`
- `APP BannerCenterTests LibraryRealtimeTests ClubsRealtimeSerializationTests CollectionContractTests LibraryFacadeTests TasteContractTests DetailProviderLinksTests`

**Not proven**
- Real SDK channel reuse by topic is established by reading the SDK, not observed. The fake channels model the teardown order.

### Row 4: Session entry points (PARTIAL)
**Success parameter.** All paths use the same lifecycle policy, and a same-account token refresh does not needlessly erase state.

**Tests**
- **`SessionEntryPointTests`:**
  - "A different user or a sign-out applies the same reset policy": `applySession`, SDK `.signedIn`, `endSession`, SDK `.signedOut`.
  - "Same-user refresh and stale SDK events keep the account context and state" (5 events).
  - Seam (funnel-level).
- **`AuthCallbackGuardTests` › "Decision table"** (12 rows; Rule) and "The service rejects such a callback before any session change…". The rows come from the fix for review-e1 B1.
- **`SessionSDKTests`** (7), SDK-stub through the real supabase-swift auth client:
  - email sign-in and failed sign-in;
  - sign-out (R-E1-3);
  - sign-out and deletion reach the SDK before the channel teardown (**MC** E8-C1 MS1/MS2);
  - deletion only when confirmed (**MC** E6c1 MD1/MD3);
  - foreign callback (**MC** MD5).
- **`AccountSessionCoordinatorTests.transitionTable`**: Pkg. **MC:** M17 (case-insensitive user id).
- **`PendingReminderTests`** covers the failed-restore variants.

**Command**
- `APP SessionEntryPointTests AuthCallbackGuardTests SessionSDKTests PendingReminderTests`
- `PKG AccountSessionCoordinatorTests`

**Status reason: PARTIAL**
- Restore (`SessionController.startLaunchRestore`, production only), sign-up, Apple, a same-user callback through `setSession`, and the listener's SDK-event→`AuthEventKind` mapping are proven only by funnel-level tests.
- review-e1 (E1 report §9) said: "Funnel-level entry-point tests cannot catch an SDK-bound path that stops calling the funnel". review-e6c1 (NITS) lists the same untested SDK legs.
- No PKCE or nonce protection is claimed. The signed-out login-CSRF residual (R-E1-2) remains.

### Row 5: Subscriptions and local reminders (COVERED, seam level)
**Success parameter.** Private listeners stop, late events are rejected, and prior-account reminders are removed or explicitly scoped.

**Tests**
- **`LateRealtimeEventTests` › "Events captured under an ended account schedule no refresh; current ones do"**. Added for review-e1 S3; it checks debounce-task creation.
- **`LibraryRealtimeTests`** (3) and **`ClubsRealtimeTests`** (2): subscribe → event → one re-read; session end tears down; late events schedule nothing; B re-subscribes; club change drops club-1's late event. Seam. **MC:** E6a channel-generation guard (Clubs); E6c1 MA5 (Library realtime late-event).
- **`ClubsRealtimeSerializationTests`** (3): the remount and teardown scenarios. **RF/MC** (E6a r1).
- **`ClubsViewRulesTests` › "A club view's disappear-stop is keyed…"** and **`ClubDetailLifecycleRulesTests`** (pure rule). **MC:** 2 red (E6a-V fix1).
- **`PendingReminderTests` › "Reminders go with their account…"** (7 transitions).
  - Uses the `FakeNotificationCenter` seam.
  - The owner marker `com.kuro.airingReminders.owner` is the explicit scoping. Reminder ids are not account-scoped.
- **`LibraryFacadeTests`:**
  - "Releases: a change that leaves an anime tracked re-arms its reminders, manga never; removal cancels" (from review-e3 B1);
  - "N1: a sign-in during the old session's teardown tail keeps the new account's reminders".
- **`ReleasesContractTests` › "Countdown timer: stopped by the session end and by a switch…"**: **MC** (E5b).

**Command**
- `APP LateRealtimeEventTests LibraryRealtimeTests ClubsRealtimeTests ClubsRealtimeSerializationTests ClubsViewRulesTests ClubDetailLifecycleRulesTests PendingReminderTests LibraryFacadeTests ReleasesContractTests`

**Not proven**
- Supabase Realtime delivery and the production channel wrappers (`SupabaseClubChannel`, `SupabaseUserListChannel`) never run.
- `UNUserNotificationCenter` is not exercised.
- A revoked notification permission is never noticed (open; reminders are silently undelivered).
- Club subscriptions to rail items, votes and reactions are unfiltered (open product item).
- `PendingReminderTests` has no recorded red or mutation run (REG).

### Row 6: Deletion cleanup (PARTIAL; Storage/GoTrue/latest-RPC legs BLOCKED)
**Success parameter.** A required cleanup failure cannot return success, retries are safe, and local SDK session cleanup is verified.

**Tests**
- **Deno `delete-account/deletion_test.ts`** (16). Examples:
  - "a failing list delete reports failure and NEVER deletes the auth user";
  - "each user-keyed table is individually required";
  - "retry after a partial failure finishes the job (idempotent)";
  - "a storage backend that reports success but removes nothing fails closed".
- **Deno `delete-account/handler_test.ts`** (17): the real handler and real adapters over fake supabase-js clients. Examples:
  - "required cleanup failure is a non-2xx… with NO success flag";
  - "end to end through handler + real adapters + real policy: client errors can no longer produce success".
  - REG against HEAD's swallow-all behaviour; the reviewer read and verified it (review-e7: 49/49 including apply/undo).
- **SQL `50_account_deletion_fk_and_rpc.sql`**: 26 assertions, 2 BLOCKED, 2 findings. It covers FK CASCADE/SET NULL rules to `auth.users`, `delete_user_concierge_data` authorization, and an emulated deletion run showing what survives.
- **`SessionSDKTests`:**
  - "Account deletion: only a confirmed deletion ends the session and removes the SDK session; a failure leaves session, identity and Library untouched (retryable)" (confirmed / 500 / `success:false`);
  - "deletionReachesTheSDKBeforeTheChannelTeardown" (scope `local`).
  - SDK-stub. **MC:** MD1/MD3.

**Command**
- `DENO delete-account`
- `SQL --only deletion`
- `APP SessionSDKTests`

**BLOCKED legs**
- Supabase Storage objects (`storage.objects` is a stub) and GoTrue admin delete (stub `auth.users`) are covered only by fakes.
- The newest `delete_user_concierge_data` (`20260806020000`) does not replay, so the fixture holds the `20260305153000` body.

**Not proven**
- Nothing is deployed.
- In production, grants (`has_table_privilege('service_role', …, 'DELETE')`), the `media` bucket and the comment tables are unverified (R-E7-2; ledger "Prepared, NOT deployed").
- Leftovers on account deletion: an orphaned solo club, and ownership transfer (open finding in the harness).

### Row 7: Library fields and identity (COVERED)
**Success parameter.** Correct target and scale; a progress intent does not overwrite unrelated fields; remove and Undo semantics stay explicit.

**Tests**
- **`LibraryStoreFieldTests`** (8; Pkg), including:
  - `progressEditKeepsUnrelatedFields`, `equalNumericIdsStayIndependent`;
  - `legacyScoresAreRejected` (0, 11, 80, 100, −1), `ratingProjectionAndFavourite`;
  - `invalidEditsNeverReachTheBackend`, `saveNeverOverwrites`, `editOfRemovedEntry`.
  - **MC:** M5, M11, M12.
- **`SupabaseLibraryBackendRequestTests`** (7) and **`SupabaseLibraryBackendMappingTests`** (3); Pkg:
  - only edited columns, explicit null, rating 1…10;
  - insert-ignore-duplicates with the `on_conflict` target;
  - `equalIdsUseDistinctTables`.
  - **MC:** M9, M10, M13, M14, M20.
- **`LibraryHTTPContractTests`:** W-04, W-07, W-10, W-02/W-13, W-06, "anime 7 and manga 7 stay distinct". SDK-stub, exact PATCH/POST/DELETE bodies.
  - **RF:** `e3/services/red-old-writers.xcresult`, 5 of 6 failed on the old writers.
  - The writers behind W-07, W-02/W-13 and W-06 were since deleted (E8-C2). The live tests pin the `LibraryActions` primitive path.
  - The W-10 repoint is not identical: it now asserts `UserRating(value: 80) == nil` and that no body carries `rating` (E8-C2 report §2).
- **`PostgrestLibraryTransportTests`** (5): the real SDK transport, exact filters, microsecond timestamps.
- **`TrackingDraftTests`** (14) and **`QuickStatusChangeTests`** (5); Rule.
  - **MC:** E3-V restoring `score*10`, verdict `.clear` and no note clear turned 5 tests (14 runs) red.
  - The quick-status tests come from review-e3v SF-2.
- **`LibraryStoreUndoTests`** (5; Pkg). **MC:** M6, M8.
- **`LibraryActionsPrimitiveTests`** (4). **MC:** E8-C1 P1–P3.
- **SQL `10_user_lists.sql`**: the same numeric id in anime and manga stays distinct; a case-variant `user_id` fails closed.

**Command**
- `PKG LibraryStoreFieldTests`
- `PKG SupabaseLibraryBackend`
- `PKG LibraryStoreUndoTests`
- `APP LibraryHTTPContractTests PostgrestLibraryTransportTests TrackingDraftTests QuickStatusChangeTests LibraryActionsPrimitiveTests`
- `SQL --only user_lists`

**Not proven**
- **F1, `user_id` casing:** the app sends the upper-case `uuidString` verbatim. The fixture RLS (`auth.uid()::text`) rejects a case-variant id. Production behaviour is unverified in either direction (R-E3-4; a read-only production check is pending).

### Row 8: Mutation sequencing (COVERED)
**Success parameter.** One writer; a stale refresh cannot replace newer accepted state; errors retain actionable state.

**Tests**
- **`LibraryStoreSequencingTests`** (9; Pkg, the real coordinator):
  - `overlappingEditsRunFIFO`;
  - `staleRefreshCannotOverwriteNewerMutation` (3 race orders);
  - `olderRefreshCannotReplaceNewer`;
  - `failureRollsBack`, `failureWithdrawsOnlyItsOwnIntent`, `failedRefreshKeepsProjection`.
  - **MC:** M1, M2, M4, M8.
- **`LibraryFacadeTests`:** "A write that outlives its account is rejected…", the toggle rollback, "Change sinks fire once per applied change…", and the server-write refresh freshness test.
- **`LibraryViewActionsTests`:** second tap ignored, add-then-remove, failed toggle rolls back. **MC:** E8-C2 T1/T2.
- **`ClubsLibraryChangeTests`** (2): a bundle re-read never joins a pre-change load, and an older answer never replaces a fresh one. **MC** (E6a r1).
- **`check_architecture.sh` check 6** is a static check: no direct `LibraryStore` writes from views, and the writers are defined only in `LibraryActions`.

**Command**
- `PKG LibraryStoreSequencingTests`
- `APP LibraryFacadeTests LibraryViewActionsTests ClubsLibraryChangeTests`
- `bash scripts/quality-gates/check_architecture.sh`

**Not proven**
- `try? await library.refresh()` in ContentView and three views drops the refresh error (review-final SHOULD-FIX 6). User-initiated refresh failures there are not surfaced, and no test pins it.
- There is no durable outbox or restart behaviour, and none is claimed.

### Row 9: Adapter compatibility (PARTIAL)
**Success parameter.** Request fields, auth ownership, null and optional values, errors and responses match the declared contract.

**Tests (real adapter against controlled transport)**
- **Library:**
  - `PostgrestLibraryTransportTests` (5) through the real SDK, including "SDK failures map to typed library errors" (the S5 codes, from review-e3 S5);
  - `SupabaseLibraryBackendRequestTests` and `SupabaseLibraryBackendMappingTests` (Pkg, `RecordingTransport`).
- **Clubs:**
  - `ClubsRPCContractTests` (5): exact parameters per RPC; typed `ClubError` for every throwing method (G3). **MC:** E8-C1 A–E.
  - `ClubErrorTests` (9): deployed answers decoded as the SDK decodes them, with the verbatim `LegacyStoreRule` as oracle.
  - **RF probe** (E6a): PostgREST's `details` arrives as `PostgrestError.detail == nil`. This is pinned as a tripwire, not fixed.
- **Request shapes:**
  - Assistant: `ImportsContractTests`, `ConciergeContractTests`, `TasteContractTests` (parse, apply, undo, AniList, warmup, feedback, deck, NEW TO YOU, profile, realm, signal; 429 → typed rate-limit error).
  - Releases: `ReleasesContractTests` (the `user_airing_next` filter, window, limit and order).
  - Telemetry: `TelemetryOwnerTests` › "Outbound link: one record_outbound_link RPC… (no user id from the client)".
- **Auth:** `SessionSDKTests` covers the token, logout scope and `delete-account` body.
- **Edge side (Deno):**
  - `delete-account/handler_test.ts` › "adapters: …" (5) and "createPlatform: …" (2);
  - `concierge-apply` › "identity: only the JWT user is written…";
  - `concierge-undo` › "identity: undo only acts for the JWT user…".

**Command**
- `APP PostgrestLibraryTransportTests ClubsRPCContractTests ClubErrorTests ImportsContractTests ConciergeContractTests TasteContractTests ReleasesContractTests TelemetryOwnerTests SessionSDKTests`
- `PKG SupabaseLibraryBackend`
- `DENO delete-account`, `DENO concierge-apply`, `DENO concierge-undo`

**Status reason: PARTIAL**
- **Auth ownership on the client side is unasserted.** `StubPostgREST` never checks the `Authorization` or `apikey` headers. JWT-derived identity is proven only for the three edge handlers.
- **The production Realtime wrappers are never executed.**
- **Responses are fixtures, not live PostgREST.** A known contract defect is pinned rather than fixed: the SDK decodes `detail` while PostgREST sends `details`, so structured DETAIL codes never reach the app (ledger "New findings from the Clubs lane" (1); CLAUDE.md's "Structured RPC error handling" pattern is therefore broken).

### Row 10: RLS and revocation (PARTIAL; Realtime, PostgREST and production-parity legs BLOCKED)
**Success parameter.** Allowed operations succeed; denied access remains denied after revocation; private cached presentation is invalidated.

**Tests**
- **SQL harness**: 10 files, 321 assertions, all `PASS`, from `final/05-db-harness.log`.

  | File | Assertions | Blocked | Findings |
  | --- | ---: | ---: | ---: |
  | `00_harness_and_preconditions.sql` (non-bypass roles, claim path, negative controls) | 14 | 0 | 0 |
  | `10_user_lists.sql` | 34 | 1 | 1 |
  | `20_clubs.sql` (owner / member / outsider / anon / **REVOKED** via owner removal and `leave_club`) | 84 | 0 | 3 |
  | `30_social_comments.sql` (club-mate, stranger, leaver, archived) | 31 | 0 | 0 |
  | `40_streaming_and_taste.sql` | 31 | 2 | 0 |
  | `50_account_deletion_fk_and_rpc.sql` | 26 | 2 | 2 |
  | `60_club_role_guard.sql` (R1) | 34 | 0 | 0 |
  | `61_club_rail_insert_policy.sql` (R2) | 13 | 0 | 0 |
  | `62_comment_reaction_visibility.sql` (R3) | 18 | 0 | 0 |
  | `63_club_privacy_levels_and_open_items.sql` (R4/R5 probes) | 36 | 0 | 3 |

  - **RF** for R1–R3: `--exclude-pending` fails exactly files 60/61/62 at their first denial assertion. The lead observed this (ledger G0); review-e7 did not run it.
  - `test_guard_env.sh` refuses production targets.
- **Client-side revocation and pending responses (SDK-stub):**
  - `ClubsRevocationTests` (2): membership loss drops the bundle, the myClubs row, the friend projection, shared providers and the channel; an in-flight bundle of a left club is dropped. **RF:** E6a red 3/3.
  - `ClubsRevocationCounterTests` (3): a pre-revocation myClubs read or loading snapshot is dropped; leave and rejoin within one round trip. **RF:** E6a r1. **MC.**
  - `ProviderAvailabilityContractTests` › "invalidateClubSharedProviders(clubId:)…" and `SocialActivityContractTests` › "invalidateFriendProjection()…". **MC** (E5b).
  - `ClubsViewRulesTests` and `ClubDetailLifecycleRulesTests` (Rule). **MC.**

**Command**
- `SQL`, plus `bash scripts/db/run_local_db_tests.sh --exclude-pending` (expected exit 1, files 60–62 failing)
- `bash scripts/db/test_guard_env.sh`
- `APP ClubsRevocationTests ClubsRevocationCounterTests ProviderAvailabilityContractTests SocialActivityContractTests ClubsViewRulesTests ClubDetailLifecycleRulesTests`

**Status reason: PARTIAL**
- **Fixture only.** RLS is proven only on the audited fixture: 176 of 238 files apply baseline-first, and 62 fail. This is not migration replay or production equality.
- **The DB pending response/event scenario was not executed** (review-final SHOULD-FIX 4). The client-side pending cases run against stubbed answers.
- **R5:** revocation is not sticky; a removed member can `join_club()` again with the same invite code.
- **R4:** any member can read raw per-user votes, reactions and memberships. R4 and R5 are open owner decisions, so "denied remains denied" is not met even on the fixture.
- **R1–R3** are prepared in `supabase/prepared-migrations/` and not deployed.
- **BLOCKED:** Realtime delivery after revocation, PostgREST HTTP mapping, the production `user_lists` view `security_invoker`, and `taste_tag_stats` isolation.
- `club_members` is not in the Realtime publication, so there is no server signal for removal.

### Row 11: Imports and assistant rules (COVERED)
**Success parameter.** No wrong adaptation, duplicate authoritative write, changed auto-apply threshold, lost field or unsafe Undo.

**Tests**
- **Production rules against the corpora (Deno):**
  - `concierge-parse/rules_corpus_test.ts`: "parser corpora: 107 cases executed through the production parser" and the multi-title split.
  - `concierge-recommend/router_test.ts` (7): the 73 offline cases, 22 German alternatives, chain order, bare-title and abbreviation seeds, fallback modes.
  - `router_corpus_test.ts` (2): 67 cases.
  - **MC** (review-e7 scope 2): disabling `isClassicIntent` → 2 red; removing the `;` splitter → red.
- **`ImportReconcilerTests`** (15; Rule):
  - "Auto-apply threshold is >= 0.85… (exact boundary)" (0.8499 / 0.85 / 0.8501 / 0.99);
  - "Ambiguous adaptations block auto-apply even at 0.99";
  - "Tracked = the server's existing_entry OR the Library…" (closes review-e6b-views B1);
  - "anime 42 and manga 42 stay distinct".
  - **MC:** E6b-V A/B/C.
- **`ImportLoadStateGateTests`** (4; **RF** E6c1) and **`ImportApplyGateTests`** (4; **MC** E8-C2 G1/G2): no Add while the Library is not loaded; apply only when loaded.
- **`ImportsContractTests`:**
  - "Apply and Undo (server-side writers) fire the single Library hook once per success…";
  - "Export text: anime 7 and manga 7…" (**RF**, E6b red);
  - request shapes.
- **`LibraryFacadeTests`** › "Concierge apply and undo re-read the Library projection after the server-side write".
- **Deno `concierge-apply/handler_test.ts`** (10): provided fields only; progress never null; rating clamp 1..10; JWT identity.
- **Deno `concierge-undo/handler_test.ts`** (7): restores only fields the import wrote; skips when a written field changed later.
- Apply/undo mutation checks: 6/6 (ledger, "Prepared, NOT deployed").
- **`ImportIntentTests`** (18): pre-existing `TextNormalization.looksLikeImport`; REG.
- **`ConciergeRoutingTests`** (15; Rule; Concierge-rules lane): clarification gate and its thresholds/abbreviation set, FM intent threshold 0.65 (NaN never trusted), keyword routing over EN/DE corpus prompts, clarify-answer routing, parser clarification only with `clarify_v2`, input-field intent order, paste detection (20+ characters), pasted-list and auto-send rules. **MC:** the lane reports 32/32 mutations killed (`e8/E8-concierge-report.md`).
- **`ImportReconcilerTests`** pre-selection and auto-apply-plan cases (6; Rule): `initialSelections` (top candidate at ≥ 0.60 unless ambiguous; the pinned first-parse divergence; parse order) and `autoApplyPlan` (apply only with the Library loaded and every line qualifying; unknown titles never auto-apply), plus a differential test against the pre-E6 Concierge and Profile compositions over a fixture matrix.

**Command**
- `DENO concierge-parse`, `DENO concierge-recommend`, `DENO concierge-apply`, `DENO concierge-undo`
- `APP ImportReconcilerTests ImportLoadStateGateTests ImportApplyGateTests ImportsContractTests LibraryFacadeTests ImportIntentTests ConciergeRoutingTests`
- `bash scripts/quality-gates/test_router_offline.sh` and `bash scripts/quality-gates/test_concierge_corpora.sh`

**Not proven**
- **Corpus disagreements with production.**
  - Router: 2 cases pinned.
  - Parser: 17 cases disagree, 13 pinned (3 as defects: `en_009`, `de_012`, `de_022`).
  - 4 more were re-expected in the test (`en_011`, `en_025`, `de_004`, `de_013`); the corpus JSON still asserts the old behaviour (review-e7 scope 2/5).
- **Live `search_titles` assumption.** 58/73 router and 55/67 corpus cases assume `search_titles` returns no row scoring ≥0.45. The gate checks routing rules, not end-to-end routing.
- **Deployment state.** The new `concierge-apply`/`concierge-undo` are not deployed, so deployed behaviour differs. `ImportReconciler.sendsStoredRatingAndNotes` must flip when the new apply is deployed.
- **Cross-tier.** There is no single run spanning the Swift client and the edge handler.
- **Weak red evidence.** The ImportReconciler red run used a port of the old rules (review-e6b-views, "Could not verify").
- **View call sites of the extracted rules.** Four flag arguments (`actionsForAmbiguousItems`, `parserAmbiguityBlocks`) encode preserved Concierge/Profile divergences; flipping one changes behaviour while the suite stays green. Only a UI smoke run would catch it (Concierge-rules lane report).

### Row 12: Catalog and paging (COVERED)
**Success parameter.** No target confusion, duplicate or missing pages, ancillary-format regression or guessed relation identity.

**Tests**
- **`CatalogCacheContractTests`** (3):
  - "anime 990007 and manga 990007 hit different tables/RPCs and never share a cache entry";
  - joins and warm reads (**RF:** E5a, 2 requests each → 1);
  - public caches survive A→B.
- **`DiscoveryContractTests`:** "Default formats (request shape): anime Browse/Search/Discover never ask for SPECIAL/MUSIC/TV_SHORT…" and "Browse keyset: the caller's cursor is sent verbatim…". REG; never red.
- **`SearchContractTests`:** "Keyset continuity: page 2 starts after page 1's last row…" (REG) and "Stale search…" (**RF** E5a; **MC** M1).
- **`CollectionContractTests`** › "Keyset continuity…": a 120-row keyset-faithful stub, independent cursors. **MC** (E5c).
- **Paging:** `SupabaseLibraryBackendRequestTests.fetchAllPagesFinitely` (Pkg) and `PostgrestLibraryTransportTests` › "fetchAll: one paged GET per table…".
- **Identity:** `AdaptationLadderTests` (6), `EntityWorkIdentityTests` (2); REG, pre-existing.
- **Content rules:** `DiscoveryContentRulesTests` (8 parameterised cases, rules moved verbatim).

**Command**
- `APP CatalogCacheContractTests DiscoveryContractTests SearchContractTests CollectionContractTests PostgrestLibraryTransportTests AdaptationLadderTests EntityWorkIdentityTests DiscoveryContentRulesTests`
- `PKG SupabaseLibraryBackendRequestTests`

**Not proven**
- Server-side exclusion of the ancillary formats is not exercised; only the request shape is.
- Browse cursor derivation stays in `BrowseView` (not moved) and is untested.
- `fetchAll` assumes PostgREST `max_rows ≥ 1000` (F2).

### Row 13: Shared UI and navigation (PARTIAL: pure route policy only)
**Success parameter.** Correct target, preserved controls/focus/selection and unchanged approved composition.

**Required check.** One representative integrated save/detail/club route per wiring pattern, plus a selective visual check. **Not executed.** The status is PARTIAL only because the typed-route policy now exists and is unit-tested; no route ran through the views.

**Supporting evidence (logic and static checks only; no view executes):**
- `LibraryViewActionsTests` (7) and `LibraryActionsPrimitiveTests` (4): the action layer the views call. **MC:** E8-C2 T1, killed only by the new test.
- `TrackingDraftTests` and `QuickStatusChangeTests`: the editor and status-chip save rules.
- `ClubDetailLifecycleRulesTests` (2) and `ClubsViewRulesTests` (3): pure decisions extracted from `ClubDetailView` (review-e6a-views SF2).
- `DeepLinkRouterTests` (5): URL parsing only; REG.
- **`RoutingTests`** (4; Rule; routes lane): kind-prefixed route ids (anime 7 ≠ manga 7 ≠ tracking/add-to-club routes), slot update (present, ignore the same route, replace a different one), double-tap dedupe, and the destination each route constructs. **MC:** M1–M5 killed (`e8/E8-routes-report.md`).
- **`DetailProviderLinksTests`** (8; SDK-stub; detail lane): the detail pages' provider-link policy, now owned by `ProviderAvailabilityStore+DetailLinks`, through the real owner and SDK (verified-vs-catalog fallback, flag off, refresh once per cooldown, progress-keyed primary, superseded run never publishes, one outbound-URL validator). **MC:** M1/M2/M4 killed (review-detail).
- `check_architecture.sh` checks 3 and 6: no SDK import in views, no direct store writes in views (static).

**Command for the supporting tests**
- `APP LibraryViewActionsTests LibraryActionsPrimitiveTests TrackingDraftTests QuickStatusChangeTests ClubDetailLifecycleRulesTests ClubsViewRulesTests DeepLinkRouterTests RoutingTests DetailProviderLinksTests`

**Not proven**
- No route, journey, sheet presentation or dismissal timing, gesture arbitration (pager vs rails), focus or selection, haptic, toast or visual composition.
- No preview rendering.
- `KuroUITests` holds sleep-based screenshot flows against the configured production backend; they are unsuitable as a baseline (§3/§6) and were not run.
- Every lane report states "UI not run".
- **Route presenter wiring.** Whether each `.routePresenter()` install point actually presents, how a replace animates, the stale-slot case and the behaviour deltas (sheets anchored at the context root, pull-to-refresh no longer inherited, one deep-link slot) are established by reasoning only. The 16 device smoke journeys in `docs/modules/README.md` were not run; review-routes approves conditionally on that run.

### Row 14: Taste and device intelligence (PARTIAL)
**Success parameter.** Signals are not duplicated or assigned to a new account, and the non-FM fallback remains usable.

**Tests**
- **`TasteContractTests`** (8; SDK-stub with `TestClock`):
  - "Outbox: a newer signal for a card replaces its queued or in-flight one…" (**RF:** the E6b red run delivered a superseded 'love' after the 'retract');
  - "Outbox is bounded…";
  - "Outbox is cleared on A -> B and on sign-out…";
  - the stale-guard test, "drained on the next success", "drained once on foreground" (injected `NotificationCenter`);
  - personalised reads; request shapes.
  - **MC:** runs A–F and r1. Run A batched 12 mutations (review-e6b SHOULD-FIX 4).
- **`TasteDeckBannerTests`** (1) and **`TasteDeckTests`** (20): pre-existing decoding and meta-chip rules; REG.
- **`AssistantCompositionTests`** (1): one FM service per object graph; the assistant owners are in the funnel list. The E8-C1 change replaced the earlier tautology with a real `!==` check.

**Command**
- `APP TasteContractTests TasteDeckBannerTests TasteDeckTests AssistantCompositionTests`

**Status reason: PARTIAL**
- **No non-FM fallback test.** Nothing executes the non-FM path. `StubFMProvider` is never instantiated; the fallback is `AppleFMService.isAvailable` (review-final SHOULD-FIX 5).
- **Deck not mounted.** `TasteDeckView(` is constructed nowhere in `Kuro/`; ContentView mounts `TastePicksView`. The outbox's only UI entry point is therefore not reachable in production.
- **Synopsis cache key.** `AppleFMService.synopsisCache` is keyed by the bare `mediaId`, so anime 7 and manga 7 collide (open).
- **No idempotency key.** The taste-signal RPC has none; a lost-ack retry relies on server replacement.

### Row 15: Packages and build settings (COVERED; re-record on the final tree)
**Success parameter.** No accidental isolation change, duplicate compilation, broken app resources or SDK leakage.

**Evidence**
- **Package tests:** `swift test`, 39/39 in 8 suites (`final/01-package.log`).
- **Package gate:** `scripts/quality-gates/test_packages.sh` (wired into `run_all.sh`).
- **App build:** the Release `generic/platform=iOS` build succeeded (`final/03-release-build.log`), on the pre-TasteStore-edit tree.
- **`check_architecture.sh`:**
  - check 5: no Supabase, SwiftUI or UIKit import in `Packages/*/Sources`;
  - check 3: no SDK import in views;
  - check 1: no `SupabaseService` references.
- **Compiler-line inspection** (`e3/library-package-report.md` §2): `-swift-version 5`, `-default-isolation nonisolated`, `StrictConcurrency` and `MemberImportVisibility` per target.
- **No duplicates:** app copies of `MediaKind`, `ListStatus`, `Verdict` and the E1 primitives were deleted (E3-S). A duplicate symbol would fail the build.
- **Project settings:** review-final reports the pbxproj diff is the package link only, so the app's MainActor default isolation is unchanged.

**Command**
- `cd Packages/KuroModules && swift build --build-tests && swift test`
- `bash scripts/quality-gates/test_packages.sh`
- `bash scripts/quality-gates/check_architecture.sh`
- `xcodebuild -project Kuro.xcodeproj -scheme Kuro -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

**Not proven**
- Runtime loading of app resources (no app run). The package has no resources.
- The ledger's E4 "isolation/access review at final" is still listed as remaining.
- The ownership manifest is stale: the E0 generation covers 94 files, the tree has 119 (review-final G3).

### Row 16: Edge/worker extraction (PARTIAL)
**Success parameter.** Stable response and entrypoint, auth, idempotency, cursor/checkpoint, lock and report behaviour.

**Tests**
- **Pure production rules:** `concierge-recommend/router_test.ts` and `router_corpus_test.ts` (`router.ts`); `concierge-parse/rules_corpus_test.ts` (`rules.ts`). Imports are relative and nothing bundles the tests. review-e7 scope 2 confirmed by AST diff that the extraction changed no behaviour.
- **Representative handlers** through controlled boundaries:
  - `concierge-apply/handler_test.ts` (10), `concierge-undo/handler_test.ts` (7): invalid JWT → 401; identity; taste import context cleared.
  - `delete-account/handler_test.ts` (17): 405/401/500/403 mapping; success body exactly `{ success: true }`; retry is idempotent; Apple revocation order.
- **Type check:** `deno check` on the changed `index.ts` files (ledger).

**Command**
- `for d in delete-account concierge-recommend concierge-parse concierge-apply concierge-undo; do (cd supabase/functions/$d && deno test); done`
- `deno check supabase/functions/{concierge-recommend,concierge-parse,concierge-apply,concierge-undo,delete-account}/index.ts`

**Status reason: PARTIAL**
- **Handler shells not run.** The `concierge-recommend` and `concierge-parse` `serve()` shells (`index.ts`, whose primary chain changed) and the type-only `concierge-resolve` change are not executed. They are verified by AST diff and `deno check` only.
- **No worker run tested.** No active worker was extracted; per the keep decisions in `docs/modules/operations.md`, the worker files are unchanged. So lock, checkpoint, cursor and report behaviour has no executed check in this initiative.
- **Untested functions.** `bulk-import-*`, `manga-chapter-enrich`, `mirror-images` and `realm-describe` have keep-cohesive notes and no tests.
- **Nothing deployed.**

### Row 17: Request/subscription regression (PARTIAL)
**Success parameter.** No unexplained increase over the pinned baseline; no duplicate client, unbounded refetch or repeated subscription.

**Tests with a pre-change baseline**
- **`CollectionRequestCountTests`** › "Request regression: a cold start reads each Collection page RPC once; one Library change re-reads each once more and never the list tables" ([1,1,1] → [2,2,2]).
  - The same test passed on the tree before extraction (`E5c-pin-before`) and after.
  - It emulates the bootstrap's two reads rather than calling `bootstrapAfterAuth` (review-e5a/review-collection §A).
- **`LibraryHTTPContractTests`** › "Request regression: cold start, concurrent view refreshes and a post-apply refresh read each list table once per refresh". review-e3 S1 measured 4 cold-start GETs before the fix; this pins 2.
- **`CatalogCacheContractTests`** › "Request regression: concurrent duplicate detail/credits/ladder reads join one request; warm reads issue none". **RF** E5a: 2 → 1.

**Post-hoc pins (no pre-change measurement)**
- `ReleasesContractTests` › "Request regression: a cold start reads user_airing_next once…": not mutation-checked (E5b).
- `ProviderAvailabilityContractTests` › "Public caches: warm reads… issue no request…": not mutation-checked.
- `ClubsBundleCacheTests` (1), `RetryAndTimedCacheTests` › "TTL: …".
- `DetailProviderLinksTests` › "streaming_availability_v1 off: no availability request…" and "Refresh requested: the enqueue server write happens once… a second resolution inside the cooldown writes nothing" (detail lane).
- Subscription counts:
  - `ClubsRealtimeSerializationTests` › "Two subscribes in flight at once leave exactly one open channel";
  - `LibraryRealtimeTests` remount;
  - `TasteContractTests` › "…one registration per store, one forced drain per foreground notification…".

**Command**
- `APP CollectionRequestCountTests LibraryHTTPContractTests CatalogCacheContractTests ReleasesContractTests ProviderAvailabilityContractTests ClubsBundleCacheTests RetryAndTimedCacheTests ClubsRealtimeSerializationTests LibraryRealtimeTests TasteContractTests DetailProviderLinksTests`

**Status reason: PARTIAL**
- **No screen-level counts.** No cold, warm or remount request counts exist for Discover, Browse, Search, the detail screens or Clubs.
- **No remount coverage for requests.** Remount is covered only for channel counts.
- **"One SDK client" is static only.** It rests on a single `SupabaseClient(` construction found by review-final, not on a test.
- **Known waste, pinned as is.** Collection still fetches two card pages that no view reads (E5c open item), so the pin preserves fidelity, not efficiency.

## 4. Tests per suite (from listings)

**Provenance**
- **App:** `xcrun xcresulttool get test-results tests --path scratchpad/final/app-tests.xcresult` (10:43 run): 60 suites, 275 test functions, 547 test runs on the device row (61 parameterised functions account for 333 of those runs).
- **Package:** `swift test list`: 39 functions in 8 suites.
- **Deno:** `rg -c 'Deno\.test\('` per file, cross-checked against `final/06-deno.log`: 61 tests.
- **SQL:** `final/05-db-harness.log`: 10 files, 321 assertions, plus the guard unit check.

### App target `KuroTests`

| File | Struct (use with `-only-testing`) | Suite title | Fns | Matrix rows |
| --- | --- | --- | ---: | --- |
| AccountLifecycleTests | StaleUserListsCompletionTests | Account lifecycle: stale user-lists completion | 1 | 1 |
| AccountLifecycleTests | PrivateStateResetTests | Account lifecycle: private-state reset | 2 | 2, 6 |
| AccountLifecycleTests | SessionEntryPointTests | Account lifecycle: session entry points | 2 | 2, 4 |
| AccountLifecycleTests | AuthCallbackGuardTests | Account lifecycle: auth callback guard | 2 | 4 |
| AccountLifecycleTests | PendingReminderTests | Account lifecycle: pending reminders | 1 | 4, 5 |
| AccountLifecycleTests | LateRealtimeEventTests | Account lifecycle: late realtime events | 1 | 5 |
| AssistantContractTests | ImportsContractTests | Assistant: Imports | 6 | 1, 9, 11 |
| AssistantContractTests | ConciergeContractTests | Assistant: Concierge | 2 | 1, 9 |
| AssistantContractTests | TasteContractTests | Assistant: Taste | 8 | 1, 3, 9, 14, 17 |
| AssistantContractTests | AssistantCompositionTests | Assistant: composition | 1 | 14 |
| ClubErrorTests | ClubErrorTests | Clubs: typed club errors for the views | 9 | 9, 10 |
| ClubsContractTests | ClubsAccountTransitionTests | Clubs: account transitions | 2 | 1 |
| ClubsContractTests | ClubsRevocationTests | Clubs: revocation | 2 | 10 |
| ClubsContractTests | ClubsRealtimeTests | Clubs: realtime channel | 2 | 5 |
| ClubsContractTests | ClubsBundleCacheTests | Clubs: bundle cache | 1 | 17 |
| ClubsContractTests | ClubsRPCContractTests | Clubs: RPC requests and error codes | 5 | 9 |
| ClubsContractTests | ClubsRealtimeSerializationTests | Clubs: realtime serialization | 3 | 3, 5, 17 |
| ClubsContractTests | ClubsRevocationCounterTests | Clubs: revocation counters | 3 | 10 |
| ClubsContractTests | ClubsLibraryChangeTests | Clubs: Library changes | 2 | 8 |
| ClubsViewRulesTests | ClubsViewRulesTests | Clubs: what the club views rely on | 3 | 2, 5, 10, 13 |
| ClubsViewRulesTests | ClubDetailLifecycleRulesTests | Clubs: club detail lifecycle rules | 2 | 5, 10, 13 |
| CollectionContractTests | CollectionRequestCountTests | Collection: request counts | 1 | 17 |
| CollectionContractTests | CollectionContractTests | Collection: card pages and feed | 7 | 1, 3, 12 |
| IdentityCompositionTests | LibraryRealtimeTests | Library realtime: the account's list channel | 3 | 3, 5, 17 |
| IdentityCompositionTests | CompositionGraphTests | Composition: one construction path and one account-scoped list | 2 | 2 |
| IdentityCompositionTests | SessionSDKTests | Session funnel through the real SDK auth client | 7 | 4, 6, 9 |
| ImportReconcilerTests | ImportReconcilerTests | Imports: reconciliation rules (ImportReconciler) | 21 (15 + 6 pre-selection/auto-apply-plan cases from the Concierge-rules lane) | 11 |
| ImportReconcilerTests | ImportLoadStateGateTests | Imports: the Library load-state gate | 4 | 11 |
| ImportReconcilerTests | ImportApplyGateTests | Imports: the apply gate (canApply) | 4 | 11 |
| ConciergeRoutingTests | ConciergeRoutingTests | Concierge: client routing rules (ConciergeRouting) | 15 | 11 |
| DetailProviderLinksTests | DetailProviderLinksTests | Detail pages: provider links (ProviderAvailability owner) | 8 | 3, 13, 17 |
| RoutingTests | RoutingTests | Routing: typed navigation outputs | 4 | 13 |
| KuroTests | KuroTests | "Kuro App Tests" | **deleted** (was 2, tautological) | none |
| KuroTests | ImportIntentTests | Import Intent Detection | 18 | 11 |
| KuroTests | AuthErrorMappingTests | Auth Error Mapping | 4 | none |
| KuroTests | CreditRoleTests | CreditRole Normalization | 12 | none |
| KuroTests | ProviderAvailabilityNoteTests | Provider Availability Note Derivation | 7 | none |
| KuroTests | EntityWorkIdentityTests | Entity Work Identity | 2 | 12 |
| KuroTests | EntityDiscoveryFilterTests | Entity Discovery Filters | 4 | none |
| KuroTests | AdaptationLadderTests | Adaptation Ladder | 6 | 12 |
| KuroTests | EditorialSearchTests | Editorial Search | 3 | none |
| KuroTests | DetailTruthfulnessTests | Detail Truthfulness | 2 | none |
| KuroTests | TasteDeckTests | Taste Deck | 20 | 14 |
| KuroTests | DeepLinkRouterTests | Deep Link Router | 5 | 13 (supporting only) |
| LibraryFacadeTests | LibraryFacadeTests | Library facade: forwarders, writes, sinks and session funnel | 11 | 3, 5, 8, 11 |
| LibraryHTTPContractTests | LibraryHTTPContractTests | Library facade: HTTP contract of list writes | 7 | 7, 17 |
| LibraryViewActionsTests | LibraryViewActionsTests | Library view actions: routed through LibraryActions | 7 | 8, 13 |
| LibraryViewActionsTests | LibraryActionsPrimitiveTests | Library actions: outcome-returning primitives | 4 | 7, 13 |
| PersonalDataHTTPContractTests | ReleasesContractTests | Personal data: Releases | 4 | 1, 5, 9, 17 |
| PersonalDataHTTPContractTests | ProviderAvailabilityContractTests | Personal data: Provider availability | 3 | 1, 10, 17 |
| PersonalDataHTTPContractTests | SocialActivityContractTests | Personal data: Social activity | 4 | 1, 10 |
| PostgrestLibraryTransportTests | PostgrestLibraryTransportTests | PostgrestLibraryTransport: requests and responses through the real SDK | 5 | 7, 9, 12 |
| PublicDataHTTPContractTests | CatalogCacheContractTests | Public data: Catalog caches | 3 | 12, 17 |
| PublicDataHTTPContractTests | DiscoveryContractTests | Public data: Discovery and Browse | 5 | 1, 2, 12 |
| PublicDataHTTPContractTests | SearchContractTests | Public data: Search | 2 | 1, 12 |
| PublicDataHTTPContractTests | DiscoveryContentRulesTests | Public data: discovery content rules | 1 | 12 |
| SharedInfrastructureTests | RetryAndTimedCacheTests | Shared infrastructure: retry and timed caches | 3 | 17 (TTL test only) |
| SharedInfrastructureTests | RuntimeFlagsTests | Shared infrastructure: injected runtime flags | 4 | none |
| SharedInfrastructureTests | BannerCenterTests | Shared infrastructure: transient banner | 1 | 3 |
| SharedInfrastructureTests | TelemetryOwnerTests | Shared infrastructure: telemetry owners | 3 | 2, 9 |
| TasteDeckBannerTests | TasteDeckBannerTests | Taste: deck 'didn't save' banner | 1 | 14 |
| TrackingDraftTests | TrackingDraftTests | TrackingDraftTests | 14 | 7, 13 |
| TrackingDraftTests | QuickStatusChangeTests | QuickStatusChangeTests | 5 | 7, 13 |
| **Total** | | | see the ledger final section (was 275 before the final lanes) | |

### Package `Packages/KuroModules`

| Target | Suite type | Fns | Matrix rows |
| --- | --- | ---: | --- |
| KuroCoreTests | AccountSessionCoordinatorTests | 1 | 4 |
| KuroCoreTests | AccountScopedLoadsTests | 3 | 3 |
| KuroLibraryTests | LibraryStoreFieldTests | 8 | 7 |
| KuroLibraryTests | LibraryStoreSequencingTests | 9 | 1, 8 |
| KuroLibraryTests | LibraryStoreUndoTests | 5 | 7, 8 |
| KuroLibraryTests | LibraryStoreLoadStateTests | 3 | 1, 11 |
| KuroSupabaseTests | SupabaseLibraryBackendRequestTests | 7 | 7, 9, 12 |
| KuroSupabaseTests | SupabaseLibraryBackendMappingTests | 3 | 7, 9 |
| **Total** | | **39** | |

### Deno (`supabase/functions`)

| File | Tests | Matrix rows |
| --- | ---: | --- |
| delete-account/deletion_test.ts | 16 | 6, 16 |
| delete-account/handler_test.ts | 17 | 6, 9, 16 |
| concierge-apply/handler_test.ts | 10 | 9, 11, 16 |
| concierge-undo/handler_test.ts | 7 | 9, 11, 16 |
| concierge-recommend/router_test.ts | 7 | 11, 16 |
| concierge-recommend/router_corpus_test.ts | 2 | 11, 16 |
| concierge-parse/rules_corpus_test.ts | 2 | 11, 16 |
| **Total** | **61** | |

### SQL (`supabase/tests/rls`)
There are 10 files and 321 assertions, all mapped to rows 10, 6 (file 50) and 7 (file 10); the per-file numbers are in row 10. The run also reports 5 BLOCKED markers and 9 finding markers. `scripts/db/test_guard_env.sh` is the environment-guard unit check (G0); the ledger records 50/50.

## 5. Tests that map to no matrix row

| Suite | Fns | Why it maps to no row |
| --- | ---: | --- |
| `KuroTests` "Kuro App Tests" | 0 (deleted) | **Tautological; deleted after this review.** `testAppLaunch` asserted `#expect(Bool(true))`; `testUIComponents` counted two local array literals. |
| `CreditRoleTests` | 12 | Pre-existing credit-role normalisation (presentation). It guards G4 compatibility of moved catalog code, not a §3 risk. |
| `ProviderAvailabilityNoteTests` | 7 | Pre-existing typed availability-note rule. E5b reused it as a regression guard for the moved provider code (G4). |
| `AuthErrorMappingTests` | 4 | User-facing auth error text, now `AuthService.userFacingAuthErrorMessage` (G4). |
| `EntityDiscoveryFilterTests` | 4 | Entity-page filter presentation. |
| `EditorialSearchTests` | 3 | View-level query gating rule. |
| `DetailTruthfulnessTests` | 2 | Description sanitiser and provider ordering. |
| `RuntimeFlagsTests` | 4 | Flag stable-hash rollout and DEBUG overrides (G4 flag semantics; no §3 row). |
| `RetryAndTimedCacheTests` (2 of 3) | 2 | The `withRetry` policy and `trimTimedCache`. Only the TTL test maps (row 17). |

## 6. Rows or legs whose only coverage was called weak or partial by an independent review

| Row and leg | Only coverage | Review citation | State now |
| --- | --- | --- | --- |
| 4: restore, sign-up, Apple, same-user callback `setSession`, event mapping | Funnel-level `SessionEntryPointTests` | E1 report §9, QA review ("cannot catch an SDK-bound path that stops calling the funnel"); review-e6c1 NITS ("untested SDK legs") | Open |
| 1: Discovery bundle post-await guard (`DiscoveryStore` ~:121) | `lateAnswerOfEndedAccountIsDropped[bundleNewToYou]`, which goes through the funnel cancel path | review-e5a, round 2 item 2 ("can be closed… small SHOULD-FIX") | Open; no owner-level test |
| 1: `SearchStore` success-path and catch checks (~165/182/255/371) | None. `newQueryCancelsOldQueryPage` reaches only the cancellation-failure path | review-e5a, round 2 item 1 ("record as unpinned defense-in-depth") | Open (accepted) |
| 1: `ClubsStore.fetchClubBundle` post-await `isCurrent` | A→B test via transport cancellation only | review-e6a, Verified ("Residual… covered only by cancellation (accepted)") | Open (accepted) |
| 13: club view lifecycle wiring | `ClubDetailLifecycleRulesTests` (extracted pure rule; the SwiftUI wiring is never run) | review-e6a/review-views SHOULD-FIX 2 ("View lifecycle logic is untested and was never run") | Rule tested; wiring not run |
| 13: typed-route presentation | `RoutingTests` (pure `RoutePolicy`; the presenters are never run) | review-routes ("APPROVE, conditional on the simulator smoke run"; "The wiring itself is not testable here") | Policy tested; presenter wiring and the 16 smoke journeys not run |
| 14: Taste outbox | `TasteContractTests`. Mutation Run A batched 12 mutations; the deck UI is unmounted | review-e6b SHOULD-FIX 1 ("not reachable") and 4 ("weaker than one mutation per run") | Wired to the store; `TasteDeckView` still constructed nowhere |
| 11: tracked-source change (`existing_entry` OR Library) | Its red run ported the old rules into the new reconciler | review-e6b/review-views, "Could not verify" ("The change of existing-entry source (B1) was never red-tested") | Green and mutation-checked; never red against the original view code |
| 11, 16: corpus execution | Router/parser corpus tests: 58/73 and 55/67 cases depend on live `search_titles` returning nothing; 4 re-expected | review-e7 scope 2 (SHOULD-FIX disclosure) and scope 5 (finding 2, nit 3) | Disclosed; corpus JSON unchanged |
| 17: Releases cold-start count; provider warm reads | E5b tests (1) and (4), not mutation-checked | E5b report, Mutation check ("Not mutation-checked: tests (1), (2), (4) and (7)"); (2) and (7) were later strengthened | Post-hoc pins |
| 10: R1–R3 red half | Observed by the lead only | review-e7, "Could not verify" (`--exclude-pending` not run by the reviewer) | Recorded in ledger G0 |
| 2: scoped-prefs deletion | `deletedAccountPrefsAreRemoved` calls the helper | review-e1, NITS and round 2 ("still tests only the helper") | Real deletion path now covered by `SessionSDKTests` |

The composition tautologies flagged by review-e6c1 (`CompositionGraphTests`, `AssistantCompositionTests`) were repaired in E8-C1. The current files compare distinct graphs (`!==`) and exact owner lists.

## 7. Citation verification (done for this document)

- **Existence.** All 20 cited names below were matched by `rg` in `KuroTests`, `Packages/KuroModules/Tests` or `supabase/functions` (1 hit each):
  - App: `staleCompletionIsDropped`, `transitionClearsPrivateState`, `airingReminders`, `staleEventsScheduleNothing`, `signOutReachesTheSDKBeforeTheChannelTeardown`, `deletionReachesTheSDKBeforeTheChannelTeardown`, "W-04: +1 on a rated entry", "Request regression: a cold start reads each Collection page RPC once", "Auto-apply threshold is >= 0.85", "Leave and rejoin within one round trip", "LT-30: an ended account", "Outbox: a newer signal for a card replaces", "anime 990007 and manga 990007".
  - Package: `predecessorCannotClearSuccessor`, `staleRefreshCannotOverwriteNewerMutation`, `equalNumericIdsStayIndependent`, `editSendsOnlyEditedColumns`.
  - Deno: "a failing list delete reports failure and NEVER deletes the auth user", "undo of an update restores the before-values", "parser corpora: 107 cases executed through the production parser".
- **Read in full and judged non-tautological** (each asserts concrete production outcomes that a defect would change):
  1. `StaleUserListsCompletionTests.staleCompletionIsDropped`: holds A's request; asserts B's projection, error, own request order `["user-a","user-b"]`.
  2. `LibraryHTTPContractTests` W-04/W-07/W-10/W-02-13/W-06: exact method, table, filters and canonical body, such as `{"progress":4}` and `{"rating":null}`, through the real SDK.
  3. `SessionSDKTests.signOutReachesTheSDKBeforeTheChannelTeardown` and `deletionReachesTheSDKBeforeTheChannelTeardown`: order raced via AsyncStream with both gates held; scope `global`/`local`; SDK `currentSession == nil`.
  4. `LibraryStoreSequencingTests.staleRefreshCannotOverwriteNewerMutation`: 3 race orders; canonical row kept; untouched title takes the refresh.
  5. `ClubsRevocationCounterTests.staleMembershipLossDoesNotRevokeTheRejoinedClub`: held NOT_A_MEMBER vote after leave and rejoin; myClubs, activity, channel, friend counts and epoch unchanged.
  6. `ImportReconcilerTests.autoApplyThreshold`: exact 0.8499/0.85/0.8501 boundary on the production rule.
  7. `CollectionRequestCountTests.coldStartAndOneChangeRequestCounts`: [1,1,1]/[2,2,2], `fetchAllCount == 1`, zero list-table reads.
  8. Deno "a failing list delete reports failure and NEVER deletes the auth user": status 500, `failedSteps`, auth user survives, other user intact.
- **Tautology found:** `KuroTests` "Kuro App Tests" (section 5).

## 8. Not proven by this evidence (paste-ready)

- **UI and devices.** No UI journey, route, sheet, gesture arbitration, focus or selection, haptic, toast, preview or visual-composition check was executed, on simulator or device. Only the pure route policy is unit-tested (`RoutingTests`); the presenter wiring and the 16 smoke journeys in `docs/modules/README.md` were not run. The only UI tests (`KuroUITests`) are sleep-based screenshot flows against the configured production backend and were not run.
- **RLS.** Authorization is proven only on the audited local PostgreSQL 17 fixture: 176 of 238 migration files apply baseline-first and 62 fail.
  - This is not migration replay and not production equality.
  - Realtime, PostgREST, Storage and GoTrue were not exercised.
  - The DB-level pending response/event scenario was not run.
  - Club revocation is not sticky (R5), and members can read raw per-user rows (R4). Both are open owner decisions.
  - The R1–R3 fixes are prepared and not deployed.
- **Session.** SDK-bound session legs (launch restore, sign-up, Apple sign-in, same-user callback `setSession`, SDK event→`AuthEventKind` mapping) are covered only by funnel entry tests. Email sign-in, failed sign-in, sign-out, deletion and the foreign-user callback run through the real SDK against an in-process stub. No PKCE or nonce protection is claimed.
- **Client adapters.** Every client HTTP test answers from in-process fixtures, not live PostgREST.
  - The `Authorization`/`apikey` headers are not asserted.
  - The production Realtime channel wrappers and `UNUserNotificationCenter` are never executed.
  - The PostgREST `details` vs SDK `detail` defect is pinned, not fixed.
- **Request counts.** Baselines exist only for specific flows: Library list reads, Collection pages, upcoming airings, catalog detail/credits/ladder, provider public caches, the club bundle cache, and channel counts. There are no screen-level cold, warm or remount counts. "One SDK client" is a static check.
- **Offline and restart.** Durable offline sync, a durable Library outbox and restart behaviour are not implemented and not claimed. All projections and the Taste outbox are in memory.
- **Edge functions and workers.**
  - Nothing is deployed. The tests run against fakes.
  - The `concierge-recommend`/`concierge-parse` `serve()` shells were not executed.
  - Workers (locks, checkpoints, reports) were unchanged and not exercised.
  - The router/parser corpus gates assume live `search_titles` returns no strong row, and 17 parser plus 2 router cases disagree with the corpus.
- **Deletion.** Storage and auth-admin legs run against fakes or stubs, and the newest `delete_user_concierge_data` does not replay. Production grants and the bucket are unverified.
- **Open correctness items.**
  - F1 (`user_id` casing) needs a production check.
  - The `AppleFMService.synopsisCache` key collides for anime and manga with the same id.
  - A revoked notification permission is never noticed.
  - The non-FM fallback is not executed.
  - `TasteDeckView` is not mounted.
- **Test environment.** The KuroTests host app builds `AppComposition.shared` with production configuration and runs `startLaunchRestore()`, with no test-host guard. Tests make no network calls, but the host may.
- **Evidence identity.** The 10:43 final run predates the 10:47 `TasteStore.swift` edit, and `07-taste-fix` executed 0 tests. Only the lead's frozen-tree re-run qualifies the final source.

## 9. Evidence runs for the ledger (commands only; the lead fills in results)

Run these once on the frozen tree, in this order, after recording the source identity. `-only-testing` must name suite structs (section 4).

| ID | Risk rows | Command | Exit / count | Source identity |
| --- | --- | --- | --- | --- |
| V0 | all | `git rev-parse HEAD; git status --porcelain \| awk '{print substr($0,1,2)}' \| sort \| uniq -c; shasum -a 256 Kuro/ContentView.swift Kuro/KuroApp.swift Kuro/Views/TastePicksView.swift Kuro/Views/TasteDeckView.swift Kuro/Taste/TasteStore.swift; rg -l MUTATION Kuro KuroTests Packages` | | |
| V1 | 1, 3, 4, 7, 8, 9, 12, 15 | `cd Packages/KuroModules && swift build --build-tests && swift test` | | |
| V2 | 1–14, 17 | `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:KuroTests -resultBundlePath <dir>/app-tests.xcresult` then `xcrun xcresulttool get test-results summary --path <dir>/app-tests.xcresult` | | |
| V3 | 15 | `xcodebuild -project Kuro.xcodeproj -scheme Kuro -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | | |
| V4 | 11, 15, 16 (+ G7 docs) | `SKIP_RAILS_AUDIT=1 SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 bash scripts/quality-gates/run_all.sh` (secrets, migrations, corpora shape and exec, router rules, docs-current-state, swift-packages, architecture) | | |
| V5 | 8, 13, 15 | `bash scripts/quality-gates/check_architecture.sh` | | |
| V6 | G0, 10 | `bash scripts/db/test_guard_env.sh` | | |
| V7 | 6, 7, 10 | `bash scripts/db/run_local_db_tests.sh` | | |
| V8 | 10 (red half) | `bash scripts/db/run_local_db_tests.sh --exclude-pending` (expected: exit 1, failures only in files 60/61/62) | | |
| V9 | 6, 9, 11, 16 | `for d in delete-account concierge-recommend concierge-parse concierge-apply concierge-undo; do (cd supabase/functions/$d && NO_COLOR=1 deno test); done` | | |
| V10 | 16 | `deno check supabase/functions/concierge-recommend/index.ts supabase/functions/concierge-parse/index.ts supabase/functions/concierge-apply/index.ts supabase/functions/concierge-undo/index.ts supabase/functions/delete-account/index.ts` (needs network or a warm deno cache for the esm.sh supabase-js types; a cache miss is not a regression) | | |
| V11 | 13 | Selected UI journeys: **no safe, non-production UI harness exists**. Record row 13 as PARTIAL (pure route policy only) unless the journeys in `docs/modules/README.md` are run against a non-production configuration. | | |
