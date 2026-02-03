APPENDIX View ↔ Service Links
==============================

Purpose
- Map UI views to SupabaseService methods and data used.

DiscoverView.swift
- On appear:
  - Prefetch: `prefetchAnime(total:)` (pageSize set to 50; 300–500 total based on screen)
  - Sections:
    - Trending (all/airing only): `fetchTrendingAnime(limit:, onlyAiring:)`
    - Current Season (season+year, airing): `fetchSeasonAnime(season:, year:, limit:, onlyAiring:true)`
    - Newly Added: `fetchNewlyAddedAnime(limit:)`
    - Top Rated: `fetchTopRatedAnime(limit:, minScore:)`
    - Airing Soon: `fetchAiringSoonAnime(hours:, limit:)`

EditorialDiscoverView.swift
- Composes curated sections from `supabaseService.animeItems` (prefetch via app lifecycle or other views).

EditorialSearchView.swift
- Uses service paged search:
  - `resetSearch(query:isManga:)`
  - `setSearchFilters(_:)`
  - `fetchNextSearchPage()` (applies filters: trending/newSeason/classics/hiddenGems/airingOnly/season)

Collection/CollectionManagementView.swift
- Loads user lists: `fetchUserLists()`
- Prefetch content: `prefetchAnime(total:)`, `prefetchManga(total:)`
- Uses in-memory `userLists` to filter Anime and Manga sections.
- Item actions: `toggleInCollection(animeId:)` (calls add/remove list), `isInCollection`, `isFavorited`, `toggleFavorite` (updates rating).

DetailPages/AnimeDetailView.swift
- Episodes section renders `Episode` models (populated by importer into `episodes` table and fetched as part of detail flows).

BrowseView.swift
- Consumes `supabaseService.animeItems/mangaItems` with client-side filters.

SearchView.swift
- Legacy local search utilities (`normalized`, `tokens`) — server search is in `EditorialSearchView` via service.

