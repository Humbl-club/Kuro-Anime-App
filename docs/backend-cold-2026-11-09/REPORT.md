# Cold-start repair and production attempt — 9 November 2026

**Fix deployed; 100-user cold-start qualification remains OPEN / UNQUALIFIED.** The one authorized production restart was performed. The first successful healthy/new-postmaster observation already contained **727 public/associated-TOAST buffers**, so the required empty-buffer condition was not established. **Zero load-test starts were offered.** There was no second restart, cache eviction, relaxed limit or retry to obtain a pass.

The later six-request functional smoke succeeded, but its first Manga Search took **1,632.90 ms against the unchanged750 ms budget**. It is not a latency pass. It ran after the failed cold attempt, during fixture cleanup, with no verified cold state or measured upstream-time breakdown. Neither the server contribution nor a specific cause of this timing is established. The prior warmed R15 acceptance remains a dated result for its narrower original routing; it does not prove this broader workload or cold-start capacity.

## What is live

Explicit authorization is recorded in [approval-receipt.json](approval-receipt.json). Exact migration `20261109123758_cold_catalogue_reads_v1` is applied atomically and its stored statement matches the immutable source SHA256 `c1acc7f38a955b87a66b4283f0369ca35a897b75c6efde6f33010aa47b9c9278`. It was promoted to canonical migrations only after history verification; its original “PREPARED” SQL comment is retained because applied statements are immutable. Canonical SQL count is251.

The migration adds four partial indexes matching the actual Discover materialized-view eligibility/order and one medium/realm covering index with `weight>=0.25`. The two Search functions now set trigram candidate threshold0.35, matching their existing final acceptance bound. All six reader bodies, signatures, return types, SECURITY DEFINER attributes and ACLs compare unchanged. New indexes occupy **9,035,776 bytes** at deployment; all five new and all20 earlier performance indexes remain valid/ready. [Deployment receipt](deployment-receipt.json), [25-index readback](final-index-readiness-cold1.json).

Fresh post-restart comparison again verifies all six reader bodies/security against the saved pre-deployment definitions. Five bounded read-only production inner-query plans select all five new indexes without forced planner settings: four30-item rails use30/25/32/32 root buffer accesses (0.132/0.154/0.160/0.183ms execution); the cozy realm aggregation uses26 (2.475ms). These are post-cleanup inner SQL diagnostics, not whole-RPC, cold or concurrent HTTP timing. Refresh/WAL overhead under scheduled refresh was not measured. [Plans](post-deployment-inner-plans.json), [reader parity](final-reader-parity.json).

Parse **v50** and Recommend **v56** were deployed from isolated, unchanged eight-file source closures. All16 downloaded entries matched their approved hashes; JWT checks remain enabled and the other functions compare unchanged. No narration was paid for. [Source/deployment receipt](edge-redeployment-receipt.json).

Final owning-service readback confirms **ACTIVE_HEALTHY**, pool3, unchanged selected Auth settings, unchanged worker math/body/server-only grants and minute cron, exact six reviewed migration statements, Search settings0.35, no long queries or lock waiters, and no security/performance advisor ERRORs. Existing advisor warnings remain: this is not an all-warnings remediation. No compute, billing, credentials, feature flags or native release changed. [Final live state](final-live-state-cold1.json).

## Actual restart and why the attempt is unqualified

| Observation | UTC / result |
|---|---|
| Single restart request |14:07:11.167547; request count1 |
| New postmaster |14:07:47.716686; old postmaster was4 August |
| First successful healthy/new-postmaster/cache probe started |14:08:14.324913;727 target buffers already resident |
| Later full relation metadata |14:09:02.891289;4,834 target buffers; explicitly a later snapshot |
| Cold soak / burst / recovery |NOT RUN;0/16,200 planned load starts |
| Post-abort functional smoke |6/6 HTTP200 with semantic checks; not cold or capacity proof |

