# Hosted steps (2026-11-18; Part A executed 2026-11-19)

Everything below is built, tested locally and merged (or on `kuro/tracker-gaps`). **Part A
(A0–A7) was applied/deployed 2026-11-19** under owner instruction to execute the handoff; receipts
live beside this file (`applied-*.json`, `final-state.json`, `a6-shadow-runs.json`,
`a7-cron-scheduled.json`, first comparator reports under `docs/catalogue-sources-2026-11/runs/`).
**Part B and C are still waiting.** Each remaining step lists what it does, its risk and how it is
verified. Run them in this order.

To let Claude run them: allow the hosted actions in Claude Code's permission settings for this
project (Management API `/database/query` with `read_only: false` and `supabase functions deploy`),
or run the commands yourself. Every migration is applied in one transaction with its exact text
recorded in `supabase_migrations.schema_migrations` (helper pattern: `apply()` in the session
scratch `k.py`, same as the 2026-11-10 latency deploy).

## A. No user-visible change (safe first)

| # | Step | What it does | Verify |
| --- | --- | --- | --- |
| A0 | **Security first:** apply `20261118110000_guest_anon_allowlist_v1` (independently reviewed twice; inserts `guest_browsing_v1` disabled) | Signed-out callers can execute 110 public functions today (unguarded queue writers among them); after it, only the 20–22 allowlisted ones. Signed-in access is unchanged except `get_provider_availability_refresh_candidates` (service-only by intent) | before: read-only Q1–Q8 (`docs/plans/open-work-deploy-2026-11-18/live-anon-review-queries-2026-11-18.json`) and 7 days of API logs for anon `/rpc/*` names outside the allowlist; after: live audit query 1 returns exactly the allowlist, contact form and anonymous parse smoke-tested |
| A0b | Deploy concierge-parse, -apply, -undo, -recommend, -resolve, -import-anilist, -retrieve-assist, -retrieve-feedback (each with its current JWT setting), **then** apply `20261118140000_concierge_rate_limit_bounds_v1` | Rate-limit buckets keyed by HMAC of the IP (no one can fill another IP's bucket), only known kinds, anon cannot choose windows. **Order matters: the migration rejects raw IPs, so deploy the functions first** | Deno suites; limiter smoke per function; contact form still works |
| A0c | Apply `20261118150000_refresh_queue_hardening_v1` | Refresh queues: media must exist, fixed reasons, no reset of in-progress rows, 30 per 5 min per user | test 129; detail page availability/relations still refresh |
| A1 | Deploy `concierge-recommend` (isolated 8-file closure, JWT on) | Gimmick focus uses Kuro tag ids (was always empty live); no `tags.anilist_id` read | version bump, `verify_jwt` true, warmup/401 smoke, Deno 31/31 |
| A2 | Apply `20261112100000_catalogue_sources_v1` | Five service-only catalogue tables, id-link triggers, cutover switch (all groups `anilist`) | RLS on, no anon/auth SELECT, triggers present, test 120 |
| A3 | Apply `20261112100100_catalogue_shadow_report_v1` | Comparator RPC (service-only) | EXECUTE denied to anon/auth |
| A4 | Apply `20261112100200_catalogue_tag_sources_v1` | Tag-map table (service-only), `tags.description_kuro` / `retired_at` columns | test 123 |
| A5 | Deploy `catalogue-intake` (`--no-verify-jwt`, guarded by `IMPORT_SECRET`) | Shadow intake only: writes catalogue tables, never published columns | handler smoke with the secret; 401 without it |
| A6 | Run `wikidata`, `ann`, `mangaupdates`, `pageviews`, then `compose` by hand, then the comparator report (`scripts/catalogue_shadow_report.js`, read-only) | First real coverage/agreement numbers against frozen AniList values | report JSON in `docs/catalogue-sources-2026-11/` |
| A7 | Schedule the intake jobs from `docs/catalogue-sources-2026-11/cron-prepared.sql` | Keeps shadow data fresh | `cron.job` rows, first runs succeed |

## B. Visible changes (each its own go-ahead)

| # | Step | Needs first | Effect |
| --- | --- | --- | --- |
| B1 | Apply `20261112100400_catalogue_visibility_v1` | production EXPLAIN of the changed readers (`docs/catalogue-sources-2026-11/visibility-plans.md`) | `catalogue_visibility` column; browse/search/discover hide `list_only` titles (none exist yet) |
| B2 | Apply `20261112100450_catalogue_create_v1`; run `create` in report mode | B1 | report of what would be added |
| B3 | `create` in insert mode | owner picks `minYear` | **new titles resume** (anime; manga after the MangaUpdates new-series fetch lands) |
| B4 | Apply `20261118100000_search_hidden_adult_v1` | independent review of the import adult-guard trigger | search v2 + import guard; flag stays 0 % |
| B5 | Apply `20261118130000_library_up_next_v1` | — | W10 RPC; flag stays 0 % |
| B6 | Raise flags (`search_adult_notice_v1`, `collection_up_next_v1`, `library_export_v1`, `library_date_autofill_v1`) | owner-approved `--qualify` load run per profile (D-H) | features visible |
| B7 | Apply `20261112100150_catalogue_publish_v1`; deploy importers/release-intake/mirror-images | comparator gates pass for a group | a field group can switch to Kuro sources |
| B8 | Apply `20261112100401` then `20261112100500` | app build without AniList-id reads shipped and older builds retired; update `scripts/live/probe_import_workflow_v2.js` | AniList ids leave public reads; newly-added matviews dropped |

**Order rule for the W5 guest allowlist (`20261118110000_guest_anon_allowlist_v1`).** It closes only what exists when it
runs, and the global PUBLIC default stays open. Re-run live audit query 1
(`docs/tracker-gaps-2026-11/W5-guest/live-anon-grants.sql`) after EVERY later migration that adds or replaces a public
function; the expected result is exactly the 22 allowlist rows (20 until W4 `20261118100000` is applied). `20261112100401`
no longer grants `catalogue_anime_visible` / `catalogue_manga_visible` to anon, so apply it before W5 or re-run query 1 after.

## C. Outside Supabase

- TestFlight: App Store Connect returns `403 REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`. The account holder accepts the agreement (Business → Agreements); then a new build from `main` (widget-less variant unless the App Group is registered) is archived and uploaded.
