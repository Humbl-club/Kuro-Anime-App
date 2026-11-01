# Prototype-Fidelity Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The native Home (anime and manga), both detail pages, the first-run path, Taste and all other pager screens match the approved prototype, and every screen has a branded, animated loading, error, offline and empty state.

**Architecture:**
- **Phase 0** captures the prototype as reference images plus a measured spec.
- **Phase 1** (serial, one owner) changes the shared foundation: tokens, type ramp, artwork materials, keys, motion, branded states, header.
- **Phase 2** runs screen lanes in parallel git worktrees with exclusive file ownership.
- **Phase 3** merges, runs a per-screen fidelity review against the reference captures, and runs the full verification.

Data comes from existing owners only; no new live backend.

**Tech Stack:** SwiftUI (iOS 17+/26), `@Observable` owners, Swift Testing (`KuroTests`), Playwright (reference captures), the local package `Packages/KuroModules`.

**Spec:** `docs/superpowers/specs/2026-11-01-prototype-fidelity-design.md`. Also read: `docs/overnight-2026-11-01/understand/DESIGN_RULEBOOK.md` (only where the spec does not override it) and `docs/overnight-2026-11-01/FOUNDATION_API.md`.

## Global Constraints

- **Prototype wins:** the prototype source wins over the 9 Oct native adjustments and over any rulebook rule the spec lists as overridden (spec §2).
- **Palette:**
  - Home canvas `#fffef8`; detail paper `#f5f5f4`.
  - Component tints follow the prototype: keys `--key-face`, rails `--rail-*`.
  - Statuses stay monochrome; red only for destructive actions.
- **Artwork material** follows the `art-hue-v1` port exactly (spec §3), with white text on `base` at ≥ 7:1.
- **Motion:**
  - contact 120 ms, settle 220 ms, medium 320 ms, ease `cubic-bezier(.2,.8,.25,1)`
  - Reduce Motion and Low Power show the composed final frame
  - no loop runs more than 2 cycles, except loading until content arrives
  - nothing animates offscreen
- **Copy:**
  - every user-facing string goes through `KuroLocale.text(en, de)`
  - no internal words ("verified", "approved", "fallback", "server")
  - no fabricated data; a section without data is hidden
- **Tracking:** writes only through `LibraryActions` and the existing Home/Collection advance paths (caught-up guard, Undo). The detail page acts on the entry that is open.
- **Both flag worlds work:** live (series flags off) and target (`--ff-on=series_foundation_v1 --ff-on=series_home_native_v1`). The new detail is the detail for everyone.
- **No live writes:** no migration apply, deploy, flag/cron/secret change, push or TestFlight. Owned simulator `7FC4B58A-430C-457D-A017-6B0095723F3F` only, never erased.
- **Code rules:** no force unwraps; `print` only in `#if DEBUG`; DEBUG-only types guarded; no Combine; no `UIScreen.main`; no hardcoded card widths; 44 pt targets.
- **Every lane verifies:**
  - Debug `build-for-testing`
  - Release `build` (`-configuration Release -destination 'generic/platform=iOS'`)
  - `scripts/quality-gates/check_architecture.sh`
  - its own Swift Testing suites
- **Snapshot evidence** is written only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`.

## Review Focus

1. **Long and German titles and Dynamic Type AX5** on scene feet, Also-watching tiles, manga leaves and the detail hero: titles wrap to 2 lines and then truncate; counters and keys never overlap the title. *(Test: `HomeLayoutPolicyTests.longTitleNeverOverlapsKey`, Task 5.)*
2. **Artwork that fails to load, or a missing `cover_image_color`:** the material falls back to the neutral ink base `#3a3d3c`; white text stays ≥ 7:1; no layout jump when the material arrives. *(Test: `ArtworkMaterialTests.missingImageUsesNeutralBase`, Task 2.)*
3. **A title with one season, no ladder, no songs, no characters and no club** (most of the catalogue): the detail page still reads as complete, never shows an empty heading, and never invents "Season 1". *(Test: `DetailSectionPolicyTests.sparseTitleShowsOnlyRealSections`, Task 6.)*
4. **An untracked title opened from Discover:** the detail shows "Not in your list" + Add. No progress, Up next or +1 appears until it is saved. Add opens the status choice. *(Test: `DetailSectionPolicyTests.untrackedHidesProgress`, Task 6.)*
5. **Offline at launch with a cached library:** Home shows cached content plus the offline band, not the error stroke. A cold offline launch with no cache shows the branded offline state with Try again. *(Test: `BrandedStateTests.offlineWithContentKeepsContent`, Task 3.)*

