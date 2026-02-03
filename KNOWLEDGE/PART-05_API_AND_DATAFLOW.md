PART-05 API & Dataflow
======================

End-to-End Flow
- AniList → Edge Functions → Postgres → iOS App

1) AniList GraphQL (server-side)
- bulk-import-anime/manga query AniList by pages of 50 items sorted by POPULARITY_DESC.
- Enriched fields: titles, images, status/format, season/season_year, scores, trending, genres, links, streamingEpisodes (anime), staff/characters/tags.

2) Supabase Edge Functions (Deno)
- bulk-import-anime: upsert anime by `anilist_id`, refresh episodes from `streamingEpisodes`, upsert studios/tags/characters/staff and relationships. Inputs: `startPage`, `pagesPerBatch`, `runToEnd`, `maxPagesPerRun`, `timeBudgetMs`, `useCursor`.
- bulk-import-manga: upsert manga by `anilist_id`, create placeholder `chapters` and `volumes` (count-based) when detailed lists aren’t available; upsert authors/tags/characters/staff and relationships.
- mirror-images: download remote URLs and upload to Storage (bucket `media` by default), then update DB URLs to public Storage URLs (skip if already mirrored; cacheControl applied).

3) Postgres Schema
- Indexed columns to support server-driven UI filters: `trending`, `season_year`, `created_at`, `average_score`, `next_airing_at`, and GIN on `genres`.
- Unified `user_lists` view for simple cross-media list queries.

4) iOS Client Queries
- Paged lists: `.range(from:offset, to:offset+pageSize-1)` sorted primarily by popularity (Discover prefetch) or by trending/score/date as needed.
- Search: `.textSearch("title_english,title_romaji,description_normalized", query)` with facets applied (`trending`, `airingOnly`, `season/year`).
- Sections:
  - Trending: `gt("trending", 0)` with optional `status == 'RELEASING'` when “Airing Only”.
  - Current/Season: `eq("season", <name>).eq("season_year", <year>)`, optionally `status == 'RELEASING'`.
  - Newly Added: `order("created_at", false)` (desc).
  - Top Rated: `gte("average_score", min).order("average_score", false)`.
  - Airing Soon: `next_airing_at` between now and now+24h.

Data Contracts (selected)
- Anime model keys (client): `title_english`, `title_romaji`, `cover_image_medium/large`, `season`, `season_year`, `next_airing_at`, `next_episode_number`, `average_score`, `trending`, `genres`, etc. (Kuro/Models/SupabaseModels.swift:1)
- Manga model keys: `chapters`, `volumes`, `average_score`, `genres`, etc. (Kuro/Models/SupabaseModels.swift:260)
- Lists: `anime_user_lists`, `manga_user_lists` mapped to in-app `UserList`; unified view shape in 08_create_user_lists_view.sql:1

Operational Considerations
- Rate limits: Edge functions pace requests (e.g., DELAY_BETWEEN_REQUESTS ≈ 670ms); increase pagesPerBatch with caution.
- Idempotency: `upsert` with onConflict; episodes/chapters/volumes refreshed per-title when present.
- Realtime: swap timer polling with Supabase Realtime channels for better UX if desired.

