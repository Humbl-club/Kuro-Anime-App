import Foundation
import SwiftUI

/// W4: the one plain line Search shows when 18+ titles matched the query but are not listed.
nonisolated enum SearchAdultNotice {
    /// `nil` when nothing was hidden (count <= 0).
    static func line(hiddenAdult: Int, german: Bool) -> String? {
        guard hiddenAdult > 0 else { return nil }
        return german ? "Kuro listet keine Titel ab 18." : "Kuro doesn't list 18+ titles."
    }
}

/// The footnote under the results and under the no-results state: the line, or nothing (zero
/// height) when no 18+ title was hidden. Monochrome, no icon.
struct SearchAdultFootnote: View {
    let hiddenAdult: Int

    var body: some View {
        if let line = SearchAdultNotice.line(hiddenAdult: hiddenAdult, german: KuroLocale.isGerman) {
            Text(line)
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, KuroDesignSpacing.sm)
                .accessibilityIdentifier("search.adultNotice")
        }
    }
}
