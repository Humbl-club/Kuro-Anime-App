> **Current checkpoint: NOT QUALIFIED; recommendation repair awaits deployment approval.** Wired R13 completed 12,000 requests without errors or missed starts, but the 2,000-title recommendation subgroup failed at 2,614.42 ms against 2,500 ms (three samples). Burst and recovery were stopped. All 400 temporary identities and 20 clubs are independently clean. A local request-scoped query-sharing repair passes 26 focused tests and 36 complete-response comparisons; premium calls fall from 276 to 120 across those offline comparisons. It is not deployed. [Exact reviewed change](DEPLOYMENT-RECOMMEND-FANOUT.md).

# Kuro backend capacity — wired qualification, 9 November 2026

**NOT QUALIFIED — required checks remain incomplete or failed.** Latest R13 completions: 12,300; errors: 0; missed offered starts: 0. Acceptance requires every unchanged stage and subgroup gate, real background work, ownership checks and exact cleanup. The result is a bounded workload qualification on the existing production configuration, not an unlimited scalability or release guarantee.

## Workload and test boundary

The owner chose 100 simultaneously active users. Fixed arrivals model one backend request per user every five seconds: 20 rps for ten minutes, then 40 rps for one minute and 20 rps for 90 seconds recovery, preceded by a 60-second 5 rps gate. This is not 100 constantly busy SQL queries. Production is the Frankfurt project `bkdifromsqxkndnllmdj`, existing Micro compute and API pool cap three; no production code, plan or configuration changed for the wired retest.

The fourth cohort has 100 distinct ordinary JWT identities: 20 empty libraries, 50×25 titles, 25×100, five×2,000; 13,750 independently counted list rows (9,650 anime / 4,100 manga), five clubs with ten members each. Catalogue approximately 21.7k anime / 41.7k manga. Administrative credentials are used only for setup, observation and cleanup. All measured requests use ordinary user tokens; no spoofed IPs, disabled guards, retries, mocks or paid narration.

Mix: Home 20%, Browse 20%, Search 15%, Detail 20%, Mood 8%, Clubs 5%, Discover 5%, Progress 5%, Parse 1%, deterministic Recommend 1%. Empty users revisit Home. Reads cover both media; progress writes are anime-only. Club loading covers membership without seeded rails/polls. Applied progress receipts and semantic responses are required. Rates, deadlines, endpoint/library/medium limits and safety stops remain those declared in [PLAN](PLAN.md).

The Mac's wired default route is en0, independently checked before testing and every ten seconds; route change creates the STOP file. The same Node 22.22.0 transport and eight hashed source/test files are used. Ethernet changes the test path; it does not retroactively invalidate the earlier failures.

## Wired measurements

All times are end-to-end milliseconds, including errors/timeouts. Zero unexpected errors and zero missed starts are mandatory. Raw JSON retains every completion, subgroup result, upstream timing and generator measurement.

| Stage | Completed/offered | Achieved rps | Errors / missed starts | Overall p95 ms | Overall p99 ms | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| [r12-warmup-5rps](r12-warmup-5rps.json) | 300/300 | 5.01 | 0 / 0 | 163.09 | 663.58 | FAIL |
| [r13-warmup-5rps](r13-warmup-5rps.json) | 300/300 | 5.01 | 0 / 0 | 119.59 | 450.47 | PASS |
| [r13-soak-20rps](r13-soak-20rps.json) | 12000/12000 | 20.00 | 0 / 0 | 109.18 | 428.60 | FAIL |

R12 completed 300/300 without errors or missed starts. All overall endpoints passed, but the empty-library Search subgroup failed because the first request was 834.55 ms (674 ms reported upstream), above 750 ms. It remains a failed cold-call observation. Six subsequent identical Manga/Naruto probes across library sizes returned 298–640 ms with 30 valid rows each. R13 then repeated the unchanged gate and full sequence. A later steady-state pass does not establish cold-start compliance or erase R12.

## Latest endpoint limits

| Stage | Endpoint | Requests | p95 ms | Declared limit ms | Gate |
| --- | --- | ---: | ---: | ---: | --- |
| r13-soak-20rps | home | 2499 | 58.83 | 1200 | PASS |
| r13-soak-20rps | browse | 2393 | 53.76 | 750 | PASS |
| r13-soak-20rps | search | 1805 | 171.98 | 750 | PASS |
| r13-soak-20rps | detail | 2354 | 66.08 | 1200 | PASS |
| r13-soak-20rps | mood | 1028 | 112.62 | 1500 | PASS |
| r13-soak-20rps | clubs | 615 | 57.15 | 750 | PASS |
| r13-soak-20rps | discover | 590 | 126.73 | 1500 | PASS |
| r13-soak-20rps | progress | 488 | 56.82 | 750 | PASS |
| r13-soak-20rps | parse | 118 | 526.90 | 2500 | PASS |
| r13-soak-20rps | recommend | 110 | 962.56 | 2500 | PASS |

