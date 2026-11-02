# Stage 4 receipt: data on (2026-11-02)

Project `bkdifromsqxkndnllmdj`. Operator: Claude (subagent, Senior Backend Engineer). All times UTC.
No secret, key, JWT or token value appears in this file.

## Approval

The owner said: implement everything so it is live in production, and turn on manga release dates
(MangaUpdates) and anime songs (AnimeThemes). This is read as the owner's answer to the two open
checklist items from `STAGE2_RECEIPT.md`:

- **D11 (licensing):** AnimeThemes theme data and MangaUpdates release data may be used, with the
  source credit the rows already carry (`source`, `source_url`).
- **0.3 `MU_OFFICIAL_GROUP_IDS`:** the full recommended allowlist from
  `MANGAUPDATES_OFFICIAL_GROUPS.md` (MANGA Plus, VIZ, LINE Webtoon), not the conservative one.

## 1. Catalog import restored (IMPORT_SECRET rotated)

### Root cause (two faults, both fixed)
1. **Auth (401 since about August).** Cron jobs 101–104 sent the import secret with one extra
   trailing character, so the `x-import-secret` check in `bulk-import-anime` / `bulk-import-manga`
   rejected every call. Jobs 106–112 sent the correct value, which is why `mirror-images` and
   `manga-chapter-enrich` kept working.
2. **Cursor past AniList's page-depth limit.** Once auth passed, the first run (import_runs 42081)
   failed with `AniList GraphQL error: Page depth exceeds maximum allowed for API requests (5000
   entries)`. The legacy cursor in `import_state` sat at `last_page = 500` for ANIME and MANGA.
   With `perPage` 25 that is entry 12,525, and AniList now refuses anything past entry 5,000.

### What changed
| Time | Change |
|---|---|
| 11:15:35 | New `IMPORT_SECRET` (64 hex chars, `openssl rand -hex 32`) set as an Edge Function secret through `supabase secrets set --env-file` (value never on a command line). |
| 11:15:37 | One SQL `DO` block: read the old value from job 106 inside the database, then `cron.alter_job` on every job containing it, replacing `old + trailing char` and `old` with the new value. It asserted exactly 11 jobs: **101, 102, 103, 104, 106, 107, 108, 109, 110, 111, 112**. No other job carried the secret. |
| 11:18:02 | `update import_state set last_page = 0 where media_type in ('ANIME','MANGA') and last_page = 500` (previous value 500 for both). |

Verification of the rotation, as booleans only, per job: each of the 11 jobs contains the new value,
its header value equals the new value exactly, and none has the trailing character. The secret
digest shown by `supabase secrets list` matches the sha256 of the new value.

### Evidence that the import and the other secret users work
| Function | How it was triggered | Result |
|---|---|---|
| `bulk-import-anime` | job 101's own command, executed once from SQL | import_runs 42082 `success`, 50 anime; `import_state` ANIME `last_page` 0 → 2; 50 `anime.last_synced_at` rows moved (the latest had been 2026-06-07) |
| `bulk-import-manga` | job 103's own command, executed once; then job 103 on its own schedule at 11:35 | import_runs 42083 and 42087 `success`, 50 manga each; MANGA `last_page` 0 → 2 → 4 |
| `mirror-images` | job 110's own command, executed once | mirror_runs 1354 `success` (staff 89) |
| `manga-chapter-enrich` | scheduled job 112 at 11:30 | import_runs 42086 `success` |
| `release-intake` | see section 3 | HTTP 200, import_runs 42084 / 42085 `success` |

`net._http_response` shows `null` with a 5 s client timeout for most of these calls. That is pg_net's
default timeout; the functions keep running and record their outcome in `import_runs` /
`mirror_runs`, which is the evidence used above. The 401s stop after 11:10.

Not exercised: `manga-source-review-action` (operator action, reads the same `IMPORT_SECRET`) and
`realm-describe` (deployed, dormant, not scheduled). Both read the secret from the function
environment, so they use the new value automatically. Local operator scripts that send the
secret (`scripts/run_full_import.js`, `run_manga_chapter_crunch.js`, `check_cron_health.js`,
`realm_descriptor_worker.js`, `scripts/manual/*`) need the new value in `IMPORT_SECRET` when run.
No launch agent or env file on this Mac held the old value.

