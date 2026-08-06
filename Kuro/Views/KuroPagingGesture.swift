import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Paging swipe exclusions
// We want "swipe anywhere" paging, but horizontal carousels (ScrollView(.horizontal))
// must remain scrollable without accidentally switching pages.

struct KuroSwipeExclusionZone: ViewModifier {
    @State private var markedHorizontalDrag = false

    /// Screen width for the edge-margin check (same source as ContentView.rootWidth).
    private var screenWidth: CGFloat {
        #if os(iOS)
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width) ?? 393
        #else
        1024
        #endif
    }

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
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        guard dx > max(4, dy * 1.1) else { return }
                        // Drags starting in the outer screen-edge margin belong to the
                        // root pager (ContentView's swipeEdgeMargin): never rail-mark
                        // them, or a full-page zone (the deck card) would trap paging.
                        let x = value.startLocation.x
                        guard x > KuroGesturePolicy.edgeMarginPt,
                              x < screenWidth - KuroGesturePolicy.edgeMarginPt else { return }
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
