# Kuro Release Gate Decision (2026-02-20)

This document is the release decision for the audit run captured in:
- `/Applications/Kuro/docs/audit-2026-02-20-manifest.md`
- `/Applications/Kuro/docs/audit-2026-02-20-findings.md`
- `/Applications/Kuro/docs/audit-2026-02-20-remediation-plan.md`

## Gate Policy

Release is allowed only if all are true:
1. P0 findings = 0
2. P1 findings = 0
3. P2/P3 findings are triaged (owner + due date)

## Current Finding Counts

| Severity | Count | Gate impact |
|---|---:|---|
| P0 | 1 | Blocking |
| P1 | 1 | Blocking |
| P2 | 3 | Non-blocking (must be triaged) |
| P3/Info | 1 | Non-blocking |

## Blocking Findings Snapshot

| ID | Title | Status | Evidence |
|---|---|---|---|
| F-001 | Plaintext import secret embedded in migration SQL | Open | `/Applications/Kuro/supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql:27`, `/Applications/Kuro/supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql:34` |
| F-002 | Deployed backend artifacts not tracked in git | Open | `/Applications/Kuro` git status + remote migration/function lists |

## Decision

**NO-GO** for release and TestFlight promotion.

Reason: release blockers are still open (P0=1, P1=1).

## Exit Criteria to Flip to GO

All of the following must pass:
1. R-001 complete:
   - old import secret invalidated,
   - no plaintext live secret in migrations,
   - protected functions reject old/missing secret.
2. R-002 complete:
   - deployed migration/function artifacts committed and reviewed,
   - no deploy/source drift.
3. Verification rerun passes:
   - `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build`
   - targeted tests in `KuroTests` and `KuroUITests`
   - function auth smoke + cron health script with env.
4. P2/P3 triage recorded with owner/due date.

## Re-Verification Checklist

- [ ] Build/test logs attached to release PR
- [ ] Secret-rotation evidence attached (401 old secret, success new secret)
- [ ] Migration/function sync evidence attached
- [ ] Updated findings status (`Open` -> `Resolved`) in findings doc
- [ ] Gate re-signed by backend + iOS owners

## Optional TestFlight Readiness (after GO)

1. Run Fastlane lane for beta build/upload.
2. Attach release notes summarizing only user-visible fixes.
3. Confirm backend migration/function versions in release notes appendix.
