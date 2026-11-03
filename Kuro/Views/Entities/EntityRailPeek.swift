import CoreGraphics

// MARK: - Edge peek, entity pages (details-songs spec §5.1, D18)
// The body of `KuroRailPeek` copied verbatim (the integrator folds `DetailRailPeek`, `EntityRailPeek` and
// Discover's copy into `Kuro/Views/Shared/KuroRailPeek.swift`, §19.7). Every horizontal rail on an entity
// page spans the page column, starts at the 24 pt gutter, ends with the gutter as trailing inset, and shows
// a slice of the next card.

/// Edge peek (details-songs spec §5.1). `visible` = the rail's frame width minus its leading content inset
/// (390 iPhone, detail gutter 24: 366; Discover gutter 20: 370; iPad readable column 680 − 20: 660).
nonisolated enum EntityRailPeek {
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
}

/// The entity pages' layout numbers.
nonisolated enum EntityPageLayout {
    /// The detail body's gutter, at every width (spec §4, §9).
    static let gutter: CGFloat = 24
    /// A rail's visible width inside a page column of `column` points.
    static func railVisible(column: CGFloat) -> CGFloat { max(0, column - gutter) }
    /// The voice-role read's limit (the data lane's reader clamps at 100). A read that returns this many is a
    /// floor ("100+"), never a total.
    static let voiceRoleLimit = 100
    /// Whether a bounded read stopped at its limit (its count is a floor).
    static func isFloor(_ count: Int, limit: Int) -> Bool { limit > 0 && count >= limit }

    /// The studio name is 34 pt on a compact column (320 pt phones), otherwise 44 (Home's cover line).
    static func studioNameSize(column: CGFloat) -> CGFloat { column > 0 && column < 360 ? 34 : 44 }
}
