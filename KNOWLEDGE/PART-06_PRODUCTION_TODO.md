PART-06 Production TODO
=======================

Security & Config
- Replace fallback service-role key in `Kuro/Services/SupabaseService.swift:58` with proper anon key via Info.plist/env; never ship service role in app binaries.
- Create per-env configuration (xcconfig or Info.plist variants) and pass secrets via CI (not in repo).

Data Ingestion & Schedules
- Ensure daily schedules for:
  - bulk-import-anime (runToEnd + timeBudget).
  - bulk-import-manga (runToEnd + timeBudget).
  - mirror-images staggered batches (offset sweep). See SCHEDULES.md for payloads.
- Monitor function execution time and result counts; add additional staggered schedules if hitting limits.

Storage/CDN
- Create public bucket `media`; deploy mirror-images; run batches for ANIME/MANGA/CHARACTER/STAFF.
- Optionally tune cacheControl per media type.

App Features & UX
- Realtime: replace `subscribeToUpdates()` timer with Supabase Realtime for user lists and content updates.
- Discover performance: verify section caps and lazy layouts across large datasets; keep section limits (e.g., 12) to avoid overdraw.
- Search facets: verify combined filters (season + trending/airingOnly) return stable pages (ordering then range).
- Collection Management: consider a Manga-specific card/progress UI or generalize card to show chapter/volume progress.

Backend Fit & Quality
- Index audit: confirm all frequently filtered/sorted columns (trending, season_year, created_at, next_airing_at, average_score) have indexes in production.
- Date decoding: ensure ISO8601 decoding is consistent (e.g., `next_airing_at`, created/updated timestamps). Adjust dateDecodingStrategy if needed.
- Tags: if stored as text/JSON string on import, consider JSONB normalization if heavy querying/filtering by tags is planned.

Testing & CI
- Remove Firebase remnants from tests or configure Firebase properly; keep tests aligned with the actual stack.
- Add integration checks for service methods (e.g., paging stops when page < size; filters compose correctly).
- Add a minimal health check script to call edge functions and validate DB counts after scheduled runs.

Operational Targets (initial)
- Content volume: at least 2000 anime and 3000 manga; continue imports until thresholds are reached.
- Airing coverage: count titles with `next_airing_at` populated; verify “Airing Soon” returns non-trivial results daily.
- Image coverage: >95% of anime/manga rows with Storage-backed `cover_image_medium`.

Open Questions / Future Enhancements
- Trending/New accuracy: move some facets to SQL views/materialized views for clarity and reuse; consider adding “This Season, Airing only” as a view.
- “Airing Today” pill: add a dedicated endpoint/view ordering by `next_airing_at ASC` within 24h.
- Episodes/Volumes enrichment: optional separate functions to backfill episode titles/dates from other sources (if allowed), respecting ToS.

Update Discipline (must-follow)
- Any change to code or infra must update this knowledge base:
  - Update the relevant PART (do not append randomly).
  - Add/adjust File References (path:line) so LLMs can anchor precisely.
  - If adding new scope, link it from INDEX and the nearest related part.

