import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

/// W6: the batched, cached reviewed-membership read of `CatalogStore+SeriesMembership`.
@MainActor
@Suite struct SeriesMembershipReaderTests {
    nonisolated static func ids(_ request: RecordedRequest, column: String = "anime_id") -> [Int] {
        guard let value = request.query(column), value.hasPrefix("in.(") else { return [] }
        return value.dropFirst("in.(".count).dropLast().split(separator: ",").compactMap { Int($0) }
    }

    nonisolated static func span(
        _ id: Int, medium: String = "anime", series: String = "S", seriesMedium: String = "anime",
        continuity: String = "verified", grouping: String = "approved", sectionState: String = "approved",
        ordinal: Int? = 1, kind: String = "season"
    ) -> [String: Any] {
        [
            "anime_id": medium == "anime" ? id : NSNull(), "manga_id": medium == "manga" ? id : NSNull(),
            "medium": medium,
            "series": ["id": series, "medium": seriesMedium, "continuity": continuity, "grouping_state": grouping],
            "series_sections": [
                "kind": kind, "ordinal": ordinal ?? NSNull(), "name": "Season", "sort_order": ordinal ?? 1,
                "state": sectionState,
            ],
        ]
    }

    nonisolated static func respond(_ rows: @escaping @Sendable (RecordedRequest) -> [[String: Any]]) -> StubServer.Responder {
        { request in
            guard request.resource == "series_entry_spans" else { return .emptyArray }
            return ListRowJSON.response(rows(request))
        }
    }

    @Test func readsInBatchesOfThreeHundredPerMedium() async throws {
        let h = try PublicDataHarness(responder: Self.respond { _ in [] })
        let keys = (1...650).map { MediaKey(kind: .anime, id: $0) } + (1...10).map { MediaKey(kind: .manga, id: $0) }
        await h.service.catalog.loadSeriesMembership(for: keys)
        let reads = h.requests(to: "series_entry_spans")
        let anime = reads.filter { $0.query("medium") == "eq.anime" }
        #expect(anime.map { Self.ids($0).count } == [300, 300, 50])
        #expect(reads.filter { $0.query("medium") == "eq.manga" }.map { Self.ids($0, column: "manga_id").count } == [10])
        #expect(reads.allSatisfy { $0.method == "GET" })
        #expect(reads.allSatisfy {
            $0.query("series.continuity") == "eq.verified" && $0.query("series.grouping_state") == "eq.approved"
                && $0.query("series_sections.state") == "eq.approved"
        })
        #expect(reads.allSatisfy { ($0.query("select") ?? "").contains("!inner") })
        await h.tearDown()
    }

    @Test func keepsOnlyReviewedRowsAndCachesNegatives() async throws {
        let h = try PublicDataHarness(responder: Self.respond { _ in
            [Self.span(1, series: "A"), Self.span(2, series: "B", continuity: "disputed")]
        })
        let catalog = h.service.catalog
        let keys = [MediaKey(kind: .anime, id: 1), MediaKey(kind: .anime, id: 2), MediaKey(kind: .anime, id: 3)]
        await catalog.loadSeriesMembership(for: keys)
        #expect(catalog.seriesMembershipMap.count == 1)
        #expect(catalog.seriesMembership(for: keys[0])?.seriesId == "A")
        #expect(catalog.seriesMembership(for: keys[0])?.ordinal == 1)
        let before = h.requests(to: "series_entry_spans").count
        await catalog.loadSeriesMembership(for: keys)
        #expect(h.requests(to: "series_entry_spans").count == before)
        for key in keys { catalog.seriesMembershipCheckedAt[key] = Date().addingTimeInterval(-86_401) }
        await catalog.loadSeriesMembership(for: keys)
        #expect(h.requests(to: "series_entry_spans").count == before + 1)
        await h.tearDown()
    }

    @Test func crossMediumSpanIsDroppedOnTheClient() async throws {
        let h = try PublicDataHarness(responder: Self.respond { _ in
            [Self.span(5, medium: "manga", series: "X", seriesMedium: "anime")]
        })
        await h.service.catalog.loadSeriesMembership(for: [MediaKey(kind: .manga, id: 5)])
        #expect(h.service.catalog.seriesMembershipMap.isEmpty)
        await h.tearDown()
    }

    @Test func serverRowsOutsideTheReviewedDefinitionAreIgnoredEvenIfReturned() async throws {
        let h = try PublicDataHarness(responder: Self.respond { _ in
            [Self.span(1, continuity: "singleton"), Self.span(2, sectionState: "superseded"),
             Self.span(3, grouping: "proposed"), Self.span(4, series: "OK")]
        })
        await h.service.catalog.loadSeriesMembership(for: (1...4).map { MediaKey(kind: .anime, id: $0) })
        #expect(h.service.catalog.seriesMembershipMap.keys.map(\.id) == [4])
        await h.tearDown()
    }

    @Test func failureIsSilentAndKeepsKnownMembership() async throws {
        let calls = CallCounter()
        let h = try PublicDataHarness(responder: { request in
            guard request.resource == "series_entry_spans" else { return .emptyArray }
            if calls.next() == 1 { return ListRowJSON.response([Self.span(1, series: "A")]) }
            return .json(#"{"code":"500","message":"boom","details":null,"hint":null}"#, status: 500)
        })
        let catalog = h.service.catalog
        let key = MediaKey(kind: .anime, id: 1)
        await catalog.loadSeriesMembership(for: [key])
        let version = catalog.seriesMembershipVersion
        let map = catalog.seriesMembershipMap
        catalog.seriesMembershipCheckedAt[key] = Date().addingTimeInterval(-86_401)
        await catalog.loadSeriesMembership(for: [key])
        #expect(catalog.seriesMembershipMap == map)
        #expect(catalog.seriesMembershipVersion == version)
        #expect(catalog.seriesMembershipCheckedAt[key].map { Date().timeIntervalSince($0) > 86_400 } == true,
                "a failed read records no fresh check")
        await h.tearDown()
    }

    @Test func cancelledReadRecordsNoNegativeCache() async throws {
        let gate = StubGate()
        let h = try PublicDataHarness(responder: { request in
            guard request.resource == "series_entry_spans" else { return .emptyArray }
            return ListRowJSON.response([Self.span(1, series: "A")]).held(by: gate)
        })
        let catalog = h.service.catalog
        let keys = [MediaKey(kind: .anime, id: 1), MediaKey(kind: .anime, id: 2)]
        let task = Task { await catalog.loadSeriesMembership(for: keys) }
        _ = await h.server.waitForRequest { $0.resource == "series_entry_spans" }
        task.cancel()
        gate.open()
        await task.value
        #expect(catalog.seriesMembershipCheckedAt.isEmpty)
        #expect(catalog.seriesMembershipMap.isEmpty)
        let before = h.requests(to: "series_entry_spans").count
        await catalog.loadSeriesMembership(for: keys)
        #expect(h.requests(to: "series_entry_spans").count == before + 1, "the next read sends exactly one request")
        await h.tearDown()
    }
}
