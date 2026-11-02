import SwiftUI

// MARK: - Readable width (spec D3, §3.5)
// iPhone content runs the full width. On a regular-width container (iPad, any orientation) content
// is constrained to a readable column centred in the available space; the page behind it keeps its
// own background.

private struct KuroReadableWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Readable column for regular width (iPad): at most `maxWidth` (680 pt), centred. No change on
    /// compact width (iPhone portrait).
    func kuroReadableWidth(_ maxWidth: CGFloat = KuroReadableWidth.maxWidth) -> some View {
        modifier(KuroReadableWidthModifier(maxWidth: maxWidth))
    }
}

/// The readable column's numbers.
enum KuroReadableWidth {
    /// Maximum content width on regular width (spec D3).
    static let maxWidth: CGFloat = 680
}
