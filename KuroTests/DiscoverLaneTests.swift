//
//  DiscoverLaneTests.swift
//  KuroTests
//
//  Discover lane (overnight 2026-11-01): one `discover_bundle` per launch and no repeated writer
//  call, the Airing today order (stated times only), per-account recent searches, Browse failure vs
//  empty, the frame copy and the width rules of the Discover, Browse, Search and Taste pages.
//

import Foundation
import KuroCore
import Testing
@testable import Kuro

private let emptyBundleJSON = """
    {"anime":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],
     "newly_added":[],"airing_today":[],"current_season":[]},
     "manga":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],"newly_added":[]}}
    """

@MainActor
@Suite("Discover lane: one bundle per launch", .timeLimit(.minutes(1)))
struct DiscoverBundleOncePerLaunchTests {
    @Test("The launch bundle is reused past the 120 s TTL: no second impression-writing call")
    func ensureReusesLaunchBundle() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_bundle" ? .json(emptyBundleJSON) : .emptyArray
        }
        let discovery = harness.service.discovery
        // The launch warm-up's entry, five minutes old on the same Berlin day (fixed instants, so the
        // test never straddles midnight).
        let storedAt = try #require(ISO8601DateFormatter().date(from: "2026-11-01T11:00:00Z"))
        discovery.discoverBundleCache[DiscoveryStore.bundleKey(user: nil, limit: 30, hours: 24)] = TimedCache(
            value: try LifecycleFixtures.decode(DiscoverBundle.self, emptyBundleJSON),
            storedAt: storedAt
        )

        #expect(await discovery.ensureDiscoverBundle(now: storedAt.addingTimeInterval(300)) != nil)
        #expect(harness.requests(to: "rpc/discover_bundle").isEmpty, "Discover's first load must not ask again")
        await harness.tearDown()
    }

    @Test("A bundle from an earlier Berlin day counts as missing (Airing today is never yesterday's)")
    func ensureExpiresAtRailMidnight() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_bundle" ? .json(emptyBundleJSON) : .emptyArray
        }
        let discovery = harness.service.discovery
        // 22:00 Berlin on 31 October, read again at 01:30 Berlin on 1 November.
        let storedAt = try #require(ISO8601DateFormatter().date(from: "2026-10-31T21:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-01T00:30:00Z"))
        #expect(!DiscoveryStore.isSameRailDay(storedAt, now))
        #expect(DiscoveryStore.isSameRailDay(now, now.addingTimeInterval(3600)))
        discovery.discoverBundleCache[DiscoveryStore.bundleKey(user: nil, limit: 30, hours: 24)] = TimedCache(
            value: try LifecycleFixtures.decode(DiscoverBundle.self, emptyBundleJSON),
            storedAt: storedAt
        )

        #expect(await discovery.ensureDiscoverBundle(now: now) != nil)
        #expect(harness.requests(to: "rpc/discover_bundle").count == 1)
        await harness.tearDown()
    }

    @Test("Memory pressure keeps the current account's launch bundle and drops the others")
    func trimKeepsLaunchBundle() async throws {
        let harness = try PublicDataHarness()
        let discovery = harness.service.discovery
        let bundle = try LifecycleFixtures.decode(DiscoverBundle.self, emptyBundleJSON)
        let mine = DiscoveryStore.bundleKey(user: nil, limit: 30, hours: 24)
        let other = DiscoveryStore.bundleKey(user: "someone-else", limit: 30, hours: 24)
        discovery.discoverBundleCache[mine] = TimedCache(value: bundle, storedAt: Date())
        discovery.discoverBundleCache[other] = TimedCache(value: bundle, storedAt: Date())

        discovery.trimCachesForMemoryPressure()

        #expect(discovery.discoverBundleCache[mine] != nil)
        #expect(discovery.discoverBundleCache[other] == nil)
        await harness.tearDown()
    }

    @Test("Without a launch bundle, the page and Taste share one read")
    func ensureLoadsOnceAndJoins() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_bundle" ? .json(emptyBundleJSON) : .emptyArray
        }
        let discovery = harness.service.discovery

        async let page = discovery.ensureDiscoverBundle()
        async let taste = discovery.ensureDiscoverBundle()
        let (a, b) = await (page, taste)
        #expect(a != nil && b != nil)
        #expect(await discovery.ensureDiscoverBundle() != nil)
        #expect(harness.requests(to: "rpc/discover_bundle").count == 1)
        await harness.tearDown()
    }

    @Test("Pull to refresh still asks for a fresh bundle")
    func forceStillReads() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_bundle" ? .json(emptyBundleJSON) : .emptyArray
        }
        let discovery = harness.service.discovery
        _ = await discovery.ensureDiscoverBundle()
        _ = await discovery.fetchDiscoverBundle(limit: 30, hours: 24, force: true)
        #expect(harness.requests(to: "rpc/discover_bundle").count == 2)
        await harness.tearDown()
    }

    @Test("A timed-out bundle call is not repeated (the server may already have recorded impressions)")
    func timeoutIsNotRetried() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_bundle" ? .failure(.timedOut) : .emptyArray
        }
        #expect(await harness.service.discovery.ensureDiscoverBundle() == nil)
        #expect(harness.requests(to: "rpc/discover_bundle").count == 1)
        await harness.tearDown()
    }

    @Test("A call that never left the device is repeated once")
    func preSendFailureIsRetriedOnce() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_bundle" ? .failure(.notConnectedToInternet) : .emptyArray
        }
        #expect(await harness.service.discovery.ensureDiscoverBundle() == nil)
        #expect(harness.requests(to: "rpc/discover_bundle").count == 2)
        await harness.tearDown()
    }

    @Test("Transport classification: only failures before sending are repeatable")
    func transportClassification() {
        #expect(DiscoveryTransport.failedBeforeSending(URLError(.notConnectedToInternet)))
        #expect(DiscoveryTransport.failedBeforeSending(URLError(.cannotFindHost)))
        #expect(!DiscoveryTransport.failedBeforeSending(URLError(.timedOut)))
        #expect(!DiscoveryTransport.failedBeforeSending(URLError(.networkConnectionLost)))
        #expect(!DiscoveryTransport.failedBeforeSending(CancellationError()))
    }
}

