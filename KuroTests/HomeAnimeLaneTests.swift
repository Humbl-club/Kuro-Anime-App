import CoreGraphics
import ImageIO
import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Prototype-fidelity Task 4 (Home, anime): the opening line (LANE_AMENDMENTS 3), scene cards, Also
/// watching, the Coming up glance and the medium word's contrast floor (amendment 7), plus fixture
/// renders of the busy / full / undated / quiet anime Home next to `docs/prototype-fidelity/reference`.
@Suite("Home anime lane", .serialized, .timeLimit(.minutes(4)))
@MainActor
struct HomeAnimeLaneTests {
    // MARK: Opening line

    @Test("Opening line copy: new units, caught up, new account, EN and DE")
    func openingLineCopy() {
        #expect(HomeOpeningLine.headline(available: 2, caughtUp: false, newAccount: false, medium: .anime, german: false) == "2 new episodes")
        #expect(HomeOpeningLine.headline(available: 1, caughtUp: false, newAccount: false, medium: .anime, german: false) == "1 new episode")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .anime, german: false) == "Keep watching.")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: false, newAccount: true, medium: .anime, german: false) == "Begin here.")
        #expect(HomeOpeningLine.headline(available: 4, caughtUp: false, newAccount: false, medium: .manga, german: false) == "4 new chapters")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .manga, german: false) == "Keep reading.")
        #expect(HomeOpeningLine.quietLine(german: false) == "Nothing new today. Stay at your own pace.")

        #expect(HomeOpeningLine.headline(available: 2, caughtUp: false, newAccount: false, medium: .anime, german: true) == "2 neue Folgen")
        #expect(HomeOpeningLine.headline(available: 1, caughtUp: false, newAccount: false, medium: .manga, german: true) == "1 neues Kapitel")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .anime, german: true) == "Weiterschauen.")
        #expect(HomeOpeningLine.headline(available: 0, caughtUp: false, newAccount: true, medium: .anime, german: true) == "Fang hier an.")
        #expect(HomeOpeningLine.quietLine(german: true) == "Heute nichts Neues. Bleib in deinem Tempo.")

        #expect(HomeOpeningLine.kicker(newAccount: false, medium: .anime, german: false) == "Now watching")
        #expect(HomeOpeningLine.kicker(newAccount: false, medium: .manga, german: false) == "Now reading")
        #expect(HomeOpeningLine.kicker(newAccount: true, medium: .anime, german: false) == "Your collection")
    }

