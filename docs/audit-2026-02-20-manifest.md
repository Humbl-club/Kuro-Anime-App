# Kuro Senior Audit Manifest

- Audit date (UTC): 2026-02-19T23:19:32Z
- Repository: `/Applications/Kuro`
- Branch: `main`
- HEAD: `6cc354aa34237104024912fd38debd368416a9bd`
- Audit scope: full stack (iOS + Supabase + cron + docs)
- Release policy: block on P1+

## 1) Baseline Snapshot

### Git state (captured at audit start)

- Dirty file count: `171`
- Working tree is mixed across iOS, functions, migrations, scripts, and docs.
- High-impact untracked artifacts in current release wave:
  - `supabase/functions/manga-source-review-action/`
  - `supabase/migrations/20260219153000_manga_chapter_enrichment_v1.sql`
  - `supabase/migrations/20260219234000_fix_manga_chapter_enrich_cron_secret.sql`
  - `supabase/migrations/20260219235500_manga_review_approved_mapping_method.sql`
  - `supabase/migrations/20260219003703_cron_cleanup_and_mirror_auth.sql`

### File/domain inventory (captured at audit start)

- Swift files: `60`
- Edge function directories (including `_shared`): `16`
- Migration SQL files: `131`
- Docs markdown files in `/Applications/Kuro/docs`: `6`

### Post-audit artifact delta

- Added audit deliverables in this run:
  - `/Applications/Kuro/docs/audit-2026-02-20-findings.md`
  - `/Applications/Kuro/docs/audit-2026-02-20-remediation-plan.md`
  - `/Applications/Kuro/docs/audit-2026-02-20-release-gate.md`

## 2) Deployed Backend Snapshot

### Deployed functions (Supabase project `bkdifromsqxkndnllmdj`)

| Function | Status | Version | Updated (UTC) |
|---|---:|---:|---|
| bulk-import-anime | ACTIVE | 16 | 2026-02-09 22:40:34 |
| bulk-import-manga | ACTIVE | 14 | 2026-02-19 20:11:52 |
| mirror-images | ACTIVE | 13 | 2026-02-19 00:28:36 |
| concierge-parse | ACTIVE | 42 | 2026-02-11 14:21:09 |
| concierge-apply | ACTIVE | 20 | 2026-02-09 22:40:26 |
| concierge-undo | ACTIVE | 13 | 2026-02-04 22:54:15 |
| concierge-recommend | ACTIVE | 46 | 2026-02-18 14:18:19 |
| concierge-resolve | ACTIVE | 13 | 2026-02-08 23:47:50 |
| concierge-retrieve-assist | ACTIVE | 4 | 2026-02-11 14:21:11 |
| concierge-retrieve-feedback | ACTIVE | 2 | 2026-02-11 14:21:12 |
| delete-account | ACTIVE | 5 | 2026-02-15 13:02:43 |
| auth-callback | ACTIVE | 1 | 2026-02-17 12:48:53 |
| concierge-import-anilist | ACTIVE | 1 | 2026-02-19 00:28:42 |
| manga-chapter-enrich | ACTIVE | 2 | 2026-02-19 22:38:37 |
| manga-source-review-action | ACTIVE | 1 | 2026-02-19 22:58:20 |

### Remote migration tail (applied)

| Migration ID | Applied (UTC) |
|---|---|
| 20260219114953 | 2026-02-19 11:49:53 |
| 20260219120000 | 2026-02-19 12:00:00 |
| 20260219153000 | 2026-02-19 15:30:00 |
| 20260219234000 | 2026-02-19 23:40:00 |
| 20260219235500 | 2026-02-19 23:55:00 |

## 3) Verification Runs (Reproducible)

### iOS build and tests

- `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build` -> **BUILD SUCCEEDED**
- `xcodebuild test ... -only-testing:KuroTests` -> **TEST SUCCEEDED**
  - `KuroTests/testUIComponents()` passed
  - `KuroTests/testAppLaunch()` passed
- Targeted UI smoke:
  - `KuroUITests/testSwipeDoesNotOpenCardDetail` -> **TEST SUCCEEDED**
  - `KuroUITests/testSwipePagingScreenshots` -> **TEST SUCCEEDED**
  - `KuroUITests/testClubsScreenshots` -> **TEST SUCCEEDED**