The63.16seconds from request to the first successful probe's start is an **observation interval, not an exact outage duration**. The response timestamps and earliest actual service recovery were not captured. The API returned a non-JSON/empty restart acknowledgement; a new postmaster and healthy services establish that the restart happened, without resending it. [Original/reconciled receipt](restart-receipt.json), [attempt verdict](cold1-sequence.json), [first count provenance](cold-state-at-readiness.json).

Two avoidable harness compatibility failures impaired early observation. The provider rejected the documented optional `timeout_ms` query parameter because it received a string; the continuation omitted it and contained no restart operation. Python3.9 then rejected the historic PostgreSQL timestamp's five-digit fraction/short timezone form. The retained polls still recorded healthy services, the new postmaster and727 buffers; the primary stopped the continuation and reconciled those receipts rather than launching load or restarting again. The exact first cache-response timestamp/full relation breakdown was not persisted; only the first poll's count/start timestamp survives. [Executed sources and limitations](executed-harness/README.md).

A natural taste-worker run overlapped restart/readiness at14:08:00, succeeded in0.706seconds and preceded the first successful buffer observation. It is evidence of background activity, **not proof that it caused every cached block**. Cron was never disabled or rescheduled. There was no zero-buffer-to-onset interval to qualify. [Cron evidence](cron-during-restart-readiness.json). PostgreSQL shared-buffer observations never establish an empty OS/storage cache.

Before any functional smoke, the provider query returned no recorded boot/execution events for the two new Edge versions in the observed window. There was no measured load onset with which to correlate boot evidence. Edge-isolate cold qualification therefore remains **UNPROVEN**, independently of the database precondition. [Pre-smoke event receipt](edge-events-after-attempt.json). Later single-user function responses cannot repair this missing cold-load proof.

## Safety, functional checks and cleanup

The approved cache inspector needed a narrower namespace boundary on this managed platform. The original1.5 installer rolled back because Supabase's extension owner retained PUBLIC EXECUTE on its superuser-guarded eviction function; requesting1.4 also rolled back after the platform actually installed1.5. No roles, ownership, credentials or memberships were escalated. The successful inspected1.5 lived in a fresh private `kuro_cold_inspection` schema, outside Data API schemas/search path. Both client roles lacked schema USAGE/CREATE, view SELECT and the three read-function grants; four actual client-resolution probes failed at that namespace. The eviction function's underlying EXECUTE ACL bit remained true, but clients could not resolve it and it was **never invoked**. [Actual isolation receipt](inspector-install-receipt.json), [adaptation and hashes](inspector-private-schema-adaptation.json), [native managed-grantor tests](private-inspector-tests.log).

After the attempt, both the extension and its experiment-owned schema were removed with **RESTRICT**, and independent readback confirms both absent. [Removal receipt](inspector-removal-receipt.json). No cache-eviction operation occurred.

The sixth fixture was independently verified before restart:100 ordinary identities,20 empty/50×25/25×100/five×2,000 saved-title libraries,13,750 rows, five clubs/50 memberships across all four library sizes. [Shape](fixture-final-shape-r6.json). Every new identity was removed through `delete-account`, with Auth404 readback; no administrative deletion fallback was needed. Five exact clubs are absent;41 user-bearing base-table columns contain no unexpected fixture rows. Tokens are removed. Only the existing100 seven-day deletion barriers intentionally remain for stale-token protection. A fresh combined audit also verifies **all600 identities/30 clubs across six cohorts absent**, with no tokens or unexpected application rows;600 existing security barriers are retained. [Sixth cleanup](cleanup-verification-r6.json), [all-cohort cleanup](cleanup-verification-all-six-cohorts.json).

Six bounded post-abort requests used an ordinary fixture JWT: Manga/Anime Search, Discover, Mood, Parse and Recommend all returned200 and passed semantic checks. Manga Search1,632.90ms exceeded750; the other individual calls were within their respective limits. No percentile or concurrency claim follows from six sequential requests. [Raw functional timings](post-abort-functional-smoke.json).

