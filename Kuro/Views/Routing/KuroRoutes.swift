import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Typed navigation outputs (E5 route migration; journeys since 2026-11-02)
//
// A feature view does not construct a sibling feature's detail or sheet. It emits a typed route to
// the nearest presenter through the environment:
//
//     @Environment(\.kuroRoutes) private var routes
//     routes.openMedia(MediaRoute(media.libraryKey))      // or openClub / openCharacter / openPage(...)
//     routes.presentTrackingEditor(TrackingEditorRequest(media: media))   // a tool
//
// Routes are of two kinds (navigation contract, docs/superpowers/specs/2026-11-02-navigation-contract-
// design.md): PAGES (a title, a club, a person, a studio, the catalogue, a lane page: `JourneyPage`,
// KuroJourney.swift) and TOOLS (tracking editor, add to club). The pure mapping is `RoutePolicy`
// (unit-tested in RoutingTests) and `JourneyPolicy` (JourneyPolicyTests).
//
// NESTING RULE (journeys, 2026-11-02). There is ONE way to show a page: inside a journey.
//
//   - Outside a journey (a pager page, the app root, a page-level sheet that is not a journey yet), the
//     nearest `.routePresenter()` opens a page as a NEW journey sheet (`JourneyHost` with that page as
//     its root) and a tool as a tool sheet. The app root's presenter is `.kuroRootNavigation(_:)`
//     (KuroRootView), which also owns deep-link collapse (`KuroNavigationCoordinator`, N10).
//   - Inside a journey, `\.kuroRoutes` PUSHES pages onto the journey's stack (N5 dedupe: an open page
//     is popped to, the top is never pushed again) and presents tools from the host's single tool slot
//     over the current page (N7). `.routePresenter()` inside a journey is a FORWARDER: existing call
//     sites keep compiling and simply hand their routes to the journey. Only while something covers the
//     journey (a legacy page-local `.sheet` that has not been migrated yet) does it present its own
//     journey sheet on top, exactly as before, so a tap is never swallowed under a sheet.
//   - Never build a detail/club/person view inside `.sheet(...)`; never wrap a page in its own
//     `NavigationStack` (use `KuroJourneyAwareStack`, which adds a stack only outside a journey).
//   - A page-local sheet that shows routed content of its own and should NOT push into the journey
//     behind it applies `.kuroLeavesJourney()` to its content (the host's tool sheets already do).
//   - Pages draw their back chevron and ✕ with `.kuroJourneyChrome(title:collapseProgress:material:)`
//     (KuroJourneyChrome.swift), which also keeps edge swipe-back working (N2).
//
// Presenters installed today: the app root (`.kuroRootNavigation`), and the `.routePresenter()` sites
// listed by `grep -rn "routePresenter()" Kuro` (Search, Concierge, Profile import, see-all sheets, club
// detail, the detail pages, entity pages, Home's season overview). Inside a journey they forward.

/// A catalog title to open in its detail sheet.
struct MediaRoute {
    /// A detail model the caller already loaded (Concierge recommendations): presented directly, as
    /// before, instead of being loaded again by key.
    enum Preloaded {
        case anime(Anime)
        case manga(Manga)
    }

    let key: MediaKey
    let preloaded: Preloaded?

    init(_ key: MediaKey) {
        self.key = key
        self.preloaded = nil
    }

    init(kind: MediaKind, id: Int) {
        self.init(MediaKey(kind: kind, id: id))
    }

    init(anime: Anime) {
        self.key = MediaKey(kind: .anime, id: anime.id)
        self.preloaded = .anime(anime)
    }

    init(manga: Manga) {
        self.key = MediaKey(kind: .manga, id: manga.id)
        self.preloaded = .manga(manga)
    }
}