### Exposure note
- During this step one read-only query meant to redact the cron commands used a pattern that did
  not match the `'x-import-secret','<value>'` form. It printed the **old** value into the operator
  session's output (not into any file). The value was rotated about two minutes later and is no
  longer accepted by any function.
- The new value is stored in plain text inside `cron.job.command`, as the old one was. That is the
  existing pattern (pg_cron cannot send a JWT-only call). Moving it to Vault is a follow-up.

### Open: the import will stall again at page 200
`bulk-import-*` only wraps its cursor on an empty page. A GraphQL error is treated as an error
with no cursor advance. With `perPage` 25, page 201 is past the 5,000-entry limit, so the
popularity crawl will fail again once the cursor reaches page 200. Jobs 101 and 102 share the
ANIME cursor at about 3 pages per hour, so that happens in roughly 2–3 days; the manga cursor
follows a similar pace. Fixing it needs a code change (wrap or cap at
`page * perPage > 5000`) and a deploy. Until then, the workaround is to repeat the
`import_state` reset above. While it stalls, `import_runs` shows `error` with the page-depth
message, so the failure is visible.

Also: about 36 titles currently airing on AniList are not in the catalog yet (import was down
since August). The popularity crawl will add them over the next days, and `release-intake` picks
them up on its next run after they exist.

## 2. `MU_OFFICIAL_GROUP_IDS`

Set at about 11:20 to `49204242348,45251742061,3657285706` (MANGA Plus, VIZ, LINE Webtoon;
decimal ids, comma-separated). The digest in `supabase secrets list` matches the sha256 of that
exact string.

## 3. `release-intake` scheduled

| Job | Name | Schedule (UTC) | Body |
|---|---|---|---|
| **116** | `kuro-release-intake-airing-hourly` | `25 * * * *` | `{"mode":"airing"}` |
| **117** | `kuro-release-intake-manga-daily` | `50 3 * * *` | `{"mode":"manga","limit":40,"timeBudgetMs":120000}` |

Both were built in SQL from job 101's command (same `Authorization` JWT and the new
`x-import-secret`), changing only the URL to `/functions/v1/release-intake` and the body. Owner
`postgres`, active.

AniList budget: the bulk imports fire at :00, :05, :10 and :35 and finish within about a minute;
airing intake at :25 does not overlap them. One airing run used 4 AniList requests (3 window
pages + 1 stale-sweep request), well under 25 per minute. Manga mode uses MangaDex and
MangaUpdates (1 request per 1.1 s), not AniList; 03:50 is clear of the 03:35 and 03:45 enrich runs.

### First runs
- **Airing dry run** (200): 3 pages, 122 schedules, 83 rows, 36 AniList titles not in the catalog.
- **Airing real run** (200, import_runs 42084 `success`): `release_events` now holds **83**
  `anime / anilist / confirmed / scheduled` rows; `anime.next_*` patched for 80 titles in the
  window plus 50 from the stale sweep. 81 anime now have `next_airing_at > now()` (none had
  before).
- `media_release_schedule_v1('anime', 1129, 5)` as `anon` returns Case Closed Ep. 1219 on
  2026-11-07 09:00 (confirmed, AniList credit). For id 11 (ONE PIECE) it returns Ep. 1181 on
  2027-01-03 (written by the stale sweep).
- **Manga real run** with the scheduled payload (import_runs 42085 `success`): 0 release rows,
  0 estimates. Nothing was written because nothing qualified, which is the intended behaviour.

### Why manga dates are thin (open)
The manga intake maps titles only through an active `manga_source_links` MangaDex link. Of the
200 most popular RELEASING manga (its candidate list), **only 1 has a link**; One Piece,
Kagurabachi, The World After the Fall and Witch Watch have none. A dry run over the 40 most
popular *linked* RELEASING titles found 388 release records, all from non-official groups, so 0
rows (12 volume counts would have been raised). Until the MangaDex mapping covers Shueisha and
WEBTOON titles, expect few or no manga release dates. Volume counts still move up for linked
titles. Separately, the 120 s budget processed about 14 titles per run, so `limit` 40 is an upper
bound, not a guarantee.

## 4. Anime songs (AnimeThemes)

### Backfill
`scripts/series_enrichment_worker.py --apply --allow-hosted --themes --anilist-ids <top 500 by
popularity>` (20 GraphQL requests, worker pacing at most 90 per minute):

