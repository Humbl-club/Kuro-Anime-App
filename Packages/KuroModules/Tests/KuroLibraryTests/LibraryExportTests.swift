import Foundation
import KuroCore
import KuroLibrary
import Testing

@Suite("Library export: value types and RFC 4180 encoder")
struct LibraryExportTests {
    @Test func rfc4180FieldQuotesOnlyWhenNeeded() {
        #expect(RFC4180.field("plain") == "plain")
        #expect(RFC4180.field("a,b") == "\"a,b\"")
        #expect(RFC4180.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(RFC4180.field("line1\nline2") == "\"line1\nline2\"")
        #expect(RFC4180.field("cr\r") == "\"cr\r\"")
        #expect(RFC4180.row(["a", "b,c"]) == "a,\"b,c\"\r\n")
    }

    /// `"\r\n"` is ONE `Character` in Swift, so a `Character` search for `"\r"` or `"\n"` misses it, and a
    /// `"` followed by a combining mark is one grapheme that a text search for `"` can skip. Both must be
    /// handled by scalar, or a note would leave a field unquoted / a quote undoubled.
    @Test func rfc4180FieldHandlesGraphemeClustersAndEmptyValues() {
        #expect(RFC4180.field("a\r\nb") == "\"a\r\nb\"")
        #expect(RFC4180.field("\r\n") == "\"\r\n\"")
        #expect(RFC4180.field("q\"\u{0301}x") == "\"q\"\"\u{0301}x\"")
        #expect(RFC4180.field("") == "")
        #expect(RFC4180.field("日本語 ✓") == "日本語 ✓")
        #expect(RFC4180.field("\"") == "\"\"\"\"")
        #expect(RFC4180.row(["", "", ""]) == ",,\r\n")
        #expect(RFC4180.row(["x"]) == "x\r\n")
        #expect(RFC4180.row([]) == "\r\n")
    }

    @Test func summaryGapsFollowTheTwoIndependentCauses() {
        let line = ExportReportLine(key: MediaKey(kind: .anime, id: 7), title: "Anime #7")
        let complete = LibraryExportSummary(
            entryCount: 1, malExported: [.anime: 1], withoutMalId: [], identityUnavailable: [],
            notesAdjusted: [], datesOmitted: []
        )
        #expect(complete.gaps.isEmpty)
        #expect(complete.isComplete)

        let offline = LibraryExportSummary(
            entryCount: 1, malExported: [:], withoutMalId: [], identityUnavailable: [line],
            notesAdjusted: [], datesOmitted: [], organisationUnavailable: true
        )
        #expect(offline.gaps == [.identityUnavailable, .organisationUnavailable])
        #expect(!offline.isComplete)

        let identityOnly = LibraryExportSummary(
            entryCount: 1, malExported: [:], withoutMalId: [], identityUnavailable: [line],
            notesAdjusted: [], datesOmitted: []
        )
        #expect(identityOnly.gaps == [.identityUnavailable])

        // MAL-format limits are reports, not gaps: CSV and JSON still hold those entries completely.
        let limitsOnly = LibraryExportSummary(
            entryCount: 3, malExported: [.anime: 1], withoutMalId: [line], identityUnavailable: [],
            notesAdjusted: [line], datesOmitted: [line]
        )
        #expect(limitsOnly.isComplete)

        let defaults = complete
        #expect(defaults.organisationUnavailable == false)
        #expect(defaults.malParts.isEmpty)
        #expect(defaults.listItemsOutsideLibrary == 0)
    }

    @Test func exportInputDefaultsAndFormatRawValues() {
        let input = LibraryExportInput(entries: [], catalogue: [:])
        #expect(input.tagsByKey.isEmpty)
        #expect(input.customLists.isEmpty)
        #expect(input.organisationUnavailable == false)
        #expect(LibraryExportFormat.allCases.map(\.rawValue) == ["mal_xml", "csv", "json"])
        #expect(LibraryExportGap.allCases.map(\.rawValue) == ["identity_unavailable", "organisation_unavailable"])
        #expect(ExportCatalogueRow(title: nil, anilistId: nil, malId: 5).malId == 5)
    }
}
