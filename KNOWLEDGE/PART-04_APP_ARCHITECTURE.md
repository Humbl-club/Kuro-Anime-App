PART-04 App Architecture
========================

Runtime Environment
- SwiftUI app; Observation framework; optional Supabase SDK import. If SDK isn’t present the app runs a mock service.
- Config: App reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from Info.plist/env; otherwise uses fallback.
  - Kuro/Services/SupabaseService.swift:55–70
  - Kuro/Services/AppConfig.swift:1

Core Service
- SupabaseService domain split
  - Kuro/Services/SupabaseService.swift: auth/bootstrap, collection, clubs/social, detail data, caches
  - Kuro/Services/SupabaseService+Browse.swift: browse keyset paging + browse query helpers
  - Kuro/Services/SupabaseService+Recommendations.swift: similar-title recommendation hydration and batched ID fetches
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
- EditorialCollectionView.swift + EditorialCollectionComponents.swift: collection shell/state plus extracted filters, grid/list cards, empty/loading states, batch actions.
- EditorialSearchView.swift & SearchView.swift: text search with facets and optional season selector when “SEASON” active.
- Kuro/Views/PosterView.swift, EditorialCards.swift, BrowseComponents.swift, and ClubDetailSections.swift: reusable UI components consumed by the main screens.

Key UI Behaviors
- Discover prefetch on appear, with server queries layered to ensure accurate sections (Trending/Airing-Only toggle, Current Season window).
- Search applies server-side filters (trending, airingOnly, season/year) and paged `range` queries for stable ordering.
- Collection Management toggles between Anime/Manga and filters by status using in-app `userLists` (fetched from normalized tables).

Config & Secrets
- Replace fallback service-role key in SupabaseService with anon key via Info.plist/env for production.
- Consider per-env xcconfig or Info.plist variants and CI secret injection (not committed).
