PART-02 Codebase Map & Rules
============================

Repository Structure (key paths)
- Kuro/Services
  - SupabaseService.swift: central service and client, paging, search, curated sections, lists.
  - AppConfig.swift: resolves SUPABASE_URL and SUPABASE_ANON_KEY from Info.plist/env.
- Kuro/Models
  - SupabaseModels.swift: Codable models for Anime, Manga, Episode, UserList, etc.
- Kuro/Views
  - DiscoverView.swift, EditorialDiscoverView.swift: server-driven sections + editorial layouts.
  - EditorialCollectionView.swift, Collection/CollectionManagementView.swift: collection UX and list filtering.
  - EditorialSearchView.swift, SearchView.swift: server-paged text search + facets.
- supabase/functions
  - bulk-import-anime, bulk-import-manga: Edge Functions for ingestion.
  - mirror-images: Edge Function for image mirroring to Storage.
- SQL & Docs
  - 02_comprehensive_table_creation.sql: core schema, indexes, RLS, triggers.
  - 08_create_user_lists_view.sql: unified user_lists view.
  - 09_import_state.sql: cursor storage for scheduled imports.
  - SCHEDULES.md: cron payloads for imports and mirroring.

Critical File References
- Supabase URL/key source and fallback: Kuro/Services/SupabaseService.swift:55–70, Kuro/Services/AppConfig.swift:1
- Server-driven Discover queries: Kuro/Services/SupabaseService.swift:307–365
- Search paging + filters: Kuro/Services/SupabaseService.swift:240–304
- Mirror-images function (skip-if-mirrored + cacheControl): supabase/functions/mirror-images/index.ts:140–220 and 160–190
- Schema (user lists, episodes/chapters/volumes, joins, indexes, RLS): 02_comprehensive_table_creation.sql:150 and onward
- Unified view: 08_create_user_lists_view.sql:1

Rules for This Codebase
- Config
  - Never hardcode service-role keys in production builds. Provide `SUPABASE_URL` and `SUPABASE_ANON_KEY` via Info.plist/env/CI.
- Schema/Edge Functions
  - Keep SQL and function sources in repo; any DB change must include a matching SQL migration file or function patch.
  - Functions must be idempotent; upsert with explicit `onConflict` and safe deletes per-entity when refreshing.
- App Code Style
  - Keep changes minimal and surgical; favor existing patterns in models and service API.
  - Avoid one-letter variables; no inline copyrights.
- Knowledge Updates (must-follow)
  - When modifying code, update the corresponding sections in PART-01 to PART-06.
  - Do not append blindly; locate the right section and edit in-place. If new scope, create a new subsection and link it from INDEX and the nearest relevant part.
  - Add file path + line references (e.g., `Kuro/Services/SupabaseService.swift:307`) to anchor changes.

Quick TODO Summary (see PART-06 for full list)
- Replace fallback service-role key with proper anon key via Info.plist/env.
- Deploy mirror-images and set staggered schedules; sweep ANIME/MANGA/CHARACTER/STAFF.
- Keep import schedules running to expand dataset; monitor time budgets.
- Consider Supabase Realtime (or subscriptions) for lists instead of timer polling.
- Harden decoding for dates/JSON tags if mismatches appear.
- Clean tests; remove any Firebase remnants or configure properly.

LLM Reading Guidance
- For backend specifics (tables, indexes, RLS), open PART-03.
- For service methods and queries used on-device, open PART-04 and code references above.
- For end-to-end dataflow or API tuning, open PART-05.

