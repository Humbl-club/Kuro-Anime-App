import KuroCore
import SwiftUI
import UIKit

// MARK: - Journey host (navigation contract §1–§2)
//
// One sheet = one `JourneyHost` = one `NavigationStack(path:)` over `JourneyPage` values. The host:
//   - builds every page (`JourneyPageView`) for the root and for `navigationDestination(for:)`,
//   - injects `\.kuroRoutes` so pages push (N5 dedupe through `JourneyPolicy`) and tools open from the
//     host's one tool slot over the current page (N7),
//   - injects `\.kuroJourney` (`JourneyContext`) per page: `isPushed` (draw Back), `pop()`, `close()`
//     (dismiss the whole journey, N3/N4),
//   - keeps edge swipe-back working on pages that hide the system bar (N2, `KuroInteractivePopEnabler`).
//
// Usage:
//   - From a presenter (automatic): `routes.openMedia(...)` / `routes.openPage(...)` outside a journey
//     opens `JourneyHost(navigator:)` in a sheet.
//   - A lane turning an existing sheet into a journey: `.sheet(isPresented: $show) {
//     JourneyHost(root: .custom(AnyJourneyPage(id: "search", title: …) { SearchPage() })) }`.

/// A journey's stack: its root page, the pushed pages and the one tool slot.
@Observable
final class JourneyNavigator {
    /// The journey's first page (✕ only, no Back).
    let root: JourneyPage
    /// The pushed pages, bottom to top.
    var path: [JourneyPage] = []
    /// The tool shown over the current page (tracking editor, add to club).
    var tool: AppRoute?

    /// The UIKit navigation controller of this journey's stack (resolved by the pop enabler); used to
    /// tell whether a legacy sheet covers the journey.
    @ObservationIgnored weak var navigationController: UINavigationController?
    /// Dismisses the journey's sheet (set by the host from its presentation's `dismiss`).
    @ObservationIgnored var dismissJourney: (() -> Void)?

    init(root: JourneyPage) {
        self.root = root
    }

    /// The page on top.
    var top: JourneyPage { JourneyPolicy.top(root: root, path: path) }

    /// Opens a route inside the journey: a page is pushed (or popped to, N5), a tool is presented over
    /// the current page (N7). A page opened from inside the host's own tool closes the tool first.
    func open(_ route: AppRoute) {
        if let page = RoutePolicy.journeyPage(for: route) {
            open(page)
        } else if let next = RoutePolicy.update(current: tool, requested: route) {
            tool = next
        }
    }

    /// Opens a page inside the journey (N5).
    func open(_ page: JourneyPage) {
        if tool != nil { tool = nil }
        let next = JourneyPolicy.push(page, root: root, path: path)
        if next != path { path = next }
    }

    /// Back (N1): one level.
    func pop() {
        guard !path.isEmpty else { return }
        path = JourneyPolicy.pop(path)
    }

    /// ✕ / collapse (N3, N4): the whole journey closes.
    func close() {
        tool = nil
        dismissJourney?()
    }

    /// Whether a sheet the host did not present (a legacy page-local sheet) covers the journey.
    var isCoveredByForeignSheet: Bool {
        guard tool == nil, let navigationController else { return false }
        var host: UIViewController = navigationController
        while let parent = host.parent { host = parent }
        return host.presentedViewController != nil
    }

    /// The routes pages of this journey read (built once).
    @ObservationIgnored
    private(set) lazy var routes = KuroRoutes { [weak self] route in
        self?.open(route)
    }

    /// The context a page reads (`\.kuroJourney`); built once per kind so the environment value a page
    /// reads never changes.
    func context(isPushed: Bool) -> JourneyContext {
        isPushed ? pushedContext : rootContext
    }

    @ObservationIgnored private lazy var rootContext = makeContext(isPushed: false)
    @ObservationIgnored private lazy var pushedContext = makeContext(isPushed: true)

    private func makeContext(isPushed: Bool) -> JourneyContext {
        JourneyContext(
            isPushed: isPushed,
            open: { [weak self] route in self?.open(route) },
            pop: { [weak self] in self?.pop() },
            close: { [weak self] in self?.close() },
            isCovered: { [weak self] in self?.isCoveredByForeignSheet ?? false },
            journeyID: ObjectIdentifier(self)
        )
    }
}

