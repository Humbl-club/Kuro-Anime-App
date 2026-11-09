# Production remediation receipt — 9 November 2026

User authorization: deploy the backend fixes and auth settings to production, verify live, and update repository documentation. Target: `bkdifromsqxkndnllmdj` (`eu-central-1`). This is backend delivery; the Discover client fixes remain local. Local Berlin date is 9 November; deployment timestamps below are UTC on 8 November.

## Deployed identities

| Function | Previous | Active version | JWT verification |
| --- | ---: | ---: | --- |
| bulk-import-anime | 86 | 87 | on |
| bulk-import-manga | 84 | 85 | on |
| concierge-parse | 48 | 49 | on |
| concierge-recommend | 53 | 54 | on |
| concierge-resolve | 19 | 20 | on |

All 36 source/dependency entries downloaded from production match the reviewed SHA-256 manifest. Recommend/Resolve were deployed before the privilege revokes; Resolve remains dormant. CLI 2.78.1 used the Management API deployment path with JWT verification retained. The connected MCP denied project access; existing CLI authentication supplied the authorized fallback.

| Migration | Applied UTC | SHA-256 |
| --- | --- | --- |
| 20261108120159_review_security_v1 | 2026-11-08 23:49:11 | `9b415eddaee9cdd61c23bcc4f42f6cd9971e74371a39d66a7a0300ab9717162d` |
| 20261108120211_catalog_intake_schedule_v1 | 2026-11-08 23:50:11 | `2a54ec1f1a87c8a35d75259d0d11248ac55e3636bc4e00028cd56f6757dac1cd` |

Each approved migration and its exact source text were recorded atomically in `supabase_migrations.schema_migrations`. Postflight history hashes match. Only these two migrations were applied; no blanket push, historical replay, or migration-history repair. Their byte-identical files now live in `supabase/migrations/`; historical PREPARED headers are retained because applied SQL must not be edited. `approved-manifest.json` preserves the original approval inputs; `../manifest.json` maps current canonical paths. The pending registry was reconciled against live history. The older `20261101030000_auth_hardening` identity is absent and superseded by the new email-oracle revoke, not falsely marked applied.

## Live behavior

All **19 HTTP checks** passed; the disposable account was then deleted through `delete-account` and independently read back as 404. No verification email or paid AI call was requested.

- Anonymous calls to all five privileged RPCs return 401 / SQL 42501; authenticated calls return 403 / 42501. Effective grants are false/false/true for anon/authenticated/service_role, including inherited PUBLIC permissions.
- A service-role SQL transaction successfully exercised the rate helper, empty recommendation-graph write, global budget reserve/finalize and nonexistent-email lookup, then rolled back every write. These establish server access without retaining synthetic quotas or graph data.
- Six-character and known-breached passwords return 422 `weak_password`. A fresh strong-password account signs in successfully.
- Authenticated Parse returns candidates with matching verified identity; deterministic Recommend returns nonempty results without narration. Dormant Resolve authenticates and returns an empty selection without provider work.
- Both catalogue importers reject a missing import secret with 401.

## Catalogue execution

The same four job IDs, active states, postgres owners, schedules, endpoint/credential strings and request counts were preserved. Only each body expression changed. The names ending in `weekly` are historical: their actual schedules are hourly.

| Existing job | Schedule UTC | Manual verification run | Titles | Errors |
| --- | --- | ---: | ---: | ---: |
| kuro-import-anime-hourly (101) | `5 * * * *` | 43616 | 50 | 0 |
| kuro-import-anime-weekly (102) | `0 * * * *` | 43615 | 10 | 0 |
| kuro-import-manga-hourly (103) | `35 * * * *` | 43618 | 50 | 0 |
| kuro-import-manga-weekly (104) | `10 * * * *` | 43617 | 10 | 0 |

