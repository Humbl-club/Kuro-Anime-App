import CoreGraphics

// MARK: - Edge peek (details-songs spec §5.1, D18)
// Every horizontal card rail (Discover, detail pages, entity pages) spans the full width of its page
// column, starts at the page gutter, ends with the gutter as trailing content inset and shows a slice
// of the next card. The integrator folded the lane copies (`DetailRailPeek`, `EntityRailPeek`,
// `DiscoverRailPeek`, all byte-identical) into this one file (§19.7). Pinned in KuroTests
// (DSdetailTests, DSsongsTests, DSprofileTests). Exempt: the D4 season tiles, club rails, Home,
// Browse, Search, Taste and Collection.

/// Edge peek (details-songs spec §5.1). `visible` = the rail's frame width minus its leading content inset
/// (390 iPhone, detail gutter 24: 366; Discover gutter 20: 370; iPad readable column 680 − 20: 660).
nonisolated enum KuroRailPeek {
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

    /// Cards fully shown at `visible` (the spec table's second column), for the tests and the renders.
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
