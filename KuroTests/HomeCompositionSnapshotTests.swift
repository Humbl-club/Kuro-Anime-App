import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Renders native Home and detail shells at 320 / 390 / 430 for the Home composition evidence pack.
@Suite("Home composition snapshots", .timeLimit(.minutes(2)))
@MainActor
struct HomeCompositionSnapshotTests {
    @Test("Home release navigation keeps Taste and legacy fallback independent")
    func releasePagerOrder() {
        let release: [KuroMainView.Section] = [.taste, .home, .discover, .collection, .clubs]
        #expect(KuroMainView.Section.pagerOrder(tasteDeck: true, seriesHome: true) == release)
        #expect(KuroMainView.Section.pagerOrder(tasteDeck: false, seriesHome: true) == release)
        #expect(KuroMainView.Section.pagerOrder(tasteDeck: false, seriesHome: false) == [.concierge, .discover, .browse, .collection, .clubs])
    }

    @Test("Exact numeric unit cursor survives decoding and the next RPC body")
    func exactUnitCursor() throws {
        let exact = "2.000000000000000000000001"
        let unit = try JSONDecoder().decode(SeriesDetailBundle.Unit.self, from: Data("""
        {"id":"33333333-3333-4333-8333-333333333333","label":"2 special","order_key":"\(exact)","available":true,"edition_key":"translation:de"}
        """.utf8))
        #expect(unit.exactOrderKey == exact)
        #expect(SeriesUnitPresentation.integerPosition(unit.exactOrderKey) == nil,
                "A Double rounds this value to 2; a precise unit cannot become integer progress.")
        #expect(SeriesUnitPresentation.integerPosition("2.000") == 2)
        let cursor = try JSONDecoder().decode(SeriesUnitPage.Cursor.self, from: Data("""
        {"order":"\(exact)","id":"33333333-3333-4333-8333-333333333333"}
        """.utf8))
        let body = try JSONEncoder().encode(RPCSeriesUnitPage(p_medium: "manga", p_media_id: 10,
            p_section_id: nil, p_edition_key: unit.editionKey, p_after_order: cursor.order, p_after_id: cursor.id))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["p_after_order"] as? String == exact)
        #expect(json["p_edition_key"] as? String == "translation:de")
    }

    @Test("The server's selected edition remains reachable beyond the first edition page")
    func selectedEdition() {
        var bundle = Self.mangaDetailBundle
        bundle.edition = "translation:de"
        bundle.editions = ["", "translation:en"]
        bundle.editionsNext = "translation:en"
        #expect(SeriesUnitPresentation.selectedEdition(bundle) == "translation:de")
        #expect(SeriesUnitPresentation.editionKeys(bundle) == ["", "translation:en", "translation:de"])
        #expect(SeriesUnitPresentation.selectedEdition(Self.animeDetailBundle) == "")
    }

    @Test("Calendar groups the release schedule by the day each line reads, then windows, then undated")
    func calendarReleaseDays() throws {
        let now = Date(timeIntervalSince1970: 1_791_979_200) // Wed 14 Oct 2026, 12:00 UTC
        let copy = ReleaseCopy(now: now, german: false, locale: Locale(identifier: "en_GB"),
                               timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")))
        func row(_ id: Int, _ at: Date?, basis: ReleaseBasis = .confirmed, precision: ReleasePrecision? = nil) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: "T\(id)", unitKind: .episode, unitNumber: 1,
                                releaseAt: at, basis: basis, source: "anilist", precision: precision)
        }
        let items = [
            // Sat 17 Oct 00:00 in Tokyo (a source day): Saturday for a reader in Los Angeles too.
            row(1, Date(timeIntervalSince1970: 1_792_162_800), basis: .announced, precision: .day),
            // Thu 15 Oct 16:30 UTC = 09:30 in Los Angeles (an instant on the reader's day).
            row(2, Date(timeIntervalSince1970: 1_792_081_800)),
            // A month window and an undated row.
            row(3, Date(timeIntervalSince1970: 1_793_491_200), basis: .announced, precision: .month),
            row(4, nil),
            // Thu 15 Oct 23:00 UTC = 16:00 in Los Angeles: same day as row 2.
            row(5, Date(timeIntervalSince1970: 1_792_105_200))
        ]
        let groups = HomeCalendarPresentation.groups(items, copy: copy)
        #expect(groups.map(\.id) == ["2026-10-15", "2026-10-17", "later", "undated"])
        try #require(groups.count == 4)
        #expect(groups[0].items.map(\.mediaId) == [2, 5], "Keep the server's order within each day.")
        #expect(groups[0].label == "Tomorrow")
        #expect(groups[1].label == "Sat 17 Oct" && groups[1].day == "17")
        #expect(groups[2].kind == .later && groups[2].items.map(\.mediaId) == [3])
        #expect(groups[3].kind == .undated && groups[3].label == "Dates to come" && groups[3].day == "…")
        #expect(groups[3].items[0].releaseAt == nil, "An undated row never acquires a date.")
        #expect(HomeCalendarPresentation.glanceCaption(items: items, copy: copy) == "3 this week")
        #expect(HomeCalendarPresentation.glanceCaption(items: [row(4, nil)], copy: copy) == "Dates still to come")
        let german = ReleaseCopy(now: now, german: true, locale: Locale(identifier: "de_DE"),
                                 timeZone: try #require(TimeZone(identifier: "Europe/Berlin")))
        #expect(HomeCalendarPresentation.glanceCaption(items: [], copy: german) == "Nichts angekündigt")
        #expect(HomeCalendarPresentation.glanceCaption(items: [], copy: copy, offline: true) != "Nothing scheduled",
                "offline with no rows is unknown, not empty")
    }
    private let widths: [CGFloat] = [320, 390, 430]
    private let outDir: URL = {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repo
            .appendingPathComponent("docs/handoffs/2026-10-08-fresh-session/native-polish-screenshots")
    }()

    @Test("native Home anime and manga at 320/390/430")
    func homeMediums() async throws {
        try await Self.seedArtwork()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let graph = AppComposition.testingGraph(
            testingUserDefaults: UserDefaults(suiteName: "home-comp-\(UUID().uuidString)")!,
            notificationCenter: FakeNotificationCenter()
        )
        let home = graph.home
        home.seedForVisualQA(anime: Self.animeBundle, manga: Self.mangaBundle, medium: "anime")

        for width in widths {
            try await render(
                HomeView(skipNetworkLoad:true)
                    .environment(home)
                    .environment(graph.library)
                    .environment(graph.libraryActions)
                    .environment(graph.imports)
                    .environment(graph.releases)
                    .environment(NetworkMonitor())
                    .environment(\.kuroRoutes, KuroRoutes.unhandled),
                width: width,
                name: "anime-home-\(Int(width)).png"
            )
        }

        home.selectMedium("manga")
        for width in widths {
            try await render(
                HomeView(skipNetworkLoad:true)
                    .environment(home)
                    .environment(graph.library)
                    .environment(graph.libraryActions)
                    .environment(graph.imports)
                    .environment(graph.releases)
                    .environment(NetworkMonitor())
                    .environment(\.kuroRoutes, KuroRoutes.unhandled),
                width: width,
                name: "manga-home-\(Int(width)).png"
            )
        }
    }

    @Test("empty Home invitation at 390")
    func emptyHome() async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let graph = AppComposition.testingGraph(
            testingUserDefaults: UserDefaults(suiteName: "home-empty-\(UUID().uuidString)")!,
            notificationCenter: FakeNotificationCenter()
        )
        graph.home.seedForVisualQA(anime: Self.emptyBundle("anime"), manga: Self.emptyBundle("manga"), medium: "anime")
        try await render(
            HomeView(skipNetworkLoad: true)
                .environment(graph.home)
                .environment(graph.library)
                .environment(graph.libraryActions)
                .environment(graph.imports)
                .environment(graph.releases)
                .environment(NetworkMonitor())
                .environment(\.kuroRoutes, KuroRoutes.unhandled),
            width: 390,
            name: "empty-home-390.png"
        )
    }

    @Test("profile hub at 390")
    func profileHub() async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let graph = AppComposition.testingGraph(
            testingUserDefaults: UserDefaults(suiteName: "profile-polish-\(UUID().uuidString)")!,
            notificationCenter: FakeNotificationCenter()
        )
        try await render(
            ProfileView()
                .environment(graph.library)
                .environment(graph.identity)
                .environment(graph.auth)
                .environment(graph.session)
                .environment(graph.collection)
                .environment(graph.releases)
                .environment(graph.availability)
                .environment(graph.clubs)
                .environment(graph.imports)
                .environment(graph.flags),
            width: 390,
            height: 1400,
            name: "profile-390.png"
        )
    }

    @Test("native anime and manga detail shells at 320/390/430")
    func detailShells() async throws {
        try await Self.seedArtwork()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let graph = AppComposition.testingGraph(
            testingUserDefaults: UserDefaults(suiteName: "home-detail-\(UUID().uuidString)")!,
            notificationCenter: FakeNotificationCenter()
        )
        let home = graph.home
        home.seedForVisualQA(anime: Self.animeBundle, manga: Self.mangaBundle, medium: "anime")

        for width in widths {
            try await render(
                SeriesAnimeDetailView(anime: Self.sampleAnime, previewBundle: Self.animeDetailBundle)
                    .environment(home)
                    .environment(graph.libraryActions)
                    .environment(graph.library)
                    .environment(graph.clubs)
                    .environment(graph.social)
                    .environment(graph.catalog)
                    .environment(graph.releases),
                width: width,
                name: "detail-anime-\(Int(width)).png"
            )
            try await render(
                SeriesMangaDetailView(manga: Self.sampleManga, previewBundle: Self.mangaDetailBundle)
                    .environment(home)
                    .environment(graph.libraryActions)
                    .environment(graph.library)
                    .environment(graph.clubs)
                    .environment(graph.social)
                    .environment(graph.catalog)
                    .environment(graph.releases),
                width: width,
                name: "detail-manga-\(Int(width)).png"
            )
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat, height preferredHeight: CGFloat? = nil, name: String) async throws {
        let height = preferredHeight ?? width * 2.2
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        let window=UIWindow(frame:CGRect(x:0,y:0,width:width,height:height))
        window.rootViewController=host; window.isHidden=false
        defer { window.isHidden=true; window.rootViewController=nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = .white
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for:.milliseconds(400))
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let url = outDir.appendingPathComponent(name)
        guard let data = image.pngData() else {
            Issue.record("png encode failed for \(name)")
            return
        }
        try data.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    private static func emptyBundle(_ medium: String) -> HomeBundle {
        decode("""
        {"medium":"\(medium)","window_days":7,"home_revision":1,"active":[],"upcoming":[],"pending":[],
         "schedule_state":"ok","next_cursor":null,"club":{"state":"ready","label":"Sunday Club","items":[]}}
        """)
    }

    private static let animeBundle: HomeBundle = decode("""
    {
      "medium":"anime","window_days":7,"home_revision":1,
      "active":[
        {"media_id":1,"list_type":"WATCHING","progress":4,"server_revision":2,
         "lifecycle_id":"11111111-1111-4111-8111-111111111111","title":"Demon Slayer",
         "format":"TV","episodes":26,"section_ordinal":1,"section_kind":"season","section_name":"Season 1"},
        {"media_id":2,"list_type":"WATCHING","progress":7,"server_revision":3,
         "lifecycle_id":"33333333-3333-4333-8333-333333333333","title":"Attack on Titan",
         "format":"TV","episodes":25,"section_ordinal":2,"section_kind":"season","section_name":"Season 2"},
        {"media_id":4,"list_type":"WATCHING","progress":1,"server_revision":1,
         "lifecycle_id":"66666666-6666-4666-8666-666666666666",
         "title":"Die sehr lange Geschichte eines wandernden Schwertes im Herbst",
         "format":"TV","episodes":12,"section_ordinal":1,"section_kind":"season","section_name":"Season 1"}
      ],
      "upcoming":[
        {"event_id":"anime-day-1","media_id":1,"title":"Demon Slayer","precision":"day","source_local_date":"2026-10-09","unit_label":"Episode 5"},
        {"event_id":"anime-day-2","media_id":2,"title":"Attack on Titan","precision":"day","source_local_date":"2026-10-09","unit_label":"Episode 8"}
      ],"pending":[{"media_id":9,"title":"Undated title","status":"announcement"}],
      "schedule_state":"ok","next_cursor":null,
      "club":{"state":"ready","label":"Sunday Club","items":[
        {"comment_id":"c1","media_id":1,"media_type":"ANIME","text":"That episode hit.",
         "display_name":null,"spoiler_scope":"none","created_at":"2026-10-01T00:00:00Z"}
      ]}
    }
    """)

    private static let mangaBundle: HomeBundle = decode("""
    {
      "medium":"manga","window_days":7,"home_revision":1,
      "active":[
        {"media_id":10,"list_type":"READING","progress":24,"server_revision":2,
         "lifecycle_id":"44444444-4444-4444-8444-444444444444","title":"Chainsaw Man","chapters":120},
        {"media_id":11,"list_type":"READING","progress":8,"server_revision":2,
         "lifecycle_id":"55555555-5555-4555-8555-555555555555","title":"Solo Leveling","chapters":200}
      ],
      "upcoming":[
        {"event_id":"manga-day-1","media_id":10,"title":"Chainsaw Man","precision":"day","source_local_date":"2026-10-09","unit_label":"Chapter 25"},
        {"event_id":"manga-day-2","media_id":11,"title":"Solo Leveling","precision":"day","source_local_date":"2026-10-09","unit_label":"Chapter 9"}
      ],"pending":[],
      "schedule_state":"ok","next_cursor":null,
      "club":{"state":"ready","label":"Sunday Club","items":[]}
    }
    """)

    private static let animeDetailBundle: SeriesDetailBundle = decode("""
    {
      "medium":"anime","media_id":2,"series_id":"22222222-2222-4222-8222-222222222222",
      "section_id":null,
      "header":{"media_id":2,"title":"JUJUTSU KAISEN","format":"TV","catalogue_status":"FINISHED",
                "episodes":25,"artwork_scope":"cover_fallback"},
      "sections":[
        {"id":"s1","kind":"season","ordinal":1,"name":"Season 1","sort_order":1,
         "entries":[{"media_id":2,"title":"JUJUTSU KAISEN","episodes":24}]},
        {"id":"s2","kind":"season","ordinal":2,"name":"Season 2","sort_order":2,
         "entries":[{"media_id":3,"title":"Attack on Titan","episodes":12}]}
      ],
      "units":[{"id":"u1","label":"Episode 1","order_key":1,"available":true,"edition_key":""}],
      "units_state":"ok",
      "copy":{"premise":"Walls hold for now.","story_state":"present"},
      "themes":[],"cast":[],
      "user":{"server_revision":3,"lifecycle_id":"33333333-3333-4333-8333-333333333333",
              "progress":7,"list_type":"WATCHING"}
    }
    """)

    private static let mangaDetailBundle: SeriesDetailBundle = decode("""
    {
      "medium":"manga","media_id":10,
      "header":{"media_id":10,"title":"Chainsaw Man","format":"MANGA",
                "catalogue_status":"RELEASING","chapters":120,"volumes":14,"artwork_scope":"cover"},
      "sections":[],"units":[],"units_state":"not_in_catalogue",
      "copy":{"premise":"Small dreams. Monstrous consequences.","story_state":"present"},
      "themes":[],"cast":[],
      "user":{"server_revision":2,"lifecycle_id":"44444444-4444-4444-8444-444444444444",
              "progress":24,"list_type":"READING"}
    }
    """)

    private static let sampleAnime: Anime = decode("""
    {"id":2,"title_romaji":"JUJUTSU KAISEN","title_english":"JUJUTSU KAISEN",
     "format":"TV","status":"FINISHED","episodes":25,"is_adult":false,
     "genres":[],"created_at":0,"updated_at":0}
    """)

    private static let sampleManga: Manga = decode("""
    {"id":10,"title_romaji":"Chainsaw Man","title_english":"Chainsaw Man",
     "format":"MANGA","status":"RELEASING","chapters":120,"volumes":14,"is_adult":false,
     "genres":[],"created_at":0,"updated_at":0}
    """)

    private static let artwork:[String:(cover:String,banner:String)] = [
        "Demon Slayer":("anime1.jpg","anime1-banner.jpg"),"Attack on Titan":("anime0.jpg","anime0-banner.jpg"),
        "JUJUTSU KAISEN":("anime2.jpg","anime2.jpg"),"Chainsaw Man":("manga0.jpg","manga0-banner.jpg"),
        "Solo Leveling":("manga1.jpg","manga1-banner.jpg")
    ]
    private static func seedArtwork() async throws {
        let repo=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in Set(artwork.values.flatMap { [$0.cover,$0.banner] }) {
            let data=try Data(contentsOf:repo.appendingPathComponent("tools/design-directions/assets/"+name))
            #expect(UIImage(data:data) != nil,"Actual reference artwork must decode")
            let url=URL(string:"https://visual-fixture.invalid/"+name)!
            let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"image/jpeg"])!
            URLCache.shared.storeCachedResponse(CachedURLResponse(response:response,data:data,storagePolicy:.allowedInMemoryOnly),for:URLRequest(url:url))
        }
    }
    private static func decorate(_ value:Any) -> Any {
        if let array=value as? [Any] { return array.map(decorate) }
        guard var object=value as? [String:Any] else { return value }
        for (key,value) in object { object[key]=decorate(value) }
        let title=(object["title"] ?? object["title_english"]) as? String
        if let title,let art=artwork[title] {
            object["cover_image"]="https://visual-fixture.invalid/"+art.cover
            object["cover_image_large"]="https://visual-fixture.invalid/"+art.cover
            object["banner_image"]="https://visual-fixture.invalid/"+art.banner
        }
        return object
    }

    private static func decode<T: Decodable>(_ json: String) -> T {
        do {
            let value=try JSONSerialization.jsonObject(with:Data(json.utf8))
            return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:decorate(value)))
        } catch {
            preconditionFailure("fixture decode \(T.self): \(error)")
        }
    }
}
