# Judging: two Discover usability directions (2026-11-04)

**Judge:** design lead lane.

**Inputs**
- `guided.html`: "Guided: a short, finishable issue."
- `tactile.html`: "Every touch answers. Discover that rewards acting."
- The owner request (2026-11-03) and the approved plan, which binds the scope: where people get lost, the Discover contract R1–R8, and build items 1–12.
- Design authority:
  - the shipped daily issue (`docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md`)
  - `docs/discover-clubs-2026-11-03/understand/HOME_GRAMMAR.md`
  - the navigation contract (`docs/superpowers/specs/2026-11-02-navigation-contract-design.md`)
- The code on `kuro/details-songs-platform` (56d7239)

**Outputs**
- The binding spec: `docs/superpowers/specs/2026-11-04-discover-usability-design.md`
- The final mockup: `final.html`. It is Tactile's frames, plus a binding "differences" box and the copy fixes listed below.

## How the two were judged

**Rendering.** Each mockup was rendered in headless Chrome over CDP, with a private port and profile.
- The pages were captured at 1600 px and at 4700 px wide, because the frame strips run off the side at 1600 px.
- They were cropped and read at full resolution.
- Guided: 62 of 62 images loaded, with no horizontal page overflow.
- Tactile: 52 of 52 images loaded, with no horizontal page overflow.

**Text.** Each page's annotations, data map, copy table and open questions were read in full.

**Code checks.** Every claim that decides feasibility was checked against the code and the migrations. The verdicts below cite their sources.

## Criteria

| Criterion | Weight | What it measures |
|---|---|---|
| Usability for first-time users | 35% | Can someone new tell what each section is for, find the rest, act on a title without leaving, say "not for me", and know when they are done? Measured against the observed problems and R1–R8. |
| Satisfaction | 25% | Does every touch answer? Is coming back rewarded? Does the page feel finished instead of endless? |
| Consistency with Home and Discover | 25% | Does it use the shipped daily-issue and Home grammar (canvas, headings, keys, toasts, motion, branded states) without new paradigms? |
| Feasibility | 15% | Does it use data and components that exist? Is every backend need prepared-only? Can two UI lanes and a data lane build it without colliding? |

## Scores (0–10 per criterion; the total is weighted, out of 10)

| Direction | Usability (35%) | Satisfaction (25%) | Consistency (25%) | Feasibility (15%) | **Total** |
|---|---|---|---|---|---|
| **Tactile** | 8.5 | 9.0 | 8.0 | 7.5 | **8.35** |
| Guided | 8.0 | 7.0 | 8.5 | 7.0 | 7.73 |

**Winner: Tactile,** with grafts from Guided.

### Tactile: 8.35

**Usability (8.5)**
- It is the only direction that meets R3 on every card. Each card has a Plan key under its cover: trio, rail, index, See all and mood rows. The key never sits on the artwork.
  - Guided's trio and This-season rail have no key (frame 2), which misses the contract. That reverses the shipped §6.2 ("No key on the trio"). The approved plan makes R3 binding, so it is not an open question.
- The four mood keys sit in a 2 × 2 grid, so all four show at 390 pt.
  - In Guided's horizontal strip, the third key is clipped and the fourth is off-screen (frame 1, confirmed in the render).
- The contents use two columns of numbered jump rows with ↓, plus a count or "{n} new". That reads as links, not tags, and stays short enough that the first section starts in the first screen and a half.
- The end of the page keeps the lists that the six-section cap drops ("More lists: Top rated › Just added › Essential manga ›"), so nothing becomes unreachable.
- The filter words match the code. Short is ≤ 13 episodes (`DiscoverRailFilter.includes`, `EditorialDiscoverFrames.swift:387`), so "Up to 13 episodes" is right. Guided's "Under 13 episodes" and "13 or more" contradict the shipped rule (long is > 50).
- Deductions:
  - The pinned index word "Canon" is new vocabulary. The section is called "Essential anime" (fixed in the final: "Essentials").
  - It hides owned titles in This season, but the lead's rule is to mark them outside personal sections (fixed).
  - The preview says tapping it opens the title, and that is not implementable (see below).

