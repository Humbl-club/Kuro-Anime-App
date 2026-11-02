import KuroCore
import SwiftUI

// MARK: - App shell journeys (navigation contract, docs/superpowers/specs/2026-11-02-navigation-contract-design.md)
//
// The header's sheets (Profile, Search, Concierge) and the pages Profile opens (Data sources, Clubs,
// Find, Concierge) are journeys: each header sheet hosts ONE navigation stack (`ShellJourneyHost`, a
// `JourneyHost` that also knows when its sheet ends), and every page opened inside it is pushed (back
// chevron + edge swipe-back), ✕ collapses the whole sheet (N1–N4). Deep links go through
// `ShellLinkPolicy` (pure, tested in KuroTests/NavshellTests.swift) and the root coordinator's collapse
// (N10): the onboarding cover finishes first, then every sheet, tool and journey closes, then the
// target opens.
//
// Page lifetime. A pushed page fires `onDisappear` on the page under it (it is covered, not gone).
// Pages whose `onDisappear` cancels work (Profile's imports, Concierge's chat) read
// `\.shellPageLifetime`: while the page is still in its journey's stack they keep working, and their
// teardown runs when they are popped or the journey's sheet ends.

/// Stable identities of the shell's journey pages (kind-prefixed by `JourneyPage.custom` as
/// `custom:<id>`).
enum ShellPageID {
    static let profile = "profile"
    static let search = "search"
    static let concierge = "concierge"
    /// Concierge opened from an import result with the list to review (a different page from the plain
    /// Concierge row, so the review is never popped back onto an earlier chat).
    static let conciergeReview = "concierge:review"
    static let dataSources = "profile:dataSources"
    static let clubs = "profile:clubs"
}

// MARK: - Deep links (N10, pure)

/// What a `kuro://` link does in the app shell.
enum ShellLinkAction: Equatable {
    /// The onboarding cover is open: the link waits until the cover has finished closing.
    case waitForOnboarding
    /// Collapse everything, then open this page as a new journey on the root.
    case openJourney(JourneyPage)
    /// Collapse everything, then switch the pager to this page.
    case switchPage(KuroMainView.Section)
    /// Collapse everything, then open the Concierge sheet (a journey) with this prompt.
    case openConciergeSheet(prompt: String?)
    /// Collapse everything, then switch to the pager's Concierge page with this prompt (legacy order).
    case openConciergePage(prompt: String?)
    /// Collapse everything, then switch to Clubs with the invite code prefilled.
    case joinClub(code: String)
    /// Handled elsewhere (auth callbacks are consumed at the app level).
    case none
}

enum ShellLinkPolicy {
    /// The action for `link`. `onboardingOpen`: the first-run cover is showing. `conciergeInPager`:
    /// the pager has a Concierge page (legacy order) instead of the Concierge sheet.
    static func action(for link: DeepLink, onboardingOpen: Bool, conciergeInPager: Bool) -> ShellLinkAction {
        if case .authCallback = link { return .none }
        if onboardingOpen { return .waitForOnboarding }
        switch link {
        case .anime(let id): return .openJourney(.media(MediaRoute(kind: .anime, id: id)))
        case .manga(let id): return .openJourney(.media(MediaRoute(kind: .manga, id: id)))
        case .club(let id): return .openJourney(.club(id: id))
        case .collection: return .switchPage(.collection)
        case .discover: return .switchPage(.discover)
        case .concierge(let prompt):
            return conciergeInPager ? .openConciergePage(prompt: prompt) : .openConciergeSheet(prompt: prompt)
        case .joinClub(let code): return .joinClub(code: code)
        case .authCallback: return .none
        }
    }
}

// MARK: - Page lifetime

/// Ends with a shell journey's sheet (not with its root page's `onDisappear` on a push).
@MainActor
final class ShellJourneyLifetime {
    let navigator: JourneyNavigator
    private(set) var ended = false
    private var handlers: [String: () -> Void] = [:]

    init(navigator: JourneyNavigator) {
        self.navigator = navigator
    }

    /// Whether the page with this `JourneyPage.id` is still in the journey (root or pushed; covered by a
    /// push counts) and the journey has not ended.
    func contains(pageID: String) -> Bool {
        !ended && Self.isInStack(pageID: pageID, root: navigator.root, path: navigator.path)
    }

    /// The pure rule behind `contains`.
    static func isInStack(pageID: String, root: JourneyPage, path: [JourneyPage]) -> Bool {
        root.id == pageID || path.contains { $0.id == pageID }
    }

    /// Registers (or replaces) a page's teardown for the end of the journey.
    func onEnd(_ pageID: String, perform handler: @escaping () -> Void) {
        guard !ended else { handler(); return }
        handlers[pageID] = handler
    }

    /// Removes a page's teardown (the page tore itself down when it was popped).
    func cancel(_ pageID: String) {
        handlers[pageID] = nil
    }

    /// The journey's sheet ended: every registered teardown runs once.
    func end() {
        guard !ended else { return }
        ended = true
        let pending = handlers
        handlers = [:]
        for handler in pending.values { handler() }
    }
}

/// What a shell journey page knows about its own lifetime (`\.shellPageLifetime`; nil outside a shell
/// journey, where pages keep their plain `onDisappear` teardown).
struct ShellPageLifetime {
    let pageID: String
    let journey: ShellJourneyLifetime

    /// The page is still in its journey (covered by a pushed page): keep its work running.
    @MainActor var isStillInJourney: Bool { journey.contains(pageID: pageID) }

    /// Runs `teardown` when the journey's sheet ends (registered once per page; re-registering
    /// replaces it).
    @MainActor func onJourneyEnd(_ teardown: @escaping () -> Void) {
        journey.onEnd(pageID, perform: teardown)
    }

