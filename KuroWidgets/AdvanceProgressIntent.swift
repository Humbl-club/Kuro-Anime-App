import AppIntents
import Foundation
import KuroCore
import KuroWidgetSupport
import WidgetKit

// MARK: - +1 from the Home Screen (interactive widget button, iOS 17+ API)
// Runs in the WIDGET EXTENSION process (`supportedModes = .background`: the app is never opened and
// never launched for it). It does NOT write tracking data and holds no credentials: it checks the tap
// against the snapshot the app wrote for the current account, appends ONE request to the App Group
// queue (`WidgetAdvanceQueue`, idempotent per account / title / target unit), pings a running app
// (Darwin notification, no payload) and reloads the widget so the queued position shows at once.
// The app applies the request through `LibraryActions` (caught-up guard, durable progress outbox,
// revision fence) when it next drains: on foreground, on the ping while it runs, after sign-in.
// Not discoverable (no Shortcuts / Spotlight entry) and never reachable through a URL.
// See docs/details-songs-2026-11-03/platform/WIDGET.md.

struct AdvanceProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark the next episode or chapter"
    static let description = IntentDescription("Moves a title you are watching or reading on by one.")
    /// Widget-only: never offered in Shortcuts, Spotlight or Siri suggestions.
    static let isDiscoverable = false
    /// Runs in the background of the extension; the app is not opened.
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Medium") var medium: String
    @Parameter(title: "Title id") var mediaId: Int
    @Parameter(title: "Target unit") var targetUnit: Int

    init() {}

    init(item: WidgetNowWatchingItem) {
        medium = item.medium.rawValue
        mediaId = item.mediaId
        targetUnit = item.progress + 1
    }

    func perform() async throws -> some IntentResult {
        guard let store = WidgetSnapshotStore.shared(), let queue = WidgetAdvanceQueue.shared(),
              let kind = MediaKind(rawValue: medium) else { return .result() }
        // Only a title of the CURRENT snapshot, at the position the widget shows (queued taps included).
        guard let request = Self.request(for: kind, mediaId: mediaId, targetUnit: targetUnit,
                                         snapshot: store.read(), queued: queue.all(), now: Date()) else {
            return .result()
        }
        if queue.enqueue(request) == .queued {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFNotificationName(KuroAppGroup.advanceQueuedNotification as CFString),
                                                 nil, nil, true)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: KuroAppGroup.WidgetKind.nowWatching)
        return .result()
    }

    /// The request a tap may queue: the title is in the snapshot (same account), the tapped target is
    /// exactly the next unit after the shown position (snapshot + queued taps), and it is not caught up.
    static func request(for kind: MediaKind, mediaId: Int, targetUnit: Int, snapshot: WidgetSnapshot?,
                        queued: [WidgetAdvanceRequest], now: Date) -> WidgetAdvanceRequest? {
        guard let snapshot else { return nil }
        let shown = snapshot.applyingPending(queued)
        guard let item = shown.nowWatching.first(where: { $0.medium == kind && $0.mediaId == mediaId }),
              let next = item.advanceRequest(account: snapshot.account, now: now),
              next.targetUnit == targetUnit else { return nil }
        return next
    }
}
