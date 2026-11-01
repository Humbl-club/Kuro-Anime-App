# Intake lane: every data intake path into the Kuro database

Audit date 2026-11-01 (Europe/Berlin). Read-only. Branch `kuro/overnight-2026-11-01`.
This lane made no source edits, no git changes, no simulator changes, and no remote calls beyond reading files already in the repo.

## How to read the evidence

- **Source citations** are `path:line` against the current tree. The bulk importers were split into modules: `index.ts` is now 31 lines and the logic lives in `anilist.ts`, `handler.ts`, `mapping.ts` and `persistence.ts`. The `index.ts:NNN` citations in `docs/research/2026-09-26-kuro-plan/KURO_FULL_REVIEW.md` §E3–E5 and `evidence/edge-cost-audit.md` are stale. §6 says which of their findings are fixed and which are still open.
- **Live table evidence** comes from `docs/overnight-2026-11-01/live/table-stats.txt` and `index-stats.txt`, captured tonight.
  - The "Estimated row count" column is `reltuples`, and it is stale. `public.manga` shows 0 rows at 108 MB, and `episodes` and `external_links` also show 0. Do not read that column as a row count.
  - **Table size is the stronger proxy.** 8192 bytes means one heap page: at most a few dozen rows, but at least one write ever. This report calls such tables "≈empty", not "empty".
  - Index scan counters may have been reset recently, so treat 0 scans as weak evidence.
- **Live cron evidence** comes from `docs/research/2026-09-26-kuro-plan/evidence/live-cron.json`, observed **2026-09-25** (about 5 weeks old).
  - The `kuro-import-*` jobs and the re-armed mirror and chapter-enrich commands are **remote-only**. Their payloads (track preset, page sizes) are **not in git**: `docs/superpowers/specs/2026-08-06-independent-review-wave2.md:15` says "literals stay out of git".
  - The run durations in that file (about 0.04 s) measure `net.http_post` dispatch time, not import time.
- **Deployment status of the Series/Home foundation.**
  - `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql` still says "prepared, NOT deployed" in its header (line 1), and CLAUDE.md agrees.
  - It **was applied**. `docs/handoffs/2026-10-08-backend-integration/approved-deployment-postflight.json` lists identity `20261007040000`. The applied atomic packet contains the triggers: `backend-atomic-DRAFT.sql:3559-3562` (`series_bridge_episodes`, `series_bridge_chapters`) and `:4117-4121` (`series_enrichment_source`). Tonight's live table list includes `theme_links`, `release_events`, `catalogue_units` and `series_enrichment_jobs`. `HANDOFF.md:124` and `:139` confirm the deployment and that "No backfill or worker scheduling occurred."
  - Not verified: whether each trigger still exists live. Live-inventory does not list triggers.
- **Confidence labels:** **[VERIFIED]** means read in code or evidence. **[INFERRED]** means reasoned from evidence. **[UNKNOWN]** means it needs a live read (exact read-only queries are in §9).

---

## 1. Summary: what we take in, and what is missing

| Owner ask | What exists today | Is it fed? | Verdict |
|---|---|---|---|
| **Next episode air time** | `anime.next_episode_number` and `anime.next_airing_at`, written by `bulk-import-anime` (`mapping.ts:40-41`, `:78-79`). Read by view `user_airing_next`, `ReleasesStore`, `ReminderScheduler` and `home_events_page_v1` (fallback union). | Yes, but only when the popularity-ordered cursor reaches the title (§2.1). Freshness for a given title can be days to weeks [INFERRED; the payload is unknown]. | **Freshness defect.** The schema and UI work; the intake strategy is wrong. |
| **Per-episode dates/titles** | `episodes.air_at`, `episodes.air_date`, `is_filler`, `is_recap` (baseline `20260807000000:260-281`). | **No writer sets air dates or filler flags** [VERIFIED by grep across `supabase/functions` and `scripts`]. Episodes come only from AniList `streamingEpisodes` (`mapping.ts:123-146`). | Gap. |
| **Release calendar table** | `release_events` (`20261007040000:363-391`, plus `source_identity` at `:3461-3462`). | **≈empty** (8 kB). The only producer is the legacy bridge trigger, which needs dated episode/chapter rows that nothing writes. | Built, never fed. |
| **Next manga chapter** | `manga.next_chapter_number` and `manga.next_chapter_at` (baseline `:340-341`, index `:1803`). | **Never set non-null.** Every writer sets it to `null` (`bulk-import-manga/mapping.ts:66-67`, `import_anilist_fast.js:195`, `import_anilist_local.js:296-297`) [VERIFIED]. | Dead column. |
| **Chapter rows** | `chapters` (51 MB table plus 44 MB index). MangaDex `/aggregate` supplies chapter **numbers only**, with title `Chapter N` (`repository.ts:378-382`). AniList placeholders also give `Chapter 1..N`, capped at 120 (`bulk-import-manga/mapping.ts:113-126`, `handler.ts:34`). | Chapters have no dates or titles. `release_date` and `release_at` are never written. | Partial (count-only). |
| **Next volume / book** | `volumes` table with `release_date`, `release_at`, `isbn`, price (baseline `:505-524`). | Only placeholders `Volume 1..N`, capped at 24 (`bulk-import-manga/mapping.ts:128-143`, `handler.ts:35`). No dates. MangaDex `/aggregate` already returns chapters **grouped by volume**, and `parseAggregateChapters` discards the grouping (`mangadex.ts:403-435`). | Gap, with one free data source being thrown away. |
| **Songs / OP / ED** | `theme_links` (`20261007040000:330-341`, plus `source_identity`/`freshness` at `:4056-4059`). Written only by `finish_series_enrichment_v1` (`:4204-4223`), fed by `scripts/series_enrichment_worker.py` (AnimeThemes). UI: `SeriesDetailViews.swift:268-285`. | **≈empty** (8 kB). The worker is manual-only, needs `--apply --allow-hosted`, handles ≤20 jobs per run, and has **never been scheduled** (`HANDOFF.md:139`). Its queue `series_enrichment_jobs` is 2.4 MB and still filling from triggers. | Built end-to-end, never run. |
| Trailer, rankings, stats, airing schedule, studio main flag, voice actors, `status(version:2)` HIATUS | Not queried (§3). | — | Gaps. |
| Where to watch / read | `external_links`, from AniList `externalLinks`, with `is_disabled` hard-coded to `false` (`mapping.ts:115`). `provider_availability` (Watchmode; flag at 0%) is ≈empty. | Partly. | Link quality gap. |

---

