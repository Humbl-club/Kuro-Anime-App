# Kuro — Current State of the Application (Authoritative, Technical)

**Last updated:** 2026-02-05

This document is the **authoritative, technical snapshot** of the Kuro app (iOS client + Supabase backend) and the current codebase. It is written for engineers and LLMs that need a complete and precise understanding of how the system works today.

For a non‑technical version, see: `CURRENT_APP_STATE_PLAIN.md`.

---

## 0) RULES: This file must always be updated

This file is a **contract**. It must be updated **after every single change** to the app or backend.

**Update protocol (required):**
1. Update the relevant sections in this file immediately after any change (UI, backend, schema, edge functions, scripts, cron jobs, ops, performance, etc.).
2. Add a new entry to the **Change Log** section with:
   - Date
   - Brief summary of changes
   - Commit hash(es)
3. If you are unsure where a change belongs, add a note under **Open Questions / Unknowns**.
4. If you are making changes for a new chat/LLM, this file must be the **first reference** and must reflect the current state.
5. After changes, refresh the auto-generated sections:
   ```bash
   node scripts/generate_app_state_inventory.js
   node scripts/generate_app_state_maps.js
   node scripts/generate_app_state_sources.js
   node scripts/generate_app_state_codebase_bundle.js
   # Optional (requires SUPABASE_SERVICE_ROLE_KEY + deployed admin_schema_snapshot RPC):
   node scripts/generate_app_state_live_snapshot.js
   ```

**Failure to update this file = incorrect system state.**

---

## 1) High-level architecture

**Client:** iOS SwiftUI app (`/Kuro`)
- Local caching and UI-only state.
- Uses Supabase as system of record.
- Concierge: deterministic-first parsing + LLM fallback.

**Backend:** Supabase (Postgres + Edge Functions + Storage + RPC + RLS)
- Postgres stores anime/manga catalog, user lists, recommendations, concierge sessions, and ops metrics.
- Edge Functions handle bulk imports, concierge operations, and image mirroring.
- Storage provides CDN for mirrored images (public bucket).

**Primary data source:** AniList (imported via scripts + edge functions).

---

## 1.1) Configuration + secrets (where keys live)

### iOS app config
- `Kuro/Services/AppConfig.swift` reads:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  from **Info.plist** or process env.
- If missing, `SupabaseService` uses **hardcoded fallback** URL + anon key (see `SupabaseService.init()`).

### Supabase Edge Functions env vars
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GROQ_API_KEY` (LLM)
- `GROQ_MODEL`, `GROQ_MODEL_RESOLVE` (LLM models)

### LLM flags
- `public.system_flags` controls `llm_enabled` (on/off)
- Budgets + rate limits in `public.concierge_config` (JSON)

---

## 2) Repository map (where things live)

### Root
- `Kuro/` — iOS app source (SwiftUI views, services, models)
- `supabase/` — Supabase migrations, edge functions, ops docs
- `scripts/` — import scripts, audits, load tests, ops tools
- `mockups/` — UI references
- `BROWSE_REFINED_SUMMARY.md`, `MASTER_PLAN.md`, `COMPLETE_APP_DOCUMENTATION.md` — historical docs

<!-- BEGIN AUTO-INVENTORY -->

## 2.1) Auto-generated inventory (exhaustive file lists)

Generated: **2026-02-05T13:05:07.006Z**  (git: `4d470f8` on `main`)

This section is auto-generated. Rebuild it after any repo change:
```bash
node scripts/generate_app_state_inventory.js
```

### iOS (Swift) files (count: 45)
- `Kuro/ContentView.swift`
- `Kuro/Design/KuroDesignSystem.swift`
- `Kuro/KuroApp.swift`
- `Kuro/Models/DiscoverBundle.swift`
- `Kuro/Models/SupabaseModels.swift`
- `Kuro/Services/AppConfig.swift`
- `Kuro/Services/ImagePipeline.swift`
- `Kuro/Services/KuroDiskDetailCache.swift`
- `Kuro/Services/KuroPerf.swift`
- `Kuro/Services/SupabaseRPCParams.swift`
- `Kuro/Services/SupabaseService.swift`
- `Kuro/Views/AuthView.swift`
- `Kuro/Views/BrowseView.swift`
- `Kuro/Views/BrowseViewRefined.swift`
- `Kuro/Views/Cards.swift`
- `Kuro/Views/Collection/CollectionManagementView.swift`
- `Kuro/Views/ConciergeOverlay.swift`
- `Kuro/Views/ConciergeView.swift`
- `Kuro/Views/CountdownTimer.swift`
- `Kuro/Views/DetailPages/AnimeDetailView.swift`
- `Kuro/Views/DetailPages/MangaDetailView.swift`
- `Kuro/Views/DetailPages/MediaDetailSheet.swift`
- `Kuro/Views/DiscoverView.swift`
- `Kuro/Views/DiscoverViewModel.swift`
- `Kuro/Views/EditorialCards.swift`
- `Kuro/Views/EditorialCollectionView.swift`
- `Kuro/Views/EditorialDiscoverView.swift`
- `Kuro/Views/EditorialSearchView.swift`
- `Kuro/Views/GenreHubView.swift`
- `Kuro/Views/KuroCachedAsyncImage.swift`
- `Kuro/Views/KuroCardText.swift`
- `Kuro/Views/KuroChanMascot.swift`
- `Kuro/Views/KuroConciergeMark.swift`
- `Kuro/Views/KuroGlass.swift`
- `Kuro/Views/KuroInteractionEnvironment.swift`
- `Kuro/Views/KuroLoadMoreSentinel.swift`
- `Kuro/Views/KuroPagingGesture.swift`
- `Kuro/Views/KuroRefinedCard.swift`
- `Kuro/Views/KuroToast.swift`
- `Kuro/Views/KuroTransientBanner.swift`
- `Kuro/Views/ProfileView.swift`
- `Kuro/Views/SearchView.swift`
- `Kuro/Views/SearchViewModel.swift`
- `Kuro/Views/SettingsView.swift`
- `Kuro/Views/UIComponents.swift`

### Supabase migrations (count: 27)
- `supabase/migrations/20250109_remote_applied_placeholder.sql`
- `supabase/migrations/20250909_remote_applied_placeholder.sql`
- `supabase/migrations/20250917_remote_applied_placeholder.sql`
- `supabase/migrations/20260203171100_concierge_core.sql`
- `supabase/migrations/20260203171110_concierge_title_search_rebuild.sql`
- `supabase/migrations/20260203181000_profiles_insert_policy.sql`
- `supabase/migrations/20260203183000_concierge_recommend_rpc.sql`
- `supabase/migrations/20260203190000_editorial_recommend_engine.sql`
- `supabase/migrations/20260203191500_recommend_focus_tags.sql`
- `supabase/migrations/20260203194500_recommend_focus_filter.sql`
- `supabase/migrations/20260203201000_editorial_story_boosts.sql`
- `supabase/migrations/20260203203000_recommend_seed_similarity.sql`
- `supabase/migrations/20260203223000_scale_perf_bundle_and_indexes.sql`
- `supabase/migrations/20260203224500_browse_rpc_add_created_at.sql`
- `supabase/migrations/20260203233500_mirror_runs.sql`
- `supabase/migrations/20260203235500_search_rpc_keyset.sql`
- `supabase/migrations/20260204010500_collection_paging_rpc.sql`
- `supabase/migrations/20260204124500_title_aliases.sql`
- `supabase/migrations/20260204133000_collection_feed_paging_rpc.sql`
- `supabase/migrations/20260204221500_concierge_rate_limits_and_llm_budgets.sql`
- `supabase/migrations/20260204233000_recommend_seed_similarity_allow_anon.sql`
- `supabase/migrations/20260204233010_concierge_ops_observability_and_retention.sql`
- `supabase/migrations/20260204234500_recommend_seed_similarity_ranked_tags.sql`
- `supabase/migrations/20260204235500_recommend_seed_similarity_genre_gate.sql`
- `supabase/migrations/20260204240500_backfill_anime_episodes_from_next_airing.sql`
- `supabase/migrations/20260205000500_concierge_global_llm_budget_and_default_tuning.sql`
- `supabase/migrations/20260205002000_concierge_budget_raise.sql`

### Supabase Edge Functions (index.ts) (count: 8)
- `supabase/functions/bulk-import-anime/index.ts`
- `supabase/functions/bulk-import-manga/index.ts`
- `supabase/functions/concierge-apply/index.ts`
- `supabase/functions/concierge-parse/index.ts`
- `supabase/functions/concierge-recommend/index.ts`
- `supabase/functions/concierge-resolve/index.ts`
- `supabase/functions/concierge-undo/index.ts`
- `supabase/functions/mirror-images/index.ts`

### Repo scripts (count: 16)
- `scripts/apply_remote_sql.js`
- `scripts/check_cron_health.js`
- `scripts/collect_db_metrics.js`
- `scripts/concierge_corpus_generate.js`
- `scripts/concierge_eval_parse.js`
- `scripts/db_state.sql`
- `scripts/generate_app_state_inventory.js`
- `scripts/generate_app_state_maps.js`
- `scripts/genre_audit.js`
- `scripts/import_anilist_fast.js`
- `scripts/import_anilist_local.js`
- `scripts/load_test_concierge.js`
- `scripts/report_airing_window.js`
- `scripts/run_full_import.js`
- `scripts/smoke_concierge_recommend.js`
- `scripts/smoke_magic_parse_apply.js`


<!-- END AUTO-INVENTORY -->

### iOS app structure (`/Kuro`)
- `Kuro/ContentView.swift` — app entry point + navigation/swipe pager + top header
- `Kuro/Services/SupabaseService.swift` — core data layer, RPC usage, caching
- `Kuro/Views/` — SwiftUI UI components
- `Kuro/Models/` — data models (Anime, Manga, UserList, etc.)

### Feature-to-file map (frontend)
- **Concierge UI**: `Kuro/Views/ConciergeView.swift` (chat, import, recommend UI, toasts)
- **Discover**: `Kuro/Views/EditorialDiscoverView.swift` (sections, rails, filters)
- **Collection**: `Kuro/Views/EditorialCollectionView.swift` + list helpers in `SupabaseService`
- **Browse**: `Kuro/Views/BrowseViewRefined.swift`
- **Search**: `Kuro/Views/EditorialSearchView.swift`
- **Cards / badges**: `Kuro/Views/KuroRefinedCard.swift`, `Kuro/Views/KuroCardText.swift`
- **Glass UI**: `Kuro/Views/KuroGlass.swift`
- **Toasts**: `Kuro/Views/KuroToast.swift`
- **Image caching**: `Kuro/Views/KuroCachedAsyncImage.swift`, `Kuro/Services/ImagePipeline.swift`
- **Profile**: `Kuro/Views/ProfileView.swift`

### Supabase
- `supabase/migrations/` — schema, indexes, views, RPCs, cron jobs
- `supabase/functions/` — Edge Functions
- `supabase/CONCIERGE_OPS.md` — concierge budgets, rate limits, retention

### Edge function map
- `bulk-import-anime/` — imports anime catalog from AniList (server-side ingest)
- `bulk-import-manga/` — imports manga catalog from AniList (server-side ingest)
- `concierge-parse/` — deterministic parser; search title candidates
- `concierge-resolve/` — LLM disambiguation for ambiguous titles
- `concierge-recommend/` — deterministic recommendations + optional LLM narration
- `concierge-apply/` — apply parsed items to user lists
- `concierge-undo/` — rollback last import session
- `mirror-images/` — mirror external images to Storage CDN

### Scripts
- `scripts/import_anilist_fast.js`, `scripts/import_anilist_local.js`, `scripts/run_full_import.js` — AniList ingestion
- `scripts/genre_audit.js`, `scripts/report_airing_window.js` — data QA
- `scripts/concierge_eval_parse.js`, `scripts/concierge_corpus_generate.js`, `scripts/load_test_concierge.js` — concierge QA/ops
- `scripts/check_cron_health.js`, `scripts/collect_db_metrics.js` — ops
- `scripts/db_state.sql` — DB snapshot queries (row counts, coverage, etc.)

---

## 3) Frontend (iOS) — current UX + navigation

### Main navigation
- File: `Kuro/ContentView.swift`
- Root: `ContentView -> KuroRootView -> KuroMainView`
- Swipe order (left to right):
  1. **Concierge**
  2. **Discover**
  3. **Collection**
  4. **Browse**
  5. **Search**

### Header (top bar)
- Left: **KURO** wordmark only (no concierge icon next to it).
- Center: animated section title window (shows section name).
- On Concierge page only: a small **chat icon** appears next to the section title.
- Right: **Profile menu** (circle with initial). Dropdown contains:
  - Profile (sheet)
  - Sign Out

### Concierge
- Full left page (no floating launcher in header).
- Empty state:
  - Concierge glass intro card
  - Quick-start glass pills:
    - Paste from clipboard
    - Try example import
    - Give me a vibe
- Main features:
  - Deterministic parsing of pasted list
  - Candidate disambiguation
  - LLM fallback for ambiguous lines
  - Apply/undo sessions
  - Recommendations with LLM narration (optional)
- The floating assistant widget exists in code but is **disabled** when Concierge is used as a full page (`ConciergeView(assistantEnabled: false)` in the pager).
- The floating assistant widget exists in `ConciergeView` but is **disabled** when used as a full page (`ConciergeView(assistantEnabled: false)` in the pager).

### Discover
- Editorial layout with sections (Essentials, Classics, New to You, Trending, etc.)
- Cards are two-column + compact horizontal rails
- Cards show rating pill + metadata line (YEAR · EPS/CH)

### Collection
- Uses collection feed + paging RPCs

### Browse + Search
- RPC-backed paging

---

## 3.1) Client data layer (SupabaseService)

Key responsibilities (file: `Kuro/Services/SupabaseService.swift`):
- **Auth bootstrap**: restores session, ensures `profiles` row, loads user lists + feed.
- **Discover**: `fetchDiscoverBundle()` uses RPC `discover_bundle`, cached with in-flight de-dupe.
- **Search**: RPCs `search_anime_page`, `search_manga_page`.
- **Browse**: RPCs `browse_anime_page`, `browse_manga_page` with sort selection.
- **Collection**: keyset paging RPCs `collection_*_page` + in-memory caches.
- **Upcoming**: `airing_next(days)` RPC + caching/backoff for rate-safe refresh.
- **Concierge**: calls Edge Functions for parse/recommend/apply/undo; caches parse + recommend.
- **Realtime**: subscribes to user-scoped channel to refresh list/collection data on changes.
- **Local caches**: `discoverBundleCache`, `conciergeParseCache`, `conciergeRecommendCache` (in-memory, TTL-based).

<!-- BEGIN AUTO-IOS-MAP -->

## 3.2) Auto iOS backend usage index

Generated: **2026-02-05T13:05:07.075Z** (git: `4d470f8`)

- Swift file scanned: `Kuro/Services/SupabaseService.swift`

### RPCs used by iOS (count: 9)
- `browse_anime_page`
- `browse_manga_page`
- `collection_anime_page`
- `collection_feed_page`
- `collection_manga_page`
- `discover_bundle`
- `recommend_ids_similar_to_seeds`
- `search_anime_page`
- `search_manga_page`

### Edge Functions invoked by iOS (count: 5)
- `concierge-apply`
- `concierge-parse`
- `concierge-recommend`
- `concierge-resolve`
- `concierge-undo`


<!-- END AUTO-IOS-MAP -->

---

## 4) Design system (current)

**Design philosophy:** Editorial minimalism + premium glass surfaces

**Key design primitives**
- `KuroGlassCard` in `Kuro/Views/KuroGlass.swift`
- `KuroGlassPill` in `Kuro/Views/KuroGlass.swift`
- `KuroScoreBadge`, `KuroPortraitCard`, `KuroCompactCard` in `Kuro/Views/KuroRefinedCard.swift`
- Concierge iconography: `KuroConciergeMark` (butler glyph) in `Kuro/Views/KuroConciergeMark.swift`

**Typography**
- Serif for titles and editorial feel
- Light weights for subtitles
- Uppercase tracking for section titles

**Card details (current)**
- Rating pill in top-right of poster
- Metadata line shows `YEAR · EPS/CH` under title
- Poster corners rounded (8–12pt depending on card type)

---

## 5) Image + CDN pipeline

### Client-side caching
- `Kuro/Views/KuroCachedAsyncImage.swift` uses `ImagePipeline`
- `Kuro/Services/ImagePipeline.swift`:
  - In-memory cache (NSCache, ~80MB)
  - URLCache-backed disk cache
  - Downsampling to max pixel size
  - Request de-dupe for in-flight images

### Server-side image mirroring
- Edge Function: `supabase/functions/mirror-images`
- Mirrors AniList image URLs into Supabase Storage public bucket
- Uses public URLs: `https://<ref>.supabase.co/storage/v1/object/public/<bucket>/<path>`
- Supports ANIME, MANGA, CHARACTER, STAFF images
- Payload supports:
  - `bucket` (default `media`)
  - `mediaTypes` (array)
  - `limit`, `offset`, `overwrite`
  - `skipIfMirrored` (default true)
  - `cacheControl` (default 604800)
  - `timeBudgetMs` (default 90000)

