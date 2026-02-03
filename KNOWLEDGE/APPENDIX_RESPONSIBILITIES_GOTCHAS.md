APPENDIX Responsibilities & Gotchas
===================================

Discover (Server Sections)
- Responsibilities
  - Ensure server queries reflect intended semantics (Trending, Season, Airing Soon) with indexed columns.
  - Keep sections capped for performance; disable implicit animations on refresh.
- Gotchas
  - `next_airing_at` is UTC; format in UI accordingly.
  - Season calculations must keep month→season logic consistent across Search and Discover.

Search (Paged + Facets)
- Responsibilities
  - Always order (trending or popularity) before `.range()` to maintain stable pages.
  - Apply filters conjunctively; provide clear empty states.
- Gotchas
  - Overly restrictive combinations return empty pages; handle `hasMoreSearch=false` correctly.

Collection & Lists
- Responsibilities
  - Respect RLS: user can only read/write their own list entries; supply `auth.uid()` via anonymous login.
  - Upsert on add to avoid duplicates; delete by (user_id, media_id) on remove.
- Gotchas
  - In view `user_lists`, types for `user_id` may be text/UUID string; keep consistent in app.
  - Rating scale is 0–10 in DB; app shows 0–100 — convert appropriately.

Detail Pages
- Responsibilities
  - Display imported `episodes` when available; otherwise keep UI resilient.
- Gotchas
  - `streamingEpisodes` are incomplete for many anime; placeholder strategy may be necessary.
  - Manga `next_chapter_*` is commonly null; avoid relying on it.

Edge Functions (Imports)
- Responsibilities
  - Idempotent upserts; episodes/chapters refresh logic; pacing to respect external API.
  - Use `import_state` cursor only when requested; leave default simple mode intact.
- Gotchas
  - MAL uniqueness constraints can cause conflicts; prefer `anilist_id` as primary external key.
  - Worker timeouts: prefer `runToEnd` + `timeBudgetMs` with staggered cron.

Mirror Images
- Responsibilities
  - Skip if URL already mirrored to Storage; set cacheControl; handle content types; update DB URLs.
- Gotchas
  - Ensure bucket is public or use signed URLs; Storage public URL format must match project host.
  - Overwrite only when needed (large bandwidth otherwise).

Config/Secrets
- Responsibilities
  - Provide `SUPABASE_URL` and `SUPABASE_ANON_KEY` via Info.plist/env/CI; never ship service role in client.
- Gotchas
  - Fallback key in code is for dev only; remove before release.

Indexes & Performance
- Responsibilities
  - Maintain indexes used by UI queries: `trending`, `season_year`, `created_at`, `next_airing_at`, `average_score`, GIN on `genres`.
- Gotchas
  - Changing ordering keys without updating indexes will degrade UX (slow queries, unstable paging).

Realtime
- Responsibilities
  - If enabled, subscribe to list table changes for the authed user channel; debounce UI updates.
- Gotchas
  - Avoid extra bandwidth/updates when user isn’t on Collection views.

