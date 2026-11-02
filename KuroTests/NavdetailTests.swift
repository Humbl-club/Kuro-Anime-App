//
//  NavdetailTests.swift
//  KuroTests
//
//  Navigation lane "detail" (docs/superpowers/specs/2026-11-02-navigation-contract-design.md): the anime
//  and manga detail pages as journey pages. Pure rules only: what every in-detail tap opens (a pushed
//  journey page, never a tool), the ladder-sourced "Original work" target, the club rail card's club
//  (N9), the shrinking header's distance (H1-H3), the fold keys, the F2 scroll-back test and the
//  restored-open unit list load (F3), and the grabber (N8).
//

import Testing
import Foundation
import SwiftUI
import UIKit
import KuroCore
@testable import Kuro

@MainActor
@Suite("Navigation lane: detail pages")
struct NavdetailTests {

    // MARK: Fixtures

    private func anime(_ id: Int) throws -> Anime {
        let json = #"{"id":\#(id),"is_adult":false,"genres":[],"created_at":0,"updated_at":0}"#
        return try JSONDecoder().decode(Anime.self, from: Data(json.utf8))
    }

    private func character(_ id: Int) throws -> Character {
        try JSONDecoder().decode(Character.self, from: Data(#"{"id":\#(id)}"#.utf8))
    }

    private func staff(_ id: Int, name: String? = nil) throws -> Staff {
        let json = name.map { #"{"id":\#(id),"name_full":"\#($0)"}"# } ?? #"{"id":\#(id)}"#
        return try JSONDecoder().decode(Staff.self, from: Data(json.utf8))
    }

    private func studio(_ id: Int) throws -> Studio {
        try JSONDecoder().decode(Studio.self, from: Data(#"{"id":\#(id)}"#.utf8))
    }

    private func author(_ id: Int) throws -> Author {
        try JSONDecoder().decode(Author.self, from: Data(#"{"id":\#(id)}"#.utf8))
    }

    private func ladder(_ type: String, _ id: Int, author: String? = "Gege Akutami") -> MediaLadderItem {
        MediaLadderItem(mediaType: type, mediaId: id, title: "Source \(id)", coverImage: nil, year: 2018,
                        format: type, rating: nil, reasonLabel: nil, sourceAuthorName: author)
    }

    private func clubActivity(id: String) throws -> ClubMediaActivity {
        let json = #"{"id":"\#(id)","name":"Friday","description":null,"sharing_level":"status","max_members":20,"is_archived":false,"invite_code":null,"created_at":"2026-11-01T00:00:00Z"}"#
        let club = try JSONDecoder().decode(ClubInfo.self, from: Data(json.utf8))
        return ClubMediaActivity(club: club, memberCount: 3, sharingLevel: "status", members: [], matchingItems: [])
    }

    // MARK: Every in-detail tap is a pushed page (N9), never a tool (N7)

    @Test("Season tiles, ladder cards, people and clubs open journey pages, not tools")
    func tapsArePages() throws {
        let season = DetailNavigation.seasonPage(id: 41)
        #expect(season.id == "media:anime:41")

        #expect(DetailNavigation.ladderPage(ladder("MANGA", 30))?.id == "media:manga:30")
        #expect(DetailNavigation.ladderPage(ladder("manga", 30))?.id == "media:manga:30")
        #expect(DetailNavigation.ladderPage(ladder("ANIME", 127230))?.id == "media:anime:127230")
        #expect(DetailNavigation.ladderPage(ladder("MANGA", 0)) == nil, "a ladder row without a catalogue id opens nothing")

        #expect(DetailNavigation.characterPage(try character(12)).id == "character:12")
        #expect(DetailNavigation.creditPage(.staff(try staff(5))).map(\.id) == "staff:5")
        #expect(DetailNavigation.creditPage(.studio(try studio(6))).map(\.id) == "studio:6")
        #expect(DetailNavigation.creditPage(.author(try author(7))).map(\.id) == "author:7")
        #expect(DetailNavigation.creditPage(.media(MediaKey(kind: .manga, id: 30))).map(\.id) == "media:manga:30")
        #expect(DetailNavigation.creditPage(.none) == nil)

        // Every one of them is a page inside the journey (pushed), never a tool over the page.
        let pages: [JourneyPage] = [season, DetailNavigation.characterPage(try character(12)),
                                    DetailNavigation.clubPage(try clubActivity(id: "club-9"))]
        for page in pages {
            #expect(RoutePolicy.journeyPage(for: .page(page)) == page)
            let navigator = JourneyNavigator(root: .media(MediaRoute(kind: .anime, id: 1)))
            navigator.open(.page(page))
            #expect(navigator.path == [page])
            #expect(navigator.tool == nil)
        }
    }

    @Test("A club rail card opens its club (N9: no dead tap)")
    func clubRailCardOpensClub() throws {
        let page = DetailNavigation.clubPage(try clubActivity(id: "club-9"))
        #expect(page == .club(id: "club-9"))
        #expect(page.id == "club:club-9")
    }

    @Test("List settings and add to a club stay tools: the detail stays on top (N7)")
    func toolsDoNotPush() throws {
        let root: JourneyPage = .media(MediaRoute(kind: .anime, id: 1))
        let navigator = JourneyNavigator(root: root)
        navigator.open(.page(DetailNavigation.seasonPage(id: 2)))
        navigator.open(.trackingEditor(TrackingEditorRequest(media: try anime(2))))
        #expect(navigator.path == [DetailNavigation.seasonPage(id: 2)])
        #expect(navigator.tool?.id == "tracking:anime:2")
        navigator.open(.addToClub(MediaKey(kind: .anime, id: 2)))
        #expect(navigator.path.count == 1)
        #expect(navigator.tool?.id == "addToClub:anime:2")
    }

    @Test("Season ping-pong pops back (N5), with a preloaded or a key-only root")
    func seasonPingPong() throws {
        // The journey was opened with a preloaded title (Concierge) and the season tile opens it by key.
        let preloaded: JourneyPage = .media(MediaRoute(anime: try anime(1)))
        var path: [JourneyPage] = []
        path = JourneyPolicy.push(DetailNavigation.seasonPage(id: 2), root: preloaded, path: path)
        #expect(path == [DetailNavigation.seasonPage(id: 2)])
        #expect(JourneyPolicy.step(opening: DetailNavigation.seasonPage(id: 1), root: preloaded, path: path) == .popToRoot)
        // A → B → C → B pops to B; a double tap on the top page does nothing.
        path = JourneyPolicy.push(DetailNavigation.seasonPage(id: 3), root: preloaded, path: path)
        #expect(JourneyPolicy.step(opening: DetailNavigation.seasonPage(id: 2), root: preloaded, path: path) == .popTo(keep: 1))
        #expect(JourneyPolicy.step(opening: DetailNavigation.seasonPage(id: 3), root: preloaded, path: path) == .none)
    }

    // MARK: Ladder-sourced "Original work" (N9)

    @Test("The ladder's original work is a button when it maps to a title, text otherwise")
    func originalWorkFromLadder() throws {
        let source = ladder("MANGA", 30)
        let mapped = DetailCreditRow.anime(staff: [], studios: [], sourceAuthor: source.sourceAuthorName,
                                           sourceKey: DetailNavigation.ladderKey(source), german: false)
        let row = try #require(mapped.first)
        #expect(row.role == "Original work")
        #expect(row.name == "Gege Akutami")
        #expect(row.isInteractive)
        #expect(DetailNavigation.creditPage(row.target)?.id == "media:manga:30")

        let unmapped = DetailCreditRow.anime(staff: [], studios: [], sourceAuthor: "Gege Akutami", german: true)
        #expect(unmapped.first?.role == "Vorlage")
        #expect(unmapped.first?.isInteractive == false)

        // The staff record wins over the ladder name: it opens the person, as before.
        let creator = try staff(4, name: "Gege Akutami")
        let staffRows = DetailCreditRow.anime(staff: [(staff: creator, role: "Original Creator")], studios: [],
                                              sourceAuthor: "Gege Akutami",
                                              sourceKey: DetailNavigation.ladderKey(source), german: false)
        #expect(staffRows.first.flatMap { DetailNavigation.creditPage($0.target) }?.id == "staff:4")
    }

    // MARK: Shrinking header (H1-H3)

    @Test("The collapse distance is the hero less the compact bar, never zero")
    func collapseDistance() {
        #expect(DetailCollapse.distance(heroHeight: 300) == 300 - KuroJourneyChrome.barHeight)
        #expect(DetailCollapse.distance(heroHeight: 0) == 1)
        #expect(DetailCollapse.distance(heroHeight: 40) == 1)
        // The hero has scrolled under the bar exactly at the distance: progress 1 (compact bar).
        let distance = DetailCollapse.distance(heroHeight: 300)
        #expect(KuroCollapse.progress(offset: 0, distance: distance) == 0)
        #expect(KuroCollapse.progress(offset: distance, distance: distance) == 1)
        #expect(KuroCollapse.progress(offset: distance / 2, distance: distance) == 0.5)
    }

    @Test("The collapse state starts at the hero (round keys), not the compact bar")
    func collapseStateStartsOpen() {
        let state = DetailCollapseState()
        #expect(state.progress == 0)
        #expect(state.heroHeight == 0)
    }

    // MARK: Folds (F1-F3)

    @Test("Fold memory is per title and section, and survives leaving the page (F3)")
    func foldKeys() {
        #expect(DetailFold.page(MediaKey(kind: .anime, id: 7)) == "anime:7")
        #expect(DetailFold.page(MediaKey(kind: .manga, id: 7)) == "manga:7")
        let sections = [DetailFold.story, DetailFold.units, DetailFold.songs, DetailFold.coverage, DetailFold.adaptationGuide]
        #expect(Set(sections).count == sections.count)

        let memory = KuroFoldMemory()
        let anime7 = DetailFold.page(MediaKey(kind: .anime, id: 7))
        let manga7 = DetailFold.page(MediaKey(kind: .manga, id: 7))
        let story = memory.binding(page: anime7, section: DetailFold.story)
        #expect(story.wrappedValue == false)
        story.wrappedValue = true
        // A new binding (the page rebuilt after Back) reads the same answer; other titles stay folded.
        #expect(memory.binding(page: anime7, section: DetailFold.story).wrappedValue)
        #expect(!memory.isExpanded(page: manga7, section: DetailFold.story))
        #expect(!memory.isExpanded(page: anime7, section: DetailFold.songs))
    }

    @Test("F2: a fold scrolls back only when its section's top has gone above the view")
    func scrollBack() {
        #expect(DetailFold.scrollsBack(sectionMinY: -1))
        #expect(DetailFold.scrollsBack(sectionMinY: -400))
        #expect(!DetailFold.scrollsBack(sectionMinY: 0))
        #expect(!DetailFold.scrollsBack(sectionMinY: 120))
    }

    @Test("An open unit list loads its pages, also when restored open from the session")
    func restoredOpenLoads() {
        #expect(DetailFold.loadsAllUnits(expanded: true, loadedCount: 0, hasMore: true, loading: false))
        #expect(!DetailFold.loadsAllUnits(expanded: false, loadedCount: 0, hasMore: true, loading: false))
        #expect(!DetailFold.loadsAllUnits(expanded: true, loadedCount: 50, hasMore: true, loading: false),
                "the sentinel pages on from there")
        #expect(!DetailFold.loadsAllUnits(expanded: true, loadedCount: 0, hasMore: false, loading: false))
        #expect(!DetailFold.loadsAllUnits(expanded: true, loadedCount: 0, hasMore: true, loading: true))
    }

    // MARK: Grabber (N8)

    @Test("The detail journey always shows its grabber")
    func grabber() {
        #expect(DetailLoaderChrome.dragIndicator == .visible)
    }
}

// MARK: - Journey renders (evidence for the shrinking header, N1-N3 / H1-H2)

/// Renders the anime and manga detail inside a real `JourneyHost`: the root page (✕ only, round key over
/// the hero), a pushed page (Back + ✕) and the pushed page scrolled under the compact bar. PNGs go to a
/// temporary folder, or to docs/navigation/detail/ with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`.
@Suite("Navigation lane: detail journey renders", .serialized, .timeLimit(.minutes(3)))
@MainActor
struct NavdetailRenderTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-nav-detail", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/navigation/detail")
    }()

    @Test("Detail journey: root, pushed and collapsed chrome")
    func journeyChrome() async throws {
        let suite = "nav-detail-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: [])
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: FakeLibraryBackend(), flags: flags)

        let dark = try Self.anime(id: 2, title: "Jujutsu Kaisen", color: "#2b3a55")
        let light = try Self.anime(id: 3, title: "Mushishi", color: "#e8e2c8")
        let manga = try Self.manga(id: 30, title: "Chainsaw Man", color: "#d9c27a")
        var content = AnimeDetailContent()
        content.studios = [Studio(id: 1, anilistId: nil, name: "MAPPA", isAnimationStudio: true, siteUrl: nil, favourites: nil)]
        // Enough sections that the page scrolls well past its hero (the collapsed render).
        content.songs = (1...6).map { ThemeSong(kind: $0 % 2 == 0 ? .ending : .opening, sequence: $0, title: "Song \($0)",
                                                artist: "Artist \($0)", episodes: "1–12") }
        content.characters = (1...4).map { index in
            (character: Character(id: index, anilistId: nil, nameFull: "Character \(index)", nameNative: nil, imageLarge: nil,
                                  description: nil, gender: nil, age: nil), role: "MAIN")
        }

        let root: JourneyPage = .custom(AnyJourneyPage(id: "detail:2") { AnimeDetailPage(anime: dark, preview: content) })
        let navigator = JourneyNavigator(root: root)
        let view = Self.host(JourneyHost(navigator: navigator), graph: graph)
        let window = Self.window(view, width: 390, height: 844)
        defer { window.isHidden = true; window.rootViewController = nil }
        try? await Task.sleep(for: .milliseconds(900))
        await capture(window, name: "nav-detail-root-dark-390.png")
        #expect(navigator.path.isEmpty, "the journey's root: ✕ only, no Back")

        // A pushed light-artwork title: Back + ✕.
        navigator.open(.custom(AnyJourneyPage(id: "detail:3") { AnimeDetailPage(anime: light, preview: content) }))
        try? await Task.sleep(for: .milliseconds(1_200))
        await capture(window, name: "nav-detail-pushed-light-390.png")
        #expect(navigator.path.count == 1, "a pushed page: Back + ✕")

        // Scrolled under the compact bar: plain ink glyphs on paper, the title in the bar.
        if let scroll = Self.scrollView(in: window) {
            scroll.setContentOffset(CGPoint(x: 0, y: 420), animated: false)
        }
        try? await Task.sleep(for: .milliseconds(700))
        await capture(window, name: "nav-detail-pushed-collapsed-390.png")

        // The manga folio band (light paper, neutral keys), pushed.
        navigator.open(.custom(AnyJourneyPage(id: "detail:m30") { MangaDetailPage(manga: manga, preview: MangaDetailContent()) }))
        try? await Task.sleep(for: .milliseconds(1_200))
        await capture(window, name: "nav-detail-manga-pushed-390.png")
        #expect(navigator.path.count == 2)

        // Back pops exactly one level (N1).
        navigator.pop()
        #expect(navigator.path.count == 1)
    }

    // MARK: Hosting

    private static func host<V: View>(_ view: V, graph: AppGraph) -> some View {
        view
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(graph.home)
            .environment(graph.catalog)
            .environment(graph.releases)
            .environment(graph.social)
            .environment(graph.clubs)
            .environment(graph.availability)
            .environment(graph.flags)
            .environment(graph.outboundLinks)
            .environment(graph.artworkMaterials)
            .environment(graph.identity)
    }

    private static func window<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> UIWindow {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        host.safeAreaRegions = []
        // A window in the test host's foreground scene (a scene-less window does not draw).
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.isHidden = false
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.layoutIfNeeded()
        return window
    }

    private func capture(_ window: UIWindow, name: String) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { Issue.record("\(name): PNG encoding failed"); return }
        let url = Self.outDir.appendingPathComponent(name)
        do { try data.write(to: url) } catch { Issue.record("\(name): write failed (\(error))") }
    }

    /// The visible page's vertical scroll view (the top of the journey's stack).
    private static func scrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var stack = [root]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.window != nil, !scroll.isHidden,
               scroll.contentSize.height > scroll.bounds.height,
               scroll.convert(scroll.bounds, to: nil).intersects(root.bounds) {
                if best == nil || scroll.contentSize.height > (best?.contentSize.height ?? 0) { best = scroll }
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }

    private static func anime(id: Int, title: String, color: String) throws -> Anime {
        let object: [String: Any] = [
            "id": id, "is_adult": false, "genres": ["Drama"], "created_at": 0, "updated_at": 0,
            "title_english": title, "format": "TV", "status": "FINISHED", "episodes": 24, "season_year": 2023,
            "cover_image_color": color,
            "description": String(repeating: "A long synopsis line that keeps the page tall enough to scroll. ", count: 30)
        ]
        return try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func manga(id: Int, title: String, color: String) throws -> Manga {
        let object: [String: Any] = [
            "id": id, "is_adult": false, "genres": ["Action"], "created_at": 0, "updated_at": 0,
            "title_english": title, "format": "MANGA", "status": "RELEASING", "cover_image_color": color,
            "description": String(repeating: "A long synopsis line that keeps the page tall enough to scroll. ", count: 30)
        ]
        return try JSONDecoder().decode(Manga.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
