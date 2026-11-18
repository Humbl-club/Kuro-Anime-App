> Historical snapshot before the Ethernet retest. For current status see [REPORT.md](REPORT.md).

# Kuro backend load qualification — 9 November 2026

**NOT QUALIFIED for the complete agreed workload.** All three approved performance migrations are deployed and verified. An earlier configuration passed the normal ten-minute workload, but burst and recovery failed. The current configuration has not passed its complete sequence. Zero request errors alone does not count as a capacity pass.

## Workload and acceptance

The owner chose **100 simultaneous active users**. Fixed arrivals model one backend request per user every five seconds: 20 rps for 600 seconds, then 40 rps for 60 seconds and 20 rps for 90 seconds recovery. A 60-second, 5 rps gate precedes escalation. This models active sessions, not 100 continuously busy SQL queries. Rates, deadlines, semantic checks and end-to-end latency limits were declared in [PLAN](PLAN.md) and were never relaxed.

Each cohort contains 100 distinct ordinary authenticated identities: 20 empty libraries, 50 with 25 titles, 25 with 100, and five with 2,000. There are 13,750 list rows (9,650 anime / 4,100 manga) and five private clubs with ten members each. The catalogue is real production data, approximately 21.7k anime / 41.7k manga. Administrative credentials are restricted to setup, observation and cleanup; measured client traffic uses ordinary JWTs.

The mix is Home 20%, Browse 20%, Search 15%, Detail 20%, Mood 8%, Clubs 5%, Discover 5%, Progress 5%, Parse 1%, deterministic Recommend 1%. Empty users revisit Home instead of writing progress. Reads cover both media; progress writes are anime-only. Clubs cover membership/loading bundles without seeded rails or polls. Progress must return an applied mutation receipt. No spoofed IPs, disabled guards, automatic retries, mocks or paid narration are used.

## Every measured phase

Milliseconds are end-to-end from this Mac; errors/timeouts remain in the distribution. Zero unexpected errors and zero missed offered starts are required, alongside endpoint, library-size and medium gates. Original JSON contains all samples and generator timing. Separate medium checks derive Search/Browse media from the frozen request builder without changing raw samples.

| Phase | Completed/offered | Errors / missed starts | Overall p95 ms | Overall p99 ms | Gates |
| --- | ---: | ---: | ---: | ---: | --- |
| [before-100users-2rps](before-100users-2rps.json) | 120/120 | 0 / 0 | 500.90 | 826.36 | FAIL |
| [before-100users-5rps](before-100users-5rps.json) | 300/300 | 0 / 0 | 613.03 | 975.92 | FAIL |
| [after-2rps](after-2rps.json) | 120/120 | 0 / 0 | 222.54 | 674.07 | PASS |
| [after-5rps](after-5rps.json) | 300/300 | 0 / 0 | 142.88 | 367.68 | PASS |
| [ramp-10rps](ramp-10rps.json) | 600/600 | 0 / 0 | 160.34 | 310.13 | PASS |
| [soak-20rps](soak-20rps.json) | 2819/2863 | 54 / 44 | 326.05 | 8001.72 | FAIL |
| [r2-warmup-5rps](r2-warmup-5rps.json) | 150/150 | 0 / 0 | 275.03 | 890.92 | FAIL |
| [r3-warmup-5rps](r3-warmup-5rps.json) | 300/300 | 0 / 0 | 168.56 | 596.07 | PASS |
| [r3-soak-20rps](r3-soak-20rps.json) | 1876/1890 | 73 / 14 | 3833.62 | 8002.55 | FAIL |
| [diagnostic-10rps-180s](diagnostic-10rps-180s.json) | 1800/1800 | 6 / 0 | 464.00 | 857.45 | FAIL |
| [r4-warmup-5rps](r4-warmup-5rps.json) | 300/300 | 0 / 0 | 253.52 | 1122.90 | FAIL |
| [r5-warmup-5rps](r5-warmup-5rps.json) | 300/300 | 0 / 0 | 179.21 | 413.28 | PASS |
| [r5-soak-20rps](r5-soak-20rps.json) | 12000/12000 | 0 / 0 | 276.89 | 681.94 | PASS |
| [r5-spike-40rps](r5-spike-40rps.json) | 2337/2400 | 0 / 63 | 688.82 | 3217.53 | FAIL |
| [r6-recovery-20rps](r6-recovery-20rps.json) | 119/162 | 67 / 43 | 8001.80 | 8002.00 | FAIL |
| [r7-warmup-5rps](r7-warmup-5rps.json) | 300/300 | 0 / 0 | 293.90 | 1692.81 | FAIL |
| [r8-warmup-5rps](r8-warmup-5rps.json) | 300/300 | 0 / 0 | 914.57 | 1743.28 | FAIL |
| [r9-warmup-5rps](r9-warmup-5rps.json) | 300/300 | 2 / 0 | 778.78 | 4829.79 | FAIL |
| [r10-warmup-5rps](r10-warmup-5rps.json) | 300/300 | 0 / 0 | 614.02 | 1548.86 | FAIL |
| [r11-warmup-5rps](r11-warmup-5rps.json) | 300/300 | 0 / 0 | 992.17 | 1748.08 | FAIL |