These were bounded executions of the exact stored job commands, not fabricated scheduler outcomes. At UTC hour 23, the light tracks selected `popularity_core`; heavy tracks selected `airing_or_releasing`. Four independent cursors persisted success at pages 2/1. Anime heavy wrote **50 voice-actor links**; cast data reached 10,252 links with refresh timestamp 23:53:56 UTC. A read-only evaluation across all 24 UTC hours confirms four light presets and three heavy presets, the 50/10 title limits, and heavy-anime voice-actor refresh. This does not establish completed catalogue coverage, observed MAL collision recovery, declining unknown airing counts, every preset's upstream response, or load capacity. Those need continued measured runs.

The next autonomous cron execution also passed: anime heavy backfill run `43619`, 2026-11-09 00:00:02–00:00:25 UTC, 10 titles, 112 voice-actor writes and zero errors. This independently confirms the real scheduler path beyond the four manually triggered existing commands; the other rotating upstream presets and load capacity still need measurement. Evidence: `natural-schedule-observation.json`.

## Auth readback and API exception

Confirmed live: `password_min_length=8`, `password_hibp_enabled=true`, `site_url=kuro://auth/callback` with the stray leading space removed. Redirect allow-list, email auto-confirm choice, SMTP settings and other writable settings were preserved.

**Exception:** the auth PATCH also changed the read-only `custom_oauth_max_providers` result from 3 to 32,767. A bounded restore attempt was accepted but ignored. The current official OpenAPI schema includes this field in GET output and omits it from PATCH input; there is no documented setter. Custom OAuth remains **disabled**, and no plan change was requested. This provider-managed output could not be restored through the documented API; it is explicitly unresolved rather than reported unchanged. Evidence: `auth-after.json`, `auth-schema-evidence.json`; official [GET auth configuration](https://supabase.com/docs/reference/api/v1-get-auth-service-config) and [PATCH auth configuration](https://supabase.com/docs/reference/api/v1-update-auth-service-config).

## Health, recovery and limits

The project read back `ACTIVE_HEALTHY`, all five functions ACTIVE, and zero other active queries older than 30 seconds at final postflight. Security and performance advisors reported no ERROR entries; existing warnings remain (including other executable SECURITY DEFINER RPCs, 35 RLS tables without policies, one mutable search path, materialized views, and index/connection recommendations). The leaked-password warning disappeared. This is a scoped remediation, not a complete security clearance.

The latest completed physical backup observed before deployment was **2026-11-08 05:49:42.686 UTC** (backup 2201552266); PITR was already off. Previous function bundles, auth state and exact job commands are retained privately with restricted permissions for rollback, outside the repo. Do not publish their credentials. Prefer reverting job bodies/function revision if needed while retaining the security revokes.

The prior local 29 native / 127 Deno / 29 SQL assertion passes remain scoped evidence. No new iOS binary, TestFlight upload, App Group registration, Resend credential change, licensing approval or public release occurred. Legacy whole-chain migration replay gaps, full release-evidence gates and device qualification remain open. Local source checks do not replace those outcomes.

## Evidence index

- `preflight.json`, `final-postflight.json`: sanitized project, auth, function and health snapshots.
- `deployed-source-verification.json`, `approved-manifest.json`: deployed closure hashes and approval inputs.
- `applied-*.json`, `migration-history.json`: exact migration receipts and read-only history.
- `effective-grants.json`, `service-role-checks.json`, `http-smoke.json`: privilege and real request outcomes.
- `cron-after.json`, `manual-intake-checks.json`, `intake-progress.json`, `intake-cursors.json`, `rotation-live.json`, `cast-after.json`: preserved job properties and actual importer results.
- `auth-after.json`, `auth-schema-evidence.json`, `advisors-after.json`: settings exception and remaining warnings.

Final repository checks: current-state docs PASS (293 app Swift / 33 package Swift / 247 migration SQL); source secrets gate PASS (0); credential scan of public evidence PASS; all 39 manifest entries match; staged/unstaged whitespace PASS. The migration gate records only the two newly staged migration files as its warning; all pre-existing checksums are unchanged, and the two new checksums match deployed history. No app/function source changed after the recorded local suites. See `local-final-checks.json`.
