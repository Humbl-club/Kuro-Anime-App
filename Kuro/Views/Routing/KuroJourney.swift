import KuroCore
import SwiftUI

// MARK: - Journeys (navigation contract, docs/superpowers/specs/2026-11-02-navigation-contract-design.md)
//
// A journey is ONE sheet hosting a navigation stack (`JourneyHost`, JourneyHost.swift). Its pages are
// `JourneyPage` values; every further tap inside the journey PUSHES a page (never a second content
// sheet). The rules are pure and unit-tested (`JourneyPolicy`, `NavigationCollapsePolicy`,
// KuroTests/JourneyPolicyTests.swift):
//
//   N5  opening a page already in the stack pops back to it; the page on top is never pushed again
//   N3  ✕ / swipe-down dismisses the whole journey (`JourneyContext.close`)
//   N7  a tool (tracking editor, add to club) opens over the current page and never changes the path
//   N10 a deep link collapses every cover, sheet, tool and journey first, then opens its target
//
// Identity: a page's `id` is kind-prefixed (`media:anime:7`, `character:12`, `seeAll:<id>`, …) and is
// the ONLY thing equality and hashing look at. The models a page carries (a preloaded `Anime`, a
// `Character`, a lane's builder) are payload: a preloaded and a key-only route to the same title are
// the same page (N5 dedupe works across both).

/// A page a journey can show. Add a page kind by giving it a case here (with an id prefix and a
/// destination in `JourneyPolicy.destination(for:)`), or, from a lane's own file, by wrapping a
/// `JourneyPageContent` in `AnyJourneyPage` and using `.seeAll`, `.seasonOverview`, `.profileList` or
/// `.custom`.
enum JourneyPage: Hashable, Identifiable {
    /// A title's detail (key-only: the loader; preloaded: the caller's model, as `MediaRoute`).
    case media(MediaRoute)
    /// A club's detail.
    case club(id: String)
    /// A character (appearances).
    case character(Character)
    /// A staff member (filmography).
    case staff(Staff)
    /// A studio (productions).
    case studio(Studio)
    /// An author (works).
    case author(Author)
    /// The full catalogue with filters (`BrowseView`).
    case browse
    /// A "See all" section (Discover rails, Search, …): the lane supplies the page.
    case seeAll(AnyJourneyPage)
    /// Home's season overview: the lane supplies the page.
    case seasonOverview(AnyJourneyPage)
    /// Profile → Your lists → a list (N11): the lane supplies the page.
    case profileList(AnyJourneyPage)
    /// Any other page a lane adds in its own file (Search root, Profile root, …).
    case custom(AnyJourneyPage)

    /// Kind-prefixed identity: the one thing equality, hashing and N5 dedupe use.
    var id: String {
        switch self {
        case .media(let route): return "media:\(route.key.kind.rawValue):\(route.key.id)"
        case .club(let id): return "club:\(id)"
        case .character(let character): return "character:\(character.id)"
        case .staff(let staff): return "staff:\(staff.id)"
        case .studio(let studio): return "studio:\(studio.id)"
        case .author(let author): return "author:\(author.id)"
        case .browse: return "browse"
        case .seeAll(let page): return "seeAll:\(page.id)"
        case .seasonOverview(let page): return "season:\(page.id)"
        case .profileList(let page): return "profileList:\(page.id)"
        case .custom(let page): return "custom:\(page.id)"
        }
    }

    /// The page's one-line title for the compact bar and VoiceOver; nil when the page names itself
    /// once loaded (titles, clubs).
    var title: String? {
        switch self {
        case .media, .club: return nil
        case .character(let character): return character.nameFull
        case .staff(let staff): return staff.nameFull
        case .studio(let studio): return studio.name
        case .author(let author): return author.nameFull
        case .browse: return KuroLocale.text("Browse", "Katalog")
        case .seeAll(let page), .seasonOverview(let page), .profileList(let page), .custom(let page):
            return page.title
        }
    }

