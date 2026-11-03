import Foundation
import KuroWidgetSupport
import WidgetKit

// MARK: - Timeline (reads the app's snapshot; never the network)
// One entry now, plus one at every release expiry within the next day, so a passed episode leaves the
// widget without waiting for the app. The app reloads the timelines whenever it writes a new snapshot
// (throttled); the policy asks again after six hours at the latest.

struct KuroWidgetEntry: TimelineEntry {
    let date: Date
    /// nil: signed out, no snapshot yet, or no App Group (placeholder copy is shown).
    let snapshot: WidgetSnapshot?

    /// Releases still ahead at this entry's date.
    var releases: [WidgetReleaseItem] { snapshot?.releases(at: date) ?? [] }
    var nowWatching: [WidgetNowWatchingItem] { snapshot?.nowWatching ?? [] }
    var german: Bool { snapshot?.german ?? Locale.preferredLanguages.first?.hasPrefix("de") == true }
}

struct KuroSnapshotProvider: TimelineProvider {
    /// How long a timeline is trusted without an app write.
    static let refreshInterval: TimeInterval = 6 * 3600

    func placeholder(in context: Context) -> KuroWidgetEntry {
        KuroWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (KuroWidgetEntry) -> Void) {
        completion(KuroWidgetEntry(date: Date(), snapshot: Self.currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KuroWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = Self.currentSnapshot()
        completion(Timeline(entries: Self.entries(snapshot: snapshot, now: now),
                            policy: .after(now.addingTimeInterval(Self.refreshInterval))))
    }

    /// The app's snapshot with the extension's own queued +1 taps overlaid.
    static func currentSnapshot() -> WidgetSnapshot? {
        guard let snapshot = WidgetSnapshotStore.shared()?.read() else { return nil }
        return snapshot.applyingPending(WidgetAdvanceQueue.shared()?.all() ?? [])
    }

    /// Now, then each release expiry in the next 24 hours (at most 12 entries).
    static func entries(snapshot: WidgetSnapshot?, now: Date) -> [KuroWidgetEntry] {
        let horizon = now.addingTimeInterval(24 * 3600)
        let expiries = Set((snapshot?.releases ?? []).compactMap(\.expiresAt).filter { $0 > now && $0 < horizon })
        let dates = [now] + expiries.sorted().prefix(11)
        return dates.map { KuroWidgetEntry(date: $0, snapshot: snapshot) }
    }
}
