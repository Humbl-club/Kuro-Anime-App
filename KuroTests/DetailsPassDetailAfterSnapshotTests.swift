import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// "After" fixture renders of the detail lane (details-songs spec §6, §7, §19.1). No network: the pages
/// get complete `AnimeDetailContent` / `MangaDetailContent` values (which turn their reads off), the
/// Library is a fake backend, and every picture is a repo asset seeded into `URLCache` under
/// `visual-fixture.invalid`. JPEGs (quality 80, at most 603 px wide) are written to
/// `docs/details-songs-2026-11-03/after/detail-*.jpg` only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`;
/// ordinary runs render into a temporary folder. Run it alone
/// (`-only-testing:KuroTests/DetailsPassDetailAfterSnapshotTests`) so no other suite rewrites its
/// committed evidence.
@Suite("Details pass: detail after renders", .serialized, .timeLimit(.minutes(10)))
@MainActor
struct DetailsPassDetailAfterSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-ds-detail-after", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/details-songs-2026-11-03/after")
    }()

    /// The iPad render's window (a portrait 11" iPad; the page keeps its 680 pt readable column).
    private static let iPadWidth: CGFloat = 834

    // MARK: Anime

    @Test("Anime detail: hero fact rows, timeline, cast, More like this; estimate, untracked, rejected stills")
    func anime() async throws {
        await Self.seedArtwork()
        let suite = "ds-detail-after-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 2, rowId: 2, status: .current, progress: 6),
                         FakeLibraryBackend.entry(.manga, 30, rowId: 30, status: .current, progress: 67)],
                        for: LifecycleFixtures.userA)
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=social_activity_v1"])
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend, flags: flags)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        try? await graph.library.refresh()

        let tracked = try Self.anime(id: 2, title: "Jujutsu Kaisen", art: "anime2.jpg", color: "#e4935d", episodes: 23,
                                     status: "RELEASING", score: 86)
        let content = try Self.trackedContent(next: .confirmed)
        let page = Self.host(AnimeDetailPage(anime: tracked, preview: content), graph: graph)
        await render(page, width: 390, height: 844, name: "detail-anime-top-390")
        await render(page, width: 390, height: 844, name: "detail-anime-full-390", fullPage: true)
        await render(page, width: 320, height: 700, name: "detail-anime-top-320")
        await render(page, width: Self.iPadWidth, height: 1_112, name: "detail-anime-top-ipad")
        await renderAX5(page, width: 390, name: "detail-anime-top-ax5-390")

        // The timeline's watched run open (F1-F3 fold memory).
        let memory = KuroFoldMemory()
        memory.setExpanded(true, page: DetailFold.page(tracked.libraryKey), section: DetailFold.watched)
        await render(page.environment(\.kuroFoldMemory, memory), width: 390, height: 844, name: "detail-anime-timeline-open-390",
                     fullPage: true)

        // German, the whole page.
        let german = await withGerman {
            await render(page, width: 390, height: 844, name: "detail-anime-de-390", fullPage: true)
        }
        #expect(german, "KuroLocale did not pick up the volatile AppleLanguages override")

        // An estimate: the dashed mark and no bell; future rows dashed.
        let estimate = Self.host(AnimeDetailPage(anime: tracked, preview: try Self.trackedContent(next: .estimated)), graph: graph)
        await render(estimate, width: 390, height: 844, name: "detail-anime-estimate-390")

        // Untracked, only background characters, no recommendations: rows from Episode 1, no ticks.
        let untracked = try Self.anime(id: 77, title: "Mushishi", art: "journal-anime-12-cover.jpg", color: nil, episodes: 26,
                                       status: "FINISHED", score: 87)
        var sparse = AnimeDetailContent()
        sparse.studios = [Studio(id: 9, anilistId: nil, name: "Artland", isAnimationStudio: true, siteUrl: nil, favourites: nil)]
        sparse.episodes = (1...4).map { Self.episode($0, animeId: 77, title: $0 == 1 ? "The Green Seat" : "Episode \($0)",
                                                       still: $0 <= 2 ? "anime0-banner.jpg" : nil) }
        sparse.cast = [CastMember(character: Self.character(40, "Ginko", "detail-character-180.png"), role: "BACKGROUND",
                                  voiceActor: nil, language: nil)]
        sparse.source = MediaLadderItem(mediaType: "MANGA", mediaId: 31, title: "Mushishi", coverImage: Self.artURL("journal-manga-13-cover.jpg"),
                                        year: 1999, format: "MANGA", rating: nil, reasonLabel: nil, sourceAuthorName: "Yuki Urushibara")
        await render(Self.host(AnimeDetailPage(anime: untracked, preview: sparse), graph: graph),
                     width: 390, height: 844, name: "detail-anime-untracked-390", fullPage: true)

        // Wrong-season stills (24 rows for a 23-episode season): every row by number, branded tiles.
        var rejected = try Self.trackedContent(next: .confirmed)
        rejected.episodes = (5...24).map { Self.episode($0, title: "Season one \($0)", still: "anime1-banner.jpg") }
        rejected.source = MediaLadderItem(mediaType: "MANGA", mediaId: 30, title: "Jujutsu Kaisen", coverImage: nil, year: 2018,
                                          format: "MANGA", rating: nil, reasonLabel: nil, sourceAuthorName: "Gege Akutami")
        await render(Self.host(AnimeDetailPage(anime: tracked, preview: rejected), graph: graph),
                     width: 390, height: 844, name: "detail-anime-stills-rejected-390", fullPage: true)
        await graph.session.endSession()
    }

    // MARK: Manga

    @Test("Manga detail: facts, next-chapter glance, read run, adaptation cover, More like this")
    func manga() async throws {
        await Self.seedArtwork()
        let suite = "ds-detail-manga-after-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.manga, 30, rowId: 30, status: .current, progress: 67)], for: LifecycleFixtures.userA)
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: [])
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend, flags: flags)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        try? await graph.library.refresh()

        let manga = try Self.manga(id: 30, title: "Chainsaw Man", art: "manga0.jpg", color: "#d9c27a")
        let page = Self.host(MangaDetailPage(manga: manga, preview: try Self.mangaContent(basis: .estimated)), graph: graph)
        await render(page, width: 390, height: 844, name: "detail-manga-top-390")
        await render(page, width: 390, height: 844, name: "detail-manga-full-390", fullPage: true)
        await render(page, width: 320, height: 700, name: "detail-manga-top-320")
        await render(page, width: Self.iPadWidth, height: 1_112, name: "detail-manga-top-ipad")
        let german = await withGerman {
            await render(page, width: 390, height: 844, name: "detail-manga-de-390", fullPage: true)
        }
        #expect(german, "KuroLocale did not pick up the volatile AppleLanguages override")

        // A publisher instant (rare): the solid mark and the bell on the glance.
        let confirmed = Self.host(MangaDetailPage(manga: manga, preview: try Self.mangaContent(basis: .confirmed)), graph: graph)
        await render(confirmed, width: 390, height: 844, name: "detail-manga-glance-confirmed-390")

        await graph.session.endSession()
    }

    // MARK: Hosting

    private static func host<V: View>(_ view: V, graph: AppGraph) -> some View {
        view
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(graph.home)
            .environment(graph.catalog)
            .environment(graph.releases)
            .environment(graph.recommendations)
            .environment(graph.songPreview)
            .environment(graph.social)
            .environment(graph.clubs)
            .environment(graph.availability)
            .environment(graph.flags)
            .environment(graph.outboundLinks)
            .environment(graph.artworkMaterials)
            .environment(graph.identity)
            .environment(graph.banner)
    }

    private func renderAX5<V: View>(_ view: V, width: CGFloat, name: String) async {
        KuroTypeScale.current.update(category: .accessibilityExtraExtraExtraLarge)
        await render(view.environment(\.dynamicTypeSize, .accessibility5), width: width, height: 844, name: name)
        KuroTypeScale.current.update(category: UIApplication.shared.preferredContentSizeCategory)
    }

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

    /// Renders a window at 1 px = 1 pt; `fullPage` scrolls the page in viewport steps and stitches the
    /// frames. Written as JPEG (quality 80), scaled to at most 603 px wide.
    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, fullPage: Bool = false) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(1_800))
        host.view.layoutIfNeeded()
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
                UIColor(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF4 / 255.0, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: total + top))
                for (offset, tile) in tiles {
                    if offset == 0 {
                        tile.draw(at: .zero)
                    } else if let cg = tile.cgImage?.cropping(to: CGRect(x: 0, y: top + 100, width: width, height: viewport - 100)) {
                        // Each later frame drops its top 100 pt, where the journey's compact bar sits.
                        UIImage(cgImage: cg).draw(at: CGPoint(x: 0, y: top + offset + 100))
                    }
                }
            }
        }
        if image.size.width > 603 {
            let scale = 603 / image.size.width
            let size = CGSize(width: 603, height: (image.size.height * scale).rounded())
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        }
        let url = Self.outDir.appendingPathComponent(name + ".jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else { Issue.record("\(name): JPEG encoding failed"); return }
        do {
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
    }

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
    stage for a confrontation. Familiar faces carry a different weight as the story widens.
    """

    private static func artURL(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static let artFiles = ["anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg", "anime0-banner.jpg", "anime1-banner.jpg",
                                   "anime3-banner.jpg", "journal-anime-12-cover.jpg", "journal-anime-16-cover.jpg",
                                   "journal-anime-22-cover.jpg", "journal-manga-13-cover.jpg", "journal-manga-16-cover.jpg",
                                   "journal-manga-23-cover.jpg", "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg",
                                   "detail-character-21.png", "detail-character-22.png", "detail-character-23.png",
                                   "detail-character-24.png", "detail-character-180.png", "detail-character-181.png",
                                   "detail-character-182.png"]

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

    private static func anime(id: Int, title: String, art: String, color: String?, episodes: Int, status: String,
                              score: Int?, format: String = "TV", year: Int = 2023) throws -> Anime {
        var object: [String: Any] = [
            "id": id, "is_adult": false, "genres": ["Action", "Drama"], "created_at": 0, "updated_at": 0,
            "title_english": title, "cover_image_large": artURL(art), "format": format, "status": status,
            "episodes": episodes, "description": synopsis, "season_year": year
        ]
        if let color { object["cover_image_color"] = color }
        if let score { object["average_score"] = score }
        return try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func manga(id: Int, title: String, art: String, color: String?, format: String = "MANGA") throws -> Manga {
        var object: [String: Any] = [
            "id": id, "is_adult": false, "genres": ["Action"], "created_at": 0, "updated_at": 0,
            "title_english": title, "cover_image_large": artURL(art), "format": format, "status": "RELEASING",
            "description": synopsis, "start_date_year": 2018, "volumes": 18, "average_score": 85
        ]
        if let color { object["cover_image_color"] = color }
        return try JSONDecoder().decode(Manga.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func character(_ id: Int, _ name: String, _ art: String?) -> Character {
        Character(id: id, anilistId: id, nameFull: name, nameNative: nil, imageLarge: art.map(artURL), description: nil,
                  gender: nil, age: nil)
    }

    private static func episode(_ number: Int, animeId: Int = 2, title: String? = nil, still: String? = nil) -> Episode {
        Episode(id: animeId * 1_000 + number, animeId: animeId, number: number, title: title, titleRomaji: nil, description: nil,
                airDate: Date(timeIntervalSince1970: 1_789_776_000 + Double(number) * 604_800), airAt: nil,
                thumbnail: still.map(artURL), duration: 24, isFiller: false, isRecap: false, isMixed: false,
                fillerSource: nil, streamUrl: nil, streamSite: nil, createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0))
    }

    private static func similarAnime() throws -> [SimilarTitle] {
        let rows: [(Int, String, String, String, Int)] = [(501, "Chainsaw Man", "anime0.jpg", "TV", 2022),
                                                          (502, "Hell's Paradise", "anime1.jpg", "TV", 2023),
                                                          (503, "Dorohedoro", "anime3.jpg", "ONA", 2020),
                                                          (504, "Mob Psycho 100", "journal-anime-16-cover.jpg", "TV", 2016),
                                                          (505, "Fire Force", "journal-anime-22-cover.jpg", "TV", 2019)]
        let models = try rows.map { try anime(id: $0.0, title: $0.1, art: $0.2, color: nil, episodes: 12, status: "FINISHED",
                                              score: 80, format: $0.3, year: $0.4) }
        // Also the page's own previous season (id 1): it must be dropped by the rail.
        let own = try anime(id: 1, title: "Jujutsu Kaisen", art: "anime2.jpg", color: nil, episodes: 24, status: "FINISHED", score: 85)
        return RecommendationsReader.similarTitles(anime: [own] + models, limit: 12)
    }

    private static func similarManga() throws -> [SimilarTitle] {
        let rows: [(Int, String, String)] = [(601, "Fire Punch", "manga1.jpg"), (602, "Dandadan", "manga2.jpg"),
                                             (603, "Kaiju No. 8", "manga3.jpg"), (604, "Look Back", "journal-manga-16-cover.jpg")]
        let models = try rows.map { try manga(id: $0.0, title: $0.1, art: $0.2, color: nil, format: $0.0 == 604 ? "ONE_SHOT" : "MANGA") }
        return RecommendationsReader.similarTitles(manga: models, limit: 12)
    }

    private static func trackedContent(next basis: ReleaseBasis) throws -> AnimeDetailContent {
        var content = AnimeDetailContent()
        let chain = [LadderChainEntry(mediaId: 1, title: "Jujutsu Kaisen", format: "TV", year: 2020),
                     LadderChainEntry(mediaId: 2, title: "Jujutsu Kaisen Season 2", format: "TV", year: 2023)]
        let seasons = LadderSeasons.seasons(chain: chain, current: 2)
        content.numbered = seasons.numbered
        content.extras = seasons.extras
        content.chainIsProven = true
        content.source = MediaLadderItem(mediaType: "MANGA", mediaId: 30, title: "Jujutsu Kaisen",
                                         coverImage: artURL("journal-manga-23-cover.jpg"), year: 2018,
                                         format: "MANGA", rating: nil, reasonLabel: nil, sourceAuthorName: "Gege Akutami")
        let voices = [CatalogVoiceFixtures.kaji, CatalogVoiceFixtures.hanazawa,
                      Staff(id: 95_014, anilistId: 95_014, nameFull: "Yui Ishikawa", nameNative: nil, imageLarge: nil,
                            description: nil, primaryOccupations: nil), nil]
        content.cast = [("Yuji Itadori", 22, "MAIN"), ("Megumi Fushiguro", 21, "MAIN"), ("Nobara Kugisaki", 23, "MAIN"),
                        ("Satoru Gojo", 24, "SUPPORTING")]
            .enumerated().map { index, item in
                CastMember(character: character(index + 1, item.0, "detail-character-\(item.1).png"), role: item.2,
                           voiceActor: voices[index], language: voices[index] == nil ? nil : "JAPANESE")
            }
        content.staff = [
            (staff: Staff(id: 1, anilistId: nil, nameFull: "Gege Akutami", nameNative: nil, imageLarge: nil, description: nil,
                          primaryOccupations: nil), role: "Original Creator"),
            (staff: Staff(id: 2, anilistId: nil, nameFull: "Shota Goshozono", nameNative: nil, imageLarge: nil, description: nil,
                          primaryOccupations: nil), role: "Director")
        ]
        content.studios = [Studio(id: 1, anilistId: nil, name: "MAPPA", isAnimationStudio: true, siteUrl: nil, favourites: nil)]
        let titles = [5: "Hidden Inventory", 6: "Premature Death", 7: "Episode 7", 8: nil, 9: "Shibuya", 10: nil]
        content.episodes = (5...10).map { number in
            episode(number, title: titles[number] ?? nil, still: number <= 7 ? ["anime0-banner.jpg", "anime1-banner.jpg", "anime3-banner.jpg"][number % 3] : nil)
        }
        content.songs = [
            ThemeSong(kind: .opening, sequence: 1, title: "Where Our Blue Is", artist: "Tatsuya Kitani", episodes: "1–5"),
            ThemeSong(kind: .ending, sequence: 1, title: "Akari", artist: "Soushi Sakiyama", episodes: "1–5"),
        ]
        let now = Date()
        let soon = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now.addingTimeInterval(259_200)
        content.schedule = [
            ReleaseScheduleItem(medium: .anime, mediaId: 2, title: "Jujutsu Kaisen", unitKind: .episode, unitNumber: 8,
                                releaseAt: soon, basis: basis, confidence: 0.9, source: basis == .estimated ? "kuro_estimate" : "anilist",
                                precision: .instant),
            ReleaseScheduleItem(medium: .anime, mediaId: 2, title: "Jujutsu Kaisen", unitKind: .episode, unitNumber: 9,
                                releaseAt: soon.addingTimeInterval(604_800), basis: .estimated, confidence: 0.9,
                                source: "kuro_estimate", precision: .instant),
        ]
        content.similar = try similarAnime()
        content.reminderOn = true
        return content
    }

    private static func mangaContent(basis: ReleaseBasis) throws -> MangaDetailContent {
        var content = MangaDetailContent()
        content.adaptation = MediaLadderItem(mediaType: "ANIME", mediaId: 2, title: "Chainsaw Man", coverImage: artURL("anime0.jpg"),
                                             year: 2022, format: "TV", rating: nil, reasonLabel: nil, sourceAuthorName: nil)
        content.characters = [("Denji", "detail-character-181.png"), ("Power", "detail-character-182.png"),
                               ("Makima", "detail-character-180.png")]
            .enumerated().map { index, item in (character: character(100 + index, item.0, item.1), role: "MAIN") }
        content.authors = [(author: Author(id: 1, anilistId: nil, nameFull: "Tatsuki Fujimoto", nameNative: nil, imageLarge: nil,
                                           description: nil), role: "Story & Art")]
        content.chapters = (66...70).map { number in
            MangaChapter(id: 5_000 + number, mangaId: 30, number: number, title: number == 67 ? "Bang" : "Chapter \(number)",
                         titleRomaji: nil, description: nil,
                         releaseDate: Date(timeIntervalSince1970: 1_560_000_000 + Double(number) * 604_800),
                         releaseAt: nil, thumbnail: nil, pages: nil,
                         createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
        }
        content.readLinks = [ProviderSheetItem(id: "mp", title: "MANGA Plus by SHUEISHA",
                                               url: "https://mangaplus.shueisha.co.jp/titles/100000", subtitle: nil, isVerified: false)]
        let now = Date()
        let soon = Calendar.current.date(byAdding: .day, value: 4, to: now) ?? now.addingTimeInterval(345_600)
        content.schedule = [
            ReleaseScheduleItem(medium: .manga, mediaId: 30, title: "Chainsaw Man", unitKind: .chapter, unitNumber: 68,
                                releaseAt: soon, basis: basis, confidence: 0.9,
                                source: basis == .estimated ? "kuro_estimate" : "publisher",
                                precision: basis == .estimated ? .day : .instant)
        ]
        content.similar = try similarManga()
        content.reminderOn = basis == .confirmed ? false : nil
        return content
    }
}
