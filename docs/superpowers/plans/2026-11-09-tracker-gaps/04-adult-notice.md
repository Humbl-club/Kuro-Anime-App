# W4 Say plainly that 18+ titles are not listed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Search or an import leaves out 18+ titles, Kuro says so in one plain line ("Kuro doesn't list 18+ titles." / "18+ — not listed in Kuro") instead of looking broken, without ever returning an adult title's name, id or picture from Search.

**Architecture:** A prepared migration adds `search_anime_page_v2` / `search_manga_page_v2`: plpgsql wrappers that return `{"items": <v1 rows in v1 order>, "hidden_adult": <bounded count or null>}` in one response, so the live v1 functions (and old TestFlight builds, the club rail search and the import match picker) stay byte-identical. `SearchStore` uses v2 for its own paged search behind flag `search_adult_notice_v1` and falls back to v1 while v2 is not deployed. For imports, a staging-time trigger on `library_import_items` turns a match to an adult catalogue row into `unmatched` with the stable detail code `ADULT_NOT_LISTED` (no new disposition value, so old clients still decode), `_import_v2_counts` adds `adult_not_listed`, and the review sheet labels those rows, keeps them out of "needs review" and out of the retry loop, and lists them in a new shareable unresolved-titles CSV.

**Tech Stack:** PostgreSQL 17 (plpgsql, pg_trgm, disposable fixture `scripts/db/run_local_db_tests.sh`), supabase-swift PostgREST, SwiftUI `ShareLink` + `Transferable`, Swift Testing, Node load harness.

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + features/W4-adult-notice.feature

## Global Constraints
- "p95 end-to-end thresholds: **Browse/Search/Clubs/Progress ≤ 750 ms**" → v2 page 1 (items + count) is Search class.
- "every new or changed backend read/write is assigned to one existing budget class, added to `scripts/load/backend_workload.js` (F3), and covered by an SQL-plan check. A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED, and its change must not worsen the measured steady-state result. Budgets are never relaxed for a retry." → no extra request per search (the count rides in the page-1 response); flag `search_adult_notice_v1` stays 0 % until qualification.
- "RLS on every new table; every function `SET search_path = public, extensions`; no raw `user_id` from clients; SECURITY DEFINER functions grant EXECUTE only to the roles that need it and revoke PUBLIC (see `20261108120159_review_security_v1.sql`); new SQL bodies in plpgsql (fixture rule); error codes in MESSAGE or HINT, never DETAIL alone. Migrations are written to `supabase/prepared-migrations/` and applied only after explicit owner approval; never `supabase db push --include-all` or history repair without a new approval."
- Changing a `RETURNS TABLE` needs DROP + CREATE; v1 is therefore not changed at all (additive v2).
- "every user-facing string through `KuroLocale` (EN + DE); monochrome only, no coloured status; branded states only (`check_branded_states.sh`); light only until W8 ships."
- "one `@MainActor @Observable final class` owner per capability … views … import no Supabase SDK module … no Combine; `print` only inside `#if DEBUG`; no force unwraps."
- "Do not interpret missing source history as newly deleted data." → adult import rows are never applied, never erase anything, and are kept in the unresolved file.
- "Process: Rule 1 (three state docs) and Rule 2 (memory) after every workstream; quality gates `scripts/quality-gates/run_all.sh` green; build warning count does not rise above the 2026-10-31 baseline (60 unique Kuro-side warnings)."
- Binding names: prepared migration `20261110100000_search_hidden_adult_v1.sql`; DB test `supabase/tests/rls/105_search_hidden_adult_count.sql`; load profile `search-with-hidden-adult-count`; RFC 4180 encoder `KuroLibrary.RFC4180` from W2 Task 1.

## Review Focus
1. **A false "18+" line.** Titles hidden for other reasons (Ecchi-only, `SPECIAL`/`MUSIC`/`TV_SHORT`, an active refinement such as Airing) must not count, nor may a filters-only search, a 1-character query or page 2+. Definition: adult = `is_adult is true or genres @> array['Hentai']`; counted only when it passes every other v1 filter and the v1 text-match predicate; only for page 1 (`p_cursor_id is null`) and a trimmed query of ≥ 2 characters; capped at 100. Pinned by the matrix in `105_search_hidden_adult_count.sql` (Task 1).
2. **Leaking adult data through v2.** The response must never contain an adult row's title, id or cover URL, including via ordering ties or the count. Pinned by the "response text contains none of …" assertions in 105 (Task 1).
3. **v2 not deployed / old builds.** Until the owner applies the migration, v2 answers PGRST202; Search must keep working (fallback to v1, no footnote) and must not retry v2 on every keystroke. Old TestFlight builds keep calling v1, which is unchanged. Pinned by `AdultNoticeTests/searchFallsBackToV1WhenV2NotDeployed` (Task 3) and the differential v1 = v2.items check in 105.
4. **Adult import rows treated as failures or looping.** They must not raise `needsReview`, must not flip the heading to "Saved, with items to review.", must not be re-staged by "Review unresolved titles in a new import" (endless loop), must not offer "Match to a catalogue title", and must not change rows of imports that were already applied (undo paths). Pinned by `AdultNoticeTests/importReviewLabelsAdultMatchesAndKeepsThemInUnresolvedFile` (Task 5) and the trigger scope assertions in 105 (Task 2).
5. **Old clients decoding import items.** `ImportDisposition` is a closed enum in TestFlight 25; a new raw value would fail whole item pages. The plan keeps `unmatched` and puts the code in `detail`; the new `adult_not_listed` counter is ignored by the old lenient `ImportCounts` decoder. Pinned by `AdultNoticeTests/oldImportPayloadStillDecodes` (Task 5).

