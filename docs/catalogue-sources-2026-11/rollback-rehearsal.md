# Catalogue rollback rehearsal (Task 15 Step 5)

Input to spec section 6 "rollback rehearsed". Local only: the disposable PostgreSQL 17 fixture of
`scripts/db/run_local_db_tests.sh`, not production, not Supabase. Nothing was applied anywhere.

## What was rehearsed

`supabase/tests/rls/124_catalogue_publish_lists.sql`, section 10, on 2,000 anime rows:

1. every shadow row for the group (titles, facts, adult, credits and relations carry real values; each
   title has a 1-entry staff list and one accepted relation);
2. switch the group to `new`, run `catalogue_publish_batch_v1` in 4 batches of 500 titles (it snapshots, then
   replaces);
3. switch the group back to `anilist`, run `catalogue_restore_batch_v1` in batches of 500 until nothing remains;
4. assert: all 2,000 titles restored, columns equal their pre-switch values, no `source='kuro'` relation left, no
   snapshot left (these are the test's assertions; each group's "restored" count was 2,000).

Command: `LC_ALL=en_US.UTF-8 KURO_DB_PORT=54349 bash scripts/db/run_local_db_tests.sh --only 124_catalogue --report-dir <dir>`
(the durations are `RAISE NOTICE` lines in `<dir>/*124*.log`).

## Durations (one run, 2026-11-18, laptop fixture, 2,000 titles)

| Group | Publish (first, with snapshot) | Restore |
|---|---|---|
| titles | 401 ms | 381 ms |
| facts | 560 ms | 635 ms |
| adult | 65 ms | 208 ms |
| credits | 151 ms | 35 ms |
| relations | 138 ms | 38 ms |

The groups with no shadow values yet (popularity, tags, synopsis, episodes, links, images, identity) snapshot and
restore their columns the same way, and are not rehearsed with data because compose does not write shadow values
for them until Tasks 9 to 14. The restore function takes any group.

## Limits (do not read this as a production figure)

- The fixture has about 2,000 anime and an empty manga table; production has about 21,900 anime and 41,900 manga.
  Restore time scales with the number of snapshot rows: ≈ 0.2 to 0.3 ms per title here, so tens of seconds per group
  for the whole catalogue, in 500-title transactions. A production rehearsal needs a clone of the data and is not done.
- Plans, locks and concurrent traffic (the importers are skipping the group, but readers are running) are not exercised.
- The restore of `relations` removes only `source='kuro'` rows, so `anilist` and `editorial` rows are never touched.
- `media_relations` and `get_media_ladder` are not in the fixture; the test creates a stand-in table.
- A restore re-sets `data_sources` to the snapshot only for the group whose snapshot carried it (the first group of a
  publish run); another group still `new` re-publishes it on its next run.

The restore handler is `POST catalogue-intake { "handler": "restore", "group": "<group>" }`; it refuses a group that
is still `new`, makes no AniList request and records its duration in `import_runs` (run_type `catalogue_restore_<group>`).