@MainActor
@Suite("Discover lane: Browse failure is not an empty page", .timeLimit(.minutes(1)))
struct BrowseFailureTests {
    @Test("A failed page is nil; an empty page is []; the legacy wrapper keeps []")
    func failureVersusEmpty() async throws {
        let failing = try PublicDataHarness { request in
            request.resource == "rpc/browse_anime_page" ? .failure(.timedOut) : .emptyArray
        }
        let failed = await failing.service.discovery.browseAnimePage(
            genre: nil, status: nil, minEpisodes: nil, maxEpisodes: nil,
            cursorInt: nil, cursorDate: nil, cursorId: nil, limit: 60
        )
        #expect(failed == nil)
        let legacy = await failing.service.discovery.fetchBrowseAnimePageKeyset(
            genre: nil, status: nil, minEpisodes: nil, maxEpisodes: nil,
            cursorInt: nil, cursorDate: nil, cursorId: nil, limit: 60
        )
        #expect(legacy.isEmpty)
        await failing.tearDown()

        let empty = try PublicDataHarness()
        let page = await empty.service.discovery.browseMangaPage(
            genre: nil, status: nil, minChapters: nil, maxChapters: nil,
            cursorInt: nil, cursorDate: nil, cursorId: nil, limit: 60
        )
        #expect(page?.isEmpty == true)
        await empty.tearDown()
    }
}

