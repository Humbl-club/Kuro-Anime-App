import CoreGraphics
import SwiftUI

// MARK: - Edge peek (details-songs spec §5.1, D18; detail lane copy)
// Every sideways rail on the detail pages spans its column, starts at the page gutter, ends with the
// gutter as trailing content inset and shows a slice of the next card. The width function below is
// the spec's code, copied verbatim (the integrator folds the lane copies into
// `Kuro/Views/Shared/KuroRailPeek.swift`, §19.7). Pinned in KuroTests/DSdetailTests.swift.

/// Edge peek (details-songs spec §5.1). `visible` = the rail's frame width minus its leading content inset
/// (390 iPhone, detail gutter 24: 366; Discover gutter 20: 370; iPad readable column 680 − 20: 660).
nonisolated enum DetailRailPeek {
    static let preferredWidth: CGFloat = 100
    static let minWidth: CGFloat = 92
    static let maxWidth: CGFloat = 112
    static let peekTarget: CGFloat = 28
    static let peekMin: CGFloat = 18
    static let spacing: CGFloat = 14

    static func cardWidth(visible: CGFloat, spacing: CGFloat = spacing) -> CGFloat {
        guard visible > 0 else { return preferredWidth }
        let whole = max(2, Int(((visible - peekMin) / (preferredWidth + spacing)).rounded(.down)))
        let count = CGFloat(whole)
        let width = ((visible - count * spacing - peekTarget) / count).rounded(.down)
        return min(maxWidth, max(minWidth, width))
    }

    /// 2 : 3 covers and portraits.
    static func coverHeight(width: CGFloat) -> CGFloat { (width * 1.5).rounded() }

    /// The detail body's gutter (`AnimeDetailSections` body `.padding(.horizontal, 24)`, every width).
    static let detailGutter: CGFloat = 24

    /// Cards fully shown at `visible` (the table's second column), for the tests and the renders.
    static func cardsShown(visible: CGFloat, spacing: CGFloat = spacing) -> Int {
        let width = cardWidth(visible: visible, spacing: spacing)
        return max(0, Int(((visible + spacing) / (width + spacing)).rounded(.down)))
    }

    /// The slice of the next card that shows after the fully shown ones.
    static func slice(visible: CGFloat, spacing: CGFloat = spacing) -> CGFloat {
        let width = cardWidth(visible: visible, spacing: spacing)
        let count = CGFloat(cardsShown(visible: visible, spacing: spacing))
        return visible - count * (width + spacing)
    }
}

extension View {
    /// A detail rail inside the page's padded column: the scroll view bleeds past the trailing gutter
    /// to the column edge and keeps the gutter as trailing content inset (§5.1), and `width` receives
    /// the rail's visible width for `DetailRailPeek`: the bled frame starts at the gutter (the column's
    /// own padding is its leading inset), so its width is the spec's `visible` (366 at 390 pt).
    func detailRailBleed(visible width: Binding<CGFloat>, gutter: CGFloat = DetailRailPeek.detailGutter) -> some View {
        self
            .contentMargins(.trailing, gutter, for: .scrollContent)
            .padding(.trailing, -gutter)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visible in
                if abs(width.wrappedValue - visible) > 0.5 { width.wrappedValue = visible }
            }
    }
}
