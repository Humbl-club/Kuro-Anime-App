//
//  PublicDataHTTPContractTests.swift
//  KuroTests
//
//  Public-data capabilities (Catalog, Discovery + Browse, Search, Recommendations read side)
//  asserted on the HTTP requests the real supabase-swift client emits (StubPostgREST: in-process,
//  no network). Each test is named by the risk it covers.
//

import Testing
import Foundation
import KuroCore
import Synchronization
@testable import Kuro

// `PublicDataHarness` (a service over a `StubServer`) lives in StubPostgREST.swift (shared).

/// Rows as PostgREST returns them for the public tables and RPCs.
enum PublicRowJSON {
    static func anime(_ id: Int, title: String) -> String {
        #"{"id":\#(id),"title_english":"\#(title)","is_adult":false,"genres":["Action"],"created_at":"2026-01-01T00:00:00+00:00","updated_at":"2026-01-01T00:00:00+00:00"}"#
    }

    static func manga(_ id: Int, title: String) -> String {
        #"{"id":\#(id),"title_english":"\#(title)","is_adult":false,"genres":["Drama"],"created_at":"2026-01-01T00:00:00+00:00","updated_at":"2026-01-01T00:00:00+00:00"}"#
    }

    static func character(_ id: Int, name: String) -> String {
        #"{"role":"MAIN","characters":{"id":\#(id),"name_full":"\#(name)"}}"#
    }

    static func ladder(note: String) -> String {
        #"{"source_material":[],"adaptations":[],"prequels":[],"sequels":[],"side_stories":[],"spin_offs":[],"franchise_note":"\#(note)"}"#
    }

    /// Search/browse card rows, ordered like the keyset (`rank` and `popularity` descend with id).
    static func cards(_ ids: [Int]) -> StubResponse {
        let rows = ids.map { id in
            #"{"id":\#(id),"title_english":"Title \#(id)","format":"TV","popularity":\#(popularity(id)),"rank":\#(rank(id))}"#
        }
        return .json("[" + rows.joined(separator: ",") + "]")
    }

    static func popularity(_ id: Int) -> Int { 10_000 - id }

    /// Whole numbers, so the cursor compares exactly after the JSON round trip.
    static func rank(_ id: Int) -> Double { Double(1_000 - id) }

    /// A Discover bundle whose anime NEW TO YOU rail holds `newToYou`.
    static func bundle(newToYou: [Int]) -> StubResponse {
        let cards = newToYou.map { #"{"id":\#($0),"title_english":"Pick \#($0)"}"# }.joined(separator: ",")
        return .json("""
            {"anime":{"essentials":[],"classics":[],"new_to_you":[\(cards)],"trending":[],"top_rated":[],
             "newly_added":[],"airing_today":[],"current_season":[]},
             "manga":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],"newly_added":[]}}
            """)
    }
}

// MARK: - Catalog

@MainActor
@Suite("Public data: Catalog caches", .timeLimit(.minutes(1)))
struct CatalogCacheContractTests {

