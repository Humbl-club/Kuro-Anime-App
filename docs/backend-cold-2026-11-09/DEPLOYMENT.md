# Cold-start repair and qualification — approval package

**Prepared, not deployed. Production cold-start capacity remains unproved.** Existing warmed R15 proof stays valid for its dated workload; this package does not turn that into cold-start proof.

Exact migration: `supabase/prepared-migrations/20261109123758_cold_catalogue_reads_v1.sql`. Reviewed hashes and the two unchanged Edge closures are pinned in [deployment-manifest.json](deployment-manifest.json). Five new indexes, two Search function settings, no table rows or RPC bodies/grants/RLS changed. The original 750/1,200/1,500/2,500 ms limits remain unchanged.

## Authorized scope requested

1. Apply only this exact migration atomically and record its exact immutable statement in history. Promote it to canonical migrations only after live/history verification. No blanket push/history repair.
2. Temporarily install `pg_buffercache`1.5 using the exact [installation SQL](INSTALL-CACHE-INSPECTION.sql). It is currently available but absent. Restrict every extension function and its view against `PUBLIC`, `anon` and `authenticated`, verify effective denial, and retain its creation receipt. No eviction function is ever called. The purpose is a verifiable buffer-state observation, not a new application dependency. Stop if it already exists or installation/client-denial verification fails.
3. Redeploy **unchanged** approved sources for `concierge-parse` (currently49) and `concierge-recommend` (currently55), JWT verification true, using isolated eight-file closures. This is a new runtime version for observation, not a behavior change. Verify downloaded hashes and versions; invoke neither function before the measured test.
4. Perform **one controlled restart** of the existing production project `bkdifromsqxkndnllmdj`. This creates a maintenance outage; measure/report its actual duration separately. No compute upgrade, billing, credential, Auth, feature-flag or pool change. No repeated restarts or retries to manufacture a pass.
5. Run the cold-onset sequence and exact cleanup below. Remove the temporary extension [without CASCADE](REMOVE-CACHE-INSPECTION.sql) only if this experiment's receipt proves it created it; stop rather than delete another owner's dependency.

This is a new migration, new runtime redeployments and an interrupting hosted operation. Current `AGENTS.md` requires explicit authorization for those scopes. Earlier v55 approval is retained as deployment history, not reused as permission for a restart.

## Prerequisites and recovery

Freshly verify source hashes, project/backup status, exact current function versions/JWT, selected Auth settings, five existing migration statements, current pool and no unrelated pending deployments. Required four ranked relations and the realm relation must be materialized views. The optional realm index skips only a genuinely absent optional relation; present wrong type fails. Production qualification requires all five reviewed indexes present/valid/ready. Stop on concurrent source/runtime drift.

Index construction takes ordinary transactional locks and can conflict with materialized-view refresh. Lock timeout3 s /statement timeout90 s preserve atomic failure; do not retry blindly or weaken limits. Local synthetic index size is about9.3 MiB, mostly realm covering data. Production size and refresh overhead must be measured, not assumed equal. Keep existing unique keys and refresh schedules intact. Index-only benefit can diminish after refresh until visibility maps recover; record heap fetches.

Save current safe config/source/ACL/index definitions and backup metadata privately. If the new SQL causes a regression, the reviewed recovery scope is to drop only these five new indexes and restore only the two Search per-function thresholds to0.3, with short lock/time limits, preserving all earlier security/performance work and migration history. Do not restore an old entire database or function bundle. If restart/health fails, stop testing, preserve provider evidence and surface the incident rather than issue further restarts. No credential or plan change is part of recovery.

## Verifiable cold condition

Create and independently verify a **fresh sixth** fixture before the restart:100 tagged ordinary identities,20 empty/50×25/25×100/five×2,000 libraries,13,750 rows, five clubs/50 memberships. Existing500 identities/25 clubs are already cleaned and cannot be reused. Use the current private fixture recovery inventory and four-starts/second setup/cleanup limits. Administrative credentials never enter measured requests.

