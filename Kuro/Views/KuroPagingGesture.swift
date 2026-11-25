import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Paging swipe exclusions & root directional pan recognizer
// We want "swipe anywhere" paging on whitespace, while vertical ScrollViews own every vertical drag
// at a locked 120 Hz (the root UIPanGestureRecognizer fails immediately in `gestureRecognizerShouldBegin`
// on vertical movement, zero SwiftUI DragGesture evaluation per frame) and horizontal carousels /
// swipeable card stacks own horizontal gestures cleanly across their full bounds.

struct KuroSwipeExclusionZone: ViewModifier {
    @State private var zoneID = UUID()

    func body(content: Content) -> some View {
        content
            .background(
                KuroExclusionAnchorView(zoneID: zoneID)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .onDisappear {
                KuroGestureCoordinator.shared.unregisterExclusionZone(id: zoneID)
            }
    }
}

#if canImport(UIKit)
/// Pure directional helpers for `KuroRootPagerPanOverlay` (unit-tested in KuroTests).
nonisolated enum KuroRootPanPolicy {
    static func shouldBeginHorizontalPan(translation: CGPoint, velocity: CGPoint) -> Bool {
        let vx = abs(velocity.x)
        let vy = abs(velocity.y)
        let dx = abs(translation.x)
        let dy = abs(translation.height)
        if vx + vy > 0 {
            return vx > vy * 1.15 && (dx >= dy || vx > 40)
        }
        return dx > max(2, dy * 1.15)
    }

    static func effectiveHorizontalTranslation(dx: CGFloat, vx: CGFloat) -> CGFloat {
        let velocityContribution = vx * 0.14
        if (dx >= 0 && velocityContribution >= 0) || (dx <= 0 && velocityContribution <= 0) {
            return dx + velocityContribution
        }
        return abs(velocityContribution) > abs(dx) ? velocityContribution : dx
    }
}

private extension CGPoint {
    var height: CGFloat { y }
}

/// Attaches a single UIKit `UIPanGestureRecognizer` to the enclosing hosting view covering the root
/// pager. Vertical drags fail synchronously inside `gestureRecognizerShouldBegin` without touching
/// exclusion closures or SwiftUI state, eliminating 120 Hz vertical-scroll choppiness.
struct KuroRootPagerPanOverlay: UIViewControllerRepresentable {
    var isEnabled: Bool
    var swipeThreshold: CGFloat = 40
    var onSuppressTaps: () -> Void
    var onSwipeEnded: (_ fastFlick: Bool) -> Void
    var onCommitDirection: (_ step: Int) -> Void
    var onDragChanged: (_ translationX: CGFloat) -> Void = { _ in }
    var onDragCancelled: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> HostController {
        let controller = HostController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: HostController, context: Context) {
        context.coordinator.parent = self
        uiViewController.coordinator = context.coordinator
        uiViewController.attachIfNeeded()
        context.coordinator.panRecognizer?.isEnabled = isEnabled
    }

