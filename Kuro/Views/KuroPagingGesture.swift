import SwiftUI

// MARK: - Paging swipe exclusions
// We want "swipe anywhere" paging, but horizontal carousels (ScrollView(.horizontal))
// must remain scrollable without accidentally switching pages.

struct KuroSwipeExclusionZone: ViewModifier {
    @State private var markedHorizontalDrag = false

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
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        guard dx > max(4, dy * 1.1) else { return }
                        if !markedHorizontalDrag {
                            markedHorizontalDrag = true
                            KuroGestureCoordinator.shared.beginHorizontalRailDrag()
                        }
                    }
                    .onEnded { _ in
                        if markedHorizontalDrag {
                            KuroGestureCoordinator.shared.endHorizontalRailDrag(afterMs: 140)
                            markedHorizontalDrag = false
                        }
                    }
            )
            .onDisappear {
                if markedHorizontalDrag {
                    KuroGestureCoordinator.shared.endHorizontalRailDrag(afterMs: 0)
                    markedHorizontalDrag = false
                }
            }
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