    @Test("Request regression: concurrent duplicate detail/credits/ladder reads join one request; warm reads issue none")
    func duplicateReadsJoinAndWarmReadsAreFree() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "anime": return .json("[" + PublicRowJSON.anime(990_042, title: "Anime 990042") + "]")
            case "anime_characters": return .json("[" + PublicRowJSON.character(1, name: "Hero") + "]")
            case "rpc/get_media_ladder": return .json(PublicRowJSON.ladder(note: "anime ladder"))
            default: return .emptyArray
            }
        }
        let catalog = harness.service.catalog

        // Two screens ask at the same time: the second joins the first one's request.
        let detailA = Task.immediate { @MainActor in try await catalog.fetchAnimeById(990_042) }
        let detailB = Task.immediate { @MainActor in try await catalog.fetchAnimeById(990_042) }
        let castA = Task.immediate { @MainActor in await catalog.fetchCharactersForAnime(animeId: 990_042) }
        let castB = Task.immediate { @MainActor in await catalog.fetchCharactersForAnime(animeId: 990_042) }
        let ladderA = Task.immediate { @MainActor in await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 990_042) }
        let ladderB = Task.immediate { @MainActor in await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 990_042) }
        #expect(try await detailA.value?.title == "Anime 990042")
        #expect(try await detailB.value?.title == "Anime 990042")
        #expect(await castA.value.map(\.character.nameFull) == ["Hero"])
        #expect(await castB.value.map(\.character.nameFull) == ["Hero"])
        #expect(await ladderA.value.franchiseNote == "anime ladder")
        #expect(await ladderB.value.franchiseNote == "anime ladder")
        #expect(harness.requests(to: "anime").count == 1, "\(harness.server.requests)")
        #expect(harness.requests(to: "anime_characters").count == 1, "\(harness.server.requests)")
        #expect(harness.requests(to: "rpc/get_media_ladder").count == 1, "\(harness.server.requests)")

        // Warm: served from the public caches, zero requests.
        let before = harness.server.requests.count
        #expect(try await catalog.fetchAnimeById(990_042)?.title == "Anime 990042")
        #expect(await catalog.fetchCharactersForAnime(animeId: 990_042).count == 1)
        #expect(await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 990_042).franchiseNote == "anime ladder")
        #expect(harness.server.requests.count == before, "\(harness.server.requests.dropFirst(before))")
        await harness.tearDown()
    }

    @Test("anime 990007 and manga 990007 hit different tables/RPCs and never share a cache entry")
    func equalIdsStayDistinct() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "anime": return .json("[" + PublicRowJSON.anime(990_007, title: "Anime 7") + "]")
            case "manga": return .json("[" + PublicRowJSON.manga(990_007, title: "Manga 7") + "]")
            case "anime_characters": return .json("[" + PublicRowJSON.character(1, name: "Anime cast") + "]")
            case "manga_characters": return .json("[" + PublicRowJSON.character(2, name: "Manga cast") + "]")
            case "rpc/get_media_ladder":
                return .json(PublicRowJSON.ladder(note: request.jsonObject?["p_media_type"] as? String ?? "?"))
            default: return .emptyArray
            }
        }
        let catalog = harness.service.catalog

        #expect(try await catalog.fetchAnimeById(990_007)?.title == "Anime 7")
        #expect(try await catalog.fetchMangaById(990_007)?.title == "Manga 7")
        #expect(await catalog.fetchCharactersForAnime(animeId: 990_007).map(\.character.nameFull) == ["Anime cast"])
        #expect(await catalog.fetchCharactersForManga(mangaId: 990_007).map(\.character.nameFull) == ["Manga cast"])
        #expect(await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 990_007).franchiseNote == "ANIME")
        #expect(await catalog.fetchMediaLadder(mediaType: "MANGA", mediaId: 990_007).franchiseNote == "MANGA")

        // Each request names its own table / media type for the same numeric id.
        #expect(harness.requests(to: "anime").map { $0.query("id") } == ["eq.990007"])
        #expect(harness.requests(to: "manga").map { $0.query("id") } == ["eq.990007"])
        #expect(harness.requests(to: "anime_characters").map { $0.query("anime_id") } == ["eq.990007"])
        #expect(harness.requests(to: "manga_characters").map { $0.query("manga_id") } == ["eq.990007"])
        #expect(harness.requests(to: "rpc/get_media_ladder").compactMap { $0.jsonObject?["p_media_type"] as? String }
                == ["ANIME", "MANGA"])

        // Warm, in the opposite order: each kind is served from its own entry, with no request.
        let before = harness.server.requests.count
        #expect(try await catalog.fetchMangaById(990_007)?.title == "Manga 7")
        #expect(try await catalog.fetchAnimeById(990_007)?.title == "Anime 7")
        #expect(await catalog.fetchCharactersForManga(mangaId: 990_007).map(\.character.nameFull) == ["Manga cast"])
        #expect(await catalog.fetchCharactersForAnime(animeId: 990_007).map(\.character.nameFull) == ["Anime cast"])
        #expect(await catalog.fetchMediaLadder(mediaType: "MANGA", mediaId: 990_007).franchiseNote == "MANGA")
        #expect(await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 990_007).franchiseNote == "ANIME")
        #expect(harness.server.requests.count == before)
        await harness.tearDown()
    }

    @Test("Public caches are not account-scoped: detail/credits/ladder loaded for A are served after A -> B and sign-out with zero requests")
    func publicCachesSurviveAccountTransitions() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "anime": return .json("[" + PublicRowJSON.anime(990_100, title: "Anime 990100") + "]")
            case "anime_characters": return .json("[" + PublicRowJSON.character(1, name: "Hero") + "]")
            case "rpc/get_media_ladder": return .json(PublicRowJSON.ladder(note: "anime ladder"))
            default: return .emptyArray
            }
        }
        let service = harness.service
        let catalog = service.catalog
        let catalogResources: Set<String> = ["anime", "anime_characters", "rpc/get_media_ladder"]
        func catalogRequests() -> Int {
            harness.server.requests.filter { catalogResources.contains($0.resource ?? "") }.count
        }

        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        #expect(try await catalog.fetchAnimeById(990_100)?.title == "Anime 990100")
        #expect(await catalog.fetchCharactersForAnime(animeId: 990_100).count == 1)
        #expect(await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 990_100).franchiseNote == "anime ladder")
        #expect(catalogRequests() == 3)

        await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")
        #expect(catalog.animeDetailCache[990_100] != nil)
        #expect(try await catalog.fetchAnimeById(990_100)?.title == "Anime 990100")
        #expect(await catalog.fetchCharactersForAnime(animeId: 990_100).count == 1)
        #expect(await catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 990_100).franchiseNote == "anime ladder")

        await service.session.endSession()
        #expect(try await catalog.fetchAnimeById(990_100)?.title == "Anime 990100")
        #expect(catalogRequests() == 3, "public catalog reads must not be repeated after a transition")
        await harness.tearDown()
    }
}

