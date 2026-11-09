# Kuro backend capacity — recommendation v55 wired qualification, 9 November 2026

**PASS for the specified 100-active-session steady-state workload.** R15 completions: 16,500; errors: 0; missed offered starts: 0. Acceptance requires every unchanged stage and subgroup gate, real background work, ownership checks, exact cleanup and fresh production readback. This is a bounded workload qualification, not an unlimited scalability or release guarantee. All checkpoints are explicit in [the machine-readable verdict](capacity-verdict-r15.json).

## Workload and measured environment

The owner chose 100 simultaneously active users. Fixed arrivals model one backend request per user every five seconds: 20 rps for ten minutes, then 40 rps for one minute and 20 rps for 90 seconds recovery, preceded by a 60-second 5 rps gate. The complete sequence offers 16,500 requests. This is not 100 constantly busy SQL queries. Production is the Frankfurt project `bkdifromsqxkndnllmdj`, existing Micro compute and API pool cap three. The only newly deployed runtime change before R14/R15 is the explicitly approved Recommend v55; its [deployment receipt](recommend-fanout-deployment-receipt.json) verifies downloaded source and JWT enforcement.

The fifth cohort has 100 distinct ordinary JWT identities: 20 empty libraries, 50×25 titles, 25×100 and five×2,000; 13,750 independently counted list rows (9,650 anime / 4,100 manga), five clubs with ten members each. Catalogue approximately 21.7k anime /41.7k manga. Administrative credentials are used only for setup, observation and cleanup. All measured requests use ordinary user tokens; no spoofed IPs, disabled guards, retries, mocks or paid narration. [Independent fixture counts](fixture-final-shape-r5.json).

Mix: Home 20%, Browse 20%, Search 15%, Detail 20%, Mood 8%, Clubs 5%, Discover 5%, Progress 5%, Parse 1%, deterministic Recommend 1%. Empty users revisit Home. Reads cover both media; progress writes are anime-only. Club loading covers membership without seeded rails/polls. Applied progress receipts and semantic responses are required. Rates, deadlines, endpoint/library/medium limits and safety stops remain those declared in [PLAN](PLAN.md).

The Mac's wired default route is en0, checked before testing and every ten seconds; route change creates the STOP file. The same Node 22.22.0 transport and eight hashed source/test files are used. There is no client threshold or transport change for this retest.

## R15 measurements

All times are end-to-end milliseconds, including errors/timeouts. Zero unexpected errors and zero missed starts are mandatory. Every endpoint, library-size and medium subgroup must pass. Small subgroups keep their original nearest-rank p95, even when that equals the maximum.

| Stage | Completed/offered | Achieved rps | Errors / missed starts | Overall p95 ms | Overall p99 ms | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| [r15-warmup-5rps](r15-warmup-5rps.json) | 300/300 | 5.01 | 0 / 0 | 123.25 | 498.73 | PASS |
| [r15-soak-20rps](r15-soak-20rps.json) | 12000/12000 | 20.00 | 0 / 0 | 112.09 | 440.60 | PASS |
| [r15-spike-40rps](r15-spike-40rps.json) | 2400/2400 | 39.99 | 0 / 0 | 111.15 | 368.61 | PASS |
| [r15-recovery-20rps](r15-recovery-20rps.json) | 1800/1800 | 19.99 | 0 / 0 | 104.45 | 333.15 | PASS |