### Edge function smoke/auth

- With valid `x-import-secret`:
  - `bulk-import-anime` -> `200`
  - `bulk-import-manga` -> `200`
  - `mirror-images` -> `200`
  - `manga-chapter-enrich` -> `200`
  - `manga-source-review-action` -> `404` for nonexistent `reviewId` (expected)
  - `concierge-parse` -> `200`
  - `concierge-recommend/apply/undo/resolve` -> `401` with anon token (expected auth)
- Without `x-import-secret`:
  - `manga-chapter-enrich`, `manga-source-review-action`, `bulk-import-anime`, `mirror-images` -> all `401`

### Ops script execution

- `node --check scripts/check_cron_health.js` -> syntax OK
- `node scripts/check_cron_health.js` -> fails without env:
  - `Missing SUPABASE_SERVICE_ROLE_KEY env var.`

### Production data spot checks

- Forced enrich for known problematic manga (`forceMangaId=263`) result:
  - `manga_processed=1`
  - `unresolved_mappings=1`
  - `chapters_upserted=0`
  - confirms strict mapping + review-queue behavior for unresolved title.

## 4) Claim Inventory (Major Claims)

| Claim ID | Source | Claim | Method | Status | Evidence |
|---|---|---|---|---|---|
| C-001 | `/Applications/Kuro/CURRENT_APP_STATE.md:1541` | Manga chapter enrichment v1 exists | File + deploy + migration check | Verified | function list + migration list + file presence |
| C-002 | `/Applications/Kuro/CURRENT_APP_STATE.md:1552` | `manga-source-review-action` exists | File + deploy check | Verified | function ACTIVE v1 |
| C-003 | `/Applications/Kuro/CURRENT_APP_STATE.md:1559` | Manga legal link resolver is wired in app | Static code review | Verified | `/Applications/Kuro/Kuro/Services/SupabaseService.swift:3128`, `/Applications/Kuro/Kuro/Views/DetailPages/MangaDetailView.swift:661` |
| C-004 | `/Applications/Kuro/CURRENT_APP_STATE.md:1567` | Cron secret header hardening is safe | Migration review | Partial | hardening exists, but plaintext fallback secret is present |
| C-005 | `/Applications/Kuro/CURRENT_APP_STATE.md:176` | Migration count is 104 | Inventory check | False | local SQL files count is 131 |
| C-006 | `/Applications/Kuro/CURRENT_APP_STATE.md:277` | Edge function count is 14 | Deploy + filesystem check | False | remote ACTIVE functions are 15 |
| C-007 | `/Applications/Kuro/CURRENT_APP_STATE_PLAIN.md:508` | One-tap review endpoint added | File + deploy check | Verified | `/Applications/Kuro/supabase/functions/manga-source-review-action/index.ts`, function ACTIVE |
| C-008 | `/Applications/Kuro/IMPLEMENTATION_PLAN_Variation1.md:479` | Build is verified | Build run | Verified | current run succeeded |
| C-009 | User finding (`ClubDetailView` string matching) | Add-to-rail errors are string-based | Static code review | False (resolved) | `/Applications/Kuro/Kuro/Views/ClubDetailView.swift:1811`, `:1836` |
| C-010 | `/Applications/Kuro/CURRENT_APP_STATE.md:1557` | `check_cron_health.js` includes chapter enrich checks | Static code review | Verified | `/Applications/Kuro/scripts/check_cron_health.js:108`, `:116`, `:239` |
| C-011 | `/Applications/Kuro/CURRENT_APP_STATE_PLAIN.md:508` | Review action triggers immediate enrich | API behavior | Partial | endpoint exists; approve path not exercised in prod-safe audit |
| C-012 | `/Applications/Kuro/CURRENT_APP_STATE.md` (release-ready posture) | Source/deploy are synchronized | Git + deploy diff | False | deployed migrations/functions in this wave are currently untracked in git |

## 5) Audit Constraints

- No destructive DB operations were performed.
- No mutation was performed against review rows in production for approve/reject path validation (to avoid accidental operational changes).
- Full `KuroUITests` aggregate suite was not used as a release gate signal in this audit; targeted smoke tests were used instead.
