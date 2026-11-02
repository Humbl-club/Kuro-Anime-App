# Native renders: reference index

Each reference in `docs/prototype-fidelity/reference/` and the native fixture render(s) to compare it with.
Paths are relative to this folder. All renders are fixture-only (no network, prototype sample art from
`tools/design-directions/assets`) and are rewritten only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`.

- **Primary** is the render to put next to the reference. For Home it is the integrated `HomeView`
  (the page the pager mounts since Task 10), on the pager's canvas for that medium, 1 px = 1 pt.
- **Supplementary** renders come from lane harnesses (component stacks or stand-ins), from other widths,
  German (`-de`, from a `-testLanguage de -testRegion DE` run) or accessibility size 5 (`-ax5`).
  They are evidence for one part of the page, not the integrated page.
- Native renders have no app header (`KuroHeaderNew`, drawn by the pager): the references include it.
  The `firstrun/pager-*` composites (round 3) draw ContentView's header over the new-account Home and
  Taste, so the header can be compared too; their y is not the reference's y − 70 (the native header is
  shorter).

| Reference | Primary native render | Supplementary |
|---|---|---|
| `ref-home-busy-anime-390.png` | `home-anime/home-busy-anime-390.png` | `home-anime/home-busy-anime-toast-390.png` and `-toast-de-390.png` (the +1 toast after a real +1, on a 390 × 844 screen), `home-anime/home-busy-anime-de-390.png`, `home-anime/home-busy-anime-ax5-390.png`, `home-manga/home-anime-calendar-club-390.png`, `home-manga/home-anime-calendar-club-ax5-390.png` (lane harness: calendar + club only) |
| `ref-home-busy-anime-320.png` | `home-anime/home-busy-anime-320.png` | - |
| `ref-home-busy-anime-430.png` | `home-anime/home-busy-anime-430.png` | - |
| `ref-home-full-anime-390.png` | `home-anime/home-full-anime-390.png` | - |
| `ref-home-full-anime-320.png` | `home-anime/home-full-anime-320.png` | - |
| `ref-home-full-anime-430.png` | `home-anime/home-full-anime-430.png` | - |
| `ref-home-undated-anime-390.png` | `home-anime/home-undated-anime-390.png` | - |
| `ref-home-undated-anime-320.png` | `home-anime/home-undated-anime-320.png` | - |
| `ref-home-undated-anime-430.png` | `home-anime/home-undated-anime-430.png` | - |
| `ref-home-quiet-anime-390.png` | `home-anime/home-quiet-anime-390.png` | `home-anime/home-quiet-anime-de-390.png` |
| `ref-home-quiet-anime-320.png` | `home-anime/home-quiet-anime-320.png` | - |
| `ref-home-quiet-anime-430.png` | `home-anime/home-quiet-anime-430.png` | - |
| `ref-home-new-anime-390.png` | `firstrun/home-new-anime-homeview-390.png` | `firstrun/pager-home-new-anime-390.png` (with the app header), `firstrun/home-new-anime-390.png` (first-run harness: stand-in switch and opening, not HomeView), `firstrun/home-new-anime-de-390.png`, `firstrun/home-new-anime-ax5-390.png`, `firstrun/home-new-anime-prototype-block-390.png`, `firstrun/home-new-anime-loader-390.png` (harness) |
| `ref-home-new-anime-320.png` | `firstrun/home-new-anime-homeview-320.png` | `firstrun/home-new-anime-320.png` (first-run harness: stand-in switch and opening, not HomeView) |
| `ref-home-new-anime-430.png` | `firstrun/home-new-anime-homeview-430.png` | `firstrun/home-new-anime-430.png` (first-run harness: stand-in switch and opening, not HomeView) |
| `ref-home-busy-manga-390.png` | `home-manga/home-busy-manga-390.png` | `home-manga/home-busy-manga-de-390.png`, `home-manga/home-manga-busy-390.png` (lane harness, component stack, not HomeView), `home-manga/home-manga-busy-ax5-390.png`, `home-manga/home-manga-states-390.png` (lane harness) |
| `ref-home-busy-manga-320.png` | `home-manga/home-busy-manga-320.png` | `home-manga/home-manga-busy-320.png` (lane harness, component stack, not HomeView) |
| `ref-home-busy-manga-430.png` | `home-manga/home-busy-manga-430.png` | `home-manga/home-manga-busy-430.png` (lane harness, component stack, not HomeView) |
| `ref-home-full-manga-390.png` | `home-manga/home-full-manga-390.png` | - |
| `ref-home-full-manga-320.png` | `home-manga/home-full-manga-320.png` | - |
| `ref-home-full-manga-430.png` | `home-manga/home-full-manga-430.png` | - |
| `ref-home-undated-manga-390.png` | `home-manga/home-undated-manga-390.png` | - |
| `ref-home-undated-manga-320.png` | `home-manga/home-undated-manga-320.png` | - |
| `ref-home-undated-manga-430.png` | `home-manga/home-undated-manga-430.png` | - |
| `ref-home-quiet-manga-390.png` | `home-manga/home-quiet-manga-390.png` | `home-manga/home-quiet-manga-de-390.png` |
| `ref-home-quiet-manga-320.png` | `home-manga/home-quiet-manga-320.png` | - |
| `ref-home-quiet-manga-430.png` | `home-manga/home-quiet-manga-430.png` | - |
| `ref-home-new-manga-390.png` | `firstrun/home-new-manga-homeview-390.png` | `firstrun/pager-home-new-manga-390.png` (with the app header), `firstrun/home-new-manga-390.png` (first-run harness: stand-in switch and opening, not HomeView), `firstrun/home-new-manga-de-390.png`, `firstrun/home-new-manga-ax5-390.png`, `firstrun/home-new-manga-prototype-block-390.png`, `firstrun/home-new-manga-loader-390.png` (harness) |
| `ref-home-new-manga-320.png` | `firstrun/home-new-manga-homeview-320.png` | `firstrun/home-new-manga-320.png` (first-run harness: stand-in switch and opening, not HomeView) |
| `ref-home-new-manga-430.png` | `firstrun/home-new-manga-homeview-430.png` | `firstrun/home-new-manga-430.png` (first-run harness: stand-in switch and opening, not HomeView) |
| `ref-detail-anime-390.png` | `detail/detail-anime-390.png` | `detail/detail-anime-bundle-390.png`, `detail/detail-anime-untracked-390.png`, `detail/detail-anime-untracked-de-390.png`, `detail/detail-anime-untracked-de-320.png`, `detail/detail-anime-ax5-320.png`, `detail/detail-anime-de-390.png` |
| `ref-detail-anime-top-390.png` | `detail/detail-anime-top-390.png` | `detail/detail-anime-top-320.png`, `detail/detail-anime-top-ax5-320.png` |
| `ref-detail-manga-390.png` | `detail/detail-manga-390.png` | `detail/detail-manga-bundle-390.png`, `detail/detail-manga-untracked-390.png`, `detail/detail-manga-untracked-de-390.png`, `detail/detail-manga-untracked-de-320.png`, `detail/detail-manga-ax5-320.png` |
| `ref-detail-manga-top-390.png` | `detail/detail-manga-top-390.png` | `detail/detail-manga-top-320.png`, `detail/detail-manga-top-ax5-320.png` |
| `ref-taste-busy-anime-390.png` | `firstrun/taste-busy-anime-390.png` | `firstrun/pager-taste-busy-anime-390.png` (with the app header), `firstrun/taste-busy-anime-de-390.png`, `firstrun/taste-busy-anime-ax5-390.png`, `firstrun/taste-loading-anime-390.png`, `firstrun/taste-busy-anime-planned-390.png` |
| `ref-taste-busy-manga-390.png` | `firstrun/taste-busy-manga-390.png` | `firstrun/pager-taste-busy-manga-390.png` (with the app header), `firstrun/taste-busy-manga-de-390.png`, `firstrun/taste-busy-manga-ax5-390.png`, `firstrun/taste-loading-manga-390.png` |
| `ref-taste-new-anime-390.png` | `firstrun/taste-new-anime-390.png` | `firstrun/pager-taste-new-anime-390.png` (with the app header), `firstrun/taste-live-new-anime-390.png` (TastePicksView itself over the seeded bundle and catalogue) |
| `ref-taste-new-manga-390.png` | `firstrun/taste-new-manga-390.png` | `firstrun/pager-taste-new-manga-390.png` (with the app header) |

Every reference has a primary native render (38 references).

## Where each render comes from

| Folder | Test | What it renders |
|---|---|---|
| `home-anime/` | `KuroTests/HomeAnimeLaneTests.swift`, `animeHomeRenders`, `progressToastRender` | `HomeView`, anime, busy / full / undated / quiet; the +1 toast |
| `home-manga/home-{state}-manga-*` | `KuroTests/HomeAnimeLaneTests.swift`, `mangaHomeRenders` | `HomeView`, manga, busy / full / undated / quiet |
| `home-manga/home-manga-*`, `home-anime-calendar-club-*` | `KuroTests/HomeMangaLaneTests.swift`, `HomeMangaLaneSnapshotTests` | lane-4/5 component stacks (2x scale) |
| `firstrun/home-new-*-homeview-*` | `KuroTests/FirstRunSnapshotTests.swift`, `newAccountHomeView` | `HomeView` for a new account (latched, empty Library, seeded Discover bundle) |
| `firstrun/pager-*` | `KuroTests/FirstRunSnapshotTests.swift`, `pagerComposites` | `KuroHeaderNew` over the new-account `HomeView` and over `TastePageContent`, Series Home pager order |
| `firstrun/` (other) | `KuroTests/FirstRunSnapshotTests.swift` | first-run harness, `TastePageContent` (the content `TastePicksView` hosts), search, collection invitation, at 1 px = 1 pt; see `firstrun/NOTES.txt` |
| `detail/` | `KuroTests/DetailAnimeSnapshotTests.swift`, `DetailMangaSnapshotTests.swift` | the prototype detail pages over a complete fixture bundle |
| `restyle/` | `KuroTests/RestyleSnapshotTests.swift` | the remaining restyled screens (no reference in `reference/`) |

## Fixture notes for the Home renders (read before judging a difference)

Differences that stay, and why, are listed per finding in `../FIDELITY_REVIEW.md`.

- **Locale.** English renders run with `-testLanguage en -testRegion GB` (the reference's "Fri 9 Oct" and
  24-hour times; English `KuroLocale` follows the device region). German renders run with
  `-testLanguage de -testRegion DE`.
- **Schedule on calendar days.** Anime rows are anchored to the reader's days (today at 16:00 / 17:00 /
  18:00 while those are ahead, later days at noon), so a render never depends on the hour it runs.
  Busy and quiet: 3 today, 2 tomorrow, 1 in six days. Full (both media): 6 on each of 8 days
  ("Show 3 more releases", "Next 4 dates · 24 releases").
- **Anime totals.** Demon Slayer 4 / 5 and Attack on Titan 7 / 8, as the reference. Quiet: 5 / 5 and 8 / 8.
- **Anime undated.** Demon Slayer episode 6 and Attack on Titan episode 9 are announced without a date
  (so 5 and 8 are out: "2 new episodes"), plus Mob Psycho 100's new season.
- **Scene foot colours.** The prototype hand-set its two scene banners' materials (`OVERRIDES` in
  `build_art_materials.py`); the app derives them (FIDELITY_REVIEW note A).
- **Manga sixth title.** The references show Vagabond. The fixture art for that slot is Vinland Saga's
  cover, so the fixture names it Vinland Saga rather than put a wrong cover under a real title.
- **Manga busy headline.** "4 new chapters" is computed, not written: Chainsaw Man 24 against chapter 26
  ahead, Jujutsu Kaisen 19 against 22, SPY x FAMILY 4 against 6 (released = next known chapter - 1).
  Solo Leveling is finished at 9 (a backlog is never "new"). Berserk and Vinland Saga are on hiatus
  (released count unknown: their keys keep the +1, as the reference). So Jujutsu Kaisen reads Ch. 19
  and SPY x FAMILY Ch. 4 where the reference shows 16 and 5.
- **Manga quiet keys.** Chainsaw Man, Solo Leveling and Jujutsu Kaisen read Caught up with the light ✓
  key, as the reference. SPY x FAMILY also reads Caught up (its chapter 6 is tomorrow) where the
  reference draws a +1: Home never offers a +1 for an unreleased chapter (PF-QA-1).
- **Manga undated headline.** With only undated volume announcements nothing released is known, so the page
  says "Keep reading." where the reference shows "4 new chapters" (FIDELITY_REVIEW note G).
- **Club room.** The fixture account has one club, "Sunday Club" (activity two hours ago). Mina's note and
  her ending-scoped spoiler are on Death Note (anime) / Berserk (manga); Jules's note is on Attack on
  Titan / Solo Leveling. The verbs "Finished …" / "… started" need data Home does not have yet
  (FIDELITY_REVIEW note B).
- **New account.** The selected medium word shows the first starter pick's cover (the same rule as Taste),
  the picks come from the seeded Discover bundle (`HomeNewAccount`'s own loader) and are completed from the
  seeded catalogue detail rows (premises), and the page sits on the medium's canvas.
- **Taste.** Busy and new picks go through the page's own path: the rows as their reads return them, then
  the catalogue read (`TasteCardDetails`) adds the premise and, for the first busy anime pick, the banner
  (so busy anime opens with the landscape card). The catalogue rows are seeded into `CatalogStore`'s detail
  cache with the prototype's sample premises (fixture data only).
- **+1 toast.** `progressToastRender` saves a real +1 through `HomeStore` (signed-in fixture account, a
  temporary progress outbox, Jujutsu Kaisen 6 → 7), lets the drain attempt it (the fixture has no client,
  so the attempt fails as offline), checks that the toast's Undo (`HomeProgressToasts.performUndo`) puts
  the count back to 6, saves the +1 again, and renders the page with the toast that +1 produces
  ("Progress saved." with Undo and ×) at the screen foot. Undo while the send is in flight and after its
  receipt is covered by `HomeToastRound3Tests`.
- **Raster (round 3).** Every 1 px = 1 pt render (`HomeAnimeLaneTests.render`, used for all primary Home
  renders, and `FirstRunSnapshotTests`) is drawn at the screen scale and block-averaged to 1 px = 1 pt (`KuroTests/FixtureRaster.swift`), as a 1x screen shows it. The earlier 1x
  `drawHierarchy` resampled the 3x snapshot with a sharpening filter and blurred 1 pt rules over three
  rows. `TEST_RUNNER_KURO_RENDER_SCALE=3` writes device-pixel renders to a temporary folder for diagnosis.
- **Re-rendered in round 3 (2026-11-02):** every `home-anime/`, `home-manga/` and `firstrun/` render, for
  the block-averaged raster, the darker word floor, and Taste's premise, heading, leaf and ink changes
  (German under de_DE), plus the new `firstrun/pager-*` composites. The 2x lane-harness renders
  (`home-manga/home-manga-*`, `home-anime-calendar-club-*`) keep their 2x raster.
- **Re-rendered in round 2 (2026-11-02):** every `home-anime/` and `home-manga/` render (the art-filled word
  and the switch rule changed; German under de_DE), every `firstrun/` render (now 1 px = 1 pt, like the
  references; previously 3x), plus the new toast renders. `taste-busy-anime-banner-joined-390.png` is gone:
  the primary busy render now shows the landscape card through the catalogue read.
- **Re-rendered in the Task 10 pass (en_GB):** every `home-anime/` and `home-manga/` render (German ones under
  de_DE), the first-run HomeView renders, and `restyle/folio-*` (the key caps and the 40 pt manga
  leaf face changed). Not re-rendered: the other `firstrun/` and `restyle/` renders and all of
  `detail/` (they were made under the default US region before this pass; the detail pages draw
  no `KuroAdvanceKey`, and a GB run changed only date formats there, so they were kept).
