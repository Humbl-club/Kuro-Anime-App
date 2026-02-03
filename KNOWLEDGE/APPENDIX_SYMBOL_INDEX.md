APPENDIX Symbol Index (Types & Functions)
=========================================

Purpose
- Per-file anchors to top-level types (class/struct/enum/protocol) and notable functions for precise referencing.

Swift Sources
- Kuro/ContentView.swift
  - struct ContentView: View — line 21
  - struct KuroRootView: View — 31
  - struct KuroLaunchView: View — 51
  - struct KuroMainView: View — 85
  - struct KuroHeaderNew: View — 151
  - struct DiscoverViewNew: View — 203
  - struct DiscoverSectionNew: View — 286
  - struct LoadingStateViewNew: View — 327
  - struct SophisticatedCardLoading: View — 361
  - struct DiscoverSection: View — 427
  - struct LoadingStateView: View — 474
  - struct DiscoverEmptyStateView: View — 532
  - struct CollectionViewSimple: View — 553
  - struct SearchViewNew: View — 726
  - struct CategoryPillSelectable: View — 1083
  - struct SearchResultRowReal: View — 1108
  - struct CollectionCardLoading: View — 1200
  - struct CollectionCardReal: View — 1242
  - struct MoodPillSimple: View — 1331
  - struct FeaturedCardSimple: View — 1355
  - struct CollectionCardSimple: View — 1395
  - struct FilterTabSimple: View — 1429
  - struct CategoryPillSimple: View — 1452
  - struct SearchResultRowSimple: View — 1469
  - struct SophisticatedAnimeCard: View — 1514
  - struct DiscoverCardElegant: View — 1630
  - struct DiscoverCardLoading: View — 1703
  - struct FeaturedCardReal: View — 1736
  - struct FeaturedCardLoading: View — 1796

- Kuro/Design/KuroDesignSystem.swift
  - struct KuroDesignSpacing — 91
  - struct KuroSpacing — 141
  - struct KuroRadius — 152
  - struct KuroShadow — 171
  - struct KuroAnimation — 203
  - struct KuroScreen — 243
  - struct ResponsiveLayout — 289
  - struct KuroAccessibility — 319
  - struct KuroiOS26 — 370
  - struct KuroCardMetrics — 391
  - struct KuroStyle — 418
  - struct EditorialLayout — 457

- Kuro/KuroApp.swift
  - struct KuroApp: App — 11

- Kuro/Models/SupabaseModels.swift
  - protocol MediaDisplayable — 4
  - struct Media — 17
  - struct Anime — 78
  - struct Manga — 223
  - struct UserList — 304
  - enum ListStatus — 349
  - struct Episode — 369

- Kuro/Services/AppConfig.swift
  - struct AppConfig — 8

- Kuro/Services/SupabaseService.swift
  - class SupabaseService — 12
  - func signInAnonymously — 84
  - func setPageSize — 90
  - func resetAnimePaging — 94
  - func fetchNextAnimePage — 100
  - func prefetchAnime — 127
  - func fetchAnime — 137
  - func resetMangaPaging — 146
  - func fetchNextMangaPage — 152
  - func prefetchManga — 179
  - func searchContent — 189
  - func setSearchPageSize — 222
  - func resetSearch — 224
  - func setSearchFilters — 233
  - func fetchNextSearchPage — 237
  - func fetchTrendingAnime — 307
  - func fetchCurrentSeasonAnime — 316
  - func fetchSeasonAnime — 326
  - func fetchNewlyAddedAnime — 335
  - func fetchTopRatedAnime — 343
  - func fetchAiringSoonAnime — 352
  - func fetchUserLists — 390
  - func addToList — 481
  - func removeFromList — 524
  - func filterByGenre — 551
  - func getByMood — 575
  - func subscribeToUpdates — 613
  - func isInCollection — 625
  - func isFavorited — 629
  - func toggleInCollection — 634
  - func toggleFavorite — 642
  - (Mock) class SupabaseService — 679 (fallback when SDK missing)

- Kuro/Views/BrowseView.swift
  - struct BrowseView — 7
  - struct FilterChip — 257
  - struct BrowseGrid — 280
  - struct BrowseEmptyState — 312

- Kuro/Views/Cards.swift
  - enum CardStatus — 7
  - struct SmartBadge — 39
  - struct QuickActionBar — 105
  - struct SharedVerticalAnimeCard — 174
  - struct SharedHorizontalAnimeCard — 386
  - struct CompactLabelStyle — 586
  - func makeBody — 587