**Satisfaction (9.0)**
- The two-beat feedback is the strongest idea in either direction. Beat 1 is the instant flip and haptic. Beat 2 is `.kuroConfirmStamp` and the toast, played only after a durable save, which is Home grammar rule 8. A failure plays `.kuroRestore` and shows "Not saved."
- A removed title is replaced from the section's own reserve, so the page visibly answers "Not interested".
- The end tally ("You planned 2, hid 1 and marked 1 as seen") rewards finishing, and every number in it is honest because it counts this session only.

**Consistency (8.0)**
- It uses the shipped daily issue unchanged where it can: the opening row, the three-word switch, the cover story on material, the shipped toast, the season-tab face for NEW, and the 28 × 2 mark that fades in place.
- Deductions:
  - The Plan key under every trio and rail cover adds density that Home doesn't have. That is accepted, because R3 requires it.
  - The Seen-it toast needs one more action than the shipped toast has. Tactile records this honestly as a grammar extension.

**Feasibility (7.5)**
- It found the facts that matter:
  - the serving exclusion at `20260806020000_serving_hardening_v1.sql:449`
  - the ≤ 13 rule
  - the German collision between "Abgeschlossen" (the filter) and "Abgeschlossen" (the Completed status word)
  - that a "Because you finished X" seed doesn't exist
  - that removals must never be a horizontal swipe inside the pager
- Deductions, shared with Guided:
  - **`.pass` for Not interested.** `pass` is stored at strength 0.00 and is excluded from the profile recompute (`20260731090000_taste_deck_pass_memory.sql:1-30, 891-926`). It is memory only; it teaches nothing. The deck's own "NOT FOR ME" sends `.skip` (−0.45, `TasteDeckView.swift:450`). So "You'll see fewer like this" would be false with `.pass`.
  - **"Tapping the preview opens the title."** SwiftUI's `contextMenu(menuItems:preview:)` has no preview-commit action. Tapping the lifted preview only dismisses it. Open has to be a menu item.
  - **Cozy and Intense from realms.** That would need a new read RPC. The curated rails `cozy_comfort_*` and `dark_serious_*` already exist, and the live `curated_rail_cards(p_rail_id, p_limit, p_exclude_seen)` is granted to `authenticated` (`20260205231000_curated_rails.sql:189`).

### Guided: 7.73

**Usability (8.0)**
- Its strongest idea is a one-line question under every section and in every contents row. That idea is grafted into the final, with the question under the heading.
- The explicit end, and "Top rated / Just added become sorts", are both good.
- Deductions:
  - The mood strip is clipped.
  - The trio and the season rail have no key (R3).
  - The six-row path card with questions is about 300 pt tall. It pushes every section below the first screen, so the first screen holds only navigation.
  - Its filter words don't match the code.

**Satisfaction (7.0)**
- The "0 of 6 read" progress bar turns the issue into homework. "Read" also has a fuzzy definition: the last row scrolled under the pinned track.
- The feedback is described as one beat (haptic + stamp), with no failure path.

**Consistency (8.5)**
- It is very close to the shipped issue: the path card is a glance card, and the trio is unchanged.
- It loses half a point because it drops the Airing-today glance from All.

**Feasibility (7.0)**
- It has the same `.pass` error.
- Its menu subtitle "Seen it: shows less like it" is wrong, because `known` is +0.25.
- It cites `get_media_ladder` as a franchise key, but that is one RPC per title and can't dedupe a page.
- It leaves three data questions open that this judging answered from the code.

## Facts checked in the code (both mockups depended on them)

