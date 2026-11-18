//
//  AdultNoticeTests.swift
//  KuroTests
//
//  W4: say plainly that 18+ titles are not listed. Search reads the hidden-adult count from
//  `search_*_page_v2` page 1 behind `search_adult_notice_v1` (requests asserted on the stub server).
//

import Testing
import Foundation
import KuroCore
@testable import Kuro

@MainActor
@Suite struct AdultNoticeTests {

    /// A v2 page: `ids` as v1 card rows plus the hidden count.
    private nonisolated static func v2(_ ids: [Int], hidden: Int?) -> StubResponse {
        let rows = ids.map { id in
            #"{"id":\#(id),"title_english":"Title \#(id)","format":"TV","popularity":\#(PublicRowJSON.popularity(id)),"rank":\#(PublicRowJSON.rank(id))}"#
        }
        let count = hidden.map(String.init) ?? "null"
        return .json(#"{"items":[\#(rows.joined(separator: ","))],"hidden_adult":\#(count)}"#)
    }

    @Test func searchShowsNoticeOnlyWhenAdultTitlesWereHidden() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/search_anime_page_v2" ? Self.v2([], hidden: 1) : .json("{}", status: 500)
        }
        let search = harness.service.search
        search.adultNoticeEnabled = { true }
        search.resetSearch(query: "velvet hush", isManga: false)
        await search.fetchNextSearchPage()
        #expect(search.hiddenAdultCount == 1 && search.searchAnimeItems.isEmpty)
        #expect(SearchAdultNotice.line(hiddenAdult: search.hiddenAdultCount, german: false) == "Kuro doesn't list 18+ titles.")
        #expect(SearchAdultNotice.line(hiddenAdult: 1, german: true) == "Kuro listet keine Titel ab 18.")

        harness.server.respond(with: { _ in Self.v2([], hidden: 0) })
        search.resetSearch(query: "quiet harbor", isManga: false)
        await search.fetchNextSearchPage()
        #expect(search.hiddenAdultCount == 0)
        #expect(SearchAdultNotice.line(hiddenAdult: 0, german: false) == nil)
        await harness.tearDown()
    }

    @Test func searchFallsBackToV1WhenV2NotDeployed() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/search_anime_page_v2":
                return ClubJSON.error(message: "Could not find the function", code: "PGRST202", status: 404)
            case "rpc/search_anime_page": return PublicRowJSON.cards([7])
            default: return .emptyArray
            }
        }
        let search = harness.service.search
        search.adultNoticeEnabled = { true }
        search.resetSearch(query: "naruto", isManga: false)
        await search.fetchNextSearchPage()
        #expect(search.searchAnimeItems.map(\.id) == [7])
        #expect(search.hiddenAdultCount == 0)
        #expect(search.errorMessage == nil)
        #expect(harness.requests(to: "rpc/search_anime_page_v2").count == 1)

        // The next query inside the retry interval does not ask v2 again.
        search.resetSearch(query: "bleach", isManga: false)
        await search.fetchNextSearchPage()
        #expect(search.searchAnimeItems.map(\.id) == [7])
        #expect(harness.requests(to: "rpc/search_anime_page_v2").count == 1)
        #expect(harness.requests(to: "rpc/search_anime_page").count == 2)
        await harness.tearDown()
    }

    @Test func combinedScopeSumsBothCountsAndPageTwoSendsNoCount() async throws {
        let fullPage = Array(1...20)
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/search_anime_page_v2": return Self.v2(fullPage, hidden: 1)
            case "rpc/search_manga_page_v2": return Self.v2([], hidden: 2)
            case "rpc/search_anime_page": return PublicRowJSON.cards([21, 22])
            default: return .emptyArray
            }
        }
        let search = harness.service.search
        search.adultNoticeEnabled = { true }
        search.resetCombinedSearch(query: "velvet")
        await search.fetchNextSearchPage()
        #expect(search.hiddenAdultCount == 3)
        #expect(search.searchAnimeItems.count == 20)

        await search.fetchNextSearchPage()
        #expect(search.searchAnimeItems.count == 22)
        #expect(search.hiddenAdultCount == 3, "page 2 never changes the count")
        #expect(harness.requests(to: "rpc/search_anime_page_v2").count == 1)
        #expect(harness.requests(to: "rpc/search_manga_page_v2").count == 1)
        let page2 = harness.requests(to: "rpc/search_anime_page")
        #expect(page2.count == 1)
        #expect(page2.first?.jsonObject?["p_cursor_id"] as? Int == 20)
        await harness.tearDown()
    }

    @Test func flagOffSendsNoRequest() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/search_anime_page" ? PublicRowJSON.cards([3]) : .emptyArray
        }
        let search = harness.service.search
        search.adultNoticeEnabled = { false }
        search.resetSearch(query: "velvet hush", isManga: false)
        await search.fetchNextSearchPage()
        #expect(harness.requests(to: "rpc/search_anime_page_v2").isEmpty)
        #expect(harness.requests(to: "rpc/search_manga_page_v2").isEmpty)
        #expect(harness.requests(to: "rpc/search_anime_page").count == 1)
        #expect(search.searchAnimeItems.map(\.id) == [3])
        #expect(search.hiddenAdultCount == 0)
        await harness.tearDown()
    }
}