- Kuro/Views/Collection/CollectionManagementView.swift
  - struct CollectionManagementView — 6
  - struct CollectionHeader — 121
  - struct StatusFilterBar — 159
  - struct StatusFilterButton — 185
  - struct CollectionItemCard — 209
  - struct ProgressBar — 265
  - struct EmptyCollectionView — 293
  - struct AddToListSheet — 360
  - struct MediaPreview — 497
  - struct StatusCard — 548

- Kuro/Views/CountdownTimer.swift
  - struct NextEpisodeCountdown — 7

- Kuro/Views/DetailPages/AnimeDetailView.swift
  - struct AnimeDetailView — 6
  - struct HeroSection — 71
  - struct TitleSection — 122
  - struct StatsGrid — 164
  - struct StatCard — 204
  - struct DescriptionSection — 232
  - struct GenresSection — 269
  - struct GenreTag — 290
  - struct EpisodesSection — 308
  - struct EpisodeRow — 363
  - struct ActionButtons — 386
  - struct SecondaryActionButton — 425
  - struct BackButton — 451
  - struct FlowLayout — 473 (methods 476, 485)

- Kuro/Views/DetailPages/MangaDetailView.swift
  - struct MangaDetailView — 6
  - struct MangaHeroSection — 76
  - struct MangaTitleSection — 127
  - struct MangaStatsGrid — 169
  - struct ChaptersSection — 209
  - struct ChapterRow — 264
  - struct VolumesSection — 287
  - struct VolumeCard — 349
  - struct MangaActionButtons — 371

- Kuro/Views/DiscoverView.swift
  - struct DiscoverView — 6
  - struct HeroFeaturedCard — 223
  - struct HorizontalSection — 332
  - struct VerticalGridSection — 391
  - struct VerticalGridCard — 435
  - struct DiscoverLoadingView — 484
  - struct DiscoverEmptyView — 520

- Kuro/Views/DiscoverViewModel.swift
  - func update(with:) — 27
  - func updateManga(with:) — 67
  - enum DiscoverVMSection — 90

- Kuro/Views/EditorialCards.swift
  - struct EditorialHeroCard — 10
  - struct EditorialFeatureCard — 104
  - struct EditorialCompactCard — 174
  - struct EditorialGridCard — 247
  - struct EditorialListRow — 332

- Kuro/Views/EditorialCollectionView.swift
  - struct EditorialCollectionView — 7
  - struct EditorialFilterBar — 131
  - struct EditorialFilterTab — 155
  - struct EditorialCollectionGrid — 181
  - struct EditorialCollectionLoading — 232
  - struct EditorialCollectionEmpty — 266
  - struct InstructionRow — 315
  - struct EditorialMasonryGrid — 336
  - struct CollectionGridCard — 390

- Kuro/Views/EditorialDiscoverView.swift
  - struct EditorialDiscoverView — 7
  - struct CompactHorizontalSection — 116
  - struct Dense2ColumnSection — 152
  - struct CompactAnimeCard — 212
  - struct GridAnimeCard — 306
  - struct EditorialLoadingView — 454
  - struct EditorialEmptyView — 482
  - struct CompactHorizontalMangaSection — 502
  - struct Dense2ColumnMangaSection — 535
  - struct Dense2ColumnSectionFixed — 588
  - struct Dense2ColumnMangaSectionFixed — 644

- Kuro/Views/EditorialSearchView.swift
  - struct EditorialSearchView — 7
  - struct EditorialSearchBar — 159
  - struct EditorialCategoryFilters — 206
  - struct EditorialCategoryPill — 235
  - struct EditorialSearchResults — 262
  - struct SearchResultRow — 299
  - struct EditorialSearchEmpty — 388
  - struct EditorialSearchPlaceholder — 427

- Kuro/Views/SearchView.swift
  - func normalized() — 4
  - func tokens() — 7
  - struct SearchView — 14

- Kuro/Views/SearchViewModel.swift
  - func updateQuery — 12
  - func toggleCategory — 17
  - func search — 36
  - func normalized — 72
  - func tokens — 75

- Kuro/Views/SettingsView.swift
  - struct SettingsView — 7
  - struct StatBox — 133
  - struct SettingsRow — 158

- Kuro/Views/UIComponents.swift
  - struct KuroHeader — 4
  - struct PageDots — 57

- KuroTests/KuroTests.swift
  - struct KuroTests — 12
  - func testAppLaunch — 15
  - func testUIComponents — 23

- KuroUITests/KuroUITests.swift
  - func testExample — 26
  - func testLaunchPerformance — 35

- KuroUITests/KuroUITestsLaunchTests.swift
  - func testLaunch — 21

- PosterView.swift
  - struct PosterView — 3

