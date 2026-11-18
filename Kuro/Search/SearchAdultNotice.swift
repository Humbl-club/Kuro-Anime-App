import Foundation

/// W4: the one plain line Search shows when 18+ titles matched the query but are not listed.
nonisolated enum SearchAdultNotice {
    /// `nil` when nothing was hidden (count <= 0).
    static func line(hiddenAdult: Int, german: Bool) -> String? {
        guard hiddenAdult > 0 else { return nil }
        return german ? "Kuro listet keine Titel ab 18." : "Kuro doesn't list 18+ titles."
    }
}
