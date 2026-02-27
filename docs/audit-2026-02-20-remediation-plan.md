# Kuro Audit Remediation Plan (2026-02-20)

This plan is execution-ready and ordered for release recovery. It covers only current **P0/P1 blockers** from `/Applications/Kuro/docs/audit-2026-02-20-findings.md`.

- Release policy: block on P1+
- Current gate: blocked (P0=1, P1=1)

## 1) Blocking Backlog (P0/P1)

| Remediation ID | Finding | Severity | Owner | Status | Target |
|---|---|---|---|---|---|
| R-001 | F-001 Plaintext import secret in migration SQL | P0 | Backend owner | TODO | Immediate (same day) |
| R-002 | F-002 Deployed backend drift vs git source | P1 | Backend + release owner | TODO | Before next release cut |

## 2) R-001 — Rotate import secret + remove plaintext fallback

### Scope
- Remove plaintext `x-import-secret` literals from tracked SQL and prevent fallback to literals.
- Rotate production `IMPORT_SECRET` and invalidate exposed value.
- Re-seed pg_cron jobs to use DB settings only.

### Evidence
- `/Applications/Kuro/supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql:27`
- `/Applications/Kuro/supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql:34`

### Minimal safe patch
1. Create a new migration (`20260220xxxx_rotate_import_secret_and_reseed_cron.sql`) that:
   - verifies `current_setting('app.settings.import_secret', true)` is present (raise exception if missing),
   - unschedules and recreates all affected cron jobs,
   - uses only `current_setting(...)` for `x-import-secret` (no literal fallback).
2. Sanitize historical local SQL files in this branch (replace literal with settings-based expression or explicit placeholder comment).
3. Rotate function secret in deployed project.

### Deploy steps
1. Generate new secret:
   - `openssl rand -base64 32`
2. Update function secret:
   - `supabase secrets set IMPORT_SECRET='<new-secret>' --project-ref bkdifromsqxkndnllmdj`
3. Apply migration that re-seeds cron jobs with settings-based headers.
4. Confirm old secret rejected by protected functions.

### Rollback
- Keep previous migration-ready cron SQL and previous secret in secure incident vault only.
- If rotate causes job failures:
  1. re-set prior known-good secret with `supabase secrets set`,
  2. re-apply previous cron header config,
  3. reopen P0 and block release.

### Verification commands
- Secret exposure scan:
  - `rg -n "x-import-secret|IMPORT_SECRET" /Applications/Kuro/supabase/migrations`
  - must show no live literal secret values.
- Auth checks:
  - protected functions return `401` without/with old secret, and success with new secret.
- Cron header smoke:
  - run `/Applications/Kuro/scripts/check_cron_health.js` with service role env and verify enrich/import jobs execute.

### Tests to add/update
- Add CI secret scan gate for SQL migrations (`gitleaks`/custom regex).
- Add migration test that fails when secret fallback literal is present.

## 3) R-002 — Reconcile deployed migration/function artifacts into git

### Scope
- Ensure deployed production state is reproducible from git.
- Remove “deployed but untracked” drift before next release.

### Evidence
- `git status --porcelain` shows untracked critical files:
  - `/Applications/Kuro/supabase/functions/manga-source-review-action/`
  - `/Applications/Kuro/supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql`
  - `/Applications/Kuro/supabase/migrations/20260219153000_manga_chapter_enrichment_v1.sql`
  - `/Applications/Kuro/supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql`
  - `/Applications/Kuro/supabase/migrations/20260219235500_manga_review_approved_mapping_method.sql`
- Remote already has these IDs/function versions applied.

### Minimal safe patch
1. Add all deployed artifacts to version control with exact deployed behavior.
2. Commit with a dedicated “state reconciliation” commit.
3. Add CI gate to detect drift:
   - compare linked remote migration IDs with local migration filenames,
   - fail release if remote-applied IDs are absent from repo.
4. Add release gate requiring clean tree before deploy scripts.

### Deploy steps
1. Stage and commit reconciled files.
2. Run build + targeted tests.
3. Run remote migration/function list check in CI.

### Rollback
- If reconciliation commit introduces regressions:
  - revert reconciliation commit only,
  - keep production unchanged,
  - reopen release gate with blocking status.

### Verification commands
- `git status --porcelain` -> no untracked migration/function artifacts.
- `supabase migration list --linked` -> all remote IDs present locally.
- `supabase functions list --project-ref bkdifromsqxkndnllmdj` -> expected slugs align with tracked `supabase/functions/*` dirs.
- Fresh-clone smoke: project bootstrap and lint/build succeed without manual patching.

### Tests to add/update
- CI job: `scripts/quality-gates/check_remote_local_migration_sync.sh`
- CI job: ensure required function slugs exist in repo for all ACTIVE deployed functions.

## 4) Execution Order and Acceptance Gates

1. **Run R-001 first (P0)**
   - Exit gate: old secret invalidated + no SQL plaintext secret literals.
2. **Run R-002 second (P1)**
   - Exit gate: deploy/source reproducibility restored.
3. Re-run audit smoke suite:
   - iOS build/tests,
   - backend function auth/reachability,
   - cron health script with env.
4. Update release decision doc (`/Applications/Kuro/docs/audit-2026-02-20-release-gate.md`) from NO-GO to GO only when P0=0 and P1=0.
