# Home Screen widget, +1 hand-off and release notifications — platform lane

Date: 2026-11-03. Branch `kuro/details-songs-platform-platform` (from `kuro/discover-clubs-redesign`). Local only: nothing pushed, deployed, flagged or written to production. No backend change (no migration, no edge function).

Items covered: **9** (WidgetKit widget, Now Watching +1, App Group snapshot) and the core of **10** (local release notifications). The widget's look belongs to the widget UI lane; the Profile toggle / detail bell UI belongs to the profile lane. This lane ships the target, the data contract, the write path, the scheduler and the APIs those lanes call.

## 1. What was added

| Piece | Where | Role |
|---|---|---|
| App Group `group.com.Kuro.app` | `Kuro/Kuro.entitlements`, `KuroWidgets/KuroWidgets.entitlements` | The only shared storage between the app and the extension. |
| Widget extension target **KuroWidgets** | `KuroWidgets/` (synced folder; `Info.plist` excluded from membership), `Kuro.xcodeproj` | `com.Kuro.app.widgets`, team `YLG68JL5Y7`, automatic signing, `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `CURRENT_PROJECT_VERSION = 23` / `MARKETING_VERSION = 1.0` (same as the app; `release_candidate.rb` checks every `CURRENT_PROJECT_VERSION`), `APPLICATION_EXTENSION_API_ONLY = YES`, generated Info.plist + `NSExtensionPointIdentifier = com.apple.widgetkit-extension`. Embedded through the app's "Embed Foundation Extensions" phase; the app target depends on it; it is a build entry of the shared `Kuro` scheme. |
| Package target **KuroWidgetSupport** | `Packages/KuroModules/Sources/KuroWidgetSupport/` | Foundation + CryptoKit only. `KuroAppGroup` (ids, file layout, widget kinds, Darwin ping name), `WidgetSnapshot` (+ release / Now Watching rows), `WidgetSnapshotStore` (snapshot + `thumbs/`), `WidgetAdvanceQueue` (+1 hand-off), `WidgetAccountHash`. Linked by the app AND the extension; the extension links only this and `KuroCore` (never the tracking store or the SDK). |
| `WidgetSnapshotWriter` (+ `WidgetIntentInbox`) | `Kuro/Widgets/` | App owner (`@MainActor @Observable`, `AccountScopedState`, registered in `AppComposition.makeAccountScopedStates` before the telemetry). Writes the snapshot, drains the +1 queue. |
| `WidgetSnapshotBuilder` | `Kuro/Widgets/WidgetSnapshotBuilder.swift` | Pure: schedule + Library rows + catalogue facts → `WidgetSnapshot`, wording from `ReleaseCopy`. |
| `LibraryActions.advanceQueuedProgress` | `Kuro/Library/LibraryActions.swift` | The one write path the widget's +1 reaches. |
| `AdvanceProgressIntent` | `KuroWidgets/AdvanceProgressIntent.swift` | Interactive widget button. Queues only. |
| Release notifications | `Kuro/Releases/ReleaseNotificationPlanner.swift`, `ReminderScheduler+Releases.swift`, `ReleasesStore+Notifications.swift`, `ReleaseNotificationRouting.swift` | Plan (pure), device commit on the reminder chain, view-facing toggle API, tap routing. |

The iOS 26 deployment floor: the app's minimum is iOS 26 and the local package declares `.iOS(.v26)`, so the extension cannot go lower (an extension never runs on an OS its app does not support). Every widget API used (interactive `Button(intent:)`, `containerBackground`, `AppIntent`) is iOS 17+; the "iOS 17+" requirement is met as an API floor.

## 2. Snapshot contract (app → extension)

`Widgets/snapshot.json` in the App Group, schema `WidgetSnapshot.currentSchema = 1`:

- `account`: `WidgetAccountHash` = SHA-256(per-install salt | lower-cased user id). The salt lives in the APP's own `UserDefaults` (`com.kuro.widgets.accountSalt`), never in the group, so the extension cannot derive or compare user ids and the tag is not linkable across installs. No user id, e-mail, token or key is written.
- `german`: the language the app rendered.
- `releases` (≤ 8, soonest first, displayable and still ahead): `unitLabel`, `datePhrase`, `line`, `accessibilityLine` rendered by `ReleaseCopy` (EN/DE); `basis`, `precision`; **`countdownTarget` is set only when `ReleaseScheduleItem.showsTime` (an instant that is not an estimate)** — announced days, month/quarter/year windows and estimates never carry a time; `isEstimate`; `expiresAt` (the instant, or the next local midnight after a day release; nil for windows); `thumbnail`; `deepLink` (`kuro://anime/<id>` / `kuro://manga/<id>`, navigation only).
- `nowWatching` (≤ 6, watching/rewatching/reading/rereading, newest update first, a title is required): displayed `progress` (pending outbox writes included), `total`, `unitPrefix` ("Ep. "/"F. ", "Ch. "/"Kap. "), `lifecycleId`, `revision` (informational), `artworkURL`, `thumbnail`, `deepLink`.

