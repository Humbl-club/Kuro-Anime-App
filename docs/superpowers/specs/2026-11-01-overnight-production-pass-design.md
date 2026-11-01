# Kuro overnight production pass (2026-11-01): design and lane plan

Owner request (31 Oct, verbatim intent): check every API call, intake path and table; take in more from sources (songs, next episode, next chapter, next volume, more); optimize tables, intake and delivery; hyper-polish Home, Discover, Clubs, Profile with lists (an innovative, visually easy list experience), onboarding, sign-in/up with branded screens and good button interactions; map every screen incl. the localhost prototypes; make every screen adaptive and on-brand; generate assets if needed; work autonomously overnight.

Evidence base: `docs/overnight-2026-11-01/understand/*.md` (8 audit lanes + CRITIC.md) and `docs/overnight-2026-11-01/live/` (read-only live snapshot). **Design authority for every screen: `docs/overnight-2026-11-01/understand/DESIGN_RULEBOOK.md`** (precedence, approved/rejected ledger, palette, type, geometry, motion, states, copy, forbidden list, per-screen direction, lane checklist §16). This spec only adds decisions and the build plan.

## 0. Hard boundaries (owner away; set by the lead)

- No writes to the live Supabase project: no `db push`, no migration apply, no function deploy, no cron/flag/secret change, no live data writes. All backend work is **prepared** (`supabase/prepared-migrations/20261101*`, edge source, worker scripts) and verified on the disposable local PostgreSQL harness and offline deno tests.
- No git push, no TestFlight/archive/upload, no App Store action.
- Simulator: only the owned UUID `7FC4B58A-430C-457D-A017-6B0095723F3F`, only by the lead's screenshot step. Do not erase it; keep its dev account.
- Generated art is brand art only (no imitation of real anime/manga characters or titles).
- Library (`LibraryStore` via `LibraryActions`) stays the only tracking authority. Account isolation, club permission checks, guarded Undo and import recovery stay intact. MAL connector stays Debug-only.
- "Production ready" in reports means built, tested and packaged locally. Never claim live readiness.

## 1. Facts that shape the plan (verified 2026-11-01)

- Live flags (`live/feature-flags.txt`): `series_foundation_v1` and `series_home_native_v1` are **off (0%)**. Live users see Taste / Discover / Browse / Collection / Clubs and the legacy detail. `feature_flag_overrides` does **not** exist live (PGRST205), and `FeatureFlags` treats that error as destructive (flips Home off mid-bootstrap in flag-on builds).
- `theme_links`, `release_events`, `catalogue_units`, `series` are empty live. `volumes` = 49,945 placeholder rows, `chapters` = 622,698 mostly placeholders; nothing writes chapter/volume dates; manga `next_chapter_*` is hard-nulled by every importer.
- 97% of DB time is `rebuild_media_similar_titles` (schema.md §P0-1).
- Licensing (sources.md §0): AniList ToS restricts mass storage and tracker use; AnimeThemes, MangaDex, AnimeSchedule, MAL/Jikan restrict commercial use; MangaUpdates is permissive with credit. No attribution exists in the app.

## 2. Decisions (lead's calls, reversible; owner should review)