### Storage bucket
- Public bucket name used by default: `media`
- Public URL pattern: `https://<ref>.supabase.co/storage/v1/object/public/media/<path>`

---

## 6) Backend data model (Supabase)

### Core catalog tables
- `anime`
- `manga`
- `episodes`
- `chapters`
- `volumes`
- `characters`
- `staff`
- `studios`
- `authors`
- `tags`, `anime_tags`, `manga_tags`
- `genres`
- `external_links` (for source/streaming links)
- Join tables: `anime_characters`, `manga_characters`, `anime_staff`, `manga_staff`, `anime_studios`, `manga_authors`
- Comments: `anime_comments`, `manga_comments`

### User data
- `profiles` (1:1 with auth.users)
- `anime_user_lists`
- `manga_user_lists`
- `user_lists` (user-specific list metadata)
- `collection_feed` views (via RPC)
- `user_airing_next` view + RPCs (airing countdown/next-episode data)

### Search + discover
- `title_aliases` (for canonical search)
- `search_*` RPCs
- `discover_bundle` RPC
- `recommend_*` RPCs

### Concierge
- `import_sessions`
- `import_session_items`
- `concierge_runs`
- `concierge_parse_feedback`
- `concierge_config` (rate limits + budgets JSON)
- `rate_limit_buckets`
- `llm_daily_usage`
- `system_flags` (e.g., `llm_enabled`)
- `mirror_runs` (logs mirror-image jobs)

### Ops / metrics
- `concierge_metrics_hourly`
- `llm_usage_daily_totals`
- `rate_limit_recent_top`
- `import_state` (cursor table for scheduled AniList imports)
- `import_runs` (optional; bulk-import functions write run history if present)

**Schema definitions are in** `supabase/migrations/`.

### Auth + RLS
- Supabase Auth is used (email/password; OAuth can be added later).
- `profiles` row is ensured on sign-in (`SupabaseService.ensureProfileRow()`).
- RLS is enabled; user tables are scoped to `auth.uid()` in migrations.
- Concierge endpoints always derive user id from JWT (never accept raw user_id from client).

---

## 6.1) Unified views (important)

### `public.user_lists` view
- Defined in `08_create_user_lists_view.sql` (root).
- Unifies `anime_user_lists` + `manga_user_lists` into a single shape used by:
  - recommendation RPCs
  - concierge logic
- **This view must exist** or many recommend RPCs break.

### `public.user_airing_next` view + `public.airing_next(days)` RPC
- Defined in `10_create_user_airing_next_view.sql` and `11_airing_next_rpc.sql` (root).
- Pulls upcoming airings for titles in the user’s list.
- `user_id` is stored as `text` in those views for compatibility.

---

## 7) RPCs (current usage)

Client + edge functions rely on these RPCs:
- `discover_bundle`
- `search_anime_page`, `search_manga_page`
- `browse_anime_page`, `browse_manga_page`
- `collection_feed_page`
- `collection_anime_page`, `collection_manga_page`
- `recommend_ids_similar_to_seeds`
- `recommend_ids_premium`
- `search_titles`
- `check_concierge_rate_limit`
- `get_concierge_config`
- `log_concierge_run`
- `log_concierge_parse_feedback`
- `llm_budget_reserve`, `llm_budget_finalize`
- `llm_global_budget_reserve`, `llm_global_budget_finalize`
- `is_flag_enabled`
- `acquire_import_lock`, `release_import_lock`

<!-- BEGIN AUTO-MIGRATION-MAP -->

## 7.1) Auto migration map (objects by migration)

Generated: **2026-02-05T13:05:07.075Z** (git: `4d470f8`)

Each migration is summarized by the objects it defines. For full SQL, open the file.

### supabase/migrations/20250109_remote_applied_placeholder.sql

### supabase/migrations/20250909_remote_applied_placeholder.sql

### supabase/migrations/20250917_remote_applied_placeholder.sql

### supabase/migrations/20260203171100_concierge_core.sql
- Extensions (1): `pg_trgm`
- Tables (6): `public.concierge_runs`, `public.import_session_items`, `public.import_sessions`, `public.profiles`, `public.title_search`, `public.user_taste_profiles`
- Functions (4): `public.log_concierge_run`, `public.normalize_title`, `public.search_titles`, `public.set_updated_at`
- Policies (6): `public.import_session_items:import_session_items_own_all`, `public.import_sessions:import_sessions_own_all`, `public.profiles:profiles_select_own`, `public.profiles:profiles_update_own`, `public.title_search:title_search_select_all`, `public.user_taste_profiles:taste_profiles_own_all`
- Indexes (5): `idx_concierge_runs_user_created`, `idx_import_session_items_session`, `idx_import_sessions_user_created`, `idx_title_search_media`, `idx_title_search_title_norm_trgm`
- Triggers (3): `import_session_items_set_updated_at`, `import_sessions_set_updated_at`, `profiles_set_updated_at`

### supabase/migrations/20260203171110_concierge_title_search_rebuild.sql
- Functions (1): `public.rebuild_title_search`

### supabase/migrations/20260203181000_profiles_insert_policy.sql
- Policies (1): `public.profiles:profiles_insert_own`

### supabase/migrations/20260203183000_concierge_recommend_rpc.sql
- Functions (1): `public.recommend_ids_by_tag_categories`

### supabase/migrations/20260203190000_editorial_recommend_engine.sql
- Tables (2): `public.editorial_boosts`, `public.editorial_penalty_tags`
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203191500_recommend_focus_tags.sql
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203194500_recommend_focus_filter.sql
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203201000_editorial_story_boosts.sql
- Tables (1): `public.editorial_tag_boosts`
- Functions (1): `public.recommend_ids_premium`

### supabase/migrations/20260203203000_recommend_seed_similarity.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260203223000_scale_perf_bundle_and_indexes.sql
- Functions (4): `public.browse_anime_page`, `public.browse_manga_page`, `public.current_season_name`, `public.discover_bundle`
- Indexes (15): `idx_anime_created_id`, `idx_anime_genres_gin`, `idx_anime_next_airing_at`, `idx_anime_popularity_id`, `idx_anime_score_id`, `idx_anime_search_tsv`, `idx_anime_season_year_popularity_id`, `idx_anime_status_popularity_id`, `idx_anime_trending_id`, `idx_manga_created_id`, `idx_manga_genres_gin`, `idx_manga_popularity_id`, `idx_manga_score_id`, `idx_manga_search_tsv`, `idx_manga_trending_id`

### supabase/migrations/20260203224500_browse_rpc_add_created_at.sql
- Functions (2): `public.browse_anime_page`, `public.browse_manga_page`

### supabase/migrations/20260203233500_mirror_runs.sql
- Tables (1): `public.mirror_runs`
- Indexes (1): `idx_mirror_runs_started_at`

### supabase/migrations/20260203235500_search_rpc_keyset.sql
- Extensions (1): `pg_trgm`
- Functions (2): `public.search_anime_page`, `public.search_manga_page`
- Indexes (2): `idx_anime_title_trgm`, `idx_manga_title_trgm`

### supabase/migrations/20260204010500_collection_paging_rpc.sql
- Functions (2): `public.collection_anime_page`, `public.collection_manga_page`
- Indexes (2): `idx_anime_user_lists_user_updated_id`, `idx_manga_user_lists_user_updated_id`

### supabase/migrations/20260204124500_title_aliases.sql
- Tables (1): `public.title_aliases`
- Policies (1): `public.title_aliases:title_aliases_own_all`
- Indexes (2): `idx_title_aliases_user_alias`, `idx_title_aliases_user_updated`
- Triggers (1): `title_aliases_set_updated_at`

### supabase/migrations/20260204133000_collection_feed_paging_rpc.sql
- Functions (1): `public.collection_feed_page`

### supabase/migrations/20260204221500_concierge_rate_limits_and_llm_budgets.sql
- Tables (3): `public.llm_daily_usage`, `public.rate_limit_buckets`, `public.system_flags`
- Functions (5): `public.check_concierge_rate_limit`, `public.is_flag_enabled`, `public.llm_budget_finalize`, `public.llm_budget_reserve`, `public.rate_limit_hit`
- Indexes (1): `idx_rate_limit_buckets_window_start`
- Triggers (3): `llm_daily_usage_set_updated_at`, `rate_limit_buckets_set_updated_at`, `system_flags_set_updated_at`

