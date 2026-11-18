# W9 Tags and custom lists with manual order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** People can tag their entries, filter Collection by tag, keep mixed-medium custom lists in their own drag order, and turn imported custom-list names into Kuro lists. All of it stays private, bounded and deleted with the account.

**Architecture:**
- **Database.** One prepared migration adds three per-user tables: `library_tags`, `custom_lists` and `custom_list_items`. Each has a UUID `user_id` with an `auth.users` FK `ON DELETE CASCADE`, RLS select-own, and no client write grants. Writes go through plpgsql SECURITY DEFINER RPCs, which take a per-account advisory lock and never touch the library list rows (so `server_revision` is never advanced).
- **Conflict contract (corrections 2026-11-09, item 4).** No RPC replaces a whole set from a possibly stale client. Organisation writes are **deltas**: one atomic `apply_title_organisation_delta_v1(p_medium, p_media_id, p_add_tags, p_remove_tags, p_add_list_ids, p_remove_list_ids)`. Every custom list carries a `revision`, bumped by each membership or order change. Reorder and rebalance require the expected revision and raise `STALE_LIST` otherwise. The client then reloads and retries once, only when the user asks; it never retries silently.
- **Release switch (item 1).** Flag `library_organise_v1` (0 %), read from the injected `FeatureFlags` at call time, before any request. While it is off, the owners send nothing and the UI is hidden.
- **Credential lease (item 2).** Every private request runs inside `accountSession.withCredentialLease(for: account) { … }`.
- **App owners.** Two account-scoped owners, `LibraryTagsStore` and `CustomListsStore`, live in `Kuro/Library/`.
- **Ordering rule.** The pure sparse-position rule `CustomListOrder` lives in `KuroLibrary`, so a drag writes one item row (plus the list's revision).
- **UI.** Collection gains a tag word strip, which selects keys from the whole library (the existing key-selection pattern), and a "Your lists" journey. Tags and list membership are edited in one tool sheet with one atomic delta write.

**Tech Stack:** PostgreSQL 17 plpgsql (prepared migration + disposable DB tests, dblink concurrency tests), SwiftUI (iOS 26 SDK), Swift Testing (`KuroTests` with `StubPostgREST` and `SessionSDKHarness`, `KuroModules` package tests), Node `node:test` load profile.

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + features/W9-lists.feature (Rules "Tags", "Custom lists with manual order" and "Everything goes with the account". The rule "Repeat count and dates are editable (F2 contract)" is implemented by `00-foundation.md` Task F2.x.)

## Global Constraints
- §5.2 W9: "Tags (≤ 10 per entry, ≤ 24 characters, case-insensitive unique), custom lists (≤ 50 per account, both media, manual drag order that survives relaunch)"; "imported custom-list names can seed lists; all of it exported by W2 and deleted with the account; private to the owner."
- §5.2 W9: "Collection reads with tags/lists stay in Browse class ≤ 750 ms for the 2,000-title fixture; organisation writes (`apply_title_organisation_delta_v1`, `move_custom_list_item_v1`) stay in Progress class ≤ 750 ms; a reorder writes one item row plus the list's revision, and a stale reorder fails with `STALE_LIST` instead of overwriting."
- §6 W9: "New per-user tables (UUID user ids) with RLS; writes through RPCs that respect the existing revision fence for list rows"; "Tag and list membership changes are deltas through one atomic RPC, `apply_title_organisation_delta_v1(…)` … Custom-list order uses sparse numeric positions, so a move (`move_custom_list_item_v1(…, p_expected_list_revision)`) writes one item row plus the list's `revision`; a move or rebalance whose expected revision is stale raises `STALE_LIST`."
- §3 Database: "RLS on every new table; every function `SET search_path = public, extensions`; no raw `user_id` from clients; SECURITY DEFINER functions grant EXECUTE only to the roles that need it and revoke PUBLIC (see `20261108120159_review_security_v1.sql`); new SQL bodies in plpgsql (fixture rule); error codes in MESSAGE or HINT, never DETAIL alone. Migrations are written to `supabase/prepared-migrations/` and applied only after explicit owner approval"; "Account deletion (`delete-account`) must remove every new per-user table."
- §3 Capacity: "every new or changed backend read/write is assigned to one existing budget class, added to `scripts/load/backend_workload.js` (F3), and covered by an SQL-plan check. A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED". Budget: "Browse/Search/Clubs/Progress ≤ 750 ms".
- §3 Architecture: "one `@MainActor @Observable final class` owner per capability in `Kuro/<Capability>/`, built once in `AppComposition`; views read owners with `@Environment(Type.self)` and import no Supabase SDK module; account-scoped owners conform to `AccountScopedState`, capture `AccountContext` at the start of every async operation and check `isCurrent` before every private write, and are registered in `makeAccountScopedStates`".
- §3 Navigation: "Rule 5 (navigation contract) … apply to every new screen, sheet and tap target. New sheets register `.kuroNavigationLayer`; tool sheets use `.kuroLeavesJourney()`; unsaved input uses `.kuroDiscardGuard`."
- §3 Copy and design: "every user-facing string through `KuroLocale` (EN + DE); monochrome only, no coloured status; branded states only (`check_branded_states.sh`); light only until W8 ships."
- §3 Business: "Kuro will not charge for tracking, ordinary discovery, search/filter/sort, history, import/export or useful reminders."
- Corrections brief 2026-11-09 (owner-approved), binding for this plan:
  - Item 1: "Every user-visible workstream has a server feature flag (`feature_flags`, read via the injected `FeatureFlags`), default 0 %, checked BEFORE any request is sent … A feature whose RPC exists but whose flag is off sends no request. A test pins this per workstream (`<Suite>/flagOffSendsNoRequest`)."
  - Item 2: "Every new private (account-scoped) SDK request runs inside `accountSession.withCredentialLease(for: account) { … }` … Checking `isCurrent` only before publishing is not enough." The pattern test is `KuroTests/CredentialLeaseTests.swift` (`preDispatchSwitchSendsNothingAsB`, `preDispatchSwitchForEveryFamily`; harness `SessionSDKHarness` in `KuroTests/IdentityCompositionTests.swift:361`, which reads each request's `bearerSubject`). The package rule is pinned by `Packages/KuroModules/Tests/KuroCoreTests/AccountSessionTests.swift` (`CredentialLeaseTests.leaseIsRevalidatedBeforeItStarts`).
  - Item 4: "No whole-set replacement from a possibly stale client … for reorder, an expected-position guard … raising `STALE_LIST` → client reloads and retries once on user action, never silently. Two-device tests: B adds while A's sheet is open → A's save keeps B's addition; two concurrent reorders → second gets STALE_LIST."
  - Item 5: absolute-rate profiles, qualification mode with populated fixtures, semantic assertions, representative writes, cleanup verification, and "≥ 100 completions per endpoint and ≥ 30 per library-size subgroup; fewer → result `insufficient`, never `pass`". Typical and supported-maximum payloads are tested (2,000 items in one list, 10 tags per entry).
  - Item 7: "No manufactured red." A test added after its code exists gets a labelled "non-vacuity check", reverted in the same step.
- Binding names (planner brief):
  - `Kuro/Library/LibraryTagsStore.swift` (`func tags(for key: MediaKey) -> [String]`);
  - `Kuro/Library/CustomListsStore.swift` (`var lists: [CustomList]`; `struct CustomList: Identifiable, Equatable { let id: UUID; var name: String; var items: [MediaKey] }`);
  - both are `AccountScopedState`.

**Decisions this plan makes (owner may revisit):**
- **"Respects the revision fence"** means tag and list RPCs never write `anime_user_lists` / `manga_user_lists`, so they neither advance nor depend on `server_revision`, and pending progress intents never conflict because of them.
- **A tag or list membership can be *added* only for a title the caller tracks now** (`ENTRY_NOT_FOUND` otherwise). Removing is always allowed, so an orphaned title can leave its lists. Undo of a removal is offered only while the title is tracked; for an untracked title the notice has no Undo.
- **Rows are keyed by title `(medium, media_id)`, not by lifecycle.** They survive Remove → Undo.
- **List items survive library removal.** Removing a title from the library never deletes its `custom_list_items` rows. What people see:
  - On the list page the row stays in its place. It shows the title and the quiet line "No longer in your library" / "Nicht mehr in deiner Bibliothek" (monochrome, `kuroInkQuiet`).
  - Tapping the row still opens the title journey, where the title can be added again.
  - Its long-press menu offers only "Remove from list" (no Undo, see above) and hides "Tags & lists…", because adding is not allowed for an untracked title.
  - The "Your lists" counts include these items.
  - **Export (W2):** `CustomListsStore.exportLists()` keeps them in their manual position, and it emits empty lists too. W2 marks them `in_library: false`, because it derives that from the export's own entries.
- **Tags of a removed title** stay in `library_tags`, but the tag strip and the tag filter count only tracked titles (`allTags(tracked:)`, `keys(taggedWith:among:)`). W2 exports tags per library entry, so they are not exported. They come back when the title is added again.
- **Delta organisation writes** (item 4). Choice: one atomic RPC, `apply_title_organisation_delta_v1(p_medium text, p_media_id integer, p_add_tags text[], p_remove_tags text[], p_add_list_ids uuid[], p_remove_list_ids uuid[])`. No whole-set RPC exists; `set_title_organisation_v1` is not created.
  - Adds and removes are idempotent. A tag add is matched by `tag_key`: adding an existing key is a no-op and keeps the stored spelling, so a case-only respelling is not supported. A tag remove of an absent key is a no-op. A list add of an existing membership is a no-op; a list remove of an absent membership, or of a list that no longer exists, is a no-op.
  - The same tag key or list id in both an add and a remove array → `DELTA_INVALID`. The client's `TitleOrganisationDelta.between` never produces this.
  - Order under the lock: removes, then adds. `TAG_LIMIT` is checked on the resulting set, so another device's additions count. `ENTRY_NOT_FOUND` is raised only when an add is new and the title is untracked.
  - A list add to a missing or foreign list → `LIST_NOT_FOUND`.
  - The result is the title's server state after the call (`tags`, `items`), plus `{list_id, revision_before, revision}` for each list it changed.
- **List revision** (item 4). `custom_lists.revision bigint not null default 0` is bumped by every membership change (delta, seed) and every order change (move, rebalance) on that list. Rename does not bump it (order is unaffected).
  - `move_custom_list_item_v1` and `rebalance_custom_list_v1` take `p_expected_list_revision` and raise `STALE_LIST` when it differs. The revision is read after the advisory lock, so under READ COMMITTED the second of two concurrent moves sees the first commit.
  - A move therefore writes one `custom_list_items` row and one `custom_lists` row (the revision).
  - `LIST_ORDER_STALE` is retired; rebalance also raises `STALE_LIST` when the id set differs.
  - The client adopts a list's new revision from a delta result only when `revision_before` equals its local revision. Otherwise it keeps the old one, so its next move gets `STALE_LIST` and reloads instead of moving against an order it has not seen.
- **Bounds:**
  - list name 1–60 characters;
  - ≤ 2,000 items per list and ≤ 10,000 list items per account (keeps `custom_lists_v1()` ≤ ~600 KB);
  - tag and name length is counted in Unicode scalars after trim + NFC, which equals PostgreSQL `char_length`.
- **Flag `library_organise_v1`** (item 1). Accessor `FeatureFlags.libraryOrganiseV1Enabled`. Both owners take `flags: FeatureFlags` by initializer and read the accessor inside every `load`, write, seed and export call (never captured at composition: flags hydrate after launch and carry per-account overrides).
  - Off: `load` sets `loadState = .unavailable` and sends nothing; every write and the seed return `.failure(.unavailable)` and send nothing. The UI hides on `.unavailable`, the same path as "not deployed".
  - Export providers while off return the empty value (`[:]` / `[]`) without a request, not `nil`. At 0 % nobody has organisation data, and `nil` would mark every export `organisationUnavailable`. Caveat for the owner: if the flag is lowered after people used W9, their exports omit tags and lists until it is raised again.
- **Account deletion** is the FK cascade (reviewed set in test 50), with no barrier trigger: per `20261005140000`, "Tables whose user FK CASCADEs need no barrier". The function `delete-account` is unchanged. The scenario is retagged from `@deno:…::deletes tags and custom lists` to `@sql:rls/108_custom_lists_account_deletion.sql`, because a Deno test of a cascade the function never performs could never fail first.

## Review Focus
1. **App and database disagree on a tag.**
   - NFC "é" (U+00E9) vs NFD "e" + U+0301, "Comfy" vs "comfy", and a 24-scalar tag with emoji.
   - Grapheme counting in Swift (`count`) would accept a tag the database rejects.
   - Pinned in `107_library_tags.sql` (NFC/NFD dedupe, 24 emoji scalars accepted, 25 rejected) and in `LibraryTagsStoreTests/normalisesAndCountsLikeTheDatabase` (Task W9.4).
2. **Concurrent writes pass a limit.** Two devices create the 50th list, or add the 10th tag, at the same time. The per-account advisory lock in every write RPC serialises them. Pinned by `supabase/tests/concurrency/108_custom_list_limit_race.sql` (two dblink actors, exactly one `LIST_LIMIT`) (Task W9.2).
3. **A stale sheet or a stale order overwrites another device's work** (item 4).
   - The organise sheet was open on device A while device B (same account) added a tag and a list membership; A's save must keep them.
   - Two devices reorder the same list at once; the second must get `STALE_LIST`, not a silent interleave.
   - Pinned by `supabase/tests/concurrency/108_organisation_two_devices.sql` (two dblink sessions of the **same** user), `LibraryTagsStoreTests/organiseSaveSendsOnlyTheDelta` and `CustomListsStoreTests/staleReorderReloadsAndRetriesOnlyOnRequest` (Tasks W9.2, W9.4, W9.5).
4. **The order breaks after many drags.**
   - The midpoint gap can be exhausted (positions `1` and `nextUp(1)`).
   - Equal positions can appear from a stale client.
   - A drag can arrive from a list the store has already reloaded.

   Pinned by `CustomListOrderTests/exhaustedGapRebalances`, `CustomListOrderTests/tiesBreakByItemIdLikeTheServer` (Task W9.3) and `CustomListsStoreTests/staleReorderReloadsAndRetriesOnlyOnRequest` (Task W9.5).
5. **Account switch mid-operation** (a drag, a seed or an organise save in flight).
   - Post-dispatch (a result arrives after the switch): pinned by `CustomListsStoreTests/workFromPreviousAccountNeverPublishes` and `LibraryTagsStoreTests/tagsClearOnAccountSwitch` (Tasks W9.4, W9.5).
   - Pre-dispatch (A's request must never be sent with B's credential): pinned by `OrganiseCredentialLeaseTests/preDispatchSwitchSendsNoOrganiseRequestAsB` over every W9 request family (Task W9.6).
6. **A tag filter that covers only loaded pages, or is slow at 2,000 titles.** `collection_feed_page` is paged, so filtering loaded rows hides tagged titles beyond page one. The filter selects keys from the full tag index ∩ `LibraryStore.allEntries`, then hydrates 30 at a time. Pinned by the traced `LibraryTagsStoreTests/filterByTagShowsOnlyTaggedEntries`, which uses a 2,000-entry library with tagged titles outside the first page, and by the 107/108 EXPLAIN checks on the 2,000-title fixture (Tasks W9.1, W9.2, W9.4).
7. **Traffic while the flag is off.** Pinned by `LibraryTagsStoreTests/flagOffSendsNoRequest` and `CustomListsStoreTests/flagOffSendsNoRequest` (Tasks W9.4, W9.5).

## Success parameters
| §5.2 W9 parameter | Measured by | Expected |
|---|---|---|
| Tags ≤ 10 per entry, ≤ 24 characters, case-insensitive unique, private | `scripts/db/run_local_db_tests.sh --only 107_library_tags` | `TESTS : 1 test files, N assertions passed … PASS` |
| Custom lists ≤ 50, both media, private | `scripts/db/run_local_db_tests.sh --only 108_custom_lists` | PASS |
| Drag order survives relaunch; a reorder writes one item row plus the list's revision | `cd Packages/KuroModules && swift test --filter CustomListOrderTests`, plus the 108 assertions that `move_custom_list_item_v1` changes exactly one `custom_list_items` row's `ctid` and bumps the list `revision` by 1 | pass; `a move writes one item row` = 1; `revision + 1` |
| No stale overwrite between devices | `scripts/db/run_local_db_tests.sh --only 108_organisation_two_devices`; `-only-testing:KuroTests/LibraryTagsStoreTests/organiseSaveSendsOnlyTheDelta`, `…/CustomListsStoreTests/staleReorderReloadsAndRetriesOnlyOnRequest` | PASS; pass |
| Imported custom-list names can seed lists | `xcodebuild … -only-testing:KuroTests/CustomListsStoreTests` | `importedCustomListNamesCanSeedLists` passes |
| Filter Collection by tag | `xcodebuild … -only-testing:KuroTests/LibraryTagsStoreTests` | `filterByTagShowsOnlyTaggedEntries` passes |
| Hidden and silent while the flag is off | `…/LibraryTagsStoreTests/flagOffSendsNoRequest`, `…/CustomListsStoreTests/flagOffSendsNoRequest` | pass (0 requests) |
| Private requests carry their own account's credential | `-only-testing:KuroTests/OrganiseCredentialLeaseTests` | pass for every family |
| Deleted with the account | `--only 108_custom_lists_account_deletion`, plus `--only 50_account_deletion` with the reviewed CASCADE set updated | PASS |
| Exported by W2 | `LibraryTagsStore.tagsByKey` and the ordered list objects `CustomListsStore.exportLists()` feed W2's `LibraryExportService(tagsByKey:customLists:)` providers. W2 merges first (`00-program.md` merge order), so W9.6 wires them in `makeGraph` | `-only-testing:KuroTests/LibraryExportFlowTests` and `…/CustomListsStoreTests/exportListsKeepManualOrderEmptyListsAndRemovedTitles` pass |
| Collection reads and organisation writes ≤ 750 ms p95 (Browse reads, Progress writes) at 2,000 titles | Offline: the 107/108 `pg_temp.plan_uses_index` assertions and `node --test scripts/load/profiles/collection-with-tags-and-lists.test.js`. Live: an owner-approved **qualification-mode** run with the `collection-with-tags-and-lists` profile on the populated fixture (later qualification) | index plans true; profile test passes; live p95 ≤ 750 ms per class, every endpoint ≥ 100 completions and each library-size subgroup ≥ 30 (else `insufficient`), cleanup verified |

## File Structure
- `supabase/prepared-migrations/20261118120000_library_tags_custom_lists_v1.sql` (new): tables, indexes, RLS, grants, nine RPCs (`library_tag_index_v1`, `apply_title_organisation_delta_v1`, `custom_lists_v1`, `create_custom_list_v1`, `rename_custom_list_v1`, `delete_custom_list_v1`, `move_custom_list_item_v1`, `rebalance_custom_list_v1`, `seed_custom_lists_v1`).
- `supabase/tests/pending_migrations.txt`: lists the new file.
- `supabase/tests/README.md`: pending table row.
- `supabase/tests/rls/107_library_tags.sql` (new): tag privacy, bounds, normalisation, delta semantics, grants, plan, cascade.
- `supabase/tests/rls/108_custom_lists.sql` (new): list privacy, bounds, mixed media, one-row move with revision guard, seed, grants, plan.
- `supabase/tests/rls/108_custom_lists_account_deletion.sql` (new): account-deletion cascade removes tags, lists and list items (its own file so the deletion scenario has exactly one test and can fail first on its own).
- `supabase/tests/concurrency/108_custom_list_limit_race.sql` (new): two-session limit race.
- `supabase/tests/concurrency/108_organisation_two_devices.sql` (new): one user in two sessions: a stale sheet keeps the other device's additions; two concurrent reorders → exactly one `STALE_LIST`.
- `supabase/tests/rls/50_account_deletion_fk_and_rpc.sql`: reviewed CASCADE set gains the three `user_id` FKs.
- `Packages/KuroModules/Sources/KuroLibrary/CustomListOrder.swift` (new): sparse positions, move (with neighbour positions), rebalance, tie-break.
- `Packages/KuroModules/Tests/KuroLibraryTests/CustomListOrderTests.swift` (new).
- `Kuro/Services/FeatureFlags.swift`: `var libraryOrganiseV1Enabled: Bool { evaluate("library_organise_v1") }`.
- `Kuro/Library/LibraryOrganisationModels.swift` (new): wire rows, outcomes, tag rules (`LibraryTagRules`), `TitleOrganisationDelta`, copy (`OrganiseCopy`, EN/DE).
- `Kuro/Library/LibraryTagsStore.swift` (new): tag index owner; the atomic organise delta write.
- `Kuro/Library/CustomListsStore.swift` (new): lists owner (lists, revisions, order, guarded move and retry, remove/Undo, seed, export objects, catalogue hydration).
- `Kuro/Collection/CollectionStore+ImportedTitles.swift`: `CollectionSelectionSource` and `showTaggedTitles`.
- `Kuro/Collection/CollectionStore.swift`: `selectionSource` property, cleared with the selection.
- `Kuro/Composition/AppComposition.swift`: build, wire and register both owners; `AppGraph` fields; W2 export providers.
- `Kuro/KuroApp.swift`: `.environment(libraryTags)` and `.environment(customLists)`.
- `Kuro/Views/Lists/FolioOrganiseRows.swift` (new): `FolioTagWords`, `FolioListsLink`.
- `Kuro/Views/Lists/CustomListPages.swift` (new): `CustomListsJourneyPage` (index) and `CustomListJourneyPage` (one list, Arrange, untracked rows, stale-move notice).
- `Kuro/Views/Lists/CustomListSheets.swift` (new): `CustomListNameSheet` (create/rename) and `TitleOrganiseSheet` (tags + lists).
- `Kuro/Views/Lists/FolioItems.swift`: `FolioRowActions.organise` and the context-menu item "Tags & lists…".
- `Kuro/Views/EditorialCollectionView.swift`: tag strip, lists link, organise sheet and its navigation layer, tagged-selection header.
- `KuroTests/LibraryTagsStoreTests.swift`, `KuroTests/CustomListsStoreTests.swift`, `KuroTests/OrganiseCredentialLeaseTests.swift` and `KuroTests/OrganiseRenderTests.swift` (new); `KuroTests/IdentityCompositionTests.swift` (expected owner list; `SessionSDKHarness` takes an optional `flags:` parameter, added by W2 Task 5, which merges first; add it here only if it is missing).
- `scripts/load/profiles/collection-with-tags-and-lists.js` and `.test.js` (new); `scripts/load/workloads/tracker-gaps-combined.js` (one line, 5 rps).
- `docs/superpowers/specs/2026-11-09-tracker-gaps/features/W9-lists.feature`: deletion scenario retagged (done in planning); flag, lease, two-device and stale-reorder scenarios (added with the 2026-11-09 corrections).
- `docs/tracker-gaps-2026-11/lists/EVIDENCE.md` (new).

---

### Task W9.1: Prepared migration (tables, tags, organisation delta) + DB test 107

**Files:** create `supabase/prepared-migrations/20261118120000_library_tags_custom_lists_v1.sql` (the three tables, tag RPCs, the delta RPC) and `supabase/tests/rls/107_library_tags.sql`; modify `supabase/tests/pending_migrations.txt`, `supabase/tests/README.md` and `supabase/tests/rls/50_account_deletion_fk_and_rpc.sql`.

**Interfaces (Produces):**
```sql
-- header: PREPARED ONLY; owner approval required; depends on 20261007040000 (live); rollback = drop the 9 functions, 3 tables.
create table public.library_tags (
  user_id uuid not null references auth.users(id) on delete cascade,
  medium text not null check (medium in ('anime','manga')),
  media_id integer not null check (media_id > 0),
  tag text not null check (tag = btrim(tag) and tag = normalize(tag, NFC) and char_length(tag) between 1 and 24),
  tag_key text generated always as (lower(tag collate "und-x-icu")) stored,   -- Unicode case folding independent of the
                                                                             -- cluster's lc_ctype (fixture runs C.UTF-8 or C)
  created_at timestamptz not null default now(),
  primary key (user_id, medium, media_id, tag_key));
create index library_tags_user_tag_idx on public.library_tags (user_id, tag_key);
-- RLS on; policy library_tags_select_own for select to authenticated using ((select auth.uid()) = user_id);
-- revoke all on public.library_tags from public, anon, authenticated; grant select to authenticated; grant all to service_role.

-- The list tables are created here too, because apply_title_organisation_delta_v1 always reads them (its result
-- carries the title's items and changed lists); W9.2 adds only the list RPCs.
create table public.custom_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (name = btrim(name) and name = normalize(name, NFC) and char_length(name) between 1 and 60),
  name_key text generated always as (lower(name collate "und-x-icu")) stored,
  revision bigint not null default 0 check (revision >= 0),       -- bumped by every membership/order change of this list
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (user_id, name_key), unique (id, user_id));
create table public.custom_list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  medium text not null check (medium in ('anime','manga')),
  media_id integer not null check (media_id > 0),
  position double precision not null check (position > '-Infinity'::float8 and position < 'Infinity'::float8),  -- NaN fails both
  added_at timestamptz not null default now(),
  foreign key (list_id, user_id) references public.custom_lists(id, user_id) on delete cascade,
  unique (list_id, medium, media_id));
-- No FK to <medium>_user_lists: an item survives the title's removal from the library (Decisions).
create index custom_list_items_order_idx on public.custom_list_items (list_id, position, id);
create index custom_list_items_user_idx on public.custom_list_items (user_id, list_id);
-- RLS select-own on both; same grants pattern as library_tags.

-- plpgsql SECURITY DEFINER, set search_path = public, extensions; revoke all from public, anon; grant execute to authenticated, service_role:
public.library_tag_index_v1() returns table(medium text, media_id integer, tags text[])
  -- caller's rows only (auth.uid()), tags ordered by tag_key; ordered by medium, media_id.
public.apply_title_organisation_delta_v1(p_medium text, p_media_id integer, p_add_tags text[], p_remove_tags text[],
                                         p_add_list_ids uuid[], p_remove_list_ids uuid[]) returns jsonb
  -- null or empty array = nothing for that part. Lock: pg_advisory_xact_lock(hashtextextended('kuro.library.organise:'||auth.uid()::text,0)).
  -- Tags: btrim + normalize(NFC) every input; adds deduped by lower() keeping the first spelling.
  -- Under the lock: removes (by tag_key / membership; absent = no-op), then adds (existing key / membership = no-op).
  -- MESSAGE codes: UNAUTHENTICATED, INVALID_MEDIUM, DELTA_INVALID (same tag key or list id in an add and a remove array),
  -- ENTRY_NOT_FOUND (raised ONLY when an add is NEW, i.e. the title does not already have that tag key / membership,
  -- AND the title is not in the caller's <medium>_user_lists where user_id = auth.uid()::text; a call that only removes,
  -- or only re-adds what exists, is always allowed, so an orphaned title can still leave its lists and lose its tags),
  -- TAG_EMPTY, TAG_TOO_LONG, TAG_LIMIT (> 10 in the RESULTING set, so another device's tags count),
  -- LIST_NOT_FOUND (an add to a missing or foreign list; a remove from one is a no-op), LIST_FULL (2,000),
  -- LIST_ITEMS_LIMIT (10,000 per account).
  -- New items appended at max(position)+1024 (or 1024). Every list whose membership changed: revision = revision + 1, updated_at = now().
  -- returns {"tags":[...], "items":[{"list_id","item_id","position"}...], "lists":[{"list_id","revision_before","revision"}...]}:
  -- the title's server state after the call (other devices' changes included) and the lists this call changed.
```
No RPC replaces a title's whole tag set or membership. The list-part SQL is completed in W9.2. `apply_title_organisation_delta_v1` is written once here with both halves, so that the 108 tests exercise its list half (W9.2 adds the RPCs that create and order lists).

Steps
- [ ] Write the failing test `107_library_tags.sql`. Header: `-- @requires table public.anime_user_lists`, `-- @requires table public.manga_user_lists`. Body: `begin; \ir ../fixtures/library_2000.sql`, then `tests.make_user(1)` and `tests.make_user(2)`; insert A's list rows (anime 1, manga 2), then:
  - as user 1: `apply_title_organisation_delta_v1('anime',1,array['comfy'],null,null,null)` → `tests.eq('A tagged', (select tags from public.library_tag_index_v1() where media_id=1), array['comfy'])`.
  - as user 2:
    - `tests.eq('B reads none of A', tests.rowcount('select * from public.library_tags'), 0::bigint)`
    - `tests.eq('B index empty', tests.rowcount('select * from public.library_tag_index_v1()'), 0::bigint)`
    - `tests.denied('B cannot insert', 'insert into public.library_tags(user_id,medium,media_id,tag) values ('''||tests.uid(1)||''',''anime'',1,''x'')')`
    - `tests.denied` for update and delete.
    - `tests.raises('B cannot tag a title B does not track', 'select public.apply_title_organisation_delta_v1(''anime'',1,array[''x''],null,null,null)', '%ENTRY_NOT_FOUND%')`
    - After the attempt, as user 1, A's tag is unchanged.
  - Delta semantics (as user 1, on anime 1):
    - Adding `array['Comfy']` again is a no-op: the tag stays `comfy` (stored spelling kept, one row).
    - Removing `array['absent']` succeeds and changes nothing.
    - `apply…(…, array['x'], array['X'], null, null)` → `'%DELTA_INVALID%'`.
    - The resulting-set limit: with 9 tags stored, a call adding 2 new tags → `'%TAG_LIMIT%'`; a call adding 2 and removing 1 → succeeds with 10 tags.
  - Orphan removal, on its own title so later assertions keep anime 1:
    - A tracks anime 3, tags it `'old'`, then deletes it from `anime_user_lists`.
    - `apply_title_organisation_delta_v1('anime',3,null,array['old'],null,null)` succeeds and leaves 0 tags.
    - Re-tagging it with `array['comfy']` raises `ENTRY_NOT_FOUND`.
  - Bounds (as user 1, on a fresh tracked title):
    - 11 distinct tags in one add → `raises … '%TAG_LIMIT%'`
    - `repeat('a',25)` → `'%TAG_TOO_LONG%'`
    - `'   '` → `'%TAG_EMPTY%'`
    - 10 tags succeed (the supported maximum per entry)
    - A 24-scalar emoji tag (`repeat('😀',24)`) succeeds; 25 → `TAG_TOO_LONG`.
  - Normalisation: `array['Comfy','comfy',' comfy ']` stores one tag `Comfy`. `array[U&'cafe\0301', U&'caf\00E9']` stores one tag whose `normalize(tag,NFC) = tag`. `array['Émotion','émotion']` stores one tag: non-ASCII case folding works through the ICU collation even though the fixture cluster runs `C.UTF-8` or `C` (`run_local_db_tests.sh` `initdb -E UTF8 --locale=C.UTF-8`, falling back to `C`).
  - Precondition: `tests.ok('ICU collation available', exists(select 1 from pg_collation where collname = 'und-x-icu'))`, and the server encoding is UTF8, so `normalize()` is valid.
  - Grants:
    - `tests.ok('anon cannot execute', not has_function_privilege('anon','public.apply_title_organisation_delta_v1(text,integer,text[],text[],uuid[],uuid[])','execute'))`, and the same for `library_tag_index_v1()`.
    - `tests.ok('no whole-set organisation RPC exists', to_regproc('public.set_title_organisation_v1') is null)`.
    - `tests.ok('search_path pinned', …proconfig @> array['search_path=public, extensions'])` for both.
    - `prosecdef` is true and `prolang` is plpgsql.
  - Plan:
    - `pg_temp.load_library_2000(tests.uid(1))` (400 noise users × 250 rows, F3); insert tags for every 2nd title of user 1 and of the noise users (`set local session_replication_role=replica`, direct insert as superuser); `analyze public.library_tags`.
    - `tests.ok('tag index read uses library_tags_pkey at 2,000 titles', pg_temp.plan_uses_index(format('select medium, media_id, array_agg(tag order by tag_key) from public.library_tags where user_id=%L group by medium, media_id', tests.uid(1)), 'library_tags_pkey'))`. The query text mirrors the function body; a comment in both files says so.
    - Negative control: `alter table public.library_tags drop constraint library_tags_pkey;` and `drop index public.library_tags_user_tag_idx;`, then `tests.ok('control: without the index the plan check is false', not pg_temp.plan_uses_index(<same query>, 'library_tags_pkey'))`. Put this after every other assertion that needs the key; the transaction rolls back.
  - Cascade: `tests.reset(); delete from auth.users where id=tests.uid(1);` then `tests.eq('tags cascade', (select count(*) from public.library_tags where user_id=tests.uid(1)), 0::bigint)`.
  - `rollback;`
- [ ] Update `50_account_deletion_fk_and_rpc.sql` `'CASCADE set is the reviewed one'`: insert `custom_list_items.user_id`, `custom_lists.user_id` and `library_tags.user_id` into the expected string in sorted position (the FKs appear in this task, so the full suite stays green between W9.1 and W9.2).
- [ ] Add `20261118120000_library_tags_custom_lists_v1.sql` to `pending_migrations.txt` (under a `# 2026-11-10 tracker gaps W9 (prepared only)` comment), and add a README pending-table row (`| 20261118120000_library_tags_custom_lists_v1.sql | W9 tags, custom lists | 107, 108, 50, concurrency/108 (limit race, two devices) |`).
- [ ] Run `scripts/db/run_local_db_tests.sh --only 107_library_tags,50_account_deletion`. Expected FAIL: `function public.apply_title_organisation_delta_v1(...) does not exist` (107, first assertion) and the CASCADE string mismatch (50).
- [ ] Implement the three tables (indexes, RLS, grants), the tag RPC and `apply_title_organisation_delta_v1` (both halves).
- [ ] Run again. Expected: PASS for both. Then run `scripts/db/run_local_db_tests.sh --exclude-pending --only 107_library_tags`. Expected: FAIL at the first assertion (the red half of the evidence); record both lines.
- [ ] Commit: `git add supabase/prepared-migrations/20261118120000_library_tags_custom_lists_v1.sql supabase/tests/rls/107_library_tags.sql supabase/tests/pending_migrations.txt supabase/tests/README.md supabase/tests/rls/50_account_deletion_fk_and_rpc.sql`; message `W9: prepared organisation tables and library tags (private, ≤10 × ≤24, NFC case-insensitive) with atomic organisation delta RPC`.

### Task W9.2: Custom list RPCs in the migration + DB tests 108 and concurrency

**Files:** modify the migration (the seven list RPCs; the tables exist since W9.1); create `supabase/tests/rls/108_custom_lists.sql`, `supabase/tests/rls/108_custom_lists_account_deletion.sql`, `supabase/tests/concurrency/108_custom_list_limit_race.sql` and `supabase/tests/concurrency/108_organisation_two_devices.sql`.

**Interfaces (Produces):**
```sql
-- RPCs (plpgsql SECURITY DEFINER, search_path pinned, per-account advisory lock on writes, EXECUTE authenticated + service_role only):
public.custom_lists_v1() returns jsonb
  -- [{"id","name","created_at","updated_at","revision","items":[{"item_id","medium","media_id","position"}…]}…],
  -- lists by name_key, items by (position, id); empty lists included
public.create_custom_list_v1(p_name text) returns jsonb          -- {"id","name","created_at","revision":0}; LIST_NAME_INVALID, LIST_NAME_TAKEN, LIST_LIMIT (50)
public.rename_custom_list_v1(p_list_id uuid, p_name text) returns jsonb   -- + LIST_NOT_FOUND; revision unchanged
public.delete_custom_list_v1(p_list_id uuid) returns void        -- LIST_NOT_FOUND
public.move_custom_list_item_v1(p_list_id uuid, p_item_id uuid, p_after_position double precision,
                                p_before_position double precision, p_expected_list_revision bigint) returns jsonb
  -- under the lock, in this order: LIST_NOT_FOUND; STALE_LIST (revision <> p_expected_list_revision, read after the lock);
  -- ITEM_NOT_FOUND (item not in the list); new position = midpoint(after, before), or before - 1024 when after is null
  -- (head), or after + 1024 when before is null (tail); both null, a non-finite result, or a result not strictly between
  -- the neighbours → POSITION_INVALID (the client rebalances instead). ONE item UPDATE + revision = revision + 1.
  -- returns {"item_id","position","revision"}
public.rebalance_custom_list_v1(p_list_id uuid, p_item_ids uuid[], p_expected_list_revision bigint) returns jsonb
  -- STALE_LIST unless the revision matches AND p_item_ids = exactly the list's items; positions 1024*(i); revision + 1.
  -- returns {"revision","items":[{"item_id","position"}…]}
public.seed_custom_lists_v1(p_lists jsonb) returns jsonb
  -- p_lists = [{"name":text,"items":[{"medium","media_id"}…]}…] (≤ 60 names, ≤ 2,000 items each, else SEED_INVALID)
  -- per name (btrim+NFC, case-insensitive): reuse the existing list or create one while < 50; items the caller
  -- does not track or already in the list are skipped; every list it adds to: revision + 1; returns {"created":[names],
  -- "reused":[names], "skipped":[{"name","reason":"LIST_LIMIT"|"LIST_NAME_INVALID"}], "added":int}. Idempotent.
```
`LIST_ORDER_STALE` does not exist; every stale-order answer is `STALE_LIST`.

Steps
- [ ] Write the failing test `108_custom_lists.sql`. Header: `@requires` for the list tables; `\ir ../fixtures/library_2000.sql`; users 1 and 2; A tracks anime 1 and manga 2.
  - Mixed medium and privacy:
    - A: `create_custom_list_v1('Winter picks')`, then `apply_title_organisation_delta_v1('anime',1,null,null,array[<id>],null)` and `apply_title_organisation_delta_v1('manga',2,null,null,array[<id>],null)`.
    - `tests.eq('both media in one list', (select jsonb_array_length(l->'items') from jsonb_array_elements(public.custom_lists_v1()) l), 2)`.
    - `tests.eq('two membership changes bump the revision twice', (select (l->>'revision')::bigint from jsonb_array_elements(public.custom_lists_v1()) l), 2::bigint)`.
    - As B: `tests.eq('B sees no lists', jsonb_array_length(public.custom_lists_v1()), 0)`, `tests.eq` row counts 0 on both tables, and `tests.raises('B cannot rename A''s list', …, '%LIST_NOT_FOUND%')`.
    - `tests.denied` for direct insert, update and delete on both tables.
  - Limits:
    - A creates lists 2…50 → OK; the 51st → `'%LIST_LIMIT%'`.
    - `create_custom_list_v1('winter PICKS')` → `'%LIST_NAME_TAKEN%'`.
    - `repeat('x',61)` → `'%LIST_NAME_INVALID%'`.
    - Supported maximum: a list filled to 2,000 items (replica insert) → one more add through the delta → `'%LIST_FULL%'`.
  - One-row move with the revision guard:
    - Insert 200 items into a fresh list (positions 1024·i) as superuser for user 1 (replica role); read its revision `r`.
    - Snapshot `(id, ctid)` of the 200 rows into a temp table, call `public.move_custom_list_item_v1(<list>, <id of item 150>, 2048, 3072, r)`, then `tests.eq('a move writes one item row', (select count(*) from public.custom_list_items i join snap s using (id) where i.ctid <> s.ctid), 1::bigint)`. Use `ctid`, not `xmin`: inside the test's single transaction every row already carries the same `xmin`, while an UPDATE always writes a new tuple version. Do not use `tests.affected`: it reports `GET DIAGNOSTICS row_count` of the `select`, which is always 1.
    - `tests.eq('the move bumps the list revision once', <revision>, r + 1)` and the returned position is 2560.
    - Then `(select array_agg(media_id order by position, id) …)` equals the expected order (item 150 at index 3).
    - The same call again with the old `r` → `'%STALE_LIST%'`, and no item row changed (ctid snapshot again).
    - `p_after_position => 'NaN'`, `'Infinity'`, both null, and `(1, 1)` (no room) → `'%POSITION_INVALID%'`.
  - Rebalance: a stale id set → `'%STALE_LIST%'`; a stale revision with the full set → `'%STALE_LIST%'`; the full set with the current revision → positions `1024,2048,…` and revision + 1. Supported maximum: rebalance of the 2,000-item list with all 2,000 ids succeeds.
  - Seed:
    - `seed_custom_lists_v1('[{"name":"Favourites","items":[{"medium":"anime","media_id":1}]},{"name":"To rewatch","items":[{"medium":"manga","media_id":2},{"medium":"anime","media_id":999999}]}]')` → `created = ["Favourites","To rewatch"]`, `added = 2` (the untracked 999999 is skipped).
    - A second identical call → `created = []`, `reused` holds both, `added = 0`.
  - Orphans, on a separate title (anime 3):
    - A adds anime 3 to "Winter picks", then deletes it from `anime_user_lists`.
    - `tests.eq('the list item survives library removal', <count of anime 3 in Winter picks>, 1::bigint)`, and `custom_lists_v1()` still lists it.
    - `apply_title_organisation_delta_v1('anime',3,null,null,null,array[<Winter picks id>])` succeeds and anime 3 leaves the list.
    - Re-adding it with `p_add_list_ids => array[<Winter picks id>]` raises `'%ENTRY_NOT_FOUND%'`.
  - Delta list semantics: a remove from a deleted list id is a no-op; an add to a deleted list id → `'%LIST_NOT_FOUND%'`; an add to a list that already holds the title changes nothing and does not bump the revision.
  - Grants and config: anon has no EXECUTE on all seven list RPCs; `search_path` is pinned; `prosecdef` is set; the language is plpgsql.
  - Plan at 2,000 titles: `pg_temp.load_library_2000(tests.uid(1))`; 20 lists × 100 items for user 1 and the noise users (replica insert); `analyze`. Then `tests.ok('list items read uses custom_list_items_user_idx', pg_temp.plan_uses_index(format('select list_id, id, medium, media_id, position from public.custom_list_items where user_id=%L order by list_id, position, id', tests.uid(1)), 'custom_list_items_user_idx'))`. The query mirrors `custom_lists_v1` (a comment in both). Negative control: `drop index public.custom_list_items_user_idx;` → the same check is false.
  - `rollback;`
- [ ] Write `108_custom_lists_account_deletion.sql` (the traced deletion scenario): A has tags, lists and items. `tests.reset(); delete from auth.users where id=tests.uid(1);` then three `tests.eq(..., 0::bigint)` (`library_tags`, `custom_lists`, `custom_list_items` for user 1), and B's rows are intact (`tests.eq` on B's counts unchanged).
- [ ] Write `concurrency/108_custom_list_limit_race.sql`: the user has 49 lists; two dblink actors (`tests.actor_open/send/result`) call `create_custom_list_v1('a')` and `create_custom_list_v1('b')` at once. Assert exactly one succeeds, the other raises `LIST_LIMIT`, and the final count is 50. Follow the header and requirements style of `concurrency/91_club_lifecycle_join_race.sql` (read it first).
- [ ] Write `concurrency/108_organisation_two_devices.sql`. Two dblink actors `device_a` and `device_b`, both authenticated as the **same** user 1 (each sets `request.jwt.claims` with `sub = tests.uid(1)` and `role authenticated`). User 2 is not used: this test is about one account on two devices, not privacy. Same header style as `91_…`.
  - Stale sheet keeps the other device's additions:
    - Setup (committed by the superuser, cleaned up at the end like `91_…`): user 1 tracks anime 1, which has tag `comfy` and is in list L1; list L2 exists.
    - `device_a` reads the title's state (`library_tag_index_v1`, `custom_lists_v1`): its "sheet" holds `{comfy}` and `{L1}`.
    - `device_b` sends `apply_title_organisation_delta_v1('anime',1,array['rewatch'],null,array[L2],null)`.
    - `device_a` then saves its own edit as a delta from its stale snapshot: `apply…('anime',1,array['slow burn'],array['comfy'],null,array[L1])`.
    - Assert the final tags are exactly `{rewatch, slow burn}` and the membership is exactly `{L2}`: B's additions are kept, and A removed only what A removed.
    - Assert `device_a`'s returned `tags` already include `rewatch` (the server state, so the app shows B's tag at once).
  - Two concurrent reorders → exactly one `STALE_LIST`:
    - List L3 holds 10 items at revision `r`.
    - `device_a` opens a transaction, sends `move_custom_list_item_v1(L3, <item 9>, 1024, 2048, r)`, and holds the transaction open.
    - `device_b` sends `move_custom_list_item_v1(L3, <item 5>, 7168, 8192, r)` (it blocks on the advisory lock).
    - `device_a` commits.
    - `tests.ok('second reorder is refused as stale', tests.actor_result('device_b') like '%STALE_LIST%')`.
    - The final revision is `r + 1`, and only item 9 moved.
  - Close both actors; delete the setup rows.
