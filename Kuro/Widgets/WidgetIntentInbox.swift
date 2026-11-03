import Foundation
import KuroCore
import KuroLibrary
import KuroWidgetSupport

// MARK: - Widget +1 inbox (the app side of the hand-off queue)
// The widget's `AdvanceProgressIntent` only appends requests to the App Group queue. The app is the
// ONLY writer: it drains the queue for the CURRENT account once the Library holds that account's rows
// and applies each request through `LibraryActions.advanceQueuedProgress` (same caught-up guard,
// durable outbox and revision fence as an in-app +1; honoured only while the title still shows
// `target - 1` on the same lifecycle). Triggers: foreground, a Library change (covers the first load
// after a cold launch or sign-in), and the extension's Darwin ping while the app runs.
// Outcomes: applied / stale / refused / untracked → removed; not ready / retryable failure → kept
// (the queue's TTL bounds how long).

extension WidgetSnapshotWriter {
    /// What one drain did (tests and diagnostics).
    struct DrainReport: Equatable, Sendable {
        var applied = 0
        var dropped = 0
        var kept = 0
    }

    /// Drains when an account is current, its Library rows are loaded and requests are waiting.
    func drainIfLibraryReady() {
        guard drainTask == nil, let queue, let account = currentAccountHash,
              libraryIsReady, !queue.pending(for: account).isEmpty else { return }
        startDrain()
    }

    /// Whether the Library holds the current account's rows.
    var libraryIsReady: Bool { libraryLoadState == .loaded }

    /// Drains the current account's queued requests now (oldest first; per title in target order).
    @discardableResult
    func drainQueuedAdvances() async -> DrainReport {
        guard let queue, let context = accountSession.current, libraryIsReady else { return DrainReport() }
        let account = accountHash(for: context.userId)
        var report = DrainReport()
        var processed = Set<UUID>()
        for request in queue.pending(for: account) {
            guard accountSession.isCurrent(context), !Task.isCancelled else { break }
            let lifecycle = request.lifecycleId.flatMap(UUID.init(uuidString:))
            // A lifecycle id that is present but unreadable can never match: the request is stale.
            if request.lifecycleId != nil, lifecycle == nil {
                processed.insert(request.id)
                report.dropped += 1
                continue
            }
            // The caught-up guard uses the app's own count, never only the total echoed by the App Group.
            let own = await ownUnitCap(for: request.key)
            guard accountSession.isCurrent(context), !Task.isCancelled else { break }
            let outcome = await advanceQueuedProgress(request.key, to: request.targetUnit, lifecycleId: lifecycle,
                                                      cap: Self.queuedAdvanceCap(own: own, queued: request.total))
            switch outcome {
            case .applied:
                processed.insert(request.id)
                report.applied += 1
            case .stale, .refused, .untracked, .failed(retryable: false):
                processed.insert(request.id)
                report.dropped += 1
            case .notReady, .failed(retryable: true):
                report.kept += 1
            }
        }
        queue.remove(ids: processed)
        guard accountSession.isCurrent(context) else { return report }
        recordDrain(report)
        if report.applied > 0 || report.dropped > 0 { setNeedsWrite() }
        return report
    }

    private func startDrain() {
        let id = UUID()
        drainTaskId = id
        drainTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.drainQueuedAdvances()
            self.finishDrainTask(id)
        }
    }

    // MARK: Darwin ping from the extension

    /// Listens for the extension's "a +1 was queued" ping while the app runs (no payload: the queue is
    /// re-read and every entry validated). Installed once by composition.
    func installAdvancePing() {
        WidgetAdvancePing.shared.target = self
        WidgetAdvancePing.shared.install()
    }
}

/// The Darwin notification observer (C callback → main actor). Holds the writer weakly.
@MainActor
final class WidgetAdvancePing {
    static let shared = WidgetAdvancePing()

    weak var target: WidgetSnapshotWriter?
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, { _, _, _, _, _ in
            Task { @MainActor in WidgetAdvancePing.shared.target?.drainIfLibraryReady() }
        }, KuroAppGroup.advanceQueuedNotification as CFString, nil, .deliverImmediately)
    }
}