## 2. Intake path inventory (one block per path)

### 2.1 `bulk-import-anime` (AniList GraphQL, edge function)

- **Source:** `https://graphql.anilist.co` (`anilist.ts:4`), POST with no auth and no User-Agent.
- **Auth/trigger:**
  - The `x-import-secret` header must equal `IMPORT_SECRET` (`index.ts:13-20`).
  - `IMPORT_HEAVY_ENABLED` env (default true) gates non-lightweight runs (`index.ts:29`, `handler.ts:181-199`).
  - Live pg_cron jobs (`live-cron.json:155-163`):
    - `kuro-import-anime-hourly` runs at `5 * * * *`.
    - `kuro-import-anime-weekly` runs at `0 * * * *`. **Despite the name it is hourly.**
  - Both jobs are remote-only. Their payloads are not in git, and the migration `20260209225348_add_import_secret_to_cron_jobs.sql` cited at CURRENT_APP_STATE.md:2383 **does not exist in the repo** [VERIFIED].
- **Query:** `media(sort: POPULARITY_DESC, type: ANIME)` (`anilist.ts:57`). **Every track preset uses the same query.** `fetchPage` takes only `(page, perPage, includeRelations, includeEpisodes, retries)` (`anilist.ts:37`). Presets `airing_or_releasing`, `recent_updates` and `catalog_backfill` change sizing and cursor key only (`handler.ts:55-111`); they do not change the upstream filter or sort [VERIFIED].
- **Tables written:**
  - `anime`: upsert on `anilist_id` (`mapping.ts:100`).
  - `external_links`: upsert per link (`:117`).
  - `episodes`: **delete all for anime, then insert one by one** (`:124-145`).
  - `studios` and `anime_studios` (`:148-160`).
  - `tags` and `anime_tags` (`:162-174`).
  - `characters` and `anime_characters` (`:176-190`).
  - `staff` and `anime_staff` (`:192-206`).
  - `media_relations`: delete source rows, then upsert (`:239-287`).
  - Bookkeeping: `import_runs` (`persistence.ts:108-145`), `import_track_state` and `import_state` (`:163-214`), and the `acquire_import_lock`/`release_import_lock` RPCs.
  - Triggered side effects (deployed foundation):
    - `series_enrichment_source` fires on `insert or update of description,banner_image,cover_image_large,anilist_id,mal_id` (`20261007040000:4078-4086`). PostgreSQL `UPDATE OF col` fires whenever the column is in the SET list, even if its value is unchanged. The full upsert at `mapping.ts:56-100` lists all of those columns, so **every stale-title refresh re-enqueues an enrichment job**. The job row is only rewritten when the snapshot hash changes (`:4071-4075`).
    - `series_bridge_episodes` fires on every episode delete and insert (§5.2).
- **Change detection:** the full write happens only when AniList `updatedAt` differs (`mapping.ts:34`). Unchanged titles get a small patch: `last_synced_at`, `next_episode_number`, `next_airing_at`, and `episodes` if it grew (`:35-54`).
- **Idempotency:** the anime upsert is idempotent. Episodes and relations use delete-then-insert, which is **not transactional**: an interrupted run leaves partial rows. Episode numbers come from the regex `/Episode\s+(\d+)/` or array position (`:130-131`). The unique index `idx_episodes_anime_id_number_unique` (in index-stats) makes duplicate numbers fail as "optional errors".
- **Rate limiting:**
  - Default delay 670 ms per page; preset delays 0–250 ms (`handler.ts:25`, `:67`, `:80`, `:93`, `:107`).
  - Within a page, items are processed 5 in parallel (`:28`, `:232-243`).
  - Retry: 3 attempts with backoff of 500 ms × 2^n on 429/5xx/throw. **No `Retry-After`, no jitter, no fetch timeout** (`anilist.ts:10-35`).
- **Failure handling:**
  - Lock: **fails closed**. Only `data === true` counts as acquired (`persistence.ts:43-56`).
  - A primary write failure re-throws and the page is not checkpointed (`handler.ts:244-246`, `:268-282`).
  - Optional enrichments count errors and continue (`mapping.ts:9-14`).
  - **Open hazard:** a GraphQL error body returned with HTTP 200, or `data: null`, becomes `[]` (`anilist.ts:81-82`). On the first page of a run, `[]` sets `lastProcessed = 0` and the run reports success (`handler.ts:226-229`, `:254-266`). **The cursor wraps to page 1 on a provider error** [VERIFIED code path; how often AniList returns 200+errors is UNKNOWN].
- **Guard-rail defect:** anime reads `scheduleSafe` from the payload only (`handler.ts:149`). Manga inherits it from the preset (`bulk-import-manga/handler.ts:163`). Unless a cron payload sets `scheduleSafe` explicitly, anime presets are not clamped by `:154-160`.
- **Cursor defects:**
  - The cursor is read **before** the lock (`handler.ts:161-171` vs `:202`).
  - Every track also overwrites the legacy `import_state(media_type)` (`persistence.ts:177-181`, `:206-213`). Any track invoked **without** `trackKey`/`trackPreset` reads that clobbered cursor (`handler.ts:167-171`).
- **Freshness of `next_airing_at`:**
  - The cursor walks the whole popularity-ordered catalog linearly and wraps at the end. Live catalog estimate: about 21.7k anime rows (the anime estimate looks plausible; table 51 MB).
  - Sweep period ≈ `N_titles / (perPage × pagesProcessedPerRun) × runInterval`.
  - With the `airing_or_releasing` defaults (`perPage 20`, `pagesPerBatch 1`, no runToEnd), one hourly job refreshes 20 titles per run. That is 480 per day, and **≈45 days per full sweep**.
  - With the schedule-safe clamp (`≤10 per page × ≤2 pages`, `handler.ts:154-158`), it refreshes 20 per run: the same ≈45 days.
  - The `popularity_core` defaults (25 × 2 = 50 per run) give ≈18 days.
  - Two hourly anime jobs roughly halve these figures if they use different track keys.
  - All of these are **[INFERRED]**: the real payloads are unknown.
  - **Consequence:** after a title's `next_airing_at` passes, `user_airing_next` (`WHERE next_airing_at > now()`, `legacy_sql/10_create_user_airing_next_view.sql:19-21`) and `home_events_page_v1` (`20261007040000:3391-3395`) **drop the title** until the cursor reaches its page again. Weekly shows disappear from "Upcoming" and from countdowns for most of the week, and reminders schedule from stale timestamps (`ReminderScheduler.swift:177-197`).
  - Delays and hiatuses are only seen on the same cadence.
  - Not-yet-released new announcements rank low by popularity and are reached rarely.