---

## Phase 0 — Reference

### Task 1: Prototype reference pack

**Files:**
- Create: `docs/prototype-fidelity/reference/*.png`
- Create: `docs/prototype-fidelity/PROTOTYPE_SPEC.md`

**Interfaces:**
- Produces: reference images `ref-<screen>-<state>-390.png` (also `-320` and `-430` for the Home states) and `PROTOTYPE_SPEC.md`. Every later task cites both.

- [ ] **Step 1:** Serve the prototype: `python3 -m http.server 8803 --bind 127.0.0.1 --directory tools/design-directions` (skip if `curl -s -o /dev/null -w %{http_code} http://127.0.0.1:8803/instrument.html` prints 200).
- [ ] **Step 2: Capture with Playwright** at phone widths 390, 320 and 430.
  - States: `instrument.html?switch=poster&scenario={busy,full,undated,quiet,new}` × `medium={anime,manga}`; `&detail=anime-2`; `&detail=manga-0`; Taste via the "‹ Taste" control, also in the `new` scenario.
  - Method: expand `.phone` to its `scrollHeight` before the element screenshot. For `#detail`, capture at `scrollTop` steps of `clientHeight − 32` and stitch with PIL.
- [ ] **Step 3: Write `PROTOTYPE_SPEC.md`.**
  - Per component, measured from `instrument.css`/`instrument.js`: font size, weight, tracking, colour token, radius, shadow, padding and spacing.
  - Components: header, medium switch, coming-up glance, opening line, scene card, also-watching tile, manga leaf, calendar day/row, dates-to-come, club room, footer, every detail section from spec §5.2, the Taste story card, the new-account Home.
  - The three keyframes `confirm`, `count` and `restore` with their exact CSS.
  - Every copy string, with a German draft.
  - Expected: one table per component; no "TBD".
- [ ] **Step 4: Commit:** `git add docs/prototype-fidelity && git commit -m "Prototype reference pack: captures + measured spec"`

---

## Phase 1 — Foundation (serial, one owner)

### Task 2: Prototype tokens, type ramp and artwork materials

**Files:**
- Modify: `Kuro/Design/KuroDesignSystem.swift`
- Create: `Kuro/Design/ArtworkMaterial.swift`
- Create: `Kuro/Design/ArtworkMaterialStore.swift`
- Modify: `Kuro/Composition/AppComposition.swift` (inject the store)
- Test: `KuroTests/ArtworkMaterialTests.swift`

**Interfaces:**
- Produces:
  - `struct ArtworkMaterial: Equatable, Codable, Sendable { base, deep, wash, edge, ink: KuroRGB; contrast: Double; method: String }`
  - `static func ArtworkMaterial.derive(from cgImage: CGImage, banner: Bool) -> ArtworkMaterial`
  - `static func ArtworkMaterial.fromHex(_ hex: String?) -> ArtworkMaterial` (first paint; `nil` → neutral base `#3a3d3c`)
  - `@MainActor @Observable final class ArtworkMaterialStore { func material(for url: URL?, seedHex: String?) -> ArtworkMaterial }` (returns the seed immediately and publishes the derived material when ready; memory + disk cache keyed by URL)
  - Colour tokens: `Color.kuroCanvasHome` (`#fffef8`), `kuroPaper` (`#f5f5f4`), `kuroInk` (`#252625`), `kuroMuted` (`#696c6b`), `kuroLine` (`#272b2920`), `kuroKeyLightTop` (`#f1f4f2`), `kuroKeyLightBottom` (`#d5ded8`), `kuroKeyDarkTop` (`#444a47`), `kuroKeyDarkBottom` (`#2c322f`)
  - Type roles in the prototype's sans: `kuroHero`/`kuroDisplay`/`kuroHeadline`/`kuroTitle` change globally to the prototype's sans weights and tracking from `PROTOTYPE_SPEC.md`. New `Font.kuroEditorial(size:)` (system serif) and `Font.kuroMediumWord()` (heavy sans uppercase, tracking from spec).
  - Motion tokens: `KuroMotion.contact`, `.settle` and `.medium` as `Animation` values with timing curve (0.2, 0.8, 0.25, 1).

