import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Fixture renders of the prototype anime detail (Task 6) for the fidelity review against
/// docs/prototype-fidelity/reference/ref-detail-anime-390.png. No network: the page gets a complete
/// `AnimeDetailContent` (which turns its reads off), the Library is a fake backend, the artwork is
/// seeded into `URLCache`. PNGs are written to docs/prototype-fidelity/native/detail/ only with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; ordinary runs render into a temporary folder.
@Suite("Detail anime snapshots", .serialized, .timeLimit(.minutes(3)))
@MainActor
struct DetailAnimeSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-detail-anime", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/detail")
    }()

    @Test("Anime detail: tracked season with club, untracked sparse title")
    func animeDetail() async throws {
        await Self.seedArtwork()
        let suite = "detail-anime-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 2, rowId: 2, status: .current, progress: 6)],
                        for: LifecycleFixtures.userA)
        // social_activity_v1 on (live: 100 %): "Between us." and the club row need it.
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=social_activity_v1"])
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend, flags: flags)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        try? await graph.library.refresh()
        graph.clubs.myClubs = try Self.clubs()

        let tracked = try Self.anime(id: 2, title: "Jujutsu Kaisen", art: "anime2.jpg", color: "#e4935d", episodes: 23,
                                     synopsis: Self.synopsis, genres: ["Action", "Drama", "Supernatural"])
        let page = Self.host(AnimeDetailPage(anime: tracked, preview: Self.trackedContent()), graph: graph)
        await render(page, width: 390, height: 844, name: "detail-anime-390.png", fullPage: true)
        await render(page, width: 390, height: 844, name: "detail-anime-top-390.png")
        await render(page, width: 320, height: 844, name: "detail-anime-top-320.png")
        // Review focus 1: the hero and Up next at the largest accessibility size, then the whole page.
        await renderAX5(page, width: 320, name: "detail-anime-top-ax5-320.png")
        await renderAX5(page, width: 320, name: "detail-anime-ax5-320.png", fullPage: true)
        // German, tracked, the whole page: long headings, the sound panel and "Unter uns.".
        let germanTracked = await withGerman {
            await render(page, width: 390, height: 844, name: "detail-anime-de-390.png", fullPage: true)
        }
        #expect(germanTracked, "KuroLocale did not pick up the volatile AppleLanguages override")

        // Series flags on with bundle data: the `detail_copy` hook and the manga coverage disclosure.
        var withBundle = Self.trackedContent()
        withBundle.bundle = try Self.bundle()
        await render(Self.host(AnimeDetailPage(anime: tracked, preview: withBundle), graph: graph),
                     width: 390, height: 844, name: "detail-anime-bundle-390.png", fullPage: true)

        // An untracked title opened from Discover with only a synopsis and one credit: hero with
        // "Not in your list" + Add, the story and "Behind the frames." — nothing else.
        let sparse = try Self.anime(id: 77, title: "Mushishi", art: "journal-anime-12-cover.jpg", color: nil, episodes: 26,
                                    synopsis: Self.synopsis, genres: [])
        var sparseContent = AnimeDetailContent()
        sparseContent.studios = [Studio(id: 9, anilistId: nil, name: "Artland", isAnimationStudio: true, siteUrl: nil, favourites: nil)]
        graph.clubs.myClubs = []
        await render(Self.host(AnimeDetailPage(anime: sparse, preview: sparseContent), graph: graph),
                     width: 390, height: 844, name: "detail-anime-untracked-390.png", fullPage: true)
        // German, untracked: "Nicht in deiner Liste" + "Hinzufügen" beside or under the title.
        let germanRendered = await withGerman {
            let germanPage = Self.host(AnimeDetailPage(anime: sparse, preview: sparseContent), graph: graph)
            await render(germanPage, width: 390, height: 844, name: "detail-anime-untracked-de-390.png")
            await render(germanPage, width: 320, height: 844, name: "detail-anime-untracked-de-320.png")
        }
        #expect(germanRendered, "KuroLocale did not pick up the volatile AppleLanguages override")
        await graph.session.endSession()
    }

    /// Real AX5 type: the type roles read the process-wide `KuroTypeScale`, which the environment
    /// value alone does not move. Restored to the device category afterwards.
    private func renderAX5<V: View>(_ view: V, width: CGFloat, name: String, fullPage: Bool = false) async {
        KuroTypeScale.current.update(category: .accessibilityExtraExtraExtraLarge)
        await render(view.environment(\.dynamicTypeSize, .accessibility5), width: width, height: 844, name: name,
                     fullPage: fullPage)
        KuroTypeScale.current.update(category: UIApplication.shared.preferredContentSizeCategory)
    }

    /// Runs `body` with German as the first preferred language, set only in this process's volatile
    /// argument domain (nothing is written to the app's preferences). Returns false, skipping the
    /// body, when `KuroLocale` does not see the change.
    private func withGerman(_ body: () async -> Void) async -> Bool {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var german = previous
        german["AppleLanguages"] = ["de-DE"]
        defaults.setVolatileDomain(german, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        guard KuroLocale.isGerman else { return false }
        await body()
        return true
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

    /// Renders a phone-sized window. `fullPage` scrolls the page's scroll view in viewport steps and
    /// stitches the frames (the reference method; one tall window does not draw).
    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, fullPage: Bool = false) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        // A page sheet has no top inset: the window's status-bar inset would push the close control
        // down (the reference pins it 12 pt from the sheet's top).
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Artwork and its material (seed first, then derived) settle before the capture.
        try? await Task.sleep(for: .milliseconds(1_800))
        host.view.layoutIfNeeded()
        // 1 px = 1 pt, as the reference captures.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        func frame() -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
        }
        var image = frame()
        if fullPage, let scroll = Self.scrollView(in: host.view) {
            let total = max(height, scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom)
            let viewport = scroll.bounds.height
            let maxOffset = max(0, total - viewport)
            var tiles: [(CGFloat, UIImage)] = [(0, image)]
            var offset: CGFloat = 0
            while offset < maxOffset {
                offset = min(maxOffset, offset + viewport - 132)
                scroll.setContentOffset(CGPoint(x: 0, y: offset - scroll.adjustedContentInset.top), animated: false)
                host.view.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(450))
                host.view.layoutIfNeeded()
                tiles.append((offset, frame()))
            }
            let top = scroll.frame.minY
            image = UIGraphicsImageRenderer(size: CGSize(width: width, height: total + top), format: format).image { context in
                // The page's paper under any strip no frame covered.
                UIColor(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF4 / 255.0, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: total + top))
                for (offset, tile) in tiles {
                    // Draw the scroll area of each frame at its content position (the first frame whole).
                    if offset == 0 {
                        tile.draw(at: .zero)
                    } else if let cg = tile.cgImage?.cropping(to: CGRect(x: 0, y: top + 100, width: width, height: viewport - 100)) {
                        // Each later frame drops its top 100 pt, where the fixed close control sits.
                        UIImage(cgImage: cg).draw(at: CGPoint(x: 0, y: top + offset + 100))
                    }
                }
            }
        }
        let url = Self.outDir.appendingPathComponent(name)
        guard let data = image.pngData() else { Issue.record("\(name): PNG encoding failed"); return }
        do {
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
    }

    /// The largest vertical scroll view under `root` (the page's).
    private static func scrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var stack = [root]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height,
               scroll.bounds.width >= (best?.bounds.width ?? 0) {
                if best == nil || scroll.contentSize.height > (best?.contentSize.height ?? 0) { best = scroll }
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }

    // MARK: Fixtures (test data only; never shipped)

    private static let synopsis = """
    Two connected chapters shift the perspective: the bonds of an earlier generation, and a city becoming the \
    stage for a confrontation. Familiar faces carry a different weight as the story widens, and an old \
    friendship turns into the question the whole season keeps asking.
    """

    private static func artURL(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static let artFiles = ["anime2.jpg", "journal-anime-12-cover.jpg", "detail-character-21.png",
                                   "detail-character-22.png", "detail-character-23.png", "detail-character-24.png"]

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: artURL(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": file.hasSuffix("png") ? "image/png" : "image/jpeg"])
            else { continue }
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                                                for: URLRequest(url: url))
        }
    }

    private static func anime(id: Int, title: String, art: String, color: String?, episodes: Int, synopsis: String,
                              genres: [String]) throws -> Anime {
        var object: [String: Any] = [
            "id": id, "is_adult": false, "genres": genres, "created_at": 0, "updated_at": 0,
            "title_english": title, "cover_image_large": artURL(art), "format": "TV", "status": "FINISHED",
            "episodes": episodes, "description": synopsis, "season_year": 2023
        ]
        if let color { object["cover_image_color"] = color }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Anime.self, from: data)
    }

    private static func bundle() throws -> SeriesDetailBundle {
        let json = """
        {"medium":"anime","media_id":2,"series_id":"22222222-2222-4222-8222-222222222222","section_id":null,
         "header":{"media_id":2,"title":"Jujutsu Kaisen","format":"TV","catalogue_status":"FINISHED","episodes":23},
         "sections":[],"units":[],"units_state":"ok",
         "copy":{"hook":"Old friendships. A city on the edge.","synopsis":"\(synopsis)","story_state":"present"},
         "themes":[],"cast":[],
         "coverage":{"source_kind":"manga","mapping_state":"exact","starts_at":"Ch. 65","ends_at":"Ch. 136",
                     "read_next":"Ch. 137","source_manga_id":30}}
        """
        return try JSONDecoder().decode(SeriesDetailBundle.self, from: Data(json.utf8))
    }

    private static func clubs() throws -> [ClubListRow] {
        let json = #"[{"id":"club-1","name":"Sunday Club","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z"}]"#
        return try JSONDecoder().decode([ClubListRow].self, from: Data(json.utf8))
    }

    private static func episode(_ number: Int, description: String? = nil) -> Episode {
        Episode(id: 1_000 + number, animeId: 2, number: number, title: nil, titleRomaji: nil, description: description,
                airDate: nil, airAt: nil, thumbnail: nil, duration: 24, isFiller: false, isRecap: false, isMixed: false,
                fillerSource: nil, streamUrl: nil, streamSite: nil, createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0))
    }

    private static func trackedContent() -> AnimeDetailContent {
        var content = AnimeDetailContent()
        let chain = [LadderChainEntry(mediaId: 1, title: "Jujutsu Kaisen", format: "TV", year: 2020),
                     LadderChainEntry(mediaId: 2, title: "Jujutsu Kaisen Season 2", format: "TV", year: 2023)]
        let seasons = LadderSeasons.seasons(chain: chain, current: 2)
        content.numbered = seasons.numbered
        content.extras = seasons.extras
        content.chainIsProven = true
        content.source = MediaLadderItem(mediaType: "MANGA", mediaId: 30, title: "Jujutsu Kaisen", coverImage: nil, year: 2018,
                                         format: "MANGA", rating: nil, reasonLabel: nil, sourceAuthorName: "Gege Akutami")
        content.characters = [("Yuji Itadori", 22), ("Megumi Fushiguro", 21), ("Nobara Kugisaki", 23), ("Satoru Gojo", 24)]
            .enumerated().map { index, item in
                (character: Character(id: index + 1, anilistId: nil, nameFull: item.0, nameNative: nil,
                                      imageLarge: artURL("detail-character-\(item.1).png"), description: nil, gender: nil, age: nil),
                 role: "MAIN")
            }
        content.staff = [
            (staff: Staff(id: 1, anilistId: nil, nameFull: "Gege Akutami", nameNative: nil, imageLarge: nil, description: nil,
                          primaryOccupations: nil), role: "Original Creator"),
            (staff: Staff(id: 2, anilistId: nil, nameFull: "Shota Goshozono", nameNative: nil, imageLarge: nil, description: nil,
                          primaryOccupations: nil), role: "Director")
        ]
        content.studios = [Studio(id: 1, anilistId: nil, name: "MAPPA", isAnimationStudio: true, siteUrl: nil, favourites: nil)]
        content.episodes = [episode(6), episode(7), episode(8, description: "The barrier closes over the city."), episode(9), episode(10)]
        content.songs = [
            ThemeSong(kind: .opening, sequence: 1, title: "Where Our Blue Is", artist: "Tatsuya Kitani", episodes: "1–5"),
            ThemeSong(kind: .ending, sequence: 1, title: "Akari", artist: "Soushi Sakiyama", episodes: "1–5"),
            ThemeSong(kind: .opening, sequence: 2, title: "SPECIALZ", artist: "King Gnu", episodes: "6–23"),
            ThemeSong(kind: .ending, sequence: 2, title: "more than words", artist: "Hitsujibungaku", episodes: "6–23")
        ]
        let friends = ["Mina", "Jules", "Noah"].enumerated().map { index, name in
            SocialActivityStore.FriendTitleActivity(user_id: "u\(index)", display_name: name, status: "CURRENT",
                                                    progress: 4 + index, rating: nil, updated_at: nil)
        }
        let comments = [
            SocialActivityStore.TitleComment(id: "c1", user_id: "u0", display_name: "Mina",
                                             text: "Came for the animation. Stayed for the characters.",
                                             created_at: "2026-10-30T10:00:00Z", updated_at: "2026-10-30T10:00:00Z",
                                             is_own: false, up_count: 0, down_count: 0, my_reaction: nil, spoiler_scope: nil),
            SocialActivityStore.TitleComment(id: "c2", user_id: "u1", display_name: "Jules",
                                             text: "That ending.", created_at: "2026-10-31T10:00:00Z",
                                             updated_at: "2026-10-31T10:00:00Z", is_own: false, up_count: 0, down_count: 0,
                                             my_reaction: nil, spoiler_scope: "story")
        ]
        content.friendsPreview = .init(friends_tracking: friends, comments: comments, own_comment: nil,
                                       comments_next: nil, friends_next: nil)
        return content
    }
}