// MARK: - Journey context (environment)

/// What a journey page knows about its journey. `nil` (the environment default) outside a journey.
struct JourneyContext {
    /// The page was pushed (draw the back chevron); false on the journey's root page (✕ only).
    let isPushed: Bool
    /// Opens a route inside this journey (pages push, tools present over the current page).
    let open: (AppRoute) -> Void
    /// Back: pops exactly one level (N1).
    let pop: () -> Void
    /// ✕: dismisses the whole journey (N3/N4).
    let close: () -> Void
    /// A sheet the host did not present covers the journey (see the nesting rule).
    let isCovered: () -> Bool
    /// The journey's identity (its navigator): a sheet a page of this journey presents registers under
    /// it, so a deep link that keeps the journey closes that sheet (N10).
    var journeyID: ObjectIdentifier? = nil

    /// ✕ on a journey page: closes the whole journey (N3) — unless a foreign sheet covers the journey,
    /// in which case the tapped control belongs to that sheet and `fallback` (its `dismiss`) runs.
    func closeOrDismiss(_ fallback: () -> Void) {
        if JourneyContext.closesJourney(isCovered: isCovered()) { close() } else { fallback() }
    }

    /// The pure rule behind `closeOrDismiss` (tested in JourneyPolicyTests).
    nonisolated static func closesJourney(isCovered: Bool) -> Bool { !isCovered }
}

private struct KuroJourneyKey: EnvironmentKey {
    static let defaultValue: JourneyContext? = nil
}

extension EnvironmentValues {
    /// The journey this view is in (nil outside a journey).
    var kuroJourney: JourneyContext? {
        get { self[KuroJourneyKey.self] }
        set { self[KuroJourneyKey.self] = newValue }
    }
}

extension View {
    /// Content presented in a sheet over a journey page that should not push into the journey behind it
    /// (its own `.routePresenter()` then presents as outside a journey). Tool sheets get it from the host.
    func kuroLeavesJourney() -> some View {
        environment(\.kuroJourney, nil)
    }
}

// MARK: - Pull to refresh (H4)

extension JourneyContext {
    /// H4: pull-down at the top of a journey's FIRST page dismisses the sheet, so that page never
    /// installs pull-to-refresh (it would take the gesture). Pushed pages (where pull-down never pops)
    /// and pages outside a journey (the pager) keep it. Pure; tested in JourneyPolicyTests.
    nonisolated static func allowsPullToRefresh(inJourney: Bool, isPushed: Bool) -> Bool {
        !inJourney || isPushed
    }
}

private struct KuroJourneyRefreshable: ViewModifier {
    /// MainActor-typed: SwiftUI's own `.refreshable` inherits the caller's actor (`@_inheritActorContext`);
    /// a plain `@Sendable` parameter would not, and every view-body closure would run off the main actor.
    let action: @MainActor @Sendable () async -> Void
    @Environment(\.kuroJourney) private var journey

