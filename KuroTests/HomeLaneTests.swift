//
//  HomeLaneTests.swift
//  KuroTests
//
//  Lane 3 (overnight 2026-11-01): Home shelf partition (planned titles never take an in-progress
//  slot), Home copy, the series detail fallback (spec D15), unit row presentation, the detail
//  release seed (never a guessed date) and the series songs fallback.
//

import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

@MainActor
@Suite("Home lane: shelf, copy and series fallback")
struct HomeLaneTests {
    static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func card(_ id: Int, _ listType: String) throws -> HomeCard {
        try decode("""
        {"media_id":\(id),"list_type":"\(listType)","progress":0,"server_revision":1,
         "lifecycle_id":"11111111-1111-4111-8111-11111111111\(id % 10)","title":"T\(id)"}
        """)
    }

    @Test("Planned titles never take an in-progress slot; server order is kept")
    func partition() throws {
        let cards = try [Self.card(1, "PLANNING"), Self.card(2, "WATCHING"), Self.card(3, "PLANNING"), Self.card(4, "READING"), Self.card(5, "PAUSED")]
        let split = HomeShelfPolicy.partition(cards)
        #expect(split.inProgress.map(\.mediaId) == [2, 4])
        #expect(split.planned.map(\.mediaId) == [1, 3])
        #expect(split.paused.map(\.mediaId) == [5], "paused titles get their own labelled row")
        #expect(split.saved.isEmpty)
        #expect(HomeShelfPolicy.leadCard(cards)?.mediaId == 2, "a planned title never stands for the shelf")
        #expect(HomeShelfPolicy.leadCard(try [Self.card(1, "PLANNING")]) == nil)
        #expect(HomeShelfPolicy.isInProgress(listType: "current"))
        #expect(!HomeShelfPolicy.isInProgress(listType: "PLANNING"))
    }

    @Test("Library's raw progress messages get display text; Undo keys on the raw value")
    func homeCopy() {
        #expect(HomeCopy.librarySavedOnDevice == "Saved on this device")
        let shown = HomeCopy.display(HomeCopy.librarySavedOnDevice)
        #expect(shown == "Saved on this device." || shown == "Auf diesem Gerät gespeichert.")
        #expect(HomeCopy.display("Something else") == "Something else")
        #expect(HomeCopy.isOffline(URLError(.notConnectedToInternet)))
        #expect(!HomeCopy.isOffline(URLError(.badServerResponse)))
        #expect(!HomeCopy.isOffline(CancellationError()))
    }