// MARK: - Discovery + Browse

@MainActor
@Suite("Public data: Discovery and Browse", .timeLimit(.minutes(1)))
struct DiscoveryContractTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    /// The first bundle request is answered with A's NEW TO YOU pick (101), any later one with B's (202).
    static func bundleResponder() -> StubServer.Responder {
        let bundles = Mutex(0)
        return { request in
            guard request.resource == "rpc/discover_bundle" else { return .emptyArray }
            let call = bundles.withLock { count in
                count += 1
                return count
            }
            return PublicRowJSON.bundle(newToYou: call == 1 ? [101] : [202])
        }
    }

    @Test("Default formats (request shape): anime Browse/Search/Discover never ask for SPECIAL/MUSIC/TV_SHORT; an explicit Browse format is sent")
    func defaultFormatRequestShape() async throws {
        let harness = try PublicDataHarness()
        let discovery = harness.service.discovery
        let search = harness.service.search

        // Browse: no format key by default (the server then hides ancillary anime formats).
        _ = await discovery.fetchBrowseAnimePageKeyset(
            genre: nil, status: nil, minEpisodes: nil, maxEpisodes: nil,
            cursorInt: nil, cursorDate: nil, cursorId: nil, limit: 60
        )
        // Browse with the user's explicit format filter.
        _ = await discovery.fetchBrowseAnimePageKeyset(
            genre: nil, status: nil, minEpisodes: nil, maxEpisodes: nil,
            cursorInt: nil, cursorDate: nil, cursorId: nil, format: "SPECIAL", limit: 60
        )
        // Search and the Discover bundle carry no format parameter at all.
        search.resetSearch(query: "naruto", isManga: false)
        await search.fetchNextSearchPage()
        _ = await discovery.fetchDiscoverBundle()

        let browse = harness.requests(to: "rpc/browse_anime_page").map { $0.jsonObject ?? [:] }
        #expect(browse.count == 2)
        #expect(browse.first?["p_format"] == nil, "default Browse must not name a format: \(browse)")
        #expect(browse.last?["p_format"] as? String == "SPECIAL")
        let searchKeys = Set(harness.requests(to: "rpc/search_anime_page").first?.jsonObject.map { Array($0.keys) } ?? [])
        #expect(!searchKeys.isEmpty)
        #expect(searchKeys.allSatisfy { !$0.contains("format") }, "\(searchKeys)")
        let bundleKeys = Set(harness.requests(to: "rpc/discover_bundle").first?.jsonObject.map { Array($0.keys) } ?? [])
        #expect(bundleKeys == ["p_limit", "p_hours"])
        await harness.tearDown()
    }

    @Test("Browse keyset: the caller's cursor is sent verbatim (Browse cursor derivation lives in BrowseView)")
    func browseSendsCursorVerbatim() async throws {
        let harness = try PublicDataHarness()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cursor = try #require(formatter.date(from: "2026-02-03T13:58:30.123+09:00"))
        _ = await harness.service.discovery.fetchBrowseAnimePageKeyset(
            genre: "Action", status: nil, minEpisodes: nil, maxEpisodes: nil, sort: .topRated,
            cursorInt: 87, cursorDate: cursor, cursorId: 4_242, limit: 60
        )
        let body = try #require(harness.requests(to: "rpc/browse_anime_page").first?.jsonObject)
        #expect(body["p_sort"] as? String == "topRated")
        #expect(body["p_cursor_int"] as? Int == 87)
        #expect(body["p_cursor_id"] as? Int == 4_242)
        let sentCursor = try #require(body["p_cursor_ts"] as? String)
        #expect(sentCursor == "2026-02-03T04:58:30.123Z")
        #expect(formatter.date(from: sentCursor) == cursor)
        #expect(body["p_genre"] as? String == "Action")
        await harness.tearDown()
    }

    @Test("Personalised bundle: A's NEW TO YOU is cached for A only and is gone after A -> B")
    func bundleIsAccountScoped() async throws {
        let harness = try PublicDataHarness(responder: Self.bundleResponder())
        let service = harness.service
        let discovery = service.discovery

        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        #expect(await discovery.fetchDiscoverBundle()?.anime.newToYou.map(\.id) == [101])
        #expect(await discovery.fetchDiscoverBundle()?.anime.newToYou.map(\.id) == [101], "warm read")
        #expect(harness.requests(to: "rpc/discover_bundle").count == 1)

        // The session funnel clears the owner through `AccountScopedState`.
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(discovery.discoverBundleCache.isEmpty)
        #expect(await discovery.fetchDiscoverBundle()?.anime.newToYou.map(\.id) == [202])
        #expect(harness.requests(to: "rpc/discover_bundle").count == 2)
        #expect(discovery.discoverBundleCache.keys.allSatisfy { $0.contains(Self.userB) })
        await harness.tearDown()
    }

    @Test("Personalised bundle cache is keyed by user: B never reads A's entry, even before it is cleared")
    func bundleCacheIsKeyedByUser() async throws {
        let harness = try PublicDataHarness(responder: Self.bundleResponder())
        let accounts = AccountSessionCoordinator()
        let discovery = DiscoveryStore(
            client: StubSupabase.makeClient(server: harness.server),
            accountSession: accounts,
            library: harness.service.library
        )

        _ = accounts.begin(userId: Self.userA)
        #expect(await discovery.fetchDiscoverBundle()?.anime.newToYou.map(\.id) == [101])
        // B takes over without any clearing: A's cached entry must not be served to B.
        _ = accounts.begin(userId: Self.userB)
        #expect(await discovery.fetchDiscoverBundle()?.anime.newToYou.map(\.id) == [202])
        #expect(harness.requests(to: "rpc/discover_bundle").count == 2)

        discovery.clearPrivateState()
        #expect(discovery.discoverBundleCache.isEmpty)
        await harness.tearDown()
    }

    /// The personalised Discover surfaces whose answer for account A may arrive after A's session ended.
    enum PersonalisedSurface: String, CaseIterable, Sendable {
        case bundleNewToYou, becauseYou, tonightShelf, hiddenGem

        var resource: String {
            switch self {
            case .bundleNewToYou: return "rpc/discover_bundle"
            case .becauseYou: return "rpc/fetch_because_you_rail"
            case .tonightShelf: return "rpc/fetch_tonight_shelf"
            case .hiddenGem: return "rpc/fetch_realm_hidden_gem"
            }
        }

        /// The ids the caller receives (nil and empty both mean "nothing to show").
        @MainActor
        func load(from discovery: DiscoveryStore) async -> [Int] {
            switch self {
            case .bundleNewToYou: return await discovery.fetchDiscoverBundle()?.anime.newToYou.map(\.id) ?? []
            case .becauseYou: return await discovery.fetchBecauseYouRail()?.map(\.mediaId) ?? []
            case .tonightShelf: return await discovery.fetchTonightShelf()?.map(\.mediaId) ?? []
            case .hiddenGem: return await discovery.fetchRealmHiddenGem().map { [$0.mediaId] } ?? []
            }
        }
    }

    enum LateTransition: String, CaseIterable, Sendable {
        /// Control: no transition, A's answer is handed out.
        case none, switchToB, signOut
    }

    /// Every personalised surface answers with title 101, held until `gate` opens.
    static func personalisedResponder(gate: StubGate) -> StubServer.Responder {
        let card = #"{"media_type":"ANIME","media_id":101,"title":"Pick 101","realm":"r"}"#
        return { request in
            switch request.resource {
            case "rpc/discover_bundle": return PublicRowJSON.bundle(newToYou: [101]).held(by: gate)
            case "rpc/fetch_because_you_rail", "rpc/fetch_tonight_shelf", "rpc/fetch_realm_hidden_gem":
                return .json("[" + card + "]").held(by: gate)
            default: return .emptyArray
            }
        }
    }

    @Test("Late personalised answer: A's result arriving after A's session ended is never handed out or cached",
          arguments: PersonalisedSurface.allCases, LateTransition.allCases)
    func lateAnswerOfEndedAccountIsDropped(surface: PersonalisedSurface, transition: LateTransition) async throws {
        let gate = StubGate()
        let harness = try PublicDataHarness(responder: Self.personalisedResponder(gate: gate))
        let service = harness.service
        let discovery = service.discovery
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        // A's request is in flight and held.
        let late = Task.immediate { @MainActor in await surface.load(from: discovery) }
        let resource = surface.resource
        _ = await harness.server.waitForRequest { $0.resource == resource }

        switch transition {
        case .none: break
        case .switchToB: await service.session.applySession(userId: Self.userB, email: "b@example.com")
        case .signOut: await service.session.endSession()
        }
        gate.open()
        let received = await late.value

        if transition == .none {
            #expect(received == [101], "control: the held answer reaches A")
        } else {
            #expect(received.isEmpty, "A's late answer was handed out after \(transition): \(received)")
            #expect(discovery.discoverBundleCache.isEmpty, "\(discovery.discoverBundleCache.keys)")
        }
        await harness.tearDown()
    }
}

