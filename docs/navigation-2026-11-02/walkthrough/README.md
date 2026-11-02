# Live walkthrough — navigation contract (2026-11-02)

Owner request: "go through it all". Every chain below was driven on the owned simulator
(`7FC4B58A-…`) against **live production data**, signed in as the dev simulator account, with the
new Home on (`--ff-on=series_foundation_v1 --ff-on=series_home_native_v1`). Driver:
`KuroUITests/LiveWalkthroughUITests.swift` (skipped unless `TEST_RUNNER_KURO_WALK=1`; screenshots (JPEG)
and accessibility trees land here via `TEST_RUNNER_KURO_WALK_DIR`). Rules: `docs/superpowers/specs/2026-11-02-navigation-contract-design.md`.

## Chains walked

| Chain | Screens | Result |
| --- | --- | --- |
| W1 Home → Cowboy Bebop → Director (Shinichirou Watanabe) → Carole & Tuesday → studio BONES | `w1-*` | Journey root shows ✕ only; every pushed page shows ← and ✕; shrinking header turns into the "Cowboy Bebop" compact bar; "More episodes" ⇄ "Fewer episodes" folds (Expanded/Collapsed) and stays in view; Back pops one level; edge swipe-back pops and keeps the filmography row's scroll position; ✕ from level 3 and swipe-down from level 2 both land on Home. PASS |
| W0 Swipe vs tap on Home | `w0-*` | **Bug found and fixed**: a horizontal swipe starting on the scene artwork opened the title. Now the swipe turns to Discover and a plain tap still opens it (`67e78a1`). |
| W2/W7 Search → result | `w2-*`, `w7-*` | Search is a journey (title bar, ✕); results push with ←; compact "Berserk" bar. **Fixed**: after switching scope the list kept its old offset and hid the first result under the filters (scroll resets per scope). |
| W3 Discover → See all → card → Back → ✕ | `w3-*` | PASS. **Fixed**: Today's pick showed a raw `<br>` (`356ac51`). |
| W4 Collection, Clubs pages | `w4-*` | Render; Clubs empty state (dev account has no clubs; club journeys are covered by the offline `NavigationContractUITests`). |
| W5/W9 Profile and every row | `w5-*`, `w9-*` | Profile is a journey with compact bar. Your clubs and Data sources push (← returns at the same scroll); Contact us and Import from AniList are tool sheets that close back to Profile; "Show advanced" ⇄ "Hide advanced"; "Open Collection" collapses Profile and lands on Collection as its hint says. **Fixed**: import screen said "This MVP uses public lists only. Private entries will need OAuth later." |
| W6 Deep link while Profile is open | `w6-*` | `kuro://anime/117` collapses Profile, opens Cowboy Bebop as a fresh journey (no ←), ✕ lands on Home. PASS (links use Kuro ids, not AniList ids). |
| W8 Manga: `kuro://manga/5` → Guts → anime adaptation → author Kentarou Miura → ✕ | `w8-*` | PASS. **Fixed**: releasing manga on work cards read "airing" (now "publishing"/"erscheint"). |
| W10/W12 Collection → detail → list editor → Save | `w10-*`, `w12-*` | The status mark opens the editor tool; Save closes back to the detail (N7). (The first run tapped the row's +1 by mistake; the dev account's Cowboy Bebop progress was set back to 0/26 through the editor.) |
| W11 Home Planned row, Taste | `w11-*` | Planned row opens a journey; swipe-down returns to Home; Taste renders. |

## Open (not navigation defects)

- Characters show no voice actors (no character→voice-actor data in the catalogue yet).
- Studio/staff work rows show exactly three cards at rest with no edge peek, so the sideways scroll is not obvious.
- Live club chain not walked (dev account has no club; creating one would write production data).
- VoiceOver order and the escape gesture need a device check (VoiceOver does not run in the simulator).
