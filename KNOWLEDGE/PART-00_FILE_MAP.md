PART-00 File Map (Exhaustive)
=============================

Scope
- Lists every repository file path (excluding build/ artifacts) grouped by category, with key file line counts and purposes. For source files, see also APPENDIX_SYMBOL_INDEX.md for type/function anchors.

Top-Level
- SQL migrations and functions source
  - 01_delete_all_tables.sql — Drop helper.
  - 02_comprehensive_table_creation.sql — Full schema, indexes, triggers, RLS, policies.
  - 03_updated_edge_function.js — Legacy function draft.
  - 04_manga_edge_function.js — Legacy manga function draft.
  - 05_fix_triggers_and_episodes.sql — Trigger/episode fixes.
  - 06_anime_edge_function_with_episodes.js — Legacy anime importer (JS).
  - 07_manga_edge_function_with_chapters.js — Legacy manga importer (JS).
  - 08_create_user_lists_view.sql — Unified `user_lists` view.
  - 09_import_state.sql — Cursor table for scheduled imports.

- Knowledge & docs
  - KNOWLEDGE/INDEX.md — Directory and navigation.
  - KNOWLEDGE/PART-01_MASTER_OVERVIEW.md
  - KNOWLEDGE/PART-02_CODEBASE_MAP_AND_RULES.md
  - KNOWLEDGE/PART-03_BACKEND_DATA_INFRA.md
  - KNOWLEDGE/PART-04_APP_ARCHITECTURE.md
  - KNOWLEDGE/PART-05_API_AND_DATAFLOW.md
  - KNOWLEDGE/PART-06_PRODUCTION_TODO.md
  - KURO_CLOUD_KNOWLEDGE.md — Prior knowledge doc.
  - KURO_CLOUD_KNOWLEDGE_ADDENDUM.md — Prior addendum.
  - COMPLETE_APP_DOCUMENTATION.md — Large prior doc.
  - DESIGN_UPDATE_OCT_8_2025.md, DISCOVER_SECTIONS_UPDATE.md, DOCUMENTATION_INDEX.md, NAVIGATION_DESIGN_LOCKED.md, SLEEK_REDESIGN_COMPLETE.md, SMART_LAYOUT_REFACTOR.md, SOPHISTICATED_DISCOVER_DESIGN.md — Design docs.
  - SCHEDULES.md — Cron payloads for imports/mirroring.

- App (Swift)
  - Kuro/KuroApp.swift (20 lines) — App entry.
  - Kuro/Design/KuroDesignSystem.swift (512) — Spacing/typography/layout constants.
  - Kuro/Models/SupabaseModels.swift (403) — Codable models (Anime/Manga/Episode/UserList/etc.).
  - Kuro/Services/AppConfig.swift (31) — Reads SUPABASE_URL/ANON_KEY from Info.plist/env.
  - Kuro/Services/SupabaseService.swift (744) — Supabase client/service: paging/search/sections/lists.
  - Kuro/ContentView.swift (1836) — Root composition and multiple view sections/components.
  - Kuro/Views/... — Feature views and UI components:
    - BrowseView.swift (338)
    - Cards.swift (598)
    - Collection/CollectionManagementView.swift (586)
    - CountdownTimer.swift (80)
    - DetailPages/AnimeDetailView.swift (522); MangaDetailView.swift (408)
    - DiscoverView.swift (539); DiscoverViewModel.swift (96)
    - EditorialCards.swift (394)
    - EditorialCollectionView.swift (547)
    - EditorialDiscoverView.swift (689)
    - EditorialSearchView.swift (462)
    - SearchView.swift (183); SearchViewModel.swift (80)
    - SettingsView.swift (199); UIComponents.swift (80)
  - PosterView.swift (101) — Poster renderer.

- Tests
  - KuroTests/KuroTests.swift (33) — Basic tests (no Firebase usage).
  - KuroUITests/KuroUITests.swift (41), KuroUITestsLaunchTests.swift (33) — UI tests stubs.

- Supabase Edge Functions (TypeScript)
  - supabase/functions/bulk-import-anime/index.ts — Anime importer.
  - supabase/functions/bulk-import-manga/index.ts — Manga importer.
  - supabase/functions/mirror-images/index.ts — Image mirroring to Storage.

- Xcode project
  - Kuro.xcodeproj/project.pbxproj — Build settings.
  - Kuro.xcodeproj/... — Workspace and scheme files; placeholder Firebase plist.

- Misc
  - database_export.json — Sample export.
  - node_modules/** — Third-party JS deps for local scripts; not part of iOS runtime.

Note: Build outputs under build/ are excluded from this map (ephemeral artifacts).

