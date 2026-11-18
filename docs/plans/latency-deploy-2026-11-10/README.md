# Backend latency plan — production deployment, 2026-11-10

Owner approval: "do it all" (2026-11-10), after the report on [the plan](../2026-11-09-backend-latency-plan.md).
Project `bkdifromsqxkndnllmdj`. All SQL ran through the Management API; every migration was applied in
one transaction with its exact file text recorded in `supabase_migrations.schema_migrations` in the
same transaction (md5 of `statements[1]` checked afterwards). No blanket push, no history repair.

## What is live

| Step | Version / artifact | Applied (UTC) | Live check |
| --- | --- | --- | --- |
| 1b | `20261109200100_search_titles_topn_v1` | 09:40:41 | 24/24 row+score parity with the old body; grants kept. **Regression found by timing** (below) |
| 1b fix | `20261110100000_search_titles_param_v1` | 09:53:45 | 24/24 parity; plpgsql, `normalize_title` once, `RETURN QUERY EXECUTE … USING` |
| 1a | `20261109200000_search_staged_v1` | 09:42:57 | 40/40 Search pages (page 1 and the page after) byte-identical before vs after; threshold 0.35 kept; ACL unchanged |
| 1d | `concierge-parse` v51, `concierge-recommend` v57 (were v50 / v56) | ~09:47 | `verify_jwt` true; deployed from isolated eight-file closures (only `handler.ts`/`index.ts` differ from v50/v56, hashes in `edge-closures.json`); parse warmup 200, recommend answers 405/401 from the handler |

The three applied files are promoted byte-identically to `supabase/migrations/` with checksums.

## Not deployed

**1c (Newly added from base tables, drop of the two snapshot matviews).** The apply call was stopped by
this session's permission layer before it reached the database: `20261109200200` is **not** in live
history and both matviews still exist. It stays in `supabase/prepared-migrations/` and
`pending_migrations.txt`.

Correction found in preflight: `mv_anime_newly_added` / `mv_manga_newly_added` **do** grant SELECT to
`anon` and `authenticated` (`pg_class.relacl`; the earlier "no grant" check used a view that does not
list materialized views). App builds before the 2026-10-31 architecture read them directly
(`SupabaseService.fetchNewlyAdded*`). TestFlight 20–25 do not. Dropping them removes the newly-added
list from any older TestFlight build still installed. The 1c header now says this.

## Production timings

`timing-before.json` / `timing-after*.json` compare across time and are noisy (the same unchanged call
varied by up to ±30 % within the hour). The decisive numbers are the **interleaved A/B**: the
pre-deploy definition installed as a session-temporary function and the live function, alternated per
repetition, EXPLAIN ANALYZE execution time, medians (`ab-interleaved.json`, `ab-interleaved-2.json`).

Search (1a), old → new:
- anime: monster 129.7 → 18.0 ms (−86 %), dandadan 85.2 → 57.5 (−33 %), naruto 71.2 → 50.8 (−29 %),
  chainsaw man 54.6 → 45.3 (−17 %), frieren 38.5 → 34.5 (−10 %); one piece, berserk, vinland saga,
  spy x family within ±3 %; no match (xyzzyq) 16.3 → 18.0 (+11 %).
- manga: monster 225.5 → 38.4 (−83 %), dandadan 204.6 → 132.2 (−35 %), chainsaw man 138.7 → 105.5
  (−24 %), frieren 93.3 → 72.2 (−23 %), one piece 91.4 → 76.5 (−16 %), vinland saga −8 %, spy x family
  −3 %; no match 35.8 → 39.0 (+9 %); berserk +31 % in the first run, +1 % in the second (noisy).

`search_titles` (1b):
- The local finding did **not** hold in production: the old InitPlan body already used the trigram
  index live (~18–21 ms for 'naruto'); the fixture's full scan was a fixture-statistics effect.
- `20261109200100` made it slower live (~21 → ~32 ms 'naruto', ~20 → ~26 'attack on titan'): a
  non-inlined SQL function is planned with an unknown parameter, so `normalize_title(p_query)` was
  recomputed for each of ~1,100 rechecked rows. Live for ~13 minutes.
- Fixed forward by `20261110100000`. A/B now: naruto 18.3 vs 18.6 ms, attack on titan 18.1 vs 17.3,
  no match 5.2 vs 5.8. **Net: no speed change**; what remains is the deterministic tie order.

Newly added rail (1c, not applied): the base-table query costs 0.37–0.46 ms vs 0.28–0.30 ms from the
snapshot, so 1c is a freshness change, not a speed change.

Concierge (1d): not timed (needs signed-in calls); the change only stops awaiting log/cache writes.

## Files here

`preflight.json`, `before-function-definitions.json`, `before-newly-added-matviews.json` (rollback
material), `applied-*.json`, `verify-1a*.json`, `verify-1b-fix.json`, `pre/post-1a-search-outputs.json`,
`pre-1c-bundle.json`, `search-titles-candidates.json`, `edge-closures.json`, `edge-deployed.json`,
`edge-smoke.json`, timing and A/B files.

## Rollback (not needed so far)

- 1a: a new migration recreating `search_anime_page` / `search_manga_page` from
  `before-function-definitions.json` (needs `select extensions.similarity('a','b')` in the same session
  because of the per-function `pg_trgm` setting).
- 1b: same, for `search_titles`.
- 1d: redeploy v50 / v56 sources (git HEAD files, hashes in `docs/backend-cold-2026-11-09/deployment-manifest.json`).
