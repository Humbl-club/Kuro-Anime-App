PART-07 Functionality Deep Dives
================================

This part explains each major functionality: how it’s implemented, dependencies, data contracts, UI wiring, edge cases, and responsibilities vs. non‑responsibilities. File:line anchors let LLMs jump straight to code.

1) Discover: Server‑Driven Sections (Anime)
- Features
  - Trending (All/Airing Only toggle), Current Season, Season Picker, Newly Added, Top Rated, Airing Soon; Hero Featured card.
- Implementation
  - View: Kuro/Views/DiscoverView.swift:6
    - On appear, prefetch initial pages from `anime` then fetch precise server lists in parallel (lines ~140–174).
    - Trending toggle triggers a secondary fetch for “airing only”.
    - Season picker uses previous/next helpers: DiscoverView.swift:203, 212.
    - HeroFeaturedCard rendering: DiscoverView.swift:223.
  - Service: Kuro/Services/SupabaseService.swift
    - fetchTrendingAnime: 307 — `gt(trending,0)` [+ optional `status='RELEASING'`] → order by trending desc.
    - fetchCurrentSeasonAnime: 316 — `eq(season_year, <year>)` [+ optional `status='RELEASING'`].
    - fetchSeasonAnime: 326 — `eq(season, <name>).eq(season_year,<year>)` [+ optional `status='RELEASING'`].
    - fetchNewlyAddedAnime: 335 — order by created_at desc, id desc.
    - fetchTopRatedAnime: 343 — `gte(average_score, minScore)` then order by score desc.
    - fetchAiringSoonAnime: 352 — `next_airing_at` between now and now+24h → order ascending.
- Dependencies
  - Database columns: `trending`, `season`, `season_year`, `created_at`, `average_score`, `next_airing_at` (indexed).
  - Supabase SDK, ISO8601 date decoding for `next_airing_at`.
- Design & Care
  - Keep section item caps small (≈12) for performance.
  - Ensure ordering is stable before applying `.range()` to avoid flicker across pages.
  - Timezones: server stores `TIMESTAMPTZ`; client converts from ISO UTC.
- Not Our Concern
  - AniList accuracy of “trending”; we surface what’s indexed in DB.

2) Discover (Editorial variants)
- Features
  - Alternate editorial layouts (compact sections, dense grids, curated cards).
- Implementation
  - EditorialDiscoverView.swift:7; EditorialCards.swift:10; EditorialCollectionView.swift:7.
  - Consume `supabaseService.animeItems` prefetch and sort/filter locally for style‑only sections.
- Dependencies
  - KuroDesignSystem constants for spacing/typography; PosterView.swift for images.
- Care
  - Don’t mix server sections with editorial placeholders without labeling; keep consistent item limits.

3) Search (Server‑Paged with Facets)
- Features
  - Text search across anime/manga with facets: TRENDING, AIRING ONLY, THIS SEASON/SEASON, NEW SEASON, CLASSICS, HIDDEN GEMS; season selector; reset filters.
- Implementation
  - View: EditorialSearchView.swift:7 (search bar, pills, results, empty/placeholder), ContentView.swift lines ~733–906 for season UI.
  - Service: SupabaseService.swift:240–304 (paged search for manga/anime with filters and stable ordering); helper setters: 222, 224, 233.
- Dependencies
  - DB full‑text search fields (anime: `title_english,title_romaji,description_normalized`; manga: `title_english,title_romaji,description_normalized`).
  - Indexed columns for filters (trending, season_year, average_score).
- Care
  - Always order before `.range()` for deterministic paging windows.
  - Combine filters conservatively to avoid empty result churn.
  - “Season” facet sets explicit `season` + `season_year` equality; keep season picker state in sync.
- Not Our Concern
  - FTS ranking logic; we rely on DB index configuration.

4) Collection & User Lists (Anime + Manga)
- Features
  - Toggle Anime/Manga tabs; filter by list status (Watching/Planned/Completed/…).
  - Add/remove to list; toggle favorite via rating; progress bar display.
- Implementation
  - View: Collection/CollectionManagementView.swift:6 (toggle), 159–208 (status filters), 209–292 (cards), 360 (add sheet UX).
  - Service: SupabaseService.swift
    - fetchUserLists: 390 — loads both `anime_user_lists` and `manga_user_lists`; maps to unified `UserList` (id, mediaId, mediaType, status, score, timestamps).
    - addToList: 481 — upsert row into `anime_user_lists` or `manga_user_lists` with user_id from auth; default progress 0.
    - removeFromList: 524 — delete by (user_id, media_id).
    - updateListScore: 652 — updates rating (0–10 scaled from 0–100).
    - UI helpers: isInCollection 625, isFavorited 629, toggleInCollection 634, toggleFavorite 642.
- Dependencies
  - Auth: `client.auth.signInAnonymously()`; RLS policies ensure users manage their own list rows.
  - Unified view: 08_create_user_lists_view.sql makes future cross‑media queries trivial.
- Care
  - Ensure `user_id` types match (UUID string in app vs DB text conversion in view).
  - Keep writes idempotent; `upsert` avoids duplicates.
  - Progress display is local UI; backend accepts updates if added later.
