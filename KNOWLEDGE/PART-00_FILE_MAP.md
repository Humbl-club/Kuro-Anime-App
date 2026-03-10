PART-00 File Map (Exhaustive)
=============================

Scope
- High-level repository file map grouped by category, with key file purposes and the most important surfaces called out explicitly. For source-level anchors, use APPENDIX_SYMBOL_INDEX.md.

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
  - KNOWLEDGE/PART-07_FUNCTIONALITY_DEEP_DIVES.md
  - SCHEDULES.md — Cron payloads for imports/mirroring.
  - archive/ — 17 historical design docs and superseded knowledge bases (moved 2026-03-10).

- App (Swift) — 68 files in `Kuro/`

  Entry points:
  - Kuro/KuroApp.swift — `@main`, scenePhase lifecycle, NetworkMonitor + SupabaseService injection, `.onOpenURL` deep link handler
  - Kuro/ContentView.swift — 5-page swipe pager, header (KURO wordmark / section title / search + profile), deep link sheet presentation

  Services (11 files):
  - Kuro/Services/SupabaseService.swift — core data layer, RPC calls, caching, auth bootstrap, `fmService`, `withRetry` helper
  - Kuro/Services/AppleFMService.swift — on-device FM (4 capabilities, FMProvider protocol, StubFMProvider fallback)
  - Kuro/Services/AppConfig.swift — reads SUPABASE_URL/ANON_KEY from Info.plist/env
  - Kuro/Services/NetworkMonitor.swift — NWPathMonitor connectivity, `isConnected`, offline banner
  - Kuro/Services/FeatureFlags.swift — server-controlled flags, UserDefaults cache, stable hash rollout
  - Kuro/Services/DeepLinkRouter.swift — `enum DeepLink`, `kuro://` URL parsing
  - Kuro/Services/ConciergeAnalytics.swift — concierge + club interaction telemetry
  - Kuro/Services/TextNormalization.swift — search/parsing text utilities
  - Kuro/Services/ImagePipeline.swift — NSCache (~80MB) + URLCache disk cache, downsampling, request dedup
  - Kuro/Services/KuroDiskDetailCache.swift — on-disk detail page cache
  - Kuro/Services/KuroPerf.swift — performance measurement utilities
  - Kuro/Services/SupabaseRPCParams.swift — RPC parameter structs

  Concierge UI (10 files):
  - Kuro/Views/ConciergeView.swift — main concierge view controller
  - Kuro/Views/ConciergeEditorialShell.swift — editorial shell wrapper
  - Kuro/Views/ConciergeComponents.swift — shared components + curated copy layer (EN/DE mode titles)
  - Kuro/Views/ConciergeInputField.swift — text input field
  - Kuro/Views/ConciergeComposerDock.swift — input composer dock
  - Kuro/Views/ConciergeActionFooter.swift — action footer bar
  - Kuro/Views/ConciergeIntentDeck.swift — quick-action intent cards
  - Kuro/Views/ConciergeImportCards.swift — import preview/confirm cards
  - Kuro/Views/ConciergeRecommendationRails.swift — recommendation rail rendering
  - Kuro/Views/ConciergeResponseStage.swift — response stage rendering

  Views (remaining):
  - Kuro/Views/EditorialDiscoverView.swift — Discover page
  - Kuro/Views/BrowseView.swift — Browse page (full-page, not a sheet)
  - Kuro/Views/EditorialCollectionView.swift — Collection page
  - Kuro/Views/ClubsView.swift — Clubs list page (enriched cards, unread dots)
  - Kuro/Views/ClubDetailView.swift — Club detail (3-tab: Rails/This Week/Polls)
  - Kuro/Views/ClubCreateSheets.swift — Create/join club sheets
  - Kuro/Views/EditorialSearchView.swift — Search sheet
  - Kuro/Views/OnboardingView.swift — First-launch onboarding
  - Kuro/Views/ProfileView.swift — Profile menu (includes Clubs secondary access)
  - Kuro/Views/AuthView.swift — Authentication
  - Kuro/Views/DetailPages/AnimeDetailView.swift — Anime detail page
  - Kuro/Views/DetailPages/MangaDetailView.swift — Manga detail page
  - Kuro/Views/DetailPages/MediaDetailSheet.swift — Shared media detail sheet
  - Kuro/Views/DetailPages/ClubActivitySection.swift — Club activity on detail pages
  - Kuro/Views/DetailPages/FriendsActivitySection.swift — Friend activity on detail pages
  - Kuro/Views/DetailPages/ExternalLinksSection.swift — External links section
  - Kuro/Views/DetailPages/CastSection.swift — Characters section on detail pages
  - Kuro/Views/DetailPages/CreditsSection.swift — Staff/studios/authors on detail pages
  - Kuro/Views/DetailPages/EntityDetailSheets.swift — Character/staff/studio/author detail sheets
  - Kuro/Views/DetailPages/AdaptationPathSection.swift — Adaptation ladder on detail pages
  - Kuro/Views/KuroRefinedCard.swift — Portrait + Compact card components
  - Kuro/Views/KuroCardText.swift — Card text rendering
  - Kuro/Views/KuroGlass.swift — Glass morphism effects
  - Kuro/Views/KuroCachedAsyncImage.swift — Cached async image loader
  - Kuro/Views/KuroToast.swift — Toast notifications
  - Kuro/Views/KuroTransientBanner.swift — Transient banners
  - Kuro/Views/KuroConciergeMark.swift — Concierge mark/logo
  - Kuro/Views/KuroInteractionEnvironment.swift — Interaction environment values
  - Kuro/Views/KuroLoadMoreSentinel.swift — Infinite scroll sentinel
  - Kuro/Views/KuroPagingGesture.swift — Paging gesture handler
  - Kuro/Views/KuroDeliberateTap.swift — Deliberate tap gesture
  - Kuro/Views/KuroGestureCoordinator.swift — Gesture coordination
  - Kuro/Views/KuroGesturePolicy.swift — Gesture policy constants
  - Kuro/Views/EditorialCards.swift — Editorial card components
  - Kuro/Views/Cards.swift — Shared card components
  - Kuro/Views/UIComponents.swift — Miscellaneous UI components
  - Kuro/Views/GenreHubView.swift — Genre hub view
  - Kuro/Views/CountdownTimer.swift — Countdown timer component
  - Kuro/Views/AddToListSheet.swift — Add/edit list entry sheet
  - Kuro/Views/DiscoverViewModel.swift — Discover view model (legacy)

  Design (2 files):
  - Kuro/Design/KuroDesignSystem.swift — colors, typography, spacing, radii, animations
  - Kuro/Design/Color+Hex.swift — hex color utility

  Models (2 files):
  - Kuro/Models/SupabaseModels.swift — all Supabase data models
  - Kuro/Models/DiscoverBundle.swift — discover bundle response model

