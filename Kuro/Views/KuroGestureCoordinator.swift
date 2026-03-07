import Foundation
import Observation

@MainActor
@Observable
final class KuroGestureCoordinator {
    static let shared = KuroGestureCoordinator()

    var isHorizontalRailDragging = false
    var lastHorizontalRailDragAt: Date?

    private var clearDragTask: Task<Void, Never>?

    func beginHorizontalRailDrag() {
        clearDragTask?.cancel()
        isHorizontalRailDragging = true
        lastHorizontalRailDragAt = Date()
    }

    func endHorizontalRailDrag(afterMs: Double = 120) {
        lastHorizontalRailDragAt = Date()
        clearDragTask?.cancel()
        clearDragTask = Task { @MainActor in
            let delayNs = UInt64(max(0, afterMs) * 1_000_000)
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            isHorizontalRailDragging = false
        }
    }

    func recentlyDraggedRail(withinMs: Double = 220) -> Bool {
        guard let lastHorizontalRailDragAt else { return false }
        return Date().timeIntervalSince(lastHorizontalRailDragAt) * 1_000 < withinMs
    }
}