- [ ] **Step 1: Write the failing tests** in `ArtworkMaterialTests.swift`:
  - `deriveMatchesPythonReference`: run `derive` on `tools/design-directions/assets/anime0.jpg` (bundle-loaded via `#filePath`); expect `base` hex `#493a31` ±2 per channel, `contrast >= 7`.
  - `missingImageUsesNeutralBase`: `fromHex(nil).base.hex == "#3a3d3c"`; `contrast >= 7`.
  - `brightHexIsDarkenedToContrast`: `fromHex("#f4e4a1").contrast >= 7`.
  - `washIs92PercentPaper`: given a base, `wash` equals `mix(base, #fafaf5, 0.92)`.
- [ ] **Step 2:** Run `xcodebuild … test -only-testing:KuroTests/ArtworkMaterialTests` on the owned UUID. Expected: FAIL (types missing).
- [ ] **Step 3: Implement** `ArtworkMaterial.derive` as an exact port of `material()` in `tools/design-directions/build_art_materials.py`:
  - CoreGraphics downsample to 104×32 for banners, or fit 64×96 for posters
  - HSV with value .12–.94 and saturation ≥ .12
  - weight `s*(1-abs(v-.55))`
  - 24 hue bins
  - `hls(hue,.24,.20)`
  - darken by mixing 5% black until `1.05/(L+.05) ≥ 7`
  - `deep = mix(base,(.06,.07,.07),.5)`, `wash = mix(base,(.98,.98,.96),.92)`, `edge = mix(base,(.98,.98,.96),.72)`
  - `fromHex` applies the same contrast loop.
- [ ] **Step 4: Change the tokens and roles** in `KuroDesignSystem.swift`. Old names keep compiling, aliased to the new roles.
- [ ] **Step 5:** Run the tests and both builds. Expected: PASS, and BUILD SUCCEEDED for Debug and Release.
- [ ] **Step 6: Commit:** `feat: prototype tokens, sans type ramp, artwork materials`

### Task 3: Keys, motion, branded states, header

**Files:**
- Modify: `Kuro/Views/Shared/KuroAdvanceKey.swift` (prototype raised keys)
- Create: `Kuro/Views/Shared/KuroMotionEffects.swift` (`confirm`, `count`, `restore`)
- Create: `Kuro/Views/Shared/KuroBrandedStates.swift` (`KuroLoadingView`, `KuroSkeleton`, `KuroErrorView`, `KuroOfflineView`, `KuroEmptyView`)
- Modify: `Kuro/Views/Shared/KuroStateView.swift` (thin wrapper over the new family; keep its API)
- Modify: `Kuro/ContentView.swift` (`KuroHeaderNew` restyle)
- Create: `scripts/quality-gates/check_branded_states.sh` (grep gate), wired into `scripts/quality-gates/run_all.sh`
- Test: `KuroTests/BrandedStateTests.swift`

**Interfaces:**
- Consumes: Task 2 tokens and `KuroMotion`.
- Produces:
  - `KuroAdvanceKey(style: .light | .dark | .material(ArtworkMaterial), …)`: existing initializer plus a `style` parameter.
  - `.kuroConfirmStamp(trigger:)`, `.kuroCountRoll(value:)`, `.kuroRestore(trigger:)`: view modifiers ported from the prototype keyframes.
  - `KuroSkeleton(kind: .sceneCard | .coverLeaf | .calendarDay | .detailSection | .row)`
  - `KuroLoadingView(scope: .inline | .page)`
  - `KuroErrorView(headline:message:retry:)`
  - `KuroOfflineView(hasContent: Bool, retry:)`
  - `KuroEmptyView(headline:message:actions:)`
  - `KuroBrandedState`: a pure enum `{ loading, empty, offline(hasContent), failed(hasContent) }` with `static func resolve(isLoading:Bool, hasContent:Bool, isOffline:Bool, failed:Bool) -> KuroBrandedState?`. Returns `nil` when content is shown with no overlay.
  - Header: `KuroHeaderNew` with `KURO` left, page name centre (prototype sans), Search and Profile as ink glyphs, smaller dots, and "‹ Taste" on Home.

