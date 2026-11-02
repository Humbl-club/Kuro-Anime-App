import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Fixture renders for prototype-fidelity Task 9 (remaining screens restyle and branded states):
/// Clubs (loading, empty invitation, failed, list), Profile (new account, seeded), Folio (anime and
/// manga keys), Discover and Browse failed (branded error), Onboarding, the import chooser, the auth
/// sign-in form and Data sources, at 390. No network: nil clients, a fake Library backend or an
/// in-process stub endpoint. PNGs are written to `docs/prototype-fidelity/native/restyle/` only with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1` (run it with `-only-testing:KuroTests/RestyleSnapshotTests`
/// so the overnight screen map is not rewritten); ordinary runs render into a temporary folder.
@Suite("Restyle lane snapshots", .serialized, .timeLimit(.minutes(4)))
@MainActor
struct RestyleSnapshotTests {
    private static let repo: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-restyle", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/restyle")
    }()

    // MARK: Clubs

    @Test("Clubs: loading, empty invitation, failed and list at 390")
    func clubs() async throws {
        await Self.seedArtwork()
        guard let defaults = UserDefaults(suiteName: "restyle-clubs") else { return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        await render(ClubsView().environment(graph.clubs).environment(NetworkMonitor()),
                     width: 390, height: 844, name: "clubs-loading-390.png", settle: 900)
        // A nil client makes the read fail (not a connectivity failure): the branded error.
        await graph.clubs.fetchMyClubs()
        await render(ClubsView().environment(graph.clubs).environment(NetworkMonitor()),
                     width: 390, height: 844, name: "clubs-failed-390.png", settle: 1_600)
        defaults.removePersistentDomain(forName: "restyle-clubs")

        if let harness = try? ClubsHarness(responder: { _ in .emptyArray }) {
            _ = await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
            await harness.clubs.fetchMyClubs()
            await render(ClubsView().environment(harness.clubs).environment(NetworkMonitor()),
                         width: 390, height: 844, name: "clubs-empty-390.png", settle: 1_000)
            await render(ClubsView().environment(harness.clubs).environment(NetworkMonitor()),
                         width: 320, height: 700, name: "clubs-empty-320.png", settle: 1_000)
            await harness.tearDown()
        }

        let rows = """
        [{"id":"c1","name":"Late Night Watch","sharing_level":"status","is_archived":false,
          "created_at":"2026-01-01T00:00:00Z","member_count":4,"rail_count":2,
          "cover_images":["\(Self.artURL("anime0.jpg"))","\(Self.artURL("anime1.jpg"))","\(Self.artURL("anime2.jpg"))","\(Self.artURL("anime3.jpg"))"],
          "member_names":["Ana","Ben","Cleo","Dev"]},
         {"id":"c2","name":"Ink Readers","sharing_level":"private","is_archived":false,
          "created_at":"2026-01-02T00:00:00Z","member_count":3,"rail_count":1,
          "cover_images":["\(Self.artURL("manga0.jpg"))","\(Self.artURL("manga1.jpg"))"]}]
        """
        if let harness = try? ClubsHarness(responder: { request in
            (request.resource ?? "").hasPrefix("rpc/fetch_my_clubs") ? .json(rows) : .emptyArray
        }) {
            _ = await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
            await harness.clubs.fetchMyClubs()
            await render(ClubsView().environment(harness.clubs).environment(NetworkMonitor()),
                         width: 390, height: 1_200, name: "clubs-list-390.png", settle: 1_600)
            await harness.tearDown()
        }
    }

    @Test("Club detail: open club and failed first load at 390")
    func clubDetail() async throws {
        if let harness = try? ClubsHarness(responder: { request in
            request.resource == "rpc/fetch_club_bundle" ? .json(ClubJSON.bundle(clubId: "c1")) : .emptyArray
        }) {
            _ = await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
            await render(Self.inject(NavigationStack { ClubDetailView(clubId: "c1") }, graph: harness.service),
                         width: 390, height: 1_100, name: "club-detail-390.png", settle: 2_000)
            await harness.tearDown()
        }
        guard let defaults = UserDefaults(suiteName: "restyle-club-detail") else { return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        await render(Self.inject(NavigationStack { ClubDetailView(clubId: "c1") }, graph: graph),
                     width: 390, height: 844, name: "club-detail-failed-390.png", settle: 2_000)
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "restyle-club-detail")
    }

    // MARK: Profile

    @Test("Profile: new account, seeded library and failed library at 390")
    func profile() async throws {
        await Self.seedArtwork()
        for (suffix, rows) in [("new", [LibraryEntry]()), ("seeded", Self.libraryEntries())] {
            guard let defaults = UserDefaults(suiteName: "restyle-profile-\(suffix)") else { continue }
            let backend = FakeLibraryBackend()
            backend.setRows(rows, for: LifecycleFixtures.userA)
            let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                    libraryBackend: backend)
            _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
            try? await graph.library.refresh()
            graph.collection.listPreview = rows.isEmpty ? [:] : Self.previews()
            graph.collection.listPreviewFailed = false
            graph.collection.listPreviewLoadedAt = Date()
            await render(Self.inject(ProfileView(), graph: graph), width: 390, height: 1_500,
                         name: "profile-\(suffix)-390.png", settle: 1_400)
            await graph.session.endSession()
            defaults.removePersistentDomain(forName: "restyle-profile-\(suffix)")
        }

        // The library's first read fails with nothing on screen: the branded error with Try again.
        guard let defaults = UserDefaults(suiteName: "restyle-profile-failed") else { return }
        let source = ControlledResponses<[LibraryEntry]>()
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: FakeLibraryBackend(fetchSource: source))
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        // The session funnel starts the library read (`startLibraryRefresh`); fail every read asked for,
        // then wait for the store to publish the failure.
        for _ in 0..<200 where graph.library.loadState != .failed {
            for label in source.requests { source.complete(label, with: .failure(ControlledFailure())) }
            await Task.yield()
        }
        #expect(graph.library.loadState == .failed)
        graph.collection.listPreviewLoadedAt = Date()
        await render(Self.inject(ProfileView(), graph: graph), width: 390, height: 1_500,
                     name: "profile-failed-390.png", settle: 1_400)
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "restyle-profile-failed")
    }

    // MARK: Folio

    @Test("Folio: anime light keys, manga dark keys, index and shelf at 390")
    func folio() async throws {
        await Self.seedArtwork()
        for medium in [MediaKind.anime, .manga] {
            for density in FolioDensity.allCases {
                await render(Self.folioPage(medium: medium, density: density, width: 390), width: 390, height: 844,
                             name: "folio-\(medium == .anime ? "anime" : "manga")-\(density.rawValue)-390.png", settle: 1_200)
            }
        }
    }

    // MARK: Discover, Browse

    @Test("Discover and Browse: branded failed states at 390")
    func discoverBrowse() async throws {
        guard let defaults = UserDefaults(suiteName: "restyle-discover") else { return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        await render(Self.inject(EditorialDiscoverView(), graph: graph), width: 390, height: 844,
                     name: "discover-failed-390.png", settle: 2_500)
        await render(Self.inject(BrowseView(), graph: graph), width: 390, height: 844,
                     name: "browse-failed-390.png", settle: 2_500)
        defaults.removePersistentDomain(forName: "restyle-discover")
    }

    // MARK: Onboarding, imports, auth, about

    @Test("Onboarding, import chooser, auth sign-in form and data sources at 390")
    func flows() async throws {
        guard let defaults = UserDefaults(suiteName: "restyle-flows") else { return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        await render(Self.inject(OnboardingView(onComplete: { _ in }), graph: graph), width: 390, height: 844,
                     name: "onboarding-390.png", settle: 900)
        await render(Self.inject(ImportSourceChooser(onNavigate: { _ in }), graph: graph), width: 390, height: 844,
                     name: "import-chooser-390.png", settle: 900)
        graph.identity.authNoticeMessage = KuroLocale.text("Check your email, then sign in.", "Prüfe deine E-Mails und melde dich dann an.")
        await render(Self.inject(AuthView(), graph: graph), width: 390, height: 844, name: "auth-signin-390.png", settle: 1_600)
        await render(DataSourcesView().background(Color.kuroCanvasPage), width: 390, height: 1_300,
                     name: "data-sources-390.png")
        defaults.removePersistentDomain(forName: "restyle-flows")
    }

    // MARK: Environment

    private static func inject<V: View>(_ view: V, graph: AppGraph) -> some View {
        view
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
            .environment(NetworkMonitor())
            .environment(\.kuroRoutes, KuroRoutes.unhandled)
    }

    // MARK: Rendering (the ScreenMapSnapshotTests helper)

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, settle: Int = 500) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            return
        }
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
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
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let url = Self.outDir.appendingPathComponent(name)
        guard let data = image.pngData() else { return }
        do {
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        } catch {
            #if DEBUG
            print("Restyle snapshot write failed: \(error)")
            #endif
        }
    }

    // MARK: Fixtures

    private static let artFiles: [String] = ["anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg",
                                             "anime0-banner.jpg", "anime1-banner.jpg", "anime3-banner.jpg",
                                             "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg"]

    private static func artURL(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: artURL(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }

    private struct Row {
        let id: Int
        let title: String
        let art: String
        let status: ListStatus
        let progress: Int
        let total: Int?
    }

    private static let animeRows: [Row] = [
        Row(id: 1, title: "Attack on Titan", art: "anime0.jpg", status: .current, progress: 7, total: 25),
        Row(id: 2, title: "Demon Slayer", art: "anime1.jpg", status: .current, progress: 4, total: 26),
        Row(id: 3, title: "Jujutsu Kaisen", art: "anime2.jpg", status: .current, progress: 6, total: 24),
        Row(id: 4, title: "Mob Psycho 100", art: "anime3.jpg", status: .planning, progress: 0, total: 12)
    ]

    private static let mangaRows: [Row] = [
        Row(id: 10, title: "Chainsaw Man", art: "manga0.jpg", status: .current, progress: 24, total: 120),
        Row(id: 11, title: "Solo Leveling", art: "manga1.jpg", status: .current, progress: 8, total: 200),
        Row(id: 12, title: "Berserk", art: "manga2.jpg", status: .current, progress: 3, total: nil),
        Row(id: 13, title: "Vagabond", art: "manga3.jpg", status: .completed, progress: 327, total: 327)
    ]

    private static func media(_ row: Row, kind: MediaKind) -> Media {
        Media(id: row.id, kind: kind, title: row.title, imageURL: artURL(row.art), year: "2020",
              displayDescription: "", episodes: kind == .anime ? row.total : nil,
              chapters: kind == .manga ? row.total : nil, rating: 8.4, genres: ["Drama"],
              statusRaw: "RELEASING", formatRaw: kind == .anime ? "TV" : "MANGA",
              popularityValue: nil, trendingValue: nil, createdAtValue: nil)
    }

    private static func entry(_ row: Row, kind: MediaKind) -> LibraryEntry {
        FakeLibraryBackend.entry(kind, row.id, rowId: row.id, status: row.status, progress: row.progress, verdict: nil)
    }

    private static func libraryEntries() -> [LibraryEntry] {
        animeRows.map { entry($0, kind: .anime) } + mangaRows.map { entry($0, kind: .manga) }
    }

    private static func previews() -> [ListStatus: [Media]] {
        var result: [ListStatus: [Media]] = [:]
        for row in animeRows { result[row.status, default: []].append(media(row, kind: .anime)) }
        for row in mangaRows { result[row.status, default: []].append(media(row, kind: .manga)) }
        return result
    }

    private static func folioPage(medium: MediaKind, density: FolioDensity, width: CGFloat) -> some View {
        let rows = (medium == .anime ? animeRows : mangaRows).filter { $0.status == .current }
        let items = rows.map { row in
            FolioItem(media: media(row, kind: medium), entry: entry(row, kind: medium), progress: row.progress,
                      next: nil, banner: nil)
        }
        let gutter = FolioPolicy.gutter(forWidth: width)
        let entries = libraryEntries()
        let actions = FolioRowActions(
            open: { _ in }, advance: { _ in }, edit: { _ in }, classify: { _ in }, remove: { _ in },
            toggleSelection: { _ in },
            keyPhase: { item in
                FolioPolicy.keyPhase(status: item.entry.status, progress: item.progress, total: item.total,
                                     needsChoice: false, isPending: false)
            }
        )
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                KuroMediumSwitch(selection: .constant(medium), size: .compact)
                    .padding(.horizontal, gutter)
                    .padding(.top, KuroDesignSpacing.sm)
                FolioStatusStrip(selection: .constant(.watching), counts: FolioPolicy.counts(entries, medium: medium),
                                 medium: medium, gutter: gutter)
                FolioControlsRow(density: .constant(density), sort: .constant(.recent), isSearching: false,
                                 isSelecting: false, canSelect: true, onToggleSearch: {}, onToggleSelect: {}, gutter: gutter)
                Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                    .padding(.horizontal, gutter)
                    .padding(.top, KuroDesignSpacing.xs)
                if density == .shelf {
                    FolioShelf(items: items, medium: medium, width: width, isSelecting: false, selectedKeys: [],
                               actions: actions)
                } else {
                    FolioIndex(items: items, width: width, isSelecting: false, selectedKeys: [], actions: actions)
                }
            }
        }
        .background(Color.kuroCanvasPage)
    }
}