The original baseline accidentally seeded 1,600 titles in large libraries because REST capped a 2,000-ID read at 1,000. Pagination was repaired and 2,000 titles independently verified before capacity tests. Original files remain unchanged.

The first sustained run stopped after 150.45 seconds with 54 timeouts and 44 missed starts. The worker-only R3 retry also failed. R5 later completed **12,000/12,000 at 20 rps for ten minutes**, without errors or missed starts: overall p95 276.89 ms, Search 296.97 ms, Recommend 1,217.20 ms. Its 40 rps burst then missed 63 starts and failed Clubs, Progress, Parse and Recommend limits. The scheduled recovery was skipped after failure. A separate R6 recovery probe stopped with 67 timeouts and 43 missed starts.

The separate 10 rps diagnostic had no HTTP failures but six HTTP-200 progress conflicts after earlier timed-out writes had committed, plus slow recommendations. It is not a pass. Owner-token-only refresh reconciled three stale fixture revisions before later runs; no resets occurred within a measured stage.

## Deployed and verified repairs

- **Search/Browse, `20261109001251`** (`cba0a331…`): 18 valid indexes and parameter-bound custom plans, preserving ranking, filters and cursors. All 74 local differential cases, five SQL assertions and 34 same-snapshot production comparisons pass. Representative live Search SQL improved 357/730 → 23/17 ms; separate 5 rps HTTP Search p95 improved 878.58 → 157.99 ms. [Receipt](deployment-receipt.json), [deployment](DEPLOYMENT.md).
- **Taste worker, `20261109003243`** (`5ff1e8e…`), deployed 09:15 UTC: five FIFO profiles per minute with locked-row skipping. Taste math, server-only grants and job 37 identity/command are unchanged. Eleven worker/concurrency assertions and four real-vector comparisons pass. Smaller batches alone did not close capacity. [Receipt](worker-deployment-receipt.json), [deployment](DEPLOYMENT-WORKER.md).
- **Parent lookups, `20261109100800`** (`57e8b11d…`), deployed 10:11 UTC: full episodes(anime_id) and chapters(manga_id) indexes; partial uniqueness remains. Ten local scan/parity/NULL/plan assertions pass. Live indexes are valid/ready, parent rows match, and recorded reads improved 10.609 → 0.577 ms / 44.762 → 1.176 ms. Observed importer DELETEs used the unsupported parent-only predicate. The current detail bundle uses its series-unit model; this is not a confirmed direct detail-bundle cause. Parent/number planner statistics were refreshed. [Receipt](parent-index-deployment-receipt.json), [deployment](DEPLOYMENT-PARENT-INDEXES.md).

Applied SQL bytes and exact history are preserved. Inventory: 250 canonical migrations, 293 app Swift files and 33 package Swift files. Historical migration replay remains incomplete (203 applied / 62 failed), separate from targeted passes.

## Memory and connection-pool findings

The earlier production compilation explanation was overstated: production JIT was already globally off, with no JIT-on role/helper override found. Controlled JIT-on/off comparisons do not establish live compilation overhead. Scoped JIT-off settings are defensive.

The existing Micro instance has approximately 1 GB RAM and two shared CPUs. The lower-rate diagnostic fell from 236 MB to 82 MB available memory with 210,631 swap-in pages. Automatic pooling had up to 21 observed sessions. A cap of six was applied at 09:43 UTC; every other API field, including signing secret, compared unchanged in memory. A brief readiness 503 during reload occurred outside load traffic.

Six connections still did not qualify: R9's minute-cached interval recorded 36,264 swap-in pages, 11,174 swap-out pages and 15.81 CPU-seconds of IO wait. PostgreSQL wait_event can be null during operating-system memory faults; null does not prove CPU saturation.