- [ ] **Step 1: Write the failing tests** in `BrandedStateTests.swift`:
  - `offlineWithContentKeepsContent`: `resolve(isLoading:false, hasContent:true, isOffline:true, failed:false) == .offline(hasContent:true)`
  - `coldOfflineIsOfflineWithoutContent`: same with `hasContent:false` gives `.offline(hasContent:false)`
  - `contentWinsOverLoading`: `resolve(isLoading:true, hasContent:true, …) == nil`
  - `failedWithoutContent`: `.failed(hasContent:false)`
  - Copy pins: `KuroErrorView` default retry label EN `"Try again"` / DE `"Erneut versuchen"`; offline-with-content line EN `"You're offline. Showing what you saw last."`
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3: Implement the motion and states.**
  - Ink-stroke mountain path: trace the `KuroZenMountains` ridge once into a normalized `Path` stored in `KuroBrandedStates.swift`, drawn with `trim(from:0,to:progress)` over 1.2 s.
  - Loading scrub line: travels every 1.6 s.
  - Wordmark letters settle on a 60 ms stagger.
  - Every animation reads `accessibilityReduceMotion` and `ProcessInfo.isLowPowerModeEnabled` and shows the final frame when either is set.
- [ ] **Step 4: Write `check_branded_states.sh`.** It fails on `ProgressView(` in `Kuro/Views/**` outside `Kuro/Views/Shared/KuroBrandedStates.swift`. Wire it into `run_all.sh`. Expected now: it lists today's offenders. The lanes fix their own files, and the gate must pass at Phase 3.
- [ ] **Step 5:** Run tests and both builds. Expected: PASS and SUCCEEDED.
- [ ] **Step 6: Commit:** `feat: prototype keys, motion effects, branded state family, header`

---

## Phase 2 — Screen lanes (parallel worktrees from the Phase 1 commit)

Each lane:
- Owns exactly the files listed for it, plus new tests named `<Lane>Tests.swift`.
- Cites the reference images and `PROTOTYPE_SPEC.md`.
- Replaces every spinner and plain empty text in its files with Task 3 components.
- Adds focused tests.
- Builds Debug and Release.
- Is reviewed by two independent reviewers (one for correctness and data honesty, one for fidelity against the references).
- Then fixes and commits.

### Task 4: Home — anime

**Files:**
- Modify: `Kuro/Views/Home/HomeView.swift`, `Kuro/Views/Home/HomePagePicture.swift`, `Kuro/Views/Home/HomeShelfPolicy.swift`
- Create: `Kuro/Views/Home/HomeSceneCard.swift`, `Kuro/Views/Home/HomeAlsoWatching.swift`, `Kuro/Views/Home/HomeComingUpGlance.swift`, `Kuro/Views/Home/HomeOpeningLine.swift`
- Test: `KuroTests/HomeAnimeLaneTests.swift`

**Interfaces:**
- Consumes: `HomeStore`, `ReleasesStore` (`scheduleCoverage(for:)`, `nextRelease(for:)`), `ArtworkMaterialStore`, Task 3 keys, motion and states.
- Produces: `HomeOpeningLine.headline(available:Int, caughtUp:Bool, newAccount:Bool, medium:MediaKind) -> String` (EN: `"2 new episodes"`, `"Keep watching."`, `"Begin here."`, `"Nothing new today. Stay at your own pace."`).

