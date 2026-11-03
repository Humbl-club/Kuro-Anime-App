# Voice actors + Apple song matches: bounded backfill plan (NOT run)

Prepared 2026-11-03 by the DATA lane of the details/songs pass. **Nothing below has been run.**
Applying migrations, deploying functions and running backfills are the lead's steps, after review
and owner approval. Never print `IMPORT_SECRET` or `SUPABASE_SERVICE_ROLE_KEY`; pass them through
the environment only.

## 0. Prerequisites (in this order)

1. Apply `supabase/prepared-migrations/20261103100000_character_voice_actors_v1.sql` (table +
   `anime_cast_v1` / `character_voice_actors_v1` / `staff_voice_roles_v1`).
2. Deploy the `bulk-import-anime` build from this branch. Its default query is byte-identical to the
   deployed one (test: "the voice-actor fragment is only in the query when requested"); voice
   actors are written only when a run's payload says `"includeVoiceActors": true`.
3. For the Apple pass (section 3): `20261101000000_release_schedule_and_themes_v2.sql` (live since
   2026-11-02, `docs/go-live/2026-11-02/STAGE2_RECEIPT.md`), then
   `20261103100200_theme_links_apple_v1.sql`.

## 1. Voice actors: which titles first

Order = AniList `POPULARITY_DESC`, the order of the untracked popularity page crawl. It puts the
titles people open most first and matches how our catalogue was filled.

| Wave | AniList popularity rank | Pages at perPage 10 | Why |
| --- | --- | --- | --- |
| A | 1 - 1,000 | `startPage` 1 - 100 | The titles behind most detail-page opens; verify the cast rail here |
| B | 1,001 - 5,000 | 101 - 500 | AniList refuses a Page past 5,000 entries (`ANILIST_MAX_PAGE_DEPTH`), so a page crawl ends at rank 5,000 |
| C | beyond 5,000 | (no page crawl) | Refreshed as they change: after wave B, add `"includeVoiceActors": true` to the scheduled `airing_or_releasing` and `recent_updates` cron payloads (a cron command change, owner approval) |

## 2. Voice actors: how many per run, AniList limits

Per run (payload below): 4 pages x 10 titles = **40 titles, 4 AniList requests**. One run every
**2 minutes** = about 2 requests/minute on average.

- AniList: the shared limiter spaces requests at 25/minute per isolate
  (`DEFAULT_ANILIST_PER_MINUTE`, `_shared/anilist_client.ts`); AniList's degraded limit is
  30/minute **across all callers**, and the hourly scheduled tracks share it. 2/minute leaves the
  scheduled tracks their room. A 429 honours `Retry-After`; a budget stop commits only fully
  persisted pages.
- Query cost: the voice-actor fragment makes each page heavier (10 characters, their JAPANESE
  voice actors). Run ONE page first (`maxPagesPerRun: 1`). A complexity rejection is a GraphQL
  error: the run fails without writing that page. If that happens, use `perPage: 5` and double the
  page numbers.
- Writes per title: the anime row (only changed columns; mirrored images and an unchanged
  description are kept), studios/tags/characters/staff upserts, and per character a replace of at
  most 3 `character_voice_actors` rows (<= 10 characters, so <= 30 rows and <= 30 staff upserts).
  Voice-actor staff upserts send only name/native/image, never `description` or occupations.
- `forceRefresh: true` is required: an unchanged title otherwise returns before the relations are
  written. `includeEpisodes: false` keeps the episode rows untouched.
- `useCursor: false` + an explicit `startPage`: the run neither reads nor writes `import_state` /
  `import_track_state`, so the scheduled cursors do not move. It takes the import lock; when a
  scheduled run holds it, the backfill run answers `locked` and writes nothing (retry the same page).

Totals: wave A = 25 runs (about 50 minutes); wave B = 100 runs (about 3.5 hours).

### Payload (one run; change only `startPage`, +4 per run)

```json
{
  "useCursor": false,
  "startPage": 1,
  "pagesPerBatch": 1,
  "maxPagesPerRun": 4,
  "perPage": 10,
  "runToEnd": false,
  "lightweight": false,
  "includeRelations": true,
  "includeEpisodes": false,
  "includeVoiceActors": true,
  "forceRefresh": true,
  "scheduleSafe": true,
  "delayMs": 250
}
```

```bash
# IMPORT_SECRET from the secret store, never echoed. One run:
curl -sS -X POST "https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/bulk-import-anime" \
  -H "x-import-secret: ${IMPORT_SECRET:?}" -H "Content-Type: application/json" \
  -d @payload.json | jq '{success, results, stoppedEarly, nextStartPage}'
```

Stop the wave when a run reports `results.errors > 0`, `success: false`, a GraphQL complexity
error, or repeated 429s; fix, then resume at the same `startPage`.

### Verify (read-only)

```sql
select count(*) as rows, count(distinct anime_id) as titles, count(distinct staff_id) as people
from public.character_voice_actors;
-- spot check one title the owner knows (Attack on Titan = AniList 16498):
select character_name_full, staff_name_full, staff_name_native
from public.anime_cast_v1((select id from public.anime where anilist_id = 16498));
```

Rollback: `truncate public.character_voice_actors;` (service role). Nothing else references it;
staff rows added for voice actors are ordinary catalogue rows.

## 3. Apple song matches (`scripts/series_enrichment_worker.py --apple`)

Needs `theme_links` rows (the AnimeThemes backfill ran at go-live on 2026-11-02) and the two theme
migrations above.

- Rate: one iTunes Search request every 3 s (<= 20/minute), User-Agent `Kuro-Intake/1.0`,
  `Retry-After` honoured on 403/429. Storefront JP first, US only when JP has no confident match,
  so 1 - 2 requests per song.
- Per run: `--limit` rows (max 200) of `theme_links` never checked or checked more than 30 days
  ago, oldest first. 200 rows = at most 400 requests = at most 20 minutes.
- Matching is strict (title AND artist, confidence >= 0.8, variants such as karaoke/instrumental/
  off vocal/cover/remix rejected). A row without an artist is recorded as checked with no match,
  without a request. Writes go through `upsert_theme_apple_matches_v1`; a row whose title/artist
  changed after it was read is skipped (stale).

```bash
# 1) Dry run: queries Apple, prints the counts and up to 10 sample matches, writes nothing.
SUPABASE_URL=https://bkdifromsqxkndnllmdj.supabase.co SUPABASE_SERVICE_ROLE_KEY=... \
  python3 scripts/series_enrichment_worker.py --apply --allow-hosted --apple --dry-run --limit 20
# 2) Owner reviews the samples (spot-check 10 against Apple Music), then the real pass:
python3 scripts/series_enrichment_worker.py --apply --allow-hosted --apple --limit 200
```

Run it at most once an hour until `checked` reaches 0, then monthly (the 30-day re-check). It is
not scheduled anywhere; scheduling it is a separate decision.

Verify: `select count(*) filter (where apple_track_id is not null) as matched, count(*) filter (where apple_checked_at is not null) as checked, count(*) as themes from public.theme_links;`

Rollback: `update public.theme_links set apple_track_id = null, apple_artwork_url = null, apple_preview_url = null, apple_music_url = null, apple_match_confidence = null, apple_match_key = null, apple_checked_at = null;`
(the app then shows no ▶ and falls back to the Apple Music search link).
