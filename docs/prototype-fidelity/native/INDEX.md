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

| Reference | Primary native render | Supplementary |
|---|---|---|
| `ref-home-busy-anime-390.png` | `home-anime/home-busy-anime-390.png` | `home-anime/home-busy-anime-de-390.png`, `home-anime/home-busy-anime-ax5-390.png`, `home-manga/home-anime-calendar-club-390.png`, `home-manga/home-anime-calendar-club-ax5-390.png` (lane harness: calendar + club only) |
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
| `ref-home-new-anime-390.png` | `firstrun/home-new-anime-homeview-390.png` | `firstrun/home-new-anime-390.png` (first-run harness: stand-in switch and opening, not HomeView), `firstrun/home-new-anime-de-390.png`, `firstrun/home-new-anime-ax5-390.png`, `firstrun/home-new-anime-prototype-block-390.png`, `firstrun/home-new-anime-loader-390.png` (harness) |
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
| `ref-home-new-manga-390.png` | `firstrun/home-new-manga-homeview-390.png` | `firstrun/home-new-manga-390.png` (first-run harness: stand-in switch and opening, not HomeView), `firstrun/home-new-manga-de-390.png`, `firstrun/home-new-manga-ax5-390.png`, `firstrun/home-new-manga-prototype-block-390.png`, `firstrun/home-new-manga-loader-390.png` (harness) |
| `ref-home-new-manga-320.png` | `firstrun/home-new-manga-homeview-320.png` | `firstrun/home-new-manga-320.png` (first-run harness: stand-in switch and opening, not HomeView) |
| `ref-home-new-manga-430.png` | `firstrun/home-new-manga-homeview-430.png` | `firstrun/home-new-manga-430.png` (first-run harness: stand-in switch and opening, not HomeView) |
| `ref-detail-anime-390.png` | `detail/detail-anime-390.png` | `detail/detail-anime-bundle-390.png`, `detail/detail-anime-untracked-390.png`, `detail/detail-anime-untracked-de-390.png`, `detail/detail-anime-untracked-de-320.png`, `detail/detail-anime-ax5-320.png`, `detail/detail-anime-de-390.png` |
| `ref-detail-anime-top-390.png` | `detail/detail-anime-top-390.png` | `detail/detail-anime-top-320.png`, `detail/detail-anime-top-ax5-320.png` |
| `ref-detail-manga-390.png` | `detail/detail-manga-390.png` | `detail/detail-manga-bundle-390.png`, `detail/detail-manga-untracked-390.png`, `detail/detail-manga-untracked-de-390.png`, `detail/detail-manga-untracked-de-320.png`, `detail/detail-manga-ax5-320.png` |
| `ref-detail-manga-top-390.png` | `detail/detail-manga-top-390.png` | `detail/detail-manga-top-320.png`, `detail/detail-manga-top-ax5-320.png` |
| `ref-taste-busy-anime-390.png` | `firstrun/taste-busy-anime-390.png` | `firstrun/taste-busy-anime-de-390.png`, `firstrun/taste-busy-anime-ax5-390.png`, `firstrun/taste-loading-anime-390.png`, `firstrun/taste-busy-anime-banner-joined-390.png`, `firstrun/taste-busy-anime-planned-390.png` |
| `ref-taste-busy-manga-390.png` | `firstrun/taste-busy-manga-390.png` | `firstrun/taste-busy-manga-de-390.png`, `firstrun/taste-busy-manga-ax5-390.png`, `firstrun/taste-loading-manga-390.png` |
| `ref-taste-new-anime-390.png` | `firstrun/taste-new-anime-390.png` | `firstrun/taste-live-new-anime-390.png` (TastePicksView itself over the seeded bundle) |
| `ref-taste-new-manga-390.png` | `firstrun/taste-new-manga-390.png` | - |

Every reference has a primary native render (38 references).

## Where each render comes from

| Folder | Test | What it renders |
|---|---|---|
| `home-anime/` | `KuroTests/HomeAnimeLaneTests.swift`, `animeHomeRenders` | `HomeView`, anime, busy / full / undated / quiet |
| `home-manga/home-{state}-manga-*` | `KuroTests/HomeAnimeLaneTests.swift`, `mangaHomeRenders` | `HomeView`, manga, busy / full / undated / quiet |
| `home-manga/home-manga-*`, `home-anime-calendar-club-*` | `KuroTests/HomeMangaLaneTests.swift`, `HomeMangaLaneSnapshotTests` | lane-4/5 component stacks (2x scale) |
| `firstrun/home-new-*-homeview-*` | `KuroTests/FirstRunSnapshotTests.swift`, `newAccountHomeView` | `HomeView` for a new account (latched, empty Library, seeded Discover bundle) |
| `firstrun/` (other) | `KuroTests/FirstRunSnapshotTests.swift` | first-run harness, `TastePageContent` (the content `TastePicksView` hosts), search, collection invitation; see `firstrun/NOTES.txt` |
| `detail/` | `KuroTests/DetailAnimeSnapshotTests.swift`, `DetailMangaSnapshotTests.swift` | the prototype detail pages over a complete fixture bundle |
| `restyle/` | `KuroTests/RestyleSnapshotTests.swift` | the remaining restyled screens (no reference in `reference/`) |

## Fixture notes for the Home renders (read before judging a difference)

- **Manga sixth title.** The references show Vagabond. The fixture art for that slot is Vinland Saga's
  cover, so the fixture names it Vinland Saga rather than put a wrong cover under a real title.
- **Manga busy headline.** "4 new chapters" is computed, not written: Chainsaw Man 24 against chapter 26
  ahead, Jujutsu Kaisen 19 against 22, SPY x FAMILY 4 against 6 (released = next known chapter - 1).
  Solo Leveling is finished at 9 (a backlog is never "new"). So Jujutsu Kaisen reads Ch. 19 and SPY x
  FAMILY Ch. 4 where the reference shows 16 and 5.
- **Manga quiet keys.** Every title is caught up and the page says "Keep reading." with the quiet line,
  but only Solo Leveling (at its total) shows the ✓ key: Home keeps the manga +1 capped by the catalogue
  total only (`HomeView.keyState`), while the reference draws ✓ on the first three. A product rule, not
  a fixture artifact.
- **Manga undated headline.** With only undated announcements nothing released is known, so the page says
  "Keep reading." (no count, no quiet line) where the reference shows "4 new chapters".
- **Club room.** The fixture account has one club, "Sunday Club" (activity two hours ago), so the club
  room shows the bundle's notes. The anime notes are about Attack on Titan, the manga notes about Berserk.
- **New account.** The selected medium word shows the mountain (empty shelf), the picks come from the
  seeded Discover bundle (`HomeNewAccount`'s own loader), and the page sits on the medium's canvas.

