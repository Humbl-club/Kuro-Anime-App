# Kuro review remediation release

Status: backend deployed and live-verified with explicit owner approval on 9 November 2026; client changes remain local on `codex/review-remediation-20261108`. One auth API read-only-field exception remains recorded. [Production receipt](live-2026-11-09/RECEIPT.md).

## Changes

- Close client EXECUTE, including inherited PUBLIC and direct anon grants, on the recommendation graph writer, rate-bucket helper, both global AI budget writers and the email-existence oracle. Keep server access and intended public read RPCs.
- Recommend and dormant Resolve use a separate service-role client for global accounting. Caller identity, private reads and per-user budgets remain on the caller client. A missing server credential prevents paid work. Caller clients in Recommend, Resolve and Parse cannot fall back to service-role credentials.
- Discover persists pending feedback and Undo per account, restores it after relaunch, keeps retrying through outages, and removes acknowledged work. Storage is capped at 300 durable signals and 30 days, alongside the existing 50 ephemeral deck hints. A server reconciliation recovers unacknowledged overlays from older builds; explicit acknowledgments prevent replay after a lagging read. Account deletion removes pending disk state.
- A MAL-id collision retries the primary catalogue write once without claiming the conflicting alias. The AniList identity and existing MAL owner stay separate. Other errors still fail the page. Run metrics count conflicts and retain at most ten public identifier samples for investigation.
- Four existing cron slots retain their schedules, credentials and request bounds. Light jobs rotate new titles, recent updates, airing/releasing and popularity; heavy jobs rotate backfill, updates and airing/releasing. Separate cursor keys prevent heavy/light page-size interference. Heavy anime requests include voice actors and bypass the unchanged-source shortcut. No placeholder chapter/volume fan-out.
- The recommendation-edge operator script requires a server credential rather than a user JWT.

## Bounded work

Light runs fetch at most 50 titles, heavy runs at most 10, with a 55-second budget. No cron jobs are added. Conflict retries add no request to successful writes and at most one retry to a conflicting write. Existing AniList pacing remains in force. This bounds the changed paths; it is not a claim of qualified throughput at an arbitrary user count. Large-list query plans and capacity evidence remain separate release work.

## Deployment sequence (completed with approval on 9 November)

Target: Supabase project `bkdifromsqxkndnllmdj` only. Do not run a blanket `db push --include-all`; historical prepared files include already-applied and unapplied work.

1. Record a fresh backup point, effective grants, auth settings, the four cron schedules, and current function versions. Never log cron commands or secrets. Check the manifest hashes against the reviewed files.
2. Deploy `concierge-recommend` and `concierge-resolve` first, preserving JWT verification. This moves global accounting to the server role before client grants are removed. Resolve stays dormant; no flag is enabled.
3. Apply `supabase/migrations/20261108120159_review_security_v1.sql` and record its version/name/file text in migration history using the project's established convention, atomically with the change. This also closes the outstanding email oracle; do not reapply historical migrations.
4. Deploy `bulk-import-anime`, `bulk-import-manga` and `concierge-parse`, preserving JWT verification. Parse receives the repository's fail-closed limiter implementation identified as absent from production during review.
5. Apply `supabase/migrations/20261108120211_catalog_intake_schedule_v1.sql` and atomically record history. It changes only the four existing job bodies; unexpected or partially configured jobs abort the transaction. It is idempotent.
6. PATCH auth configuration with `auth-settings.patch.json`: minimum length 8, breached-password protection on, and the existing custom-scheme site URL with its stray leading space removed. Preserve email-confirmation choice, SMTP, redirect allow-list and all unrelated settings. Do not upgrade the plan if the protection is unavailable; report that boundary.
7. Run `VERIFY.sql` read-only, read back the three auth fields and deployed function source, then observe actual scheduled import outcomes. Confirm separate track cursors advance, voice actors refresh, MAL conflicts no longer pin pages, and unknown airing-title counts decline. New/recent/airing tracks run over subsequent slots; one successful run is not full catalogue coverage.
8. An iOS release is separate: install and qualify the durable-feedback build before uploading to TestFlight. No App Group registration, TestFlight upload, public release, external message or credential rotation is included in backend approval.

## Rollback

Record previous function bundles and job definitions securely before deployment. Revert intake job bodies or redeploy the reviewed function revision if needed. Keep the security revokes in place; restoring anonymous privileged writes is not an acceptable rollback. If narration becomes unavailable, leave its deterministic recommendation fallback active while repairing the server accounting path. Auth settings require a separately reviewed change if rolled back.

## Verification

Local results below are the 8 November pre-deployment record. Production verification is now recorded in [the live receipt](live-2026-11-09/RECEIPT.md): 19 HTTP checks, matching deployed source/history, effective grants and four actual bounded import runs passed. PostgreSQL fixture checks have historical replay gaps; no clean-rebuild or whole-app/device acceptance is claimed. The OAuth-limit exception and measured-capacity work remain open.

## Remaining owner inputs

Resend notification credentials and delivery proof; App Group registration and physical widget checks; legal/domain approval; data-source licensing decisions. Existing compiler warnings outside these changed paths and the blocked live-service release-evidence gate remain visible. No automatic claim of App Store readiness is made.


Historical local checks before deployment (8 November 2026): 29 iOS tests in four affected suites PASS on iPhone 17 Pro / iOS 26.2, including parameterized outage/Undo cases, legacy recovery and acknowledged-write crash recovery; unsigned app/test build PASS, with no warnings in the changed Taste/Discover data files. Deno: 127 tests across six affected suites PASS; every selected entrypoint typechecks. SQL fixture: three selected files, 29 assertions PASS; both prepared migrations apply in the audited baseline fixture. Historical full replay remains INCOMPLETE (baseline-first 201 applied / 62 failed; strict 154 / 109), so no clean-rebuild claim. Architecture, navigation, branded states, secrets, documentation, migration hygiene and git diff whitespace checks PASS; operator script syntax PASS. manifest.json pins 36 function source/dependency entries plus the two migrations and auth patch. The first native test attempt stalled before execution; the successful run used the explicitly booted iPhone 17 Pro destination. No production write, key rotation, upload or external message occurred during that local preparation initiative. The subsequently authorized backend deployment is recorded above.

## Production result — 9 November 2026

Both approved SQL files were promoted byte-for-byte to the canonical migration directory after application; manifest paths now reflect that move, and the original approval manifest is preserved in the live evidence folder. Five function versions are ACTIVE with JWT checks retained. The three requested auth settings are verified, including actual weak/breached password denial and successful valid sign-in. Four manual executions of existing stored cron commands completed with zero errors; all four cursors persisted independently. Existing schedules/credentials were preserved. Live coverage does not yet include every rotating upstream preset or a real MAL conflict; observed unknown airing counts and load qualification remain future measurements. The API’s additional read-only OAuth limit change could not be restored; Custom OAuth remains disabled. See the receipt for the exact evidence, limits and rollback record.

The next autonomous cron execution also passed: anime heavy backfill run `43619`, 2026-11-09 00:00:02–00:00:25 UTC, 10 titles, 112 voice-actor writes and zero errors. This independently confirms the real scheduler path beyond the four manually triggered existing commands; the other rotating upstream presets and load capacity still need measurement.
