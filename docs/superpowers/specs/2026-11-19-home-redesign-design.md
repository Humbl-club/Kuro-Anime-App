# Home, Discover & Clubs Existing-Parts Polish Specification

**Date:** 2026-11-19  
**Status:** IMPLEMENTED & LOCALLY VERIFIED (simulator snapshot & unit tests; not yet uploaded to TestFlight).  
**Predecessor:** [UX Redesign Handoff (2026-11-19)](../../plans/2026-11-19-ux-redesign-handoff.md)  
**Owner Direction:** Refine and polish the **existing parts** across Home, Discover, and Clubs/Rails so they feel calm, responsive, and cohesive with the Anime/Manga Detail pages — without inventing new tabs, page layouts, or backend SQL migrations (`home_bundle_v1` already returns `PLANNING` cards with full artwork/unit metadata).  
**Contracts preserved:** [Navigation Contract](2026-11-02-navigation-contract-design.md), [Discover Usability Design](2026-11-04-discover-usability-design.md), `KuroDesignSystem` tokens, `AGENTS.md` architecture & UI rules.

---

## 1. Home: Plan-to-Watch & Mixed Shelf Polish

### Root Causes Fixed
1. `HomeShelfPolicy.showsNewAccount` + `ContentView.latchHomeNewAccount` previously kept `HomeNewAccount` ("Your stories belong here.") mounted indefinitely while `onlyBarePlans(library.allEntries)` was true — hiding titles added to Plan-to-Watch from Discover, Taste, Search, or Collection.
2. `HomeShelfPolicy.leadCard` returned `nil` on Planned-only shelves (leaving `ANIME`/`MANGA` unlit grey), `HomeView` still showed an empty `Coming up · Nothing scheduled` card and *"Start a planned title from its page."* wall, and `quietShelf` rendered 40×60 rows without metadata, Start `+` keys, or fold caps.

### Implemented Behavior
- **`starterHold` Isolation (`HomeShelfPolicy.showsNewAccount`, `HomeView`):** Adding Plan-to-Watch entries from Discover, Taste, Search, or Collection now displays Home's shelf immediately. `HomeNewAccount` stays mounted only while `starterPlanHold` is active during an in-place tap on its `"A first favourite."` starter picks (resetting on medium switch, disappear, or account change).
- **Medium Word Fill (`HomeShelfPolicy.leadCard`):** Prefers the first `isInProgress` card (`WATCHING`/`READING`/`CURRENT`/`REPEATING`), falling back to the first `PLANNING` card so the medium word lights up with real artwork.
- **Planned-Only Poster Home Stage (`HomeShelfPolicy.plannedStage`, `HomeOpeningLine.plannedKicker`/`plannedHeadline`, `HomeView`):**
  - Suppresses empty `comingUpLine` and empty `calendarSection` when `split.inProgress.isEmpty` and no schedules exist.
  - Renders `PLAN TO WATCH` / `PLAN TO READ` · `"N ready to start."`, reusing `HomeSceneCard` (top 2 planned anime) + `HomeAlsoWatchingGrid` under `"Up next on your list"` (or `HomeMangaLeaves` for manga) folded past 6 titles via `KuroFoldButton`.
  - Each planned card's `+` key (`startPlannedKey`) calls `DetailAdvance.advance` (`LibraryActions.apply`, promoting `.planning` → `.current` at `progress = 1`), guarded by `AccountActionScope` + in-flight tracking, with confirm stamp, haptic, and Undo toast (`DetailAdvance.undo` via `LibraryActions.restore`).
- **Mixed Shelf `quietShelf` (`HomeView`, `HomeShelfPolicy.quietMeta`):** Upgrades rows to `44×64` rounded-4pt covers, honest `format · N episodes/chapters` subtitles, trailing sibling `+` Start keys on `Planned`, and a 4-row `KuroFoldButton` cap.

---

## 2. Discover: Above-the-Fold Relief & Quiet Card Actions