Thumbnails: ≤ 150 px JPEG (q 0.7) from `ImagePipeline`, ≤ 96 KB each, ≤ 10 fetched per write, names `"<medium>-<id>-<fnv(url)>.jpg"`, unreferenced files pruned. A name read back from the file is validated (letters, digits, `-`, `.`, no leading dot) so it can never leave `thumbs/`.

Writes: inputs observed with `withObservationTracking` (Library rows + load state, `ReleasesStore.schedule`, `upcomingAirings`), one write after 1.5 s, also on foreground and when the scene goes to the background. An unchanged snapshot (`hasSameContent`) is neither written nor reloaded, so the daily WidgetKit reload budget is spent only on real changes. All files: atomic, `NSFileCoordinator`, `completeUntilFirstUserAuthentication` (the widget renders on a locked device after the first unlock).

## 3. The +1 mechanism (item 9, part C) and why

**Chosen: the extension queues, the app writes.**

1. The widget's `Button(intent: AdvanceProgressIntent(item:))` runs `perform()` in the **extension** process (`supportedModes = .background`; the app is not opened or launched). `isDiscoverable = false`: no Shortcuts / Spotlight / Siri entry.
2. `perform()` reads the current snapshot and the queue and accepts the tap only when the title is in the snapshot and the tapped target is exactly the next unit after the shown position (snapshot + already queued taps) and the title is not caught up. It appends ONE `WidgetAdvanceRequest` (account tag, medium, id, `targetUnit`, lifecycle, total, time) to `Widgets/advance-queue.json`, posts the Darwin notification `com.Kuro.app.widgets.advance-queued` (no payload) and reloads the Now Watching timeline, which overlays the queued taps (`applyingPending`), so the widget shows the new position at once ("Saving in Kuro" as the VoiceOver value).
3. The app drains (`WidgetIntentInbox`) for the CURRENT account once the Library holds that account's rows: on foreground, on any Library change (covers the first load after a cold launch or sign-in), and on the Darwin ping while the app runs. Each request goes through `LibraryActions.advanceQueuedProgress`, which mirrors `CollectionStore.advanceFromList`: the durable `ProgressOutbox` with the unit cap when it accepts writes (its caught-up guard and the server revision fence apply at admission), otherwise one absolute progress edit, never past the cap. It is honoured only while the title still shows `target − 1` on the same lifecycle.
4. Outcomes: applied / stale / refused / untracked → removed from the queue; not ready / retryable failure → kept (48 h TTL). No banner, no Undo receipt (Home's and Collection's Undo paths are untouched).

Security reasoning:

- **The extension never writes tracking data** and holds no credentials: it has no SDK, no Supabase client, no Keychain access group, and the package it links has no network code.
- **Never URL-triggered**: there is no `kuro://` route for +1; widget links only open title journeys. The intent is not discoverable, so it cannot be built into a Shortcut from the UI.
- **A crafted or replayed queue entry can do at most what the user could do in the app at that moment**: the app checks the account tag of the current account, the lifecycle, the exact expected position (`target − 1`) and the cap, then uses the normal write path with its own fence. Idempotency per (account, title, target unit) comes from the queue (one entry per key; a double tap queues once) and from the expected-position check (an already-applied request is a no-op).
- **Account scope**: a request carries the opaque account tag; the app applies only the current account's; a switch keeps only the next account's requests, sign-out removes all (section 5).

Considered and not chosen:

- `supportedModes = .foreground(...)` (successor of `openAppWhenRun` / `ForegroundContinuableIntent`, both deprecated in the iOS 26 SDK): every +1 would open Kuro, so the button would no longer be an interactive widget control.
- Compiling the intent into the app and conforming it to `LiveActivityIntent` so the system runs `perform()` in the app process: that protocol is meant for Live Activities, and it would boot the whole object graph headless (session restore, Library refresh) inside a widget tap.