    static func dismantleUIViewController(_ uiViewController: HostController, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class HostController: UIViewController {
        weak var coordinator: Coordinator?

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            self.view = view
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attachIfNeeded()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfNeeded()
        }

        func attachIfNeeded() {
            guard let coordinator else { return }
            let targetHost = parent?.view ?? nearestHostingView(from: view)
            guard let targetHost else { return }
            coordinator.attach(to: targetHost, boundsView: view, hostController: parent)
        }

        private func nearestHostingView(from leaf: UIView) -> UIView? {
            var current: UIView? = leaf.superview
            var candidate: UIView?
            while let view = current {
                if view is UIWindow { break }
                candidate = view
                if String(describing: type(of: view)).contains("UIHosting") {
                    return view
                }
                current = view.superview
            }
            return candidate
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: KuroRootPagerPanOverlay
        weak var attachedView: UIView?
        weak var boundsView: UIView?
        weak var hostController: UIViewController?
        var panRecognizer: UIPanGestureRecognizer?
        private var didSuppressThisGesture = false
        private var isTrackingHorizontalDrag = false

        init(parent: KuroRootPagerPanOverlay) {
            self.parent = parent
        }

        func attach(to targetView: UIView, boundsView: UIView, hostController: UIViewController?) {
            self.boundsView = boundsView
            self.hostController = hostController
            if attachedView === targetView, panRecognizer != nil { return }
            detach()

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            pan.isEnabled = parent.isEnabled
            targetView.addGestureRecognizer(pan)
            attachedView = targetView
            panRecognizer = pan
        }

        func detach() {
            if let panRecognizer, let attachedView {
                attachedView.removeGestureRecognizer(panRecognizer)
            }
            panRecognizer = nil
            attachedView = nil
        }

        private func hasHorizontalScrollAncestor(startingAt hitView: UIView?, boundBy rootView: UIView) -> Bool {
            var cursor = hitView
            while let view = cursor, view !== rootView {
                if let scroll = view as? UIScrollView,
                   scroll.isScrollEnabled,
                   scroll.contentSize.width > scroll.bounds.width + 2 {
                    return true
                }
                cursor = view.superview
            }
            return false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let hostView = attachedView,
                  hostController?.presentedViewController == nil else {
                return false
            }

            let translation = pan.translation(in: hostView)
            let velocity = pan.velocity(in: hostView)
            // Vertical scroll check FIRST (O(1) math, zero UIView.convert or hitTest calls).
            guard KuroRootPanPolicy.shouldBeginHorizontalPan(translation: translation, velocity: velocity) else {
                return false
            }

            let globalPoint = pan.location(in: nil)
            if let boundsView, boundsView.window != nil {
                let globalBounds = boundsView.convert(boundsView.bounds, to: nil)
                if !globalBounds.isEmpty && !globalBounds.contains(globalPoint) {
                    return false
                }
            }

            let localPoint = pan.location(in: hostView)
            if hasHorizontalScrollAncestor(startingAt: hostView.hitTest(localPoint, with: nil), boundBy: hostView) {
                return false
            }

            if KuroGestureCoordinator.shared.isHorizontalRailDragging
                || KuroGestureCoordinator.shared.recentlyDraggedRail(withinMs: KuroGesturePolicy.postSwipeTapCooldownMs)
                || KuroGestureCoordinator.shared.isTouchInExclusionZone(globalPoint) {
                return false
            }

            didSuppressThisGesture = false
            isTrackingHorizontalDrag = false
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allow UIKit controls/scroll views to coexist cleanly while vertical drags were already
            // filtered out in `gestureRecognizerShouldBegin`.
            true
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let hostView = attachedView else { return }
            let translation = pan.translation(in: hostView)
            let velocity = pan.velocity(in: hostView)

            switch pan.state {
            case .began, .changed:
                let dx = abs(translation.x)
                let dy = abs(translation.y)
                if !isTrackingHorizontalDrag {
                    guard dx > 8, dx > dy * 1.1 else { return }
                    guard !KuroGestureCoordinator.shared.isHorizontalRailDragging else { return }
                    isTrackingHorizontalDrag = true
                }
                parent.onDragChanged(translation.x)
                let predictedDx = abs(KuroRootPanPolicy.effectiveHorizontalTranslation(dx: translation.x, vx: velocity.x))
                if !didSuppressThisGesture && (predictedDx > 18 || abs(velocity.x) > 180 || dx > 20) {
                    didSuppressThisGesture = true
                    parent.onSuppressTaps()
                }
            case .ended, .cancelled, .failed:
                let dx = translation.x
                let dy = translation.y
                let effectiveDx = KuroRootPanPolicy.effectiveHorizontalTranslation(dx: dx, vx: velocity.x)
                let fastFlick = abs(velocity.x) > 700
                let wasTracking = isTrackingHorizontalDrag
                defer {
                    didSuppressThisGesture = false
                    isTrackingHorizontalDrag = false
                }
                guard pan.state == .ended else {
                    if wasTracking { parent.onDragCancelled() }
                    if didSuppressThisGesture { parent.onSwipeEnded(false) }
                    return
                }
                if (abs(dx) > abs(dy) * 0.85 || abs(velocity.x) > abs(velocity.y) * 1.1),
                   abs(effectiveDx) >= parent.swipeThreshold,
                   !KuroGestureCoordinator.shared.isHorizontalRailDragging,
                   !KuroGestureCoordinator.shared.recentlyDraggedRail(withinMs: KuroGesturePolicy.postSwipeTapCooldownMs) {
                    let step = effectiveDx < 0 ? 1 : -1
                    parent.onCommitDirection(step)
                    parent.onSwipeEnded(fastFlick)
                } else {
                    if wasTracking { parent.onDragCancelled() }
                    if didSuppressThisGesture { parent.onSwipeEnded(false) }
                }
            default:
                break
            }
        }
    }
}
#else
nonisolated enum KuroRootPanPolicy {
    static func shouldBeginHorizontalPan(translation: CGPoint, velocity: CGPoint) -> Bool { false }
    static func effectiveHorizontalTranslation(dx: CGFloat, vx: CGFloat) -> CGFloat { dx }
}

struct KuroRootPagerPanOverlay: View {
    var isEnabled: Bool
    var swipeThreshold: CGFloat = 40
    var onSuppressTaps: () -> Void
    var onSwipeEnded: (_ fastFlick: Bool) -> Void
    var onCommitDirection: (_ step: Int) -> Void
    var onDragChanged: (_ translationX: CGFloat) -> Void = { _ in }
    var onDragCancelled: () -> Void = {}
    var body: some View { Color.clear }
}
#endif

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
