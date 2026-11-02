# Stage 2 receipt: overnight backend go-live (2026-11-02)

Project `bkdifromsqxkndnllmdj` (PostgreSQL 17.6, eu-central-1). Operator: Claude (workflow subagent, Senior Backend Engineer).
All times are UTC. Evidence: `preflight.json` and `postflight.json` in this folder. JWTs and the import secret are redacted from both files.

## Where the approval came from

- The owner wrote "Yeah, weekly is fine. That's all right." This answers checklist decision 0.2: similar-titles freshness changes from nightly to at least weekly. The owner also asked for next-episode, manga date and theme data, which needs `20261101000000`.
- The rest of the scope came from the workflow task text, not from the owner's own words: the index drops, the bridge fix, the edge deploys and leaving out `20261101030000_auth_hardening.sql`.
- Checklist decisions 0.1 (licensing D11) and 0.3 (`MU_OFFICIAL_GROUP_IDS`) are still open. That is why `release-intake` is deployed but **not scheduled** and no secret was set.

## What was applied

| # | Time | Item | Result |
|---|------|------|--------|
| 1 | 10:42–10:45 | Preflight (read-only) | PG 17.6. No queries running longer than 30 s. All target objects present, new ones absent. `release_events`, `theme_links` and `catalogue_units` hold 0 rows. Daily physical backup completed 2026-11-02 05:49. PITR is **off**. |
| 2 | 10:45:22 | `20261101000000_release_schedule_and_themes_v2.sql` (one request) | OK on the first attempt (no lock timeout). 8 + 6 new columns; RPCs `user_release_schedule_v1`, `media_release_schedule_v1`, `media_themes_v1`; writers `upsert_release_events_v1` and `upsert_theme_links_v1`. |
| 3a | 10:45:42 | Paused cron jobs 54, 87, 101, 102, 103 and 104 | Waited until the in-flight job-87 run finished (10:46:51) and nothing was active. |
| 3b | 10:46:57 | `20261101010000_perf_hotpaths.sql` | OK on the first attempt. Similar-titles gate, change-aware `updated_at` triggers, `refresh_discover_matviews_v1`, `prune_catalog_safety_audit_v1` (not scheduled), `assert_exact_duplicate_index_v1`. `mv_anime_current_season` was dropped. |
| 3c | 10:47:12 | Resumed 87, 101, 102, 103 and 104 | All active. The file itself replaced job 54 (`realm-similar-nightly`) with **115**, which runs `media_similar_nightly_v1()` (weekly freshness), and job 113 (`kuro-refresh-matviews`) with **114**, which runs `refresh_discover_matviews_v1()`. Both are active, run on the same schedules and are owned by `postgres` as before. |
| 4 | 10:47:21–10:47:33 | `20261101010100_perf_drop_duplicate_indexes.sql`, outside a transaction: 1 guard block plus 23 single `DROP INDEX CONCURRENTLY` requests | The guard passed for all 22 pairs, and every drop returned OK. Afterwards none of the 23 indexes remain, no index in `public` is invalid or not ready, and the surviving PK/unique indexes are valid. |
| 5 | 10:47:43 | `20261101020000_bridge_identity_fix.sql` | OK. The natural-key bridge is live and the one-time repair ran. It touched 0 rows because the tables are empty. |
| 6 | — | `20261101030000_auth_hardening.sql` | **Not applied**, as instructed. `anon` can still execute `check_email_exists`, and there is no history row. |
| 7 | after each apply | `supabase_migrations.schema_migrations` | One row per applied file, following the 2026-10-08 convention: `version`, `name` (without the version prefix) and `statements = ARRAY[<whole file text>]`, with `created_by`, `idempotency_key` and `rollback` left NULL. Stored lengths match the files (61228 / 22436 / 7018 / 10119). The history count went from 249 to 253. |
| 8 | 10:47:53–10:48:10 | Edge deploys (CLI v2.78.1) | Version changes: `bulk-import-anime` v79→v80, `bulk-import-manga` v78→v79, `manga-chapter-enrich` v66→v67, `release-intake` new at v1 (verify_jwt on, needs `x-import-secret`, **not scheduled**), `auth-callback` v4→v5 with `--no-verify-jwt`. Each deploy log ended "Deployed Functions on project …". |
| 9 | 10:48–10:55 | Postflight | See below and `postflight.json`. |

## Postflight results

- **Grants match the contract.**
  - `user_release_schedule_v1`: authenticated only. Called as anon it returns 42501.
  - `media_release_schedule_v1` and `media_themes_v1`: anon and authenticated.
  - Writers and repair functions: `service_role` only.
- **RPC calls.** I ran them as `anon` inside a transaction that was rolled back. Both RPCs execute and return 0 rows.
  - **No anime has `next_airing_at > now()`.** The latest value is 2026-10-22, and the latest `last_synced_at` is 2026-06-07. I used id 11 (ONE PIECE) instead.
  - The 0 rows are expected while `release_events` and `theme_links` are empty and the AniList pointer is stale. See problem 1.
