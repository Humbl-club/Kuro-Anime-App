# Screens lane: native screen map and adaptivity/polish audit

**Date:** 2026-11-01. **Branch:** `kuro/overnight-2026-11-01` (clean at d8aeae7). **Lane:** read-only (screens).
**Author persona:** Senior iOS Engineer (SwiftUI layout, adaptivity, accessibility, HIG).

## How this audit was done, and what it is not

- **Static source review only.** Nothing was built, run, installed or screenshotted. The behaviour described at 320/375/390/430 pt, at the largest Dynamic Type sizes and in landscape is **inferred from code**, not observed. Every such claim should be checked in the Simulator before a fix is merged.
- **Coverage.** I inventoried all 75 Swift files in `Kuro/Views/**`, plus `Kuro/ContentView.swift`, `Kuro/KuroApp.swift` and `Kuro/Views/Routing/KuroRoutes.swift`. I read these in full or in large part: ContentView, KuroApp, KuroRoutes, HomeView, HomePagePicture, the anime half of SeriesDetailViews, TastePicksView, OnboardingView, AuthView lines 1–715, ProfileView lines 1–330, MediaDetailSheet and KuroSceneryLoop. I read targeted ranges of EditorialDiscoverView, EditorialCollectionView, ClubsView, AddToListSheet, EditorialCollectionComponents and AnimeDetailView. Everything else is covered through per-file grep metrics (fixed fonts, fixed frames, raw colours, accessibility modifiers, Reduce Motion, Dynamic Type, keyboard handling) and the inventory below. Those screens are marked **metrics-only** where I make a claim about them.
- **Line numbers** are `file:line` at d8aeae7.
- **Heuristic caveat.** I flagged icon-only buttons without labels with a script, and several SF Symbols carry default VoiceOver labels. Treat those items as "verify with Accessibility Inspector". The ones I confirmed by reading are marked **confirmed**.
- **Severity scale.**
  - **Blocker:** stops a class of users from using the app, or is likely to block App Store review.
  - **High:** a visible defect or a policy/brand violation on a primary path.
  - **Medium:** degraded quality or adaptivity on a real path.
  - **Low:** polish, consistency or dead code.

---

## 1. Navigation model (what users can actually reach)

### 1.1 Pager orders

`KuroMainView.Section.pagerOrder` (`Kuro/ContentView.swift:140-146`):

| Configuration | Pages, left to right | Who sees it |
|---|---|---|
| `series_home_native_v1` effective. It also needs `series_foundation_v1` and post-sign-in hydration (`Kuro/Services/FeatureFlags.swift:57-58`) | **Taste ← Home → Discover → Collection → Clubs** | Debug simulator only, via `--ff-on`. Both `series_*` flags were last recorded at 0% (CURRENT_APP_STATE.md:914). This is the **target** layout. |
| `taste_deck_v1` on (100%) | **Taste ← Discover → Browse → Collection → Clubs** | **Every production install today** |
| Both flags off | Concierge ← Discover → Browse → Collection → Clubs | Legacy rollback only |

- **The Taste page is always `TastePicksView`**, under both the target and the live order (`Kuro/ContentView.swift:659-661`). The 1,304-line `TasteDeckView` is never constructed (see §8). Several sources still say "Taste Deck at index 0": CLAUDE.md, CURRENT_APP_STATE.md:930-939 and the onboarding copy (`Kuro/Views/OnboardingView.swift:158-163`). All three are stale.
- **Launch selection.** The pager starts on Discover (`ContentView.swift:149`). It switches to Home when the series flag is on (`ContentView.swift:338-341`, `499-506`).
- **Mounting.** The pager mounts the current page and its neighbours, and keeps every page it has visited (`ContentView.swift:650-680`).
- **Swipe paging.** Paging is a root `DragGesture` (`ContentView.swift:343-417`). There is no `TabView`, no tab bar and no accessibility paging action (see H-1).

### 1.2 Presentation contexts and route presenters

These views install `.routePresenter()`:
- the app root (`ContentView.swift:42`)
- the Concierge sheet from the header (`ContentView.swift:527`)
- `EditorialSearchView:176`
- `ClubDetailView:259`
- `SeriesAnimeDetailView:54` and `SeriesMangaDetailView:379`
- `HomeSeasonOverview` (`HomeView.swift:70`)
- the Discover full-section sheets (`EditorialDiscoverView.swift:1259`, `1323`)
- the Concierge sheet from Profile (`ProfileView.swift:211`)
- `AnimeDetailView:311` and `MangaDetailView:307`
- the four entity sheets (`EntityDetailSheets.swift:207`, `310`, `401`, `485`)

I cross-checked every file that reads `\.kuroRoutes` against these presenters:
- **No sheet root shows a routed leaf without its own presenter.** `AddToListSheet`, `ImportWorkflowSheet`, `ClubDetailSheets`, `ImportSourceChooser`, `ConciergeAniListImportSheet` and Profile's Clubs sheet contain no route readers. `ClubsView` presents `ClubDetailView` directly, and that view installs its own presenter.
- One deviation: `AdaptationPathSection` constructs `MediaDetailSheet` directly instead of using a route (`AdaptationPathSection.swift:59-62`, `347-350`). It works, because the detail installs a presenter, but it does not follow the routing pattern (Low).

### 1.3 Gates before the pager

`RootView` (`Kuro/KuroApp.swift:120-191`) shows, in order:
1. a configuration-error screen (`138-154`)
2. an auth-bootstrapping splash (`155-166`)
3. `ContentView`, keyed by user id (`167-171`), or `AuthView` (`173`)

After that, `KuroRootView` overlays `KuroLaunchView` for about 0.4 s (`ContentView.swift:44-68`, `72-103`). `OnboardingView` is a `fullScreenCover` inside the signed-in tree (`ContentView.swift:530-538`), keyed on a per-device UserDefaults flag (`OnboardingView.swift:137-141`, `248-251`).

---

## 2. Full screen map

**Column key.**
- **Live** = reachable in today's production (`taste_deck_v1` order, legacy detail bodies).
- **Series** = reachable with `series_home_native_v1` on.
- **Owner** = `@Environment` capability owners the screen reads.
- "—" = not reachable in that configuration.

### 2.1 Gates, chrome, pager pages