| # | Decision |
|---|---|
| D1 | Every screen change must work in **both** worlds: live (flags off: legacy pager/detail/Collection) and target (flags on: Home pager, series detail). Flags stay off live. |
| D2 | Flag-on world regains Browse: a "Browse the catalogue" entry in Discover and in Search's idle state opens `BrowseView` through a route. |
| D3 | iPhone is portrait-only; iPad keeps all orientations with content constrained to a readable max width (680 pt) centered. |
| D4 | Localization stays inline EN/DE pairs via one helper `KuroLocale.isGerman` (`Kuro/Design/KuroLocale.swift`); no String Catalog migration tonight. Every new string ships EN+DE. |
| D5 | Medium switch keeps the native heavy serif mixed case (rulebook §15.1). Manga Home stays 2 columns (§15.6). Club room hue = neutral `#222222` token (§15.4). |
| D6 | Welcome composition stays frozen (b943e457). Headline copy unchanged (open for owner). |
| D7 | Onboarding is rebuilt as at most 3 frames in the welcome language (scenery still, serif line, one sentence, ink rule + arrow): (1) choose Anime/Manga (persists Home medium), (2) bring your list (opens the existing Import chooser, skippable), (3) clubs are private. Completion is stored per account. Reduce Motion respected. No icon circles. Its `tasteDeck` destination maps to the Taste page. |
| D8 | Discover keeps a lead frame but drops glass: issue-style frames on white (picture, serif title, ≤1–2 lines), no score chips/genre pills in frames. Airing-today rail sorted by air time. |
| D9 | **Lists = "Folio" shared component** (product-surfaces Concept A + B): status word strip (Watching/Reading · Planned · Completed · Paused · Dropped, with counts), two densities toggled in one control: **Shelf** (equal manga covers / shallow anime scenes) and **Index** (64 pt rows: thumb, title, progress numeral, 44 pt advance key, next-release line). Sort words: Recent, Title, Score, Next release. It is used by Collection (both worlds, replacing the series text list and polishing the legacy grid) and previewed in Profile ("Your lists": one cover row per status, tap opens Collection filtered). Reads Library/Collection owners only; writes via `LibraryActions` / existing advance paths with caught-up guard + Undo. |
| D10 | Release certainty model: every displayed date is **confirmed** (source states it), **announced** (source states a window/date without time), or **estimated** (computed from cadence, confidence ≥ 0.7 only, copy "Expected around …"). Otherwise nothing is shown ("Dates to come." only where a slot would be empty). Source is always recorded; UI can show "via AniList" etc. in detail. |
| D11 | Licensing: no newly *scheduled* collection from restricted sources. Prepared intake code for AniList airing window (same source already in production use), MangaUpdates (permissive, with credit) and AnimeThemes GraphQL (needs owner endorsement decision) ships unscheduled. A **Data sources & credits** screen is added (Profile > About). Song "Listen" links are on-device Apple Music / Spotify **search** URLs (nothing stored from Spotify). |
| D12 | Auth: login-CSRF fix + password reset done client-side: a persisted pending-flow record (kind, email hash, created_at, 1 h expiry) is written when the device starts reset/magic-link; a signed-out callback is accepted only with a matching pending flow; PKCE `?code=` is exchanged; `type=recovery` leads to a branded set-new-password screen (`auth.update(password:)`). Signed-in guard unchanged. Sign-in no longer enforces the 8-char rule (sign-up only). |
| D13 | `check_email_exists`: the client stops the live "Taken" check (enumeration); duplicate e-mail is reported on submit. Prepared migration revokes anon EXECUTE. |
| D14 | `FeatureFlags`: the overrides query runs only in DEBUG, and any overrides error is non-destructive (no cohort removal). |
| D15 | Series detail (flag-on) falls back to the legacy detail sections when its bundle has no series data; empty-state internal copy is rewritten (rulebook §9). |
| D16 | Dead `TasteDeckView` is left in place (no deletion tonight); docs say it is unreferenced. |

## 3. Shared data contracts (backend and client must match exactly)

### 3.1 `public.user_release_schedule_v1(p_medium text default null, p_limit int default 60)`
SECURITY DEFINER, `SET search_path = public, extensions`, STABLE, `auth.uid()` required (else raise `UNAUTHENTICATED`). Returns rows for titles the caller tracks with status current/planning/paused/repeating (anime_user_lists / manga_user_lists, `user_id::text = auth.uid()::text` lower-case compare), next upcoming unit only per title, ordered by `release_at nulls last`:

