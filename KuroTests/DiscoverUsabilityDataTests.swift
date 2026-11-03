//
//  DiscoverUsabilityDataTests.swift
//  KuroTests
//
//  DATA lane of the 2026-11-04 Discover usability pass: the Discover contract's data rules (R2
//  franchise/owned/hidden composition, R5 Not interested / Seen it memory with Undo, R6 See all sort
//  and filters, mood journeys) and their owners (`TasteStore`, `DiscoveryStore`) with silent
//  fallback while the prepared readers (20261104100000) are not deployed. HTTP tests run the real
//  supabase-swift client against StubPostgREST (in-process, no network).
//

import Foundation
import KuroCore
import KuroLibrary
import Synchronization
import Testing
@testable import Kuro

private enum DUJSON {
    static let pgrst202 = StubResponse.json(
        #"{"code":"PGRST202","message":"Could not find the function in the schema cache","details":null,"hint":null}"#,
        status: 404)
    static let serverError = StubResponse.json(#"{"code":"XX000","message":"boom","details":null,"hint":null}"#, status: 500)
    static let signalOK = StubResponse.json(#"{"ok":true}"#)
}

private func anime(_ id: Int, _ title: String, popularity: Int = 100, score: Int? = 80, year: Int? = 2020,
                   episodes: Int? = 12, status: String = "FINISHED", format: String = "TV") -> AnimeCard {
    AnimeCard(id: id, titleEnglish: title, titleRomaji: title, titleNative: nil, coverImageLarge: "https://img.invalid/\(id).jpg",
              coverImageMedium: nil, bannerImage: nil, format: format, status: status, episodeCount: episodes,
              seasonYear: year, startDateYear: year, averageScore: score, popularity: popularity, trending: nil,
              favourites: nil, genreList: nil, createdAt: nil, rank: nil)
}

private func manga(_ id: Int, _ title: String, chapters: Int? = 40) -> MangaCard {
    MangaCard(id: id, titleEnglish: title, titleRomaji: title, titleNative: nil, coverImageLarge: "https://img.invalid/m\(id).jpg",
              coverImageMedium: nil, format: "MANGA", status: "FINISHED", chapterCount: chapters, startDateYear: 2001,
              averageScore: 80, popularity: 10, trending: nil, favourites: nil, genreList: nil, createdAt: nil, rank: nil)
}

// MARK: - Pure rules

@MainActor
@Suite("Discover usability data: pure rules", .timeLimit(.minutes(1)))
struct DiscoverUsabilityRuleTests {
    @Test("Feedback mapping is one constant: Not interested = deck 'skip' (teaches Taste), Seen it = 'known'; pass and love never hide")
    func feedbackMapping() {
        #expect(DiscoverFeedback.notInterested.deckAction == .skip)
        #expect(DiscoverFeedback.seenIt.deckAction == .known)
        #expect(DiscoverFeedback(eventType: "deck_skip") == .notInterested)
        #expect(DiscoverFeedback(eventType: "deck_known") == .seenIt)
        #expect(DiscoverFeedback(eventType: "deck_pass") == nil, "an undecided deck swipe must not vanish from Discover")
        #expect(DiscoverFeedback(eventType: "deck_love") == nil)
        #expect(DiscoverFeedback(deckAction: .retract) == nil)
    }

    @Test("Title stem: season, part, sequel and subtitle markers collapse to one series; short or distinct names stay apart")
    func stems() {
        let same: [(String, String)] = [
            ("Demon Slayer: Kimetsu no Yaiba", "Demon Slayer: Kimetsu no Yaiba Swordsmith Village Arc"),
            ("Attack on Titan", "Attack on Titan Season 3 Part 2"),
            ("Attack on Titan", "Attack on Titan: The Final Season"),
            ("Mob Psycho 100", "Mob Psycho 100 II"),
            ("Spy x Family", "SPY x FAMILY Season 2"),
            ("Kaguya-sama: Love is War", "Kaguya-sama: Love Is War - Ultra Romantic"),
            ("Re:ZERO -Starting Life in Another World-", "Re:ZERO -Starting Life in Another World- Season 2"),
            ("Haikyu!!", "Haikyu!! 2nd Season"),
        ]
        for (a, b) in same {
            #expect(DiscoverFranchiseStem.stem(a) != nil && DiscoverFranchiseStem.stem(a) == DiscoverFranchiseStem.stem(b), "\(a) / \(b)")
        }
        #expect(DiscoverFranchiseStem.stem("Monster") != DiscoverFranchiseStem.stem("Monster Musume: Everyday Life with Monster Girls"))
        #expect(DiscoverFranchiseStem.stem("86") == nil, "too short to be a safe key")
        #expect(DiscoverFranchiseStem.stem("Mob Psycho 100") == "mob psycho 100", "a 3-digit number is part of the name")
    }

    private func keys(_ card: AnimeCard, components: [Int: Int] = [:]) -> Set<DiscoverFranchiseKey> {
        var keys: Set<DiscoverFranchiseKey> = [.component(.anime, components[card.id] ?? card.id)]
        if let stem = DiscoverFranchiseStem.stem(card.title) { keys.insert(.stem(.anime, stem)) }
        return keys
    }

    @Test("Composer: hidden out, owned hidden in personal / marked in editorial, one franchise per page (first wins), backfill to the display count")
    func composer() {
        let aot1 = anime(1, "Attack on Titan"), aot2 = anime(2, "Attack on Titan Season 2")
        let ds1 = anime(3, "Demon Slayer: Kimetsu no Yaiba"), ds2 = anime(4, "Demon Slayer: Mugen Train")
        let owned = anime(5, "Frieren"), hidden = anime(6, "Mushishi"), odd = anime(7, "Odd Taxi"), ping = anime(8, "Ping Pong")
        let sameComponent = anime(9, "Shingeki Specials")   // no shared stem, same server component as aot1
        let sections = [
            DiscoverSectionInput(id: "newToYou", policy: .hide, items: [aot1, owned, hidden, ds1, ds2, odd], displayCount: 3),
            DiscoverSectionInput(id: "essentials", policy: .mark, items: [aot2, owned, ds2, sameComponent, ping, odd], displayCount: 3),
        ]
        let placed = DiscoverPageComposer.compose(
            sections,
            key: { MediaKey(kind: .anime, id: $0.id) },
            franchiseKeys: { self.keys($0, components: [9: 1]) },
            isHidden: { $0.id == 6 },
            ownedStatus: { $0.id == 5 ? .current : nil })
        #expect(placed.map(\.id) == ["newToYou", "essentials"])
        #expect(placed[0].items.map(\.item.id) == [1, 3, 7], "owned + hidden out; Demon Slayer once (first wins)")
        #expect(placed[0].items.allSatisfy { $0.ownedStatus == nil })
        #expect(placed[1].items.map(\.item.id) == [5, 8], "AoT S2 / DS film / same component out; the owned title stays, marked")
        #expect(placed[1].items.first?.ownedStatus == .current)
        #expect(placed[0].remainingCount == 0)
    }

    @Test("Composer: anime 7 and manga 7 are different titles; within one section a franchise also appears once")
    func composerKeysCarryMedium() {
        struct Row { let key: MediaKey; let title: String }
        let rows = [Row(key: MediaKey(kind: .anime, id: 7), title: "Monster"), Row(key: MediaKey(kind: .manga, id: 7), title: "Monster"),
                    Row(key: MediaKey(kind: .anime, id: 8), title: "Monster")]
        let placed = DiscoverPageComposer.compose(
            [DiscoverSectionInput(id: "all", policy: .mark, items: rows, displayCount: 10)],
            key: { $0.key },
            franchiseKeys: { row in [.stem(row.key.kind, DiscoverFranchiseStem.stem(row.title) ?? "")] },
            isHidden: { _ in false }, ownedStatus: { _ in nil })
        #expect(placed[0].items.map(\.item.key) == [MediaKey(kind: .anime, id: 7), MediaKey(kind: .manga, id: 7)])
    }

    @Test("Accumulator: pages append without repeating a title or franchise; hidden and owned rules; the journey ends on a nil cursor")
    func accumulator() {
        func item(_ id: Int, _ title: String, franchise: Int? = nil, server: ListStatus? = nil) -> DiscoverPageItem {
            DiscoverPageItem(card: .anime(anime(id, title)), franchiseId: franchise, serverListStatus: server)
        }
        func fkeys(_ item: DiscoverPageItem) -> Set<DiscoverFranchiseKey> {
            var keys: Set<DiscoverFranchiseKey> = [.component(.anime, item.franchiseId ?? item.key.id)]
            if let stem = DiscoverFranchiseStem.stem(item.card.title) { keys.insert(.stem(.anime, stem)) }
            return keys
        }
        var journey = DiscoverPageAccumulator(policy: .mark)
        #expect(!journey.isFinished)
        journey.append(DiscoverPage(items: [item(1, "Frieren"), item(2, "Mushishi", server: .completed), item(3, "Odd Taxi")],
                                    next: .offset(3), reason: DiscoverReason(key: MediaKey(kind: .anime, id: 99), title: "Seed"), origin: .server),
                       franchiseKeys: fkeys, isHidden: { $0.id == 3 }, ownedStatus: { _ in nil })
        journey.append(DiscoverPage(items: [item(1, "Frieren"), item(4, "Frieren Season 2"), item(5, "Ping Pong", franchise: 2)],
                                    next: nil, reason: nil, origin: .server),
                       franchiseKeys: fkeys, isHidden: { _ in false }, ownedStatus: { $0.id == 1 ? .planning : nil })
        #expect(journey.items.map(\.item.key.id) == [1, 2], "repeat, same stem and same component dropped; hidden out")
        #expect(journey.items[1].ownedStatus == .completed, "the server's list status marks when the Library has no entry")
        #expect(journey.reason?.title == "Seed")
        #expect(journey.isFinished)
        journey.remove(MediaKey(kind: .anime, id: 1))
        #expect(journey.items.map(\.item.key.id) == [2])

        var personal = DiscoverPageAccumulator(policy: .hide)
        personal.append(DiscoverPage(items: [item(1, "Frieren"), item(2, "Mushishi")], next: .offset(2), reason: nil, origin: .fallback),
                        franchiseKeys: fkeys, isHidden: { _ in false }, ownedStatus: { $0.id == 1 ? .current : nil })
        #expect(personal.items.map(\.item.key.id) == [2])
        #expect(personal.items[0].ownedStatus == nil)
    }

    @Test("Hidden memory: hides and undos apply in order over the snapshot; a server read prunes what it reflects; lifetime and capacity bound the overlay")
    func hiddenMemory() throws {
        let a = MediaKey(kind: .anime, id: 1), b = MediaKey(kind: .manga, id: 1), c = MediaKey(kind: .anime, id: 3)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var memory = DiscoverHiddenMemory()
        memory.adopt(server: [c: .seenIt], now: t0)
        memory.record(a, state: .notInterested, at: t0)
        memory.record(b, state: .seenIt, at: t0)
        memory.record(c, state: nil, at: t0)
        #expect(memory.hidden.compactMapValues { $0 } == [a: .notInterested, b: .seenIt])

        // The server now reflects a (hidden) but still shows c hidden and does not know b yet.
        memory.adopt(server: [a: .notInterested, c: .seenIt], now: t0.addingTimeInterval(60))
        #expect(memory.overlay.map(\.ref) == [DiscoverMediaRef(b), DiscoverMediaRef(c)], "a is reflected and pruned")
        #expect(memory.hidden.compactMapValues { $0 } == [a: .notInterested, b: .seenIt], "a local undo beats a stale server row")

        // After the lifetime an unreflected entry is dropped.
        memory.adopt(server: [a: .notInterested, c: .seenIt], now: t0.addingTimeInterval(DiscoverHiddenMemory.overlayLifetime + 1))
        #expect(memory.overlay.isEmpty)
        #expect(memory.hidden.compactMapValues { $0 } == [a: .notInterested, c: .seenIt])

        for id in 0..<(DiscoverHiddenMemory.overlayCapacity + 5) {
            memory.record(MediaKey(kind: .anime, id: 10_000 + id), state: .notInterested, at: t0)
        }
        #expect(memory.overlay.count == DiscoverHiddenMemory.overlayCapacity)

        let data = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(DiscoverHiddenMemory.self, from: data) == memory)
        #expect(DiscoverHiddenMemory.storageKey(userId: "ABC") == "kuro.discover.hidden.abc")
        #expect(DiscoverHiddenMemory.storageKey(userId: nil) == nil)
    }

    @Test("Local See all page: medium, format, length and status filters; popular / top rated / newest (release year) sorts keep the section order on ties")
    func localPage() {
        let cards: [DiscoverCardValue] = [
            .anime(anime(1, "A", popularity: 10, score: 70, year: 2001, episodes: 12)),
            .anime(anime(2, "B", popularity: 30, score: 90, year: 2020, episodes: 64)),
            .anime(anime(3, "C", popularity: 20, score: nil, year: 2010, episodes: 1, format: "MOVIE")),
            .anime(anime(4, "D", popularity: 30, score: 90, year: nil, episodes: 24, status: "RELEASING")),
            .manga(manga(5, "M")),
        ]
        func ids(_ query: DiscoverSeeAllQuery) -> [Int] { DiscoverLocalPage.page(cards, query: query).map(\.key.id) }
        var query = DiscoverSeeAllQuery(section: .essentials, medium: .anime)
        #expect(ids(query) == [1, 2, 3, 4])
        query.sort = .popular
        #expect(ids(query) == [2, 4, 3, 1])
        query.sort = .topRated
        #expect(ids(query) == [2, 4, 1, 3], "unknown score last")
        query.sort = .newest
        #expect(ids(query) == [2, 3, 1, 4], "release year, unknown last")
        query = DiscoverSeeAllQuery(section: .essentials, medium: .anime, length: .short)
        #expect(ids(query) == [1, 3])
        query = DiscoverSeeAllQuery(section: .essentials, medium: .anime, format: "movie")
        #expect(ids(query) == [3])
        query = DiscoverSeeAllQuery(section: .essentials, medium: .anime, status: .releasing)
        #expect(ids(query) == [4])
        #expect(ids(DiscoverSeeAllQuery(section: .essentials, medium: .manga)) == [5])
        #expect(DiscoverLengthFilter.short.matches(kind: .manga, episodes: nil, chapters: nil, volumes: 4))
        #expect(!DiscoverLengthFilter.long.matches(kind: .anime, episodes: nil, chapters: nil))
    }

    @Test("Section policies and server paging: personal sections hide owned titles; anime-only sections are not paged for manga")
    func sectionPolicies() {
        #expect(DiscoverSectionKey.newToYou.ownedPolicy == .hide)
        #expect(DiscoverSectionKey.becauseYou.ownedPolicy == .hide)
        #expect(DiscoverSectionKey.essentials.ownedPolicy == .mark)
        #expect(DiscoverSectionKey.trending.ownedPolicy == .mark)
        #expect(!DiscoverSectionKey.becauseYou.isServerPaged(for: .anime))
        #expect(!DiscoverSectionKey.currentSeason.isServerPaged(for: .manga))
        #expect(DiscoverSectionKey.currentSeason.isServerPaged(for: .anime))
    }

    @Test("Server paging overlaps the boundary: a title hidden or planned mid-journey shifts the pool, the overlap re-reads it and the accumulator drops the repeats")
    func pagingOverlap() {
        #expect(DiscoveryStore.pageOverlap(limit: 24) == 8)
        #expect(DiscoveryStore.pageOverlap(limit: 3) == 1)
        #expect(DiscoveryStore.pageOverlap(limit: 2) == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func rows(firstId: Int, firstRank: Int, count: Int) -> [DiscoverPageRow] {
            (try? decoder.decode([DiscoverPageRow].self, from: Data(DiscoverUsabilityFixtures.pageRowsJSON(
                kind: .anime, count: count, firstId: firstId, firstRank: firstRank).utf8))) ?? []
        }
        // Page 1: ranks 1-3 = ids 100-102. Next asks offset 2 (overlap 1), not 3.
        let first = DiscoveryStore.serverPage(rows(firstId: 100, firstRank: 1, count: 3), offset: 0, limit: 3)
        #expect(first.next == .offset(2))
        var journey = DiscoverPageAccumulator(policy: .mark)
        journey.append(first, franchiseKeys: { [.component(.anime, $0.key.id)] }, isHidden: { _ in false }, ownedStatus: { _ in nil })
        // The person hides 101: the server pool shrinks, 102 is now rank 2 and 103 rank 3. Offset 2
        // answers 103...; without the overlap (offset 3) 103 would never be shown.
        journey.remove(MediaKey(kind: .anime, id: 101))
        let second = DiscoveryStore.serverPage(rows(firstId: 103, firstRank: 3, count: 3), offset: 2, limit: 3)
        journey.append(second, franchiseKeys: { [.component(.anime, $0.key.id)] },
                       isHidden: { $0.id == 101 }, ownedStatus: { _ in nil })
        #expect(journey.items.map(\.item.key.id) == [100, 102, 103, 104, 105])
        // Without a shift the overlap row is a repeat and is dropped.
        var steady = DiscoverPageAccumulator(policy: .mark)
        steady.append(first, franchiseKeys: { [.component(.anime, $0.key.id)] }, isHidden: { _ in false }, ownedStatus: { _ in nil })
        steady.append(DiscoveryStore.serverPage(rows(firstId: 102, firstRank: 3, count: 3), offset: 2, limit: 3),
                      franchiseKeys: { [.component(.anime, $0.key.id)] }, isHidden: { _ in false }, ownedStatus: { _ in nil })
        #expect(steady.items.map(\.item.key.id) == [100, 101, 102, 103, 104])
        // A page too small for an overlap still advances.
        #expect(DiscoveryStore.serverPage(rows(firstId: 1, firstRank: 1, count: 1), offset: 0, limit: 1).next == .offset(1))
    }

