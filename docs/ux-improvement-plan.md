# Kuro UX Improvement Plan

Consolidated findings from a 7-agent audit of the entire Kuro iOS app, covering navigation, discovery, list management, detail pages, concierge, clubs, profile/auth/settings, accessibility, and visual consistency.

**Date**: 2026-02-14
**Branch**: codex/concierge-curated-personal
**Methodology**: Each agent independently audited a domain area, findings were deduplicated and prioritized by impact x effort.

### Post-Audit Cross-Check Errata

The raw audit was cross-checked line-by-line against the codebase. Corrections applied:

**FALSE (removed from raw audit):**
1. ClubActivitySection "placeholder" claim — implementation renders real per-member status/progress from `member_statuses`, "Not started" is a nil-fallback only, `sharing_level` used correctly for privacy gating. (Evidence: `ClubActivitySection.swift:438,670-676,402`)

**OVERSTATED (corrected in plan):**
2. "No nav affordance at all" → Title window (`ContentView.swift:381-423`) IS an affordance. Real gap: missing *positional* context (dot indicators).
3. "No quick-add via long press" → Discover cards have `.contextMenu` quick-add (`EditorialDiscoverView.swift:822`). Real gap: inconsistent coverage across other card surfaces.

### Implementation Status (validated 2026-02-14)

| Status | Count | Items |
|--------|-------|-------|
| **Implemented** | 4 | P0-DETAIL-1 (sticky actions), P1-DETAIL-2 (sharing), P2-DETAIL-2 (airing info), P0-CONC-1 (first-time text) |
| **Partial** | 12 | P1-NAV-4, P1-DISC-2, P2-DISC-1, P0-LIST-1, P1-LIST-3, P1-DETAIL-1, P2-CLUB-1, P0-AUTH-1, P2-A11Y-1, P2-A11Y-2, P0-POLISH-1, P2-POLISH-1 |
| **Not implemented** | 31 | All remaining items |

---

## Priority Definitions

| Priority | Label | Criteria |
|----------|-------|----------|
| **P0** | Quick Wins | High impact, low effort (< 1 day each) |
| **P1** | Strategic | High impact, medium effort (1-3 days each) |
| **P2** | Polish | Medium impact, low effort (< 1 day each) |
| **P3** | Future | Any impact, high effort (3+ days each) |

---

## 1. Navigation & Information Architecture

**Core problem**: 6 tabs with minimal nav affordance. Users can see the current section name in an animated title window (with stroke hints that strengthen when swiping is possible), but have no positional context — they don't know how many sections exist or where they are in the sequence. Tabs 4-6 (Browse, Search, Clubs) are effectively hidden because there's no indication they exist until the user swipes far enough to reach them.

### P0-NAV-1: Add positional navigation indicator (dots or pill strip)
- **What**: Add a row of small dot indicators or a scrollable pill strip below the existing header title window showing all section names with the active one highlighted. The title window already shows the current section name, but users have no sense of *position* (which of N sections am I on?) or *scope* (how many sections exist?).
- **Why**: The existing title window tells users *where* they are but not *what else exists*. Without positional context, users don't know there are more tabs to discover. Tabs 4-6 remain hidden for users who don't swipe far enough.
- **Files**: `Kuro/ContentView.swift` (KuroHeaderNew, line ~425-544)
- **Scope**: Small
- **Source**: nav-discovery-auditor (CRITICAL)
- **Correction note**: Original audit overstated this as "no nav affordance at all." The title window (line 381-423) with animated section name transitions and stroke opacity hints IS an affordance — but it lacks positional context.

### P0-NAV-2: Reduce splash screen delay from 2s to 1s
- **What**: Change `DispatchQueue.main.asyncAfter(deadline: .now() + 2.0)` to `1.0` in KuroLaunchView.
- **Why**: The 2-second fixed splash delay is cosmetic padding. Modern apps launch as fast as possible. 1s is sufficient for the fade-in animation.
- **Files**: `Kuro/ContentView.swift:39` (KuroRootView)
- **Scope**: Small
- **Source**: nav-discovery-auditor (LOW)