- [ ] Run `scripts/db/run_local_db_tests.sh --only 108_custom_lists,108_custom_list_limit_race,108_organisation_two_devices`. Expected FAIL: `function public.create_custom_list_v1(text) does not exist` in 108 and in both concurrency files' setup (the list RPCs are not written yet). The deletion file seeds its rows directly and the cascade exists since W9.1, so it can pass on its first normal run; its red half is `--exclude-pending --only 108_custom_lists_account_deletion` → FAIL (`relation "public.custom_lists" does not exist`). Record that line.
- [ ] Implement the list part of the migration.
- [ ] Run `--only 108_custom_lists,108_custom_lists_account_deletion,108_custom_list_limit_race,108_organisation_two_devices,50_account_deletion` again. Expected: PASS for the five files. Then run the full `scripts/db/run_local_db_tests.sh`. Expected: `TESTS … PASS (executed tests only)` and `PREPARED : every non-excluded … applied`.
- [ ] Commit: `git add supabase/prepared-migrations/20261118120000_library_tags_custom_lists_v1.sql supabase/tests/rls/108_custom_lists.sql supabase/tests/rls/108_custom_lists_account_deletion.sql supabase/tests/concurrency/108_custom_list_limit_race.sql supabase/tests/concurrency/108_organisation_two_devices.sql`; message `W9: prepared custom lists (≤50, mixed media, sparse positions, revision-guarded one-row move, seed) deleted with the account`.

