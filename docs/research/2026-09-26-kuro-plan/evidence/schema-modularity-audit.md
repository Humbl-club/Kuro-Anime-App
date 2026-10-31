# Kuro: SQL, schema and modularity audit

Read-only review, 26 September 2026. Repository: `/Users/max/Kuro-Anime-App`. No repository edits, migrations, hosted RPC executions, EXPLAIN ANALYZE, configuration changes or deployments were performed by this agent. Root collected the hosted metadata and historical statistics cited below.

## Coverage and confidence

Scanned all 235 migration SQL files in filename order, indexed 140 latest function names, and mapped 49 literal RPC names called by the Swift app. `evidence/rpc-review-register.csv` records the callers and candidate latest definitions, plus supplementary SQL dependencies. This is a function-name index, not a complete SQL parser: overloaded signatures, guarded baseline captures, dynamic invocation and dependency ordering still require explicit review. Major hot paths were manually read. Earlier superseded implementations are not presented as current.

Compared the bodies of **16 current hosted functions** from `evidence/live-serving-functions.json` and `live-functions.json` against the latest local definitions after removing SQL comments and normalizing whitespace. **All 16 bodies match**: search_anime_page, search_manga_page, browse_anime_page, browse_manga_page, discover_bundle, fetch_club_bundle, fetch_club_bundle_loading, fetch_friend_activity_for_title, fetch_my_clubs_enriched, fetch_my_clubs_loading, collection_anime_page, collection_manga_page, collection_feed_page, count_friends_tracking, rebuild_media_realm_tier, rebuild_media_similar_titles. This is body parity for the sample, not proof of matching grants, owners, RLS, relation kinds, indexes, every function, or clean migration replay.

The largest measured cost is scheduled recommendation maintenance. The most credible interactive SQL concern from inspection is Search candidate generation/index alignment. Existing collection keyset paging, precomputed similarity, rail batching and typed anime/manga models are worth preserving.

## 1. Prioritize scheduled maintenance before adding more recommendation work

**High confidence; measured historical operational cost, current definition confirmed.** Root's `live-cron.json`, observed 2026-09-25 22:16:55 UTC, records the active five-minute similarity driver (job87): 287 successful runs in the preceding 24 hours, mean25.89s, max442.59s. Realm-tier refresh (job51) ran once in133.57s. These are cron execution durations, not user-request latency or current p95. The wider statistics window supplied by root (Aug4–Sep25 UTC) reports 15,060 similarity-rebuild calls averaging25,543ms and 871,431,881 temporary blocks written; separate counters should not be converted into a realtime throughput claim.

Current `rebuild_media_similar_titles` has an advisory transaction lock at extracted live SQL lines14–15, so it already guards overlapping work. It seeds missing state, then builds global recursive franchise components (lines73–105), synchronizes component/entry-point tables and evaluates entry-point windows (lines123–159), **before** selecting a bounded stale-seed batch and returning when it is empty (lines168–177). This matches `supabase/migrations/20260807010000_leftover_repairs_v1.sql`. The source explicitly says this ordering keeps franchise identity fresh even after recommendations converge. A simple early return would lose that behavior.

**Decision:** separate franchise/component freshness from similarity batch work, or gate that refresh on a reliable relation/cut-data revision. Preserve the precomputed recommendation store, advisory guard, editorial cut edges and newcomer entry points. Inspect the global recursive graph's actual cardinality/temp spill before tuning memory or adding hardware. Do not run full rebuilds from request handlers. Keep the daily realm tier rebuild under review; it is expensive but much less frequent.

**Acceptance:** empty stale queue plus unchanged relation revision takes a demonstrably cheap path; changed relations/editorial cuts update components within an explicit freshness SLA even with no stale seeds; mixed anime/manga identities and removed/cut edges stay correct; concurrent drivers cannot duplicate work; representative full backlog completes within budget without starving serving queries. Compare equal-duration before/after database CPU, temporary writes, run duration, stale backlog and foreground latency. Set a target after obtaining a controlled baseline rather than claiming the historical mean predicts it.

## 2. Restore a reproducible schema contract before expanding it

**Confirmed source-chain problem, separate from the matching function bodies.** `supabase/migrations/README_baseline_capture.md:28–77` documents that the late baseline does not make the full chain replayable. Early migrations create indexes or alter tables before those objects are captured by `20260807000000_baseline_capture_v1.sql`; lines58–72 list examples. The four hollowed February15 migrations contain only `;` (README38–41). Standalone baseline tests recorded at81–96 do not prove whole-chain replay.

