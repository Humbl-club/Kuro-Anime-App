# Kuro operational database and ingestion audit — 2026-09-26

## Scope and evidence boundary

Read-only source review of `scripts/` and `research/` executable JS/TS/Swift/Python/shell files, plus migration cron registration history. No worker, importer, healthcheck, SQL writer, installation, hosted query or deployment was executed. No credential files were opened. Source checkout remains unchanged.

Artifacts:
- `evidence/operational-call-register.csv`: 427 static records: 138 SDK table sites, 21 RPC sites, 10 typed REST client sites, 8 SDK auth/function sites, 64 HTTP/CLI transports, 112 selected helper invocations, and 74 historical cron schedule/unschedule declarations (38/36). This is **not 427 unique requests per session**: helpers and their transport sites are deliberately separate.
- `evidence/operational-coverage.json`: 87 executable files screened; 51 contain registered call sites. The remaining 36 include launch wrappers/installers, local-only dashboards, code generators, quality gates and a legacy UI reference. A wrapper may trigger a registered worker even if it has no direct DB transport call.
- Source targets derived statically; unresolved dynamic table/URL arguments remain explicitly marked. SQL bodies, deployed functions, iOS foreground request graphs and runtime traces belong to the parallel audits. No statement that every dynamic runtime path has been profiled is justified.

## Highest-priority findings

### OP01 — Empty media-relation queue still triggers 1,000 title RPCs and a full relation scan

`media_relations_worker.js:592–604` unconditionally runs `buildCoverageReport(REPORT_SAMPLE_SIZE)` after queue work, including when the queue is empty. Default sample size 500 is applied independently to anime and manga (`:349–365`), then each title invokes `get_media_ladder` with concurrency 8 (`:499–516`). It also obtains an exact count and reads the entire relation table in 1,000-row offset pages to count distinct sources in JS (`:446–468`). The installer default is every 900 seconds (`install_media_relations_launchd.sh:72`); root and report paths are hardcoded `/Applications/Kuro`, so actual installed activation/path must be checked before claiming current cost.

If defaults were installed and 500 eligible titles exist in each mode, an idle run costs approximately **1,003 + relation-page-count requests**, versus the single queue fetch needed to discover no work. At 96 runs/day the ladder report alone would generate 96,000 RPCs/day. This is a conditional source-derived estimate, not an observed live count. Move wide coverage audits to a manual/daily operation; use bounded SQL aggregates or cached counters; report deltas for the titles actually processed. Idle worker should exit cheaply.

### OP02 — Recommendation-edge importer retries server errors forever

`import_anilist_rec_edges.js:278–313`: `upsertEdges` has `for (...;;)` and, on HTTP >=500, sleeps 2 seconds and continues without incrementing a bounded failure counter or enforcing a deadline. Hourly RPC rate-limit waits are separately capped at three, but the server-error branch is not. Add capped exponential backoff with jitter, per-request timeout, total attempt/time budget, cancellation and retained checkpoint. This is a manual importer source defect; no evidence it is presently running.

### OP03 — Relation refresh is chatty and nontransactional

`media_relations_worker.js:203–244` deletes all AniList edges for a source before resolving target IDs one by one and upserting replacement rows. Request failure after delete can erase a valid ladder until retry. Local-ID memoization prevents repeated lookups within one process, but not the first N target calls or across runs. Queue hydration also performs one anime/manga query per queue item (`:257–287`), followed by per-item status writes (`:296–339`). Queue candidate reads are not a transactional lease: local shell PID lock only protects one local report directory, not a second host/worker; errored rows are eligible immediately with no retry ceiling or next-attempt condition. Batch ID mapping, lease candidate rows in SQL, transactional replace only after complete validated source response, retain last-known-good data, and cap failures with backoff.

### OP04 — Fast importer batches writes but not ID-map hydration

`import_anilist_fast.js:128–134` resolves `.in(keyField, ids)` without chunking/pagination; a media page can contribute up to 50 characters and 50 staff per title, so unique auxiliary IDs can exceed a PostgREST result cap. Upserts are chunked at 1,000 (`:151–156`) but subsequent mapping can silently omit later IDs, resulting in missing joins. Verify actual endpoint max-rows; chunk ID lookups and assert every required imported entity maps or is reported. Main accepts unvalidated concurrency (`:403`): zero/negative concurrency leaves the `while` loop waiting forever, and very high input launches uncontrolled page concurrency. Default is 3, finite page range; cap and validate. Calls lack explicit network abort deadlines. Page failures log and allow eventual successful process exit; ensure resumable failed-page manifest and failure summary.

### OP05 — Old local/legacy importers amplify entity writes and replace child rows

