# Historical agent instructions — 9 November 2026

**Status: historical reference only.** These are exact pre-consolidation working-tree contents, including uncommitted edits. They are superseded by root `AGENTS.md`, `agents/routes.yaml` and the Claude adapter. Do not load these as instructions, execute their command lists, or use their runtime facts as current evidence.

## Original `AGENTS.md`

SHA-256: `15af4c09812e103b57594526f704ce37616ac8b52d835a7b77a74735d1d8ebd5`

~~~~markdown
# AGENTS.md — Kuro Project Rules & Context

**Last synced: 2026-03-26** | **This file is mandatory reading. Every rule is binding.**

---

## MANDATORY RULES — READ FIRST

### Rule 1: Update documentation after EVERY change
After **every single work initiative** — no matter how small — you MUST update these 3 files:
1. `CURRENT_APP_STATE.md` — authoritative technical snapshot (update the relevant sections + append to Change Log)
2. `CURRENT_APP_STATE_PLAIN.md` — plain English version (update relevant sections + append to Change Log)
3. `IMPLEMENTATION_PLAN_Variation1.md` — update status section if the change relates to any tracked feature

This is **not optional**. This is **not a suggestion**. Failure to update = incorrect system state = broken context for the next session.

### Rule 2: Update memory after EVERY change
After every change, update `~/.Codex/projects/-Applications-Kuro/memory/MEMORY.md` with:
- Any new files created or deleted
- Any new patterns discovered
- Any gotchas encountered
- Updated file counts if files were added/removed
- Any new architectural decisions

This is **mandatory, not optional**. The memory file is how future sessions get instant context.

Documentation hierarchy reference:
- `CURRENT_APP_STATE.md` = technical current-state authority
- `CURRENT_APP_STATE_PLAIN.md` = plain-English current-state authority
- `docs/documentation-surface-map.md` = keep/trim/archive map for all major Markdown surfaces
- `archive/README.md` = historical-doc disclaimer for archived material

### Rule 3: Read before writing
Never propose changes to code you haven't read. Always read the file first. Understand existing patterns before modifying.

### Rule 4: Match existing patterns exactly
This codebase has established patterns. Match them. Don't introduce new paradigms, different naming conventions, or alternative approaches unless explicitly asked.

---

## WHAT THIS APP IS (exact description)

Kuro is a curated anime + manga iOS app. It lets users browse premium editorial picks, maintain personal watchlists, create private clubs with friends, and use a "Concierge" AI assistant to import lists and get mood-based recommendations. The app runs on SwiftUI with a Supabase backend.

Latest notable shipped additions: Discover `NEW TO YOU` now rotates server-side per user (unseen titles first, then popularity/score/favourites), default anime Search/Browse/Discover now hide ancillary formats (`SPECIAL`, `MUSIC`, `TV_SHORT`) unless the user explicitly filters into them in Browse, and auth transport failures now surface clear offline/timeout/server messages instead of the generic "Cannot connect to the server."

Current release-build status: Kuro-side archive warnings from `SupabaseService`, `GenreHubView`, `KuroRefinedCard`, and `KuroTests` were cleaned on 2026-03-09; the only remaining build/test warning is Xcode's App Intents metadata tool noting that no `AppIntents.framework` dependency is present.

Runtime cleanup status: remaining delayed main-queue UI resets in `ContentView`, `Cards`, and `ConciergeInputField` were moved to cancellable task-based timing on 2026-03-10 so dismissed views no longer keep fire-and-forget `DispatchQueue.main.asyncAfter` callbacks alive.

**Tech stack (exact):**
- **Frontend**: iOS SwiftUI, `@Observable` pattern (NOT Combine — never use `ObservableObject`, `@Published`, `sink`, `assign`)
- **Backend**: Supabase — PostgreSQL + Edge Functions (Deno/TypeScript) + Storage + RPC + RLS
- **On-device AI**: Apple Foundation Models (iOS 26+) for classification tasks
- **Server-side AI**: Groq (narration only — never for routing/classification)
- **Data source**: AniList (imported via scripts + edge functions)
- **CI/CD**: Fastlane for TestFlight builds

---

## CURRENT APPLICATION STATE (as of 2026-02-24)

### Backend parity snapshot (2026-02-20 CLI re-check)
- Verified with:
  - `supabase functions list --project-ref bkdifromsqxkndnllmdj`
  - `supabase migration list --linked`
  - `supabase db lint --linked`
  - `supabase inspect db db-stats --linked`
  - `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build`
- Current state:
  - iOS build passes (`BUILD SUCCEEDED`).
  - DB lint warnings only: `public.generate_invite_code` has a shadowed/unused `_i` loop variable.
  - DB runtime health is stable (no blocking/long-running queries reported; cache hit rates remain high).
  - Deployment parity is now closed:
    - Migrations `20260221150000` and `20260221162000` are applied remotely.
    - Deployed versions are `manga-chapter-enrich:v4` and `manga-source-review-action:v2`.

### Backend/runtime snapshot refresh (2026-02-24 CLI check)
- Verified with:
  - `supabase migration list --linked`
  - `supabase functions list --project-ref bkdifromsqxkndnllmdj`
- Current state:
  - Remote migrations include `20260223002000_synopsis_retry_backoff_and_resume`.
  - Deployed function versions:
    - `manga-chapter-enrich:v10`
    - `bulk-import-anime:v20`
    - `bulk-import-manga:v19`
    - `manga-source-review-action:v2`

### Streaming availability status (2026-03-02)
- Streaming Availability v1 stays intentionally staged behind `streaming_availability_v1` at 0%.
- Additional country/language metadata scaffolding was added for pre-production validation (`20260301153000_streaming_availability_country_lang_v1.sql` + local provider-availability worker/dashboard scripts), but rollout is deferred.
- Follow-up migration `20260306113000_provider_availability_note_contract.sql` is applied remotely. `batch_provider_availability_for_media_v2` now returns `audio_languages`, `subtitle_languages`, and `countries_by_sub_lang`, and iOS renders a typed note (`dub` / `audio` / `subtitles` / generic availability) instead of forcing every audio locale into `dub`.
- Decision lock: keep this work feature-flagged and non-default until provider source/cost strategy is finalized.
- Free-source research spike now lives under `research/streaming_availability/` with local-only reports in `reports/streaming-availability-research/`. Current evidence is anime-only and partial (`13/50` deterministic matches, `12/50` titles with locale evidence, `0/25` manga matches), so it is not a production source-of-truth path. Repo paths and search-country are CLI-configurable; it remains strictly non-production.

### Synopsis enrichment runtime (local Mac, continuous)
- Worker: `scripts/synopsis_enrichment_worker.swift`
  - writes enhanced synopsis variants through RPCs (non-destructive; raw source text preserved)
  - emits metrics: `tone_polish_used`, `fallback_used`, `autodeduped_sentences`, `backlog_due_before`, `backlog_due_after`
  - writes reports to `reports/synopsis-enrichment/` including `generated-samples-latest.md` and `weak-sources-latest.md`.
- Runner: `scripts/run_synopsis_enrichment.sh`
  - single-run lock (`reports/synopsis-enrichment/.worker.lock`) prevents overlaps
  - stale lock auto-recovery uses lock PID + TTL (`SYNOPSIS_LOCK_TTL_SECONDS`, default 1800s)
  - default profile: `140..420` chars, `3..4` sentences, min source chars `110`.
- Launchd installer: `scripts/install_synopsis_enrichment_launchd.sh`
  - preserves existing env values if already installed
  - fails fast if `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are missing.
- Dashboard: `scripts/synopsis_dashboard_server.js` (localhost)
  - exposes run status, cumulative totals, 24h rollups, and generated sample previews.

### Catalog safety runtime (local Mac, separate pipeline)
- Migration scaffold: `supabase/migrations/20260224101000_catalog_safety_runner_v1.sql`
  - adds safety state columns on `anime` and `manga`
  - adds `catalog_safety_terms` + `catalog_safety_audit`
  - adds service-role RPCs: `get_catalog_safety_candidates`, `upsert_catalog_safety_result`, `mark_catalog_safety_failed`, `get_catalog_safety_open_gaps`, `get_catalog_safety_backlog_count`
- Worker: `scripts/catalog_safety_worker.swift`
  - separate report root: `reports/catalog-safety/`
  - writes `latest-status.json`, `run-*.log`, and `uncertain-latest.md`
- Runner + launchd:
  - `scripts/run_catalog_safety.sh`
  - `scripts/install_catalog_safety_launchd.sh` (label: `com.kuro.catalog-safety`, default 10-minute interval)
- Dashboard:
  - `scripts/catalog_safety_dashboard_server.js`
  - localhost URL: `http://127.0.0.1:8788`
- Isolation rule:
  - do not share lock files, launchd label, report directories, or dashboard port with synopsis pipeline.

### Navigation (5-page swipe pager)
Pages swipe left-to-right in this exact order:
1. **Concierge** — inline editorial shell for imports + recommendations
2. **Discover** — curated editorial sections (Essentials, Classics, Trending, etc.)
3. **Browse** — full catalog with filters (genre, status, length, decade, format, sort)
4. **Collection** — user's personal anime/manga list
5. **Clubs** — private groups (2-20 members) with shared rails, polls, reactions, chat

**Search is NOT a page.** It opens as a sheet from the magnifying glass icon in the header.
- Search now exposes server-backed refinement chips (`TRENDING`, `NEW`, `CLASSICS`, `HIDDEN GEMS`, plus anime-only `AIRING`) on top of query + scope.
- Discover remains editorial-first: any chip inside a single rail is a local rail refinement, not a global catalog filter.

Default page on launch: **Discover** (index 1).

### Concierge (AI assistant)
- **Architecture**: Deterministic-first NLP parser → LLM fallback (Groq for narration only)
- **23 vibe modes** (v8 config), each with curated editorial copy in EN/DE
- **50 curated rails** across anime/manga
- **UI**: Editorial shell with modular components (9 Swift files), inline chat (no full-screen takeovers)
- **Import flow**: Parse → Reconcile (Add/Update/Skip) → Confirm → Apply → Toast with Undo
- **Auto-apply**: When all items score >= 0.85 and no ambiguous adaptations
- **German NLP**: Vibe adjective inflection allowlist, intent keywords, umlaut normalization

### Clubs
- Private groups, 2-20 members, invite-code based
- 3-tab detail view: Rails / This Week / Polls (chat tab removed)
- Emoji reactions (fire/heart/eyes/100), anonymous aggregate counts
- Pace sync ("3 ep behind the group"), milestone celebrations
- Supabase Realtime subscriptions for live updates (gated by `clubs_realtime_v1`)
- Privacy levels: private (aggregates only), status (names + statuses), progress (full detail)
- In-app notification badges for unseen activity
- "Add to Club..." context menu on all card types

### Social Activity Layer
- Title-level comments + reactions visible to users who share a club ("friends")
- `title_comments` (one per user per title, 500 char max) + `title_comment_reactions` (thumbs_up/thumbs_down)
- `shares_club_with()` SECURITY DEFINER helper for friend detection
- 5 RPCs: `upsert_title_comment`, `delete_title_comment`, `toggle_comment_reaction`, `fetch_friend_activity_for_title`, `count_friends_tracking`
- Friend count indicators on cards (Portrait, Compact, Hero, SharedVertical, SharedHorizontal)
- Batch prefetch of friend counts on Discover, Browse, Collection page loads
- Feature flag: `social_activity_v1` at 100% rollout
- Rate limits: 10 comments/5min, 30 reactions/min

### On-device AI (Apple Foundation Models)
- Mode classification, disambiguation, synopsis condensation, NL collection search intent
- `AppleFMService.swift`: `@MainActor @Observable`, fresh session per request, `#available(iOS 26, *)`
- 4 `@Generable` structs — reasoning properties BEFORE selection properties (sequential generation order)
- Graceful fallback via `StubFMProvider` on non-FM-capable devices
- **NO ENTITLEMENT NEEDED** — just `import FoundationModels` + availability guard

### Feature Flags (staged rollout)
Server-controlled via `feature_flags` DB table, cached in UserDefaults, deterministic hash rollout.
Flags defined in `FeatureFlags.swift` (selected):
- `rag_assist_v1` — RAG retrieval assist
- `fm_assist_v1` — Apple Foundation Models assist
- `clarify_v2` — improved clarification flow
- `clubs_interaction_v2` — clubs interaction improvements
- `concierge_perf_v2` — concierge performance optimizations
- `concierge_editorial_v1` — editorial shell UI
- `swipe_tap_guard_v1` — swipe/tap gesture conflict guard
- `clubs_list_enriched_v1` (100%) — enriched club list cards
- `clubs_reactions_v1` (100%) — emoji reactions
- `clubs_pace_sync_v1` (100%) — pace tracking
- `clubs_realtime_v1` (100%) — live updates
- `social_activity_v1` (100%) — title-level friend comments + reactions
- `clubs_notifications_v1` (100%) — in-app badges
- `streaming_availability_v1` (0%) — where-to-watch/read provider filters and shared availability UI
- `credits_cast_v1` (100%) — characters, staff, studios, authors on detail pages
- `taste_deck_v1` (100%) — Taste Deck at pager index 0
- `personalized_new_to_you_v1` (0%) — Because-You / personalized NTY
- `discover_realm_rails_v1` (0%) — Discover Shelf + Hidden Gem (realm Stage 4)
- Debug override: `--ff-on=flag_name` / `--ff-off=flag_name` launch args

### Deep Linking
`kuro://` scheme routes (registered via `Info.plist` at project root):
- `kuro://anime/12345` → anime detail sheet
- `kuro://manga/67890` → manga detail sheet
- `kuro://club/uuid` → club detail sheet
- `kuro://collection` → Collection page
- `kuro://discover` → Discover page
- `kuro://concierge?prompt=action` → Concierge with pre-filled prompt
- `kuro://auth/callback#access_token=...&refresh_token=...` → signs user in (email verification)

### Auth Email Flow (complete step-by-step)
1. User signs up or clicks email verification link
2. Supabase verifies token server-side
3. Supabase 303-redirects to `redirectTo` URL: `kuro://auth/callback#access_token=...&refresh_token=...&type=signup`
4. iOS intercepts the `kuro://` custom scheme (registered in `Info.plist`)
5. `KuroApp.swift:33` `.onOpenURL` fires → `DeepLink.from(url:)` parses the URL
6. `DeepLinkRouter.parseAuthParams()` extracts tokens from URL fragment (Supabase) or query params (edge function fallback)
7. Auth callbacks are handled at app level (line 37, before auth gate) — NOT passed to ContentView
8. `SupabaseService.handleAuthCallback()` (line 483) calls `client.auth.setSession()` with the tokens
9. User is signed in immediately — no manual login step

**Key code locations:**
- `SupabaseService.authCallbackURL` (line 420): `kuro://auth/callback`
- `signUpWithEmail` (line 422): passes `redirectTo: Self.authCallbackURL`
- `resetPassword` (line 478): passes `redirectTo: Self.authCallbackURL`
- `handleAuthCallback` (line 483): `setSession()` + `ensureProfileRow()` + `bootstrapAfterAuth()`

**Fallback path:** `auth-callback` edge function (315 lines) — dark-themed HTML page with Cormorant serif, grain overlay, animated K logo, type-specific status messages (signup/recovery/magiclink/email_change/invite), "Open Kuro" CTA button after 4s timeout. Used when direct `kuro://` redirect fails.

**5 branded email templates** in `emails/`: warm gray `#f5f5f0` background, Cormorant serif K wordmark, monochrome editorial styling, MSO-compatible table layout, `{{ .ConfirmationURL }}` Supabase template variables.

**Custom SMTP (required for production):**
- Supabase built-in SMTP: ~2 emails/hour, only team member emails, no SLA
- Resend MCP server configured in `.mcp.json`
- Production setup: configure Resend SMTP credentials in Supabase Dashboard → Auth → SMTP Settings (`smtp.resend.com`, port 465, API key as password)

**Pending manual Supabase Dashboard step:**
1. Auth → Settings → Set "Enable email confirmations" to **OFF** (inline validation replaces email verification)

*Previously required (no longer needed for launch):* redirect URLs, email templates, SMTP/Resend config. The `emails/` templates and `auth-callback` edge function remain in repo if email confirmation is re-enabled later.

---

## FILE MAP (exact, current as of 2026-03-24)

### iOS app — 94 Swift files in `Kuro/`

