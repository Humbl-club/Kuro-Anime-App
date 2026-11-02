//
//  JourneyPolicyTests.swift
//  KuroTests
//
//  The navigation contract's pure rules (docs/superpowers/specs/2026-11-02-navigation-contract-design.md
//  §5): journey page identity, the stack rules (push, N5 dedupe pop-to-existing, pop, collapse), the
//  tool-return rule (N7), the deep-link collapse order (N10), the shrinking header's offset → progress
//  (H1/H3), fold memory (F3) and the swipe-back rule (N2).
//

import Testing
import Foundation
import SwiftUI
import KuroCore
@testable import Kuro

@MainActor
@Suite("Navigation contract: journeys, collapse, folds")
struct JourneyPolicyTests {

    // MARK: Fixtures

    private func anime(_ id: Int) throws -> Anime {
        let json = #"{"id":\#(id),"is_adult":false,"genres":[],"created_at":0,"updated_at":0}"#
        return try JSONDecoder().decode(Anime.self, from: Data(json.utf8))
    }

    private func character(_ id: Int) throws -> Character {
        try JSONDecoder().decode(Character.self, from: Data(#"{"id":\#(id)}"#.utf8))
    }

    private func staff(_ id: Int) throws -> Staff {
        try JSONDecoder().decode(Staff.self, from: Data(#"{"id":\#(id)}"#.utf8))
    }

    private func studio(_ id: Int) throws -> Studio {
        try JSONDecoder().decode(Studio.self, from: Data(#"{"id":\#(id)}"#.utf8))
    }

    private func author(_ id: Int) throws -> Author {
        try JSONDecoder().decode(Author.self, from: Data(#"{"id":\#(id)}"#.utf8))
    }

    private func media(_ kind: MediaKind, _ id: Int) -> Media {
        Media(
            id: id, kind: kind, title: "Title \(id)", imageURL: nil, year: "2020",
            displayDescription: "", episodes: kind == .anime ? 12 : nil, chapters: kind == .manga ? 40 : nil,
            rating: nil, genres: nil, statusRaw: nil, formatRaw: nil,
            popularityValue: nil, trendingValue: nil, createdAtValue: nil
        )
    }

    private let a: JourneyPage = .media(MediaRoute(kind: .anime, id: 1))
    private let b: JourneyPage = .media(MediaRoute(kind: .manga, id: 2))
    private let c: JourneyPage = .club(id: "c-3")

    // MARK: Identity

    @Test("Page ids are kind-prefixed; equality is the id only (preloaded == key-only)")
    func identity() throws {
        let lane = AnyJourneyPage(id: "discover:trending", title: "Trending") { EmptyView() }
        let rows: [(page: JourneyPage, id: String)] = [
            (.media(MediaRoute(kind: .anime, id: 7)), "media:anime:7"),
            (.media(MediaRoute(kind: .manga, id: 7)), "media:manga:7"),
            (.club(id: "c-1"), "club:c-1"),
            (.character(try character(5)), "character:5"),
            (.staff(try staff(5)), "staff:5"),
            (.studio(try studio(5)), "studio:5"),
            (.author(try author(5)), "author:5"),
            (.browse, "browse"),
            (.seeAll(lane), "seeAll:discover:trending"),
            (.seasonOverview(lane), "season:discover:trending"),
            (.profileList(lane), "profileList:discover:trending"),
            (.custom(lane), "custom:discover:trending"),
        ]
        for row in rows { #expect(row.page.id == row.id) }
        #expect(Set(rows.map(\.page)).count == rows.count)

        #expect(JourneyPage.media(MediaRoute(anime: try anime(7))) == .media(MediaRoute(kind: .anime, id: 7)))
        #expect(JourneyPage.media(MediaRoute(kind: .anime, id: 7)) != .media(MediaRoute(kind: .manga, id: 7)))
        #expect(JourneyPage.staff(try staff(5)) != .author(try author(5)))
        // A route to a page and the page itself share an id (dedupe across both entry points).
        #expect(AppRoute.page(.club(id: "c-1")).id == AppRoute.club(id: "c-1").id)
    }

    // MARK: Stack rules (N1, N5)

    @Test("Push: onto an empty path, then on top")
    func push() {
        #expect(JourneyPolicy.push(b, root: a, path: []) == [b])
        #expect(JourneyPolicy.push(c, root: a, path: [b]) == [b, c])
        #expect(JourneyPolicy.step(opening: c, root: a, path: [b]) == .push(c))
    }

    @Test("N5: the page on top is never pushed again (double tap, root included)")
    func sameAsTop() {
        #expect(JourneyPolicy.step(opening: a, root: a, path: []) == .none)
        #expect(JourneyPolicy.step(opening: b, root: a, path: [b]) == .none)
        #expect(JourneyPolicy.push(b, root: a, path: [b]) == [b])
    }

    @Test("N5: a page already in the stack pops back to it; the root clears the path")
    func popToExisting() {
        let d: JourneyPage = .browse
        #expect(JourneyPolicy.step(opening: b, root: a, path: [b, c, d]) == .popTo(keep: 1))
        #expect(JourneyPolicy.push(b, root: a, path: [b, c, d]) == [b])
        #expect(JourneyPolicy.step(opening: a, root: a, path: [b, c]) == .popToRoot)
        #expect(JourneyPolicy.push(a, root: a, path: [b, c]).isEmpty)
    }

    @Test("Season ping-pong A → B → A returns to A instead of stacking forever")
    func pingPong() {
        var path: [JourneyPage] = []
        for page in [b, a, b, a, b] { path = JourneyPolicy.push(page, root: a, path: path) }
        #expect(path == [b])
        path = JourneyPolicy.push(c, root: a, path: path)
        path = JourneyPolicy.push(b, root: a, path: path)
        #expect(path == [b])
    }

    @Test("Back pops exactly one level; the root has nothing to pop")
    func pop() {
        #expect(JourneyPolicy.pop([b, c]) == [b])
        #expect(JourneyPolicy.pop([b]).isEmpty)
        #expect(JourneyPolicy.pop([]).isEmpty)
        #expect(JourneyPolicy.top(root: a, path: []) == a)
        #expect(JourneyPolicy.top(root: a, path: [b, c]) == c)
    }

    @Test("Navigator: pages push, double taps don't, an open page is popped to, close collapses")
    func navigator() {
        let navigator = JourneyNavigator(root: a)
        var closed = 0
        navigator.dismissJourney = { closed += 1 }
        navigator.routes.openMedia(MediaRoute(kind: .manga, id: 2))
        navigator.routes.openMedia(MediaRoute(kind: .manga, id: 2))
        navigator.routes.openClub("c-3")
        #expect(navigator.path == [b, c])
        navigator.routes.openPage(b)
        #expect(navigator.path == [b])
        navigator.pop()
        #expect(navigator.path.isEmpty)
        navigator.pop()
        #expect(navigator.path.isEmpty)
        navigator.open(b)
        navigator.close()
        #expect(closed == 1)
    }

    @Test("✕ closes the whole journey, except in a foreign sheet covering it (that sheet closes itself)")
    func closeRule() {
        #expect(JourneyContext.closesJourney(isCovered: false))
        #expect(!JourneyContext.closesJourney(isCovered: true))
        var closed = 0
        var dismissed = 0
        var covered = false
        let context = JourneyContext(isPushed: true, open: { _ in }, pop: {}, close: { closed += 1 },
                                     isCovered: { covered })
        context.closeOrDismiss { dismissed += 1 }
        covered = true
        context.closeOrDismiss { dismissed += 1 }
        #expect(closed == 1 && dismissed == 1)
    }

    @Test("H4: a journey's first page has no pull-to-refresh (pull-down dismisses); pushed and pager pages keep it")
    func pullToRefreshRule() {
        #expect(!JourneyContext.allowsPullToRefresh(inJourney: true, isPushed: false))
        #expect(JourneyContext.allowsPullToRefresh(inJourney: true, isPushed: true))
        #expect(JourneyContext.allowsPullToRefresh(inJourney: false, isPushed: false))
    }

    // MARK: Tools (N7)

    @Test("N7: tools never become pages; a tool leaves the path unchanged and closes back to it")
    func tools() {
        let tracking = AppRoute.trackingEditor(TrackingEditorRequest(media: media(.anime, 1)))
        let addToClub = AppRoute.addToClub(MediaKey(kind: .anime, id: 1))
        #expect(RoutePolicy.journeyPage(for: tracking) == nil)
        #expect(RoutePolicy.journeyPage(for: addToClub) == nil)
        #expect(RoutePolicy.journeyPage(for: .browse) == .browse)
        #expect(RoutePolicy.journeyPage(for: .media(MediaRoute(kind: .anime, id: 1))) == a)

        let navigator = JourneyNavigator(root: a)
        navigator.open(b)
        navigator.open(tracking)
        #expect(navigator.tool?.id == tracking.id)
        #expect(navigator.path == [b])
        navigator.open(tracking)                         // double tap: same tool stays
        #expect(navigator.tool?.id == tracking.id)
        navigator.tool = nil                             // Cancel / Save
        #expect(navigator.path == [b])
        #expect(navigator.top == b)

        // A page opened from inside the host's own tool closes the tool, then pushes.
        navigator.open(addToClub)
        navigator.open(c)
        #expect(navigator.tool == nil)
        #expect(navigator.path == [b, c])
    }

    @Test("Presenter slot: a page opens a new journey, the same page again changes nothing, a tool is a tool")
    func presenterSlot() throws {
        let slot = PresentationSlot()
        slot.routes.openMedia(MediaRoute(kind: .anime, id: 1))
        guard case .journey(let first) = slot.presented else { Issue.record("no journey"); return }
        #expect(first.root == a)
        slot.routes.openMedia(MediaRoute(anime: try anime(1)))
        guard case .journey(let same) = slot.presented else { Issue.record("journey lost"); return }
        #expect(same === first)
        slot.routes.presentAddToClub(MediaKey(kind: .anime, id: 1))
        guard case .tool(let tool) = slot.presented else { Issue.record("no tool"); return }
        #expect(tool.id == "addToClub:anime:1")
    }

    @Test("A presenter inside a journey forwards (push); while a foreign sheet covers it, it presents")
    func presenterForwards() {
        let navigator = JourneyNavigator(root: a)
        let slot = PresentationSlot()
        var covered = false
        slot.journey = JourneyContext(isPushed: false, open: { navigator.open($0) }, pop: {}, close: {},
                                      isCovered: { covered })
        slot.routes.openClub("c-3")
        #expect(navigator.path == [c])
        #expect(slot.presented == nil)
        covered = true
        slot.routes.openMedia(MediaRoute(kind: .manga, id: 2))
        #expect(navigator.path == [c])
        guard case .journey(let shown) = slot.presented else { Issue.record("not presented"); return }
        #expect(shown.root == b)
    }

    // MARK: Deep-link collapse (N10)

    @Test("N10: the onboarding cover finishes first")
    func coverFirst() {
        var snapshot = NavigationCollapsePolicy.Snapshot()
        snapshot.coverOpen = true
        snapshot.openSheets = ["profile"]
        #expect(NavigationCollapsePolicy.plan(snapshot, target: .journey(a)) == [.waitForCover])
    }

    @Test("N10: sheets, tool and journey close in order, then the target opens")
    func collapseOrder() {
        var snapshot = NavigationCollapsePolicy.Snapshot()
        snapshot.openSheets = ["profile", "search"]
        snapshot.journeyTop = c
        let steps = NavigationCollapsePolicy.plan(snapshot, target: .journey(a))
        #expect(steps == [.closeSheets(["profile", "search"]), .closeJourney, .openJourney(a)])
        #expect(NavigationCollapsePolicy.needsDismissalWait(steps))

        var toolOnly = NavigationCollapsePolicy.Snapshot()
        toolOnly.rootToolOpen = true
        #expect(NavigationCollapsePolicy.plan(toolOnly, target: .page) == [.closeRootTool, .performPageAction])

        let nothingOpen = NavigationCollapsePolicy.plan(.init(), target: .journey(a))
        #expect(nothingOpen == [.openJourney(a)])
        #expect(!NavigationCollapsePolicy.needsDismissalWait(nothingOpen))
    }

    @Test("N10: a link to the page already on top keeps that journey (only its tool closes)")
    func sameTargetOnTop() {
        var snapshot = NavigationCollapsePolicy.Snapshot()
        snapshot.journeyTop = a
        #expect(NavigationCollapsePolicy.plan(snapshot, target: .journey(a)) == [.keepJourney])
        snapshot.journeyToolOpen = true
        #expect(NavigationCollapsePolicy.plan(snapshot, target: .journey(a)) == [.closeJourneyTool, .keepJourney])
        snapshot.openSheets = ["profile"]
        #expect(NavigationCollapsePolicy.plan(snapshot, target: .journey(a))
                == [.closeSheets(["profile"]), .closeJourney, .openJourney(a)])
    }

    @Test("Coordinator: closes registered sheets, then opens the journey; a held link runs after the cover")
    func coordinator() async throws {
        let navigation = KuroNavigationCoordinator(dismissalDelay: .zero)
        var profileOpen = true
        var onboardingOpen = true
        navigation.registerLayer("profile", kind: .sheet, isPresented: { profileOpen }, close: { profileOpen = false })
        navigation.registerLayer("onboarding", kind: .cover, isPresented: { onboardingOpen }, close: { onboardingOpen = false })

        navigation.collapseThenOpen(b)
        #expect(profileOpen)                       // held: the cover finishes first
        #expect(navigation.journey == nil)

        onboardingOpen = false
        navigation.layerDidChange()
        #expect(!profileOpen)
        try await Task.sleep(for: .milliseconds(50))
        #expect(navigation.journey?.root == b)

        // Same page on top: kept (no new journey).
        let kept = navigation.journey
        navigation.collapseThenOpen(b)
        #expect(navigation.journey === kept)

        // A page link: everything collapses, then the action runs.
        var switched = false
        navigation.collapseThen { switched = true }
        #expect(navigation.journey == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(switched)
    }

    // MARK: Shrinking header (H1, H3)

    @Test("Offset → progress is clamped 0…1; Reduce Motion snaps half way")
    func collapseProgress() {
        #expect(KuroCollapse.progress(offset: -40, distance: 200) == 0)
        #expect(KuroCollapse.progress(offset: 0, distance: 200) == 0)
        #expect(KuroCollapse.progress(offset: 100, distance: 200) == 0.5)
        #expect(KuroCollapse.progress(offset: 400, distance: 200) == 1)
        #expect(KuroCollapse.progress(offset: 150, start: 100, distance: 100) == 0.5)
        #expect(KuroCollapse.progress(offset: 10, distance: 0) == 1)
        #expect(KuroCollapse.displayProgress(0.3, reduceMotion: false) == 0.3)
        #expect(KuroCollapse.displayProgress(0.3, reduceMotion: true) == 0)
        #expect(KuroCollapse.displayProgress(0.5, reduceMotion: true) == 1)
        #expect(KuroCollapse.keyOpacity(0) == 1)
        #expect(KuroCollapse.keyOpacity(0.6) == 0)
        #expect(KuroCollapse.keyOpacity(1) == 0)
    }

    // MARK: Folds (F2, F3)

    @Test("Fold memory: per page and section, default until toggled, collapse remembered too")
    func foldMemory() {
        let folds = KuroFoldMemory()
        let page = KuroFold.page(kind: "anime", id: 7)
        #expect(!folds.isExpanded(page: page, section: "story"))
        #expect(folds.isExpanded(page: page, section: "songs", defaultExpanded: true))
        folds.setExpanded(true, page: page, section: "story")
        #expect(folds.isExpanded(page: page, section: "story"))
        #expect(!folds.isExpanded(page: KuroFold.page(kind: "manga", id: 7), section: "story"))
        folds.setExpanded(false, page: page, section: "songs")
        #expect(!folds.isExpanded(page: page, section: "songs", defaultExpanded: true))
        let binding = folds.binding(page: page, section: "episodes")
        binding.wrappedValue = true
        #expect(folds.isExpanded(page: page, section: "episodes"))
        #expect(KuroFold.accessibilityValue(expanded: true, german: false) == "Expanded")
        #expect(KuroFold.accessibilityValue(expanded: false, german: true) == "Zugeklappt")
        #expect(KuroFold.animation(reduceMotion: true) == nil)
    }

    // MARK: Swipe-back (N2)

    @Test("Edge swipe-back is allowed whenever there is a page to pop to and no transition runs")
    func popGesture() {
        #expect(!KuroPopGestureDelegate.allowsPop(stackCount: 1, isTransitioning: false))
        #expect(KuroPopGestureDelegate.allowsPop(stackCount: 2, isTransitioning: false))
        #expect(!KuroPopGestureDelegate.allowsPop(stackCount: 3, isTransitioning: true))
    }
}