### supabase/migrations/20260204233000_recommend_seed_similarity_allow_anon.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260204233010_concierge_ops_observability_and_retention.sql
- Extensions (1): `pg_cron`
- Tables (2): `public.concierge_config`, `public.concierge_parse_feedback`
- Views (3): `public.concierge_metrics_hourly`, `public.llm_usage_daily_totals`, `public.rate_limit_recent_top`
- Functions (5): `public.check_concierge_rate_limit`, `public.concierge_housekeeping`, `public.get_concierge_config`, `public.llm_budget_reserve`, `public.log_concierge_parse_feedback`
- Indexes (2): `idx_concierge_parse_feedback_created`, `idx_concierge_parse_feedback_user_created`
- Triggers (1): `concierge_config_set_updated_at`
- Cron (1): `concierge_housekeeping_daily @ 0 4 * * *`

### supabase/migrations/20260204234500_recommend_seed_similarity_ranked_tags.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260204235500_recommend_seed_similarity_genre_gate.sql
- Functions (1): `public.recommend_ids_similar_to_seeds`

### supabase/migrations/20260204240500_backfill_anime_episodes_from_next_airing.sql

### supabase/migrations/20260205000500_concierge_global_llm_budget_and_default_tuning.sql
- Tables (1): `public.llm_global_daily_usage`
- Functions (2): `public.llm_global_budget_finalize`, `public.llm_global_budget_reserve`
- Triggers (1): `llm_global_daily_usage_set_updated_at`

### supabase/migrations/20260205002000_concierge_budget_raise.sql


<!-- END AUTO-MIGRATION-MAP -->

---

## 8) Concierge system (detailed)

### Deterministic-first
- `concierge-parse` Edge Function
  - Parses user text (list or vibe)
  - Calls `search_titles` RPC to get candidates
  - Logs parse feedback when low-confidence
  - Supports: abbreviations (AoT/JJK/etc), seasons (`S2`, `Season 2`), episode markers (`ep 12`, `S2E5`), roman numerals, and “completed/caught up” flags

### Disambiguation
- `concierge-resolve` Edge Function
  - LLM fallback (Groq OpenAI-compatible)
  - Uses budgets + rate limits

### Recommendations
- `concierge-recommend` Edge Function
  - Uses deterministic recommendation pipeline first (RPCs)
  - Optional LLM narration (Groq)
  - Supports “seeded” requests (e.g., “like Vagabond”) via `recommend_ids_similar_to_seeds`
  - Uses editorial scoring + tag/category inference when no seed is provided

### Apply + Undo
- `concierge-apply` writes user list items
- `concierge-undo` rolls back last session

### Budgets + rate limits
- Configured in `public.concierge_config`
- Default as of now (from `supabase/CONCIERGE_OPS.md`):
  - Rate limits (per 60s):
    - parse: user 120/min, ip 300/min
    - recommend: user 20/min, ip 80/min
    - resolve: user 10/min, ip 40/min
    - apply: user 12/min, ip 50/min
    - undo: user 6/min, ip 20/min
  - LLM budgets:
    - per user per day: 50,000 tokens, 40 calls
    - global per day: 1,000,000 tokens, 600 calls
- Rate limits are enforced by RPC `check_concierge_rate_limit`, stored in `rate_limit_buckets`.

### LLM provider
- Groq (OpenAI-compatible endpoint)
- Env vars:
  - `GROQ_API_KEY`
  - `GROQ_MODEL` (default `openai/gpt-oss-20b`)
  - `GROQ_MODEL_RESOLVE` (optional override)

---

### Edge Function contracts (concierge)
**concierge-parse** (deterministic parser)
Request JSON:
- `text` (string)
- `scope` (`anime` | `manga` | `both`, default `both`)
- `limitPerItem` (int, default 10)

Response JSON:
- `items[]` (parsed lines with candidate lists)
- `userId` (null if unauthenticated)

**concierge-resolve** (LLM disambiguation)
Request JSON:
- `items[]` (parsed items w/ `raw`, `parsed`, `candidates`)
- `maxCandidates` (int, 2–10)

Response JSON:
- `choices[]` (indexes into candidates)
- `budget_exceeded` / `global_budget_exceeded` flags

**concierge-recommend** (recommendations)
Request JSON:
- `text` (string)
- `scope` (`anime` | `manga` | `both`)
- `limit` (3–20)
- `narrate` (bool)

Response JSON:
- list of recommended items (ids + titles + optional narration)

**concierge-apply** (write to list)
Request JSON:
- `items[]` each with `mediaType`, `mediaId`, `status`, and optional progress fields

Response JSON:
- `sessionId`
- `applied` count + errors

**concierge-undo** (rollback)
Request JSON:
- `sessionId` (optional; defaults to last applied)

<!-- BEGIN AUTO-EDGE-MAP -->

## 8.2) Auto edge-function map (contracts + dependencies)

Generated: **2026-02-05T13:05:07.075Z** (git: `4d470f8`)

### bulk-import-anime
- Source: `supabase/functions/bulk-import-anime/index.ts`
- Env vars: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `anime`, `anime_characters`, `anime_staff`, `anime_studios`, `anime_tags`, `characters`, `episodes`, `external_links`, `import_runs`, `import_state`, `staff`, `studios`, `tags`

### bulk-import-manga
- Source: `supabase/functions/bulk-import-manga/index.ts`
- Env vars: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`, `release_import_lock`
- Tables touched: `authors`, `chapters`, `characters`, `external_links`, `import_runs`, `import_state`, `manga`, `manga_authors`, `manga_characters`, `manga_staff`, `manga_tags`, `staff`, `tags`, `volumes`

### concierge-apply
- Source: `supabase/functions/concierge-apply/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `log_concierge_run`
- Tables touched: `anime`, `anime_user_lists`, `episodes`, `import_session_items`, `import_sessions`, `manga`, `manga_user_lists`, `title_aliases`

### concierge-parse
- Source: `supabase/functions/concierge-parse/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `log_concierge_parse_feedback`, `log_concierge_run`, `search_titles`
- Tables touched: `title_aliases`

### concierge-recommend
- Source: `supabase/functions/concierge-recommend/index.ts`
- Env vars: `GROQ_API_KEY`, `GROQ_MODEL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `is_flag_enabled`, `llm_budget_finalize`, `llm_budget_reserve`, `llm_global_budget_finalize`, `llm_global_budget_reserve`, `log_concierge_run`, `recommend_ids_premium`, `recommend_ids_similar_to_seeds`, `search_titles`
- Tables touched: `editorial_boosts`, `editorial_tag_boosts`

### concierge-resolve
- Source: `supabase/functions/concierge-resolve/index.ts`
- Env vars: `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_MODEL_RESOLVE`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `get_concierge_config`, `is_flag_enabled`, `llm_budget_finalize`, `llm_budget_reserve`, `llm_global_budget_finalize`, `llm_global_budget_reserve`

### concierge-undo
- Source: `supabase/functions/concierge-undo/index.ts`
- Env vars: `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `check_concierge_rate_limit`, `log_concierge_run`
- Tables touched: `anime_user_lists`, `import_session_items`, `import_sessions`, `manga_user_lists`

### mirror-images
- Source: `supabase/functions/mirror-images/index.ts`
- Env vars: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`
- RPCs: `acquire_import_lock`
- Tables touched: `anime`, `characters`, `manga`, `mirror_runs`, `staff`


<!-- END AUTO-EDGE-MAP -->

---

### Adult content filters
- Default behavior excludes adult content:
  - `is_adult` false
  - tag categories exclude `Sexual Content`
  - filters out `Hentai` and `Ecchi` genres

---

## 8.1) Recommendation engine (editorial)

- `editorial_boosts` and `editorial_penalty_tags` tables bias “premium/classic” picks.
- RPC `recommend_ids_premium` combines:
  - tag match score
  - quality signals (favourites/popularity/score)
  - classic bias (older high‑value titles)
  - editorial boosts and penalties
- Results exclude already‑listed user titles via `user_lists` view.

---

## 9) Scheduled jobs / cron

**Current pg_cron job** (from `supabase/migrations/20260204233010_concierge_ops_observability_and_retention.sql`):
- `concierge_housekeeping_daily`
  - Schedule: `0 4 * * *`
  - Function: `public.concierge_housekeeping()`
  - Cleans: rate limit buckets, LLM usage, old import sessions, concierge runs, feedback

**Other periodic operations**
- Mirror images: manual or external scheduler calling `mirror-images` function
- Bulk AniList imports: run via scripts or edge functions manually

---

## 9.1) Ops & observability

- Concierge logging: `concierge_runs` + `concierge_parse_feedback`
- Metrics views:
  - `concierge_metrics_hourly`
  - `llm_usage_daily_totals`
  - `rate_limit_recent_top`
- Ops doc: `supabase/CONCIERGE_OPS.md`
- Scripts:
  - `scripts/check_cron_health.js`
  - `scripts/collect_db_metrics.js`
  - `scripts/load_test_concierge.js`

---

## 10) Data ingestion (sources)

### AniList ingestion
- `scripts/import_anilist_fast.js` / `scripts/run_full_import.js`
- Edge functions: `bulk-import-anime`, `bulk-import-manga`
- Imports include:
  - core anime/manga records
  - episodes/chapters
  - tags/genres
  - staff/character links
  - external links / streaming links (stored in `external_links`)

### Import locking / concurrency
- Edge functions use `acquire_import_lock` + `release_import_lock` to prevent overlapping runs.
- `mirror-images` also uses the same lock mechanism.

### Post-processing
- `mirror-images` edge function for CDN storage
- `title_aliases` for search
- Discover + recommendation engines use dedicated RPCs

---

## 11) Performance + caching

### Client caching
- `ImagePipeline` with memory + disk caching
- SupabaseService uses in-flight task de-duplication for:
  - discover bundle
  - concierge recommend/parse
  - collection feeds
  - upcoming airing windows

### Server performance
- Keyset pagination RPCs for collection + search
- Indexes added in migrations (see `20260203223000_scale_perf_bundle_and_indexes.sql`)

### Pagination defaults
- `SupabaseService` default page size: **50**
- Collection feed uses keyset pagination on `(updated_at, id)` for anime/manga lists
- Browse + Search use RPC paging (`browse_*`, `search_*`)

### Realtime
- `SupabaseService` subscribes to user-scoped realtime channels to keep lists/collection fresh.
- Subscriptions are stopped on sign out.

### Perf instrumentation
- `KuroPerf` is used around heavy RPCs + image fetches for perf logging.

---

## 12) Current UI state (Concierge + Header)

- Concierge is a **full page** (left swipe). The **floating assistant** widget exists in code but is disabled on the page.
- Header left is **only KURO text**.
- A small **chat icon** appears next to the section title **only on Concierge page**.
- Profile is a **top-right menu** (not a dedicated page).

---

## 13) Build + run

- Xcode project: `Kuro.xcodeproj`
- Scheme: `Kuro`
- Default simulator: iPhone 17 Pro (iOS 26.0)

---

## 14) Change Log (append-only)

- 2026-02-05: Added auto-generated inventory + maps (migrations, edge functions, iOS RPC usage) via scripts.
- 2026-02-05: Added deep appendices (data dictionary, RPC catalog, edge function examples, operator runbook).
- 2026-02-05: Expanded CURRENT_APP_STATE with appendices (full DDL + concierge guardrails).
- 2026-02-05: Added/expanded CURRENT_APP_STATE docs with full technical + plain-English snapshots.
- 2026-02-05: Concierge left page + profile menu. Header simplified. Cards show `YEAR · EPS`. Concierge intro + quick-start glass pills added. Commits: `2565d4d`, `a9d0e2c`

---

## 15) Open Questions / Unknowns

- Are mirror-images / bulk import functions running on a scheduled Supabase schedule or via external cron? (Not found in migrations; assumed manual/external.)
- Exact current state of all RLS policies is in migrations; confirm if additional tables were added after 2026-02-05.
- `import_runs` table is referenced by bulk-import edge functions but is not created in `supabase/migrations/` in this repo; it may exist remotely or be optional.
- Unused/legacy Swift files exist (e.g., `Kuro/Views/KuroChanMascot.swift`, `Kuro/Views/ConciergeOverlay.swift`). Inventory lists them; decide whether to delete or keep as reference.

---

## 16) Appendix A — Core Schema DDL (02_comprehensive_table_creation.sql)