| # | Screen | File | Reached via | Owner(s) | Live | Series |
|---|---|---|---|---|---|---|
| G1 | Config-error screen | `KuroApp.swift:138-154` | `identity.configError != nil` | IdentityStore | yes | yes |
| G2 | Auth-bootstrap splash ("KURO" + spinner) | `KuroApp.swift:155-166` | `identity.isAuthBootstrapping` | IdentityStore | yes | yes |
| G3 | Offline strip ("OFFLINE", 9 pt) | `KuroApp.swift:127-135` | `!networkMonitor.isConnected`, above everything | NetworkMonitor | yes | yes |
| G4 | **AuthView: Welcome** (scenery + "Get started" + Sign in with Apple) | `AuthView.swift:143-227` | Signed out | Identity, AuthService, SessionController, DiscoveryStore | yes | yes |
| G5 | **AuthView: Email form** (sign in / create account tabs) | `AuthView.swift:283-436` | "Get started", Apple failure | same | yes | yes |
| G6 | AuthView: "Genie" welcome (`AuthGenieHero`, about 670 lines) | `AuthView.swift:231-279`, `715-1388` | DEBUG launch arg `-AuthGenieHero` only (`24-26`) | DiscoveryStore (covers) | — (debug only) | — |
| G7 | Launch overlay `KuroLaunchView` ("KURO / CURATED ANIME") | `ContentView.swift:72-103` | Every signed-in mount | none | yes | yes |
| G8 | **OnboardingView** (5-card pager) | `OnboardingView.swift:11-142` | fullScreenCover on first run (`ContentView.swift:530`) | FeatureFlags | yes | yes |
| C1 | Header `KuroHeaderNew` (wordmark, section window, dots, search, profile menu) | `ContentView.swift:705-980` | Always above the pager | Identity, Session, Clubs, Flags | yes | yes |
| C2 | Transient banner | `KuroTransientBanner.swift`, `ContentView.swift:539-548` | `BannerCenter.message` | BannerCenter | yes | yes |
| P1 | **Taste page: `TastePicksView`** | `TastePicksView.swift:7-158` | Pager index 0 | DiscoveryStore, LibraryStore | yes | yes |
| P2 | **Home: `HomeView`** (medium switch, invitation, anime scenes / manga books, Coming up, calendar, private club) | `Home/HomeView.swift:7-1165` | Pager index 1 (series) | HomeStore, LibraryStore, LibraryActions, ImportsService | — | yes |
| P2a | Home invitation picture behind header | `HomePagePicture.swift`, `ContentView.swift:252-258`, `684-702` | Empty selected medium | HomeStore | — | yes |
| P3 | **Discover: `EditorialDiscoverView`** | `EditorialDiscoverView.swift:9-645` | Pager | DiscoveryStore, CatalogStore, TasteStore, Library, Social, Flags, Network | yes | yes |
| P4 | **Browse: `BrowseView`** | `BrowseView.swift:7-580` | Pager (live only) | DiscoveryStore, Social, Flags, Network | yes | — **(unreachable; no other entry point)** |
| P5 | **Collection: `EditorialCollectionView`**, legacy grid/list | `EditorialCollectionView.swift:9-975`, `EditorialCollectionComponents.swift` | Pager | CollectionStore, LibraryStore, LibraryActions, Social, Availability, FM, Network | yes | — |
| P5s | **Collection, series list** (`seriesCollection`) | `EditorialCollectionView.swift:594-677` | Pager when the series flag is on | CollectionStore, HomeStore | — | yes |
| P6 | **Clubs: `ClubsView`** | `ClubsView.swift:8-198` | Pager; Profile → Clubs sheet; `kuro://join/<code>` | ClubsStore | yes | yes |
| P7 | Concierge page `ConciergeView` | `ConciergeView.swift:15` | Pager only when both flags are off | Concierge, Catalog, Collection, Imports, Library, FM, Telemetry | — (sheet only) | — (sheet only) |

### 2.2 Sheets and covers

| # | Screen | File | Reached via | Owner(s) | Live | Series |
|---|---|---|---|---|---|---|
| S1 | **Profile** (identity band, Library, Imports, Pending, Clubs, Preferences, Account) | `ProfileView.swift:8-755` | Header avatar menu → "Profile" (`ContentView.swift:896-899`, `430-446`); Home invitation `onOpenImport` | Identity, Auth, Session, Library, Collection, Releases, Availability, Clubs, Imports, Flags | yes | yes |
| S1a | Streaming service picker | `ProfileView.swift:826-979` | Profile preferences (`500`); only with `streaming_availability_v1` (0%) | Availability | flag-gated | flag-gated |
| S1b | Profile import result card, freshness card, import history | `ProfileView.swift:980-1127`; `ProfileFreshnessCard.swift`; `ImportHistorySection.swift` | Inside Profile | Imports, Availability | yes | yes |
| S1c | Clubs in a sheet | `ProfileView.swift:151-167` | Profile → Clubs row | ClubsStore | yes | yes |
| S2 | **Search** `EditorialSearchView` | `EditorialSearchView.swift:16-233` | Header magnifier (`ContentView.swift:447-462`) | SearchStore, Library, LibraryActions, Banner | yes | yes |
| S3 | **Concierge sheet** | `ContentView.swift:516-529`; `ProfileView.swift:201-213` | Profile row, `kuro://concierge`, `--kuro-start=concierge` | (as P7) | yes | yes |
| S3a | Concierge AniList import sheet | `ConciergeView+AniListImport.swift:5` | Concierge, Profile, ImportSourceChooser | ImportsService | yes | yes |
| S3b | Why-this sheet | `ConciergeRecommendationRails.swift:334` | Concierge rec rail | — | yes | yes |
| S4 | **ImportSourceChooser** (AniList / MAL / XML) | `ImportSourceChooser.swift:9-230` | Home invitation "Import your list" (`HomeView.swift:71-76`) | Imports, Library, Collection, Releases, Flags | — | yes |
| S5 | **ImportWorkflowSheet** (+ `ImportCatalogMatchPicker`) | `ImportWorkflowSheet.swift:12`; `ImportCatalogMatchPicker.swift:6` | Home resume banner, Profile, Chooser, Concierge | ImportsService, SearchStore | yes | yes |
| S6 | Home season overview | `HomeView.swift:1211-1270` | Home season chip/tab | HomeStore | — | yes |
| S7 | **Media detail loader** `MediaDetailSheet` | `DetailPages/MediaDetailSheet.swift:4-147` | `routes.openMedia`, `kuro://anime|manga/<id>` | CatalogStore | yes | yes |
| S7a | **Legacy `AnimeDetailView` body** | `DetailPages/AnimeDetailView.swift:58-311` (+ sections to `1521`) | S7 when the series flag is off | Catalog, Recs, FM, Flags, Library, Availability, Outbound | yes | — |
| S7b | **Legacy `MangaDetailView` body** | `DetailPages/MangaDetailView.swift` (1461 lines) | same | same | yes | — |
| S7c | **`SeriesAnimeDetailView`** | `Home/SeriesDetailViews.swift:7-338` | S7 when the series flag is on (`AnimeDetailView.swift:51-55`) | HomeStore, Library, LibraryActions | — | yes |
| S7d | **`SeriesMangaDetailView`** | `Home/SeriesDetailViews.swift:341-570` | `MangaDetailView.swift:53` | same | — | yes |
| S7e | Series unit chooser | `SeriesDetailViews.swift:786`, `800-956` | Series bookmark "list.number" | HomeStore | — | yes |
| S8 | Episode list / Chapter list sheets | `AnimeDetailView.swift:1088`, `858`; `MangaDetailView.swift:931`, `727` | Legacy detail "see all" | Catalog | yes | — |
| S9 | QuickVerdict picker | `QuickVerdictActionCard.swift:511`; `AnimeDetailView.swift:1424`; `MangaDetailView.swift:1368` | Legacy detail action bar | Library, LibraryActions | yes | — |
| S9a | QuickVerdict action sheet | `QuickVerdictActionCard.swift:481`; `EditorialCollectionComponents.swift:594`, `807` | Legacy collection card | same | yes | — |
| S10 | **ProviderSelectionSheet** (where to watch/read) | `DetailPages/ProviderLinkViews.swift:10-262`; `AnimeDetailView.swift:1427` | Legacy detail action bar | Availability (via parent) | yes | — |
| S11 | Cast directory, Character / Staff / Studio / Author sheets, All credits | `CastSection.swift:204`; `EntityDetailSheets.swift:114-490`; `CreditsSection.swift:172` | Legacy detail cast/credits (`credits_cast_v1`, 100%) | CatalogStore | yes | — (series detail uses `SeriesCast`/`SeriesPrincipals` instead) |
| S12 | Franchise path sheet | `AdaptationPathSection.swift:294` | Legacy detail ladder | (parent) | yes | — |
| S13 | Next-pick detail (direct sheet) | `AnimeDetailView.swift:600`; `MangaDetailView.swift:479` | Legacy detail "next pick" | — | yes | — |
| S14 | **AddToListSheet** (tracking editor) | `AddToListSheet.swift:7-565` | `routes.presentTrackingEditor` (cards, Taste, series detail, collection) | Library, LibraryActions, Network | yes | yes |
| S15 | **AddToClubRailSheet** | `SharedCards/AddToClubRailSheet.swift:19` | `routes.presentAddToClub` (card context menus), ClubActivitySection | Clubs, Flags, Telemetry | yes | yes |
| S16 | **ClubDetailView** (Rails / This Week / Polls) | `ClubDetailView.swift:18-634` + Shell/Tab components | ClubsView card; `kuro://club/<id>` | Clubs, Flags, Telemetry, Network, Availability | yes | yes |
| S16a | Club settings, Add item to rail, Create rail, Create poll | `ClubDetailSheets.swift:6`, `339`; `ClubCreateSheets.swift:6`, `144` | Club detail | Clubs, Identity, Search | yes | yes |
| S17 | Create club / Join club | `ClubsView.swift:591`, `753` | Clubs actions; `kuro://join/<code>` | Clubs | yes | yes |
| S18 | Browse filters sheet | `BrowseComponents.swift:422`; `BrowseView.swift:287` | Browse | — | yes | — |
| S19 | Discover full-section sheets (`FullSectionView`, `FullMangaSectionView`) | `EditorialDiscoverView.swift:400`, `~1200-1327` | Discover "See all" | Discovery | yes | yes |

