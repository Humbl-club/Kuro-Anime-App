# Kuro Senior Audit Findings (2026-02-20)

This report is evidence-first and ordered by severity.

## P0 Findings (Release Blocking)

### F-001 — Plaintext import secret is embedded in migration SQL

- **Severity:** P0
- **Confidence:** 0.99
- **Evidence:**
  - `/Applications/Kuro/supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql:27`
  - `/Applications/Kuro/supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql:34`
- **Repro steps:**
  1. Search repository for the import secret literal.
  2. Use that same value as `x-import-secret` when calling protected functions.
  3. Protected functions respond `200` with the exposed value and `401` without it.
- **Root cause:** cron fallback strategy hardcoded a live secret directly into SQL.
- **Why this is critical:** this secret gates operational mutation endpoints (`bulk-import-*`, `mirror-images`, `manga-chapter-enrich`, `manga-source-review-action`). Exposure grants privileged operations.
- **Fix proposal (smallest safe):**
  1. Rotate `IMPORT_SECRET` immediately.
  2. Remove plaintext secret fallback from SQL; require `current_setting('app.settings.import_secret', true)` only.
  3. Fail migration/job creation if secret is empty instead of falling back to a literal.
  4. Verify all previously exposed values are invalidated.
- **Test needed:**
  - Old secret returns `401` on all protected endpoints.
  - New secret returns expected responses.
  - Scheduled jobs continue to execute with DB setting-backed secret.

## P1 Findings (Release Blocking)

### F-002 — Deployment/source-of-truth drift: applied backend changes are not tracked in git

- **Severity:** P1
- **Confidence:** 0.96
- **Evidence:**
  - `/Applications/Kuro` git status includes untracked critical files:
    - `/Applications/Kuro/supabase/functions/manga-source-review-action/index.ts`
    - `/Applications/Kuro/supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql`
    - `/Applications/Kuro/supabase/migrations/20260219153000_manga_chapter_enrichment_v1.sql`
    - `/Applications/Kuro/supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql`
    - `/Applications/Kuro/supabase/migrations/20260219235500_manga_review_approved_mapping_method.sql`
  - Remote migration history already includes `20260219153000`, `20260219234000`, `20260219235500`.
  - Deployed function list includes active `manga-source-review-action`.
- **Repro steps:**
  1. Run `git status --short` in `/Applications/Kuro`.
  2. Run `supabase migration list --linked` and `supabase functions list --project-ref bkdifromsqxkndnllmdj`.
  3. Compare deployed state vs tracked source; the current wave is deployed but untracked.
- **Root cause:** production deployment occurred before source control finalized for same artifacts.
- **Impact:** rollback/recovery/reproducibility risk; teammate/CI cannot reliably reconstruct production behavior from git state.
- **Fix proposal (smallest safe):**
  1. Commit all deployed migration/function source with exact deployed content.
  2. Add CI gate: fail if `supabase migration list --linked` contains IDs absent from tracked files in release branch.
  3. Add deployment gate requiring clean working tree for migration/function deploy jobs.
- **Test needed:**
  - Fresh clone reproduces local schema/function state without manual patches.
  - CI gate fails when deployed IDs are missing locally.

## P2 Findings

### F-003 — Documentation inventory counts are stale vs current state

- **Severity:** P2
- **Confidence:** 0.93
- **Evidence:**
  - `/Applications/Kuro/CURRENT_APP_STATE.md:176` says migrations count is `104`; current local SQL files are `131`.
  - `/Applications/Kuro/CURRENT_APP_STATE.md:277` says edge function count is `14`; deployed active functions are `15`.
- **Repro steps:**
  1. Read counts in `CURRENT_APP_STATE.md`.
  2. Compare with `find supabase/migrations -name '*.sql' | wc -l` and `supabase functions list`.
- **Root cause:** hand-maintained counts not auto-generated and drifted after recent waves.
- **Fix proposal (smallest safe):**
  1. Auto-generate inventory counts in docs update script.
  2. Remove hardcoded count labels if exact numbers are not generated at update time.
- **Test needed:**
  - Docs lint job verifies declared counts equal measured counts.

### F-004 — `manga-source-review-action` approve path is not atomic

- **Severity:** P2
- **Confidence:** 0.74
- **Evidence:**
  - `/Applications/Kuro/supabase/functions/manga-source-review-action/index.ts:103-130`
  - Mapping upsert and review status update are separate operations with no transaction boundary.
- **Repro steps:**
  1. Observe two-step write sequence (`manga_source_links` then `manga_source_link_review`).
  2. If second write fails, mapping persists while review row remains pending.
- **Root cause:** business transaction split across two independent writes in edge function.
- **Impact:** inconsistent admin state and ambiguous retries for review actions.
- **Fix proposal (smallest safe):**
  1. Move approve/reject to a single SQL RPC transaction (`security definer`).
  2. Return typed result envelope from RPC.
- **Test needed:**
  - Integration test injects a failure between writes and validates atomic rollback.

### F-005 — Ops smoke script is not self-runnable without privileged env bootstrap

- **Severity:** P2
- **Confidence:** 0.83
- **Evidence:**
  - `/Applications/Kuro/scripts/check_cron_health.js:27`
  - Runtime failure: `Missing SUPABASE_SERVICE_ROLE_KEY env var.`
- **Repro steps:**
  1. Run `node /Applications/Kuro/scripts/check_cron_health.js` in a default shell.
  2. Script hard-fails before checks.
- **Root cause:** required environment bootstrap is not encapsulated in a local runnable wrapper for audit/release checks.
- **Impact:** reduces reproducibility of release verification and handoff audits.
- **Fix proposal (smallest safe):**
  1. Add `/Applications/Kuro/scripts/check_cron_health.sh` that loads `.env.local`/CI vars.
  2. Add a degraded anon-mode check path with clear warning.
- **Test needed:**
  - Script succeeds in both full (service-role) and degraded (anon) modes with explicit status output.

## P3 / Previously Reported Finding Check

### F-006 — Prior P3 add-to-rail string matching issue is resolved

- **Severity:** Informational
- **Confidence:** 0.97
- **Evidence:**
  - `/Applications/Kuro/Kuro/Views/ClubDetailView.swift:1811-1866`
  - Error handling uses typed `PostgrestError` + enum mapping (`AddRailItemErrorCode`) and no `msg.contains(...)` parsing.
- **Outcome:** no action required for this specific prior finding.