```sql
-- ============================================
-- COMPREHENSIVE TABLE CREATION SCRIPT
-- Optimal structure with internal IDs + external references
-- ============================================

-- ============================================
-- 1. ANIME TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE anime (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Basic Info
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    
    -- Anime-specific
    format TEXT, -- 'TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL'
    status TEXT, -- 'FINISHED', 'RELEASING', 'NOT_YET_RELEASED'
    description TEXT,
    description_normalized TEXT,
    
    -- Episodes
    episodes INTEGER,
    duration INTEGER, -- minutes per episode
    total_duration INTEGER, -- total runtime in minutes
    season TEXT, -- 'SPRING', 'SUMMER', 'FALL', 'WINTER'
    season_year INTEGER,
    
    -- Airing schedule
    next_episode_number INTEGER,
    next_airing_at TIMESTAMP WITH TIME ZONE,
    
    -- Dates
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    
    -- Ratings
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    
    -- Content
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    
    -- External links
    site_url TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

-- ============================================
-- 2. MANGA TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE manga (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Basic Info
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    
    -- Manga-specific
    format TEXT, -- 'MANGA', 'NOVEL', 'ONE_SHOT', 'DOUJINSHI', 'MANHWA', 'MANHUA'
    status TEXT, -- 'FINISHED', 'RELEASING', 'NOT_YET_RELEASED', 'HIATUS'
    description TEXT,
    description_normalized TEXT,
    
    -- Chapters/Volumes
    chapters INTEGER,
    volumes INTEGER,
    
    -- Chapter schedule
    next_chapter_number INTEGER,
    next_chapter_at TIMESTAMP WITH TIME ZONE,
    
    -- Dates
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    
    -- Ratings
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    
    -- Content
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    
    -- External links
    site_url TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

-- ============================================
-- 3. EPISODES TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE episodes (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Episode info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Airing info
    air_date DATE,
    air_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    duration INTEGER, -- minutes
    
    -- Episode metadata
    is_filler BOOLEAN DEFAULT false,
    is_recap BOOLEAN DEFAULT false,
    is_mixed BOOLEAN DEFAULT false,
    filler_source TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 4. CHAPTERS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE chapters (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Chapter info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Release info
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    pages INTEGER,
    
    -- Chapter metadata
    is_side_story BOOLEAN DEFAULT false,
    is_extra BOOLEAN DEFAULT false,
    is_omake BOOLEAN DEFAULT false,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 5. VOLUMES TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE volumes (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Volume info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    
    -- Release info
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    pages INTEGER,
    
    -- Volume metadata
    isbn TEXT,
    price_jpy INTEGER,
    price_usd DECIMAL(10,2),
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 6. CHARACTERS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE characters (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Character info
    name_full TEXT,
    name_native TEXT,
    name_alternative TEXT[],
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Character details
    description TEXT,
    gender TEXT, -- 'Male', 'Female', 'Non-binary', 'Unknown'
    age INTEGER,
    birthday DATE,
    blood_type TEXT, -- 'A', 'B', 'AB', 'O', 'Unknown'
    
    -- Physical attributes
    height INTEGER, -- cm
    weight INTEGER, -- kg
    hair_color TEXT,
    eye_color TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 7. STUDIOS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE studios (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Studio info
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    
    -- Studio details
    description TEXT,
    is_animation_studio BOOLEAN DEFAULT false,
    is_producer BOOLEAN DEFAULT false,
    is_licensor BOOLEAN DEFAULT false,
    
    -- External
    site_url TEXT,
    favourites INTEGER DEFAULT 0,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 8. AUTHORS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE authors (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Author info
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Author details
    description TEXT,
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 9. STAFF TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE staff (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Staff info
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Staff details
    description TEXT,
    primary_occupations TEXT[], -- ['Director', 'Writer', 'Music', 'Character Design']
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 10. TAGS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE tags (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Tag info
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    description TEXT,
    
    -- Tag metadata
    category TEXT, -- 'Genre', 'Theme', 'Demographic', 'Content'
    is_general_spoiler BOOLEAN DEFAULT false,
    is_media_spoiler BOOLEAN DEFAULT false,
    is_adult BOOLEAN DEFAULT false,
    rank INTEGER DEFAULT 0,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 11. RELATIONSHIP TABLES (All use INTERNAL IDs)
-- ============================================

-- Anime-Character relationship
CREATE TABLE anime_characters (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Main', 'Supporting', 'Background'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, character_id)
);

-- Manga-Character relationship
CREATE TABLE manga_characters (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Main', 'Supporting', 'Background'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, character_id)
);

-- Anime-Studio relationship
CREATE TABLE anime_studios (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    studio_id INTEGER REFERENCES studios(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Animation', 'Production', 'Licensor'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, studio_id)
);

-- Manga-Author relationship
CREATE TABLE manga_authors (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    author_id INTEGER REFERENCES authors(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Story', 'Art', 'Story & Art', 'Supervision'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, author_id)
);

-- Anime-Staff relationship
CREATE TABLE anime_staff (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    staff_id INTEGER REFERENCES staff(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Director', 'Writer', 'Music', 'Character Design'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, staff_id)
);

-- Manga-Staff relationship
CREATE TABLE manga_staff (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    staff_id INTEGER REFERENCES staff(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Editor', 'Publisher', 'Translator'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, staff_id)
);

-- Anime-Tag relationship
CREATE TABLE anime_tags (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE, -- INTERNAL reference
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, tag_id)
);

-- Manga-Tag relationship
CREATE TABLE manga_tags (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE, -- INTERNAL reference
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, tag_id)
);

-- ============================================
-- 12. USER INTERACTION TABLES (All use INTERNAL IDs)
-- ============================================

-- Anime user lists
CREATE TABLE anime_user_lists (
    id SERIAL PRIMARY KEY, -- Auto-increment for user list entry ID
    user_id INTEGER NOT NULL, -- Your user system ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    list_type TEXT NOT NULL, -- 'WATCHING', 'COMPLETED', 'PLANNING', 'DROPPED', 'PAUSED'
    progress INTEGER DEFAULT 0, -- episodes watched
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, anime_id)
);

-- Manga user lists
CREATE TABLE manga_user_lists (
    id SERIAL PRIMARY KEY, -- Auto-increment for user list entry ID
    user_id INTEGER NOT NULL, -- Your user system ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    list_type TEXT NOT NULL, -- 'READING', 'COMPLETED', 'PLANNING', 'DROPPED', 'PAUSED'
    progress INTEGER DEFAULT 0, -- chapters read
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, manga_id)
);

-- Anime comments
CREATE TABLE anime_comments (
    id SERIAL PRIMARY KEY, -- Auto-increment for comment ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    user_id INTEGER NOT NULL, -- Your user system ID
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Manga comments
CREATE TABLE manga_comments (
    id SERIAL PRIMARY KEY, -- Auto-increment for comment ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    user_id INTEGER NOT NULL, -- Your user system ID
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 13. PERFORMANCE INDEXES
-- ============================================

-- Primary entity indexes (INTERNAL IDs)
CREATE INDEX idx_anime_id ON anime(id);
CREATE INDEX idx_manga_id ON manga(id);
CREATE INDEX idx_episodes_id ON episodes(id);
CREATE INDEX idx_chapters_id ON chapters(id);
CREATE INDEX idx_volumes_id ON volumes(id);
CREATE INDEX idx_characters_id ON characters(id);
CREATE INDEX idx_studios_id ON studios(id);
CREATE INDEX idx_authors_id ON authors(id);
CREATE INDEX idx_staff_id ON staff(id);
CREATE INDEX idx_tags_id ON tags(id);

-- External ID indexes (for sync)
CREATE INDEX idx_anime_anilist_id ON anime(anilist_id);
CREATE INDEX idx_anime_mal_id ON anime(mal_id);
CREATE INDEX idx_manga_anilist_id ON manga(anilist_id);
CREATE INDEX idx_manga_mal_id ON manga(mal_id);
CREATE INDEX idx_characters_anilist_id ON characters(anilist_id);
CREATE INDEX idx_characters_mal_id ON characters(mal_id);
CREATE INDEX idx_studios_anilist_id ON studios(anilist_id);
CREATE INDEX idx_studios_mal_id ON studios(mal_id);
CREATE INDEX idx_authors_anilist_id ON authors(anilist_id);
CREATE INDEX idx_authors_mal_id ON authors(mal_id);
CREATE INDEX idx_staff_anilist_id ON staff(anilist_id);
CREATE INDEX idx_staff_mal_id ON staff(mal_id);
CREATE INDEX idx_tags_anilist_id ON tags(anilist_id);
CREATE INDEX idx_tags_mal_id ON tags(mal_id);

-- Content indexes
CREATE INDEX idx_anime_title_english ON anime(title_english);
CREATE INDEX idx_anime_title_romaji ON anime(title_romaji);
CREATE INDEX idx_anime_status ON anime(status);
CREATE INDEX idx_anime_popularity ON anime(popularity DESC);
CREATE INDEX idx_anime_average_score ON anime(average_score DESC);
CREATE INDEX idx_anime_genres ON anime USING GIN(genres);
CREATE INDEX idx_anime_season_year ON anime(season_year);
CREATE INDEX idx_anime_next_airing ON anime(next_airing_at);

CREATE INDEX idx_manga_title_english ON manga(title_english);
CREATE INDEX idx_manga_title_romaji ON manga(title_romaji);
CREATE INDEX idx_manga_status ON manga(status);
CREATE INDEX idx_manga_popularity ON manga(popularity DESC);
CREATE INDEX idx_manga_average_score ON manga(average_score DESC);
CREATE INDEX idx_manga_genres ON manga USING GIN(genres);
CREATE INDEX idx_manga_next_chapter ON manga(next_chapter_at);

-- Relationship indexes (INTERNAL IDs)
CREATE INDEX idx_anime_characters_anime_id ON anime_characters(anime_id);
CREATE INDEX idx_anime_characters_character_id ON anime_characters(character_id);
CREATE INDEX idx_manga_characters_manga_id ON manga_characters(manga_id);
CREATE INDEX idx_manga_characters_character_id ON manga_characters(character_id);
CREATE INDEX idx_anime_studios_anime_id ON anime_studios(anime_id);
CREATE INDEX idx_anime_studios_studio_id ON anime_studios(studio_id);
CREATE INDEX idx_manga_authors_manga_id ON manga_authors(manga_id);
CREATE INDEX idx_manga_authors_author_id ON manga_authors(author_id);
CREATE INDEX idx_anime_staff_anime_id ON anime_staff(anime_id);
CREATE INDEX idx_anime_staff_staff_id ON anime_staff(staff_id);
CREATE INDEX idx_manga_staff_manga_id ON manga_staff(manga_id);
CREATE INDEX idx_manga_staff_staff_id ON manga_staff(staff_id);
CREATE INDEX idx_anime_tags_anime_id ON anime_tags(anime_id);
CREATE INDEX idx_anime_tags_tag_id ON anime_tags(tag_id);
CREATE INDEX idx_manga_tags_manga_id ON manga_tags(manga_id);
CREATE INDEX idx_manga_tags_tag_id ON manga_tags(tag_id);

-- User interaction indexes
CREATE INDEX idx_anime_user_lists_user_id ON anime_user_lists(user_id);
CREATE INDEX idx_anime_user_lists_anime_id ON anime_user_lists(anime_id);
CREATE INDEX idx_anime_user_lists_list_type ON anime_user_lists(list_type);
CREATE INDEX idx_manga_user_lists_user_id ON manga_user_lists(user_id);
CREATE INDEX idx_manga_user_lists_manga_id ON manga_user_lists(manga_id);
CREATE INDEX idx_manga_user_lists_list_type ON manga_user_lists(list_type);
CREATE INDEX idx_anime_comments_anime_id ON anime_comments(anime_id);
CREATE INDEX idx_anime_comments_user_id ON anime_comments(user_id);
CREATE INDEX idx_manga_comments_manga_id ON manga_comments(manga_id);
CREATE INDEX idx_manga_comments_user_id ON manga_comments(user_id);

-- ============================================
-- 14. AUTO-UPDATE TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for all tables
CREATE TRIGGER update_anime_updated_at BEFORE UPDATE ON anime FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_manga_updated_at BEFORE UPDATE ON manga FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_episodes_updated_at BEFORE UPDATE ON episodes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_chapters_updated_at BEFORE UPDATE ON chapters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_volumes_updated_at BEFORE UPDATE ON volumes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_characters_updated_at BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_studios_updated_at BEFORE UPDATE ON studios FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_authors_updated_at BEFORE UPDATE ON authors FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_staff_updated_at BEFORE UPDATE ON staff FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tags_updated_at BEFORE UPDATE ON tags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 15. ROW LEVEL SECURITY (RLS)
-- ============================================

-- Enable RLS on all tables
ALTER TABLE anime ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga ENABLE ROW LEVEL SECURITY;
ALTER TABLE episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE chapters ENABLE ROW LEVEL SECURITY;
ALTER TABLE volumes ENABLE ROW LEVEL SECURITY;
ALTER TABLE characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_comments ENABLE ROW LEVEL SECURITY;

-- Create policies for public read access
CREATE POLICY "Public read access" ON anime FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga FOR SELECT USING (true);
CREATE POLICY "Public read access" ON episodes FOR SELECT USING (true);
CREATE POLICY "Public read access" ON chapters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON volumes FOR SELECT USING (true);
CREATE POLICY "Public read access" ON characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON studios FOR SELECT USING (true);
CREATE POLICY "Public read access" ON authors FOR SELECT USING (true);
CREATE POLICY "Public read access" ON staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON tags FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_studios FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_authors FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_tags FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_tags FOR SELECT USING (true);

-- User-specific policies for user lists and comments
CREATE POLICY "Users can manage their own lists" ON anime_user_lists USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own lists" ON manga_user_lists USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own comments" ON anime_comments USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own comments" ON manga_comments USING (auth.uid()::text = user_id::text);

-- ============================================
-- 16. VERIFICATION
-- ============================================

-- Verify all tables were created
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;

-- Verify all indexes were created
SELECT 
    schemaname,
    tablename,
    indexname
FROM pg_indexes 
WHERE schemaname = 'public' 
ORDER BY tablename, indexname;

-- Verify all triggers were created
SELECT 
    trigger_name,
    event_object_table,
    action_timing,
    event_manipulation
FROM information_schema.triggers 
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

```