Consequence (open item for the owner): when Kuro is not running, a widget +1 is stored on the device and shown on the widget at once, and reaches the server the next time Kuro opens (or the Library loads after sign-in). If the server save has to happen while Kuro stays closed, the `LiveActivityIntent` route above is the alternative.

## 4. Release notifications (item 10 core)

Rules (`ReleaseNotificationPlanner`, all pinned by `PlatformLaneTests`):

- Only titles the account is **watching / reading** (`current`, `repeating`) and has not muted with the detail bell. The existing airing reminders (`airing-<id>-start` / `-1h`) follow the same rule now: a planned or paused anime is not armed (and loses pending ones), also at import publication.
- Only **confirmed** and **announced** rows; **an estimate never notifies**.
- Precision **instant**: at the release moment, body may show the time (`"Ep. 8 · Today, 21:30"` / `"F. 8 · Heute, 21:30"`).
- Precision **day**: **09:00 local** on the release day, day wording, no time (`"Ch. 68 · Today"` / `"Kap. 68 · Heute"`). The day is read exactly as `ReleaseCopy.calendarDay` reads it, so a day stored at 00:00 UTC is never a day early west of UTC.
- Month / quarter / year windows and undated rows: no notification.
- Nothing closer than 60 s, soonest first, **at most 64 pending per app**: the commit budgets 64 minus the device reminders it does not own (e.g. the airing path's "in 1 hour" requests).
- Copy is `ReleaseCopy` rendered at the fire moment (EN/DE via `KuroLocale`). Ids are stable per unit (`release-<medium>-<id>-<unit>-<n>`); an AniList-confirmed anime episode uses the airing reminder's own id `airing-<id>-start`, so the two paths never notify twice.
- Payload `kuro_link` = `kuro://anime/<id>` / `kuro://manga/<id>`. A tap goes through `KuroNotificationDelegate` (installed by `KuroAppDelegate` before launch finishes) → `NotificationLinkInbox` → `KuroApp` sets `pendingDeepLink` exactly like `onOpenURL`, so the navigation contract's N10 collapse rules apply. Any other scheme/host/path/query is ignored (`ReleaseNotificationLink.validatedURL`).

Permission: **asked only from an explicit user action**. `ReleasesStore.setReleaseNotificationsEnabled(true)` (Profile toggle) and `setReleaseNotification(true, for:)` (detail bell) are the only callers of the prompting request. Every automatic path reads the permission without prompting (`PendingNotificationCenter.currentPermission()`); the existing airing reminders were changed to that as well (they used to prompt on the first tracked anime). An account that turns notifications off gets no automatic reminders at all.

Preference per account (app `UserDefaults`, keyed like the existing owner marker): unset → follows the system permission (an account that already allowed notifications keeps its reminders after this update; nobody is opted in without having allowed them); `true` / `false` → the user's choice. Muted titles are a per-account set. Deletion removes both.

Re-planning: on every schedule change (`publishSchedule`), on every non-progress Library change, on foreground (`refreshReleaseNotifications`), at bootstrap (`startCountdownUpdates`), and on toggle / bell. An account that chose "on" gets its schedule read even if no screen loaded it. Clearing: the session funnel's reminder removal now removes `release-*` with `airing-*` on sign-out and account switch (same F05 chain and owner marker), and `ReleasesStore.clearPrivateState` resets the observable state.

## 5. Account scope of the widget files

`WidgetSnapshotWriter.clearPrivateState` runs after the session funnel already names the next account:

- signed out → snapshot, thumbnails and every queued +1 removed, timelines reloaded;
- another account → the same, except that account's own queued requests stay;
- the same account restored at launch → files kept, so a tap made while Kuro was not running is applied once the Library loads;
- a failed launch restore (offline, expired token) in which no account ended → files kept (the writer remembers in memory which account it last served; none before and none after means nobody signed out);
- a failed restore after which the SDK holds no session any more → snapshot, thumbnails and queue removed (`AccountScopedState.removeDataWithoutOwner`, called by the session funnel next to the airing-reminder removal);
- account deletion (`removeDeletedAccountData`) → that account's snapshot and requests removed.

Unsigned builds (`CODE_SIGNING_ALLOWED=NO`) may have no App Group container; the writer then does nothing. Test and fixture hosts never use the App Group (tests pass their own directory).

## 6. Interfaces for the other lanes

Widget UI lane (replace the bodies of `KuroWidgets/KuroWidgetViews.swift`; keep the contract):

```swift
struct KuroWidgetEntry: TimelineEntry {          // KuroWidgets/KuroWidgetTimeline.swift
    let date: Date
    let snapshot: WidgetSnapshot?                 // nil: signed out / no snapshot yet
    var releases: [WidgetReleaseItem]             // still ahead at `date`
    var nowWatching: [WidgetNowWatchingItem]      // queued +1 taps already overlaid
    var german: Bool
}
AdvanceProgressIntent(item: WidgetNowWatchingItem) // the ONLY +1; Button(intent:) on a non-caught-up row
item.isCaughtUp / item.progressText / item.isQueued / item.thumbnail / item.deepLink
release.line / release.accessibilityLine / release.countdownTarget (time allowed only when non-nil)
release.isEstimate / release.expiresAt / release.thumbnail / release.deepLink
WidgetThumbnail(name:), WidgetLinked(url:), WidgetPalette, WidgetChrome (EN/DE chrome strings)
KuroAppGroup.WidgetKind.nextRelease / .nowWatching (kinds; the app reloads exactly these)
```

Rules for that lane: never show a clock time unless `countdownTarget != nil` (use `Text(target, style: .relative/.timer)` or `line`); never add a `kuro://` link that changes data; never fetch from the network (thumbnails are cached by the app).

Profile lane (toggle) and detail lane (bell), all on `@Environment(ReleasesStore.self)`:

```swift
var releaseNotificationsEnabled: Bool                         // observable
var notificationPermission: NotificationPermission            // .authorized / .denied / .notDetermined (no prompt)
var mutedReleaseNotificationKeys: Set<MediaKey>
func setReleaseNotificationsEnabled(_ enabled: Bool) async -> ReleaseNotificationToggleResult
func setReleaseNotification(_ enabled: Bool, for key: MediaKey) async -> ReleaseNotificationToggleResult
func releaseNotificationsOn(for key: MediaKey) -> Bool
func refreshReleaseNotificationState() async                  // call from .task to show the current state
enum ReleaseNotificationToggleResult { case enabled, disabled, permissionDenied, signedOut }
```

On `.permissionDenied` the UI offers the system Settings (`UIApplication.openNotificationSettingsURLString`) with EN/DE copy via `KuroLocale`; it must not call any other permission API.

## 7. TestFlight archive steps (lead)

1. App Store Connect / Developer portal (or let Xcode do it with `-allowProvisioningUpdates`, which `fastlane archive_beta` already passes): register the App Group **`group.com.Kuro.app`**, register the App ID **`com.Kuro.app.widgets`**, enable the **App Groups** capability on both `com.Kuro.app` and `com.Kuro.app.widgets`, and assign the group to both. With automatic signing and an account that may create identifiers, `xcodebuild -allowProvisioningUpdates` creates the App ID, enables the capability and regenerates both App Store profiles itself; the account used by the archive must have the Admin or App Manager role with access to Certificates, Identifiers & Profiles.
2. `fastlane/Fastfile` `archive_beta` exports with `signingStyle: automatic` and no `provisioningProfiles` map, so the extension needs no extra entry. `freeze_beta` (`increment_build_number`) bumps `CURRENT_PROJECT_VERSION` in every target, and `release_candidate.rb` refuses a candidate unless all of them match: the extension carries the same literal `23` today.
3. `record_archive!` checks the IPA's bundle id is `com.Kuro.app` (unchanged; the extension is inside `Kuro.app/PlugIns/KuroWidgets.appex`).
4. After upload, check in TestFlight that the widget gallery shows "Up next" and "Now watching", and that a +1 on the widget shows at once and is saved after opening Kuro.

## 8. Verification (this lane)

See the lane's final report for the exact commands. Unit: `PlatformLaneTests` (22 tests: snapshot certainty rules, German/bounds, Now Watching rows, sign-out / switch / restore / deletion of the widget files, drain order / idempotency / caught-up / lifecycle / foreign account, notification plan rules, 64 budget, toggle prompting, account-switch clearing) and `KuroWidgetSupportTests` (12 tests). The existing F19 reminder tests were updated to the "never prompt automatically" rule.

## 9. Open

- Widget +1 reaches the server only when Kuro next runs (section 3); owner decision if that must change.
- VoiceOver order and the widget on a real device / Home Screen are not device-checked in this lane (no signed build); the placeholder views give every row one element and the +1 a label and value.
- Legacy airing reminder text ("… airs now" / "In 1 hour: …") is still English-only; the release notifications that replace it for AniList episodes use `ReleaseCopy` (EN/DE).
- The snapshot is written only while the app runs; a release that passes is dropped by the widget's own timeline (`expiresAt`), but the next unit appears only after the app refreshes the schedule.