### P1-NAV-1: Aggressive tab consolidation — merge Browse + Search into Discover
- **What**: Two consolidation options (choose one):
  - **Option A (Conservative)**: Merge Browse into Discover as a filter toggle. Keep Search as its own tab. Result: 5 tabs (Concierge / Discover / Collection / Search / Clubs).
  - **Option B (Aggressive, recommended by nav-discovery auditor)**: Merge Browse into Discover AND make Search a global overlay accessible from any tab. Move Clubs under Profile. Result: 3 core tabs (Discover / Collection / Concierge) with Search overlay and Clubs in Profile.
- **Why**: Genre pills in Discover duplicate Browse's genre filter. Discover's "See All" sheets recreate Browse functionality. Search category filters (Trending, New Season, Classics, Hidden Gems) duplicate Discover rails. 6 tabs is too many — most successful apps use 3-5.
- **Files**: `Kuro/Views/EditorialDiscoverView.swift`, `Kuro/Views/BrowseViewRefined.swift`, `Kuro/Views/EditorialSearchView.swift`, `Kuro/ContentView.swift`
- **Scope**: Large
- **Source**: nav-discovery-auditor (CRITICAL + HIGH)

### P1-NAV-2: Make Search globally accessible
- **What**: Add a search icon in the header (or make the header title tappable to open search) so users can search from any tab, not just the Search tab. Implement as a sheet/overlay that can be invoked from anywhere.
- **Why**: Having to swipe to the 5th tab to search is high friction. Most apps have search accessible from everywhere.
- **Files**: `Kuro/ContentView.swift` (KuroHeaderNew), `Kuro/Views/EditorialSearchView.swift`
- **Scope**: Medium
- **Source**: nav-discovery-auditor (HIGH)

