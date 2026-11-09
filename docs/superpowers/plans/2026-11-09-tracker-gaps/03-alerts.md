# W3a Release Alert Offer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a save puts an airing title on Watching, the confirmation the user is already looking at offers "Notify me when episode N airs". Accepting goes through the existing per-title bell; "Not now" on three titles stops the offers for that account.

**Architecture:** `ReleasesStore` already receives every applied Library change (`ReleasesLibrarySink`). It gains a small offer state: one `pendingAlertOffer`, decided by a pure `ReleaseAlertOfferPolicy` from data already on the device (no new request). The view never gets a second toast slot. Each page's existing foot slot (detail toast, Collection notice, Home progress toast, Discover/Taste toast, Search banner) wraps its toast in one shared `ReleaseAlertOfferStack`. That stack draws the offer row directly above the page's own toast, in the same overlay. Which host draws it is decided from what is actually visible, not from attachment order (corrections brief 2026-11-09): the pager's selected section (`KuroMainView.selection`, mirrored into `KuroNavigationCoordinator.pagerSelection`) and the topmost presentation layer the root coordinator knows (`KuroNavigationCoordinator`: root journey and its tool, journey-presented sheets, header sheet journeys, cover, foreign sheets), through `ReleaseAlertOfferSlotPolicy.presenter(selectedSection:topmostLayer:hosts:)`. A mounted but offscreen pager page, or a page under a sheet, never receives the offer and never expires it. "Notify me" calls `setReleaseNotification(true, for:)`, the detail bell's call and the only place that may prompt.

**Tech Stack:** Swift 6 / SwiftUI, `@Observable`, UserNotifications through the `PendingNotificationCenter` seam, Swift Testing (`KuroTests`).

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + features/W3-alerts.feature

**Corrections applied (2026-11-09, owner-approved corrections brief):** the presenting host is chosen from actual visibility (pager selection + topmost navigation layer), not attachment order; tests run through the real pager with neighbours mounted and with a journey sheet on top; an offscreen host never receives or expires the offer. Item 7: every red step shows missing behaviour (a missing type or member, or no offer row in the real app); none forces a failure with a wrong expectation.

## Global Constraints
- **Notifications** (§3, verbatim): "D14 as written (`docs/superpowers/specs/2026-11-03-details-songs-platform-design.md` §D14) until the owner amends it via D-B: only exact confirmed/announced instants notify; only the Profile toggle and the detail bell may ask for permission; default off; cleared on sign-out."
- **W3a decision** (§6, verbatim): "Shown inline in the save confirmation, only when: the title has a future exact release instant, the global release toggle is off, no per-title override exists, and the account has not declined three times. It never prompts by itself; only the tap on "Notify me" reaches `toggle(_:)`." (The as-built `toggle(_:)` is `ReleasesStore.setReleaseNotification(_:for:)`.)
- **Architecture** (§3, verbatim): "account-scoped owners conform to `AccountScopedState`, capture `AccountContext` at the start of every async operation and check `isCurrent` before every private write, and are registered in `makeAccountScopedStates`; tracking reads/writes only through `LibraryStore` / `LibraryActions`; no second Supabase client; no Combine; `print` only inside `#if DEBUG`; no force unwraps."
- **Copy and design** (§3, verbatim): "every user-facing string through `KuroLocale` (EN + DE); monochrome only, no coloured status; branded states only (`check_branded_states.sh`); light only until W8 ships."
- **Navigation** (§3, verbatim): "Rule 5 (navigation contract) and Rule 6 (Discover R1–R8) apply to every new screen, sheet and tap target."
- **Performance** (§5.2 W3a, verbatim): "No new backend calls."
- **Process** (§3, verbatim): "build warning count does not rise above the 2026-10-31 baseline (60 unique Kuro-side warnings)."

### Scope decision: Watching only, not Planning (conflict with §5.2; the owner must confirm)
§5.2 says "After saving an airing title as Watching/Planning". As built, a Planning title can never notify:
- `ReleasesStore.plannedReleaseNotifications` follows only `.current` / `.repeating`.
- `DetailReminderRule.isFollowed` hides the detail bell for every other status ("a bell on any other title would promise a reminder that never comes").
- `PlatformLaneTests.bellFollowsStatus` pins that.

An offer accepted on a Planning save would therefore promise an alert that never comes, attached to a bell the user cannot see. This plan offers only when the status enters `.current` or `.repeating`. That also takes every Plan-key path out of scope (Taste/Discover/detail heart, `toggleInCollection`, Concierge quick-save), because they all save `.planning`. Widening this means changing D14's "which titles are on" rule, which is an owner decision. It is not done here.

### Where the offer lives (decision)
- **Trigger:** `ReleasesStore.libraryDidChange(_:)`, which every single-title write already reaches: AddToListSheet, QuickVerdict, the detail +1 creating Watching, Home/Folio +1 promoting a plan. `LibraryStore.refresh()` never calls sinks ("Change sinks are not called."), so import publication, realtime and launch never raise an offer.
  - Two local writers would raise an offer with no save confirmation on screen, so both run inside `releases.withAlertOffersSuppressed { … }`: the Folio batch status change (many titles) and the widget's queued +1 (`LibraryActions.advanceQueuedProgress`).
  - The suppression count is read synchronously when the sink fires, not inside the spawned task, because the batch scope may have ended by the time the task runs.
- **Release data, with no new request:**
  1. `nextRelease(for:)`, which reads the account schedule and the anime `upcomingAirings`.
  2. A fresh cached `mediaSchedule` answer for that title (the detail page loaded it).
  3. If neither knows the title yet (a brand-new add: `scheduleMembershipDidChange` drops the cache), wait for the `libraryChangeTask` that `libraryDidChange` already starts for an added anime (`fetchUpcomingForUser(days: 7)`), then evaluate once.

  The release must become known within `ReleaseAlertOfferPolicy.window` (5 s) of the save, or no offer is made.

  **Known limitation (accepted, no new request added):** `fetchUpcomingForUser` is throttled to one read per 20 s (`upcomingThrottle`). A brand-new add made within 20 s of an earlier upcoming read gets no offer, unless the detail page's media-schedule cache already holds the title. Manga only ever offers from the account schedule or the media cache, because no airing read exists for manga.
