# Concrete background-worker repair

Applied with explicit owner approval on 9 November 2026: `supabase/migrations/20261109003243_taste_worker_latency_v1.sql`.
SHA-256: `5ff1e8e3d0523e3b821e6a4933215a888417054b4b36afdcbae903f1851b0b96`.

The first sustained20rps sequence is retained as FAIL:2,819 completions from2,863 offered starts,54 timeouts and44 dropped starts. Its safety guard stopped new traffic. The failure overlaps cron run99466, `taste-profile-drain-15m`, 00:30:00–00:30:31 UTC. Interactive paths were fast until that overlap. The worker processes50 profiles per transaction; query stats confirm a30.918s maximum. One2,000-title fixture profile took1,650.746ms with JIT and532.936ms without it. Other fixture shapes also improve with JIT off. These controlled JIT-on/off comparisons do not establish production compilation overhead: the resumed audit found JIT already off globally and zero query-stat JIT counters. Cron overlap supports investigating background contention but does not isolate its cause. The worker-only R3 retry still failed; see POOL-TUNING.md.

The deployed forward change:

- Disable JIT on profile recomputation and its queue worker; profile mathematics/source remains unchanged.
- Keep the worker signature and poison-row behavior, but take at most five FIFO rows with `FOR UPDATE SKIP LOCKED`. Claiming the row ensures a concurrent signal cannot be lost behind the processed stamp, and concurrent workers skip claimed work.
- Change only existing job37’s schedule to once per minute, keeping its historical name, ID, owner, active state and exact SQL command. Full-batch capacity is nominally300 profiles/hour versus200 before; transactions are smaller. No user-facing feature, API shape, RLS, paid provider, Edge bundle or plan change.
- Restate the already-live server-only EXECUTE grants on both maintenance functions. Live checks confirmed anon/authenticated already denied; the first local grant assertion caught the fixture’s broader default ACLs, not a newly discovered live permission exposure.

Verification before approval: six worker assertions plus five real two-session concurrency assertions PASS. These cover FIFO/batch size, poison progress, skipping locked rows, and requeues surviving the worker commit. Four same-transaction real fixture vectors match exactly with JIT on/off; every diagnostic write rolled back. The first local failure and the corrected run remain retained. Historical whole-chain replay remains incomplete (203 applied/62 failed in the audited baseline fixture), separate from these targeted passes.

Deployment pinned the two existing definitions/grants/job properties, applied only this migration atomically with exact history, and verified source/math/grants and the preserved job fields. Qualification must rerun the full20rps ten-minute soak with a queued fixture backlog and real worker executions,40rps spike and20rps recovery. Keep the original failed sequence and query/cron overlap evidence. No blanket db push, disabled scheduler, or concealed failing run.

Rollback: restore only the saved worker definition/config and previous job schedule; retain server-only grants and the already deployed Search/Browse repair. Exact previous definition/settings and job command are privately retained. All disposable account/club resources still require verified cleanup, including on failure; deletion barriers are intentionally retained for stale-token protection under the existing seven-day policy.

Live application and exact history are confirmed in `worker-deployment-receipt.json`. Profile math body is byte-identical; both maintenance functions remain server-only; job37 retains ID/name/owner/active state/command and now runs once per minute. Capacity acceptance awaits the fresh full workload and exact cleanup.
