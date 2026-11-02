import SwiftUI

// MARK: - Root navigation (navigation contract N10)
//
// `KuroNavigationCoordinator` is the app root's presenter: it opens pages as journeys over the pager
// (`.kuroRootNavigation(_:)` at KuroRootView) and owns "collapse everything, then open" for deep links
// and notifications. Page-level layers above the pager (the Profile / Search / Concierge sheets, the
// onboarding cover) register themselves so a collapse can close them:
//
//     .sheet(isPresented: $showProfileSheet) { … }
//     .kuroNavigationLayer("profile", isPresented: $showProfileSheet)
//     .fullScreenCover(isPresented: $showOnboarding) { … }
//     .kuroNavigationLayer("onboarding", kind: .cover, isPresented: $showOnboarding)
//
// A deep link then calls (KuroMainView.handleDeepLink):
//
//     @Environment(\.kuroNavigation) private var navigation
//     navigation?.collapseThenOpen(.media(MediaRoute(kind: .anime, id: id)))
//     navigation?.collapseThen { selection = .collection }        // page links
//
// The order is `NavigationCollapsePolicy.plan` (pure, tested): the onboarding cover finishes first,
// then every sheet, tool and journey closes, then the target opens after the dismissal (presenting
// while a sheet is still leaving fails silently). A link whose page is already on top of the open root
// journey keeps that journey (only a tool over it closes).

/// The app root's presenter and collapse coordinator (one per KuroRootView, UI state only).
@Observable
final class KuroNavigationCoordinator {
    /// What the root shows over the pager: a journey or a tool.
    let slot = PresentationSlot()

    /// How long a dismissal is given before the next presentation.
    @ObservationIgnored let dismissalDelay: Duration
    /// Increments on every collapse; a layer that cannot register a binding can observe it instead.
    private(set) var collapseGeneration = 0

    /// A registered presentation layer above the pager.
    struct Layer {
        enum Kind { case sheet, cover }
        let kind: Kind
        let isPresented: () -> Bool
        let close: () -> Void
    }

    @ObservationIgnored private var layers: [String: Layer] = [:]
    @ObservationIgnored private var pending: (target: NavigationCollapsePolicy.Target, action: (() -> Void)?)?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    /// 700 ms (was 450): on iOS 26 a journey re-presented 450 ms after the previous one closed came up
    /// without its grabber (N8; reproduced on the owned simulator with `--kuro-nav-fixture` + a deep link).
    init(dismissalDelay: Duration = .milliseconds(700)) {
        self.dismissalDelay = dismissalDelay
    }

    /// The routes the pager's pages read (outside any journey).
    var routes: KuroRoutes { slot.routes }

    /// The open root journey, if any.
    var journey: JourneyNavigator? {
        if case .journey(let navigator) = slot.presented { return navigator }
        return nil
    }

    // MARK: Layers

    func registerLayer(_ id: String, kind: Layer.Kind, isPresented: @escaping () -> Bool, close: @escaping () -> Void) {
        layers[id] = Layer(kind: kind, isPresented: isPresented, close: close)
    }

    func unregisterLayer(_ id: String) {
        layers[id] = nil
    }

    /// A layer opened or closed: a link held for the cover runs once the cover is gone.
    func layerDidChange() {
        guard let pending, !coverOpen else { return }
        self.pending = nil
        run(pending.target, then: pending.action)
    }

    private var coverOpen: Bool {
        layers.values.contains { $0.kind == .cover && $0.isPresented() }
    }

    // MARK: Collapse

    /// The current presentation state (`NavigationCollapsePolicy.Snapshot`).
    var snapshot: NavigationCollapsePolicy.Snapshot {
        var snapshot = NavigationCollapsePolicy.Snapshot()
        snapshot.coverOpen = coverOpen
        snapshot.openSheets = layers.filter { $0.value.kind == .sheet && $0.value.isPresented() }.keys.sorted()
        if case .tool = slot.presented { snapshot.rootToolOpen = true }
        if let journey {
            snapshot.journeyTop = journey.top
            snapshot.journeyToolOpen = journey.tool != nil
        }
        return snapshot
    }