    @Test("Fixture rows decode into pages (both media, reason, list status)")
    func fixtures() {
        let page = DiscoverUsabilityFixtures.page(kind: .anime, count: 4, reason: (id: 5, title: "Frieren"))
        #expect(page.items.count == 4)
        #expect(page.reason?.title == "Frieren")
        #expect(DiscoverUsabilityFixtures.page(kind: .manga, count: 3).items.allSatisfy { $0.key.kind == .manga })
    }
}

// MARK: - TasteStore: Not interested / Seen it

@MainActor
@Suite("Discover usability data: Discover answers (TasteStore)", .serialized, .timeLimit(.minutes(1)))
struct DiscoverFeedbackStoreTests {
    static let userA = "AAAAAAAA-0000-4000-8000-00000000000A"
    static let userB = "BBBBBBBB-0000-4000-8000-00000000000B"
    static let signalRPC = "rpc/record_taste_deck_signal"

    @MainActor
    private struct Fixture {
        let server = StubServer()
        let accountSession = AccountSessionCoordinator()
        let suiteName = "kuro.tests.discover-answers.\(UUID().uuidString)"
        let defaults: UserDefaults

        init(signals: String = "[]") throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            let rows = signals
            server.respond { request in
                switch request.resource {
                case DiscoverFeedbackStoreTests.signalRPC: return DUJSON.signalOK
                case "taste_signal_events": return .json(rows)
                default: return .emptyArray
                }
            }
        }

