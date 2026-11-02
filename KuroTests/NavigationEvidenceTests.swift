import KuroCore
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Visual evidence for the navigation contract integration (spec §5 "snapshot/fixture renders"): every
/// page is rendered inside a real `JourneyHost`, no network (nil clients / an in-process stub).
/// - anime detail as a journey's first page over dark and light artwork, at the top (round keys over
///   the hero), part way through the collapse (H2) and scrolled (paper compact bar with the title, ink
///   glyphs);
/// - a pushed character page (Back + ✕);
/// - club detail at the top and scrolled (compact bar);
/// - the story fold, folded and unfolded (session fold memory).
/// PNGs go to a temporary folder, or to `docs/navigation-2026-11-02/` with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1` (run `-only-testing:KuroTests/NavigationEvidenceTests`).
@Suite("Navigation integration evidence renders", .serialized, .timeLimit(.minutes(4)))
@MainActor
struct NavigationEvidenceTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-nav-evidence", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/navigation-2026-11-02")
    }()

    @Test("Anime detail (dark/light, top/scrolled), story folded/unfolded, pushed character")
    func detailAndCharacter() async throws {
        let suite = "nav-evidence-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: [])
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: FakeLibraryBackend(), flags: flags)
        let folds = KuroFoldMemory()

        for (id, title, color, tone) in [(2, "Jujutsu Kaisen", "#2b3a55", "dark"), (3, "Mushishi", "#e8e2c8", "light")] {
            let anime = try Self.anime(id: id, title: title, color: color)
            let navigator = JourneyNavigator(root: .custom(AnyJourneyPage(id: "evidence:\(id)") {
                AnimeDetailPage(anime: anime, preview: Self.content())
            }))
            let window = Self.window(Self.host(JourneyHost(navigator: navigator), graph: graph, folds: folds))
            defer { window.isHidden = true; window.rootViewController = nil }
            try? await Task.sleep(for: .milliseconds(1_000))
            await capture(window, name: "detail-\(tone)-top-390.png")
            #expect(navigator.path.isEmpty)
            // H2: part way through the collapse (p ≈ 0.3): one glyph colour on its whole key, never a
            // white/ink blend over a half-faded backdrop.
            if let scroll = Self.scrollView(in: window) { scroll.setContentOffset(CGPoint(x: 0, y: 50), animated: false) }
            try? await Task.sleep(for: .milliseconds(500))
            await capture(window, name: "detail-\(tone)-mid-collapse-390.png")
            if let scroll = Self.scrollView(in: window) { scroll.setContentOffset(CGPoint(x: 0, y: 420), animated: false) }
            try? await Task.sleep(for: .milliseconds(700))
            await capture(window, name: "detail-\(tone)-scrolled-compact-bar-390.png")

            if tone == "dark" {
                // F1-F3: the story fold, folded (default) then unfolded through the session's fold memory.
                if let scroll = Self.scrollView(in: window) { scroll.setContentOffset(CGPoint(x: 0, y: 200), animated: false) }
                try? await Task.sleep(for: .milliseconds(500))
                await capture(window, name: "detail-story-folded-390.png")
                folds.setExpanded(true, page: DetailFold.page(MediaKey(kind: .anime, id: id)), section: DetailFold.story)
                try? await Task.sleep(for: .milliseconds(900))
                await capture(window, name: "detail-story-unfolded-390.png")
                #expect(folds.isExpanded(page: DetailFold.page(MediaKey(kind: .anime, id: id)), section: DetailFold.story))

                // A character pushed from the detail: Back + ✕ (offline: its works rail shows no titles).
                navigator.open(.character(Self.character()))
                try? await Task.sleep(for: .milliseconds(1_400))
                await capture(window, name: "character-pushed-390.png")
                #expect(navigator.path.count == 1)
            }
        }
    }

    @Test("Club detail as a journey page: top and scrolled (compact bar)")
    func clubDetail() async throws {
        let harness = try ClubsHarness(responder: { request in
            request.resource == "rpc/fetch_club_bundle" ? .json(Self.tallClubBundle()) : .emptyArray
        })
        _ = await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        let navigator = JourneyNavigator(root: .club(id: "c1"))
        let window = Self.window(Self.host(JourneyHost(navigator: navigator), graph: harness.service, folds: KuroFoldMemory()))
        try? await Task.sleep(for: .milliseconds(2_000))
        await capture(window, name: "club-top-390.png")
        if let scroll = Self.scrollView(in: window) {
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, min(520, scroll.contentSize.height - scroll.bounds.height))), animated: false)
        }
        try? await Task.sleep(for: .milliseconds(800))
        await capture(window, name: "club-scrolled-compact-bar-390.png")
        window.isHidden = true
        window.rootViewController = nil
        await harness.tearDown()
    }

    // MARK: Fixtures

    /// `ClubJSON.bundle` with five rails (the one-rail club is shorter than a screen, so the room could
    /// not scroll under the compact bar).
    nonisolated private static func tallClubBundle() -> String {
        let base = ClubJSON.bundle(clubId: "c1")
        guard let data = base.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rails = object["rails"] as? [[String: Any]], let rail = rails.first else { return base }
        object["rails"] = (0..<5).map { index -> [String: Any] in
            var copy = rail
            copy["id"] = "rail-c1-\(index)"
            copy["title"] = "Rail \(index + 1)"
            copy["sort_order"] = index
            return copy
        }
        guard let out = try? JSONSerialization.data(withJSONObject: object) else { return base }
        return String(decoding: out, as: UTF8.self)
    }

    private static func content() -> AnimeDetailContent {
        var content = AnimeDetailContent()
        content.studios = [Studio(id: 1, anilistId: nil, name: "MAPPA", isAnimationStudio: true, siteUrl: nil, favourites: nil)]
        content.songs = (1...6).map { ThemeSong(kind: $0 % 2 == 0 ? .ending : .opening, sequence: $0, title: "Song \($0)",
                                                artist: "Artist \($0)", episodes: "1–12") }
        content.characters = (1...4).map { index in
            (character: Character(id: index, anilistId: nil, nameFull: "Character \(index)", nameNative: nil, imageLarge: nil,
                                  description: nil, gender: nil, age: nil), role: "MAIN")
        }
        return content
    }

    private static func character() -> Character {
        Character(id: 1, anilistId: nil, nameFull: "Character 1", nameNative: "キャラ", imageLarge: nil,
                  description: nil, gender: "Female", age: "17")
    }

    private static func anime(id: Int, title: String, color: String) throws -> Anime {
        let object: [String: Any] = [
            "id": id, "is_adult": false, "genres": ["Drama"], "created_at": 0, "updated_at": 0,
            "title_english": title, "format": "TV", "status": "FINISHED", "episodes": 24, "season_year": 2023,
            "cover_image_color": color,
            "description": String(repeating: "A long synopsis line that keeps the story folded until it is opened. ", count: 14)
        ]
        return try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: Hosting

    private static func host<V: View>(_ view: V, graph: AppGraph, folds: KuroFoldMemory) -> some View {
        view
            .environment(graph.identity)
            .environment(graph.session)
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
            .environment(graph.banner)
            .environment(graph.auth)
            .environment(graph.search)
            .environment(graph.discovery)
            .environment(graph.recommendations)
            .environment(graph.collection)
            .environment(graph.imports)
            .environment(graph.concierge)
            .environment(graph.taste)
            .environment(graph.deviceIntelligence)
            .environment(graph.support)
            .environment(graph.interactionTelemetry)
            .environment(NetworkMonitor())
            .environment(\.kuroFoldMemory, folds)
    }

    private static func window<V: View>(_ view: V, height: CGFloat = 844) -> UIWindow {
        let width: CGFloat = 390
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
        do { try data.write(to: Self.outDir.appendingPathComponent(name)) } catch { Issue.record("\(name): write failed (\(error))") }
    }

    /// The visible page's tallest vertical scroll view.
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
}