| Stage | Endpoint | Requests | p95 ms | Declared limit ms | Gate |
| --- | --- | ---: | ---: | ---: | --- |
| r15-soak-20rps | home | 2499 | 58.01 | 1200 | PASS |
| r15-soak-20rps | browse | 2393 | 53.93 | 750 | PASS |
| r15-soak-20rps | search | 1805 | 169.94 | 750 | PASS |
| r15-soak-20rps | detail | 2354 | 67.92 | 1200 | PASS |
| r15-soak-20rps | mood | 1028 | 113.17 | 1500 | PASS |
| r15-soak-20rps | clubs | 615 | 54.96 | 750 | PASS |
| r15-soak-20rps | discover | 590 | 127.88 | 1500 | PASS |
| r15-soak-20rps | progress | 488 | 60.47 | 750 | PASS |
| r15-soak-20rps | parse | 118 | 533.74 | 2500 | PASS |
| r15-soak-20rps | recommend | 110 | 936.00 | 2500 | PASS |
| r15-spike-40rps | home | 528 | 53.95 | 1200 | PASS |
| r15-spike-40rps | browse | 508 | 51.31 | 750 | PASS |
| r15-spike-40rps | search | 358 | 173.15 | 750 | PASS |
| r15-spike-40rps | detail | 454 | 52.51 | 1200 | PASS |
| r15-spike-40rps | mood | 208 | 122.13 | 1500 | PASS |
| r15-spike-40rps | clubs | 106 | 46.57 | 750 | PASS |
| r15-spike-40rps | discover | 100 | 127.19 | 1500 | PASS |
| r15-spike-40rps | progress | 93 | 48.75 | 750 | PASS |
| r15-spike-40rps | parse | 28 | 469.17 | 2500 | PASS |
| r15-spike-40rps | recommend | 17 | 1079.57 | 2500 | PASS |
| r15-recovery-20rps | home | 398 | 50.75 | 1200 | PASS |
| r15-recovery-20rps | browse | 393 | 47.72 | 750 | PASS |
| r15-recovery-20rps | search | 278 | 197.59 | 750 | PASS |
| r15-recovery-20rps | detail | 333 | 53.34 | 1200 | PASS |
| r15-recovery-20rps | mood | 151 | 110.78 | 1500 | PASS |
| r15-recovery-20rps | clubs | 81 | 53.92 | 750 | PASS |
| r15-recovery-20rps | discover | 70 | 117.83 | 1500 | PASS |
| r15-recovery-20rps | progress | 66 | 43.70 | 750 | PASS |
| r15-recovery-20rps | parse | 19 | 462.98 | 2500 | PASS |
| r15-recovery-20rps | recommend | 11 | 878.12 | 2500 | PASS |

The runner independently checks library-size and explicit-medium groups. [Derived medium checks](derived-medium-check-r15.json) supplement Search/Browse's null medium field using the frozen builder's sequence rule, cross-check explicit media and hash raw inputs. Identical declared limits apply; no raw sample changes. Inspect the raw stage JSON for every subgroup, completion, upstream timing and generator measurement.

The formerly failing 2,000-title Recommend subgroup has three R15 soak samples: 1,354.23 /979.93 /1,737.48 ms, all below the unchanged 2,500 ms limit. Its nearest-rank p95 is 1,737.48 ms versus R13’s 2,614.42 ms; n=3 is sparse and does not establish a stable tail distribution.

## Repairs and contract evidence

- Query migration `20261109001251` (`cba0a331…`): 18 Search/Browse indexes and parameter-bound custom plans preserve ranking, filters and cursors. 74 local differential cases, five SQL assertions and 34 same-snapshot live comparisons pass. Representative Search SQL 357/730 →23/17 ms; separate earlier 5 rps HTTP p95 878.58 →157.99 ms. [Receipt](deployment-receipt.json).
- Worker migration `20261109003243` (`5ff1e8e…`): five FIFO profiles per minute with locked-row skipping; math, server-only grants and job 37 identity/command preserved. Eleven worker/concurrency assertions and four real-vector comparisons pass. [Receipt](worker-deployment-receipt.json).
- Parent-index migration `20261109100800` (`57e8b11d…`): full parent indexes retain uniqueness and nullable numbers; ten local plan/parity/NULL assertions pass. Live indexed reads 10.609 →0.577 ms /44.762 →1.176 ms with matching rows. Parent/number planner statistics refreshed. [Receipt](parent-index-deployment-receipt.json).
- **Recommend v55**, approved catalogue repository SHA `49b88d972cec80199a86ef58bca6cf0f17fb5d77300d50af918484c9ad7af92b`: identical candidate reads share fulfilled/in-flight results only inside one authenticated request. All five RPC arguments form the key, returned rows are independently cloned, failed reads are evicted and followers retain independent recovery. Hydration, ranking, response, JWT and RLS behavior remain unchanged. All eight downloaded source entries match the approved closure; other function versions/JWT settings and selected Auth configuration compare unchanged. Twenty-six focused tests and 36 complete handler-response comparisons pass; premium queries 276 →120 across offline cases, and six →one for the affected large-library prompt. Offline parity is separate from the live measurements above. [Reviewed deployment](DEPLOYMENT-RECOMMEND-FANOUT.md), [parity](recommend-fanout-parity.json), [live smoke](recommend-v55-live-smoke.json).

All deployments were explicitly approved. Historical whole-chain SQL replay remains incomplete (203 applied /62 failed); targeted tests do not establish a full database rebuild. Production JIT was already globally off: earlier compilation causality was overstated; scoped JIT-off is defensive.

Current runtime pool cap is three. Its update returned provider HTTP 500 while acknowledging configuration, but fresh GET, session count and API readiness confirmed application. Other nonsensitive settings compare unchanged; prior signing-secret bytes were not retained after the failed process, so no byte comparison is claimed for that request. Existing JWTs validate; no credential operation or compute/billing change was requested. [Pool record](POOL-TUNING.md), [pool-three receipt](postgrest-pool3-receipt.json).

## Resources, background work and isolation