- Not Our Concern
  - Cross‑user sharing/visibility (lists are private by policy unless expanded later).

5) Detail Pages (Anime & Manga)
- Features
  - Rich hero/title/stats/description/genres; Episodes (Anime), Chapters/Volumes (Manga); action buttons.
- Implementation
  - AnimeDetailView.swift:6; sections at 71, 122, 164, 232, 269, 308, 363, 386…
  - MangaDetailView.swift:6; sections at 76, 127, 169, 209, 264, 287, 349, 371…
  - Episodes are imported from AniList `streamingEpisodes` (when available); chapters/volumes may be placeholders from counts.
- Dependencies
  - Edge functions populate `episodes`, `chapters`, `volumes` tables.
- Care
  - Many anime won’t have full episode lists from AniList; keep placeholders minimal.
  - Manga next chapter schedule is generally unavailable.

6) Browse
- Features
  - Filtered grids for anime/manga by genre, length, status.
- Implementation
  - BrowseView.swift:7; filter chip and grid components at 257, 280.
- Dependencies
  - Consumes `supabaseService.animeItems/mangaItems`; no additional API calls.
- Care
  - Keep client filters simple; heavy filters belong server‑side.

7) Supabase Service & Auth
- Features
  - Supabase client setup, anon sign‑in, paging, search, curated sections, list CRUD, basic realtime (timer fallback).
- Implementation
  - SupabaseService.swift:12; anon sign-in 84; paging 100/152; search 189; sections 307–365; lists 390–665; timer 613.
- Dependencies
  - Supabase SDK; Info.plist/env config via AppConfig.swift:8; fallback URL/key (replace with anon key for prod).
- Care
  - Never ship service role keys; move to Info.plist/env/CI.
  - Always order before range; consistent sorts prevent unstable pagination.
  - Date decoding: ensure ISO strings from DB decode into Date (next_airing_at, created/updated).

8) Edge Functions: Imports
- Features
  - bulk‑import‑anime: idempotent AniList sync; episodes refresh; relationships upsert.
  - bulk‑import‑manga: idempotent AniList sync; create chapters/volumes from counts; relationships upsert.
- Implementation
  - supabase/functions/bulk-import-anime/index.ts (209 lines) and …/bulk-import-manga/index.ts (200 lines).
  - Inputs: `startPage`, `pagesPerBatch`, `useCursor`, `runToEnd`, `maxPagesPerRun`, `timeBudgetMs`.
  - Internals: AniList GraphQL (perPage 50), pacing (delay ≈670ms), upserts by `anilist_id`, relationship upserts, episodes delete+insert.
- Dependencies
  - Tables: anime, episodes, studios, tags, characters, staff and all join tables.
  - import_state cursor table (09_import_state.sql) when `useCursor=true`.
- Care
  - Respect function time budgets; stagger schedules; logs and counts for observability.
  - MAL id uniqueness can conflict if present; upsert by anilist_id is safer.

9) Edge Function: Mirror Images
- Features
  - Download remote URLs, upload to Storage, rewrite DB URL fields to Storage public URLs. Supports ANIME, MANGA, CHARACTER, STAFF.
- Implementation
  - supabase/functions/mirror-images/index.ts (214 lines). Skip‑if‑mirrored logic + cacheControl; uploads with upsert; content-type → extension mapping.
- Dependencies
  - Storage bucket `media` (public); DB columns for image fields; Storage public URL API.
- Care
  - Keep overwrite=false normally; run staggered offset batches; verify bucket public policy.
  - Handle content types (webp/png/jpg); errors are skipped.

10) Database & Policies
- Features
  - Normalized schema with internal IDs; external IDs for sync; comprehensive indexes; RLS policies; triggers.
- Implementation
  - 02_comprehensive_table_creation.sql (748 lines): tables, joins, indexes, triggers, RLS/policies.
  - user_lists view: 08_create_user_lists_view.sql.
  - import_state: 09_import_state.sql.
- Care
  - Create indexes for any new filters; keep RLS aligned with app’s auth (anon read, user managed lists).

11) Config & Secrets
- Features
  - AppConfig reads SUPABASE_URL/ANON_KEY from Info.plist/env with fallback logging.
- Implementation
  - Kuro/Services/AppConfig.swift:8; SupabaseService.swift:55–70.
- Care
  - Replace fallback service role with anon key; configure CI to inject secrets.

12) Performance & UX Notes
- Use `.transaction { $0.animation = nil }` in large ScrollViews (see DiscoverView.swift and Collection) to avoid jank on data refresh.
- Limit visible items per section; prefer lazy grids.
- Preload limited pages on appear, then paginate.

13) Error Handling & Logging
- SupabaseService keeps `errorMessage` for user feedback; prints detailed console errors (`❌ …`).
- Edge functions return JSON `{ success, results | error }` for dashboards/scripts.

14) Realtime
- Current approach uses a timer (subscribeToUpdates) to refresh anime and lists.
- To upgrade: add Supabase Realtime subscriptions on `anime_user_lists`/`manga_user_lists` channels keyed by auth user; debounce UI updates.