**Entry points:**
- `KuroApp.swift` — `@main`, scenePhase lifecycle, NetworkMonitor + SupabaseService injection, `.onOpenURL` deep link handler
- `ContentView.swift` — 5-page swipe pager, header (KURO wordmark / section title / search + profile), deep link sheet presentation

**Services (21 files):**
- `SupabaseService.swift` — core data layer, auth/bootstrap, detail data, caching, `fmService`, `withRetry` helper
- `SupabaseService+Browse.swift` — browse page keyset paging + browse query helpers
- `SupabaseService+Clubs.swift` — club CRUD, bundle fetch/cache, reactions, polls, notifications, entity fetches, media ladder
- `SupabaseService+ClubRealtime.swift` — Supabase Realtime subscriptions for live club updates
- `SupabaseService+Collection.swift` — user collection queries, prefetch helpers
- `SupabaseService+Concierge.swift` — concierge RPC calls and session management
- `SupabaseService+Recommendations.swift` — similar-title recommendation hydration and batched ID fetches
- `SupabaseService+Social.swift` — title comments, reactions, friend activity RPCs
- `SupabaseService+Streaming.swift` — provider registry/availability, user streaming service selection, and club shared-provider helpers
- `SupabaseService+UserLists.swift` — anime/manga user list mutations (add, remove, update, toggle, batch)
- `AppleFMService.swift` — on-device FM (4 capabilities, FMProvider protocol, StubFMProvider fallback)
- `AppConfig.swift` — reads SUPABASE_URL/ANON_KEY from Info.plist/env
- `NetworkMonitor.swift` — NWPathMonitor connectivity, `isConnected`, offline banner
- `FeatureFlags.swift` — server-controlled flags, UserDefaults cache, stable hash rollout
- `DeepLinkRouter.swift` — `enum DeepLink`, `kuro://` URL parsing
- `ConciergeAnalytics.swift` — concierge + club interaction telemetry
- `TextNormalization.swift` — search/parsing text utilities
- `ImagePipeline.swift` — NSCache (~80MB) + URLCache disk cache, downsampling, request dedup
- `KuroDiskDetailCache.swift` — on-disk detail page cache
- `KuroPerf.swift` — performance measurement utilities
- `SupabaseRPCParams.swift` — RPC parameter structs

**Concierge UI (13 files):**
- `ConciergeView.swift` — main concierge view controller
- `ConciergeView+AniListImport.swift` — AniList import UI flow (extracted from ConciergeView)
- `ConciergeAniListImportCoordinator.swift` — AniList import coordination logic
- `ConciergeEditorialShell.swift` — editorial shell wrapper
- `ConciergeComponents.swift` — shared components + curated copy layer (EN/DE mode titles)
- `ConciergeInputField.swift` — text input field
- `ConciergeComposerDock.swift` — input composer dock
- `ConciergeActionFooter.swift` — action footer bar
- `ConciergeIntentDeck.swift` — quick-action intent cards
- `ConciergeImportCards.swift` — import preview/confirm cards
- `ConciergeRecommendationRails.swift` — recommendation rail rendering
- `ConciergeResponseStage.swift` — response stage rendering

**Views (remaining):**
- `EditorialDiscoverView.swift` — Discover page
- `EditorialDiscoverRouting.swift` — Discover page navigation/detail routing
- `BrowseView.swift` — Browse page shell/state (full-page, not a sheet)
- `BrowseComponents.swift` — browse controls, filters sheet, grid, hero card, skeletons
- `EditorialCollectionView.swift` — Collection page shell/state
- `EditorialCollectionComponents.swift` — collection filters, grid/list cards, empty/loading states, batch bar
- `ClubsView.swift` — Clubs list page (enriched cards, unread dots)
- `ClubDetailView.swift` — Club detail shell/state (3-tab: Rails/This Week/Polls)
- `ClubDetailShellComponents.swift` — club detail hero, status bar, tab bar, bottom bar
- `ClubDetailTabComponents.swift` — club detail tab content (rails, activity, polls)
- `ClubDetailSheets.swift` — club settings sheet, add-item sheet, rail search
- `ClubCreateSheets.swift` — Create/join club sheets
- `EditorialSearchView.swift` — Search sheet
- `OnboardingView.swift` — First-launch onboarding
- `ProfileView.swift` — Profile menu (includes Clubs secondary access)
- `ProfileFreshnessCard.swift` — profile-level provider refresh observability card
- `AuthView.swift` — Authentication
- Detail pages: `AnimeDetailView.swift`, `MangaDetailView.swift`, `MediaDetailSheet.swift`, `ClubActivitySection.swift`, `FriendsActivitySection.swift`, `ExternalLinksSection.swift`, `CastSection.swift`, `CreditsSection.swift`, `EntityDetailSheets.swift`
- UI components: `KuroRefinedCard.swift`, `KuroCardText.swift`, `KuroGlass.swift`, `KuroCachedAsyncImage.swift`, `KuroToast.swift`, `KuroTransientBanner.swift`, `KuroConciergeMark.swift`, `KuroInteractionEnvironment.swift`, `KuroLoadMoreSentinel.swift`, `KuroPagingGesture.swift`, `EditorialCards.swift`, `Cards.swift`, `QuickVerdictActionCard.swift`, `UIComponents.swift`, `GenreHubView.swift`, `CountdownTimer.swift`
- Shared: `AddToListSheet.swift` — editorial "spread" list sheet (full-bleed poster hero, capsule status pills, serif score + dots, pull-quote notes, pinned save dock)
- Shared: `PosterView.swift` — reusable poster image view
- Legacy/secondary: `DiscoverViewModel.swift`

**Design (2 files):**
- `KuroDesignSystem.swift` — colors, typography, spacing, radii, animations
- `Color+Hex.swift` — hex color utility

**Models (2 files):**
- `SupabaseModels.swift` — all Supabase data models
- `DiscoverBundle.swift` — discover bundle response model

### Supabase — 176 migration files in repo, 15 deployed edge functions (as of 2026-07-31)

**Edge functions (15):**
- `concierge-parse` — deterministic NLP parser, title candidate search
- `concierge-recommend` — deterministic recommendations + optional Groq narration (~1800 lines)
- `concierge-apply` — apply parsed items to user lists
- `concierge-resolve` — LLM disambiguation for ambiguous titles
- `concierge-undo` — rollback last import session
- `concierge-retrieve-assist` — RAG retrieval assist
- `concierge-retrieve-feedback` — RAG feedback collection
- `concierge-import-anilist` — AniList import helper
- `bulk-import-anime` — bulk anime catalog import (requires IMPORT_SECRET)
- `bulk-import-manga` — bulk manga catalog import (requires IMPORT_SECRET)
- `mirror-images` — mirror external images to Storage CDN
- `manga-chapter-enrich` — MangaDex chapter enrichment + mapping/match pipeline
- `manga-source-review-action` — approve/reject unresolved mappings and optionally trigger re-enrich
- `delete-account` — GDPR account deletion
- `auth-callback` — email verification fallback redirect page (verify_jwt: false)

**Database tables (key groups):**
- Catalog: `anime`, `manga`, `episodes`, `chapters`, `volumes`, `characters`, `staff`, `studios`, `authors`, `tags`, `genres`, `external_links` + join tables
- User: `profiles`, `anime_user_lists`, `manga_user_lists`, `import_sessions`, `import_session_items`
- Concierge: `concierge_runs`, `concierge_config`, `rate_limit_buckets`, `llm_daily_usage`, `system_flags`
- Clubs (9 tables): `clubs`, `club_members`, `club_rails`, `club_rail_items`, `club_rail_item_reactions`, `club_polls`, `club_poll_options`, `club_votes`, `club_messages`, `club_analytics`
- Social activity (2 tables): `title_comments`, `title_comment_reactions`
- Ops: `mirror_runs`, `import_state`, `feature_flags`

**Cron jobs (pg_cron):**
- Hourly: bulk-import-anime, bulk-import-manga (with IMPORT_SECRET header)
- Daily: mirror-images (per-batch locks, 200 batch, 15-min spacing, IMPORT_SECRET auth), matview refresh, concierge housekeeping, cron history cleanup (14-day retention)
- Unscheduled (deprecated): club message pruning (was 30-day, at 03:15 — chat replaced by social activity layer)

### Scripts & quality gates
- `scripts/quality-gates/` — 11 files: 8 gate scripts (`check_secrets.sh`, `check_migrations.sh`, `test_concierge_corpora.sh`, `test_router_offline.sh`, `audit_rails.sh`, `check_docs_current_state.sh`, `build_ios.sh`, `test_ios_unit.sh`), `run_all.sh` orchestrator, `router_test_cases.js` offline router test data, and `check_docs_current_state.py` docs-current-state checker
- `.githooks/pre-commit` — secrets + migration name checks
- `scripts/` — 19+ operational scripts (imports, audits, load tests, generators), including `audit_curated_rails_quality.js` (rail quality checks)

### Config, CI & Root Files
- `fastlane/Appfile` + `fastlane/Fastfile` — TestFlight automation (`fastlane beta`)
- `Config/Shared.xcconfig`, `Config/Debug.xcconfig`, `Config/Release.xcconfig` — build settings
- `Kuro/Kuro.entitlements` — `com.apple.developer.applesignin` + `applinks:kuro.app` (Associated Domains placeholder)
- `Info.plist` (project root, NOT `Kuro/Info.plist`) — `CFBundleURLTypes` registering `kuro://` URL scheme. `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Info.plist` in both Debug+Release configs (lines 447-448, 495-496 of project.pbxproj). Xcode merges generated keys with custom ones.
- `.mcp.json` (project root) — MCP server config: Supabase (HTTP, project ref `bkdifromsqxkndnllmdj`) + Resend (`@resend/mcp` via npx, API key in env)
- `emails/` — 5 branded HTML email templates (Cormorant serif wordmark, warm gray `#f5f5f0` background, black CTA buttons, MSO-compatible table layout):
  - `confirm.html` — signup email verification
  - `reset-password.html` — password reset
  - `magic-link.html` — passwordless login
  - `change-email.html` — email address change
  - `invite.html` — team/club invitation

---

## DESIGN SYSTEM (exact tokens — use these, never hardcode)

### Colors (monochrome only)
- Primary text: `Color.kuroBlack80` (black @ 0.8)
- Secondary text: `Color.kuroTextSecondary` (black @ 0.55) — WCAG AA compliant
- Tertiary text: `Color.kuroTextTertiary` (black @ 0.45)
- Subtle backgrounds: `Color.kuroBlack08` (black @ 0.08)
- Status pill text: `black.opacity(0.55)` — pill background: `black.opacity(0.06)`
- **NO colored status pills/dots anywhere.** Red ONLY for destructive actions (leave/delete).

### Typography (serif for editorial, sans-serif for body)
- `.kuroHero()` — 64pt serif, dramatic statements
- `.kuroDisplay()` — 44pt serif, large section headers
- `.kuroFeature()` — 34pt serif, feature titles
- `.kuroHeadline()` — 26pt serif, card titles
- `.kuroTitle()` — 19pt serif, secondary titles
- `.kuroBody()` — 15pt sans-serif, descriptions
- `.kuroCaption()` — 11pt sans-serif, small labels
- `.kuroMicro()` — 9pt sans-serif, tiny metadata

### Spacing (8px base unit)
- `KuroDesignSpacing.xs` = 4pt, `.sm` = 8pt, `.md` = 16pt, `.lg` = 24pt

### Radii
- `KuroRadius.xs` = 4pt, `.sm` = 8pt, `.md` = 12pt, `.lg` = 16pt

### Card sizing (adaptive, never hardcoded)
- Width formula: `floor((screenWidth - 56) / 2.8)` clamped to [112, 144]
- Always pass explicit `containerWidth` — no defaults, no hardcoded 393pt
- Poster corners: 8-12pt depending on card type

### App appearance
- **Light mode only** — `.preferredColorScheme(.light)` is set in KuroApp.swift
- Dark mode tokens are prepared but not active

---

## BACKEND DETAILS (exact)

### Supabase project
- **URL**: `https://bkdifromsqxkndnllmdj.supabase.co`
- **Project ref**: `bkdifromsqxkndnllmdj`

### Auth & RLS
- Supabase Auth (email/password with branded templates, Apple Sign In)
- Email verification: `redirectTo` → `kuro://auth/callback` (direct app redirect, no intermediate page)
- 5 branded templates in `emails/` — must be pasted into Supabase Dashboard
- Custom SMTP required for production (Resend configured in `.mcp.json`)
- RLS enabled on ALL tables — user tables scoped to `auth.uid()`
- Edge functions derive user ID from JWT — NEVER accept raw user_id from client
- Club RLS: 30+ policies, 4 SECURITY DEFINER helpers (`is_club_member`, `is_club_admin_or_owner`, `is_club_owner`, `sharing_level_rank`)
- Storage RLS: read public, write/delete authenticated, service_role full access

### User ID type mismatch (known tech debt)
- Club tables: UUID
- Legacy tables (`anime_user_lists`, `manga_user_lists`): TEXT
- JOINs require `::text` cast

