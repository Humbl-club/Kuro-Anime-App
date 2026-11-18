# W10 Up Next In Your Series Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collection shows "Up next in your series": the direct sequels or next reviewed seasons of titles you completed that are not in your library. Each has a one-tap Plan with a stamp and Undo, and can be dismissed for this account.

**Architecture:**
- **Server:** one prepared SECURITY INVOKER plpgsql RPC, `library_up_next_v1(p_medium, p_limit)`. It joins the caller's COMPLETED rows with two sources: AniList `SEQUEL` edges in `media_relations` (same medium) and the next approved section of a reviewed `series`. It excludes owned, dismissed and catalogue-excluded titles, and returns at most 30 rows.
- **Client:** a new account-scoped owner, `UpNextStore` (`Kuro/Collection/`), reads it with a silent "not deployed" fallback. It filters rows on the device (`LibraryStore.isTracked`, `TasteStore.isHiddenOnDiscover`), so Plan, Dismiss and both Undos need no refetch. Plan goes through `LibraryActions.save(_:status: .planning)`.
- **Dismiss:** reuses Discover's Not interested, `TasteStore.recordDiscoverFeedback(.notInterested, …)`, which sends a deck `skip`.
- **Page:** the section sits on Collection's Completed view. Its results use Collection's one notice slot, `FolioNoticeBar`.
- **Release switch (corrections 2026-11-09, item 1):** flag `collection_up_next_v1` (0 %), read from the injected `FeatureFlags` at call time. While it is off, `UpNextStore` neither loads nor sends anything (phase `.hidden`), and the section never mounts its load.
- **Credential lease (item 2):** the one new private request, `library_up_next_v1`, runs inside `accountSession.withCredentialLease(for: account) { … }`. Plan, Undo and Dismiss add no SDK call of their own: they go through `LibraryActions` and `TasteStore`.
- **Undo receipt (item 3):** a Plan receipt carries the created entry's `rowId`, `lifecycleId` and `revision` plus `created`. Undo removes only an entry this Plan created and nobody has changed since.

**Tech Stack:** PostgreSQL 17 (disposable fixture), plpgsql, Swift 6 / SwiftUI `@Observable`, Swift Testing, Node `node:test` (load profile).

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + features/W10-up-next.feature