`import_anilist_local.js:172–409` upserts one title, then each studio/tag/character/staff and join individually; also deletes and recreates episode/chapter/volume placeholders. Chapter/volume arrays are generated from total counts. `scripts/legacy/*edge_function*.js` preserves similar patterns but is **legacy reference**, not deployed-edge proof. Distinguish these from the active edge implementations reviewed elsewhere. Consolidate supported ingestion entry points, retire unsafe paths, compare source versions/hashes, batch upserts and preserve enriched child metadata. Placeholder totals must never be represented as verified release dates or songs.

### OP06 — Reporting utilities can scan tables and some healthchecks write

`collect_db_metrics.js` executes separate exact-count queries for 23 tables, filtered coverage counts, 10 list-status counts and many missingness fields. HEAD reduces payload, not exact-count work. Manual use is appropriate at a controlled cadence; don't turn this into Home polling. `check_cron_health.js:49` uses exact count just to establish a table exists; `:277,:290,:310` invokes actual import, manga-enrichment and mirror functions, so it is **not read-only**. `genre_audit.js:50` reads up to 25,000 rows per media type and scans tags in pages; counts/coverage can be incomplete relative to current larger catalog. Prefer bounded aggregate diagnostics with explicit sample size, and separate read-only monitoring from run-work controls.

### OP07 — Provider worker has sensible bounds but per-title round trips and soft deadline

`provider_availability_worker.swift:582–630`: default limit 100, 45s time budget, sequential candidates. Each candidate obtains media seed, source map, optional refresh state, provider source data, offers upsert, refresh state upsert and a stale-offer ID read (up to 1,000 IDs merely for a count at `:1143`). Candidate deadline is checked between titles, not as a hard deadline on individual network operations. Source matching and offers are intentionally separate; keep that integrity while returning mapping/media fields in candidate batches and persisting result/state atomically. Mapping errors retry at up to 24-hour intervals; Watchmode has a 3 requests/s limiter and bounded retries. Source/price decision remains gated, so code existence does not prove live provider coverage.

### OP08 — Synopsis and safety workers are bounded but incur avoidable bookkeeping scans

Synopsis: before counts per media type, candidate RPC per media type, one result/failure RPC per item, after counts. Direct worker default 25 per type capped 200; installer default is 100 per type every 240 seconds. Catalog safety: lexicon read, before counts, candidates, one result/failure RPC per item, after counts and open-gaps RPC; default 200 per type capped 1,000, installer every 600s. PID/TTL locks prevent local overlap. Queue/backoff SQL exists but must be evaluated by SQL audit; transport clients use URLSession without explicit request deadlines/retry policy. Separate inexpensive work polling from full backlog/open-gap scans and batch result commits where it preserves failure isolation. Do not remove needed retry or safety review evidence solely to lower call counts.

## Current hosted cron evidence supplied by root audit

Root freshly captured `evidence/live-cron.json` and `evidence/rebuild_media_similar_titles.sql` during this initiative:
- `realm-similar-drive-5m`: 287 runs in 24h; mean 25.89s; maximum 442.59s. This is background job runtime, not a Home-request latency measurement.
- `realm-tier-refresh`: one run ~133.57s in that window.
- Live similar builder performs global seed sync and recursive franchise-component maintenance **before** checking for an empty stale batch; overlap advisory lock exists. Thus an apparent empty-batch path is not necessarily a cheap no-op.
- Cumulative pg_stat_statements supplied by root: 15,060 similar rebuild calls averaging 25.54s since the stats window, and 54 tier rebuild calls averaging 133.77s. Temp IO and table rows-scanned are cumulative and must not be presented as current per-request cost.

Prioritize change-driven invalidation and moving invariant/global maintenance out of every 5-minute driver invocation; measure quiet and active queue deltas separately. Retain previous serving rows until successful rebuild, advisory overlap protection and timeout guards. Validate whether nightly full re-stale is needed for unchanged inputs rather than simply slowing all fresh-data delivery.

HTTP pg_cron success proves dispatch only; it does not prove an edge function finished or persisted updates. Need edge/import run completion and source freshness evidence.

## Operational call graph and schedule intent