## Success parameters
| Spec §5.2 W4 | Measured by | Expected |
|---|---|---|
| Search shows "Kuro doesn't list 18+ titles" when the query matched only adult titles | `xcodebuild … -only-testing:KuroTests/AdultNoticeTests` + `scripts/db/run_local_db_tests.sh --only 105_search_hidden_adult_count` | `searchShowsNoticeOnlyWhenAdultTitlesWereHidden` passes; 105: `items = []`, `hidden_adult = 1` for the adult-only query |
| The import review counts adult titles separately and keeps them in the unresolved file | same `AdultNoticeTests` run + 105 import section | `importReviewLabelsAdultMatchesAndKeepsThemInUnresolvedFile` passes; 105: disposition `unmatched`, detail prefix `ADULT_NOT_LISTED:`, `adult_not_listed = 3` |
| Search stays ≤ 750 ms p95 with the count | `node --test scripts/load/profiles/search-with-hidden-adult-count.test.js` (offline), 105 EXPLAIN assertions, then the owner-approved load run | profile registered in class `search` at 1 rps; count subquery uses `Bitmap Index Scan` on a title index (no `Seq Scan` on `anime`/`manga`); owner-approved `--qualify` run: p95 ≤ 750 ms with ≥ 100 completions and ≥ 30 per subgroup, base lane not worse than the current report |
| Switched off, the count is never requested | `xcodebuild … -only-testing:KuroTests/AdultNoticeTests/flagOffSendsNoRequest` | passes: flag off → zero `search_*_page_v2` requests, v1 search unchanged |

## File Structure
| File | Responsibility |
|---|---|
| `supabase/prepared-migrations/20261110100000_search_hidden_adult_v1.sql` (new) | `_search_hidden_adult_{anime,manga}_v1`, `search_anime_page_v2`, `search_manga_page_v2`, grants; import adult trigger; `_import_v2_counts` + `adult_not_listed` |
| `supabase/tests/rls/105_search_hidden_adult_count.sql` (new) | search matrix, no-leak, differential v1 = v2.items, grants, EXPLAIN; import staging, re-staging, counts, trigger scope |
| `supabase/tests/pending_migrations.txt` (modify) | list the new prepared migration |
| `Kuro/Search/SearchRPCParams.swift` (modify) | `SearchPageV2<Card>` decodable |
| `Kuro/Search/SearchStore.swift` (modify) | page-1 via v2 behind the flag, `hiddenAdultCount`, v1 fallback + not-deployed memory |
| `Kuro/Search/SearchAdultNotice.swift` (new) | pure footnote rule + EN/DE copy |
| `Kuro/Services/FeatureFlags.swift` (modify) | `searchAdultNoticeV1Enabled` |
| `Kuro/Composition/AppComposition.swift` (modify) | `publicData.search.adultNoticeEnabled = { shell.flags.searchAdultNoticeV1Enabled }` |
| `Kuro/Views/EditorialSearchView.swift` (modify) | the footnote under results and under the no-results state |
| `Packages/KuroModules/Sources/KuroLibrary/LibraryImportWorkflow.swift` (modify) | `ImportCounts.adultNotListed`, `needsReview` excludes it; `ImportReviewItem.isAdultNotListed` + code constant |
| `Kuro/Imports/ImportUnresolvedFile.swift` (new) | unresolved-titles CSV (`Transferable`), reasons incl. `adult_not_listed` |
| `Kuro/Imports/ImportWorkflowPresentation.swift` (modify) | retry set excludes adult rows (`unresolvedRetryIds`) |
| `Kuro/Views/ImportCopy.swift` (modify) | "18+ — not listed in Kuro" row label + count line, EN/DE |
| `Kuro/Views/ImportWorkflowSheet.swift` (modify) | label adult rows, hide the match action, keep them out of "Needs review", share the unresolved file |
| `KuroTests/AdultNoticeTests.swift` (new) | Swift tests named in the feature + pinning tests |
| `scripts/load/profiles/search-with-hidden-adult-count.js`, `.test.js` (new); `scripts/load/workloads/tracker-gaps-combined.js` (one line) | profile `search-with-hidden-adult-count` (F3 contract, 1 rps) |
| `docs/tracker-gaps-2026-11/acceptance/W4.json` (new) | F1.3 execution record |
| `docs/tracker-gaps-2026-11/W4-adult-notice/` (new) | precondition result, plans, evidence |
| `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, memory `MEMORY.md` | Rules 1–2 |

**Order:** W2 Task 1 (`KuroLibrary/RFC4180.swift`) must be merged before Task 5 here. If W4 runs first, Task 5 creates `RFC4180.swift` exactly as W2 Task 1 specifies (same file, signature and test `rfc4180FieldQuotesOnlyWhenNeeded`), and W2 Task 1 then only adds its value types.

---

### Task 0: Precondition (owner, read-only, no code)
- [ ] Ask the owner to run, read-only, in the SQL editor: `select 'anime', count(*) filter (where is_adult), count(*) filter (where genres @> array['Hentai']) from public.anime union all select 'manga', count(*) filter (where is_adult), count(*) filter (where genres @> array['Hentai']) from public.manga;` Record the four numbers in `docs/tracker-gaps-2026-11/W4-adult-notice/PRECONDITION.md`. Agents do not query production.
- [ ] If both media hold adult rows (expected: the bulk importers store `is_adult: anime.isAdult` with no AniList adult filter), proceed. If they hold none, the search count and the import label never fire: stop and report to the lead (the import half would need `isAdult` in `concierge-import-anilist/paging.ts`, an Edge Function change with its own deploy approval, and MAL XML has no adult field).

### Task 1: v2 search functions with the bounded hidden-adult count

**Files:** create `supabase/prepared-migrations/20261110100000_search_hidden_adult_v1.sql` (search section), `supabase/tests/rls/105_search_hidden_adult_count.sql` (search section); modify `supabase/tests/pending_migrations.txt`.

**Interfaces — Consumes:** live `public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)` and `public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)` (unchanged; definitions in `20261109001251_load_hotpaths_v1.sql`), indexes `idx_{anime,manga}_load_title_{english,romaji,native,blob,fts}_v1`. **Produces:**
```sql
-- internal, not callable by clients; one per medium so each holds exactly one $count$ … $count$ dynamic SQL block
create function public._search_hidden_adult_anime_v1(p_query text, p_trending boolean, p_new_season boolean, p_classics boolean,
  p_hidden_gems boolean, p_airing_only boolean, p_season text, p_season_year integer) returns integer
  language plpgsql stable security definer set search_path = public, extensions set jit = off set pg_trgm.similarity_threshold = '0.3';
