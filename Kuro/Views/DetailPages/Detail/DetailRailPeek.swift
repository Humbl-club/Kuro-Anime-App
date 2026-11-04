import CoreGraphics
import SwiftUI

// MARK: - Edge peek (details-songs spec §5.1, D18; detail lane copy)
// Every sideways rail on the detail pages spans its column, starts at the page gutter, ends with the
// gutter as trailing content inset and shows a slice of the next card. The width function below is
// `KuroRailPeek` (folded from the lane copies, §19.7); this file keeps the detail gutter and the bleed.

/// The detail pages' rail numbers; the width rule itself is `KuroRailPeek` (Kuro/Views/Shared).
nonisolated enum DetailRailPeek {
    /// The detail body's gutter (`AnimeDetailSections` body `.padding(.horizontal, 24)`, every width).
    static let detailGutter: CGFloat = 24
}

extension View {
    /// A detail rail inside the page's padded column: the scroll view bleeds past the trailing gutter
    /// to the column edge and keeps the gutter as trailing content inset (§5.1), and `width` receives
    /// the rail's visible width for `KuroRailPeek`: the bled frame starts at the gutter (the column's
    /// own padding is its leading inset), so its width is the spec's `visible` (366 at 390 pt).
    func detailRailBleed(visible width: Binding<CGFloat>, gutter: CGFloat = DetailRailPeek.detailGutter) -> some View {
        self
            .contentMargins(.trailing, gutter, for: .scrollContent)
            // Measured on the scroll view itself, before the bleed: the padding below reports the
            // column's width to the page, while the scroll view is laid out `gutter` wider.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visible in
                if abs(width.wrappedValue - visible) > 0.5 { width.wrappedValue = visible }
            }
            .padding(.trailing, -gutter)
    }
}