The same README42–45 says `media_realm_tier` is a materialized view in the chain but a plain table in production. Root's current relation catalog confirms relkind `r`, roughly56,959 estimated rows,6.7MB and no primary key advisory. Do not assume this advisory is a nonexistent-matview false positive. Determine its intended natural uniqueness and duplicate state before proposing a key.

A further dependency is **`user_lists`**: its CREATE VIEW exists in `legacy_sql/08_create_user_lists_view.sql:6`, while migrations only ALTER it to security_invoker (`20260206150000_security_hardening_rls_and_views.sql:40`; `20260206164200_security_hardening_rls_and_views.sql:14`). No CREATE for this view was found in the235-file chain. Many RPCs use it. The legacy view's null/constant projection is not sufficient evidence of the live view definition; root should capture `pg_get_viewdef`.

**Decision:** establish one explicit supported fresh-bootstrap path plus an upgrade path, reconcile table-versus-matview kind and missing view dependencies, and compare actual grants/RLS/indexes as well as function text. Preserve applied migration history; do not casually rewrite already-applied files or move the baseline and assume that fixes all intermediate compatibility.

**Acceptance:** an isolated Supabase-shaped database reaches the expected schema from the documented path with ON_ERROR_STOP; repeated application is safe where designed; representative upgrade from the existing schema succeeds; no missing relations/functions, policy/grant differences or relation-kind ambiguity; unified list projection preserves both media's progress and privacy semantics. No production reset is required.

## 3. Make Search use a deliberate indexed candidate path

**Current hosted body confirmed; plan/performance hypothesis remains unmeasured.** Latest search_anime_page and search_manga_page are in `20260326234000_exclude_ancillary_anime_from_default_surfaces.sql:14,227`. They normalize each title and a `lower(trim(concat_ws(...nullif...)))` title blob, rank exact/prefix/word/substring/full-text/fuzzy matches, and apply numerous OR alternatives. Fuzzy filtering computes greatest(similarity(...)) >=0.35. LIMIT50 bounds returned rows, not candidate work.

Existing trgm expression indexes (`20260203235500_search_rpc_keyset.sql:8,10`) use lower(coalesce(title_english,'') || ' ' || coalesce(title_romaji,'') || ' ' || coalesce(title_native,'')), a structurally different expression. Existing full-text GIN indexes (`20260203223000_scale_perf_bundle_and_indexes.sql:25,33`) include English/romaji/description_normalized, unlike the new title blob/native-title expression. These cannot be assumed to service the new expressions directly. A CTE itself does not prove materialization or a full scan; inspect actual plans.

**Decision:** use one canonical normalized title/search projection and a bounded index-supported candidate stage, then preserve current ranking and filtering over those candidates. Prefer reusing the established title_search machinery if it can meet user-search semantics, or align an explicit stored/indexable projection. Do not simply add another GIN index to every column. The Concierge `search_titles` path is distinct: `20260209000000_search_titles_add_cover_image.sql:5` uses `title_search.title_norm % normalize_title(query)` with its matching GIN trgm index (`20260203171100_concierge_core.sql:64`), so it is not evidence of the same mismatch.

**Acceptance:** exact, native-script, prefix, one/two/three-character, >=5-character typo and empty queries retain ordering/safety/filter behavior; first and deep cursor pages have stable tie breaks; real plans show the desired candidate bound/index access; query work and p95/p99 remain inside an agreed budget under concurrent typing and cancellation. Verify user-visible recall against a fixed corpus before replacing ranking.

## 4. Preserve good pagination; benchmark conditional Browse plans

Collection anime/manga RPCs (`20260204010500_collection_paging_rpc.sql:10,84`) filter user_id by auth.uid()::text and use `(updated_at,id)` descending keysets. Matching `(user_id,updated_at DESC,id DESC)` indexes are in the same file:5,7. Mixed collection feed (`20260204133000_collection_feed_paging_rpc.sql:6`) UNION ALLs the two owner-scoped branches and orders by updated_at descending, source_rank ascending, row ID descending. Limits are capped120. These are sound foundations; switching to OFFSET would discard useful work.

Browse RPCs (`20260326234000...:443,569`) also use keysets and capped limits. Conditional CASE sorts, COALESCE metrics and combined genre/status/year/format filters merit real-plan checks against the existing plain btree and genre GIN indexes. Do not infer those indexes are useless solely from source shape.

**Acceptance:** large accounts and deep pages; equal timestamps/metric scores; anime and manga with the same numeric ID; null metric values; status changes between pages; stable cursors without gaps/duplicates within the defined consistency model. For Browse, compare each supported sort and common filter combination before adding indexes.