- [ ] **Step 1: Failing tests:**
  - `opening line copy`: the four cases above in EN and DE.
  - `scene card shows at most two titles; rest go to Also watching`
  - `planned titles never become scene cards`
  - `season tab omitted when the ladder number is unknown`
  - `longTitleNeverOverlapsKey`: layout policy keeps a fixed 44 pt key column and gives the title `lineLimit(2)`.
- [ ] **Step 2: Implement the anime Home composition** exactly as `ref-home-busy-anime-390.png`:
  - medium switch (`kuroMediumWord`, art-filled selected word)
  - glance card
  - opening line
  - scene cards with material foot, counter scrub and light key
  - 2-column Also watching
  - Also covers the busy, full, undated and quiet states.
- [ ] **Step 3:** Tests, both builds, then commit.

### Task 5: Home — manga, calendar, club room, footer

**Files:**
- Create: `Kuro/Views/Home/HomeMangaLeaves.swift`, `Kuro/Views/Home/HomeCalendarCard.swift`, `Kuro/Views/Home/HomeClubRoom.swift`, `Kuro/Views/Home/HomeFooter.swift`
- Modify: `Kuro/Views/Home/HomeCalendarPresentation.swift`
- Test: `KuroTests/HomeMangaLaneTests.swift`

**Interfaces:**
- Consumes: as Task 4, plus `ClubsStore` and `SocialActivityStore` (existing reads only).
- Produces:
  - `HomeCalendarCard(groups: [HomeCalendarDay], coverage: ReleaseScheduleCoverage)`
  - `HomeClubRoom.pick(clubs: [ClubSummary]) -> ClubSummary?`: the club with the latest real activity; `nil` hides the room.