    @Test("Caught up (amendment 3): the headline is 'Keep watching.' and the quiet line is a separate card")
    func caughtUpQuietCard() {
        let headline = HomeOpeningLine.headline(available: 0, caughtUp: true, newAccount: false, medium: .anime, german: false)
        #expect(headline == "Keep watching.")
        #expect(!headline.contains("Nothing new"), "The quiet line is never folded into the headline.")
        #expect(HomeOpeningLine.showsQuietLine(available: 0, caughtUp: true, newAccount: false))
        #expect(!HomeOpeningLine.showsQuietLine(available: 1, caughtUp: false, newAccount: false))
        #expect(!HomeOpeningLine.showsQuietLine(available: 0, caughtUp: false, newAccount: false),
                "Unknown availability is not caught up: no quiet card.")
        #expect(!HomeOpeningLine.showsQuietLine(available: 0, caughtUp: true, newAccount: true))
    }

    // MARK: Scenes and Also watching

    @Test("Scene card shows at most two titles; the rest go to Also watching")
    func sceneCardsAtMostTwo() throws {
        let cards = try (1...5).map { try Self.card($0, "WATCHING") }
        let lanes = HomeShelfPolicy.scenes(cards)
        #expect(lanes.scenes.map(\.mediaId) == [1, 2])
        #expect(lanes.alsoWatching.map(\.mediaId) == [3, 4, 5])
        let two = HomeShelfPolicy.scenes(Array(cards.prefix(2)))
        #expect(two.scenes.count == 2 && two.alsoWatching.isEmpty)
    }

    @Test("Planned titles never become scene cards or Also watching tiles")
    func plannedNeverScenes() throws {
        let cards = [try Self.card(1, "PLANNING"), try Self.card(2, "WATCHING"), try Self.card(3, "PLANNING"),
                     try Self.card(4, "CURRENT"), try Self.card(5, "PAUSED"), try Self.card(6, "WATCHING")]
        let lanes = HomeShelfPolicy.scenes(cards)
        #expect(lanes.scenes.map(\.mediaId) == [2, 4])
        #expect(lanes.alsoWatching.map(\.mediaId) == [6])
        #expect(!(lanes.scenes + lanes.alsoWatching).contains { $0.listType == "PLANNING" })
    }

    @Test("Season tab omitted when the ladder number is unknown; never an invented Season 1")
    func seasonTabNeedsLadderNumber() {
        #expect(HomeSeasonTab.make(sectionOrdinal: nil, sectionKind: "season", german: false) == nil)
        #expect(HomeSeasonTab.make(sectionOrdinal: nil, sectionKind: nil, german: false) == nil)
        #expect(HomeSeasonTab.make(sectionOrdinal: 0, sectionKind: "season", german: false) == nil)
        #expect(HomeSeasonTab.make(sectionOrdinal: 2, sectionKind: "season", german: false)
                == HomeSeasonTab(word: "Season", number: "2"))
        #expect(HomeSeasonTab.make(sectionOrdinal: 2, sectionKind: "season", german: true)?.word == "Staffel")
        #expect(HomeSeasonTab.make(sectionOrdinal: nil, sectionKind: "film", german: false)
                == HomeSeasonTab(word: nil, number: "Film"))
    }

    @Test("longTitleNeverOverlapsKey: a fixed 44 pt key column; titles wrap to two lines, then truncate")
    func longTitleNeverOverlapsKey() {
        #expect(HomeSceneMetrics.keyColumn == 44)
        #expect(HomeSceneMetrics.sceneTitleLines(accessibility: false) == 2)
        #expect(HomeSceneMetrics.sceneTitleLines(accessibility: true) == 3)
        #expect(HomeSceneMetrics.tileTitleLines(accessibility: false) == 3)
        // At accessibility sizes the readout and key move under the title, and Also watching is one column.
        #expect(HomeSceneMetrics.stacksSceneFoot(accessibility: true))
        #expect(!HomeSceneMetrics.stacksSceneFoot(accessibility: false))
        #expect(HomeSceneMetrics.alsoWatchingColumns(accessibility: false) == 2)
        #expect(HomeSceneMetrics.alsoWatchingColumns(accessibility: true) == 1)
        #expect(HomeSceneMetrics.isCompact(columnWidth: 288))
        #expect(!HomeSceneMetrics.isCompact(columnWidth: 350))
        #expect(!HomeSceneMetrics.isCompact(columnWidth: 0), "Unmeasured is not a small phone.")
    }

    // MARK: Honest availability

    @Test("Released units: finished uses the total, releasing the next known release, else unknown")
    func availabilityIsNeverGuessed() {
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "FINISHED", total: 26, nextUnit: nil) == 26)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "FINISHED", total: nil, nextUnit: nil) == nil)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: 12, nextUnit: 6) == 5)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: 4, nextUnit: 9) == 4)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: nil, nextUnit: 9) == 8)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "RELEASING", total: 12, nextUnit: nil) == nil)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: "NOT_YET_RELEASED", total: 12, nextUnit: 1) == nil)
        #expect(HomeShelfPolicy.availableUnits(catalogueStatus: nil, total: 12, nextUnit: 3) == nil)

        #expect(HomeShelfPolicy.hasNewUnit(progress: 4, available: 5, catalogueStatus: "RELEASING"))
        #expect(!HomeShelfPolicy.hasNewUnit(progress: 4, available: 26, catalogueStatus: "FINISHED"),
                "A finished title's backlog is not new.")
        #expect(!HomeShelfPolicy.hasNewUnit(progress: 5, available: 5, catalogueStatus: "RELEASING"))
        #expect(!HomeShelfPolicy.hasNewUnit(progress: 1, available: nil, catalogueStatus: "RELEASING"))
        #expect(HomeShelfPolicy.isKnownCaughtUp(progress: 5, available: 5))
        #expect(!HomeShelfPolicy.isKnownCaughtUp(progress: 5, available: nil))
    }

    @Test("Scene footer: one honest fact, else nothing; club names only when real")
    func sceneFact() {
        #expect(HomeSceneFact.make(hasNew: true, knownCaughtUp: false, clubNames: ["Mina"], medium: .anime, german: false)
                == .newUnit("New episode available"))
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: true, clubNames: [], medium: .anime, german: false)
                == .upToDate("Up to date"))
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: false, clubNames: ["Mina", "Jules", "Noah"], medium: .anime, german: false)
                == .club(names: ["Mina", "Jules"]))
        #expect(HomeSceneFact.make(hasNew: false, knownCaughtUp: false, clubNames: [], medium: .anime, german: false) == nil)
        #expect(HomeSceneFact.make(hasNew: true, knownCaughtUp: false, clubNames: [], medium: .anime, german: true)
                == .newUnit("Neue Folge verfügbar"))
        #expect(HomeSceneFact.clubLine(["Mina", "Jules"]) == "Mina + Jules")
        #expect(HomeAlsoWatchingHeading.countLine(4, german: false) == "4 titles")
        #expect(HomeAlsoWatchingHeading.countLine(1, german: false) == "1 title")
        #expect(HomeAlsoWatchingHeading.countLine(4, german: true) == "4 Titel")
        #expect(HomeAlsoWatchingHeading.title(medium: .anime, german: true) == "Schaust du auch")
    }

    // MARK: Medium word (amendment 7)

    @Test("The art-filled medium word never reads lighter than the unselected word")
    func mediumWordContrastFloor() {
        let canvas = KuroRGB(1, 0xFE / 255, 0xF8 / 255)
        func contrast(_ ink: KuroRGB) -> Double { (canvas.luminance + 0.05) / (ink.luminance + 0.05) }
        #expect(HomeMediumWordInk.floor.luminance < HomeMediumWordInk.unselected.luminance)
        #expect(contrast(HomeMediumWordInk.floor) > contrast(HomeMediumWordInk.unselected))
        #expect(contrast(HomeMediumWordInk.floor) >= 4.5, "The lightest the selected word can be still passes AA.")
        #expect(HomeMediumWordInk.unselected.hex.lowercased() == "#6e786f")
    }

    // MARK: Coming up glance

    @Test("Glance: the first day and its count, undated pending, honest states with nothing to count")
    func glanceSummary() throws {
        let now = Date(timeIntervalSince1970: 1_791_979_200) // Wed 14 Oct 2026, 12:00 UTC
        let copy = ReleaseCopy(now: now, german: false, locale: Locale(identifier: "en_GB"),
                               timeZone: try #require(TimeZone(identifier: "Europe/Berlin")))
        func row(_ id: Int, _ at: Date?) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: "T\(id)", unitKind: .episode, unitNumber: 2,
                                releaseAt: at, basis: at == nil ? .announced : .confirmed, source: "anilist")
        }
        let today = [row(1, now.addingTimeInterval(1_800)), row(2, now.addingTimeInterval(3_600)),
                     row(3, now.addingTimeInterval(5_400))]
        let busy = today + [row(4, now.addingTimeInterval(86_400)), row(5, nil)]
        let summary = HomeGlanceSummary.make(items: busy, copy: copy, offline: false, coverage: .complete, checked: true)
        #expect(summary.caption == "Today · 3 releases")
        #expect(summary.count == 4 && summary.countLabel == "this week")
        #expect(summary.art.map(\.mediaId) == [1, 2, 3])
        #expect(summary.linksToCalendar)

        let undated = HomeGlanceSummary.make(items: [row(7, nil), row(8, nil)], copy: copy, offline: false,
                                             coverage: .complete, checked: true)
        #expect(undated.caption == "Dates still to come")
        #expect(undated.count == 2 && undated.countLabel == "pending")

        let unchecked = HomeGlanceSummary.make(items: [], copy: copy, offline: false, coverage: .pending, checked: false)
        #expect(unchecked.caption == "Checking dates" && unchecked.count == nil && !unchecked.linksToCalendar)
        let nothing = HomeGlanceSummary.make(items: [], copy: copy, offline: false, coverage: .complete, checked: true)
        #expect(nothing.caption == "Nothing scheduled" && nothing.count == nil)
        let failed = HomeGlanceSummary.make(items: [], copy: copy, offline: false, coverage: .failed, checked: true)
        #expect(failed.caption == "Couldn't load dates", "A failed read is never 'nothing scheduled'.")

        let german = ReleaseCopy(now: now, german: true, locale: Locale(identifier: "de_DE"),
                                 timeZone: try #require(TimeZone(identifier: "Europe/Berlin")))
        let de = HomeGlanceSummary.make(items: busy, copy: german, offline: false, coverage: .complete, checked: true)
        #expect(de.caption == "Heute · 3 Veröffentlichungen" && de.countLabel == "diese Woche")
    }

    // MARK: Fixture renders (evidence; written only with TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1)

    enum Scenario: String, CaseIterable { case busy, full, undated, quiet }

    @Test("Anime Home fixture renders: busy, full, undated and quiet at 320 / 390 / 430")
    func animeHomeRenders() async throws {
        Self.seedArtwork()
        let materials = ArtworkMaterialStore(cacheDirectory: nil, loader: Self.fixtureLoader)
        await Self.warm(materials)
        let outDir = Self.outDir
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for scenario in Scenario.allCases {
            guard let defaults = UserDefaults(suiteName: "home-anime-lane-\(UUID().uuidString)") else { continue }
            let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
            graph.home.seedForVisualQA(anime: Self.bundle(scenario), manga: nil, medium: "anime")
            graph.releases.schedule = Self.schedule(scenario)
            for width: CGFloat in [390, 320, 430] {
                let view = HomeView(skipNetworkLoad: true)
                    .environment(graph.home)
                    .environment(graph.library)
                    .environment(graph.libraryActions)
                    .environment(graph.imports)
                    .environment(graph.releases)
                    .environment(NetworkMonitor())
                    .environment(materials)
                    .environment(\.kuroRoutes, KuroRoutes.unhandled)
                    .background(Color.kuroCanvasHome)
                    // The pager places Home under the header, never under the status bar.
                    .ignoresSafeArea()
                let url = outDir.appendingPathComponent("home-\(scenario.rawValue)-anime-\(Int(width)).png")
                try await Self.render(view, width: width, height: 2_300, to: url)
                #expect(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    // MARK: Fixture support

    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static var outDir: URL {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-home-anime-lane", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/prototype-fidelity/native/home-anime", isDirectory: true)
    }

    static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func card(_ id: Int, _ listType: String) throws -> HomeCard {
        try decode("""
        {"media_id":\(id),"list_type":"\(listType)","progress":1,"server_revision":1,
         "lifecycle_id":"11111111-1111-4111-8111-11111111111\(id % 10)","title":"T\(id)"}
        """)
    }

    private static let artHost = "https://visual-fixture.invalid/"

    /// Prototype sample art (fixtures only): scene banners and covers from tools/design-directions/assets.
    private static let titles: [(id: Int, title: String, cover: String, banner: String?)] = [
        (1, "Demon Slayer", "anime1.jpg", "anime1-banner.jpg"),
        (2, "Attack on Titan", "anime0.jpg", "anime0-banner.jpg"),
        (3, "Jujutsu Kaisen", "anime2.jpg", nil),
        (4, "Death Note", "anime3.jpg", "anime3-banner.jpg"),
        (5, "Mob Psycho 100", "journal-anime-22-cover.jpg", "journal-anime-22-banner.jpg"),
        (6, "Fullmetal Alchemist: Brotherhood", "journal-anime-12-cover.jpg", nil)
    ]

    private static func art(_ id: Int) -> (cover: String, banner: String?) {
        let row = titles.first { $0.id == id }
        return (artHost + (row?.cover ?? "anime1.jpg"), row?.banner.map { artHost + $0 })
    }

    private static func cardJSON(_ id: Int, progress: Int, episodes: Int, status: String, season: Int?) -> String {
        let row = titles.first { $0.id == id }
        let artwork = art(id)
        let banner = artwork.banner.map { "\"\($0)\"" } ?? "null"
        let section = season.map { ",\"section_ordinal\":\($0),\"section_kind\":\"season\",\"section_name\":\"Season \($0)\"" } ?? ""
        return """
        {"media_id":\(id),"list_type":"WATCHING","progress":\(progress),"server_revision":2,
         "lifecycle_id":"1111111\(id)-1111-4111-8111-111111111111","title":"\(row?.title ?? "")",
         "cover_image":"\(artwork.cover)","banner_image":\(banner),"format":"TV","episodes":\(episodes),
         "catalogue_status":"\(status)"\(section)}
        """
    }

    static func bundle(_ scenario: Scenario) -> HomeBundle? {
        let quiet = scenario == .quiet
        let cards = [
            cardJSON(1, progress: quiet ? 5 : 4, episodes: 12, status: "RELEASING", season: 1),
            cardJSON(2, progress: quiet ? 8 : 7, episodes: quiet ? 8 : 12, status: quiet ? "FINISHED" : "RELEASING", season: 2),
            cardJSON(3, progress: 6, episodes: 23, status: "RELEASING", season: 2),
            cardJSON(4, progress: 11, episodes: 37, status: "FINISHED", season: nil),
            cardJSON(5, progress: 3, episodes: 12, status: "FINISHED", season: 2),
            cardJSON(6, progress: 8, episodes: 64, status: "FINISHED", season: nil)
        ].joined(separator: ",")
        let club = """
        {"state":"ready","label":"Sunday Club","items":[
          {"comment_id":"c1","media_id":2,"media_type":"ANIME","text":"Famous last words.","display_name":"Mina",
           "spoiler_scope":"none","created_at":"2026-10-01T00:00:00Z"},
          {"comment_id":"c2","media_id":2,"media_type":"ANIME","text":"Again.","display_name":"Jules",
           "spoiler_scope":"none","created_at":"2026-10-01T00:00:00Z"}]}
        """
        return try? decode("""
        {"medium":"anime","window_days":7,"home_revision":1,"active":[\(cards)],"upcoming":[],"pending":[],
         "schedule_state":"ok","next_cursor":null,"club":\(club)}
        """)
    }

    /// The account's schedule relative to now (rows behind now never show). Quiet keeps the busy dates;
    /// the caught-up titles' next episodes are still ahead.
    static func schedule(_ scenario: Scenario) -> [ReleaseScheduleItem] {
        let now = Date()
        func row(_ id: Int, _ unit: Double, _ offset: TimeInterval?) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: titles.first { $0.id == id }?.title ?? "",
                                coverImage: art(id).cover, unitKind: .episode, unitNumber: unit,
                                releaseAt: offset.map { now.addingTimeInterval($0) },
                                basis: offset == nil ? .announced : .confirmed, source: "anilist")
        }
        let hour: TimeInterval = 3_600, day: TimeInterval = 86_400
        let undated = [row(4, 1, nil), row(5, 1, nil), row(6, 1, nil)]
        switch scenario {
        case .undated:
            return undated
        case .busy, .quiet:
            return [row(1, 6, 0.2 * hour), row(2, 9, 0.4 * hour), row(3, 7, 0.6 * hour),
                    row(4, 38, day), row(5, 13, day + hour), row(6, 65, 6 * day)] + undated
        case .full:
            var rows = [row(1, 6, 0.2 * hour), row(2, 9, 0.4 * hour), row(3, 7, 0.6 * hour)]
            for week in 1...6 {
                for id in 1...6 { rows.append(row(id, Double(6 + week + id), Double(week) * 7 * day + Double(id) * hour)) }
            }
            return rows + undated
        }
    }

    /// Images go through `KuroCachedAsyncImage` → URLCache: store each fixture under its fixture URL.
    static func seedArtwork() {
        for row in titles {
            for name in [row.cover] + (row.banner.map { [$0] } ?? []) {
                guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + name)),
                      let url = URL(string: artHost + name),
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                     headerFields: ["Content-Type": "image/jpeg"]) else { continue }
                URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                                                    for: URLRequest(url: url))
            }
        }
    }

    /// The material loader for fixtures: reads the asset named by the URL's last path component.
    nonisolated static let fixtureLoader: ArtworkMaterialStore.Loader = { url in
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/design-directions/assets/" + url.lastPathComponent)
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Asks for every fixture material and waits (≤ 5 s) until each one is derived.
    static func warm(_ store: ArtworkMaterialStore) async {
        let urls = titles.compactMap { URL(string: artHost + ($0.banner ?? $0.cover)) }
        for _ in 0..<100 {
            let ready = urls.allSatisfy { store.material(for: $0, seedHex: nil).method == "art-hue-v1" }
            if ready { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, to url: URL) async throws {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = UIColor(Color.kuroCanvasHome)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1_200))
        host.view.layoutIfNeeded()
        // 1 px = 1 pt, as the reference captures (PROTOTYPE_SPEC.md §1).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            Issue.record("png encode failed for \(url.lastPathComponent)")
            return
        }
        try data.write(to: url)
    }
}