- **Synopsis churn:** every stale upsert writes `synopsis_enhanced_state: 'pending'` (`mapping.ts:96`). This resets the synopsis pipeline whenever AniList `updatedAt` changes, which is roughly every episode for airing shows [VERIFIED write; impact INFERRED].
- **Mirror churn:** the upsert writes the AniList `cover_image_large`, `cover_image_medium` and `banner_image` (`:63-66`). That **overwrites the Storage-CDN URL** set by `mirror-images` (`mirror_repository.ts:177-180`), puts the title back into the mirror window, and re-fires `series_enrichment_source` [INFERRED from code; no URL-preserve guard exists].

### 2.2 `bulk-import-manga` (AniList GraphQL, edge function)

- Same transport, auth, lock and checkpoint as anime. It imports `../bulk-import-anime/persistence.ts`.
- **Cron:** `kuro-import-manga-hourly` at `35 * * * *` and `kuro-import-manga-weekly` at `10 * * * *` (hourly despite the name) (`live-cron.json:169-177`).
- **Query:** `media(sort: POPULARITY_DESC, type: MANGA)` (`bulk-import-manga/anilist.ts:56`). It fetches `chapters volumes` (`:67`), but there is no schedule field (AniList has none for manga), **no `status(version: 2)`** (so HIATUS is not distinguished), and no studios.
- **Tables written:**
  - `manga` upsert (`mapping.ts:88`), with `next_chapter_number`/`next_chapter_at` forced to `null` (`:66-67`) and `synopsis_enhanced_state: 'pending'` (`:84`).
  - `external_links`.
  - Optional placeholders: `chapters` `Chapter 1..min(N,120)` when the manga has none (`:113-126`), and `volumes` `Volume 1..min(N,24)` (`:128-143`).
  - `authors`/`manga_authors` **and** `staff`/`manga_staff`: the same AniList staff nodes are written twice.
  - `tags`, `characters`, `media_relations`.
- **Non-stale path:** only `last_synced_at` (`mapping.ts:41-48`).
- **Clobbering:**
  - The stale upsert writes `chapters: manga.chapters` (`:64`). AniList is often `null` for RELEASING series. That **erases the MangaDex-derived count** written by `updateMangaSyncFields` (`manga-chapter-enrich/repository.ts:409-431`) [VERIFIED both writes].
  - Both pipelines also write the shared `manga.last_synced_at`. Chapter-enrich priority class 2 (`RELEASING and last_synced_at < now()-24h`, `20260221173000:70-71`) keys off that same clock. **A bulk-import touch therefore defers chapter refresh** [VERIFIED code; impact INFERRED].
- **Placeholders pollute coverage:**
  - Fake `Chapter N` rows make `chapter_row_count > 0`, which removes priority class 1 (zero rows) from chapter enrichment (`20260221173000:69`).
  - The rows also inflate `chapters`. The 51 MB table is mostly placeholder-shaped rows [INFERRED].
  - Placeholders have no dates, so the bridge would mark them `available=false` (§5.2).

### 2.3 `manga-chapter-enrich` (MangaDex REST, edge function)

- **Source:** `https://api.mangadex.org` (`mangadex.ts:7`). Endpoints:
  - `GET /manga?title=…&limit=10&includes[]=cover_art`, used for title search (`mangadex.ts:390-400`).
  - `GET /manga/{id}`, used for verification (`:372-377`).
  - `GET /manga/{id}/aggregate?translatedLanguage[]=…`, per language, then falling back to all languages (`:437-482`).
- **Headers:** only `Content-Type` is sent (`:245`, `:317`). **No User-Agent.** MangaDex's API guidance asks for an identifying UA [UNVERIFIED against current MangaDex terms].
- **Trigger** (`live-cron.json:8`, `:36`):
  - `manga-chapter-enrich-15m` (`*/15 * * * *`). Migration source: `20260219153000:260`, later rescheduled.
  - `manga-chapter-enrich-nightly-sweep` (`35 3 * * *`). Migration `20260221162000:263-290` gives a payload of limit 200, 45 s budget, and languages en/de with fallback.
  - The live commands were re-armed remotely with literal secrets on 2026-08-06 (CURRENT_APP_STATE.md:2611), so the live payloads may differ.
- **Candidates:** RPC `get_manga_chapter_enrich_candidates`. The latest version is `20260221173000:8-105`.
  - It runs a **global `GROUP BY` over all chapters before the LIMIT** (`:31-35`).
  - Priority classes: forced, then zero rows, then RELEASING and stale >24h, then rows < chapters, then verify due, then review due (`:67-76`).
- **Writes:**
  - `manga_source_links` (mapping, with verify state).
  - `manga_source_link_review` (unresolved, 30-day auto-expire cron at `20260221162000:236-249`).
  - `manga_mapping_alias_memory`.
  - `chapters`: missing numbers only, title `Chapter N`, **no dates, no titles, no fractional chapters** (`mangadex.ts:425-427` skips `x.5`) (`repository.ts:354-395`).
  - `manga.chapters = max(existing, maxNumber)` and `last_synced_at` (`repository.ts:409-431`). This conflates "highest chapter on MangaDex" with the total chapter count.
  - `manga_chapter_enrich_state`, `import_runs`.
- **Matching:** title search first, then exact `links.al`/`links.mal` filtering (`run.ts:696`, `:718`), then fuzzy v2 at ≥0.95 confidence (`run.ts:55-56`).
- **Rate limiting:**
  - A process-local limiter at 3 RPS by default, with a 2.5 s cooldown after 2 consecutive 429s (`mangadex.ts:8-11`, `:37-45`).
  - Per-run deadline via AbortController (`:85-99`).
  - Retries on 5xx with jitter (`:338-343`).
  - A 429 returns `rateLimited` with no retry (`:333-336`).
- **Lock:** fails closed (`repository.ts` acquire/release and the comment above `acquireImportLock`).
- **Coverage:**
  - Live `manga_source_links` is 200 kB and `manga_chapter_enrich_state` is 184 kB. That is a few thousand rows at most, against a 108 MB `manga` table [INFERRED; exact counts UNKNOWN].
  - The job was dead from 2026-07-31 until the 2026-08-06 re-arm (CURRENT_APP_STATE.md:2611).
  - `catalogue_units` and `release_events` are ≈empty although the chapter bridge trigger is deployed. That suggests **few or no chapter inserts since 2026-10-08** [INFERRED; see §9 Q3].