After restart, verify changed `pg_postmaster_start_time`. Poll only owning-service status, Auth health and REST metadata readiness; no catalogue RPC, smoke recommendation, EXPLAIN, sample title lookup, manual worker call or application-data read is permitted before onset. Record every readiness observation and the planned-outage interval.

Use [READ-CACHE-STATE.sql](READ-CACHE-STATE.sql) to observe public heaps, indexes, materialized views and associated TOAST buffers without reading catalogue rows. **Require zero target cached blocks**, record exact timestamp and new postmaster start, and start the fresh Node generator within five seconds of this observation/readiness. Natural cron remains enabled; record any intervening executions. If background/client activity has already warmed the target buffers, label the attempt NOT COLD/UNQUALIFIED, do not relabel it or restart again. Preserve the trace and clean the fixture.

A PostgreSQL restart and empty shared buffers do not prove an empty OS/storage cache. Report that boundary explicitly. Edge redeployment alone does not prove a new isolate: inspect provider boot/execution evidence correlated to the new deployed versions and measured onset, including boot time in first-request latency. If that evidence is unavailable, report Edge-cold state UNPROVEN and do not claim whole-backend cold qualification. Do not use warm calls to check readiness. This separates database-buffer/process-cold, client-connection-cold, Edge-isolate-cold and unobservable OS/storage state.

## Same workload, stricter onset acceptance

Use the same pinned eight-file Node workload, ordinary100 JWT actors, original seed/mix, request bodies, semantic checks, eight-second deadlines, safety stops, rates and limits. Start **20 rps immediately**, with no5-rps warmup. Run20 rps/600 s,40 rps/60 s,20 rps/90 s:16,200 offered starts. One active request/user/five seconds (two-and-a-half during burst) remains the agreed model, not100 permanently busy queries.

In addition to every original endpoint/library/media gate and zero errors/missed starts, use [backend_cold_gate.js](../../scripts/load/backend_cold_gate.js):

- All100 actors represented in the first100 starts (first five seconds), without dropped/duplicate starts.
- First60seconds:1,200 completions, all16 required route/media variants, same p95/error limits by route and every observed library group. Missing first-minute library groups are listed, not silently treated as tested.
- Whole cold stage: all39 declared endpoint/library groups (empty progress excluded), all16 route/media variants, and the same per-group limits. Missing mandatory groups fail.
- The very first request in each declared route/media and endpoint/library cell must individually meet its existing latency limit. Warm requests cannot wash out a slow first call.

First-use groups encountered later in the stage share earlier cache activity; this is one observed cold-start sequence, not63 independent cold experiments. Do not claim independently cold behavior for each cell. Stop escalation after any failed stage or cold gate; retain every failure and do not retry to a pass.

Observers start before onset with unique markers. Keep Ethernet/en0 route checks and DB connection/lock safety observations about every10 s; stop on route change, two monitor errors or the existing pressure limits. Keep host metrics about60 s, slow-query hashes/public references, private raw SQL and independent HTTPS controls. Requeue only50 verified fixture profiles during the soak after onset; confirm all five large profiles recompute and record actual natural cron work. Run owner/outsider library/club checks and five privileged-RPC grant checks during load. HTTP cron dispatch success is not importer completion proof.

After any outcome, remove only the exact tagged100 Auth identities/five clubs through the app route with Auth404 checks. Verify41 user-bearing table columns and exact club IDs physically empty, allowing only existing seven-day deletion barriers. Remove fixture tokens. Freshly recheck the exact migration/history, source closures/JWT, Auth/pool, worker math/grants/cron, index definitions/readiness, health and advisors; independently review final evidence and update the three canonical docs/project memory. A cold PASS requires the cold-state receipts, all unchanged/extra gates, background/isolation checks and exact cleanup. Missing proof remains a failed/unqualified gate.

References: [Supabase restart API](https://supabase.com/docs/reference/api/v1-restart-a-project), [PostgreSQL17 buffer inspection](https://www.postgresql.org/docs/17/pgbuffercache.html), [pg_trgm implementation](https://github.com/postgres/postgres/blob/REL_17_STABLE/contrib/pg_trgm/trgm_op.c).
