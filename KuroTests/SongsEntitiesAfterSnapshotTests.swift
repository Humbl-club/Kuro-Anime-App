import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// "After" fixture renders of the Songs + entities lane (details-songs spec §8, §9, §19.2). No network:
/// the catalogue answers from the in-process stub PostgREST server, the voice readers from their DEBUG
/// seeders, the Library from a fake backend, and the artwork (Apple's included) from `URLCache`. JPEGs
/// (quality 0.8, at most 603 px wide) go to `docs/details-songs-2026-11-03/after/` (`songs-*.jpg` and
/// `entity-*.jpg` only) and only with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; run it with
/// `-only-testing:KuroTests/SongsEntitiesAfterSnapshotTests`. Ordinary runs render into a temporary folder.
@Suite("Songs + entities after renders", .serialized, .timeLimit(.minutes(10)))
@MainActor
struct SongsEntitiesAfterSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-ds-songs-after", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/details-songs-2026-11-03/after")
    }()

    // MARK: Songs

    @Test("Songs: parts, versions, matched / unmatched / spoiler / NSFW rows, playing, failed, offline; 320 and iPad")
    func songs() async throws {
        await Self.seedArtwork()
        let world = try Self.world()
        await Self.signIn(world)
        let material = ArtworkMaterial.fromHex("#5d7f9b")

        // Collapsed (six rows), then all, at 390; the collapsed shelf at 320 and in the iPad column.
        for (width, suffix) in [(CGFloat(390), "390"), (320, "320"), (834, "ipad")] {
            let shelf = Self.shelf(Self.jjkSongs, material: material, progress: 6, showsAll: false)
            await capture(Self.page(shelf, graph: world.graph, player: world.graph.songPreview, ipad: suffix == "ipad"),
                          width: width, height: 1_100, name: "songs-\(suffix)", fits: true)
        }
        await capture(Self.page(Self.shelf(Self.jjkSongs, material: material, progress: 6, showsAll: true),
                                graph: world.graph, player: world.graph.songPreview),
                      width: 390, height: 1_500, name: "songs-all-390", fits: true)

        // Playing: a fake engine that starts at once.
        let playing = SongPreviewPlayer(engine: FixtureEngine(event: .started), audioSession: FixtureAudioSession())
        if let akari = Self.jjkSongs.first(where: { $0.title == "Akari" }) { playing.play(akari) }
        await capture(Self.page(Self.shelf(Self.jjkSongs, material: material, progress: 6, showsAll: false),
                                graph: world.graph, player: playing),
                      width: 390, height: 1_100, name: "songs-playing-390", settle: 2_400, fits: true)
        playing.stop()

        // A preview that failed: "Preview unavailable." and the Apple Music link.
        let failing = SongPreviewPlayer(engine: FixtureEngine(event: .failed), audioSession: FixtureAudioSession())
        if let akari = Self.jjkSongs.first(where: { $0.title == "Akari" }) { failing.play(akari) }
        await capture(Self.page(Self.shelf(Self.jjkSongs, material: material, progress: 6, showsAll: false),
                                graph: world.graph, player: failing),
                      width: 390, height: 1_100, name: "songs-preview-failed-390", fits: true)

        // Offline: ▶ disabled with "You're offline."
        let offline = NetworkMonitor()
        try? await Task.sleep(for: .milliseconds(200))
        offline.isConnected = false
        await capture(Self.page(Self.shelf(Self.jjkSongs, material: material, progress: 6, showsAll: false),
                                graph: world.graph, player: world.graph.songPreview, monitor: offline),
                      width: 390, height: 1_100, name: "songs-offline-390", fits: true, beforeCapture: { offline.isConnected = false })

        // The Apple columns absent live (migration not applied): every row unmatched, AnimeThemes credit only.
        let unmatched = Self.jjkSongs.map {
            ThemeSong(kind: $0.kind, sequence: $0.sequence, title: $0.title, artist: $0.artist, episodes: $0.episodes,
                      version: $0.version, isSpoiler: $0.isSpoiler, isNSFW: $0.isNSFW)
        }
        await capture(Self.page(Self.shelf(unmatched, material: material, progress: 0, showsAll: false),
                                graph: world.graph, player: world.graph.songPreview),
                      width: 390, height: 1_100, name: "songs-unmatched-390", fits: true)

        // One part only (no headings), the episode span on each row; German.
        let single = Self.page(Self.shelf(Self.singlePartSongs, material: ArtworkMaterial.fromHex("#b5473f"), progress: 0,
                                          showsAll: false), graph: world.graph, player: world.graph.songPreview)
        await capture(single, width: 390, height: 760, name: "songs-single-part-390", fits: true)
        let german = await withGerman {
            await capture(Self.page(Self.shelf(Self.jjkSongs, material: material, progress: 6, showsAll: false),
                                    graph: world.graph, player: world.graph.songPreview),
                          width: 390, height: 1_100, name: "songs-de-390", fits: true)
        }
        #expect(german, "KuroLocale did not pick up the volatile AppleLanguages override")
        await world.tearDown()
    }

    // MARK: Character page

    @Test("Character page: voice card, appears-in rail with refine words, in your list; 320, iPad; no voice; loading")
    func characterPage() async throws {
        await Self.seedArtwork()
        let world = try Self.world()
        await Self.signIn(world)
        let gojo = Self.character(4_201, "Satoru Gojo", "五条悟", image: Self.art("journal-anime-16-cover.jpg"),
                                  description: Self.gojoDescription, gender: "Male", age: "28")
        world.graph.catalog.seedFixtureVoiceActors(characterId: gojo.id, credits: [
            VoiceActorCredit(staff: Self.nakamura, language: "JAPANESE", animeIds: [401]),
        ])
        world.graph.catalog.seedFixtureVoiceRoles(staffId: Self.nakamura.id, roles: Self.nakamuraRoles,
                                                 limit: EntityPageLayout.voiceRoleLimit)
        for (width, suffix) in [(CGFloat(390), "390"), (320, "320"), (834, "ipad")] {
            await capture(Self.journey(.character(gojo), graph: world.graph, ipad: suffix == "ipad"),
                          width: width, height: 1_400, name: "entity-character-\(suffix)", settle: 2_200)
        }
        await capture(Self.journey(.character(gojo), graph: world.graph), width: 390, height: 844,
                      name: "entity-character-top-390", settle: 2_200, crop: false)

        // The voice contract absent live: no voice card, nothing invented.
        let noVoice = Self.character(4_202, "Megumi Fushiguro", "伏黒恵", image: Self.art("journal-anime-22-cover.jpg"),
                                     description: nil, gender: nil, age: nil)
        await capture(Self.journey(.character(noVoice), graph: world.graph), width: 390, height: 1_200,
                      name: "entity-character-no-voice-390", settle: 2_200)
        await world.tearDown()

        // Loading: the works read held back.
        let gate = StubGate()
        let held = try Self.world(responder: { _ in StubResponse.json("[]").held(by: gate) })
        await capture(Self.journey(.character(gojo), graph: held.graph), width: 390, height: 844,
                      name: "entity-character-loading-390", settle: 1_200, crop: false)
        gate.open()
        await held.tearDown()
    }

    // MARK: Staff pages

    @Test("Staff pages: a voice actor (roles, characters you know, works) and a director (role words)")
    func staffPages() async throws {
        await Self.seedArtwork()
        let world = try Self.world()
        await Self.signIn(world)
        world.graph.catalog.seedFixtureVoiceRoles(staffId: Self.nakamura.id, roles: Self.nakamuraRoles,
                                                 limit: EntityPageLayout.voiceRoleLimit)
        await capture(Self.journey(.staff(Self.nakamura), graph: world.graph), width: 390, height: 1_900,
                      name: "entity-staff-voice-390", settle: 2_200)
        let director = Staff(id: 5_001, anilistId: 5_001, nameFull: "Sunghoo Park", nameNative: "朴性厚", imageLarge: nil,
                             description: "Director and storyboard artist.", primaryOccupations: ["Director", "Storyboard"])
        world.graph.catalog.seedFixtureVoiceRoles(staffId: director.id, roles: [],
                                                 limit: EntityPageLayout.voiceRoleLimit)
        await capture(Self.journey(.staff(director), graph: world.graph), width: 390, height: 1_400,
                      name: "entity-staff-director-390", settle: 2_200)
        await world.tearDown()
    }

    // MARK: Studio and author

    @Test("Studio (cover line, in your list, most loved, by year, a year page) and author pages")
    func studioAndAuthor() async throws {
        await Self.seedArtwork()
        let world = try Self.world()
        await Self.signIn(world)
        let mappa = Studio(id: 569, anilistId: 569, name: "MAPPA", isAnimationStudio: true, siteUrl: nil, favourites: nil)
        await capture(Self.journey(.studio(mappa), graph: world.graph), width: 390, height: 1_500,
                      name: "entity-studio-390", settle: 2_200)
        await capture(Self.journey(.studio(mappa), graph: world.graph), width: 320, height: 1_500,
                      name: "entity-studio-320", settle: 2_200)
        let busy = EntityWorks.byYear(Self.studioWorks.map { Self.media($0) }).first { !$0.isInline }
        if let busy {
            await capture(Self.journey(EntityYearPage.page(studioName: "MAPPA", group: busy), graph: world.graph),
                          width: 390, height: 900, name: "entity-studio-year-390", settle: 1_600)
        }
        let author = Author(id: 7_001, anilistId: 7_001, nameFull: "Gege Akutami", nameNative: "芥見下々", imageLarge: nil,
                            description: "Manga artist.")
        await capture(Self.journey(.author(author), graph: world.graph), width: 390, height: 1_200,
                      name: "entity-author-390", settle: 2_200)
        await world.tearDown()
    }

    // MARK: World

    private struct World {
        let server: StubServer
        let graph: AppGraph
        let defaults: UserDefaults
        let suite: String

        func tearDown() async {
            await graph.session.endSession()
            defaults.removePersistentDomain(forName: suite)
            server.shutDown()
        }
    }

    private static func world(responder: StubServer.Responder? = nil) throws -> World {
        let server = StubServer()
        server.respond(with: responder ?? Self.responder)
        let suite = "ds-songs-after-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let backend = FakeLibraryBackend()
        backend.setRows([
            FakeLibraryBackend.entry(.anime, 401, rowId: 1, status: .current, progress: 6),
            FakeLibraryBackend.entry(.manga, 411, rowId: 2, status: .planning, progress: 0),
        ], for: LifecycleFixtures.userA)
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                client: StubSupabase.makeClient(server: server), libraryBackend: backend)
        return World(server: server, graph: graph, defaults: defaults, suite: suite)
    }

    /// The fake backend's rows reach the Library once the session starts.
    private static func signIn(_ world: World) async {
        _ = await world.graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        try? await world.graph.library.refresh()
    }

    // MARK: Hosting

    private static func shelf(_ songs: [ThemeSong], material: ArtworkMaterial, progress: Int, showsAll: Bool) -> some View {
        DetailSongShelf(songs: songs, material: material, progress: progress, showsAll: .constant(showsAll), onCollapse: {})
    }

    /// The shelf on detail paper with the 24 pt gutter (the iPad column is 680 pt, as the detail body).
    private static func page<V: View>(_ shelf: V, graph: AppGraph, player: SongPreviewPlayer,
                                      monitor: NetworkMonitor? = nil, ipad: Bool = false) -> AnyView {
        let body = shelf
            .padding(.horizontal, EntityPageLayout.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: ipad ? KuroReadableWidth.maxWidth : .infinity)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Color.kuroPaper)
        return inject(body, graph: graph, monitor: monitor ?? NetworkMonitor(), player: player)
    }

    private static func journey(_ root: JourneyPage, graph: AppGraph, ipad: Bool = false) -> AnyView {
        let host = JourneyHost(navigator: JourneyNavigator(root: root))
            .environment(\.horizontalSizeClass, ipad ? .regular : .compact)
        return inject(host, graph: graph, monitor: NetworkMonitor(), player: graph.songPreview, routes: false)
    }

    private static func inject<V: View>(_ view: V, graph: AppGraph, monitor: NetworkMonitor, player: SongPreviewPlayer,
                                        routes: Bool = true) -> AnyView {
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
            .environment(player)
            .environment(monitor)
        return routes ? AnyView(base.environment(\.kuroRoutes, KuroRoutes.unhandled)) : AnyView(base)
    }

    /// Runs `body` with German as the first preferred language (process-volatile argument domain only).
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

    // MARK: Capture

    /// Renders `view` in a window `height` tall, crops to the page's content (unless `crop` is false) and
    /// writes a JPEG at quality 0.8, at most 603 px wide.
    private func capture(_ view: AnyView, width: CGFloat, height requested: CGFloat, name: String, settle: Int = 1_500,
                         crop: Bool = true, fits: Bool = false, beforeCapture: (() -> Void)? = nil) async {
        // A shelf (no scroll view) is captured at its own height.
        let height = fits ? ceil(UIHostingController(rootView: view.frame(width: width))
            .sizeThatFits(in: CGSize(width: width, height: 10_000)).height) : requested
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        host.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.isHidden = false
        window.makeKey()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = UIColor(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF4 / 255.0, alpha: 1)
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(settle))
        beforeCapture?()
        try? await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()
        let shown = crop && !fits ? Self.contentHeight(in: window) : height
        // Draw the whole window (drawing into a shorter rect would squash it), then crop to the content.
        guard let png = FixtureRaster.png(of: window, size: CGSize(width: width, height: height), diagnosticScale: nil),
              let full = UIImage(data: png)?.cgImage,
              let cropped = full.cropping(to: CGRect(x: 0, y: 0, width: full.width,
                                                     height: min(full.height, Int((shown * CGFloat(full.height) / height).rounded())))) else {
            Issue.record("\(name): rendering failed")
            return
        }
        let image = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        let maxWidth: CGFloat = 603
        var output = image
        if image.size.width > maxWidth {
            let scale = maxWidth / image.size.width
            let size = CGSize(width: maxWidth, height: (image.size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let data = output.jpegData(compressionQuality: 0.8) else {
            Issue.record("\(name): JPEG encoding failed")
            return
        }
        do {
            try data.write(to: Self.outDir.appendingPathComponent("\(name).jpg"))
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
    }

    /// The tallest page scroll view's content height (or a shelf's measured height), capped at the window, so
    /// captures end with the page.
    private static func contentHeight(in window: UIWindow) -> CGFloat {
        var best: CGFloat = 0
        var stack: [UIView] = [window]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.window != nil, !scroll.isHidden,
               scroll.bounds.width >= window.bounds.width * 0.6 {
                // Where the content ends in the window: the scroll view's top, its inset, the content.
                let top = scroll.convert(CGPoint.zero, to: window).y
                best = max(best, top + scroll.adjustedContentInset.top + scroll.contentSize.height
                           + scroll.adjustedContentInset.bottom)
            }
            stack.append(contentsOf: view.subviews)
        }
        return best > 0 ? min(ceil(best), window.bounds.height) : window.bounds.height
    }

    // MARK: Artwork

    private static let artFiles: [String] = [
        "anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg", "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg",
        "journal-anime-12-cover.jpg", "journal-anime-16-cover.jpg", "journal-anime-22-cover.jpg",
        "journal-manga-13-cover.jpg", "journal-manga-16-cover.jpg", "journal-manga-23-cover.jpg",
    ]

    nonisolated static func art(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    /// Apple's artwork for fixture track `id` (600 px as stored; the shelf asks for 132 px).
    nonisolated static func appleArt(_ id: Int) -> String {
        "https://is1-ssl.mzstatic.com/image/thumb/Music/fixture\(id)/600x600bb.jpg"
    }

    private static func seedArtwork() async {
        func store(_ data: Data, at raw: String) {
            guard let url = URL(string: raw),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { return }
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                                                for: URLRequest(url: url))
        }
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)) else { continue }
            store(data, at: art(file))
        }
        // Apple artwork stand-ins (the 132 px URL the shelf requests).
        for (id, file) in [(1_001, "anime1.jpg"), (1_002, "anime3.jpg"), (1_003, "manga2.jpg"), (1_004, "anime0.jpg")] {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let resized = SongShelfGrouping.artworkURL(URL(string: appleArt(id)), side: 132) else { continue }
            store(data, at: resized.absoluteString)
        }
    }

    // MARK: Fixtures: songs

    nonisolated static func apple(_ id: Int, preview: Bool = true) -> AppleSongMatch? {
        AppleSongMatch(trackId: id, artwork: appleArt(id),
                       preview: preview ? "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/fixture\(id).m4a" : nil,
                       music: "https://music.apple.com/jp/album/fixture/\(id + 1)?i=\(id)", confidence: 0.96)
    }

    /// A two-cour show: an unmatched OP1 (an alias the strict matcher does not accept), a matched ED1, OP2 in
    /// three versions (the last a TV size), a matched ED2 without a preview, a spoiler ED3 already reached by
    /// progress (auto-revealed), a spoiler insert song not yet reached, an NSFW song and a song without an artist.
    nonisolated static let jjkSongs: [ThemeSong] = [
        ThemeSong(kind: .opening, sequence: 1, title: "Ao no Sumika", artist: "Tatsuya Kitani", episodes: "1-5"),
        ThemeSong(kind: .ending, sequence: 1, title: "Akari", artist: "Soushi Sakiyama", episodes: "1-5", apple: apple(1_001)),
        ThemeSong(kind: .opening, sequence: 2, title: "SPECIALZ", artist: "King Gnu", episodes: "6-16, 18-19", version: 1,
                  apple: apple(1_002)),
        ThemeSong(kind: .opening, sequence: 2, title: "SPECIALZ", artist: "King Gnu", episodes: "20-22", version: 2),
        ThemeSong(kind: .opening, sequence: 2, title: "SPECIALZ (TV Size)", artist: "King Gnu", episodes: "23", version: 3),
        ThemeSong(kind: .ending, sequence: 2, title: "more than words", artist: "Hitsujibungaku", episodes: "6-23",
                  isSpoiler: true, apple: apple(1_003, preview: false)),
        ThemeSong(kind: .insert, sequence: 1, title: "Inner Mother", artist: "Insert Artist", episodes: "17", isSpoiler: true,
                  apple: apple(1_004)),
        ThemeSong(kind: .insert, sequence: 2, title: "Shibuya Night", artist: nil, episodes: "18"),
        ThemeSong(kind: .ending, sequence: 3, title: "Late Night Song", artist: "Someone", episodes: "21", isNSFW: true),
    ]

    nonisolated static let singlePartSongs: [ThemeSong] = [
        ThemeSong(kind: .opening, sequence: 1, title: "Gurenge", artist: "LiSA", episodes: "1-19", apple: apple(1_001)),
        ThemeSong(kind: .ending, sequence: 1, title: "from the edge", artist: "FictionJunction feat. LiSA", episodes: "1-25"),
        ThemeSong(kind: .insert, sequence: 1, title: "Kamado Tanjiro no Uta", artist: "Go Shiina feat. Nami Nakagawa",
                  episodes: "19"),
    ]

    // MARK: Fixtures: people and works

    static let nakamura = Staff(id: 95_084, anilistId: 95_084, nameFull: "Yuuichi Nakamura", nameNative: "中村悠一",
                                imageLarge: nil, description: nil, primaryOccupations: ["Voice Actor"])

    static func character(_ id: Int, _ name: String, _ native: String?, image: String?, description: String?,
                          gender: String?, age: String?) -> Character {
        Character(id: id, anilistId: id, nameFull: name, nameNative: native, imageLarge: image,
                  description: description, gender: gender, age: age)
    }

    static let gojoDescription = """
    __Height:__ 190 cm<br><br>A teacher at Tokyo Jujutsu High with an unconventional approach to everything, from lessons \
    to lunch. He is the strongest sorcerer of his generation, and he knows it. ~!He is sealed in the Prison Realm.!~ \
    He wants a generation of students strong enough to change the world he grew up in.
    """

    static var nakamuraRoles: [VoiceRole] {
        func role(_ id: Int, _ name: String, _ anime: Int, _ title: String, _ art: String?, year: Int, main: Bool = true) -> VoiceRole {
            VoiceRole(character: character(id, name, nil, image: nil, description: nil, gender: nil, age: nil),
                      role: main ? "MAIN" : "SUPPORTING", language: "JAPANESE",
                      anime: VoiceRoleAnime(id: anime, titleEnglish: title, titleRomaji: nil, titleNative: nil,
                                            coverImageLarge: art, format: "TV", year: year))
        }
        return [
            VoiceRole(character: character(4_201, "Satoru Gojo", "五条悟", image: art("journal-anime-16-cover.jpg"),
                                           description: nil, gender: nil, age: nil),
                      role: "MAIN", language: "JAPANESE",
                      anime: VoiceRoleAnime(id: 401, titleEnglish: "Jujutsu Kaisen", titleRomaji: nil, titleNative: nil,
                                            coverImageLarge: art("anime2.jpg"), format: "TV", year: 2020)),
            role(4_301, "Gray Fullbuster", 501, "Fairy Tail", nil, year: 2009),
            role(4_302, "Tomoya Okazaki", 502, "Clannad", art("anime1.jpg"), year: 2007),
            role(4_303, "Bruno Bucciarati", 503, "JoJo's Bizarre Adventure: Golden Wind", nil, year: 2018),
            role(4_304, "Kyo Sohma", 504, "Fruits Basket", art("anime3.jpg"), year: 2019, main: false),
        ]
    }

    /// (id, kind, title, cover, year, score, format)
    nonisolated static let characterWorks: [(Int, MediaKind, String, String?, Int, Int, String)] = [
        (401, .anime, "Jujutsu Kaisen", "anime2.jpg", 2020, 86, "TV"),
        (411, .manga, "Jujutsu Kaisen", "manga1.jpg", 2018, 85, "MANGA"),
        (402, .anime, "Jujutsu Kaisen 0", nil, 2021, 84, "MOVIE"),
        (412, .manga, "Jujutsu Kaisen 0", nil, 2017, 80, "MANGA"),
        (403, .anime, "Jujutsu Kaisen Season 2", "anime0.jpg", 2023, 88, "TV"),
    ]

    nonisolated static let studioWorks: [(Int, MediaKind, String, String?, Int, Int, String)] = [
        (401, .anime, "Jujutsu Kaisen", "anime2.jpg", 2020, 86, "TV"),
        (403, .anime, "Jujutsu Kaisen Season 2", "anime0.jpg", 2023, 88, "TV"),
        (421, .anime, "Chainsaw Man", nil, 2022, 85, "TV"),
        (422, .anime, "Vinland Saga Season 2", "anime3.jpg", 2023, 88, "TV"),
        (423, .anime, "Hell's Paradise", nil, 2023, 80, "TV"),
        (424, .anime, "Zombieland Saga", "anime1.jpg", 2023, 76, "TV"),
        (402, .anime, "Jujutsu Kaisen 0", nil, 2021, 84, "MOVIE"),
    ]

    static func media(_ work: (Int, MediaKind, String, String?, Int, Int, String)) -> Media {
        Media(id: work.0, kind: work.1, title: work.2, imageURL: work.3.map(art), year: String(work.4), displayDescription: "",
              episodes: work.1 == .anime ? 24 : nil, chapters: nil, rating: Double(work.5), genres: nil,
              statusRaw: "FINISHED", formatRaw: work.6, popularityValue: nil, trendingValue: nil, createdAtValue: nil)
    }

    nonisolated private static func animeEmbed(_ work: (Int, MediaKind, String, String?, Int, Int, String)) -> String {
        let cover = work.3.map { "\"\(art($0))\"" } ?? "null"
        return """
        {"id":\(work.0),"title_english":"\(work.2)","title_romaji":null,"cover_image_large":\(cover),"average_score":\(work.5),\
        "season_year":\(work.4),"format":"\(work.6)","status":"FINISHED","genres":["Action"],"is_adult":false,"episodes":24}
        """
    }

    nonisolated private static func mangaEmbed(_ work: (Int, MediaKind, String, String?, Int, Int, String)) -> String {
        let cover = work.3.map { "\"\(art($0))\"" } ?? "null"
        return """
        {"id":\(work.0),"title_english":"\(work.2)","title_romaji":null,"cover_image_large":\(cover),"average_score":\(work.5),\
        "start_date_year":\(work.4),"format":"\(work.6)","status":"FINISHED","genres":["Action"],"is_adult":false,"chapters":271}
        """
    }

    nonisolated private static let responder: StubServer.Responder = { request in
        let anime = characterWorks.filter { $0.1 == .anime }
        let manga = characterWorks.filter { $0.1 == .manga }
        switch request.resource ?? "" {
        case "anime_characters":
            return .json("[" + anime.map { "{\"anime\":\(animeEmbed($0))}" }.joined(separator: ",") + "]")
        case "manga_characters":
            return .json("[" + manga.map { "{\"manga\":\(mangaEmbed($0))}" }.joined(separator: ",") + "]")
        case "anime_studios":
            return .json("[" + studioWorks.map { "{\"anime\":\(animeEmbed($0))}" }.joined(separator: ",") + "]")
        case "anime_staff":
            let rows = [("Director", studioWorks[2]), ("Director", studioWorks[0]), ("Storyboard", studioWorks[1]),
                        ("Episode Director", studioWorks[3]), ("Storyboard", studioWorks[6])]
            return .json("[" + rows.map { "{\"role\":\"\($0.0)\",\"anime\":\(animeEmbed($0.1))}" }.joined(separator: ",") + "]")
        case "manga_staff":
            return .emptyArray
        case "manga_authors":
            let rows = [("Story & Art", characterWorks[1]), ("Story & Art", characterWorks[3]),
                        ("Story", (430, MediaKind.manga, "Tokyo Jujutsu High", nil as String?, 2017, 72, "ONE_SHOT"))]
            return .json("[" + rows.map { "{\"role\":\"\($0.0)\",\"manga\":\(mangaEmbed($0.1))}" }.joined(separator: ",") + "]")
        default:
            return .emptyArray
        }
    }
}

// MARK: - Preview engine stand-ins (no audio in renders)

@MainActor
private final class FixtureEngine: SongPreviewEngine {
    let event: SongPreviewEvent
    init(event: SongPreviewEvent) { self.event = event }
    func play(_ url: URL, onEvent: @escaping @MainActor (SongPreviewEvent) -> Void) {
        let event = self.event
        Task { @MainActor in onEvent(event) }
    }
    func stop() {}
}

@MainActor
private final class FixtureAudioSession: SongPreviewAudioSession {
    func activateForPreview() throws {}
    func deactivateAfterPreview() {}
}