- **What `/aggregate` already returns but we drop:** `volumes{ "<vol>": { chapters { "<ch>": {...} } } }`. That is volume number to chapter range, for free (`mangadex.ts:404-430`).
- **What MangaDex offers but we do not call** [UNVERIFIED shape; check the MangaDex docs]: `GET /manga/{id}/feed?order[chapter]=desc&translatedLanguage[]=en&limit=…`. It returns per-chapter `publishAt`, `readableAt`, `title`, `volume`, `pages` and `externalUrl` (official-publisher chapters such as MANGA Plus), which would give a real "latest chapter at" date. MangaDex has **no future-release schedule**.

### 2.4 `mirror-images` (AniList CDN to Supabase Storage, edge function)

- **Source:** only `https://s4.anilist.co` (`source_fetch.ts:7`), with bounded timeout and byte limit.
- **Trigger:** five pg_cron jobs between 02:00 and 03:00 (`20260731020000_image_convergence_v1.sql:259-312`; live `live-cron.json`, jobs 106-110). Payload offsets are 0/600/1200 with limit 200 for anime/manga, and limit 300 for characters/staff. Each run first drains ≤50 `image_mirror_state.priority_at` rows (mirror-on-view).
- **Writes:** Storage bucket `media` only (`mirror_storage.ts:22-25`), the catalog URL columns `cover_image_large`, `cover_image_medium`, `banner_image` and `image_large` (`mirror_repository.ts:177-180`), plus `image_mirror_state` and `mirror_runs`.
- **Window:** remote-only rows ordered by popularity or visibility (`mirror_repository.ts:157-175`).
- **Lock:** **fail-open on RPC error.** `unavailable` proceeds without the lock (`mirror_repository.ts:11-12`, `mirror_run.ts:104-105`). This is still open from the prior review.
- **Freshness/loss:** bulk-import stale upserts revert the mirrored URLs (§2.1). AniList `coverImage.extraLarge` is fetched (`anilist.ts:60`) but **never stored or mirrored**, so the highest-resolution hero art is lost.

### 2.5 `concierge-import-anilist` (user list read, edge function)

- **Source:** AniList `User` and `Page.mediaList` by username (`concierge-import-anilist/paging.ts:18-49`). JWT auth, plus the `check_concierge_rate_limit('anilist_import')` RPC (`index.ts:46-53`).
- **Writes:** none to the catalog. It returns text lines; writes go through concierge-apply and the v2 import RPCs (`start_library_import_v1`, `apply_import_chunk_v1`, `finish_library_import_v1` at `20261007040000:2071-2440`), into `library_import_*` and the user list tables.
- **Gap:** titles in the user's AniList list that **are not in Kuro's catalog** are not enqueued for catalog import. The `media.id` (AniList id) is available at `paging.ts:42`, but nothing captures it as a demand signal.

### 2.6 Media relations worker (local, AniList GraphQL)

- **Files:** `scripts/media_relations_worker.js`, runner `scripts/run_media_relations_refresh.sh`, launchd `com.kuro.media-relations` (`install_media_relations_launchd.sh:69-70`, default 900 s).
- **Source:** single and aliased **batched** queries of 10 per request (`m0: Media(id:…) { relations … }`, `media_relations_worker.js:193-245`). Delay 350 ms, timeout 20 s (`:102-104`).
- **Writes:** `media_relations` (delete then upsert, `:264-310`). It drains `media_relation_refresh_queue` (`:324`, `:361`).
- **Running?** **No `com.kuro.*` launch agent is installed on this Mac, and there is no `reports/media-relations` directory** [VERIFIED locally; whether it runs on another machine is UNKNOWN]. That contradicts CLAUDE.md's description of these as continuous local pipelines.
- **Reusable pattern:** the aliased batch query is the right shape for an airing refresh, preferably `Page{media(id_in:[…])}` [verify against AniList docs].

### 2.7 `series_enrichment_worker.py` (copy, palette and themes; local, manual)

- **Sources:**
  - Catalog description (no network) for `detail_copy`.
  - Artwork bytes from `s4.anilist.co`, `cdn.myanimelist.net` or Kuro Storage (`:24`), run through PIL and `tools/design-directions/build_art_materials.py`, into `artwork_materials`.
  - **AnimeThemes REST:** `api.animethemes.moe/anime?filter[has]=resources&filter[site]=AniList&filter[external_id]=…&include=resources,animethemes.song,animethemes.song.artists` (`:75-79`), into `theme_links`.
- **Queue:** `series_enrichment_jobs` (`20261007040000:4039-4048`), filled by triggers on `anime` and `manga` (`:4078-4091`) and an optional backfill (`:4107-4124`). Claim leases last 5 minutes (`:4126-4140`). `finish_series_enrichment_v1` writes the last-good data (`:4143-4227`).
- **Trigger/schedule:** **none.**
  - The default invocation is a dry run (`:152-154`).
  - Hosted writes need `--allow-hosted` (`:121-129`).
  - Each run processes ≤20 jobs, one claim at a time, with a 1 s sleep (`:161-178`).
  - "No backfill or worker scheduling occurred" (`HANDOFF.md:139`).
  - **PIL is not installed** in this environment (`python3 -I -c "import PIL"` raises ModuleNotFoundError).
- **Producer live, consumer never run:** the queue table is 2.4 MB, with an estimated 3,678 rows (stale estimate). Due jobs pile up, and `theme_links`, `detail_copy` and `artwork_materials` are ≈empty (8 kB each).
- **Coupling defect:** copy, artwork and themes are extracted in **one try block** (`:168-175`). An artwork failure (missing PIL, disallowed host, size limit) sends `p_error` and the **themes and copy are discarded** for that attempt. The job then backs off exponentially, up to 24 h (`:4160-4163`).
  - Separately, `INVALID_MATERIAL`/`INVALID_THEME` exceptions raised inside `finish_series_enrichment_v1` (`:4179-4188`, `:4214`) surface as HTTP errors. These are **outside** the try block, so they would crash the run [VERIFIED structure].
- **Theme fidelity gaps:**
  - The role map `{0:'op',1:'ed','OP':'op','ED':'ed'}` (`:109`) drops `IN` (insert songs). The table check allows only `op`, `ed`, `insert` (`:334`), and finish rejects anything other than `op`/`ed` (`:4214`).
  - Not requested: `animethemeentries` (episode coverage, version, spoiler/NSFW), song `resources` (Spotify, Apple Music, YouTube Music links), and audio/video. The research memo says nested song resources need a separate song hydration (`music-metadata-research.md`, AnimeThemes section).
  - Every row is written with `match_state='search'` (`:4216-4217`). The UI shows a direct link only for `verified` plus `open.spotify.com` (`SeriesDetailViews.swift:276`); everything else becomes a search URL (`:281-283`).
  - One HTTP request per anime. AnimeThemes GraphQL `findAnimeByExternalSite(site: ANILIST, id:[…])` takes many IDs per call [research memo; verify].
  - AnimeThemes returned 403 from the research environment on 2026-09-26 (research memo, "Recommendation" paragraph). Access is unverified.