- Integration: HomeView (Task 4's file) embeds these by type name. Lane 4 owns HomeView and adds the embed calls. Lane 5 only creates the components with these exact initializers.

- [ ] **Step 1: Failing tests:**
  - `manga leaves are three columns with Ch + key row`
  - `calendar day chip shows day number and month abbreviation (EN "OCT", DE "OKT")`
  - `Dates to come row appears only for announced/undated items`
  - `club room picks the most recent activity, hides with no clubs`
  - `club room never shows a fabricated club name`
- [ ] **Step 2: Implement** to `ref-home-busy-manga-390.png`, the calendar section of `ref-home-full-anime-390.png`, and the club room in `ref-home-busy-anime-390.png`.
- [ ] **Step 3:** Tests, both builds, then commit.

### Task 6: Detail — shared page skeleton and anime

**Files:**
- Create: `Kuro/Views/DetailPages/Prototype/DetailPage.swift` (shell, hero, status mark, section ordering)
- Create: `Kuro/Views/DetailPages/Prototype/DetailSectionPolicy.swift` (pure)
- Create: `Kuro/Views/DetailPages/Prototype/AnimeDetailSections.swift`
- Create: `Kuro/Views/DetailPages/Prototype/DetailBetweenUs.swift`
- Modify: `Kuro/Views/DetailPages/AnimeDetailView.swift` (route to the new page for everyone)
- Modify: `Kuro/Views/Home/SeriesDetailViews.swift` (`SeriesAnimeDetailView` delegates to the new page)
- Test: `KuroTests/DetailSectionPolicyTests.swift`

**Interfaces:**
- Consumes:
  - `CatalogStore.fetchAnimeById`, `fetchCharactersForAnime(animeId:)`, `fetchStaffForAnime(animeId:)`, `fetchStudiosForAnime(animeId:)`, `fetchMediaLadder(mediaType:mediaId:)`, `fetchEpisodesPage(animeId:offset:limit:)`, `fetchExternalLinks(mediaType:mediaId:)`
  - `ReleasesStore` title schedule and themes
  - `SocialActivityStore.fetchFriendActivityForTitle(mediaType:mediaId:)`
  - `LibraryStore` entry; `routes.presentTrackingEditor`, `routes.openMedia`
  - Task 2/3 components
- Produces:
  - `enum DetailSection { hero, story, clubPresence, seasons, progress, units, source, songs, characters, credits, betweenUs }`
  - `struct DetailSectionPolicy { static func sections(for input: DetailInput) -> [DetailSection] }` (pure)
  - `struct DetailInput` with booleans and counts for each data source, plus `isTracked`.
  - `struct LadderSeasons { static func seasons(from: MediaLadderResponse, current: Int) -> (numbered: [Season], extras: [Season]) }`: TV/ONA chain numbered; movies, OVAs and specials go to extras; split-cour parts keep their label.
  - `DetailStatusMark(entry:onListSettings:onFavourite:onVerdict:onProviders:)`

- [ ] **Step 1: Failing tests:**
  - `sparseTitleShowsOnlyRealSections`: input with synopsis only gives `[.hero, .story, .credits]` when credits exist, and `[.hero, .story]` otherwise.
  - `untrackedHidesProgress`: `isTracked == false` excludes `.progress` and `.units`' Up next; the status mark reads EN `"Not in your list"`.
  - `ladder numbering`: chain TV S1 → TV S2 → MOVIE → TV S3 gives numbered `[1,2,3]` and extras `[MOVIE]`.
  - `single entry hides seasons`
  - `status mark keeps List settings, Favourite, Verdict and Where to watch` (assert the four action closures are wired; none removed)
- [ ] **Step 2: Implement** the page to `ref-detail-anime-390.png`:
  - material hero band and paper `wash`
  - story with "About this season +"
  - club avatars
  - season tiles opening the sibling via `routes.openMedia`
  - progress with scrub
  - Up next raised row (advance via the existing path)
  - episode rows, "More episodes ↓"
  - The original story card (原作) from the ladder's source entry
  - "The sound of it." panel (hidden without themes)
  - characters, "Behind the frames.", "Between us." with notes, spoiler reveal and Leave a thought
- [ ] **Step 3:** Tests, both builds, then commit.

### Task 7: Detail — manga

**Files:**
- Create: `Kuro/Views/DetailPages/Prototype/MangaDetailSections.swift`
- Modify: `Kuro/Views/DetailPages/MangaDetailView.swift`, `Kuro/Views/Home/SeriesDetailViews.swift` (`SeriesMangaDetailView` delegates)
- Test: `KuroTests/MangaDetailLaneTests.swift`

**Interfaces:**
- Consumes: Task 6 `DetailPage`, `DetailSectionPolicy`, `DetailStatusMark`, `DetailBetweenUs`; `CatalogStore.fetchMangaById`, `fetchCharactersForManga(mangaId:)`, `fetchChaptersPage(mangaId:offset:limit:)`, the ladder and external links.
- Produces: `MangaDetailSections.chaptersAreReal(_ chapters: [MangaChapter]) -> Bool`, false when every title matches `^Chapter \d+$` with no dates.

- [ ] **Step 1: Failing tests:**
  - `placeholder chapters hide the chapter list`
  - `bookmark card shows Ch. N / total only when total is known`
  - `Seen the anime? appears only with an anime adaptation in the ladder`
  - `Read with the publisher appears only with a publisher external link`
- [ ] **Step 2: Implement** to `ref-detail-manga-390.png`: cover beside the title, "Series overview" hook, "Your bookmark" folio card, Chapters with Up next, "Seen the anime?" (映) card, characters, "Behind the pages.", "Read with the publisher ↗", Between us.
- [ ] **Step 3:** Tests, both builds, then commit.

### Task 8: First run, Taste and empty states across pages

**Files:**
- Modify: `Kuro/Views/TastePicksView.swift`
- Create: `Kuro/Views/Home/HomeNewAccount.swift` (Lane 4 embeds it by type name)
- Modify: `Kuro/Views/EditorialCollectionView.swift` (empty only), `Kuro/Views/ClubsView.swift` (empty only), `Kuro/Views/ProfileView.swift` (new-account library line only), `Kuro/Views/EditorialSearchView.swift` (no-history only)
- Test: `KuroTests/FirstRunLaneTests.swift`

**Interfaces:**
- Consumes: `TasteStore` and `DiscoveryStore` existing reads, `LibraryActions.save(_:status:)`, Task 3 states.
- Produces:
  - `HomeNewAccount(medium: MediaKind, onImport: () -> Void, onExploreTaste: () -> Void)`
  - `FirstFavouritePicks.pick(from: [TasteCard], max: 4) -> [TasteCard]`: real titles only; empty input hides the row.

- [ ] **Step 1: Failing tests:**
  - `new-account Home copy`: EN "Your stories belong here." / "Import your list to bring your place with you."
  - `first favourite picks come only from loaded cards, max 4`
  - `one-tap Plan saves through LibraryActions with .planning`
  - `Profile new account shows "Nothing saved yet" and no zero counts`
  - `Collection empty shows the invitation, never a blank page`
- [ ] **Step 2: Implement:**
  - Taste to the prototype Taste reference: "FOR YOUR TASTE" / "Another world." / "Another chapter." story cards with a separate Plan key.
  - The new-account variants in all listed files.
- [ ] **Step 3:** Tests, both builds, then commit.

### Task 9: Remaining screens restyle and branded states

**Files:**
- Modify: `Kuro/Views/EditorialDiscover*.swift`, `Kuro/Views/DiscoverOneThingCard.swift`, `Kuro/Views/Browse*.swift`, `Kuro/Views/Club*.swift` (except Task 8's empty block in `ClubsView.swift`, which is only appended to), `Kuro/Views/Lists/**`, `Kuro/Views/ProfileView.swift` (except Task 8's line), `Kuro/Views/AuthView.swift` (form only; welcome frozen), `Kuro/Views/OnboardingView.swift`, `Kuro/Views/Import*.swift`, `Kuro/Views/About/**`
- Test: `KuroTests/RestyleLaneTests.swift`

**Interfaces:**
- Consumes: Task 2/3 tokens, keys and states.
- Produces: nothing new. Every `ProgressView(` and plain empty text in these files is replaced by Task 3 components.

- [ ] **Step 1: Failing test:** `restyled screens use branded states`. It drives each screen's state resolver into `.failed(hasContent:false)` and asserts a `KuroErrorView` is produced, via each screen's existing state enum or a small `static func brandedState(…)` added per screen.
- [ ] **Step 2: Implement** the prototype type ramp, key styles and Folio keys (light on anime, dark on manga, as the prototype), plus branded states. Keep layouts unless the prototype specifies them.
- [ ] **Step 3:** Run `scripts/quality-gates/check_branded_states.sh` (expected: no offenders in owned files), tests and both builds. Commit.

File-ownership note: `ClubsView.swift` and `ProfileView.swift` are shared between Tasks 8 and 9. Task 8 runs first in its worktree and touches only the named blocks; Task 9 rebases onto Task 8's commit before editing. All other lanes are fully parallel.

---

## Phase 3 — Integration and fidelity

### Task 10: Merge, verify, fidelity review, report

**Files:**
- Create: `docs/prototype-fidelity/FIDELITY_REVIEW.md`, `docs/prototype-fidelity/screens/*.png`, `docs/prototype-fidelity/gallery/*`
- Modify: `CLAUDE.md`, `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, memory

- [ ] **Step 1: Merge** lanes 4→9 into `kuro/prototype-fidelity` (branched from `kuro/overnight-2026-11-01` at the Phase 1 commit).
- [ ] **Step 2: Verify.** Expected: everything passes, including 0 `ProgressView` offenders.
  - Debug `build-for-testing`, Release build
  - full `KuroTests` on the owned UUID with `-parallel-testing-enabled NO`
  - `run_all.sh` with `SKIP_RAILS_AUDIT=1`
  - package tests
- [ ] **Step 3: Native captures** for every reference state.
  - Use fixture snapshot suites with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1` for states that need data.
  - Use the owned simulator in both flag worlds for live screens (read-only).
- [ ] **Step 4: Fidelity review.**
  - For each reference/native pair, a reviewer lists every visible difference: composition, type, colour, spacing, copy, motion.
  - Each difference is fixed or justified (data honesty, accessibility).
  - Loop until no unjustified difference remains. Then the adversarial code review (security, integrity, pathways, design, both worlds) with skeptic verification.
- [ ] **Step 5: Gallery and docs.** Build the before/after gallery (prototype vs native) and update the docs and memory. Commit. Report to the owner with the screenshots.