- Tests
  - KuroTests/KuroTests.swift — Unit tests (CreditRole, ImportIntent, etc.)
  - KuroUITests/KuroUITests.swift — UI tests
  - KuroUITests/KuroUITestsLaunchTests.swift — Launch tests

- Supabase Edge Functions (15 deployed):
  - supabase/functions/concierge-parse/index.ts — deterministic NLP parser, title candidate search
  - supabase/functions/concierge-recommend/index.ts — deterministic recommendations + optional Groq narration (~1800 lines)
  - supabase/functions/concierge-apply/index.ts — apply parsed items to user lists
  - supabase/functions/concierge-resolve/index.ts — LLM disambiguation for ambiguous titles
  - supabase/functions/concierge-undo/index.ts — rollback last import session
  - supabase/functions/concierge-retrieve-assist/index.ts — RAG retrieval assist
  - supabase/functions/concierge-retrieve-feedback/index.ts — RAG feedback collection
  - supabase/functions/concierge-import-anilist/index.ts — AniList import helper
  - supabase/functions/bulk-import-anime/index.ts — bulk anime catalog import (requires IMPORT_SECRET)
  - supabase/functions/bulk-import-manga/index.ts — bulk manga catalog import (requires IMPORT_SECRET)
  - supabase/functions/mirror-images/index.ts — mirror external images to Storage CDN
  - supabase/functions/manga-chapter-enrich/index.ts — MangaDex chapter enrichment + mapping/match pipeline
  - supabase/functions/manga-source-review-action/index.ts — approve/reject unresolved mappings and optionally trigger re-enrich
  - supabase/functions/delete-account/index.ts — GDPR account deletion
  - supabase/functions/auth-callback/index.ts — email verification fallback redirect page (verify_jwt: false)

- Xcode project
  - Kuro.xcodeproj/project.pbxproj — Build settings.
  - Kuro.xcodeproj/... — Workspace and scheme files.

- Misc
  - database_export.json — Sample export.
  - node_modules/** — Third-party JS deps for local scripts; not part of iOS runtime.

Note: Build outputs under build/ are excluded from this map (ephemeral artifacts).