| column | type | notes |
|---|---|---|
| medium | text | `anime` / `manga` |
| media_id | int | |
| title | text | display title |
| cover_image | text | |
| unit_kind | text | `episode` / `chapter` / `volume` / `season` |
| unit_number | numeric | null when unknown |
| unit_label | text | e.g. `Ep. 7`, `Ch. 1197`, `Vol. 115` |
| release_at | timestamptz | null when unknown |
| basis | text | `confirmed` / `announced` / `estimated` |
| confidence | real | 0–1; estimated rows only returned when ≥ 0.7 |
| source | text | `anilist` / `mangaupdates` / `mangadex` / `publisher` / `kuro_estimate` |
| source_url | text | nullable |

Anime: from `release_events` (confirmed AniList airing) falling back to `anime.next_airing_at` / `next_episode_number` (basis confirmed, source anilist). Manga: `release_events` rows (chapter/volume) — confirmed/announced from sources, estimated from cadence over the last ≥ 6 dated chapters.

### 3.2 `public.media_release_schedule_v1(p_medium text, p_media_id int, p_limit int default 6)`
Public catalog read (no auth needed, anon + authenticated EXECUTE), same columns, upcoming units for one title (also the last confirmed past unit with `release_at < now()` flagged by a boolean column `is_past`).

### 3.3 `public.media_themes_v1(p_anime_id int)`
Public read. Returns: `kind` text (`OP`/`ED`/`IN`), `sequence` int, `title` text, `artist` text, `episodes` text (e.g. `1–12`), `version` int, `is_spoiler` bool, `is_nsfw` bool, `source` text (`animethemes`), `source_url` text. Backed by `theme_links` (+ additive columns `episodes`, `version`, `is_spoiler`, `is_nsfw`, `source`, `source_url`).

### 3.4 Client tolerance (live today has none of the above)
Swift owners call these RPCs and on PostgREST "function not found" (PGRST202 / 404) or any decode failure **silently** fall back: anime next episode from the existing `user_airing_next` / `anime.next_airing_at` path (basis confirmed); manga and themes return empty, and the UI hides the section (no banner, no error copy). Cache results per account (TimedCache, 5 min). Models live in `Kuro/Releases/ReleaseModels.swift` (`ReleaseScheduleItem`, `ReleaseBasis`, `ThemeSong`) owned by the foundation lane.

### 3.5 Shared SwiftUI components (foundation lane creates, lanes consume) — `Kuro/Views/Shared/`
- `KuroMediumSwitch` (serif word switch with ink underline; Anime/Manga; binding).
- `KuroAdvanceKey` (44 pt +1 key, light/dark variants, haptic `.selection`, disabled when caught up, accessibility "Mark episode 8 watched").
- `KuroReleaseLine` (renders a `ReleaseScheduleItem` with certainty copy EN/DE: confirmed "Ep. 7 · Thu 15 Oct, 18:30", announced "Vol. 115 · November", estimated "Ch. 1197 · expected around Sun 9 Nov"; relative "today/tomorrow"; uses `de_DE`/`Europe/Berlin` when German, device locale otherwise).
- `KuroStateView` (loading / empty / offline / failed / denied with honest EN/DE copy, optional retry action).
- `KuroSectionHeader` (serif section title with `.isHeader`).
- `KuroInkButton` (primary ink capsule 52 pt, secondary text-with-rule-and-arrow, destructive red), consistent pressed state (scale 0.98, 120 ms) and haptics.
- `KuroReadableWidth` modifier (max 680 pt centered on regular width).
- `KuroThemeSongRow` (OP/ED label, title, artist, episodes, Listen menu → Apple Music / Spotify search URLs).

## 4. Lanes and exclusive file ownership

Foundation runs first in the main tree and is committed; then lanes 1–7 run in parallel git worktrees branched from that commit; the lead merges. A lane may only edit files it owns; anything else goes into its report as a request for the lead.