### 2.8 Synopsis enrichment / catalog safety / provider availability (local Swift workers)

| Worker | Source | RPCs / tables | Schedule | Running here? |
|---|---|---|---|---|
| `synopsis_enrichment_worker.swift` + `synopsis_run.swift` | catalog `description` | `get_synopsis_enrichment_candidates`, `upsert_synopsis_enhanced`, `mark_synopsis_enhanced_failed`, `get_synopsis_enrichment_backlog_count` (`synopsis_enrichment_worker.swift:69-97`), writing the `anime`/`manga.synopsis_enhanced_*` columns | launchd `com.kuro.synopsis-enrichment`, 240 s (`install_synopsis_enrichment_launchd.sh:4`, `:46-47`) | **No** agent installed, no `reports/synopsis-enrichment` |
| `catalog_safety_worker.swift` + `catalog_safety_run.swift` | catalog text plus lexicon | `get_catalog_safety_candidates`, `upsert_catalog_safety_result`, `mark_catalog_safety_failed`, `get_catalog_safety_open_gaps`, `get_catalog_safety_backlog_count` (`catalog_safety_worker.swift:94-130`), writing `safety_*` columns and `catalog_safety_audit` (**88 MB table, 43 MB index, and no retention job anywhere in the repo**) | `com.kuro.catalog-safety`, 600 s | **No** |
| `provider_availability_worker.swift` | **Watchmode** API `https://api.watchmode.com/v1` (`:119`) | `get_provider_availability_refresh_candidates` (`:263`), writing `provider_availability` (≈empty) and `provider_source_map` | `com.kuro.provider-availability`, 600 s | **No**. The feature flag `streaming_availability_v1` is at 0% |

Interaction: bulk import resets `synopsis_enhanced_state='pending'` on every stale refresh (§2.1, §2.2). With no worker running, that has no effect today. Once the worker runs, it will re-enhance airing shows weekly.

### 2.9 Manual / one-off AniList scripts (not scheduled)

- `scripts/import_anilist_fast.js` and `scripts/import_anilist_local.js` use `POPULARITY_DESC` with 50 per page and fetch characters and staff at 50 each (`import_anilist_fast.js:94-116`; `import_anilist_local.js:93-115`). They fetch `externalLinks{… isDisabled}` (`:111`/`:110`), which the edge function does not.
- `scripts/run_full_import.js` is a client-orchestrated backfill driver around the edge function.
- `scripts/import_anilist_rec_edges.js` imports AniList `recommendations(sort: RATING_DESC, perPage: 25)` (`:196-210`) into `media_rec_edges` (17 MB live) through the `upsert_rec_edges` RPC, **authenticating with `KURO_TEST_JWT`** (`:21-24`). `20260806000000_security_and_mirror_repair.sql:7` revoked that RPC from `authenticated`, so **the script as written can no longer write** [INFERRED]. Recommendation edges are therefore frozen at their last import.
- `scripts/run_manga_chapter_crunch.js` is a manual driver for chapter enrichment.
- `scripts/realm_descriptor_worker.js` and the `realm-describe` edge function write Groq-generated realm descriptors (`media_realm_llm` via `upsert_media_realm_llm`, `realm-describe/index.ts:1-9`). The cron was paused (`20260802120000_pause_realm_describe_cron_again.sql`). The worker needs `KURO_TEST_JWT` to read the pending view.

### 2.10 Scheduled DB-internal jobs (no external source; they shape delivery)

From `live-cron.json` (2026-09-25):

- **Materialized views:**
  - `kuro-refresh-matviews` at 01:30 runs a **non-concurrent** `REFRESH MATERIALIZED VIEW` of 7 matviews (`baseline_capture_v1.sql:3010-3028`). Unique indexes for CONCURRENTLY were added at `:2994-3003` but are unused. `mv_anime_current_season` carries `next_airing_at` (`:2676-2677`; filter `RELEASING` at `:2699`), so Discover's current-season data is up to 24 h stale on top of the import staleness.
  - `taste-tag-vectors-refresh` at 03:50.
  - `realm-membership-refresh` at 04:30.
  - `realm-affinity-refresh` at 04:40.
- **Precompute:** `realm-tier-refresh` at 04:50 (about 134 s), `realm-similar-drive-5m` (mean 26 s, max 443 s; the heaviest recurring job), and `realm-similar-nightly`.
- **Retention:** `kuro-import-runs-retention` at 01:10 (remote-only), `cleanup-cron-history`, `concierge_housekeeping_daily`, `outbound-link-ledger-retention`, `manga-source-review-auto-expire-daily`.

---

## 3. AniList Media fields: fetched vs not fetched

Field names were checked against the current edge query (`bulk-import-anime/anilist.ts:37-80`, `bulk-import-manga/anilist.ts:38-76`). "Not fetched" entries are AniList Media schema fields per `docs/research/2026-09-26-kuro-plan/evidence/music-metadata-research.md` §1 and the AniList Media reference; **verify each selection against AniList docs before use.**

### 3.1 Fetched and stored
`id`, `idMal`, `title{romaji english native}`, `synonyms`, `coverImage{large medium color}`, `bannerImage`, `format`, `status` (v1 enum), `description`, `source`, `countryOfOrigin`, `isAdult`, `startDate`, `endDate`, `episodes`, `duration`, `season`, `seasonYear`, `nextAiringEpisode{episode airingAt}`, `averageScore`, `meanScore`, `popularity`, `trending`, `favourites`, `genres`, `siteUrl`, `updatedAt`, plus `chapters` and `volumes` for manga.

Relation-dependent fields:
- `externalLinks{site url language color}`.
- `streamingEpisodes{title thumbnail url site}`: anime, airing/backfill presets only.
- `studios{nodes{…}}`.
- `tags{…rank, spoiler flags}`.
- `characters(sort: ROLE, perPage: 10)`.
- `staff(sort: RELEVANCE, perPage: 10)`.
- `relations{edges{relationType(version:2) node{id type}}}`, filtered to 6 types (`mapping.ts:4`).