**The current cap is three.** The provider returned HTTP 500 while acknowledging this update, but a fresh configuration read, three actual PostgREST sessions and API 200 independently confirmed application. Other nonsensitive fields compare unchanged. The failed process did not retain prior signing-secret bytes, so no byte-identical comparison is claimed for that request. Existing JWTs validate; no credential operation, compute upgrade, billing, Auth, RLS or feature-flag change was requested. [Original receipt](postgrest-pool-receipt.json), [pool-three receipt](postgrest-pool3-receipt.json), [tuning record](POOL-TUNING.md). Revisit the cap when compute or traffic changes.

## Remaining latency and test-path limits

R7 first Discover took 1,692.81 ms (1,596 ms upstream), exceeding 1,500 ms. Six subsequent calls across all library sizes returned 269–568 ms. R8 and R11 also show a different pattern: 1–2-second client waits with only 3–70 ms reported upstream. R11 Progress took 1,392.28 ms with 6 ms upstream. Those gaps do not identify SQL as their cause; the exact client, network or downstream gateway contribution remains unproven.

The HTTP/2 comparison did not explain every failure: R9 also had actual multi-second upstream waits and two timeouts. After the smaller pool, R10 HTTP/2 completed 300/300 without errors or missed starts, failing only Discover's latency limit. R11's original connection-reusing Node transport completed 300/300 but failed Search and Progress limits. Neither escalated to sustained traffic.

The only active physical interface is Wi-Fi (en1); no Ethernet interface is connected. An Ethernet test was requested. No cloud workflow, cloud secrets or remote branch were created or approved. More SQL changes based solely on client-side waits would be unsupported.

[Envoy's timing definition](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/router_filter#x-envoy-upstream-service-time) includes upstream processing and the Envoy-to-upstream network path. It is not exact SQL time or full client-to-gateway time, and does not identify the downstream component responsible for a gap.

## Background, safety and isolation

Database observers sample every ten seconds and stop on declared pressure or monitoring loss; counters are never reset. Host metrics use 60-second cadence because the provider caches about a minute. Earlier R5 ten-second polling hit HTTP 429; its gap remains explicit. Each phase has separate DB, host, worker and connectivity evidence. Sampled data does not establish peak RSS or a hardware ceiling.

R5 requeued 50 fixture profiles and independently verified all five 2,000-title profiles recomputed. Natural cron remained active. The 10:00 UTC heavy anime import actually completed ten titles, 450 episodes, 104 voice-actor links and zero errors. Chapter enrichment also completed with zero errors while retaining unresolved mappings/retries. [Import overlap](catalogue-import-overlap-r5.json). These bounded overlaps do not prove provider saturation capacity. Later gates stopped before controlled backlog injection.

Owner-positive and outsider-negative library/club probes and five privileged-RPC grant checks passed during R5. Worker grants remain server-only. These are scoped checks, not a full security audit.

## Cleanup, reproduction and remaining proof

The first two cohorts are independently clean: 200 Auth identities and ten clubs removed, with 41 user-bearing base-table checks per cohort empty except 200 intentional seven-day stale-token deletion barriers. Third-cohort cleanup: **PASS**. Barriers are retained; fixture tokens are removed after deletion. [Cleanup evidence](cleanup-verification-r3.json), [reproduction](README.md).

Nineteen Node tests pass, including bounds, semantic receipts, offered starts, stop files, catalogue paging, safe cleanup, read-only revision refresh and curl credential/origin/abort guards. Eight current JS files are hashed; earlier six-file sources v1–v4 and every failed run remain archived. Curl negotiates TLS normally, follows no redirects, retries nothing and passes JWTs by stdin rather than arguments/files/logs. Only numeric upstream/protocol headers are recorded. Curl's response-start marker follows body collection; parent Node CPU excludes child CPU, while total latency includes all overhead.

Final acceptance still requires the unchanged complete sequence and exact cleanup over a reliable path. Current pool-three sustained/burst/recovery, cold starts, hours-long durability, larger data, constantly busy concurrency, multiple regions, native/device/CDN/Realtime/auth floods/poll/provider bursts and paid narration remain unqualified. No TestFlight or public release acceptance is implied.

Fresh post-cleanup live readback: [final-live-state-r11.json](final-live-state-r11.json), including five applied source/history checks, current pool three, worker math/grants/job, Auth/function identity, no advisor ERROR entries and all 20 reviewed indexes valid/ready.

Updated UTC: 2026-11-09T10:46:39.753068+00:00.