    static func == (lhs: JourneyPage, rhs: JourneyPage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Extension point

/// A page a lane defines in its own file. `journeyID` is its identity inside the case it is wrapped
/// in (e.g. `"discover:trending"` for `.seeAll`); `makeBody()` builds the page (no NavigationStack:
/// the journey host owns the stack).
protocol JourneyPageContent {
    var journeyID: String { get }
    var journeyTitle: String? { get }
    @MainActor func makeBody() -> AnyView
}

extension JourneyPageContent {
    var journeyTitle: String? { nil }
}

/// A type-erased lane page. Equality is its `id` only (the builder is payload).
struct AnyJourneyPage: Hashable {
    let id: String
    let title: String?
    private let build: @MainActor () -> AnyView

    init<Content: JourneyPageContent>(_ content: Content) {
        id = content.journeyID
        title = content.journeyTitle
        build = { content.makeBody() }
    }

    init<Body: View>(id: String, title: String? = nil, @ViewBuilder content: @escaping @MainActor () -> Body) {
        self.id = id
        self.title = title
        build = { AnyView(content()) }
    }

    @MainActor func makeBody() -> AnyView { build() }

    static func == (lhs: AnyJourneyPage, rhs: AnyJourneyPage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Destinations

/// What the journey host builds for a page.
enum JourneyDestination {
    /// A title or club (or the catalogue): the same constructions `RoutePolicy.destination` names.
    case route(RouteDestination)
    case character(Character)
    case staff(Staff)
    case studio(Studio)
    case author(Author)
    /// A lane page.
    case content(AnyJourneyPage)
}

// MARK: - Journey policy (pure)

/// What a push request does to a journey's stack.
enum JourneyStep: Equatable {
    /// The page is already on top (double tap, or the root while nothing is pushed): nothing happens.
    case none
    /// The page is pushed.
    case push(JourneyPage)
    /// The page is already in the stack: everything above it is popped (`keep` = pushed pages kept).
    case popTo(keep: Int)
    /// The page is the journey's root: every pushed page is popped.
    case popToRoot
}

/// The journey stack rules (N5, N7). `root` is the journey's first page; `path` the pushed pages.
enum JourneyPolicy {
    /// The page on top of the journey.
    static func top(root: JourneyPage, path: [JourneyPage]) -> JourneyPage {
        path.last ?? root
    }

    /// What opening `page` does (N5: an existing page is popped to, the top is never pushed again).
    static func step(opening page: JourneyPage, root: JourneyPage, path: [JourneyPage]) -> JourneyStep {
        if top(root: root, path: path) == page { return .none }
        if page == root { return .popToRoot }
        if let index = path.firstIndex(of: page) { return .popTo(keep: index + 1) }
        return .push(page)
    }

    /// The path after opening `page`.
    static func push(_ page: JourneyPage, root: JourneyPage, path: [JourneyPage]) -> [JourneyPage] {
        apply(step(opening: page, root: root, path: path), to: path)
    }

    /// The path after a step.
    static func apply(_ step: JourneyStep, to path: [JourneyPage]) -> [JourneyPage] {
        switch step {
        case .none: return path
        case .push(let page): return path + [page]
        case .popTo(let keep): return Array(path.prefix(keep))
        case .popToRoot: return []
        }
    }

    /// The path after Back (N1): exactly one level; the root has no Back.
    static func pop(_ path: [JourneyPage]) -> [JourneyPage] {
        Array(path.dropLast())
    }

    /// Whether a route opens a journey page (pushed inside a journey) or a tool (N7: presented over the
    /// current page, never changing the path).
    static func page(for route: AppRoute) -> JourneyPage? {
        RoutePolicy.journeyPage(for: route)
    }

    /// What the host builds for a page.
    static func destination(for page: JourneyPage) -> JourneyDestination {
        switch page {
        case .media(let route): return .route(RoutePolicy.destination(for: .media(route)))
        case .club(let id): return .route(.club(id: id))
        case .browse: return .route(.browse)
        case .character(let character): return .character(character)
        case .staff(let staff): return .staff(staff)
        case .studio(let studio): return .studio(studio)
        case .author(let author): return .author(author)
        case .seeAll(let content), .seasonOverview(let content), .profileList(let content), .custom(let content):
            return .content(content)
        }
    }
}

// MARK: - Collapse policy (N10, pure)

/// What a deep link (or any "collapse then open") does, in order.
enum NavigationCollapsePolicy {
    /// The key of the root journey in `Snapshot.journeySheets` (header journeys use their layer id).
    static let rootJourney = "root"

    /// The presentation state above the pager.
    struct Snapshot: Equatable {
        /// A full-screen cover that must finish first (onboarding).
        var coverOpen = false
        /// Page-level sheets that are open (Profile, Search, Concierge, a pager page's own sheets such as
        /// Clubs → Create or Collection → Import), by layer id.
        var openSheets: [String] = []
        /// Open page-level sheets that host a journey (Profile, Search, Concierge): layer id → its top page.
        var sheetJourneyTops: [String: JourneyPage] = [:]
        /// Open page-level sheets whose journey has a tool open (by layer id).
        var sheetJourneyTools: Set<String> = []
        /// Sheets a journey page presented itself (verdict, providers, club settings, …), by journey key
        /// (`rootJourney` or the header sheet's layer id).
        var journeySheets: [String: [String]] = [:]
        /// A tool sheet presented from a page (not inside a journey).
        var rootToolOpen = false
        /// The root journey's top page, when a root journey is open.
        var journeyTop: JourneyPage?
        /// A tool is open inside the root journey.
        var journeyToolOpen = false
        /// Something no layer accounts for is presented over the pager (an unregistered sheet or
        /// dialog): it is dismissed too, then the target opens.
        var foreignSheetOpen = false
        /// An earlier collapse's dismissal is still running (its delayed open was replaced by this link).
        var dismissalInFlight = false
    }

    /// What the link asks for.
    enum Target: Equatable {
        /// Open this page as a new journey on the root.
        case journey(JourneyPage)
        /// Collapse everything; the caller then switches the pager page itself.
        case page
    }

    enum Step: Equatable {
        /// The cover finishes first; plan again when it has closed.
        case waitForCover
        /// The tool inside the root journey closes.
        case closeJourneyTool
        /// The tool inside this header journey (layer id) closes.
        case closeSheetJourneyTool(String)
        /// These sheets, presented by the kept journey's pages, close.
        case closeJourneySheets([String])
        /// The root journey (or the header journey) already shows the target on top: it stays.
        case keepJourney
        /// An unregistered presentation over the pager closes.
        case closeForeignSheet
        /// These page-level sheets close.
        case closeSheets([String])
        /// The tool presented from a page closes.
        case closeRootTool
        /// The root journey closes.
        case closeJourney
        /// An earlier dismissal is still running: wait for it before presenting.
        case awaitDismissalInFlight
        /// The target opens as a new journey on the root.
        case openJourney(JourneyPage)
        /// The caller performs its page action (switch the pager).
        case performPageAction
    }

    static func plan(_ snapshot: Snapshot, target: Target) -> [Step] {
        if snapshot.coverOpen { return [.waitForCover] }
        if case .journey(let page) = target, !snapshot.rootToolOpen, !snapshot.foreignSheetOpen {
            // N10: a link to what is already on top of the open journey keeps that journey; only what
            // covers its top page (its tool, sheets its pages presented) closes.
            if snapshot.journeyTop == page, snapshot.openSheets.isEmpty {
                return keep(rootJourney, toolOpen: snapshot.journeyToolOpen, snapshot: snapshot)
            }
            if snapshot.journeyTop == nil, snapshot.openSheets.count == 1, let id = snapshot.openSheets.first,
               snapshot.sheetJourneyTops[id] == page {
                return keep(id, toolOpen: snapshot.sheetJourneyTools.contains(id), snapshot: snapshot)
            }
        }
        var steps: [Step] = []
        if snapshot.foreignSheetOpen { steps.append(.closeForeignSheet) }
        if !snapshot.openSheets.isEmpty { steps.append(.closeSheets(snapshot.openSheets)) }
        if snapshot.rootToolOpen { steps.append(.closeRootTool) }
        if snapshot.journeyTop != nil { steps.append(.closeJourney) }
        if snapshot.dismissalInFlight && steps.isEmpty { steps.append(.awaitDismissalInFlight) }
        switch target {
        case .journey(let page): steps.append(.openJourney(page))
        case .page: steps.append(.performPageAction)
        }
        return steps
    }

    private static func keep(_ journey: String, toolOpen: Bool, snapshot: Snapshot) -> [Step] {
        var steps: [Step] = []
        if toolOpen { steps.append(journey == rootJourney ? .closeJourneyTool : .closeSheetJourneyTool(journey)) }
        if let sheets = snapshot.journeySheets[journey], !sheets.isEmpty { steps.append(.closeJourneySheets(sheets)) }
        return steps + [.keepJourney]
    }

    /// Whether the plan dismisses something before it presents (the presentation then waits for the
    /// dismissal: presenting while a sheet is still leaving fails silently).
    static func needsDismissalWait(_ steps: [Step]) -> Bool {
        steps.contains { step in
            switch step {
            case .closeSheets, .closeRootTool, .closeJourney, .closeJourneyTool, .closeSheetJourneyTool,
                 .closeJourneySheets, .closeForeignSheet, .awaitDismissalInFlight:
                return true
            case .waitForCover, .keepJourney, .openJourney, .performPageAction:
                return false
            }
        }
    }
}