### 3.2 Fetched but dropped (wasted bytes, or lost value)
| Field | Where fetched | Value lost |
|---|---|---|
| `coverImage.extraLarge` | `anilist.ts:60` (both) | **High-resolution hero/poster for the redesigned screens**. There is no column (baseline `anime` DDL `:59-129`). |
| `hashtag` | `:60`/`:59` | Social or official hashtag; minor |
| `title.userPreferred` | `:59` | Minor |
| `type` | `:63`/`:62` | Redundant |
| `nextAiringEpisode.timeUntilAiring` | anime `:70` | Redundant with `airingAt` |
| relation node `title{…}`, `format`, `coverImage{large}` | `:45` | Could render relation targets **not yet in the catalog**; today unresolved targets are dropped (`mapping.ts:266-269`) |
| relation types outside `SOURCE, ADAPTATION, PREQUEL, SEQUEL, SIDE_STORY, SPIN_OFF` | `:42-46` | `ALTERNATIVE`, `SUMMARY`, `COMPILATION`, `CONTAINS`, `CHARACTER` and `OTHER` are discarded |

### 3.3 Not fetched (candidate additions)
| AniList field | Product value | Notes |
|---|---|---|
| **`airingSchedule(notYetAired: true, perPage: N){nodes{episode airingAt}}`** or top-level **`Page{airingSchedules(airingAt_greater, airingAt_lesser, sort: TIME)}`** | Exact per-episode future air times and delays, enough to fill `release_events` and `episodes.air_at` | The top-level time-window query covers *all* airing anime in about 2–6 pages per run [verify page sizes]. |
| **`status(version: 2)`** | Distinguishes **HIATUS** for manga and anime | Currently only the v1 enum is used |
| `trailer{id site thumbnail}` | Trailer hero on detail | No column today |
| `rankings{rank type allTime season year context}` | "#3 most popular of Fall 2026" editorial badges | |
| `stats{scoreDistribution statusDistribution}` | Distribution charts and social proof | |
| `studios(isMain: true)` or `studios{edges{isMain node{…}}}` | **Main studio**. Its absence is a documented ranking defect (`20260804110000_totoro_credits_and_studio_main.sql:34-54`) | |
| `characters{edges{voiceActors(language: JAPANESE) …}}` | Voice cast | Not fetched |
| full `characters`/`staff` pagination | The edge function caps at 10; the manual scripts use 50 | |
| `externalLinks{type isDisabled notes icon}` | Separates `STREAMING`, `INFO` and `SOCIAL`; drops dead links | `is_disabled` is hard-coded `false` (`mapping.ts:115`) |
| `recommendations` | Only `import_anilist_rec_edges.js` reads it (frozen, §2.9) | |
| `isLicensed`, `seasonInt`, `isLocked`, `modNotes` | Low | |

AniList Terms and rate-limit caveats are in the research memo §1. It documents a nominal limit of 90 requests/min, a degraded mode of 30/min, and restrictions on mass collection. Any expansion should be **narrower and change-driven**, not broader crawling.

---

## 4. Tables touched by intake (live sizes tonight)

| Table | Size (table+index) | Writer(s) | Notes |
|---|---|---|---|
| `manga` | 108 + 46 MB | bulk-import-manga, chapter-enrich, mirror, synopsis, safety | `reltuples` estimate 0 is stale |
| `catalog_safety_audit` | 88 + 43 MB | catalog safety worker | **No retention** |
| `chapters` | 51 + 44 MB | placeholders, chapter-enrich | Mostly number-only rows |
| `anime` | 51 + 30 MB | bulk-import-anime, mirror, synopsis, safety | about 21.7k (estimate) |
| `characters` / `staff` | 51+14 / 16+5.7 MB | both importers | |
| `external_links` | 19 + 14 MB | both importers | `is_disabled` never true |
| `image_mirror_state` | 24 + 8 MB | mirror-images | |
| `episodes` | 17 + 7 MB | bulk-import-anime | delete/insert churn |
| `media_relations` | 2 + 9.5 MB | importers, relations worker | |
| `volumes` | 3.9 + 4.9 MB | placeholders only | |
| `import_runs` | 5.9 MB | all imports | retention cron is remote-only |
| `series_enrichment_jobs` | 2.4 MB | triggers | **No consumer scheduled** |
| `media_rec_edges` | 17 MB | rec-edges script (frozen) | |
| `manga_source_links` / `_review` / `manga_chapter_enrich_state` | 200 kB / 528 kB / 184 kB | chapter-enrich | Small coverage |
| `release_events`, `theme_links`, `catalogue_units`, `detail_copy`, `artwork_materials`, `provider_availability`, `series*` | 8 kB each | bridge, series worker, provider worker | **≈empty** |

---

## 5. Specific checks requested

### 5.1 Next episode
- **Source of truth today:** `anime.next_airing_at`/`next_episode_number`, refreshed only when the bulk importer visits the title (§2.1). It is also refreshed on the "unchanged" fast path (`mapping.ts:38-42`), which is good, but the visit cadence is the problem.
- **Delivery:**
  - The view `user_airing_next` is remote-defined. The repo copy at `legacy_sql/10_create_user_airing_next_view.sql:7-22` does not match the migration chain; only `ALTER VIEW … security_invoker` appears, at `20260206164200:12`.
  - It is read by `ReleasesStore.swift:135-146` (7-day window, limit 500) and `ReminderScheduler.swift:177-197`.
  - Home `home_events_page_v1` unions `release_events` (≈empty) with the `anime.next_airing_at` fallback (`20261007040000:3391-3395`).
  - Discover current season comes from the matview, refreshed nightly.
- **Index:** `idx_anime_next_airing_at` (453 scans tonight).
- **Missing:** a dedicated, time-window airing intake; per-episode schedule; delay and hiatus status; and finale detection (`episodes` set when status flips to FINISHED depends on the same cadence).

