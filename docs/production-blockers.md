# Kuro Production Blockers & Findings

**Generated**: 2026-02-09
**Status**: Pending review
**Source**: 4-agent production-readiness audit

---

## P0 -- Ship Blockers

| # | Area | Finding | Fix Complexity |
|---|------|---------|---------------|
| 1 | iOS | Hardcoded Supabase service_role key in `SupabaseService.swift:27` -- must rotate + move to Info.plist/xcconfig | Medium |
| 2 | iOS | No offline/network handling -- zero `NWPathMonitor` usage, raw error strings when offline | Medium |
| 3 | iOS | No app lifecycle handling -- no `scenePhase` observer, stale data + broken WebSocket after backgrounding | Medium |
| 4 | Edge | `bulk-import-anime`/`bulk-import-manga` have zero auth -- `verify_jwt: false` + no secret header | Low |
| 5 | Storage | 97.3% of images still on AniList CDN -- only 644/24,149 mirrored (2.7%), ~6 months at current rate | High |
| 6 | Storage | No MIME type restriction on `media` bucket -- any file type uploadable | Low |
| 7 | Storage | No write-protection RLS on `storage.objects` -- anon key could write/delete | Low |

## P1 -- Must Fix Before Beta

| # | Area | Finding | Fix Complexity |
|---|------|---------|---------------|
| 1 | DB | Missing `NOT NULL` on 18 FK columns across junction tables | Low (single migration) |
| 2 | DB | Anonymous write policies on user tables (comments, user_lists, clubs) | Low (single migration) |
| 3 | DB | 3 new functions missing `SET search_path = public` | Low (single migration) |
| 4 | DB | 15 RLS policies call `auth.uid()` without `(SELECT ...)` -- per-row re-evaluation | Low (single migration) |
| 5 | DB | 3 unindexed FKs on club tables (polls, rail_items, rails created_by) | Low (single migration) |
| 6 | DB | 3 duplicate indexes (anime_next_airing, anime_genres, manga_genres) | Low (single migration) |
| 7 | DB | Postgres security patches available (running 17.4.1.054) | Dashboard |
| 8 | DB | OTP expiry > 1 hour -- reduce to 5-10 minutes | Dashboard |
| 9 | DB | Leaked password protection (HaveIBeenPwned) disabled | Dashboard |
| 10 | DB | `pg_trgm` + `pg_net` in public schema instead of extensions | Medium (migration) |
| 11 | Edge | No input size limit on `concierge-parse` text field -- regex DoS risk | Low |
| 12 | Edge | No payload cap on `concierge-apply` items array -- unbounded DB writes | Low |
| 13 | Edge | User text injected directly into Groq LLM prompts (resolve + recommend) | Medium |
| 14 | Edge | `mirror-images` doesn't release import lock on failure (30-min blocking) | Low |
| 15 | Storage | No bucket-level file size limit (global 50MB too generous for images) | Low (API call) |
| 16 | Storage | Mirror cron locking: 58% of runs skipped due to contention | Medium |
| 17 | iOS | 60+ `print()` statements leak internal state to device console | Medium |
| 18 | iOS | No retry logic for transient network failures (single attempt everywhere) | Medium |
| 19 | iOS | `UIScreen.main` deprecated (ContentView.swift, KuroCachedAsyncImage.swift) | Low |

## P2 -- Nice to Fix

| # | Area | Finding |
|---|------|---------|
| 1 | DB | Nullable `created_at` on nearly all catalog tables |
| 2 | DB | 35 unused indexes (FTS/trigram superseded by title_search; club indexes pre-launch) |
| 3 | DB | Multiple permissive DELETE policies on `club_members` -- merge into single OR |
| 4 | Edge | `concierge-parse` has duplicate `serve()` call (~200 lines dead code) |
| 5 | Edge | Warmup endpoint bypasses auth (benign but inconsistent) |
| 6 | Storage | Banner images stored as PNG up to 2.8MB -- convert to JPEG/WebP |
| 7 | Storage | AVIF autodetection disabled |
| 8 | Storage | Cache-Control could use `immutable` for CDN optimization |
| 9 | Storage | No alerting when mirror pipeline stalls |
| 10 | iOS | Discover sections silently return `[]` on error (no per-rail error indicator) |
| 11 | iOS | Partial accessibility coverage (ContentView good, other views unaudited) |
| 12 | iOS | `Task.detached` in ConciergeView never cancelled on view disappear |
| 13 | iOS | Bundle ID is generic `com.kuro.app`, test targets use `Lazy.Kuro*` |
| 14 | iOS | No deep linking / universal links support |
| 15 | iOS | Vote errors silently swallowed in ClubDetailView (`try?`) |

---

## Review Schedule

- [ ] P0 items -- fix before any public release
- [ ] P1 items -- fix before beta users
- [ ] P2 items -- fix when capacity allows
- [ ] Dashboard items (OTP, password protection, Postgres upgrade) -- manual action in Supabase dashboard