// MARK: - Search

@MainActor
@Suite("Public data: Search", .timeLimit(.minutes(1)))
struct SearchContractTests {

    @Test("Stale search: a new query cancels the old query's in-flight page; neither its rows nor its failure reach the new query")
    func newQueryCancelsOldQueryPage() async throws {
        let slow = StubGate()
        let pageB = Array(11...30) // a full page: B has more to load
        let harness = try PublicDataHarness { request in
            guard request.resource == "rpc/search_anime_page" else { return .emptyArray }
            switch request.jsonObject?["p_query"] as? String {
            case "naruto": return PublicRowJSON.cards([1, 2, 3]).held(by: slow)
            case "bleach": return PublicRowJSON.cards(pageB)
            default: return .emptyArray
            }
        }
        let search = harness.service.search
        let isQueryA: @Sendable (RecordedRequest) -> Bool = { $0.jsonObject?["p_query"] as? String == "naruto" }

        search.resetSearch(query: "naruto", isManga: false)
        let pageA = Task.immediate { @MainActor in await search.fetchNextSearchPage() }
        _ = await harness.server.waitForRequest(where: isQueryA)

        // The user typed on: query B starts while A's page is still in flight.
        search.resetSearch(query: "bleach", isManga: false)
        await search.fetchNextSearchPage()
        // A's request was cancelled at the transport; its held page is never delivered.
        _ = await harness.server.waitForStop(where: isQueryA)
        slow.open()
        await pageA.value

        let queries = harness.requests(to: "rpc/search_anime_page").compactMap { $0.jsonObject?["p_query"] as? String }
        #expect(queries == ["naruto", "bleach"], "B must run its own page instead of waiting on A")
        #expect(search.searchAnimeItems.map(\.id) == pageB)
        #expect(search.hasMoreSearch, "A's cancelled page must not end B's paging")
        #expect(search.errorMessage == nil, "A's cancellation must not surface as a failure of B")
        #expect(!search.isSearching)
        await harness.tearDown()
    }