## 5. Bound social aggregation and preserve privacy semantics

Current count_friends_tracking (`20260731040000_clubs_trust_pack_v1.sql:229`; hosted body matches) calculates effective sharing from shared nonarchived clubs. Its list join casts stored TEXT `ul.user_id::uuid` (local line282), although user-list indexes start with TEXT user_id. Cast the bounded UUID friend side to TEXT when equivalent instead of forcing every candidate list column through a UUID cast; verify plans and legacy data first. A malformed legacy ID can otherwise fail the batch cast. This is not a reason for an immediate broad user-ID migration.

The RPC parses a JSON item list without an explicit server item cap. `SupabaseService+Social.swift:94–119` sends all received items in one request; cancellation and stable media-type/id cache keys already exist, but there is no chunk in that method.

Club list loading (`20260318104000_club_loading_rpcs.sql:7`) performs correlated member/rail/poll/activity summaries per club, with repeated latest-activity calculations. Max20 members per club is not a cap on a user's club count or retained history. Bundle-loading starts at132. Membership helpers and member indexes exist; do not claim absent authorization.

**Decision/acceptance:** bound and deduplicate friend-count input, align join types/index access, retain batched counts, and profile club summary queries across realistic club counts/history. Tests must cover private/status/progress visibility, mixed memberships granting different sharing, archived clubs, no shared club and malicious oversized input. Introduce maintained summary data only if measured aggregation cost warrants its consistency burden.

## 6. Keep recommendation limits meaningful and measure fallback amplification

- `curated_rail_cards` (`20260205231000_curated_rails.sql:64`) fetches a narrow rail with catalog joins and seen exclusion; this is preferable to regenerating every rail.
- `recommend_ids_premium` (`20260203201000_editorial_story_boosts.sql:32`) scores broad catalog candidates with tag boosts/penalties/focus aggregates before LIMIT50. The edge agent observed repeated fallback builds; reducing duplicate calls is likely more useful than shrinking the returned limit.
- `recommend_ids_similar_to_seeds` (`20260806020000_serving_hardening_v1.sql:134`) reads precomputed similarity, combines seeds and deduplicates/excludes franchises. Cold/no-precomputed seeds or special options can enter `_recommend_ids_similar_to_seeds_live` (`20260804130000_media_similar_titles_precompute.sql:830`), with broader candidate/vector/tag/realm work. Measure fallback frequency, coverage and freshness explicitly.
- Latest `fetch_taste_deck_batch` (`20260731150000_realm_graph_v1.sql:1402`) caps output2–40 and candidate pools per medium to max58, then performs vector/window/diversity/temporary-table work. Its `random()<0.10` negative probe is **not** `ORDER BY random()`. The latest-definition scan did not find an ORDER BY random() pattern in the indexed function bodies; old superseded functions must not be used to allege a current random full-catalog sort.
- `fetch_tonight_shelf` (`20260806010000_serving_fixes_v1.sql:85`) and `fetch_realm_hidden_gem` (`20260806020000_serving_hardening_v1.sql:369`) include franchise/window ranking before output limits. Returning one hidden gem does not imply evaluating one row. `_franchise_component_labels` is a SECURITY DEFINER accessor; check whether the planner can restrict its returned data in each use.
- `media_realm_membership_effective` (`20260805112000...:32`) is a security-invoker view merging base/delta/overrides through FULL OUTER JOIN and a materialized override CTE. Existing set-based materialization in expensive workers is intentional; do not replace it with per-row subqueries.
- `get_manga_chapter_enrich_candidates` (`20260221173000_manga_chapter_crunch_mode.sql:8`) aggregates chapter counts/mapping/review state before priority and LIMIT<=200. Inspect normal batch and forced-single-title plans separately; the single-title filter may or may not be pushed into each aggregate.

**Acceptance:** report requests and SQL calls per visible rail, duplicate-fallback rate, cold/warm seed behavior and recommendation quality. Bound parse fanout and rail concurrency at the caller. Measure temp DDL/spill under concurrent taste-deck requests. Preserve exclusion, safety and franchise correctness when reducing candidate work.

## 7. Refresh and RLS: targeted changes only

The baseline adds unique id indexes to seven catalog materialized views (`20260807000000_baseline_capture_v1.sql:2986–3003`), enabling concurrent refresh, but its recorded cron command at3019–3025 still refreshes seven serially without CONCURRENTLY. Root's current cron metadata confirms daily01:30 scheduling and one successful10.76s execution in the last24h, but does not by itself prove the exact current command or blocking duration. Confirm that command before proposing concurrent refresh; test readers during it and preserve freshness/failure visibility.

