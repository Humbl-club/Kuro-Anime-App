# Navigation contract integration — visual evidence (2 November 2026)

Rule: `docs/superpowers/specs/2026-11-02-navigation-contract-design.md` (CLAUDE.md Rule 5). Branch `kuro/prototype-fidelity`, local only, nothing deployed.

Nothing here reached the network. The in-process renders use nil clients or an in-process stub. The UI shots come from the owned simulator `7FC4B58A-…` running with `--kuro-fixture-host`, so every request failed locally.

## In-process renders (`KuroTests/NavigationEvidenceTests.swift`)

Each page is rendered inside a real `JourneyHost` at 390 pt. To regenerate, run `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1 … -only-testing:KuroTests/NavigationEvidenceTests`.

| File | What it shows |
|---|---|
| `detail-dark-top-390.png` | Anime detail as a journey's first page over dark artwork: ✕ only, as a round material key over the hero (N3, H2). |
| `detail-dark-scrolled-compact-bar-390.png` | Same page scrolled: the hero is gone and the paper compact bar shows the one-line title, an ink ✕ and a hairline (H1). |
| `detail-light-top-390.png` / `detail-light-scrolled-compact-bar-390.png` | The same over light artwork (spec §5: compact bar over light and dark artwork). |
| `detail-story-folded-390.png` / `detail-story-unfolded-390.png` | The story section folded ("More +") and unfolded ("Show less −"). It was unfolded through the session fold memory (F1–F3). |
| `character-pushed-390.png` | Character page pushed from the detail: Back (top-left) and ✕ (top-right) (N1, N3). Offline, so the works rail is empty. |
| `club-top-390.png` | Club detail as a journey's first page: settings and ✕ over the room, no Back. |
| `club-scrolled-compact-bar-390.png` | Club scrolled: paper compact bar with the club name, settings and ✕ (H1). |

## Owned-simulator UI shots (`KuroUITests/NavigationContractUITests.swift`, folder `ui/`)

These were written with `TEST_RUNNER_KURO_NAV_SHOTS=<dir>`. The app runs `--kuro-fixture-host --kuro-skip-auth --kuro-nav-fixture`. The fixture journey is built from the real navigation parts plus the real `AnimeDetailPage` over preview content (`Kuro/Views/Routing/NavigationFixture.swift`, DEBUG only).

| File | Chain |
|---|---|
| `ui/nav-01-level3.png` | Fixture level 3 (pushed twice): Back and ✕ in the compact bar. |
| `ui/nav-02-back-to-level1-position-kept.png` | Back twice: level 1 at the same scroll position. Row 25 sits within 2 pt of where it was (N1). |
| `ui/nav-03-detail-pushed.png` | The real anime detail pushed: Back and ✕ round keys over the hero, grabber visible (N8). |
| `ui/nav-04-character-level5.png` | Level 5, the character page pushed from the detail: Back and ✕. |
| `ui/nav-05-closed-to-start-page.png` | ✕ on level 5: the whole journey closed back to the Discover pager (N3/N4). |
| `ui/nav-06-tool-open.png` | Tracking editor (tool) over the detail. Its ✕ returns to the same detail, still pushed (N7). |
| `ui/nav-07-deep-link-target.png` | `kuro://anime/21` while a 3-level journey was open: the journey collapsed and the target opened as a new journey's first page (✕ only; offline loader) (N10). |

## Finding fixed during integration

The grabber was missing on a journey re-presented right after a collapse. A deep link closed the open root journey and opened the target 450 ms later. On iOS 26 that sheet came up without its grabber (N8): the grabber pixels were uniform. Raising `KuroNavigationCoordinator`'s dismissal wait to 700 ms brought it back. The fix was checked on the owned simulator with `simctl openurl` and a pixel check of the grabber area.
