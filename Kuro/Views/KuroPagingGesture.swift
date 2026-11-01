import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Paging swipe exclusions
// We want "swipe anywhere" paging, but horizontal carousels (ScrollView(.horizontal))
// must remain scrollable without accidentally switching pages.

struct KuroSwipeExclusionZone: ViewModifier {
    @State private var markedHorizontalDrag = false
    /// The pager root's measured width (same source as ContentView.rootWidth); 0 outside the pager.
    @Environment(\.kuroPagerWidth) private var pagerWidth

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
                        // Global start location vs the pager width: on iPhone the pager spans the
                        // screen. Outside the pager (width 0) every drag may mark the rail.
                        let x = value.startLocation.x
                        if pagerWidth > 0 {
                            guard x > KuroGesturePolicy.edgeMarginPt,
                                  x < pagerWidth - KuroGesturePolicy.edgeMarginPt else { return }
                        }
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

// MARK: - Pager width

private struct KuroPagerWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The root pager's measured width (set by `KuroMainView`; 0 outside it), in the pager's global
    /// coordinates. For the gesture edge check only (`KuroSwipeExclusionZone`): it is NOT a layout
    /// width. On iPad each page's content is a readable column (`.kuroReadableWidth()`, max 680 pt)
    /// narrower than this, so size cards from the container you are in (`onGeometryChange`,
    /// `containerRelativeFrame`, `GeometryReader`).
    var kuroPagerWidth: CGFloat {
        get { self[KuroPagerWidthKey.self] }
        set { self[KuroPagerWidthKey.self] = newValue }
    }
}
