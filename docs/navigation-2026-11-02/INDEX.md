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
| `detail-dark-mid-collapse-390.png` / `detail-light-mid-collapse-390.png` | Part way through the collapse (p ≈ 0.3, review fix H2): the white ✕ still sits on its whole material key over a half-faded paper bar. There is one glyph colour at a time, never a white/ink blend. |
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
| `ui/nav-07-deep-link-target.png` | `kuro://anime/21`, delivered to the RUNNING app (`XCUIDevice.shared.system.open`), while a 3-level journey was open: the journey collapsed and the target opened as a new journey's first page (✕ only; offline loader) (N10). |
| `ui/nav-08-deep-link-keeps-journey.png` | The same link while anime 21 was already on top of the open journey: the journey was kept, Back still pops to the level below (N10 keep-journey). |
| `ui/nav-09-pager-sheet-open.png` | Review fix N10: the Browse pager page's own Filters sheet is open (no fixture journey, `--kuro-start=browse`). |
| `ui/nav-10-pager-sheet-link-target.png` | `kuro://anime/21` sent to the running app while those filters were open. The filters closed first, then the target opened as a new journey (✕ only, offline loader). After ✕ the pager is back and Filters opens again. |

## Findings during integration

The grabber was missing on a journey re-presented right after a collapse. A deep link closed the open root journey and opened the target 450 ms later. On iOS 26 that sheet came up without its grabber (N8): the grabber pixels were uniform. Raising `KuroNavigationCoordinator`'s dismissal wait to 700 ms brought it back. The fix was checked on the owned simulator with `simctl openurl` (same app process, confirmed in the system log) and a pixel check of the grabber area; one sample per setting.

`XCUIApplication.open(URL)` relaunches the app, so a deep-link UI test using it never runs the collapse; the link is handled on a cold launch instead. The deep-link tests (here and in `NavshellUITests`) now deliver links through `XCUIDevice.shared.system.open`. The system log showed the same process and coordinator collapsing an open journey (top `navfixture:level:3`), and keeping one whose top was `media:anime:21`.

H4 negative control: with Search's `.kuroJourneyRefreshable` temporarily reverted to `.refreshable`, `testPullDownOnSearchJourneyDismissesIt` failed (pull-down did not dismiss Search); with the fix it passes.

## Final state after the review round (2 November 2026, evening)

Fourteen reviewer findings were checked against the code; all were real. Three were duplicates of another finding (pager-page sheets N10, the covered kept journey, Profile Advanced), which leaves eleven distinct fixes. None was rejected.

