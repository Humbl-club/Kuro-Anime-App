import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Paging swipe exclusions
// We want "swipe anywhere" paging on whitespace, while horizontal carousels and swipeable
// card stacks own horizontal gestures cleanly across their full bounds (zero scroll-time
// PreferenceKey invalidation at 120 Hz).

struct KuroSwipeExclusionZone: ViewModifier {
    @State private var zoneID = UUID()
    @State private var markedHorizontalDrag = false

    func body(content: Content) -> some View {
        content
            .background(
                KuroExclusionAnchorView(zoneID: zoneID)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
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
                KuroGestureCoordinator.shared.unregisterExclusionZone(id: zoneID)
                if markedHorizontalDrag {
                    KuroGestureCoordinator.shared.endHorizontalRailDrag(afterMs: 0)
                    markedHorizontalDrag = false
                }
            }
    }
}

#if canImport(UIKit)
private struct KuroExclusionAnchorView: UIViewRepresentable {
    let zoneID: UUID

    final class AnchorUIView: UIView {
        var zoneID: UUID

        init(zoneID: UUID) {
            self.zoneID = zoneID
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isOpaque = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let id = zoneID
            if window != nil {
                Task { @MainActor in
                    KuroGestureCoordinator.shared.registerExclusionZone(id: id) { [weak self] in
                        guard let self, self.window != nil, !self.isHidden, self.alpha > 0.01 else {
                            return nil
                        }
                        return self.convert(self.bounds, to: nil)
                    }
                }
            } else {
                Task { @MainActor in
                    KuroGestureCoordinator.shared.unregisterExclusionZone(id: id)
                }
            }
        }
    }

    func makeUIView(context: Context) -> AnchorUIView {
        let view = AnchorUIView(zoneID: zoneID)
        KuroGestureCoordinator.shared.registerExclusionZone(id: zoneID) { [weak view] in
            guard let view, view.window != nil, !view.isHidden, view.alpha > 0.01 else {
                return nil
            }
            return view.convert(view.bounds, to: nil)
        }
        return view
    }

    func updateUIView(_ uiView: AnchorUIView, context: Context) {
        if uiView.zoneID != zoneID {
            let oldID = uiView.zoneID
            uiView.zoneID = zoneID
            KuroGestureCoordinator.shared.unregisterExclusionZone(id: oldID)
            KuroGestureCoordinator.shared.registerExclusionZone(id: zoneID) { [weak uiView] in
                guard let uiView, uiView.window != nil, !uiView.isHidden, uiView.alpha > 0.01 else {
                    return nil
                }
                return uiView.convert(uiView.bounds, to: nil)
            }
        }
    }

    static func dismantleUIView(_ uiView: AnchorUIView, coordinator: ()) {
        KuroGestureCoordinator.shared.unregisterExclusionZone(id: uiView.zoneID)
    }
}
#else
private struct KuroExclusionAnchorView: View {
    let zoneID: UUID
    var body: some View { Color.clear }
}
#endif

extension View {
    /// Marks this view's frame as a "do not page-swipe" zone (used for horizontal carousels).
    func kuroSwipeExclusionZone() -> some View {
        modifier(KuroSwipeExclusionZone())
    }
}

// MARK: - Pager width

private struct KuroPagerWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The root pager's measured width (set by `KuroMainView`; 0 outside it), in the pager's global
    /// coordinates. Layout sizing always uses container geometry (`onGeometryChange`,
    /// `containerRelativeFrame`, `GeometryReader`).
    var kuroPagerWidth: CGFloat {
        get { self[KuroPagerWidthKey.self] }
        set { self[KuroPagerWidthKey.self] = newValue }
    }
}