- **`DiscoverMoodKeys`:** Replaces the 2×2 boxy grey gradient grid (and empty 4th cell when unseeded) at non-accessibility sizes with a single-row horizontal warm-paper pill strip (`minHeight: 44` targets, `.kuroSwipeExclusionZone()`, exact VoiceOver `"\(title). \(subtitle)"` preserved for `LiveWalkthroughUITests`), retaining the 1-column vertical grid at AX sizes.
- **`DiscoverContentsLine`:** Replaces the multi-row Contents table at non-accessibility sizes with a compact single-row horizontal jump strip (`01 New to you ↓` · `02 This season ↓` …) under `IN THIS ISSUE · N SECTIONS`, bringing `New to you.` onto the first viewport while preserving AX vertical rows.
- **`DiscoverPlanKey` (`DiscoverCardActions.swift`):** Uses calm capsule pills (`+ Plan` / `Planned` / tracked status word, `height: 28` inside `minHeight: 44` hit targets) for `.leaf` portrait tiles and `.right`-aligned index rows, keeping `TastePlanKey` unchanged on `TastePicksView` and `.landscape` cover stories.
- **`DiscoverCoverStory`:** Softens bannerless `.feature` inline spreads from dark `base → deep` slabs to `material.wash` + 1pt `material.edge` paper cards with dark ink (`Color.kuroInk`), keeping `Today's pick` (`.lead`) and banner stories dark.

---

## 3. Clubs & Club Rails: Horizontal 2:3 Poster Rails

- **`JournalRailSection` & `JournalRailTile` (`ClubDetailTabComponents.swift`):**
  - Replaces the cramped 2-column `44×66` thumbnail grid with a real horizontal 2:3 poster rail (`ClubRailCardMetrics` `height = (width * 1.5).rounded()`, `.detailRailBleed(visible:gutter:)`, sharp `360px` covers, `KuroBrandedTile` fallback).
  - Moves section Add action to a compact `+ Add` pill in the rail heading (keeping `ClubTextAction` under empty rails).
  - Expands inline spoiler notes into a full-width editorial quote card below the rail instead of inside narrow tile columns (retaining 1-column `verticalRow` layout at AX sizes).
- **`ClubKeyRow` (`ClubDetailShellComponents.swift`) & `ClubsView`:** Refines action strips to calm warm-paper `RoundedRectangle(cornerRadius: 10)` pills (`minHeight: 44`), and bumps `ClubRoomCard` fan covers to `180px`.

---

## 4. Verification Summary

- Focused native test suites (`155` tests across `16` suites: `HomeShelfPolicyTests`, `HomeLaneTests`, `HomeAnimeLaneTests`, `FirstRunLaneTests`, `DetailPathwayTests`, `DiscoverPageBuildTests`, `DiscoverIssueTests`, `DiscoverVisitTests`, `DiscoverPageFeedbackTests`, `DiscoverReviewFixTests`, `DCDiscoverLayoutTests`, `DCDiscoverCopyTests`, `DCDiscoverPageTests`, `DCDiscoverSectionTests`, `DCclubsTests`, `ClubsViewRulesTests`) passed on `iPhone 17 Pro Kuro Qualification` (`7FC4B58A-430C-457D-A017-6B0095723F3F`).
- Fresh 390pt simulator renders (`after-*`) inspected for Home Plan-to-Watch (Anime & Manga), Mixed Home, Discover All/Manga, Club Detail Top/Rails, and Clubs List.
- Quality gates (`check_architecture.sh`, `check_navigation.sh`, `policy.py --check`, `policy.py --check-claude`, `check_docs_current_state.sh`) verified after edits.

## Phase 2 Functional Polish (2026-11-19)

- **Cross-Medium Immediate Home Sync (`HomeContracts.swift`, `HomeStore.swift`, `LibraryChangeSinks.swift`):**
  - `HomeLibrarySink` delivers `LibraryChange` events whenever either `store?.anime != nil || store?.manga != nil`.
  - `HomeBundle.applyingLibraryChange(mediaId:status:progress:)` optimistically patches already-loaded cards in place (updating `listType`/`progress` for `WATCHING`/`READING`/`REPEATING`/`PLANNING`/`PAUSED`, removing `.completed`/`.dropped`/deleted rows) while leaving `homeRevision` unchanged so the server bundle always supersedes it.
  - `HomeStore` tracks `staleMedia: Set<String>`, refreshes the active medium after a 60ms debounce, refreshes an already-cached inactive medium in the background via `otherMediumRefreshTask`, and triggers `load()` in `selectMedium(_:)` whenever `bundle == nil || staleMedia.contains(next)`.