---

## 17) Appendix B — Core Views + Aux Tables

### 08_create_user_lists_view.sql
```sql
-- ============================================
-- CREATE UNIFIED VIEW: user_lists
-- Bridges anime_user_lists and manga_user_lists into a single shape expected by the app
-- ============================================

CREATE OR REPLACE VIEW public.user_lists AS
SELECT
  aul.id AS id,
  aul.user_id::text AS user_id,
  aul.anime_id AS media_id,
  'anime'::text AS media_type,
  aul.list_type AS status,
  aul.progress AS progress,
  NULL::integer AS progress_volumes,
  CASE WHEN aul.rating IS NULL THEN NULL ELSE aul.rating * 10 END AS score,
  aul.notes AS notes,
  NULL::timestamp with time zone AS started_at,
  NULL::timestamp with time zone AS completed_at,
  FALSE AS private,
  aul.created_at AS created_at,
  aul.updated_at AS updated_at
FROM public.anime_user_lists aul
UNION ALL
SELECT
  mul.id AS id,
  mul.user_id::text AS user_id,
  mul.manga_id AS media_id,
  'manga'::text AS media_type,
  mul.list_type AS status,
  mul.progress AS progress,
  NULL::integer AS progress_volumes,
  CASE WHEN mul.rating IS NULL THEN NULL ELSE mul.rating * 10 END AS score,
  mul.notes AS notes,
  NULL::timestamp with time zone AS started_at,
  NULL::timestamp with time zone AS completed_at,
  FALSE AS private,
  mul.created_at AS created_at,
  mul.updated_at AS updated_at
FROM public.manga_user_lists mul;

-- Optional helper indexes on the view via materialized pattern could be added if needed.

```

### 09_import_state.sql
```sql
-- Cursor table for scheduled imports
CREATE TABLE IF NOT EXISTS public.import_state (
  media_type text PRIMARY KEY, -- 'ANIME' | 'MANGA'
  last_page integer NOT NULL DEFAULT 0,
  updated_at timestamp with time zone DEFAULT now()
);

-- Seed rows if not present
INSERT INTO public.import_state (media_type, last_page)
VALUES ('ANIME', 0)
ON CONFLICT (media_type) DO NOTHING;

INSERT INTO public.import_state (media_type, last_page)
VALUES ('MANGA', 0)
ON CONFLICT (media_type) DO NOTHING;

```

### 10_create_user_airing_next_view.sql
```sql
-- ============================================
-- CREATE USER-SCOPED UPCOMING AIRINGS VIEW (ANIME)
-- Only includes titles saved by a user, with a future next_airing_at
-- Requires: 12_fix_user_id_type.sql must be run FIRST
-- ============================================

CREATE OR REPLACE VIEW public.user_airing_next AS
SELECT
  aul.user_id        AS user_id,           -- TEXT (after migration)
  a.id               AS anime_id,          -- anime PK
  a.title_english    AS title_english,
  a.title_romaji     AS title_romaji,
  a.next_episode_number AS next_episode_number,
  a.next_airing_at   AS next_airing_at,
  aul.list_type      AS list_type,         -- WATCHING, COMPLETED, etc.
  aul.progress       AS progress,          -- Episodes watched
  aul.updated_at     AS list_updated_at
FROM public.anime_user_lists aul
JOIN public.anime a ON a.id = aul.anime_id
WHERE a.next_airing_at IS NOT NULL
  AND a.next_airing_at > now()
ORDER BY a.next_airing_at ASC;

-- Notes:
-- - RLS applies on underlying tables
-- - Client should filter: WHERE user_id = auth.uid()::text
-- - Can add additional filters for date windows (e.g., next 7 days)
-- - Ordered by airing date (soonest first)

-- Verification query (optional):
-- SELECT * FROM user_airing_next WHERE user_id = auth.uid()::text LIMIT 5;
```

### 11_airing_next_rpc.sql
```sql
-- ============================================
-- OPTIONAL: RPC to fetch the caller's upcoming airings within N days
-- Uses auth.uid() for scoping; SECURITY INVOKER respects RLS
-- Requires: 12_fix_user_id_type.sql must be run FIRST
-- ============================================

CREATE OR REPLACE FUNCTION public.airing_next(days integer DEFAULT 7)
RETURNS TABLE(
  anime_id int,
  title_english text,
  title_romaji text,
  next_episode_number int,
  next_airing_at timestamptz,
  list_type text,
  progress int
) AS $$
  SELECT
    a.id,
    a.title_english,
    a.title_romaji,
    a.next_episode_number,
    a.next_airing_at,
    aul.list_type,
    aul.progress
  FROM public.anime a
  JOIN public.anime_user_lists aul ON aul.anime_id = a.id
  WHERE aul.user_id = auth.uid()::text  -- Matches TEXT user_id
    AND a.next_airing_at IS NOT NULL
    AND a.next_airing_at BETWEEN now() AND (now() + (days || ' days')::interval)
  ORDER BY a.next_airing_at ASC
  LIMIT 500;
$$ LANGUAGE sql SECURITY INVOKER STABLE;

-- Notes:
-- - SECURITY INVOKER: Executes with caller's permissions (respects RLS)
-- - STABLE: Query result doesn't change within transaction (optimization)
-- - Returns up to 500 upcoming episodes within specified days window
-- - Ordered by airing date (soonest first)

-- Usage example:
-- SELECT * FROM airing_next(7);  -- Next 7 days
-- SELECT * FROM airing_next(1);  -- Next 24 hours
```

### 13_alter_episodes_add_stream_fields.sql
```sql
-- Adds streaming link fields to episodes for Watch CTA support
ALTER TABLE public.episodes
  ADD COLUMN IF NOT EXISTS stream_url TEXT;

ALTER TABLE public.episodes
  ADD COLUMN IF NOT EXISTS stream_site TEXT;
```

### 14_create_external_links.sql
```sql
-- Stores curated external streaming links for anime/manga detail CTAs
CREATE TABLE IF NOT EXISTS public.external_links (
  id SERIAL PRIMARY KEY,
  media_type TEXT CHECK (media_type IN ('ANIME','MANGA')) NOT NULL,
  media_id INT NOT NULL,
  site TEXT,
  url TEXT NOT NULL,
  language TEXT,
  color TEXT,
  priority INT DEFAULT 999,
  is_disabled BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(media_type, media_id, url)
);

CREATE INDEX IF NOT EXISTS idx_external_links_media ON public.external_links(media_type, media_id);

ALTER TABLE public.external_links ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  BEGIN
    CREATE POLICY "Public read access" ON public.external_links FOR SELECT USING (true);
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END;
$$;
```

### 20260204124500_title_aliases.sql
```sql
-- User-specific title aliases for "magic" parsing.
-- Stores previously-confirmed mappings from noisy user input -> canonical media id.

begin;

create table if not exists public.title_aliases (
  user_id uuid not null references auth.users(id) on delete cascade,
  alias_norm text not null,
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  title_raw text,
  hits integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, alias_norm, media_type)
);

create index if not exists idx_title_aliases_user_updated on public.title_aliases (user_id, updated_at desc);
create index if not exists idx_title_aliases_user_alias on public.title_aliases (user_id, alias_norm);

alter table public.title_aliases enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='title_aliases' and policyname='title_aliases_own_all'
  ) then
    create policy title_aliases_own_all on public.title_aliases
      for all
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'title_aliases_set_updated_at') then
    create trigger title_aliases_set_updated_at
      before update on public.title_aliases
      for each row execute function public.set_updated_at();
  end if;
end $$;

commit;

```

### 20260203233500_mirror_runs.sql
```sql
begin;

-- Track mirror-images runs so schedules can be verified and failures diagnosed.
create table if not exists public.mirror_runs (
  id bigserial primary key,
  status text not null default 'running', -- running | success | error | skipped
  payload jsonb,
  results jsonb,
  message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  duration_ms integer
);

create index if not exists idx_mirror_runs_started_at on public.mirror_runs (started_at desc);

commit;

```

---

## 18) Appendix C — Concierge Guardrails + Budgets DDL

### 20260204221500_concierge_rate_limits_and_llm_budgets.sql
```sql
-- Server-side guardrails for Concierge:
-- - Rate limits (per-user and per-IP) for Edge Functions
-- - LLM daily budget + global kill-switch flag

begin;

-- 1) Kill switch / flags (readable via SECURITY DEFINER function).
create table if not exists public.system_flags (
  key text primary key,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.system_flags enable row level security;

-- No policies: clients cannot read flags directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'system_flags_set_updated_at') then
    create trigger system_flags_set_updated_at
      before update on public.system_flags
      for each row execute function public.set_updated_at();
  end if;
end $$;

insert into public.system_flags(key, enabled)
values ('llm_enabled', true)
on conflict (key) do nothing;

create or replace function public.is_flag_enabled(p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v boolean;
begin
  select enabled into v from public.system_flags where key = p_key;
  return coalesce(v, true);
end $$;

grant execute on function public.is_flag_enabled(text) to anon, authenticated;

-- 2) Rate limit buckets (atomic upsert increments).
create table if not exists public.rate_limit_buckets (
  bucket_key text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (bucket_key, window_start)
);

create index if not exists idx_rate_limit_buckets_window_start on public.rate_limit_buckets (window_start desc);

alter table public.rate_limit_buckets enable row level security;
-- No policies: users cannot read/write buckets directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'rate_limit_buckets_set_updated_at') then
    create trigger rate_limit_buckets_set_updated_at
      before update on public.rate_limit_buckets
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.rate_limit_hit(
  p_bucket_key text,
  p_window_seconds integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare wstart timestamptz;
declare v integer;
begin
  if p_bucket_key is null or length(p_bucket_key) = 0 then
    raise exception 'rate_limit_hit: missing bucket_key';
  end if;
  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'rate_limit_hit: invalid window_seconds';
  end if;

  -- Fixed window bucket aligned to epoch.
  wstart := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.rate_limit_buckets(bucket_key, window_start, hits)
  values (p_bucket_key, wstart, 1)
  on conflict (bucket_key, window_start)
  do update set hits = public.rate_limit_buckets.hits + 1, updated_at = now()
  returning hits into v;

  return v;
end $$;

grant execute on function public.rate_limit_hit(text, integer) to anon, authenticated;

create or replace function public.check_concierge_rate_limit(
  p_kind text,
  p_ip text,
  p_window_seconds integer default 60,
  p_max_user integer default 40,
  p_max_ip integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare u_hits integer;
declare ip_hits integer;
declare allow boolean := true;
declare retry_after integer;
declare kind text;
begin
  uid := auth.uid();
  kind := coalesce(nullif(p_kind, ''), 'any');

  if uid is null and (p_ip is null or length(p_ip) = 0) then
    return jsonb_build_object('allowed', true, 'note', 'no uid/ip');
  end if;

  if uid is not null then
    u_hits := public.rate_limit_hit('user:' || uid::text || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if u_hits > coalesce(p_max_user, 0) then allow := false; end if;
  end if;

  if p_ip is not null and length(p_ip) > 0 then
    ip_hits := public.rate_limit_hit('ip:' || p_ip || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if ip_hits > coalesce(p_max_ip, 0) then allow := false; end if;
  end if;

  retry_after := p_window_seconds - (extract(epoch from now())::integer % p_window_seconds);
  return jsonb_build_object(
    'allowed', allow,
    'user_hits', u_hits,
    'ip_hits', ip_hits,
    'retry_after_s', retry_after
  );
end $$;

grant execute on function public.check_concierge_rate_limit(text, text, integer, integer, integer) to anon, authenticated;

-- 3) LLM daily budget (reserve + finalize to keep budgets accurate and concurrency-safe).
create table if not exists public.llm_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  last_model text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.llm_daily_usage enable row level security;
-- No policies: users cannot read/write usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_daily_usage_set_updated_at') then
    create trigger llm_daily_usage_set_updated_at
      before update on public.llm_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.llm_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer default 20000,
  p_max_daily_calls integer default 80,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select
    coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0),
    coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_daily_usage
  where user_id = uid and day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow :=
    next_tokens <= coalesce(p_max_daily_tokens, 0)
    and next_calls <= coalesce(p_max_daily_calls, 0);

  if allow then
    insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
    values (uid, d, p_reserved_tokens, 0, 1, p_model)
    on conflict (user_id, day)
    do update set
      reserved_tokens = public.llm_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_daily_usage.calls + 1,
      last_model = coalesce(excluded.last_model, public.llm_daily_usage.last_model),
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', p_max_daily_tokens,
    'max_daily_calls', p_max_daily_calls
  );
end $$;

create or replace function public.llm_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare tokens_total integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('success', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  -- Ensure row exists even if finalize is called after a failed reserve (best-effort).
  insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
  values (uid, d, 0, 0, 0, p_model)
  on conflict (user_id, day) do nothing;

  update public.llm_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    last_model = coalesce(p_model, last_model),
    updated_at = now()
  where user_id = uid and day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_daily_usage
  where user_id = uid and day = d;

  tokens_total := coalesce(reserved_total, 0) + coalesce(actual_total, 0);
  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'tokens_total', coalesce(tokens_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;

grant execute on function public.llm_budget_reserve(integer, integer, integer, text) to authenticated;
grant execute on function public.llm_budget_finalize(integer, integer, text) to authenticated;

commit;
```

