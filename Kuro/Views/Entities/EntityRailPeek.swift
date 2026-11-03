import CoreGraphics

// MARK: - Entity page layout (details-songs spec §9). The rail width rule is `KuroRailPeek`.

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
