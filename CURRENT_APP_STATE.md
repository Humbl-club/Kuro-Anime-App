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

- 2026-02-05: Added/expanded CURRENT_APP_STATE docs with full technical + plain-English snapshots.
- 2026-02-05: Concierge left page + profile menu. Header simplified. Cards show `YEAR · EPS`. Concierge intro + quick-start glass pills added. Commits: `2565d4d`, `a9d0e2c`

---

## 15) Open Questions / Unknowns

- Are mirror-images / bulk import functions running on a scheduled Supabase schedule or via external cron? (Not found in migrations; assumed manual/external.)
- Exact current state of all RLS policies is in migrations; confirm if additional tables were added after 2026-02-05.
