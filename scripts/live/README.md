# Live disposable probes

These explicitly project-pinned entrypoints exercise **new disposable accounts only** on
`https://bkdifromsqxkndnllmdj.supabase.co`. They do not enable feature flags, deploy,
change settings, drive native UI, or mutate existing customer resources.

| Script | Checks |
| --- | --- |
| `probe_import_sessions_select_only.js` | Actual Apply creates one session/item; owner sees both, outsider sees neither; INSERT/UPDATE/DELETE on both tables require `42501`; rows stay unchanged; actual Undo removes the added list row |
| `probe_auth_api.js` | Real signup/password sign-in/refresh identity; scoped profile reads, authenticated outsider denial, unchanged data and actual PostgREST error body |
| `probe_account_storage.js` | Readable seed upload; held upload overlapping app deletion; same old-token denial; exact Auth/media and public-origin physical absence |
| `probe_club_activity_signals.js` | A joined member and owner receive an actual activity event; outsider does not; member receives own removal signal and cannot read/receive subsequent activity while owner supplies a positive control |

Run from the repository root with `SUPABASE_URL` and `SUPABASE_ANON_KEY`
(or existing `scripts/project_public.env`). Realtime also needs `@supabase/supabase-js`.
Use securely configured `SUPABASE_SERVICE_ROLE_KEY` for physical club-absence verification
and exact-ID emergency cleanup of a newly returned identity without a session. It is never
printed and never used for permission assertions. No need to paste keys into chat.

```bash
node scripts/live/probe_import_sessions_select_only.js
node scripts/live/probe_club_activity_signals.js
node scripts/live/probe_auth_api.js
node scripts/live/probe_account_storage.js
```

The Auth/API and Storage producers require securely supplied administrative Auth
and media cleanup access **before creating anything**. Preflight queries a random
nonexistent Auth UUID (recognized 404) and an empty random media prefix; it never
lists customer users. Missing access returns BLOCKED with no new resources.
All four producers cap each run at five accounts, five in-flight requests, five
request starts per second and 1,000 requests. Operations have bounded timeouts.
The Storage probe holds an upload body while app deletion dispatches, retaining
monotonic nanoseconds and wall-clock timestamps. Valid RLS refusals include an
outer HTTP 400 with body statusCode 403; arbitrary errors cannot count as denial.

On failure they stop subsequent business writes, still attempt scoped cleanup
and retain the exact inventory. Emergency cleanup removes only recorded newly
created IDs/object paths and leaves the verdict FAIL. Unknown signup identities
remain explicitly unresolved. Sanitized actual HTTP traces and signal events
are retained; passwords, tokens and full customer listings are removed. Server
refresh proof does not demonstrate native session restore. No hosted calls were
performed when implementing these producers.

The release evidence bundle contains four separately identified probe runs.
Journal uses two accounts, Realtime three, Auth/API two and Storage one. Each
run has its own timestamp/random run ID, request count and cleanup inventory;
the bundle is not one eight-account run. Run these sequentially so their
individual limits also bound the combined offered request rate. Do not start
parallel hosted probes without shared aggregate budgeting.

The old `KURO_LIVE_PROBE_ALLOW_OTHER` bypass is refused. URL lookalikes, userinfo,
non-HTTPS URLs, paths, queries and fragments fail before any sign-up.
Run IDs include random entropy. Resources are recorded before failure-prone steps;
request/body waits and subscription acknowledgments have deadlines. Channels are disposed
and account deletion runs in cleanup even when assertions fail. Known user IDs without a
session can be administratively cleaned, but that is not proof of the app deletion route.
An unknown/timed-out sign-up identity is explicitly reported for scoped follow-up.

The final sanitized JSON is emitted **after cleanup**:

- `PASS`, exit `0`: this probe's assertions and cleanup verification succeeded.
- `FAIL`, exit `1`: assertion, operation or cleanup failed.
- `BLOCKED`, exit `4`: assertions succeeded but required cleanup proof is unavailable.

Missing admin access makes physical club cleanup verification BLOCKED; member/nonmember
RLS invisibility is never counted as absence. A failed test with blocked cleanup stays FAIL.
Inspect its `cleanup` and `resources` arrays for exact follow-up, without a broad sweep.

Realtime revision/RLS evidence is reported separately and cannot replace event delivery.
Negative delivery observations use a bounded interval after an authorized positive control;
they do not claim indefinite non-delivery or native subscription teardown/account-switch proof.
The journal probe selects one existing catalog title read-only and modifies only its newly
created account's list. It uses the deployed Apply/Undo paths, not administrative journal inserts.

Offline boundary checks require no Supabase connection or keys:

```bash
node --test scripts/live/probe_checkers.test.js scripts/live/auth_storage_probes.test.js
```

These tests execute the actual probe logic with controlled external responses. They prevent
known false passes; they are **not hosted-service evidence**.
