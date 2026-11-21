import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class KuroGestureCoordinator {
    static let shared = KuroGestureCoordinator()

    var isHorizontalRailDragging = false
    var lastHorizontalRailDragAt: Date?

    @ObservationIgnored private var clearDragTask: Task<Void, Never>?
    @ObservationIgnored private var exclusionProviders: [UUID: @MainActor () -> CGRect?] = [:]

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

    func registerExclusionZone(id: UUID, provider: @escaping @MainActor () -> CGRect?) {
        exclusionProviders[id] = provider
    }

    func unregisterExclusionZone(id: UUID) {
        exclusionProviders.removeValue(forKey: id)
    }

    func isTouchInExclusionZone(_ globalPoint: CGPoint, verticalPadding: CGFloat = 10) -> Bool {
        let zones = exclusionProviders.values.compactMap { $0() }
        return Self.contains(globalPoint, in: zones, verticalPadding: verticalPadding)
    }

    nonisolated static func contains(_ point: CGPoint, in zones: [CGRect], verticalPadding: CGFloat = 10) -> Bool {
        zones.contains { rect in
            guard rect.width > 0, rect.height > 0 else { return false }
            return rect.insetBy(dx: 0, dy: -verticalPadding).contains(point)
        }
    }
}
