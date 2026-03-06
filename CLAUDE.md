# CLAUDE.md — Kuro Project Rules & Context

**Last synced: 2026-03-06** | **This file is mandatory reading. Every rule is binding.**

---

## MANDATORY RULES — READ FIRST

### Rule 1: Update documentation after EVERY change
After **every single work initiative** — no matter how small — you MUST update these 3 files:
1. `CURRENT_APP_STATE.md` — authoritative technical snapshot (update the relevant sections + append to Change Log)
2. `CURRENT_APP_STATE_PLAIN.md` — plain English version (update relevant sections + append to Change Log)
3. `IMPLEMENTATION_PLAN_Variation1.md` — update status section if the change relates to any tracked feature

This is **not optional**. This is **not a suggestion**. Failure to update = incorrect system state = broken context for the next session.

### Rule 2: Update memory after EVERY change
After every change, update `~/.claude/projects/-Applications-Kuro/memory/MEMORY.md` with:
- Any new files created or deleted
- Any new patterns discovered
- Any gotchas encountered
- Updated file counts if files were added/removed
- Any new architectural decisions

This is **mandatory, not optional**. The memory file is how future sessions get instant context.

### Rule 3: Read before writing
Never propose changes to code you haven't read. Always read the file first. Understand existing patterns before modifying.

### Rule 4: Match existing patterns exactly
This codebase has established patterns. Match them. Don't introduce new paradigms, different naming conventions, or alternative approaches unless explicitly asked.

---

## WHAT THIS APP IS (exact description)

Kuro is a curated anime + manga iOS app. It lets users browse premium editorial picks, maintain personal watchlists, create private clubs with friends, and use a "Concierge" AI assistant to import lists and get mood-based recommendations. The app runs on SwiftUI with a Supabase backend.

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
- Feature flag: `social_activity_v1` at 0% rollout
- Rate limits: 10 comments/5min, 30 reactions/min

### On-device AI (Apple Foundation Models)
- Mode classification, disambiguation, synopsis condensation, NL collection search intent
- `AppleFMService.swift`: `@MainActor @Observable`, fresh session per request, `#available(iOS 26, *)`
- 4 `@Generable` structs — reasoning properties BEFORE selection properties (sequential generation order)
- Graceful fallback via `StubFMProvider` on non-FM-capable devices
- **NO ENTITLEMENT NEEDED** — just `import FoundationModels` + availability guard

### Feature Flags (staged rollout)
Server-controlled via `feature_flags` DB table, cached in UserDefaults, deterministic hash rollout.
All 15 flags defined in `FeatureFlags.swift`:
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
- `social_activity_v1` (0%) — title-level friend comments + reactions
- `clubs_notifications_v1` (100%) — in-app badges
- `streaming_availability_v1` (0%) — where-to-watch/read provider filters and shared availability UI
- `credits_cast_v1` (100%) — characters, staff, studios, authors on detail pages
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

## FILE MAP (exact, current as of 2026-02-24)

### iOS app — 67 Swift files in `Kuro/`

**Entry points:**
- `KuroApp.swift` — `@main`, scenePhase lifecycle, NetworkMonitor + SupabaseService injection, `.onOpenURL` deep link handler
- `ContentView.swift` — 5-page swipe pager, header (KURO wordmark / section title / search + profile), deep link sheet presentation

**Services (11 files):**
- `SupabaseService.swift` — core data layer, RPC calls, caching, auth bootstrap, `fmService`, `withRetry` helper
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

**Concierge UI (10 files):**
- `ConciergeView.swift` — main concierge view controller
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
- `BrowseView.swift` — Browse page (full-page, not a sheet)
- `EditorialCollectionView.swift` — Collection page
- `ClubsView.swift` — Clubs list page (enriched cards, unread dots)
- `ClubDetailView.swift` — Club detail (3-tab: Rails/This Week/Polls)
- `ClubCreateSheets.swift` — Create/join club sheets
- `EditorialSearchView.swift` — Search sheet
- `OnboardingView.swift` — First-launch onboarding
- `ProfileView.swift` — Profile menu (includes Clubs secondary access)
- `AuthView.swift` — Authentication
- Detail pages: `AnimeDetailView.swift`, `MangaDetailView.swift`, `MediaDetailSheet.swift`, `ClubActivitySection.swift`, `FriendsActivitySection.swift`, `ExternalLinksSection.swift`, `CastSection.swift`, `CreditsSection.swift`, `EntityDetailSheets.swift`
- UI components: `KuroRefinedCard.swift`, `KuroCardText.swift`, `KuroGlass.swift`, `KuroCachedAsyncImage.swift`, `KuroToast.swift`, `KuroTransientBanner.swift`, `KuroConciergeMark.swift`, `KuroInteractionEnvironment.swift`, `KuroLoadMoreSentinel.swift`, `KuroPagingGesture.swift`, `EditorialCards.swift`, `Cards.swift`, `UIComponents.swift`, `GenreHubView.swift`, `CountdownTimer.swift`
- Shared: `AddToListSheet.swift` — add/edit list entry sheet (used by cards + detail pages)
- Legacy/secondary: `DiscoverViewModel.swift`

**Design (2 files):**
- `KuroDesignSystem.swift` — colors, typography, spacing, radii, animations
- `Color+Hex.swift` — hex color utility

**Models (2 files):**
- `SupabaseModels.swift` — all Supabase data models
- `DiscoverBundle.swift` — discover bundle response model

### Supabase — 145 migration files in repo, 15 deployed edge functions (as of 2026-03-04)

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
- `scripts/quality-gates/` — 8 scripts: `check_secrets.sh`, `check_migrations.sh`, `test_router_offline.sh`, `router_test_cases.js`, `test_concierge_corpora.sh`, `audit_rails.sh`, `build_ios.sh`, `run_all.sh`
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
| Session memory / gotchas | `~/.claude/projects/-Applications-Kuro/memory/MEMORY.md` |
| Clubs product spec | `docs/clubs-spec.md` |
| Production blockers audit | `docs/production-blockers.md` |
| Apple FM migration report | `docs/apple-fm-migration-report.md` |

## CURRENT BEHAVIOR NOTE (2026-03-06)

- Concierge is intentionally **session-local**. Do not describe it as cross-session persistent unless a future change reintroduces full, honest persistence.
