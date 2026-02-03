PART-03 Backend Data & Infra
============================

Database (Postgres)
- Core entities
  - anime: internal id + external references (anilist_id/mal_id), titles, images, format/status, episodes/duration, season/season_year, next_episode_number/next_airing_at, scores/popularity/trending, genres, site_url, timestamps.
  - manga: internal id + external references, titles, images, format/status, chapters/volumes, next_chapter_* (may be null), scores/popularity/trending, genres, site_url, timestamps.
  - episodes: per-anime episodes; includes number/title/air_date/air_at/thumbnail/duration.
  - chapters, volumes: per-manga content; include number/title/description and image fields (volumes).
  - characters, studios, authors, staff, tags: reference catalogs.
  - relationship tables: anime_characters, manga_characters, anime_studios, manga_authors, anime_staff, manga_staff, anime_tags, manga_tags.
  - user lists: anime_user_lists, manga_user_lists; comments tables for each.
- Important SQL sources
  - Schema: 02_comprehensive_table_creation.sql:1
  - Unified view: 08_create_user_lists_view.sql:1 (view user_lists unions anime_* and manga_* tables with normalized columns)
  - Import cursors: 09_import_state.sql:1
- Indexes
  - Coverage for popularity, average_score, season_year, next_airing_at, and GIN on genres. See 02_comprehensive_table_creation.sql:520 and below.
- RLS and policies
  - RLS enabled; public read policies for core tables and joins; user-managed lists/comments restricted by auth.uid(). See 02_comprehensive_table_creation.sql:520 and below.
- Triggers
  - update_updated_at_column() and per-table BEFORE UPDATE triggers keep updated_at fresh.

Edge Functions
- bulk-import-anime (supabase/functions/bulk-import-anime/index.ts)
  - Inputs: startPage, pagesPerBatch, useCursor, runToEnd, maxPagesPerRun, timeBudgetMs.
  - Behavior: Fetches AniList, upserts anime and related entities (studios/tags/characters/staff), deletes+reinserts episodes from streamingEpisodes, writes next_airing metadata.
  - Idempotency: onConflict by anilist_id, safe refresh of episodes per-title.
- bulk-import-manga (supabase/functions/bulk-import-manga/index.ts)
  - Similar structure; creates placeholder chapters/volumes from counts if detailed lists aren’t available.
- mirror-images (supabase/functions/mirror-images/index.ts)
  - Inputs: bucket (default media), mediaTypes (ANIME/MANGA/CHARACTER/STAFF), limit, offset, overwrite=false, skipIfMirrored=true, cacheControl=604800.
  - Behavior: Downloads remote images, uploads to Storage with upsert and cache control, updates DB columns to Storage public URLs.
  - Skip-if-mirrored: avoids processing URLs already pointing at this project’s Storage domain.
  - Output: counts per media type updated.

Storage (CDN)
- Bucket: media (public).
- Public URL pattern: https://<project>.supabase.co/storage/v1/object/public/media/<path>
- Recommended: staggered mirror schedules to sweep rows with offsets (see SCHEDULES.md).

Schedules
- See SCHEDULES.md for:
  - Daily anime/manga imports (runToEnd + timeBudget cap).
  - Three staggered mirror-images batches (offset 0/500/1000, etc.).

Operational Queries (examples)
- Counts
  - Anime: `select count(*) from anime;`
  - Manga: `select count(*) from manga;`
- Airing soon (next 24h)
  - `select count(*) from anime where next_airing_at between now() and now() + interval '24 hours';`
- Mirrored image coverage
  - `select count(*) from anime where cover_image_medium like '%/storage/v1/object/public/%';`

Notes & Constraints
- AniList often lacks next chapter schedules; `next_chapter_*` stays null.
- Edge function timeouts: prefer runToEnd with timeBudget and multiple schedules for large backfills.

