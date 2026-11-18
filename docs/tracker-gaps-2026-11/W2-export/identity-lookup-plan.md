# W2 export: identity lookup query plan

Check: `supabase/tests/rls/110_export_identity_lookup_plan.sql`, run 2026-11-18 with
`LC_ALL=en_US.UTF-8 KURO_DB_PORT=54345 bash scripts/db/run_local_db_tests.sh --only 110_export`
-> `PASS 110_export_identity_lookup_plan.sql 10 assertions, 0 blocked markers, 0 findings`.

Query (what `CatalogStore+ExportIdentities` sends per batch, 500 ids at most):
`select id,anilist_id,mal_id,title_english,title_romaji,title_native from public.<medium> where id = any(<500 ids>)`.

Fixture: disposable local PostgreSQL 17 (audited schema fixture, not Supabase, not PostgREST), 22,000
generated rows per medium (ids 9100001..9122000), `analyze`d. Plans are `EXPLAIN (ANALYZE, FORMAT JSON)`
without buffers; timings are from a laptop fixture and are NOT a latency claim (the load profile
`export-mal-id-lookup` is the latency evidence, and no qualification run exists yet).

| medium | role | top node | index | rows (plan / actual) | execution ms |
|---|---|---|---|---|---|
| anime | anon | Index Scan | anime_pkey | 500 / 500 | 0.125 |
| anime | authenticated | Index Scan | anime_pkey | 500 / 500 | 0.068 |
| manga | anon | Index Scan | manga_pkey | 500 / 500 | 0.102 |
| manga | authenticated | Index Scan | manga_pkey | 500 / 500 | 0.062 |
| anime | authenticated, primary key dropped (negative control) | Seq Scan | none | 500 / 500 | 2.374 |
| manga | authenticated, primary key dropped (negative control) | Seq Scan | none | 500 / 500 | 2.046 |

Assertions: each indexed plan names `<medium>_pkey` and contains no `Seq Scan`; each returns 500 rows;
without the primary key the plan no longer names it (so the positive check can fail). The full JSON
plans are raised as `NOTICE PLAN ...` lines in the runner's per-test log (`--report-dir`).

Limits: the fixture catalogue has no RLS policy differences from production that this test checks; the
production table sizes, statistics and PostgREST's own query shape (it wraps the select in a JSON
aggregate) are not reproduced here. W2 changes no SQL and no migration.