The runner independently checks library-size and explicit-medium groups. `derived-medium-check-r13.json` supplements Search/Browse's null medium field by using the frozen builder's sequence rule, cross-checking explicit media and hashing raw inputs. Identical declared limits apply; no raw sample is changed.

## Production repairs and independent contract proof

- Query migration `20261109001251` (`cba0a331…`): 18 Search/Browse indexes and parameter-bound custom plans preserve ranking, filters and cursors. 74 local differential cases, five SQL assertions and 34 same-snapshot live comparisons pass. Representative Search SQL 357/730 → 23/17 ms; separate earlier 5 rps HTTP p95 878.58 → 157.99 ms. [Receipt](deployment-receipt.json).
- Worker migration `20261109003243` (`5ff1e8e…`): five FIFO profiles per minute with locked-row skipping; math, server-only grants and job 37 identity/command preserved. Eleven worker/concurrency assertions and four real-vector comparisons pass. [Receipt](worker-deployment-receipt.json).
- Parent-index migration `20261109100800` (`57e8b11d…`): full parent indexes retain uniqueness and nullable numbers; ten local plan/parity/NULL assertions pass. Live indexed reads 10.609 → 0.577 ms / 44.762 → 1.176 ms with matching rows. Parent/number planner statistics refreshed. [Receipt](parent-index-deployment-receipt.json).

All three were explicitly approved and applied with immutable source/history. Historical whole-chain SQL replay remains incomplete (203 applied / 62 failed); targeted tests do not constitute a full rebuild claim. Production JIT was already globally off: earlier compilation causality was overstated, and scoped JIT-off is defensive. No speculative query rewrite or feature change was added for Ethernet.

Current runtime cap is three. Its update returned provider HTTP 500 while acknowledging configuration, but fresh GET, session count and API readiness confirmed application. Other nonsensitive settings compare unchanged; prior signing-secret bytes were not retained after the failed process, so no byte comparison is claimed for that request. Existing JWTs validate; no credential operation or compute/billing/Auth/RLS change was requested. [Pool record](POOL-TUNING.md), [pool-three receipt](postgrest-pool3-receipt.json).

## Resources, background work and isolation

64 database/route observations: maximum 13/60 connections, 4 active sessions and 0 lock waiters. Deadlock delta 0. Default route en0 in every observation: True. [Database and route samples](db-capacity-sequence-r13.json).

12 minute-cached host samples: available memory 177.9–246.3 MB; swap-in counter delta 89,958 pages. Host observer errors: 0. Paging is reported even if latency passes; this does not establish a hardware saturation ceiling. [Host samples](resources-capacity-sequence-r13.json). Samples are cached and sparse; counters are never reset.

11 completed natural worker executions observed; maximum 5.385 seconds. Controlled fixture backlog: 50 accounts, including five large libraries, requeued during sustained traffic; manual execution 162.409 ms. Natural cron remains enabled. `worker-large-profiles-r13.json` independently checks all five large profiles were computed after requeue; a manual call alone does not prove which accounts it processed. Worker time series and actual catalogue overlap are recorded separately.

`isolation-under-load-r13.json` records owner-positive and outsider-negative library/club probes and effective grants on five privileged RPCs. Worker grants and exact production identities are rechecked after cleanup. These scoped checks do not imply a complete security or native release audit.

## Earlier failures, cleanup and remaining limits

All earlier failures and alternative transport diagnostics are retained in [the pre-Ethernet report](REPORT-BEFORE-ETHERNET.md) and original raw files. The previous pool-six configuration passed 12,000 requests at 20 rps but failed burst/recovery. Later tests showed both real upstream stalls and separate downstream/client delays; Ethernet success alone would not isolate every prior cause. Do not interpret either local SQL speed or low upstream timing as full end-to-end capacity proof.

The first three cohorts are independently clean: 300 Auth identities and 15 clubs removed, with 41 user-bearing base-table checks per cohort and only intentional seven-day deletion barriers retained. Fourth cohort cleanup: **PASS**; see `cleanup-accounts-r4.json` / `cleanup-verification-r4.json`. Full acceptance requires this cleanup. No customer sweep is used; private fixture tokens are removed after deletion.

Nineteen focused harness tests pass; all eight source hashes and snapshots v1–v4 remain available. [Reproduction](README.md), [final live readback](final-live-state-r13.json). Source inventory remains 293 app Swift / 33 package Swift / 250 canonical SQL migrations; no iOS/TestFlight release was made.

This qualification does not establish cold-start limits, hours-long durability, much larger datasets, 100 permanently busy queries, distributed-region latency, native/device/CDN/Realtime/auth floods/poll mutations, provider saturation or paid narration. A changed workload or compute tier requires another measured qualification. Updated UTC: 2026-11-09T11:40:37.027411+00:00.
