import Foundation
import Observation

/// Owner of the app's transient banner (E6c2; moved from `SupabaseService`, behavior unchanged).
///
/// One message at a time: `show` replaces the current message at once (newest wins) and clears it
/// after `duration` seconds (2.4 s by default) unless a newer message replaced it meanwhile. Composition
/// owns the single instance and injects it into the SwiftUI environment; the session funnel (rejected
/// auth callbacks) and `LibraryActions` (toggle results) post to it.
@MainActor
@Observable
final class BannerCenter {
    /// Production auto-clear wait.
    static func sleep(_ delay: Duration) async throws {
        try await Task.sleep(for: delay)
    }

    /// The banner on screen, if any.
    private(set) var message: String? = nil

    /// The pending auto-clear of the current message (awaitable in tests).
    @ObservationIgnored private(set) var dismissTask: Task<Void, Never>? = nil
    /// The auto-clear wait (injectable for tests; production sleeps).
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    init(sleep: @escaping @MainActor (Duration) async throws -> Void = BannerCenter.sleep) {
        self.sleep = sleep
    }

    func show(_ message: String, duration: Double = 2.4) {
        dismissTask?.cancel()
        self.message = message
        let sleep = self.sleep
        dismissTask = Task { @MainActor in
            try? await sleep(.seconds(duration))
            guard !Task.isCancelled else { return }
            if self.message == message {
                self.message = nil
            }
        }
    }
}