### 2.3 Major shared components

| Component | File | Used by |
|---|---|---|
| `KuroCompactCard`, `KuroHeroCard`, `KuroScoreBadge` | `KuroRefinedCard.swift` | Discover, detail "similar", entity rails |
| `CompactAnimeCard` | `SharedCards/CompactAnimeCard.swift` | TastePicks, Discover manga rails |
| `GridAnimeCard` | `SharedCards/GridAnimeCard.swift` | Browse grid, Discover dense sections |
| `DiscoverOneThingCard`, skeleton | `DiscoverOneThingCard.swift` | Discover hero |
| `CollectionGridCard`, `CollectionListRow`, `CollectionBatchBar` | `EditorialCollectionComponents.swift` | Legacy Collection |
| `NextEpisodeCountdown` | `CountdownTimer.swift` | Legacy Collection card (`EditorialCollectionComponents.swift:546`) |
| `KuroSceneryLoop` | `KuroSceneryLoop.swift` | Auth welcome, Home invitation, Profile header |
| `KuroToast`, `KuroTransientBanner`, `KuroGlassPill`, `KuroConciergeMark`, `KuroLoadMoreSentinel` | various | various |
| Club/Friends activity sections | `DetailPages/ClubActivitySection.swift`, `FriendsActivitySection.swift` | Legacy detail. Friends section is also used in series detail (`SeriesDetailViews.swift:305`) |

### 2.4 Unreachable everywhere (dead or legacy)

| Item | Evidence |
|---|---|
| `TasteDeckView` (1,304 lines) | No construction outside its file. ContentView renders `TastePicksView` for `.taste` (`ContentView.swift:660`). |
| `TasteLeaningsSheet`, `TasteDeckCardSurface` | Only reachable from `TasteDeckView` (`TasteDeckView.swift:616-618`). Previews only otherwise. |
| `GenrePickerSheet` | `EditorialDiscoverView.swift:1328`, zero references. |
| `HomeView.inkIndex` / `animePaper` / `animeIndexRow` / `mangaPaper` / `mangaIndexCover` | `HomeView.swift:689-827`, never called. |
| `AuthGenieHero` stack | `AuthView.swift:715-1388`, DEBUG-only path (`AuthView.swift:24-26`). |
| `BrowseView` and children | Unreachable when the series flag is on. No entry point except the pager. |
| Concierge as a page | Only when both flags are off. |

---

## 3. Cross-cutting findings (apply to many screens)

### H-1 [Blocker] The header hides Search and Profile from VoiceOver, and the pager cannot be changed with assistive tech

- The header's outer HStack has `.accessibilityElement(children: .ignore)` with label "Section navigation" (`ContentView.swift:916-922`; the modifier is at `919`). This collapses the **Search** button (`882-894`) and the **Profile menu** (`896-913`) into one non-interactive element. Their own `accessibilityLabel`s (`893`, `911`) are discarded.
- The centre block repeats the pattern (`872`).
- There is no `accessibilityAdjustableAction`, `accessibilityScrollAction` or custom action anywhere in ContentView (grep: none).
- The page dots are `accessibilityHidden` (`869`).
- Paging is a raw drag gesture (`343-417`).
- **Impact:** VoiceOver and Switch Control users cannot reach Search, Profile or Sign Out, and cannot move between Taste / Home / Discover / Collection / Clubs. A VoiceOver three-finger swipe will not page a custom HStack offset.
- This affects both the live and the series configuration. It is likely to fail App Store accessibility expectations and any accessibility audit.
- **Fix direction:**
  - Remove `children: .ignore` on the outer row.
  - Make the section window an adjustable element (increment/decrement → `selection`), or add a real `TabView`/tab bar.
  - Keep the buttons as separate elements.

### H-2 [High] The type system caps Dynamic Type and may not react to live size changes

- Every Kuro font role computes a fixed point size through `UIFontMetrics.scaledValue` inside a static function (`Kuro/Design/KuroDesignSystem.swift:114-139`, `144-229`). The roles are clamped:
  - `kuroBody` ≤ 26 pt (AX5 body is about 53 pt)
  - `kuroCaption` ≤ 20
  - `kuroMicro` ≤ 16
  - `kuroNavigation` ≤ 18
  - `kuroTitle` ≤ 32
- Two consequences:
  1. Accessibility sizes are only partly honoured.
  2. **(Uncertain, needs a runtime check.)** The size is read from UIKit trait state, not from SwiftUI's `\.dynamicTypeSize` environment, so views that don't otherwise invalidate may keep the old size after the user changes text size while the app is running.
- On top of this there are **about 200 hard-coded `.system(size:)` fonts in views** that never scale (full list in §9). The worst concentrations:
  - AuthView (21)
  - EditorialDiscoverView (20)
  - HomeView (18)
  - KuroRefinedCard (16, the Discover cards)
  - EditorialSearchView (12)
  - EditorialCollectionView (12)
  - MangaDetailView (10)
  - AnimeDetailView (9)
  - AddToListSheet (8)
- **Fix direction:** build the roles on `Font.custom(_:size:relativeTo:)` or `.system(.body, design:)` with `.dynamicTypeSize(...)` limits per container, and replace view-level literals with roles.

### H-3 [High] Fixed-height containers clip text at large sizes

| Location | Problem |
|---|---|
| Header `.frame(height: 54)` (`ContentView.swift:971`) | The section title width is **measured with a fixed 11 pt UIFont** (`745-752`, used at `927`, `934-935`) but drawn with the scaled `kuroNavigation` font (up to 18 pt) inside a clip (`793-797`). Long titles ("COLLECTION", "CONCIERGE") will clip at larger text sizes. |
| Profile identity header `.frame(height: 280)` + `.clipped()` (`ProfileView.swift:246-248`) | Contains a 72 pt initial (`231`), `kuroDisplay` (up to 72 pt) and the account caption. At AX sizes the email and headline are cut off. |
| AddToListSheet hero 280 pt (`AddToListSheet.swift:241`, `280`) | — |
| Onboarding `TabView.frame(maxHeight: 420)` (`OnboardingView.swift:43`) | Headline + body + icon overflow at AX sizes. There is no ScrollView. |
| Series anime artwork `.aspectRatio(1.9)` + `.clipped()` (`SeriesDetailViews.swift:118-123`) | Overlays a `kuroDisplay` title and status (`95-107`). Long German titles at large sizes get clipped. |
| Auth CTAs `.frame(height: 54)` with 17 pt fixed text (`AuthView.swift:199-204`, `403-409`) | Acceptable only because the text is fixed-size, which is itself H-2. |