    @Test("Keyset continuity: page 2 starts after page 1's last row; no duplicate or missing boundary row")
    func cursorContinuity() async throws {
        let firstPage = Array(1...20)
        let secondPage = Array(21...25)
        let harness = try PublicDataHarness { request in
            guard request.resource == "rpc/search_anime_page" else { return .emptyArray }
            // Rows strictly after the cursor row, as the keyset RPC returns them.
            guard let cursorId = request.jsonObject?["p_cursor_id"] as? Int else {
                return PublicRowJSON.cards(firstPage)
            }
            return PublicRowJSON.cards((firstPage + secondPage).filter { $0 > cursorId })
        }
        let search = harness.service.search

        search.resetSearch(query: "naruto", isManga: false)
        await search.fetchNextSearchPage()
        #expect(search.hasMoreSearch)
        await search.fetchNextSearchPage()

        let bodies = harness.requests(to: "rpc/search_anime_page").map { $0.jsonObject ?? [:] }
        #expect(bodies.count == 2)
        #expect(bodies.first?["p_cursor_id"] == nil)
        #expect(bodies.last?["p_cursor_id"] as? Int == 20)
        #expect(bodies.last?["p_cursor_popularity"] as? Int == PublicRowJSON.popularity(20))
        #expect(bodies.last?["p_cursor_rank"] as? Double == PublicRowJSON.rank(20))
        #expect(search.searchAnimeItems.map(\.id) == firstPage + secondPage)
        #expect(!search.hasMoreSearch)
        await harness.tearDown()
    }
}

