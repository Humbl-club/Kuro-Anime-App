import SwiftUI

// MARK: - Paging swipe exclusions
// We want "swipe anywhere" paging, but horizontal carousels (ScrollView(.horizontal))
// must remain scrollable without accidentally switching pages.

struct KuroSwipeExclusionZone: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: KuroSwipeExclusionPreferenceKey.self,
                            value: [proxy.frame(in: .named("kuro_root"))]
                        )
                }
            )
    }
}

extension View {
    /// Marks this view's frame as a "do not page-swipe" zone (used for horizontal carousels).
    func kuroSwipeExclusionZone() -> some View {
        modifier(KuroSwipeExclusionZone())
    }
}

struct KuroSwipeExclusionPreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

