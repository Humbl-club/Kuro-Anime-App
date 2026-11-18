# Reproducing the 100 active user backend test

Read [PLAN](PLAN.md), [REPORT](REPORT.md) and the deployment receipts. Production testing requires owner authorization. This initiative is authorized; future runs need their own approved window. Keep credentials in the existing secure environment, never commands, logs, reports or Git.

## Current qualification protocol

Use Node 22+ and the original connection-reusing `--transport=node`. Supply `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` securely for fixture operations. Put fixtures outside the repository in a private directory (0700 parent /0600 file). Administrative credentials are used only for setup/observation/cleanup; measured requests use one ordinary authenticated token per disposable account. No spoofed IPs or service-role workload calls.

```bash
# Fresh path for each new cohort; inventory precedes dependent writes.
node scripts/load/backend_fixture.js setup /absolute/private/path/fixture.json

node --test scripts/load/backend_workload.test.js scripts/load/backend_fixture.test.js scripts/load/backend_runner.test.js scripts/load/backend_transport.test.js

node scripts/load_test_backend.js --production --transport=node --fixture=/absolute/private/path/fixture.json --output=/absolute/report/path/warmup.json --vus=100 --rps=5 --duration=60 --stop-file=/absolute/private/path/STOP
```

Independently verify 100 server-tagged identities: 20 empty /50×25 /25×100 /five×2,000 titles; 13,750 list rows (9,650 anime /4,100 manga), five clubs and 50 memberships. Check each actual library against its declared size. Use current production catalogue IDs and retain fixture identity only in the private recovery inventory.

The unchanged resumed sequence is **5 rps/60 s →20 rps/600 s →40 rps/60 s →20 rps/90 s**, offering 16,500 starts. Change the example output, rps and duration for each stage. Stop escalation after any failed stage. The earliest investigation also used 2/5/10 rps short ramps; those are separate historical measurements. The runner rejects above 50 rps, 100 VUs, 600 seconds/stage or20,000 starts/stage. No automatic retries or mid-stage state resets.

Zero unexpected errors/timeouts and zero missed offered starts are mandatory. End-to-end p95 limits: Browse/Search/Clubs/Progress750 ms; Home/Detail1,200 ms; Discover/Mood1,500 ms; Parse/Recommend2,500 ms. Require all endpoint, library-size and medium gates, including sparse groups whose nearest-rank p95 equals the maximum. HTTP status alone is insufficient: responses and applied progress receipts must pass semantic checks. Empty users revisit Home; progress writes use anime. Club reads cover membership without seeded polls or rails. Narration is disabled to avoid paid AI/provider load.

Search/Browse encode medium in the RPC name, leaving their sample `medium` null. Supplement the runner using the pinned builder: `sequence % 3 === 0` means manga, otherwise anime; Progress always means anime. Cross-check recorded explicit media, hash the original stage JSON and apply the same endpoint limits to every group. See `derived-medium-check-r15.json`; do not edit samples to derive these checks.

## Observation and safety

Sample [MONITOR.sql](MONITOR.sql) approximately every ten seconds through an administrative read-only session or Management API with `read_only=true`. Stop new starts after two consecutive observations with ≥35 active sessions, ≥52 total connections, or >five lock waiters and oldest active query >five seconds. Stop after two monitor errors. The client independently stops for ≥three failures in its last50 completions (once20 exist) or ≥five replies above five seconds; each request has an eight-second deadline. Create the configured STOP file; let in-flight requests drain and retain the failed output.

Verify wired default route en0 before the measured sequence and during each database observation; route change must stop starts. R15's three observers initially saw R14's completed marker and restarted during warmup; their initial files are retained (database observations13.40 seconds apart). Sustained/burst/recovery observation uses the corrected sequence-specific marker. This warmup gap is disclosed in REPORT.md.

Keep natural cron enabled. During sustained traffic, requeue only 50 verified fixture identities, including all five large libraries, using the existing worker queue contract. Record the real worker execution and natural minute cron runs. Independently confirm all five large profiles updated after requeue; a successful manual drain does not prove which profiles it processed. Verify owner-positive /outsider-negative library and club reads plus five existing privileged-RPC revokes under load.

Collect host metrics approximately every60seconds, retaining provider cache caveats, swap/memory/I/O counters and errors. Never reset counters. Capture slow queries privately; publish only function references and hashes because SQL may contain identifiers or secrets. Separate independent HTTPS control latency from database timings. HTTP reports retain numeric Envoy `upstreamMs` and local `responseStartMs`; they omit other headers/tokens. Envoy timing covers upstream processing and its upstream network path, not the complete client path; low upstream time does not isolate the remaining delay to the local Mac. See [Envoy's definition](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/router_filter#x-envoy-upstream-service-time).

## Exact cleanup and production readback

After testing, including failed stages:

```bash
node scripts/load/backend_fixture.js cleanup /absolute/private/path/fixture.json
```

Setup/cleanup are capped at four request starts/second. Before deletion, the helper checks exact ID, server-set run tag, normalized email and token identity. It prefers the app's `delete-account` route; any exact-ID admin fallback must be recorded. Auth absence must read back404. It never lists or sweeps customer accounts. Keep the private inventory until cleanup is independently confirmed; the helper removes workload tokens after deletion.

Independently inspect the exact fixture Auth/club IDs and all public base-table `user_id` /`created_by` fields plus `profiles.id` (41 column checks on the measured schema). RLS invisibility is not physical absence proof. Existing seven-day account deletion barriers intentionally remain for stale-token protection. Retain sanitized account and physical-absence receipts only.

Finally recheck production health, five applied SQL statements against immutable source/history, current function versions/JWT verification, Auth settings, API pool three, worker math/source/server-only grants/minute cron, reviewed index readiness and advisor errors. Never retain the full `/postgrest` response: it contains a signing secret. Read back only whitelisted nonsensitive fields. The prior pool update's acknowledgement timeout and missing old-secret comparison remain disclosed in [POOL-TUNING](POOL-TUNING.md).

## Evidence boundaries and historical gotchas

Current eight JS source/test hashes are pinned in `workload-source-sha256.json`; 19 focused tests passed. Earlier source snapshots v1–v4, their hashes and every failed raw run are immutable. Recommend v55 has its own eight-file deployment closure, 26 focused tests, 36 before/after complete-response comparisons and downloaded production source proof. Those local comparisons do not prove live capacity.

The original baseline requested2,000 catalogue IDs in one REST read but received1,000 because of the API cap, leaving1,600-title large libraries. Later fixture code pages catalogue IDs and independently verifies2,000. GoTrue lowercases email addresses; provenance checks normalize case while preserving exact IDs/run tags. After an uncertain committed progress write, refresh owner revisions between sequences using `backend_fixture.js refresh`; never hide earlier conflicts or refresh mid-stage. No refresh was required between R14/R15: all progress writes returned applied receipts.

Optional `--transport=curl` was used only to diagnose earlier path delays. System curl8.7.1 uses fresh HTTP/2 connections, strict TLS, no redirects/retries and credentials via stdin. It includes process/handshake/body time; `responseStartMs` is a completion marker. Parent Node CPU excludes curl children. Keep those diagnostics separate from the original Node qualification.

Keep cold-call failures and all failed subgroups even after a later steady-state pass. A bounded local-generator production test does not establish cold-start limits, hours-long durability, larger registered datasets or concurrency, native/device/CDN/Realtime/auth floods/poll mutations, provider saturation, paid narration or whole-app release acceptance. A changed workload/configuration needs a fresh measured qualification.
