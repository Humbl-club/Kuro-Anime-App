import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Fixture renders of the first-run lane (plan Task 8) for the side-by-side fidelity check against
/// `docs/prototype-fidelity/reference/ref-home-new-*` and `ref-taste-*`. No network: a nil client, a
/// fake Library backend, the Discover bundle seeded into `DiscoveryStore`'s cache, and the prototype's
/// own artwork seeded into `URLCache`. Committed PNGs are rewritten only with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; ordinary runs render into a temporary folder.
@Suite("First-run snapshots", .serialized, .timeLimit(.minutes(3)))
@MainActor
struct FirstRunSnapshotTests {
    private static let repo: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-firstrun", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/firstrun")
    }()

    // MARK: New-account Home

    @Test("New-account Home, anime and manga, at 320/390/430 (with and without starter picks)")
    func newAccountHome() async throws {
        await Self.seedArtwork()
        let (graph, defaults) = try await Self.signedInGraph("firstrun-home")
        for medium in [MediaKind.anime, .manga] {
            let picks = Self.cards(medium, premise: false).prefix(HomeNewAccountCopy.pickCount(medium))
            for width: CGFloat in [320, 390, 430] {
                await render(Self.homeNewPage(medium: medium, picks: Array(picks), width: width)
                                .environment(graph.library)
                                .environment(graph.libraryActions),
                             width: width, height: medium == .anime ? 1_560 : 1_880,
                             name: "home-new-\(medium.rawValue)-\(Int(width)).png", settle: 1_400)
            }
            await render(Self.homeNewPage(medium: medium, picks: [], width: 390)
                            .environment(graph.library)
                            .environment(graph.libraryActions),
                         width: 390, height: 844,
                         name: "home-new-\(medium.rawValue)-prototype-block-390.png", settle: 600)
        }
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-home")
        note("Home new: the KURO header, the medium switch's two-column grid with the art-filled word, the opening line (HomeOpeningLine, Task 4) and the page footer (HomeFooter, Task 5) belong to other lanes. The harness stands them in with KuroMediumSwitch(.large, material: nil), the Taste opening row (YOUR COLLECTION / Begin here.) and the Taste footer; no header is drawn. Only the block under the opening line is HomeNewAccount.")
    }

    @Test("New-account Home through its own loader (seeded Discover bundle)")
    func newAccountHomeLive() async throws {
        await Self.seedArtwork()
        let (graph, defaults) = try await Self.signedInGraph("firstrun-home-live")
        for medium in [MediaKind.anime, .manga] {
            await render(
                ScrollView {
                    HomeNewAccount(medium: medium, onImport: {}, onExploreTaste: {})
                }
                .background(TastePageContent.canvas(for: medium))
                .environment(graph.discovery)
                .environment(graph.library)
                .environment(graph.libraryActions)
                .environment(\.kuroRoutes, KuroRoutes.unhandled),
                width: 390, height: medium == .anime ? 1_200 : 1_500,
                name: "home-new-\(medium.rawValue)-loader-390.png", settle: 1_600
            )
        }
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-home-live")
    }

    // MARK: Taste

    @Test("Taste busy and new account, anime and manga, at 390; loading; the live page with a seeded bundle")
    func taste() async throws {
        await Self.seedArtwork()
        let (graph, defaults) = try await Self.signedInGraph("firstrun-taste")
        for medium in [MediaKind.anime, .manga] {
            for newAccount in [false, true] {
                // Busy: personal picks (because-you rows carry a synopsis). New: bundle picks (no synopsis).
                let cards = Array(Self.cards(medium, premise: !newAccount).prefix(2))
                await render(
                    Self.tastePage(medium: medium, state: .cards(cards), newAccount: newAccount, width: 390)
                        .environment(graph.library)
                        .environment(graph.libraryActions),
                    width: 390, height: 844,
                    name: "taste-\(newAccount ? "new" : "busy")-\(medium.rawValue)-390.png", settle: 1_400
                )
            }
            await render(
                Self.tastePage(medium: medium, state: .loading, newAccount: false, width: 390)
                    .environment(graph.library)
                    .environment(graph.libraryActions),
                width: 390, height: 844, name: "taste-loading-\(medium.rawValue)-390.png", settle: 400
            )
        }
        // A planned card: the dark key face.
        let planned = Self.cards(.anime, premise: true)[1]
        graph.backendForFixtures?.setRows([FakeLibraryBackend.entry(.anime, planned.media.id, rowId: 1, status: .planning,
                                                                   progress: 0)], for: LifecycleFixtures.userA)
        try? await graph.library.refresh()
        await render(
            Self.tastePage(medium: .anime, state: .cards(Array(Self.cards(.anime, premise: true).prefix(2))),
                           newAccount: false, width: 390)
                .environment(graph.library)
                .environment(graph.libraryActions),
            width: 390, height: 844, name: "taste-busy-anime-planned-390.png", settle: 1_400
        )
        graph.backendForFixtures?.setRows([], for: LifecycleFixtures.userA)
        try? await graph.library.refresh()

        // The real page: TastePicksView over the seeded bundle (the because-you read fails with no client,
        // so the bundle's NEW TO YOU picks stand in; the account is new, so "A first favourite.").
        await render(
            TastePicksView()
                .environment(graph.discovery)
                .environment(graph.library)
                .environment(graph.libraryActions)
                .environment(graph.artworkMaterials)
                .environment(NetworkMonitor())
                .environment(\.kuroRoutes, KuroRoutes.unhandled),
            width: 390, height: 1_200, name: "taste-live-new-anime-390.png", settle: 1_800
        )
        note("Taste: the busy fixtures carry a one-sentence premise as a because-you row would (its synopsis); the new-account fixtures are Discover bundle rows, which carry no synopsis, so no premise is drawn (never a placeholder). Taste's medium switch is KuroMediumSwitch(.large) filled with the first pick's ArtworkMaterial (gradient), not the prototype's artwork clipped into the letters, and its words sit side by side rather than in the prototype's two-column grid (Task 4 owns the switch).")
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-taste")
    }

    // MARK: Collection and Search

    @Test("Collection empty invitation and Search with no history, at 390")
    func collectionAndSearch() async throws {
        let copyGerman = KuroLocale.isGerman
        await render(
            ScrollView {
                VStack(spacing: 0) {
                    KuroMediumSwitch(selection: .constant(.anime), size: .compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, KuroDesignSpacing.padding)
                        .padding(.top, KuroDesignSpacing.sm)
                    FirstRunInvitation(headline: HomeNewAccountCopy.headline(german: copyGerman),
                                       line: HomeNewAccountCopy.line(german: copyGerman)) {
                        KuroOutlineButton(HomeNewAccountCopy.importList(german: copyGerman)) {}
                        KuroOutlineButton(copyGerman ? "Titel finden" : "Find a title") {}
                    }
                }
            }
            .background(Color.kuroBackground),
            width: 390, height: 700, name: "collection-empty-invitation-390.png"
        )
        note("Collection empty: the invitation block as EditorialCollectionView.libraryInvitation composes it (FirstRunInvitation + Import / Find a title), under a compact switch. The full page is not hosted: its feed read needs the network, and with no client it resolves to the failed state, not the invitation.")

        guard let defaults = UserDefaults(suiteName: "firstrun-search") else { return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        await render(
            EditorialSearchView()
                .environment(graph.banner)
                .environment(graph.search)
                .environment(graph.discovery)
                .environment(NetworkMonitor())
                .environment(graph.flags)
                .environment(graph.library)
                .environment(graph.libraryActions)
                .environment(graph.clubs)
                .environment(\.kuroRoutes, KuroRoutes.unhandled),
            width: 390, height: 844, name: "search-no-history-390.png", settle: 1_000
        )
        defaults.removePersistentDomain(forName: "firstrun-search")
    }

    // MARK: Compositions

    private static func homeNewPage(medium: MediaKind, picks: [TasteCard], width: CGFloat) -> some View {
        let german = KuroLocale.isGerman
        return ScrollView {
            VStack(spacing: 0) {
                TasteOpening(medium: .constant(medium), material: nil, metrics: TasteMetrics(pageWidth: width),
                             kicker: german ? "DEINE SAMMLUNG" : "YOUR COLLECTION",
                             headline: german ? "Fang hier an." : "Begin here.")
                HomeNewAccountContent(medium: medium, picks: picks, width: width, onImport: {}, onExploreTaste: {})
                TasteFooter()
            }
        }
        .background(TastePageContent.canvas(for: medium))
        .environment(\.kuroRoutes, KuroRoutes.unhandled)
    }

    private static func tastePage(medium: MediaKind, state: TastePageContent.State, newAccount: Bool,
                                  width: CGFloat) -> some View {
        ScrollView {
            TastePageContent(medium: .constant(medium), state: state, newAccount: newAccount,
                             material: nil, width: width)
        }
        .background(TastePageContent.canvas(for: medium))
        .environment(\.kuroRoutes, KuroRoutes.unhandled)
    }

    // MARK: Fixtures

    private static func artURL(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static let artFiles = ["journal-anime-15-banner.jpg", "journal-anime-15-cover.png",
                                   "journal-anime-16-cover.jpg", "anime1.jpg",
                                   "journal-manga-16-cover.jpg", "journal-manga-23-cover.jpg",
                                   "manga0.jpg", "manga1.jpg"]

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: artURL(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": file.hasSuffix(".png") ? "image/png" : "image/jpeg"])
            else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }

    private struct Fixture {
        let id: Int
        let title: String
        let cover: String
        let banner: String?
        let format: String
        let genre: String
        let premise: String
    }

    private static let animeFixtures: [Fixture] = [
        Fixture(id: 15, title: "Your Name.", cover: "journal-anime-15-cover.png", banner: "journal-anime-15-banner.jpg",
                format: "MOVIE", genre: "Romance", premise: "Two strangers wake up in each other’s lives."),
        Fixture(id: 16, title: "A Silent Voice", cover: "journal-anime-16-cover.jpg", banner: nil,
                format: "MOVIE", genre: "Drama", premise: "A former bully seeks forgiveness from the deaf girl he hurt."),
        Fixture(id: 101, title: "Demon Slayer", cover: "anime1.jpg", banner: nil,
                format: "TV", genre: "Action", premise: "A boy hunts demons to save his sister.")
    ]

    private static let mangaFixtures: [Fixture] = [
        Fixture(id: 16, title: "Vinland Saga", cover: "journal-manga-16-cover.jpg", banner: nil,
                format: "MANGA", genre: "Historical", premise: "A young Viking dreams of a land beyond war."),
        Fixture(id: 23, title: "Dandadan", cover: "journal-manga-23-cover.jpg", banner: nil,
                format: "MANGA", genre: "Supernatural", premise: "Two teens test their beliefs in ghosts and aliens."),
        Fixture(id: 10, title: "Chainsaw Man", cover: "manga0.jpg", banner: nil,
                format: "MANGA", genre: "Action", premise: "A broke devil hunter makes a deal."),
        Fixture(id: 11, title: "Solo Leveling", cover: "manga1.jpg", banner: nil,
                format: "MANGA", genre: "Fantasy", premise: "The weakest hunter gets a second chance.")
    ]

    private static func cards(_ medium: MediaKind, premise: Bool) -> [TasteCard] {
        (medium == .anime ? animeFixtures : mangaFixtures).map { fixture in
            TasteCard(
                media: Media(id: fixture.id, kind: medium, title: fixture.title, imageURL: artURL(fixture.cover),
                             year: "2016", displayDescription: "", episodes: nil, chapters: nil, rating: nil,
                             genres: [fixture.genre], statusRaw: nil, formatRaw: fixture.format,
                             popularityValue: nil, trendingValue: nil, createdAtValue: nil),
                bannerURL: fixture.banner.map(artURL),
                premise: premise ? fixture.premise : nil
            )
        }
    }

    /// The Discover bundle as `discover_bundle` would return it, holding the fixtures as NEW TO YOU.
    private static func bundle() throws -> DiscoverBundle {
        func anime(_ fixture: Fixture) -> [String: Any] {
            var row: [String: Any] = ["id": fixture.id, "title_english": fixture.title, "format": fixture.format,
                                      "genres": [fixture.genre], "cover_image_large": artURL(fixture.cover)]
            if let banner = fixture.banner { row["banner_image"] = artURL(banner) }
            return row
        }
        func manga(_ fixture: Fixture) -> [String: Any] {
            ["id": fixture.id, "title_english": fixture.title, "format": fixture.format,
             "genres": [fixture.genre], "cover_image_large": artURL(fixture.cover)]
        }
        let empty: [[String: Any]] = []
        let object: [String: Any] = [
            "anime": ["essentials": empty, "classics": empty, "new_to_you": animeFixtures.map(anime), "trending": empty,
                      "top_rated": empty, "newly_added": empty, "airing_today": empty, "current_season": empty],
            "manga": ["essentials": empty, "classics": empty, "new_to_you": mangaFixtures.map(manga), "trending": empty,
                      "top_rated": empty, "newly_added": empty]
        ]
        return try JSONDecoder().decode(DiscoverBundle.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// A signed-in graph whose Library loaded empty (a new account) and whose Discover bundle is cached.
    private static func signedInGraph(_ suite: String) async throws -> (FixtureGraph, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        let backend = FakeLibraryBackend()
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "new@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
        try? await graph.library.refresh()
        let key = DiscoveryStore.bundleKey(user: LifecycleFixtures.userA, limit: 30, hours: 24)
        graph.discovery.discoverBundleCache[key] = TimedCache(value: try bundle(), storedAt: Date())
        return (FixtureGraph(graph: graph, backend: backend), defaults)
    }

    /// The test graph plus its fake Library backend (to seed a planned row).
    @dynamicMemberLookup
    private struct FixtureGraph {
        let graph: AppGraph
        let backend: FakeLibraryBackend
        var backendForFixtures: FakeLibraryBackend? { backend }
        subscript<T>(dynamicMember path: KeyPath<AppGraph, T>) -> T { graph[keyPath: path] }
    }

    // MARK: Rendering

    @discardableResult
    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, settle: Int = 500) async -> Bool {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            note("\(name): could not create the output folder (\(error))")
            return false
        }
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        // The page sits under the app header in the pager: no device safe area in the fixture.
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = .white
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(settle))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let url = Self.outDir.appendingPathComponent(name)
        guard let data = image.pngData() else {
            note("\(name): PNG encoding failed")
            return false
        }
        do {
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
            return true
        } catch {
            note("\(name): write failed (\(error))")
            return false
        }
    }

    private func note(_ line: String) {
        let url = Self.outDir.appendingPathComponent("NOTES.txt")
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing.contains(line) { return }
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } else {
                try Data((line + "\n").utf8).write(to: url)
            }
        } catch {
            #if DEBUG
            print("FirstRun note failed: \(error)")
            #endif
        }
    }
}
