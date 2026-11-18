# Backend latency plan — 2026-11-09

Status (2026-11-10): **1a, 1b (+ fix-forward 20261110100000) and 1d are live** after owner approval
("do it all"); **1c is not applied** (stopped by the session permission layer). Deployment receipt and
production A/B timings: [latency-deploy-2026-11-10/README.md](latency-deploy-2026-11-10/README.md).

Owner decisions (2026-11-09): the "Newly added" rail may become fresher (base tables instead of a
daily snapshot); three read-only production checks were approved and run (below).

## Read-only production evidence (Management API, `read_only: true`, 2026-11-09)

| Check | Result |
| --- | --- |
| `cron.job` | job 114 `kuro-refresh-matviews` `30 1 * * *` runs `select public.refresh_discover_matviews_v1();` (active); job 115 runs `media_similar_nightly_v1()` |
| `public.user_lists` | view with `reloptions = {security_invoker=on}`: the F40 leak is closed live (the prepared file header saying "not applied" is stale) |
| public matviews | the six Discover matviews plus `media_realm_membership`, `media_tag_vectors`, `realm_affinity` |
| Search config | `search_anime_page` / `search_manga_page`: `search_path=public, extensions`, `jit=off`, `pg_trgm.similarity_threshold=0.35`; `search_titles`: invoker, `search_path=public, extensions` |
| `anime.created_at`, `manga.created_at` | **NOT NULL** on both; 0 null rows in anime |
| Newly-added matviews | no `anon`/`authenticated` grants |
| Sizes | anime 21,867 · manga 41,902 · title_search 72,560 |
| Existing indexes | `idx_{anime,manga}_created_at (created_at DESC)` and `idx_{anime,manga}_load_created_v1 (created_at DESC NULLS LAST, id DESC)` |
| `discover_bundle(integer,integer)` | definer, `search_path`, `jit=off`; live body md5 `7087aac736713c45d6916182abb1fbbb` (captured in the step 1c work, compared against the repo body before replacing) |

A further read-only timing pass over the live Search RPCs was not run (the session's permission
layer stopped it); latency claims below therefore come from the disposable local fixture, whose
row counts (22k anime / 42k manga) match production.

## Steps

### 1a — Staged Search (`search_anime_page`, `search_manga_page`)
- Strong stage (exact 600, prefix 500, word 450, contains 400, full-text 320) runs first. The fuzzy
  stage (trigram, rank exactly 250) runs only when the strong stage returns fewer rows than the page
  size after the cursor, and keeps **only rows whose computed rank is 250**, so no row appears in both
  stages. Both stages use the identical rank expression and keyset `(rank, popularity, id)`.
- Blank query (every row rank 0, popularity order) stays a separate single path.
- Keep `pg_trgm.similarity_threshold = 0.35` (live since `20261109123758`); the test now requires 0.35.
- Tests: all existing differential cases; new page-boundary case (35 strong + 50 fuzzy, page 30:
  page 2 = last 5 strong then fuzzy only, no repeats, fixture self-checks its bucket counts); cursor
  that starts in the fuzzy region; filtered searches with a blank query; terms that exist per medium
  (Naruto for anime, Berserk for manga).

### 1b — `search_titles`
- Compare `title_norm % normalize_title(p_query)` directly (found during the work: the InitPlan
  `(select qn from q)` form forces a full scan of `title_search` on every call).
- Pick the top N candidates from `title_search` first, then join `anime`/`manga` only for those N.
- Deterministic tie-breaker after `score desc, popularity desc nulls last`: `ts.id`. Accepted as a
  small intended change (ties were unordered). The comparison test compares tie groups as sets and
  pins the new order separately.

### 1c — "Newly added" rail from base tables
- `discover_bundle` reads `public.anime` / `public.manga` for the two newly-added CTEs with the
  same filters. Because `created_at` is NOT NULL, `order by created_at desc nulls last, id desc`
  returns exactly the rows of `created_at desc, id desc` and is served by the existing
  `idx_*_load_created_v1`; **no new index**. The test asserts the NOT NULL precondition and the plan.
  (This replaces the earlier "new partial index" idea, whose reason — missing dates — cannot occur.)
- Drop `mv_anime_newly_added` / `mv_manga_newly_added` behind a guard that refuses if any other
  function body still names them; redefine `refresh_discover_matviews_v1()` with the four remaining
  matviews; update `99_perf_hotpaths.sql` 6 → 4.
- Replace `discover_bundle` from the live body (only the two CTEs change); the comparison test
  covers the whole bundle output.

### 1d — Concierge best-effort writes off the critical path
- `concierge-recommend`: `saveModeCache` and `logRecommendRun`; `concierge-parse`:
  `logParseFeedback` and `logRun`. All are already best-effort.
- `waitUntil` is an optional injected function (wired to `EdgeRuntime.waitUntil` in `index.ts` when
  present); without it the handler awaits as before. Deferred writes run in order on one chain, so the
  later mode-cache write can never be overtaken by the earlier one.
- Tests use `queryFake` (`rpcCalls`, `reads`) plus a `waitUntil` spy. Base: deployed Recommend v56 /
  Parse v50 source.

### 1e — `user_lists` anti-joins (evidence-gated)
- EXPLAIN `recommend_ids_premium` and `curated_rail_cards` on a local 2,000-title library. Switch
  to the base tables only if the view's share of the cost is significant. No security reason remains
  (invoker is live).

## Verification
Local only: `scripts/db/run_local_db_tests.sh --only <file>` for 99/102/new search and bundle tests;
`deno test` in both Concierge folders. No hosted writes, deployments or load tests.

