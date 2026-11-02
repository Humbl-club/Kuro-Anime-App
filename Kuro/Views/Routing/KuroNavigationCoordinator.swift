import SwiftUI
import UIKit

// MARK: - Root navigation (navigation contract N10)
//
// `KuroNavigationCoordinator` is the app root's presenter: it opens pages as journeys over the pager
// (`.kuroRootNavigation(_:)` at KuroRootView) and owns "collapse everything, then open" for deep links
// and notifications. EVERY sheet a page presents registers itself as a layer so a collapse can close
// it: the header sheets (Profile / Search / Concierge, whose `ShellJourneyHost` also attaches its
// journey), the onboarding cover, a pager page's own sheets (Clubs → Create / Join, Collection →
// Import / classify, Browse → Filters, Home → Import, a verdict card's editor, Concierge's import
// sheets) and the tool sheets a journey page presents itself (verdict, providers, club settings / new
// rail / new poll / add a title):
//
//     .sheet(isPresented: $showProfileSheet) { ShellJourneyHost(root: …, layer: "profile") }
//     .kuroNavigationLayer("profile", isPresented: $showProfileSheet)
//     .sheet(item: $classifyTarget) { … }
//     .kuroNavigationLayer("collection.classify", item: $classifyTarget)
//     .fullScreenCover(isPresented: $showOnboarding) { … }
//     .kuroNavigationLayer("onboarding", kind: .cover, isPresented: $showOnboarding)
//
// A layer registers once per view instance (the same page can exist twice) and records the journey
// it is presented in (`\.kuroJourney`), so a link that KEEPS that journey closes it too. Anything still
// presented over the pager that no layer accounts for is dismissed through UIKit as a last resort
// (`foreignSheetOpen`; DEBUG logs it so it gets registered).
//
// A deep link then calls (KuroMainView.handleDeepLink):
//
//     @Environment(\.kuroNavigation) private var navigation
//     navigation?.collapseThenOpen(.media(MediaRoute(kind: .anime, id: id)))
//     navigation?.collapseThen { selection = .collection }        // page links
//
// The order is `NavigationCollapsePolicy.plan` (pure, tested): the onboarding cover finishes first,
// then every sheet, tool and journey closes, then the target opens after the dismissal (presenting
// while a sheet is still leaving fails silently; a second link inside that window waits as well). A
// link whose page is already on top of the open root journey, or of a header journey, keeps that
// journey (only a tool or a sheet over its top page closes).

/// The app root's presenter and collapse coordinator (one per KuroRootView, UI state only).
@Observable
final class KuroNavigationCoordinator {
    /// What the root shows over the pager: a journey or a tool.
    let slot = PresentationSlot()

    /// How long a dismissal is given before the next presentation.
    @ObservationIgnored let dismissalDelay: Duration
    /// Increments on every collapse; a layer that cannot register a binding can observe it instead.
    private(set) var collapseGeneration = 0

    /// A registered presentation layer.
    struct Layer {
        enum Kind { case sheet, cover }
        let kind: Kind
        let isPresented: () -> Bool
        let close: () -> Void
        /// The journey whose page presents this sheet (nil: presented by a pager page or the shell).
        var presentedInJourney: ObjectIdentifier? = nil
    }

    @ObservationIgnored private var layers: [String: Layer] = [:]
    /// Journeys hosted by page-level sheets (Profile, Search, Concierge), by layer id.
    @ObservationIgnored private var sheetJourneys: [String: WeakJourney] = [:]
    @ObservationIgnored private var pending: (target: NavigationCollapsePolicy.Target, action: (() -> Void)?)?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    /// The view controller the pager lives in (resolved by the root modifier): a presentation over it
    /// that no layer accounts for is still collapsed (`foreignSheetOpen`).
    @ObservationIgnored weak var rootController: UIViewController?

    private struct WeakJourney { weak var navigator: JourneyNavigator? }

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

    func registerLayer(_ id: String, kind: Layer.Kind, presentedInJourney: ObjectIdentifier? = nil,
                       isPresented: @escaping () -> Bool, close: @escaping () -> Void) {
        layers[id] = Layer(kind: kind, isPresented: isPresented, close: close, presentedInJourney: presentedInJourney)
    }

    func unregisterLayer(_ id: String) {
        layers[id] = nil
    }

    /// A page-level sheet's journey (Profile / Search / Concierge; `id` is the name the sheet's layer
    /// registered with): a link to its top page keeps it (N10).
    func attachJourney(_ navigator: JourneyNavigator, toLayer id: String) {
        sheetJourneys[id] = WeakJourney(navigator: navigator)
    }

    func detachJourney(_ navigator: JourneyNavigator, fromLayer id: String) {
        if sheetJourneys[id]?.navigator === navigator { sheetJourneys[id] = nil }
    }

