import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// "After" fixture renders for the Discover + Clubs redesign, Discover lane (2026-11-03). No network:
/// every graph runs over an in-process stub PostgREST endpoint (`StubServer`). PNGs are 1x
/// (`FixtureRaster`) and go to `docs/discover-clubs-2026-11-03/after/discover-*.png` only with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; run it with `-only-testing:KuroTests/DiscoverAfterSnapshotTests`
/// so no other suite rewrites its committed evidence. Ordinary runs render into a temporary folder.
/// `TEST_RUNNER_KURO_DC_SUFFIX=-de` names a German run's files (the simulator's language decides
/// `KuroLocale`). Page bodies only: the app header is not composed (it paints the same canvas).
@Suite("Discover after renders", .serialized, .timeLimit(.minutes(8)))
@MainActor
struct DiscoverAfterSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let suffix = ProcessInfo.processInfo.environment["KURO_DC_SUFFIX"] ?? ""

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-dc-after", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/discover-clubs-2026-11-03/after")
    }()

    // MARK: Content

    @Test("Discover: All / Anime / Manga, top and full page, at 390, 320 and the iPad column")
    func content() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: Self.responder())
        await harness.signIn()
        let graph = harness.graph
        let monitor = NetworkMonitor()

        for issue in EditorialDiscoverView.DiscoverMediaTypeFilter.allCases {
            let file = issue.rawValue.lowercased()
            let canvas = issue == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome
            let top = Self.window(Self.page(issue, graph: graph, monitor: monitor, canvas: canvas), width: 390, height: 844)
            try? await Task.sleep(for: .milliseconds(2_200))
            await capture(top, name: "discover-\(file)-top-390")
            Self.close(top)

            let tall = Self.window(Self.page(issue, graph: graph, monitor: monitor, canvas: canvas), width: 390, height: 4_400)
            try? await Task.sleep(for: .milliseconds(2_400))
            let height = Self.contentHeight(in: tall)
            Self.measure("discover-\(file)-full-390", height)
            await capture(tall, name: "discover-\(file)-full-390", height: height)
            Self.close(tall)
        }

        // 320 (SE): column 288, gutter 16.
        let se = Self.window(Self.page(.all, graph: graph, monitor: monitor), width: 320, height: 700)
        try? await Task.sleep(for: .milliseconds(2_000))
        await capture(se, name: "discover-all-top-320")
        Self.close(se)
        let seTall = Self.window(Self.page(.all, graph: graph, monitor: monitor), width: 320, height: 4_400)
        try? await Task.sleep(for: .milliseconds(2_200))
        let seHeight = Self.contentHeight(in: seTall)
        Self.measure("discover-all-full-320", seHeight)
        await capture(seTall, name: "discover-all-full-320", height: seHeight)
        Self.close(seTall)
        let seManga = Self.window(Self.page(.manga, graph: graph, monitor: monitor, canvas: .kuroCanvasHomeManga),
                                  width: 320, height: 700)
        try? await Task.sleep(for: .milliseconds(2_000))
        await capture(seManga, name: "discover-manga-top-320")
        Self.close(seManga)

        // iPad: the readable 680 column inside an 820 pt window, the canvas full width.
        let pad = Self.window(AnyView(Self.page(.all, graph: graph, monitor: monitor).environment(\.horizontalSizeClass, .regular)),
                              width: 820, height: 1_180)
        try? await Task.sleep(for: .milliseconds(2_200))
        await capture(pad, name: "discover-all-top-ipad")
        Self.close(pad)

        // The fold opened (session memory, F3).
        let folds = KuroFoldMemory()
        folds.setExpanded(true, page: DiscoverIssueCopy.foldPage, section: DiscoverIssueCopy.foldSection)
        let fold = Self.window(AnyView(Self.page(.all, graph: graph, monitor: monitor).environment(\.kuroFoldMemory, folds)),
                               width: 390, height: 9_500)
        try? await Task.sleep(for: .milliseconds(2_600))
        let foldHeight = Self.contentHeight(in: fold)
        Self.measure("discover-all-fold-open-full-390", foldHeight)
        await capture(fold, name: "discover-all-fold-open-full-390", height: foldHeight)
        Self.close(fold)

        // Offline band over earlier content.
        let offlineMonitor = NetworkMonitor()
        try? await Task.sleep(for: .milliseconds(300))
        offlineMonitor.isConnected = false
        let offline = Self.window(Self.page(.all, graph: graph, monitor: offlineMonitor), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_600))
        offlineMonitor.isConnected = false
        try? await Task.sleep(for: .milliseconds(300))
        await capture(offline, name: "discover-offline-with-content-390")
        Self.close(offline)
        await harness.tearDown()
    }

    @Test("Discover: the series world (Browse offered) and the flag-gated rails")
    func flagged() async throws {
        await Self.seedArtwork()
        let series = try DCDiscoverHarness(responder: Self.responder(),
                                           launchArguments: ["--ff-on=taste_deck_v1", "--ff-on=series_foundation_v1",
                                                             "--ff-on=series_home_native_v1"])
        await series.signIn(hydrateFoundation: true)
        #expect(DiscoverBrowseEntry.isOffered(flags: series.graph.flags))
        let top = Self.window(Self.page(.all, graph: series.graph, monitor: NetworkMonitor()), width: 390, height: 1_300)
        try? await Task.sleep(for: .milliseconds(2_200))
        await capture(top, name: "discover-all-browse-offered-390")
        Self.close(top)
        await series.tearDown()

        let realm = try DCDiscoverHarness(responder: Self.responder(realm: true),
                                          launchArguments: ["--ff-on=discover_realm_rails_v1", "--ff-on=personalized_new_to_you_v1",
                                                            "--ff-on=social_activity_v1"])
        await realm.signIn()
        let tall = Self.window(Self.page(.all, graph: realm.graph, monitor: NetworkMonitor()), width: 390, height: 5_200)
        try? await Task.sleep(for: .milliseconds(2_800))
        let height = Self.contentHeight(in: tall)
        Self.measure("discover-all-realm-full-390", height)
        await capture(tall, name: "discover-all-realm-full-390", height: height)
        Self.close(tall)
        await realm.tearDown()
    }

    @Test("Discover: tracked titles (Planned key face, On your list key and mark) at 390")
    func tracked() async throws {
        await Self.seedArtwork()
        let backend = FakeLibraryBackend()
        backend.setRows([
            FakeLibraryBackend.entry(.anime, 402, rowId: 402, status: .planning, progress: 0, verdict: nil),
            FakeLibraryBackend.entry(.anime, 403, rowId: 403, status: .current, progress: 7, verdict: nil),
            FakeLibraryBackend.entry(.anime, 405, rowId: 405, status: .planning, progress: 0, verdict: nil)
        ], for: LifecycleFixtures.userA)
        let harness = try DCDiscoverHarness(responder: Self.responder(), libraryBackend: backend)
        await harness.signIn()
        try? await harness.graph.library.refresh()
        let window = Self.window(Self.page(.all, graph: harness.graph, monitor: NetworkMonitor()), width: 390, height: 2_000)
        try? await Task.sleep(for: .milliseconds(2_400))
        await capture(window, name: "discover-all-tracked-390")
        Self.close(window)
        await harness.tearDown()
    }

    // MARK: States

    @Test("Discover: loading, empty (both worlds), offline and failed first load")
    func states() async throws {
        let gate = StubGate()
        let held = try DCDiscoverHarness(responder: { request in
            switch request.resource ?? "" {
            case "rpc/discover_bundle": return StubResponse.json(Self.bundleJSON()).held(by: gate)
            case "rpc/fetch_daily_feature": return StubResponse.json("[]").held(by: gate)
            default: return .emptyArray
            }
        })
        await held.signIn()
        let loading = Self.window(Self.page(.all, graph: held.graph, monitor: NetworkMonitor()), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_200))
        await capture(loading, name: "discover-loading-390")
        Self.close(loading)
        gate.open()
        await held.tearDown()

        for (world, args) in [("", [String]()),
                              ("-browse-offered", ["--ff-on=taste_deck_v1", "--ff-on=series_foundation_v1",
                                                   "--ff-on=series_home_native_v1"])] {
            let empty = try DCDiscoverHarness(responder: Self.responder(bundle: Self.emptyBundleJSON(), feature: "[]"),
                                              launchArguments: args)
            await empty.signIn(hydrateFoundation: !args.isEmpty)
            let window = Self.window(Self.page(.all, graph: empty.graph, monitor: NetworkMonitor()), width: 390, height: 844)
            try? await Task.sleep(for: .milliseconds(1_800))
            await capture(window, name: "discover-empty\(world)-390")
            Self.close(window)
            await empty.tearDown()
        }

        let offline = try DCDiscoverHarness(responder: { _ in .failure(.notConnectedToInternet) })
        await offline.signIn()
        let monitor = NetworkMonitor()
        try? await Task.sleep(for: .milliseconds(300))
        monitor.isConnected = false
        let offlineWindow = Self.window(Self.page(.all, graph: offline.graph, monitor: monitor), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_800))
        monitor.isConnected = false
        try? await Task.sleep(for: .milliseconds(300))
        await capture(offlineWindow, name: "discover-offline-390")
        Self.close(offlineWindow)
        await offline.tearDown()

        let failed = try DCDiscoverHarness(responder: { _ in ClubJSON.error(message: "boom", code: "XX000", status: 500) })
        await failed.signIn()
        let failedWindow = Self.window(Self.page(.all, graph: failed.graph, monitor: NetworkMonitor()), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_800))
        await capture(failedWindow, name: "discover-failed-390")
        Self.close(failedWindow)
        await failed.tearDown()
    }

    @Test("Discover: See all as a journey page on the warm canvas")
    func seeAll() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: { _ in .emptyArray })
        await harness.signIn()
        let items = Self.animeCards()
        let title = EditorialDiscoverRoute.animeTrending.title(german: KuroLocale.isGerman, reason: nil)
        let navigator = JourneyNavigator(root: .seeAll(AnyJourneyPage(id: DiscoverSeeAllPolicy.pageID(.animeTrending), title: title) {
            FullSectionView(title: title, items: items)
        }))
        let window = Self.window(Self.inject(JourneyHost(navigator: navigator), graph: harness.graph, monitor: NetworkMonitor(),
                                             routes: false), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_600))
        await capture(window, name: "discover-see-all-top-390")
        Self.close(window)
        await harness.tearDown()
    }

    // MARK: Hosting

    /// The page as the pager shows it: the issue held outside (as `KuroMainView` does) and the canvas
    /// the header paints behind it.
    private static func page(_ issue: EditorialDiscoverView.DiscoverMediaTypeFilter, graph: AppGraph, monitor: NetworkMonitor,
                             canvas: Color? = nil) -> AnyView {
        inject(EditorialDiscoverView(issue: .constant(issue)).background(canvas ?? Color.kuroCanvasHome),
               graph: graph, monitor: monitor)
    }

    private static func inject<V: View>(_ view: V, graph: AppGraph, monitor: NetworkMonitor, routes: Bool = true) -> AnyView {
        let base = view
            .environment(graph.identity)
            .environment(graph.auth)
            .environment(graph.session)
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(graph.home)
            .environment(graph.catalog)
            .environment(graph.search)
            .environment(graph.discovery)
            .environment(graph.recommendations)
            .environment(graph.releases)
            .environment(graph.social)
            .environment(graph.availability)
            .environment(graph.clubs)
            .environment(graph.collection)
            .environment(graph.imports)
            .environment(graph.concierge)
            .environment(graph.taste)
            .environment(graph.deviceIntelligence)
            .environment(graph.support)
            .environment(graph.banner)
            .environment(graph.flags)
            .environment(graph.interactionTelemetry)
            .environment(graph.outboundLinks)
            .environment(graph.artworkMaterials)
            .environment(monitor)
        return routes ? AnyView(base.environment(\.kuroRoutes, KuroRoutes.unhandled)) : AnyView(base)
    }

    private static func window(_ view: AnyView, width: CGFloat, height: CGFloat) -> UIWindow {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        host.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.isHidden = false
        window.makeKey()
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = .white
        host.view.layoutIfNeeded()
        return window
    }

    private static func close(_ window: UIWindow) {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
    }

    /// The page's scroll content height (the window's own height when nothing scrolls).
    private static func contentHeight(in window: UIWindow) -> CGFloat {
        window.layoutIfNeeded()
        var best: CGFloat = 0
        var stack: [UIView] = [window]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.window != nil, !scroll.isHidden,
               scroll.bounds.width >= window.bounds.width * 0.6 {
                best = max(best, scroll.contentSize.height)
            }
            stack.append(contentsOf: view.subviews)
        }
        return best > 0 ? min(ceil(best), window.bounds.height) : window.bounds.height
    }

    private static func measure(_ name: String, _ height: CGFloat) {
        #if DEBUG
        print("DCMEASURE: \(name)\(suffix) content height \(Int(height)) pt")
        #endif
    }

    private func capture(_ window: UIWindow, name: String, height: CGFloat? = nil) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        window.layoutIfNeeded()
        let size = CGSize(width: window.bounds.width, height: height ?? window.bounds.height)
        guard let data = FixtureRaster.png(of: window, size: size, diagnosticScale: nil) else {
            Issue.record("\(name): PNG encoding failed")
            return
        }
        do {
            try data.write(to: Self.outDir.appendingPathComponent("\(name)\(Self.suffix).png"))
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
    }

    // MARK: Artwork

    private static let artFiles: [String] = [
        "anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg", "anime0-banner.jpg", "anime1-banner.jpg", "anime3-banner.jpg",
        "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg", "manga0-banner.jpg", "manga1-banner.jpg", "manga3-banner.jpg",
        "journal-anime-12-cover.jpg", "journal-anime-16-cover.jpg", "journal-anime-22-cover.jpg", "journal-anime-22-banner.jpg",
        "journal-anime-15-banner.jpg", "journal-manga-13-cover.jpg", "journal-manga-16-cover.jpg", "journal-manga-23-cover.jpg"
    ]

    nonisolated static func art(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: art(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }

    // MARK: Fixtures

    nonisolated private static func responder(bundle: String? = nil, feature: String? = nil, realm: Bool = false) -> StubServer.Responder {
        let bundleJSON = bundle ?? bundleJSON()
        let featureJSON = feature ?? dailyFeatureJSON()
        let slots = airingSlotsJSON(now: Date())
        return { request in
            switch request.resource ?? "" {
            case "rpc/discover_bundle": return .json(bundleJSON)
            case "rpc/fetch_daily_feature": return .json(featureJSON)
            case "anime": return .json(slots)
            case "rpc/fetch_tonight_shelf": return realm ? .json(tonightShelfJSON()) : .emptyArray
            case "rpc/fetch_realm_hidden_gem": return realm ? .json(hiddenGemJSON()) : .emptyArray
            case "rpc/fetch_because_you_rail": return realm ? .json(becauseYouJSON()) : .emptyArray
            default: return .emptyArray
            }
        }
    }

    nonisolated private static func dailyFeatureJSON() -> String {
        """
        [{"media_type":"ANIME","media_id":402,"title":"Mushishi","cover_image_large":"\(art("journal-anime-12-cover.jpg"))",
          "banner_image":"\(art("journal-anime-22-banner.jpg"))","genres":["Mystery","Slice of Life"],"score":87,"year":2005,
          "format":"TV","argument":"Quiet, strange and kind: ten-minute stories that stay with you for days."}]
        """
    }

    /// Stated slots for two of today's titles: one later today (Berlin), one earlier today.
    nonisolated private static func airingSlotsJSON(now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let later = now.addingTimeInterval(45 * 60)
        let next = calendar.isDate(later, inSameDayAs: now) ? later : now.addingTimeInterval(-90 * 60)
        let earlier = now.addingTimeInterval(-60 * 60)
        let past = calendar.isDate(earlier, inSameDayAs: now) ? earlier : now
        let formatter = ISO8601DateFormatter()
        return """
        [{"id":405,"next_airing_at":"\(formatter.string(from: next))","next_episode_number":7},
         {"id":407,"next_airing_at":"\(formatter.string(from: past))","next_episode_number":4}]
        """
    }

    nonisolated private static let animeSeeds: [(Int, String, String, String?, Int?, String, Int, Int)] = [
        (401, "Frieren: Beyond Journey's End", "anime2.jpg", "anime0-banner.jpg", 28, "FINISHED", 2023, 91),
        (402, "Mushishi", "journal-anime-12-cover.jpg", "journal-anime-22-banner.jpg", 26, "FINISHED", 2005, 87),
        (403, "Attack on Titan", "anime0.jpg", "anime0-banner.jpg", 25, "FINISHED", 2013, 85),
        (404, "Demon Slayer", "anime1.jpg", "anime1-banner.jpg", 26, "FINISHED", 2019, 84),
        (405, "Mob Psycho 100", "anime3.jpg", "anime3-banner.jpg", 12, "FINISHED", 2016, 86),
        (406, "Cowboy Bebop", "journal-anime-16-cover.jpg", nil, 26, "FINISHED", 1998, 88),
        (407, "Dandadan", "journal-anime-22-cover.jpg", "journal-anime-15-banner.jpg", 12, "RELEASING", 2024, 83),
        (408, "Die sehr lange Geschichte eines wandernden Schwertes im Herbst", "anime2.jpg", nil, nil, "RELEASING", 2026, 79)
    ]

    nonisolated private static let mangaSeeds: [(Int, String, String, Int?, String, Int, Int)] = [
        (501, "Chainsaw Man", "manga0.jpg", 120, "RELEASING", 2018, 86),
        (502, "Solo Leveling", "manga1.jpg", 200, "FINISHED", 2018, 84),
        (503, "Berserk", "manga2.jpg", nil, "RELEASING", 1989, 93),
        (504, "Vagabond", "manga3.jpg", 327, "HIATUS", 1998, 92),
        (505, "Goodnight Punpun", "journal-manga-13-cover.jpg", 147, "FINISHED", 2007, 90),
        (506, "Monster", "journal-manga-16-cover.jpg", 162, "FINISHED", 1994, 91),
        (507, "Blue Period", "journal-manga-23-cover.jpg", nil, "RELEASING", 2017, 85)
    ]

    nonisolated private static func animeRow(_ seed: (Int, String, String, String?, Int?, String, Int, Int)) -> String {
        let banner = seed.3.map { "\"\(art($0))\"" } ?? "null"
        let episodes = seed.4.map(String.init) ?? "null"
        return """
        {"id":\(seed.0),"title_english":"\(seed.1)","title_romaji":null,"title_native":null,
         "cover_image_large":"\(art(seed.2))","cover_image_medium":"\(art(seed.2))","banner_image":\(banner),
         "format":"TV","status":"\(seed.5)","episode_count":\(episodes),"season_year":\(seed.6),"start_date_year":\(seed.6),
         "average_score":\(seed.7),"popularity":120000,"trending":40,"favourites":9000,"genres":["Drama","Fantasy"],"rank":null}
        """
    }

    nonisolated private static func mangaRow(_ seed: (Int, String, String, Int?, String, Int, Int)) -> String {
        let chapters = seed.3.map(String.init) ?? "null"
        return """
        {"id":\(seed.0),"title_english":"\(seed.1)","title_romaji":null,"title_native":null,
         "cover_image_large":"\(art(seed.2))","cover_image_medium":"\(art(seed.2))",
         "format":"MANGA","status":"\(seed.4)","chapter_count":\(chapters),"start_date_year":\(seed.5),
         "average_score":\(seed.6),"popularity":90000,"trending":30,"favourites":7000,"genres":["Seinen"],"rank":null}
        """
    }

    nonisolated private static func animeRail(rotate: Int) -> String {
        "[" + Array(animeSeeds[rotate...] + animeSeeds[..<rotate]).map(animeRow).joined(separator: ",") + "]"
    }

    nonisolated private static func mangaRail(rotate: Int) -> String {
        "[" + Array(mangaSeeds[rotate...] + mangaSeeds[..<rotate]).map(mangaRow).joined(separator: ",") + "]"
    }

    /// The audit's "before" bundle (same rails, same rotations), so before and after compare directly.
    nonisolated static func bundleJSON() -> String {
        """
        {"anime":{"essentials":\(animeRail(rotate: 0)),"classics":\(animeRail(rotate: 5)),
                  "new_to_you":\(animeRail(rotate: 2)),"trending":\(animeRail(rotate: 3)),
                  "top_rated":\(animeRail(rotate: 1)),"newly_added":\(animeRail(rotate: 6)),
                  "airing_today":\(animeRail(rotate: 6)),"current_season":\(animeRail(rotate: 4))},
         "manga":{"essentials":\(mangaRail(rotate: 0)),"classics":\(mangaRail(rotate: 3)),
                  "new_to_you":\(mangaRail(rotate: 1)),"trending":\(mangaRail(rotate: 2)),
                  "top_rated":\(mangaRail(rotate: 4)),"newly_added":\(mangaRail(rotate: 5))}}
        """
    }

    nonisolated static func emptyBundleJSON() -> String {
        """
        {"anime":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],"newly_added":[],
                  "airing_today":[],"current_season":[]},
         "manga":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],"newly_added":[]}}
        """
    }

    nonisolated private static func tonightShelfJSON() -> String {
        let rows = animeSeeds.prefix(6).map { seed in
            """
            {"realm":"quiet","display_name":"Quiet hours","blurb":"Soft, slow stories for late at night.",
             "media_type":"ANIME","media_id":\(seed.0 + 100),"title":"\(seed.1)","cover_image_large":"\(art(seed.2))",
             "cover_image_medium":"\(art(seed.2))","cover_image_color":null,"genres":["Drama"],"average_score":\(seed.7),
             "format":"TV","year":\(seed.6),"synopsis":null,"episodes":\(seed.4.map(String.init) ?? "null"),"chapters":null,"volumes":null}
            """
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    nonisolated private static func hiddenGemJSON() -> String {
        """
        [{"realm":"quiet","display_name":"Quiet hours","blurb":null,"media_type":"ANIME","media_id":406,"title":"Cowboy Bebop",
          "cover_image_large":"\(art("journal-anime-16-cover.jpg"))","banner_image":"\(art("anime3-banner.jpg"))","genres":["Space"],
          "score":88,"year":1998,"format":"TV","argument":"A crew of bounty hunters, a ship called Bebop, and jazz."}]
        """
    }

    nonisolated private static func becauseYouJSON() -> String {
        let rows = animeSeeds.prefix(6).map { seed in
            """
            {"media_type":"ANIME","media_id":\(seed.0 + 200),"title":"\(seed.1)","cover_image_large":"\(art(seed.2))",
             "cover_image_medium":"\(art(seed.2))","cover_image_color":null,"genres":["Drama"],"average_score":\(seed.7),
             "format":"TV","year":\(seed.6),"synopsis":null,"episodes":\(seed.4.map(String.init) ?? "null"),"chapters":null,
             "volumes":null,"reason_title":"Frieren"}
            """
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    private static func animeCards() -> [AnimeCard] {
        let json = "[" + animeSeeds.map(animeRow).joined(separator: ",") + "]"
        return (try? JSONDecoder().decode([AnimeCard].self, from: Data(json.utf8))) ?? []
    }
}

/// A test graph over a stub PostgREST endpoint with chosen launch-argument flags.
@MainActor
struct DCDiscoverHarness {
    let server: StubServer
    let graph: AppGraph
    private let suiteName: String
    private let defaults: UserDefaults

    init(responder: @escaping StubServer.Responder, launchArguments: [String] = [],
         libraryBackend: (any LibraryBackend)? = nil) throws {
        server = StubServer()
        server.respond(with: responder)
        suiteName = "kuro.tests.dc-discover.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        graph = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: server),
            libraryBackend: libraryBackend,
            flags: FeatureFlags(userDefaults: defaults, launchArguments: launchArguments)
        )
    }

    func signIn(hydrateFoundation: Bool = false) async {
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        if hydrateFoundation { graph.flags.completeFoundationBootstrap(userId: LifecycleFixtures.userA) }
    }

    func tearDown() async {
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}
