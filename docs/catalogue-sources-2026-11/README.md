# Catalogue sources: evidence folder (2026-11)

Evidence for `docs/superpowers/plans/2026-11-09-catalogue-sources.md`.

- `sources/` records each source's published terms as read on a dated visit (`sources/ann.md`).
- `runs/` holds comparator reports. One run is two files: `<run-id>.json` (the raw report plus the gate evaluation) and `<run-id>.md` (the gate summary and disagreement samples).

## The comparator

`catalogue_shadow_report_v1(p_medium text, p_sample int default 20)` is a service-only RPC (prepared in `supabase/prepared-migrations/20261112100100_catalogue_shadow_report_v1.sql`, DB test `supabase/tests/rls/121_catalogue_shadow_report_v1.sql`). It reads `catalogue_shadow_values` (written by `catalogue-intake` `compose`) next to the published columns and returns, per field group and tier, `{total, covered, compared, agreed, disagree_sample[]}`, plus identity gate counts and the adult review numbers. It only reads.

- Tiers: `top1k`, `top5k` (popularity rank), `in_lists` (any user-list row), `curated` (`curated_rail_items`), `all`.
- Groups measured: `identity`, `titles`, `titles_native`, `facts_start_year`, `facts_format`, `facts_status`, `facts_episodes` (FINISHED anime), `adult`.
- Not measured yet: relations, popularity, tags, episodes (airing), synopsis, images. The script lists them as `insufficient`, never `pass`.
- A tier with fewer than 30 compared rows is `insufficient`, never `pass`. Two gates fail on any miss regardless of sample size: duplicate accepted links, and adult titles that would become non-adult.
- `identity` stays `insufficient` until the owner-reviewed 200-title precision sample exists; the report cannot decide it.

`scripts/catalogue_shadow_report.js` calls the RPC, evaluates every spec section 6 gate it can measure and writes the two files. Its database access is the injected `callRpc` function, so `scripts/catalogue_shadow_report.test.js` runs offline. The report decides nothing by itself: a green report is local-shadow evidence, not a cutover and not proof of hosted behaviour.

## Run id rule

- A run id is `<UTC date>-<medium>`, for example `2026-11-18-anime`. The file name without extension is the run id.
- A second run on the same day takes a suffix: `2026-11-18-anime-2`.
- The script never overwrites: if `<run-id>.json` or `<run-id>.md` exists, it stops with an error and writes nothing.
- Reports are evidence. Do not edit them. A correction is a new run.
- Each run is recorded in the plan's evidence table with the run id and what it measured.

## Offline checks

```bash
# Node: gate evaluation, argument parsing, file output with a fake database
~/.nvm/versions/node/v24.22.0/bin/node --test scripts/catalogue_shadow_report.test.js

# SQL: report counts per tier, EXECUTE denied to anon/authenticated (local throwaway database)
LC_ALL=en_US.UTF-8 KURO_DB_PORT=54347 bash scripts/db/run_local_db_tests.sh --only 120_catalogue,121_catalogue
# red proof: the same run without the new migration fails 121
LC_ALL=en_US.UTF-8 KURO_DB_PORT=54347 bash scripts/db/run_local_db_tests.sh --only 120_catalogue,121_catalogue --exclude-migration 20261112100100_catalogue_shadow_report_v1.sql
```

The DB fixture is not production. Its popularity ranks run 1..6, so the 1,000 and 5,000 rank boundaries are not exercised, and `curated_rail_items` is a test stand-in.

## Live run (lead, read-only, not part of the offline checks)

Preconditions that are hosted actions and need their own approval:
1. `20261112100000_catalogue_sources_v1.sql` and `20261112100100_catalogue_shadow_report_v1.sql` applied. Until the second is applied the RPC does not exist and the script fails with "function ... does not exist".
2. Shadow values exist (`catalogue-intake` handlers `wikidata`, `ann` / `mangaupdates`, then `compose` have run). On an empty shadow the report shows zero coverage and every gate is `insufficient`.

Command, one per medium, from the repository root. The service key comes from the environment only:

```bash
SUPABASE_SERVICE_ROLE_KEY=<service role key> \
  ~/.nvm/versions/node/v24.22.0/bin/node scripts/catalogue_shadow_report.js \
  --medium anime --out docs/catalogue-sources-2026-11/runs/<UTC date>-anime.json
SUPABASE_SERVICE_ROLE_KEY=<service role key> \
  ~/.nvm/versions/node/v24.22.0/bin/node scripts/catalogue_shadow_report.js \
  --medium manga --out docs/catalogue-sources-2026-11/runs/<UTC date>-manga.json
```

The project URL comes from `project_public.env` (`SUPABASE_URL` overrides it). `--sample N` (0..100, default 20) caps the disagreement samples per group and tier. The script prints only the output paths and one status line per group.

## Popularity index (Task 10): shipped uncalibrated

`popularityIndex` = `round(views12m/12 * 0.02 + votes * 1 + libraryAdds * 50)`, capped to a Postgres integer; `trendingIndex` = `round(max(0, last30 - prev30) / 100)`; `scoreIndex` = vote-weighted blend of ANN `weighted` and MangaUpdates `bayesian` (each x10), null below 20 combined votes. Compose writes `popularity`, `trending` and `average_score` shadow fields with source `kuro_index` (not counted in `data_sources`). Inputs: the `pageviews` source record, ANN/MangaUpdates vote counts and per-title list-add counts (only the title id of list rows is read).

Calibration (plan Task 10 Step 4) was NOT done: comparing against AniList `popularity` needs gate L4(c), which is not granted. The coefficients above are the plan's starting values. The owner's Discover top-100 review decides whether they change.