### Edge function environment variables
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
- `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_MODEL_RESOLVE`
- `IMPORT_SECRET` — shared secret for bulk-import auth (pg_cron can't send JWTs)

---

## BUILD & DEPLOY COMMANDS (exact)

```bash
# iOS build (simulator — use this simulator name exactly)
xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# iOS build (CI / generic — for when simulator name might not exist)
xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build

# TestFlight upload (auto-increments build number, archives, uploads)
fastlane beta

# Push migrations to production
supabase db push --linked --include-all

# Deploy an edge function
supabase functions deploy <function-name> --project-ref bkdifromsqxkndnllmdj

# List deployed edge functions
supabase functions list --project-ref bkdifromsqxkndnllmdj

# Run quality gates
scripts/quality-gates/run_all.sh

# Check migration checksums (read-only by default)
scripts/quality-gates/check_migrations.sh
# To update checksums: scripts/quality-gates/check_migrations.sh --update
```

### TestFlight / App Store Connect
- **Bundle ID**: `com.Kuro.app` (capital K — must match exactly)
- **App Store Connect App ID**: 6759221230
- **Team ID**: YLG68JL5Y7
- **API Key**: Key ID `7L84A7P9X7`, Issuer ID `bca97a4b-8a3a-4051-9c89-510f10db0b06`
- **API Key file**: `~/.appstoreconnect/private_keys/AuthKey_7L84A7P9X7.p8`
- **Signing**: Automatic, `-allowProvisioningUpdates`

---

## ABSOLUTE DO-NOTs (violations will break things)

1. **Do NOT create `Kuro/Info.plist`** — that causes duplicate resource errors. `Info.plist` lives at the **project root** (not inside `Kuro/`). `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Info.plist` — Xcode merges generated keys with custom ones. Simple keys still go via `INFOPLIST_KEY_` build settings.
2. **Do NOT add Foundation Models entitlement** to `Kuro.entitlements` — FM works without it. The "Adapter Entitlement" in Developer Portal is only for custom LoRA fine-tunes.
3. **Do NOT use colored status indicators** — monochrome palette only. No colored dots, pills, or badges.
4. **Do NOT use `UIScreen.main`** — deprecated. Use `displayScale` / window scene APIs.
5. **Do NOT hardcode card widths** (e.g., 393pt) — always pass screen/geometry width.
6. **Do NOT use Combine** — no `ObservableObject`, `@Published`, `sink`, `assign`. Use `@Observable`.
7. **Do NOT use `supabase db execute`** — it doesn't exist. Use `inspect db table-stats --linked`.
8. **Do NOT run `supabase db dump --linked`** — requires Docker which isn't available.
9. **Do NOT use `iPhone 16 Pro` simulator** — those simulators don't exist. Use `iPhone 17 Pro`.
10. **Do NOT create tables without RLS policies** — every new table must have Row Level Security.
11. **Do NOT create SQL functions without `SET search_path = public, extensions`**.
12. **Do NOT accept raw `user_id` from client in edge functions** — always derive from JWT.
13. **Do NOT skip updating the 3 MD files** after changes (Rule 1).
14. **Do NOT skip updating MEMORY.md** after changes (Rule 2).
15. **Do NOT leave `print()` statements without `#if DEBUG` wrapping**.
16. **Do NOT add features, refactor code, or make "improvements" beyond what was asked.**

---

## PATTERNS TO FOLLOW (exact)

### When adding a new Supabase table:
1. Create migration in `supabase/migrations/`
2. Enable RLS: `ALTER TABLE public.new_table ENABLE ROW LEVEL SECURITY;`
3. Add appropriate policies (scoped to `auth.uid()`)
4. All helper functions: `SET search_path = public, extensions`
5. Push: `supabase db push --linked --include-all`
6. Run: `get_advisors(security)` to verify
7. Update the 3 MD files + MEMORY.md

### When adding a new Swift file:
1. Follow existing file naming conventions
2. Use `KuroDesignSystem` tokens for all UI
3. Use `@Observable` (never Combine)
4. Wrap all `print()` in `#if DEBUG`
5. For background tasks: use `@State` task refs + `.onDisappear` cancellation
6. Update the 3 MD files + MEMORY.md (including file inventory + counts)

### When adding a new edge function:
1. Create in `supabase/functions/<name>/index.ts`
2. Derive user ID from JWT, never from request body
3. Sanitize user text with `sanitizeForLLM()` before any LLM prompt
4. Add rate limiting where appropriate
5. Deploy: `supabase functions deploy <name> --project-ref bkdifromsqxkndnllmdj`
6. Update the 3 MD files + MEMORY.md

### Structured RPC error handling (club RPCs):
- `add_club_rail_item()` uses `RAISE EXCEPTION ... DETAIL = 'ERROR_CODE'` for machine-readable errors
- Error codes: `UNAUTHENTICATED`, `INVALID_MEDIA_TYPE`, `RAIL_NOT_FOUND`, `NOT_A_MEMBER`, `RAIL_LOCKED`, `MEDIA_NOT_FOUND`, `NOTE_TOO_LONG`, `DUPLICATE_ITEM`
- iOS parses `PostgrestError` detail field to show typed error messages (not free-form string matching)
- When adding new SECURITY DEFINER RPCs, follow this pattern: emit structured error codes in DETAIL so clients can branch without parsing messages

### Retry logic:
- Use `SupabaseService.withRetry()` — exponential backoff (500ms, 1s), only retries `URLError`, not HTTP 4xx

### Accessibility:
- Section headers: `.accessibilityAddTraits(.isHeader)`
- Interactive elements: `.accessibilityLabel` with descriptive text
- Message bubbles: prefix with "You said: ..." / "Concierge: ..."

---

## REFERENCE: Where to find full details

| Need | File |
|------|------|
| Complete technical state (14K+ lines) | `CURRENT_APP_STATE.md` |
| Plain English overview | `CURRENT_APP_STATE_PLAIN.md` |
| Implementation status tracker | `IMPLEMENTATION_PLAN_Variation1.md` |
| Session memory / gotchas | `~/.Codex/projects/-Applications-Kuro/memory/MEMORY.md` |
| Clubs product spec | `docs/clubs-spec.md` |
| Production blockers audit | `docs/production-blockers.md` |
| Apple FM migration report | `docs/apple-fm-migration-report.md` |
| Unified local ops dashboard | `scripts/unified_local_dashboard_server.js` |

## CURRENT BEHAVIOR NOTE (2026-03-06)

- Concierge is intentionally **session-local**. Do not describe it as cross-session persistent unless a future change reintroduces full, honest persistence.
- Adaptation Ladder v2 is live on project `bkdifromsqxkndnllmdj`. Use `get_media_ladder(...)` as the source of truth for editorial ladder data; do not guess adaptation/source paths from titles. Ladder coverage refreshes now flow through `enqueue_media_relation_refresh(...)` and the local `com.kuro.media-relations` worker/launchd pipeline.
- Local operational status now has a unified view at `http://127.0.0.1:8791` via `scripts/unified_local_dashboard_server.js`; it aggregates launchd/process/report state for the existing worker families instead of introducing a parallel status store.
- The unified dashboard exposes direct read-only drilldowns per service (`/service/:key/status`, `/service/:key/run`, `/service/:key/log`) plus a dedicated media-relations coverage panel and `/service/media_relations/coverage` report route.

~~~~

## Original `CLAUDE.md`

SHA-256: `f8898466e7bcd6d08f21e5a05a37fbfb6ff4e7d8c0fb00dcb5859586bbaee1dc`

~~~~markdown
# CLAUDE.md — Kuro Project Rules & Context

> **Backend load qualification, 9 November 2026 — APPROVED RECOMMENDATION FIX LIVE; FRESH RETEST SETUP.** Concierge Recommend v55 is deployed from the isolated approved closure. All eight live source entries match review; JWT verification, other functions and selected Auth settings are unchanged. The request-local query sharing passed 26 focused tests and 36 response comparisons before deployment. A fifth fresh 100-account cohort is being created for the unchanged wired gate/soak/burst/recovery; full capacity is not yet qualified. Previous 400 accounts/20 clubs remain independently clean. [Deployment receipt](docs/backend-load-2026-11-09/recommend-fanout-deployment-receipt.json).

**Last synced: 2026-11-09** | **This file is mandatory reading. Every rule is binding.**

> **Review remediation, 9 November 2026 — BACKEND LIVE; CLIENT FIXES LOCAL.** With explicit approval, deployed Recommend v54, Resolve v20, Parse v49, anime importer v87 and manga importer v85; applied `20261108120159` and `20261108120211` atomically. All 36 deployed source/dependency entries match review hashes. Live verification: 19 HTTP checks, effective client-deny/server-allow grants, rolled-back server accounting checks, and four manual bounded catalogue runs with zero errors, separate cursors and 50 voice-actor writes; the next autonomous backfill run also passed (10 anime, 112 voice-actor writes, zero errors). Auth minimum length 8, breached-password protection and trimmed callback URL are live. The auth API also changed read-only `custom_oauth_max_providers` from 3 to 32767; documented PATCH cannot restore it, Custom OAuth remains disabled, and no plan change was requested. Discover durable feedback/Undo remains a local iOS change; capacity, full release/device qualification and existing advisor/replay gaps remain open. [Deployment receipt](docs/review-remediation-2026-11-08/live-2026-11-09/RECEIPT.md). Earlier local-only status below is historical.


---

## MANDATORY RULES — READ FIRST

### Rule 1: Update documentation after EVERY change
After **every single work initiative** — no matter how small — you MUST update these 3 files:
1. `CURRENT_APP_STATE.md` — authoritative technical snapshot (update the relevant sections + append to Change Log)
2. `CURRENT_APP_STATE_PLAIN.md` — plain English version (update relevant sections + append to Change Log)
3. `IMPLEMENTATION_PLAN_Variation1.md` — update status section if the change relates to any tracked feature

This is **not optional**. This is **not a suggestion**. Failure to update = incorrect system state = broken context for the next session.

### Rule 2: Update memory after EVERY change
After every change, update `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md` with:
- Any new files created or deleted
- Any new patterns discovered
- Any gotchas encountered
- Updated file counts if files were added/removed
- Any new architectural decisions

This is **mandatory, not optional**. The memory file is how future sessions get instant context.

Documentation hierarchy reference:
- `CURRENT_APP_STATE.md` = technical current-state authority
- `CURRENT_APP_STATE_PLAIN.md` = plain-English current-state authority
- `docs/documentation-surface-map.md` = keep/trim/archive map for all major Markdown surfaces
- `archive/README.md` = historical-doc disclaimer for archived material

### Rule 3: Read before writing
Never propose changes to code you haven't read. Always read the file first. Understand existing patterns before modifying.

### Rule 4: Match existing patterns exactly
This codebase has established patterns. Match them. Don't introduce new paradigms, different naming conventions, or alternative approaches unless explicitly asked.

> **Recorded exception (2026-10-05):** the modular-architecture migration ([execution brief](docs/plans/2026-10-05-modular-architecture-plan.md), whose prompt explicitly authorizes "the architectural pattern changes and related refactors described here") was an authorized exception to this rule and to DO-NOT #16. Its results are now **the existing patterns to match**: one `@MainActor @Observable final class` owner per capability in `Kuro/<Capability>/`; the object graph built once in `Kuro/Composition/AppComposition.swift` over one Supabase client and injected with `.environment(...)` / read with `@Environment(Type.self)`; account-scoped owners conform to `AccountScopedState` and are registered in `AppComposition.makeAccountScopedStates`; tracking reads/writes only through `LibraryStore` / `LibraryActions` (local package `Packages/KuroModules`). Do not reintroduce a shared all-purpose service, `FeatureFlags.shared`-style business singletons, SDK imports in views, or a second Supabase client. Guide: `docs/modules/README.md`. Gate status and open items: the [execution ledger](docs/plans/2026-10-05-modular-architecture-execution-ledger.md).

### Rule 5: Navigation contract (binding since 2026-11-02)
Every screen follows `docs/superpowers/specs/2026-11-02-navigation-contract-design.md`: pages (pager) → journeys (one sheet hosting a navigation stack; every further tap **pushes**) → tools (task sheets that close back to their page). Every pushed page has a back chevron and working edge swipe-back; every journey page has ✕, and ✕ / swipe-down collapses the whole journey to the page it started from; no duplicate pages in a stack; every sheet has a visible close/cancel; every tappable thing opens its target; deep links collapse everything first; detail/club/person pages have the shrinking header with back/✕ always visible; foldable sections animate and remember their state for the session. A new screen or tap target that breaks a rule there is a bug, not a style choice.

### Rule 6: Discover contract (binding since 2026-11-04)
Every change to Discover (the page, See all, mood journeys, the long-press preview, or any Discover card) must satisfy R1–R8 and their acceptance tests in `docs/superpowers/specs/2026-11-04-discover-usability-design.md`:
- R1 one question per section, with personal sections saying why
- R2 never the same series twice on one page (owned titles hidden in personal/new sections, marked elsewhere)
- R3 one tap to open plus one Plan key per card, everything else in the long-press menu
- R4 instant feedback (haptic + stamp) and Undo
- R5 Not interested / Seen it remove the title at once and teach Taste (`.skip` / `.known`, never `.pass`)
- R6 visible, local, plain-word filters that never reset the page
- R7 the page ends: ≤ 6 sections, then "You're caught up for today" with Browse + Search
- R8 your place is kept

Every route from a pager page goes through the pager tap gate (`KuroRoutes.gated(by:)`), and removals are never horizontal swipes.

---

## WHAT THIS APP IS (exact description)

Kuro is a curated anime + manga iOS app. It lets users browse premium editorial picks, maintain personal watchlists, create private clubs with friends, and use a "Concierge" AI assistant to import lists and get mood-based recommendations. The app runs on SwiftUI with a Supabase backend.

Latest notable shipped additions: Discover `NEW TO YOU` now rotates server-side per user (unseen titles first, then popularity/score/favourites), default anime Search/Browse/Discover now hide ancillary formats (`SPECIAL`, `MUSIC`, `TV_SHORT`) unless the user explicitly filters into them in Browse, and auth transport failures now surface clear offline/timeout/server messages instead of the generic "Cannot connect to the server."

Current build status (2026-10-31, generic iOS Simulator compile): BUILD SUCCEEDED with 60 unique Kuro-side warnings plus the App Intents metadata note. 46 are `#IsolatedConformances` (become errors in Swift 6 mode), 8 `#ActorIsolatedCall`, 2 `#ImplicitStrongCapture`, plus single deprecation/unused-value/ViewBuilder/isolation warnings; worst files `ClubsStore`, `ImportsService`, `HomeStore`. The 2026-03-09 "only the App Intents warning" state no longer holds.

Repository state (2026-10-31): all October work is committed LOCALLY on `codex/integrated-testflight` in five grouped commits (`076eed2` iOS, `cd65c05` backend, `a055e11` tooling, `9580268` docs/evidence, `a21a867` design tools) on top of `a7f39b6`; NOT pushed. Full pre-commit safety snapshot: `refs/backup/kuro-snapshot-20261031` + `~/Kuro-backups/kuro-snapshot-20261031-1f13f56.tar.gz`. Latest handoff authority: `docs/handoffs/2026-10-08-fresh-session/HANDOFF.md`; native design plan `docs/plans/2026-10-08-native-design-polish.md` (owner visual acceptance OPEN).

**Overnight production pass (2026-11-01, branch `kuro/overnight-2026-11-01`, local only, NOT pushed, NOTHING deployed):** spec `docs/superpowers/specs/2026-11-01-overnight-production-pass-design.md` (lead's labelled decisions D1–D16 + shared data contracts), design authority `docs/overnight-2026-11-01/understand/DESIGN_RULEBOOK.md`, audit reports `docs/overnight-2026-11-01/understand/`, shared component API `docs/overnight-2026-11-01/FOUNDATION_API.md`, morning report `docs/overnight-2026-11-01/REPORT.md`. New backend work is PREPARED ONLY in `supabase/prepared-migrations/20261101*.sql` + `supabase/functions/release-intake/` (unscheduled); the client silently falls back while those RPCs are absent live.

**Details, songs & platform pass (2026-11-03, branch `kuro/details-songs-platform`, local only, NOT pushed, NOTHING applied/deployed/flagged):** all 13 owner items (detail hero/timeline/cast/More like this, songs with Apple previews, entity pages, Home Screen widgets `KuroWidgets` + App Group `group.com.Kuro.app`, release notifications per D14, Profile numbers, import restyle, edge peek). Backend is PREPARED ONLY: `supabase/prepared-migrations/20261103100000*` (voice actors), `20261103100100*` (`media_similar_v1`), `20261103100200*` (Apple theme columns), opt-in `includeVoiceActors` in `bulk-import-anime`, `--apple` pass in `scripts/series_enrichment_worker.py`; the client falls back silently while they are absent. Report (integration decisions, verification, open items): the "Report" section of `docs/details-songs-2026-11-03/index.html`.

Runtime cleanup status: remaining delayed main-queue UI resets in `ContentView`, `Cards`, and `ConciergeInputField` were moved to cancellable task-based timing on 2026-03-10 so dismissed views no longer keep fire-and-forget `DispatchQueue.main.asyncAfter` callbacks alive.

**Tech stack (exact):**
- **Frontend**: iOS SwiftUI, `@Observable` pattern (NOT Combine — never use `ObservableObject`, `@Published`, `sink`, `assign`)
- **Client architecture** (since 2026-10-05, executed locally): capability owners in `Kuro/<Capability>/` built by the composition root `Kuro/Composition/AppComposition.swift`; Library tracking domain in the local Swift package `Packages/KuroModules` (`KuroCore`, `KuroLibrary`, `KuroSupabase`). `SupabaseService` is retired and deleted.
- **Backend**: Supabase — PostgreSQL + Edge Functions (Deno/TypeScript) + Storage + RPC + RLS
- **On-device AI**: Apple Foundation Models (iOS 26+) for classification tasks
- **Server-side AI**: Groq (narration only — never for routing/classification)
- **Data source**: AniList (imported via scripts + edge functions)
- **CI/CD**: Fastlane for TestFlight builds

---

## CURRENT APPLICATION STATE (as of 2026-02-24)

### Backend parity snapshot (2026-02-20 CLI re-check)
- Verified with:
  - `supabase functions list --project-ref bkdifromsqxkndnllmdj`
  - `supabase migration list --linked`
  - `supabase db lint --linked`
  - `supabase inspect db db-stats --linked`
  - `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build`
- Current state:
  - iOS build passes (`BUILD SUCCEEDED`).
  - DB lint warnings only: `public.generate_invite_code` has a shadowed/unused `_i` loop variable.
  - DB runtime health is stable (no blocking/long-running queries reported; cache hit rates remain high).
  - Deployment parity is now closed:
    - Migrations `20260221150000` and `20260221162000` are applied remotely.
    - Deployed versions are `manga-chapter-enrich:v4` and `manga-source-review-action:v2`.

### Backend/runtime snapshot refresh (2026-02-24 CLI check)
- Verified with:
  - `supabase migration list --linked`
  - `supabase functions list --project-ref bkdifromsqxkndnllmdj`
- Current state:
  - Remote migrations include `20260223002000_synopsis_retry_backoff_and_resume`.
  - Deployed function versions:
    - `manga-chapter-enrich:v10`
    - `bulk-import-anime:v20`
    - `bulk-import-manga:v19`
    - `manga-source-review-action:v2`

### Streaming availability status (2026-03-02)
- Streaming Availability v1 stays intentionally staged behind `streaming_availability_v1` at 0%.
- Additional country/language metadata scaffolding was added for pre-production validation (`20260301153000_streaming_availability_country_lang_v1.sql` + local provider-availability worker/dashboard scripts), but rollout is deferred.
- Follow-up migration `20260306113000_provider_availability_note_contract.sql` is applied remotely. `batch_provider_availability_for_media_v2` now returns `audio_languages`, `subtitle_languages`, and `countries_by_sub_lang`, and iOS renders a typed note (`dub` / `audio` / `subtitles` / generic availability) instead of forcing every audio locale into `dub`.
- Decision lock: keep this work feature-flagged and non-default until provider source/cost strategy is finalized.
- Free-source research spike now lives under `research/streaming_availability/` with local-only reports in `reports/streaming-availability-research/`. Current evidence is anime-only and partial (`13/50` deterministic matches, `12/50` titles with locale evidence, `0/25` manga matches), so it is not a production source-of-truth path. Repo paths and search-country are CLI-configurable; it remains strictly non-production.

### Synopsis enrichment runtime (local Mac, continuous)
- Worker: `scripts/synopsis_enrichment_worker.swift`
  - writes enhanced synopsis variants through RPCs (non-destructive; raw source text preserved)
  - emits metrics: `tone_polish_used`, `fallback_used`, `autodeduped_sentences`, `backlog_due_before`, `backlog_due_after`
  - writes reports to `reports/synopsis-enrichment/` including `generated-samples-latest.md` and `weak-sources-latest.md`.
- Runner: `scripts/run_synopsis_enrichment.sh`
  - single-run lock (`reports/synopsis-enrichment/.worker.lock`) prevents overlaps
  - stale lock auto-recovery uses lock PID + TTL (`SYNOPSIS_LOCK_TTL_SECONDS`, default 1800s)
  - default profile: `140..420` chars, `3..4` sentences, min source chars `110`.
- Launchd installer: `scripts/install_synopsis_enrichment_launchd.sh`
  - preserves existing env values if already installed
  - fails fast if `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are missing.
- Dashboard: `scripts/synopsis_dashboard_server.js` (localhost)
  - exposes run status, cumulative totals, 24h rollups, and generated sample previews.

### Catalog safety runtime (local Mac, separate pipeline)
- Migration scaffold: `supabase/migrations/20260224101000_catalog_safety_runner_v1.sql`
  - adds safety state columns on `anime` and `manga`
  - adds `catalog_safety_terms` + `catalog_safety_audit`
  - adds service-role RPCs: `get_catalog_safety_candidates`, `upsert_catalog_safety_result`, `mark_catalog_safety_failed`, `get_catalog_safety_open_gaps`, `get_catalog_safety_backlog_count`
- Worker: `scripts/catalog_safety_worker.swift`
  - separate report root: `reports/catalog-safety/`
  - writes `latest-status.json`, `run-*.log`, and `uncertain-latest.md`
- Runner + launchd:
  - `scripts/run_catalog_safety.sh`
  - `scripts/install_catalog_safety_launchd.sh` (label: `com.kuro.catalog-safety`, default 10-minute interval)
- Dashboard:
  - `scripts/catalog_safety_dashboard_server.js`
  - localhost URL: `http://127.0.0.1:8788`
- Isolation rule:
  - do not share lock files, launchd label, report directories, or dashboard port with synopsis pipeline.

### Navigation (flag-aware swipe pager, `KuroMainView.pagerOrder` in `Kuro/ContentView.swift`)
Pager order depends on flags (checked in this order):
1. `series_home_native_v1` ON (also needs `series_foundation_v1` and post-sign-in hydration): **Taste** ← **Home** → **Discover** → **Collection** → **Clubs**. Browse and Concierge are not pages in this mode.
2. else `taste_deck_v1` ON (100% live): **Taste** → **Discover** → **Browse** → **Collection** → **Clubs**; Concierge is a sheet (Profile row / `kuro://concierge`).
3. else legacy: **Concierge** → Discover → Browse → Collection → Clubs.

The Taste page renders `TastePicksView` (`TasteDeckView` appears unreferenced). Home (`Kuro/Views/Home/HomeView.swift`) shows an Anime/Manga switch with three shelf scenes (`invitation` / `saved` / `inProgress`, `HomeShelfPolicy`); in `invitation` the shared `HomePagePicture` is pinned full-screen behind the header.

**Live vs simulator:** since 2026-11-02 20:53 UTC both `series_*` flags are enabled at 100% (owner request "roll out the new home to everyone"), so every signed-in install shows order 1 (Taste ← Home → Discover → Collection → Clubs). Rollback: `update feature_flags set enabled=false, rollout_percentage=0 where flag_name in ('series_foundation_v1','series_home_native_v1')`; apps keep a 24h offline cache of these two flags. Owned simulator: `7FC4B58A-430C-457D-A017-6B0095723F3F` ("iPhone 17 Pro Kuro Qualification") — always target it by UUID.

**Journeys (navigation contract, Rule 5; integrated 2026-11-02):** everything opened from a page or the header is ONE sheet hosting a navigation stack (`JourneyHost`): a title / club / person / studio / author / season overview / See all from the pager opens a root journey through `.kuroRootNavigation` (KuroRootView); Profile, Search and Concierge are `ShellJourneyHost` journeys registered as navigation layers. Every tap inside a journey pushes (`routes.openMedia/openClub/openPage/openCharacter/…`; a page already in the stack is popped back to, N5); Back + edge swipe-back pop one level; ✕ / swipe-down close the whole journey; tools (tracking editor, add to club, verdict, providers, create club/rail/poll, contact, import) open over the current page and close back to it (`KuroDiscardGuard` blocks swipe-down on unsaved input). Deep links collapse everything first (`KuroNavigationCoordinator.collapseThenOpen` / `collapseThen`, onboarding cover finishes first, 700 ms dismissal wait). Profile → Your lists says "Opens Collection" and closes Profile (N11). An account change rebuilds `ContentView` (`.id(currentUserId)`), so root journeys close with it.

**Search is NOT a page.** It opens as a journey sheet from the magnifying glass icon in the header (✕ top-right; results push).
- Search now exposes server-backed refinement chips (`TRENDING`, `NEW`, `CLASSICS`, `HIDDEN GEMS`, plus anime-only `AIRING`) on top of query + scope.
- Discover remains editorial-first: any chip inside a single rail is a local rail refinement, not a global catalog filter.

Default page on launch: `selection` starts at **Discover**; with `series_home_native_v1` effective it switches to **Home** once `SessionController.bootstrapAfterAuth` has hydrated the foundation flags (unless a deep link / start argument already chose a page).

Flag-on world regains Browse through `routes.openBrowse()` (Discover "Browse the catalogue" and Search idle state; gated by `DiscoverBrowseEntry.isOffered(flags:)` so the live world, which has a Browse page, never opens a second one). iPhone is portrait-only; on iPad each page is a 680 pt readable column (`.kuroReadableWidth()`).

### Concierge (AI assistant)
- **Architecture**: Deterministic-first NLP parser → LLM fallback (Groq for narration only)
- **23 vibe modes** (v8 config), each with curated editorial copy in EN/DE
- **50 curated rails** across anime/manga
- **UI**: Editorial shell with modular components (9 Swift files), inline chat (no full-screen takeovers)
- **Import flow**: Parse → Reconcile (Add/Update/Skip) → Confirm → Apply → Toast with Undo
- **Auto-apply**: When all items score >= 0.85 and no ambiguous adaptations
- **German NLP**: Vibe adjective inflection allowlist, intent keywords, umlaut normalization

### Clubs
- Private groups, 2-20 members, invite-code based
- 3-tab detail view: Rails / This Week / Polls (chat tab removed)
- Emoji reactions (fire/heart/eyes/100), anonymous aggregate counts
- Pace sync ("3 ep behind the group"), milestone celebrations
- Supabase Realtime subscriptions for live updates (gated by `clubs_realtime_v1`)
- Privacy levels: private (aggregates only), status (names + statuses), progress (full detail)
- In-app notification badges for unseen activity
- "Add to Club..." context menu on all card types

### Social Activity Layer
- Title-level comments + reactions visible to users who share a club ("friends")
- `title_comments` (one per user per title, 500 char max) + `title_comment_reactions` (thumbs_up/thumbs_down)
- `shares_club_with()` SECURITY DEFINER helper for friend detection
- 5 RPCs: `upsert_title_comment`, `delete_title_comment`, `toggle_comment_reaction`, `fetch_friend_activity_for_title`, `count_friends_tracking`
- Friend count indicators on cards (Portrait, Compact, Hero, SharedVertical, SharedHorizontal)
- Batch prefetch of friend counts on Discover, Browse, Collection page loads
- Feature flag: `social_activity_v1` at 100% rollout
- Rate limits: 10 comments/5min, 30 reactions/min

### On-device AI (Apple Foundation Models)
- Mode classification, disambiguation, synopsis condensation, NL collection search intent
- `AppleFMService.swift`: `@MainActor @Observable`, fresh session per request, `#available(iOS 26, *)`
- 4 `@Generable` structs — reasoning properties BEFORE selection properties (sequential generation order)
- Graceful fallback on non-FM-capable devices: `AppleFMService` itself checks availability (`isAvailable`: `#available(iOS 26, *)` + `SystemLanguageModel.default.isAvailable`) and each capability returns `nil` when unavailable, so callers take their non-FM path. `StubFMProvider` is defined but never instantiated (verified 2026-10-05)
- **NO ENTITLEMENT NEEDED** — just `import FoundationModels` + availability guard

### Feature Flags (staged rollout)
Server-controlled via `feature_flags` DB table, cached in UserDefaults, deterministic hash rollout.
Flags defined in `FeatureFlags.swift` (selected):
- `rag_assist_v1` — RAG retrieval assist
- `fm_assist_v1` — Apple Foundation Models assist
- `clarify_v2` — improved clarification flow
- `clubs_interaction_v2` — clubs interaction improvements
- `concierge_perf_v2` — concierge performance optimizations
- `concierge_editorial_v1` — editorial shell UI
- `swipe_tap_guard_v1` — swipe/tap gesture conflict guard
- `clubs_list_enriched_v1` (100%) — enriched club list cards
- `clubs_reactions_v1` (100%) — emoji reactions
- `clubs_pace_sync_v1` (100%) — pace tracking
- `clubs_realtime_v1` (100%) — live updates
- `social_activity_v1` (100%) — title-level friend comments + reactions
- `clubs_notifications_v1` (100%) — in-app badges
- `streaming_availability_v1` (0%) — where-to-watch/read provider filters and shared availability UI
- `credits_cast_v1` (100%) — characters, staff, studios, authors on detail pages
- `taste_deck_v1` (100%) — Taste page at pager index 0 (renders `TastePicksView`)
- `series_foundation_v1` (100% live since 2026-11-02 20:53 UTC; owner override row also present) — revision-fenced progress writes via the SQLite `ProgressOutbox`, import publication
- `series_home_native_v1` (100% live since 2026-11-02 20:53 UTC; owner override row also present) — Home page; requires `series_foundation_v1`. Titles open the same prototype detail pages (`AnimeDetailPage` / `MangaDetailPage` as journey pages) in both flag worlds; `SeriesAnimeDetailView` / `SeriesMangaDetailView` (`Kuro/Views/Home/SeriesDetailViews.swift`) are referenced only by `HomeCompositionSnapshotTests` (verified 2026-11-02)
- `personalized_new_to_you_v1` (0%) — Because-You / personalized NTY
- `discover_realm_rails_v1` (0%) — Discover Shelf + Hidden Gem (realm Stage 4)
- Debug override: `--ff-on=flag_name` / `--ff-off=flag_name` launch args; per-account overrides table `feature_flag_overrides` is LIVE since 2026-11-02 (owner account contact@lazy.space has both `series_*` flags on; rows are written with the service role only) and every build reads it since build 21. Only the two `series_*` flags get a 24h offline cache.
- Access (since 2026-10-05): one `FeatureFlags` instance built by `AppComposition` and injected — views use `@Environment(FeatureFlags.self)`, owners receive it by initializer. `FeatureFlags.shared` no longer exists (`scripts/quality-gates/check_architecture.sh` fails on it).

### Deep Linking
`kuro://` scheme routes (registered via `Info.plist` at project root):
- `kuro://anime/12345` → anime detail sheet
- `kuro://manga/67890` → manga detail sheet
- `kuro://club/uuid` → club detail sheet
- `kuro://join/<code>` → join club by invite code
- `kuro://mal/callback` → MAL native OAuth callback (Debug simulator only; `MAL_REGISTRATION_APPROVED=NO` in Release)
- `kuro://collection` → Collection page
- `kuro://discover` → Discover page
- `kuro://concierge?prompt=action` → Concierge with pre-filled prompt
- `kuro://auth/callback#access_token=...&refresh_token=...` → signs user in (email verification)

### Auth Email Flow (complete step-by-step)
1. User signs up or clicks email verification link
2. Supabase verifies token server-side
3. Supabase 303-redirects to `redirectTo` URL: `kuro://auth/callback#access_token=...&refresh_token=...&type=signup`
4. iOS intercepts the `kuro://` custom scheme (registered in `Info.plist`)
5. `KuroApp.swift` `.onOpenURL` fires → `DeepLink.from(url:)` parses the URL
6. `DeepLinkRouter.parseAuthParams()` extracts tokens from URL fragment (Supabase) or query params (edge function fallback)
7. Auth callbacks are handled at app level (before auth gate) — NOT passed to ContentView
8. `SessionController.handleAuthCallback(accessToken:refreshToken:)` first runs the fail-closed `AuthCallbackGuard` (while signed in, only a token whose `sub` is the current user and whose `exp` is ≥60 s ahead proceeds), then calls `client.auth.setSession()` and re-checks the session
9. User is signed in immediately — no manual login step

**Key code locations (since 2026-10-05; `SupabaseService` is retired):**
- `AuthService.authCallbackURL` (`Kuro/Identity/AuthService.swift`): `kuro://auth/callback`
- `SessionController.signUpWithEmail` → `AuthService.signUp`: no `redirectTo` (email confirmation is disabled)
- `AuthService.resetPassword`: passes `redirectTo: Self.authCallbackURL`
- `SessionController.handleAuthCallback` (`Kuro/Identity/SessionController.swift`): guard → `setSession()` → session re-check → `ensureProfileRow()` → `bootstrapAfterAuth()`

**Fallback path:** `auth-callback` edge function (315 lines) — dark-themed HTML page with Cormorant serif, grain overlay, animated K logo, type-specific status messages (signup/recovery/magiclink/email_change/invite), "Open Kuro" CTA button after 4s timeout. Used when direct `kuro://` redirect fails.

**5 branded email templates** in `emails/`: warm gray `#f5f5f0` background, Cormorant serif K wordmark, monochrome editorial styling, MSO-compatible table layout, `{{ .ConfirmationURL }}` Supabase template variables.

**Custom SMTP (required for production):**
- Supabase built-in SMTP: ~2 emails/hour, only team member emails, no SLA
- Resend MCP server configured in `.mcp.json`
- Production setup: configure Resend SMTP credentials in Supabase Dashboard → Auth → SMTP Settings (`smtp.resend.com`, port 465, API key as password)

**Pending manual Supabase Dashboard step:**
1. Auth → Settings → Set "Enable email confirmations" to **OFF** (inline validation replaces email verification)

*Previously required (no longer needed for launch):* redirect URLs, email templates, SMTP/Resend config. The `emails/` templates and `auth-callback` edge function remain in repo if email confirmation is re-enabled later.

---

## FILE MAP (exact; iOS app, package and gates current as of 2026-10-31, other subsections carry their own dates)

### iOS app — 293 Swift files in `Kuro/`

Plus 33 Swift files in the local package `Packages/KuroModules` (incl. `Package.swift`), 87 in `KuroTests/`, 6 in `KuroUITests/`, 4 in the widget extension `KuroWidgets/` and 8 in `KuroWidgetViews/` (2026-11-03: the widget views, compiled into the extension and KuroTests). Navigation map and add/remove-a-capability guide: `docs/modules/README.md`; final owner map: `docs/plans/2026-10-05-modular-architecture-ownership-map.md`.

**Entry points:**
- `KuroApp.swift` — `@main`, scenePhase lifecycle, NetworkMonitor + `AppComposition` owners injected with `.environment(...)`, `.onOpenURL` deep link handler
- `ContentView.swift` — flag-aware swipe pager (see Navigation), header `KuroHeaderNew` (KURO wordmark / section title / search + profile; clear fill on Home), deep link sheet presentation, onboarding `fullScreenCover`

**Composition root (`Kuro/Composition/`, 8 files):**
- `AppComposition.swift` — builds the object graph ONCE (`makeGraph`; KuroTests use `testingGraph`) over one Supabase client and one `AccountSessionCoordinator`; `makeAccountScopedStates` is the one ordered list of account-scoped owners; `memoryPressureOwners`
- `AccountScopedState.swift` (`cancelAccountWork()`, `clearPrivateState()`), `LibraryChangeSinks.swift`, `LibraryRefreshHook.swift`, `PostgrestLibraryTransport.swift` (SDK binding of the Library list adapter), `PostgrestRequestEncoding.swift`, `BannerCenter.swift`, `FixtureHost.swift` (DEBUG test-host fixture composition: fixture URL/key, in-memory auth, deny-all URL session)

**Capability owners (one folder each; `@MainActor @Observable final class`):**
- `Identity/` — `IdentityStore` (UI auth state), `AuthService` (SDK auth transport, `check_email_exists`, `delete-account`), `SessionController` (session funnel: restore, auth events, sign-in/out, callbacks, deletion; single Library read at bootstrap), `AuthCallbackGuard` (since 2026-11-01: a signed-out callback is accepted only with a matching `PendingAuthFlow` record written when this device started a reset/magic-link flow; PKCE `?code=` exchange; `type=recovery` → set-new-password), `PendingAuthFlow`, `AuthCopy` (EN/DE auth error mapping by SDK error code), `OnboardingCompletion` (per-account onboarding key)
- `Library/` — `LibraryActions` (the one view-facing writer mapping + banners: `save`, `apply`, `remove`, `toggleInCollection`, `incrementProgress`, `publishImport`), `LibraryRealtime` (user-list channel); the store itself is `LibraryStore` in `Packages/KuroModules`
- `Home/` — `HomeStore` (Home bundle, medium selection, builds/attaches the SQLite `ProgressOutbox`, drains progress through `apply_progress_mutations_v1`), `HomeContracts`, `HomePersonalSnapshot`; views in `Kuro/Views/Home/` (`HomeView`, `SeriesDetailViews`, `HomeShelfPolicy`, `HomePagePicture`, `HomeCalendarPresentation`)
- `Catalog/` — `CatalogStore` (detail, credits/entities, relations, ladder, links, episodes/chapters; public caches; since 2026-11-03 `CatalogStore+Voices` cast/voice-actor readers over the prepared `anime_cast_v1` / `character_voice_actors_v1` / `staff_voice_roles_v1` with silent fallback, models in `CatalogVoiceModels`)
- `Discovery/` — `DiscoveryStore` (Discover bundle, Browse paging), `RecommendationsReader` ("More like this": `fetchSimilar(kind:id:limit:)` over the prepared `media_similar_v1`, per-account cache, `AccountScopedState`), `DiscoverCards`
- `Search/` — `SearchStore`
- `Collection/` — `CollectionStore` (card pages + feed; no tracking fields)
- `Releases/` — `ReleasesStore` (`user_airing_next`, countdowns; since 2026-11-01 also the release schedule + songs read model: `user_release_schedule_v1` / `media_release_schedule_v1` / `media_themes_v1` with silent fallback to `user_airing_next` while those prepared RPCs are not deployed), `ReleaseModels` (`ReleaseScheduleItem`, `ReleaseBasis` confirmed/announced/estimated, `release_precision`, `ThemeSong`), `ReleaseCopy` (certainty wording EN/DE; never a time unless precision = instant), `ReminderScheduler` (device notifications; since 2026-11-03 also the release notifications: `ReleaseNotificationPlanner` (spec D14: only exact confirmed/announced times notify, at their moment; an announced day or an estimate never; two per title, 48 cap; `ReleaseReminderCopy` EN/DE), `ReminderScheduler+Releases` (per-account preference, default OFF, plus bell-allowed and muted title sets; commit on the F05 chain; retires the legacy `airing-*` reminders once), `ReleasesStore+Notifications` (Profile toggle / detail bell API: the ONLY permission prompts; the bell is a per-title override and never flips the toggle), `ReleaseNotificationRouting` (tap → `kuro://` title journey); automatic scheduling never prompts), `SongPreviewPlayer` (2026-11-03: one Apple 30-second preview at a time, AVPlayer, `.soloAmbient`, stops on background/interruption/account change; `ThemeSong.apple` from the prepared trailing `media_themes_v1` columns)
- `Providers/` — `ProviderAvailabilityStore` (+ `LegalLinks`, + `DetailLinks`: the detail pages' one `ProviderLinkSnapshot` API and the one `validatedOutboundURL`), `ProviderLinkBuilders` (pure link builders)
- `Social/` — `SocialActivityStore`
- `Clubs/` — `ClubsStore` (throws typed `ClubError`), `ClubRealtimeCoordinator`, `ClubsLibrarySink`, `ClubModels`
- `Imports/` (11 files) — `ImportsService` (+`Workflow`, `WorkflowRPC`, `WorkflowSources`, `MALAccount`: import v2 staged review, Stop, guarded Undo, journal checkpoints), `ImportReconciler` (pure reconcile/auto-apply rules), `ImportModels`, `ImportLibraryProjectionModels`, `ImportWorkflowPresentation`, `ProfileImportCoordinator` (AniList / MAL XML / MAL account entry), `MALNativeAccountConnector` (Debug-simulator MAL OAuth, public client, no secret)
- `Concierge/` — `ConciergeStore`, `ConciergeFunctions`, `ConciergeRecommendModels`, `ConciergeRouting` (pure clarification gate, FM/keyword routing, input-field intent/paste rules)
- `Taste/` — `TasteStore` (deck, signals + bounded outbox, profile, personalised NEW TO YOU), `TasteModels`
- `Telemetry/` — `InteractionTelemetry`, `OutboundLinkTelemetry`
- `Widgets/` (2026-11-03) — `WidgetSnapshotWriter` (account-scoped App Group snapshot for the KuroWidgets extension; registered in `makeAccountScopedStates`), `WidgetIntentInbox` (drains the widget's +1 queue through `LibraryActions.advanceQueuedProgress`; the extension never writes tracking data), `WidgetSnapshotBuilder` (pure; `ReleaseCopy` wording). Design + security: `docs/details-songs-2026-11-03/platform/WIDGET.md`
- `Support/` (2026-11-02) — `SupportStore` (the in-app contact form: account-scoped draft, validation, one `contact-submit` call with the signed-in session, no auto-retry; registered in `makeAccountScopedStates` before interaction telemetry)
- `Infrastructure/` — `TimedCache`, `withRetry` (`Retry.swift`), `MemoryPressure.swift`

**Local package (`Packages/KuroModules`, linked into the app):** `KuroCore` (`MediaKind`, `MediaKey`, `AccountContext`, `AccountSessionCoordinator`, `AccountScopedLoads`), `KuroLibrary` (tracking values/contracts + `LibraryStore`, durable SQLite `ProgressOutbox` + `LibraryProgress`, import workflow/journal/batch (file-backed, file-protected), `MALExportParser`, `MALAccountList`, `SeriesGrouping`), `KuroSupabase` (`SupabaseLibraryBackend`, `LibraryRowTransport`, `LibraryFenceTransport` (revision-fenced writes when `series_foundation_v1` is on), `UserIdText`), `KuroWidgetSupport` (2026-11-03: App Group `group.com.Kuro.app` contract shared with the `KuroWidgets` extension: `WidgetSnapshot`, `WidgetSnapshotStore`, `WidgetAdvanceQueue`, `WidgetAccountHash`; Foundation + CryptoKit only). No SwiftUI/UIKit/supabase-swift imports; Swift 5 mode, explicit isolation policy in `Package.swift`.

**Retired (2026-10-05):** `SupabaseService.swift` and its 12 extensions (`+Browse`, `+ClubRealtime`, `+Clubs`, `+Collection`, `+Concierge`, `+Discover`, `+Monetization`, `+Recommendations`, `+Social`, `+Streaming`, `+Taste`, `+UserLists`) — deleted; see the ownership map for where each part went.

**Services (`Kuro/Services/`, 10 files):**
- `AppleFMService.swift` — on-device FM (4 capabilities, FMProvider protocol; falls back by returning `nil` when FM is unavailable, `StubFMProvider` is unused); one instance injected by `AppComposition`
- `AppConfig.swift` — reads SUPABASE_URL/ANON_KEY from Info.plist/env
- `NetworkMonitor.swift` — NWPathMonitor connectivity, `isConnected`, offline banner
- `FeatureFlags.swift` — server-controlled flags, UserDefaults cache, stable hash rollout (one injected instance; no `.shared`)
- `DeepLinkRouter.swift` — `enum DeepLink`, `kuro://` URL parsing
- `ConciergeAnalytics.swift` — concierge + club interaction telemetry
- `TextNormalization.swift` — search/parsing text utilities
- `ImagePipeline.swift` — NSCache (~80MB) + URLCache disk cache, downsampling, request dedup
- `KuroDiskDetailCache.swift` — on-disk detail page cache
- `KuroPerf.swift` — performance measurement utilities

**Concierge UI (9 view files in `Kuro/Views/`; owners in `Kuro/Imports/` + `Kuro/Concierge/`):**
- `ConciergeView.swift` — main concierge view controller
- `ConciergeView+AniListImport.swift` — AniList import UI flow (extracted from ConciergeView)
- `ConciergeAniListImportCoordinator.swift` — AniList import coordination logic
- `ConciergeEditorialShell.swift` — editorial shell wrapper
- `ConciergeComponents.swift` — shared components + curated copy layer (EN/DE mode titles)
- `ConciergeInputField.swift` — text input field
- `ConciergeImportCards.swift` — import preview/confirm cards
- `ConciergeRecommendationRails.swift` — recommendation rail rendering
- `ConciergeResponseStage.swift` — response stage rendering

**Views (remaining):**
- `EditorialDiscoverView.swift` — Discover page (since 2026-11-03 the "daily issue" in Home's grammar; its parts live in `Views/Discover/`, see below)
- `EditorialDiscoverRouting.swift` — Discover page navigation/detail routing
- `BrowseView.swift` — Browse page shell/state (full-page, not a sheet)
- `BrowseComponents.swift` — browse controls, filters sheet, grid, hero card, skeletons
- `EditorialCollectionView.swift` — Collection page shell/state
- `EditorialCollectionComponents.swift` — collection filters, grid/list cards, empty/loading states, batch bar
- `ClubsView.swift` — Clubs list page (since 2026-11-03: Home's opening row, one dark club room per club (`Views/Clubs/ClubRoomCard`), invitation link rows, Home's footer; monochrome unread dot)
- `ClubDetailView.swift` — Club detail shell/state (3-tab: Rails/This Week/Polls)
- `ClubDetailShellComponents.swift` — club detail room hero, labelled key row (`ClubKeyRow`: Add a title / Start a rail / Invite / Ask, visibility from `ClubRoomRules.keys`), Home-switch tabs
- `ClubDetailTabComponents.swift` — club detail tab content (rails, activity, polls)
- `ClubDetailSheets.swift` — club settings sheet, add-item sheet, rail search
- `ClubCreateSheets.swift` — Create/join club sheets
- `EditorialSearchView.swift` — Search sheet
- `OnboardingView.swift` — First-launch onboarding
- `ProfileView.swift` — Profile menu (includes Clubs secondary access)
- `ProfileFreshnessCard.swift` — profile-level provider refresh observability card
- `AuthView.swift` — Authentication
- Detail pages: `AnimeDetailView.swift`, `MangaDetailView.swift` (load table in each file header), `DetailSharedComponents.swift` (shared chrome), `ProviderLinkViews.swift` (provider sheet), `MediaDetailSheet.swift`, `ClubActivitySection.swift`, `FriendsActivitySection.swift`, `ExternalLinksSection.swift`, `CastSection.swift`, `CreditsSection.swift`, `EntityDetailSheets.swift`, `AdaptationPathSection.swift` — see `docs/modules/detail-pages.md`
- Navigation contract foundation (2026-11-02, Rule 5): `Views/Routing/KuroJourney.swift` (`JourneyPage`, `AnyJourneyPage`/`JourneyPageContent` extension point, pure `JourneyPolicy` N5 dedupe, pure `NavigationCollapsePolicy` N10), `JourneyHost.swift` (`JourneyHost`, `JourneyNavigator`, `\.kuroJourney` `JourneyContext`, `.kuroLeavesJourney()`, `KuroJourneyAwareStack`), `KuroJourneyChrome.swift` (`.kuroJourneyChrome(title:collapseProgress:material:)`, `.kuroCollapseTracking`, `KuroCollapse`, `KuroInteractivePopEnabler`), `KuroNavigationCoordinator.swift` (root presenter `.kuroRootNavigation(_:)`, `\.kuroNavigation`, `.kuroNavigationLayer`), `Views/Shared/KuroFold.swift` (`KuroFoldMemory` `\.kuroFoldMemory`, `KuroFoldButton`), `.kuroJourneyRefreshable` (H4: no pull-to-refresh on a journey's first page), `Views/Routing/NavigationFixture.swift` (DEBUG only: `--kuro-nav-fixture` opens a fixture journey for the UI tests); gate `scripts/quality-gates/check_navigation.sh` (BLOCKING since the 2026-11-02 lane integration, 0 offenders). Lane files (integrated 2026-11-02): `Views/DetailPages/Prototype/DetailNavigation.swift` (detail chrome, pushes, `DetailFold`), `Catalog/EntityWorks.swift` (staff page anime + manga works), `Views/ShellJourneys.swift` (`ShellJourneyHost`, Profile/Search/Concierge/See all journeys, `ShellLinkPolicy`), `Views/Shared/KuroDiscardGuard.swift`. Tests: `KuroTests/JourneyPolicyTests.swift`, `NavdetailTests`, `NaventityTests`, `NavclubsTests`, `NavshellTests`, `NavigationEvidenceTests` (renders to `docs/navigation-2026-11-02/`), UI: `KuroUITests/NavigationContractUITests.swift` (offline, fixture host) and `NavshellUITests.swift` (reads live data)
- Routing: `Views/Routing/KuroRoutes.swift` — typed navigation outputs `EnvironmentValues.kuroRoutes` (`openMedia`, `openClub`, `presentTrackingEditor`, `presentAddToClub`), `.routePresenter()` (one route slot per presentation context), pure `RoutePolicy`. Cross-feature detail/editor/club/add-to-club sheets are opened through routes, not constructed by the caller
- Shared cards: `Views/SharedCards/` — `CompactAnimeCard.swift`, `GridAnimeCard.swift`, `AddToClubRailSheet.swift` (connected components, kept in the app by recorded decision)
- UI components: `KuroRefinedCard.swift`, `KuroCardText.swift`, `KuroGlass.swift`, `KuroCachedAsyncImage.swift`, `KuroToast.swift`, `KuroTransientBanner.swift`, `KuroConciergeMark.swift`, `KuroInteractionEnvironment.swift`, `KuroLoadMoreSentinel.swift`, `KuroPagingGesture.swift`, `QuickVerdictActionCard.swift`, `GenreHubView.swift` (unreferenced by grep), `CountdownTimer.swift` (`EditorialCards.swift`, `Cards.swift`, `UIComponents.swift`, `PosterView.swift` and the Concierge `ComposerDock`/`ActionFooter`/`IntentDeck` were deleted as dead code on 2026-10-05)
- Shared components (`Views/Shared/`, 2026-11-01): `KuroMediumSwitch` (heavy sans uppercase, selected word filled with the title's `material:`), `KuroAdvanceKey` (44 pt +1; prototype raised faces `.light` / `.dark` (manga leaf) / `.ink` (dark gradient, keys without artwork, e.g. Folio) / `.material(ArtworkMaterial)`, `confirmTrigger` plays confirm/restore), `KuroMotionEffects.swift` (`.kuroConfirmStamp(trigger:)`, `.kuroRestore(trigger:)`, `.kuroCountRoll(value:pageTurn:)`, `.kuroPressSettle(trigger:)`, `KuroMotionAllowance`, `KuroMotion.playsMotion(reduceMotion:lowPower:)`, `KuroMotion.playsMotionNow(reduceMotion:)` for one-off animation sites), `KuroBrandedStates.swift` (the branded state family: `KuroBrandedState.resolve`, `KuroLoadingView(scope:label:)` (a label shows as a muted caption), `KuroBusyMark` (a working control's short scrub line), `KuroScrubLine(tint:track:)`, `KuroSkeleton(kind:)`, `KuroErrorView`, `KuroOfflineView(hasContent:retry:)`, `KuroEmptyView`, `KuroOutlineButton`; the only file in `Kuro/` allowed to use `ProgressView(`), `KuroReleaseLine`, `KuroStateView` (loading/empty/offline/failed/denied, `hasCachedContent`; a thin wrapper over the branded family), `KuroSectionHeader`, `KuroInkButton`/`KuroPressStyle`, `.kuroReadableWidth()`, `KuroThemeSongRow` (Listen → Apple Music / Spotify search URLs, nothing stored). Use these instead of re-inventing controls; `KuroDiscardGuard.swift` (2026-11-02, N7: `.kuroDiscardGuard(isDirty:isBusy:isConfirming:onDiscard:)` blocks swipe-down on unsaved input and asks "Discard changes?" on Cancel).
- Discover (`Views/Discover/`, 11 files, 2026-11-03 Discover + Clubs redesign, spec `docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md`): `DiscoverIssueSwitch` (All · Anime · Manga, selected word filled with the lead's artwork; the issue choice is owned by `KuroMainView`, so the header canvas follows it), `DiscoverPageHeading` (Home's opening row, stacks via `ViewThatFits`), `DiscoverCoverStory` (lead on the title's `ArtworkMaterial`, `TastePlanKey`), `DiscoverGlanceCard` (Airing today), `DiscoverContents` ("In this issue" + Browse row), `DiscoverFeatureTrio`, `DiscoverIndexRow` (numbered index with leaf Plan keys), `DiscoverRefineRow` (local rail refinement), `DiscoverIssueSkeleton` (loading + offline band), `DiscoverIssueLayout`, `DiscoverIssueCopy` (EN/DE). The fold remembers open/closed per app run via `KuroFoldMemory` (page `discover`, section `more`); `kuro_discover_show_more` is no longer read. **Since 2026-11-04 (usability pass, Rule 6):** the fold is retired (≤ 6 sections, then `DiscoverIssueEnd` "You're caught up for today."); new page parts `DiscoverCardActions` (`discoverMenu(for:)` → lane B's `discoverTitleMenu`, `DiscoverPlanKey` with `stampsOnConfirm`, `DiscoverPageFeedback` tallies + page events, `discoverPageHost` = `discoverFeedbackHost` one toast slot), `DiscoverMoodKeys`, `DiscoverNewMarker` (per-account `DiscoverVisitLedger`), `DiscoverPinnedIndex`, `DiscoverProgressHook`; `Views/Discover/Preview/` (`DiscoverTitleMenu`, `DiscoverTitlePreview`, `DiscoverFeedbackController`, `DiscoverFeedbackToastView`, `DiscoverMenuCopy`), `Views/Discover/SeeAll/` (`DiscoverSeeAllPage` + chips/copy/feed/row), `Views/Discover/Mood/DiscoverMoodPage` (`DiscoverMoodRoute`). Data: `Kuro/Discovery/DiscoveryStore+Usability.swift`, `DiscoverUsabilityModels.swift`, `Kuro/Taste/TasteStore+DiscoverFeedback.swift` (Not interested = `.skip`, Seen it = `.known`). Discover and Clubs paint `kuroCanvasHome` (Manga issue: `kuroCanvasHomeManga`) via `KuroMainView.Section.canvas`.
- Clubs (`Views/Clubs/`, 5 files, 2026-11-03): `ClubRoomLayout` (`ClubPageHeading`, `ClubSubHeading`, `ClubOfflineBand`, `ClubLinkRow`, `ClubMemberFills`), `ClubRoomCard` (list room + `ClubRoomSkeleton`), `ClubWeekCard` (This Week summary), `ClubInviteSheet`, `ClubRailChooserSheet`. Pure rules in `ClubViewLifecycle.swift` (`ClubRoomRules`, `ClubsListCardRules`, now `nonisolated`); one seal via `ClubSeal.ring(compact:)` (36/30, `ClubRoomStyle.swift`). Tests: `KuroTests/DCclubsTests.swift`, `DCdiscoverTests.swift`; fixture renders `ClubsAfterSnapshotTests`, `DiscoverAfterSnapshotTests` → `docs/discover-clubs-2026-11-03/after/` (write only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`).
- Details, songs & platform (2026-11-03, spec `docs/superpowers/specs/2026-11-03-details-songs-platform-design.md`): `Views/DetailPages/Detail/` (hero facts + next row + bell + season tab `DetailHeroParts`, episode timeline `DetailEpisodeTimeline` + `EpisodeStillPolicy` in `DetailPassRules`, cast rail + More like this `DetailRails`, `detailRailBleed` in `DetailRailPeek`), `Views/DetailPages/Songs/` (`DetailSongShelf`: parts by episode span, versions, Apple 30-second previews via the injected `SongPreviewPlayer`, spoiler veil), `Views/Entities/` (character / staff / studio / author pages in Home's grammar: hero, voice card, work rails, refine words), `Views/Profile/` ("Your numbers" `ProfileStats*`, `ProfileYearCard`, `ProfileRemindersRow`), `Views/ImportRestyleComponents.swift` (import screens' shells); shared `Views/Shared/KuroRailPeek.swift` (THE edge-peek card width for every sideways rail outside the exempt pages) and `Views/Shared/KuroBrandedTile.swift` (THE missing-picture tile; no kanji glyphs). Evidence, gallery and integration report: `docs/details-songs-2026-11-03/index.html`.
- Lists (`Views/Lists/`, 2026-11-01): the "Folio" list experience used by Collection in both flag worlds (status word strip, Shelf/Index density, sort words, medium switch, +1 with caught-up guard + Undo via `CollectionStore.advanceFromList`/`undoListAdvance`, batch bar incl. Dropped) and `ProfileListsPreview` (Profile "Your lists").
- About (`Views/About/`, 2026-11-01): `DataSourcesView` (Data sources & credits: AniList, MangaDex, MangaUpdates, AnimeThemes), `KuroLegalLinks` (Terms URL still nil until the owner confirms it; `kuro.app` did not resolve on 2026-11-02), `ContactSheet` (2026-11-02: Profile → About → Contact us, over `SupportStore`).
- Shared: `AddToListSheet.swift` — editorial "spread" list sheet (full-bleed poster hero, capsule status pills, serif score + dots, pull-quote notes, pinned save dock); its save rule is `TrackingDraft.swift` (the one `LibraryEdit` a save sends)
- Shared: `LibraryViewActions.swift` — typed-key adapters from views to `LibraryActions` (views never write `LibraryStore` directly); `ClubViewLifecycle.swift` — pure club-view lifecycle rule
- Legacy/secondary: `DiscoverViewModel.swift`

**Design (6 files):**
- `ArtworkMaterial.swift` — `KuroRGB` + `ArtworkMaterial` (on-device port of the prototype's `art-hue-v1`; `derive(from:banner:)`, `fromHex(_:)`, white text ≥ 7:1, neutral base #3a3d3c)
- `ArtworkMaterialStore.swift` — `@MainActor @Observable` store: seed colour first, derived material published later; memory + disk cache by image URL; built by `AppComposition`, read with `@Environment(ArtworkMaterialStore.self)`
- `KuroDesignSystem.swift` — colors (neutral roles since 2026-11-01: `kuroCanvasPage` #FFFFFF, `kuroCanvasQuiet` #F6F6F6, `kuroInk` #252625 (prototype ink), prototype tokens `kuroCanvasHome`/`kuroPaper`/`kuroMuted`/`kuroLine`/`kuroKeyLight*`/`kuroKeyDark*`, `kuroInkSecondary` #5C5C5C, `kuroInkQuiet` #6B6B6B, `kuroHairline`, `kuroRoom` #222222; legacy names alias these), Dynamic-Type-reactive typography (`KuroTypeScale`; display roles in the prototype's sans with `KuroTypeRole.tracking`/`.kuroTracking(_:)`, serif `kuroEditorial(size:)`, `kuroMediumWord()`; roles `kuroTitleName`/`kuroMeta`/`kuroButtonLabel`), spacing, radii, animations (`KuroMotion.contact/settle/medium` on the prototype ease)
- `KuroLocale.swift` — the one EN/DE switch (`KuroLocale.isGerman`, `KuroLocale.text(en, de)`); every user-facing string goes through it
- `Color+Hex.swift` — hex color utility
- `FlowLayout.swift` — wrapping layout primitive (detail pages, Browse, Profile, AddToList, Credits)

**Models (1 file):**
- `DiscoverBundle.swift` — discover bundle response model (`SupabaseModels.swift` was deleted; models now live with their owning capability folder)

### Supabase — 250 migration files in `supabase/migrations/`, 25 prepared files (+1 opt-in) in `supabase/prepared-migrations/` (5 of them are the unapplied 20261101* overnight files), 16 edge function directories (deployed list below as of 2026-07-31; `realm-describe` is deployed and dormant)

**Migration history caveat (2026-10-08, do NOT "repair"):** live history has 249 identities = the 245 local + 4 applied from `prepared-migrations/` in one approved transaction (`20261007040000_series_home_foundation_v1`, `20261007130000_series_account_lifecycle`, `20261008100000_import_status_fence_preserves_units`, `20261008110000_import_review_recovery_v2`). The nine `20261005*` prepared files are byte-identical copies of applied migrations. `20261007120000_feature_flag_overrides` was applied and recorded on 2026-11-02 (owner request: new Home for the owner account); the `opt-in/` backfill is intentionally NOT applied. Never `supabase db push --include-all` or run history repair without an explicit new approval.

**Go-live deployment (2026-11-02, owner-authorized; records in `docs/go-live/2026-11-02/`):** prepared migrations `20261101000000`, `20261101010000`, `20261101010100`, `20261101020000` and `20261102100000_contact_messages` applied and recorded in history (`20261101030000_auth_hardening` is NOT applied: only after the new app build is released). Functions: `bulk-import-anime` v84 / `bulk-import-manga` v83 (AniList 5,000-entry page-depth stop, character age / authors column fixes), `release-intake` (linked-first manga candidates), `manga-chapter-enrich` v67, `auth-callback` (`--no-verify-jwt`), `contact-submit` (`--no-verify-jwt`, secret-keyed rate-limit buckets). `IMPORT_SECRET` rotated; `CONTACT_IP_HASH_SECRET` and `MU_OFFICIAL_GROUP_IDS` set. There is no `supabase/config.toml`: `--no-verify-jwt` must be passed on every deploy of `auth-callback` and `contact-submit`. Client IP in Edge Functions: XFF[0] / `cf-connecting-ip` are set by the platform and not spoofable (live probe); never use the rightmost XFF entry.

**Edge deployment (2026-10-08):** `concierge-apply` v27, `concierge-undo` v18, `delete-account` v10, `concierge-recommend` v50, `concierge-retrieve-assist` v9, `concierge-import-anilist` v6. The other functions' local handler/module refactors are NOT deployed — do not deploy them opportunistically.

Since 2026-10-05: `concierge-apply`, `concierge-undo` and `delete-account` are split into handler/plan modules with offline `deno test` suites, and `concierge-recommend/router.ts` + `concierge-parse/rules.ts` hold the production rules the corpus gates execute (`docs/modules/edge-functions.md`). Their changes are prepared, NOT deployed (see the execution ledger). `supabase/tests/` holds the disposable local-PostgreSQL authorization tests.

**Edge functions (15):**
- `concierge-parse` — deterministic NLP parser, title candidate search
- `concierge-recommend` — deterministic recommendations + optional Groq narration (~1800 lines)
- `concierge-apply` — apply parsed items to user lists
- `concierge-resolve` — LLM disambiguation for ambiguous titles
- `concierge-undo` — rollback last import session
- `concierge-retrieve-assist` — RAG retrieval assist
- `concierge-retrieve-feedback` — RAG feedback collection
- `concierge-import-anilist` — AniList import helper
- `bulk-import-anime` — bulk anime catalog import (requires IMPORT_SECRET)
- `bulk-import-manga` — bulk manga catalog import (requires IMPORT_SECRET)
- `mirror-images` — mirror external images to Storage CDN
- `manga-chapter-enrich` — MangaDex chapter enrichment + mapping/match pipeline
- `manga-source-review-action` — approve/reject unresolved mappings and optionally trigger re-enrich
- `delete-account` — GDPR account deletion
- `auth-callback` — email verification fallback redirect page (verify_jwt: false)
- `contact-submit` (LIVE since 2026-11-02; e-mail alert waits for the owner's Resend key) — contact form of the legal site (`web/legal/kontakt.html`) and the app's Contact sheet; deploy with `--no-verify-jwt`; user id only from a verified user JWT; limiter kind `contact` 5/h per HMAC-hashed IP and per user; service-role insert into `contact_messages` (prepared migration `20261102100000`); optional Resend notification

**Database tables (key groups):**
- Catalog: `anime`, `manga`, `episodes`, `chapters`, `volumes`, `characters`, `staff`, `studios`, `authors`, `tags`, `genres`, `external_links` + join tables
- User: `profiles`, `anime_user_lists`, `manga_user_lists`, `import_sessions`, `import_session_items`
- Concierge: `concierge_runs`, `concierge_config`, `rate_limit_buckets`, `llm_daily_usage`, `system_flags`
- Clubs (9 tables): `clubs`, `club_members`, `club_rails`, `club_rail_items`, `club_rail_item_reactions`, `club_polls`, `club_poll_options`, `club_votes`, `club_messages`, `club_analytics`
- Social activity (2 tables): `title_comments`, `title_comment_reactions`
- Ops: `mirror_runs`, `import_state`, `feature_flags`

**Cron jobs (pg_cron):**
- Hourly: bulk-import-anime, bulk-import-manga (with IMPORT_SECRET header); release-intake airing (job 116, :25)
- Daily: release-intake manga (job 117, 03:50, limit 40), contact-messages-retention (job 119, 04:50, 12-month purge); weekly similar-titles re-stale (job 115)
- Removed 2026-11-02: job 118 `kuro-import-cursor-depth-guard` (superseded by the importer's page-depth stop)
- Daily: mirror-images (per-batch locks, 200 batch, 15-min spacing, IMPORT_SECRET auth), matview refresh, concierge housekeeping, cron history cleanup (14-day retention)
- Unscheduled (deprecated): club message pruning (was 30-day, at 03:15 — chat replaced by social activity layer)

### Scripts & quality gates
- `scripts/quality-gates/` — gate scripts (`check_secrets.sh`, `check_migrations.sh`, `test_concierge_corpora.sh`, `test_router_offline.sh`, `test_edge_functions.sh`, `check_live_services.sh`, `audit_rails.sh`, `check_docs_current_state.sh`, `test_packages.sh`, `check_architecture.sh`, `check_branded_states.sh` (2026-11-01: no stray `ProgressView(` anywhere in `Kuro/` outside `KuroBrandedStates.swift`; blocking since prototype-fidelity Task 10, 0 offenders), `build_ios.sh`, `test_ios_unit.sh`, `check_navigation.sh` (navigation contract; blocking since 2026-11-02, 0 offenders)); a gate registered with blocking flag `0` in `run_all.sh` is recorded as WARN, never FAIL; `run_all.sh` orchestrator, `router_test_cases.js` offline router test data, and `check_docs_current_state.py` docs-current-state checker (package-aware: also counts `Packages/` Swift files). The corpus/router gates now run the production `rules.ts`/`router.ts` with `deno`.
- `scripts/db/` — disposable local database test harness (`run_local_db_tests.sh`, `guard_env.sh`, `test_guard_env.sh`, `replay_migrations.sh`); refuses production and non-local targets; not part of `run_all.sh`
- `.githooks/pre-commit` — secrets + migration name checks
- `scripts/` — 19+ operational scripts (imports, audits, load tests, generators), including `audit_curated_rails_quality.js` (rail quality checks)

### Config, CI & Root Files
- `fastlane/Appfile` + `fastlane/Fastfile` — TestFlight automation (`fastlane beta`)
- `Config/Shared.xcconfig`, `Config/Debug.xcconfig`, `Config/Release.xcconfig` — build settings
- `Kuro/Kuro.entitlements` — `com.apple.developer.applesignin` + `applinks:kuro.app` (Associated Domains placeholder) + App Group `group.com.Kuro.app` (2026-11-03, shared with `KuroWidgets/KuroWidgets.entitlements`; widget extension `com.Kuro.app.widgets`, embedded via "Embed Foundation Extensions")
- `Info.plist` (project root, NOT `Kuro/Info.plist`) — `CFBundleURLTypes` registering `kuro://` URL scheme. `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Info.plist` in both Debug+Release configs (lines 447-448, 495-496 of project.pbxproj). Xcode merges generated keys with custom ones.
- `.mcp.json` (project root) — MCP server config: Supabase (HTTP, project ref `bkdifromsqxkndnllmdj`) + Resend (`@resend/mcp` via npx, API key in env)
- `emails/` — 5 branded HTML email templates (Cormorant serif wordmark, warm gray `#f5f5f0` background, black CTA buttons, MSO-compatible table layout):
  - `confirm.html` — signup email verification
  - `reset-password.html` — password reset
  - `magic-link.html` — passwordless login
  - `change-email.html` — email address change
  - `invite.html` — team/club invitation

---

## DESIGN SYSTEM (exact tokens — use these, never hardcode)

### Colors (monochrome only)
- Primary text: `Color.kuroBlack80` (black @ 0.8)
- Secondary text: `Color.kuroTextSecondary` (black @ 0.55) — WCAG AA compliant
- Tertiary text: `Color.kuroTextTertiary` (black @ 0.45)
- Subtle backgrounds: `Color.kuroBlack08` (black @ 0.08)
- Status pill text: `black.opacity(0.55)` — pill background: `black.opacity(0.06)`
- **NO colored status pills/dots anywhere.** Red ONLY for destructive actions (leave/delete).
- Prototype palette (2026-11-01, owner-approved): `kuroInk` #252625, `kuroCanvasHome` #fffef8 (Home/Taste), `kuroPaper` #f5f5f4 (detail), `kuroMuted` #696c6b, `kuroLine`, key faces `kuroKeyLightTop/Bottom`, `kuroKeyDarkTop/Bottom`; per-title tint only via `ArtworkMaterial` / `@Environment(ArtworkMaterialStore.self)` (never a per-title colour table). Statuses stay monochrome.

### Typography (since 2026-11-01: the prototype's sans for display roles; serif only for editorial headings)
- `.kuroHero()` — 64pt sans heavy, dramatic statements
- `.kuroDisplay()` — 44pt sans semibold, large section headers
- `.kuroFeature()` — 34pt sans semibold, feature titles
- `.kuroHeadline()` — 26pt sans semibold, card titles
- `.kuroTitle()` — 19pt sans semibold, secondary titles
- Tight tracking is opt-in: `.kuroTracking(.headline)` etc. (`KuroTypeRole.tracking`; a `Font` cannot carry it)
- `.kuroEditorial(size:)` — system serif, only for the prototype's editorial headings (club name/quote, "Between us.", manga detail title/hook, "Your bookmark", manga row numbers, "Seen the anime?")
- `.kuroMediumWord()` + `.kuroMediumWordStyle()` — the ANIME / MANGA switch words (heavy, uppercase, tracked)
- `.kuroBody()` — 15pt sans-serif, descriptions
- `.kuroCaption()` — 11pt sans-serif, small labels
- `.kuroMicro()` — 9pt sans-serif, tiny metadata

### Spacing (8px base unit)
- `KuroDesignSpacing.xs` = 4pt, `.sm` = 8pt, `.md` = 16pt, `.lg` = 24pt

### Radii
- `KuroRadius.xs` = 4pt, `.sm` = 8pt, `.md` = 12pt, `.lg` = 16pt

### Card sizing (adaptive, never hardcoded)
- Width formula: `floor((screenWidth - 56) / 2.8)` clamped to [112, 144]
- Always pass explicit `containerWidth` — no defaults, no hardcoded 393pt
- Poster corners: 8-12pt depending on card type

### App appearance
- **Light mode only** — `.preferredColorScheme(.light)` is set in KuroApp.swift
- Dark mode tokens are prepared but not active

---

## BACKEND DETAILS (exact)

### Supabase project
- **URL**: `https://bkdifromsqxkndnllmdj.supabase.co`
- **Project ref**: `bkdifromsqxkndnllmdj`

### Auth & RLS
- Supabase Auth (email/password with branded templates, Apple Sign In)
- Email verification: `redirectTo` → `kuro://auth/callback` (direct app redirect, no intermediate page)
- 5 branded templates in `emails/` — must be pasted into Supabase Dashboard
- Custom SMTP required for production (Resend configured in `.mcp.json`)
- RLS enabled on ALL tables — user tables scoped to `auth.uid()`
- Edge functions derive user ID from JWT — NEVER accept raw user_id from client
- Club RLS: 30+ policies, 4 SECURITY DEFINER helpers (`is_club_member`, `is_club_admin_or_owner`, `is_club_owner`, `sharing_level_rank`)
- Storage RLS: read public, write/delete authenticated, service_role full access

### User ID type mismatch (known tech debt)
- Club tables: UUID
- Legacy tables (`anime_user_lists`, `manga_user_lists`): TEXT
- JOINs require `::text` cast

### Edge function environment variables
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
- `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_MODEL_RESOLVE`
- `IMPORT_SECRET` — shared secret for bulk-import auth (pg_cron can't send JWTs)

---

## BUILD & DEPLOY COMMANDS (exact)

```bash
# iOS build (simulator — use this simulator name exactly)
xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# iOS build (CI / generic — for when simulator name might not exist)
xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build

# TestFlight upload (auto-increments build number, archives, uploads)
fastlane beta

# Push migrations to production
supabase db push --linked --include-all

# Deploy an edge function
supabase functions deploy <function-name> --project-ref bkdifromsqxkndnllmdj

# List deployed edge functions
supabase functions list --project-ref bkdifromsqxkndnllmdj

# Run quality gates (10 gates; SKIP_RAILS_AUDIT=1 skips the live-project rails audit)
scripts/quality-gates/run_all.sh

# App unit tests (simulator)
xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:KuroTests

# Local package tests (macOS host, no simulator/network) — also run by the swift-packages gate
cd Packages/KuroModules && swift test

# Architecture boundaries (retired SupabaseService, FeatureFlags.shared, SDK imports in views, tracking writers)
scripts/quality-gates/check_architecture.sh

# Local database authorization tests (throwaway PostgreSQL 17; refuses production/non-local targets; NOT a migration replay)
scripts/db/run_local_db_tests.sh                 # --exclude-pending = deployed-chain state; --only <name>

# Edge function rule/handler tests (offline, per function directory)
deno test --no-prompt supabase/functions/concierge-apply/   # also concierge-undo, delete-account, concierge-recommend, concierge-parse

# Check migration checksums (read-only by default)
scripts/quality-gates/check_migrations.sh
# To update checksums: scripts/quality-gates/check_migrations.sh --update
```

### TestFlight / App Store Connect
- **Bundle ID**: `com.Kuro.app` (capital K — must match exactly)
- **App Store Connect App ID**: 6759221230
- **Team ID**: YLG68JL5Y7
- **API Key**: Key ID `4Y9VLAQLQN` (since 2026-11-02; the old `7L84A7P9X7` file is not on this Mac; `fastlane/Fastfile` reads `KURO_ASC_KEY_ID`, default `4Y9VLAQLQN`), Issuer ID `bca97a4b-8a3a-4051-9c89-510f10db0b06`
- **API Key file**: `~/.appstoreconnect/private_keys/AuthKey_4Y9VLAQLQN.p8`
- **Latest TestFlight build**: 25 (2026-11-04; Discover usability: moods, long-press preview, Not interested / Seen it, See all page, pinned index, end state, new-since markers, Essentials progress; widget still EXCLUDED until the owner registers the App Group `group.com.Kuro.app` with an Apple ID — API-key signing cannot create App Groups). Tags `testflight-24`/`-25` point at the shipped widget-less variants. Next is 26.
- **Signing**: Automatic, `-allowProvisioningUpdates`

---

## ABSOLUTE DO-NOTs (violations will break things)

1. **Do NOT create `Kuro/Info.plist`** — that causes duplicate resource errors. `Info.plist` lives at the **project root** (not inside `Kuro/`). `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Info.plist` — Xcode merges generated keys with custom ones. Simple keys still go via `INFOPLIST_KEY_` build settings.
2. **Do NOT add Foundation Models entitlement** to `Kuro.entitlements` — FM works without it. The "Adapter Entitlement" in Developer Portal is only for custom LoRA fine-tunes.
3. **Do NOT use colored status indicators** — monochrome palette only. No colored dots, pills, or badges.
4. **Do NOT use `UIScreen.main`** — deprecated. Use `displayScale` / window scene APIs.
5. **Do NOT hardcode card widths** (e.g., 393pt) — always pass screen/geometry width.
6. **Do NOT use Combine** — no `ObservableObject`, `@Published`, `sink`, `assign`. Use `@Observable`.
7. **Do NOT use `supabase db execute`** — it doesn't exist. Use `inspect db table-stats --linked`.
8. **Do NOT run `supabase db dump --linked`** — requires Docker which isn't available.
9. **Do NOT use `iPhone 16 Pro` simulator** — those simulators don't exist. Use `iPhone 17 Pro`.
10. **Do NOT create tables without RLS policies** — every new table must have Row Level Security.
11. **Do NOT create SQL functions without `SET search_path = public, extensions`**.
12. **Do NOT accept raw `user_id` from client in edge functions** — always derive from JWT.
13. **Do NOT skip updating the 3 MD files** after changes (Rule 1).
14. **Do NOT skip updating MEMORY.md** after changes (Rule 2).
15. **Do NOT leave `print()` statements without `#if DEBUG` wrapping**.
16. **Do NOT add features, refactor code, or make "improvements" beyond what was asked.**
    *(Recorded exception, 2026-10-05: the modular-architecture migration was explicitly authorized by its execution brief; see the note under Rule 4. This rule applies unchanged to all other work.)*

---

## PATTERNS TO FOLLOW (exact)

### When adding a new Supabase table:
1. Create migration in `supabase/migrations/`
2. Enable RLS: `ALTER TABLE public.new_table ENABLE ROW LEVEL SECURITY;`
3. Add appropriate policies (scoped to `auth.uid()`)
4. All helper functions: `SET search_path = public, extensions`
5. Push: `supabase db push --linked --include-all`
6. Run: `get_advisors(security)` to verify
7. Update the 3 MD files + MEMORY.md

### When adding a new Swift file:
1. Follow existing file naming conventions
2. Use `KuroDesignSystem` tokens for all UI
3. Use `@Observable` (never Combine)
4. Wrap all `print()` in `#if DEBUG`
5. For background tasks: use `@State` task refs + `.onDisappear` cancellation
6. Update the 3 MD files + MEMORY.md (including file inventory + counts)
7. Put data access in the owning capability (`Kuro/<Capability>/`), never in a view; views read owners via `@Environment(Type.self)` and import no Supabase SDK module. Take the Supabase client by initializer from `AppComposition` (never create a second client). Account-scoped state: conform to `AccountScopedState`, capture the `AccountContext` at the start of every async operation and check `isCurrent` before every private write, and register the owner in `AppComposition.makeAccountScopedStates`. Open another feature's detail, tracking editor, club or add-to-club sheet through `@Environment(\.kuroRoutes)` instead of constructing it; a new sheet whose content contains routed cards must install its own `.routePresenter()` (see the header of `Kuro/Views/Routing/KuroRoutes.swift`). New capability or removal: follow `docs/modules/README.md` ("Add a capability" / "Remove a capability"), then run `scripts/quality-gates/check_architecture.sh`.

### When adding a new edge function:
1. Create in `supabase/functions/<name>/index.ts`
2. Derive user ID from JWT, never from request body
3. Sanitize user text with `sanitizeForLLM()` before any LLM prompt
4. Add rate limiting where appropriate
5. Deploy: `supabase functions deploy <name> --project-ref bkdifromsqxkndnllmdj`
6. Update the 3 MD files + MEMORY.md

### Structured RPC error handling (club RPCs):
- `add_club_rail_item()` uses `RAISE EXCEPTION ... DETAIL = 'ERROR_CODE'` for machine-readable errors
- Error codes: `UNAUTHENTICATED`, `INVALID_MEDIA_TYPE`, `RAIL_NOT_FOUND`, `NOT_A_MEMBER`, `RAIL_LOCKED`, `MEDIA_NOT_FOUND`, `NOTE_TOO_LONG`, `DUPLICATE_ITEM`
- iOS classifies every club error through `ClubError(_:)` (`Kuro/Clubs/ClubsStore.swift`): the code is looked up in `PostgrestError` detail → hint → message, then SQLSTATE (`42501` → `permissionDenied`, `23505` → `uniqueViolation`); views branch on the typed `ClubError` (not free-form string matching)
- **Verified caveat (2026-10-05, open):** supabase-swift 2.54.1 decodes the PostgREST error field `detail`, but PostgREST sends `details`, so codes raised ONLY in SQL DETAIL never reach the app (this pre-dates the migration; since `20260216193000` the DETAIL-based pattern has never worked). Only `add_club_rail_item` relies on DETAIL; its failures currently fall back to SQLSTATE or `.other`. Every other club RPC puts the code in the MESSAGE, which works. No security impact (the server still rejects). Owner-decided fix pending: put the code in HINT or MESSAGE server-side, or upgrade/patch the SDK.
- When adding new SECURITY DEFINER RPCs, emit structured error codes, but until the caveat above is fixed put the code where the app can read it (the MESSAGE, e.g. `RAISE EXCEPTION 'CODE: text'`, or HINT) rather than relying on DETAIL alone

### Retry logic:
- Use `withRetry(...)` (`Kuro/Infrastructure/Retry.swift`, neutral free function; was `SupabaseService.withRetry()` until 2026-10-05) — exponential backoff (500ms, 1s), only retries `URLError`, not HTTP 4xx

### Accessibility:
- Section headers: `.accessibilityAddTraits(.isHeader)`
- Interactive elements: `.accessibilityLabel` with descriptive text
- Message bubbles: prefix with "You said: ..." / "Concierge: ..."

---

## REFERENCE: Where to find full details

| Need | File |
|------|------|
| Complete technical state (14K+ lines) | `CURRENT_APP_STATE.md` |
| Plain English overview | `CURRENT_APP_STATE_PLAIN.md` |
| Implementation status tracker | `IMPLEMENTATION_PLAN_Variation1.md` |
| Session memory / gotchas | `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md` |
| Clubs product spec | `docs/clubs-spec.md` |
| Production blockers audit | `docs/production-blockers.md` |
| Apple FM migration report | `docs/apple-fm-migration-report.md` |
| Unified local ops dashboard | `scripts/unified_local_dashboard_server.js` |
| Where each capability lives + add/remove-a-capability guide | `docs/modules/README.md` |
| Modular architecture: gate status, rulings, test results, prepared-not-deployed, blockers | `docs/plans/2026-10-05-modular-architecture-execution-ledger.md` |
| Modular architecture: contracts / final owner map | `docs/plans/2026-10-05-modular-architecture-contracts.md`, `docs/plans/2026-10-05-modular-architecture-ownership-map.md` |
| Edge functions / ops scripts / SQL function index | `docs/modules/edge-functions.md`, `docs/modules/operations.md`, `docs/modules/sql-function-index.md` |
| Local DB test harness (audited-schema fixture, not a replay) | `supabase/tests/README.md` |
| Doc roles (keep/trim/archive) | `docs/documentation-surface-map.md` |

## CURRENT BEHAVIOR NOTE (2026-03-06)

- Concierge is intentionally **session-local**. Do not describe it as cross-session persistent unless a future change reintroduces full, honest persistence.
- Adaptation Ladder v2 is live on project `bkdifromsqxkndnllmdj`. Use `get_media_ladder(...)` as the source of truth for editorial ladder data; do not guess adaptation/source paths from titles. Ladder coverage refreshes now flow through `enqueue_media_relation_refresh(...)` and the local `com.kuro.media-relations` worker/launchd pipeline.
- Local operational status now has a unified view at `http://127.0.0.1:8791` via `scripts/unified_local_dashboard_server.js`; it aggregates launchd/process/report state for the existing worker families instead of introducing a parallel status store.
- The unified dashboard exposes direct read-only drilldowns per service (`/service/:key/status`, `/service/:key/run`, `/service/:key/log`) plus a dedicated media-relations coverage panel and `/service/media_relations/coverage` report route.

~~~~

## Original `.claude/rules/agent-routing.md`

SHA-256: `61cab123bc836b5a701859b3b1dc90235a228d64ca8f6f15ccc4f65cd67dba06`

~~~~markdown
# Agent and model routing (Claude Code)

Default to doing the work in the main session. Spawn a subagent only when it buys parallel time or keeps bulky output out of context. Research basis: Google/DeepMind/MIT "Towards a Science of Scaling Agent Systems" (arXiv 2512.08296 v3): multi-agent setups lose 39–70% on sequential tasks, help decomposable ones (+81%), and cost far more per success. Anthropic's multi-agent research system uses ~15× the tokens of chat and notes that coding has fewer parallel parts than research.

| Work | Who | Model |
| --- | --- | --- |
| Planning, architecture, specs, ambiguous requests | main session | Opus |
| Migrations, RLS, auth, security, live data, deploys | main session (never delegated) | Opus |
| "Where is X / who calls Y" searches | `Explore` | Haiku |
| Builds, tests, gates with long output | `kuro-runner` | Haiku |
| Implementing a written plan, file list known | `kuro-implementer` | Sonnet |
| Independent review before "done" | `kuro-reviewer` | Opus |

Rules:
1. **Sequential work stays in one agent.** One feature touching linked files is sequential. Fan out only over truly independent parts: separate files, no shared state, no ordering.
2. **Fan-out size follows the task.** A lookup needs no subagent. Comparing 2–4 independent things needs 2–4 agents. Reserve more than 4 for broad research.
3. **The main session coordinates and checks.** Workers report to it; it verifies their claims before building on them. Centralized checking contains errors (4.4× amplification vs 17.2× for independent agents).
4. **Escalate, don't guess.** If a Sonnet or Haiku agent reports ambiguity or a conflict with the code, the main session decides. Workers do not improvise scope.
5. **Review is mandatory for non-trivial changes and must be independent.** Give `kuro-reviewer` the diff, not your conclusion. Trivial changes (docs, one-line fixes) need verification output, not a reviewer.
6. **Keep worker toolsets small.** Read-only agents get no Edit/Write.

~~~~

## Original `.claude/rules/backend-data.md`

SHA-256: `5151c4b4c65ca536d647a74a5f55cd25480c28a87f9ff1b58cde90863dfbd96a`

~~~~markdown
---
paths:
  - "supabase/**"
  - "scripts/**"
---

# Backend data rules: concurrency, latency, table hygiene

These add to the CLAUDE.md DO-NOTs (RLS on every table, `SET search_path = public, extensions`, user id from the JWT only). The capacity facts are in `system-facts.md`.

## Migrations
- Applied migrations are immutable. A fix is a new migration.
- New SQL starts in `supabase/prepared-migrations/` with a DB test in `supabase/tests/`. Applying it to production needs explicit owner approval for that exact file.
- **Never run `supabase db push --include-all` or migration history repair.** The live history includes four files applied from `prepared-migrations/` (see the CLAUDE.md migration caveat). CLAUDE.md's command list still shows `--include-all`; that line is superseded by the caveat.
- Changing a `RETURNS TABLE` signature needs `DROP` + `CREATE`. New function bodies use plpgsql (sql bodies fail the local fixture).

## Concurrency and race conditions
- Every write a client can repeat (double tap, retry, offline replay) is idempotent: upsert on a natural key, or a client mutation id or revision fence. Progress writes go through `apply_progress_mutations_v1` with revision fencing; follow that pattern.
- Queue and batch workers claim rows with `FOR UPDATE SKIP LOCKED`, bounded batch sizes, and a lock or lease that expires. Never let two cron runs process the same row.
- Counters and aggregates are updated in one statement (`set n = n + 1`) or recomputed. Never read-modify-write across round trips.
- Overlapping callers of a rate-limited provider share one budget. AniList limits add up across parallel functions; MangaUpdates allows 1 request per 1.1 s.
- Keep transactions short: the API pool is 3 connections. Never hold a transaction open across an HTTP call to a provider.

## Latency
- One request per screen section. Batch by id list (`= any($1)`), never one RPC per item.
- Every new filter, join or sort column on a user-facing path has an index, plus `EXPLAIN (ANALYZE, BUFFERS)` evidence at realistic size (a 2,000-title library and the full catalogue) before it is called done.
- Prefer parameter-bound plans and keyset (cursor) paging over `OFFSET`.
- Edge functions: no sequential awaits that could run in parallel; no provider call on the request path when a cached or table value exists.

## Table hygiene
- Every table that grows per event or per request has a retention rule (a pg_cron purge or partition drop), stated in the migration that creates it. Example: `contact-messages-retention`, 12 months.
- Every table has a primary key, `created_at`, explicit foreign keys with a deliberate `ON DELETE`, and is covered by account deletion (`delete-account`) if it holds user data.
- User-id columns on new tables are `uuid`. The legacy `text` columns in `anime_user_lists` / `manga_user_lists` are known debt; do not copy them.
- Load-test or fixture rows are removed and the removal is independently verified. Never leave test identities in production.

~~~~

## Original `.claude/rules/client-latency.md`

SHA-256: `fa74b53e78bee4ce42a21025f6f0e269d6ba0a562ef8fb088a3ce6385f54694c`

~~~~markdown
---
paths:
  - "Kuro/**"
  - "Packages/**"
  - "KuroWidgets/**"
  - "KuroWidgetViews/**"
---

# Client rules: latency, concurrency, account safety

Budgets and capacity are in `system-facts.md`.

- **Round trips.** A screen loads with one request per section (bundle RPCs such as the Home or Discover bundle). Never loop network calls per card. Batch prefetches (e.g. friend counts) take an id list.
- **Cache first.** Show cached or stored content immediately, then refresh (`TimedCache`, `KuroDiskDetailCache`, `ArtworkMaterialStore`). Never blank a populated screen while it refreshes.
- **Cancellation.** Every view-started task is cancellable (`.task`, or a stored task cancelled in `.onDisappear`). A stale response must never overwrite a newer one: check the request token or `AccountContext.isCurrent` before writing state.
- **Account switches.** Capture `AccountContext` at the start of each async operation and check `isCurrent` before every private write. New account-scoped owners conform to `AccountScopedState` and are registered in `AppComposition.makeAccountScopedStates`.
- **Writes.** Tracking writes go only through `LibraryActions`. Progress goes through the durable `ProgressOutbox`, so rapid +1 taps coalesce and survive offline. Never fire one request per tap.
- **Retries.** Use `withRetry` (retries only `URLError`, backoff 500 ms then 1 s). Never retry 4xx, and never retry a non-idempotent write without a mutation id.
- **Main actor.** No decoding, image work or sorting of large lists on the main actor in a hot path. `ImagePipeline` already downsamples and dedups requests; use it.

~~~~

## Original `.claude/rules/system-facts.md`

SHA-256: `f6b6fb170b70847677ee6114af10985ae0b7b28c0f4bc21c935594c1b5eef4f4`

~~~~markdown
# System facts — read before any design, query or performance decision

Facts verified 2026-11-09 against code and `docs/backend-load-2026-11-09/`. When a fact here changes, update this file in the same change.

## Stack
- iOS 17+ SwiftUI app, `@Observable` owners per capability, one Supabase client (`Kuro/Composition/AppComposition.swift`). Light mode, portrait iPhone.
- Supabase project `bkdifromsqxkndnllmdj`, region Frankfurt, **Micro compute**, PostgREST **API pool cap 3** (lowered from 6 on 2026-11-09), max 60 DB connections. PostgreSQL + RLS + RPC + Deno Edge Functions + pg_cron.
- On-device AI: Apple Foundation Models (iOS 26+, returns `nil` when unavailable). Server AI: Groq, narration only and optional.

## Who it is for and load
- Anime/manga fans tracking lists, browsing editorial picks, small private clubs (2–20 members). Pre-launch: TestFlight only; real concurrent-user count is not measured.
- **Design target: 100 simultaneously active users** (owner choice), modelled as one request per user every 5 s = 20 rps sustained, 40 rps bursts. Qualification on the current tier is **in progress, not signed off**. Do not design for more than this tier can carry without saying so; a changed workload or tier needs a new measured qualification.
- Catalogue ≈ 21.7k anime / 41.7k manga. Libraries range 0 → 2,000+ titles per user; design for the 2,000-title user.

## Latency budgets (p95, end-to-end from client, errors included)
| Surface | p95 limit |
| --- | ---: |
| Browse, Search, Clubs, Progress write | 750 ms |
| Home, Detail | 1,200 ms |
| Discover, Moods | 1,500 ms |
| Edge Parse / Recommend | 2,500 ms |

Known open gap: **first (cold) calls** have exceeded these (Search 835 ms, Discover 1,693–1,758 ms, Recommend 3,262 ms) while steady state passes. Any change on these paths must not add to cold cost.

Small per-call costs multiply: the app makes thousands of these calls. A change that adds 20 ms or one extra round trip per item is a regression even if one call still passes. State the latency cost of any hot-path change against the table above.

## Intake sources (where data comes from)
| Data | Source | Path | Fallback today |
| --- | --- | --- | --- |
| Anime + manga catalogue, characters, staff, relations | AniList GraphQL | `bulk-import-anime` / `bulk-import-manga` (hourly cron), `_shared/anilist_client.ts` | **None** — AniList is a single source. Client shows cached data. AniList's degraded limit is 30 req/min; parallel callers add up, and 429 pauses the whole limiter. |
| Airing schedule / next episode | AniList `airingSchedules` | `release-intake` airing mode (cron job 116, hourly :25) | Client falls back to `user_airing_next` |
| Manga chapters | MangaDex | `manga-chapter-enrich` | None; unresolved mappings go to manual review (`manga-source-review-action`) |
| Manga volumes / official release dates | MangaUpdates (reached via MangaDex `links.mu`, 1 req / 1.1 s) | `release-intake` manga mode (cron job 117, daily) | None; this depends on MangaDex mapping, so it is not a backup for MangaDex |
| Theme songs | AnimeThemes; Apple iTunes for 30 s previews | nightly song job, `scripts/series_enrichment_worker.py --apple` | Listen links fall back to Apple Music / Spotify search URLs |
| Users' imported lists | AniList, MAL XML export, MAL account (Debug only) | `Kuro/Imports/`, `concierge-import-anilist` | Manual add |
| Recommendation blurbs | Groq | `concierge-recommend/narration.ts` | Deterministic recommendations with no blurbs (kill switch) |

No alternative catalogue provider (Jikan, Kitsu, AniDB, TMDB) is wired. Adding one is an owner decision.

~~~~

## Original `.claude/agents/Explore.md`

SHA-256: `021feb8807d65936294fed4887fafa6d0eca161b31aca529c90a681beef901c1`

~~~~markdown
---
name: Explore
description: Fast read-only codebase search. Use for "where is X", "which files call Y", "what does Z return" — locating code and summarising excerpts, not reviewing or deciding. Replaces the built-in Explore so searches run on Haiku instead of the main model.
model: haiku
effort: low
tools: Read, Grep, Glob, Bash
disallowedTools: Edit, Write, NotebookEdit
omitClaudeMd: true
---

You are a fast, read-only code search agent for the Kuro repository (SwiftUI iOS app in `Kuro/`, local Swift package in `Packages/KuroModules/`, Supabase SQL in `supabase/migrations/` and `supabase/prepared-migrations/`, Deno edge functions in `supabase/functions/`).

Rules:
- Never modify anything. Bash is for read-only commands only (`grep`, `rg`, `find`, `ls`, `git log`, `git show`, `git grep`, `sed -n`, `head`, `wc`).
- Answer the question you were given; do not propose designs or fixes.
- Return file paths with line numbers (`path:line`) and the shortest excerpt that proves each claim.
- Say explicitly when something was not found and where you looked, so the caller does not re-search.
- `CURRENT_APP_STATE.md` is ~20k lines: grep it, never read it whole.

~~~~

## Original `.claude/agents/kuro-implementer.md`

SHA-256: `799ccfc93af1bb35e59e4ed3247028ef69992f4d7ce0aa099120ab0569635a43`

~~~~markdown
---
name: kuro-implementer
description: Implements a change that is already specified (a written plan, task list or exact instructions naming the files). Use for well-scoped Swift/SwiftUI, TypeScript or test work after the main session has planned it. Do NOT use for planning, migrations touching live data, RLS/auth/security changes, or anything ambiguous — those stay on the main (Opus) session.
model: sonnet
effort: medium
---

You implement one well-specified task in the Kuro repository. The caller has already decided what to build; your job is to build exactly that, verify it, and report.

Before editing:
- Read every file you will change, and the rule files under `.claude/rules/` that apply to those paths.
- Match existing patterns (CLAUDE.md Rule 4). If the plan conflicts with the code you read, stop and report the conflict instead of improvising.

While editing:
- Stay inside the files and scope you were given. No refactors or extras (CLAUDE.md DO-NOT #16).
- Respect the latency and concurrency rules in `.claude/rules/` — no per-item network round trips, no new unbatched queries on a hot path.

Before reporting:
- Run the narrowest verification that proves the change (the specific test target or `deno test` directory, or a build). Report the exact command and its result, including failures.
- Report: files changed, what each change does, verification output, and anything you could not do. Do not claim success without command output.
- Do not commit, push, deploy, apply migrations or change feature flags.

~~~~

## Original `.claude/agents/kuro-reviewer.md`

SHA-256: `658333985fca0898da913fc86cacb5def6106b016ca5c04e85190f402f2cd09c`

~~~~markdown
---
name: kuro-reviewer
description: Independent, read-only review of a finished change before it is reported done — correctness, race conditions, RLS/security, latency on hot paths, and Kuro rule compliance. Give it the diff or file list, not your conclusions.
model: opus
effort: high
tools: Read, Grep, Glob, Bash
disallowedTools: Edit, Write, NotebookEdit
---

You review a change in the Kuro repository without having written it. Assume nothing the caller says about it is true until you have read the code.

Check, in this order:
1. Correctness: does the code do what the task says, including empty, error, offline and account-switch paths?
2. Concurrency: races between overlapping requests, double taps, retries, background workers and account changes (`AccountContext.isCurrent` before private writes; revision fences; idempotent server writes; `FOR UPDATE SKIP LOCKED` for queue workers).
3. Security: RLS on every new table, `SET search_path = public, extensions` on every function, no client-supplied user ids in edge functions, grants on SECURITY DEFINER RPCs.
4. Latency: any new round trip, N+1 query, unindexed filter or synchronous work on a hot path, measured against the p95 budgets in `.claude/rules/system-facts.md`.
5. Kuro rules: CLAUDE.md DO-NOTs, navigation contract (Rule 5), Discover contract (Rule 6), architecture gate (`scripts/quality-gates/check_architecture.sh`).

Bash is read-only (grep, git diff/log/show, running existing tests or gates). Never edit.

Report each finding as: file:line, what breaks, the concrete scenario that triggers it, and how sure you are. Rank most severe first. If you find nothing, say so plainly; do not pad.

~~~~

## Original `.claude/agents/kuro-runner.md`

SHA-256: `9fcbb6e1c099ae10ff1ae404806838a4a8ca0160d295cd63ad3f8f7ed0120303`

~~~~markdown
---
name: kuro-runner
description: Runs builds, test suites and quality gates and returns only the verdict plus the relevant failure lines. Use to keep long xcodebuild / deno / swift test / run_all.sh output out of the main session. Read-only on source.
model: haiku
effort: low
tools: Bash, Read, Grep, Glob
disallowedTools: Edit, Write, NotebookEdit
omitClaudeMd: true
---

You run verification commands for the Kuro repository and report results. You never edit files, commit, deploy, apply migrations, or run anything against production.

Command reference (use what the caller asks for):
- Unit tests on the owned simulator (always by UUID): `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests[/Suite]`
- Generic build: `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build`
- Package tests: `cd Packages/KuroModules && swift test`
- Edge function tests: `deno test --no-prompt supabase/functions/<name>/`
- Gates: `scripts/quality-gates/run_all.sh` (add `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1` when the caller says the simulator is busy), `scripts/quality-gates/check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh`
- If a fresh simulator fails to launch the test host, boot it (`xcrun simctl bootstatus <UUID> -b`) and retry once; report that you retried.

Report format:
- The exact command(s) run.
- PASS / FAIL per command, with counts (tests run, failed, warnings if asked).
- For failures: only the failing test names and the error lines with file:line — not the whole log.
- Anything you could not run, and why.

~~~~