### H-4 [High] Landscape and iPad are declared but not designed for

- `Info.plist:61-66` allows iPhone landscape. `TARGETED_DEVICE_FAMILY = "1,2"` (`Kuro.xcodeproj/project.pbxproj:468`, `505`, …) ships an iPad app.
- Examples:
  - Home `sceneryHeight = max(520, width * 1.45)` (`HomeView.swift:183-186`). On an iPhone in landscape (width about 844–932) this gives a minimum content height over 1,200 pt, and an iPad gives about 1,900 pt.
  - Only Discover caps content width (hero ≤ 520, `EditorialDiscoverView.swift:65-71`). Home, Collection, Clubs, Profile, Auth and the details run edge to edge on iPad.
  - `KuroDesignSpacing.adaptive` / `ResponsiveLayout` scale by width breakpoints (`KuroDesignSystem.swift:287-295`, `493-520`). That is not a layout strategy for regular size classes.
- App Store submission for an iPad-enabled build needs iPad screenshots and passes iPad review.
- **Decision needed** (open question): lock iPhone to portrait and drop iPad (fastest path to a polished v1), or add max-width containers and regular-width layouts.

### H-5 [High] Brand and palette are inconsistent across surfaces

The 2026-10-08 plan (`docs/plans/2026-10-08-native-design-polish.md:26-38`) asks for white/neutral surfaces with no yellow or green cast, token-only colours and monochrome statuses.

- **Home uses green-cast hex literals** instead of tokens. `DCDDD7`, `D7D9D2` and `D7DAD2` are paper strokes; `60645E`, `30352E`, `2C322F` and `252B28` are inks and fills. Locations: `HomeView.swift:564`, `606`, `614`, `628`, `663`, `666`, `670`, `1067`.
- **Auth has its own palette.**
  - Warm ink `Color(red:22,20,18)` and a **red accent** (`AuthView.swift:53-54`). The accent is used for the selected-tab underline (`448`), valid checkmarks (`572`, `583`), "Forgot password?" (`420`) and success text (`657`). CLAUDE.md allows red only for destructive actions.
  - **Blue focus colours**: label, fill and stroke (`488`, `509-511`, `516-518`).
  - `Color(white:0.55)` legal text at 11 pt (`217-219`) is about 3.4:1 contrast and fails WCAG AA.
- **Provider brand marks are coloured**: Crunchyroll orange, Netflix red, Prime blue, Hulu green and others (`ProviderLinkViews.swift:239-249`). Currently behind `streaming_availability_v1` (0%) and the legacy detail. Open question: are third-party brand colours an accepted exception?
- **Red is used for non-destructive errors** with literals instead of the `kuroError` token (`KuroDesignSystem.swift:46`). There are about 20 sites: `ClubsView.swift:656`, `800`; `ClubDetailSheets.swift:69`, `545-565`; `ClubCreateSheets.swift:65`, `206`, `233`; `FriendsActivitySection.swift:90`, `247`; `KuroToast.swift:32`; `AddToListSheet.swift:67`, `540`; `QuickVerdictActionCard.swift:244-284`, `596`; `EditorialCollectionComponents.swift:859-866`; `ConciergeEditorialShell.swift:26`; `AddToClubRailSheet.swift:106`.
- **Raw `Color.black/white.opacity(...)` instead of tokens** is widespread. Raw-colour counts: ClubsView 39, AuthView 34, EditorialDiscoverView 33, EditorialSearchView 29, ClubDetailView 25, FriendsActivitySection 21, HomeView 19.
- **Gutters are inconsistent**: `EditorialLayout.marginEditorial = 24` (`KuroDesignSystem.swift:713`, used by Collection) against 20 everywhere else (the plan says 20).
- **Two canvas tokens coexist**: `kuroBackground` (`systemBackground`, `KuroDesignSystem.swift:64`) and `kuroCanvasPage` (`#FFFFFF`, `98`). They match in light mode, but the semantic split is unclear.
- No cream/yellow page surface remains in Swift. The plan's `FFFEF8` is gone (grep for `FFFEF8|F5F5F0|cream` finds only comments, `AuthView.swift:961`, `1242`).

### H-6 [High] Localization is ad hoc

- There is no String Catalog usage. Screens branch on `isGerman` / `isGermanLocale` and supply hand-written pairs: HomeView, Onboarding, Profile, Collection, ImportSourceChooser and others. Many strings on the same screens are English-only. Home examples: "Loading your Home" (`HomeView.swift:269`), "Try again" (`274`), "More" (`421`), "Coming up" captions (`709-712`), "Dates to come…" (`931`, `957-958`), "Club activity needs a fresh connection." (`1020`), the conflict copy (`402-416`), and all of the series detail.
- **Home dates are forced to English.** `HomeView.swift:1118-1120` uses an `en_US_POSIX` `DateFormatter` with the pattern `"EEE, d MMM"`, so German users see "Mon, 3 Nov".
- Auth, Clubs, Discover, Search and Taste are English-only.

### H-7 [Medium] Keyboard handling is minimal

- Only three focus/keyboard affordances exist in all of Views:
  - `scrollDismissesKeyboard` in Concierge (`ConciergeView.swift:456`)
  - `@FocusState` in the Search bar (`EditorialSearchView.swift:309`, `321`) and the AniList username field (`ConciergeView+AniListImport.swift:34`)
  - one `onSubmit` in Collection search (`EditorialCollectionView.swift:540`)
- **Auth tracks focus with `@State` + `onTapGesture`** (`AuthView.swift:38`, `500`). The focus styling therefore doesn't follow real keyboard focus. There's no Next/Go `submitLabel`, no email→password chaining, and no interactive dismiss.
- Club create/join, AddToList notes and club settings have no focus management (metrics-only).

### H-8 [Medium] Touch targets under 44 pt (confirmed by reading)

| Control | Size | Location |
|---|---|---|
| Header search/profile circles | 32×32, no `contentShape` expansion | `ContentView.swift:806-812` |
| AddToListSheet close (no label), +/− steppers | 32×32 | `AddToListSheet.swift:137-144`, `392-412` |
| Collection header search toggle and grid/list toggle | Bare 15 pt / 13 pt glyphs, no frame, no `accessibilityLabel` | `EditorialCollectionView.swift:333-337`, `409-414` |
| Collection verdict filter labels | 9 pt at 0.35 opacity | `EditorialCollectionView.swift:363-366` |
| Discover TYPE menu | 9 pt glyph + 9 pt text at 0.35 opacity | `EditorialDiscoverView.swift:129-138` |
| Onboarding "Skip" | `kuroCaption` text only, no min frame | `OnboardingView.swift:78-83`, `101-106` |
| Auth password eye toggle | No label, no frame | `AuthView.swift:366-371` |
| Legacy detail action bar circles | 38×38 | `AnimeDetailView.swift:1336`, `1393`; `MangaDetailView.swift:1280`, `1337` |

