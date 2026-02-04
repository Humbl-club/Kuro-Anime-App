import SwiftUI

// Shared UI environment flags for gesture-driven interactions.

private struct KuroSuppressCardTapsKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// When true, card taps should be ignored to avoid accidental opens while paging/swiping.
    var kuroSuppressCardTaps: Bool {
        get { self[KuroSuppressCardTapsKey.self] }
        set { self[KuroSuppressCardTapsKey.self] = newValue }
    }
}