- **Similar-titles gate.**
  - The first gated fire at 10:50 ran the core (1 m 50 s), set `last_core_run_at`, and cleared the dirty row (1 → 0).
  - 837 of 7537 seeds were still stale from this morning's blanket re-stale. Runs keep working through them at about 100 seeds per 5 minutes. Once the backlog is gone they should return immediately; I did not observe that yet.
- **Advisors.**
  - Security: 212 lints. The 5 new ones are the intended anon/authenticated EXECUTE grants on the three read RPCs, flagged as `*_security_definer_function_executable`.
  - Performance: 128 lints, no `duplicate_index` among them, and nothing that names an object from this deploy.
  - The rest are pre-existing: `generate_invite_code` search_path, leaked-password protection off, `pg_net` in public, and so on.

## Problems found (not caused by this deploy, not fixed)

1. **The catalog import is broken.** I found this in `net._http_response`. The `kuro-import-*` cron calls (10:00, 10:05, 10:10, 10:35) return **401 `{"error":"Unauthorized"}`**, which comes from the function's own `x-import-secret` check. `import_state` was last updated 2026-08-06.
   - Effect: no next-episode dates, no new titles and stale airing data. This blocks the "when is the next episode" feature until it is fixed.
   - **Verified after the deploy:** at 11:00, job 102 called the new `bulk-import-anime` v80. It booted and returned the same 401 from its `x-import-secret` check (`index.ts` line 18). This was not a boot error.
   - Also verified: at 11:00, the new `manga-chapter-enrich` v67 completed `import_runs` 42079 with status success, 20 processed and 0 errors.
   - Fix (owner decision): **rotate** the secret. Set a new `IMPORT_SECRET` function secret and put the same new value in the `x-import-secret` header of cron jobs 101–104, and of 106–112 if they share it.
   - The current value should be treated as exposed, for two reasons:
     - The cron commands store it in plain text in `cron.job`, together with a JWT.
     - During this deploy a verification query printed those commands into the operator session's output. They were not written to any committed file.
2. **`auth-callback` was live with verify_jwt=true**, so browsers got 401, which contradicts its header. It is now deployed with verify_jwt=false as the header specifies, and a GET returns 200.
   - However, Supabase serves HTML from the default `*.supabase.co` domain as `text/plain` with a sandbox CSP, so the re-skinned page shows as source text.
   - It needs a custom domain (or another host) to render. The primary flow (`kuro://auth/callback`) does not depend on this page.
3. **PITR is off.** Rollback relies on the daily physical backup (2026-11-02 05:49) and on the definitions captured in `preflight.json`.

## Rollback notes

- **000000:** drop the five new functions; re-create `home_events_page_v1` and `finish_series_enrichment_v1` from `20261007040000`; drop the new constraints, indexes and columns. No reader depends on them, and the tables are empty.
- **010000:**
  - Rename `_rebuild_media_similar_titles_core_v1` back over the wrapper.
  - Drop the `media_similar_graph_rev_*` triggers, `media_similar_graph_dirty`, `media_similar_rebuild_gate` and the new functions.
  - Repoint `update_anime_updated_at` / `update_manga_updated_at` to `update_updated_at_column()`.
  - Recreate `mv_anime_current_season` from `preflight.json` → `rollback_capture`. That entry holds the definition, both indexes and the ACL.
  - Cron: unschedule 114 and 115. Then reschedule the old commands from `preflight.json` → `cron_jobs_54_113_full`. **To go back to nightly freshness only**, reschedule `realm-similar-nightly` (`10 5 * * *`) with `update public.media_similar_seed_state set stale = true where stale = false;`.
- **010100:** recreate any of the 23 indexes from `preflight.json` → `rollback_capture.duplicate_index_defs`, using `CREATE INDEX CONCURRENTLY`.
- **020000:** re-create `_bridge_legacy_unit_v1` from `20261007040000` and drop `repair_legacy_bridge_identity_v1`. No rows were re-keyed.
- **History rows:** `delete from supabase_migrations.schema_migrations where version in (...)`, only together with a schema rollback.
- **Edge functions:** redeploy the previous git revision of each function. `auth-callback` previously had verify_jwt=true. Delete `release-intake` if it is not wanted.

## Still open for the owner

- Fix the import secret (problem 1). This is the highest-impact item.
- Decisions D11 (licensing) and `MU_OFFICIAL_GROUP_IDS`, then schedule `release-intake` and the themes worker. The schedule must be staggered against the bulk imports to stay at or under 25 AniList requests per minute.
- Apply `20261101030000_auth_hardening.sql` after the iOS build without `check_email_exists` ships.
- Optional: schedule `catalog-safety-audit-prune`, then `VACUUM (ANALYZE) catalog_safety_audit`.
- Dashboard items from checklist section 4: templates, password policy, leaked-password protection, SMTP, and a `kuro.app/privacy` host.
- CLAUDE.md Rule 1/2 doc updates (`CURRENT_APP_STATE*.md`, the implementation plan, MEMORY.md) were not part of this step, which committed `docs/go-live` only.