- Heuristic list of icon buttons without labels (verify): `AddToListSheet:138,396,407`; `AuthView:293,367`; `ClubCreateSheets:204`; `ClubDetailSheets:443`; `ClubDetailTabComponents:404`; `ConciergeComponents:52,574,900,1544`; `AnimeDetailView:1348,1367`; `MangaDetailView:1292,1311`; `EditorialCollectionComponents:722`; `EditorialCollectionView:334,410,465,493,521,562`; `EditorialDiscoverView:131,1252,1316`; `EditorialSearchView:330`; `KuroGlass:100`; `ProfileFreshnessCard:63`; `ProfileView:963,1025`; `QuickVerdictActionCard:214`; `ContentView:454` (the search sheet's xmark).
- Accessibility-modifier density is very low in several large files:
  - ClubsView: 4 in 884 lines
  - ClubDetailView: 3 in 1,100
  - AddToListSheet: 3 in 591
  - OnboardingView: 0
  - ProviderLinkViews: 0
  - EntityDetailSheets: 0
  - ClubActivitySection: 0
  - AddToClubRailSheet: 0

### H-9 [Medium] Reduce Motion is honoured only in a few places

- Reduce Motion is read in HomeView (5 sites), TasteDeckView (dead), AuthView, ProfileView, KuroSceneryLoop and the pager animation (`ContentView.swift:646`).
- It is **not** read in:
  - Onboarding: appear offset and page animation (`OnboardingView.swift:127-134`, `61-63`)
  - the header title slide (`ContentView.swift:941-958`)
  - the header button rotation/scale (`1012-1018`)
  - Auth's `AuthStaggerEnter` spring (`AuthView.swift:688-701`)
  - Discover, Collection, Clubs, Club detail, Search and AddToList (0 reads each)
- The edge bounce on the first/last page (`ContentView.swift:396-405`) animates regardless.

### H-10 [Medium] Empty, loading, error and offline states are uneven

| Screen | State handling |
|---|---|
| Discover | Good: skeleton, offline error with retry, empty, "SHOWING CACHED DATA" (`EditorialDiscoverView.swift:73-118`) |
| Browse | Good: skeleton / offline error / empty / pagination skeleton (`BrowseView.swift:193-266`) |
| Club detail | Good: explicit offline messaging (`ClubDetailView.swift:89-101`) |
| Legacy Collection | Good: error and offline variants (`EditorialCollectionView.swift:680-720`) |
| **Clubs list** | No error state. A failed or offline `fetchMyClubs` falls through to the "create your first club" empty state (`ClubsView.swift:34-43`), which is misleading. |
| **Home** | `.failed(message)` shows the raw store message and "Try again" (`HomeView.swift:271-276`). There's no offline variant and no skeleton (plain `ProgressView("Loading your Home")`, `269-270`). |
| **TastePicks** | Plain `ProgressView`; failure is one line plus a bare "Retry" text button (`TastePicksView.swift:33-48`). |
| **Series Collection** | The raw error string and the 4-word empty line "Nothing in this collection yet." (`EditorialCollectionView.swift:609-615`). No guidance, no CTA. |
| **Media detail loader** | `error.localizedDescription` shown to users (`MediaDetailSheet.swift:80-82`, `141-143`). |
| **Series detail** | Internal-sounding absence copy, which the plan says to replace (plan:99): "This entry is not in an approved season group." (`SeriesDetailViews.swift:157`), "Chapter boundaries unverified." (`260`), "Find on Spotify · unmatched tracks are searches, not identified recordings." (`291`), "No spoiler-light premise is on file for this book." (`457`), "No approved season grouping." (`HomeView.swift:1224`). |

### H-11 [Medium] Global offline and launch chrome is off-brand

- The OFFLINE strip is fixed at 9 pt with system `.secondary` on `Color.primary.opacity(0.06)` (`KuroApp.swift:127-135`).
- The config-error and bootstrapping screens use `Color(.systemBackground)` and fixed 11 pt text (`KuroApp.swift:140-165`).
- **Three different brand moments in a row on launch:**
  1. the empty `UILaunchScreen` (`Info.plist:57-58`)
  2. the "KURO" + spinner bootstrap
  3. `KuroLaunchView` "KURO / CURATED ANIME" (`ContentView.swift:80-93`), whose subtitle omits manga
- The Auth welcome is a fourth composition (serif "Kuro" + mountains).
- This should become one designed launch → splash → welcome sequence.

---

## 4. Per-screen issue lists

### G4/G5 AuthView (sign in / sign up)

| Sev | Issue | Evidence |
|---|---|---|
| High | Non-monochrome palette on the primary conversion screen: red accent and blue focus colours | `AuthView.swift:53-54`, `420`, `448`, `488`, `509-518`, `572`, `583` |
| High | No Dynamic Type: 21 fixed fonts, including the 33 pt hero and 34 pt headings | `AuthView.swift:180-589` |
| High | "Terms of Service and Privacy Policy" is plain text, not links. Contrast is about 3.4:1 at 11 pt. App Store and GDPR expect reachable policies at sign-up. | `AuthView.swift:217-222`, `268-273` |
| Medium | Focus is not real `@FocusState`; no submit chaining, `submitLabel` or keyboard dismissal | `AuthView.swift:38`, `476-523` |
| Medium | Password-reset success is shown in the red error slot | `AuthView.swift:657` |
| Medium | Welcome copy is "Your next favorite anime…" (manga missing); brand is "Kuro" in serif at 18 pt, unlike the KURO wordmark elsewhere | `AuthView.swift:179-188` |
| Medium | Sign-up has no password confirmation or show-requirements text beyond the "Min 8" hint; status icons have no labels | `AuthView.swift:563-591` |
| Low | `DispatchQueue.main.asyncAfter` for the reveal (project rule prefers cancellable tasks) | `AuthView.swift:121-123` |
| Low | About 670 lines of DEBUG-only Genie hero ship in the binary | `AuthView.swift:715-1388` |
| Low | Back chevron and eye toggle have no explicit labels (SF default may cover chevron.left) | `AuthView.swift:289-300`, `366-371` |

### G8 OnboardingView

| Sev | Issue | Evidence |
|---|---|---|
| **High** | Copy describes features users don't get: the Taste Deck ritual ("pass, know, or love"), which is dead; a Browse page, which doesn't exist under the series order; and no Home. The last CTA "TEACH KURO YOUR TASTE" lands on `TastePicksView`, which is not a teaching ritual. | `OnboardingView.swift:155-200`, `85-99`; `ContentView.swift:530-538`, `660` |
| High | Not branded: generic SF Symbols in grey circles. The plan asks to reuse the welcome's scenery language. | `OnboardingView.swift:213-220`; plan:20 |
| Medium | `maxHeight: 420` TabView, no ScrollView: clips at AX sizes | `OnboardingView.swift:43` |
| Medium | Skip target below 44 pt; dots not accessible; no Reduce Motion | `OnboardingView.swift:78-83`, `46-52`, `127-134` |
| Medium | Collects nothing useful: no medium preference, no import offer, no notification permission for release reminders | whole file |
| Low | Completion flag is per device, not per account | `OnboardingView.swift:139`, `249-250` |

### C1 Header

| Sev | Issue | Evidence |
|---|---|---|
| Blocker | See H-1 | `ContentView.swift:872`, `919` |
| Medium | Title measured at a fixed 11 pt, drawn scaled; 54 pt fixed height | `ContentView.swift:745-752`, `971` |
| Medium | 32 pt icon targets | `ContentView.swift:806-812` |
| Medium | `rootWidth` falls back to a hard-coded 393 (CLAUDE.md DO-NOT #5); swipe-exclusion viewport hard-coded to height 2000 | `ContentView.swift:216-224`, `305-311` |
| Low | Sign Out sits in the avatar menu with no confirmation, next to Profile | `ContentView.swift:896-903` |
| Low | Unseen-clubs badge is a 6 pt dot with no accessible announcement (dots hidden) | `ContentView.swift:858-864` |

### P1 Taste (TastePicksView), visible to all users today

| Sev | Issue | Evidence |
|---|---|---|
| High | Underdesigned primary page: four `CompactAnimeCard`s, each followed by a plain "Add to list" text button. No editorial framing, no imagery hierarchy, no taste feedback loop (the Taste Deck it replaced is dead). | `TastePicksView.swift:22-75` |
| Medium | Loading, failure and empty states are minimal | `TastePicksView.swift:33-48` |
| Medium | ANIME/MANGA switch uses a different grammar from the Home medium switch (caption caps vs. 40 pt heavy serif) | `TastePicksView.swift:80-96` vs `HomeView.swift:225-261` |
| Low | Card width = container − 40 (a full-width compact card); not tuned for 430 pt or iPad | `TastePicksView.swift:24`, `56` |

### P2 Home (series target)

| Sev | Issue | Evidence |
|---|---|---|
| **High** | Fabricated club label fallback "Sunday Club" when the server sends none. The plan forbids invented club content. | `HomeView.swift:1030`; plan:89 |
| High | Green-cast hex palette and fixed fonts throughout the shelf: season tab 7 pt / 17 pt, title 17 pt, progress 9/19/28 pt, keys 15–16 pt | `HomeView.swift:464-466`, `483`, `519`, `583`, `626-636`, `661`, `1084-1098`; hex list in H-5 |
| Medium | "Find your first title" ignores the medium; ContentView's `onFindTitle` just switches to Discover | `HomeView.swift:836`; `ContentView.swift:285-288` |
| Medium | Dates in English only (en_US_POSIX); many strings not localized | `HomeView.swift:1117-1124`; H-6 |
| Medium | `sceneryHeight` depends only on width (min 520) and breaks landscape/iPad | `HomeView.swift:183-186`, `55` |
| Medium | Error/loading states are plain (H-10); conflict UI uses two unstyled buttons | `HomeView.swift:268-276`, `400-419` |
| Medium | Club band uses a dark green-grey fill `252B28` with white text at 0.62 opacity for the kicker (contrast is borderline at micro size) | `HomeView.swift:1027-1029`, `1067` |
| Low | Dead index code, 140 lines | `HomeView.swift:689-827` |
| Low | Medium-switch lettering uses `.system(size: 40/32, .heavy, .serif)` with `minimumScaleFactor(0.6)` instead of a role | `HomeView.swift:227-232` |
| Note | Good: 44 pt progress keys with descriptive labels (`676`, `1113`), Reduce-Motion-aware press style (`1201-1209`), accessibility-size column switch for manga (`551`) and calendar art (`960`, `993`), calendar focus management (`26`, `717`, `935-937`). | — |

### P3 Discover

| Sev | Issue | Evidence |
|---|---|---|
| Medium | 20 fixed fonts, 33 raw colours; section headers at 16/11/12 pt fixed | `EditorialDiscoverView.swift:710-730`, `896-916`, `1048-1068`, `1142-1162` |
| Medium | TYPE filter is a 9 pt, 0.35-opacity menu (contrast and target) | `EditorialDiscoverView.swift:121-140` |
| Medium | Internal-sounding subtitles, e.g. "Gateway picks (high confidence)" | `EditorialDiscoverView.swift:212` |
| Medium | No Reduce Motion reads; "MORE SECTIONS" expansion animates | `EditorialDiscoverView.swift:270-294` |
| Low | Section titles in all caps with a parenthetical "(MANGA)"; anime and manga rails interleave in one stream, while Home separates media with a switch | `EditorialDiscoverView.swift:237` |
| Note | Good: complete state handling; hero width capped at 520. | — |

### P4 Browse (live only)

| Sev | Issue | Evidence |
|---|---|---|
| Medium | Unreachable under the target pager. If Home ships, catalogue browsing with filters disappears unless Browse is re-entered (e.g., from Discover or Search). | `ContentView.swift:140-146` |
| Low | 1 fixed font; otherwise metrics-clean | `BrowseView.swift:199` |

### P5 Collection (legacy) and P5s (series list): the owner's "lists" screen

| Sev | Issue | Evidence |
|---|---|---|
| **High** | The series Collection is a bare text list: the series title as a header, child titles as text rows, and a numeric progress button. No artwork, status grouping, sort, countdowns or "next episode/chapter" date. This is the screen the owner asked to make "visually easy". | `EditorialCollectionView.swift:605-677` |
| High | Its "+1" advance is a bare `Task` that does not pass `episodeCap`, so `HomeStore.advance`'s caught-up guard is skipped (`Kuro/Home/HomeStore.swift:507-519`). There's no Undo affordance and no visible status message here (the store's `statusMessage` is only shown on Home). The account context is captured in the store (`HomeStore.swift:509`). Verify whether the server clamps progress to the total. | `EditorialCollectionView.swift:639-656` |
| Medium | Legacy header is crowded at 320 pt: 6 filter tabs, a sort scroller, 3 menus, the grid toggle and an edit button in one row | `EditorialCollectionView.swift:317-350`, `387-430` |
| Medium | Icon toggles have no labels and small targets; 9 pt / 0.35-opacity verdict filter | `EditorialCollectionView.swift:333-337`, `409-414`, `363-366` |
| Medium | Empty-state CTAs navigate by opening `kuro://` URLs through `UIApplication.shared.open` | `EditorialCollectionView.swift:695-706` |
| Low | "WATCHING" status label is used for manga too | `EditorialCollectionView.swift:42` |

### P6 Clubs list / S16 Club detail / S16a, S17 club sheets

| Sev | Issue | Evidence |
|---|---|---|
| Medium | Failure or offline looks like "no clubs" (H-10) | `ClubsView.swift:34-43` |
| Medium | 39 raw colours, 6 fixed fonts, fixed 140 pt banner art, 26 pt avatar stacks with 9–10 pt initials | `ClubsView.swift:471`, `507-516`, `532-569` |
| Medium | Very few accessibility modifiers (Clubs 4, Club detail 3); club cards and tab bar need audit | `ClubsView.swift`, `ClubDetailView.swift` |
| Medium | Club detail fixed sizes: rail cards 120×170, reaction rows fixed at 120 width | `ClubDetailTabComponents.swift:462`, `1335`, `1398` |
| Low | Skeleton blocks at fixed widths (210/156/116) | `ClubDetailView.swift:773-830` |
| Note | Good: offline-aware error copy and retry in Club detail | `ClubDetailView.swift:89-138` |

### S1 Profile

| Sev | Issue | Evidence |
|---|---|---|
| **High** | Profile has no lists. The owner wants Profile to be "where your lists are". Lists live only in the Collection page; Profile links out with "Open Collection". | `ProfileView.swift:271-330`, `299-303` |
| High | Identity band is fixed at 280 pt and clipped (H-3). The headline is still the generic "Your account" that the plan criticised. | `ProfileView.swift:216-249`, `234`; plan:18, 105 |
| Medium | `.transaction { $0.animation = nil }` disables all animation on the sheet, including toasts | `ProfileView.swift:90` |
| Medium | It's a sheet with a custom close overlay, not a navigable hub; deeper flows (Clubs, Concierge, imports) stack more sheets | `ProfileView.swift:123-213` |
| Low | 5 fixed fonts (72 pt initial, 20/15/12 pt) | `ProfileView.swift:129`, `231`, `964`, `1026`, `1057` |
| Note | Good: honest "current list totals, not lifetime history" (`319-321`), Apple private-relay masking (`264-269`), structure matches the plan's six groups (`57-77`). | — |

### S2 Search

| Sev | Issue | Evidence |
|---|---|---|
| Medium | 12 fixed fonts in result rows (14/11/9 pt) and the search bar (18/16 pt) | `EditorialSearchView.swift:314-546` |
| Medium | Clear button glyph without a label (heuristic) | `EditorialSearchView.swift:330` |
| Low | 60×90 thumbnails fixed; results don't reflow at AX sizes | `EditorialSearchView.swift:488-493`, `619` |
| Note | Good: has `@FocusState` (`309`, `321`), skeleton rows, empty state with suggestions. | — |

### S7 detail pages

| Sev | Issue | Evidence |
|---|---|---|
| High (product) | The **series detail drops most legacy content**: similar titles, next pick, where to watch/read (providers), external links, genres/tags, cast directory → entity sheets, club activity section and the episode/chapter list sheets. It adds coverage ("original story"), Spotify themes and a private discussion. Shipping the series flag regresses detail richness. | `SeriesDetailViews.swift:30-47` vs `AnimeDetailView.swift:79-160` |
| Medium | Series detail: internal copy (H-10); artwork band with both a gradient and a 0.72 black panel; title clipped in the 1.9 box | `SeriesDetailViews.swift:86-107`, `118-123` |
| Medium | Legacy detail: 9–10 fixed fonts each; title uses `ResponsiveLayout.fontSize(24)` (width-scaled, not Dynamic Type); 38 pt action circles | `AnimeDetailView.swift:696`, `1334-1393`; `MangaDetailView.swift:573`, `1278-1337` |
| Medium | Loader error shows `localizedDescription`; the retry pill is raw black | `MediaDetailSheet.swift:39-63`, `80-82` |
| Low | The music section links only to Spotify; no Apple Music | `SeriesDetailViews.swift:268-296` |

### S14 AddToListSheet (tracking editor)

| Sev | Issue | Evidence |
|---|---|---|
| Medium | Close and ± controls are 32 pt with no labels; 8 fixed fonts (34/44 pt serif numerals) | `AddToListSheet.swift:137-144`, `336-431`, `392-412` |
| Medium | Hero fixed at 280 pt | `AddToListSheet.swift:241`, `280` |
| Low | Red used for offline mutation text | `AddToListSheet.swift:67` |

### S10 ProviderSelectionSheet / S11 entity sheets / S12 franchise / S15 Add to club

| Sev | Issue | Evidence |
|---|---|---|
| Medium | Provider marks in brand colours (open question); 0 accessibility modifiers | `ProviderLinkViews.swift:198-249` |
| Medium | Entity sheets: 0 accessibility modifiers; fixed 120×120 hero, 8 pt work-card captions | `EntityDetailSheets.swift:510-515`, `715` |
| Low | Add to club sheet: 14 raw colours, 0 accessibility modifiers (metrics-only) | `AddToClubRailSheet.swift` |

### S4/S5 Import chooser and workflow

| Sev | Issue | Evidence |
|---|---|---|
| Low | Chooser copy constrained to `maxWidth: 300`; one fixed font | `ImportSourceChooser.swift:49-60`, `192` |
| Note | Workflow sheet and match picker are metrics-clean (no fixed fonts/frames) | — |

---

## 5. Width behaviour (inferred, not run)

- **320 pt**
  - Home's manga grid switches to its narrow branch (`containerWidth < 360` → 180 pt art, `HomeView.swift:550-556`).
  - The legacy Collection header row is the most likely overflow or crowding point (P5).
  - Discover clamps layout math to `max(320, width)` (`EditorialDiscoverView.swift:65`).
  - The Auth hero (33 pt serif, 28 pt gutters) wraps to 3–4 lines; it fits because it is multiline.
  - Native 320 screenshots exist only for Home and the details (§6).
- **375 / 390 pt**
  - The reference width for most work. 390 screenshots exist for Home, the details, empty Home and Profile.
- **430 pt**
  - No max-width containers outside the Discover hero.
  - Card-width formulas follow CLAUDE.md for Discover rails. TastePicks cards span the full width.
- **Landscape / iPad:** see H-4.
- **Largest Dynamic Type:** see H-2 and H-3. Home is the most prepared, with `isAccessibilitySize` branches at `HomeView.swift:227`, `551`, `960`, `993`, `1040`. Series detail has 4 `dynamicTypeSize` reads. No other surface reads `dynamicTypeSize`.

---

## 6. Screenshots that exist (and gaps)

| Folder | Files | Content |
|---|---|---|
| `docs/handoffs/2026-10-08-fresh-session/native-polish-screenshots/` | 26 | anime-home-320/390/430, manga-home-320/390/430, detail-anime-320/390/430, detail-manga-320/390/430, empty-home-390, home-coming-up, home-continues(-anime), home-full-anime/manga, home-import-sheet, home-invitation-type, home-picture-through-header(-top), home-saved-anime/manga, installed-launch, profile-390 |
| `docs/handoffs/2026-10-07-home-series-evidence/screenshots/native/` | 12 | anime/manga Home and detail at 320/390/430 |
| `docs/handoffs/2026-10-07-home-series-evidence/screenshots/poster/` | 12 | Poster-variant Home/detail at 320/390/430 |
| `docs/handoffs/2026-10-07-home-series-evidence/repairs/screenshots/native/` | 12 | repaired native set. HANDOFF.md:85 notes that some pre-final shots show an outdated Close colour. |
| `docs/handoffs/2026-10-08-simulator-qualification/` | 5 | qualified-signed-in, isolated-callback, password-sign-in, restored-profile, mal-synchronization-paused |
| `docs/handoffs/2026-10-08-backend-integration/` | 5 | import-v2-installed-profile, live-deployment-preview, approved-installed-mal-login, approved-installed-home-manga, approved-installed-home-anime |
| `docs/handoffs/2026-10-07-integrated-release-evidence/` | 3 | development-account-profile, simulator-only-installed, simulator-latest-sign-in |
| `tools/screen-canvas/captures/` | 52 | **Stale (captured 2026-09-30, `manifest.json`)**: welcome, signin, signup, onboarding (+1–4), taste (the old deck), discover, browse, collection, clubs, search, profile, concierge, club sheets/tabs, import, anime/manga detail, add sheets, episodes/chapters, entity sheets, credits, verdict, cast, genres, leanings, providers, addclub, quickactions, franchise, why, genie. Predates Home, series detail, the native-polish Profile and TastePicks. |

**Gaps (nothing current):**
- Discover, Clubs, Club detail, Collection (both variants), Search, Onboarding, Auth email form, TastePicks and AddToListSheet in the post-polish build
- any accessibility text size
- German
- landscape
- iPad
- Reduce Motion stills
- VoiceOver walkthrough evidence

---

## 7. Localhost design prototypes (owner said "map every screen on localhost")

The owner's "localhost" is the design server at `http://127.0.0.1:8803` (`tools/design-directions/`, README lines 7–406). There are also two viewers:
- the native screen canvas (`tools/screen-canvas/index.html`, offline viewer)
- the live preview at `http://127.0.0.1:8799` (`tools/live-preview/README.md`), which captures real SwiftUI into a separate `com.Kuro.canvaspreview` host

| Prototype page | Status per README | Native counterpart |
|---|---|---|
| `instrument.html` (+ `archive/fluid-v9`, `material-v8`) | Selected Home direction (the !Boring-led reference) | `HomeView` (P2). The plan names it "Original Instrument reference" (plan:156). |
| `manga-library.html` | Selected Manga Library reference | Home manga books (`HomeView.swift:549-617`), `SeriesMangaDetailView` |
| `boring-study.html` | Research board | none (reference) |
| `folio.html`, `panels.html`, `interlude.html`, `flow.html`, `studies.html`, `journal.html`, `world.html`, `modern.html`, `aperture.html` | Explicitly **rejected** Home studies (README:45-187) | none |
| `composition-review.html`, `reference-atlas.html`, `references.html` | Reference boards | none |
| `manga-crosscut.html`, `manga-four.html`, `manga-options.html`, `manga-reference-study.html`, `switch-options.html` | Manga and medium-switch explorations | Home medium switch (`HomeView.swift:217-261`), manga shelf |
| `index.html` | Directory index | none |

**Note:** these prototypes have **no counterpart for Discover, Clubs, Profile lists, Onboarding or Auth**. The prototypes are Home-only. Screens beyond Home need design direction, either new prototypes or a written spec, before the polish pass.

---

## 8. Documentation drift found while mapping

- CLAUDE.md lists `taste_deck_v1` "Taste Deck at pager index 0". CURRENT_APP_STATE.md:930-939 describes `TasteDeckView` as the Taste page. Source renders `TastePicksView` (`ContentView.swift:660`).
- CLAUDE.md's Views list omits `TastePicksView`, `Home/*`, `ImportSourceChooser`, `ImportWorkflowSheet`, `ImportCatalogMatchPicker`, `ImportHistorySection`, `KuroSceneryLoop`, `DiscoverOneThingCard`, `KuroDeliberateTap` and `KuroGesture*`.
- The onboarding copy describes the Deck and Browse (§4 G8).
- `tools/screen-canvas` is stale; no current capture of Home, series or Taste picks.

---

## 9. Appendix: raw metrics

### Per-file counts

Column key:
- **sysFont:** `.system(size:)` literals
- **fixW / fixH:** numeric `frame(width:)` / `frame(height:)` literals (includes legitimate 44 pt targets)
- **A11y:** `accessibility*` modifiers
- **RM:** Reduce Motion reads
- **DT:** `dynamicTypeSize` reads
- **raw:** raw colour literals

| File | sysFont | fixW | fixH | A11y | RM | DT | raw |
|---|---|---|---|---|---|---|---|
| ContentView | 0 | 4 | 6 | 15 | 2 | 0 | 9 |
| KuroApp | 3 | 0 | 0 | 0 | 0 | 0 | 2 |
| AuthView | 21 | 3 | 9 | 2 | 13 | 0 | 34 |
| OnboardingView | 1 | 2 | 3 | 0 | 0 | 0 | 11 |
| TastePicksView | 0 | 0 | 3 | 2 | 0 | 0 | 0 |
| Home/HomeView | 18 | 15 | 45 | 29 | 5 | 8 | 19 (+8 hex) |
| Home/SeriesDetailViews | 1 | 9 | 31 | 16 | 0 | 4 | 8 |
| EditorialDiscoverView | 20 | 2 | 4 | 6 | 0 | 0 | 33 |
| BrowseView / BrowseComponents | 1 / 0 | 0 / 0 | 0 / 7 | 0 / 14 | 0 | 0 | 2 / 0 |
| EditorialCollectionView / Components | 12 / 0 | 1 / 6 | 8 / 10 | 5 / 10 | 0 | 0 | 12 / 3 |
| ClubsView | 6 | 8 | 15 | 4 | 0 | 0 | 39 |
| ClubDetailView / Shell / Tab / Sheets / Create | 2 / 1 / 1 / 0 / 2 | 11 / 8 / 8 / 4 / 0 | 16 / 10 / 12 / 5 / 0 | 3 / 3 / 8 / 3 / 0 | 0 | 0 | 25 / 1 / 8 / 4 / 12 |
| ProfileView | 5 | 3 | 14 | 9 | 2 | 0 | 3 |
| EditorialSearchView | 12 | 8 | 10 | 10 | 0 | 0 | 29 |
| AddToListSheet | 8 | 6 | 9 | 3 | 0 | 0 | 17 |
| AnimeDetailView / MangaDetailView | 9 / 10 | 7 / 6 | 9 / 9 | 14 / 12 | 0 | 0 | 8 / 7 |
| FriendsActivitySection | 6 | 6 | 11 | 6 | 0 | 0 | 21 |
| ClubActivitySection | 0 | 2 | 5 | 0 | 0 | 0 | 18 |
| EntityDetailSheets | 2 | 2 | 2 | 0 | 0 | 0 | 8 |
| ProviderLinkViews | 5 | 0 | 0 | 0 | 0 | 0 | 6 |
| KuroRefinedCard | 16 | 0 | 1 | 2 | 0 | 0 | 15 |
| CompactAnimeCard / GridAnimeCard | 4 / 3 | 0 / 1 | 0 / 2 | 5 / 5 | 0 | 0 | 7 / 5 |
| ConciergeComponents / RecRails / ImportCards | 0 / 5 / 0 | 19 / 2 / 5 | 14 / 4 / 5 | 16 / 6 / 2 | 0 | 0 | 0 / 18 / 15 |
| TasteDeckView (dead) | 0 | 1 | 7 | 7 | 5 | 2 | 0 |

### Other checks

- `UIScreen`: none in executable code. Only a comment at `KuroCachedAsyncImage.swift:12`.
- `print(` outside `#if DEBUG`: none found in the views read. `HomeView.swift:105` and `KuroRoutes.swift:167` are inside `#if DEBUG`.

---

## 10. Prioritised recommendations for the implementation lanes

1. **Accessibility unblock (S effort, client only):**
   - Fix the header element grouping and add an adjustable pager action (H-1).
   - Raise header, AddToList and Collection icon targets to 44 pt and add labels (H-8).
2. **Type-system rebase (M):**
   - Build the Kuro roles on scaled fonts that react to `dynamicTypeSize`, with per-container caps.
   - Replace the ~200 `.system(size:)` literals with roles.
   - Remove the fixed-height clips (H-2, H-3).
3. **Palette freeze (S–M):**
   - Add tokens for paper stroke, quiet ink, key fill and club band (neutral, no green cast).
   - Replace the Home hex literals and the Auth red/blue.
   - Route errors through `kuroError` (H-5).
   - Remove the "Sunday Club" fallback.
4. **Lists experience (L):**
   - Redesign the series Collection into a visual list with artwork, status lanes, next-release dates and inline progress with Undo.
   - Give Profile a "Your lists" entry or embed (P5s, S1).
   - Pass `episodeCap` and show feedback on advance.
5. **Onboarding and launch (M):**
   - Rewrite the onboarding content for the real pager.
   - Reuse the scenery language; offer medium choice and import.
   - Unify the launch/bootstrap/welcome sequence (G8, H-11).
6. **Auth polish (M):**
   - Token palette, Dynamic Type, real `@FocusState` with submit chaining, linked Terms/Privacy, manga-inclusive copy.
7. **Series detail parity (M–L):** decide which legacy sections (providers, similar, cast directory, episode list, club activity) must carry over before the series flag ships.
8. **Scope decision:** portrait-only iPhone vs. landscape/iPad (H-4).
9. **Localization (M):** move to a String Catalog; fix the Home date formatter.
10. **Dead code removal (S):** `TasteDeckView` family, `GenrePickerSheet`, `HomeView.inkIndex` and children, and optionally the DEBUG Genie hero. Update CLAUDE.md, CURRENT_APP_STATE.md and the screen-canvas registry.