@MainActor
@Suite("Discover lane: Airing today order", .timeLimit(.minutes(1)))
struct AiringTodayOrderTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private func date(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try #require(formatter.date(from: iso))
    }

    @Test("Timed titles first, earliest first; untimed titles keep the server order")
    func ordering() throws {
        let now = try date("2026-11-01T09:00:00Z")
        let slots: [Int: DiscoverAiringSlot] = [
            3: DiscoverAiringSlot(animeId: 3, airingAt: try date("2026-11-01T20:30:00Z"), episode: 5),
            4: DiscoverAiringSlot(animeId: 4, airingAt: try date("2026-11-01T12:00:00Z"), episode: 9),
            // Rolled forward a week after airing: not today's slot.
            5: DiscoverAiringSlot(animeId: 5, airingAt: try date("2026-11-08T08:00:00Z"), episode: 2),
        ]
        let ordered = DiscoverAiringOrder.ordered([1, 2, 3, 4, 5], id: { $0 }, slots: slots, now: now, timeZone: berlin)
        #expect(ordered == [4, 3, 1, 2, 5])
    }

    @Test("Equal times keep the server order; no slot means no reorder")
    func stableTies() throws {
        let now = try date("2026-11-01T09:00:00Z")
        let at = try date("2026-11-01T15:00:00Z")
        let slots: [Int: DiscoverAiringSlot] = [
            8: DiscoverAiringSlot(animeId: 8, airingAt: at, episode: nil),
            7: DiscoverAiringSlot(animeId: 7, airingAt: at, episode: nil),
        ]
        #expect(DiscoverAiringOrder.ordered([7, 8, 9], id: { $0 }, slots: slots, now: now, timeZone: berlin) == [7, 8, 9])
        #expect(DiscoverAiringOrder.ordered([3, 1, 2], id: { $0 }, slots: [:], now: now, timeZone: berlin) == [3, 1, 2])
    }

    @Test("Today is the rail's Berlin day (23:30 UTC on 31 Oct is already 1 Nov in Berlin)")
    func berlinDay() throws {
        let now = try date("2026-11-01T10:00:00Z")
        let lateEvening = DiscoverAiringSlot(animeId: 1, airingAt: try date("2026-10-31T23:30:00Z"), episode: 1)
        let yesterday = DiscoverAiringSlot(animeId: 2, airingAt: try date("2026-10-31T22:30:00Z"), episode: 1)
        #expect(DiscoverAiringOrder.todaysSlot(lateEvening, now: now, timeZone: berlin) != nil)
        #expect(DiscoverAiringOrder.todaysSlot(yesterday, now: now, timeZone: berlin) == nil)
        #expect(DiscoverAiringOrder.todaysSlot(nil, now: now, timeZone: berlin) == nil)
    }

    @Test("Stated times are read once per session with a narrow column list")
    func airingSlotRead() async throws {
        let harness = try PublicDataHarness { request in
            guard request.resource == "anime" else { return .emptyArray }
            return .json(#"[{"id":11,"next_airing_at":"2026-11-01T12:00:00+00:00","next_episode_number":4},{"id":12,"next_airing_at":null,"next_episode_number":null}]"#)
        }
        let discovery = harness.service.discovery
        await discovery.loadAiringSlots(for: [11, 12])
        await discovery.loadAiringSlots(for: [11, 12])

        let reads = harness.requests(to: "anime")
        #expect(reads.count == 1)
        #expect(reads.first?.query("select") == "id,next_airing_at,next_episode_number")
        #expect(discovery.airingSlots[11]?.episode == 4)
        #expect(discovery.airingSlots[12] == nil, "a title without a stated time gets no slot")

        // A new rail day reads again (a long-lived session never keeps yesterday's slots).
        await discovery.loadAiringSlots(for: [11, 12], now: Date().addingTimeInterval(2 * 24 * 3600))
        #expect(harness.requests(to: "anime").count == 2)
        await harness.tearDown()
    }
}

@MainActor
@Suite("Discover lane: recent searches", .timeLimit(.minutes(1)))
struct RecentSearchTests {
    @Test("Newest first, case-insensitively unique, capped, never shorter than two characters")
    func listRules() {
        var list = RecentSearchList(["Frieren", "frieren", "a", "  Monster  "])
        #expect(list.queries == ["Frieren", "Monster"])
        list.record("MONSTER")
        #expect(list.queries == ["MONSTER", "Frieren"])
        list.record("x")
        #expect(list.queries.count == 2)
        for index in 0..<12 { list.record("Title \(index)") }
        #expect(list.queries.count == RecentSearchList.capacity)
        #expect(list.queries.first == "Title 11")
        list.remove("title 11")
        #expect(list.queries.first == "Title 10")
        #expect(RecentSearchList.storageKey(userId: "ABC") == "kuro.search.recent.abc")
        #expect(RecentSearchList.storageKey(userId: nil) == nil)
    }

    @Test("Each account keeps its own list on this device; signed out records nothing")
    func accountIsolation() async throws {
        let suite = "kuro.tests.recent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let harness = try PublicDataHarness()
        let accounts = AccountSessionCoordinator()
        let discovery = DiscoveryStore(client: nil, accountSession: accounts, library: harness.service.library, defaults: defaults)

        discovery.recordRecentSearch("Signed out")
        #expect(discovery.recentSearches.isEmpty)

        _ = accounts.begin(userId: "user-a")
        discovery.loadRecentSearches()
        discovery.recordRecentSearch("Frieren")
        #expect(discovery.recentSearches == ["Frieren"])

        _ = accounts.begin(userId: "user-b")
        discovery.clearPrivateState()
        discovery.loadRecentSearches()
        #expect(discovery.recentSearches.isEmpty, "B never sees A's searches")
        discovery.recordRecentSearch("Monster")

        _ = accounts.begin(userId: "user-a")
        discovery.loadRecentSearches()
        #expect(discovery.recentSearches == ["Frieren"])
        discovery.clearRecentSearches()
        #expect(defaults.stringArray(forKey: "kuro.search.recent.user-a") == nil)
        #expect(defaults.stringArray(forKey: "kuro.search.recent.user-b") == ["Monster"])
        await harness.tearDown()
    }