        func store(libraryHook: LibraryRefreshHook? = nil) -> TasteStore {
            TasteStore(client: StubSupabase.makeClient(server: server), accountSession: accountSession,
                       libraryHook: libraryHook ?? LibraryRefreshHook(), retryBaseDelay: 10, defaults: defaults)
        }

        func sentSignals() -> [String] {
            server.requests.filter { $0.resource == DiscoverFeedbackStoreTests.signalRPC }.compactMap { request in
                guard let body = request.jsonObject, let action = body["p_action"] as? String,
                      let id = body["p_media_id"] as? Int, let type = body["p_media_type"] as? String else { return nil }
                return "\(action) \(type) \(id)"
            }
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            server.shutDown()
        }
    }

    @Test("An answer hides the title at once, is delivered as one deck signal, and Undo retracts it when there was none before")
    func recordAndUndo() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        _ = fixture.accountSession.begin(userId: Self.userA)
        let taste = fixture.store()
        let key = MediaKey(kind: .anime, id: 42)
        let receipt = try #require(taste.recordDiscoverFeedback(.notInterested, for: key))
        #expect(taste.isHiddenOnDiscover(key))
        #expect(taste.discoverHidden[key] == .notInterested)
        #expect(receipt.priorAction == nil)
        await taste.drainTask?.value
        #expect(fixture.sentSignals() == ["skip ANIME 42"])

        #expect(taste.undoDiscoverFeedback(receipt))
        #expect(!taste.isHiddenOnDiscover(key))
        await taste.drainTask?.value
        #expect(fixture.sentSignals() == ["skip ANIME 42", "retract ANIME 42"])

        let seen = try #require(taste.recordDiscoverFeedback(.seenIt, for: MediaKey(kind: .manga, id: 42)))
        await taste.drainTask?.value
        #expect(fixture.sentSignals().last == "known MANGA 42")
        #expect(seen.key.kind == .manga)
    }

    @Test("The server read: own deck rows only (user, event types, window, newest first); skip/known hide, pass/love do not; Undo restores a deck love instead of erasing it")
    func serverReadAndPriorAction() async throws {
        let now = Date()
        let rows = DiscoverUsabilityFixtures.deckSignalRowsJSON([
            (MediaKey(kind: .anime, id: 1), "deck_skip", now),
            (MediaKey(kind: .anime, id: 2), "deck_known", now.addingTimeInterval(-60)),
            (MediaKey(kind: .anime, id: 3), "deck_pass", now.addingTimeInterval(-120)),
            (MediaKey(kind: .manga, id: 4), "deck_love", now.addingTimeInterval(-180)),
        ])
        let fixture = try Fixture(signals: rows)
        defer { fixture.tearDown() }
        // A delivered 'love' (the Undo below) calls the Library hook: connect it to a graph's actions.
        let graph = try PublicDataHarness()
        let hook = LibraryRefreshHook()
        hook.connect(to: graph.service.libraryActions)
        _ = fixture.accountSession.begin(userId: Self.userA)
        let taste = fixture.store(libraryHook: hook)
        #expect(await taste.loadDiscoverHidden())
        #expect(taste.discoverHidden == [MediaKey(kind: .anime, id: 1): .notInterested, MediaKey(kind: .anime, id: 2): .seenIt])

        let read = try #require(fixture.server.requests.first { $0.resource == "taste_signal_events" })
        #expect(read.method == "GET")
        #expect(read.query("user_id") == "eq.\(Self.userA.lowercased())")
        #expect(read.query("event_type") == "in.(deck_love,deck_known,deck_skip,deck_pass)")
        #expect(read.query("created_at")?.hasPrefix("gte.") == true)
        #expect(read.query("order")?.hasPrefix("created_at.desc") == true)
        #expect(read.query("limit") == "2000")

        // Within the TTL the read is reused.
        #expect(await taste.loadDiscoverHidden())
        #expect(fixture.server.requests.filter { $0.resource == "taste_signal_events" }.count == 1)

        let loved = MediaKey(kind: .manga, id: 4)
        let receipt = try #require(taste.recordDiscoverFeedback(.notInterested, for: loved))
        #expect(receipt.priorAction == .love)
        await taste.drainTask?.value
        #expect(taste.undoDiscoverFeedback(receipt))
        await taste.drainTask?.value
        #expect(fixture.sentSignals() == ["skip MANGA 4", "love MANGA 4"])
        #expect(!taste.isHiddenOnDiscover(loved))

        // Undo of a Not interested on a title already marked Seen it restores Seen it (still hidden).
        let known = MediaKey(kind: .anime, id: 2)
        let second = try #require(taste.recordDiscoverFeedback(.notInterested, for: known))
        #expect(second.priorAction == .known)
        taste.undoDiscoverFeedback(second)
        #expect(taste.discoverHidden[known] == .seenIt)
        await taste.drainTask?.value
        await graph.tearDown()
    }

    @Test("Device memory: answers survive a new store instance before any read; account changes clear the in-memory copy; deletion removes the device copy")
    func persistenceAndAccountScope() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        _ = fixture.accountSession.begin(userId: Self.userA)
        let first = fixture.store()
        let key = MediaKey(kind: .anime, id: 7)
        first.recordDiscoverFeedback(.seenIt, for: key)
        await first.drainTask?.value

        let relaunched = fixture.store()
        #expect(relaunched.discoverHidden.isEmpty)
        relaunched.restoreDiscoverMemory()
        #expect(relaunched.discoverHidden[key] == .seenIt, "shown hidden before the server read")
        // The server read does not reflect the answer yet: the device answer stays in effect.
        #expect(await relaunched.loadDiscoverHidden(force: true))
        #expect(relaunched.isHiddenOnDiscover(key))

        // Another account sees none of it.
        relaunched.cancelAccountWork()
        relaunched.clearPrivateState()
        #expect(relaunched.discoverHidden.isEmpty)
        _ = fixture.accountSession.begin(userId: Self.userB)
        relaunched.restoreDiscoverMemory()
        #expect(relaunched.discoverHidden.isEmpty)
        let otherReceipt = DiscoverFeedbackReceipt(key: key, feedback: .seenIt, priorAction: nil, accountUserId: Self.userA)
        #expect(!relaunched.undoDiscoverFeedback(otherReceipt), "an Undo of the previous account changes nothing")

        // Deleting account A removes its device copy.
        try await relaunched.removeDeletedAccountData(userId: Self.userA)
        #expect(TasteStore.readDiscoverMemory(defaults: fixture.defaults, userId: Self.userA) == nil)
    }

    @Test("Signed out: nothing is recorded or read")
    func signedOut() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let taste = fixture.store()
        #expect(taste.recordDiscoverFeedback(.notInterested, for: MediaKey(kind: .anime, id: 1)) == nil)
        #expect(!(await taste.loadDiscoverHidden()))
        #expect(fixture.server.requests.isEmpty)
    }

    @Test("A read finished after the account changed applies nothing")
    func staleReadDropped() async throws {
        let gate = StubGate()
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let rows = DiscoverUsabilityFixtures.deckSignalRowsJSON([(MediaKey(kind: .anime, id: 1), "deck_skip", Date())])
        fixture.server.respond { request in
            request.resource == "taste_signal_events" ? StubResponse.json(rows).held(by: gate) : .emptyArray
        }
        _ = fixture.accountSession.begin(userId: Self.userA)
        let taste = fixture.store()
        let read = Task { await taste.loadDiscoverHidden() }
        _ = await fixture.server.waitForRequest { $0.resource == "taste_signal_events" }
        _ = fixture.accountSession.begin(userId: Self.userB)
        taste.clearPrivateState()
        gate.open()
        #expect(!(await read.value))
        #expect(taste.discoverHidden.isEmpty)
    }
}

