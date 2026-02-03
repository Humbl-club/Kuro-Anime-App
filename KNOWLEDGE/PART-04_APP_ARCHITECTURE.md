PART-04 App Architecture
========================

Runtime Environment
- SwiftUI app; Observation framework; optional Supabase SDK import. If SDK isn’t present the app runs a mock service.
- Config: App reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from Info.plist/env; otherwise uses fallback.
  - Kuro/Services/SupabaseService.swift:55–70
  - Kuro/Services/AppConfig.swift:1

Core Service
- SupabaseService (Kuro/Services/SupabaseService.swift:1)
  - Auth: `signInAnonymously()` uses Supabase auth.
  - Paging: `fetchNextAnimePage`, `fetchNextMangaPage`; `prefetchAnime/Manga(total:)` helpers.
  - Search: server-paged text search with filters (trending/newSeason/classics/hiddenGems/airingOnly/season).
    - See Kuro/Services/SupabaseService.swift:240–304
  - Server-driven Discover sections (Anime):
    - `fetchTrendingAnime`, `fetchCurrentSeasonAnime`, `fetchSeasonAnime`, `fetchNewlyAddedAnime`, `fetchTopRatedAnime`, `fetchAiringSoonAnime`
    - See Kuro/Services/SupabaseService.swift:307–365
  - User lists: load, add/remove/update via `anime_user_lists` / `manga_user_lists`; unified in-app mapping compatible with `user_lists` view.
    - Load: Kuro/Services/SupabaseService.swift:390–460
    - Write: add/remove/update rating: 486–531 and 612–628
  - Realtime: placeholder `subscribeToUpdates()` uses a timer polling pattern; can be upgraded to Supabase Realtime.

Models
- Kuro/Models/SupabaseModels.swift:1
  - Anime/Manga: column-aligned Codable structs with computed UI helpers (e.g., `displayTitle`, `displayImage`).
  - Episode, UserList, ListStatus enumerations; decoding aligns with server fields (e.g., `next_airing_at` as Date).

Views (selected)
- DiscoverView.swift: server-driven sections + season picker + “Airing Soon”; uses SupabaseService methods above.
- EditorialDiscoverView.swift: alternative editorial layout using service data.
- EditorialCollectionView.swift & Collection/CollectionManagementView.swift: user list filtering for anime and manga; grid cards, progress visualization.
- EditorialSearchView.swift & SearchView.swift: text search with facets and optional season selector when “SEASON” active.
- PosterView.swift and EditorialCards.swift: UI components consumed by sections.

Key UI Behaviors
- Discover prefetch on appear, with server queries layered to ensure accurate sections (Trending/Airing-Only toggle, Current Season window).
- Search applies server-side filters (trending, airingOnly, season/year) and paged `range` queries for stable ordering.
- Collection Management toggles between Anime/Manga and filters by status using in-app `userLists` (fetched from normalized tables).

Config & Secrets
- Replace fallback service-role key in SupabaseService with anon key via Info.plist/env for production.
- Consider per-env xcconfig or Info.plist variants and CI secret injection (not committed).

