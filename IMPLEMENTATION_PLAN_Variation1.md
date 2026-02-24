# Concierge "Modes Router" Plan (Variation 1)

This file documents the idea of routing free-text "vibe" prompts into curated recommendation rails (modes), with the LLM used only as an optional presentation layer.

## Current status (as of 2026-02-24)

The core plan is fully implemented, expanded, and quality-hardened. All major feature work completed. Production-readiness session completed: Apple FM integration, on-device intelligence features, and comprehensive security/stability hardening across DB, edge functions, storage, and iOS. The February 2026 follow-up added the curated concierge copy layer and club activity status clarity pass. P2 production blockers completed (2026-02-16): backend hardening (NOT NULL on catalog created_at, 12 unused indexes dropped, merged duplicate policies, mirror health check, AVIF support), iOS bug fixes (vote error handling, task cancellation, discover error state), accessibility pass (6 views), and deep linking infrastructure (kuro:// scheme). Detail page error feedback (2026-02-17): markWatched/markRead now show error toasts, chapter accessibility hint fixed. Branded email templates + auth callback (2026-02-17): 5 editorial email templates, auth-callback edge function. Direct kuro:// redirect (2026-02-18): Supabase redirects straight to app after email verification, URL scheme registered, Resend MCP configured for production SMTP. Pre-ship quality audit (2026-02-18): 7-agent audit fixed withRetry force-unwrap, auth callback silent failure, precondition crash, BrowseGrid ForEach identity, Unicode URL encoding (1,417 links), Privacy Manifest, join_club archived check. Audit follow-up (2026-02-18): 4-agent team fixed 21 remaining findings — error handling across auth/clubs/chat, deleted ~2,100 lines dead code, fixed force-unwraps, backend hardening (storage path restriction, description validation, input limits, RPCs in migrations). Database health audit (2026-02-18): comprehensive audit of 70 tables, 67 functions, 15 cron jobs — all healthy; dropped 2 duplicate indexes + 1 dead function; backfilled 3 remote-only migrations locally; Postgres 17.6 confirmed; pending Dashboard items reduced from 6 to 3. 93 total migrations (91 local + 2 remote-applied), 60 Swift files.

**Senior stability audit pass (2026-02-20)**: Published evidence-backed audit artifacts in `/Applications/Kuro/docs/` (`audit-2026-02-20-manifest.md`, `audit-2026-02-20-findings.md`, `audit-2026-02-20-remediation-plan.md`, `audit-2026-02-20-release-gate.md`). Current gate is **NO-GO** pending remediation of one P0 (plaintext import secret exposure in migration SQL) and one P1 (deployed migration/function artifacts not yet committed).

**Backend parity re-check + deploy closeout (2026-02-20)**: Re-ran Supabase CLI health checks (`functions list`, `migration list --linked`, `db lint --linked`, `inspect db db-stats`) plus iOS generic build, then applied pending migrations and deployed chapter-enrichment functions. Result: parity gap closed (remote now has `20260221150000` and `20260221162000`; function versions `manga-chapter-enrich:v4`, `manga-source-review-action:v2`). DB remains healthy with warnings-only lint and iOS build remains green.

**Chapter-enrichment collision hardening (2026-02-20)**: `manga-chapter-enrich` upgraded to `v6` with looser collision thresholds, English-title preference in tiebreak selection, stronger chapter-coverage weighting, and a race-safe chapter insert path (replacing failing PostgREST upsert conflict target). Verified on AniList `86707` (`Tales of Demons and Gods`): mapping now resolves, 321 chapter rows inserted, max chapter 468, status is `ready`.

**Import orchestration hardening (2026-02-20)**: `scripts/run_full_import.js` now includes automatic timeout fallback. When heavy anime/manga import calls return timeout-class failures (e.g. 504), the script automatically executes a schedule-safe lightweight batch and continues the loop. This keeps cursor progress moving during long backfills without manual restarts.

**Import cursor persistence fix (2026-02-20)**: `ensureImportState()` in `scripts/run_full_import.js` no longer rewinds `import_state.last_page` to zero. It now seeds ANIME/MANGA rows only when missing (`onConflict: media_type`, `ignoreDuplicates: true`) so existing cursor progress is preserved.

**Synopsis enrichment runtime hardening (2026-02-23)**: Applied migration `20260223002000_synopsis_retry_backoff_and_resume.sql` remotely and hardened the local continuous enrichment loop. `scripts/synopsis_enrichment_worker.swift` now tracks due backlog before/after, emits quality counters (`tone_polish_used`, `fallback_used`, `autodeduped_sentences`), and writes generated samples (`reports/synopsis-enrichment/generated-samples-latest.md`). `scripts/run_synopsis_enrichment.sh` now guards overlap via `.worker.lock` and self-heals stale locks via PID+TTL fallback (`SYNOPSIS_LOCK_TTL_SECONDS`), and `scripts/install_synopsis_enrichment_launchd.sh` preserves existing env values while validating required Supabase secrets before install. Dashboard (`scripts/synopsis_dashboard_server.js`) now shows cumulative/24h totals plus generated-sample visibility, and `/api/status` now backfills `updated_at` from latest run metadata when missing in status JSON.

**Catalog safety runner split (2026-02-24)**: Added a fully separate catalog-safety runtime so synopsis and safety pipelines are operationally isolated. New migration `20260224101000_catalog_safety_runner_v1.sql` adds safety state fields on `anime`/`manga`, lexicon/audit tables, and service-role RPCs (`get_catalog_safety_candidates`, `upsert_catalog_safety_result`, `mark_catalog_safety_failed`, `get_catalog_safety_open_gaps`, `get_catalog_safety_backlog_count`). New scripts: `scripts/catalog_safety_worker.swift`, `scripts/run_catalog_safety.sh`, `scripts/install_catalog_safety_launchd.sh`, and `scripts/catalog_safety_dashboard_server.js` (localhost `:8788`). Safety reports now live under `reports/catalog-safety/` (`uncertain-latest.md` + per-run uncertain files), independent from synopsis report files and launchd label.

**Catalog safety audit remediation (2026-02-24)**: Removed silent open-gap fallback in `scripts/catalog_safety_worker.swift`. Open-gap fetch now uses explicit error handling, increments `open_gaps_fetch_failed`, logs warning lines to worker log, preserves `uncertain-latest.md` when fetch fails to avoid false empty/open-gap dashboards, and now includes `open_gaps_fetch_failed` in run summary lines for faster ops triage. Technical inventory in `CURRENT_APP_STATE.md` was regenerated to remove stale file/count claims, `CLAUDE.md` runtime function-version snapshot was synchronized with live deployed versions, and the safety dashboard now visualizes queue completion progress (baseline/remaining/reduced + %).

**Catalog safety uncertain-rate fix (2026-02-24)**: Investigated high uncertain runs and confirmed dominant pattern was `model_uncertain + no_strong_signal`. Updated worker decisioning to mark titles as safe when there is no meaningful porn signal (low rule score + no rule hits), added `safe_fallback_no_signal` metric, and surfaced it on the safety dashboard. Forced validation run showed expected behavior (`processed=240`, `safe=235`, `uncertain=0`, `blocked=5`).

**Detail page scrolling fixes (2026-02-24)**: Fixed two bugs on anime/manga detail sheets. (1) Vertical dead zone at bottom: hero `.offset(y: -safeTop)` was visual-only, leaving a phantom layout gap; added `.padding(.bottom, -safeTop)` to compensate. (2) Horizontal rails ("More Like This") couldn't scroll: removed `.kuroSwipeExclusionZone()` from `SimilarSection`/`MangaSimilarSection` — these sections only appear inside sheets where the pager gesture doesn't apply, so the exclusion zone just added a competing drag recognizer. Build: SUCCEEDED.

**Social Activity Layer + Add to Club Context Menu (2026-02-24)**: Replaced club-level ephemeral chat with title-level social activity. New migration `20260224150000_social_activity_layer.sql` adds `title_comments` and `title_comment_reactions` tables, `shares_club_with()` SECURITY DEFINER helper, RLS policies gating visibility to club co-members, and 5 RPCs (`upsert_title_comment`, `delete_title_comment`, `toggle_comment_reaction`, `fetch_friend_activity_for_title`, `count_friends_tracking`). Rate-limited (10 comments/5min, 30 reactions/min). Feature flag `social_activity_v1` at 0% for staged rollout. iOS: new `FriendsActivitySection.swift` on detail pages (friend tracking pills, comments, reactions), friend count indicators on all card types (Portrait/Compact/Hero/SharedVertical/SharedHorizontal), batch prefetch on Discover/Browse/Collection, "Add to Club..." context menu on cards, `AddToClubRailSheet` made public. Club chat tab removed from `ClubDetailView` (~315 lines), `clubs_chat_v1` disabled, `prune_club_messages` cron unscheduled. 2 new files, 12 modified, 64 Swift files, 142 migrations. Build: SUCCEEDED.

**Manga matching hardening v2 (2026-02-20)**: `manga-chapter-enrich` now supports runtime matcher mode (`strict`/`fuzzy_v2`), weighted fuzzy title scoring with confidence+margin gates, hard conflict filtering on external IDs, persistent mapping verification memory (`next_verify_at`, `verify_status`, fail counters), and automatic safety degrade to strict mode when 24h wrong-map proxy exceeds threshold. Added migration `20260220103000_manga_fuzzy_matcher_v2.sql` (new verification columns + candidate priority class 4 + quality metrics RPC + daily auto-expire for stale pending review rows). `scripts/check_cron_health.js` now prints a dedicated fuzzy quality scorecard (auto-resolve, wrong-map proxy, unresolved trend, verify deactivation, mode/degraded flag).

**Additional backend pipeline (2026-02-19)**: Implemented Manga Chapter Enrichment v1 as a separate additive path (no router behavior changes): new edge function `manga-chapter-enrich`, new mapping/review tables (`manga_source_links`, `manga_source_link_review`), candidate + metrics RPCs, and 15-minute cron schedule. Follow-up migration `20260219234000_fix_manga_chapter_enrich_cron_secret.sql` hardens the cron header path so `x-import-secret` is always sent. Added `manga-source-review-action` edge function plus migration `20260219235500_manga_review_approved_mapping_method.sql` so unresolved review rows can be approved/rejected and immediately re-enriched in one call. iOS manga chapter-open behavior now uses strict legal-provider link allowlist and no longer falls back to generic `siteUrl`.

**Add-to-rail + adaptive sizing (2026-02-16)**: "+" button per club rail in ClubDetailView opens AddItemToRailSheet with server-side search and typed PostgrestError handling. Member identity labels stabilized (UUID hex prefix). Adaptive card widths across all surfaces (Discover, GenreHub, detail similar sections) — removed hardcoded 393pt default, cards scale via `floor((screenWidth - 56) / 2.8)` clamped [112, 144].

**Clubs Enhancement completed (2026-02-16)**: 6-phase expansion shipped — list enrichment (member counts, activity previews, unread dots), emoji reactions (fire/heart/eyes/100 with anonymous aggregate counts), watch-together pace sync (median-based "3 ep behind the group"), Supabase Realtime subscriptions (live updates without pull-to-refresh), ephemeral club chat (280 char, 30-day auto-prune, rate-limited), and in-app notification badges. 4 new DB migrations, 6 new feature flags (staged rollout: 0-100%), 9 tables total, 12 RPCs. All privacy-preserving: anonymous reaction counts, median-only pace, ephemeral chat with GDPR cascade delete.

**5-page navigation restored (2026-02-15)**: Swipe pager expanded from 3 to 5 pages: Concierge ← [Discover] → Browse → Collection → Clubs. Browse promoted from sheet modal to page. Clubs elevated from ProfileView to own page. Distance-based mounting, `.snappy` animation, 120fps ProMotion, viewport-filtered exclusion zones. Search remains global sheet.

**First TestFlight build live (2026-02-15)**: 43 UX improvements shipped via 16-agent team. Fastlane configured for automated TestFlight builds (`fastlane beta`). Build 2 (v1.0) uploaded to App Store Connect. Bundle ID: `com.Kuro.app`. Foundation Models compiled in — no entitlement needed (confirmed via ASC API). Placeholder app icon added.

**Production readiness completed (2026-02-09)**: Apple FM migration (on-device classify, disambiguate, condense, search intent), synopsis condenser, NL collection search, Next Up picks, NetworkMonitor, lifecycle handling, IMPORT_SECRET auth, storage MIME + RLS + 5MB limits, 11 DB fixes, 5 edge function hardening items, mirror cron contention fix, 64 print→DEBUG, withRetry helper, UIScreen.main deprecation fix, 6 migrations applied, 6 edge functions deployed.

**Concierge redesign completed (2026-02-09)**: State machine removed, inline chat architecture, visual token alignment with KuroDesignSystem, German NLP hardening (vibe allowlist, intent keywords, umlaut normalization), 6 new vibe modes (23 total), 12 new curated rails (50 total), auth+rate-limit parallelized, edge function warmup, and auto-apply for high-confidence imports.

**Clubs feature completed (2026-02-09)**: Full social feature with 7 tables, 22 RLS policies, 6+ RPCs, analytics, iOS views (ClubsView, ClubDetailView, ClubActivitySection, ProfileView clubs tab), import reconciliation with Add/Update/Skip and previous_values tracking, concierge-undo edge function, monochrome palette polish, member detail, security fixes.

**Security hardening completed (2026-02-09)**: Rail lock bypass fixed in RLS, function search paths pinned (`generate_invite_code`, `sharing_level_rank`), secrets gate no false-positive on anon key.

**Performance optimizations completed (2026-02-09)**: `fetch_club_bundle` LEFT JOIN refactor, auth+rate-limit parallelized in all three concierge edge functions, iOS post-apply fetches parallelized with `async let`.

Implemented:
- Config-driven "modes" (curated rails) stored in DB config JSON.
- Deterministic router that picks up to 2 modes per prompt (fast, predictable, cheap).
- Backend returns grouped rails (`sets`) plus backward-compatible flattened items.
- iOS renders rails from backend `sets`.
- Classics rail expanded (do not remove existing classic boosts; return more classics by heuristic + config filters).
- **23 modes** (v8, deployed): internal IDs map to butler-facing copy in `ConciergeCuratedCopy`:
  - `premium_picks` → **The Cut**
  - `gateway_start_here` → **Start Here**
  - `premium_action` → **Action With Craft**
  - `premium_comedy_grownup` → **Comedy With Bite**
  - `cozy_comfort` → **Soft Evenings**
  - `dark_serious` → **Dark, Not Empty**
  - `hidden_gems` → **Underseen**
  - `classics_expanded` → **The Canon**
  - `short_one_season` → **Short, Complete**
  - `movie_night` → **One Perfect Film**
  - `romance_serious` → **Romance That Lands**
  - `romcom` → **Light, Sharp Romance**
  - `fantasy_non_isekai` → **Fantasy With Texture**
  - `isekai` → **Other Worlds, Cleanly**
  - `sports` → **Competition, Pure**
  - `scifi` → **Ideas With Heat**
  - `horror_supernatural` → **Unease, Done Right**
  - `mecha` → **Steel and Stakes**
  - `mystery_detective` → **Cases With Discipline**
  - `music_performance` → **Sound and Feeling**
  - `historical` → **Period Weight**
  - `school_coming_of_age` → **Coming-of-Age, Quietly**
  - `shoujo_josei` → **Emotion, With Clarity**
- **50 curated rails** (27 original + 23 new: sports, sci-fi, horror/supernatural, mecha, mystery/detective, music/performance, historical, school/coming-of-age, shoujo/josei anime+manga, plus existing seinen anime+manga, josei manga).
- Intent detectors in `scoreMode()` for movie, short, isekai/non-isekai, romcom/serious-romance, sports, sci-fi, horror disambiguation.
- Enriched synonyms with German translations across all modes.
- **Negative genre filtering**: "action but no romance", "fantasy without harem" — parsed and applied to both curated/algorithmic rails AND mode selection (excluded genres suppress conflicting mode matches in `mapStrongGenreToModeId` and penalize conflicting modes in `scoreMode`).
- **30 abbreviations** in parser (up from 10): OP, DB/DBZ/DBS, SAO, NGE/Eva, LOTGH, MP100, BC, ToG, MiA, ReZero, KonoSuba, TPN, BNHA, DM, COTE, etc.
- **Phase 0 quality overhaul** (2026-02-08): cross-rail overlap reduced from 94% to ~36%, sequels/misclassified items removed, all rails slimmed to 30-80, classics cleaned (0 post-2014 titles), isekai rebuilt (114 bogus → 14 genuine).
- **Mode analytics table** (`concierge_mode_analytics`) for tracking mode selection patterns.
- **Enhanced audit script** with 5 quality checks: overlap, franchise duplication, classics year, rail size, score floors.
- Foundation migration consolidating all core catalog tables + import tracking + materialized views + lock RPCs (schema drift resolved).
- Migration to fix legacy production drift (`tags.kitsu_id`, `comments.user_id` type): `/Applications/Kuro/supabase/migrations/20260206143000_fix_legacy_tags_and_comments.sql`.

Not implemented yet:
- On-device Core ML classifier.
- Active learning loop ("not my vibe", "too childish", etc.) feeding training data.
- Admin UI to edit modes (today: DB JSON only).

## What happened to this plan file

`/Applications/Kuro/IMPLEMENTATION_PLAN_Variation1.md` started as a historical plan document and now tracks implementation status and follow-up refinements.

## Why this architecture is strong

It makes Concierge feel premium without paying LLM costs for every request:
- Deterministic routing + DB queries are fast and consistent.
- LLM is optional narration (and guarded by per-user + global budgets).
- The "taste" is controlled by mode constraints and editorial boosts, not prompt randomness.

## Current implementation (where it lives)

### 1) Modes config
- Migrations write `config.modes` into the single-row JSON config:
  - v1: `/Applications/Kuro/supabase/migrations/20260205190000_concierge_modes_config.sql` (6 modes)
  - v2: `/Applications/Kuro/supabase/migrations/20260205233000_concierge_modes_v2_config.sql` (8 modes + rail_id + router_llm knobs)
  - v3: `/Applications/Kuro/supabase/migrations/20260206100000_concierge_modes_v3_expanded.sql` (14 modes + enriched synonyms)
  - v7: `/Applications/Kuro/supabase/migrations/20260209100000_concierge_modes_v7_german_synonyms.sql` (German synonyms for all modes)
  - v8: `/Applications/Kuro/supabase/migrations/20260209110000_concierge_modes_v8_expanded.sql` (23 modes: +mecha, mystery_detective, music_performance, historical, school_coming_of_age, shoujo_josei)
- Modes are stored at:
  - `public.concierge_config.config.modes`

Each mode supports (subset may be omitted):
- `id`, `title`
- `synonyms` (phrase matches, including German translations)
- `required_genres`
- `exclude_genres`
- `min_score`, `min_popularity`, `max_popularity`
- `exclude_formats`
- `classic_year_max` (for classics mode)
- `rail_id` (maps media type to a pinned curated rail)

### 2) Mode router + rails output
- Implemented in:
  - `/Applications/Kuro/supabase/functions/concierge-recommend/index.ts`

Key behaviors:
- Picks up to 2 rails ("modes") for each prompt.
- Biases toward including a Classics rail as a stable second rail.
- If prompt includes a seed ("like Vagabond"), replaces the primary rail with `Similar to "X"` (deterministic similarity RPC), while keeping Classics as the other rail.
- Returns:
  - `modes`: selected rails with `confidence` + `reason`
  - `sets`: array of rails, each with `title` + `items` (`set.title` is backend/internal; UI replaces with curated copy)
  - `items`: flattened (backwards compatibility and for narration)

Perf note:
- The Edge function reuses shared candidate pools and media context across rails to avoid extra DB roundtrips.

### 3) iOS rendering
- Decoding:
  - `/Applications/Kuro/Kuro/Services/SupabaseService.swift`
- UI:
  - `/Applications/Kuro/Kuro/Views/ConciergeView.swift`

Behavior:
- If backend returns `sets`, Concierge renders each set as a titled horizontal rail (internal title -> curated/locale title at render time).
- If `sets` is missing (older backend), it falls back to the previous single list rendering.

## Reanalysis: should we do more, and what's the "better way"

### What we should keep (recommended)

Keep the current design as the default:
- Backend deterministic router + config-driven modes is the best cost/perf/iteration point.
- It already gets you 90 percent of the "premium" feel without ML complexity.

### What to improve next (highest leverage)

1. ~~Expand and tune modes in config~~ **(DONE as of v6)**
- All originally planned modes have been added, plus 3 new genre modes:
  - `Gateway / First Anime` (v2)
  - `Short One-Season` (v3: `short_one_season`)
  - `Movie Night` (v3: `movie_night`)
  - `Romance (serious)` vs `Romcom` (v3: `romance_serious`, `romcom`)
  - `Fantasy (non-isekai)` vs `Isekai` (v3: `fantasy_non_isekai`, `isekai`)
  - `Sports` (v6: `sports`) — Haikyuu, Blue Lock, Slam Dunk, Hajime no Ippo
  - `Sci-Fi` (v6: `scifi`) — Cowboy Bebop, Ghost in the Shell, Steins;Gate, Psycho-Pass
  - `Horror & Supernatural` (v6: `horror_supernatural`) — Shiki, Higurashi, Parasyte, Junji Ito
  - `Mecha` (v8: `mecha`) — Mecha (giant robots, Gundam, Evangelion)
  - `Mystery & Detective` (v8: `mystery_detective`) — Mystery & Detective (Monster, Death Note, Hyouka)
  - `Music & Performance` (v8: `music_performance`) — Music & Performance (K-On, Your Lie in April, Bocchi)
  - `Historical & Period` (v8: `historical`) — Historical & Period (Vinland Saga, Kingdom, Golden Kamuy)
  - `School & Coming of Age` (v8: `school_coming_of_age`) — School & Coming of Age (Toradora, Oregairu, Kaguya-sama)
  - `Shoujo & Josei` (v8: `shoujo_josei`) — Shoujo & Josei (Fruits Basket, Nana, Skip and Loafer)
- Demographic rails added (not full modes): seinen, shoujo, josei
- Current count: **23 modes** (within the recommended 20-50 ceiling). Room for more.

2. Add a feedback loop (active learning)
- Add UI actions like:
  - "Not my vibe" (for the whole rail)
  - "More like this" / "Less like this" (for a title)
  - "Too childish" / "Too dark" quick toggles
- Log this as labeled data (user prompt -> selected mode(s) -> feedback).
- Use it to improve synonyms and scoring (and later train ML).

3. Add a lightweight evaluation harness
- Reuse the existing scripts/corpus infrastructure to measure routing stability and result quality:
  - `/Applications/Kuro/scripts/concierge_eval_parse.js` (pattern to follow)
  - Add a similar `concierge_eval_modes.js` if needed (prompt -> expected modes).

### Core ML vs server-side embedding router

Core ML (on-device):
- Pros: instant, free per request, private, works offline.
- Cons: requires a training + versioning pipeline and shipping app updates to improve routing.
- When to do it: only after we have enough real labeled data (from feedback) and we see misrouting is a real problem.

Server-side embeddings (router):
- Pros: easy to iterate without app update (update mode vectors or examples).
- Cons: embedding calls cost money and add latency; also introduces a new provider dependency.
- If you want "ML but cheap", do it offline:
  - Precompute mode centroids from synonyms.
  - Only embed user text when deterministic scoring confidence is low.
  - Cache (prompt_norm -> chosen_modes) for a while.

Pragmatic recommendation:
- Keep deterministic router as primary (already done).
- Add feedback logging + mode tuning first.
- Add ML only if metrics show it meaningfully improves routing.

## Two-mode vs one-mode routing

You previously asked for up to 2 modes. That is implemented and is a good default:
- Mode A: best-fit vibe rail
- Mode B: Classics (expanded) rail (stable, always good)

If you ever want to switch to 1-mode:
- Keep Classics as a separate fixed section in Discover (not in Concierge).
- Let Concierge always return one rail for "vibe" only.

## Deployment notes

To get the latest 23-mode router live, you must deploy:
- DB migrations (in order): **93 total migrations (91 local + 2 remote-applied)** — see `supabase/migrations/` for full list
  - Key mode migrations:
    - `20260205190000_concierge_modes_config.sql` (v1: 6 modes)
    - `20260205233000_concierge_modes_v2_config.sql` (v2: 8 modes + rail_id + router_llm)
    - `20260206100000_concierge_modes_v3_expanded.sql` (v3: 14 modes)
    - `20260208022110_add_sports_mode.sql` (sports rails)
    - `20260208022153_add_scifi_mode.sql` (sci-fi rails)
    - `20260208022239_add_horror_supernatural_mode.sql` (horror/supernatural rails)
    - `20260208022342_add_demographic_rails.sql` (seinen, shoujo, josei)
    - `20260208022356_update_concierge_config_new_modes.sql` (v6: 17 modes in config)
    - `20260209100000_concierge_modes_v7_german_synonyms.sql` (v7: German synonyms)
    - `20260209110000_concierge_modes_v8_expanded.sql` (v8: 23 modes)
  - Key quality migrations:
    - `20260208022035_phase0_remove_sequels.sql`
    - `20260208022136_phase0_remove_misclassified.sql`
    - `20260208022250_phase0_dedup_rails.sql`
    - `20260208022326_phase0_slim_and_rerank.sql`
    - `20260208022404_phase0_fix_classics.sql`
- Edge functions (deployed):
  - `concierge-parse` (year mention extraction + boost; strips years from trigram search queries)
  - `concierge-resolve` (includes year/format tags in LLM prompt and passes them through in response)
  - `concierge-recommend` (negative-genre suppression in routing + scoring; improved seed/classics intent)
- Note: Avoid pinning Edge Function version numbers in docs. Verify actual deployed versions with:
  - `supabase functions list --project-ref bkdifromsqxkndnllmdj`
- **Adaptation disambiguation** (iOS): auto-apply guard blocks when top candidates share base title but differ in media_id. Year override: if user mentions a year matching the top candidate, auto-apply proceeds.

The iOS UI is already compatible (renders `sets` when present).

## Quality infrastructure

- **Audit script**: `scripts/audit_curated_rails_quality.js` — 5 checks: cross-rail overlap (>15%), franchise duplication, classics year (>2014), rail size (>80), score floor (category-specific). Run with `node scripts/audit_curated_rails_quality.js`.
- **Router eval**: `scripts/eval_router.js` — 63 test cases against live endpoint, 90% pass threshold. Exponential backoff for 429/5xx (up to 3 retries, honours Retry-After). Infra errors excluded from pass rate.
- **Rail generator**: `scripts/generate_rail_migration.js` — deterministic SQL from `scripts/rail_config.json`. Validates: no duplicates, max 100 items/rail, valid media types. Same config always produces same SQL.
- **Mode analytics**: `concierge_mode_analytics` table logs mode selections, synonyms matched, confidence scores, and whether the request was LLM-routed.
- **Overlap target**: No rail pair should exceed 15% overlap (was 94%, now ~36% worst-case).

## Concierge redesign (2026-02-09) -- COMPLETED

Full redesign across 8 phases:

### Phase 1: State machine killed, inline chat -- COMPLETED
- Removed complex state machine architecture from ConciergeView
- Replaced with inline chat-style interaction model
- Dead code removed: ConciergeOverlay.swift, KuroChanMascot.swift, getByMood(), SearchViewNew (~500 lines total)

### Phase 2: Visual token alignment -- COMPLETED
- KuroDesignSystem token alignment across all concierge UI
- Consistent spacing, typography, and color usage

### Phase 3: Editorial rec cards -- COMPLETED
- Recommendation cards redesigned with editorial styling
- Cover art integration via `cover_image_medium` in `search_titles()` return type

### Phase 4: Inline confirm -- COMPLETED
- Import confirmation now inline (no modal overlay)
- Confirm bubble shows diff groups (new vs update vs skip)

### Phase 5: Performance (warmup, parallel auth, auto-apply) -- COMPLETED
- Edge function warmup for cold-start mitigation
- Auth + rate-limit checks parallelized across all 3 edge functions
- Auto-apply for high-confidence single-item imports (with adaptation disambiguation guard)

### Phase 6: Dead code cleanup -- COMPLETED
- ConciergeOverlay.swift removed
- KuroChanMascot.swift removed
- `getByMood()` removed
- `#if false` SearchViewNew block removed (~500 lines total)

### Phase 7: German NLP -- COMPLETED
- Inflection allowlist for German vibe words
- Intent keywords expanded with German translations
- Synonym lists enriched with German equivalents across all 23 modes
- Umlaut normalization in parser
- Migration: `20260209100000_concierge_modes_v7_german_synonyms.sql`

### Phase 8: Curation expansion -- COMPLETED
- 6 new modes added (17 -> 23 total):
  - Mecha, Mystery & Detective, Music & Performance, Historical & Period, School & Coming of Age, Shoujo & Josei
- 12 new curated rails (38 -> 50 total)
- Migration: `20260209110000_concierge_modes_v8_expanded.sql`

## Security hardening (2026-02-09) -- COMPLETED

- **Rail lock bypass fixed**: RLS policies updated to prevent bypass of rail lock mechanism
  - Migrations: `20260206150000_security_hardening_rls_and_views.sql`, `20260206164200_security_hardening_rls_and_views.sql`
- **Function search paths pinned**: `generate_invite_code` and `sharing_level_rank` RPCs use explicit `SET search_path = public` to prevent search path injection
- **Secrets gate no false-positive**: Quality gate `check_secrets.sh` updated to not flag the Supabase anon key (which is public/publishable) as a leaked secret

## Concierge images (2026-02-09) -- COMPLETED

- **Migration**: `20260209000000_search_titles_add_cover_image.sql` adds `cover_image_medium` to `search_titles()` return type.
- **Swift model**: `ConciergeCandidate` gains `cover_image_medium: String?`.
- **Import preview (ConfirmRow)**: Now renders `KuroCachedAsyncImage` with gradient fallback instead of static gradient.
- **Recommendation carousel (PresentCard)**: Same — actual cover art from `item.imageURL` instead of gradient.
- **`ConciergeConfirmItem`**: Gains `imageURL: String?` wired from `topCandidate?.cover_image_medium`.

## Performance optimizations (2026-02-09) -- COMPLETED

All three concierge edge functions parallelized for snappiness:

- **concierge-parse**: Per-item processing now runs via `Promise.all` (was serial `for` loop). Within each item, search queries + denoised queries also parallelized. Auth + rate-limit checks parallelized. Expected 3-5x latency improvement for multi-item pastes.
- **concierge-apply**: Per-item upserts now run via `Promise.all` (was serial). Auth + rate-limit + body parsing parallelized. Expected 3-5x improvement for multi-item imports.
- **concierge-recommend**: Primary + secondary rail building now runs via `Promise.all` (was sequential). Inside `fetchMediaContext`, 3 independent DB queries parallelized. Curated rail anime/manga fetches parallelized. Seed similarity fetches parallelized. Config + tag mapping + editorial boosts fetch parallelized. LLM feature flag checks parallelized. Expected 2-3x improvement overall.
- **fetch_club_bundle RPC**: Refactored from N+1 subselects to LEFT JOIN pattern for club data fetching.
- **iOS (ConciergeView)**: Post-apply fetches (`fetchUserLists`, `fetchCollectionItems`, `fetchCollectionFeed`) now run with `async let` instead of sequential `await`.

## Clubs feature (2026-02-09) -- COMPLETED

Full feature launch across 5 phases:

### Phase 0: Product spec -- COMPLETED
- Product spec written: `/Applications/Kuro/docs/clubs-spec.md`

### Phase 1: Backend -- COMPLETED
- **7 tables**: clubs, club_members, club_activity, club_polls, club_poll_votes, club_watchlist, club_discussions
- **22 RLS policies**: Full row-level security across all club tables
- **6+ RPCs**: Including `fetch_club_bundle` (LEFT JOIN refactor for performance), `generate_invite_code`, `log_club_event`, etc.
- **Analytics table**: `club_analytics` for tracking club events
- Migrations:
  - `20260209200000_clubs_foundation.sql` (tables + indexes)
  - `20260209201000_clubs_rls_policies.sql` (22 RLS policies)
  - `20260209202000_clubs_rpcs.sql` (RPCs with pinned search paths)
  - `20260209220000_club_analytics.sql` (analytics + housekeeping)

### Phase 2: iOS UI -- COMPLETED
- `/Applications/Kuro/Kuro/Views/ClubsView.swift` — Club listing, create/join sheets
- `/Applications/Kuro/Kuro/Views/ClubDetailView.swift` — Club detail, settings, member management
- `/Applications/Kuro/Kuro/Views/DetailPages/ClubActivitySection.swift` — Activity feed section
- `/Applications/Kuro/Kuro/Views/ProfileView.swift` — Clubs tab added to user profile

### Phase 3: Import reconciliation -- COMPLETED
- Concierge parse detects existing entries in user's library
- Apply respects Add/Update/Skip actions with TOCTOU protection
- `previous_values` tracking for undo support
- iOS confirm bubble shows diff groups (new vs update vs skip)
- **concierge-undo** edge function: `/Applications/Kuro/supabase/functions/concierge-undo/index.ts`
- Migration: `20260209135229_import_reconciliation.sql`

### Phase 4: Quality gates -- COMPLETED
- **6 scripts** in `/Applications/Kuro/scripts/quality-gates/`:
  - `check_secrets.sh` — Scans for leaked secrets (no false-positive on anon key)
  - `check_migrations.sh` — Lints migration files
  - `test_router_offline.sh` — Offline router test cases
  - `audit_rails.sh` — Curated rail quality audit
  - `build_ios.sh` — iOS build verification
  - `run_all.sh` — Orchestrator: runs all gates, prints summary, exits 1 on hard-fail
- Pre-commit hook wired to quality gates

### Phase 5: Polish -- COMPLETED
- Monochrome palette applied across club UI
- Member detail views refined
- Security fixes: function search paths pinned (`generate_invite_code`, `sharing_level_rank`)
- Haptics tuned (medium for create/join/confirm, light for vote/nav)
- Empty states improved
- Owner transfer UX context-aware
- Build verified on iPhone 17 Pro simulator

## Bug fix: Progress data forwarding (2026-02-09) -- COMPLETED

**P0 fix**: `confirmImport()` in ConciergeView.swift now forwards all parsed progress fields (`progressEpisodes`, `progressChapters`, `progressVolumes`, `seasonNumber`, `episodeInSeason`, `caughtUp`, `lastEpisode`, `completed`) to the `concierge-apply` edge function. Previously these were all dropped, causing every import to land with progress=0 regardless of user input.

## Production readiness (2026-02-09) -- COMPLETED

Comprehensive production-readiness pass covering Apple FM integration, on-device intelligence features, and security/stability hardening across the full stack.

### Apple FM Migration (Partial) -- COMPLETED

On-device intelligence via Apple Foundation Models, replacing server-side LLM where possible:

- **AppleFMService.swift created** with 4 capabilities:
  - `classify` — on-device intent classification
  - `disambiguate` — on-device disambiguation for ambiguous matches
  - `condenseSynopsis` — on-device synopsis summarization
  - `parseSearchIntent` — on-device natural language search intent extraction
- **FMProvider protocol** + **StubFMProvider** for non-FM-capable devices (graceful fallback)
- **Integrated into SupabaseService.fmService** — available app-wide
- **groqRouteMode removed** from concierge-recommend: LLM router deleted entirely (only 1.36% fallback rate did not justify the cost/latency)
- **groqNarrate kept** — narration still uses Groq server-side (Apple FM not suited for long-form creative text)

### New Features -- COMPLETED

Three new on-device intelligence features shipped:

1. **Synopsis Condenser**
   - `AnimeDetailView` and `MangaDetailView` call `fmService.condenseSynopsis()` to generate concise summaries
   - Runs entirely on-device via Apple FM; falls back gracefully on non-FM devices

2. **Natural Language Collection Search**
   - `parseSearchIntent()` in AppleFMService extracts structured search parameters from free-text queries
   - Enables queries like "show me my completed manga from 2023" against local collections

3. **Next Up Pick**
   - `NextUpSection` (anime) and `MangaNextUpSection` (manga) added to detail views
   - Surfaces contextual "what to watch/read next" recommendations within series pages

### Production Blockers (P0) -- COMPLETED

| ID | Issue | Fix |
|----|-------|-----|
| P0-2 | No network monitoring | `NetworkMonitor.swift` created with `NWPathMonitor` |
| P0-3 | No lifecycle handling | `scenePhase` handling added to `KuroApp.swift` |
| P0-4 | Bulk imports unauthenticated | `IMPORT_SECRET` auth header required on all bulk import edge functions |
| P0-6 | Storage accepts any MIME type | MIME type restrictions applied to storage buckets |
| P0-7 | Storage missing RLS | RLS policies added to storage buckets |

### Production Hardening (P1) -- COMPLETED

| ID | Issue | Fix |
|----|-------|-----|
| P1-1 through P1-6 | DB schema issues | NOT NULL constraints, RLS initplan optimization, anon policies, indexes |
| P1-10 | pg_trgm in wrong schema | Moved to `extensions` schema |
| P1-11 | concierge-parse no input limit | 5,000 character limit enforced |
| P1-12 | concierge-apply no item cap | 100 item cap per request |
| P1-13 | LLM prompt injection | Input sanitization added to all LLM-facing prompts |
| P1-14 | mirror-images lock leak | Lock release guaranteed in finally block |
| P1-15 | Storage no size limit | 5MB per-file limit enforced |
| P1-16 | Mirror cron contention | Per-batch advisory locks, 120s TTL, 200-item batches, 15-min spacing between cron runs |
| P1-17 | 64 print() in production | All converted to `#if DEBUG` conditional compilation |
| P1-18 | No retry logic | `withRetry` helper added (exponential backoff, applied to 5 call sites) |
| P1-19 | UIScreen.main deprecated | Replaced with `displayScale` / window scene APIs |

### Infrastructure -- COMPLETED

- **6 DB migrations applied** to production
- **6 edge functions deployed** (concierge-parse, concierge-recommend, concierge-apply, concierge-resolve, concierge-undo, mirror-images)
- **IMPORT_SECRET** environment variable set in Supabase project + **4 pg_cron jobs** updated to include secret header
- **xcconfig files created** for environment configuration (Debug.xcconfig, Release.xcconfig)
- **Mock SupabaseService** cleaned up for testability

### Production Quality (P2) -- COMPLETED

| ID | Category | Issue | Fix |
|----|----------|-------|-----|
| P2-1 | Backend | `created_at` nullable on catalog tables | Migration `catalog_created_at_not_null`: backfilled NULLs + NOT NULL on 8 tables (anime, manga, episodes, chapters, volumes, characters, studios, staff) |
| P2-2 | Backend | 12 unused indexes (FTS/trigram superseded) | Migration `drop_unused_indexes_merge_policies_health_check`: dropped 12 indexes (FTS, duplicate genre GIN, unused sort) |
| P2-3 | Backend | Duplicate DELETE policies on club_members | Same migration: merged into single `club_members_delete_self_or_admin` |
| P2-4 | Backend | No mirror health monitoring | Same migration: created `check_mirror_health()` function returning JSONB (run stats, consecutive failures, alert boolean) |
| P2-5 | Backend | Mirror-images missing AVIF support | `getExtFromContentType()` now handles `image/avif`; cache-control changed to `max-age=31536000, immutable` |
| P2-6 | iOS | Vote errors silently swallowed | ClubDetailView: `castVote` wrapped in do/catch with `.error` toast + `errorHaptic()` |
| P2-7 | iOS | Task.detached leak on ConciergeView disappear | Tracked `@State` task refs (warmupTask, prefetchTask, prefetchTask2, backgroundRefreshTask, backgroundRefreshTask2) with consolidated `.onDisappear` cancellation |
| P2-8 | iOS | EditorialDiscoverView blank on first-load failure | `@State loadError` with inline retry view when `fetchDiscoverBundle()` fails |
| P2-9 | Accessibility | Missing VoiceOver traits across views | `.accessibilityAddTraits(.isHeader)` on section headers in ClubDetailView, EditorialCollectionView, EditorialDiscoverView, ConciergeRecommendationRails. `.accessibilityLabel` on ClubsView empty state + club cards. Message bubble labels ("You said:"/"Concierge:") and combined clarification card labels in ConciergeView/Components |
| P2-10 | Infrastructure | No deep linking | `DeepLinkRouter.swift` (enum DeepLink: anime/manga/club/collection/discover/concierge), `KuroApp.swift` `.onOpenURL`, `ContentView.swift` navigation/sheet handling, Associated Domains placeholder in entitlements |
| P2-11 | Infrastructure | Default Supabase emails, no auth callback flow | **Code complete.** 5 branded email templates in `emails/` (confirm, reset, magic-link, change-email, invite) with monochrome editorial styling (Cormorant serif, warm gray `#f5f5f0`, MSO-compatible). `auth-callback` edge function deployed (315 lines, dark-themed HTML fallback with animated K logo, type-specific messages, "Open Kuro" CTA after 4s). `redirectTo` changed from edge function URL to `kuro://auth/callback` directly (commit `13fa6f4`) — Supabase redirects straight into app (no intermediate webpage). `Info.plist` at project root registers `kuro://` URL scheme via `CFBundleURLTypes`. `INFOPLIST_FILE = Info.plist` in both Debug+Release configs. `DeepLinkRouter` extended with `.authCallback(accessToken:, refreshToken:)` + `parseAuthParams()` (fragment priority, query fallback). `KuroApp.swift:37` intercepts auth callbacks before auth gate. `SupabaseService`: `authCallbackURL` (line 420), `handleAuthCallback()` (line 483) via `setSession()`, `signUpWithEmail`/`resetPassword` pass `redirectTo`. Resend MCP server configured in `.mcp.json`. **3 manual Supabase Dashboard steps pending**: (1) add `kuro://auth/callback` to Additional Redirect URLs, (2) paste 5 email templates, (3) configure Resend SMTP credentials (`smtp.resend.com:465`). |

### 2026-02-18: Database Health Audit
- Full audit: 15 cron jobs healthy (1,177/1,177 OK), 70 tables (~420 MB), 67 functions, zero Swift-DB mismatches
- Dropped 2 duplicate indexes (~19 MB), 1 dead function
- Backfilled 3 remote-only migration files locally
- Postgres 17.6 confirmed, pending Dashboard items reduced to 3

### Backend Quality Remediation (2026-02-19) -- COMPLETE
- 5-phase remediation based on 7-agent backend audit
- Phase 1: Critical security — dropped 5 dangerous functions, revoked 4 admin functions, fixed analytics policy
- Phase 2: Edge function auth — added IMPORT_SECRET to mirror-images, deployed concierge-import-anilist
- Phase 3: Swift model fixes — fixed CodingKeys (mal_id, kitsu_id), removed dead properties (tags, trailerUrl), added Realtime publication, made is_adult NOT NULL
- Phase 4: RPC hardening — rate limits on reactions/club creation, emoji allowlist, tightened 5 policies to authenticated, fixed storage policy, added FK indexes, dropped ambiguous overloads
- Phase 5: Cron cleanup — added history cleanup, removed duplicate job, fixed scheduling overlap, updated mirror cron auth

### 2026-02-19: Pre-Ship Audit P0 Remediation — COMPLETE
- 7-agent full-stack audit identified 13 P0, 21 P1, 24 P2, 10 P3 issues
- All 13 P0 issues fixed:
  - 9 nullable DB columns constrained to NOT NULL (1 migration, 17 ALTER statements)
  - Import rating field carried through parse→apply pipeline (SupabaseService + ConciergeView)
  - Club Realtime subscriptions extended to polls + messages tables
  - Silent error handling replaced with user-visible error messages (4 locations)
  - Deep link prompt injection wired end-to-end (ContentView → ConciergeView)
  - Club chat error/retry UI added
  - Club reaction error feedback via toast
  - Mock initializer fixed for new struct properties
- Build verified: BUILD SUCCEEDED

### Still Pending (deferred)

These items were evaluated and intentionally deferred:

| ID | Issue | Reason Deferred |
|----|-------|-----------------|
| P0-1 | Anon key hardcoded in SupabaseService.swift | Actually safe — this is the public anon key (not service_role). xcconfig infrastructure created for future migration. |
| P0-5 | Image mirroring backlog (2.7%) | Long-term data backfill issue, not a code fix. Mirror cron will catch up over time. |
| P1-7 | ~~Postgres version upgrade~~ | **Done** (2026-02-18): Postgres 17.6 confirmed via DB health audit |
| P1-8 | OTP configuration | Dashboard-only operation (Supabase console) — kept as-is after review |
| P1-9 | ~~Leaked password detection~~ | **Skipped** (2026-02-18): evaluated and deprioritized during DB health audit |
| — | Email templates + SMTP | Dashboard-only: (1) add `kuro://auth/callback` to redirect URLs, (2) paste 5 email templates, (3) configure Resend SMTP credentials |
| — | Concierge Redesign phases 1-8 | Already completed in earlier session (see above) |
| — | On-device Core ML classifier | Deferred until sufficient labeled data from feedback loop |
| — | Active learning / feedback loop | Next priority after production stabilization |
| — | Admin UI for modes | Low priority — DB JSON editing sufficient for now |