// MARK: - DiscoveryStore: franchise ids, See all, moods

@MainActor
@Suite("Discover usability data: readers with silent fallback (DiscoveryStore)", .serialized, .timeLimit(.minutes(1)))
struct DiscoverReadersTests {
    @Test("Franchise ids: one batched read per medium set, merged into the map; while undeployed nothing is asked again and the stem rule still dedupes")
    func franchiseIds() async throws {
        let calls = CallCounter()
        let rows = DiscoverUsabilityFixtures.franchiseRowsJSON(
            [MediaKey(kind: .anime, id: 1), MediaKey(kind: .anime, id: 2), MediaKey(kind: .manga, id: 1)],
            label: { $0.kind == .anime ? 1 : $0.id })
        let harness = try PublicDataHarness { request in
            guard request.resource == "rpc/media_franchise_ids_v1" else { return .emptyArray }
            _ = calls.next()
            return .json(rows)
        }
        let discovery = harness.service.discovery
        await discovery.loadFranchiseIds(for: [MediaKey(kind: .anime, id: 2), MediaKey(kind: .anime, id: 1), MediaKey(kind: .manga, id: 1)])
        #expect(discovery.franchiseIds[MediaKey(kind: .anime, id: 2)] == 1)
        #expect(discovery.franchiseIds[MediaKey(kind: .manga, id: 1)] == 1)
        let body = try #require(harness.requests(to: "rpc/media_franchise_ids_v1").first?.jsonObject)
        #expect(body["p_anime_ids"] as? [Int] == [1, 2])
        #expect(body["p_manga_ids"] as? [Int] == [1])
        // Known ids are not asked again.
        await discovery.loadFranchiseIds(for: [MediaKey(kind: .anime, id: 1)])
        #expect(harness.requests(to: "rpc/media_franchise_ids_v1").count == 1)
        #expect(discovery.franchiseKeys(for: MediaKey(kind: .anime, id: 2), title: "Attack on Titan Season 2")
                    == [.component(.anime, 1)], "a read component is the truth (no stem key)")
        await harness.tearDown()

