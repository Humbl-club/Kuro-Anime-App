//
//  LibraryExportFlowTests.swift
//  KuroTests
//
//  W2 (list export), app side: the batched catalogue identity read on `CatalogStore`. The HTTP tests
//  run the real supabase-swift client against StubPostgREST (in-process, no network). The owner and
//  flow tests of `LibraryExportService` join this suite with Task 5.
//

import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

@MainActor
@Suite("Library export: catalogue identity read", .timeLimit(.minutes(1)))
struct LibraryExportFlowTests {
    // MARK: - Helpers

    /// The ids of an `id=in.(1,2,3)` filter.
    nonisolated static func inList(_ request: RecordedRequest) -> [Int] {
        guard let value = request.query("id"), value.hasPrefix("in.(") else { return [] }
        return value.dropFirst("in.(".count).dropLast().split(separator: ",").compactMap { Int($0) }
    }

    nonisolated static func inListCount(_ request: RecordedRequest) -> Int {
        inList(request).count
    }

    /// One catalogue row as PostgREST returns it.
    nonisolated static func identityRow(
        id: Int, malId: Int?, anilistId: Int?, english: String? = nil, romaji: String? = nil, native: String? = nil
    ) -> [String: Any] {
        [
            "id": id, "mal_id": malId as Any? ?? NSNull(), "anilist_id": anilistId as Any? ?? NSNull(),
            "title_english": english as Any? ?? NSNull(), "title_romaji": romaji as Any? ?? NSNull(),
            "title_native": native as Any? ?? NSNull(),
        ]
    }

    /// Answers every `id=in.(…)` read with one row per requested id: `mal_id = id + 10_000`.
    nonisolated static func identityRows(for request: RecordedRequest) -> StubResponse {
        guard request.resource == "anime" || request.resource == "manga" else { return .emptyArray }
        let rows = inList(request).map {
            identityRow(id: $0, malId: $0 + 10_000, anilistId: $0 + 20_000, english: "Title \($0)")
        }
        return ListRowJSON.response(rows)
    }

    // MARK: - Tests

    @Test("The lookup sends at most 500 ids per GET, per medium, and never filters adult titles")
    func identityLookupBatchesAtMostFiveHundredIds() async throws {
        let harness = try PublicDataHarness { request in Self.identityRows(for: request) }
        let keys = Set((1...1_200).map { MediaKey(kind: .anime, id: $0) } + (1...300).map { MediaKey(kind: .manga, id: $0) })
        let rows = await harness.service.catalog.exportIdentities(for: keys)
        let requests = harness.server.requests.filter { $0.resource == "anime" || $0.resource == "manga" }
        #expect(requests.count == 4)   // 500 + 500 + 200 anime, 300 manga
        #expect(requests.allSatisfy { Self.inListCount($0) <= 500 && $0.method == "GET" })
        #expect(requests.allSatisfy { $0.query("is_adult") == nil })
        #expect(requests.allSatisfy { $0.query("select") == "id,anilist_id,mal_id,title_english,title_romaji,title_native" })
        #expect(requests.filter { $0.resource == "anime" }.map(Self.inListCount) == [500, 500, 200])
        #expect(requests.filter { $0.resource == "manga" }.map(Self.inListCount) == [300])
        #expect(rows.count == 1_500)
        #expect(rows[MediaKey(kind: .anime, id: 7)]?.malId == 10_007)
        #expect(rows[MediaKey(kind: .anime, id: 7)]?.anilistId == 20_007)
        #expect(rows[MediaKey(kind: .anime, id: 7)]?.title == "Title 7")
        #expect(rows[MediaKey(kind: .manga, id: 7)]?.malId == 10_007, "manga 7 is its own title, not anime 7")
        await harness.tearDown()
    }

    @Test("A cancelled caller sends no further batch")
    func identityLookupStopsBetweenBatchesWhenCancelled() async throws {
        let gate = StubGate()
        let harness = try PublicDataHarness { request in
            Self.identityRows(for: request).held(by: gate)
        }
        let catalog = harness.service.catalog
        let keys = Set((1...1_500).map { MediaKey(kind: .anime, id: $0) })
        let lookup = Task { await catalog.exportIdentities(for: keys) }
        _ = await harness.server.waitForRequest { $0.resource == "anime" }
        lookup.cancel()
        gate.open()
        let rows = await lookup.value
        let animeRequests = harness.server.requests.filter { $0.resource == "anime" }
        #expect(animeRequests.count == 1, "the first batch was in flight; the second must never be sent")
        #expect(rows.count <= Self.inListCount(animeRequests[0]), "at most the first batch's rows")
        await harness.tearDown()
    }

    @Test("A failed batch leaves only its own keys absent; titles fall back English, romaji, native; blanks are nil")
    func identityLookupSkipsFailedBatchesAndPicksTitles() async throws {
        let harness = try PublicDataHarness { request in
            guard request.resource == "anime" else { return .emptyArray }
            // A 400 (not a transport failure: the SDK retries those) for the batch that starts at id 1.
            if Self.inList(request).first == 1 {
                return .json(#"{"code":"PGRST100","message":"rejected","details":null,"hint":null}"#, status: 400)
            }
            return ListRowJSON.response([
                Self.identityRow(id: 501, malId: nil, anilistId: 9, english: "  ", romaji: " Romaji Name ", native: "Native"),
                Self.identityRow(id: 502, malId: 5, anilistId: nil, native: "  Native Only "),
                Self.identityRow(id: 503, malId: 6, anilistId: 7, english: "", romaji: " "),
            ])
        }
        let keys = Set((1...600).map { MediaKey(kind: .anime, id: $0) })
        let rows = await harness.service.catalog.exportIdentities(for: keys)
        #expect(harness.server.requests.filter { $0.resource == "anime" }.count == 2, "the failed first batch does not stop the second")
        #expect(rows.count == 3, "the 500 keys of the failed batch are absent")
        #expect(rows[MediaKey(kind: .anime, id: 100)] == nil)
        #expect(rows[MediaKey(kind: .anime, id: 501)] == ExportCatalogueRow(title: "Romaji Name", anilistId: 9, malId: nil))
        #expect(rows[MediaKey(kind: .anime, id: 502)] == ExportCatalogueRow(title: "Native Only", anilistId: nil, malId: 5))
        #expect(rows[MediaKey(kind: .anime, id: 503)] == ExportCatalogueRow(title: nil, anilistId: 7, malId: 6))
        await harness.tearDown()
    }

    @Test("An empty key set sends no request")
    func identityLookupOfNothingSendsNothing() async throws {
        let harness = try PublicDataHarness { request in Self.identityRows(for: request) }
        let rows = await harness.service.catalog.exportIdentities(for: [])
        #expect(rows.isEmpty)
        #expect(harness.server.requests.isEmpty)
        await harness.tearDown()
    }
}