| Finding | Fix |
|---|---|
| N10 (major, two reports): pager-page sheets are invisible to the collapse | Every page-level sheet registers as a layer (`.kuroNavigationLayer`, with a new `item:` overload for item sheets): Clubs create/join, Collection classify/import, Browse filters, Home import/recovery, the verdict card's editor, Concierge's AniList/import-review sheets and Why-this. Registrations are unique per view instance (`"<name>#<uuid>"`). Last resort: something presented over the pager that no layer accounts for is dismissed through UIKit (`foreignSheetOpen`, root controller resolved by `KuroPresenterProbe`; DEBUG logs it). |
| N10: a link to a header journey's top closed it | `ShellJourneyHost(root:layer:)` attaches its navigator; the snapshot carries `sheetJourneyTops` / `sheetJourneyTools`, and the plan keeps that journey (`.closeSheetJourneyTool(id)` + `.keepJourney`). |
| N10 keep path (two reports): page-local tool sheets stayed over the kept page | Layers record the journey they are presented in (`JourneyContext.journeyID`). The keep plan emits `.closeJourneySheets(ids)` for the kept journey: verdict / providers on anime and manga detail, and club settings / new rail / new poll / add a title. This is the "proper" variant: the journey and its stack are kept, and only the covering sheets close. |
| N10: second link inside the dismissal window | `Snapshot.dismissalInFlight` (an unfinished `collapseTask`) makes the plan emit `.awaitDismissalInFlight`, so the second link waits before presenting; the last link wins. |
| Swift 6 isolation (major): `kuroJourneyRefreshable` dropped MainActor | The action is `@MainActor @Sendable () async -> Void`, installed with `content.refreshable { await action() }`. Release build: the two warnings the review found (`JourneyHost.swift:169`, `ClubDetailView.swift:194`) are gone, and no warning is new (the remaining unique warnings match the reviewer's build except those two). |
| H2 contrast (major): white and ink glyphs cross-faded over a fading backdrop | `KuroCollapse.handover` = 0.5. Below it there is a whole material disc with a white glyph (≥ 7:1). From it there is an ink glyph on a paper bar that is solid by the handover (`barOpacity`). The title shows from the handover (`titleOpacity`). One glyph colour at a time (`KuroJourneyChromeKey.glyphIsWhite`). |
| Focus order / escape | The chrome bar and `JournalStatusBar` are `.accessibilityElement(children: .contain).accessibilitySortPriority(1)`. `.kuroJourneyEscape()` (two-finger Z: Back when pushed, ✕ on a journey's first page) is applied to every `.kuroJourneyChrome` page and to club detail. Not checked with VoiceOver on a device. |
| N7: the AniList import sheet cancelled silently | `.interactiveDismissDisabled(isBusy)`. While AniList is read or the import is sent, Done becomes Stop with the chooser's confirmation (`ImportChooserTopControl` copy). Stop resets the form and keeps the sheet open. |
| N8: grabbers | `.presentationDragIndicator(.visible)` on the AniList import sheet, `ImportWorkflowSheet`, `ImportCatalogMatchPicker`, the chooser's Concierge review sheet and `StreamingServicePickerSheet`. |
| §1/N9: chooser review stacked a sheet over a journey | Inside a journey (Profile) the chooser pushes `ShellJourneyPages.concierge(prompt:review:true, …)` onto that journey and closes. The sheet stays only for journey-less callers (Onboarding, the pager's Collection / Home). |
| F1–F3: Profile "Advanced" | `KuroFoldButton` bound to `folds.binding(page: "profile", section: "advanced")` ("Show advanced" / "Hide advanced", EN/DE). Fold toggles run in `KuroFold.transaction` (marked `isKuroFold`), and Profile's animation suppression now skips those transactions. |

### Verification (owned simulator `7FC4B58A-…`, `CODE_SIGNING_ALLOWED=NO`, no parallel testing)

- KuroTests: 872 tests in 143 suites passed. They include new `JourneyPolicyTests` cases:
  - header-journey keep;
  - kept journey closes its page sheets;
  - pager-page sheet and foreign presentation;
  - dismissal in flight (pure, and through the coordinator);
  - coordinator snapshot of a header journey;
  - composited chrome contrast at every progress 0…1 over five artwork tones and five materials: glyph ≥ 3:1, title ≥ 4.5:1.
- UI: `NavigationContractUITests` 11/11 (new: `testDeepLinkCollapsesPagerPageSheetThenOpensTarget`) and `NavshellUITests` 4/4.
- Negative controls for the new UI test:
  - Browse's layer removed and the foreign fallback disabled: the test FAILS ("the pager page's sheet collapsed first").
  - Only the layer removed: the UIKit fallback alone passes it, including reopening Filters afterwards (SwiftUI reset the binding).
- Release build (generic iOS) succeeded. `check_navigation.sh`: 0 offenders.

## Per-rule compliance

| Rule | How it is met | Test / evidence |
|---|---|---|
| §1 three levels | Pager pages; journeys = one `JourneyHost` sheet with a `NavigationStack`; tools = the host's tool slot or page-local tool sheets with `.kuroLeavesJourney()` | `JourneyPolicyTests`, `NavdetailTests`, `NavclubsTests`; gate `check_navigation.sh` |
| N1 Back | `KuroJourneyChrome` draws Back only when `JourneyContext.isPushed`; `pop()` removes one level; VoiceOver "Back"/"Zurück" and escape action | `testBackChevronPopsOneLevelKeepingScrollPosition`, `nav-02` |
| N2 edge swipe-back | `KuroInteractivePopEnabler` / `KuroPopGestureDelegate` restore the pop gesture on hidden-bar pages | `testEdgeSwipeBackPopsAndHalfSwipeStays`, `JourneyPolicyTests` (allowsPop) |
| N3 ✕ closes the journey | ✕ on every journey page → `JourneyNavigator.close()`; first page shows ✕ only | `testCloseOnLevelFiveLandsOnStartPage`, `testSwipeDownOnLevelThreeCollapsesJourney`, `nav-05` |
| N4 one-move collapse | ✕ / swipe-down dismiss the one sheet from any depth | same as N3 |
| N5 no duplicates | `JourneyPolicy.push` pops to an existing page; top never re-pushed | `testOpeningAPageInTheStackPopsBackToIt`, `NavdetailTests` season ping-pong, `NaventityTests` |
| N6 depth | No limit; N5 bounds cycles | `JourneyPolicyTests` |
| N7 tools return | Tools open in the host's tool slot / page-local sheets over the current page. `KuroDiscardGuard` blocks swipe-down on dirty forms. Both import sheets (chooser, AniList) turn Close/Done into a confirmed Stop while busy | `testToolCloseReturnsToItsDetail`, `NavclubsTests` (discard guard, import chooser top control), `nav-06` |
| N8 every sheet closable | Every journey (`JourneyHost`) and tool sheet has a visible close/cancel and `.presentationDragIndicator(.visible)` where swipeable (review fix: AniList import, import workflow, match picker, chooser review, streaming services) | `NavdetailTests` grabber test; UI shots `nav-03`, `nav-10` |
| N9 every tap goes somewhere | Rows, cards, credits, club rail / This-week entries push; chooser review pushes inside Profile's journey | `NavdetailTests`, `NavclubsTests`, `NaventityTests`, `NavshellTests` |
| N10 deep links | `KuroNavigationCoordinator.collapseThenOpen` / `collapseThen` → pure `NavigationCollapsePolicy.plan`. The cover finishes first. Every registered sheet closes: header, pager-page and journey-page sheets, plus the UIKit fallback for unregistered ones. A link inside the dismissal window waits. A link to the top of the root or a header journey keeps it and closes only its tool and page sheets | `JourneyPolicyTests` (N10 cases + coordinator), `NavshellTests`, `testDeepLinkCollapsesJourneyThenOpensTarget`, `testDeepLinkCollapsesPagerPageSheetThenOpensTarget`, `testDeepLinkToTopPageKeepsJourney`, `testDeepLinkCollapsesProfileJourneyThenOpensTarget`, `nav-07`–`nav-10` |
| N11 leaving on purpose | Profile → Your lists says "Opens Collection" and collapses like ✕ | `NavshellTests` ("Your lists says where it goes") |
| H1 compact bar | Paper bar + hairline + one-line title fades in with the scroll (`kuroCollapseTracking`) on anime/manga detail, entity pages, club detail | `NavdetailTests`, `NavclubsTests`, renders `detail-*-scrolled`, `club-scrolled` |
| H2 controls always visible, contrast | One glyph colour per state switched at `KuroCollapse.handover`; disc whole before it, bar solid from it; 44 pt keys; sort priority puts them first for VoiceOver | `JourneyPolicyTests` "H2: chrome glyphs ≥ 3:1 …", renders `detail-*-mid-collapse` |
| H3 tied to offset, Reduce Motion | Progress from the scroll offset; `displayProgress` snaps with a short cross-fade under Reduce Motion | `JourneyPolicyTests` collapseProgress |
| H4 pull-down | `.kuroJourneyRefreshable` (MainActor action) skips refresh on a journey's first page | `testPullDownAtTopOfFirstPageDismisses`, `testPullDownOnSearchJourneyDismissesIt` (+ negative control) |
| F1 fold animation | `KuroFoldButton` with `KuroFold.transaction` (settle; none under Reduce Motion / Low Power): story, episodes/chapters, songs, coverage, Profile Advanced | renders `detail-story-*` |
| F2 fold wording / VoiceOver / stays in view | Labels say what they do (EN/DE), value "Expanded"/"Collapsed", `onCollapse` scrolls back | `NavdetailTests` (F2 scroll-back) |
| F3 session memory | `KuroFoldMemory` per page + section (Profile: `profile#advanced`), never persisted | `JourneyPolicyTests` fold memory, `NavdetailTests` |

### Still open

- VoiceOver focus order and the escape gesture were not exercised on a device (the simulator cannot run VoiceOver).
- `check_navigation.sh` still does not implement spec §5's third check (a sheet without a close/cancel control).
- A new page-level sheet must add `.kuroNavigationLayer`, or it falls back to the UIKit dismissal (logged in DEBUG); the gate does not enforce this yet.
- The 700 ms dismissal wait is still a fixed delay (one sample per setting).