        let undeployed = try PublicDataHarness { request in
            request.resource == "rpc/media_franchise_ids_v1" ? DUJSON.pgrst202 : .emptyArray
        }
        let store = undeployed.service.discovery
        await store.loadFranchiseIds(for: [MediaKey(kind: .anime, id: 1)])
        await store.loadFranchiseIds(for: [MediaKey(kind: .anime, id: 2)])
        #expect(undeployed.requests(to: "rpc/media_franchise_ids_v1").count == 1, "an undeployed reader is not asked again")
        #expect(store.franchiseIds.isEmpty)
        let first = store.franchiseKeys(for: MediaKey(kind: .anime, id: 1), title: "Attack on Titan")
        let sequel = store.franchiseKeys(for: MediaKey(kind: .anime, id: 2), title: "Attack on Titan Season 2")
        #expect(!first.isDisjoint(with: sequel), "the stem key matches without the server")
        #expect(!first.contains(.component(.anime, 1)), "no component key is invented while undeployed")
        await undeployed.tearDown()
    }

    @Test("See all (server): params on the wire, rank order, franchise id and list status decoded, next = offset after the last rank")
    func seeAllServer() async throws {
        let rows = DiscoverUsabilityFixtures.pageRowsJSON(kind: .anime, count: 3, firstRank: 25, listStatusAt: [1: "CURRENT"])
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_section_page_v1" ? .json(rows) : .emptyArray
        }
        let query = DiscoverSeeAllQuery(section: .trending, medium: .anime, sort: .newest, format: "tv", length: .short, status: .finished)
        let page = try #require(await harness.service.discovery.seeAllPage(query, cursor: .offset(24), limit: 3))
        #expect(page.origin == .server)
        #expect(page.items.map(\.key.id) == [991_000, 991_001, 991_002])
        #expect(page.items[1].serverListStatus == .current)
        #expect(page.items[0].franchiseId == 991_000)
        #expect(page.next == .offset(26), "one row of overlap (a third of a 3-row page)")
        let body = try #require(harness.requests(to: "rpc/discover_section_page_v1").first?.canonicalBody)
        #expect(body == #"{"p_format":"TV","p_length":"short","p_limit":3,"p_media_type":"ANIME","p_offset":24,"p_section":"trending","p_sort":"newest","p_status":"finished"}"#)

        // A short page ends the journey.
        let last = try #require(await harness.service.discovery.seeAllPage(query, limit: 10))
        #expect(last.next == nil)
        await harness.tearDown()
    }

    @Test("See all fallback while undeployed: trending pages through live Browse in its order with the filters; curated sections use the loaded rows; offline answers nil")
    func seeAllFallback() async throws {
        let browse = #"[{"id":10,"title_english":"Ten","format":"TV","status":"FINISHED","episode_count":12,"popularity":5,"trending":9,"average_score":80},{"id":11,"title_english":"Eleven","format":"TV","status":"FINISHED","episode_count":12,"popularity":4,"trending":8,"average_score":81}]"#
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/discover_section_page_v1": return DUJSON.pgrst202
            case "rpc/browse_anime_page": return .json(browse)
            default: return .emptyArray
            }
        }
        let discovery = harness.service.discovery
        let query = DiscoverSeeAllQuery(section: .trending, medium: .anime, length: .short, status: .finished)
        let page = try #require(await discovery.seeAllPage(query, limit: 2))
        #expect(page.origin == .fallback)
        #expect(page.items.map(\.key.id) == [10, 11])
        #expect(page.next == .browse(cursorInt: 8, cursorDate: nil, cursorId: 11))
        let body = try #require(harness.requests(to: "rpc/browse_anime_page").first?.jsonObject)
        #expect(body["p_sort"] as? String == "trending")
        #expect(body["p_min_episodes"] as? Int == 1)
        #expect(body["p_max_episodes"] as? Int == 13)
        #expect(body["p_status"] as? String == "FINISHED")
        #expect(body["p_limit"] as? Int == 2)

        // The browse cursor continues through Browse (the prepared reader is not asked again).
        _ = await discovery.seeAllPage(query, cursor: page.next, limit: 2)
        #expect(harness.requests(to: "rpc/discover_section_page_v1").count == 1)
        let second = try #require(harness.requests(to: "rpc/browse_anime_page").last?.jsonObject)
        #expect(second["p_cursor_int"] as? Int == 8)
        #expect(second["p_cursor_id"] as? Int == 11)

        let loaded: [DiscoverCardValue] = [.anime(anime(1, "A", popularity: 1)), .anime(anime(2, "B", popularity: 9))]
        let essentials = try #require(await discovery.seeAllPage(
            DiscoverSeeAllQuery(section: .essentials, medium: .anime, sort: .popular), loadedRows: loaded))
        #expect(essentials.origin == .local)
        #expect(essentials.items.map(\.key.id) == [2, 1])
        #expect(essentials.next == nil)
        await harness.tearDown()

        let offline = try PublicDataHarness { request in
            request.resource == "rpc/discover_section_page_v1" ? DUJSON.serverError : .emptyArray
        }
        #expect(await offline.service.discovery.seeAllPage(DiscoverSeeAllQuery(section: .trending, medium: .anime)) == nil)
        #expect(offline.requests(to: "rpc/browse_anime_page").isEmpty, "a transient failure is not a fallback")
        await offline.tearDown()
    }

    @Test("Moods: server page with its reason; while undeployed short browses finished 1-13 episodes, cozy browses its genre, like_last_loved without a seed is an empty page")
    func moods() async throws {
        let rows = DiscoverUsabilityFixtures.pageRowsJSON(kind: .manga, count: 2, reason: (id: 7, title: "Vagabond"))
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_mood_v1" ? .json(rows) : .emptyArray
        }
        let page = try #require(await harness.service.discovery.moodPage(.likeLastLoved, medium: .manga, limit: 2))
        #expect(page.reason == DiscoverReason(key: MediaKey(kind: .manga, id: 7), title: "Vagabond"))
        #expect(page.next == .offset(2))
        let body = try #require(harness.requests(to: "rpc/discover_mood_v1").first?.canonicalBody)
        #expect(body == #"{"p_limit":2,"p_media_type":"MANGA","p_mood":"like_last_loved","p_offset":0}"#)
        await harness.tearDown()

        let undeployed = try PublicDataHarness { request in
            request.resource == "rpc/discover_mood_v1" ? DUJSON.pgrst202 : .emptyArray
        }
        let discovery = undeployed.service.discovery
        let short = try #require(await discovery.moodPage(.short, medium: .anime))
        #expect(short.origin == .fallback)
        let shortBody = try #require(undeployed.requests(to: "rpc/browse_anime_page").last?.jsonObject)
        #expect(shortBody["p_status"] as? String == "FINISHED")
        #expect(shortBody["p_max_episodes"] as? Int == 13)
        #expect(shortBody["p_sort"] as? String == "popular")
        _ = await discovery.moodPage(.cozy, medium: .manga)
        let cozyBody = try #require(undeployed.requests(to: "rpc/browse_manga_page").last?.jsonObject)
        #expect(cozyBody["p_genre"] as? String == "Slice of Life")
        let loved = try #require(await discovery.moodPage(.likeLastLoved, medium: .anime))
        #expect(loved.items.isEmpty)
        #expect(loved.next == nil)
        #expect(undeployed.requests(to: "rpc/discover_mood_v1").count == 1, "the undeployed reader is remembered")
        await undeployed.tearDown()
    }
}