- **Slot:** each existing foot slot wraps its toast in `ReleaseAlertOfferStack { existingToast }`. The stack draws the offer row directly above that toast, inside the same overlay and transition. When the page has no toast (the editor dismissed), the row stands alone and leads with "Saved." Hosts attach on appear and detach on disappear, each with its place: a pager page's section (`\.kuroPagerSection`, set per page in `KuroSectionPager.page(for:)`) or the journey page it sits on (`\.kuroJourney?.journeyID` + `\.kuroJourneyPageID`). A page with two foot overlays (detail pages: `DetailToastOverlay` + `tastePlanHost`; Home: progress toast + `tastePlanHost`) registers only one of them: `TastePlanHost` gets `offerSlot: Bool = false`, and only Taste passes `true`.
- **Visibility, not attachment order (corrections brief).** The old rule ("the last attached host draws") is wrong in the real pager: `KuroSectionPager.page(for:)` (`Kuro/ContentView.swift:829–832`) mounts the selected page ± 1 **and every page already visited** (`mountedSections`), so several pager hosts are attached at once and the last one to attach is often offscreen; a pager host also stays attached while a journey sheet covers the pager. The presenter is therefore:
  - topmost layer `.pager` → the attached host with `layer == .pager` and `section == selectedSection`;
  - topmost layer `.journey(id, top:)` → the attached host on that journey's top page (`layer == .journey(id, top:)`);
  - topmost layer `.blocked` (cover, root tool, a journey's tool, a sheet presented over a journey page, a foreign/unregistered sheet, a dismissal in flight, more than one page-level presentation, a page-level sheet without a journey) → none;
  - several matches (should not happen: one host per page) → the last attached among the matches; no match → none (`pagerSelection == nil` before KuroMainView mirrored it → none: never guess).
- **Binding and pausing.** The first host that draws the offer binds it (`alertOfferPresented(_:by:)`, which also records the title as offered). A bound offer is drawn only by that host: when the host stops being the presenter (the user pages away, a sheet opens), the row disappears and its hold `Task.sleep` is cancelled; cancellation never calls `expireAlertOffer`. Coming back shows it again with a fresh hold. No other host takes it over.
- **Unseen offers lapse.** An offer that no host has drawn within `ReleaseAlertOfferPolicy.presentWithin` (30 s) of `createdAt` is dropped unseen: not offered, not declined (e.g. a save from a tool over Clubs, which has no host). Evaluated lazily by the stack and by `considerAlertOffer`, no timer.

## Review Focus
1. **The title's release is not loaded at the moment of the add.** Right after a new add, `nextRelease` is nil. The offer must appear after the existing `user_airing_next` refresh, and no extra request may be sent. Pinned by `offerAppearsAfterExistingUpcomingRefresh` (Task 3).
2. **Bulk writes raise offers.** A Folio batch "→ Watching" of N titles, an import publication, or a realtime refresh must raise none. Pinned by `noOfferForRefreshImportOrBatch` (Task 3).
3. **Notification permission already denied in Settings.** "Notify me" would be a dead end, so no offer. Pinned by `noOfferWhenPermissionDenied` (Task 2, pure).
4. **Account switch while the offer shows.** The offer goes, and an accept or decline sent after the switch writes nothing for account B. Pinned by `offerStateIsClearedOnAccountSwitch` (Task 4, also asserts a stale accept is refused).
5. **An offscreen or covered page draws or expires the offer.** Neighbour and visited pager pages stay mounted with their hosts attached; a journey sheet covers the pager without detaching them. The presenter follows the selected section and the topmost layer; a hidden host never calls `alertOfferPresented` or `expireAlertOffer`. Pinned by `offerFollowsTheVisiblePageNotAttachOrder` (Task 5, real coordinator), `ReleaseAlertOfferUITests/testOffscreenNeighbourPagesNeverShowTheOffer` and `testJourneySheetOnTopHidesThePagerOfferUntilItCloses` (Task 5, real pager on the offline fixture host).
6. **Statuses and data that cannot notify.** Planning, paused, an estimate, an announced day, a past or under-a-minute row, a muted title, or a toggle that is already on: none may offer. Also: offer shown ⇒ the planner would notify for that title once its bell is on. Pinned by `noOfferForEstimatesDaysOrFinishedTitles`, `noOfferForPlanningOrUntrackedStatuses` and `offerImpliesPlannerWouldNotify` (Task 2).

## Success parameters
| §5.2 W3a | How it is measured | Expected |
|---|---|---|
| "After saving an airing title as Watching/Planning, an inline offer appears once per title" (Watching/Rewatching only, see Scope decision) | `xcodebuild … test -only-testing:KuroTests/ReleaseAlertOfferTests` | `offerShownAfterSavingAiringTitleWithExactNextRelease`, `offerShownOncePerTitle` pass |
| ""Notify me" calls the existing bell API (the only prompt)" | same suite | `notifyMeUsesBellToggleOnly`: `authorizationRequests` 0 before the tap, 1 after; the title is in `allowedReleaseNotificationKeys`; the Profile toggle stays off |
| ""Not now" three times stops offers for the account" | same suite | `threeDeclinesStopOffersForTheAccount`, `offerStateIsClearedOnAccountSwitch` pass |
| "No new backend calls." | `offerAppearsAfterExistingUpcomingRefresh` counts stub-server requests | requests after the save = exactly the pre-existing `user_airing_next` read (1), the same count with the feature off |
| Only the page the user is looking at shows the offer (corrections brief) | `-only-testing:KuroTests/ReleaseAlertOfferTests` + `xcodebuild … test -only-testing:KuroUITests/ReleaseAlertOfferUITests` on the owned simulator | `slotPolicyFollowsPagerSelectionAndTopmostLayer`, `topmostLayerFollowsTheRootCoordinator`, `offerFollowsTheVisiblePageNotAttachOrder`, `unseenOfferLapsesWithoutCountingAsOffered`, `testOffscreenNeighbourPagesNeverShowTheOffer`, `testJourneySheetOnTopHidesThePagerOfferUntilItCloses` pass |
| Learning goal, not a release criterion (corrections brief item 8): offer acceptance ≈ 30 %; permission denial rate does not rise | acceptance = `release_alert_offer` events with result `accepted` ÷ events with result `shown` (ids only, through `InteractionTelemetry`); denial = `ReleaseNotificationToggleResult.denied` outcomes after `accepted` ÷ `accepted`, compared with the four weeks before release | reviewed by the owner 4 weeks after release; informs D-B and copy, never blocks shipping |

## File Structure
| File | Responsibility |
|---|---|
| `Kuro/Releases/ReleaseAlertOffer.swift` (new) | Pure: `ReleaseAlertOffer` model, `ReleaseAlertOfferPolicy`, `ReleaseAlertOfferCopy` (EN/DE) |
| `Kuro/Releases/ReleasesStore+AlertOffer.swift` (new) | Owner API: consider on Library change, accept, decline, expire, presented (binding), lapse of unseen offers, batch suppression; DEBUG fixture offer |
| `Kuro/Releases/ReleasesStore.swift` | Stored offer state; `libraryDidChange` calls `considerAlertOffer`; `cancelAccountWork` / `clearPrivateState` |
| `Kuro/Releases/ReleasesStore+Schedule.swift` | `cachedMediaRelease(for:now:)` (reads the private cache only; no request) |
| `Kuro/Releases/ReminderScheduler+Releases.swift` | Per-account offered / declined keys; removed with the account's other release preferences |
| `Kuro/Views/Shared/ReleaseAlertOfferStack.swift` (new) | `ReleaseAlertOfferStack` (one slot: offer row above the host toast), `ReleaseAlertOfferRow`, `OfferLayer`, `OfferHost`, `ReleaseAlertOfferSlotPolicy` (visibility rule; view layer, because it uses `KuroMainView.Section`), env keys `\.kuroPagerSection`, `\.kuroJourneyPageID` |
| `Kuro/Views/Routing/KuroNavigationCoordinator.swift` | `pagerSelection`, observable `layerRevision`, `offerHosts` + attach/detach, `offerTopmostLayer`, `isOfferPresenter(_:)` |
| `Kuro/Views/Routing/JourneyHost.swift` | sets `\.kuroJourneyPageID` to `page.id` on the root page and on each pushed page (two lines) |
| `Kuro/ContentView.swift` | `KuroSectionPager.page(for:)` sets `\.kuroPagerSection`; `KuroMainView` mirrors `selection` into `navigation?.pagerSelection` (`.onChange(of: selection, initial: true)`); DEBUG `--kuro-offer-fixture` hook next to the `--kuro-nav-fixture` hook (`ContentView.swift:78`) |
| `KuroUITests/ReleaseAlertOfferUITests.swift` (new) | real-pager tests on the offline fixture host |
| `Kuro/Views/DetailPages/Prototype/DetailPage.swift` | `DetailToastOverlay` hosts the stack |
| `Kuro/Views/TastePicksView.swift` | `TastePlanHost(offerSlot:)`; Taste passes `true` |
| `Kuro/Views/Discover/Preview/DiscoverFeedbackController.swift` | `DiscoverFeedbackHost` hosts the stack |
| `Kuro/Views/Home/HomeView.swift` | The progress-toast overlay hosts the stack |
| `Kuro/Views/EditorialCollectionView.swift` | The FolioNotice inset hosts the stack; the batch status change is suppressed |
| `Kuro/Views/EditorialSearchView.swift` | The banner position hosts the stack |
| `Kuro/Library/LibraryActions.swift` | The widget's queued +1 runs with offers suppressed |
| `KuroTests/ReleaseAlertOfferTests.swift` (new) | Every tagged scenario plus the Review Focus pins |
| `docs/tracker-gaps-2026-11/W3a-alerts/EVIDENCE.md` (new) | Red/green log, live-walk notes |

---

### Task 1: Per-account offer memory (device)

**Files:** modify `Kuro/Releases/ReminderScheduler+Releases.swift`; create `KuroTests/ReleaseAlertOfferTests.swift` (suite skeleton + this task's test).

**Interfaces**
- Consumes: `AccountContext`, `AccountSessionCoordinator.isCurrent`, the existing private `keys(forKey:)` / `store(_:forKey:)` encoding (`"<kind>:<id>"`).
- Produces (on `ReminderScheduler`):
  ```swift
  nonisolated static let alertOfferMemory = 500
  func offeredAlertKeys(for context: AccountContext) -> Set<MediaKey>
  func noteAlertOffered(_ key: MediaKey, for context: AccountContext)   // order kept, oldest dropped past alertOfferMemory
  func declinedAlertKeys(for context: AccountContext) -> Set<MediaKey>
  func noteAlertDeclined(_ key: MediaKey, for context: AccountContext)
  ```
  UserDefaults keys: `com.kuro.releaseNotifications.offered.<userId lower-cased>` (ordered string array) and `com.kuro.releaseNotifications.offerDeclined.<userId lower-cased>`. Both writes are no-ops when `context` is not current. `removeReleaseNotificationPreferences(userId:)` also removes both keys.

- [ ] **Step 1: Write the failing test.** In the new `KuroTests/ReleaseAlertOfferTests.swift` add `@MainActor @Suite("Release alert offer", .serialized, .timeLimit(.minutes(1))) struct ReleaseAlertOfferTests`, with the private `AlertOfferHarness` described in Task 3 Step 1 (built here first). Add:
  ```swift
  @Test func offerMemoryIsPerAccountAndDeletedWithTheAccount() async throws
  // signIn(userA); noteAlertDeclined(k1..k3, A); declinedAlertKeys(A).count == 3
  // noteAlertOffered for 501 distinct keys → offeredAlertKeys(A).count == 500 and the first key is gone
  // signIn(userB): declinedAlertKeys(B).isEmpty && offeredAlertKeys(B).isEmpty
  // a note made with A's stale context while B is current changes nothing for either account
  // removeReleaseNotificationPreferences(userId: userA) → defaults has no "…offered.<a>" / "…offerDeclined.<a>" object
  ```
- [ ] **Step 2: Run it.** `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/ReleaseAlertOfferTests`. Expected: FAIL to compile, "value of type 'ReminderScheduler' has no member 'noteAlertDeclined'".
- [ ] **Step 3: Implement** the four methods and the deletion in `ReminderScheduler+Releases.swift`, following the existing `mutedKey` / `allowedKey` pattern.
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit.** `git add Kuro/Releases/ReminderScheduler+Releases.swift KuroTests/ReleaseAlertOfferTests.swift && git commit -m "Release alert offer: per-account offered/declined memory"`

### Task 2: Pure policy and copy

**Files:** create `Kuro/Releases/ReleaseAlertOffer.swift`; extend `KuroTests/ReleaseAlertOfferTests.swift`.

**Interfaces**
- Consumes: `ReleaseScheduleItem`, `ReleaseNotificationPlanner.isEligible(_:now:)` and `.plan(...)`, `NotificationPermission`, `ListStatus`, `MediaKey`.
- Produces:
  ```swift
  nonisolated struct ReleaseAlertOffer: Equatable, Sendable, Identifiable {
      let id: UUID; let key: MediaKey; let item: ReleaseScheduleItem
      let accountUserId: String; let createdAt: Date
  }
  nonisolated enum ReleaseAlertOfferPolicy {
      static let declineLimit = 3
      static let window: TimeInterval = 5      // release must be known this soon after the save
      static let hold: TimeInterval = 10       // on screen without assistive tech
      static let presentWithin: TimeInterval = 30   // an offer no host drew by createdAt + 30 s lapses unseen
      struct Input: Equatable, Sendable {
          var previousStatus: ListStatus?; var status: ListStatus?
          var next: ReleaseScheduleItem?
          var toggleOn: Bool                    // the account's stored Profile preference == true
          var permission: NotificationPermission
          var allowed: Set<MediaKey>; var muted: Set<MediaKey>
          var offered: Set<MediaKey>; var declined: Set<MediaKey>
          var suppressed: Bool
      }
      /// The status entered the followed set (.current / .repeating) with this change.
      static func entersFollowed(previous: ListStatus?, current: ListStatus?) -> Bool
      static func shouldOffer(_ input: Input, key: MediaKey, now: Date) -> Bool
      /// Unbound and older than presentWithin: dropped unseen (not offered, not declined).
      static func hasLapsed(_ offer: ReleaseAlertOffer, boundHost: UUID?, now: Date) -> Bool
  }
  nonisolated enum ReleaseAlertOfferCopy {
      static func prompt(_ item: ReleaseScheduleItem, german: Bool) -> String
      static func notifyMe(german: Bool) -> String     // "Notify me" / "Benachrichtigen"
      static func notNow(german: Bool) -> String       // "Not now" / "Nicht jetzt"
      static func saved(german: Bool) -> String        // "Saved." / "Gespeichert."
  }
  ```
  (The slot rule moved out of this file: it depends on the pager's `KuroMainView.Section` and the navigation layers, so it lives in the view layer, Task 5.)

  `shouldOffer` is true only when all of these hold:
  - `entersFollowed`
  - `next?.key == key`, and `ReleaseNotificationPlanner.isEligible(next, now:)`
  - `!toggleOn`
  - `permission != .denied`
  - `key ∉ allowed ∪ muted`
  - `key ∉ offered`
  - `declined.count < declineLimit`
  - `!suppressed`

  Prompt copy:

  | Release | EN | DE |
  |---|---|---|
  | Episode with a number | "Notify me when episode 5 airs" | "Benachrichtigen, wenn Folge 5 läuft" |
  | Chapter with a number | "Notify me when chapter 120 is out" | "Benachrichtigen, wenn Kapitel 120 erscheint" |
  | Volume with a number | "Notify me when volume 3 is out" | "Benachrichtigen, wenn Band 3 erscheint" |
  | No number | "Notify me when the next episode airs" | "Benachrichtigen, wenn die nächste Folge läuft" |

- [ ] **Step 1: Write the failing tests** (pure; fixed `now = Date(timeIntervalSince1970: 1_793_707_200)`; `base` = Input(previous nil, status .current, next = episode 5 confirmed instant at now+3 d, toggle off, permission .notDetermined, every set empty, suppressed false)):
  ```swift
  @Test func noOfferForEstimatesDaysOrFinishedTitles()
  // shouldOffer(base) == true (control)
  // next.basis .estimated (precision .instant) → false
  // next .announced with precision .day → false; precision .month → false
  // next.isPast → false; next at now+30 s → false (minimumLead 60); next nil → false
  // next for another key → false; status .completed / .dropped → false
  @Test func noOfferForPlanningOrUntrackedStatuses()
  // status .planning, .paused, nil → false; status .repeating from nil → true
  // previous .current → status .current (an edit) → false; previous .planning → .current → true
  @Test func noOfferWhenPermissionDenied()
  // permission .denied → false; .authorized → true; .notDetermined → true
  @Test func overridesToggleDeclinesAndSuppressionStopTheOffer()
  // toggleOn → false; allowed ∋ key → false; muted ∋ key → false; offered ∋ key → false
  // declined.count 2 → true; 3 → false; suppressed → false
  @Test func offerImpliesPlannerWouldNotify()
  // for every Input in a 40-case table where shouldOffer is true:
  //   ReleaseNotificationPlanner.plan(items: [next], following: [key], muted: [], now:, …).count == 1
  @Test func promptCopyIsEnglishAndGerman()
  // prompt(ep 5, false) == "Notify me when episode 5 airs"; (true) == "Benachrichtigen, wenn Folge 5 läuft"
  // chapter 120 / volume 3 / no-number rows as in the table above
  @Test func unseenOfferLapsesWithoutCountingAsOffered()
  // offer createdAt t: hasLapsed(boundHost: nil, now: t+29) == false; (now: t+31) == true; bound (boundHost: h, now: t+300) == false
  ```
- [ ] **Step 2: Run** `-only-testing:KuroTests/ReleaseAlertOfferTests`. Expected: FAIL to compile, "cannot find 'ReleaseAlertOfferPolicy' in scope".
- [ ] **Step 3: Implement** `ReleaseAlertOffer.swift` with the signatures above. All strings go through `german ? … : …`, with the `KuroLocale.isGerman` value passed in by the caller.
- [ ] **Step 4: Run.** Expected: PASS (7 new tests).
- [ ] **Step 5: Commit.** `git add Kuro/Releases/ReleaseAlertOffer.swift KuroTests/ReleaseAlertOfferTests.swift && git commit -m "Release alert offer: pure policy and EN/DE copy"`

### Task 3: The owner raises the offer after a save (no new request)

**Files:** create `Kuro/Releases/ReleasesStore+AlertOffer.swift`; modify `Kuro/Releases/ReleasesStore.swift`, `Kuro/Releases/ReleasesStore+Schedule.swift`, `Kuro/Views/EditorialCollectionView.swift` (batch wrapper only), `Kuro/Library/LibraryActions.swift` (`advanceQueuedProgress` runs inside `releases?.withAlertOffersSuppressed`; `releases` is the existing weak reference); extend the test file.

**Interfaces**
- Consumes: Task 1 and Task 2 APIs; `LibraryChange`; `libraryChangeTask`; `nextRelease(for:now:)`; `reminders.releaseNotificationPreference(for:)`, `mutedReleaseNotificationKeys(for:)`, `allowedReleaseNotificationKeys(for:)`, `notificationPermission()` (never prompts).
- Produces:
  ```swift
  // ReleasesStore.swift, stored:
  var pendingAlertOffer: ReleaseAlertOffer? = nil
  var alertOfferBoundHost: UUID? = nil          // the host that first drew the pending offer (UI identity, not account data)
  @ObservationIgnored var alertOfferTask: Task<Void, Never>? = nil
  @ObservationIgnored var alertOfferSuppression = 0
  // ReleasesStore+Schedule.swift (same file as the private cacheKey/freshSchedule):
  func cachedMediaRelease(for key: MediaKey, now: Date = Date()) -> ReleaseScheduleItem?   // first eligible row of any fresh "<user>|media|<kind>|<id>|…" entry; never requests
  // ReleasesStore+AlertOffer.swift:
  func considerAlertOffer(_ change: LibraryChange, now: Date = Date())
  func withAlertOffersSuppressed<T>(_ work: () async -> T) async -> T
  func knownRelease(for key: MediaKey, now: Date = Date()) -> ReleaseScheduleItem?   // nextRelease ?? cachedMediaRelease
  /// The pending offer for a host the VIEW LAYER already found to be the presenter (Task 5): nil when the offer is
  /// bound to another host or has lapsed unseen (hasLapsed → cleared here). The owner knows no pager or layer.
  func alertOffer(forPresenter hostId: UUID, now: Date = Date()) -> ReleaseAlertOffer?
  func alertOfferPresented(_ offerId: UUID, by hostId: UUID)  // binds the offer to hostId; records the key as offered (once per title)
  func expireAlertOffer(_ offerId: UUID, by hostId: UUID)     // hold elapsed in the bound host: clears, NOT a decline; ignored from any other host
  ```
  Host registration and the presenter choice are not on the owner: they are view-layer state on `KuroNavigationCoordinator` (Task 5), because they depend on the pager selection and navigation layers.
  `considerAlertOffer` does this:
  1. Capture `accountSession.current`. Return if `change.account` is not that account, or if `!entersFollowed`.
  2. Build `Input` from `reminders` for the context. Read the permission with `await reminders.notificationPermission()` inside the task, never `requestNotificationPermission`.
  3. Evaluate with `knownRelease`.
  4. If it is nil, the key is anime and `libraryChangeTask` is set: await that task, then evaluate once more, only while `isCurrent(context)` and `Date() < change time + window`.
  5. Publish `pendingAlertOffer` (newest wins).

  `libraryDidChange(_:)` gets `defer { considerAlertOffer(change) }` placed right after its first guard (`accountSession.isCurrent(change.account), !change.isProgressOnly`).
  - It cannot be a plain last line: the method returns early for manga (`guard change.key.kind == .anime`) and for anime changes that skip the refresh.
  - The `defer` runs on every path, after `libraryChangeTask` is assigned.
  - `considerAlertOffer` reads `alertOfferSuppression > 0` synchronously into `Input.suppressed` before it spawns `alertOfferTask`. `cancelAccountWork()` cancels `alertOfferTask`. `clearPrivateState()` sets `pendingAlertOffer = nil`, `alertOfferBoundHost = nil` and `alertOfferSuppression = 0`. `considerAlertOffer` publishing a new offer resets `alertOfferBoundHost` (newest wins, unbound).

- [ ] **Step 1: Write the failing tests.**

  **Harness.** `PlatformHarness.init` takes no client, so add a private `AlertOfferHarness` in `ReleaseAlertOfferTests.swift`. It copies `PublicDataHarness`'s construction (`KuroTests/StubPostgREST.swift`: `StubServer` + `StubSupabase.makeClient(server:)` through `AppComposition.testingGraph`) and adds `libraryBackend: FakeLibraryBackend()`, so saves work as in `PlatformHarness`. `withCredentialLease` over the stub client is already exercised by `ReleaseContractFallbackTests`.

  Sign in with `service.session.applySession(userId:email:)` and await `libraryActions.libraryRefreshTask`. Default stub answers:
  - `user_airing_next`: one row for anime 501 (episode 5, `next_airing_at` = now+2 d, title "Frieren");
  - everything else: `[]`.

  Also `FakeNotificationCenter.permission = .notDetermined`, and `FakeLibraryBackend` holds no rows. Task 1's test uses the same harness.
  ```swift
  @Test func offerShownAfterSavingAiringTitleWithExactNextRelease() async throws
  // seed the media-schedule cache as the detail page leaves it: await releases.mediaSchedule(kind: .anime, id: 501)
  //   (stub answers rpc/media_release_schedule_v1 = ReleaseContract.mediaSchedule with episode 5, confirmed, instant, now+2 d;
  //    the stub's user_airing_next answer is empty in THIS test, so only the cache can supply the release)
  // apply(LibraryEdit(status: .set(.current)), to: anime 501, createIfMissing: .current) succeeds
  // await releases.alertOfferTask?.value
  // pendingAlertOffer?.key == anime 501; ReleaseAlertOfferCopy.prompt(offer.item, german: false) == "Notify me when episode 5 airs"
  // notifications.authorizationRequests == 0
  @Test func offerAppearsAfterExistingUpcomingRefresh() async throws
  // no media-schedule cache; save anime 501 as .current; await releases.libraryChangeTask?.value; await alertOfferTask?.value
  // pendingAlertOffer?.key == anime 501
  // server.requests filtered to resources != library rows: exactly ["user_airing_next"] (the pre-existing refresh)
  // repeat with a fresh harness and a title the stub has no airing for: pendingAlertOffer == nil, same single request
  @Test func mangaReadingTitleWithExactChapterTimeOffers() async throws
  // the account schedule holds manga 2 chapter 68, confirmed, instant, now+3 d (the PlatformLaneTests Kagurabachi row,
  //   seeded as seedSchedule does); apply .current to manga 2 → pendingAlertOffer?.key == manga 2
  //   (proves the defer runs past libraryDidChange's anime-only guard)
  @Test func noOfferForRefreshImportOrBatch() async throws
  // backend rows change server-side → libraryActions.libraryChangedServerSide(for:) awaited → pendingAlertOffer == nil
  // await releases.withAlertOffersSuppressed { apply .current to anime 501 and 502 } → pendingAlertOffer == nil
  // a plain apply .current afterwards (suppression ended) → offer for that key
  // a tracked planning entry advanced through libraryActions.advanceQueuedProgress (widget +1) → pendingAlertOffer == nil
  @Test func offerShownOncePerTitle() async throws
  // offer raised; alertOfferPresented(offer.id, by: h); expireAlertOffer(offer.id, by: other) → still pending (only the bound host expires);
  // expireAlertOffer(offer.id, by: h) → nil, declined still empty
  // set the title to .paused then .current again → no new offer (offered memory), also after a new PlatformHarness over the same suiteName (relaunch)
  ```
- [ ] **Step 2: Run** `-only-testing:KuroTests/ReleaseAlertOfferTests`. Expected: FAIL to compile, "value of type 'ReleasesStore' has no member 'pendingAlertOffer'".
- [ ] **Step 3: Implement** the stored properties, `cachedMediaRelease`, and `ReleasesStore+AlertOffer.swift` as specified. In `EditorialCollectionView.batchChangeStatus`, wrap the `collection.applyBatchStatusChange(...)` call in `await releases.withAlertOffersSuppressed { … }`; the view already reads `ReleasesStore`.
- [ ] **Step 4: Run.** Expected: PASS. Then run the existing suites to confirm the sink change broke nothing: `-only-testing:KuroTests/ReleaseNotificationDeviceTests -only-testing:KuroTests/ReleaseScheduleTests`. Expected: PASS.
- [ ] **Step 5: Commit.** `git add Kuro/Releases/ReleasesStore.swift Kuro/Releases/ReleasesStore+Schedule.swift Kuro/Releases/ReleasesStore+AlertOffer.swift Kuro/Views/EditorialCollectionView.swift Kuro/Library/LibraryActions.swift KuroTests/ReleaseAlertOfferTests.swift && git commit -m "Release alert offer: raised from the Library sink with on-device release data only"`

### Task 4: Accept through the bell, decline, account isolation

**Files:** modify `Kuro/Releases/ReleasesStore+AlertOffer.swift`; extend the test file.

**Interfaces**
- Consumes: `setReleaseNotification(_:for:)` (the detail bell's call), Task 1 memory, `InteractionTelemetry` is NOT referenced by the owner (the view sends telemetry).
- Produces:
  ```swift
  /// The one path from the offer to a permission prompt: the bell's own call, for the offer's title.
  func acceptAlertOffer(_ offerId: UUID) async -> ReleaseNotificationToggleResult?   // nil: no such offer, or another account is current
  func declineAlertOffer(_ offerId: UUID)                                             // records the title in the declined set
  ```
  Both guard `pendingAlertOffer?.id == offerId` and that `accountSession.current?.userId` equals `offer.accountUserId` (case-insensitive, `AccountSessionCoordinator.sameUser`), then clear the offer before acting.

- [ ] **Step 1: Write the failing tests:**
  ```swift
  @Test func notifyMeUsesBellToggleOnly() async throws
  // precondition, stated in the test: scheduleCoverageByMedium is empty and the stub answers rpc/user_release_schedule_v1
  //   with anime 501 episode 5 (confirmed, instant, now+2 d). setReleaseNotification reloads the account schedule only
  //   when coverage is empty, and plannedReleaseNotifications reads `schedule`, not the media cache or upcomingAirings
  // offer raised for anime 501 (as Task 3); notifications.authorizationRequests == 0
  // promptAnswer = .authorized; result = await acceptAlertOffer(offer.id)
  // result == .enabled; authorizationRequests == 1; prompts == 1
  // releases.allowedReleaseNotificationKeys == [anime 501]; releaseNotificationsEnabled == false
  // reminders.releaseNotificationPreference(for: ctx) == nil (Profile toggle untouched)
  // pendingAlertOffer == nil; notifications.pending == ["release-anime-501-episode-5"]
  // a second acceptAlertOffer(offer.id) == nil and authorizationRequests stays 1
  @Test func threeDeclinesStopOffersForTheAccount() async throws
  // for anime 501, 502, 503 (each with an exact episode row): save .current → offer → declineAlertOffer
  // save anime 504 .current → pendingAlertOffer == nil
  // Profile toggle still works: promptAnswer .authorized; await setReleaseNotificationsEnabled(true) == .enabled
  @Test func offerStateIsClearedOnAccountSwitch() async throws
  // userA declines 501, 502, 503 (three titles)
  // signIn(userB); userB saves anime 504 .current → pendingAlertOffer?.key == anime 504 (B's memory is empty)
  // keep that offer's id (staleId), do not answer it; signIn(userA)
  // pendingAlertOffer == nil (clearPrivateState); await acceptAlertOffer(staleId) == nil; authorizationRequests == 0
  // allowedReleaseNotificationKeys(for: A) is empty (nothing written for A from B's offer)
  // userA saves anime 506 .current → pendingAlertOffer == nil (A's three declines survived the switch)
  ```
- [ ] **Step 2: Run.** Expected: FAIL to compile, "value of type 'ReleasesStore' has no member 'acceptAlertOffer'".
- [ ] **Step 3: Implement** both methods.
- [ ] **Step 4: Run** the whole suite. Expected: PASS (all W3a tests so far).
- [ ] **Step 5: Commit.** `git add Kuro/Releases/ReleasesStore+AlertOffer.swift KuroTests/ReleaseAlertOfferTests.swift && git commit -m "Release alert offer: accept through the bell, decline memory, account isolation"`

### Task 5: One slot: the offer row inside the visible page's existing foot slot

**Files:** create `Kuro/Views/Shared/ReleaseAlertOfferStack.swift`, `KuroUITests/ReleaseAlertOfferUITests.swift`. Modify the presenter inputs:
- `Kuro/Views/Routing/KuroNavigationCoordinator.swift` (pager selection, layer revision, offer hosts, topmost layer)
- `Kuro/Views/Routing/JourneyHost.swift` (`\.kuroJourneyPageID` on the root page and on each pushed page)
- `Kuro/ContentView.swift` (`\.kuroPagerSection` per page in `KuroSectionPager.page(for:)`; `selection` mirrored into the coordinator; DEBUG `--kuro-offer-fixture` hook)
- `Kuro/Releases/ReleasesStore+AlertOffer.swift` (DEBUG `installFixtureAlertOffer(now:)`, compiled only `#if DEBUG`)

And these host sites only:
- `DetailPage.swift` (`DetailToastOverlay`)
- `TastePicksView.swift` (`TastePlanHost` + `tastePlanHost(_:offerSlot:)`, and Taste's own call passes `true`)
- `DiscoverFeedbackController.swift` (`DiscoverFeedbackHost`)
- `HomeView.swift` (`progressToast` overlay)
- `EditorialCollectionView.swift` (the `safeAreaInset` VStack)
- `EditorialSearchView.swift` (the `banner.message` position)

Extend `KuroTests/ReleaseAlertOfferTests.swift`.

**Interfaces**
- Consumes: `@Environment(ReleasesStore.self) private var releases: ReleasesStore?` (optional, so existing test hosts that do not inject Releases keep rendering); `@Environment(\.kuroNavigation)` (nil in test hosts without the root coordinator → the stack never draws an offer); `@Environment(\.kuroJourney)`; `@Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?`; `KuroToastHold.assistiveTechnologyRunning()`; `DetailReminderRule.toast(_:german:)` for the result line (same words as the detail bell); `NavigationCollapsePolicy.Snapshot` (the coordinator's existing presentation snapshot).
- Produces (view layer; declared without `nonisolated`, i.e. main-actor under the app's default isolation, because `KuroMainView.Section` is main-actor; the suite is `@MainActor`):
  ```swift
  enum OfferLayer: Hashable {
      case pager                                         // nothing is presented over the pager
      case journey(ObjectIdentifier, top: String)        // a journey (root or a header sheet's) and its top page id (JourneyPage.id)
      case blocked                                       // see the Architecture rule: no host is visible
  }
  struct OfferHost: Equatable {
      let id: UUID
      let section: KuroMainView.Section?                 // pager hosts: their page; journey hosts: nil
      let layer: OfferLayer                              // pager hosts: .pager; journey hosts: .journey(journeyID, top: own page id)
  }
  enum ReleaseAlertOfferSlotPolicy {
      /// Visibility rule (Architecture → "Visibility, not attachment order"). `hosts` in attach order.
      static func presenter(selectedSection: KuroMainView.Section?, topmostLayer: OfferLayer, hosts: [OfferHost]) -> UUID?
      /// Pure derivation of the topmost layer from the coordinator's state.
      static func topmostLayer(_ s: OfferLayerSnapshot) -> OfferLayer
  }
  struct OfferLayerSnapshot: Equatable {
      var collapse: NavigationCollapsePolicy.Snapshot    // coverOpen, rootToolOpen, journeyTop, journeyToolOpen, openSheets,
                                                         // sheetJourneyTops, sheetJourneyTools, journeySheets, dismissalInFlight, foreignSheetOpen
      var rootJourney: ObjectIdentifier?                 // the open root journey's navigator
      var sheetJourneys: [String: ObjectIdentifier]      // open header sheet layer key → its journey navigator
  }
  // topmostLayer: cover / dismissal in flight / foreign sheet / root tool → .blocked;
  //   more than one of {root journey, page-level sheets} open → .blocked (never guess which is on top);
  //   root journey only: journeyToolOpen or a non-empty collapse.journeySheets[NavigationCollapsePolicy.rootJourney] → .blocked,
  //     else .journey(rootJourney, top: journeyTop.id);
  //   one page-level sheet `key` only: hosting a journey (sheetJourneys[key] != nil) → key ∈ sheetJourneyTools or a non-empty
  //     collapse.journeySheets[key] → .blocked, else .journey(sheetJourneys[key], top: sheetJourneyTops[key].id);
  //   (journeySheets is keyed by Strings — the rootJourney constant or the sheet's layer key — never by the navigator id)
  //     without a journey → .blocked; nothing open → .pager.

  // KuroNavigationCoordinator (UI state only):
  var pagerSelection: KuroMainView.Section?              // mirrored by KuroMainView; nil until then
  private(set) var layerRevision = 0                     // observed; += 1 in registerLayer / unregisterLayer / layerDidChange
                                                         // (`layers` is @ObservationIgnored and holds closures, so views need this to re-evaluate)
  private(set) var offerHosts: [OfferHost] = []          // attach order
  func attachOfferHost(_ host: OfferHost)                // replaces an entry with the same id (its place can change)
  func detachOfferHost(_ id: UUID)
  var offerTopmostLayer: OfferLayer { get }              // reads layerRevision, slot.presented, journey tops; then ReleaseAlertOfferSlotPolicy.topmostLayer
  func isOfferPresenter(_ id: UUID) -> Bool              // presenter(selectedSection: pagerSelection, topmostLayer: offerTopmostLayer, hosts: offerHosts) == id

  // Environment (defaults nil): \.kuroPagerSection (set in KuroSectionPager.page(for:)), \.kuroJourneyPageID (set by JourneyHost)

  struct ReleaseAlertOfferStack<Toast: View>: View {
      init(@ViewBuilder toast: () -> Toast)
      // @State hostId = UUID(). Place: kuroJourney?.journeyID and kuroJourneyPageID both non-nil → .journey(journeyID, top: pageID),
      //   section nil (header journeys render through JourneyHost via ShellJourneyHost, so Search's page gets its id);
      //   kuroJourney set but either id nil → no place; else kuroPagerSection != nil → .pager with that section;
      //   no place → never attaches, never draws.
      // onAppear / place change → navigation?.attachOfferHost(OfferHost(…)); onDisappear → detachOfferHost(hostId)
      // let offer = navigation?.isOfferPresenter(hostId) == true ? releases?.alertOffer(forPresenter: hostId) : nil
      // VStack(spacing: 6) { if let offer { ReleaseAlertOfferRow(…) }; toast }
      // .task(id: offer?.id): alertOfferPresented(offer.id, by: hostId); telemetry "release_alert_offer" result "shown"
      //   (once per offer); unless assistive tech, try await Task.sleep(hold) then expireAlertOffer(offer.id, by: hostId).
      //   A cancelled sleep (the host stopped being the presenter) returns without expiring.
  }
  struct ReleaseAlertOfferRow: View {
      let prompt: String; let leadsWithSaved: Bool; let german: Bool
      let onNotify: () -> Void; let onNotNow: () -> Void
      // .accessibilityIdentifier("release-alert-offer") on the row container (UI tests)
  }
  extension View { func releaseAlertOfferHost() -> some View }   // for a host with no toast of its own (Search)
  ```
  DEBUG fixture (UI tests only): with `--kuro-offer-fixture`, KuroRootView's existing fixture `.task` (next to `NavigationFixture`, `ContentView.swift:78`) calls `releases.installFixtureAlertOffer(now:)`; when `--kuro-nav-fixture` is also present it does so only after the fixture journey has been presented (`NavigationFixture.didOpen` and the coordinator's `journey != nil`), so no pager host can bind the offer in the gap after launch. It publishes one unbound offer (anime 501, episode 5, confirmed instant at now + 2 d, `accountUserId` of the current context or `"fixture"`). Accept/decline of the fixture offer are not exercised by UI tests.

  Row anatomy: the same as `TastePlanToastView`, so the two read as one family:
  - `#282F2B` at 0xF5 opacity, white 12 pt text, radius 18, padding 5/5/5/14, inset 13/13/12.
  - Two 44 pt text buttons, "Notify me" and "Not now".
  - `ViewThatFits` moves the buttons under the text when German at 320 pt or large type does not fit on one row (the `DiscoverFeedbackToastView` pattern).
  - Monochrome, no bell colour.
  - `.accessibilityElement(children: .contain)`, announced once on appear.

  "Notify me" calls `acceptAlertOffer`. A result other than `.enabled` shows `DetailReminderRule.toast(change)` for 3 s in the row's place.

- [ ] **Step 1: Write the failing tests.** In `KuroTests/ReleaseAlertOfferTests.swift`:
  ```swift
  @Test func slotPolicyFollowsPagerSelectionAndTopmostLayer()
  // hosts in attach order: taste(.pager, .taste), discover(.pager, .discover), collection(.pager, .collection),
  //   detail(.journey(J, top: "media:anime:501")), under(.journey(J, top: "media:anime:7"))
  // presenter(selected .discover, .pager) == discover            (taste and collection attached too, collection last: attach order loses)
  // presenter(selected .collection, .pager) == collection; presenter(selected .clubs, .pager) == nil (Clubs has no host)
  // presenter(selected nil, .pager) == nil                       (selection not mirrored yet: never guess)
  // presenter(selected .discover, .journey(J, top: "media:anime:501")) == detail   (pager hosts are covered)
  // presenter(selected .discover, .journey(J, top: "media:anime:9")) == nil        (top page has no host; the page under it never draws)
  // presenter(selected .discover, .blocked) == nil
  @Test func topmostLayerFollowsTheRootCoordinator() async throws
  // real KuroNavigationCoordinator(dismissalDelay: .zero) (pattern: NavshellTests "Coordinator: a link while Search or Concierge is open…", NavshellTests.swift:61)
  // nothing open → .pager
  // collapseThenOpen(.media(MediaRoute(kind: .anime, id: 501))) → .journey(root navigator, top: "media:anime:501")
  // root journey's tool set → .blocked; tool cleared → .journey again
  // registerLayer("search#1", isPresented: { true }) with an attached journey whose top is the Search root → .blocked while the root
  //   journey is also open (two page-level presentations); with the root journey closed → .journey(search navigator, top: <search root id>)
  // registerLayer("collection.import#1", isPresented: { true }) without a journey → .blocked; a .cover layer presented → .blocked
  // layerRevision increases on register / unregister / layerDidChange
  @Test func offerFollowsTheVisiblePageNotAttachOrder() async throws
  // AlertOfferHarness + a real coordinator: raise an offer for anime 501 (as Task 3); pagerSelection = .discover
  // attach pager hosts for .home, .discover, .collection (as KuroSectionPager mounts the selected page ± 1 and visited pages),
  //   .collection attached LAST; precondition: coordinator.offerHosts.count >= 2
  // isOfferPresenter(discover) == true; isOfferPresenter(home) == false; isOfferPresenter(collection) == false
  // only the presenter calls alertOfferPresented: after the discover host presents, offeredAlertKeys(A) == [anime 501]
  // a second offer (anime 502) while pagerSelection = .clubs (no host) and no presenter for 31 s (injected now):
  //   alertOffer(forPresenter:) == nil for every host, pendingAlertOffer == nil afterwards, offeredAlertKeys(A) has no anime 502,
  //   declinedAlertKeys(A).isEmpty
  // open a root journey (collapseThenOpen(.media(anime 7))) over the pager while the anime 501 offer is pending and unbound:
  //   no pager host is presenter; expireAlertOffer from a pager host that is not bound changes nothing; pendingAlertOffer still set
  @Test func offerRowFitsGermanAtLargestCappedType() throws
  // render ReleaseAlertOfferRow(prompt: "Benachrichtigen, wenn Folge 12 läuft", leadsWithSaved: true, german: true, …)
  // at width 320, .dynamicTypeSize(.accessibility3) in a UIHostingController attached to the foreground scene
  // sizeThatFits.width <= 320 and both button labels present in the accessibility tree (no truncation "…")
  ```
  In `KuroUITests/ReleaseAlertOfferUITests.swift` (`final class ReleaseAlertOfferUITests: XCTestCase`; launch pattern of `NavigationContractUITests`: `--kuro-fixture-host --kuro-skip-auth`, offline, owned simulator by UUID):
  ```swift
  func testOffscreenNeighbourPagesNeverShowTheOffer() throws
  // launch with --kuro-fixture-host --kuro-skip-auth --ff-on=taste_deck_v1 --kuro-offer-fixture
  //   (order Taste → Discover → Browse → Collection → Clubs; Discover selected; Taste, a host, is mounted as its neighbour)
  // exactly one element "release-alert-offer" exists, is hittable and lies inside the window frame
  // swipe to Taste (now visible, mounted all along): zero "release-alert-offer" elements (the offer is bound to Discover's host)
  // wait 12 s (> hold 10 s) on Taste, swipe back to Discover: exactly one "release-alert-offer" again (the hidden host neither drew nor expired it)
  func testJourneySheetOnTopHidesThePagerOfferUntilItCloses() throws
  // launch with --kuro-fixture-host --kuro-skip-auth --ff-on=taste_deck_v1 --kuro-offer-fixture --kuro-nav-fixture
  //   (the navigation fixture opens a root journey over the pager right after launch; its pages have no offer host)
  // while the journey is open: zero "release-alert-offer" elements; wait 12 s (> hold)
  // tap ✕ (journey closes, well within presentWithin 30 s): exactly one "release-alert-offer" on the selected pager page
  ```
  Precondition check for the neighbour test (do it first, record it in EVIDENCE.md): on the offline fixture host, Taste's page must mount `TastePlanHost` (the stack wraps it whether or not cards loaded). If it does not, use Collection as the hosted neighbour instead (select Browse, so Discover and Collection are both mounted hosts) and keep the same assertions; never weaken "exactly one" to "at least one".
- [ ] **Step 2: Run.** `-only-testing:KuroTests/ReleaseAlertOfferTests` → FAIL to compile, "cannot find 'ReleaseAlertOfferSlotPolicy' in scope" (and "cannot find 'ReleaseAlertOfferRow' in scope"). `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroUITests/ReleaseAlertOfferUITests` → FAIL: no "release-alert-offer" element exists (the app has no offer row and ignores `--kuro-offer-fixture`). Both are missing behaviour, not a forced failure.
- [ ] **Step 3: Implement** the coordinator additions, the two environment keys, `ReleaseAlertOfferStack.swift`, the `ContentView.swift` wiring (`.environment(\.kuroPagerSection, section)` inside `page(for:)`'s mounted branch; `.onChange(of: selection, initial: true) { navigation?.pagerSelection = $1 }` on the pager; the DEBUG fixture hook), the `JourneyHost` page id, the DEBUG fixture offer, then wrap each host:
  - `DetailToastOverlay`: `ReleaseAlertOfferStack { if let toast { KuroToast(…) } }`.
  - `TastePlanHost`: wrap only when `offerSlot`. The detail pages, Home and `HomeNewAccount` keep the default `false`; Taste passes `true`.
  - `DiscoverFeedbackHost`: wrap the whole `if/else if` toast block.
  - `HomeView`: wrap `progressToast`.
  - `EditorialCollectionView`: put the stack around the `FolioNoticeBar` inside the existing `safeAreaInset` VStack.
  - `EditorialSearchView`: replace the `if let transientBannerMessage` block with `ReleaseAlertOfferStack { if let … { KuroTransientBanner(…) } }`.

  The `prompt` argument is `ReleaseAlertOfferCopy.prompt(offer.item, german: KuroLocale.isGerman)`. `leadsWithSaved` is true when the host has no toast at that moment.
- [ ] **Step 4: Run** both commands from Step 2 → PASS; then `-only-testing:KuroTests/NavshellTests -only-testing:KuroTests/JourneyPolicyTests` (coordinator change) → PASS; then `scripts/quality-gates/check_navigation.sh` and `scripts/quality-gates/check_branded_states.sh` → 0 offenders (no sheet, no `ProgressView(`).
- [ ] **Step 5: Commit.** `git add Kuro/Views/Shared/ReleaseAlertOfferStack.swift Kuro/Views/Routing/KuroNavigationCoordinator.swift Kuro/Views/Routing/JourneyHost.swift Kuro/ContentView.swift Kuro/Releases/ReleasesStore+AlertOffer.swift Kuro/Views/DetailPages/Prototype/DetailPage.swift Kuro/Views/TastePicksView.swift Kuro/Views/Discover/Preview/DiscoverFeedbackController.swift Kuro/Views/Home/HomeView.swift Kuro/Views/EditorialCollectionView.swift Kuro/Views/EditorialSearchView.swift KuroTests/ReleaseAlertOfferTests.swift KuroUITests/ReleaseAlertOfferUITests.swift && git commit -m "Release alert offer: drawn only by the visible page's foot slot"`

### Task 6: Docs, full verification, evidence

**Files:** `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md` (Rule 1), `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md` (Rule 2), `docs/tracker-gaps-2026-11/W3a-alerts/EVIDENCE.md` (new).

- [ ] **Step 0: Do Step 4 (Rule 1 docs, inventory sentences) first**, so the blocking `docs-current-state` gate in Step 1 already sees the new Swift files; Step 4 then only adds the evidence-derived lines.
- [ ] **Step 1: Run the gates**, each with its expected result:
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → no FAIL.
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → TEST SUCCEEDED.
  - Same destination, `-only-testing:KuroUITests/ReleaseAlertOfferUITests -only-testing:KuroUITests/NavigationContractUITests` → TEST SUCCEEDED (offline fixture host; the navigation suite guards the coordinator change).
  - `scripts/quality-gates/check_architecture.sh`, `check_navigation.sh`, `check_branded_states.sh` → 0 offenders.
  - Append `W3-alerts.feature` to `scripts/quality-gates/bdd_landed.txt` (F1 landed scope), then `scripts/quality-gates/check_bdd_traceability.sh` (F1) → every `W3-alerts.feature` scenario resolves to one `ReleaseAlertOfferTests/<name>` or `ReleaseAlertOfferUITests/test<Name>`; the `@manual:awaits-D-B @owner-gate` scenario is reported as gated; exit 0. Resolved is not accepted: after Step 5's commit, re-run the `KuroTests` / `KuroUITests` commands above on that clean commit with their logs saved under `docs/tracker-gaps-2026-11/acceptance/logs/W3-<run id>.txt`, start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template W3` and write `docs/tracker-gaps-2026-11/acceptance/W3.json` in F1.3's schema (workstream `W3` = the feature basename up to its first `-`, spec §4; `context.kind: "simulator"` with the UUID; one entry per non-gated scenario (8); `unresolvedGates` names D-B for the gated W3b Rule). Run `check_bdd_traceability.sh --accepted W3` → exit 0 only when every non-gated scenario has `pass` for the tested commit; then commit only `docs/tracker-gaps-2026-11/acceptance/W3.json` and `acceptance/logs/` (F1.3 rule 2: nothing outside that folder may change after the tested commit) with message `W3a: acceptance record`.
  - `python3 scripts/quality-gates/check_docs_current_state.py` → `PASS` after Step 4 updated the inventory sentences (app Swift +3, KuroTests +1, KuroUITests +1; numbers from the script's expected text, recomputed at merge time).
  - `cd Packages/KuroModules && swift test` → pass (untouched).
  - `scripts/db/run_local_db_tests.sh` → unchanged verdict (no SQL in W3a).
  - No `deno` run: no function touched.
  - Build warnings, by unique Kuro-side warning count from the generic build log: ≤ 60.
- [ ] **Step 2: Live walk** on simulator `7FC4B58A-…` (owner-approved account, notification permission reset):
  - Save an airing anime as Watching from the detail page, from Collection's editor and from Search. Each shows exactly one offer, in that page's foot slot.
  - The pager page behind a journey shows none; neighbouring and previously visited pager pages (swipe one page left and right) show none while the offer is on screen.
  - "Notify me" shows the system prompt once.
  - Record screenshots in `docs/tracker-gaps-2026-11/W3a-alerts/`.
- [ ] **Step 3: Write `EVIDENCE.md`** with:
  - the red message and green result per task;
  - the gate outputs;
  - the warning count;
  - the Scope decision (Watching only), restated as an open owner question.
- [ ] **Step 4: Update the docs.**
  - Rule 1: Releases section + Change Log in both state docs, and the W3a status in `IMPLEMENTATION_PLAN_Variation1.md`.
  - Rule 2: in `MEMORY.md`, record the new files (`ReleaseAlertOffer.swift`, `ReleasesStore+AlertOffer.swift`, `ReleaseAlertOfferStack.swift`, `ReleaseAlertOfferTests.swift`), the updated app/test Swift counts, and these gotchas:
    - `TastePlanHost(offerSlot:)` defaults to false;
    - host environments read `ReleasesStore?` optionally;
    - the Folio batch runs under `withAlertOffersSuppressed`;
    - the presenter is chosen by visibility (`KuroNavigationCoordinator.pagerSelection` + `offerTopmostLayer`), never attach order: the pager keeps visited pages mounted; `layerRevision` exists because `layers` is not observable;
    - `--kuro-offer-fixture` (DEBUG) publishes a fixture offer for UI tests.
- [ ] **Step 5: Commit.** `git add CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md docs/tracker-gaps-2026-11/W3a-alerts/ scripts/quality-gates/bdd_landed.txt && git commit -m "Docs: W3a release alert offer"` (MEMORY.md lives outside the repo; it is saved, not committed).

---

## Gated: W3b options (needs D-B; no tasks)
D-B amends D14 ("an announced *day* does not notify") for manga chapters. Options from spec §2:
1. Keep D14: manga alerts only on exact instants (rare).
2. A day-precision alert at 09:00 local, labelled "expected today".
3. Background refresh detects a newly recorded chapter and notifies "new chapter is out". iOS decides when it runs, so it is not guaranteed to be timely.

Whichever is chosen, the W3a offer policy above (`ReleaseNotificationPlanner.isEligible` as its gate) follows it automatically for option 1, and needs its eligibility input widened for option 2 or 3. `W3-alerts.feature`'s gated rule is rewritten when the owner decides.
