import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// "After" renders of the Discover usability pass, lane A (the page; 2026-11-04). No network: every
/// graph runs over an in-process stub PostgREST endpoint with the usability fixture (`DUFixture`).
/// JPEGs (q 0.8, 1x, at most 603 px wide) go to `docs/discover-usability-2026-11-04/after/page-*.jpg`
/// only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; run it with
/// `-only-testing:KuroTests/DiscoverUsabilitySnapshotTests` so no other suite rewrites its evidence.
/// Ordinary runs render into a temporary folder. Page bodies only: the app header is not composed.
@Suite("Discover usability after renders (page)", .serialized, .timeLimit(.minutes(10)))
@MainActor
struct DiscoverUsabilitySnapshotTests {
    init() { DUFixture.clearHiddenMemory() }

    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-du-page-after", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/discover-usability-2026-11-04/after")
    }()

    // MARK: The page

    @Test("All: top, full page (end block), SE 320, accessibility XL; Anime and Manga full")
    func issues() async throws {
        await Self.seedArtwork()
        let backend = Self.trackedBackend()
        let harness = try DCDiscoverHarness(responder: DUFixture.responder(), libraryBackend: backend)
        await harness.signIn()
        try? await harness.graph.library.refresh()
        let visits = try Self.visitDefaults()

        let top = Self.window(Self.page(.all, harness: harness, visits: visits), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(2_400))
        await capture(top, name: "page-all-top-390")
        Self.close(top)

        for issue in EditorialDiscoverView.DiscoverMediaTypeFilter.allCases {
            let file = issue.rawValue.lowercased()
            let tall = Self.window(Self.page(issue, harness: harness, visits: visits), width: 390, height: 5_200)
            try? await Task.sleep(for: .milliseconds(2_600))
            let height = Self.contentHeight(in: tall)
            Self.measure("page-\(file)-full-390", height)
            // Usability spec §4 targets ≤ 2,300 pt for All at 390; the six sections with a Plan key on
            // every card measure more (recorded in DUMEASURE and reported as an open item, not asserted).
            await capture(tall, name: "page-\(file)-full-390", height: height)
            Self.close(tall)
        }

        let se = Self.window(Self.page(.all, harness: harness, visits: visits), width: 320, height: 700)
        try? await Task.sleep(for: .milliseconds(2_200))
        await capture(se, name: "page-all-top-320")
        Self.close(se)

        let xl = Self.window(AnyView(Self.page(.all, harness: harness, visits: visits)
                                        .environment(\.dynamicTypeSize, .accessibility2)), width: 390, height: 1_400)
        try? await Task.sleep(for: .milliseconds(2_400))
        await capture(xl, name: "page-all-top-390-ax2")
        Self.close(xl)

        await harness.tearDown()
    }

    @Test("iPad (regular width, the 680 pt readable column): All top and full, downscaled to 603 px")
    func iPadIssue() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: DUFixture.responder(), libraryBackend: Self.trackedBackend())
        await harness.signIn()
        try? await harness.graph.library.refresh()
        let visits = try Self.visitDefaults()
        let regular = AnyView(Self.page(.all, harness: harness, visits: visits)
                                .environment(\.horizontalSizeClass, .regular))
        let top = Self.window(regular, width: 820, height: 1_180)
        try? await Task.sleep(for: .milliseconds(2_600))
        await capture(top, name: "page-all-top-ipad", scaleToWidth: 603)
        Self.close(top)
        let tall = Self.window(AnyView(Self.page(.all, harness: harness, visits: visits)
                                        .environment(\.horizontalSizeClass, .regular)), width: 820, height: 5_200)
        try? await Task.sleep(for: .milliseconds(2_800))
        let height = Self.contentHeight(in: tall)
        await capture(tall, name: "page-all-full-ipad", height: height, scaleToWidth: 603)
        Self.close(tall)
        await harness.tearDown()
    }

    /// German renders: only in a run with `-testLanguage de -testRegion DE` (KuroLocale follows the
    /// process's preferred languages); an English run skips them, so it never overwrites them.
    @Test("German (de_DE): All full at 390 and 320, the contents and mood keys, Manga top")
    func germanIssue() async throws {
        guard KuroLocale.isGerman else { return }
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: DUFixture.responder(), libraryBackend: Self.trackedBackend())
        await harness.signIn()
        try? await harness.graph.library.refresh()
        let visits = try Self.visitDefaults()
        for width in [CGFloat(390), 320] {
            let tall = Self.window(Self.page(.all, harness: harness, visits: visits), width: width, height: 5_400)
            try? await Task.sleep(for: .milliseconds(2_600))
            let height = Self.contentHeight(in: tall)
            await capture(tall, name: "page-all-full-\(Int(width))-de", height: height)
            Self.close(tall)
        }
        let manga = Self.window(Self.page(.manga, harness: harness, visits: visits), width: 390, height: 1_400)
        try? await Task.sleep(for: .milliseconds(2_400))
        await capture(manga, name: "page-manga-top-390-de")
        Self.close(manga)
        await harness.tearDown()
    }

    @Test("All scrolled: the pinned index under the header and NEW marks on the second visit")
    func scrolledWithNew() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: DUFixture.responder(), libraryBackend: Self.trackedBackend())
        await harness.signIn()
        try? await harness.graph.library.refresh()
        let visits = try Self.visitDefaults()
        // The last visit (two days ago, two hours past the 30-minute rule) saw these sections without a
        // few of today's titles: those are NEW now.
        var ledger = DiscoverVisitLedger()
        let past = Date().addingTimeInterval(-2 * 86_400)
        ledger.commit(seen: [
            "animeNewToYou": [15, 20, 23, 25, 26].map { MediaKey(kind: .anime, id: $0) },
            "animeTrending": [4, 42, 17, 27, 6, 29, 44, 40, 39].map { MediaKey(kind: .anime, id: $0) },
            "animeEssentials": [1, 10, 9, 11, 7].map { MediaKey(kind: .anime, id: $0) }
        ], at: past)
        ledger.save(defaults: visits, userId: LifecycleFixtures.userA)

        let window = Self.window(Self.page(.all, harness: harness, visits: visits), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(2_400))
        await capture(window, name: "page-all-new-top-390")
        Self.scroll(window, to: 1_050)
        // Past the band's fade (settle, 220 ms) with room for the render loop.
        try? await Task.sleep(for: .milliseconds(400))
        Self.scroll(window, to: 1_050)
        try? await Task.sleep(for: .milliseconds(1_800))
        await capture(window, name: "page-all-scrolled-pinned-390")
        Self.scroll(window, to: 1_900)
        try? await Task.sleep(for: .milliseconds(900))
        await capture(window, name: "page-all-scrolled-end-390")
        Self.close(window)
        await harness.tearDown()
    }

    @Test("After a Not interested: the title is gone, its section refilled, the toast with Undo")
    func afterHide() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: DUFixture.responder())
        await harness.signIn()
        let visits = try Self.visitDefaults()
        // Odd Taxi (New to you's first trio cover) answered Not interested before the page builds.
        _ = harness.graph.taste.recordDiscoverFeedback(.notInterested, for: MediaKey(kind: .anime, id: 15))
        let window = Self.window(Self.page(.all, harness: harness, visits: visits), width: 390, height: 1_700)
        try? await Task.sleep(for: .milliseconds(2_400))
        await capture(window, name: "page-all-after-hide-390")
        Self.close(window)

        // The toast itself (one slot, D12), over the page foot.
        let page = DiscoverPageFeedback()
        let hides = DiscoverFeedbackController(holdSeconds: 600, assistiveTechnologyRunning: { true })
        let plans = TastePlanController(holdSeconds: 600, assistiveTechnologyRunning: { true })
        let card = try #require(DUFixture.animeCard(16))
        _ = hides.record(.seenIt, for: card.media, taste: harness.graph.taste, german: KuroLocale.isGerman)
        let host = Color.kuroCanvasHome.frame(height: 160).discoverPageHost(page, hides: hides, plans: plans)
        let toast = Self.window(Self.inject(host,
                                            graph: harness.graph, visits: visits), width: 390, height: 160)
        try? await Task.sleep(for: .milliseconds(600))
        await capture(toast, name: "page-toast-seen-390")
        Self.close(toast)
        await harness.tearDown()
        DUFixture.clearHiddenMemory()
    }

    @Test("Components: the Essentials hook, the end block, the mood keys without a seed, the contents")
    func components() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: { _ in .emptyArray })
        await harness.signIn()
        let visits = try Self.visitDefaults()
        let cards = DUFixture.cards("essentials")
        let model = DiscoverProgressModel.make(
            items: cards.map { ($0.key, $0.media.title) },
            status: { [1: ListStatus.completed, 10: .completed, 9: .current][$0.id] },
            hidden: { $0.id == 11 ? .seenIt : nil })
        let hook = DiscoverIndexSection(anchor: "e", title: "Essential anime.",
                                        purpose: DiscoverIssueCopy.purposeEssentials(count: cards.count, manga: false, german: KuroLocale.isGerman),
                                        cards: cards, total: cards.count, column: 350, hook: model, rowLimit: 5, onSeeAll: {})
        await render(hook, harness: harness, visits: visits, name: "page-essentials-hook-390")

        let end = DiscoverIssueEnd(sections: 6, titles: 38, planned: 2, hidden: 1, seen: 1, browseOffered: true,
                                   moreLists: [.init(id: "a", name: "Essential manga", action: {}),
                                               .init(id: "b", name: "Top rated", action: {}),
                                               .init(id: "c", name: "Just added", action: {})],
                                   onBrowse: {}, onSearch: {})
        await render(end, harness: harness, visits: visits, name: "page-end-block-390")

        let moods = DiscoverMoodKeys(kind: .anime, likeTitle: nil, column: 350, onOpen: { _ in })
        await render(moods, harness: harness, visits: visits, name: "page-moods-no-seed-390")
        let seeded = DiscoverMoodKeys(kind: .anime, likeTitle: "Frieren", column: 350, onOpen: { _ in })
        await render(seeded, harness: harness, visits: visits, name: "page-moods-390")

        let contents = DiscoverContentsLine(entries: [
            .init(id: "a", name: "New to you", count: 11, newCount: 2), .init(id: "b", name: "This season", count: 8),
            .init(id: "c", name: "Essential anime", count: 11), .init(id: "d", name: "Manga new to you", count: 16),
            .init(id: "e", name: "Trending", count: 11, newCount: 1), .init(id: "f", name: "Classics", count: 5)
        ], browseOffered: false, column: 350, onJump: { _ in }, onBrowse: {})
        await render(contents, harness: harness, visits: visits, name: "page-contents-390")
        await harness.tearDown()
    }

    @Test("States: loading, offline with content (band), offline first load, failed")
    func states() async throws {
        let gate = StubGate()
        let held = try DCDiscoverHarness(responder: { request in
            switch request.resource ?? "" {
            case "rpc/discover_bundle": return StubResponse.json(DUFixture.bundleJSON()).held(by: gate)
            default: return .emptyArray
            }
        })
        await held.signIn()
        let visits = try Self.visitDefaults()
        let loading = Self.window(Self.page(.all, harness: held, visits: visits), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_200))
        await capture(loading, name: "page-loading-390")
        Self.close(loading)
        gate.open()
        await held.tearDown()

        await Self.seedArtwork()
        let content = try DCDiscoverHarness(responder: DUFixture.responder())
        await content.signIn()
        let monitor = NetworkMonitor()
        let band = Self.window(Self.page(.all, harness: content, visits: visits, monitor: monitor), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(2_200))
        monitor.isConnected = false
        try? await Task.sleep(for: .milliseconds(400))
        await capture(band, name: "page-offline-with-content-390")
        Self.close(band)
        await content.tearDown()

        let offline = try DCDiscoverHarness(responder: { _ in .failure(.notConnectedToInternet) })
        await offline.signIn()
        let offlineMonitor = NetworkMonitor()
        offlineMonitor.isConnected = false
        let offlineWindow = Self.window(Self.page(.all, harness: offline, visits: visits, monitor: offlineMonitor), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_800))
        offlineMonitor.isConnected = false
        await capture(offlineWindow, name: "page-offline-390")
        Self.close(offlineWindow)
        await offline.tearDown()

        let failed = try DCDiscoverHarness(responder: { _ in ClubJSON.error(message: "boom", code: "XX000", status: 500) })
        await failed.signIn()
        let failedWindow = Self.window(Self.page(.all, harness: failed, visits: visits), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_800))
        await capture(failedWindow, name: "page-failed-390")
        Self.close(failedWindow)
        await failed.tearDown()
    }

    // MARK: Hosting

    /// Essentials with a hook: two Completed, one Watching (the anime fixture's ids 1, 10, 9).
    private static func trackedBackend() -> FakeLibraryBackend {
        let backend = FakeLibraryBackend()
        backend.setRows([
            FakeLibraryBackend.entry(.anime, 1, rowId: 1, status: .completed, progress: 25),
            FakeLibraryBackend.entry(.anime, 10, rowId: 10, status: .completed, progress: 64),
            FakeLibraryBackend.entry(.anime, 9, rowId: 9, status: .current, progress: 5),
            FakeLibraryBackend.entry(.anime, 43, rowId: 43, status: .planning, progress: 0)
        ], for: LifecycleFixtures.userA)
        return backend
    }

    private static func visitDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "kuro.tests.du-page-visits.\(UUID().uuidString)"))
    }

    private static func page(_ issue: EditorialDiscoverView.DiscoverMediaTypeFilter, harness: DCDiscoverHarness,
                             visits: UserDefaults, monitor: NetworkMonitor? = nil) -> AnyView {
        let canvas = issue == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome
        return inject(EditorialDiscoverView(issue: .constant(issue)).background(canvas),
                      graph: harness.graph, visits: visits, monitor: monitor ?? NetworkMonitor())
    }

    private static func inject<V: View>(_ view: V, graph: AppGraph, visits: UserDefaults,
                                        monitor: NetworkMonitor? = nil) -> AnyView {
        let monitor = monitor ?? NetworkMonitor()
        return AnyView(view
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
            .environment(\.discoverVisitDefaults, visits)
            .environment(\.scenePhase, .active)
            .environment(\.kuroRoutes, KuroRoutes.unhandled))
    }

    private func render<V: View>(_ view: V, harness: DCDiscoverHarness, visits: UserDefaults, name: String) async {
        let host = UIHostingController(rootView: Self.inject(view.padding(.horizontal, 20).padding(.vertical, 16)
                                                                .background(Color.kuroCanvasHome),
                                                             graph: harness.graph, visits: visits))
        let size = host.sizeThatFits(in: CGSize(width: 390, height: 4_000))
        let window = Self.window(Self.inject(view.padding(.horizontal, 20).padding(.vertical, 16).background(Color.kuroCanvasHome),
                                             graph: harness.graph, visits: visits),
                                 width: 390, height: max(80, ceil(size.height)))
        try? await Task.sleep(for: .milliseconds(900))
        await capture(window, name: name)
        Self.close(window)
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

    /// The page's vertical scroll view.
    private static func pageScroll(in window: UIWindow) -> UIScrollView? {
        var stack: [UIView] = [window]
        var best: UIScrollView?
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.bounds.width >= window.bounds.width * 0.6,
               scroll.contentSize.height > scroll.bounds.height {
                if best == nil || scroll.contentSize.height > (best?.contentSize.height ?? 0) { best = scroll }
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }

    private static func scroll(_ window: UIWindow, to y: CGFloat) {
        guard let scroll = pageScroll(in: window) else { return }
        let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: min(y, maxY)), animated: false)
        window.layoutIfNeeded()
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
        print("DUMEASURE: \(name) content height \(Int(height)) pt")
        #endif
    }

    /// JPEG q 0.8 at 1x (390 / 320 px wide, never above 603).
    private func capture(_ window: UIWindow, name: String, height: CGFloat? = nil, scaleToWidth: CGFloat? = nil) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        window.layoutIfNeeded()
        let size = CGSize(width: window.bounds.width, height: height ?? window.bounds.height)
        guard let png = FixtureRaster.png(of: window, size: size, diagnosticScale: nil),
              let raster = UIImage(data: png) else {
            Issue.record("\(name): encoding failed")
            return
        }
        // iPad renders: the 820 pt window drawn at 1x, then scaled down to the gallery's 603 px.
        var image = raster
        if let target = scaleToWidth, raster.size.width * raster.scale > target {
            let factor = target / (raster.size.width * raster.scale)
            let scaled = CGSize(width: target, height: (raster.size.height * raster.scale * factor).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            image = UIGraphicsImageRenderer(size: scaled, format: format).image { _ in
                raster.draw(in: CGRect(origin: .zero, size: scaled))
            }
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            Issue.record("\(name): encoding failed")
            return
        }
        #expect(image.size.width * image.scale <= 603, "\(name) is wider than 603 px")
        do {
            try jpeg.write(to: Self.outDir.appendingPathComponent("\(name).jpg"))
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
    }

    // MARK: Artwork

    private static let artFiles: [String] = [
        "anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg", "anime0-banner.jpg", "anime1-banner.jpg", "anime3-banner.jpg",
        "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg",
        "journal-anime-12-cover.jpg", "journal-anime-16-cover.jpg", "journal-anime-22-cover.jpg", "journal-anime-22-banner.jpg",
        "journal-anime-15-banner.jpg", "journal-manga-13-cover.jpg", "journal-manga-16-cover.jpg", "journal-manga-23-cover.jpg"
    ]

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: DUFixture.art(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }
}