    @Test("Home pages forward by itself when page 1 holds only planned titles but one is in progress")
    func pagesForInProgress() throws {
        // Page 1 after an import: twelve planned titles, newest first; the title in progress is on page 2.
        let firstPage = try (1...12).map { try Self.card($0, "PLANNING") }
        let split = HomeShelfPolicy.partition(firstPage)
        #expect(split.inProgress.isEmpty)
        #expect(HomeShelfPolicy.shouldPageForInProgress(partition: split, scene: .inProgress, nextCursor: "c2", pagesFetched: 0))
        #expect(HomeShelfPolicy.shouldPageForInProgress(partition: split, scene: .inProgress, nextCursor: "c3", pagesFetched: 2))
        #expect(!HomeShelfPolicy.shouldPageForInProgress(partition: split, scene: .inProgress, nextCursor: "c4",
                                                         pagesFetched: HomeShelfPolicy.maxInProgressPages), "bounded")
        #expect(!HomeShelfPolicy.shouldPageForInProgress(partition: split, scene: .inProgress, nextCursor: nil, pagesFetched: 0))
        #expect(!HomeShelfPolicy.shouldPageForInProgress(partition: split, scene: .inProgress, nextCursor: "", pagesFetched: 0))
        #expect(!HomeShelfPolicy.shouldPageForInProgress(partition: split, scene: .saved, nextCursor: "c2", pagesFetched: 0),
                "nothing in progress in the Library: no paging")

        // Page 2 arrives with the title in progress: paging stops.
        let secondPage = try [Self.card(13, "PLANNING"), Self.card(14, "WATCHING")]
        let merged = HomeShelfPolicy.partition(firstPage + secondPage)
        #expect(merged.inProgress.map(\.mediaId) == [14])
        #expect(!HomeShelfPolicy.shouldPageForInProgress(partition: merged, scene: .inProgress, nextCursor: "c3", pagesFetched: 1))
    }

    @Test("Library errors become EN/DE Home copy; internal wording never reaches the reader")
    func libraryErrorCopy() {
        let unsaved = HomeCopy.progressNotSaved
        #expect(HomeCopy.libraryError(.retryable(message: "Incomplete progress receipts")) == unsaved)
        #expect(HomeCopy.libraryError(.unavailable(message: "something new")) == unsaved)
        #expect(HomeCopy.libraryError(.invalidValue(field: "progress")) == unsaved)
        let inFlight = HomeCopy.libraryError(.retryable(message: "That save is already on its way."))
        #expect(inFlight == "That save is already on its way." || inFlight == "Diese Speicherung ist schon unterwegs.")
        let signedOut = HomeCopy.libraryError(.notAuthenticated)
        #expect(signedOut.hasPrefix("You're signed out") || signedOut.hasPrefix("Du bist abgemeldet"))
        #expect(!HomeCopy.chooseNextUnit(medium: "anime").contains("ihrer Seite"))
    }

    @Test("Calendar and glance never count or list what already aired")
    func calendarPastRows() throws {
        let now = Date(timeIntervalSince1970: 1_791_979_200) // Wed 14 Oct 2026, 12:00 UTC
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let copy = ReleaseCopy(now: now, german: true, locale: Locale(identifier: "de_DE"), timeZone: berlin)
        func row(_ id: Int, _ at: Date?, precision: ReleasePrecision? = nil, basis: ReleaseBasis = .confirmed) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: .anime, mediaId: id, title: "T\(id)", unitKind: .episode, unitNumber: 1,
                                releaseAt: at, basis: basis, source: "anilist", precision: precision)
        }
        let airedYesterday = row(1, now.addingTimeInterval(-20 * 3_600))
        let airedThisMorning = row(2, now.addingTimeInterval(-2 * 3_600))
        let tonight = row(3, now.addingTimeInterval(6 * 3_600))
        let todayByDay = row(4, Date(timeIntervalSince1970: 1_791_936_000), precision: .day, basis: .announced) // 14 Oct 00:00 UTC
        let yesterdayByDay = row(5, Date(timeIntervalSince1970: 1_791_849_600), precision: .day, basis: .announced) // 13 Oct
        let rows = [airedYesterday, airedThisMorning, tonight, todayByDay, yesterdayByDay]
        #expect(HomeCalendarPresentation.countThisWeek(rows, copy: copy) == 2, "tonight and today's dated release only")
        let groups = HomeCalendarPresentation.groups(rows, copy: copy)
        #expect(groups.flatMap(\.items).map(\.mediaId).sorted() == [3, 4])
        #expect(copy.daysFromToday(todayByDay) == 0)
        #expect(copy.daysFromToday(yesterdayByDay) == -1)
        #expect(copy.isAhead(row(6, nil)), "an undated row is still to come")
    }

    @Test("Coming up claims 'Nothing scheduled' only after an answer; unknown and failed say so (EN/DE)")
    func glanceCoverageCopy() throws {
        let now = Date(timeIntervalSince1970: 1_791_979_200) // Wed 14 Oct 2026, 12:00 UTC
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let en = ReleaseCopy(now: now, german: false, locale: Locale(identifier: "en_GB"), timeZone: berlin)
        let de = ReleaseCopy(now: now, german: true, locale: Locale(identifier: "de_DE"), timeZone: berlin)
        func caption(_ copy: ReleaseCopy, _ coverage: ReleaseScheduleCoverage, offline: Bool = false) -> String {
            HomeCalendarPresentation.glanceCaption(items: [], copy: copy, offline: offline, coverage: coverage)
        }
        #expect(caption(en, .complete) == "Nothing scheduled")
        #expect(caption(de, .complete) == "Nichts angekündigt")
        #expect(caption(en, .nextSevenDays) == "Nothing scheduled this week")
        #expect(caption(de, .nextSevenDays) == "Diese Woche ist nichts angekündigt")
        #expect(caption(en, .noSource) == "Dates to come")
        #expect(caption(de, .noSource) == "Termine folgen")
        #expect(caption(en, .failed) == "Couldn't load dates")
        #expect(caption(de, .failed) == "Termine konnten nicht geladen werden")
        #expect(caption(en, .pending) == "Checking dates")
        #expect(caption(de, .pending) == "Termine werden geprüft")
        #expect(caption(en, .complete, offline: true).hasPrefix("Offline"))
        #expect(HomeCalendarPresentation.offersRetry(items: [], copy: en, offline: false, coverage: .failed))
        #expect(!HomeCalendarPresentation.offersRetry(items: [], copy: en, offline: true, coverage: .failed))
        #expect(!HomeCalendarPresentation.offersRetry(items: [], copy: en, offline: false, coverage: .noSource))
        // An upcoming row outranks the coverage: something is known.
        let undated = ReleaseScheduleItem(medium: .manga, mediaId: 1, title: "M", unitKind: .chapter, unitNumber: 3,
                                          releaseAt: nil, basis: .announced, source: "mangaupdates")
        #expect(HomeCalendarPresentation.glanceCaption(items: [undated], copy: en, coverage: .failed) == "Dates still to come")
    }

    @Test("The original story names a source only when the bundle knows one")
    func boundaryCopy() {
        #expect(SeriesCopy.boundaryUnknown(sourceKind: "manga").contains("anga"))
        #expect(SeriesCopy.boundaryUnknown(sourceKind: "novel").contains("Roman") || SeriesCopy.boundaryUnknown(sourceKind: "novel").contains("novel"))
        let generic = SeriesCopy.boundaryUnknown(sourceKind: nil)
        #expect(!generic.contains("manga") && !generic.contains("Manga"))
    }

    @Test("A cancelled detail load is not a failure")
    func detailCancellation() {
        #expect(DetailLoadFailure.isCancellation(CancellationError()))
        #expect(DetailLoadFailure.isCancellation(URLError(.cancelled)))
        #expect(!DetailLoadFailure.isCancellation(URLError(.timedOut)))
        #expect(DetailLoadFailure(URLError(.notConnectedToInternet)) == .offline)
    }

    static func bundle(seriesId: String?, sections: String = "[]") throws -> SeriesDetailBundle {
        let series = seriesId.map { "\"\($0)\"" } ?? "null"
        return try decode("""
        {"medium":"anime","media_id":2,"series_id":\(series),
         "header":{"media_id":2,"title":"T"},"sections":\(sections),"units":[],"units_state":"ok",
         "copy":{},"themes":[{"role":"OP2","song_title":"Rise","artist":"A","match_state":"search"},
                              {"role":"ED","song_title":"  ","match_state":"search"},
                              {"role":"BGM","song_title":"Score","match_state":"search"}],
         "cast":[]}
        """)
    }

    @Test("D15: legacy sections when the bundle has no series data or cannot be read")
    func seriesFallback() throws {
        let bare = try Self.bundle(seriesId: nil)
        let grouped = try Self.bundle(seriesId: "22222222-2222-4222-8222-222222222222")
        let sectioned = try Self.bundle(seriesId: nil, sections: #"[{"id":"s1","kind":"season","ordinal":1,"name":"Season 1","sort_order":1}]"#)
        #expect(SeriesDetailFallback.usesLegacy(bundle: bare, loadFailed: false))
        #expect(!SeriesDetailFallback.usesLegacy(bundle: grouped, loadFailed: false))
        #expect(!SeriesDetailFallback.usesLegacy(bundle: sectioned, loadFailed: false))
        #expect(SeriesDetailFallback.usesLegacy(bundle: nil, loadFailed: true), "the series RPC is not deployed live")
        #expect(!SeriesDetailFallback.usesLegacy(bundle: nil, loadFailed: false), "still loading: undecided")

        // Decided once, on the first answer; never without a legacy body; previews start as series.
        #expect(SeriesDetailMode.initial(preview: nil, hasLegacy: true) == .resolving)
        #expect(SeriesDetailMode.initial(preview: nil, hasLegacy: false) == .series)
        #expect(SeriesDetailMode.initial(preview: grouped, hasLegacy: true) == .series)
        #expect(SeriesDetailMode.resolving.resolved(bundle: bare, loadFailed: false, hasLegacy: true) == .legacy)
        #expect(SeriesDetailMode.resolving.resolved(bundle: nil, loadFailed: true, hasLegacy: true) == .legacy)
        #expect(SeriesDetailMode.resolving.resolved(bundle: grouped, loadFailed: false, hasLegacy: true) == .series)
        #expect(SeriesDetailMode.resolving.resolved(bundle: bare, loadFailed: false, hasLegacy: false) == .series)
        #expect(SeriesDetailMode.series.resolved(bundle: nil, loadFailed: true, hasLegacy: true) == .series,
                "a later season switch that fails never flips the page")
    }

    @Test("Series songs fallback keeps only real, titled opening/ending/insert songs")
    func seriesSongs() throws {
        let songs = SeriesDetailFallback.songs(from: try Self.bundle(seriesId: nil).themes)
        #expect(songs.map(\.label) == ["OP2"])
        #expect(songs.first?.title == "Rise")
        #expect(SeriesDetailFallback.statusText("RELEASING", medium: .manga) != SeriesDetailFallback.statusText("RELEASING", medium: .anime))
        #expect(SeriesDetailFallback.statusText(nil, medium: .anime) == nil)
        #expect(SeriesDetailFallback.statusText("SOMETHING_NEW", medium: .anime) == nil)
    }

    @Test("Unit rows never repeat the unit word")
    func unitDisplay() throws {
        let labelled: SeriesDetailBundle.Unit = try Self.decode(
            #"{"id":"u1","label":"Episode 1","order_key":1,"available":true,"edition_key":""}"#)
        let english = SeriesUnitPresentation.display(labelled, isManga: false, german: false)
        #expect(english.numeral == "1" && english.title == "Episode 1")
        let numeric: SeriesDetailBundle.Unit = try Self.decode(
            #"{"id":"u2","label":"12","order_key":"12","available":true,"edition_key":""}"#)
        #expect(SeriesUnitPresentation.display(numeric, isManga: true, german: true).title == "Kapitel 12")
        let titled: SeriesDetailBundle.Unit = try Self.decode(
            #"{"id":"u3","label":"3","order_key":3,"available":true,"edition_key":"","title":"The Gate"}"#)
        #expect(SeriesUnitPresentation.display(titled, isManga: false, german: false).title == "The Gate")
        let special: SeriesDetailBundle.Unit = try Self.decode(
            #"{"id":"u4","label":"2 special","order_key":"2.5","available":true,"edition_key":""}"#)
        #expect(SeriesUnitPresentation.display(special, isManga: false, german: false).numeral == "2 special")
    }

    @Test("Detail release seed: only a future airing time becomes a confirmed AniList row")
    func detailSeed() throws {
        let now = Date(timeIntervalSince1970: 1_791_979_200)
        func anime(next: Int?, at: Date?) throws -> Anime {
            var object: [String: Any] = ["id": 7, "title_romaji": "Seven", "is_adult": false, "genres": [String](),
                                         "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"]
            if let next { object["next_episode_number"] = next }
            if let at { object["next_airing_at"] = ISO8601DateFormatter().string(from: at) }
            let data = try JSONSerialization.data(withJSONObject: object)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Anime.self, from: data)
        }
        let future = try anime(next: 8, at: now.addingTimeInterval(3_600))
        let seed = DetailNextReleaseSection.seed(for: future, now: now)
        #expect(seed.count == 1)
        #expect(seed.first?.unitNumber == 8 && seed.first?.basis == .confirmed && seed.first?.effectivePrecision == .instant)
        #expect(DetailNextReleaseSection.seed(for: try anime(next: 8, at: now.addingTimeInterval(-60)), now: now).isEmpty,
                "a past airing time is never turned into a next date")
        #expect(DetailNextReleaseSection.seed(for: try anime(next: 8, at: nil), now: now).isEmpty)
    }
}