### 20260204233010_concierge_ops_observability_and_retention.sql
```sql
-- Concierge ops hardening:
-- - Config table for tunable guardrails without redeploy
-- - Parse feedback logging (low-confidence/no-match)
-- - Retention + housekeeping (pg_cron)
-- - Admin-only metrics views (no grants)

begin;

-- 1) Config (single-row JSON, simple to edit in the dashboard).
create table if not exists public.concierge_config (
  id boolean primary key default true, -- single row: id=true
  config jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.concierge_config enable row level security;
-- No policies: clients cannot read/write config directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'concierge_config_set_updated_at') then
    create trigger concierge_config_set_updated_at
      before update on public.concierge_config
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- Default config (safe launch defaults).
insert into public.concierge_config(id, config)
values (
  true,
  jsonb_build_object(
    'rate_limits', jsonb_build_object(
      'parse', jsonb_build_object('window_seconds', 60, 'max_user', 140, 'max_ip', 240),
      'apply', jsonb_build_object('window_seconds', 60, 'max_user', 18, 'max_ip', 80),
      'undo', jsonb_build_object('window_seconds', 60, 'max_user', 12, 'max_ip', 50),
      'resolve', jsonb_build_object('window_seconds', 60, 'max_user', 18, 'max_ip', 80),
      'recommend', jsonb_build_object('window_seconds', 60, 'max_user', 30, 'max_ip', 100)
    ),
    'llm_budget', jsonb_build_object(
      'daily_tokens', 20000,
      'daily_calls', 80
    ),
    'parse_feedback', jsonb_build_object(
      'enabled', true,
      'low_confidence_score', 0.55,
      'max_log_chars', 140
    ),
    'retention_days', jsonb_build_object(
      'rate_limit_buckets', 2,
      'llm_daily_usage', 90,
      'import_sessions', 30,
      'concierge_runs', 60,
      'parse_feedback', 14
    )
  )
)
on conflict (id) do nothing;

create or replace function public.get_concierge_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare cfg jsonb;
begin
  select config into cfg from public.concierge_config where id = true;
  return coalesce(cfg, '{}'::jsonb);
end $$;

grant execute on function public.get_concierge_config() to anon, authenticated;

-- 2) Parse feedback table (for iterative improvement).
create table if not exists public.concierge_parse_feedback (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete cascade,
  raw_snippet text,
  normalized text,
  alias_norm text,
  best_score real,
  candidates_count integer,
  top_media_type text,
  top_media_id integer,
  created_at timestamptz not null default now()
);

create index if not exists idx_concierge_parse_feedback_created on public.concierge_parse_feedback (created_at desc);
create index if not exists idx_concierge_parse_feedback_user_created on public.concierge_parse_feedback (user_id, created_at desc);

alter table public.concierge_parse_feedback enable row level security;
-- No policies: do not expose raw user text to other clients.

create or replace function public.log_concierge_parse_feedback(
  p_raw text,
  p_normalized text,
  p_alias_norm text,
  p_best_score real,
  p_candidates_count integer,
  p_top_media_type text,
  p_top_media_id integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare cfg jsonb;
declare enabled boolean;
declare low_score real;
declare max_chars integer;
begin
  uid := auth.uid();
  if uid is null then
    return;
  end if;

  cfg := public.get_concierge_config();
  enabled := coalesce((cfg->'parse_feedback'->>'enabled')::boolean, true);
  if not enabled then
    return;
  end if;

  low_score := coalesce((cfg->'parse_feedback'->>'low_confidence_score')::real, 0.55);
  if p_best_score is not null and p_best_score >= low_score then
    return;
  end if;

  max_chars := greatest(20, least(coalesce((cfg->'parse_feedback'->>'max_log_chars')::int, 140), 400));

  insert into public.concierge_parse_feedback(
    user_id, raw_snippet, normalized, alias_norm, best_score, candidates_count, top_media_type, top_media_id
  )
  values(
    uid,
    left(coalesce(p_raw, ''), max_chars),
    left(coalesce(p_normalized, ''), max_chars),
    left(coalesce(p_alias_norm, ''), max_chars),
    p_best_score,
    p_candidates_count,
    left(coalesce(p_top_media_type, ''), 16),
    p_top_media_id
  );
end $$;

grant execute on function public.log_concierge_parse_feedback(text, text, text, real, integer, text, integer) to authenticated;

-- 3) Make guardrail functions read defaults from config when caller passes null.
create or replace function public.check_concierge_rate_limit(
  p_kind text,
  p_ip text,
  p_window_seconds integer default 60,
  p_max_user integer default 40,
  p_max_ip integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare u_hits integer;
declare ip_hits integer;
declare allow boolean := true;
declare retry_after integer;
declare kind text;
declare cfg jsonb;
declare rl jsonb;
declare win_s integer;
declare max_u integer;
declare max_i integer;
begin
  uid := auth.uid();
  kind := coalesce(nullif(p_kind, ''), 'any');

  cfg := public.get_concierge_config();
  rl := cfg->'rate_limits'->kind;

  win_s := coalesce(p_window_seconds, (rl->>'window_seconds')::int, 60);
  max_u := coalesce(p_max_user, (rl->>'max_user')::int, 40);
  max_i := coalesce(p_max_ip, (rl->>'max_ip')::int, 120);

  if uid is null and (p_ip is null or length(p_ip) = 0) then
    return jsonb_build_object('allowed', true, 'note', 'no uid/ip');
  end if;

  if uid is not null then
    u_hits := public.rate_limit_hit('user:' || uid::text || ':' || kind || ':' || win_s::text, win_s);
    if u_hits > coalesce(max_u, 0) then allow := false; end if;
  end if;

  if p_ip is not null and length(p_ip) > 0 then
    ip_hits := public.rate_limit_hit('ip:' || p_ip || ':' || kind || ':' || win_s::text, win_s);
    if ip_hits > coalesce(max_i, 0) then allow := false; end if;
  end if;

  retry_after := win_s - (extract(epoch from now())::integer % win_s);
  return jsonb_build_object(
    'allowed', allow,
    'user_hits', u_hits,
    'ip_hits', ip_hits,
    'retry_after_s', retry_after,
    'window_seconds', win_s,
    'max_user', max_u,
    'max_ip', max_i
  );
end $$;

-- LLM budget defaults from config when caller passes null.
create or replace function public.llm_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer default 20000,
  p_max_daily_calls integer default 80,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
declare cfg jsonb;
declare budget jsonb;
declare max_tokens integer;
declare max_calls integer;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;

  cfg := public.get_concierge_config();
  budget := cfg->'llm_budget';
  max_tokens := coalesce(p_max_daily_tokens, (budget->>'daily_tokens')::int, 20000);
  max_calls := coalesce(p_max_daily_calls, (budget->>'daily_calls')::int, 80);

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select
    coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0),
    coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_daily_usage
  where user_id = uid and day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow :=
    next_tokens <= coalesce(max_tokens, 0)
    and next_calls <= coalesce(max_calls, 0);

  if allow then
    insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
    values (uid, d, p_reserved_tokens, 0, 1, p_model)
    on conflict (user_id, day)
    do update set
      reserved_tokens = public.llm_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_daily_usage.calls + 1,
      last_model = coalesce(excluded.last_model, public.llm_daily_usage.last_model),
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', max_tokens,
    'max_daily_calls', max_calls
  );
end $$;

-- 4) Housekeeping + retention.
create or replace function public.concierge_housekeeping()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare cfg jsonb;
declare r jsonb;
declare days_rate integer;
declare days_llm integer;
declare days_import integer;
declare days_runs integer;
declare days_feedback integer;
begin
  cfg := public.get_concierge_config();
  r := cfg->'retention_days';
  days_rate := coalesce((r->>'rate_limit_buckets')::int, 2);
  days_llm := coalesce((r->>'llm_daily_usage')::int, 90);
  days_import := coalesce((r->>'import_sessions')::int, 30);
  days_runs := coalesce((r->>'concierge_runs')::int, 60);
  days_feedback := coalesce((r->>'parse_feedback')::int, 14);

  delete from public.rate_limit_buckets
  where window_start < now() - make_interval(days => greatest(1, days_rate));

  delete from public.llm_daily_usage
  where day < (timezone('utc', now())::date - greatest(7, days_llm));

  -- Import sessions/items (only completed/cancelled/failed; keep drafts).
  delete from public.import_session_items i
  using public.import_sessions s
  where i.session_id = s.id
    and s.status in ('applied','cancelled','failed')
    and s.updated_at < now() - make_interval(days => greatest(7, days_import));

  delete from public.import_sessions
  where status in ('applied','cancelled','failed')
    and updated_at < now() - make_interval(days => greatest(7, days_import));

  delete from public.concierge_runs
  where created_at < now() - make_interval(days => greatest(14, days_runs));

  delete from public.concierge_parse_feedback
  where created_at < now() - make_interval(days => greatest(7, days_feedback));
end $$;

-- Schedule housekeeping daily (best-effort). If pg_cron isn't available, the function still exists.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    -- ignore if extension not available in this environment
    return;
  end;

  -- Ensure we don't double-schedule.
  if not exists (select 1 from cron.job where jobname = 'concierge_housekeeping_daily') then
    perform cron.schedule('concierge_housekeeping_daily', '0 4 * * *', 'select public.concierge_housekeeping();');
  end if;
end $$;

-- 5) Admin views (no grants; use dashboard/service role).
create or replace view public.concierge_metrics_hourly as
select
  date_trunc('hour', created_at) as hour,
  kind,
  status,
  count(*)::int as runs,
  coalesce(sum(items_count), 0)::int as items_total,
  coalesce(avg(latency_ms), 0)::real as avg_latency_ms,
  coalesce(sum(case when error is null then 0 else 1 end), 0)::int as errors
from public.concierge_runs
group by 1, 2, 3;

create or replace view public.llm_usage_daily_totals as
select
  day,
  count(*)::int as users,
  sum(actual_tokens)::bigint as actual_tokens,
  sum(reserved_tokens)::bigint as reserved_tokens,
  sum(calls)::bigint as calls
from public.llm_daily_usage
group by 1
order by day desc;

create or replace view public.rate_limit_recent_top as
select
  window_start,
  bucket_key,
  hits
from public.rate_limit_buckets
where window_start > now() - interval '6 hours'
order by hits desc, window_start desc
limit 200;

commit;
```