    func body(content: Content) -> some View {
        if JourneyContext.allowsPullToRefresh(inJourney: journey != nil, isPushed: journey?.isPushed ?? false) {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

extension View {
    /// `.refreshable` for a view that can be a journey's first page: refresh everywhere except there,
    /// where pull-down must dismiss the journey (H4).
    func kuroJourneyRefreshable(action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(KuroJourneyRefreshable(action: action))
    }
}

/// A `NavigationStack` only outside a journey: a page that used to wrap itself in a stack (entity
/// pages, see-all sheets) uses this, so pushed inside a journey it never nests a second stack.
struct KuroJourneyAwareStack<Content: View>: View {
    @Environment(\.kuroJourney) private var journey
    @ViewBuilder let content: () -> Content

    var body: some View {
        if journey != nil {
            content()
        } else {
            NavigationStack { content() }
        }
    }
}

// MARK: - Host

/// One journey sheet's navigation stack.
struct JourneyHost: View {
    @State private var navigator: JourneyNavigator
    @Environment(\.dismiss) private var dismiss
    /// Optional: hosts built in tests without the telemetry owner still work (`journey_close` is skipped).
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?
    /// When the journey's root appeared, and the deepest stack it reached (`journey_close`, spec
    /// 2026-11-04 §5.12: open-and-bounce is a `discover_open` followed by a close within 5 s).
    @State private var openedAt: Date?
    @State private var deepest = 0

    /// A journey a presenter (or the root coordinator) already holds.
    init(navigator: JourneyNavigator) {
        _navigator = State(initialValue: navigator)
    }

    /// A new journey with `root` as its first page (a lane converting an existing sheet).
    init(root: JourneyPage) {
        _navigator = State(initialValue: JourneyNavigator(root: root))
    }

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.path) {
            JourneyPageView(page: navigator.root)
                .environment(\.kuroJourney, navigator.context(isPushed: false))
                .background(KuroInteractivePopEnabler { navigator.navigationController = $0 })
                .navigationDestination(for: JourneyPage.self) { page in
                    JourneyPageView(page: page)
                        .environment(\.kuroJourney, navigator.context(isPushed: true))
                }
        }
        .environment(\.kuroRoutes, navigator.routes)
        // N8: every journey sheet shows its grabber (pages that set it themselves also say `.visible`).
        .presentationDragIndicator(.visible)
        .sheet(item: $navigator.tool) { route in
            ToolDestinationView(route: route)
                .kuroLeavesJourney()
        }
        .onAppear {
            let dismiss = dismiss
            navigator.dismissJourney = { dismiss() }
            if openedAt == nil { openedAt = Date() }
        }
        .onChange(of: navigator.path.count) { _, count in deepest = max(deepest, count) }
        .onDisappear {
            guard let openedAt else { return }
            self.openedAt = nil
            telemetry?.trackInteractionEvent(
                "journey_close", surface: "journey", result: "closed",
                extra: JourneyCloseEvent.extra(root: navigator.root, seconds: Date().timeIntervalSince(openedAt),
                                               depth: deepest))
        }
    }
}

/// The `journey_close` payload (pure; spec 2026-11-04 §5.12): the root's kind, its catalogue id when the
/// root is a title (never a title string), the rounded seconds open and the deepest pushed depth.
enum JourneyCloseEvent {
    static func rootKind(_ root: JourneyPage) -> String {
        switch root {
        case .media(let route): return route.key.kind == .manga ? "manga" : "anime"
        case .club: return "club"
        default: return "page"
        }
    }

    static func extra(root: JourneyPage, seconds: TimeInterval, depth: Int) -> [String: Any] {
        var extra: [String: Any] = [
            "root_kind": rootKind(root),
            "seconds": Int(max(0, seconds).rounded()),
            "depth": max(0, depth)
        ]
        if case .media(let route) = root { extra["media_id"] = route.key.id }
        return extra
    }
}

/// Builds one journey page.
struct JourneyPageView: View {
    let page: JourneyPage

    var body: some View {
        switch JourneyPolicy.destination(for: page) {
        case .route(let destination):
            switch destination {
            case .mediaLoader(let key):
                MediaDetailSheet(kind: key.kind, id: key.id)
            case .animeDetail(let anime):
                AnimeDetailView(anime: anime)
            case .mangaDetail(let manga):
                MangaDetailView(manga: manga)
            case .club(let clubId):
                ClubDetailView(clubId: clubId)
                    .id(clubId)
            case .browse:
                JourneyBrowsePage()
            case .trackingEditor, .addToClub, .journeyPage:
                // Tools never become pages; `.journeyPage` is resolved by `JourneyPolicy` before this.
                EmptyView()
            }
        case .character(let character):
            CharacterDetailSheet(character: character)
        case .staff(let staff):
            StaffDetailSheet(staff: staff)
        case .studio(let studio):
            StudioDetailSheet(studio: studio)
        case .author(let author):
            AuthorDetailSheet(author: author)
        case .content(let content):
            content.makeBody()
        }
    }
}

/// The catalogue as a journey page: `BrowseView` with the journey's close control (its cards push).
private struct JourneyBrowsePage: View {
    @Environment(\.kuroJourney) private var journey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrowseView()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let journey { journey.closeOrDismiss { dismiss() } } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.kuroBody(weight: .regular))
                            .foregroundStyle(Color.kuroInk)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(KuroLocale.text("Close", "Schließen"))
                }
            }
    }
}