### Task W9.3: `CustomListOrder` (package)

**Files:** create `Packages/KuroModules/Sources/KuroLibrary/CustomListOrder.swift` and `Packages/KuroModules/Tests/KuroLibraryTests/CustomListOrderTests.swift`.

**Interfaces (Produces):**
```swift
public struct CustomListSlot: Equatable, Sendable, Codable { public let itemId: UUID; public let key: MediaKey; public var position: Double }
public enum CustomListMove: Equatable, Sendable {
    case none                                   // from == to
    case single(itemId: UUID, position: Double, after: Double?, before: Double?)
                                                // exactly one row changes; after/before = the neighbours' positions
                                                // (nil at head/tail) sent to move_custom_list_item_v1, which recomputes
                                                // the same position
    case rebalance([CustomListSlot])            // gap exhausted: full ordered list, positions spacing*(i+1)
}
public enum CustomListOrder {
    public static let spacing: Double = 1024
    /// (position, itemId.uuidString.lowercased()) ascending, the server's ORDER BY position, id.
    public static func ordered(_ slots: [CustomListSlot]) -> [CustomListSlot]
    /// `from`/`to` are indices in `ordered(slots)`; `to` is the final index of the moved item.
    public static func move(_ slots: [CustomListSlot], from: Int, to: Int) -> CustomListMove
    /// SwiftUI `.onMove(fromOffsets:toOffset:)` → (from, to) for a single-item move.
    public static func indices(fromOffsets: IndexSet, toOffset: Int) -> (from: Int, to: Int)?
    public static func appendPosition(after slots: [CustomListSlot]) -> Double   // last + spacing, or spacing
    public static func rebalanced(_ ordered: [CustomListSlot]) -> [CustomListSlot]
}
```
- Algorithm (pinned, identical to the server's): the new position is the midpoint of the neighbours at the target. At the head it is `first - spacing`; at the tail, `last + spacing`. If the midpoint `m` is not strictly between its neighbours (`!(lo < m && m < hi)`), or is not finite, return `.rebalance` with the moved order applied.

Steps
- [ ] Write the failing tests (`@Suite("Custom list order") struct CustomListOrderTests`):
  - `@Test func moveWritesOnePositionAndKeepsOrder()` (traced):
    - Setup: 200 slots, positions `1024·(i+1)`, anime ids 1…200.
    - `CustomListOrder.move(slots, from: 149, to: 2)` == `.single(itemId: slots[149].itemId, position: 2560, after: 2048, before: 3072)`.
    - Apply that single change; `ordered(...)` maps to ids `[1, 2, 150, 3, 4, …, 149, 151, …, 200]`.
    - Exactly one slot differs from the input (`zip(old, new).filter { $0.position != $1.position }.count == 1` by item id).
    - JSON encode → decode the slots ("reload"); `ordered` gives the same id sequence.
  - `@Test func headAndTailMoves()`: move to 0 → position `1024 - 1024 = 0` with `after == nil, before == 1024`; move to 199 → `200·1024 + 1024` with `before == nil`.
  - `@Test func exhaustedGapRebalances()`: positions `[1, 1.nextUp, 3]`; moving index 2 to 1 → `.rebalance`, with positions `[1024, 2048, 3072]` and the new order.
  - `@Test func tiesBreakByItemIdLikeTheServer()`: two slots with equal position order by `itemId.uuidString.lowercased()`.
  - `@Test func onMoveOffsetsMapToFinalIndex()`: `indices(fromOffsets:[149], toOffset: 2) == (149, 2)`; `indices(fromOffsets:[2], toOffset: 150) == (2, 149)`; a multi-index set → nil.
- [ ] Run `cd Packages/KuroModules && swift test --filter CustomListOrderTests`. Expected FAIL: `cannot find 'CustomListOrder' in scope`.
- [ ] Implement.
- [ ] Run again. Expected: 5 pass.
- [ ] Commit: `git add Packages/KuroModules/Sources/KuroLibrary/CustomListOrder.swift Packages/KuroModules/Tests/KuroLibraryTests/CustomListOrderTests.swift`; message `W9: sparse custom-list positions; a move changes one row, exhausted gaps rebalance`.

### Task W9.4: Flag, `LibraryTagsStore` and the Collection tag selection

**Files:** create `Kuro/Library/LibraryOrganisationModels.swift`, `Kuro/Library/LibraryTagsStore.swift` and `KuroTests/LibraryTagsStoreTests.swift`; modify `Kuro/Services/FeatureFlags.swift`, `Kuro/Collection/CollectionStore.swift` and `Kuro/Collection/CollectionStore+ImportedTitles.swift`.

**Interfaces (Produces):**
```swift
// FeatureFlags.swift (additive, alphabetical in the tracker-gaps block)
var libraryOrganiseV1Enabled: Bool { evaluate("library_organise_v1") }
// LibraryOrganisationModels.swift
nonisolated enum LibraryTagRules {
    static let maxTags = 10, maxLength = 24
    static func normalised(_ raw: String) -> String?            // trim whitespace+newlines, NFC (precomposedStringWithCanonicalMapping); nil if empty
    static func key(_ tag: String) -> String                    // normalised.lowercased()
    static func validate(_ raw: [String]) -> Result<[String], LibraryTagError>   // dedupe by key keeping first; scalars ≤ 24; ≤ 10
}
nonisolated enum LibraryTagError: Error, Equatable { case empty, tooLong(String), tooMany }
nonisolated struct TitleOrganisationDelta: Equatable, Sendable {
    let key: MediaKey
    var addTags: [String]; var removeTags: [String]; var addListIds: [UUID]; var removeListIds: [UUID]
    var isEmpty: Bool
    /// The sheet's edit as a delta from what the sheet showed when it opened. Tags compare by LibraryTagRules.key
    /// (adds keep the edited spelling, removes send the original spelling); no key or list id is in both an add and a remove.
    static func between(key: MediaKey, originalTags: [String], editedTags: [String],
                        originalListIds: Set<UUID>, editedListIds: Set<UUID>) -> TitleOrganisationDelta
}
nonisolated struct TitleOrganisation: Equatable, Sendable {          // the server state a delta save returns
    let tags: [String]; let items: [OrganisationItemRow]; let changedLists: [OrganisationListRevision]
}
nonisolated struct OrganisationItemRow: Equatable, Sendable, Decodable { let listId: UUID; let itemId: UUID; let position: Double }
nonisolated struct OrganisationListRevision: Equatable, Sendable, Decodable { let listId: UUID; let revisionBefore: Int64; let revision: Int64 }
nonisolated enum OrganiseLoadState: Equatable { case notLoaded, loading, loaded, failed, unavailable }   // unavailable = flag off, or PGRST202 (not deployed)
nonisolated enum OrganiseError: Error, Equatable { case offline, notTracked, tagLimit, tagTooLong, listFull, listLimit, nameTaken, nameInvalid, notFound, staleList, unavailable, failed }
enum OrganiseCopy {   // EN/DE strings via KuroLocale for every W9 label, error and notice (incl. staleList, "Try again",
                      // "No longer in your library")
    static func error(_ error: OrganiseError, german: Bool) -> String
    static func allStrings(german: Bool) -> [String]          // every key, same order in both languages (render test)
}
nonisolated enum CollectionSelectionSource: Equatable { case imported, tag(String) }
// LibraryTagsStore.swift
@MainActor @Observable final class LibraryTagsStore: AccountScopedState {
    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, flags: FeatureFlags)
    weak var customLists: CustomListsStore?                     // applies the list half of an organise result
    var isEnabled: Bool { flags.libraryOrganiseV1Enabled }      // read at call time
    private(set) var tagsByKey: [MediaKey: [String]]            // W2 export input
    private(set) var loadState: OrganiseLoadState
    func tags(for key: MediaKey) -> [String]                    // binding name
    func allTags(kind: MediaKind?, tracked: Set<MediaKey>) -> [String]   // distinct by key, sorted by key, tracked titles only
    func keys(taggedWith tag: String, among tracked: Set<MediaKey>) -> Set<MediaKey>
    func load(force: Bool = false) async                        // flag off → .unavailable, no request; else rpc library_tag_index_v1
                                                                // in a credential lease; force false sends nothing when loadState == .loaded
    func saveOrganisation(_ delta: TitleOrganisationDelta) async -> Result<TitleOrganisation, OrganiseError>
        // flag off → .failure(.unavailable), no request; empty delta → .success(current state), no request;
        // else rpc apply_title_organisation_delta_v1 in a credential lease; MESSAGE code → OrganiseError;
        // publishes the server's tags (not the client's input) and hands items + changedLists to customLists,
        // only while the captured context is current
    func cancelAccountWork(); func clearPrivateState()
}
// CollectionStore (+ImportedTitles)
var selectionSource: CollectionSelectionSource?                 // nil when no selection; set with importedTitleKeys
func showTaggedTitles(_ tag: String, keys: Set<MediaKey>)       // same paging/hydration as showImportedTitles; source .tag(tag)
// showImportedTitles sets .imported; clearImportedTitles / clearPrivateState set nil
```

Steps
- [ ] Write the failing tests (`@MainActor @Suite("Library tags", .timeLimit(.minutes(1))) struct LibraryTagsStoreTests`, using `StubSupabase.makeClient(server:)` and a signed-in `AccountSessionCoordinator`, following `DiscoverUsabilityDataTests` setup). The store is built with `FeatureFlags(userDefaults: <fresh suite>, launchArguments: ["--ff-on=library_organise_v1"])` in every test except `flagOffSendsNoRequest`, so the other tests never fail because the flag is off.
  - `@Test func filterByTagShowsOnlyTaggedEntries() async` (traced):
    - The `LibraryStore` holds 2,000 entries (ids 1…2,000, `ControlledBackend`-free in-memory backend).
    - The stub answers `rpc/library_tag_index_v1` with `comfy` on ids 5 and 1,950, `rewatch` on 7, and `Comfy` on id 3,001, which is not tracked.
    - After `await tags.load()`: `#expect(tags.keys(taggedWith: "COMFY", among: trackedKeys) == [anime 5, anime 1950])`.
    - `collection.showTaggedTitles("comfy", keys: that set)`, then `#expect(collection.importedTitleKeys == [anime 5, anime 1950])` and `#expect(collection.selectionSource == .tag("comfy"))`.
    - `#expect(tags.allTags(kind: .anime, tracked: trackedKeys) == ["comfy", "rewatch"])`.
  - `@Test func flagOffSendsNoRequest() async`: flags without `--ff-on`; `await tags.load()`, `await tags.load(force: true)` and `await tags.saveOrganisation(<delta adding "comfy">)` → `server.requests.isEmpty`, `loadState == .unavailable`, and the save returns `.failure(.unavailable)`. Then turn the flag on in the same `FeatureFlags` instance: the stub answers `feature_flags` with `[{"flag_name":"library_organise_v1","enabled":true,"rollout_percentage":100}]` and the test awaits `flags.refresh(client:userId:)`. After that, `load()` sends exactly one `rpc/library_tag_index_v1`. This proves the flag is read at call time, not captured at init.
  - `@Test func organiseSaveSendsOnlyTheDelta() async` (two devices, client side):
    - The sheet opened with tags `["comfy"]` and lists `{L1}`; the user added `"slow burn"`, removed `"comfy"`, and unticked L1.
    - `TitleOrganisationDelta.between(...)` gives `addTags ["slow burn"]`, `removeTags ["comfy"]`, `addListIds []`, `removeListIds [L1]`.
    - The canonical request body is exactly `{"p_add_list_ids":[],"p_add_tags":["slow burn"],"p_media_id":1,"p_medium":"anime","p_remove_list_ids":["<L1>"],"p_remove_tags":["comfy"]}`. It contains no full tag set.
    - The stub answers with the server state, which includes another device's `"rewatch"` and membership L2: `{"tags":["rewatch","slow burn"],"items":[{"list_id":"<L2>",…}],"lists":[…]}`.
    - `tags.tags(for: anime 1) == ["rewatch","slow burn"]`.
    - An unchanged sheet (`between` with equal sets) is `isEmpty`, and its save sends nothing.
  - `@Test func normalisesAndCountsLikeTheDatabase()`:
    - `validate(["Comfy","comfy"," comfy "]) == .success(["Comfy"])`
    - `validate(["cafe\u{301}", "caf\u{E9}"]) == .success(["café"])`
    - `validate(["Émotion", "émotion"]) == .success(["Émotion"])` (the same pair 107 asserts on the server)
    - The server's answer is the truth: after a save, `tagsByKey` holds the tags `apply_title_organisation_delta_v1` returned, not the client's normalised input.
    - 24 × "😀" ok; 25 → `.tooLong`
    - `"👩‍👩‍👧"` counts 5 scalars
    - 11 distinct → `.tooMany`
    - `["  "]` → `.empty`
    - `between` never puts one key in both arrays: original `["Comfy"]`, edited `["comfy"]` → empty delta.
  - `@Test func saveMapsServerCodes() async`: the stub answers `{"code":"P0001","message":"TAG_LIMIT"}` (status 400) → `.failure(.tagLimit)`; `ENTRY_NOT_FOUND` → `.notTracked`; a transport failure → `.offline`.
  - `@Test func undeployedReaderIsUnavailableNotFailed() async`: a PGRST202 404 → `loadState == .unavailable` and `tagsByKey` is empty.
  - `@Test func tagsClearOnAccountSwitch() async`: start `load()` gated (`StubGate`); switch the account; release → `tagsByKey` stays empty, and `clearPrivateState()` empties a loaded store.
- [ ] Run `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/LibraryTagsStoreTests`. Expected FAIL: `cannot find 'LibraryTagsStore' in scope`.
- [ ] Implement the flag accessor, the models, the store and the Collection selection source.
  - Every async method reads `isEnabled` first and returns before building any request when it is off.
  - It then captures `accountSession.current`, runs the SDK call inside `accountSession.withCredentialLease(for: account) { … }` (the `HomeStore.detailBundle` pattern, `Kuro/Home/HomeStore.swift:99`), and checks `isCurrent` before publishing.
  - `print` only inside `#if DEBUG`.
- [ ] Run again. Expected: 7 pass. Also run `-only-testing:KuroTests/LibraryFacadeTests` (it exercises `showImportedTitles`). Expected: pass.
- [ ] Commit: `git add Kuro/Services/FeatureFlags.swift Kuro/Library/LibraryOrganisationModels.swift Kuro/Library/LibraryTagsStore.swift KuroTests/LibraryTagsStoreTests.swift Kuro/Collection/CollectionStore.swift Kuro/Collection/CollectionStore+ImportedTitles.swift`; message `W9: tag owner behind library_organise_v1; delta organise saves; Collection filters by tag across the whole library`.

### Task W9.5: `CustomListsStore` (lists, revisions, order, seed, export objects)

**Files:** create `Kuro/Library/CustomListsStore.swift` and `KuroTests/CustomListsStoreTests.swift`.

**Interfaces (Produces):**
```swift
struct CustomList: Identifiable, Equatable { let id: UUID; var name: String; var items: [MediaKey] }   // binding
struct CustomListMeta: Equatable, Sendable { let createdAt: Date; var revision: Int64 }
struct CustomListRemoval: Equatable { let listId: UUID; let slot: CustomListSlot; let revisionAfter: Int64; let account: AccountContext }
struct CustomListPendingMove: Equatable, Sendable {   // what a stale move meant, by neighbour ids (survives a reload)
    let listId: UUID; let itemId: UUID; let afterItemId: UUID?; let beforeItemId: UUID?; let account: AccountContext; let isRetry: Bool
}
enum CustomListMoveOutcome: Equatable { case moved, stale(CustomListPendingMove), failed(OrganiseError) }
struct CustomListSeedReport: Equatable { var created: [String]; var reused: [String]; var skipped: [String]; var added: Int }
@MainActor @Observable final class CustomListsStore: AccountScopedState {
    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, flags: FeatureFlags)
    weak var library: LibraryStore?
    var isEnabled: Bool { flags.libraryOrganiseV1Enabled }      // read at call time
    private(set) var lists: [CustomList]                        // binding; sorted by LibraryTagRules.key(name)
    private(set) var meta: [UUID: CustomListMeta]               // created_at + revision per list (from custom_lists_v1)
    private(set) var slots: [UUID: [CustomListSlot]]            // ordered per list
    private(set) var media: [MediaKey: Media]                   // hydrated public catalogue rows
    private(set) var loadState: OrganiseLoadState
    func isTracked(_ key: MediaKey) -> Bool                     // library?.isTracked; drives the "No longer in your library" row
    func load(force: Bool = false) async                        // flag off → .unavailable, no request; rpc custom_lists_v1 in a
                                                                // credential lease; force false sends nothing when loadState == .loaded
    func create(name: String) async -> Result<CustomList, OrganiseError>
    func rename(_ id: UUID, to name: String) async -> Result<Void, OrganiseError>
    func delete(_ id: UUID) async -> Result<Void, OrganiseError>
    func move(in listId: UUID, fromOffsets: IndexSet, toOffset: Int) async -> CustomListMoveOutcome
        // optimistic reorder; CustomListOrder.move → .single → move_custom_list_item_v1(list, item, after, before,
        // meta[list].revision) | .rebalance → rebalance_custom_list_v1(list, ids, revision); adopts the returned revision.
        // STALE_LIST → rolls back, reloads (load(force: true)) and returns .stale(pending) WITHOUT sending another move;
        // ITEM_NOT_FOUND → reload, .failed(.notFound); other failures roll the projection back
    func retry(_ pending: CustomListPendingMove) async -> CustomListMoveOutcome
        // called only from the user's "Try again"; same account only; re-derives the target from the neighbour ids in
        // the reloaded list (a missing item → .failed(.notFound)); a second STALE_LIST → .failed(.staleList), never .stale
    func remove(_ key: MediaKey, from listId: UUID) async -> CustomListRemoval?   // delta remove of this one list;
        // nil (no Undo) when the removal failed or the title is not tracked (a re-add would raise ENTRY_NOT_FOUND)
    func undo(_ removal: CustomListRemoval) async -> Bool       // delta re-add (appends); then, only when the add's
        // revision_before == removal.revisionAfter, move_custom_list_item_v1 back to removal.slot's neighbours with the
        // add's revision; STALE_LIST there → reload, the title stays re-added at the end; same account only
    func exportLists() -> [ExportCustomList]?                   // W2's ordered list-objects input: W2's KuroLibrary type
        // `ExportCustomList(id:name:createdAt:items: [MediaKey])` (02-export.md; W9 builds it, never redefines it).
        // nil unless loadState == .loaded. Lists in `lists` order; createdAt from meta; items in manual order
        // (CustomListOrder.ordered); empty lists and items no longer in the library included. W2 derives position
        // (1-based rank), in_library (key among the export's entries) and title (catalogue) itself.
    func importedListNames() -> [(name: String, keys: [MediaKey])]   // from library.allEntries sourceMetadata.customLists,
        // grouped case-insensitively (first spelling wins), keys in library order, names that already exist excluded
    func seedFromImport() async -> Result<CustomListSeedReport, OrganiseError>   // ONE rpc seed_custom_lists_v1 in a
        // credential lease, then load(force:)
    func hydrate(_ keys: [MediaKey]) async                      // public catalogue read (no lease): ≤ 30 keys/call; anime/manga
        // select like CollectionStore's ImportedCatalogRow (same columns); keeps caller order; untracked titles allowed
    func apply(_ organisation: TitleOrganisation, for key: MediaKey)   // called by LibraryTagsStore after a save:
        // updates this title's membership; adopts a changed list's revision only when revisionBefore == meta revision
    func cancelAccountWork(); func clearPrivateState()
}
```

Steps
- [ ] Write the failing tests (`@MainActor @Suite("Custom lists", .timeLimit(.minutes(1))) struct CustomListsStoreTests`). Every test except `flagOffSendsNoRequest` builds the store with `--ff-on=library_organise_v1`.
  - `@Test func importedCustomListNamesCanSeedLists() async` (traced):
    - The library holds anime 1 (`customLists ["Favourites","To rewatch"]`), manga 2 (`["favourites"]`) and anime 3 (`nil`).
    - `importedListNames()` == `[("Favourites", [anime 1, manga 2]), ("To rewatch", [anime 1])]`.
    - `await store.seedFromImport()` sends exactly one `rpc/seed_custom_lists_v1` whose canonical body is `{"p_lists":[{"items":[{"media_id":1,"medium":"anime"},{"media_id":2,"medium":"manga"}],"name":"Favourites"},{"items":[{"media_id":1,"medium":"anime"}],"name":"To rewatch"}]}`.
    - The stub answers `{"created":["Favourites","To rewatch"],"reused":[],"skipped":[],"added":3}`, then `custom_lists_v1` returns both lists with their items.
    - `#expect(store.lists.map(\.name) == ["Favourites","To rewatch"])` and `#expect(store.lists[0].items == [anime 1, manga 2])`.
  - `@Test func flagOffSendsNoRequest() async`: flag off; `load()`, `create(name:)`, `move(…)`, `seedFromImport()` and `remove(_:from:)` send nothing (`server.requests.isEmpty`); `loadState == .unavailable`; `exportLists() == nil`; the writes return `.failure(.unavailable)` / `.failed(.unavailable)` / `nil`.
  - `@Test func seedingTwiceCreatesNoDuplicatesAndReportsSkips() async`: once both lists exist, `importedListNames()` is empty and `seedFromImport()` sends nothing. A seed report with `skipped: ["Extra"]` surfaces in the result.
  - `@Test func moveSendsOneRowThenRebalancesWhenExhausted() async`:
    - Three items in one list at revision 4; `move(fromOffsets:[2], toOffset:1)` sends `rpc/move_custom_list_item_v1` with `{"p_after_position":1024,"p_before_position":2048,"p_expected_list_revision":4,"p_item_id":…,"p_list_id":…}`. The answer `{"position":1536,"revision":5}` sets `meta[list].revision == 5`.
    - With positions `[1, 1.nextUp, 3]`, it sends `rpc/rebalance_custom_list_v1` with all three ids in the new order and `p_expected_list_revision`.
  - `@Test func staleReorderReloadsAndRetriesOnlyOnRequest() async`:
    - The server answers the move with `STALE_LIST`. The store sends `custom_lists_v1` once (reload), the projection equals the server order, and the outcome is `.stale(pending)`.
    - Exactly **one** `move_custom_list_item_v1` request has been sent (no silent retry).
    - `retry(pending)` sends one more move, against the reloaded revision, at the position re-derived from `pending`'s neighbour ids. When the server answers `STALE_LIST` again → `.failed(.staleList)`, with no further retry offered and two moves in total.
    - A `retry` whose account is no longer current sends nothing.
  - `@Test func removeAndUndoRestoresPosition() async`: removing the middle item, then Undo, sends `apply_title_organisation_delta_v1` (re-add, with `p_add_list_ids` = that list only), then `move_custom_list_item_v1` to the original neighbours with the revision the add returned. The final order equals the original. When the add reports a `revision_before` different from `removal.revisionAfter`, no move is sent and the title stays at the end.
  - `@Test func orphanRemovalOffersNoUndo() async`: for a key that `LibraryStore` does not track, `remove(_:from:)` sends the removal and returns `nil` (no Undo receipt).
  - `@Test func exportListsKeepManualOrderEmptyListsAndRemovedTitles() async`:
    - Before `load()` → `exportLists() == nil`.
    - `custom_lists_v1` returns "Comfort" (created `2026-10-01T…`, items anime 1 at 2048 and manga 2 at 1024) and an empty "Later".
    - The library tracks anime 1 only.
    - `exportLists()` == `[ExportCustomList(id: <Comfort>, name: "Comfort", createdAt: <server's>, items: [manga 2, anime 1]), ExportCustomList(id: <Later>, name: "Later", createdAt: <server's>, items: [])]`: manual order, the untracked manga kept, the empty list included.
    - `customLists.isTracked(manga 2) == false` (the list page's "No longer in your library" line).
  - `@Test func workFromPreviousAccountNeverPublishes() async`: hold `move` and `seedFromImport` on a `StubGate`, switch the account, release → `lists` and `slots` stay empty for the new account; `undo` of the old account's removal returns false and sends nothing.
  - `@Test func listLimitAndNameErrorsMapToCopy() async`: `LIST_LIMIT` → `.listLimit`, `LIST_NAME_TAKEN` → `.nameTaken`, `STALE_LIST` on a rebalance → `.stale`; `OrganiseCopy.error(.listLimit, german: true)` and `OrganiseCopy.error(.staleList, german: true)` are non-empty and differ from the EN strings.
- [ ] Run `xcodebuild … -only-testing:KuroTests/CustomListsStoreTests`. Expected FAIL: `cannot find 'CustomListsStore' in scope`.
- [ ] Implement. Every private request (`custom_lists_v1`, create, rename, delete, move, rebalance, seed, and the delta calls of `remove`/`undo`) reads `isEnabled` first, captures the account, and runs inside `accountSession.withCredentialLease(for: account) { … }`. `hydrate` is a public catalogue read and takes no lease.
- [ ] Run again. Expected: 10 pass.
- [ ] Commit: `git add Kuro/Library/CustomListsStore.swift KuroTests/CustomListsStoreTests.swift`; message `W9: custom lists owner (revision-guarded moves with retry on request, Undo, seed from imported names, export objects, account-safe)`.

### Task W9.6: Composition, export wiring and the credential-lease test

**Files:** modify `Kuro/Composition/AppComposition.swift`, `Kuro/KuroApp.swift` and `KuroTests/IdentityCompositionTests.swift`; create `KuroTests/OrganiseCredentialLeaseTests.swift`.

**Interfaces**
- `AppGraph` gains `let libraryTags: LibraryTagsStore` and `let customLists: CustomListsStore`, both built once in `makeGraph` (and `testingGraph`) over the single client and the one injected `FeatureFlags`.
- Wiring: `libraryTags.customLists = customLists`, `customLists.library = wiring.store`.
- `makeAccountScopedStates(…, libraryTags:, customLists:)` places them right after `collection`: `[libraryActions, home, collection, libraryTags, customLists] + …` (final order in `00-program.md`).
- `KuroApp` injects `.environment(libraryTags)` and `.environment(customLists)`.
- `SessionSDKHarness` (`KuroTests/IdentityCompositionTests.swift:361`) takes `flags: FeatureFlags? = nil`, passed to `AppComposition.testingGraph(…, flags:)`. F2.3 adds it (F2 merges before W2 and W9); add it here only if it is missing. Existing call sites are unchanged.
- **Export wiring.** W2 merges before W9 (`00-program.md` merge order), so W9.6 wires it. `makeLibraryExport` passes:
  - `tagsByKey: { [weak libraryTags] in guard let libraryTags else { return nil }; guard libraryTags.isEnabled else { return [:] }; await libraryTags.load(); return libraryTags.loadState == .loaded ? libraryTags.tagsByKey : nil }`
  - `customLists: { [weak customLists] in guard let customLists else { return nil }; guard customLists.isEnabled else { return [] }; await customLists.load(); return customLists.exportLists() }` (W2's `@MainActor () async -> [ExportCustomList]?`). `isEnabled` reads `FeatureFlags.libraryOrganiseV1Enabled`, the same check as W2's sketch, which reads `flags` directly.

  `nil` means "could not load", which W2 reports as `summary.organisationUnavailable` instead of silently exporting without tags and lists. A disabled flag returns the empty value without a request (Decisions). If the merge order ever changes so that W9 lands first, W9.6 skips this wiring and W2's composition task does it.

Steps
- [ ] Update the test `IdentityCompositionTests.expectedAccountScopedStates` to `[g.libraryActions, g.home, g.collection, g.libraryTags, g.customLists, g.discovery, …]`, and add `@Test func organisationOwnersAreWiredOnce()`: `g.libraryTags.customLists === g.customLists` and `g.customLists.library === g.library`.
- [ ] Write `OrganiseCredentialLeaseTests.swift`: `@MainActor @Suite("W9: organisation requests carry their own account's credential", .timeLimit(.minutes(1))) struct OrganiseCredentialLeaseTests`, modelled on `CredentialLeaseTests.preDispatchSwitchForEveryFamily` (read `KuroTests/CredentialLeaseTests.swift` first and reuse `signedInAsAKeepingBsSession`'s steps).
  - `enum OrganiseFamily: CaseIterable { case tagIndex, listsLoad, organiseDelta, createList, renameList, deleteList, move, rebalance, seed }`. Each case starts its call on `h.graph.libraryTags` / `h.graph.customLists`, and `matches(_:)` names its `rpc/<name>`.
  - `@Test(arguments: OrganiseFamily.allCases) func preDispatchSwitchSendsNoOrganiseRequestAsB(family:)`:
    - `SessionSDKHarness(responder: …, flags: FeatureFlags(userDefaults: <fresh suite>, launchArguments: ["--ff-on=library_organise_v1"]))`.
    - Sign in as A, keeping B's SDK session. Start the family's call for A, then `h.storage.replace(with: sessionB)` and `applySession(userId: B)` before dispatch.
    - Expect no matching request at all (`h.server.requests.filter(family.matches).isEmpty`), in particular none whose `bearerSubject` is B. The outcome is "dropped" or not accepted, never success.
- [ ] Run `xcodebuild … -only-testing:KuroTests/IdentityCompositionTests -only-testing:KuroTests/OrganiseCredentialLeaseTests`. Expected FAIL: `value of type 'AppGraph' has no member 'libraryTags'`.
- [ ] Implement the composition and the export wiring.
- [ ] Run again. Expected: pass. **Non-vacuity check** (the lease test reaches stores written in W9.4/W9.5):
  - Temporarily replace the lease in `CustomListsStore.create` with a direct `client.rpc(...)` call. Run `-only-testing:KuroTests/OrganiseCredentialLeaseTests`. Expected: the `createList` case FAILS (a `create_custom_list_v1` request is recorded after the switch).
  - Revert in the same step and re-run. Expected: pass. Record both lines in the evidence.
- [ ] Run `-only-testing:KuroTests/LibraryExportFlowTests` → pass. Run `scripts/quality-gates/check_architecture.sh`. Expected: 0 offenders (no SDK import in views, no second client).
- [ ] Commit: `git add Kuro/Composition/AppComposition.swift Kuro/KuroApp.swift KuroTests/IdentityCompositionTests.swift KuroTests/OrganiseCredentialLeaseTests.swift`; message `W9: compose and register tag and custom-list owners; export providers; credential-lease test`.

### Task W9.7: Screens: tag words, lists journey, Arrange, organise sheet

**Files:** create `Kuro/Views/Lists/FolioOrganiseRows.swift`, `Kuro/Views/Lists/CustomListPages.swift`, `Kuro/Views/Lists/CustomListSheets.swift` and `KuroTests/OrganiseRenderTests.swift`; modify `Kuro/Views/Lists/FolioItems.swift` and `Kuro/Views/EditorialCollectionView.swift`.

**Navigation (Rule 5):**
| Surface | Kind | Opened by | Close |
|---|---|---|---|
| `FolioTagWords` | local filter words on the Collection page (no navigation) | page | "All lists" clears the selection |
| "Your lists · N ›" (`FolioListsLink`) → `CustomListsJourneyPage` | root journey via `routes.openPage(.custom(AnyJourneyPage(CustomListsJourneyPage())))` | Collection header | ✕ / swipe-down |
| `CustomListJourneyPage(listId:)` | pushed page (`routes.openPage(.custom(...))` inside the journey) with `.kuroJourneyChrome(title:)`, back chevron + edge swipe | index row | Back / ✕ |
| `CustomListNameSheet` (create / rename) | tool sheet, `.kuroLeavesJourney()`, `.kuroNavigationLayer("lists.name", item:)`, `.kuroDiscardGuard(isDirty:isBusy:isConfirming:onDiscard:)`, visible Cancel | index "New list", list "Rename" | Cancel / Save |
| `TitleOrganiseSheet(media:)` (tags + lists; ONE `saveOrganisation(TitleOrganisationDelta.between(original, edited))` write, from the snapshot taken when the sheet opened) | tool sheet with the same three modifiers, registered as `collection.organise` / `lists.organise` | Folio context menu "Tags & lists…" / "Schlagwörter & Listen…", list-page row menu (tracked titles only) | Cancel / Save |
| Delete list | `.confirmationDialog`, destructive red role only | list page "Delete list" | Cancel |
| Seed offer "Your import had N lists. Create these lists" | inline row on the index page (shown when `importedListNames()` is non-empty) | — | "Not now" hides it for the session |
| Stale-move notice "This list changed on another device. Your move was not saved." / "Diese Liste wurde auf einem anderen Gerät geändert. Deine Verschiebung wurde nicht gespeichert." + "Try again" / "Erneut versuchen" | `FolioNoticeBar`-style notice on the list page after `.stale(pending)`; "Try again" calls `retry(pending)` once; after `.failed(.staleList)` the notice has no action | a move | auto-hides |

- Every title row opens its target (`routes.openMedia(MediaRoute(key))`), including rows no longer in the library.
- A row whose title is not tracked (`customLists.isTracked(key) == false`) shows the quiet second line "No longer in your library" / "Nicht mehr in deiner Bibliothek". Its menu holds only "Remove from list" (no Undo).
- After a save, the organise sheet shows the server's tags and membership (another device's changes appear).
- Arrange mode uses `List` + `.onMove` + `EditMode` toggled by the words "Arrange" / "Done" ("Ordnen" / "Fertig"). It lives only in the pushed list page, never on the pager page (no conflict with the horizontal pager swipe).
- Removing an item is a context-menu action with an Undo notice (`FolioNoticeBar` style), never a horizontal swipe.
- When `loadState == .unavailable` (flag `library_organise_v1` off, or RPC not deployed), the tag words, the lists link and the context-menu item are hidden.
- Loading, offline and failed states use `KuroStateView` / branded states only.

Steps
- [ ] Write the failing render tests (`@MainActor @Suite("Organise screens render", .serialized) struct OrganiseRenderTests`, hosting in a window attached to the foreground `UIWindowScene` as in `NavdetailTests`). For EN and DE at `.accessibility5`:
  - `CustomListsJourneyPage` (2 lists + seed offer), `CustomListJourneyPage` (3 items, one untracked showing "No longer in your library", Arrange on, the stale-move notice with "Try again"), `TitleOrganiseSheet` (3 tags, 2 lists checked) and `FolioTagWords` (5 tags) each render with a non-zero height, and their hosting view has no ambiguous layout (`hasAmbiguousLayout == false`).
  - `#expect(OrganiseCopy.allStrings(german: true).allSatisfy { !$0.isEmpty })` and EN ≠ DE for every key (including the untracked-row line, the stale-move notice and "Try again").
- [ ] Run `xcodebuild … -only-testing:KuroTests/OrganiseRenderTests`. Expected FAIL: `cannot find 'CustomListsJourneyPage' in scope`.
- [ ] Implement the views:
  - Add `organise` to `FolioRowActions` and the context-menu item.
  - In `EditorialCollectionView`:
    - the tag strip shows under the status strip when `!libraryTags.allTags(kind: medium, tracked:).isEmpty`;
    - the lists link sits in the header;
    - the selection header reads "Tagged “comfy”" / "Markiert „comfy“" for `.tag`;
    - add `.sheet(item: $organiseTarget)` and `.kuroNavigationLayer("collection.organise", item: $organiseTarget)`.
  - On page appear, `.task { await libraryTags.load(); await customLists.load() }`, account-scoped and flag-gated by the owners (a disabled flag sends nothing).
- [ ] Run again. Expected: pass. Run `scripts/quality-gates/check_navigation.sh && scripts/quality-gates/check_branded_states.sh && scripts/quality-gates/check_architecture.sh`. Expected: 0 offenders each. Run `xcodebuild … -only-testing:KuroTests/NavigationEvidenceTests -only-testing:KuroTests/JourneyPolicyTests`. Expected: pass.
- [ ] Commit: `git add Kuro/Views/Lists/FolioOrganiseRows.swift Kuro/Views/Lists/CustomListPages.swift Kuro/Views/Lists/CustomListSheets.swift Kuro/Views/Lists/FolioItems.swift Kuro/Views/EditorialCollectionView.swift KuroTests/OrganiseRenderTests.swift`; message `W9: tag words, Your lists journey with Arrange, tags & lists tool sheet`.

### Task W9.8: Load profile `collection-with-tags-and-lists` (reads and writes)

**Files:** create `scripts/load/profiles/collection-with-tags-and-lists.js` and `scripts/load/profiles/collection-with-tags-and-lists.test.js`; modify `scripts/load/workloads/tracker-gaps-combined.js` (one line).

**Contract.** F3's profile contract exactly as `00-foundation.md` defines it: F3.1 (registry, `ratePerSecond`, separate absolute-rate lane on top of the unchanged base 20 rps; a `weight` field throws), F3.1b (`operations` with `share`, `core`), F3.1c (`emptyExamples`, `requires`, `payloads`, `seed`, `cleanupCheck`, `validate(…, ctx)` with `ctx.mode`, `--qualify`, `tracker-gaps-combined`).

**Interfaces (Produces):**
```js
module.exports = {
  name: "collection-with-tags-and-lists",
  operations: {                                            // F3.1b: samples recorded as "collection-with-tags-and-lists:<op>"
    "tag-index":  { budgetClass: "browse",   share: 0.28 }, // library_tag_index_v1                      (slots 0–6)
    "lists":      { budgetClass: "browse",   share: 0.24 }, // custom_lists_v1                           (slots 7–12)
    "delta":      { budgetClass: "progress", share: 0.16 }, // apply_title_organisation_delta_v1         (slots 13–16)
    "move":       { budgetClass: "progress", share: 0.12 }, // move_custom_list_item_v1                  (slots 17–19)
    "rebalance":  { budgetClass: "progress", share: 0.04 }, // rebalance_custom_list_v1                  (slot 20)
    "create":     { budgetClass: "progress", share: 0.04 }, // create_custom_list_v1                     (slot 21)
    "seed":       { budgetClass: "progress", share: 0.04 }, // seed_custom_lists_v1                      (slot 22)
    "delete":     { budgetClass: "progress", share: 0.08 }, // delete_custom_list_v1 of the -c and -s lists (slots 23–24)
  },
  ratePerSecond: 5,                 // absolute rate in the profile lane (plan-stated); the base mix keeps its 20 rps
  librarySizes: [100, 2000],        // the fixture's typical (100-title) and maximum (2,000-title) accounts
  writes: true,
  payloads: ["typical", "maximum"], // every request names one (rule below)
  emptyExamples: [[], {}, null, { tags: [] }],   // qualify must reject each for every operation (unknown request → false)
  requires(fixture, actor),         // "no seeded organisation fixture" unless actor.profileState[name] holds the 20 list ids,
                                    //   the 2,000-item list id (2,000-title actors) and the 9-tag title keys
  seed({ actor, fixture, call, core }),   // F3.1c seed-profiles, with the actor's own token (no service role), before the
                                          //   measured window (not counted): creates the populated fixture below through
                                          //   create_custom_list_v1 / apply_title_organisation_delta_v1 / seed_custom_lists_v1;
                                          //   returns { listIds, maxListId, nineTagKeys, revisions }
  request(actor, fixture, seq, random, core) {
    // 25-slot cycle (each slot 4 %), one operation per arrival (slot → operation as in `operations` above):
    //   tag-index / lists: the actor's reads ·
    //   delta: on a 9-tag title alternately add / remove the 10th tag "load-t" (the supported maximum, 10 tags per entry),
    //          and add / remove a list membership ·
    //   move: alternately a typical 100-item list and the 2,000-item list, with after/before positions and
    //         p_expected_list_revision from the actor's state ·
    //   rebalance: alternately a typical list and the 2,000-item list (all 2,000 ids) ·
    //   create: "load-<run>-<actor>-<cycle>-c" · seed: 50 tracked titles into "load-<run>-<actor>-<cycle>-s" (a fresh
    //   name every cycle, so every seed adds 50) · delete: the "-c" and "-s" lists, so the actor returns to its 20 lists.
    //   Writes for one list are never in flight twice: per-actor state (like the predeclared "progress" kind keeps
    //   actor.writeEntry); a list with a write in flight is skipped.
    // payload: "maximum" when the request touches a supported maximum (a 2,000-title actor's reads, create, seed and
    //   delete; the delta's tag leg that reaches 10 tags; a move or rebalance on the 2,000-item list), else "typical".
    // returns { path: "/rest/v1/rpc/<rpc>", body, operation, payload }
  },
  validate(data, actor, request, ctx) {
    // ctx.mode "wiring" (default, never release evidence): shapes only. Tag index: array of {medium in anime|manga,
    // integer media_id, string[] tags}; lists: array of {id, name, created_at, integer revision, items[]} with integer
    // media_id; an empty array is valid. Writes: the documented jsonb shape. Carries the returned revision forward
    // into the actor's state (as backend_workload.js does for "progress").
    // ctx.mode "qualify": the semantic validators below.
  },
  cleanupCheck({ actor, state, call }),   // F3.1c, after the disposable account's auth 404: service-role
                                          //   GET /rest/v1/library_tags?user_id=eq.<id>&select=user_id&limit=1,
                                          //   GET /rest/v1/custom_lists?user_id=eq.<id>&select=id&limit=1 and
                                          //   GET /rest/v1/custom_list_items?user_id=eq.<id>&select=id&limit=1 all return []
                                          //   (proves delete-account / FK cascade left nothing behind)
};
```
- Combined workload line: `"collection-with-tags-and-lists": 5`.

**Qualification mode (`--qualify`), binding behaviour:**
- **Populated fixture** (written by `seed` before the measured window through the actors' own RPCs, so no service role is needed; seed requests are not counted):
  - 2,000-title actors (F3.2 shape): 20 lists, 19 × 100 items plus one list with the supported maximum of 2,000 items (3,900 items ≤ 10,000). Every 2nd title carries 1–3 tags; 10 titles carry 9 tags, so the delta reaches 10.
  - 100-title actors (the fixture's typical size): 20 lists × 10 items, tags on every 2nd title, 10 titles with 9 tags.
- **Semantic validators.** A qualification run fails, never passes, on an empty-array answer where the fixture guarantees data:
  - Tag index: ≥ 1,000 rows for a 2,000-title actor (≥ 50 for a 100-title actor); at least one row with ≥ 9 tags.
  - Lists: the 20 seeded lists (plus at most the actor's two transient `load-*` lists, so a failed delete shows up as a failed sample), and, for 2,000-title actors, the 2,000-item list with strictly ascending positions.
  - Delta: the returned `tags` contain the added tag or lack the removed one, and the item count ≤ 10.
  - Move: the returned position is strictly between `after` and `before`, and `revision` = expected + 1.
  - Rebalance: positions are `1024·i`.
  - Create: returns the name.
  - Seed: `added = 50`.
  - Delete: 2xx.
- **Answers that count as failures.** A `STALE_LIST` or `LIST_LIMIT` answer is a failed sample (the schedule raced itself), never ignored.
- **Minimum samples (F3.1c `QUALIFY_MIN`).** At 5 rps × 600 s = 3,000 arrivals, the rarest operations (`rebalance`, `create`, `seed`, share 0.04) expect 120 completions ≥ 100, i.e. 60 per subgroup ≥ 30 (2 subgroups) and 60 per payload ≥ 30 (2 payloads); every other operation expects more. Fewer → `insufficient`, never `pass`; a shorter run is refused by the preflight.
- **Cleanup verification** (F3.1c `cleanupCheck`): after each disposable account is deleted, none of its `library_tags`, `custom_lists` or `custom_list_items` rows remain; anything left makes the fixture cleanup throw (`Profile data cleanup not confirmed`) and F1.3 does not accept the load scenario.
- Reports keep this profile's lane separate from the base mix (F3), so the base regression comparison stays like-for-like.

Steps
- [ ] Write the failing test `collection-with-tags-and-lists.test.js`:
  - `W.loadProfiles()` contains the profile at `ratePerSecond === 5` with no `weight` key; `W.selectProfiles({ names: ["collection-with-tags-and-lists"] }).limits` has the eight `collection-with-tags-and-lists:<op>` keys, `tag-index` and `lists` at 750 (browse) and the six write operations at 750 (progress); `W.loadWorkload("tracker-gaps-combined").profiles["collection-with-tags-and-lists"] === 5`.
  - Over one 25-slot cycle, `request` yields exactly the eight RPC paths above in the declared shares, each naming its `operation` and a `payload`. No path matches `/bulk-import|release-intake|apply_remove/`. Every write body has its required parameters: the move has `p_expected_list_revision` and after/before; the rebalance on the max list has 2,000 ids; the delta on the max-tag title brings it to exactly 10 tags.
  - Per-list writes never overlap: a list with a write in flight is skipped.
  - Wiring `validate` (`{ mode: "wiring" }`) rejects `{}`, `[{"medium":"film","media_id":1,"tags":[]}]` and `[{"id":"x","name":"n","items":[{"media_id":"1"}]}]`, and accepts `[]` and well-formed rows. Qualify `validate` (`{ mode: "qualify" }`) rejects every `emptyExamples` entry, `[]` for the tag index and the lists of a seeded actor, and a move answer whose revision is not expected + 1.
  - `requires` names the reason for an unseeded actor and is `null` after `seed` (run against a `call` double); `seed` uses only the actor token.
  - `W.qualifyVerdicts` over simulated samples: 99 `rebalance` completions (or 29 in one subgroup, or 29 `maximum` payloads) → that endpoint `insufficient`.
  - `cleanupCheck` is true when the three service-role reads return `[]` and false when any returns a row.
  - The predeclared base mix is untouched (F3's frozen-digest test still passes; `JSON.stringify(W.WEIGHTS)` unchanged, no profile key in it).
- [ ] Run `node --test scripts/load/profiles/collection-with-tags-and-lists.test.js`. Expected FAIL: `Cannot find module './collection-with-tags-and-lists'`.
- [ ] Implement the profile and add its line to `tracker-gaps-combined.js`.
- [ ] Run `bash scripts/quality-gates/test_load_profiles.sh`. Expected: all pass, including F3's frozen-digest test and `combined workload names every profile with an explicit rate`. Run `bash scripts/quality-gates/check_bdd_traceability.sh | grep collection-with-tags-and-lists`. Expected: no finding for that scenario.
- [ ] Commit: `git add scripts/load/profiles/collection-with-tags-and-lists.js scripts/load/profiles/collection-with-tags-and-lists.test.js scripts/load/workloads/tracker-gaps-combined.js`; message `W9: load profile for tag/list reads and organisation writes (Browse/Progress), qualification fixture and cleanup`.

### Task W9.9: Docs, memory, verification and evidence

**Files:** `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `CLAUDE.md` (file map: `Kuro/Library/` owners, `Views/Lists/` files, counts, pending migration, flag), `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md`, and `docs/tracker-gaps-2026-11/lists/EVIDENCE.md`.

Steps
- [ ] Rule 1:
  - Technical and plain-English sections: tags, custom lists, the organise sheet, the delta contract and `STALE_LIST`, list items surviving library removal, the prepared migration (NOT applied), the RPC list and grants, the deletion cascade, the flag `library_organise_v1` (0 %), the load profile, and the three release switches (migration approval, qualification-mode run, flag); Change Log entries in both.
  - `IMPLEMENTATION_PLAN_Variation1.md`: W9 status.
  - Update the inventory sentences checked by `check_docs_current_state.py`: +6 app Swift files in `Kuro/` (`LibraryOrganisationModels`, `LibraryTagsStore`, `CustomListsStore`, `FolioOrganiseRows`, `CustomListPages`, `CustomListSheets`) and +2 package files (`CustomListOrder.swift`, `CustomListOrderTests.swift`). Also update the KuroTests count in the CLAUDE.md file map (+4). Take the exact numbers from the script's expected text, not from arithmetic. Run `python3 scripts/quality-gates/check_docs_current_state.py`. Expected: `PASS`.
- [ ] Rule 2: in MEMORY.md, record:
  - the new files and counts;
  - the decisions (fence reading, title-keyed rows that survive library removal, bounds, delta writes, list revision, flag-off export returns empty);
  - the gotchas: scalar counting and NFC; the 50-test CASCADE string; the deletion scenario retag; the PGRST202 → `.unavailable` fallback; flags read at call time; the two-device test uses the same user in two sessions.
- [ ] Verification (expected outputs):
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → no FAIL; `bdd-selftest PASS`.
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → `** TEST SUCCEEDED **`; unique Kuro-side warnings ≤ 60.
  - `check_architecture.sh`, `check_navigation.sh` and `check_branded_states.sh` → 0.
  - `bash scripts/quality-gates/check_bdd_traceability.sh` → no W9 finding (the `@pkg:LibraryEditV2Tests`/`PartialDateTests` scenarios resolve once F2 has landed).
  - `cd Packages/KuroModules && swift test` → pass.
  - `scripts/db/run_local_db_tests.sh` → TESTS PASS, including both `concurrency/108_*` files. Also `--exclude-pending --only 107_library_tags,108_custom_lists` → FAIL at the first assertion (red evidence).
  - `deno test --no-prompt supabase/functions/delete-account/` → pass (unchanged).
  - `bash scripts/quality-gates/test_load_profiles.sh` → pass.
  - Append `W9-lists.feature` to `scripts/quality-gates/bdd_landed.txt` (F1 landed scope); `check_bdd_traceability.sh` → exit 0. Write the execution record `docs/tracker-gaps-2026-11/acceptance/W9.json` per F1 (resolved ≠ accepted). Its load scenario stays `blocked` until a qualification-mode run id exists; the 107/108 scenarios count only from the harness's per-file `PASS … 0 blocked markers` lines. The F2 Rule's scenarios belong to workstream `F2` (`@workstream-F2`) and are not in this record. Write it in F1.3's schema: start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template W9`; workstream `W9` (the feature basename up to its first `-`, spec §4); `runs[]` with the exact command, `context` (`simulator` + UUID for `@swift`/`@ui`, `local-db` for `@sql`, `load-qualification` with report, `runKey` and cleanup report for `@load`) and a log under `docs/tracker-gaps-2026-11/acceptance/logs/W9-<run id>.txt`; one `scenarios[]` entry per non-gated scenario with its current tag. Commit order (F1.3 rule 2): make the docs/evidence commit first, run the gates on that clean commit, then commit only `docs/tracker-gaps-2026-11/acceptance/W9.json` and `acceptance/logs/` (message `W9: acceptance record`); nothing outside that folder may change after the tested commit. Run `check_bdd_traceability.sh --accepted W9` and record the output (expected `exit=1` until the qualification run).
- [ ] Write `docs/tracker-gaps-2026-11/lists/EVIDENCE.md`. It contains:
  - each traced scenario → its test, with red and green lines;
  - the non-vacuity check of W9.6 (fail line, then pass after revert);
  - the EXPLAIN plan excerpts (`LOAD_PLAN` notices) for 107/108;
  - the scenario retag note;
  - the owner checklist:
    - approve `20261118120000_library_tags_custom_lists_v1.sql` by name and checksum (`shasum -a 256`);
    - apply it in one transaction;
    - re-run 107/108 read-only checks live;
    - run the load qualification in qualification mode with the `collection-with-tags-and-lists` profile on the populated fixture;
    - then raise `library_organise_v1`.

    The feature stays hidden until then (the flag is off and the RPCs are absent, so the owners report `.unavailable`).
- [ ] Commit: `git add CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md CLAUDE.md docs/tracker-gaps-2026-11/lists/EVIDENCE.md scripts/quality-gates/bdd_landed.txt`; message `Docs: W9 tags and custom lists (prepared, not applied; flag off)`. Memory is outside the repository.