## Global Constraints
- **Capacity** (§3, verbatim): "p95 end-to-end thresholds: **Browse/Search/Clubs/Progress ≤ 750 ms, Home/Detail ≤ 1200 ms, Discover/Moods ≤ 1500 ms, Edge Parse/Recommend ≤ 2500 ms**; zero unexpected errors/timeouts, zero dropped offered starts."
- **Capacity rule** (§3, verbatim): "every new or changed backend read/write is assigned to one existing budget class, added to `scripts/load/backend_workload.js` (F3), and covered by an SQL-plan check. A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED, and its change must not worsen the measured steady-state result. Budgets are never relaxed for a retry."
- **Database** (§3, verbatim): "RLS on every new table; every function `SET search_path = public, extensions`; no raw `user_id` from clients; SECURITY DEFINER functions grant EXECUTE only to the roles that need it and revoke PUBLIC (see `20261108120159_review_security_v1.sql`); new SQL bodies in plpgsql (fixture rule); error codes in MESSAGE or HINT, never DETAIL alone. Migrations are written to `supabase/prepared-migrations/` and applied only after explicit owner approval; never `supabase db push --include-all` or history repair without a new approval. Account deletion (`delete-account`) must remove every new per-user table."
- **Continuity** (§3, verbatim): "`SeriesGrouping.decide` — "A provider relation, a shared title or a calendar season is not membership." Only reviewed continuity joins a group." W10 lists a relation as a *suggestion*. It never groups or changes membership.
- **Architecture** (§3, verbatim): "one `@MainActor @Observable final class` owner per capability in `Kuro/<Capability>/`, built once in `AppComposition`; views read owners with `@Environment(Type.self)` and import no Supabase SDK module; account-scoped owners conform to `AccountScopedState`, capture `AccountContext` at the start of every async operation and check `isCurrent` before every private write, and are registered in `makeAccountScopedStates`; tracking reads/writes only through `LibraryStore` / `LibraryActions`; no second Supabase client; no Combine; `print` only inside `#if DEBUG`; no force unwraps."
- **Navigation** (§3, verbatim): "Rule 5 (navigation contract) and Rule 6 (Discover R1–R8) apply to every new screen, sheet and tap target." The section is in Collection, not Discover. A card opens the title journey, and removal is a menu action, never a swipe.
- **W10 decision** (§6, verbatim): "A Collection section (not Discover), so Rule 6 is untouched; one RPC that joins the caller's completed entries with relations and excludes owned titles."
- **Business** (§3, verbatim): "Kuro will not charge for tracking, ordinary discovery, search/filter/sort, history, import/export or useful reminders."
- **Corrections brief 2026-11-09** (owner-approved), binding for this plan:
  - Item 1: "Every user-visible workstream has a server feature flag (`feature_flags`, read via the injected `FeatureFlags`), default 0 %, checked BEFORE any request is sent … A feature whose RPC exists but whose flag is off sends no request. A test pins this per workstream (`<Suite>/flagOffSendsNoRequest`)." For W10, loading is gated by the flag too.
  - Item 2: "Every new private (account-scoped) SDK request runs inside `accountSession.withCredentialLease(for: account) { … }` … Checking `isCurrent` only before publishing is not enough." Pattern: `KuroTests/CredentialLeaseTests.swift` (`preDispatchSwitchSendsNothingAsB`; harness `SessionSDKHarness`, `KuroTests/IdentityCompositionTests.swift:361`, which reads each request's `bearerSubject`). The package rule is `Packages/KuroModules/Tests/KuroCoreTests/AccountSessionTests.swift` `CredentialLeaseTests.leaseIsRevalidatedBeforeItStarts`.
  - Item 3: "A receipt carries the created entry's identity: `rowId`, `lifecycleId` and `revision` (as returned by the save) plus a `created: Bool` (false when `save` returned a pre-existing entry → no Undo offered). Undo refuses when the current entry's lifecycleId or revision differs (any intervening change, incl. dates/repeat count/notes) or the entry was removed and re-added." F2 widens `TastePlanAction.isBarePlan` (`Kuro/Views/TastePicksView.swift:605`) to require `repeatCount == 0`, `startedOn == nil` and `finishedOn == nil`.
  - Item 5: qualification mode needs populated fixtures, semantic assertions, representative writes and cleanup verification, and "≥ 100 completions per endpoint and ≥ 30 per library-size subgroup; fewer → result `insufficient`, never `pass`". Profiles add their own absolute `ratePerSecond` on top of the unchanged base mix.
  - Item 7: "No manufactured red."

### Decisions (with reasons)
- **SECURITY INVOKER, not DEFINER.** Every relation it reads is readable by `authenticated` under RLS:
  - `anime_user_lists` / `manga_user_lists`: "Users can manage their own lists";
  - `taste_signal_events`: `select_own`;
  - `media_relations`: `media_relations_select_all`;
  - `series`, `series_sections`, `series_entry_spans`: public-read policies;
  - `anime` / `manga`: public.

  With INVOKER, RLS itself stops a cross-account read even if a predicate were wrong. The body still filters by `auth.uid()`, and returns nothing when it is null. It never touches `media_franchise_components`, the documented invoker-ACL trap. EXECUTE goes to `authenticated` only; PUBLIC and `anon` are revoked.
- **Dismissals reuse Discover's Not interested** (`TasteStore.recordDiscoverFeedback(.notInterested, for:)`, deck `skip`):
  - it already gives per-account device memory, a durable outbox and Undo (`undoDiscoverFeedback`);
  - `record_taste_deck_signal` keeps one deck row per (user, media), and `taste_signal_events_user_media_idx` serves the RPC's `NOT EXISTS`;
  - `taste_signal_events.user_id` cascades on account deletion, so there is **no new table and no `delete-account` change**.

  Side effect, stated in the UI copy subtitle: a dismissed title is also hidden on Discover and counts as a Taste skip. That matches what "Not interested" means everywhere else. The RPC hides `deck_skip` and `deck_known` rows of the last 365 days, the same window as `DiscoverFeedback.memoryWindow`.
- **What counts as "up next":**
  - The direct `SEQUEL` of a COMPLETED title, same medium. An anime→manga edge is an adaptation, not up next.
  - Or the first `anime_id`/`manga_id` span in the next approved section (`sort_order` greater) of a **reviewed** `series` that holds the completed title. Reviewed is W6's definition (`06-grouping.md` Investigation findings): `continuity = 'verified'` AND `grouping_state = 'approved'` AND section `state = 'approved'` AND `series.medium` = the span's medium. `grouping_state` alone is not enough: a default-inserted `series` row is `'approved'` but `'singleton'`.

  Further rules:
  - One row per target. A reviewed link wins over a relation; otherwise the most recently completed predecessor names it.
  - Excluded: CANCELLED titles; adult titles, `Hentai` and `Ecchi` (the Browse exclusions); and, for anime, the `SPECIAL` / `MUSIC` / `TV_SHORT` formats (the default Browse/Search rule).
  - Unreleased (`NOT_YET_RELEASED`) sequels are listed, because planning an announced sequel is useful. The card says "Announced".
- **Placement:** Collection's **Completed** view, above the rows. Not shown while searching, selecting, or in the imported-titles view. A horizontal rail at `KuroRailPeek` width. An owner may prefer Planning or Watching; that is a one-line change in `FolioUpNextPlacement.shows(status:…)`.
- **Flag `collection_up_next_v1`.** Accessor `FeatureFlags.collectionUpNextV1Enabled`. `UpNextStore` takes `flags: FeatureFlags` by initializer and reads the accessor inside `load`, `plan` and `dismiss`, never at composition: flags hydrate after launch and carry per-account overrides.
  - Off: `load` sets the phase `.hidden` and sends nothing; `plan` / `dismiss` return nil and send nothing.
  - `FolioUpNextPlacement.shows(…)` takes `isEnabled`, so the view neither mounts the section nor calls `load` while the flag is off.
- **Plan receipt and Undo.**
  - `plan` saves through `LibraryActions.save(_:status: .planning)` and builds `UpNextPlanReceipt` from the outcome's `LibraryChange`: `rowId`, `lifecycleId`, `revision` of `change.current`, `created = (change.kind == .added)`, and `account = change.account`.
  - `created == false` (the title was already tracked, e.g. a stale server row) → the notice says "Already in your library." / "Schon in deiner Bibliothek." and has no Undo.
  - `undoPlan` refuses, sends nothing and returns false when any of these holds:
    - `!created`, or the receipt's account is not current;
    - the entry is gone;
    - `entry.rowId != rowId` (removed and re-added);
    - `entry.lifecycleId != lifecycleId` or `entry.revision != revision` (any intervening change);
    - `!TastePlanAction.isBarePlan(entry)` (F2-widened: catches date, repeat-count, notes, rating, progress and status edits even on legacy rows without a revision).
  - Otherwise it calls `actions.remove(key)`. `LibraryStore.remove` already sends the entry's revision as the fenced remove's base (`Packages/KuroModules/Sources/KuroLibrary/LibraryStore.swift:382`), so a change landing between the check and the remove is refused by the server too.
- **SQL test split:** the feature file had both SQL scenarios on one file. The second tag is now `@sql:rls/109_library_up_next_signed_out.sql`, so each scenario names its own file (F1 resolves `@sql:` by file existence). `--only 109_library_up_next` runs both.

## Review Focus
1. **Account switch while the read is in flight.**
   - Post-dispatch: a load started for A and finished after B signed in must publish nothing. Pinned by `loadFinishingAfterAccountSwitchPublishesNothing` (Task 5).
   - Pre-dispatch: A's read must never be sent with B's credential. Pinned by `preDispatchSwitchNeverSendsUpNextReadAsB` over the real SDK client (Task 5).
2. **The migration is prepared, not deployed.** PGRST202 / 404 must hide the section silently and stop asking for 30 min, never show an error. Offline with nothing cached shows the branded offline line, never a blank. Pinned by `undeployedContractHidesSectionSilently` and `offlineWithoutRowsShowsBrandedOffline` (Task 5).
3. **Stale or racing rows, and Undo that removes too much.**
   - The server returns a title the user just planned elsewhere, or one hidden on Discover; the device filter drops it.
   - A Plan of an already-tracked title offers no Undo.
   - Undo after any intervening change is refused: progress, a date-only edit, a repeat-count edit, a change that leaves a bare plan but a new revision, or remove → re-add.
   - Pinned by `trackedOrHiddenRowsNeverShow` (Task 4), `planOfAnExistingEntryOffersNoUndo` and `undoPlanRefusedAfterTheEntryChanged` (Task 5), and `plannedNoticeOffersUndoOnlyForACreatedEntry` (Task 6).
4. **Catalogue edge cases in the join:**
   - two completed seasons pointing at one sequel;
   - an anime→manga `SEQUEL` edge;
   - an adult, Hentai, Ecchi, MUSIC or CANCELLED target;
   - a proposed (unapproved) series;
   - S1 completed with S2 watching, so S3 must not appear;
   - a self-edge.

   Pinned in `109_library_up_next.sql` (Task 2).
5. **2,000-title library.** A heavy completer must stay index-driven. Pinned by the EXPLAIN block in `109_library_up_next.sql` (Task 3, with a labelled index-drop control) and by the `collection-up-next` load profile on a populated fixture (Task 7).
6. **Traffic while the flag is off.** No load, no request, no section. Pinned by `flagOffSendsNoRequest` (Task 5) and `sectionShowsOnlyOnCompletedOutsideSearchSelectAndImport` (Task 6, `isEnabled: false`).

## Success parameters
| §5.2 W10 | How it is measured | Expected |
|---|---|---|
| ""Up next in your series" lists sequels/continuations (reviewed continuity or AniList SEQUEL relation) of titles you completed that are not in your library" | `scripts/db/run_local_db_tests.sh --only 109_library_up_next` | `TESTS : 2 test files … PASS`; no `not ok` lines |
| "one tap to Plan" | `xcodebuild … -only-testing:KuroTests/UpNextStoreTests` | `planFromUpNextAddsToPlanningAndRemovesRow` passes |
| "dismissible per title" | same | `dismissHidesTitleForThisAccount` passes |
| "One RPC, LIMIT 30" | `109_library_up_next.sql` | `p_limit` 100 → 30 rows, 0 → 1 row |
| "Browse class ≤ 750 ms on the 2,000-title fixture" | (a) EXPLAIN on the 2,000-completed fixture in `109_library_up_next.sql`; (b) `node --test scripts/load/profiles/collection-up-next.test.js`; (c) live: an owner-approved **qualification-mode** run with `collection-up-next` on the populated fixture (completed titles with sequels) | (a) index scans only on the listed relations (the index-drop control turns the check false), local `Execution Time` < 250 ms (sanity, not the budget); (b) profile test passes; (c) read p95 ≤ 750 ms (Browse), Plan/Dismiss writes and their Undos p95 ≤ 750 ms (Progress), 0 errors, every endpoint ≥ 100 completions and each library-size subgroup ≥ 30 (else `insufficient`), cleanup verified (not released before) |
| Hidden and silent while `collection_up_next_v1` is off | `-only-testing:KuroTests/UpNextStoreTests/flagOffSendsNoRequest` | 0 requests, phase `.hidden` |
| The read carries its own account's credential | `…/UpNextStoreTests/preDispatchSwitchNeverSendsUpNextReadAsB` | no `library_up_next_v1` request after the switch |
| Undo removes only what Plan created | `…/UpNextStoreTests/planOfAnExistingEntryOffersNoUndo`, `…/undoPlanRefusedAfterTheEntryChanged` (every argument) | pass |
| Outcome (learning goal, not a release criterion): Plan taps from the section | telemetry `up_next_plan` (surface `collection`, ids only); denominator: Collection Completed-view visits where the section showed ≥ 1 row | the lead reviews it with the owner 4 weeks after release |

## File Structure
| File | Responsibility |
|---|---|
| `supabase/prepared-migrations/20261118130000_library_up_next_v1.sql` (new) | The RPC, grants, comment. No table, no index (the plan uses existing ones; see Task 3) |
| `supabase/tests/pending_migrations.txt` | Lists the new prepared file |
| `supabase/tests/rls/109_library_up_next.sql` (new) | Posture, row rules, exclusions, limit, order, EXPLAIN on 2,000 completed rows |
| `supabase/tests/rls/109_library_up_next_signed_out.sql` (new) | anon has no EXECUTE, a token without `sub` gets 0 rows, another account's library is never read |
| `docs/superpowers/specs/2026-11-09-tracker-gaps/features/W10-up-next.feature` | Second SQL tag split (done while planning); flag, credential-lease and receipt scenarios and the qualification-mode load scenario (2026-11-09 corrections) |
| `Kuro/Services/FeatureFlags.swift` | `var collectionUpNextV1Enabled: Bool { evaluate("collection_up_next_v1") }` |
| `Kuro/Collection/UpNextModels.swift` (new) | `UpNextItem` (decoding), `UpNextPolicy` (pure filter), `UpNextCopy` (EN/DE), `UpNextPlanReceipt` (created entry's identity) |
| `Kuro/Collection/UpNextStore.swift` (new) | The owner: load (TTL, joined, account-scoped, silent fallback), plan / undo, dismiss / undo |
| `Kuro/Collection/CollectionRPCParams.swift` | `RPCLibraryUpNextParams` |
| `Kuro/Composition/AppComposition.swift` | Builds `UpNextStore`, `AppGraph.upNext`, `makeAccountScopedStates(… upNext:)` |
| `Kuro/KuroApp.swift` | `.environment(graph.upNext)` |
| `Kuro/Views/Lists/FolioUpNext.swift` (new) | The section: heading, rail, card, Plan key with stamp, long-press menu, offline line; `FolioUpNextPlacement` |
| `Kuro/Views/Lists/FolioHeader.swift` | `FolioNotice` gains `undo: FolioNoticeUndo?` |
| `Kuro/Views/EditorialCollectionView.swift` | Places the section; loads it; routes notice actions |
| `scripts/load/profiles/collection-up-next.js`, `.test.js` (new); `scripts/load/workloads/tracker-gaps-combined.js` (one line) | `collection-up-next` profile in F3's contract (2 rps, operations, seed/cleanupCheck) |
| `KuroTests/IdentityCompositionTests.swift` | expected account-scoped owner list gains `g.upNext`; `SessionSDKHarness` takes `flags: FeatureFlags? = nil` (added by F2.3, which merges first; add it here only if it is missing) |
| `KuroTests/LibraryTestSupport.swift` | `FakeLibraryBackend(…, fence: Bool = false)`: with `fence` on, an insert stamps a fresh `lifecycleId` and `revision = 1` and every edit increments `revision` (models the server's revision fence; the default keeps every existing test unchanged) |
| `KuroTests/UpNextStoreTests.swift` (new) | Tagged scenarios + Review Focus pins |
| `docs/tracker-gaps-2026-11/W10-up-next/EVIDENCE.md` (new) | Red/green, EXPLAIN output, gate results |

---

### Task 1: Prepared migration and posture test (red first)

**Files:** create `supabase/tests/rls/109_library_up_next.sql` (posture block only), `supabase/prepared-migrations/20261118130000_library_up_next_v1.sql`; modify `supabase/tests/pending_migrations.txt`.

**Interfaces**
- Produces:
  ```sql
  public.library_up_next_v1(p_medium text, p_limit integer default 30)
  returns table(media_type text, media_id integer, title text, cover_image text, format text, status text,
                start_year integer, total_units integer, after_media_id integer, after_title text, link text)
  language plpgsql stable security invoker
  set search_path = public, extensions set jit = off
  -- order matters: FIRST validate p_medium 'anime' | 'manga' (anything else: raise exception 'INVALID_MEDIUM: %' using errcode '22023'),
  -- THEN v_limit := least(greatest(coalesce(p_limit, 30), 1), 30); v_uid := auth.uid(); null → return (0 rows)
  -- (the posture test runs as superuser, where auth.uid() is null: a uid check first would skip the raise)
  -- body: return query execute $anime_query$ … $anime_query$ using v_uid, v_limit;   (manga: $manga_query$)
  revoke all on function public.library_up_next_v1(text, integer) from public, anon;
  grant execute on function public.library_up_next_v1(text, integer) to authenticated;
  ```
  `link` is `'reviewed'` or `'sequel'`; `media_type` is lower-case `'anime'`/`'manga'`. `title` is `coalesce(nullif(title_english,''), title_romaji)`, and the same for `after_title`. `cover_image` is `cover_image_large`. `total_units` is `episodes` / `chapters`. `start_year` is `coalesce(season_year, start_date_year)` (manga: `start_date_year`). The `$anime_query$` / `$manga_query$` markers are part of the contract: Task 3's EXPLAIN extracts the SQL between them (the `102_load_hotpaths.sql` pattern).

- [ ] **Step 1: Write the failing posture test.** Header lines:
  - `-- @requires table public.media_relations`
  - `-- @requires table public.series_entry_spans`
  - `-- @requires table public.taste_signal_events`
  - `-- @requires table public.anime_user_lists`
  - `-- @requires table public.manga_user_lists`

  Then `\set ON_ERROR_STOP on`, `begin;`, and:
  ```sql
  select tests.ok('library_up_next_v1 is SECURITY INVOKER, STABLE, plpgsql, search_path = public, extensions',
    (select not prosecdef and provolatile='s' and prolang=(select oid from pg_language where lanname='plpgsql')
            and proconfig @> array['search_path=public, extensions']
       from pg_proc where oid='public.library_up_next_v1(text,integer)'::regprocedure));
  select tests.ok('authenticated may execute; anon and PUBLIC may not',
    has_function_privilege('authenticated','public.library_up_next_v1(text,integer)','execute')
    and not has_function_privilege('anon','public.library_up_next_v1(text,integer)','execute')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                    where p.oid='public.library_up_next_v1(text,integer)'::regprocedure and a.grantee=0));
  select tests.ok('invoker prerequisites: authenticated can read every relation the body reads',
    has_table_privilege('authenticated','public.media_relations','select')
    and has_table_privilege('authenticated','public.series','select')
    and has_table_privilege('authenticated','public.series_sections','select')
    and has_table_privilege('authenticated','public.series_entry_spans','select')
    and has_table_privilege('authenticated','public.taste_signal_events','select')
    and has_table_privilege('authenticated','public.anime_user_lists','select')
    and has_table_privilege('authenticated','public.manga_user_lists','select'));
  select tests.ok('the body never reads media_franchise_components (no client grant: invoker trap)',
    (select prosrc not like '%media_franchise_components%' from pg_proc
      where oid='public.library_up_next_v1(text,integer)'::regprocedure));
  select tests.raises('an unknown medium is a typed error in the MESSAGE',
    $$select * from public.library_up_next_v1('film', 30)$$, 'INVALID_MEDIUM');
  ```
  Use `tests.raises`' real signature. Read `supabase/tests/lib/00_test_helpers.sql` first.
- [ ] **Step 2: Run** `scripts/db/run_local_db_tests.sh --only 109_library_up_next`. Expected: FAIL, `function public.library_up_next_v1(text,integer) does not exist` (invalid `regprocedure`).
- [ ] **Step 3: Implement** the migration header comment and the function with the signature above:
  - The header says it is prepared, NOT deployed; owner approval required; depends on `20261007040000` (live) and `20260307120000` (live).
  - The body validates `p_medium` first (the raise above), then returns no rows. Task 2 fills it.
  - The revoke/grant, and `comment on function`.
  - Add `20261118130000_library_up_next_v1.sql` under a new comment block in `supabase/tests/pending_migrations.txt`: `# 2026-11-10 tracker gaps W10 (prepared only; owner approval required to deploy).`
- [ ] **Step 4: Run.** Expected: the posture assertions PASS. `PREPARED : every non-excluded … applied`.
- [ ] **Step 5: Commit.** `git add supabase/prepared-migrations/20261118130000_library_up_next_v1.sql supabase/tests/rls/109_library_up_next.sql supabase/tests/pending_migrations.txt && git commit -m "W10: prepared library_up_next_v1 posture (invoker, authenticated only)"`

### Task 2: Row rules (feature scenario 1)

**Files:** modify both files from Task 1.

**Interfaces**
- Consumes: `tests.reset()`, `tests.make_user(n)`, `tests.as_user(tests.uid(n))`, `tests.ok`, `tests.eq`. Use ids 1090001+ for anime and manga.
- Produces: the real body. The algorithm is not fully fixed by the signature, so it is given here. Anime shown; manga is the same over `manga_user_lists` / `MANGA` / `manga_id` / `chapters`, without the format rule.
  ```sql
  with done as (                       -- the caller's completed titles
    select l.anime_id as id, l.updated_at as done_at
    from public.anime_user_lists l where l.user_id = $1::text and l.list_type = 'COMPLETED'),
  cand as (
    select mr.to_media_id as id, d.id as after_id, d.done_at, 1 as pri, 'sequel' as link
    from done d join public.media_relations mr
      on mr.from_media_type='ANIME' and mr.from_media_id=d.id
     and mr.relation_type='SEQUEL' and mr.to_media_type='ANIME'
    union all
    select nxt.anime_id, d.id, d.done_at, 0, 'reviewed'
    from done d
    join public.series_entry_spans sp on sp.anime_id = d.id
    join public.series s on s.id = sp.series_id and s.continuity = 'verified' and s.grouping_state = 'approved'
                       and s.medium = sp.medium
    join public.series_sections sec on sec.id = sp.section_id and sec.state = 'approved'
    join lateral (select sp2.anime_id from public.series_entry_spans sp2
                  join public.series_sections sec2 on sec2.id = sp2.section_id and sec2.state = 'approved'
                  where sp2.series_id = sp.series_id and sp2.anime_id is not null and sec2.sort_order > sec.sort_order
                  order by sec2.sort_order limit 1) nxt on true),
  best as (select distinct on (c.id) c.* from cand c where c.id <> c.after_id
           order by c.id, c.pri, c.done_at desc)
  select 'anime', a.id, …, p.id, …, b.link
  from best b join public.anime a on a.id = b.id join public.anime p on p.id = b.after_id
  where coalesce(a.is_adult,false) = false
    and not ('Hentai' = any(coalesce(a.genres,'{}'))) and not ('Ecchi' = any(coalesce(a.genres,'{}')))
    and upper(coalesce(a.format,'')) not in ('SPECIAL','MUSIC','TV_SHORT')
    and coalesce(a.status,'') <> 'CANCELLED'
    and not exists (select 1 from public.anime_user_lists o where o.user_id = $1::text and o.anime_id = b.id)
    and not exists (select 1 from public.taste_signal_events e
                    where e.user_id = $1 and e.media_type = 'ANIME' and e.media_id = b.id
                      and e.event_type in ('deck_skip','deck_known') and e.created_at >= now() - interval '365 days')
  order by b.done_at desc, b.id
  limit $2
  ```
- [ ] **Step 1: Write the failing row tests.** Seed as the superuser after `tests.reset()`, with `set local session_replication_role = replica` around the list inserts (the `102` pattern, which avoids the taste triggers), and users 1091 and 1092. Then assert, as `tests.as_user(tests.uid(1091))`:
  ```
  A1 COMPLETED --SEQUEL--> A2 (not owned)              → row (A2, after A1, link 'sequel', after_title = A1 title)   [scenario: "Sequel to <season 1>"]
  A3 COMPLETED --SEQUEL--> A4 (A4 PLANNING for 1091)   → no A4
  A5 COMPLETED --SEQUEL--> A6 ; deck_skip(1091, A6)    → no A6 ; deck_known(A7 target) → no A7 ; deck_pass(A8 target) → A8 listed
  deck_skip for A6 dated 400 days ago in a second check → A6 listed (365-day window)
  targets with is_adult / 'Hentai' / 'Ecchi' / format 'MUSIC' / status 'CANCELLED'       → none listed
  target with status 'NOT_YET_RELEASED'                                                   → listed
  A10 and A11 COMPLETED both --SEQUEL--> A12             → exactly one A12 row, after = the more recently completed
  A13 COMPLETED --SEQUEL(to MANGA)--> M1                 → nothing in the anime call; nothing in the manga call
  A14 WATCHING --SEQUEL--> A15                           → no A15 (only completed titles seed)
  S1 COMPLETED --> S2 WATCHING --> S3                    → no S2 (owned), no S3 (S2 not completed)
  self edge A16 --SEQUEL--> A16                          → none
  approved series: sections sort 1 (A20 COMPLETED), 2 (A21), 3 (A22); no relation rows → exactly A21 with link 'reviewed'
  same layout in a series with grouping_state 'proposed' → nothing
  same layout in a default-inserted series (continuity 'singleton', grouping_state default 'approved') → nothing
  same layout in a verified series whose series.medium is 'manga' while the spans are anime → nothing
  A23 COMPLETED with both a SEQUEL edge and a reviewed next to A24 → one A24 row, link 'reviewed'
  manga: M10 COMPLETED --SEQUEL--> M11                    → manga call lists M11 with total_units = chapters
  order: the predecessor completed most recently comes first (updated_at seeded 1..n days ago)
  limit: 35 more completed→sequel pairs → p_limit 100 returns 30 rows; p_limit 0 returns 1; p_limit null returns 30
  ```
- [ ] **Step 2: Run** `--only 109_library_up_next`. Expected: FAIL at the first row assertion ("row (A2, after A1…)": 0 rows from the stub body).
- [ ] **Step 3: Implement** the body as given, for both media.
- [ ] **Step 4: Run.** Expected: PASS, every assertion.
- [ ] **Step 5: Commit.** `git add supabase/prepared-migrations/20261118130000_library_up_next_v1.sql supabase/tests/rls/109_library_up_next.sql && git commit -m "W10: up-next rows from completed titles (sequel edges + reviewed continuity), owned/dismissed/catalogue exclusions"`

### Task 3: Account scope (feature scenario 2) and the 2,000-title plan check

**Files:** create `supabase/tests/rls/109_library_up_next_signed_out.sql`; extend `supabase/tests/rls/109_library_up_next.sql` with the EXPLAIN block.

- [ ] **Step 1: Write the failing tests.**

  `109_library_up_next_signed_out.sql`, with the same `@requires` lines:
  ```sql
  -- seed: 1093 completed A30 --SEQUEL--> A31; 1094 completed A32 --SEQUEL--> A33 (rolled back)
  select tests.as_anon();
  select tests.denied('anon cannot execute library_up_next_v1 (signed-out caller gets nothing)',
    $$select * from public.library_up_next_v1('anime', 30)$$);           -- 42501
  reset role; select set_config('request.jwt.claims', '{"role":"authenticated"}', true); set local role authenticated;
  select tests.eq('an authenticated token without sub returns 0 rows',
    (select count(*) from public.library_up_next_v1('anime', 30)), 0::bigint);
  select tests.as_user(tests.uid(1093));
  select tests.ok('the account comes from the token: 1093 sees A31 and never 1094''s A33',
    exists (select 1 from public.library_up_next_v1('anime',30) where media_id = A31)
    and not exists (select 1 from public.library_up_next_v1('anime',30) where media_id = A33));
  select tests.ok('the RPC takes no user id parameter',
    (select pronargs = 2 and not (proargnames @> array['p_user_id']) from pg_proc
      where oid='public.library_up_next_v1(text,integer)'::regprocedure));
  ```
  Use `tests.denied`' real signature from the helpers.

  Then add an EXPLAIN block to `109_library_up_next.sql`, with `set local jit=off` and the `102_load_hotpaths` seeding pattern:
  - insert 22,000 anime (ids 9_100_001+) and 2,000 `COMPLETED` rows for user 1095;
  - insert 2,000 `SEQUEL` relations to 2,000 distinct targets, 300 of them owned by 1095;
  - insert 200 `deck_skip` rows;
  - `analyze` the five tables.

  Extract the SQL between the `$anime_query$` markers from `pg_proc.prosrc`, replace `$1` with `quote_literal(tests.uid(1095))` and `$2` with `30`, then run `explain (analyze, buffers, format json)` and store the plan. Assert:
  ```sql
  select tests.ok('2,000-completed up-next uses the relation index, the list unique key and the taste index; no seq scan on them',
    plan::text like '%idx_media_relations_from%'
    and plan::text like '%anime_user_lists_user_id_anime_id_key%'
    and plan::text like '%taste_signal_events_user_media_idx%'
    and plan::text !~ '"Node Type": "Seq Scan", [^}]*"Relation Name": "(media_relations|anime_user_lists|anime|taste_signal_events)"')
    from up_next_plans;
  select tests.ok('local sanity: execution under 250 ms (the live budget is 750 ms p95)',
    (plan->0->>'Execution Time')::numeric < 250) from up_next_plans;
  select tests.as_user(tests.uid(1095));
  select tests.eq('30 rows at the cap', (select count(*) from public.library_up_next_v1('anime',30)), 30::bigint);
  select tests.reset();
  ```
  Then a labelled negative control, last in the file (the transaction rolls back):
  - `drop index public.idx_media_relations_from;`
  - re-run the same EXPLAIN into `up_next_plans_control`;
  - `select tests.ok('control: without idx_media_relations_from the index check is false', plan::text not like '%idx_media_relations_from%') from up_next_plans_control;`

  This proves the plan assertion can fail. Print the plan with `\o` like `102`, so the evidence step can copy it.
- [ ] **Step 2: Run the red half.** The body already exists after Task 2, so the new file can pass on its first normal run. Run `scripts/db/run_local_db_tests.sh --exclude-pending --only 109_library_up_next`. Expected: FAIL in both files at their first reference to the function: `function public.library_up_next_v1(text, integer) does not exist` (the `regprocedure` cast in the posture block, and the anon/`sub` calls in the signed-out file). Record the message. Then run `--only 109_library_up_next` normally. The EXPLAIN assertions fail if the planner seq-scans a listed relation. Index or bitmap access on `anime_user_lists` for the `done` CTE (2,000 of the user's rows through `idx_anime_user_lists_user_id`) is acceptable. Do not add an index without recording the plan first.
- [ ] **Step 3: Make it pass.**
  - Only if the EXPLAIN shows a seq scan on a listed relation, add to the same migration one partial index: `create index if not exists idx_anime_user_lists_user_completed on public.anime_user_lists (user_id, updated_at desc) where list_type = 'COMPLETED';` (manga likewise). Record why in the migration comment.
  - Otherwise no index. Every write to the list tables would pay for an index, so one is added only when the plan proves it is needed.
- [ ] **Step 4: Run** `scripts/db/run_local_db_tests.sh --only 109_library_up_next`. Expected: both files PASS (`TESTS : 2 test files … PASS`).
- [ ] **Step 5: Commit.** `git add supabase/tests/rls/109_library_up_next_signed_out.sql supabase/tests/rls/109_library_up_next.sql supabase/prepared-migrations/20261118130000_library_up_next_v1.sql && git commit -m "W10: up-next account scope and 2,000-title plan check"`

### Task 4: Client models and the pure filter

**Files:** create `Kuro/Collection/UpNextModels.swift`, `KuroTests/UpNextStoreTests.swift` (suite + pure tests); modify `Kuro/Collection/CollectionRPCParams.swift`.

**Interfaces**
- Produces:
  ```swift
  struct RPCLibraryUpNextParams: Encodable, Sendable { let p_medium: String; let p_limit: Int }
  nonisolated struct UpNextItem: Identifiable, Equatable, Sendable, Decodable {
      enum Link: String, Sendable, Decodable { case reviewed, sequel }
      let key: MediaKey; let title: String; let coverImage: String?; let format: String?; let status: String?
      let startYear: Int?; let totalUnits: Int?; let afterKey: MediaKey; let afterTitle: String; let link: Link
      var id: MediaKey { key }
      var isAnnounced: Bool { status == "NOT_YET_RELEASED" }
      // decodes the RPC row (media_type, media_id, …, after_media_id, after_title, link); unknown media_type throws
  }
  nonisolated enum UpNextPolicy {
      static let limit = 30
      static let ttl: TimeInterval = 300
      static let undeployedRetry: TimeInterval = 1800
      /// Server rows minus anything tracked now or hidden on Discover now, order kept.
      static func visible(_ items: [UpNextItem], tracked: Set<MediaKey>, hidden: Set<MediaKey>) -> [UpNextItem]
  }
  struct UpNextPlanReceipt: Equatable, Sendable {
      let key: MediaKey; let account: AccountContext
      let rowId: Int; let lifecycleId: UUID?; let revision: Int64?   // change.current as returned by the save
      let created: Bool                                              // change.kind == .added; false → no Undo offered
      var offersUndo: Bool { created }
  }
  nonisolated enum UpNextCopy {
      static func heading(german: Bool) -> String                  // "Up next in your series" / "Als Nächstes in deinen Reihen"
      static func after(_ title: String, german: Bool) -> String   // "Sequel to Frieren" / "Fortsetzung von Frieren"
      static func announced(german: Bool) -> String                // "Announced" / "Angekündigt"
      static func plan(german: Bool) -> String                     // "Plan" / "Planen"
      static func dismissSubtitle(german: Bool) -> String          // "Also hidden on Discover." / "Auch auf Entdecken ausgeblendet."
      static func alreadyInLibrary(german: Bool) -> String         // "Already in your library." / "Schon in deiner Bibliothek."
  }
  ```
  `Not interested`, the toast words and `Undo` reuse `DiscoverMenuCopy.notInterested`, `DiscoverMenuCopy.toast(.notInterested, medium:german:)`, `TastePlanCopy.message(.added, …)` and `TastePlanCopy.undo`.

- [ ] **Step 1: Write the failing tests** in `@MainActor @Suite("Up next", .serialized, .timeLimit(.minutes(1))) struct UpNextStoreTests`:
  ```swift
  @Test func rowsDecodeBothMedia()
  // JSON row {media_type:"anime",media_id:1,title:"Frieren S2",…,after_media_id:9,after_title:"Frieren",link:"sequel"}
  //   → key anime 1, afterKey anime 9, link .sequel; "manga" row → manga keys; media_type "film" → decode error
  @Test func trackedOrHiddenRowsNeverShow()
  // visible([a1,a2,a3], tracked:[a2], hidden:[a3]) == [a1]; order of [a3,a1] kept → [a1]; empty sets → identity
  @Test func copyIsEnglishAndGerman()
  // after("Frieren", false) == "Sequel to Frieren"; (true) == "Fortsetzung von Frieren"; heading and alreadyInLibrary EN/DE as above
  ```
- [ ] **Step 2: Run** `-only-testing:KuroTests/UpNextStoreTests`. Expected: FAIL to compile, "cannot find 'UpNextItem' in scope".
- [ ] **Step 3: Implement** `UpNextModels.swift` and the params struct.
- [ ] **Step 4: Run.** Expected: PASS (3).
- [ ] **Step 5: Commit.** `git add Kuro/Collection/UpNextModels.swift Kuro/Collection/CollectionRPCParams.swift KuroTests/UpNextStoreTests.swift && git commit -m "W10: up-next models, device filter and EN/DE copy"`

### Task 5: The owner `UpNextStore` (scenarios 3 and 4)

**Files:** create `Kuro/Collection/UpNextStore.swift`; modify `Kuro/Services/FeatureFlags.swift`, `Kuro/Composition/AppComposition.swift`, `Kuro/KuroApp.swift`, `KuroTests/IdentityCompositionTests.swift` (`expectedAccountScopedStates` gains `g.upNext` after `g.collection`, or after `g.customLists` when W9 is merged; final order in `00-program.md`; `SessionSDKHarness(flags:)` from W2 Task 5, added here only if missing), `KuroTests/LibraryTestSupport.swift` (`FakeLibraryBackend(…, fence:)`); extend the test file.

**Interfaces**
- Consumes:
  - `SupabaseClient?`, the one client from composition;
  - `AccountSessionCoordinator` (`current`, `isCurrent`, `withCredentialLease`) and `AccountScopedLoads`;
  - `LenientRows`, and `ReleaseFailure.classify` for the not-deployed classification (the `DiscoveryStore+Usability` pattern);
  - `LibraryStore` (`isTracked`, `entry(for:)`, `allEntries`) and `LibraryActions` (`save`, `remove`);
  - `TasteStore` (`recordDiscoverFeedback`, `undoDiscoverFeedback`, `discoverHiddenKeys`, `restoreDiscoverMemory`);
  - `TastePlanAction.isBarePlan` (as widened by F2: `repeatCount == 0`, `startedOn == nil`, `finishedOn == nil`);
  - `FeatureFlags.collectionUpNextV1Enabled` (added here).
- Produces:
  ```swift
  // FeatureFlags.swift (additive, alphabetical in the tracker-gaps block)
  var collectionUpNextV1Enabled: Bool { evaluate("collection_up_next_v1") }
  @MainActor @Observable final class UpNextStore: AccountScopedState {
      enum Phase: Equatable { case idle, loading, loaded, offline, hidden }   // hidden: flag off, not deployed or nothing to show
      init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, library: LibraryStore,
           actions: LibraryActions, taste: TasteStore, flags: FeatureFlags, now: @escaping () -> Date = Date.init)
      var isEnabled: Bool { flags.collectionUpNextV1Enabled }         // read at call time, never cached
      private(set) var phase: [MediaKind: Phase]
      func load(_ medium: MediaKind, force: Bool = false) async        // flag off → phase .hidden, NO request; else TTL per
                                                                       // account+medium, joined, never throws; the RPC runs inside
                                                                       // accountSession.withCredentialLease(for: account); starts with
                                                                       // taste.restoreDiscoverMemory() (synchronous), so the account's
                                                                       // device-side dismissals apply after an account switch
      func visible(_ medium: MediaKind) -> [UpNextItem]                // UpNextPolicy.visible over library + taste now; [] while off
      func plan(_ item: UpNextItem) async -> UpNextPlanReceipt?        // flag off / no session / failure → nil; else
                                                                       // LibraryActions.save(key, status: .planning) → receipt from
                                                                       // change.current (rowId, lifecycleId, revision), created =
                                                                       // change.kind == .added, account = change.account
      func undoPlan(_ receipt: UpNextPlanReceipt) async -> Bool        // refuses (false, nothing sent) unless created, same account,
                                                                       // entry present with the receipt's rowId, lifecycleId and revision,
                                                                       // and TastePlanAction.isBarePlan(entry); then actions.remove
      func dismiss(_ item: UpNextItem) -> DiscoverFeedbackReceipt?     // flag off → nil; taste.recordDiscoverFeedback(.notInterested, for:)
      func undoDismiss(_ receipt: DiscoverFeedbackReceipt) -> Bool     // taste.undoDiscoverFeedback
      func cancelAccountWork(); func clearPrivateState()               // cancel loads; empty rows, phases, cache (keep the undeployed mark)
  }
  ```
  Composition:
  - `makeGraph` builds it after `libraryActions` and `taste` exist, passing the one injected `FeatureFlags`.
  - `AppGraph` gains `let upNext: UpNextStore`.
  - `makeAccountScopedStates(… collection:, upNext:, …)` lists it right after `collection` (after `customLists` once W9 is merged; final order pinned in `00-program.md`).
  - `KuroApp` adds `.environment(graph.upNext)`.

- [ ] **Step 1: Write the failing tests.** Harness: a private `UpNextHarness` in `UpNextStoreTests.swift`.
  - It copies `PublicDataHarness`'s construction (`KuroTests/StubPostgREST.swift`) and adds `libraryBackend: FakeLibraryBackend(fence: true)` and `flags`: `AppComposition.testingGraph(testingUserDefaults:, notificationCenter: FakeNotificationCenter(), client: StubSupabase.makeClient(server:), libraryBackend: FakeLibraryBackend(fence: true), flags: FeatureFlags(userDefaults: <the same fresh suite>, launchArguments: launchArguments))`.
  - `launchArguments` defaults to `["--ff-on=collection_up_next_v1"]`, so every test except `flagOffSendsNoRequest` runs with the flag on and never fails because of it.
  - `fence: true` gives inserted rows a `lifecycleId` and a `revision`, so the receipt comparisons are not vacuous `nil == nil` checks.
  - `PlatformHarness` takes no client. `withCredentialLease` over the stub client is already exercised by `ReleaseContractFallbackTests`.
  - The stub answers `rpc/library_up_next_v1` with one anime row (1201, after 1200, "sequel") for user A, `rpc/record_taste_deck_signal` with `DUJSON.signalOK`, `taste_signal_events` with `[]`, and everything else with `[]`.
  - Sign in through `graph.session.applySession(userId:email:)`, as `PlatformHarness.signIn` does.
  ```swift
  @Test func planFromUpNextAddsToPlanningAndRemovesRow() async throws
  // await upNext.load(.anime); visible(.anime).map(\.key) == [anime 1201]
  // receipt = await upNext.plan(item) → non-nil, receipt.created == true, receipt.rowId/lifecycleId/revision ==
  //   library.entry(for: anime 1201)'s; library.entry(for: anime 1201)?.status == .planning
  // visible(.anime).isEmpty (left the section without a refetch: rpc request count still 1)
  // await upNext.undoPlan(receipt) == true; library.entry(for: anime 1201) == nil; visible(.anime).map(\.key) == [anime 1201]
  @Test func dismissHidesTitleForThisAccount() async throws
  // load; receipt = upNext.dismiss(item) → non-nil; visible(.anime).isEmpty; taste.isHiddenOnDiscover(anime 1201)
  // sent deck signals == ["skip ANIME 1201"]
  // await upNext.load(.anime, force: true) (server still returns the row) → visible(.anime).isEmpty
  // sign in user B (stub returns the same row for B) → load → visible(.anime).map(\.key) == [anime 1201]
  // sign in A again → load → visible(.anime).isEmpty (A's device memory)
  @Test func loadFinishingAfterAccountSwitchPublishesNothing() async throws
  // stub holds the up-next answer behind a StubGate; start load for A; sign in B; open the gate
  // visible(.anime).isEmpty and phase[.anime] != .loaded for B; B's own load then reads B's rows
  @Test func undeployedContractHidesSectionSilently() async throws
  // stub answers 404 {"code":"PGRST202"}; load → phase[.anime] == .hidden, visible empty
  // a second load within 30 min sends no request; with now() + 31 min it asks again
  @Test func offlineWithoutRowsShowsBrandedOffline() async throws
  // stub fails with URLError(.notConnectedToInternet) → phase[.anime] == .offline
  // after one successful load, an offline reload keeps the rows and phase .loaded
  @Test func flagOffSendsNoRequest() async throws
  // harness launchArguments [] (flag off), signed in as A: load(.anime), load(.anime, force: true) → 0 requests to
  // rpc/library_up_next_v1 (no request at all from UpNextStore); phase[.anime] == .hidden; visible(.anime).isEmpty;
  // plan(item) == nil and dismiss(item) == nil with no library write and no deck signal
  @Test func planOfAnExistingEntryOffersNoUndo() async throws
  // library already holds anime 1201 as a bare Planning entry (the server row is stale); receipt = await plan(item) →
  // created == false; await undoPlan(receipt) == false; the entry is still present and no remove was sent
  enum InterveningChange: CaseIterable { case progress, dateOnly, repeatCount, ratingSetThenCleared, removeAndReAdd }
  @Test(arguments: InterveningChange.allCases) func undoPlanRefusedAfterTheEntryChanged(change: InterveningChange) async throws
  // plan → receipt (created); then, through LibraryActions:
  //   .progress             apply(LibraryEdit(progress: .set(2)))
  //   .dateOnly             apply(LibraryEdit(startedOn: .set(PartialDate(raw: "2026-11")!)))        (F2 field)
  //   .repeatCount          apply(LibraryEdit(repeatCount: .set(1)))                                (F2 field)
  //   .ratingSetThenCleared apply(rating 7), then apply(rating .clear): a bare plan again, but a new revision
  //   .removeAndReAdd       remove, then save(.planning): new rowId and lifecycleId
  // undoPlan(receipt) == false; library.entry(for: anime 1201) is still present; no remove sent after the change
  // and, separately: a receipt whose account is not current → false, nothing sent
  @Test func preDispatchSwitchNeverSendsUpNextReadAsB() async throws
  // SessionSDKHarness(responder:, flags: FeatureFlags(…, launchArguments: ["--ff-on=collection_up_next_v1"])), following
  // CredentialLeaseTests.preDispatchSwitchSendsNothingAsB: sign in as A keeping B's SDK session; start
  // graph.upNext.load(.anime, force: true) for A; h.storage.replace(with: sessionB) and applySession(userId: B) before
  // dispatch; await both → no rpc/library_up_next_v1 request recorded (none with bearerSubject B in particular);
  // phase[.anime] != .loaded for B
  @Test func signedOutLoadSendsNothing() async throws
  // no session: load(.anime) → no request; plan(item) == nil; dismiss(item) == nil
  ```
- [ ] **Step 2: Run** `-only-testing:KuroTests/UpNextStoreTests`. Expected: FAIL to compile, "cannot find 'UpNextStore' in scope".
- [ ] **Step 3: Implement** the flag accessor, the fenced fake option, the owner and the composition wiring (and `SessionSDKHarness(flags:)` only if W2 has not added it).
  - `load`, `plan` and `dismiss` read `isEnabled` first and return before building any request when it is off.
  - Every async path captures the `AccountContext` at its start, and publishes only while `isCurrent`.
  - `load` runs the RPC inside `accountSession.withCredentialLease(for: account) { … }` (the `HomeStore.detailBundle` pattern, `Kuro/Home/HomeStore.swift:99`) and uses `AccountScopedLoads` keyed `"up_next|<medium>"`.
  - `plan` / `undoPlan` follow the receipt rules in Decisions.
  - Then run `scripts/quality-gates/check_architecture.sh`. Expected: 0 offenders (no SDK import in views, no `.shared`).
- [ ] **Step 4: Run** the suite, then `-only-testing:KuroTests/CompositionGraphTests -only-testing:KuroTests/IdentityCompositionTests -only-testing:KuroTests/CredentialLeaseTests -only-testing:KuroTests/LibraryFacadeTests`. Expected: PASS (the account-scoped list grows by one, in the pinned order; the existing `SessionSDKHarness` and `FakeLibraryBackend` users are unchanged by the new default parameters).
- [ ] **Step 5: Commit.** `git add Kuro/Services/FeatureFlags.swift Kuro/Collection/UpNextStore.swift Kuro/Composition/AppComposition.swift Kuro/KuroApp.swift KuroTests/UpNextStoreTests.swift KuroTests/IdentityCompositionTests.swift KuroTests/LibraryTestSupport.swift && git commit -m "W10: UpNextStore behind collection_up_next_v1 (leased account-scoped read, receipt-guarded Plan Undo, dismiss through Taste)"`

### Task 6: The Collection section and its one notice slot

**Files:** create `Kuro/Views/Lists/FolioUpNext.swift`; modify `Kuro/Views/Lists/FolioHeader.swift` (`FolioNotice`) and `Kuro/Views/EditorialCollectionView.swift`; extend the test file.

**Interfaces**
- Consumes:
  - `@Environment(UpNextStore.self) private var upNext: UpNextStore?`. It is optional, so the existing snapshot hosts that do not inject it keep rendering; the section then hides.
  - `@Environment(\.kuroRoutes)` for `openMedia`; `KuroRailPeek.cardWidth`, `KuroBrandedTile`, `KuroCachedAsyncImage`.
  - `.kuroConfirmStamp(trigger:)`, `KuroOfflineView(hasContent:retry:)`, `KuroSectionHeader`.
  - `InteractionTelemetry?` (events `up_next_plan` and, once per Completed-view visit where the section shows ≥ 1 row, `up_next_shown` (the outcome's denominator); surface `collection`, extra `media_type` / `media_id` only).
  - `FeatureFlags` via `@Environment(FeatureFlags.self)` for `flags.collectionUpNextV1Enabled`.
- Produces:
  ```swift
  nonisolated enum FolioUpNextPlacement {
      static func shows(status: FolioStatus, isImportedView: Bool, isSearching: Bool, isSelecting: Bool,
                        isEnabled: Bool) -> Bool   // isEnabled (collection_up_next_v1) && .completed only
  }
  nonisolated enum FolioUpNextNotices {
      /// created → "Added to your list." with Undo (.upNextPlan); !created → "Already in your library." with no action and no undo.
      static func planned(_ receipt: UpNextPlanReceipt, german: Bool) -> FolioNotice
  }
  struct FolioUpNextSection: View {
      let medium: MediaKind; let gutter: CGFloat; let width: CGFloat
      let onPlanned: (UpNextPlanReceipt) -> Void; let onDismissed: (DiscoverFeedbackReceipt) -> Void
  }
  // FolioHeader.swift
  enum FolioNoticeUndo: Equatable { case advance, upNextPlan(UpNextPlanReceipt), upNextDismiss(DiscoverFeedbackReceipt) }
  struct FolioNotice { …; let actionTitle: String?; var undo: FolioNoticeUndo? = nil }   // existing call sites keep compiling
  ```
  Card:
  - Poster at rail width, or `KuroBrandedTile` when there is no picture.
  - Title, then `UpNextCopy.after(afterTitle)`, then `UpNextCopy.announced` when announced.
  - One Plan key (44 pt, ink, stamps on success).
  - Tapping the card opens `MediaRoute(key)`.
  - `.contextMenu` "Not interested" (with the subtitle), the only removal.
  - Accessibility: the card is one element with the label "<title>, sequel to <after>". The Plan key is a separate button.
  - Monochrome.

  The section shows only when `visible(medium)` is non-empty, or when the phase is `.offline` with no rows (then a compact `KuroOfflineView`). Phase `.hidden` or an empty list draws nothing (no heading).

  Notices: a plan shows `FolioUpNextNotices.planned(r)`. For a created entry that is `FolioNotice(tone: .confirmation, message: TastePlanCopy.message(.added), actionTitle: Undo, undo: .upNextPlan(r))`. For `r.created == false` it is `FolioNotice(tone: .confirmation, message: UpNextCopy.alreadyInLibrary, actionTitle: nil, undo: nil)`, so no Undo is offered. If an offered Undo is refused (`undoPlan` returns false after an intervening change), the notice is replaced by `TastePlanCopy.message(.failed)`, tone `.problem`, and the entry is left alone. A dismissal shows `DiscoverMenuCopy.toast(.notInterested…)` with `undo: .upNextDismiss(r)`. `performNoticeAction` switches on `notice.undo`: `.advance`, or nil while `actionTitle != nil` (the legacy path), keeps calling `undoLastAdvance()`. A failed plan shows `TastePlanCopy.message(.failed)`, tone `.problem`.

- [ ] **Step 1: Write the failing tests:**
  ```swift
  @Test func sectionShowsOnlyOnCompletedOutsideSearchSelectAndImport()
  // shows(.completed, false, false, false, isEnabled: true) == true; .watching/.planning == false; any of
  // imported/searching/selecting true → false; isEnabled: false → false for every status (flag off: no section, no load)
  // (the view's load calls are gated by this same function; the live walk in Task 8 confirms with the stub-server
  //  request log that a Watching landing, and any landing with the flag off, sends no library_up_next_v1 request)
  @Test func plannedNoticeOffersUndoOnlyForACreatedEntry()
  // planned(receipt(created: true)) → actionTitle == TastePlanCopy.undo, undo == .upNextPlan(receipt);
  // planned(receipt(created: false)) → message == UpNextCopy.alreadyInLibrary, actionTitle == nil, undo == nil (EN and DE)
  @Test func sectionFitsGermanAtLargestCappedType() throws
  // render FolioUpNextSection over a graph whose upNext holds one row titled "Frieren: Beyond Journey's End Season 2",
  // after "Frieren: Beyond Journey's End", german, width 320, .accessibility3 → every subview width <= 320 - 2*gutter
  //   (the DiscoverAfterSnapshotTests.columnFit() technique), Plan label not truncated
  ```
- [ ] **Step 2: Run.** Expected: FAIL to compile, "cannot find 'FolioUpNextPlacement' in scope".
- [ ] **Step 3: Implement.**
  - In `EditorialCollectionView.content(...)`, place `FolioUpNextSection` above the rows when `FolioUpNextPlacement.shows(...)`.
  - Load it only while the section can show: when `FolioUpNextPlacement.shows(…, isEnabled: flags.collectionUpNextV1Enabled)` is true at the existing `.task`, and from `onChange(of: status)` / `onChange(of: medium)` when the result becomes true. Collection lands on Watching, and this is backend traffic while the qualification is NOT QUALIFIED, so it is never loaded on a mount that cannot show it. The owner's own flag check is the second guard.
  - `.refreshable` calls `load(medium, force: true)` only under the same condition.
  - Route its callbacks into `show(_:)`.
- [ ] **Step 4: Run** the suite, `scripts/quality-gates/check_navigation.sh` and `check_branded_states.sh`. Expected: PASS, 0 offenders.
- [ ] **Step 5: Commit.** `git add Kuro/Views/Lists/FolioUpNext.swift Kuro/Views/Lists/FolioHeader.swift Kuro/Views/EditorialCollectionView.swift KuroTests/UpNextStoreTests.swift && git commit -m "W10: Up next section on Collection's Completed view, results in the one Folio notice slot"`

### Task 7: Load profile `collection-up-next` (F3)

**Files:** create `scripts/load/profiles/collection-up-next.js` and `scripts/load/profiles/collection-up-next.test.js`; modify `scripts/load/workloads/tracker-gaps-combined.js` (one line).

**Contract.** F3's profile contract exactly as `00-foundation.md` defines it: F3.1 (registry, `ratePerSecond`, separate absolute-rate lane on top of the unchanged base 20 rps; a `weight` field throws), F3.1b (`operations` with `share`, `core`), F3.1c (`emptyExamples`, `requires`, `seed`, `cleanupCheck`, `validate(…, ctx)` with `ctx.mode`, `--qualify`, `tracker-gaps-combined`). The predeclared base mix is unchanged, and `backend_workload.js` is not edited.

**Interfaces**
- Produces `scripts/load/profiles/collection-up-next.js`:
  - `name: "collection-up-next"`;
  - `operations` (F3.1b; samples recorded as `"collection-up-next:<op>"`): `read` `{ budgetClass: "browse", share: 0.6 }`, `plan` `{ budgetClass: "progress", share: 0.1 }`, `plan-undo` `{ budgetClass: "progress", share: 0.1 }`, `dismiss` `{ budgetClass: "progress", share: 0.1 }`, `dismiss-undo` `{ budgetClass: "progress", share: 0.1 }`;
  - `ratePerSecond: 2` (plan-stated absolute rate), `librarySizes: [100, 2000]`, `writes: true`, `emptyExamples: [[], {}, null]` (qualify must reject each; an unknown request → false);
  - `request(actor, fixture, seq, random, core)`, a 10-slot cycle, each request naming its `operation`:
    - 0–5 `read` → `{ path: "/rest/v1/rpc/library_up_next_v1", body: { p_medium: seq % 3 === 0 ? "manga" : "anime", p_limit: 30 }, operation: "read" }` (actor token, as for every personal read).
    - 6 `plan` → the insert `SupabaseLibraryBackend.insertIfMissing` sends for an up-next target the read returned: `POST /rest/v1/<medium>_user_lists?on_conflict=…&select=…` (the target's medium) with `prefer: "resolution=ignore-duplicates,return=representation"` and `list_type` Planning (read `Packages/KuroModules/Sources/KuroSupabase/SupabaseLibraryBackend.swift` and `Kuro/Composition/PostgrestLibraryTransport.swift` for the exact path, columns and headers; the profile reuses no app code).
    - 7 `plan-undo` → `rpc/apply_remove_mutations_v1` with that row's `lifecycle_id` and `server_revision`, as `removeThroughFence` sends it.
    - 8 `dismiss` → `rpc/record_taste_deck_signal` with action `skip` for another target.
    - 9 `dismiss-undo` → the same RPC with action `retract`, as `TasteStore.undoDiscoverFeedback` sends it for a title with no prior signal.

    Each write pair targets a title from the actor's latest read and is never in flight twice per actor (per-actor state, like the predeclared `progress` kind keeps `actor.writeEntry`).
  - `requires(fixture, actor)` → `"no seeded up-next fixture"` unless `actor.profileState["collection-up-next"]` records the seeded COMPLETED ids and at least the subgroup's minimum of unowned sequel targets (below);
  - `seed({ actor, fixture, call, core })` (F3.1c `seed-profiles`, before the measured window, not counted): a read-only catalogue query finds titles with `SEQUEL` edges in `media_relations`; the seed inserts, with the actor's own token exactly as `insertIfMissing` does, COMPLETED rows for such titles whose sequel the actor does not own (100 for a 2,000-title actor, 40 for a 100-title actor, both media), checks that no deck signal exists for those targets, and returns `{ completedIds, targetCount }`. F3.1c's `refresh` then excludes these ids from the base `progress` kind's `writeEntry`. (Library sizes become 2,100 / 140; the subgroup keeps the fixture's `librarySize` label.)
  - `validate(data, actor, request, ctx)`: `ctx.mode === "wiring"` (default, never release evidence): the read gives `Array.isArray(data) && data.length <= 30`; each write's documented shape (the inserted row, `items[0].outcome === "applied"` for the remove, the signal answer). `ctx.mode === "qualify"`: the semantic validators below. The runner already fails any non-2xx, including a 404 PGRST202.
  - `cleanupCheck({ actor, state, call })` (F3.1c, after the disposable account's auth 404): service-role reads of `anime_user_lists` / `manga_user_lists` for the actor's user id and of the taste-signal rows `record_taste_deck_signal` writes for the seeded targets (read the function for the table and columns first) return `[]` (delete-account removed the profile's rows).
- Combined workload line: `"collection-up-next": 2`.

**Qualification mode (`--qualify`), binding behaviour:**
- **Populated fixture:** written by `seed` (above). 2,000-title actors: ≥ 400 COMPLETED (fixture rows plus seeded ones), ≥ 100 with an unowned `SEQUEL` target, in both media. 100-title actors: ≥ 40 COMPLETED with an unowned sequel. No dismissal rows for those targets at the start.
- **Semantic validators.** An empty answer from a populated actor fails the sample, never passes.
  - Read: ≥ 1 row (30 at the cap for 2,000-title actors); every row's `after_media_id` is one of the actor's COMPLETED ids; no row is a title the actor owns; `link` is `sequel` or `reviewed`.
  - Plan: the insert returns the new Planning row.
  - Plan undo: the remove outcome is `applied`.
  - Dismiss and its undo: the signal answer reports success.
  - Because every Plan is followed by its Undo and every Dismiss by its retract for the same actor, a failed Undo or retract is itself a failed sample, so state drift cannot pass silently; the read validator also fails when a 2,000-title actor's answer drops below 30 rows (a leaked Plan or Dismiss removes a target).
- **Minimum samples (F3.1c `QUALIFY_MIN`).** At 2 rps × 600 s = 1,200 arrivals: `read` expects 720, each write operation 120 ≥ 100, i.e. 60 per subgroup ≥ 30 (2 subgroups). Fewer → `insufficient`, never `pass`; a shorter run is refused by the preflight.
- **Cleanup verification** (F3.1c `cleanupCheck`, above): anything left after account deletion makes the fixture cleanup throw and F1.3 does not accept the load scenario.
- **Destructive path, stated:** the base mix's test keeps `apply_remove` out of the predeclared kinds (`scripts/load/backend_workload.test.js`). This profile sends `apply_remove_mutations_v1` only for the Planning row it inserted in the same cycle on a disposable load account, and only in this opt-in lane.
- Reports keep this profile's lane separate from the base mix (F3), so the base regression comparison stays like-for-like.

- [ ] **Step 1: Write the failing test** `scripts/load/profiles/collection-up-next.test.js`:
  ```js
  test("collection-up-next reads library_up_next_v1 (browse) and writes Plan/Dismiss with their Undos (progress) at 2 rps", () => {
    // const p = W.loadProfiles()["collection-up-next"]; p.ratePerSecond === 2; no `weight` key
    // W.selectProfiles({ names: ["collection-up-next"] }).limits: "collection-up-next:read" 750, and :plan, :plan-undo,
    //   :dismiss, :dismiss-undo 750; W.loadWorkload("tracker-gaps-combined").profiles["collection-up-next"] === 2
    // over one 10-slot cycle: 6 reads (seq 0 → manga, seq 1 → anime; body.p_limit === 30; no anonymous flag),
    //   one insert with list_type Planning, one apply_remove_mutations_v1 carrying that row's lifecycle_id/revision,
    //   one record_taste_deck_signal skip and one retract, each naming its operation; writes never overlap per actor
    // wiring validate({}, {}, r, { mode: "wiring" }) === false; validate([], {}, r, { mode: "wiring" }) === true
    // qualify: every emptyExamples entry rejected; validate([], seededActor, r, { mode: "qualify" }) === false;
    //   a row whose after_media_id is not a seeded COMPLETED id → false
    // requires: names the reason before seed, null after seed (call double); seed uses only the actor token
    // W.qualifyVerdicts over simulated samples: 99 plan completions (or 29 in one subgroup) → "insufficient"
    // cleanupCheck true when the service-role reads return [], false when any returns a row
    // the predeclared base mix is untouched (F3 frozen-digest test still passes; W.WEIGHTS unchanged)
  });
  ```
- [ ] **Step 2: Run** `node --test scripts/load/profiles/collection-up-next.test.js`. Expected: FAIL, `Cannot read properties of undefined (reading 'ratePerSecond')` (the profile does not exist yet).
- [ ] **Step 3: Implement** the profile file and add its line to `tracker-gaps-combined.js`.
- [ ] **Step 4: Run** `bash scripts/quality-gates/test_load_profiles.sh`. Expected: PASS, every test (incl. `combined workload names every profile with an explicit rate`).
- [ ] **Step 5: Commit.** `git add scripts/load/profiles/collection-up-next.js scripts/load/profiles/collection-up-next.test.js scripts/load/workloads/tracker-gaps-combined.js && git commit -m "W10: collection-up-next load profile (read + Plan/Dismiss writes, populated qualification fixture, cleanup)"`

### Task 8: Docs, full verification, evidence

**Files:** `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md` (Rule 1), `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md` (Rule 2), `docs/tracker-gaps-2026-11/W10-up-next/EVIDENCE.md` (new).

- [ ] **Step 0: Do Step 4 (Rule 1 docs, inventory sentences) first**, so the blocking `docs-current-state` gate in Step 1 already sees the new Swift files; Step 4 then only adds the evidence-derived lines.
- [ ] **Step 1: Run the gates**, each with its expected result:
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → no FAIL (`check_migrations.sh` is clean: the new file is in `prepared-migrations/`, not `migrations/`).
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → TEST SUCCEEDED.
  - `check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh` → 0 offenders.
  - `check_bdd_traceability.sh` (F1) → the nine `W10-up-next.feature` scenarios resolve: two SQL files, six `UpNextStoreTests/…` (Plan, Dismiss, flag off, pre-existing plan, intervening change, credential lease), one load profile. The D-C rule is reported as gated.
  - `cd Packages/KuroModules && swift test` → pass (untouched).
  - `scripts/db/run_local_db_tests.sh` → TESTS PASS, the same BLOCKED set as before (exit 4 is the documented honest state), PREPARED lists the new file applied.
  - `bash scripts/quality-gates/test_load_profiles.sh` (`node --test scripts/load/*.test.js scripts/load/profiles/*.test.js`) → pass.
  - `python3 scripts/quality-gates/check_docs_current_state.py` → `PASS` after Step 4 updated the inventory sentences (app Swift +3: `UpNextModels`, `UpNextStore`, `FolioUpNext`; KuroTests +1; numbers from the script's expected text, recomputed at merge time).
  - Append `W10-up-next.feature` to `scripts/quality-gates/bdd_landed.txt` (F1 landed scope), and write the execution record `docs/tracker-gaps-2026-11/acceptance/W10.json` per F1: tested SHA, per-scenario result, commands, fixture context. Resolved ≠ accepted: the load scenario stays `blocked` until a qualification-mode run id exists, and the SQL scenarios count only with the DB test run recorded as passed. Write it in F1.3's schema: start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template W10`; workstream `W10` (the feature basename up to its first `-`, spec §4); `runs[]` with the exact command, `context` (`simulator` + UUID for `@swift`/`@ui`, `local-db` for `@sql`, `load-qualification` with report, `runKey` and cleanup report for `@load`) and a log under `docs/tracker-gaps-2026-11/acceptance/logs/W10-<run id>.txt`; one `scenarios[]` entry per non-gated scenario with its current tag. Commit order (F1.3 rule 2): make the docs/evidence commit first, run the gates on that clean commit, then commit only `docs/tracker-gaps-2026-11/acceptance/W10.json` and `acceptance/logs/` (message `W10: acceptance record`); nothing outside that folder may change after the tested commit. Run `check_bdd_traceability.sh --accepted W10` and record the output (expected `exit=1` until the qualification run).
  - No `deno`: no function touched.
  - Unique Kuro-side build warnings ≤ 60.
- [ ] **Step 2: Live walk** on simulator `7FC4B58A-…` against the fixture or an owner-approved account.
  - Default launch (flag `collection_up_next_v1` off, as for every user): landing on Watching **and** switching to Completed send **zero** `library_up_next_v1` requests (check the network log), and no section shows.
  - With `--ff-on=collection_up_next_v1`: landing on Watching sends no request. Switching to Completed sends exactly one; the RPC is not deployed, so its PGRST202 answer hides the section silently and is not asked again within 30 min.
  - Record the fixture-host render of the section in `docs/tracker-gaps-2026-11/W10-up-next/`.
- [ ] **Step 3: Write `EVIDENCE.md`** with:
  - the red/green for each task (`--exclude-pending` red included);
  - the EXPLAIN JSON excerpt;
  - the gate outputs;
  - the feature-tag split;
  - the open owner items:
    - migration approval by name and checksum;
    - the qualification-mode run on the populated fixture;
    - raising `collection_up_next_v1`; these three are separate switches;
    - the placement choice (Completed);
    - that dismissals are shared with Discover.
- [ ] **Step 4: Update the docs.**
  - Rule 1: state docs (Collection section, flag `collection_up_next_v1` at 0 %, the receipt-guarded Undo, prepared migrations list, Change Log) and the W10 status in `IMPLEMENTATION_PLAN_Variation1.md`.
  - Rule 2: in `MEMORY.md`, record the new files (`UpNextModels.swift`, `UpNextStore.swift`, `FolioUpNext.swift`, `UpNextStoreTests.swift`, the migration, the two DB tests), the updated Swift counts, and these gotchas:
    - INVOKER over RLS-readable tables only, never `media_franchise_components`;
    - `$anime_query$` / `$manga_query$` markers are an EXPLAIN contract;
    - optional `UpNextStore?` environment;
    - dismissals are Discover deck skips;
    - the flag is read at call time;
    - Undo compares `rowId`/`lifecycleId`/`revision` and the F2-widened bare plan (`FakeLibraryBackend(fence: true)` for tests).
- [ ] **Step 5: Commit.** `git add CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md docs/tracker-gaps-2026-11/W10-up-next/ scripts/quality-gates/bdd_landed.txt && git commit -m "Docs: W10 up next in your series (prepared, not deployed; flag off)"`

---

## Gated: D-C (dub info and where to watch; no tasks)
D-C chooses the data source for where-to-watch and dub availability. `streaming_availability_v1` is at 0 % and the provider dataset is empty. The options are a licensed provider API, curated manual data for the top N titles, or defer. When the owner decides:
- the `W10-up-next.feature` gated rule is rewritten with that source's scenarios;
- the up-next card can carry the provider/dub note through the existing `ProviderAvailabilityStore` (batch read, Browse class).

Nothing in this plan depends on it.
