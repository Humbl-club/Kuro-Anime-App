# Lane amendments (lead rulings after Phase 0–1, 2026-11-01)

These rulings override the plan and spec where they conflict, applying the owner's rule that **the prototype wins**. Evidence: `PROTOTYPE_SPEC.md` §8.

1. **Serif (`kuroEditorial`) appears only where the prototype uses Georgia:**
   - club name and club quote
   - "Between us."
   - manga detail title and hook
   - "Your bookmark"
   - manga chapter row numbers (italic)
   - "Seen the anime?"

   "Coming up." and "The sound of it." are SF sans, as in the prototype.
2. **Detail paper is neutral, as in the prototype:**
   - Anime sheet: `#f5f5f4`, radius 24.
   - Manga sheet: `#f6f5ef` with a `#fffdf4` border, radius 9.
   - The artwork material `wash`/`edge` appears **only** on the progress card and the Up next row.
   - `base→deep` appears on the hero band, the Up next key and the song panel.
3. **Caught-up Home:** the headline is "Keep watching." / "Keep reading.". "Nothing new today. Stay at your own pace." is a separate bordered quiet card at the top of the feed. Task 4's test changes accordingly.
4. **Keys:**
   - Also-watching keys are filled with each title's own material (base→deep, white ink).
   - The manga leaf key is solid `#2b342e`, a 38×38 face with radius 6 and ink `#f8faf7`.
   - Scene-card keys are the light raised key.
   - The `#444a47→#2c322f` gradient is not used on Poster screens.
5. **New-account Home:**
   - The prototype shows ＋, two lines and "Explore Taste ←".
   - The owner-approved additions (Import action, "A first favourite." picks) are styled in the prototype's language, below its block, never replacing it.
6. **Motion easings follow the prototype per motion:**
   - `restore`: `ease`
   - entrances and count rolls: `cubic-bezier(.2,.75,.25,1)`
   - progress trace: `cubic-bezier(.22,.8,.24,1)`
   - The `count` keyframe exists but the prototype never applies it, so don't use it unless a reference shows it.
7. **Medium switch:** the selected word shows the **artwork clipped into the letters**, as in the prototype, not the material gradient. Contrast floor: darken the art fill toward `kuroInk` so it never drops below the unselected word's legibility. Task 4 owns this in `HomeView`. `KuroMediumSwitch` (compact callers) may keep the material gradient.
8. **Canvas:**
   - Home (anime) `#fffef8`; manga Home `#f5f5f3`; Taste follows its reference.
   - Each lane paints the same tokens as `KuroMainView.Section.canvas(mangaHome:)`, so no seam appears under the header.
9. **Tracking:** a SwiftUI `Font` cannot carry tracking. Each lane applies `.kuroRoleText` / `.kuroTracking` in the files it owns, using the values in `PROTOTYPE_SPEC.md`.
10. **Ownership changes:** Task 9 owns all of `ClubsView.swift` and `ProfileView.swift`, including their empty and new-account blocks, so Tasks 8 and 9 run fully in parallel. Task 8 keeps Taste, `HomeNewAccount`, the Collection empty block in `EditorialCollectionView.swift`, and the Search no-history block.
11. **Remaining spinner-gate offenders** are fixed by their owners:
    - Task 6: `AnimeDetailView` ×2
    - Task 7: `MangaDetailView` ×2
    - Task 8: `EditorialCollectionView`
    - Task 9: everything else in its files

    The gate becomes blocking in Task 10.
12. **Simulators:**
    - Each lane gets its own clone of the owned simulator, named `Kuro-Lane-<lane>`, created by the lead.
    - A lane runs tests and fixture renders only on its clone (by UUID), with `-parallel-testing-enabled NO`.
    - Clones are deleted at Task 10. Never touch any other simulator.
13. **Local signing:** builds use `CODE_SIGNING_ALLOWED=NO` (the local profile lacks Sign in with Apple and Associated Domains).

## Task 10 integration rulings (lead, 2026-11-01)

14. **German counts and caught up:** every release count reads "N Veröffentlichung(en)" (glance, calendar heading, day, "Show N more releases"); caught up reads "Auf dem neuesten Stand" everywhere, the manga leaf included (the word takes the count's lines, up to three, in the same row height). Both are in `PROTOTYPE_SPEC.md` §7.1.
15. **One span rule:** `HomeScheduleSpan` decides the glance's count label and the calendar heading's span (`HomeCalendarPresentation.summary`); `HomeGlanceSummary.calendarSummary` is gone, and `HomeCalendarPresentation.releaseCount` is the one count.
16. **Taste follows Home (amendment 7):** Taste's medium switch is Home's `KuroPosterMediumSwitch` (two-column grid, hairline and rule) with the first pick's artwork clipped into the selected word (`KuroArtWordFill`, same contrast floor), not the material gradient.
17. **Folio manga key:** the solid manga-leaf key (`.dark`, `#2b342e`); anime keeps the light raised key.
18. **Skeleton blocks** are translucent ink (`KuroSkeleton.blockInkOpacity` 0.08, the deep tone 0.13), so they stay visible on `#fffef8`, `#f5f5f3` and `#f5f5f4` (pinned in `RestyleLaneTests`).
19. **Branded states:** `KuroStateLayout`'s headline is the prototype's empty-block headline (SF 24 w700, tracking −0.8), as `KuroEmptyView`. `check_branded_states.sh` is blocking in `run_all.sh`.
20. **Home club room** draws with `ClubRoomStyle.swift` (`ClubRoomPalette`, `ClubRoomBackground`'s drop approximation), no inline hex.
21. **New account:** the pager (`ContentView`) holds the latch (`TastePageCopy.latchNewAccount` over the whole Library) and `HomeShelfPolicy.showsNewAccount` decides the block for both the page background and `HomeView`, so the mountain picture never shows behind the new-account block; the approved invitation stays for an empty medium beside an occupied one.
22. **Taste canvas in the pager:** the pager owns Taste's medium (`KuroMainView.tasteMedium`, passed to `TastePicksView(medium:)`) and `Section.canvas(mangaHome:mangaTaste:)` paints `#f5f5f3` for manga Taste behind the pager and under the header, so neither the header nor the iPad readable-width margins show `#fffef8` beside manga Taste (first-run NOTES item 3).
23. **New-account block ends with real titles:** while latched, the block stays only while every Library entry is planned (the only status its Plan key writes) and nothing is in progress (`HomeShelfPolicy.showsNewAccount(latched:onlyPlannedTitles:scene:otherMediumOccupied:)`). The Library stays `.loaded` through an import, so the latch alone would have kept "Your stories belong here." over an imported Library.