### 5.2 `release_events` and the legacy bridge
- **Producers:** only `_bridge_legacy_unit_v1`, through the `episodes`/`chapters` triggers (`20261007040000:3464-3527`), and `backfill_legacy_series_units_v1` (`:3532-3552`). That backfill is a service job; per `HANDOFF.md:124`/`:139` it was never run.
- The bridge emits an event **only if** the row has `air_date`/`air_at` (or `release_*`), or is a deletion (`:3486`). Nothing writes those dates, so **inserts produce `catalogue_units` but no events. Deletes produce `withdrawn` events.**
- **Latent bug in delete-then-insert episode churn** [VERIFIED logic; live impact UNKNOWN]:
  1. `bulk-import-anime` deletes all episodes (`mapping.ts:124`). The delete trigger upserts the unit with `available=false` and provenance `legacy:anime:<oldEpisodeId>:…` (`:3505`, `:3473-3477`).
  2. The re-insert gets a **new episode id**, so its provenance differs. The `ON CONFLICT … DO UPDATE … WHERE catalogue_units.source_provenance = excluded.source_provenance` (`:3477`) does nothing, and `v_id` is null, so the function returns (`:3485`).
  3. **Result:** every re-imported episode unit stays `available=false`, attributed to a deleted row, with a `withdrawn` release event. This happens on every stale refresh of an airing anime that has `streamingEpisodes`.
- `v_available` (`:3470-3471`) is `false` when there is no date, so **every MangaDex chapter and every placeholder** lands as an unavailable unit.
- Live `catalogue_units` is 8 kB, although every episode or chapter insert since 2026-10-08 should create a unit. This suggests **few or no episode/chapter writes since deployment** [INFERRED; §9 Q3].

### 5.3 Next manga chapter
- `manga.next_chapter_*`: always null (§1).
- `chapters`: numbers only, no `release_date`/`release_at`, title `Chapter N`.
- `home_events_page_v1` for manga relies **only** on `release_events` (`:3382-3387`; the `anime.next_airing_at` fallback at `:3389-3395` is anime-only), which is ≈empty. **The manga side of "Coming up" on Home is structurally empty.**
- **No source supplies future chapter dates.** Candidate sources, all **unverified** for terms and access:
  - MangaDex `/manga/{id}/feed` gives latest `publishAt`/`readableAt` (past releases only). Combined with a cadence estimate, this could produce an "expected around" date at `precision='day'` or `'unknown'`, labelled as an estimate. Note that `release_events.status` has no `estimated` value (`:376`), so a schema change or a convention would be needed.
  - MANGA Plus or other publisher endpoints: unofficial, with ToS risk. Do not adopt without review.
  - MangaUpdates API (`api.mangaupdates.com/v1`): series release feed (scanlation-group releases), plus latest chapter and status. Licensing/ToS unverified.
- **Honest product option:** show "Latest: Ch. N · 3 days ago" (from feed `readableAt`) and "Usually weekly", rather than a fabricated next date.

### 5.4 Volumes (next book)
- `volumes` holds only placeholders. No ISBN, dates or covers are ever written.
- **Free improvement:** keep the volume grouping from MangaDex `/aggregate` (`mangadex.ts:404-430`). That gives the real volume count and the chapter range per volume, which supports "Vol. 12 collects Ch. 101–110".
- **Release dates for volumes** need a bibliographic source. Candidates (all **unverified** for coverage and terms): Google Books API (ISBN, publishedDate), Open Library (ISBN editions), publisher sites (Viz, Yen Press, Kodansha USA; no public APIs), and MangaUpdates. Light novels (`manga.format = 'NOVEL'`) are released by volume, so this matters for them most.

### 5.5 Songs / themes
- The schema, RPC writer and UI all exist. The worker exists and has offline tests (`scripts/test_series_enrichment_worker.py`). It has **never been scheduled**, and its job queue keeps growing.
- What is missing:
  - A scheduler (pg_cron cannot run Python; it needs launchd or an edge function port).
  - Decoupling themes from artwork.
  - Insert songs.
  - Episode coverage.
  - Verified music links, through AnimeThemes song resources, plus a way to mark `match_state='verified'`.
  - Batched lookups.
  - Confirmed access to AnimeThemes (403 seen in September).
- Licensing guidance: link out only, no playback (research memo, "Link-out versus playback decision").

---

## 6. Prior-review findings: status today

| Prior finding (KURO_FULL_REVIEW §E3–E5) | Status | Evidence |
|---|---|---|
| Presets don't change the upstream query | **OPEN** | `anilist.ts:57` (both) |
| Anime `scheduleSafe` ignores the preset | **OPEN** | `bulk-import-anime/handler.ts:149` vs manga `:163` |
| Lock fail-open on RPC error (bulk imports, chapter-enrich) | **FIXED** | `persistence.ts:43-56`; `manga-chapter-enrich/repository.ts` acquire (outcome `unavailable` does not run) |
| Lock fail-open (mirror-images) | **OPEN** | `mirror_repository.ts:11-12`, `mirror_run.ts:104-105` |
| Page advanced despite item errors | **FIXED for primary writes** | `handler.ts:244-246`; optional enrichments still count and continue (by design) |
| GraphQL errors look like end-of-catalog | **OPEN**, and causes a cursor reset | `anilist.ts:81-82` + `handler.ts:226-229` |
| No Retry-After, jitter or fetch timeout (AniList) | **OPEN** | `anilist.ts:10-35` |
| Episode delete-then-insert, non-transactional | **OPEN**, now worse because of the bridge (§5.2) | `mapping.ts:123-146` |
| Relation delete-then-insert; unresolved targets dropped | **OPEN** | `mapping.ts:239-287` |
| Per-title serial write amplification | **OPEN** | `mapping.ts:103-206` |
| `manga.chapters` conflated with max MangaDex number | **OPEN**, plus the bulk-import clobber (§2.2) | `repository.ts:409-431`, `bulk-import-manga/mapping.ts:64` |
| Candidate RPC global GROUP BY | **OPEN** | `20260221173000:31-35` |
| Chapter insert race fallback (one insert per row) | **OPEN** | `repository.ts:385-391` |

---

## 7. Gaps, ranked

1. **Airing freshness** (P0 for Home, Upcoming and reminders). The popularity-linear cursor gives a multi-day to multi-week revisit for most airing titles, and past `next_airing_at` values drop titles from the upcoming views.
2. **Producer-without-consumer queues.** `series_enrichment_jobs` grows with no worker. The local workers are not running on this machine (synopsis, safety, relations, provider).
3. **Manga "next" is structurally empty.** No dates on chapters, `next_chapter_*` is dead, and manga `home_events` reads only `release_events`.
4. **Themes/songs pipeline never ran.** The table is ≈empty, the UI is ready.
5. **Overwrites between pipelines:**
   - Bulk import resets mirrored image URLs.
   - Bulk import resets `synopsis_enhanced_state`.
   - Bulk import nulls MangaDex chapter counts.
   - The shared `last_synced_at` couples two schedulers.
   - Placeholder chapters suppress enrichment priority.