/// The tracking editor (`AddToListSheet`) for a title the caller is showing.
struct TrackingEditorRequest {
    /// What the editor shows (title, poster, year, episode/chapter total) and edits (its key).
    let media: any MediaDisplayable
    /// The status a title that is NOT on the list yet starts at in the editor (Discover "Seen it" →
    /// "Add as Completed ›", spec 2026-11-04 D13). Nothing is saved until the user taps Save; a title
    /// already on the list ignores it. A `var`, so the memberwise init keeps `(media:)` working.
    var initialStatus: ListStatus? = nil
}

/// One presentation a presenter can show.
enum AppRoute: Identifiable {
    case media(MediaRoute)
    case club(id: String)
    case trackingEditor(TrackingEditorRequest)
    case addToClub(MediaKey)
    /// The full catalogue with filters (`BrowseView`) as a sheet. The series-home pager has no
    /// Browse page, so Discover and Search open it through this route (spec D2).
    case browse
    /// Any journey page (characters, staff, studios, authors, lane pages): `KuroRoutes.openPage`.
    case page(JourneyPage)

    /// Kind-prefixed identity: `anime 7` and `manga 7` are different routes, and a title's detail,
    /// tracking editor and add-to-club sheet are three different routes.
    var id: String {
        switch self {
        case .media(let route):
            return "media:\(route.key.kind.rawValue):\(route.key.id)"
        case .club(let id):
            return "club:\(id)"
        case .trackingEditor(let request):
            return "tracking:\(request.media.kind.rawValue):\(request.media.id)"
        case .addToClub(let key):
            return "addToClub:\(key.kind.rawValue):\(key.id)"
        case .browse:
            return "browse"
        case .page(let page):
            return page.id
        }
    }
}

/// What a presenter builds for a route.
enum RouteDestination {
    /// `MediaDetailSheet(kind:id:)`: loads the title, then shows its detail view.
    case mediaLoader(MediaKey)
    /// `AnimeDetailView(anime:)` with the caller's model.
    case animeDetail(Anime)
    /// `MangaDetailView(manga:)` with the caller's model.
    case mangaDetail(Manga)
    /// `NavigationStack { ClubDetailView(clubId:).id(clubId) }`.
    case club(id: String)
    /// `AddToListSheet(media:)`.
    case trackingEditor(any MediaDisplayable)
    /// `AddToClubRailSheet(mediaId:mediaType:)`; the sheet takes the upper-case type ("ANIME"/"MANGA").
    case addToClub(mediaId: Int, mediaType: String)
    /// `BrowseView` as a journey page (`JourneyBrowsePage`, JourneyHost.swift) with the journey's close.
    case browse
    /// A journey page that is not a title, club or the catalogue (built by `JourneyHost`).
    case journeyPage(JourneyPage)
}

/// The routing rules (pure).
enum RoutePolicy {
    /// The route a presenter stores when `requested` arrives while `current` is shown, or nil when the
    /// request changes nothing.
    /// - The same route (same `id`) changes nothing: a double tap neither stacks nor re-presents it.
    /// - Otherwise the request is shown: presented when nothing is, or in place of a different route
    ///   (`.sheet(item:)` dismisses the old one), as a second `kuro://` link replaced the open detail.
    static func update(current: AppRoute?, requested: AppRoute) -> AppRoute? {
        current?.id == requested.id ? nil : requested
    }

    /// What the presenter constructs for `route`: exactly what the call sites constructed before.
    static func destination(for route: AppRoute) -> RouteDestination {
        switch route {
        case .media(let media):
            switch media.preloaded {
            case .anime(let anime):
                return .animeDetail(anime)
            case .manga(let manga):
                return .mangaDetail(manga)
            case nil:
                return .mediaLoader(media.key)
            }
        case .club(let id):
            return .club(id: id)
        case .trackingEditor(let request):
            return .trackingEditor(request.media)
        case .addToClub(let key):
            return .addToClub(mediaId: key.id, mediaType: key.kind.rawValue.uppercased())
        case .browse:
            return .browse
        case .page(let page):
            switch page {
            case .media(let media): return destination(for: .media(media))
            case .club(let id): return .club(id: id)
            case .browse: return .browse
            default: return .journeyPage(page)
            }
        }
    }