    @Test("Account deletion removes that account's searches from the device; sign-out keeps them")
    func deletionRemovesDeviceHistory() async throws {
        let suite = "kuro.tests.recent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let harness = try PublicDataHarness()
        let accounts = AccountSessionCoordinator()
        let discovery = DiscoveryStore(client: nil, accountSession: accounts, library: harness.service.library, defaults: defaults)

        _ = accounts.begin(userId: "user-a")
        discovery.loadRecentSearches()
        discovery.recordRecentSearch("Frieren")
        _ = accounts.begin(userId: "user-b")
        discovery.loadRecentSearches()
        discovery.recordRecentSearch("Monster")

        discovery.clearPrivateState()
        #expect(defaults.stringArray(forKey: "kuro.search.recent.user-a") == ["Frieren"], "account change keeps device history")

        try await discovery.removeDeletedAccountData(userId: "USER-A")
        #expect(defaults.stringArray(forKey: "kuro.search.recent.user-a") == nil)
        #expect(defaults.stringArray(forKey: "kuro.search.recent.user-b") == ["Monster"])
        await harness.tearDown()
    }
}

@MainActor
@Suite("Discover lane: copy and layout", .timeLimit(.minutes(1)))
struct DiscoverCopyAndLayoutTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    @Test("Frame line: stated airing slot, else year and length, else status or format; EN and DE")
    func frameLine() throws {
        let at = try #require(ISO8601DateFormatter().date(from: "2026-11-01T20:30:00Z"))
        let slot = DiscoverAiringSlot(animeId: 1, airingAt: at, episode: 7)
        let de = Locale(identifier: "de_DE")
        #expect(DiscoverFrameCopy.line(kind: .anime, year: "2026", episodes: 12, chapters: nil, statusRaw: nil, formatRaw: nil,
                                       airing: slot, german: true, locale: de, timeZone: berlin) == "Folge 7 · 21:30")
        #expect(DiscoverFrameCopy.line(kind: .anime, year: "2019", episodes: 12, chapters: nil, statusRaw: nil, formatRaw: nil,
                                       german: false, locale: de, timeZone: berlin) == "2019 · 12 eps")
        #expect(DiscoverFrameCopy.line(kind: .manga, year: "2008", episodes: nil, chapters: 120, statusRaw: nil, formatRaw: nil,
                                       german: true, locale: de, timeZone: berlin) == "2008 · 120 Kap.")
        #expect(DiscoverFrameCopy.line(kind: .anime, year: "TBA", episodes: nil, chapters: nil, statusRaw: "RELEASING", formatRaw: nil,
                                       german: false, locale: de, timeZone: berlin) == "Airing")
        #expect(DiscoverFrameCopy.line(kind: .anime, year: "TBA", episodes: nil, chapters: nil, statusRaw: nil, formatRaw: nil,
                                       german: false, locale: de, timeZone: berlin) == nil)
    }

    @Test("No-results copy follows the rulebook (EN/DE)")
    func noResults() {
        #expect(EditorialSearchView.noResultsTitle(query: " Frieren ", refinements: [], german: false) == "No titles match \u{2018}Frieren\u{2019}.")
        #expect(EditorialSearchView.noResultsTitle(query: "Frieren", refinements: [], german: true) == "Keine Titel passen zu \u{201E}Frieren\u{201C}.")
        #expect(EditorialSearchView.noResultsTitle(query: "", refinements: [.classics], german: false) == "No titles for Classics.")
        #expect(EditorialSearchView.shouldRunSearch(query: "a", hasFilters: false) == false)
        #expect(EditorialSearchView.shouldRunSearch(query: "", hasFilters: true))
    }

    @Test("Section titles are sentence case and exist in both languages for every See all route")
    func routeTitles() {
        for route in EditorialDiscoverRoute.allCases {
            let english = route.title(german: false)
            let german = route.title(german: true)
            #expect(!english.isEmpty && !german.isEmpty)
            #expect(english != english.uppercased(), "\(route) must not be all caps")
        }
        #expect(EditorialDiscoverRoute.animeBecauseYou.title(german: false, reason: "Frieren") == "Because you loved Frieren")
        #expect(EditorialDiscoverRoute.mangaTrending.isManga)
    }

    @Test("Widths: 16 pt gutter at 320, at least two columns, more on the iPad column, readable cap")
    func layout() {
        #expect(DiscoverLayout.gutter(for: 320) == 16)
        #expect(DiscoverLayout.gutter(for: 390) == 20)
        #expect(DiscoverLayout.columnCount(for: 288) == 2)
        #expect(DiscoverLayout.columnCount(for: 350) == 2)
        #expect(DiscoverLayout.columnCount(for: 640) == 4)
        #expect(DiscoverLayout.contentWidth(container: 1024, regularWidth: true) == 680)
        #expect(DiscoverLayout.contentWidth(container: 390, regularWidth: false) == 390)
        let width = DiscoverLayout.gridFrameWidth(for: 350, columns: 2)
        #expect(width * 2 + DiscoverLayout.frameSpacing <= 350)
        #expect(DiscoverLayout.railFrameWidth(for: 320, large: true) >= 132)
        #expect(DiscoverLayout.railFrameWidth(for: 430, large: false) <= 144)
    }

    @Test("Taste picks: personal with two or more, else unseen, else a short start; first story sentence only")
    func tastePicks() {
        let personal = TastePicksCopy.choose(personal: [1, 2, 3, 4, 5], unseen: [9], start: [8], cap: 4, german: false)
        #expect(personal.items == [1, 2, 3, 4])
        #expect(TastePicksCopy.choose(personal: [1], unseen: [9], start: [8], cap: 4, german: false).items == [9])
        #expect(TastePicksCopy.choose(personal: [Int](), unseen: [], start: [8], cap: 4, german: true).items == [8])
        let none = TastePicksCopy.choose(personal: [Int](), unseen: [], start: [], cap: 4, german: false)
        #expect(none.items.isEmpty)
        #expect(TastePicksCopy.storySentence("An elf mage <i>outlives</i> her party. Then she travels.") == "An elf mage outlives her party.")
        #expect(TastePicksCopy.storySentence("   ") == nil)
    }

    @Test("Taste picks: a failed read never settles as the empty state")
    func tastePicksSettle() {
        // Both reads loaded: an empty choice is a true empty state.
        #expect(TastePicksCopy.isSettled(personal: 0, bundleLoaded: true, chosen: 0))
        // Bundle failed: only an own personal set (two or more) may be shown.
        #expect(TastePicksCopy.isSettled(personal: 3, bundleLoaded: false, chosen: 3))
        #expect(!TastePicksCopy.isSettled(personal: 1, bundleLoaded: false, chosen: 0))
        #expect(!TastePicksCopy.isSettled(personal: 0, bundleLoaded: false, chosen: 0))
        #expect(!TastePicksCopy.isSettled(personal: nil, bundleLoaded: false, chosen: 0))
        // Because-you failed: bundle picks may stand in, but an empty choice is not "empty".
        #expect(TastePicksCopy.isSettled(personal: nil, bundleLoaded: true, chosen: 2))
        #expect(!TastePicksCopy.isSettled(personal: nil, bundleLoaded: true, chosen: 0))
    }
}

@Suite("Today's pick argument is plain text")
struct DailyFeatureArgumentTests {
    @Test("HTML from the source never reaches the lead frame; spacing collapses to one line")
    func argumentIsSanitized() throws {
        let json = #"{"media_type":"MANGA","media_id":1,"title":"Goodnight Punpun","argument":"Meet Punpun Punyama. He’s an average kid in an average town.<br>\n<br>\nHis <i>dad</i> is gone."}"#
        let feature = try JSONDecoder().decode(DailyFeature.self, from: Data(json.utf8))
        let line = try #require(feature.displayArgument)
        #expect(!line.contains("<"))
        #expect(!line.contains("\n"))
        #expect(line.hasPrefix("Meet Punpun Punyama. He’s an average kid in an average town."))
        let empty = try JSONDecoder().decode(DailyFeature.self, from: Data(#"{"media_type":"ANIME","media_id":2,"title":"x","argument":"<br>"}"#.utf8))
        #expect(empty.displayArgument == nil)
    }
}
