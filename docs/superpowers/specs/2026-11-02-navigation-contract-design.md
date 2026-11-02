# Navigation contract (binding, 2026-11-02)

**Owner request (2026-11-02, verbatim intent):** every page is properly connected and implemented, also detail pages and tertiary pages (open a detail, tap something inside it, tap again, and so on). All movements are perfectly implemented: swipe back, swipe forward, there is always a back button, and somebody can always go back to the last page they came from. "The collapse part is the most important part." Asked which collapse, the owner answered **all of them**: closing back down, the shrinking header, and folding sections.

This file is the locked rule. CLAUDE.md points here; every screen, today and in future, must satisfy it. Evidence for the starting state: the navigation audit of 2026-11-02 (summarised in §6).

## 1. The model

Kuro has three levels.

1. **Pages**: the pager (Taste / Home / Discover / Browse / Collection / Clubs). Horizontal swipe between pages, header switches. A page never needs a back button.
2. **Journeys**: anything opened from a page or from the header (a title, a club, Search, Profile, Browse-as-sheet, See all, Season overview, …) opens as **one sheet that hosts a navigation stack**. Every further tap inside the journey (another title, a character, a staff member, a studio, an author, a club, a season, a source/adaptation, a list) **pushes** a page onto that stack. It never stacks a second content sheet on top.
3. **Tools**: short task sheets with their own Save/Cancel (tracking editor, add to club, verdict picker, providers, filters, create/join club, contact, import, reset password, share). They open over the current journey page and close back to exactly that page.

Rationale (my call, recorded): pushing inside one sheet gives the system edge swipe-back, a back control on every page, and one gesture (swipe the sheet down / tap ✕) that collapses the whole journey back to the page it started from. Sheets on sheets gave none of that. "Swipe forward": iOS has no forward gesture inside an app; forward is always a tap, and horizontal swiping between the pager's pages stays as it is (§1.1).

## 2. Movement rules (every journey page)

- **N1 Back.** Every pushed page shows a back chevron, top-left, 44 pt hit area, label "Back"/"Zurück" for VoiceOver, that pops exactly one level to the page the user came from, scroll position preserved.
- **N2 Edge swipe-back.** The interactive pop gesture works on every pushed page, including pages that draw their own header or hide the system bar (the gesture must be restored explicitly when the bar is hidden). Swiping halfway and letting go returns to the current page unchanged.
- **N3 Close the journey ("collapse").** Every journey page, pushed or root, shows ✕ top-right ("Close"/"Schließen"). ✕ and swipe-down on the sheet dismiss the **whole** journey and land on the page it was opened from, unchanged. The first page of a journey shows ✕ only (no back chevron).
- **N4 One-move collapse.** ✕ (or swipe-down) is the single action that returns from any depth to the page the journey started on; no separate "back to start" control is added.
- **N5 No duplicates.** Opening a title/club/person that is already in the current journey's stack pops back to that page instead of pushing a copy (season ping-pong A → B → A returns to A). The page currently on top is never pushed again (double tap does nothing).
- **N6 Depth.** No fixed limit; N5 keeps cycles bounded. Memory: pages below the top may release heavy images (existing ImagePipeline caches).
- **N7 Tools return to their page.** A tool sheet closes to the journey page that opened it (never to the root, never dismissing the journey). Unsaved input: swipe-down is blocked while the form has changes, and Cancel asks "Discard changes?" (`AddToListSheet`, `ContactSheet`, create club/rail/poll, import busy state keeps Stop reachable).
- **N8 Every sheet is closable.** Every sheet (journey or tool) has a visible close or cancel control **and** a visible grabber when it can be swiped; no sheet relies on swipe-down alone.
- **N9 Every tap goes somewhere.** Anything that looks tappable (cards, rows, names, avatars, "In your club rails" cards, club "This Week" entries, credits rows, source/adaptation rows) opens its target by pushing inside the journey. Plain text is used only when no target exists.
- **N10 Deep links and notifications.** A `kuro://` link first collapses every open journey, tool and cover (with the onboarding cover finishing first), then opens its target as a new journey on the root. A link to something already on top of the current journey just brings that journey to the front. Page links (`collection`, `discover`) collapse everything, then switch the page.
- **N11 Leaving to another page on purpose.** Actions that intentionally switch the pager (Profile → Your lists → a list; "Browse the catalogue" in the series world) must instead push the destination inside the current journey when it can be shown there; where it cannot, they say so in the UI ("Opens Collection") and close the journey with the same animation as ✕.

## 3. Collapse: the shrinking header

