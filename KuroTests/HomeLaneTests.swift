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
        #expect(split.saved.map(\.mediaId) == [5])
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