create function public._search_hidden_adult_manga_v1(p_query text, p_trending boolean, p_new_season boolean, p_classics boolean,
  p_hidden_gems boolean) returns integer   -- same settings
create function public.search_anime_page_v2(<exactly v1's anime parameters and defaults>) returns jsonb
  language plpgsql stable security definer set search_path = public, extensions set jit = off set pg_trgm.similarity_threshold = '0.3';
create function public.search_manga_page_v2(<exactly v1's manga parameters and defaults>) returns jsonb  -- same settings
-- result: {"items": [<v1 row objects, v1 order>], "hidden_adult": <0..100> | null}
revoke all on function public._search_hidden_adult_anime_v1(...), public._search_hidden_adult_manga_v1(...) from public, anon, authenticated;
revoke all on function public.search_anime_page_v2(...), public.search_manga_page_v2(...) from public;
grant execute on function public.search_anime_page_v2(...), public.search_manga_page_v2(...) to anon, authenticated;  -- same roles as v1
```
Pinned rules:
- `items` = `coalesce(jsonb_agg(to_jsonb(r) - 'ordinality' order by r.ordinality), '[]'::jsonb)` over `public.search_<medium>_page(<all args passed through>) with ordinality r` — v1 does all ranking, filtering and paging.
- `hidden_adult` = `null` unless `p_cursor_id is null and length(btrim(coalesce(p_query, ''))) >= 2`; else `_search_hidden_adult_<medium>_v1(...)`.
- Each helper body is `declare v_count integer; begin execute $count$ <sql> $count$ into v_count using p_query, p_trending, p_new_season, p_classics, p_hidden_gems[, p_airing_only, p_season, p_season_year]; return coalesce(v_count, 0); end;` (an integer function cannot use `return query`). Placeholders are fixed: `$1` query, `$2` trending, `$3` new season, `$4` classics, `$5` hidden gems, anime only `$6` airing, `$7` season, `$8` season year. `<sql>` is `select count(*)::int from (select 1 from public.<medium> a where (a.is_adult is true or a.genres @> array['Hentai']::text[]) and <v1's non-content filters verbatim: format exclusion (anime only) and the p_trending/p_new_season/p_classics/p_hidden_gems/p_airing_only/p_season/p_season_year clauses> and (<v1 `ranked` WHERE text-match disjunction verbatim, without its `$1 is null` branch>) limit 100) s`. Ecchi is NOT a condition in either direction (an adult Ecchi title counts; an Ecchi-only title does not).

- [ ] **Step 1: failing DB test.** `105_search_hidden_adult_count.sql` header: `-- @requires table public.anime`, `-- @requires table public.manga`, `-- @requires function public.search_anime_page(text,integer,float8,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)`, `-- @requires function public.search_manga_page(text,integer,float8,integer,integer,boolean,boolean,boolean,boolean)` (v2 is the subject: NOT required, its absence must FAIL). `begin; set local jit = off;` insert fixtures (ids `9105001…`):
  - anime "X" `title_english 'Velvet Hush'`, `is_adult true`, `cover_image_large 'https://img.test/velvet.jpg'`, format TV; anime "Y" `'Quiet Harbor'` non-adult; anime `'Silk Veil'` `is_adult false`, genres `{Hentai}`; anime `'Satin Breeze'` non-adult genres `{Ecchi}`; anime `'Lacquer Night'` adult, format `SPECIAL`; anime `'Ember Rite'` adult, status FINISHED; manga `'Velvet Ledger'` adult.
  - Assertions (`tests.eq` / `tests.ok`), each a named row:
    - `search_anime_page_v2('velvet hush')` → `jsonb_array_length(items) = 0`, `hidden_adult = 1`.
    - response `::text` contains none of `'Velvet'`, `'9105001'`, `'velvet.jpg'`.
    - `'quiet harbor'` → items has Y's id, `hidden_adult = 0`.
    - `'silk veil'` → `hidden_adult = 1` (Hentai counts); `'satin breeze'` → items `[]`, `hidden_adult = 0` (Ecchi-only does not count); `'lacquer night'` → `hidden_adult = 0` (format-excluded).
    - `'ember rite'` with `p_airing_only => true` → `hidden_adult = 0` (refinement excludes it); without → `1`.
    - `'velvet hush'` with `p_cursor_id => 1, p_cursor_rank => 600, p_cursor_popularity => 0` → `hidden_adult is null`; query `'v'` → null; query `''` with `p_trending => true` → null.
    - `search_manga_page_v2('velvet ledger')` → items `[]`, `hidden_adult = 1`.
    - cap: 120 adult rows titled `'Cap Test n'` → `hidden_adult = 100`.
    - differential: for queries `'naruto'`, `'one'`, `'fate'`, `'berserk'`, `'quiet'` and a page-2 cursor taken from page 1, `v2.items = (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from v1(...) x)` for both media.
    - grants: `has_function_privilege('anon', 'public.search_anime_page_v2(...)', 'execute')` and `authenticated` true (both media); both `_search_hidden_adult_*_v1` false for `anon` and `authenticated`; `prosecdef`, `prolang = plpgsql` and `proconfig @> array['search_path=public, extensions','jit=off','pg_trgm.similarity_threshold=0.3']` for all four.
    - EXPLAIN: for each medium extract `_search_hidden_adult_<medium>_v1`'s SQL with `split_part(prosrc, '$count$', 2)` (as `102_load_hotpaths.sql` does with `'$query$'`), replace `$8`…`$2` (descending, so `$1` never clobbers `$1x`) with `null`/`false` and `$1` with `quote_literal('velvet hush')`, `explain (analyze, format json)` over the 22,000-row generated catalogue (same `generate_series` inserts as 102 with ids `8100000+n`); assert the plan text contains `Bitmap Index Scan` on one of `idx_anime_load_title_*_v1` and no `"Seq Scan"` on `anime`; record it with `raise notice`.
  - Add `20261110100000_search_hidden_adult_v1.sql` to `pending_migrations.txt` under a `# 2026-11-10 W4 (prepared only; owner approval required to deploy)` comment.
- [ ] **Step 2:** `scripts/db/run_local_db_tests.sh --only 105_search_hidden_adult_count` → FAIL: `function public.search_anime_page_v2(unknown) does not exist`.
- [ ] **Step 3:** write the search section of the migration (`begin; set local lock_timeout = '3s'; set local search_path = public, extensions; … notify pgrst, 'reload schema'; commit;`, header `-- PREPARED ONLY (W4): owner approval required to apply.`).
- [ ] **Step 4:** same command → PASS; then `scripts/db/run_local_db_tests.sh --only 102_load_hotpaths` → still PASS (v1 untouched).
- [ ] **Step 5:** `git add supabase/prepared-migrations/20261110100000_search_hidden_adult_v1.sql supabase/tests/rls/105_search_hidden_adult_count.sql supabase/tests/pending_migrations.txt && git commit -m "W4: search v2 with bounded hidden-adult count (prepared)"`

### Task 2: Import staging marks adult matches; counts expose them

**Files:** modify `supabase/prepared-migrations/20261110100000_search_hidden_adult_v1.sql` (import section), `supabase/tests/rls/105_search_hidden_adult_count.sql` (import section).

**Interfaces — Consumes:** `public.library_import_items` (columns from `20261007040000` + `20261008110000`), `prepare_import_chunk_v2`, `start_library_import_v2`, `_import_v2_counts` (all live, unchanged except the counts function). **Produces:**
```sql
create function public._import_item_adult_guard_v1() returns trigger
  language plpgsql set search_path = public, extensions;   -- not security definer; revoke all from public, anon, authenticated
create trigger library_import_items_adult_guard_v1
  before insert or update of media_id, disposition on public.library_import_items
  for each row when (new.media_id is not null and new.disposition in ('new', 'existing', 'changes'))
  execute function public._import_item_adult_guard_v1();
-- body: if the anime/manga row new.media_id (by new.medium) has is_adult is true or genres @> array['Hentai'] then
--   new.disposition := 'unmatched'; new.detail := 'ADULT_NOT_LISTED: 18+ title, not listed in Kuro';
--   (CODE: text, so TestFlight 25, which shows detail raw, reads plain English)
--   new.media_id := null;
--   new.identity_resolved := false; new.manual_resolved := false; new.current_values := null;
--   new.changed_fields := '[]'; new.expected_revision := null; new.expected_lifecycle := null;
--   new.baseline_tombstones := '[]';  (title is left as staged)
create or replace function public._import_v2_counts(p_job uuid) returns jsonb language plpgsql stable set search_path = public, extensions
  -- identical keys and filters as today, plus 'adult_not_listed', count(*) filter (where disposition = 'unmatched' and detail like 'ADULT_NOT_LISTED:%')
```
Why a trigger: it covers every staging path (`prepare_import_chunk_v2` insert and its `on conflict … do update`, manual mapping, re-review) without copying the 130-line staging function; the `when` clause leaves applied/undone rows (`added`, `updated`, `unchanged`, `pending`, `conflict`) untouched. `apply_import_chunk_v2` already raises `ITEM_REQUIRES_REVIEW` for `unmatched`/`media_id is null`. The legacy `apply_import_chunk_v1` path (writes straight into list tables) is out of scope: it is used only when `series_foundation_v1` is off (100 % on since 2026-11-02); recorded as an open item.

- [ ] **Step 1: failing assertions** appended to 105 (add `-- @requires table public.library_import_jobs` and `-- @requires function public.start_library_import_v2(jsonb,text)`): `tests.make_user(1050)`; anime `9105101` 'Velvet Hush Import' adult `mal_id 9905101`, `9105102`, `9105103` adult; `9105104` 'Plain Import' non-adult `mal_id 9905104`; as that user start a myanimelist export v2 job and `prepare_import_chunk_v2` with the four items plus one unknown MAL id `9905999`:
  - the three adult items: `disposition = 'unmatched'`, `detail like 'ADULT_NOT_LISTED:%'`, `media_id is null`, `identity_resolved = false`;
  - `9905104` → `disposition = 'new'`, `media_id = 9105104`; `9905999` → `unmatched`, detail not starting `ADULT_NOT_LISTED:`;
  - re-send the same chunk (on-conflict update path) → the adult items are still `unmatched`/`ADULT_NOT_LISTED`;
  - `public._import_v2_counts(job)` → `unmatched = 4`, `adult_not_listed = 3`;
  - `import_items_page_v2(job)` item for `9905101` has `"disposition":"unmatched"` and `detail` starting `"ADULT_NOT_LISTED:"`;
  - scope: a pre-existing item row updated to `disposition = 'added'` with an adult `media_id` (simulating an import applied before this migration) keeps `added` and its `media_id`;
  - grants: `_import_item_adult_guard_v1` not executable by `anon`/`authenticated`.
- [ ] **Step 2:** `scripts/db/run_local_db_tests.sh --only 105_search_hidden_adult_count` → FAIL at `adult items are unmatched` (got `new`).
- [ ] **Step 3:** add the import section to the migration.
- [ ] **Step 4:** same command → PASS; `scripts/db/run_local_db_tests.sh --only 97_import_review_recovery_v2` → still PASS.
- [ ] **Step 5:** `git add supabase/prepared-migrations/20261110100000_search_hidden_adult_v1.sql supabase/tests/rls/105_search_hidden_adult_count.sql && git commit -m "W4: import staging marks adult matches ADULT_NOT_LISTED (prepared)"`

### Task 3: SearchStore reads v2 page 1 with fallback

**Files:** modify `Kuro/Search/SearchRPCParams.swift`, `Kuro/Search/SearchStore.swift`, `Kuro/Services/FeatureFlags.swift`, `Kuro/Composition/AppComposition.swift`; create `Kuro/Search/SearchAdultNotice.swift`, `KuroTests/AdultNoticeTests.swift`.

**Interfaces — Produces:**
```swift
struct SearchPageV2<Card: Decodable>: Decodable { let items: [Card]; let hiddenAdult: Int? }   // keys "items", "hidden_adult"
// SearchStore
private(set) var hiddenAdultCount: Int = 0                    // reset in beginNewQuery(); anime + manga summed in combined scope
@ObservationIgnored var adultNoticeEnabled: @MainActor () -> Bool = { false }
/// First pages (cursor nil) of the owner's own paging and refresh call `search_<medium>_page_v2` when
/// adultNoticeEnabled() and the contract is not remembered as undeployed; page 2+ and every external caller
/// (`fetchSearchAnimePage` / `fetchSearchMangaPage`, used by ClubDetailSheets and ImportCatalogMatchPicker) stay on v1.
/// A v2 failure classified `ReleaseFailure.classify(error) == .notDeployed` is remembered for the same interval as
/// `DiscoveryStore.discoverUndeployedRetryInterval` and that page is re-requested once from v1.
nonisolated enum SearchAdultNotice {
    static func line(hiddenAdult: Int, german: Bool) -> String?   // nil for ≤ 0
    // EN "Kuro doesn't list 18+ titles."  DE "Kuro listet keine Titel ab 18."
}
// FeatureFlags: var searchAdultNoticeV1Enabled: Bool { evaluate("search_adult_notice_v1") }
// AppComposition.makeGraph, after makePublicData: publicData.search.adultNoticeEnabled = { shell.flags.searchAdultNoticeV1Enabled }
```
- [ ] **Step 1: failing tests** in `@MainActor @Suite struct AdultNoticeTests`:
```swift
@Test func searchShowsNoticeOnlyWhenAdultTitlesWereHidden() async throws {
    let harness = try PublicDataHarness { request in
        request.resource == "rpc/search_anime_page_v2" ? .json(#"{"items":[],"hidden_adult":1}"#) : .status(500)
    }
    let search = harness.search; search.adultNoticeEnabled = { true }
    search.resetSearch(query: "velvet hush", isManga: false); await search.fetchNextSearchPage()
    #expect(search.hiddenAdultCount == 1 && search.searchAnimeItems.isEmpty)
    #expect(SearchAdultNotice.line(hiddenAdult: search.hiddenAdultCount, german: false) == "Kuro doesn't list 18+ titles.")
    #expect(SearchAdultNotice.line(hiddenAdult: 1, german: true) == "Kuro listet keine Titel ab 18.")
    harness.respond { _ in .json(#"{"items":[],"hidden_adult":0}"#) }
    search.resetSearch(query: "quiet harbor", isManga: false); await search.fetchNextSearchPage()
    #expect(search.hiddenAdultCount == 0)
    #expect(SearchAdultNotice.line(hiddenAdult: 0, german: false) == nil)
}
@Test func searchFallsBackToV1WhenV2NotDeployed() async throws {
    // v2 → 404 PGRST202; v1 → one AnimeCard row. Expect results shown, hiddenAdultCount == 0,
    // a second query within the interval sends no v2 request (count requests by resource).
}
@Test func combinedScopeSumsBothCountsAndPageTwoSendsNoCount() async throws {
    // v2 anime hidden 1, manga hidden 2 → hiddenAdultCount == 3; next page goes to v1 with a cursor (no v2 request).
}
@Test func flagOffSendsNoRequest() async throws {
    // Release switch (program decision 1): adultNoticeEnabled false → no rpc/search_*_page_v2 request at all (the count is
    // never asked for); the search itself still runs on v1 exactly as today (one rpc/search_anime_page request), and
    // hiddenAdultCount stays 0.
}
```
(Use the existing `PublicDataHarness` response helpers in `KuroTests/StubPostgREST.swift`; if `search` is not exposed on it, build `SearchStore(client: StubSupabase.makeClient(server: harness.server))`.)
- [ ] **Step 2:** `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/AdultNoticeTests` → FAIL: `value of type 'SearchStore' has no member 'adultNoticeEnabled'`.
- [ ] **Step 3:** implement; keep both public `fetchSearch*Page` signatures unchanged; first-page private helpers return `(cards, hiddenAdult)`.
- [ ] **Step 4:** same command → PASS; existing `-only-testing:KuroTests/PublicDataHTTPContractTests` still PASS.
- [ ] **Step 5:** `git add Kuro/Search/SearchRPCParams.swift Kuro/Search/SearchStore.swift Kuro/Search/SearchAdultNotice.swift Kuro/Services/FeatureFlags.swift Kuro/Composition/AppComposition.swift KuroTests/AdultNoticeTests.swift && git commit -m "W4: SearchStore reads the hidden-adult count from search v2"`

### Task 4: Search footnote in the view

**Files:** modify `Kuro/Views/EditorialSearchView.swift`; extend `KuroTests/AdultNoticeTests.swift`.

A tiny view `SearchAdultFootnote(hiddenAdult: Int)` (in `SearchAdultNotice.swift`) renders the line or `EmptyView`. Placement: inside the results branch, after the `LazyVStack` of rows (and after the busy mark), and directly under `SearchNoResultsState` in the empty branch: `SearchAdultFootnote(hiddenAdult: search.hiddenAdultCount).padding(.horizontal, gutter)` whose body is `if let line = SearchAdultNotice.line(hiddenAdult:german: KuroLocale.isGerman) { Text(line).font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary).padding(.top, KuroDesignSpacing.sm).accessibilityIdentifier("search.adultNotice") }`. Not shown in the error/offline branches. Monochrome, no icon.

Merge order (`00-program.md`): W3 lands first and wraps `EditorialSearchView`'s transient-banner block in `ReleaseAlertOfferStack`. Rebase onto it; the footnote sits in the results and empty branches, not in the banner position, so W3's stack is left as it is.

- [ ] **Step 1: failing test** `@Test func footnoteHasHeightOnlyWhenTitlesWereHidden()`: host `SearchAdultFootnote(hiddenAdult: 1)` and `SearchAdultFootnote(hiddenAdult: 0)` in `UIHostingController` (pattern: `HomeCompositionSnapshotTests`) with `.environment(\.locale, Locale(identifier: "de_DE"))` and `.dynamicTypeSize(.accessibility3)`; `sizeThatFits(in: CGSize(width: 375, height: .greatestFiniteMagnitude))` → height > 0 and width ≤ 375 for 1, height == 0 for 0.
- [ ] **Step 2:** run `-only-testing:KuroTests/AdultNoticeTests` → FAIL: `cannot find 'SearchAdultFootnote' in scope`.
- [ ] **Step 3:** implement the two placements.
- [ ] **Step 4:** same command → PASS; `scripts/quality-gates/check_branded_states.sh` and `check_navigation.sh` → 0 offenders.
- [ ] **Step 5:** `git add Kuro/Views/EditorialSearchView.swift Kuro/Search/SearchAdultNotice.swift KuroTests/AdultNoticeTests.swift && git commit -m "W4: search footnote for hidden 18+ titles"`

### Task 5: Import review label, counts and the unresolved-titles file

**Files:** modify `Packages/KuroModules/Sources/KuroLibrary/LibraryImportWorkflow.swift`, `Kuro/Imports/ImportWorkflowPresentation.swift`, `Kuro/Views/ImportCopy.swift`, `Kuro/Views/ImportWorkflowSheet.swift`; create `Kuro/Imports/ImportUnresolvedFile.swift`; extend `KuroTests/AdultNoticeTests.swift`.

**Interfaces — Consumes:** `KuroLibrary.RFC4180` (W2 Task 1). **Produces:**
```swift
// KuroLibrary
extension ImportCounts { public var adultNotListed: Int }      // CodingKey "adult_not_listed", decodeIfPresent ?? 0
// needsReview becomes: max(0, conflict + unmatched + invalid - adultNotListed)
extension ImportReviewItem {
    public static let adultNotListedCode = "ADULT_NOT_LISTED"
    public var isAdultNotListed: Bool { disposition == .unmatched && (detail?.hasPrefix(Self.adultNotListedCode + ":") ?? false) }
}
// App
extension ImportWorkflowPresentation {
    /// Items "Review unresolved titles in a new import" re-stages: unmatched/conflict/sourceChanged minus adult rows.
    nonisolated static func unresolvedRetryIds(_ items: [ImportReviewItem]) -> Set<String>
}
struct ImportUnresolvedFile: Transferable, Equatable {
    let items: [ImportReviewItem]      // unmatched, conflict, invalid, sourceChanged (adult included)
    let fileName: String               // "kuro-import-unresolved-YYYY-MM-DD.csv" (device time zone)
    nonisolated static let header = ["medium", "external_id", "title", "reason"]
    nonisolated static func reason(_ item: ImportReviewItem) -> String
        // "adult_not_listed" | "not_in_catalogue" | "conflict" | "invalid" | "source_changed"
    nonisolated func csv() -> Data     // UTF-8 BOM + RFC4180 rows, sorted by medium, external_id
    static var transferRepresentation: some TransferRepresentation   // DataRepresentation(exportedContentType: .commaSeparatedText) + suggestedFileName
}
// ImportCopy
static func adultRowLabel(german: Bool) -> String          // "18+ — not listed in Kuro" / "18+ — nicht in Kuro gelistet"
static func adultCountLine(_ count: Int, german: Bool) -> String?   // nil for 0; "18+ — not listed in Kuro: 3" / "18+ — nicht in Kuro gelistet: 3"
static func unresolvedFileAction(german: Bool) -> String   // "Save the unresolved titles" / "Offene Titel als Datei sichern"
```
Sheet changes: summary shows `adultCountLine(job.counts.adultNotListed)` under the counts line; `reviewRow` shows `adultRowLabel` instead of "Needs review" and hides the raw `detail` text and the "Match to a catalogue title" action when `item.isAdultNotListed`; `ReviewGroup.needsReview.includes` excludes adult rows; `reviewUnresolved()` uses `unresolvedRetryIds`; when any unresolved item exists, a `ShareLink(item: ImportUnresolvedFile(...), preview: SharePreview(fileName))` styled as `textAction` with `unresolvedFileAction`. No file is written to disk by the app (the share sheet receives data). Heading/`allRejected` follow `needsReview` and so ignore adult rows; when every title of an import is adult (nothing saved, `applied == 0`, `needsReview == 0`), the heading uses the existing "Nothing was applied." / "Nichts übernommen." (extend `allRejected` to `applied == 0 && unchanged == 0 && (needsReview > 0 || adultNotListed > 0)`), never "Import complete.". The legacy Profile toast line (`ProfileImportCoordinator.importCountLine`, `LibraryImportCounts`, v1 path only) is unchanged.

- [ ] **Step 1: failing tests**
```swift
@Test func importReviewLabelsAdultMatchesAndKeepsThemInUnresolvedFile() throws {
    let counts = try JSONDecoder().decode(ImportCounts.self, from: Data(#"{"added":2,"unmatched":4,"adult_not_listed":3}"#.utf8))
    #expect(counts.adultNotListed == 3 && counts.needsReview == 1)
    let items = Self.items(adult: ["111", "112", "113"], plainUnmatched: ["999"], new: ["201", "202"])
    #expect(items.filter(\.isAdultNotListed).count == 3)
    #expect(ImportCopy.adultCountLine(3, german: false) == "18+ — not listed in Kuro: 3")
    #expect(ImportCopy.adultCountLine(3, german: true) == "18+ — nicht in Kuro gelistet: 3")
    #expect(ImportCopy.adultRowLabel(german: false) == "18+ — not listed in Kuro")
    let rows = try Self.csvRows(ImportUnresolvedFile(items: items, fileName: "x.csv").csv())
    #expect(rows[0] == ImportUnresolvedFile.header)
    #expect(rows.dropFirst().filter { $0[3] == "adult_not_listed" }.map { $0[1] } == ["111", "112", "113"])
    #expect(rows.dropFirst().contains { $0[1] == "999" && $0[3] == "not_in_catalogue" })
    #expect(!rows.dropFirst().contains { ["201", "202"].contains($0[1]) })
    #expect(ImportWorkflowPresentation.unresolvedRetryIds(items) == ["anime|999"])
    var allAdult = ImportCounts(); allAdult.unmatched = 3; allAdult.adultNotListed = 3
    #expect(allAdult.needsReview == 0)   // and ImportOutcome with these counts → allRejected == true
}
@Test func oldImportPayloadStillDecodes() throws {
    // an import_items_page_v2 page JSON without "adult_not_listed" and with detail "ADULT_NOT_LISTED: 18+ title, not listed in Kuro"
    // decodes with today's types; ImportCounts without the key → adultNotListed == 0, needsReview unchanged.
}
```
- [ ] **Step 2:** run `-only-testing:KuroTests/AdultNoticeTests` → FAIL: `value of type 'ImportCounts' has no member 'adultNotListed'`.
- [ ] **Step 3:** implement (package change first; `cd Packages/KuroModules && swift test` must stay green).
- [ ] **Step 4:** `-only-testing:KuroTests/AdultNoticeTests -only-testing:KuroTests/ImportWorkflowIntegrationTests -only-testing:KuroTests/ImportRestyleTests` → PASS.
- [ ] **Step 5:** `git add Packages/KuroModules/Sources/KuroLibrary/LibraryImportWorkflow.swift Kuro/Imports/ImportUnresolvedFile.swift Kuro/Imports/ImportWorkflowPresentation.swift Kuro/Views/ImportCopy.swift Kuro/Views/ImportWorkflowSheet.swift KuroTests/AdultNoticeTests.swift && git commit -m "W4: import review labels 18+ titles and shares the unresolved file"`

### Task 6: Load profile `search-with-hidden-adult-count`

**Files:** create `scripts/load/profiles/search-with-hidden-adult-count.js`, `scripts/load/profiles/search-with-hidden-adult-count.test.js`; modify `scripts/load/workloads/tracker-gaps-combined.js` (one line).

**Interfaces — Consumes:** F3's profile contract exactly as `00-foundation.md` defines it (F3.1 registry, `ratePerSecond` and separate absolute-rate lane, a `weight` field throws; F3.1b `core`; F3.1c `emptyExamples`, `validate(…, ctx)`, `--qualify`, `tracker-gaps-combined`). `backend_workload.js` is not edited and the profile never enters `WEIGHTS`. **Produces:**
```js
module.exports = {
  name: "search-with-hidden-adult-count",
  budgetClass: "search",          // 750 ms
  ratePerSecond: 1,               // old weight 5 × 0.2 (F3.1 conversion): page-1 v2 calls only
  writes: false,                  // librarySizes omitted: every fixture size (0, 25, 100, 2000) supplies actors
  emptyExamples: [[], {}, { items: [], hidden_adult: 0 }, { items: [{ id: 1 }] }],   // qualify must reject each (F3.1c)
  request(actor, fixture, seq, random, core) {  // medium = seq % 3 === 0 ? "manga" : "anime"; same 10-word list as the predeclared `search`
    return { path: "/rest/v1/rpc/search_" + medium + "_page_v2", body: { p_query: WORDS[seq % 10], p_limit: 30 } };
  },
  validate(data, actor, request, ctx) {
    const shape = Array.isArray(data?.items) && data.items.every((x) => Number.isInteger(x.id)) &&
      (data.hidden_adult === null || Number.isInteger(data.hidden_adult));
    if (ctx?.mode !== "qualify") return shape;                       // wiring: shape only, never release evidence
    // qualify: the fixture words match real catalogue titles, so page 1 is non-empty, and a page-1 query of ≥ 2
    // characters always carries an integer count (0–100), never null
    return shape && data.items.length >= 1 && Number.isInteger(data.hidden_adult) && data.hidden_adult >= 0 && data.hidden_adult <= 100;
  },
};
```
- Combined workload line: `"search-with-hidden-adult-count": 1`.
- Qualification arithmetic (F3.1c preflight): 1 rps × 600 s = 600 expected completions ≥ 100; ÷ 4 covered subgroups = 150 ≥ 30.
- Credential lease: not applicable. Search v2 is a public catalogue read; the query text is typed input, not account data (unlike W2's id set), and `SearchStore` is not account-scoped. The import half adds no client request (the trigger runs inside the existing staging RPC).
- [ ] **Step 1: failing test** `scripts/load/profiles/search-with-hidden-adult-count.test.js`:
```js
test("search-with-hidden-adult-count is a Search-class first page on v2 at 1 rps", () => {
  const before = JSON.stringify(W.WEIGHTS);
  const p = W.loadProfiles()["search-with-hidden-adult-count"];
  assert.equal(p.budgetClass, "search"); assert.equal(p.ratePerSecond, 1); assert.ok(!("weight" in p));
  assert.equal(W.selectProfiles({ names: ["search-with-hidden-adult-count"] }).limits["search-with-hidden-adult-count"], 750);
  assert.equal(W.loadWorkload("tracker-gaps-combined").profiles["search-with-hidden-adult-count"], 1);
  const core = { requestFor: W.requestFor, validateResponse: W.validateResponse, ORIGIN: W.ORIGIN, now: () => new Date(0) };
  const r = p.request({}, { media: { anime: [1], manga: [1] } }, 1, Math.random, core);
  assert.match(r.path, /\/rest\/v1\/rpc\/search_(anime|manga)_page_v2$/);
  assert.equal(r.body.p_cursor_id, undefined);
  assert.ok(p.validate({ items: [{ id: 1 }], hidden_adult: 0 }, {}, r, { mode: "qualify" }));
  assert.ok(p.validate({ items: [], hidden_adult: null }, {}, r, { mode: "wiring" }));
  assert.ok(!p.validate([{ id: 1 }], {}, r, { mode: "wiring" }));
  for (const e of p.emptyExamples) assert.ok(!p.validate(e, {}, r, { mode: "qualify" }));
  assert.equal(JSON.stringify(W.WEIGHTS), before); assert.ok(!("search-with-hidden-adult-count" in W.WEIGHTS));
});
```
- [ ] **Step 2:** `node --test scripts/load/profiles/search-with-hidden-adult-count.test.js` → FAIL (profile undefined: `Cannot read properties of undefined (reading 'budgetClass')`).
- [ ] **Step 3:** implement the profile file (it never `require`s `backend_workload.js`) and add its line to `tracker-gaps-combined.js`.
- [ ] **Step 4:** `bash scripts/quality-gates/test_load_profiles.sh` → PASS (incl. `combined workload names every profile with an explicit rate`).
- [ ] **Step 5:** `git add scripts/load/profiles/search-with-hidden-adult-count.js scripts/load/profiles/search-with-hidden-adult-count.test.js scripts/load/workloads/tracker-gaps-combined.js && git commit -m "W4: search-with-hidden-adult-count load profile"`

### Task 7: Docs, full verification, evidence

**Files:** create `docs/tracker-gaps-2026-11/W4-adult-notice/EVIDENCE.md`; modify `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, memory `MEMORY.md`.
- [ ] **Step 1:** Rule 1 docs: v2 contract, adult definition, flag `search_adult_notice_v1` (0 %), import code `ADULT_NOT_LISTED`, unresolved file columns, prepared migration not applied, Change Log. Rule 2 memory: new files and counts, gotchas (never add an `ImportDisposition` value; v1 search must stay byte-identical; trigger `when` scope; W5 anon allowlist must list the two v2 functions). Update the inventory sentences `check_docs_current_state.py` checks.
- [ ] **Step 2: gates.**
  - `scripts/db/run_local_db_tests.sh` → 105, 97 and 102 PASS; no new failures.
  - `scripts/db/run_local_db_tests.sh --exclude-pending` → 105 FAILS at its first v2 assertion (red half of the evidence).
  - `cd Packages/KuroModules && swift test` → pass.
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → green; `check_migrations.sh` → pass (prepared file is outside the checksum set).
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → pass; warnings ≤ 60 unique Kuro-side.
  - `check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh` → 0 offenders; `check_bdd_traceability.sh` → the 5 W4 scenarios resolve.
  - `bash scripts/quality-gates/test_load_profiles.sh` → pass.
  - `python3 scripts/quality-gates/check_docs_current_state.py` → `PASS` after Step 1 updated the inventory sentences (app Swift +2: `SearchAdultNotice`, `ImportUnresolvedFile`; KuroTests +1; numbers taken from the script's expected text at merge time).
  - Append `W4-adult-notice.feature` to `scripts/quality-gates/bdd_landed.txt` (F1 landed scope); `check_bdd_traceability.sh` → exit 0.
- [ ] **Step 3:** `EVIDENCE.md`: red/green excerpts, the 105 EXPLAIN plan, Task 0 numbers, migration SHA-256 for the owner approval, open items.
- [ ] **Step 4:** `git add docs/tracker-gaps-2026-11/W4-adult-notice CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md scripts/quality-gates/bdd_landed.txt && git commit -m "W4: docs and evidence"` (memory is outside the repo; update, do not stage).
- [ ] **Step 5: acceptance record (F1.3; resolved ≠ accepted).** After Step 4's commit, re-run the Step 2 commands on that clean commit with logs saved under `docs/tracker-gaps-2026-11/acceptance/logs/W4-<run id>.txt`; start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template W4` and write `docs/tracker-gaps-2026-11/acceptance/W4.json` in F1.3's schema (workstream `W4`, spec §4), one entry per scenario (5). The `@sql:rls/105_search_hidden_adult_count.sql` entry counts only from the `run_local_db_tests.sh` log line `PASS  105_search_hidden_adult_count.sql … 0 blocked markers …`; the `@load:search-with-hidden-adult-count` entry stays `blocked` until an owner-approved `--qualify` run passes; `unresolvedGates` names it and the migration approval. Run `check_bdd_traceability.sh --accepted W4` → expected `exit=1` until then; record the output. Commit only `docs/tracker-gaps-2026-11/acceptance/W4.json` and `acceptance/logs/` (F1.3 rule 2), message `W4: acceptance record`.

## Owner / lead questions
- O1: Task 0 numbers decide whether the import half can fire at all.
- O2: Hentai-genre titles count as 18+ (they are already hidden by v1); Ecchi-only titles stay hidden without a notice.
- O3: The spec's "unresolved download" does not exist today; this plan adds a minimal shareable CSV in the import review (scope finding).
- O4 (resolved at plan review): W5's allowlist (migration, test 106, `GuestReadAllowlist`) now lists `search_anime_page_v2` and `search_manga_page_v2` as rows 18–19 (19 entries).
- O5: The legacy `apply_import_chunk_v1` path still writes adult matches into lists; it runs only with `series_foundation_v1` off (100 % on). Left unchanged.
