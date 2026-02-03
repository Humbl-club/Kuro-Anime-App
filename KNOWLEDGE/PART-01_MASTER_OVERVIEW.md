PART-01 Master Overview
=======================

High-Level Architecture
- Data source: AniList GraphQL.
- Ingestion: Supabase Edge Functions import anime/manga metadata and related entities, then upsert into Postgres.
- Storage/CDN: Supabase Storage holds mirrored images (covers/banners/character/staff). DB columns are updated to point to Storage public URLs.
- App runtime: iOS (SwiftUI) reads via Supabase SDK. Discover/Search/Collection views use paged queries and curated server-driven sections.

Key Components
- Supabase project: bkdifromsqxkndnllmdj
- Edge Functions (server):
  - bulk-import-anime: Fetch AniList → upsert anime, episodes (streaming), studios/tags/characters/staff and joins.
  - bulk-import-manga: Fetch AniList → upsert manga, create chapters/volumes (placeholder when only counts are known), authors/tags/characters/staff and joins.
  - mirror-images: Download remote images → upload to Storage ‘media’ bucket → rewrite anime/manga/characters/staff image URLs.
- iOS App (client):
  - SupabaseService: central client/service for paging, search, curated sections, and user lists.
  - Models: Anime, Manga, Episode, UserList aligned with DB columns.
  - Views: Discover (server-driven), Collection (with user list filters), Browse/Search.

Data & Entities (normalized)
- anime, episodes; manga, chapters, volumes
- characters, studios, authors, staff, tags
- relationship tables: anime_* and manga_* joins for characters/studios/staff/tags/authors
- user list tables: anime_user_lists, manga_user_lists; unified view user_lists (read convenience)

Important Behavior
- Trending/New/Season filters resolved server-side using indexed columns (e.g., trending, season, season_year, created_at).
- “Airing soon” uses next_airing_at window from now to now+24h.
- Manga next chapter schedule is not provided by AniList; fields stay null.
- Image mirroring runs in batches/schedules and rewrites DB URLs so the app uses the CDN.

Scheduling Strategy (recap)
- Daily imports: bulk-import-anime and bulk-import-manga with runToEnd/timeBudget to process large ranges idempotently.
- Mirroring: staggered schedules (offset batches) to sweep all rows; safe to rerun.

Config
- App keys sourced from Info.plist or env; a fallback URL/key exists but must be replaced for production.
  - Supabase URL/Key: Kuro/Services/SupabaseService.swift:55, Kuro/Services/AppConfig.swift:1

Known Constraints
- Edge functions must stay within runtime limits; use multiple schedules.
- AniList often lacks per-episode timestamps beyond ‘streamingEpisodes’; many shows won’t have full episode lists.
- next_chapter_* timing is generally unavailable.

What’s Working Now
- Server-driven Discover sections (Trending, Current Season, Newly Added, Top Rated, Airing Soon) wired to Supabase queries.
- Search with facets and server paging; optional season selector.
- Collection and Collection Management integrate anime and manga; user lists loaded from normalized tables.
- Mirror-images function supports ANIME/MANGA/CHARACTER/STAFF with skip-if-mirrored and cache control.