### 20260205000500_concierge_global_llm_budget_and_default_tuning.sql
```sql
-- Add global LLM daily budget + tune default "natural usage" limits.
-- Goal: prevent LLM spend abuse even with many users.

begin;

-- 1) Global daily usage table.
create table if not exists public.llm_global_daily_usage (
  day date primary key,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.llm_global_daily_usage enable row level security;
-- No policies: clients cannot read/write global usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_global_daily_usage_set_updated_at') then
    create trigger llm_global_daily_usage_set_updated_at
      before update on public.llm_global_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.llm_global_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer,
  p_max_daily_calls integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
begin
  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;
  if p_max_daily_tokens is null or p_max_daily_tokens < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_tokens');
  end if;
  if p_max_daily_calls is null or p_max_daily_calls < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_calls');
  end if;

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0), coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_global_daily_usage
  where day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow := next_tokens <= p_max_daily_tokens and next_calls <= p_max_daily_calls;

  if allow then
    insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
    values (d, p_reserved_tokens, 0, 1)
    on conflict (day) do update set
      reserved_tokens = public.llm_global_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_global_daily_usage.calls + 1,
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', p_max_daily_tokens,
    'max_daily_calls', p_max_daily_calls
  );
end $$;

create or replace function public.llm_global_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
  values (d, 0, 0, 0)
  on conflict (day) do nothing;

  update public.llm_global_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    updated_at = now()
  where day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_global_daily_usage
  where day = d;

  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;

grant execute on function public.llm_global_budget_reserve(integer, integer, integer) to authenticated;
grant execute on function public.llm_global_budget_finalize(integer, integer) to authenticated;

-- 2) Patch default config with "natural usage" limits + global budget.
update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        config,
        '{llm_budget}',
        jsonb_build_object('daily_tokens', 12000, 'daily_calls', 40),
        true
      ),
      '{global_llm_budget}',
      jsonb_build_object('daily_tokens', 250000, 'daily_calls', 600),
      true
    ),
    '{rate_limits}',
    jsonb_build_object(
      'parse', jsonb_build_object('window_seconds', 60, 'max_user', 120, 'max_ip', 300),
      'apply', jsonb_build_object('window_seconds', 60, 'max_user', 12, 'max_ip', 50),
      'undo', jsonb_build_object('window_seconds', 60, 'max_user', 6, 'max_ip', 20),
      'resolve', jsonb_build_object('window_seconds', 60, 'max_user', 10, 'max_ip', 40),
      'recommend', jsonb_build_object('window_seconds', 60, 'max_user', 20, 'max_ip', 80)
    ),
    true
  )
where id = true;

commit;

```

### 20260205002000_concierge_budget_raise.sql
```sql
-- Raise LLM token budgets (requested):
-- - global daily tokens: 1,000,000
-- - per-user daily tokens: 50,000

begin;

update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      config,
      '{llm_budget,daily_tokens}',
      to_jsonb(50000),
      true
    ),
    '{global_llm_budget,daily_tokens}',
    to_jsonb(1000000),
    true
  )
where id = true;

commit;

```

---

## 19) Appendix D — Recommendation & Search RPC DDL (selected)

### 20260203183000_concierge_recommend_rpc.sql
```sql
-- Deterministic recommendation primitives (no LLM).
-- Uses tags + join tables to produce "new to you" premium-ish candidates.

begin;

create or replace function public.recommend_ids_by_tag_categories(
  p_media_type text,
  p_categories text[],
  p_limit integer default 10
)
returns table (
  media_type text,
  media_id integer,
  match_count integer
)
language sql stable as $$
  select media_type, media_id, match_count from (
    select
      'ANIME'::text as media_type,
      at.anime_id as media_id,
      count(*)::int as match_count,
      max(a.average_score) as avg_score,
      max(a.popularity) as pop
    from public.anime_tags at
    join public.tags t on t.id = at.tag_id
    join public.anime a on a.id = at.anime_id
    where p_media_type = 'ANIME'
      and auth.uid() is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and not exists (
        select 1
        from public.user_lists ul
        where ul.user_id = auth.uid()::text
          and ul.media_type = 'anime'
          and ul.media_id = at.anime_id
      )
    group by at.anime_id

    union all

    select
      'MANGA'::text as media_type,
      mt.manga_id as media_id,
      count(*)::int as match_count,
      max(m.average_score) as avg_score,
      max(m.popularity) as pop
    from public.manga_tags mt
    join public.tags t on t.id = mt.tag_id
    join public.manga m on m.id = mt.manga_id
    where p_media_type = 'MANGA'
      and auth.uid() is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and not exists (
        select 1
        from public.user_lists ul
        where ul.user_id = auth.uid()::text
          and ul.media_type = 'manga'
          and ul.media_id = mt.manga_id
      )
    group by mt.manga_id
  ) ranked
  order by match_count desc, avg_score desc nulls last, pop desc nulls last
  limit greatest(1, least(p_limit, 50));
$$;

grant execute on function public.recommend_ids_by_tag_categories(text, text[], integer) to authenticated;

commit;
```

### 20260203190000_editorial_recommend_engine.sql
```sql
-- Editorial weighting for premium recommendations.
-- Goal: push classics/masterpieces up front; softly de-emphasize gimmick isekai/reincarnation/harem,
-- while still keeping everything searchable and accessible.

begin;

create table if not exists public.editorial_boosts (
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  weight integer not null default 0,
  label text not null default '',
  created_at timestamptz not null default now(),
  primary key (media_type, media_id)
);

create table if not exists public.editorial_penalty_tags (
  tag_id integer primary key references public.tags(id) on delete cascade,
  penalty integer not null default 0,
  reason text,
  created_at timestamptz not null default now()
);

-- Seed: core classics/masterpieces (internal ids, not AniList ids).
insert into public.editorial_boosts (media_type, media_id, weight, label) values
  ('MANGA', 14, 25, 'classic'),   -- Vagabond
  ('MANGA', 97, 22, 'classic'),   -- Kingdom
  ('MANGA', 30, 25, 'classic'),   -- 20th Century Boys
  ('MANGA', 29, 22, 'classic'),   -- Monster
  ('MANGA', 5, 25, 'classic'),    -- Berserk
  ('MANGA', 16, 18, 'classic'),   -- Vinland Saga
  ('MANGA', 11, 18, 'classic'),   -- Oyasumi Punpun
  ('MANGA', 98, 18, 'classic'),   -- Slam Dunk
  ('MANGA', 162, 16, 'classic'),  -- Real
  ('MANGA', 116, 14, 'classic'),  -- The Climber
  ('MANGA', 169, 18, 'classic'),  -- Akira
  ('ANIME', 12, 16, 'classic'),   -- Fullmetal Alchemist: Brotherhood
  ('ANIME', 29, 14, 'classic'),   -- Steins;Gate
  ('ANIME', 117, 12, 'classic'),  -- Cowboy Bebop
  ('ANIME', 1072, 14, 'classic')  -- Legend of the Galactic Heroes
on conflict (media_type, media_id) do update
  set weight = excluded.weight, label = excluded.label;

-- Seed: de-emphasize gimmick clusters by default (not a ban).
insert into public.editorial_penalty_tags (tag_id, penalty, reason) values
  (350, -12, 'Isekai'),
  (1023, -10, 'Reincarnation'),
  (358, -6, 'Female Harem'),
  (9154, -6, 'Male Harem'),
  (18064, -6, 'Mixed Gender Harem')
on conflict (tag_id) do update
  set penalty = excluded.penalty, reason = excluded.reason;

create or replace function public.recommend_ids_premium(
  p_media_type text,
  p_categories text[] default null,
  p_limit integer default 10,
  p_allow_gimmicks boolean default false
)
returns table (
  media_id integer,
  match_count integer,
  score real
)
language sql stable security definer
set search_path = public
as $$
  with req as (
    select
      greatest(1, least(coalesce(p_limit, 10), 50))::int as lim,
      p_categories as cats,
      p_allow_gimmicks as allow_gimmicks
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  anime_pen as (
    select at.anime_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.anime_tags at
    join public.editorial_penalty_tags p on p.tag_id = at.tag_id
    group by at.anime_id
  ),
  manga_pen as (
    select mt.manga_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.manga_tags mt
    join public.editorial_penalty_tags p on p.tag_id = mt.tag_id
    group by mt.manga_id
  ),
  anime_match as (
    select
      at.anime_id as media_id,
      count(*)::int as match_count
    from public.anime_tags at
    join public.tags t on t.id = at.tag_id
    where p_categories is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(t.category, '') <> 'Sexual Content'
    group by at.anime_id
  ),
  manga_match as (
    select
      mt.manga_id as media_id,
      count(*)::int as match_count
    from public.manga_tags mt
    join public.tags t on t.id = mt.tag_id
    where p_categories is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(t.category, '') <> 'Sexual Content'
    group by mt.manga_id
  )
  select *
  from (
    select
      a.id as media_id,
      coalesce(am.match_count, 0) as match_count,
      (
        -- Tag fit (dominant when the user gives a vibe)
        coalesce(am.match_count, 0) * 8
        -- Quality (multi-signal, not rating-only)
        + ln(1 + coalesce(a.favourites, 0)) * 2.0
        + ln(1 + coalesce(a.popularity, 0)) * 1.0
        + (coalesce(a.average_score, 0) / 10.0)
        -- Classic bias
        + case
            when a.start_date_year is not null and a.start_date_year <= 2005 then 7
            when a.start_date_year is not null and a.start_date_year <= 2015 then 4
            else 0
          end
        -- Editorial boost
        + coalesce(eb.weight, 0)
        -- Soft penalties (unless user asks for gimmicks)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(ap.penalty, 0)
          end
      )::real as score
    from public.anime a
    left join anime_match am on am.media_id = a.id
    left join public.editorial_boosts eb on eb.media_type = 'ANIME' and eb.media_id = a.id
    left join anime_pen ap on ap.media_id = a.id
    where p_media_type = 'ANIME'
      and (select user_id from me) is not null
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )

    union all

    select
      m.id as media_id,
      coalesce(mm.match_count, 0) as match_count,
      (
        coalesce(mm.match_count, 0) * 8
        + ln(1 + coalesce(m.favourites, 0)) * 2.0
        + ln(1 + coalesce(m.popularity, 0)) * 1.0
        + (coalesce(m.average_score, 0) / 10.0)
        + case
            when m.start_date_year is not null and m.start_date_year <= 2000 then 6
            when m.start_date_year is not null and m.start_date_year <= 2015 then 4
            else 0
          end
        + coalesce(eb.weight, 0)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(mp.penalty, 0)
          end
      )::real as score
    from public.manga m
    left join manga_match mm on mm.media_id = m.id
    left join public.editorial_boosts eb on eb.media_type = 'MANGA' and eb.media_id = m.id
    left join manga_pen mp on mp.media_id = m.id
    where p_media_type = 'MANGA'
      and (select user_id from me) is not null
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ) ranked
  order by score desc
  limit (select lim from req);
$$;

grant execute on function public.recommend_ids_premium(text, text[], integer, boolean) to authenticated;

commit;
```

---

## 20) Appendix E — Data Dictionary (human-readable)

Notes:
- Column types and constraints are defined in the DDL appendices above.
- This section provides **semantic meaning** for each column.
- If a column is not listed in a downstream migration, assume it still exists from the base DDL unless dropped later.

### anime
- id: internal primary key (may or may not match AniList id; see schema note below).
- anilist_id, mal_id, kitsu_id: external IDs for sync/dedup.
- title_english, title_romaji, title_native: localized titles.
- title_synonyms: extra title aliases from source.
- cover_image_large, cover_image_medium, cover_image_color, banner_image: artwork URLs.
- format: TV/MOVIE/OVA/etc.
- status: FINISHED/RELEASING/NOT_YET_RELEASED.
- description: raw synopsis text.
- description_normalized: sanitized/plain text for search.
- episodes: total episodes (if known).
- duration: minutes per episode.
- total_duration: episodes * duration.
- season, season_year: seasonal metadata.
- next_episode_number, next_airing_at: next airing info.
- start_date_year/month/day, end_date_year/month/day: date components.
- average_score, mean_score: ratings.
- popularity, trending, favourites: ranking stats.
- genres: text array.
- source: original source type (manga, original, etc).
- country_of_origin: two-letter origin.
- is_adult: adult flag.
- age_rating: content rating string.
- site_url: AniList page.
- created_at, updated_at, last_synced_at, updated_at_anilist: system timestamps.

### manga
- id: internal primary key.
- anilist_id, mal_id, kitsu_id: external IDs.
- title_english, title_romaji, title_native, title_synonyms: titles.
- cover_image_large/medium/color, banner_image: artwork.
- format: MANGA/NOVEL/ONE_SHOT/etc.
- status: FINISHED/RELEASING/HIATUS/etc.
- description, description_normalized: synopsis.
- chapters, volumes: totals.
- next_chapter_number, next_chapter_at: next release info.
- start/end date components.
- average_score, mean_score, popularity, trending, favourites.
- genres, source, country_of_origin.
- is_adult, age_rating.
- site_url.
- created_at, updated_at, last_synced_at, updated_at_anilist.