78 database/route observations: maximum 11/60 connections, 2 active sessions and 0 lock waiters. Deadlock delta 0. Default route en0 in every observation: True. [Database and route samples](db-capacity-sequence-r15.json).

14 minute-cached host samples: available memory 165.9–256.6 MB; swap-in counter delta 69,344 pages. Host observer errors: 0. Paging is reported even if latency passes; this does not establish a hardware saturation ceiling. [Host samples](resources-capacity-sequence-r15.json). Samples are cached and sparse; counters are never reset. Independent [HTTPS controls](connectivity-control-r15.json) and private-query/public-hash captures support diagnosis; they do not replace end-to-end gates.

14 completed natural worker executions observed; maximum 5.508 seconds. Controlled fixture backlog: 50 accounts, including five large libraries, requeued during sustained traffic; manual execution 143.502 ms. Natural cron remains enabled. [Large-profile proof](worker-large-profiles-r15.json) checks all five large profiles computed after requeue; a manual call alone does not prove which accounts it processed. [Worker time series](worker-under-load-r15.json) and [scheduled catalogue overlap](cron-overlap-r15.json) record actual background work. HTTP-dispatch cron success is dispatch proof only; importer checkpoint timestamps are recorded separately and do not prove full-catalogue completion.

[Isolation under load](isolation-under-load-r15.json) records owner-positive and outsider-negative library/club probes and effective grants on five privileged RPCs. Worker grants, exact SQL history, current Auth/function identities, pool, health and advisors are rechecked [after cleanup](final-live-state-r15.json); [reviewed index readiness](final-index-readiness-r15.json) is checked separately. Neither advisor reports ERROR-level findings; existing warnings remain, including executable SECURITY DEFINER surfaces, service-only RLS without client policies, API materialized views, one mutable search path and an extension in public. Those warnings are listed in the readback and were not globally remediated by this capacity initiative. These scoped checks do not imply a complete security or native release audit.

## Prior failures, cleanup and limits

R14 then completed 300/300 without errors or missed starts, but its first Discover call was 1,807.22 ms /1,750 ms upstream against 1,500 ms; derived Search/Manga (942.57 ms) and Mood/Anime (1,514.75 ms) also failed. Its soak was stopped. R15 is one subsequent steady-state characterization with unchanged gates, not cold-start qualification. Three observers initially saw R14’s completed marker and were restarted during warmup (database observations 13.40 seconds apart); their initial samples are retained and the warmup observation gap is explicit.

All earlier failures remain in the [pre-Ethernet report](REPORT-BEFORE-ETHERNET.md), [pre-v55 report](REPORT-BEFORE-RECOMMEND-V55.md) and original raw files. The pool-six run passed 12,000 requests at 20 rps but failed burst/recovery. Later tests showed real upstream stalls and separate downstream/client delays. First wired R12 retained a cold empty-library Search miss: 834.55 ms /674 ms upstream, above 750 ms. Six later identical probes returned 298–640 ms with valid rows. Wired R13 completed 12,000 soak requests with zero errors/missed starts and 109.18 ms overall p95, yet **failed** the large-library Recommend subgroup: three samples 1,529.47/1,472.25/2,614.42 ms against 2,500 ms. Burst/recovery were stopped. That failure prompted v55; overall p95 never overrides a failed subgroup. Retesting does not erase cold-call or intermittent-tail risk.

The first four cohorts are independently clean: 400 Auth identities and 20 clubs removed, with 41 user-bearing base-table checks per cohort and only intentional seven-day deletion barriers retained. Fifth-cohort cleanup: **PASS**; [account receipt](cleanup-accounts-r5.json) /[independent physical absence checks](cleanup-verification-r5.json). Full acceptance requires cleanup. Exact fixture provenance is checked before deletion; there is no customer sweep. Private fixture tokens are removed after deletion.

Nineteen focused harness tests pass; all eight source hashes and snapshots v1–v4 remain available. [Reproduction](README.md). Source inventory remains 293 app Swift /33 package Swift /250 canonical SQL migrations; no iOS/TestFlight release was made.

This qualification does not establish cold-start limits, hours-long durability, much larger datasets, 100 permanently busy queries, distributed-region latency, native/device/CDN/Realtime/auth floods/poll mutations, provider saturation or paid narration. A changed workload or compute tier requires another measured qualification. Updated UTC: 2026-11-09T12:23:08.953100+00:00.

Independent read-only review found no actionable issues in the deployed request-scoped change or evidence claims. It separately recalculated149 observed endpoint/library-size groups, overall percentiles and derived media/raw hashes, and checked cleanup/source/history/readback consistency. This review used source and saved receipts; it performed no independent live probes or new test execution. [Review record](independent-review-r15.json).