6. **Bridge provenance lock-out** on episode churn, which makes units permanently `available=false` (§5.2).
7. **Dropped high-value fields:** `coverImage.extraLarge`, studio `isMain`, `status v2` HIATUS, trailer, rankings, voice actors, `externalLinks.isDisabled/type`.
8. **Ops hygiene:**
   - Cron definitions for imports, mirror and chapter-enrich exist only remotely. Payloads are unknown, and IMPORT_SECRET literals sit in 4 cron commands (CURRENT_APP_STATE.md:2611, "rotation still pending").
   - The "weekly" jobs run hourly.
   - `catalog_safety_audit` (131 MB) has no retention.
   - Matview refresh is non-concurrent.
   - `import_anilist_rec_edges.js` is broken by a grant revoke.
   - Catalog holes (user imports referencing AniList IDs not in the catalog) are not captured.

---

## 8. Recommendations (all need backend deploy and owner approval; none were executed)

1. **Airing track contract** (S/M).
   - Add a dedicated `airing_window` intake that queries AniList top-level `Page{airingSchedules(airingAt_greater: now-6h, airingAt_lesser: now+14d, sort: TIME){id episode airingAt mediaId media{id status episodes nextAiringEpisode{episode airingAt}}}}` [verify field names and page size against AniList docs].
   - Run it hourly. It writes `anime.next_*` and `release_events` (`source_identity = 'anilist:airing:<scheduleId>'`, `precision='instant'`, status `scheduled`/`released`), and optionally `episodes.air_at`.
   - Treat it as **change-driven**: unknown `mediaId`s are enqueued for catalog import.
   - This alone fixes Upcoming, reminders and Home for anime, at a few requests per hour.
2. **Give each track a real query** (S).
   - `recent_updates` uses `sort: UPDATED_AT_DESC` [verify] with an overlap cursor on `updatedAt`.
   - Releasing tracks use `status_in: [RELEASING, NOT_YET_RELEASED]`.
   - New announcements use `sort: ID_DESC`.
   - Persist the query version with the cursor (`import_track_state`).
   - Stop writing the legacy `import_state` from tracked runs.
   - Fix anime `scheduleSafe` inheritance.
3. **Fail-safe GraphQL handling** (S). Treat `errors[]`, or a missing `data.Page`, as an error that must not wrap the cursor. Honor `Retry-After`, add jitter and a per-request AbortController. This mirrors `concierge-import-anilist`, which already checks GraphQL errors.
4. **Stop cross-pipeline clobbering** (S):
   - Preserve Storage URLs on upsert (skip the image columns when the existing URL is on `/storage/v1/`, or keep the source URL in a separate `*_source` column).
   - Only reset `synopsis_enhanced_state` when `description` actually changes (compare the hash).
   - Never overwrite a non-null `manga.chapters` with null.
   - Give chapter-enrich its own `chapters_synced_at`.
5. **Episode/relation merge instead of delete+insert** (M). Upsert by `(anime_id, number)` in one RPC transaction, keyed by source. Also fix the bridge's provenance key so it uses `(medium, media_id, number)` instead of the source row id (§5.2).
6. **Manga chapter dates and volumes** (M):
   - Keep the `/aggregate` volume grouping, which yields volume rows with chapter ranges.
   - Add a bounded MangaDex `/feed` read for mapped titles to fill `chapters.release_at` and the title [verify endpoint and terms].
   - Surface "latest chapter, N days ago" and cadence. Do not fabricate a next date.
   - Stop placeholder chapter rows, or flag them `is_placeholder` so they do not count as coverage.
7. **Schedule the series enrichment worker, or port it** (M).
   - Split it into independent producers so themes do not depend on artwork.
   - Add `IN` (insert) roles, batch with GraphQL `findAnimeByExternalSite`, and fetch song resources so verified Spotify/Apple Music links can be shown.
   - Install PIL, or move palette extraction elsewhere.
   - Run it as an edge function on pg_cron (Deno) to avoid depending on a laptop.
8. **AniList field additions** (S):
   - Store `coverImage.extraLarge` (new column, mirrored).
   - `studios{edges{isMain}}`, `status(version:2)`, `trailer`, `rankings`, `externalLinks{type isDisabled}`.
   - Voice actors for the top N characters.
   - Each costs one schema column or table and a few query bytes.
9. **Ops** (S):
   - Capture the cron definitions as migrations without the secret literals (use Vault or the `x-import-secret` pattern via `vault.decrypted_secrets`).
   - Rename or fix the "weekly" schedules.
   - Make mirror fail closed.
   - Switch to `REFRESH MATERIALIZED VIEW CONCURRENTLY`.
   - Add retention to `catalog_safety_audit`.
   - Make the rec-edges import use service role or an edge function.
   - Log catalog holes from user imports into a demand queue.

---

## 9. Open questions: exact read-only queries for the next lane

These need **owner-approved read-only access** to the live project. This lane did not run any of them.

1. Live cron payloads: `select jobname, schedule, command from cron.job where jobname like 'kuro-import-%' or jobname like 'mirror-images%' or jobname like 'manga-chapter-enrich%';`. **Redact secrets before saving.**
2. Airing staleness: `select count(*) filter (where status='RELEASING') total, count(*) filter (where status='RELEASING' and (next_airing_at is null or next_airing_at < now())) stale, percentile_cont(0.5) within group (order by now()-last_synced_at) filter (where status='RELEASING') median_age from anime;`
3. Did any episode or chapter writes happen since 2026-10-08? `select max(created_at) from episodes; select max(created_at) from chapters; select count(*) from catalogue_units; select count(*), status from release_events group by 2;`
4. Import health: `select media_type, run_type, status, count(*), max(finished_at) from import_runs where started_at > now()-interval '7 days' group by 1,2,3;` and `select * from import_track_state;`
5. Queue depth: `select count(*), count(*) filter (where due_at<=now()) due, count(*) filter (where last_success_at is not null) done from series_enrichment_jobs;`
6. MangaDex coverage: `select count(*) from manga_source_links where provider='mangadex' and status='active'; select count(*) from manga where status='RELEASING';`
7. Placeholder share: `select count(*) filter (where title ~ '^Chapter [0-9]+$') placeholderish, count(*) from chapters;`
8. Triggers present live: `select tgname, tgrelid::regclass from pg_trigger where tgname in ('series_bridge_episodes','series_bridge_chapters','series_enrichment_source');`
9. Mirror revert rate: `select count(*) filter (where cover_image_large like '%/storage/v1/%') mirrored, count(*) from anime;`, compared with `image_mirror_state` rows in state `mirrored`.
10. Whether the local workers run on another host. That is an owner answer, not a query.