| Question | Answer | Source |
|---|---|---|
| Do Discover reads hide passed or "known" titles? | **No.** `discover_bundle` never reads `taste_signal_events`; it excludes only `user_lists`. `fetch_because_you_rail` does exclude deck signals. | `20260326221000_discover_new_to_you_rotation.sql` (0 references); `20260731100000_discover_p1.sql:331, 359` |
| Which signal teaches "fewer like this"? | `skip` (−0.45). `pass` is 0.00 and is excluded from the recompute. `known` is +0.25. `retract` deletes the row. | `20260731090000_taste_deck_pass_memory.sql:180-240, 880-930` |
| Is there a franchise key on the client? | **No.** `media_franchise_components` (same-type components) has no client grants. `SeriesGrouping` is a continuity decision function, not a key. Card models have no franchise field. | `20260804140000_franchise_components_and_blend_dedupe.sql:71-84`; `Packages/KuroModules/Sources/KuroLibrary/SeriesGrouping.swift`; `Catalog/MediaDisplayModels.swift:168` |
| Can moods be built from existing data? | **Yes.** `short_one_season_*`, `cozy_comfort_*` and `dark_serious_*` curated rails, read through `curated_rail_cards` (limit ≤ 120, no offset, excludes the caller's list). | `20260205231000_curated_rails.sql:62-189`; `20260207020000_curated_rails_more_vibes_seed.sql` |
| Can the preview open the title on tap? | **No.** There is no SwiftUI preview-commit; Open is a menu item. | SwiftUI `contextMenu(menuItems:preview:)` API |
| Can the tracking editor open preset to Completed? | **Not yet.** `TrackingEditorRequest` has only `media` and `TrackingDraft(entry: nil)` starts at `.planning`. The fix is an additive `initialStatus` field. | `Views/Routing/KuroRoutes.swift:74`; `Views/TrackingDraft.swift:31` |
| Can the shipped toast take a second action? | **No.** `TastePlanToastView` is message + Undo + ×, and lives in read-only `TastePicksView.swift`. | `TastePicksView.swift:757` |
| Are routes from pager pages gated? | **Yes.** Every route read from `\.kuroRoutes` inside a pager page is wrapped by `KuroRoutes.gated(by:)`. A new route field must be added there. | `Views/Routing/KuroRoutes.swift:225-256` |
| Does the analytics owner allow new event names? | **Yes.** It is the `concierge_events` insert; no name allowlist was found. Payloads already carry entity ids (`club_id`). | `Services/ConciergeAnalytics.swift:115`; `ClubDetailView.swift:551` |

## What the final takes from each direction

**From Tactile (the base):** every frame and its order, plus these elements:
- the 2 × 2 mood keys and the two-column numbered contents
- the pinned one-line index that turns ink as you pass sections
- the NEW tabs and "{n} new since {weekday}" markers
- Plan keys under every cover
- the preview with "Why it's here"
- two-beat feedback, removal with refill, and the Seen-it toast with "Add as Completed ›"
- the Essentials progress hook with half segments for titles you are watching
- the end with its tally, Browse, Search and More lists
- the See all page, with sorts, chips, a match count and paging
- mood journeys that state their rule, and the hard constraints (no swipe removal, native menu, monochrome, one toast)

**From Guided:**
1. A one-line purpose (the "question") under every section heading. This is R1.
2. One-line explanations under the risky menu items, with corrected copy: Not interested reads "Hides it and shows fewer like it."; Seen it reads "Hides it here. You can add it as Completed."
3. The other moods as a switch row at the top of a mood journey.
4. The "Hide my list" chip on See all and mood journeys.
5. Owned titles keep their status word in This season ("Watching · Ep 5").
6. The empty mood journey as a `HomeQuietCard` that offers to loosen one filter.

**New in the final (the judge's fixes):**
1. Not interested → `.skip`; Seen it → `.known`; Undo → `.retract`.
2. Open is a menu item. Tapping the preview only dismisses it.
3. "Essentials" replaces "Canon" in the pinned index.
4. The refine words become Any length · Up to 13 episodes · Over 50 episodes · Finished. German uses "Fertig erschienen" so it doesn't collide with the Completed status word. These are Discover-owned strings; `DiscoverRailFilter` keeps its labels for Entities.
5. Moods read the curated rails through `curated_rail_cards`, with no realm RPC.
6. Franchise dedupe:
   - The key is the server component label, from a prepared RPC.
   - Until that RPC is live, the fallback is a conservative title stem plus the id.
   - Anime and manga are not merged into one franchise on All (owner decision, spec §12).
7. Essentials claims its titles right after the cover story, so the canon list survives dedupe, and the progress hook counts the full curated list.
8. A deterministic six-section cap: anything dropped moves to More lists.
9. The R1 and R6 examples in the plan ("Because you finished X", "Under 13 episodes") are shown in their truthful form: "Because you loved {X}" (the existing route title from `reason_title`) and "Up to 13 episodes". The reasons are recorded in spec D3 and D9.