| Lane | Owns (exclusive) |
|---|---|
| **F Foundation** | `Kuro/Design/**`, `Kuro/Views/Shared/**` (new), `Kuro/Views/Routing/**`, `Kuro/ContentView.swift`, `Kuro/Services/FeatureFlags.swift`, `Kuro/Library/**`, `Kuro/Releases/**`, `Kuro/Composition/**`, `Kuro/Views/Kuro*.swift` primitives, `Info.plist`, `Kuro.xcodeproj/**`, `Kuro/Assets.xcassets/**` |
| **1 Backend & intake** | `supabase/**` except `supabase/functions/auth-callback/**`; `scripts/**` except `scripts/quality-gates/check_architecture.sh` |
| **2 Data delivery (client)** | `Kuro/Catalog/**`, `Kuro/Discovery/**`, `Kuro/Collection/**`, `Kuro/Search/**`, `Kuro/Social/**`, `Kuro/Providers/**`, `Kuro/Services/ImagePipeline.swift`, `Kuro/Services/KuroDiskDetailCache.swift` |
| **3 Home & detail** | `Kuro/Home/**`, `Kuro/Views/Home/**`, `Kuro/Views/DetailPages/**` |
| **4 Discover, Search, Browse, Taste** | `Kuro/Views/EditorialDiscover*.swift`, `Kuro/Views/DiscoverOneThingCard.swift`, `Kuro/Views/DiscoverViewModel.swift`, `Kuro/Views/EditorialSearchView.swift`, `Kuro/Views/Browse*.swift`, `Kuro/Views/TastePicksView.swift`, `Kuro/Taste/**` |
| **5 Clubs** | `Kuro/Views/Club*.swift`, `Kuro/Views/ClubsView.swift`, `Kuro/Clubs/**`, `Kuro/Views/SharedCards/AddToClubRailSheet.swift` |
| **6 Profile & Lists** | `Kuro/Views/ProfileView.swift`, `Kuro/Views/ProfileFreshnessCard.swift`, `Kuro/Views/EditorialCollection*.swift`, `Kuro/Views/AddToListSheet.swift`, `Kuro/Views/Import*.swift`, `Kuro/Views/Lists/**` (new), `Kuro/Views/About/**` (new: Data sources & credits, Privacy/Terms) |
| **7 Auth & onboarding** | `Kuro/Views/AuthView.swift`, `Kuro/Views/OnboardingView.swift`, `Kuro/Views/KuroSceneryLoop.swift` (exception to F's primitives), `Kuro/Identity/**`, `Kuro/KuroApp.swift`, `Kuro/Services/DeepLinkRouter.swift`, `emails/**`, `supabase/functions/auth-callback/**` |

Unowned tonight (do not edit): Concierge views/owners, `Kuro/Imports/**` owners, `Packages/**`, `Kuro/Services/*` not listed, tests owned per lane below.

Tests: each lane may add/edit test files named for its area in `KuroTests/` (new files preferred, e.g. `KuroTests/ReleaseScheduleTests.swift`), package tests are off-limits. Lanes compile with their own `-derivedDataPath` and run only package tests + their own focused unit tests if cheap; the lead runs the full `KuroTests` once after merge.

## 5. Lane briefs (what "done" means)

- **F**: neutral palette tokens frozen per rulebook §3 (remove/alias cast colors, `kuroInk*`, `kuroCanvas*`, club room `#222222`), type roles made Dynamic-Type reactive (`relativeTo:`) with sane caps; `KuroLocale`; shared components §3.5; release/theme models + `ReleasesStore` schedule APIs with §3.4 tolerance; `FeatureFlags` D14; `LibraryRealtime` self-echo suppression (ignore events for keys with a write in flight or confirmed within 5 s; never drop foreign-device events); header accessibility (don't hide Search/Profile; accessible page switching via `.accessibilityAdjustableAction`); Browse route (D2); portrait lock + iPad readable width (D3); `AccentColor` ink; remove `?? 393`/`KuroScreen.width` in owned files. Build passes; architecture gate passes.
- **1**: prepared migrations (`supabase/prepared-migrations/20261101000000_release_schedule_and_themes_v2.sql` implementing §3.1–3.3 + additive columns + RLS + grants; `…010000_perf_hotpaths.sql` similar-titles change gating, ~22 duplicate index drops, `catalog_safety_audit` retention function, CONCURRENTLY matview refresh, drop unread `mv_anime_current_season` only if no reader; `…020000_bridge_identity_fix.sql`; `…030000_auth_hardening.sql` revoke anon `check_email_exists`); edge: bulk-import robustness (GraphQL errors ≠ empty page, Retry-After + jitter + timeout + shared 25/min limiter, `onConflict` on join upserts, preserve mirrored images and synopsis state, per-track queries); new `release-intake` function (AniList `Page.airingSchedules` window now-6h..now+8d → `release_events` confirmed + `anime.next_*`; MangaUpdates last releases → chapter cadence estimate + volume counts via MangaDex `links.mu`); themes worker on AnimeThemes GraphQL (batched); keep MangaDex `/aggregate` volume grouping; local SQL tests in `supabase/tests/` + deno tests; `supabase/tests/pending_migrations.txt` corrected; replay double-apply fixed. Nothing deployed or scheduled.
- **2**: api-surface P1/P2 fixes in owned owners: explicit column lists for catalog reads (no `safety_*`/`synopsis_enhanced_*`), card projections, bounded credits, single `discover_bundle` load per launch (expose a `warmIfNeeded` the view calls), cached `external_links`, one availability status call, remove N+1 fallback, image cache keyed by pixel size, Collection feed fields needed by D9 (cover, totals, status, progress, next release via ReleasesStore).
- **3**: Home per rulebook §14.1: cast hexes → tokens, internal copy rewritten EN/DE, fabricated "Sunday Club" fallback removed, date formatting via `KuroLocale`, planned titles never become the "in progress" hero, Coming Up from `ReleasesStore` schedule with certainty, landscape/iPad sizing via readable width, adaptive 320–430. Detail (both legacy and series): next-release block (`media_release_schedule_v1` via ReleasesStore), songs section (`media_themes_v1`) with Listen menu, D15 fallback, watch-link chain from lane 2 owners, tokens, Dynamic Type, accessibility.
- **4**: Discover D8 + D2 entry, tokens (no raw `.black.opacity` text), airing-today by time, newlyAddedManga shown, See All for manga rails, states via `KuroStateView`; Search idle state (recent searches + Browse entry), ink refinement words; Browse polish/adaptivity; TastePicks states.
- **5**: Clubs list (inhabited cards, ink unread dot, honest states incl. failed/offline ≠ empty), club detail (room `#222222`, tabs RAILS/ACTIVE/POLLS kept), create/join sheets polish, removal of revisit refetch + catch-all fallback, adaptive, EN/DE.
- **6**: Profile per rulebook §14.3 (identity, Your Library counts + **Your lists** preview, Imports & connections, Clubs, Preferences, Account & privacy, Advanced; About → Data sources & credits + Privacy/Terms links); ProfileFreshnessCard moved under Advanced; **Folio** lists D9 in Collection (both worlds) with Shelf/Index, status strip, sort words, batch bar incl. Dropped, next-release line, Undo; import views polished to tokens.
- **7**: D12 + D13 + auth error mapping by SDK error code (EN/DE), Apple cancel ignored, sign-up-without-session message, reset success neutral, `@FocusState` with submit chaining, form rebrand (ink focus/underline, tokens, Dynamic Type, labels), Terms/Privacy tappable, D7 onboarding, bootstrap single Library read in `SessionController`, emails re-skinned to white/#181818 without Google Fonts (prepared, not uploaded), auth-callback page aligned (not deployed).

## 6. Verification and reporting

Per lane: compile (own derivedData), architecture gate, its tests, rulebook §16 checklist self-review, report with changed files, requests for other lanes, open issues. After merge (lead): independent adversarial review per lane, all gates, full `KuroTests` once, local DB harness + deno tests, screenshot pass on the owned simulator for both worlds at 390 (plus 320/430 for Home/Lists/Discover), completeness critic against the owner's list, then the three state docs + memory, final report. Visual acceptance remains the owner's.