    /// The journey page a route opens, or nil for a tool (tracking editor, add to club: presented over
    /// the current page, never pushed).
    static func journeyPage(for route: AppRoute) -> JourneyPage? {
        switch route {
        case .media(let media): return .media(media)
        case .club(let id): return .club(id: id)
        case .browse: return .browse
        case .page(let page): return page
        case .trackingEditor, .addToClub: return nil
        }
    }
}

// MARK: - Environment

/// The routes of the nearest presenter (`.routePresenter()`, `.kuroRootNavigation(_:)` or a journey).
struct KuroRoutes {
    var openMedia: (MediaRoute) -> Void
    var openClub: (String) -> Void
    var presentTrackingEditor: (TrackingEditorRequest) -> Void
    var presentAddToClub: (MediaKey) -> Void
    /// Opens the full catalogue (`BrowseView`) (spec D2: Discover and Search entries).
    var openBrowse: () -> Void
    /// Opens any journey page (pushed inside a journey; a new journey outside one).
    var openPage: (JourneyPage) -> Void

    /// One entry point the routes share.
    init(_ show: @escaping (AppRoute) -> Void) {
        openMedia = { show(.media($0)) }
        openClub = { show(.club(id: $0)) }
        presentTrackingEditor = { show(.trackingEditor($0)) }
        presentAddToClub = { show(.addToClub($0)) }
        openBrowse = { show(.browse) }
        openPage = { show(.page($0)) }
    }

    /// A character's page (appearances).
    func openCharacter(_ character: Character) { openPage(.character(character)) }
    /// A staff member's page (filmography).
    func openStaff(_ staff: Staff) { openPage(.staff(staff)) }
    /// A studio's page (productions).
    func openStudio(_ studio: Studio) { openPage(.studio(studio)) }
    /// An author's page (works).
    func openAuthor(_ author: Author) { openPage(.author(author)) }

    /// No presenter above the caller (only previews): nothing is presented.
    static let unhandled = KuroRoutes { route in
        #if DEBUG
        print("[KuroRoutes] no presenter installed; dropped \(route.id)")
        #endif
    }
}

/// Whether the root pager is mid-swipe (`swipe_tap_guard_v1`), read at the moment a route fires: a
/// horizontal swipe that starts on a card turns the page and never opens the card (navigation
/// contract N9). The pager writes it synchronously from its drag gesture.
final class KuroPagerTapGate {
    var isSuppressed = false
}

extension KuroRoutes {
    /// These routes with every open and tool dropped while `gate` is suppressed.
    func gated(by gate: KuroPagerTapGate) -> KuroRoutes {
        let base = self
        var routes = self
        routes.openMedia = { if !gate.isSuppressed { base.openMedia($0) } }
        routes.openClub = { if !gate.isSuppressed { base.openClub($0) } }
        routes.presentTrackingEditor = { if !gate.isSuppressed { base.presentTrackingEditor($0) } }
        routes.presentAddToClub = { if !gate.isSuppressed { base.presentAddToClub($0) } }
        routes.openBrowse = { if !gate.isSuppressed { base.openBrowse() } }
        routes.openPage = { if !gate.isSuppressed { base.openPage($0) } }
        return routes
    }
}

/// Wraps the inherited routes once (the gate is a stable reference, so the wrapped value is rebuilt
/// only when the routes above change).
struct KuroPagerTapGateModifier: ViewModifier {
    let gate: KuroPagerTapGate
    @Environment(\.kuroRoutes) private var routes

    func body(content: Content) -> some View {
        content.environment(\.kuroRoutes, routes.gated(by: gate))
    }
}