    /// N10: collapses every cover (after it finishes), sheet, tool and journey, then opens `page` as a
    /// new journey on the root.
    func collapseThenOpen(_ page: JourneyPage) {
        run(.journey(page), then: nil)
    }

    /// N10 page links: collapses everything, then runs `action` (switch the pager page).
    func collapseThen(_ action: @escaping () -> Void) {
        run(.page, then: action)
    }

    /// Collapses everything (no target).
    func collapseAll() {
        run(.page, then: nil)
    }

    private func run(_ target: NavigationCollapsePolicy.Target, then action: (() -> Void)?) {
        collapseTask?.cancel()
        let steps = NavigationCollapsePolicy.plan(snapshot, target: target)
        var opening: JourneyPage?
        var performsAction = false
        for step in steps {
            switch step {
            case .waitForCover:
                pending = (target, action)
                return
            case .closeJourneyTool:
                journey?.tool = nil
            case .keepJourney:
                break
            case .closeSheets(let ids):
                for id in ids { layers[id]?.close() }
            case .closeRootTool, .closeJourney:
                slot.presented = nil
            case .openJourney(let page):
                opening = page
            case .performPageAction:
                performsAction = true
            }
        }
        collapseGeneration += 1
        guard opening != nil || performsAction else { return }
        let finish = { [weak self] in
            if let opening { self?.slot.presented = .journey(JourneyNavigator(root: opening)) }
            if performsAction { action?() }
        }
        if NavigationCollapsePolicy.needsDismissalWait(steps) {
            let delay = dismissalDelay
            collapseTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                finish()
            }
        } else {
            finish()
        }
    }
}

// MARK: - Environment

private struct KuroNavigationKey: EnvironmentKey {
    static let defaultValue: KuroNavigationCoordinator? = nil
}

extension EnvironmentValues {
    /// The app root's navigation coordinator (nil in previews and test hosts without a root).
    var kuroNavigation: KuroNavigationCoordinator? {
        get { self[KuroNavigationKey.self] }
        set { self[KuroNavigationKey.self] = newValue }
    }
}

extension View {
    /// The app root's presenter (replaces `.routePresenter()` at KuroRootView): pages open as journeys
    /// over the pager, tools as tool sheets, and `\.kuroNavigation` gives deep links their collapse.
    func kuroRootNavigation(_ coordinator: KuroNavigationCoordinator) -> some View {
        modifier(KuroRootNavigationModifier(coordinator: coordinator))
    }

    /// Registers a page-level presentation layer so a deep link can collapse it (N10).
    func kuroNavigationLayer(_ id: String, kind: KuroNavigationCoordinator.Layer.Kind = .sheet,
                             isPresented: Binding<Bool>) -> some View {
        modifier(KuroNavigationLayerModifier(id: id, kind: kind, isPresented: isPresented))
    }
}

private struct KuroRootNavigationModifier: ViewModifier {
    let coordinator: KuroNavigationCoordinator

    func body(content: Content) -> some View {
        @Bindable var slot = coordinator.slot
        content
            .environment(\.kuroRoutes, coordinator.routes)
            .environment(\.kuroNavigation, coordinator)
            .sheet(item: $slot.presented) { presentation in
                SlotPresentationView(presentation: presentation)
            }
    }
}

private struct KuroNavigationLayerModifier: ViewModifier {
    let id: String
    let kind: KuroNavigationCoordinator.Layer.Kind
    @Binding var isPresented: Bool
    @Environment(\.kuroNavigation) private var navigation

    func body(content: Content) -> some View {
        content
            .onAppear {
                let binding = $isPresented
                navigation?.registerLayer(id, kind: kind,
                                          isPresented: { binding.wrappedValue },
                                          close: { binding.wrappedValue = false })
            }
            .onDisappear { navigation?.unregisterLayer(id) }
            .onChange(of: isPresented) { _, _ in navigation?.layerDidChange() }
    }
}