### P1-NAV-3: Consider making Concierge a sheet/overlay instead of a tab
- **What**: Move Concierge out of the tab pager and into a floating button or sheet accessible from any tab (similar to ChatGPT's input field pattern). This frees up the leftmost position for Discover.
- **Why**: Concierge as the leftmost tab hides it from users who only swipe right. As a floating action it would be more discoverable AND more contextual (e.g., invoke from a detail page to get recommendations based on what you're viewing).
- **Files**: `Kuro/ContentView.swift` (KuroMainView, KuroSectionPager), `Kuro/Views/ConciergeView.swift`
- **Scope**: Large
- **Source**: nav-discovery-auditor (HIGH)

### P1-NAV-4: Move Clubs under Profile (if keeping reduced tab count)
- **What**: If tab consolidation happens, remove Clubs as a top-level tab and make it accessible from ProfileView (already has a clubs preview section and "Clubs" action row).
- **Why**: Clubs is premature as a top-level tab — most users won't have clubs initially. ProfileView already surfaces a clubs preview. Top-level tab space is premium real estate.
- **Files**: `Kuro/Views/ProfileView.swift`, `Kuro/ContentView.swift`
- **Scope**: Medium
- **Source**: nav-discovery-auditor (MEDIUM)

### P2-NAV-1: Add haptic + animation for edge bounce on first/last tab
- **What**: When user swipes past the leftmost or rightmost tab, show a rubber-band bounce effect.
- **Why**: Currently nothing happens when you swipe past the edge. User has no feedback they've reached the end.
- **Files**: `Kuro/ContentView.swift` (swipe gesture handler)
- **Scope**: Small

### P2-NAV-2: Reduce gesture conflict fragility
- **What**: The swipe pager has ~85 lines of gesture conflict management (`swipeExclusions`, `suppressCardTaps`, velocity hints, async reset tasks). Refactor into a dedicated `SwipeConflictManager` or replace with a proper `TabView` or `UIPageViewController` wrapper that handles conflicts natively.
- **Why**: The current DragGesture-based paging with manual exclusion zones is fragile and hard to maintain. Adding/removing horizontal scroll views requires updating exclusion preferences.
- **Files**: `Kuro/ContentView.swift:178-263`
- **Scope**: Medium
- **Source**: nav-discovery-auditor (MEDIUM)

---

## 2. Discovery (Discover + Browse + Search)

**Core problem**: Three separate tabs (Discover, Browse, Search) all serve the "find anime" use case with significant functional overlap. Genre pills in Discover duplicate Browse's genre filter. Discover's "See All" sheets recreate Browse functionality. Search category filters (Trending, New Season, Classics, Hidden Gems) duplicate Discover rails. This fragmentation confuses users and spreads development effort thin.

### P0-DISC-1: Fix DiscoverEmptyStateView showing perpetual "Connecting..."
- **What**: Replace `DiscoverEmptyStateView` with a proper empty state that says "No content found" with a retry button, not a permanent spinner.
- **Why**: If the DB returns zero items (edge case), users see an infinite "Connecting to Supabase..." with no escape.
- **Files**: `Kuro/ContentView.swift:916-935`
- **Scope**: Small

### P0-DISC-2: Deduplicate genre chips between Discover and Browse
- **What**: If Browse remains as a separate tab, remove genre pills from EditorialDiscoverView (or make them link to Browse with that genre pre-selected) to eliminate the duplicate filtering surface.
- **Why**: Discover's `primaryGenreChips` (Action, Adventure, Comedy, etc.) open a GenreHubView that is functionally identical to selecting the same genre in Browse. Two paths to the same outcome confuses users.
- **Files**: `Kuro/Views/EditorialDiscoverView.swift:42-56`, `Kuro/Views/BrowseViewRefined.swift`
- **Scope**: Small
- **Source**: nav-discovery-auditor (CRITICAL)

### P1-DISC-1: Add Year and Format filters to Browse (if Browse persists)
- **What**: Add filter options for: Year range (decade picker), Format (TV / Movie / OVA / ONA / Special), Source material (Manga / Light Novel / Original / Visual Novel).
- **Why**: Browse currently only offers Genre, Length, Status, and Sort. Year and Format are common filtering needs. If Browse is going to exist separately from Discover, it needs to justify its existence with richer filtering that Discover doesn't offer.
- **Files**: `Kuro/Views/BrowseViewRefined.swift`
- **Scope**: Medium

### P1-DISC-2: Improve Search empty state with suggestions
- **What**: When search returns "NO RESULTS", show: "Try searching for..." with 3-4 popular titles, genre suggestions, or spelling correction hints.
- **Why**: Dead-end empty states cause users to give up. A helpful suggestion keeps them engaged.
- **Files**: `Kuro/Views/EditorialSearchView.swift:547`
- **Scope**: Small

### P1-DISC-3: Deduplicate Search category filters with Discover rails
- **What**: Remove the category filter chips (Trending, New Season, Classics, Hidden Gems) from EditorialSearchView since these exactly mirror Discover rails. Search should focus on text search + scope filtering (All/Anime/Manga), not duplicate curated categories.
- **Why**: Search's category filters fetch the same data as Discover's editorial rails. Users end up with two ways to browse "Trending" or "New Season" content.
- **Files**: `Kuro/Views/EditorialSearchView.swift:25,47-51`
- **Scope**: Small
- **Source**: nav-discovery-auditor (HIGH)

### P2-DISC-1: Add "In Your List" badge on cards in Discover/Browse/Search
- **What**: Overlay a subtle indicator (e.g., a small checkmark or status dot) on cards for anime/manga already in the user's list.
- **Why**: Users can't tell at a glance what they've already added without tapping into each card.
- **Files**: `Kuro/ContentView.swift` (SophisticatedAnimeCard, CollectionCardReal, DiscoverCardElegant)
- **Scope**: Medium

---

## 3. List Management & Collection

### P0-LIST-1: Extend long-press quick-add to all card surfaces
- **What**: Discover cards already have a `.contextMenu` with "Quick Add (Planned)" and "Add to List…" (see `EditorialDiscoverView.swift:822-831`). Extend this same context menu to *all* card surfaces: Browse cards, Search result cards, Collection cards, "More Like This" rails on detail pages, and club rail items. Also add additional status shortcuts ("Add to Watching", "Mark Completed") beyond the current single "Quick Add (Planned)" option.
- **Why**: Quick-add exists on Discover but coverage is not universal. Users expect the same interaction on every card. Missing it on Browse/Search/Similar rails forces the 3-tap detail-sheet flow for those surfaces.
- **Files**: `Kuro/ContentView.swift` (SophisticatedAnimeCard, CollectionCardReal), `Kuro/Views/BrowseViewRefined.swift`, `Kuro/Views/EditorialSearchView.swift`, `Kuro/Views/DetailPages/AnimeDetailView.swift` (SimilarSection)
- **Scope**: Medium
- **Correction note**: Original audit claimed no quick-add existed at all. Discover cards DO have context-menu quick-add since `EditorialDiscoverView.swift:822`. The real gap is inconsistent coverage across card surfaces.

### P1-LIST-1: Add one-tap episode increment from Collection
- **What**: Show a small "+1 EP" button on collection cards for anime with status "watching", so users can increment progress without opening the detail view.
- **Why**: Marking "I watched the next episode" is the most frequent user action and currently requires opening the full detail sheet.
- **Files**: `Kuro/Views/EditorialCollectionView.swift`, `Kuro/Views/Collection/CollectionManagementView.swift`
- **Scope**: Medium

### P1-LIST-2: Add sort options to Collection
- **What**: Add sort by: Last Updated, Title (A-Z), Rating, Progress, Date Added. Currently collection only has status filters.
- **Why**: Users with large collections (100+ items) need to find things fast. Alphabetical and by-rating sorts are table stakes.
- **Files**: `Kuro/Views/EditorialCollectionView.swift`
- **Scope**: Medium

### P1-LIST-3: Add Collection empty state with CTA for new users
- **What**: When user has zero items in collection (not just filtered empty), show: "Your collection is empty. Start adding anime from Discover." with a button that switches to the Discover tab.
- **Why**: New users see the Collection tab but have nothing in it. No guidance on how to start.
- **Files**: `Kuro/Views/EditorialCollectionView.swift`
- **Scope**: Small

### P2-LIST-1: Add list view toggle (grid vs. list) in Collection
- **What**: Add a small toggle icon in the Collection filter bar to switch between grid view (current) and compact list view.
- **Why**: Grid view shows beautiful posters but is slow to scan. A dense list view is better for managing large collections.
- **Files**: `Kuro/Views/EditorialCollectionView.swift`
- **Scope**: Medium

### P3-LIST-1: Bulk operations (multi-select + batch status change)
- **What**: Add an "Edit" mode to Collection with multi-select checkboxes and batch actions (change status, delete, export).
- **Why**: Users who drop multiple series at once need this. Currently requires individual edits.
- **Files**: `Kuro/Views/EditorialCollectionView.swift`, `Kuro/Views/Collection/CollectionManagementView.swift`
- **Scope**: Large

---

## 4. Detail Pages

### ~~P0-DETAIL-1: Make Action Buttons sticky on scroll~~ ✅ IMPLEMENTED
- Already implemented via `.safeAreaInset(edge: .bottom)` in both `AnimeDetailView.swift:109` and `MangaDetailView.swift:109`.

### P1-DETAIL-1: Add explicit AniList/MAL links alongside streaming links — PARTIAL
- **What**: Stream/read links already implemented (`AnimeDetailView.swift:1086`, `MangaDetailView.swift:1005`). Remaining gap: add explicit AniList and MyAnimeList profile links as a "View on…" section.
- **Why**: Users want cross-reference to external databases for reviews, discussions, detailed metadata.
- **Files**: `Kuro/Views/DetailPages/AnimeDetailView.swift`, `Kuro/Views/DetailPages/MangaDetailView.swift`
- **Scope**: Small (data already available via `anilist_id`/`mal_id`)

### ~~P1-DETAIL-2: Add sharing support~~ ✅ IMPLEMENTED
- Already implemented via `ShareLink` in `AnimeDetailView.swift:1105` and `MangaDetailView.swift:1024`.

### P2-DETAIL-1: Unify AnimeDetailView and MangaDetailView
- **What**: Extract shared components (HeroSection, TitleSection, DescriptionSection, GenresSection, TagChipsSection, SimilarSection, ClubActivitySection) into a generic `MediaDetailView<T: MediaDisplayable>`. Keep anime-specific (EpisodesSection) and manga-specific (ChaptersSection) sections conditional.
- **Why**: Significant code duplication between the two views. Changes must be applied twice. Risk of them drifting apart.
- **Files**: `Kuro/Views/DetailPages/AnimeDetailView.swift`, `Kuro/Views/DetailPages/MangaDetailView.swift`
- **Scope**: Large

### ~~P2-DETAIL-2: Show airing info for currently airing shows~~ ✅ IMPLEMENTED
- Already implemented via `NextUpSection` with `nextAiringAt` in `AnimeDetailView.swift:227`.

---

## 5. Concierge

### ~~P0-CONC-1: Improve first-time Concierge experience~~ ✅ IMPLEMENTED
- Already implemented with editorial subtitle and intent deck visible when empty (`ConciergeView.swift:111,177`).

### P1-CONC-1: Add guided first-use flow for Concierge
- **What**: On first Concierge visit, show a short interactive tutorial: (1) "Try typing a mood" -> (2) "Or paste your anime list" -> (3) "I'll curate recommendations". Dismiss after first use.
- **Why**: The Concierge is the app's differentiator but users don't know what it can do. The intent deck helps but isn't self-explanatory.
- **Files**: `Kuro/Views/ConciergeView.swift`, `Kuro/Views/ConciergeEditorialShell.swift`
- **Scope**: Medium

### P2-CONC-1: Show conversation history across sessions
- **What**: Persist chat messages (at least the last 20) to UserDefaults or local DB so returning users see their previous interactions.
- **Why**: Currently messages reset when the view is unmounted. Users lose their conversation and recommendations.
- **Files**: `Kuro/Views/ConciergeView.swift` (messages array)
- **Scope**: Medium

---

## 6. Clubs

### P0-CLUB-1: Surface club activity outside the Clubs tab
- **What**: Show a "Club Activity" badge or indicator on the header's profile icon when there's new activity in joined clubs.
- **Why**: Clubs is the 6th (last) tab. Users forget it exists. Activity indicators drive re-engagement.
- **Files**: `Kuro/ContentView.swift` (KuroHeaderNew), `Kuro/Views/ClubsView.swift`
- **Scope**: Medium

### P1-CLUB-1: Add invite link / QR code for club joining
- **What**: In addition to the current "join with code" flow, allow club creators to share an invite link or QR code.
- **Why**: Code-based joining is friction-heavy (dictating a code verbally is error-prone). Links/QR codes are standard.
- **Files**: `Kuro/Views/ClubsView.swift`, `Kuro/Views/ClubDetailView.swift`
- **Scope**: Medium

### P1-CLUB-2: Add discussion/reactions to club rails
- **What**: Allow club members to react (emoji reactions or simple like/dislike) to shared rails. Optionally add a simple comment thread per rail item.
- **Why**: Clubs currently show "3 watching, 1 completed" but there's no way to discuss. Clubs feel read-only and don't generate engagement.
- **Files**: `Kuro/Views/ClubDetailView.swift`, DB migration needed
- **Scope**: Large

### P2-CLUB-1: Improve privacy level explanation
- **What**: Add inline help text or an info button (i) next to privacy level options (private/status/progress) in club settings that explains what each level means.
- **Why**: Users don't understand the difference between the three privacy levels without documentation.
- **Files**: `Kuro/Views/ClubDetailView.swift` (settings sheet)
- **Scope**: Small

---

## 7. Auth & Profile

### P0-AUTH-1: Remove orphaned SettingsView or consolidate with ProfileView
- **What**: Delete `Kuro/Views/SettingsView.swift` (218 lines of dead/unreachable code) since ProfileView already serves as the settings surface. Or wire it as a sub-page of ProfileView.
- **Why**: SettingsView has 4 no-op buttons, uses raw system fonts, hardcodes "M" as initial, and is unreachable from any navigation path. It's dead code.
- **Files**: `Kuro/Views/SettingsView.swift`, `Kuro/Views/ProfileView.swift`
- **Scope**: Small

### P0-AUTH-2: Add success toast after Profile > Sync Data
- **What**: After the sync Task completes in ProfileView, show `KuroToast(.success, title: "Synced", subtitle: "Lists updated")`.
- **Why**: Currently the ProgressView disappears silently. No feedback that sync succeeded.
- **Files**: `Kuro/Views/ProfileView.swift:197-205`
- **Scope**: Small

### P1-AUTH-1: Implement Apple Sign In
- **What**: Add `SignInWithAppleButton` to AuthView using Supabase's built-in Apple OAuth provider.
- **Why**: **App Store requirement** — Apple requires Apple Sign In if any third-party authentication is offered. The placeholder text "Apple Sign-In will be added next" is still visible to users.
- **Files**: `Kuro/Views/AuthView.swift`, `Kuro/Services/SupabaseService.swift`
- **Scope**: Medium

### P1-AUTH-2: Add account deletion flow
- **What**: Add "Delete Account" button in ProfileView (destructive, with confirmation dialog) that calls Supabase's delete user API.
- **Why**: **App Store requirement** since June 2022 — all apps that offer account creation must also offer account deletion.
- **Files**: `Kuro/Views/ProfileView.swift`, `Kuro/Services/SupabaseService.swift`
- **Scope**: Medium

### P1-AUTH-3: Add forgot password / password reset
- **What**: Add a "Forgot Password?" link in AuthView that sends a password reset email via Supabase Auth.
- **Why**: Users who forget their password have no recovery path. This is basic auth hygiene.
- **Files**: `Kuro/Views/AuthView.swift`, `Kuro/Services/SupabaseService.swift`
- **Scope**: Small

### P2-AUTH-1: Migrate AuthView to KuroDesignSystem tokens
- **What**: Replace all raw `.system(size: N)` font calls in AuthView with `.kuroCaption()`, `.kuroBody()`, etc. Replace `Color.white` with `Color.kuroBackground`.
- **Why**: AuthView is the first screen users see but doesn't use the editorial design system. Inconsistent typography.
- **Files**: `Kuro/Views/AuthView.swift`
- **Scope**: Small

### P2-AUTH-2: Richer profile stats
- **What**: Add to ProfileView stats: total episodes watched, chapters read, top 3 genres, average rating given, and collection start date.
- **Why**: Current stats (anime count, manga count, completed count) are shallow. Users want to see their engagement metrics.
- **Files**: `Kuro/Views/ProfileView.swift`, `Kuro/Services/SupabaseService.swift`
- **Scope**: Medium

---

## 8. Onboarding

### P1-ONBOARD-1: Add first-launch walkthrough
- **What**: Create a 3-4 card onboarding flow shown only on first launch (persisted via UserDefaults):
  1. "Swipe to navigate" — shows the 5-6 section tabs
  2. "Your Concierge" — explains AI recommendations
  3. "Build your Collection" — add anime/manga to track
  4. "Create a Club" — watch together with friends
- **Why**: **No onboarding exists.** Users land on the app with no idea they can swipe between sections, what the Concierge does, or that Clubs exist. This is the single biggest UX gap.
- **Files**: New file: `Kuro/Views/OnboardingView.swift`, `Kuro/KuroApp.swift` (show before ContentView)
- **Scope**: Medium

---

## 9. Accessibility

### P1-A11Y-1: Make Dynamic Type actually work
- **What**: `KuroAccessibility.adaptiveFont()` is a no-op stub. Replace hardcoded `.system(size: N)` throughout the app with `@ScaledMetric` or `.dynamicTypeSize()` modifiers, or use `.font(.body)` style semantic fonts with custom design system mapping.
- **Why**: Users who need larger text get no accommodation. The stub function was never implemented.
- **Files**: `Kuro/Design/KuroDesignSystem.swift:321-334`, all view files using hardcoded font sizes
- **Scope**: Large

### P1-A11Y-2: Add Reduce Motion support
- **What**: Guard all animations with `@Environment(\.accessibilityReduceMotion)`. When true, use `.animation(nil)` or instant transitions.
- **Why**: Users with motion sensitivity get no accommodation. The parallax hero, spring animations, and page transitions all animate regardless.
- **Files**: `Kuro/Design/KuroDesignSystem.swift` (KuroAnimation), all views with animations
- **Scope**: Medium

### P2-A11Y-1: Improve contrast ratios
- **What**: Audit all text with opacity below 0.45 against white backgrounds. `.opacity(0.25)` and `.opacity(0.3)` likely fail WCAG AA (4.5:1 for normal text). Increase minimum opacity to 0.45 for small text, 0.55 for body text.
- **Why**: Several UI elements (chevrons, metadata, tertiary labels) use very low contrast that may be unreadable for low-vision users.
- **Files**: Multiple files — search for `.opacity(0.2)`, `.opacity(0.25)`, `.opacity(0.3)` in foreground colors
- **Scope**: Medium

### P2-A11Y-2: Add VoiceOver labels to interactive elements
- **What**: Add `.accessibilityLabel` to: filter pills, genre chips, stat tiles, collection cards, action buttons, media type toggles.
- **Why**: ~60 annotations across 14 files is a start but many interactive elements are unlabeled. VoiceOver users can't navigate filter states.
- **Files**: Multiple view files (EditorialCollectionView, BrowseViewRefined, ProfileView, etc.)
- **Scope**: Medium

---

## 10. Visual Consistency & Polish

### P0-POLISH-1: Add shimmer animation to skeleton loaders
- **What**: Create a `ShimmerModifier` ViewModifier with a gradient animation and apply to all skeleton/loading rectangles.
- **Why**: Static gray rectangles don't communicate "loading" — they look like broken UI. Shimmer is the modern standard.
- **Files**: `Kuro/ContentView.swift` (LoadingStateViewNew, SophisticatedCardLoading, CollectionCardLoading, DiscoverCardLoading), potentially new `Kuro/Views/ShimmerModifier.swift`
- **Scope**: Small

### P2-POLISH-1: Consolidate design token usage
- **What**: Replace all raw `.system(size: N, weight: W)` calls with KuroDesignSystem font tokens. Audit with grep for `.system(size:` and replace with appropriate `.kuroBody()`, `.kuroCaption()`, etc.
- **Why**: ContentView.swift alone has 30+ raw font declarations. AuthView, SettingsView, and some ContentView components don't use the design system at all, breaking visual consistency.
- **Files**: `Kuro/ContentView.swift`, `Kuro/Views/AuthView.swift`, `Kuro/Views/SettingsView.swift`
- **Scope**: Medium

### P3-POLISH-1: Full dark mode support
- **What**: Define a dark palette in KuroDesignSystem (invert black/white opacities, adjust material backgrounds). Remove `.preferredColorScheme(.light)` from KuroApp.swift. Replace all hardcoded `Color.white` with `Color.kuroBackground`.
- **Why**: Dark mode is explicitly disabled. ConciergeComponents has partial dark mode code suggesting it was started. Many users prefer dark mode, especially for media consumption apps.
- **Files**: `Kuro/Design/KuroDesignSystem.swift`, `Kuro/KuroApp.swift:31`, all views with hardcoded Color.white
- **Scope**: Large

---

## Implementation Roadmap

### Phase 1: App Store Blockers (P1-AUTH-1, P1-AUTH-2, P1-AUTH-3)
Apple Sign In, account deletion, and password reset are hard requirements. Do these first.

### Phase 2: Quick Wins Sprint (all P0 items)
Ship in one sprint — high impact, low effort:
- P0-NAV-1: Add navigation dots/pill strip (most impactful single change)
- P0-NAV-2: Reduce splash delay 2s -> 1s
- P0-DISC-1: Fix perpetual "Connecting..." empty state
- P0-DISC-2: Deduplicate genre chips between Discover/Browse
- P0-AUTH-1: Remove dead SettingsView
- P0-AUTH-2: Add sync success toast
- P0-CONC-1: Better Concierge first-time text
- P0-CLUB-1: Club activity indicator
- P0-LIST-1: Long-press quick-add context menus
- P0-POLISH-1: Shimmer loaders

### Phase 3: Onboarding & First-Run (P1-ONBOARD-1, P1-CONC-1)
First-launch walkthrough + guided Concierge tutorial. These compound: users who understand the app retain better.

### Phase 4: Navigation Architecture (P1-NAV-1, P1-NAV-2, P1-NAV-3, P1-NAV-4)
This is a decision point — choose a consolidation strategy:
- Merge Browse into Discover (filter toggle mode)
- Make Search a global overlay
- Consider Concierge as sheet/overlay vs tab
- Move Clubs under Profile (if reducing tabs)
- Validate with user testing before committing

### Phase 5: Core UX Improvements (P1-LIST, P1-DISC, P1-DETAIL)
- Episode increment from Collection
- Sort options for Collection
- Collection empty state with CTA
- Deduplicate Search categories with Discover rails
- External links in detail views
- Sharing support

### Phase 6: Engagement & Social (P1-CLUB)
- Club invite links / QR codes
- Club discussions / reactions

### Phase 7: Accessibility & Polish (P1-A11Y, P2-*)
- Dynamic Type (actually implement the stub)
- Reduce Motion support
- Contrast ratio fixes
- VoiceOver label audit
- Design token consolidation
- Gesture conflict refactoring

### Phase 8: Future (P3-*)
- Dark mode
- Bulk operations
- Detail view unification
- Profile customization

---

## Summary Statistics (post-validation)

| Status | Count |
|--------|-------|
| Implemented (no work needed) | 4 |
| Partial (gap-fill only) | 12 |
| Not implemented | 31 |
| **Remaining work items** | **43** |

---

## Metrics to Track

| Metric | Baseline | Target |
|--------|----------|--------|
| Time to first add-to-list (new user) | Unknown (no onboarding) | < 60 seconds |
| Sections discovered per session | ~2-3 (no positional indicator) | 4+ |
| Concierge usage rate | Unknown | 40%+ of sessions |
| Club creation rate | Unknown | 10%+ of auth users |
| Accessibility score (Xcode audit) | Low (stub Dynamic Type) | 90%+ |
| App Store review approval | Blocked (no Apple Sign In, no account deletion) | Approved |
| Search-to-add conversion | Unknown | 25%+ of searches lead to list add |
| Session duration | Unknown | 5+ min average |