// MARK: - Discovery content rules

@Suite("Public data: discovery content rules")
struct DiscoveryContentRulesTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let isAdult: Bool
        let genres: [String]
        /// nil: the default policy (no adult, no Ecchi).
        let includeAdult: Bool?
        let excludeEcchi: Bool?
        let kept: Bool
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "plain title is kept", isAdult: false, genres: ["Action"], includeAdult: nil, excludeEcchi: nil, kept: true),
        Case(name: "adult flag is removed", isAdult: true, genres: ["Action"], includeAdult: nil, excludeEcchi: nil, kept: false),
        Case(name: "Hentai genre is removed", isAdult: false, genres: ["Hentai"], includeAdult: nil, excludeEcchi: nil, kept: false),
        Case(name: "Ecchi genre is removed", isAdult: false, genres: ["Comedy", "Ecchi"], includeAdult: nil, excludeEcchi: nil, kept: false),
        Case(name: "includeAdult keeps an adult title", isAdult: true, genres: ["Action"], includeAdult: true, excludeEcchi: true, kept: true),
        Case(name: "includeAdult keeps Hentai when Ecchi is allowed", isAdult: false, genres: ["Hentai"], includeAdult: true, excludeEcchi: false, kept: true),
        Case(name: "excludeEcchi false keeps Ecchi", isAdult: false, genres: ["Ecchi"], includeAdult: false, excludeEcchi: false, kept: true),
        Case(name: "includeAdult still removes Ecchi by default", isAdult: false, genres: ["Ecchi"], includeAdult: true, excludeEcchi: true, kept: false),
    ]

    @MainActor
    @Test("sanitize*ForDiscovery and the blocked-tag rule", arguments: cases)
    func rules(_ testCase: Case) throws {
        let genres = testCase.genres.map { "\"\($0)\"" }.joined(separator: ",")
        let json = #"{"id":1,"is_adult":\#(testCase.isAdult),"genres":[\#(genres)],"created_at":0,"updated_at":0}"#
        let anime = try JSONDecoder().decode(Anime.self, from: Data(json.utf8))
        let manga = try JSONDecoder().decode(Manga.self, from: Data(json.utf8))
        let expected = testCase.kept ? 1 : 0

        if let includeAdult = testCase.includeAdult, let excludeEcchi = testCase.excludeEcchi {
            let policy = DiscoveryPolicy(includeAdult: includeAdult, excludeEcchi: excludeEcchi)
            #expect(DiscoveryContentRules.sanitizeAnimeForDiscovery([anime], policy: policy).count == expected)
            #expect(DiscoveryContentRules.sanitizeMangaForDiscovery([manga], policy: policy).count == expected)
        } else {
            #expect(DiscoveryContentRules.sanitizeAnimeForDiscovery([anime]).count == expected)
            #expect(DiscoveryContentRules.sanitizeMangaForDiscovery([manga]).count == expected)
        }
        // Tags follow the adult flag alone (detail sub-genres and genre facets).
        let tag = CatalogStore.TagNode(id: 1, name: "tag", category: nil, isAdult: testCase.isAdult)
        #expect(CatalogStore.isBlockedTag(tag) == testCase.isAdult)
    }
}
