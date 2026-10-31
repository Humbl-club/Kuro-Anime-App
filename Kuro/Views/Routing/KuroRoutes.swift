import KuroCore
import SwiftUI

// MARK: - Typed navigation outputs (E5 route migration)
//
// A feature view does not construct a sibling feature's detail or sheet. It emits a typed route to
// the nearest presenter through the environment:
//
//     @Environment(\.kuroRoutes) private var routes
//     routes.openMedia(MediaRoute(media.libraryKey))
//
// `.routePresenter()` owns the presentation: one route slot and one `.sheet(item:)` per presentation
// context, which builds `MediaDetailSheet` / `AnimeDetailView` / `MangaDetailView` (Catalog),
// `ClubDetailView` (Clubs), `AddToListSheet` (tracking editor) and `AddToClubRailSheet` (Clubs).
// The mapping and the identity rule are pure (`RoutePolicy`, unit-tested in RoutingTests).
//
// NESTING RULE. SwiftUI presents a sheet only from the topmost presentation context. Before the
// migration every leaf presented from its own position, i.e. on top of whatever context it sat in.
// To keep that, EVERY presentation context that contains a routed leaf installs its own presenter;
// the environment then resolves a leaf to the presenter of its own context. A leaf inside a sheet
// WITHOUT its own presenter would resolve to the presenter of the context below, which is already
// presenting that sheet, and nothing would appear (no diagnostic can see this: the default below
// only catches a missing root presenter). Presenters installed today:
//
//   app root ............ KuroRootView (ContentView.swift), around KuroMainView (deep links read it)
//   search sheet ........ EditorialSearchView
//   concierge sheets .... the two sheet sites (ContentView, ProfileView), around ConciergeView
//                         (the pager page uses the app root presenter)
//   "see all" sheets .... FullSectionView, FullMangaSectionView
//   club detail ......... ClubDetailView (deep link and ClubsView's own sheet)
//   media detail ........ AnimeDetailView, MangaDetailView (loader, Concierge and in-detail paths)
//   entity sheets ....... CharacterDetailSheet, StaffDetailSheet, StudioDetailSheet, AuthorDetailSheet
//
// Adding a sheet whose content shows a routed leaf (any card below, a search row, a rail item, the
// detail action bar) means adding `.routePresenter()` at that sheet's root.

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
}

/// One presentation a presenter can show.
enum AppRoute: Identifiable {
    case media(MediaRoute)
    case club(id: String)
    case trackingEditor(TrackingEditorRequest)
    case addToClub(MediaKey)

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
        }
    }
}

// MARK: - Environment

/// The routes of the nearest presenter (`.routePresenter()`).
struct KuroRoutes {
    var openMedia: (MediaRoute) -> Void
    var openClub: (String) -> Void
    var presentTrackingEditor: (TrackingEditorRequest) -> Void
    var presentAddToClub: (MediaKey) -> Void

    /// One entry point the four routes share.
    fileprivate init(_ show: @escaping (AppRoute) -> Void) {
        openMedia = { show(.media($0)) }
        openClub = { show(.club(id: $0)) }
        presentTrackingEditor = { show(.trackingEditor($0)) }
        presentAddToClub = { show(.addToClub($0)) }
    }

    /// No presenter above the caller (only previews): nothing is presented.
    static let unhandled = KuroRoutes { route in
        #if DEBUG
        print("[KuroRoutes] no presenter installed; dropped \(route.id)")
        #endif
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

/// One presentation context's route slot. The routes value is built once per slot, so the
/// environment value a presenter injects never changes and the leaves reading it are not
/// invalidated when a route is presented or dismissed.
@Observable
private final class RouteSlot {
    var route: AppRoute?

    @ObservationIgnored
    private(set) lazy var routes = KuroRoutes { [weak self] requested in
        guard let self else { return }
        if let next = RoutePolicy.update(current: self.route, requested: requested) {
            self.route = next
        }
    }
}

private struct RoutePresenter: ViewModifier {
    @State private var slot = RouteSlot()

    func body(content: Content) -> some View {
        @Bindable var slot = slot
        content
            .environment(\.kuroRoutes, slot.routes)
            .sheet(item: $slot.route) { route in
                RouteDestinationView(route: route)
            }
    }
}

private struct RouteDestinationView: View {
    let route: AppRoute

    var body: some View {
        switch RoutePolicy.destination(for: route) {
        case .mediaLoader(let key):
            MediaDetailSheet(kind: key.kind, id: key.id)
        case .animeDetail(let anime):
            AnimeDetailView(anime: anime)
        case .mangaDetail(let manga):
            MangaDetailView(manga: manga)
        case .club(let clubId):
            NavigationStack {
                ClubDetailView(clubId: clubId)
                    .id(clubId)
            }
        case .trackingEditor(let media):
            AddToListSheet(media: media)
        case .addToClub(let mediaId, let mediaType):
            AddToClubRailSheet(mediaId: mediaId, mediaType: mediaType)
        }
    }
}

extension View {
    /// Installs the route presenter for this presentation context (see the nesting rule above).
    func routePresenter() -> some View {
        modifier(RoutePresenter())
    }
}