`requested 500, matched 484, not_found 11, ambiguous 2, oversized 3, rows 2278` (516 of them
were written by the first attempt, see below).

`media_themes_v1(<Attack on Titan>)` as `anon` returns 4 songs (Guren no Yumiya, Jiyuu no
Tsubasa, Utsukushiki Zankoku na Sekai, great escape) with AnimeThemes credit.

After the launchd smoke run (below) `theme_links` holds **7,060 rows for 1,829 titles**.

### Worker fix needed for the run (uncommitted)
The first attempt aborted with `theme count exceeds bounded contract`: one long-running title has
more than 60 theme rows (`MAX_THEME_ROWS_PER_ANIME`), and the worker raised out of the whole pass.
Change in `scripts/series_enrichment_worker.py`: such a title is skipped and counted as
`oversized`, and the pass continues. The 60-row bound is unchanged, and `media_themes_v1` returns
at most 60 rows anyway. New test
`test_theme_pass_skips_title_over_row_bound_and_keeps_going`; `python3 -m unittest
test_series_enrichment_worker` → 15 tests OK. Effect: titles with more than 60 theme entries
(ONE PIECE-length shows) have no songs for now.

### Daily schedule on this Mac
- `scripts/run_series_enrichment.sh` (new): lock, then `SERIES_THEMES_PASSES` (default 4) passes
  of `--themes --limit 500 --after-id <cursor>`. The id cursor lives in
  `reports/series-enrichment/themes-cursor` and wraps to 0 when a pass finds nothing. That is
  2,000 titles a day, so the 21,668-title catalogue takes about 11 days per sweep.
  Logs: `reports/series-enrichment/worker.log`, `latest-status.json`.
- `scripts/install_series_enrichment_launchd.sh` (new): label `com.kuro.series-enrichment`,
  `StartCalendarInterval` daily at 05:20 local time, no `RunAtLoad`. Plist
  `~/Library/LaunchAgents/com.kuro.series-enrichment.plist`, mode **0600**; `SUPABASE_URL` and
  `SUPABASE_SERVICE_ROLE_KEY` live only there.
- `.gitignore` gains `/reports/series-enrichment/`.
- Smoke runs: the script by hand (2 passes of 25), then one `launchctl kickstart` of the installed
  agent: `runs = 1`, `last exit code = 0`, 4 passes, cursor 109 → 2316, 80 requests in about
  100 s.

These three script files, the worker fix and the `.gitignore` line are **not committed** (this
step commits only this receipt). The launch agent runs the working-tree copies.

## Rollback

| Item | Rollback |
|---|---|
| Release intake | `select cron.unschedule(116); select cron.unschedule(117);` Rows can be removed with `delete from release_events where source in ('anilist','mangaupdates','kuro_estimate')`; `anime.next_*` values are AniList's own data and can stay. |
| `MU_OFFICIAL_GROUP_IDS` | `supabase secrets unset MU_OFFICIAL_GROUP_IDS --project-ref bkdifromsqxkndnllmdj` (manga intake then writes no release rows) or set the conservative `49204242348,45251742061`. |
| Songs | `launchctl bootout gui/$(id -u)/com.kuro.series-enrichment` and delete the plist; rows: `delete from theme_links where source = 'animethemes'`. |
| Import cursor | `update import_state set last_page = 500 where media_type in ('ANIME','MANGA')` restores the stuck state; there is no reason to. |
| IMPORT_SECRET | Not reversible to the old value (it is treated as exposed). To rotate again, repeat the section 1 pattern: new value in a 0600 env file, `supabase secrets set --env-file`, then one SQL block replacing the current value in jobs 101–104, 106–112, 116, 117. |

## Still open for the owner
1. **Page-depth wrap** in `bulk-import-anime` / `bulk-import-manga` (code + deploy), or repeat
   the cursor reset every few days.
2. **MangaDex mapping coverage** for popular Shueisha/WEBTOON titles. Without it, manga release
   dates stay near empty.
3. Commit the uncommitted worker fix, run/installer scripts and `.gitignore` line.
4. Move the import secret and JWT out of `cron.job.command` into Vault.
5. CLAUDE.md Rule 1/2 updates (`CURRENT_APP_STATE*.md`, implementation plan, MEMORY.md) were not
   part of this step.
6. Everything still open from `STAGE2_RECEIPT.md` (auth hardening migration, dashboard items, PITR).
