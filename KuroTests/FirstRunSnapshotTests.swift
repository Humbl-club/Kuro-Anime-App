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

    /// Committed PNGs are being rewritten. The AX5 renders change the process-wide `KuroTypeScale`
    /// for a moment, so they run only then, never in an ordinary (possibly concurrent) test run.
    private static let writing = ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1"

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-firstrun", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/firstrun")
    }()

    /// A device-pixel scale for diagnosis (`TEST_RUNNER_KURO_RENDER_SCALE=3`): the renders then go to a
    /// temporary folder and never replace the committed 1 px = 1 pt renders.
    static let diagnosticScale: CGFloat? = ProcessInfo.processInfo.environment["KURO_RENDER_SCALE"]
        .flatMap(Double.init).map { CGFloat($0) }
    static let diagnosticDir = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-render-scaled", isDirectory: true)

    // MARK: New-account Home

    @Test("New-account Home, anime and manga, at 320/390/430 (with and without starter picks)")
    func newAccountHome() async throws {
        await Self.seedArtwork()
        let (graph, defaults) = try await Self.signedInGraph("firstrun-home")
        for medium in [MediaKind.anime, .manga] {
            // Bundle rows (anime banner, no synopsis), completed by the catalogue read as the page does.
            let picks = await TasteCardDetails.hydrate(
                Array(Self.cards(medium, premise: false, banner: true).prefix(HomeNewAccountCopy.pickCount(medium))),
                catalog: graph.catalog)
            for width: CGFloat in [320, 390, 430] {
                #expect(await render(Self.homeNewPage(medium: medium, picks: picks, width: width)
                                        .environment(graph.library)
                                        .environment(graph.libraryActions),
                                     width: width, height: medium == .anime ? 1_560 : 1_880,
                                     name: "home-new-\(medium.rawValue)-\(Int(width)).png", settle: 1_400))
            }
            #expect(await render(Self.homeNewPage(medium: medium, picks: [], width: 390)
                                    .environment(graph.library)
                                    .environment(graph.libraryActions),
                                 width: 390, height: 844,
                                 name: "home-new-\(medium.rawValue)-prototype-block-390.png", settle: 600))
            // German and the largest accessibility text size.
            #expect(await render(Self.homeNewPage(medium: medium, picks: picks, width: 390, german: true)
                                    .environment(graph.library)
                                    .environment(graph.libraryActions)
                                    .environment(\.tasteGerman, true),
                                 width: 390, height: medium == .anime ? 1_560 : 1_880,
                                 name: "home-new-\(medium.rawValue)-de-390.png", settle: 1_400))
            if Self.writing {
                #expect(await renderAX5(Self.homeNewPage(medium: medium, picks: picks, width: 390)
                                       .environment(graph.library)
                                       .environment(graph.libraryActions),
                                    width: 390, height: 2_600,
                                    name: "home-new-\(medium.rawValue)-ax5-390.png"))
            }
        }
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-home")
    }

    @Test("New-account Home through the integrated HomeView (Task 10), anime and manga, at 320/390/430")
    func newAccountHomeView() async throws {
        await Self.seedArtwork()
        let (graph, defaults) = try await Self.signedInGraph("firstrun-homeview")
        // An empty Home page for both media (the account has nothing yet), the Library loaded empty and
        // the pager's latch set: HomeView draws its own new-account shelf (opening row + HomeNewAccount).
        func empty(_ medium: String) throws -> HomeBundle {
            try JSONDecoder().decode(HomeBundle.self, from: Data("""
            {"medium":"\(medium)","window_days":7,"home_revision":1,"active":[],"upcoming":[],"pending":[],
             "schedule_state":"ok","next_cursor":null,"club":{"state":"ready","label":"Between us.","items":[]}}
            """.utf8))
        }
        let materials = ArtworkMaterialStore(cacheDirectory: nil, loader: HomeAnimeLaneTests.fixtureLoader)
        for medium in [MediaKind.anime, .manga] {
            graph.home.seedForVisualQA(anime: try empty("anime"), manga: try empty("manga"), medium: medium.rawValue)
            #expect(graph.home.medium == medium.rawValue)
            for width: CGFloat in [390, 320, 430] {
                let url = Self.outDir.appendingPathComponent("home-new-\(medium.rawValue)-homeview-\(Int(width)).png")
                try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
                // The pager's canvas follows Home's medium (`KuroMainView.Section.canvas`).
                let canvas = TastePageContent.canvas(for: medium)
                try await HomeAnimeLaneTests.render(
                    HomeAnimeLaneTests.home(graph.graph, materials, canvas: canvas, newAccountLatch: true),
                    width: width, height: medium == .anime ? 1_700 : 2_000, to: url, canvas: canvas)
                #expect(FileManager.default.fileExists(atPath: url.path))
            }
        }
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-homeview")
    }

    @Test("Pager composites: the app header over the new-account Home and over Taste, anime and manga, at 390")
    func pagerComposites() async throws {
        await Self.seedArtwork()
        // The Series Home pager (Taste, Home, Discover, Collection, Clubs), as the references show it.
        let (graph, defaults) = try await Self.signedInGraph(
            "firstrun-pager", launchArguments: ["--ff-on=series_foundation_v1", "--ff-on=series_home_native_v1",
                                                "--ff-on=taste_deck_v1"])
        graph.flags.completeFoundationBootstrap(userId: LifecycleFixtures.userA)
        func empty(_ medium: String) throws -> HomeBundle {
            try JSONDecoder().decode(HomeBundle.self, from: Data("""
            {"medium":"\(medium)","window_days":7,"home_revision":1,"active":[],"upcoming":[],"pending":[],
             "schedule_state":"ok","next_cursor":null,"club":{"state":"ready","label":"Between us.","items":[]}}
            """.utf8))
        }
        let materials = ArtworkMaterialStore(cacheDirectory: nil, loader: HomeAnimeLaneTests.fixtureLoader)
        /// The pager's column: its canvas behind the header and the page (`Section.canvas`), the header
        /// (`KuroHeaderNew`, ContentView's) on top, the page under it.
        func pager<Page: View>(_ section: KuroMainView.Section, medium: MediaKind, @ViewBuilder page: () -> Page) -> some View {
            VStack(spacing: 0) {
                KuroHeaderNew(selection: .constant(section), showProfileSheet: .constant(false),
                              showSearchSheet: .constant(false), tasteMedium: medium)
                page()
            }
            .background(section.canvas(mangaHome: medium == .manga, mangaTaste: medium == .manga))
            .environment(graph.identity)
            .environment(graph.session)
            .environment(graph.clubs)
            .environment(graph.flags)
            .environment(graph.home)
        }
        for medium in [MediaKind.anime, .manga] {
            graph.home.seedForVisualQA(anime: try empty("anime"), manga: try empty("manga"), medium: medium.rawValue)
            let canvas = TastePageContent.canvas(for: medium)
            #expect(await render(pager(.home, medium: medium) {
                HomeAnimeLaneTests.home(graph.graph, materials, canvas: canvas, newAccountLatch: true)
            }, width: 390, height: 1_000, name: "pager-home-new-\(medium.rawValue)-390.png", settle: 1_400))
            let busy = await Self.busy(medium, catalog: graph.catalog)
            let new = await TasteCardDetails.hydrate(
                Array(Self.cards(medium, premise: false, banner: true).prefix(TastePicksCopy.visibleCount(newAccount: true))),
                catalog: graph.catalog)
            for (state, cards, newAccount) in [("busy", busy, false), ("new", new, true)] {
                #expect(await render(pager(.taste, medium: medium) {
                    Self.tastePage(medium: medium, state: .cards(cards), newAccount: newAccount, width: 390)
                        .environment(graph.library)
                        .environment(graph.libraryActions)
                }, width: 390, height: 844, name: "pager-taste-\(state)-\(medium.rawValue)-390.png", settle: 1_400))
            }
        }
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-pager")
    }

    @Test("New-account Home through its own loader (seeded Discover bundle)")
    func newAccountHomeLive() async throws {
        await Self.seedArtwork()
        let (graph, defaults) = try await Self.signedInGraph("firstrun-home-live")
        for medium in [MediaKind.anime, .manga] {
            #expect(await render(
                ScrollView {
                    HomeNewAccount(medium: medium, onImport: {}, onExploreTaste: {})
                }
                .background(TastePageContent.canvas(for: medium))
                .environment(graph.discovery)
                .environment(graph.catalog)
                .environment(graph.library)
                .environment(graph.libraryActions)
                .environment(\.kuroRoutes, KuroRoutes.unhandled),
                width: 390, height: medium == .anime ? 1_200 : 1_500,
                name: "home-new-\(medium.rawValue)-loader-390.png", settle: 1_600
            ))
        }
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-home-live")
    }

    // MARK: Taste

    @Test("Taste busy and new account, anime and manga, at 390; loading; DE; AX5; Plan toast; the live page")
    func taste() async throws {
        await Self.seedArtwork()
        let (graph, defaults) = try await Self.signedInGraph("firstrun-taste")
        func page(_ medium: MediaKind, _ state: TastePageContent.State, newAccount: Bool) -> some View {
            Self.tastePage(medium: medium, state: state, newAccount: newAccount, width: 390)
                .environment(graph.library)
                .environment(graph.libraryActions)
        }
        for medium in [MediaKind.anime, .manga] {
            // Both through the page's own path: the rows as their reads return them, then the catalogue
            // read (`TasteCardDetails`) for what the rows lack. Busy: because-you rows carry a synopsis
            // and no banner; the catalogue lends the first anime pick its banner (the landscape card).
            // New: Discover bundle rows carry the anime banner and no synopsis; the catalogue lends the
            // premise. New-account Taste shows the reference's two cards (`visibleCount`).
            let busy = await Self.busy(medium, catalog: graph.catalog)
            let new = await TasteCardDetails.hydrate(
                Array(Self.cards(medium, premise: false, banner: true).prefix(TastePicksCopy.visibleCount(newAccount: true))),
                catalog: graph.catalog)
            #expect(await render(page(medium, .cards(busy), newAccount: false), width: 390, height: 844,
                                 name: "taste-busy-\(medium.rawValue)-390.png", settle: 1_400))
            #expect(await render(page(medium, .cards(new), newAccount: true), width: 390, height: 844,
                                 name: "taste-new-\(medium.rawValue)-390.png", settle: 1_400))
            #expect(await render(page(medium, .loading, newAccount: false), width: 390, height: 844,
                                 name: "taste-loading-\(medium.rawValue)-390.png", settle: 400))
            #expect(await render(page(medium, .cards(busy), newAccount: false).environment(\.tasteGerman, true),
                                 width: 390, height: 844, name: "taste-busy-\(medium.rawValue)-de-390.png", settle: 1_400))
            if Self.writing {
                #expect(await renderAX5(page(medium, .cards(busy), newAccount: false), width: 390,
                                    height: 2_600,
                                    name: "taste-busy-\(medium.rawValue)-ax5-390.png"))
            }
        }
        // A real one-tap Plan through the page's controller: the planned key and the toast with Undo.
        let plans = TastePlanController(holdSeconds: 60)
        let planned = await Self.busy(.anime, catalog: graph.catalog)[1]
        await plans.tap(planned, library: graph.library, actions: graph.libraryActions, routes: .unhandled,
                        german: false)?.value
        #expect(graph.library.entry(for: planned.key)?.status == .planning)
        #expect(plans.toast?.message == "Added to your list.")
        // The host reads the Library from the environment, so it sits inside the environment modifiers.
        #expect(await render(Self.tastePage(medium: .anime, state: .cards(await Self.busy(.anime, catalog: graph.catalog)),
                                            newAccount: false, width: 390)
                                .tastePlanHost(plans)
                                .environment(graph.library)
                                .environment(graph.libraryActions),
                             width: 390, height: 844, name: "taste-busy-anime-planned-390.png", settle: 1_400))
        plans.dismiss()
        graph.backendForFixtures?.setRows([], for: LifecycleFixtures.userA)
        try? await graph.library.refresh()

        // The real page: TastePicksView over the seeded bundle (the because-you read fails with no client,
        // so the bundle's NEW TO YOU picks stand in; the account is new, so "A first favourite.").
        #expect(await render(
            TastePicksView(medium: .constant(.anime))
                .environment(graph.discovery)
                .environment(graph.catalog)
                .environment(graph.library)
                .environment(graph.libraryActions)
                .environment(graph.artworkMaterials)
                .environment(NetworkMonitor())
                .environment(\.kuroRoutes, KuroRoutes.unhandled),
            width: 390, height: 1_200, name: "taste-live-new-anime-390.png", settle: 1_800
        ))
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "firstrun-taste")
    }

    /// Two because-you rows completed by the catalogue (the busy references show two cards).
    private static func busy(_ medium: MediaKind, catalog: CatalogStore) async -> [TasteCard] {
        await TasteCardDetails.hydrate(Array(cards(medium, premise: true, banner: false).prefix(2)), catalog: catalog)
    }

    // MARK: Collection and Search

    @Test("Collection empty invitation and Search with no history, at 390")
    func collectionAndSearch() async throws {
        let copyGerman = KuroLocale.isGerman
        #expect(await render(
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
        ))

        guard let defaults = UserDefaults(suiteName: "firstrun-search") else { return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        #expect(await render(
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
        ))
        defaults.removePersistentDomain(forName: "firstrun-search")
    }

    // MARK: Compositions

    private static func homeNewPage(medium: MediaKind, picks: [TasteCard], width: CGFloat,
                                    german: Bool = false) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                TasteOpening(medium: .constant(medium), artURL: picks.first?.media.imageURL,
                             metrics: TasteMetrics(pageWidth: width),
                             kicker: german ? "DEINE SAMMLUNG" : "YOUR COLLECTION",
                             headline: german ? "Fang hier an." : "Begin here.")
                HomeNewAccountContent(medium: medium, picks: picks, width: width, onImport: {}, onExploreTaste: {})
                TasteFooter()
            }
        }
        .background(TastePageContent.canvas(for: medium))
        .environment(\.kuroRoutes, KuroRoutes.unhandled)
    }

    /// The first pick's artwork, as the live page fills the selected medium word.
    private static func firstArt(_ state: TastePageContent.State) -> String? {
        if case .cards(let cards) = state { return cards.first?.media.imageURL }
        return nil
    }

    private static func tastePage(medium: MediaKind, state: TastePageContent.State, newAccount: Bool,
                                  width: CGFloat) -> some View {
        ScrollView {
            TastePageContent(medium: .constant(medium), state: state, newAccount: newAccount,
                             switchArt: Self.firstArt(state), width: width)
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

    /// The fixtures as cards. `banner`: the anime fixture's banner (a bundle row, or a because-you row
    /// whose title the bundle also holds); because-you rows on their own carry none.
    private static func cards(_ medium: MediaKind, premise: Bool, banner: Bool) -> [TasteCard] {
        (medium == .anime ? animeFixtures : mangaFixtures).map { fixture in
            TasteCard(
                media: Media(id: fixture.id, kind: medium, title: fixture.title, imageURL: artURL(fixture.cover),
                             year: "2016", displayDescription: "", episodes: nil, chapters: nil, rating: nil,
                             genres: [fixture.genre], statusRaw: nil, formatRaw: fixture.format,
                             popularityValue: nil, trendingValue: nil, createdAtValue: nil),
                bannerURL: banner ? fixture.banner.map(artURL) : nil,
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

    /// The catalogue's detail rows for the fixtures, in `CatalogStore`'s detail cache (no network): the
    /// synopsis whose first sentence is the premise, and Your Name.'s banner. The other anime have no
    /// banner, so they stay portrait cards.
    private static func seedCatalog(_ catalog: CatalogStore) throws {
        func row(_ fixture: Fixture, banner: String?) throws -> Data {
            var object: [String: Any] = ["id": fixture.id, "is_adult": false, "genres": [fixture.genre],
                                         "created_at": 0, "updated_at": 0, "title_english": fixture.title,
                                         "format": fixture.format, "cover_image_large": artURL(fixture.cover),
                                         "description": fixture.premise + " The rest of the catalogue synopsis."]
            if let banner { object["banner_image"] = artURL(banner) }
            return try JSONSerialization.data(withJSONObject: object)
        }
        for fixture in animeFixtures {
            catalog.animeDetailCache[fixture.id] = try JSONDecoder().decode(Anime.self, from: row(fixture, banner: fixture.banner))
        }
        for fixture in mangaFixtures {
            catalog.mangaDetailCache[fixture.id] = try JSONDecoder().decode(Manga.self, from: row(fixture, banner: nil))
        }
    }

    /// A signed-in graph whose Library loaded empty (a new account) and whose Discover bundle is cached.
    private static func signedInGraph(_ suite: String, launchArguments: [String] = []) async throws -> (FixtureGraph, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        let backend = FakeLibraryBackend()
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend,
                                                flags: launchArguments.isEmpty ? nil
                                                    : FeatureFlags(userDefaults: defaults, launchArguments: launchArguments))
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "new@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
        try? await graph.library.refresh()
        let key = DiscoveryStore.bundleKey(user: LifecycleFixtures.userA, limit: 30, hours: 24)
        graph.discovery.discoverBundleCache[key] = TimedCache(value: try bundle(), storedAt: Date())
        try seedCatalog(graph.catalog)
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

    /// Renders at the largest accessibility text size: SwiftUI's size for layout decisions and the
    /// shared Kuro type scale for the `kuroCustom` fonts, restored right after. At most 2,600 pt tall:
    /// taller hierarchies draw blank at 3x (the top of the page is the evidence).
    private func renderAX5<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String) async -> Bool {
        KuroTypeScale.current.update(category: .accessibilityExtraExtraExtraLarge)
        defer { KuroTypeScale.current.update(category: UIApplication.shared.preferredContentSizeCategory) }
        return await render(view.environment(\.dynamicTypeSize, .accessibility5), width: width, height: height,
                            name: name, settle: 1_400)
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, settle: Int = 500) async -> Bool {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.diagnosticDir, withIntermediateDirectories: true)
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
        // 1 px = 1 pt, as the references and the Home renders, so the two compare pixel for pixel:
        // drawn at the screen scale and block-averaged (`FixtureRaster`). `KURO_RENDER_SCALE=3`
        // (diagnosis only) keeps the device pixels and writes to a temporary folder instead.
        let data = FixtureRaster.png(of: host.view, size: CGSize(width: width, height: height),
                                     diagnosticScale: Self.diagnosticScale)
        let url = (Self.diagnosticScale == nil ? Self.outDir : Self.diagnosticDir).appendingPathComponent(name)
        guard let data else {
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
            try FileManager.default.createDirectory(at: Self.diagnosticDir, withIntermediateDirectories: true)
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