| Pipeline | Source flow | Source bounds / controls | Actual activation |
|---|---|---|---|
| Synopsis | launchd -> `run_synopsis_enrichment.sh` -> Swift client -> backlog/candidate RPC -> Apple FM or heuristic -> result/failure RPC -> local reports | installer 240s, batch100/type; direct default25/type; worker cap200; PID/TTL lock1800s | not queried here |
| Catalog safety | launchd -> `run_catalog_safety.sh` -> terms + backlog/candidates -> local rules/FM -> result/failure RPC -> open-gap report | 600s, batch200/type, cap1000, PID/TTL1800s | not queried here |
| Media relations | launchd -> shell -> queue -> catalog hydration -> AniList -> local ID resolution -> delete/upsert edges -> status -> full coverage report | 900s, queue40, top500/type, AniList20s timeout + max4 retries; lock21600s | not queried here; hardcoded old path |
| Provider | launchd -> shell -> candidate RPC -> seed/map -> Watchmode search/source -> offers/state -> reports | 600s,100 candidates,45s between-item deadline; local lock7200s; rate3/s | not queried here; rollout/source gated |
| Recommendation edges | manual CLI -> whole visible pool paged -> resume checkpoint -> AniList rec pages -> missing IDs in chunks100 -> upsert_rec_edges chunks500 -> checkpoint | AniList bounded retries + Retry-After; 3 hourly-rate waits; **5xx RPC unbounded** | manual runtime unverified |
| Realm descriptors | manual driver -> `media_realm_llm_pending` paged -> local success checkpoint -> realm-describe single or batch -> cooldown | batch default10 cap25; concurrency default3; overall limit optional; batch429/no-progress cooldown and exit guard | cron was repeatedly added/paused historically; inspect live |
| Similar titles | nightly re-stale -> 5-minute SQL builder -> media_similar_titles -> app indexed serving RPC | source batch100, timeout600s, overlap advisory lock; root observed current runtime | live root evidence above |
| Realm refresh chain | membership04:30 -> affinity04:40 -> tier04:50 -> similar-nightly05:10 | SET-first600s for membership/affinity; expensive materialized maintenance | live root metadata authoritative |
| Mirror images | five daily HTTP cron dispatches -> mirror-images edge -> bounded storage/DB batches -> run logs | anime/manga offsets0/200/400 at02:00/15/30; character02:45; staff03:00, limit200 source registrations; auth & skip-if-mirrored | edge work reviewed separately; dispatch != completion |
| Manga enrichment | 15-minute queue / nightly sweep cron -> manga-chapter-enrich edge -> canonical mapping and enrichment | several later migrations replace schedule/body | live metadata, not additive migration count |
| Catalog import | hourly edge trigger or manual `run_full_import` / local/fast importer | servercheckpoint/manualmaxLoops10; per-operation limits vary | distinguish separate supported entrypoints |
| Local dashboards | browser timer -> local /api/status -> JSON/log files | synopsis/safety/provider frontend5s polls | **not recurring DB queries**; avoid falsely counting them |

Migration history includes superseded cron registrations. E.g. similar batch changed300->200->100, realm-describe added then paused, old club message pruning removed. Register retains the historical sites as evidence, not as simultaneous live jobs. `kuro-refresh-matviews` captured in `20260807000000_baseline_capture_v1.sql:3015` uses seven ordinary `REFRESH MATERIALIZED VIEW` statements rather than CONCURRENTLY; determine current definition and reader contention from runtime evidence. Existing unique indexes alone do not make a nonconcurrent refresh concurrent.

## Contract for the comprehensive implementation plan

1. Maintain a single explicit registry connecting each supported executable to owner, trigger, deployment location, operation/write class, input source, tables/RPCs, rate budget, timeout/retry policy, checkpoint, last-success evidence and stop mechanism. Mark legacy/manual scripts clearly.
2. Prevent accidental double scheduling across local launchd, pg_cron and manual backfills using DB leases/idempotency where overlapping jobs mutate the same rows; local PID locks remain useful but are not distributed protection.
3. Ingest new songs/release/relations data through bounded queues prioritized by followed/popular titles, changes and freshness; never fetch external providers separately per visible image/card. Preserve source IDs, source timestamps, confidence/mapping status and licensing constraints.
4. Treat anime and manga as separate freshness contracts. Anime episode dates can expire; manga chapter/volume counts are not reliable dates. Serve unknown and source age honestly.
5. Home should read prepared, bounded, mode-specific results; ingestion and global scoring are background work. Don't place count diagnostics, relation coverage scans or recomputation on a user screen load.
6. Verification: dry-run fixture tests for queue leasing, retries, malformed concurrency, server500 exhaustion and source-partial failures; bounded integration tracing for idle/active worker call counts; measured DB stats deltas and EXPLAIN on representative sizes, including large catalogs/collections. Prove no last-known-good data loss on failed refresh. Keep live-load tests a separate approved step.

## Remaining uncertainty

All source files in the declared executable extensions were mechanically screened, and principal worker flows were manually inspected; this is not an AST-complete guarantee for generated URLs, dynamic SQL, dynamic wrapper targets or unexecuted branches. Cron historical declaration coverage is complete for direct `cron.schedule/unschedule` sites in migration files, while hosted job state is root evidence. Actual launchd installation, environment overrides, alternate `/Applications/Kuro` copy, API max-rows and current worker process activity were not inspected here. The CSV intentionally marks unresolved bounds/targets rather than inventing certainty.
