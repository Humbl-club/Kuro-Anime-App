APPENDIX Dependency Graph & Boundaries
======================================

Graph (high-level)
- AniList GraphQL → [bulk-import-anime, bulk-import-manga] → Postgres (tables, views, indexes, RLS)
- Postgres (images as remote URLs) → [mirror-images] → Supabase Storage (public bucket `media`) → Postgres (URLs rewritten)
- iOS App (SupabaseService) → Supabase REST/FTS → Postgres → returns JSON → Swift models

Layers & Responsibilities
- Edge Functions (server)
  - Fetch from AniList; transform and upsert; ensure idempotency; enforce pacing; own data freshness.
  - Not responsible for client UI or per-user list semantics.
- Database (schema/indexes/RLS)
  - Provide fast filters (trending/season/year/airing/score); protect writes via RLS; expose public reads.
  - Not responsible for client pagination state; that’s client/service.
- Storage/CDN
  - Host images with public URLs; mirror content safely; cache headers.
  - Not responsible for image selection or aspect in UI.
- iOS App (SupabaseService + Views)
  - Manage paging and UI composition; convert filters/facets to server queries; fetch user lists and perform CRUD within RLS policies.
  - Not responsible for data ingestion or long-running sync; trigger-only via schedules.

Inter-module Dependencies
- DiscoverView → SupabaseService.fetchTrending/Season/Newly/Top/AiringSoon (SupabaseService.swift:307–365)
- Search views → SupabaseService.search (240–304) with filters
- Collection views → SupabaseService.fetchUserLists(), add/remove/update
- Detail pages → data populated by Edge Functions (`episodes`, `chapters`, `volumes`)
- SupabaseService → AppConfig (URL/key); Supabase SDK; DB tables/indexes
- Edge Functions → AniList API; DB tables; import_state; Storage (mirror-images)

Data Contracts
- Models in Kuro/Models/SupabaseModels.swift mirror DB column names via CodingKeys; computed properties handle display.
- Mirror-images rewrites `cover_image_*`, `banner_image`, and `image_large` fields to Storage URLs; UI consumes these directly.

Key Boundaries (what to take care vs not)
- Client must provide stable ordering before range; server won’t ensure deterministic windows across changes.
- Edge functions must not exceed runtime; use timeBudget and staggered schedules.
- DB must maintain indexes used in queries; otherwise UX will degrade.

