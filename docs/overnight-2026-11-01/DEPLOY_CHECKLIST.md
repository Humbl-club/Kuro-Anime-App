# Deploy checklist — overnight backend work (prepared, NOT applied)

Nothing below has been run against production. Every step needs your explicit go. Project: `bkdifromsqxkndnllmdj`.

## 0. Decide first (blocking)

- [ ] **Licensing (D11).** Which sources may Kuro use commercially? AniList ToS restricts mass storage/tracker use; AnimeThemes needs endorsement; MangaDex and MAL/Jikan restrict commercial use; MangaUpdates is permissive with credit. Evidence: `understand/sources.md`. Until decided, do **not** schedule `release-intake` or the themes worker.
- [ ] **Similar-titles freshness.** `20261101010000` changes the nightly "mark every seed stale" job to re-mark one seventh of seeds per night: each title's similar list is rebuilt **at least weekly instead of nightly** (this is what removes ~97% of DB time). Accept or revert before applying.
- [ ] **Manga release dates.** Pick official-publisher MangaUpdates group ids (candidates: MANGA Plus, VIZ Media, K MANGA) for `MU_OFFICIAL_GROUP_IDS`. Empty = no manga dates/estimates (by design).

## 1. Pre-flight

- [ ] `select version();` → PostgreSQL **≥ 14** (`CREATE OR REPLACE TRIGGER`).
- [ ] Backup / PITR point noted.
- [ ] Local proof is green: `scripts/db/run_local_db_tests.sh` (expected exit 4 with 2 known BLOCKED scopes; 1,168 assertions pass).

## 2. Apply prepared migrations (in this order)

Files in `supabase/prepared-migrations/` — apply each deliberately (do NOT `db push --include-all`, do NOT repair history):

1. [ ] `20261101000000_release_schedule_and_themes_v2.sql` — additive columns, RPCs `user_release_schedule_v1` / `media_release_schedule_v1` / `media_themes_v1`, service writers. Sets `lock_timeout 3s`; on a lock timeout simply retry.
2. [ ] `20261101010000_perf_hotpaths.sql` — **first pause** `realm-similar-drive-5m` and the `bulk-import-*` cron jobs (`select cron.alter_job(jobid, active := false)`), wait until no run is in progress, apply, then resume them.
3. [ ] `20261101010100_perf_drop_duplicate_indexes.sql` — contains `DROP INDEX CONCURRENTLY`: run **outside a transaction** (each statement on its own; see the file header). Each drop self-checks the duplicate and raises if not exact.
4. [ ] `20261101020000_bridge_identity_fix.sql` — re-keys legacy unit bridge rows (one-time repair).
5. [ ] `20261101030000_auth_hardening.sql` — revokes anon/authenticated `check_email_exists`. **Only after the iOS build that no longer calls it has shipped.**
6. [ ] Optional: schedule `catalog-safety-audit-prune` (command in the 010000 header), then `VACUUM (ANALYZE) catalog_safety_audit;`.
7. [ ] `supabase get_advisors(security)` and `(performance)` after DDL.

## 3. Edge functions

- [ ] Deploy changed functions after the SQL: `bulk-import-anime`, `bulk-import-manga` (limiter, error handling, per-track queries), `manga-chapter-enrich` (volume grouping), `release-intake` (new; IMPORT_SECRET auth), `auth-callback` page (re-skinned). Command: `supabase functions deploy <name> --project-ref bkdifromsqxkndnllmdj`.
- [ ] If/when scheduling `release-intake`: stagger it against the hourly bulk imports — the AniList 25/min limiter is **per function instance**, combined traffic must stay ≤ 25/min.
- [ ] Set `MU_OFFICIAL_GROUP_IDS` secret only after decision 0.3.

## 4. Auth / dashboard

- [ ] Upload the 5 re-skinned templates from `emails/` (Auth → Email templates).
- [ ] Password minimum 8 + leaked-password protection; `kuro://auth/callback` in the redirect allow-list; SMTP (Resend); email-confirmation setting per CLAUDE.md.
- [ ] Make `https://kuro.app/privacy` (and a Terms page) resolve — the domain does not resolve today; then set `KuroLegalLinks.terms`.

## 5. App rollout

- [ ] After the RPCs are live, the app picks them up automatically (it silently falls back while they are missing). Verify on the owned simulator: detail "Next" + songs sections, Home Coming up, Folio "Next release" sort.
- [ ] Flags: `series_foundation_v1` / `series_home_native_v1` remain 0% — the series grouping tables have **no producer** yet (critic G1), so the flag-on Home would show no series data even after this deploy.
