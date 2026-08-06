import SwiftUI

enum KuroGesturePolicy {
    static let postSwipeTapCooldownMs: Double = 220
    static let fastFlingPredictedDxPt: CGFloat = 220
    static let fastFlingDirectionRatio: CGFloat = 1.25
    /// Outer screen-edge margin whose drags always belong to the root pager,
    /// never to rails or card flicks (mirrors ContentView's swipeEdgeMargin).
    static let edgeMarginPt: CGFloat = 24
}