## Outcome (2026-11-09, local only — nothing applied or deployed)

| Step | Artifact | Local evidence |
| --- | --- | --- |
| 1a | `supabase/prepared-migrations/20261109200000_search_staged_v1.sql`; test `105_search_staged.sql`; `102` updated (threshold 0.35 required, plan read from `$fuzzy$`) | 105: 8 assertions over 83 checks (page boundary, every filter flag non-empty, limits null/0/−5/1/34/36/51/200, null cursor parts, wildcards, short queries); 102: 74 differential cases still identical. Red without the migration. |
| 1b | `…20261109200100_search_titles_topn_v1.sql`; test `106_search_titles_topn.sql` | 106: 10 assertions over 180 checks (set/score parity with the old body, exact order vs an independent reference, tie-breaker, scan counters). Red without the migration. |
| 1c | `…20261109200200_discover_newly_added_base_v1.sql`; fixture `104_discover_bundle_baseline.sql`; test `104_discover_newly_added_base.sql`; `99` 6 → 4 | 104: 15 assertions (whole bundle identical to the old body right after a refresh, with every rail populated; fresh title appears at once; existing index, no Sort). Drop guard also checks `cron.job`. Red without the migration. |
| 1d | `concierge-recommend/{handler,index}.ts`, `concierge-parse/{handler,index}.ts` + tests | 30 / 20 Deno tests pass; the new tests deadlock against the HEAD handlers (red). |
| 1e | none (gate not met) | 2,000-title library over 22k anime: the view anti-join costs 3.46 ms vs 2.76 ms on the base table (InitPlan form) and 3.13 vs 3.15 ms (`auth.uid()` form); the manga branch is pruned and `idx_anime_user_lists_user_id` is used. Not significant: no change. |

Full local DB suite: 46 files, 1,391 assertions pass; exit 4 only for the two documented
pre-existing BLOCKED scopes. `check_migrations.sh` exits 0 (its one warning is the earlier staged
cold-read file).

Local timings (disposable fixture, 22k anime / 42k manga / 72k title variants, warm, avg of 15):
- 1a: when the strong matches fill a page — `naruto` 12.1 → 7.9 ms, `one piece` 15.2 → 11.0,
  `fate/stay` 15.3 → 10.1, manga `berserk` 19.6 → 13.7. Otherwise (few or no strong matches) the
  fuzzy stage still runs: +0.3 to +1.2 ms (`frieren` 12.1 → 12.8, `xyzzyq` 10.1 → 10.6). Common
  words stay slow in both (`story` ~145–165 ms): staging does not address them.
- 1b: the old body's InitPlan (`(select qn from q)`) hides the query value from the planner, which
  then scans all of `title_search` on every call. Direct `normalize_title(p_query)`: `naruto`
  58 → 3.6 ms, `attack on titan` 82 → 6, no match 57 → 1.7. Trade-off: queries whose trigrams
  match most rows (synthetic `story`, 57k rows) 100 → 125 ms.
- Production timing was not measured (the session's permission layer stopped the read-only
  timing pass); these numbers are fixture evidence only.

Independent read-only review (separate reviewer, no shell): no correctness defects found in the
four changes. Acted on: drop guard now also checks cron commands; vacuous test cases fixed (105
filters now non-empty, edge parameters added; 106 exact order pinned; 104 every rail populated;
manga plan bound to a limited page); the Edge "rejecting write" tests relabelled — the repository
already swallows errors, so the chain's own catch is defensive and not directly exercised.
Old app builds that read `mv_*_newly_added` through PostgREST: **corrected 2026-11-10** — both
matviews do grant SELECT to anon/authenticated (`pg_class.relacl`; the earlier check used a view that
omits materialized views). Builds before the 2026-10-31 architecture read them; TestFlight 20–25 do
not. The drop would remove the newly-added list from an older TestFlight build still installed.
Without `waitUntil` (local runs only) parse feedback writes are now serial instead of parallel.

Deployment order if approved: 1b and 1c are independent; 1a after 20261109123758 (already live).
Each needs its own approval; 1c is the only one with a visible change (fresher rail).

## Deployment outcome (2026-11-10)

- 1b's local premise did not hold in production: the old body already used the trigram index live.
  `20261109200100` was slower live (~21 → ~32 ms) because the SQL function recomputed
  `normalize_title` per rechecked row; fixed forward 13 minutes later by
  `20261110100000_search_titles_param_v1.sql` (PL/pgSQL, `RETURN QUERY EXECUTE … USING`). Net live
  effect: unchanged speed, deterministic tie order.
- 1a is a net win live (interleaved A/B): common words −83 to −86 % (`monster`), many title searches
  −10 to −35 %, others ±3 %, no-match searches +9 to +11 % (a few ms).
- 1d: Concierge parse v51 / recommend v57.
- 1c: still prepared; its header and this plan now state the corrected old-build impact.

## 1c parked (2026-11-18)

Not applied. Since 2026-11-10 the AniList import jobs are off (owner decision), so no new titles
arrive and the nightly snapshot already equals the base tables: 1c would add nothing today, and its
matview drop would remove the newly-added list from pre-build-20 TestFlight installs. Two parts:
- fresher rail: revisit when catalogue Task 15c inserts new titles; regenerate from the live
  `discover_bundle` first;
- dropping `mv_{anime,manga}_newly_added`: done inside catalogue Task 15d (which rebuilds the six
  matviews and already waits for old builds to be retired).
