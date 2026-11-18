//
//  AdultNoticeTests.swift
//  KuroTests
//
//  W4: say plainly that 18+ titles are not listed. Search reads the hidden-adult count from
//  `search_*_page_v2` page 1 behind `search_adult_notice_v1` (requests asserted on the stub server).
//

import Testing
import Foundation
import SwiftUI
import UIKit
import KuroCore
import KuroLibrary
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

    @Test func footnoteHasHeightOnlyWhenTitlesWereHidden() {
        func fitted<V: View>(_ view: V) -> CGSize {
            let host = UIHostingController(rootView: view
                .environment(\.locale, Locale(identifier: "de_DE"))
                .dynamicTypeSize(.accessibility3))
            return host.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude))
        }
        let shown = fitted(SearchAdultFootnote(hiddenAdult: 1))
        #expect(shown.height > 0 && shown.width <= 375)
        #expect(fitted(SearchAdultFootnote(hiddenAdult: 0)).height == 0)
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

    // MARK: Import review

    private static let adultDetail = "ADULT_NOT_LISTED: 18+ title, not listed in Kuro"

    private static func itemJSON(_ id: String, disposition: String, detail: String?, mediaId: Int? = nil, title: String = "Title") -> String {
        let detailJSON = detail.map { "\"\($0)\"" } ?? "null"
        let media = mediaId.map(String.init) ?? "null"
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"medium":"anime","external_id":"\#(id)","media_id":\#(media),"title":"\#(escapedTitle)","incoming":{"unavailable_fields":[]},"current":null,"expected_revision":null,"expected_lifecycle":null,"disposition":"\#(disposition)","detail":\#(detailJSON),"changed_fields":[],"undo_disposition":null}"#
    }

    private static func items(adult: [String], plainUnmatched: [String], new: [String]) throws -> [ImportReviewItem] {
        let rows = adult.map { itemJSON($0, disposition: "unmatched", detail: adultDetail) }
            + plainUnmatched.map { itemJSON($0, disposition: "unmatched", detail: "Catalogue identity requires review", title: "Odd, \"title\"") }
            + new.map { itemJSON($0, disposition: "new", detail: nil, mediaId: Int($0)) }
        return try JSONDecoder().decode([ImportReviewItem].self, from: Data(("[" + rows.joined(separator: ",") + "]").utf8))
    }

    /// Minimal RFC 4180 reader for the assertions (BOM stripped; quoted fields; CRLF records).
    private static func csvRows(_ data: Data) throws -> [[String]] {
        var text = try #require(String(data: data, encoding: .utf8))
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text.unicodeScalars)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" { if chars.first == "\"" { field.unicodeScalars.append(c); chars.removeFirst() } else { quoted = false } }
                else { field.unicodeScalars.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\r" { continue }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else { field.unicodeScalars.append(c) }
        }
        return rows
    }

    @Test func importReviewLabelsAdultMatchesAndKeepsThemInUnresolvedFile() throws {
        let counts = try JSONDecoder().decode(ImportCounts.self, from: Data(#"{"added":2,"unmatched":4,"adult_not_listed":3}"#.utf8))
        #expect(counts.adultNotListed == 3 && counts.needsReview == 1)
        let items = try Self.items(adult: ["111", "112", "113"], plainUnmatched: ["999"], new: ["201", "202"])
        #expect(items.filter(\.isAdultNotListed).count == 3)
        #expect(ImportCopy.adultCountLine(3, german: false) == "18+ — not listed in Kuro: 3")
        #expect(ImportCopy.adultCountLine(3, german: true) == "18+ — nicht in Kuro gelistet: 3")
        #expect(ImportCopy.adultCountLine(0, german: false) == nil)
        #expect(ImportCopy.adultRowLabel(german: false) == "18+ — not listed in Kuro")
        #expect(ImportCopy.adultRowLabel(german: true) == "18+ — nicht in Kuro gelistet")
        #expect(ImportCopy.unresolvedFileAction(german: false) == "Save the unresolved titles")
        #expect(ImportCopy.unresolvedFileAction(german: true) == "Offene Titel als Datei sichern")
        let rows = try Self.csvRows(ImportUnresolvedFile(items: items, fileName: "x.csv").csv())
        #expect(rows[0] == ImportUnresolvedFile.header)
        #expect(rows.dropFirst().filter { $0[3] == "adult_not_listed" }.map { $0[1] } == ["111", "112", "113"])
        #expect(rows.dropFirst().contains { $0[1] == "999" && $0[2] == "Odd, \"title\"" && $0[3] == "not_in_catalogue" })
        #expect(!rows.dropFirst().contains { ["201", "202"].contains($0[1]) })
        #expect(ImportWorkflowPresentation.unresolvedRetryIds(items) == ["anime|999"])
        var allAdult = ImportCounts(); allAdult.unmatched = 3; allAdult.adultNotListed = 3
        #expect(allAdult.needsReview == 0)
        let outcome = try JSONDecoder().decode(ImportOutcome.self, from: Data(#"""
            {"job_id":"j1","selection":{"provider":"anilist","source_kind":"account","source_identity":"x","media":["anime"],"statuses":[]},
             "phase":"ready","counts":{"unmatched":3,"adult_not_listed":3},"exhausted_media":{"anime":true},"home_revisions":{},
             "projection_ready":false,"undo_available":false,"undo_action_id":null,"history_available":true}
            """#.utf8))
        #expect(outcome.allRejected, "an import whose titles are all 18+ says nothing was applied")
        #expect(ImportUnresolvedFile.fileName(on: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
                == "kuro-import-unresolved-1970-01-01.csv")
    }

    @Test func oldImportPayloadStillDecodes() throws {
        let page = #"{"items":[\#(Self.itemJSON("5", disposition: "unmatched", detail: Self.adultDetail))],"next_cursor":null}"#
        let decoded = try JSONDecoder().decode(ImportItemsPage.self, from: Data(page.utf8))
        #expect(decoded.items.first?.disposition == .unmatched)
        #expect(decoded.items.first?.detail?.hasPrefix("ADULT_NOT_LISTED:") == true)
        let old = try JSONDecoder().decode(ImportCounts.self, from: Data(#"{"added":1,"conflict":1,"unmatched":2,"invalid":1}"#.utf8))
        #expect(old.adultNotListed == 0 && old.needsReview == 4)
        let plain = try Self.items(adult: [], plainUnmatched: ["7"], new: [])
        #expect(plain.first?.isAdultNotListed == false)
    }

    /// A manual match onto an 18+ row is refused by the server (ADULT_NOT_LISTED); the client must neither
    /// offer nor send one for a row already marked that way.
    @Test func manualMatchIsNotSentForAdultNotListedRows() async throws {
        let harness = try PublicDataHarness()
        await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "adult-match@example.com")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("adult-match-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hook = LibraryRefreshHook()
        hook.connect(to: harness.service.libraryActions)
        let imports = ImportsService(client: StubSupabase.makeClient(server: harness.server),
            accountSession: harness.service.accountSession, library: harness.service.library,
            catalog: harness.service.catalog, libraryHook: hook, importJournal: try LibraryImportPageJournal(directory: directory),
            malCredentials: InMemoryMALCredentialStore())
        let adult = try #require(try Self.items(adult: ["111"], plainUnmatched: [], new: []).first)
        do {
            _ = try await imports.matchImportItem(jobId: "job-adult", item: adult, mediaId: 5)
            Issue.record("a match for an ADULT_NOT_LISTED row must be refused")
        } catch let failure as ImportFailure {
            #expect(failure == .invalidInput("18+ titles are not listed in Kuro."))
        }
        #expect(harness.requests(to: "rpc/prepare_import_chunk_v2").isEmpty)

        let outcome = try JSONDecoder().decode(ImportOutcome.self, from: Data(#"""
            {"job_id":"job-adult","selection":{"provider":"anilist","source_kind":"account","source_identity":"x","media":["anime"],"statuses":[]},
             "phase":"reviewing","counts":{"unmatched":1,"adult_not_listed":1},"exhausted_media":{"anime":true},"home_revisions":{},
             "projection_ready":false,"undo_available":false,"undo_action_id":null,"history_available":true}
            """#.utf8))
        let screen = ImportWorkflowPresentation(imports: imports, job: outcome)
        screen.activate()
        await screen.match(adult, mediaId: 5)
        #expect(screen.failure == nil, "the presentation does not even attempt the match")
        #expect(harness.requests(to: "rpc/prepare_import_chunk_v2").isEmpty)
        screen.close()
        await harness.tearDown()
    }
}