    /// The name a layer registered with (`"profile"` for the registration key `"profile#<instance>"`).
    static func layerName(_ key: String) -> String {
        String(key.prefix { $0 != "#" })
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
        let open = layers.filter { $0.value.kind == .sheet && $0.value.isPresented() }
        snapshot.openSheets = open.filter { $0.value.presentedInJourney == nil }.keys.sorted()
        // Sheets a journey page presented are grouped by the journey they cover.
        var keys: [ObjectIdentifier: String] = [:]
        if let journey { keys[ObjectIdentifier(journey)] = NavigationCollapsePolicy.rootJourney }
        for id in snapshot.openSheets {
            guard let navigator = sheetJourneys[Self.layerName(id)]?.navigator else { continue }
            snapshot.sheetJourneyTops[id] = navigator.top
            if navigator.tool != nil { snapshot.sheetJourneyTools.insert(id) }
            keys[ObjectIdentifier(navigator)] = id
        }
        for (id, layer) in open {
            guard let owner = layer.presentedInJourney, let key = keys[owner] else { continue }
            snapshot.journeySheets[key, default: []].append(id)
        }
        for key in snapshot.journeySheets.keys { snapshot.journeySheets[key]?.sort() }
        if case .tool = slot.presented { snapshot.rootToolOpen = true }
        if let journey {
            snapshot.journeyTop = journey.top
            snapshot.journeyToolOpen = journey.tool != nil
        }
        snapshot.dismissalInFlight = collapseTask != nil
        snapshot.foreignSheetOpen = foreignPresentation(known: snapshot) != nil
        return snapshot
    }

    /// A presentation over the pager no layer, tool or journey accounts for (an unregistered sheet or
    /// dialog). Nil while anything known is open (it is that presentation) or while it is leaving.
    private func foreignPresentation(known snapshot: NavigationCollapsePolicy.Snapshot) -> UIViewController? {
        guard snapshot.openSheets.isEmpty, !snapshot.coverOpen, !snapshot.rootToolOpen, snapshot.journeyTop == nil,
              slot.presented == nil, let presented = rootController?.presentedViewController,
              !presented.isBeingDismissed else { return nil }
        return presented
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
        let snapshot = snapshot
        // A newer link replaces a held one; its dismissal (if any) is still waited for (`dismissalInFlight`).
        collapseTask?.cancel()
        collapseTask = nil
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
            case .closeSheetJourneyTool(let id):
                sheetJourneys[Self.layerName(id)]?.navigator?.tool = nil
            case .closeJourneySheets(let ids), .closeSheets(let ids):
                for id in ids { layers[id]?.close() }
            case .closeForeignSheet:
                #if DEBUG
                if let presented = foreignPresentation(known: NavigationCollapsePolicy.Snapshot()) {
                    print("[KuroNavigation] collapsing an unregistered presentation: \(type(of: presented))")
                }
                #endif
                rootController?.dismiss(animated: true)
            case .keepJourney, .awaitDismissalInFlight:
                break
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
            collapseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.collapseTask = nil
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

    /// `kuroNavigationLayer` for an item sheet (`.sheet(item:)`): closing it clears the item.
    func kuroNavigationLayer<Item>(_ id: String, item: Binding<Item?>) -> some View {
        kuroNavigationLayer(id, isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        ))
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
            .background(KuroPresenterProbe { coordinator.rootController = $0 })
    }
}

/// Resolves the view controller the pager is presented from (the top of its parent chain).
private struct KuroPresenterProbe: UIViewControllerRepresentable {
    let onResolve: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onResolve = onResolve
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onResolve = onResolve
    }

    final class Controller: UIViewController {
        var onResolve: ((UIViewController) -> Void)?

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var host: UIViewController = self
            while let parent = host.parent { host = parent }
            onResolve?(host)
        }
    }
}

private struct KuroNavigationLayerModifier: ViewModifier {
    let id: String
    let kind: KuroNavigationCoordinator.Layer.Kind
    @Binding var isPresented: Bool
    @Environment(\.kuroNavigation) private var navigation
    @Environment(\.kuroJourney) private var journey
    /// One registration per view instance: the same page can exist twice (Clubs as a pager page and
    /// pushed in Profile; one verdict card per rail item), and a fixed id would let one instance
    /// overwrite or unregister the other.
    @State private var token = UUID()

    private var key: String { "\(id)#\(token.uuidString)" }

    func body(content: Content) -> some View {
        content
            .onAppear {
                let binding = $isPresented
                navigation?.registerLayer(key, kind: kind, presentedInJourney: journey?.journeyID,
                                          isPresented: { binding.wrappedValue },
                                          close: { binding.wrappedValue = false })
            }
            .onDisappear { navigation?.unregisterLayer(key) }
            .onChange(of: isPresented) { _, _ in navigation?.layerDidChange() }
    }
}