Independent pre-run review caught and corrected JSON output parsing and a safety-monitor watchdog gap. Offline isolated execution confirmed the evaluator JSON roundtrip and that two failed route checks STOP without refreshing the successful heartbeat. The primary monitor uses6second SQL and3second route timeouts; the controller stops on25second stale complete-sample heartbeat. All observers were armed but remained behind the load marker; all exited without load when DONE was written. The review did **not** catch the provider/timestamp compatibility failures. That coverage gap is retained rather than erased. [Offline checks](controller-preflight-checks.json).

## Earlier supporting evidence and its limits

- **79 native PostgreSQL assertions PASS** on64,000 synthetic catalogue rows/256,000 realm rows, including ordered parity, exact fuzzy boundary, concurrent refresh and all five indexes. Two actual local restarts observed zero catalogue buffers. Local rail block accesses119→32,421→32,132→32,369→9; realm44,436→206. These are local plans, not production capacity. [Results](local-results.json), [successful log](local-catalogue-r7.log), [reproduction](run-local.sh). Earlier failed iterations remain.
- Existing focused SQL suite:5 assertions including74 differential Search/Browse cases PASS. Historical baseline-first replay remains **INCOMPLETE**,205 applied/62 failed. [Focused evidence](final-focused-sql.log).
- **14 counterbalanced read-only production Search comparisons** preserved ordered hashes/counts across thresholds. The effect varies by query; they do not establish cold-user latency. [Evidence](live-read-only-search-parity-counterbalanced.json).
- **27 offline Node tests PASS**. Broader deterministic routing now covers all six mood/media combinations and large members' club bundles; the old eight measured sources/hashes are preserved. Cold gates require20 first-minute routes,39 endpoint/library groups, all79 combined cells and each cell's first call within its unchanged budget. These gates were **not executed against production load** because the precondition failed. [Tests](final-node-tests.log), [planned coverage only](planned-routing-coverage.json).

## What remains open

The cold-call latency repair has implementation/local-plan evidence and deployment proof, but **no production latency or100-active-user cold-start PASS**. Cold soak, burst, recovery, under-load worker/backlog/isolation and Edge boot correlation are all NOT RUN, not successful zero-sample checks. The original750/1,200/1,500/2,500ms limits, zero-error/missed-start requirement and safety caps remain unchanged.

A further attempt needs a corrected, independently reviewed controller with offline PostgreSQL timestamp cases, the exact supported health URL/schema preflight, bounded readiness I/O and strict deadline checks. Its plan must explicitly address background/client interference before claiming empty buffers, and retain real background work during the measured workload. Any further production restart or cron changes need new explicit authorization; the original one-restart allowance is consumed. No additional hosted changes are pending or silently scheduled.

The exact original [approved plan](DEPLOYMENT-AS-APPROVED.md) and [prepared report](REPORT-PREPARED.md) are retained as historical evidence. Current outcome is summarized in [DEPLOYMENT.md](DEPLOYMENT.md); the final evidence review/check receipt is recorded separately.

## Final repository checks and independent review

Matched documentation, policy, secrets, source/archive/inspector/harness hashes and whitespace checks pass. Migration hygiene exits0 with one warning for the newly staged canonical source; exact applied bytes/history/checksum match. The reproduction runner now uses that canonical path and passes syntax/existence checks; unchanged79SQL/27Node suites were not rerun. A concurrent Swift addition briefly failed the inventory gate; its log is retained and the final294app/44package/251SQL inventory passes. Existing policy/app edits and branch were preserved; no commit, push or native release was performed.

The independent reviewer accepts **evidence accuracy only**, explicitly not cold capacity. It independently compared six immutable SQL statement MD5s,25 index states and all six saved reader-body hashes, and verified cleanup/inspector absence from the saved receipts. [Review](independent-review-execution.json). Fresh Auth/REST owning-service checks are healthy. [Current post-attempt checks](post-attempt-final-checks.json) and [machine-readable failed/not-run verdict](cold1-verdict.json) are authoritative for this attempt. The older `final-verification.json` is the13:07preapproval historical snapshot, not current production state.