Base user-list RLS in the baseline already uses initplan-style `(SELECT auth.uid())::text` ownership predicates (anime2201, manga2369); do not blanket-rewrite it based on general advice. Existing view security_invoker changes matter. Definer RPCs need deliberate auth predicates, fixed search paths, intended grants and cross-user tests, not indiscriminate conversion. Root advisors'9 unindexed FKs,8 auth-initplan findings and105 unused-index findings are candidates for object-by-object review; low usage since a stats reset does not justify deleting105 indexes.

## 8. Modularity decisions for scope, shelves, profiles and clubs

SupabaseService is one @MainActor @Observable state owner, even though domain methods are split into extensions. Core file is2972lines, models1324, RPC parameters637. Core owns auth/bootstrap, catalogs/details/caches/inflight work, collection state and cross-domain DTOs; domain extensions add behavior but do not create independent lifecycle boundaries. Large line count alone is not a refactor mandate.

Preserve the current stack and established typed model split. `SupabaseModels.swift:3` already has MediaKind; MediaDisplayable at9 and stableKey at31 provide shared presentation/identity; Anime and Manga retain their different fields. UserList at547 normalizes progress while persisted anime/manga lists remain distinct. `SupabaseService+UserLists.swift:35` builds separate mutation payloads. Unknown manga totals and chapter/volume progress must not be forced into an anime episode model.

**Scope:** introduce a typed, persisted user preference with explicit propagation through request parameters, cache keys, cancellation/generation checks and loading/error state. Discover currently computes both media in one bundle (`20260326234000...:707`); taste deck also intentionally mixes both. If the new product contract is persistent anime-only/manga-only scope, filtering the visible cards after fetching both wastes work and can starve a rail. Decide which surfaces honor scope, where cross-media discovery is intentional and how fallback behaves. Keep preferences separate from inferred taste.

**Shelves:** represent user-defined ordered membership with typed media identity, independent of watching/reading status. Do not overload PLANNING/status values to represent shelves. Establish order, duplicates, pagination, ownership, visibility and deletion semantics; index owner/shelf/order and prove RLS before UI exposure.

**Profiles:** expose an explicit public projection and opt-in fields; do not loosen existing private profiles/list RLS globally. Notes, progress, history and inferred taste need deliberate visibility. Club display-name access via privileged RPC is not permission for public profile reads. Keep public pagination and cache keys separate from personal collection state.

**Clubs:** reuse existing membership and effective-sharing rules rather than creating a second friend graph for these features. Keep suggestion generation outside heavily repeated membership/summary reads.

**Bounded extraction:** when implementing each feature, move its state/cache policy behind a cohesive existing-pattern boundary while keeping the auth/client shared. Do not simultaneously replace all services or merge physical anime/manga catalog tables. Extend shared identity/projection/progress traits, retain domain-specific payload validation, and version RPC contracts when semantics change.

**Acceptance:** scope survives relaunch; two users switching accounts cannot see previous personal cache results; old in-flight responses cannot overwrite a new user/scope; mixed numeric media IDs never collide; shelves retain status independently; unknown chapter/volume totals remain unknown; public requests cannot infer private notes/list membership; membership changes invalidate affected club data. Root's client audit owns detailed lifecycle bug confirmation.

## Suggested implementation order

1. Capture reproducible schema contracts and define migration bootstrap/upgrade acceptance; concurrently investigate the measured five-minute maintenance cost.
2. Establish Search query/candidate contract and measure actual plans; fix duplicate recommendation fanout and instrument fallback coverage.
3. Tighten social batch limits/cast alignment and verify refresh/read behavior.
4. Implement persistent scope as a cross-layer contract, then shelves and explicit profile visibility with bounded state extraction.
5. Reassess indexes, club summaries and richer recommendation models against measured load. Do not use new product features to justify a wholesale rewrite.

Evidence limitations: no hosted workload was generated by this review; no p95/p99 distribution or load capacity was proven. The matching16 functions narrow deployment uncertainty but do not remove documented schema replay gaps. Historical counters and SQL-shape risks are labeled separately throughout.


## Root follow-up: current unified list projection

At 2026-09-25 22:28:17 UTC the live view definition was read directly; see `live-user-lists-view.json`. It unions both list tables, projects rating times ten as score, null volume progress/start/completion dates and constant false private. Those placeholders do not establish user history or activity consent; authorization is separate. This closes the live-definition gap, while fresh migration replay remains untested.