### episodes
- id: internal PK.
- anime_id: FK to anime.
- anilist_id, mal_id: external episode IDs.
- number: episode number.
- title, title_romaji: names.
- description: episode synopsis.
- air_date, air_at: date/time.
- thumbnail: image URL.
- duration: minutes.
- is_filler, is_recap, is_mixed, filler_source: content classification.
- stream_url, stream_site: streaming CTA info (migration 13).
- created_at, updated_at.

### chapters
- id: internal PK.
- manga_id: FK to manga.
- anilist_id, mal_id: external chapter IDs.
- number: chapter number.
- title, title_romaji, description.
- release_date, release_at.
- created_at, updated_at.

### volumes
- id: internal PK.
- manga_id: FK to manga.
- number, title, description.
- release_date.
- created_at, updated_at.

### characters
- id: internal PK.
- anilist_id, mal_id, kitsu_id: external IDs.
- name_full, name_native.
- image_large, image_medium.
- description, gender, age, blood_type.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### studios
- id: internal PK.
- anilist_id, mal_id, kitsu_id.
- name.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### authors
- id: internal PK.
- anilist_id, mal_id, kitsu_id.
- name_full, name_native.
- image_large, image_medium.
- description.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### staff
- id: internal PK.
- anilist_id, mal_id, kitsu_id.
- name_full, name_native.
- image_large, image_medium.
- description.
- primary_occupations.
- site_url.
- favourites.
- created_at, updated_at, last_synced_at.

### tags
- id: internal PK (AniList tag id).
- name, description.
- category.
- rank.
- is_spoiler, is_adult.
- created_at, updated_at.

### anime_characters / manga_characters
- anime_id or manga_id.
- character_id.
- role (main, supporting, etc).
- created_at, updated_at.

### anime_studios / manga_authors
- anime_id or manga_id.
- studio_id or author_id.
- is_main (for studios).
- created_at, updated_at.

### anime_staff / manga_staff
- anime_id or manga_id.
- staff_id.
- role (string).
- created_at, updated_at.

### anime_tags / manga_tags
- anime_id or manga_id.
- tag_id.
- rank.
- is_spoiler, is_adult.
- created_at, updated_at.

### anime_user_lists / manga_user_lists
- id: list row PK.
- user_id: auth user id.
- anime_id or manga_id.
- list_type: WATCHING/PLANNING/COMPLETED/etc.
- progress: episodes/chapters count.
- rating: integer (0-10, converted to 0-100 in view).
- notes.
- created_at, updated_at.

### anime_comments / manga_comments
- id: PK.
- user_id.
- anime_id or manga_id.
- comment text.
- created_at, updated_at.

### external_links
- id: PK.
- media_type: ANIME/MANGA.
- media_id.
- site: source site name.
- url: link.
- language, color.
- priority: rank for display.
- is_disabled.
- created_at, updated_at.

### profiles
- id: auth user id.
- display_name.
- adult_opt_in.
- created_at, updated_at.

### title_search
- id: PK.
- media_type, media_id.
- variant_type: english/romaji/native/synonym/alias/user_alias.
- title_raw, title_norm.
- lang.
- popularity.
- created_at.

### title_aliases
- user_id.
- alias_norm.
- media_type, media_id.
- title_raw.
- hits.
- created_at, updated_at.

### import_state
- media_type: ANIME/MANGA.
- last_page: cursor for imports.
- updated_at.

### import_sessions
- id: UUID.
- user_id.
- status: draft/applied/failed/cancelled.
- source: chat (default).
- created_at, updated_at.

### import_session_items
- id: UUID.
- session_id.
- raw: raw input line.
- parsed: json payload of parsed info.
- candidates: json candidate list.
- chosen: selected candidate.
- action: final action payload.
- confidence: float score.
- state: needs_choice/ready/applied/error/skipped.
- error: error text.
- created_at, updated_at.

### concierge_runs
- id: PK.
- user_id (nullable).
- kind: parse/recommend/apply/llm_router/llm_resolve.
- status: success/error/skipped.
- input_chars, items_count.
- latency_ms.
- token_in, token_out.
- error.
- created_at.

### concierge_parse_feedback
- id: PK.
- user_id.
- raw_snippet, normalized, alias_norm.
- best_score, candidates_count.
- top_media_type, top_media_id.
- created_at.

### concierge_config
- id: single row (true).
- config: jsonb.
- created_at, updated_at.

### system_flags
- key (e.g., llm_enabled).
- enabled.
- created_at, updated_at.

### rate_limit_buckets
- bucket_key.
- window_start.
- hits.
- created_at, updated_at.

### llm_daily_usage
- user_id.
- day (date).
- reserved_tokens, actual_tokens.
- calls.
- last_model.
- created_at, updated_at.

### llm_global_daily_usage
- day.
- reserved_tokens, actual_tokens.
- calls.
- created_at, updated_at.

### mirror_runs
- id: PK.
- status: running/success/error/skipped.
- payload, results.
- message.
- started_at, finished_at, duration_ms.

### user_taste_profiles
- user_id.
- vector (jsonb).
- updated_at.

### user_lists (view)
- Unified view over anime_user_lists + manga_user_lists.
- Fields: media_type, media_id, status, progress, score, notes, timestamps.

### user_airing_next (view)
- User-scoped upcoming airings for anime in list.

Schema note:
- Some edge functions comment that `anime.id` and `manga.id` are AniList ids. The base DDL defines internal ids + `anilist_id` columns. If a migration or import strategy makes `id` = AniList id, update this section and the import scripts accordingly.

---

## 21) Appendix F — RPC Catalog (with examples)

These RPCs are used by the app and Edge Functions. For full SQL definitions, see migrations.

### discover_bundle(p_limit int, p_hours int) -> jsonb
- Returns: JSON with multiple rails (essentials, classics, trending, etc).
- Example:
```sql
select public.discover_bundle(30, 24);
```

### search_titles(p_query text, p_media_type text, p_limit int) -> setof (media_type, media_id, variant_type, title_raw, score)
- Example:
```sql
select * from public.search_titles('attack on titan', 'ANIME', 10);
```

### search_anime_page / search_manga_page
- Used by Search UI. Returns paged rows.
- Example:
```sql
select * from public.search_anime_page('naruto', 0, 30, null);
```

### browse_anime_page / browse_manga_page
- Used by Browse UI with sort keys.
- Example:
```sql
select * from public.browse_anime_page('popular', 0, 30, null);
```

### collection_feed_page
- Unified feed (anime + manga) sorted by updated_at.
- Example:
```sql
select * from public.collection_feed_page(null, null, null, 40);
```

### collection_anime_page / collection_manga_page
- Keyset paging for anime_user_lists / manga_user_lists.
- Example:
```sql
select * from public.collection_anime_page(null, null, 40);
```

### airing_next(days int)
- User upcoming airing episodes.
- Example:
```sql
select * from public.airing_next(7);
```

### recommend_ids_premium / recommend_ids_similar_to_seeds
- Deterministic recommendation primitives.
- Example:
```sql
select * from public.recommend_ids_premium('ANIME', array['Action'], 10, false);
```

### check_concierge_rate_limit(p_kind, p_ip, p_window_seconds, p_max_user, p_max_ip) -> jsonb
- Example:
```sql
select public.check_concierge_rate_limit('parse', '1.2.3.4', 60, null, null);
```

### get_concierge_config() -> jsonb
- Example:
```sql
select public.get_concierge_config();
```

### log_concierge_run(...)
- Used by Edge Functions to log runs (SECURITY DEFINER).

### log_concierge_parse_feedback(...)
- Stores low-confidence parse events.

### llm_budget_reserve / llm_budget_finalize
- Reserve + finalize per-user budget.

### llm_global_budget_reserve / llm_global_budget_finalize
- Reserve + finalize global daily budget.

### is_flag_enabled(p_key)
- Example:
```sql
select public.is_flag_enabled('llm_enabled');
```

### acquire_import_lock / release_import_lock
- Used by bulk imports + mirror-images to prevent overlap.

---

## 22) Appendix G — Edge Function HTTP API (examples)

All functions are invoked via:
```
POST https://<project-ref>.supabase.co/functions/v1/<function-name>
Authorization: Bearer <user-access-token>
Content-Type: application/json
```

### concierge-parse
Request:
```json
{ "text": "AoT completed, JJK ep 12", "scope": "both", "limitPerItem": 10 }
```
Response (shape):
```json
{ "success": true, "items": [ { "id": "...", "raw": "...", "candidates": [ ... ] } ], "userId": "..." }
```

### concierge-resolve
Request:
```json
{ "items": [ { "raw": "JJK", "parsed": {"status":"COMPLETED"}, "candidates": [ ... ] } ], "maxCandidates": 6 }
```
Response:
```json
{ "success": true, "choices": [ { "i": 0, "pick": 1 } ] }
```

### concierge-recommend
Request:
```json
{ "text": "something funny, not childish", "scope": "anime", "limit": 8, "narrate": true }
```
Response:
```json
{ "success": true, "items": [ { "mediaId": 12, "title": "...", "blurb": "..." } ] }
```

### concierge-apply
Request:
```json
{ "items": [ { "mediaType": "ANIME", "mediaId": 16498, "status": "COMPLETED", "progressEpisodes": 25 } ] }
```
Response:
```json
{ "success": true, "applied": 1, "sessionId": "...", "errors": [] }
```

### concierge-undo
Request:
```json
{ "sessionId": "<optional>" }
```
Response:
```json
{ "success": true, "reverted": 3 }
```

### bulk-import-anime / bulk-import-manga
Request:
```json
{ "startPage": 1, "pageCount": 10, "concurrency": 2 }
```
Response:
```json
{ "success": true, "pages": 10, "updated": 500 }
```

### mirror-images
Request:
```json
{ "bucket": "media", "mediaTypes": ["ANIME","MANGA"], "limit": 200, "offset": 0, "overwrite": false }
```
Response:
```json
{ "success": true, "results": { "anime": 180, "manga": 170 } }
```

---

## 23) Appendix H — Operator Runbook (step-by-step)

### Imports (AniList)
1. Set `SUPABASE_SERVICE_ROLE_KEY` in environment.
2. Run `scripts/run_full_import.js` or call `bulk-import-anime`/`bulk-import-manga` functions.
3. Verify `import_state` updates.
4. Run `scripts/db_state.sql` for counts.

### Image mirroring (CDN)
1. Call `mirror-images` edge function with mediaTypes.
2. Check `mirror_runs` table for status.
3. Verify storage URLs in `anime`/`manga`/`characters`/`staff`.

### Concierge budgets / rate limits
1. Update `public.concierge_config` JSON in SQL editor.
2. To disable LLM globally: `update public.system_flags set enabled=false where key='llm_enabled';`.
3. Check `llm_usage_daily_totals` and `rate_limit_recent_top` views.

### Housekeeping
- Manual run: `select public.concierge_housekeeping();`
- Scheduled job: `concierge_housekeeping_daily` (04:00 UTC).

### Troubleshooting
- If parse/recommend fails: check `concierge_runs` + edge function logs.
- If recommendations are empty: verify `user_lists` view and `recommend_*` RPCs.
- If images slow: ensure mirror-images has run and Storage URLs are used.
- If swipe/paging is broken: check `ContentView.swift` for swipe order + exclusions.

---

## 24) Appendix I — Live Supabase DB Snapshot (auto-generated, service-role only)

This appendix is **optional** and exists to detect **drift** between:
- the repo's declared schema (migrations), and
- the **live** Supabase database (production/dev).

It requires:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- the RPC `public.admin_schema_snapshot()` to be deployed (see migration `supabase/migrations/20260205160000_admin_schema_snapshot.sql`).

Rebuild:
```bash
node scripts/generate_app_state_live_snapshot.js
```

<!-- BEGIN AUTO-LIVE-DB-SNAPSHOT -->
_Not generated yet._
<!-- END AUTO-LIVE-DB-SNAPSHOT -->

---

## 25) Appendix J — Source of truth excerpts (auto-generated)

This appendix inlines the **exact current source** for the most important runtime components so another LLM can reason from ground truth without opening the repo.

For a complete (very large) source bundle, see: `CURRENT_APP_STATE_CODEBASE.md` (auto-generated).

Rebuild:
```bash
node scripts/generate_app_state_sources.js
node scripts/generate_app_state_codebase_bundle.js
```

<!-- BEGIN AUTO-SOURCE-EXCERPTS -->
_Not generated yet._
<!-- END AUTO-SOURCE-EXCERPTS -->