- **H1** On anime and manga detail pages, club detail and person/studio pages, the hero (artwork / name block) scrolls away and a **compact bar** fades in at the top: title (one line, truncated), back chevron (if pushed) and ✕. The bar is the prototype's paper colour with a hairline; text and controls keep ≥ 4.5:1 contrast on it.
- **H2** Back and ✕ are visible at every scroll offset: over the artwork they sit on the existing round material buttons; in the compact bar they are plain ink glyphs. They never scroll away, never overlap the status bar, and keep 44 pt.
- **H3** The transition is tied to scroll offset (no jump); Reduce Motion: cross-fade only.
- **H4** Pull-down at the top of a journey's first page still dismisses the sheet (scroll view at rest at the top); on pushed pages pull-down never pops.

## 4. Collapse: folding sections

- **F1** Foldable sections (story "Read more", episodes/chapters "More", songs "Show all", coverage/adaptation guides, Profile "Advanced", and any future section with more than its preview) expand and collapse with the prototype easing (`KuroMotion.settle`), Reduce Motion: no height animation, instant.
- **F2** The control states what it does ("Read more" / "Show less", "Show all 12 songs" / "Show fewer") in EN/DE, is a real button (VoiceOver: "expanded"/"collapsed" value), and stays in view after collapsing (the page scrolls the section header back into view if the collapse would leave the user below it).
- **F3** Fold state is remembered for the session per title/club and section (going back to a page keeps what was open); it resets on a new app launch.

## 5. Verification (how "done" is proven)

- Pure policy tests: journey stack push/pop, N5 dedupe (pop-to-existing), N10 deep-link collapse order, tool-return rule.
- UI tests on the owned simulator (`7FC4B58A-…`, by UUID): Discover card → anime detail → character → appearance (manga) → author → work: back chevron returns level by level with scroll position kept; edge swipe-back works on each pushed page; ✕ on level 5 lands on Discover; swipe-down on level 3 lands on Discover. Same for Search → result → season → source; Club → rail item → detail → add to club (tool) → cancel returns to the detail. A deep link while Profile + a journey are open lands on the target with ✕ returning to the page.
- Snapshot/fixture renders of the compact bar over light and dark artwork, and of folded/unfolded sections.
- `scripts/quality-gates/check_navigation.sh` (new): fails on a `.sheet(` whose content shows a routed leaf without the journey host, on `.navigationBarBackButtonHidden(true)` / hidden bars without the restored pop gesture, and on a sheet without a close/cancel control.

## 6. Starting state (audit, 2026-11-02)

- No `NavigationLink`/`navigationDestination` in `Kuro/`: nothing is pushed; edge swipe-back exists nowhere. Every in-detail tap stacks another sheet via a per-sheet `.routePresenter()`; no close-all; `RoutePolicy` dedupes only within one slot (season ping-pong stacks forever).
- Deep links go to the root presenter, which sits under the Profile/Search/Concierge sheets and the onboarding cover: likely ignored while a sheet is open; a new link tears down the open stack.
- No close control: Home season overview (`HomeView.swift:1253-1320`), verdict sheets (`QuickVerdictActionCard.swift:506-507, 607-608`, grabber hidden too).
- Dead taps: "In your club rails" cards on detail (`ClubActivitySection.swift:13`), club "This Week" entries (`ClubDetailTabComponents.swift:637-692`).
- Lost history: Profile → Your lists (dismisses Profile, switches pager), Profile → Concierge review, import results; creating a club doesn't open it.
- Swipe-down discards unsaved input silently (tracking editor, contact, create club/rail/poll).
- Detail pages have no collapsing header (hero scrolls away, ✕ pinned); club detail is the only one. Detail grabber hidden once loaded.
- Content gaps found on the way (fix with the push work, N9): characters never link to voice actors; the staff sheet lists anime only (an anime's "Original work" author shows anime, not their manga); ladder-sourced "Original work" is plain text.
- Unreachable legacy views (not part of this contract; candidates for deletion in a separate, owner-approved cleanup): `CreditsSection`, `AdaptationPathSection`, `ExternalLinksSection`, `GenreHubView`, `TasteDeckView`, `NextPickSection`, `SimilarSection`, `Episodes/ChaptersSection`, legacy action docks; `SeriesAnimeDetailView`/`SeriesMangaDetailView` are referenced only by tests (CLAUDE.md wrongly says they are the flag-on detail views).

## 7. Out of scope

Visual redesign of pages (the prototype stays the authority), new features, deleting the legacy views (separate decision), iPad split views.