private struct KuroRoutesKey: EnvironmentKey {
    static let defaultValue: KuroRoutes = .unhandled
}

extension EnvironmentValues {
    /// Typed navigation outputs, supplied by the nearest `.routePresenter()`.
    var kuroRoutes: KuroRoutes {
        get { self[KuroRoutesKey.self] }
        set { self[KuroRoutesKey.self] = newValue }
    }
}

// MARK: - Presenter

/// What a presenter shows: a journey (a page as the root of a new journey sheet) or a tool.
enum SlotPresentation: Identifiable {
    case journey(JourneyNavigator)
    case tool(AppRoute)

    var id: String {
        switch self {
        case .journey(let navigator): return "journey:\(navigator.root.id)"
        case .tool(let route): return "tool:\(route.id)"
        }
    }
}

/// One presentation context's slot. The routes value is built once per slot, so the environment value
/// a presenter injects never changes and the leaves reading it are not invalidated when a route is
/// presented or dismissed.
@Observable
final class PresentationSlot {
    var presented: SlotPresentation?
    /// The journey this presenter sits in (nil outside one): its routes forward there while the
    /// journey is not covered by a sheet (nesting rule).
    @ObservationIgnored var journey: JourneyContext?

    @ObservationIgnored
    private(set) lazy var routes = KuroRoutes { [weak self] requested in
        guard let self else { return }
        if let journey = self.journey, !journey.isCovered() {
            journey.open(requested)
        } else {
            self.show(requested)
        }
    }

    /// Presents a route here: a page as a new journey, a tool as a tool sheet. The same page or tool
    /// again (double tap) changes nothing; a different one replaces what is shown.
    func show(_ requested: AppRoute) {
        if let page = RoutePolicy.journeyPage(for: requested) {
            if case .journey(let open) = presented, open.top == page { return }
            presented = .journey(JourneyNavigator(root: page))
        } else {
            if case .tool(let open) = presented, RoutePolicy.update(current: open, requested: requested) == nil { return }
            presented = .tool(requested)
        }
    }
}

private struct RoutePresenter: ViewModifier {
    @State private var slot = PresentationSlot()
    @Environment(\.kuroJourney) private var journey

    func body(content: Content) -> some View {
        @Bindable var slot = slot
        let _ = { slot.journey = journey }()
        content
            .environment(\.kuroRoutes, slot.routes)
            .sheet(item: $slot.presented) { presentation in
                SlotPresentationView(presentation: presentation)
            }
    }
}

/// What a slot's sheet shows.
struct SlotPresentationView: View {
    let presentation: SlotPresentation

    var body: some View {
        switch presentation {
        case .journey(let navigator):
            JourneyHost(navigator: navigator)
        case .tool(let route):
            ToolDestinationView(route: route)
                .kuroLeavesJourney()
        }
    }
}

/// A tool's sheet content (N7).
struct ToolDestinationView: View {
    let route: AppRoute

    var body: some View {
        switch RoutePolicy.destination(for: route) {
        case .trackingEditor(let media):
            AddToListSheet(media: media, initialStatus: Self.initialStatus(of: route))
        case .addToClub(let mediaId, let mediaType):
            AddToClubRailSheet(mediaId: mediaId, mediaType: mediaType)
        case .mediaLoader, .animeDetail, .mangaDetail, .club, .browse, .journeyPage:
            // Pages never reach a tool slot (`RoutePolicy.journeyPage(for:)` sends them to a journey).
            EmptyView()
        }
    }

    /// The editor's preset status carried by a tracking-editor route (nil for every other route).
    static func initialStatus(of route: AppRoute) -> ListStatus? {
        if case .trackingEditor(let request) = route { return request.initialStatus }
        return nil
    }
}

extension View {
    /// Installs the route presenter for this presentation context (see the nesting rule above). Inside
    /// a journey it forwards to the journey.
    func routePresenter() -> some View {
        modifier(RoutePresenter())
    }
}
