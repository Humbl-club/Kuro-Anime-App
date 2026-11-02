import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Fixture renders of the prototype manga detail (Task 7) for the fidelity review against
/// docs/prototype-fidelity/reference/ref-detail-manga-390.png. No network: the page gets a complete
/// `MangaDetailContent` (which turns its reads off), the Library is a fake backend, the artwork is
/// seeded into `URLCache`. PNGs are written to docs/prototype-fidelity/native/detail/ only with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; ordinary runs render into a temporary folder.
@Suite("Detail manga snapshots", .serialized, .timeLimit(.minutes(3)))
@MainActor
struct DetailMangaSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-detail-manga", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/detail")
    }()

    @Test("Manga detail: tracked book with club, flags-on bundle, untracked placeholder chapters")
    func mangaDetail() async throws {
        await Self.seedArtwork()
        let suite = "detail-manga-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.manga, 30, rowId: 30, status: .current, progress: 24)],
                        for: LifecycleFixtures.userA)
        // social_activity_v1 on (live: 100 %): "Between us." and the club row need it.
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=social_activity_v1"])
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend, flags: flags)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        try? await graph.library.refresh()
        graph.clubs.myClubs = try Self.clubs()

        let tracked = try Self.manga(id: 30, title: "Chainsaw Man", art: "manga0.jpg", color: "#e4a15d", chapters: 97,
                                     status: "FINISHED", synopsis: Self.synopsis)
        let page = Self.host(MangaDetailPage(manga: tracked, preview: Self.trackedContent()), graph: graph)
        await render(page, width: 390, height: 844, name: "detail-manga-390.png", fullPage: true)
        await render(page, width: 390, height: 844, name: "detail-manga-top-390.png")
        await render(page, width: 320, height: 844, name: "detail-manga-top-320.png")
        // Review focus 1: the folio hero and Up next at the largest accessibility size.
        await renderAX5(page, width: 320, name: "detail-manga-top-ax5-320.png")
        await renderAX5(page, width: 320, name: "detail-manga-ax5-320.png", fullPage: true)

        // Series flags on with bundle data: the serif `detail_copy` hook + premise and the watched guide.
        var withBundle = Self.trackedContent()
        withBundle.bundle = try Self.bundle()
        await render(Self.host(MangaDetailPage(manga: tracked, preview: withBundle), graph: graph),
                     width: 390, height: 844, name: "detail-manga-bundle-390.png", fullPage: true)

        // An untracked, still-running book opened from Discover: placeholder chapters only, no credits,
        // no adaptation, no club. Hero with "Not in your list" + Add, the story and the publisher row.
        let sparse = try Self.manga(id: 77, title: "A Very Long Untranslated Manga Title That Wraps", art: "journal-manga-13-cover.jpg",
                                    color: nil, chapters: nil, status: "RELEASING", synopsis: Self.synopsis)
        var sparseContent = MangaDetailContent()
        sparseContent.chapters = (1...5).map { Self.chapter($0, mangaId: 77, dated: false) }
        sparseContent.readLinks = [ProviderSheetItem(id: "mp", title: "MANGA Plus by SHUEISHA",
                                                     url: "https://mangaplus.shueisha.co.jp/titles/100000",
                                                     subtitle: nil, isVerified: false)]
        graph.clubs.myClubs = []
        await render(Self.host(MangaDetailPage(manga: sparse, preview: sparseContent), graph: graph),
                     width: 390, height: 844, name: "detail-manga-untracked-390.png", fullPage: true)
        // German, untracked, long title: the status mark's Add drops under the mark; the heading keeps
        // clear of the close control.
        let germanRendered = await withGerman {
            let germanPage = Self.host(MangaDetailPage(manga: sparse, preview: sparseContent), graph: graph)
            await render(germanPage, width: 390, height: 844, name: "detail-manga-untracked-de-390.png")
            await render(germanPage, width: 320, height: 844, name: "detail-manga-untracked-de-320.png")
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
                UIColor(red: 0xF6 / 255.0, green: 0xF5 / 255.0, blue: 0xEF / 255.0, alpha: 1).setFill()
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
    Denji is a teenage boy living with a Chainsaw Devil named Pochita. Due to the debt his father left behind, \
    he has been living a rock-bottom life while repaying his debt by harvesting devil corpses with Pochita.
    """

    private static func artURL(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static let artFiles = ["manga0.jpg", "journal-manga-13-cover.jpg", "detail-character-180.png",
                                   "detail-character-181.png", "detail-character-182.png"]

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

    private static func manga(id: Int, title: String, art: String, color: String?, chapters: Int?, status: String,
                              synopsis: String) throws -> Manga {
        var object: [String: Any] = [
            "id": id, "is_adult": false, "genres": ["Action"], "created_at": 0, "updated_at": 0,
            "title_english": title, "cover_image_large": artURL(art), "format": "MANGA", "status": status,
            "description": synopsis, "start_date_year": 2018
        ]
        if let chapters { object["chapters"] = chapters }
        if let color { object["cover_image_color"] = color }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Manga.self, from: data)
    }

    private static func chapter(_ number: Int, mangaId: Int = 30, dated: Bool = true) -> MangaChapter {
        MangaChapter(id: 5_000 + number, mangaId: mangaId, number: number, title: "Chapter \(number)", titleRomaji: nil,
                     description: nil, releaseDate: dated ? Date(timeIntervalSince1970: 1_560_000_000 + Double(number) * 604_800) : nil,
                     releaseAt: nil, thumbnail: nil, pages: nil,
                     createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    private static func bundle() throws -> SeriesDetailBundle {
        let json = """
        {"medium":"manga","media_id":30,"series_id":"33333333-3333-4333-8333-333333333333","section_id":null,
         "header":{"media_id":30,"title":"Chainsaw Man","format":"MANGA","catalogue_status":"FINISHED","chapters":97},
         "sections":[],"units":[],"units_state":"ok",
         "copy":{"hook":"Small dreams. Monstrous consequences.",
                 "premise":"A broke young devil hunter gets a second chance at life, with a chainsaw for a heart.",
                 "synopsis":"\(synopsis)","story_state":"present"},
         "themes":[],"cast":[],"coverage":null,
         "adaptations":[{"source_kind":"manga","mapping_state":"exact","starts_at":"Ch. 1","ends_at":"Ch. 38",
                         "read_next":"Ch. 39","source_manga_id":30,"anime_id":127230,"season":"Season 1"}]}
        """
        return try JSONDecoder().decode(SeriesDetailBundle.self, from: Data(json.utf8))
    }

    private static func clubs() throws -> [ClubListRow] {
        let json = #"[{"id":"club-1","name":"Sunday Club","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z"}]"#
        return try JSONDecoder().decode([ClubListRow].self, from: Data(json.utf8))
    }

    private static func trackedContent() -> MangaDetailContent {
        var content = MangaDetailContent()
        content.adaptation = MediaLadderItem(mediaType: "ANIME", mediaId: 127230, title: "Chainsaw Man", coverImage: nil, year: 2022,
                                             format: "TV", rating: nil, reasonLabel: nil, sourceAuthorName: nil)
        content.characters = [("Power", 180), ("Aki Hayakawa", 182), ("Makima", 181)]
            .enumerated().map { index, item in
                (character: Character(id: index + 1, anilistId: nil, nameFull: item.0, nameNative: nil,
                                      imageLarge: artURL("detail-character-\(item.1).png"), description: nil, gender: nil, age: nil),
                 role: "MAIN")
            }
        content.authors = [(author: Author(id: 1, anilistId: nil, nameFull: "Tatsuki Fujimoto", nameNative: nil, imageLarge: nil,
                                           description: nil), role: "Story & Art")]
        content.chapters = (24...33).map { chapter($0) }
        content.readLinks = [ProviderSheetItem(id: "mp", title: "MANGA Plus by SHUEISHA",
                                               url: "https://mangaplus.shueisha.co.jp/titles/100037", subtitle: nil, isVerified: false),
                             ProviderSheetItem(id: "viz", title: "VIZ", url: "https://www.viz.com/shonenjump/chapters/chainsaw-man",
                                               subtitle: nil, isVerified: false)]
        // The adaptation's official site (its external links): "Official anime site ↗", as the reference.
        content.adaptationSite = URL(string: "https://chainsawman.dog/")
        let friends = ["Mina", "Jules", "Noah"].enumerated().map { index, name in
            SocialActivityStore.FriendTitleActivity(user_id: "u\(index)", display_name: name, status: "CURRENT",
                                                    progress: 20 + index, rating: nil, updated_at: nil)
        }
        let comments = [
            SocialActivityStore.TitleComment(id: "c1", user_id: "u0", display_name: "Mina",
                                             text: "The contrast between tiny everyday wishes and total chaos is everything.",
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