    /// The page tore itself down (popped): its end-of-journey teardown is no longer needed.
    @MainActor func didTearDown() {
        journey.cancel(pageID)
    }
}

private struct ShellJourneyLifetimeKey: EnvironmentKey {
    static let defaultValue: ShellJourneyLifetime? = nil
}

private struct ShellPageLifetimeKey: EnvironmentKey {
    static let defaultValue: ShellPageLifetime? = nil
}

extension EnvironmentValues {
    /// The shell journey this view is in (nil outside one).
    var shellJourneyLifetime: ShellJourneyLifetime? {
        get { self[ShellJourneyLifetimeKey.self] }
        set { self[ShellJourneyLifetimeKey.self] = newValue }
    }

    /// The current shell journey page's lifetime (nil outside a shell journey).
    var shellPageLifetime: ShellPageLifetime? {
        get { self[ShellPageLifetimeKey.self] }
        set { self[ShellPageLifetimeKey.self] = newValue }
    }
}

private struct ShellPageModifier: ViewModifier {
    let pageID: String
    @Environment(\.shellJourneyLifetime) private var journey

    func body(content: Content) -> some View {
        content.environment(\.shellPageLifetime, journey.map { ShellPageLifetime(pageID: pageID, journey: $0) })
    }
}

extension View {
    /// Marks this view as the shell journey page `pageID` (its `JourneyPage.id`).
    func shellPage(_ pageID: String) -> some View {
        modifier(ShellPageModifier(pageID: pageID))
    }

    /// The journey chrome for a page without artwork whose top is not a scrolling headline (Search,
    /// Concierge, Clubs): the compact bar from the start, and the page laid out below it.
    func shellBarChrome(title: String) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: KuroJourneyChrome.barHeight)
        }
        .kuroJourneyChrome(title: title, collapseProgress: 1)
    }
}

// MARK: - Host

/// A header sheet as a journey: `JourneyHost` with a visible grabber (N8) and a lifetime that ends with
/// the sheet (see "Page lifetime" above).
struct ShellJourneyHost: View {
    @State private var lifetime: ShellJourneyLifetime
    /// The navigation layer this sheet registered as (`.kuroNavigationLayer(layer, …)`): a deep link to
    /// the page on top of this journey keeps it (N10).
    private let layer: String?
    @Environment(\.kuroNavigation) private var navigation

    init(root: JourneyPage, layer: String? = nil) {
        _lifetime = State(initialValue: ShellJourneyLifetime(navigator: JourneyNavigator(root: root)))
        self.layer = layer
    }

    var body: some View {
        JourneyHost(navigator: lifetime.navigator)
            .environment(\.shellJourneyLifetime, lifetime)
            .presentationDragIndicator(.visible)
            .onAppear {
                if let layer { navigation?.attachJourney(lifetime.navigator, toLayer: layer) }
            }
            .onDisappear {
                if let layer { navigation?.detachJourney(lifetime.navigator, fromLayer: layer) }
                lifetime.end()
            }
    }
}

// MARK: - Pages

/// The shell's journey pages. Builders never wrap their page in a NavigationStack (the host owns it).
@MainActor
enum ShellJourneyPages {
    static var searchTitle: String { KuroLocale.text("Search", "Suche") }
    static var profileTitle: String { KuroLocale.text("Profile", "Profil") }
    static var dataSourcesTitle: String { KuroLocale.text("Data sources", "Datenquellen") }
    static var clubsTitle: String { KuroLocale.text("Clubs", "Clubs") }
    static let conciergeTitle = "Concierge"

    /// Search (header magnifier, Profile → Find): its result rows and Browse entry push.
    static func search(scope: EditorialSearchView.SearchScope = .all) -> JourneyPage {
        let title = searchTitle
        return .custom(AnyJourneyPage(id: ShellPageID.search, title: title) {
            EditorialSearchView(initialScope: scope)
                .shellBarChrome(title: title)
                .shellPage("custom:\(ShellPageID.search)")
        })
    }

    /// Profile (header avatar): its rows push Clubs, Data sources, Find and Concierge.
    static func profile(
        onImportNavigation: @escaping (ImportResultDestination) -> Void,
        onOpenCollection: @escaping () -> Void
    ) -> JourneyPage {
        .custom(AnyJourneyPage(id: ShellPageID.profile, title: profileTitle) {
            ProfileView(onImportNavigation: onImportNavigation, onOpenCollection: onOpenCollection)
                .shellPage("custom:\(ShellPageID.profile)")
        })
    }

    /// Concierge (header sheet, Profile row, Profile import review): recommendations push their title.
    static func concierge(
        prompt: String? = nil,
        review: Bool = false,
        onImportNavigation: ((ImportResultDestination) -> Void)?
    ) -> JourneyPage {
        let id = review ? ShellPageID.conciergeReview : ShellPageID.concierge
        return .custom(AnyJourneyPage(id: id, title: conciergeTitle) {
            ConciergeView(assistantEnabled: true, initialPrompt: prompt, onImportNavigation: onImportNavigation)
                .shellBarChrome(title: conciergeTitle)
                .shellPage("custom:\(id)")
        })
    }

    /// Profile → About → Data sources and credits.
    static var dataSources: JourneyPage {
        .custom(AnyJourneyPage(id: ShellPageID.dataSources, title: dataSourcesTitle) {
            DataSourcesView()
        })
    }

    /// Profile → Your clubs: the clubs list; a club pushes its detail.
    static var clubs: JourneyPage {
        let title = clubsTitle
        return .custom(AnyJourneyPage(id: ShellPageID.clubs, title: title) {
            ClubsView()
                .shellBarChrome(title: title)
        })
    }
}
