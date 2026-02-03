APPENDIX Edge Functions (Server)
================================

bulk-import-anime (supabase/functions/bulk-import-anime/index.ts)
- Purpose: Import anime metadata from AniList and upsert into Postgres with relationships; refresh streaming episodes.
- Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (provided by platform).
- Inputs (JSON payload):
  - startPage (number, default 1)
  - pagesPerBatch (number, default 5)
  - useCursor (boolean, default false); when true uses table `import_state(media_type='ANIME')` as cursor
  - runToEnd (boolean, default false); iterate until timeBudget/maxPages bound
  - maxPagesPerRun (number, default 200)
  - timeBudgetMs (number, default 55000)
- External API: AniList GraphQL (Page/media perPage: 50, sort: POPULARITY_DESC)
- Touches tables: anime, episodes, studios, tags, characters, staff, anime_studios, anime_tags, anime_characters, anime_staff; updates import_state when `useCursor=true`.
- Idempotency: upsert by anilist_id; episodes deleted and re-inserted per anime to refresh streaming data.

bulk-import-manga (supabase/functions/bulk-import-manga/index.ts)
- Purpose: Import manga metadata (and relationships); create placeholder chapters/volumes when only counts exist.
- Inputs: same shape as anime importer; media_type is MANGA for cursor usage.
- External API: AniList GraphQL.
- Touches tables: manga, chapters, volumes, authors, tags, characters, staff, manga_authors, manga_tags, manga_characters, manga_staff; updates import_state.
- Idempotency: upsert by anilist_id; chapters/volumes deleted then recreated from counts.

mirror-images (supabase/functions/mirror-images/index.ts)
- Purpose: Mirror remote cover/banner images (and character/staff images) to Supabase Storage; rewrite DB URLs to public Storage URLs.
- Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
- Inputs (JSON payload):
  - bucket (string, default "media")
  - mediaTypes (array: 'ANIME'|'MANGA'|'CHARACTER'|'STAFF'; default ['ANIME','MANGA'])
  - limit (number, default 200)
  - offset (number, default 0)
  - overwrite (boolean, default false)
  - skipIfMirrored (boolean, default true) — skip URLs already on project’s Storage domain
  - cacheControl (string, default '604800') — upload cache-control seconds
- Behavior: Select rows ordered by popularity/id, fetch remote URL, upload into `bucket` with upsert and contentType, update DB column to Storage public URL.
- Touches tables/columns:
  - anime: cover_image_large/medium, banner_image
  - manga: cover_image_large/medium, banner_image
  - characters: image_large
  - staff: image_large
- Public URL pattern: https://<ref>.supabase.co/storage/v1/object/public/<bucket>/<path>

Scheduling
- See SCHEDULES.md for:
  - Daily import schedules with runToEnd/time budgets.
  - Three staggered mirror-images batches (offset sweep) to cover all rows.

