import Foundation
import KuroCore
@testable import KuroLibrary
import Testing

/// Internals of the export that the public tests cannot reach: the CSV cell encoder, and the injectable JSON
/// serialiser that lets a test make a requested format fail. A requested format that cannot be produced is
/// reported in `summary.failedFormats`, never silently missing.
@Suite("Library export: CSV cell encoder and failed formats")
struct LibraryExportInternalsTests {
    private struct SerialiserFailure: Error {}

    @Test func csvFieldIsTheRfcEncoderPlusQuotesAroundSemicolonAndTab() {
        // Everything without a semicolon or TAB is exactly the RFC 4180 encoding.
        for value in ["plain", "a,b", "say \"hi\"", "l1\nl2", "cr\r", "", "'=x", "日本語"] {
            #expect(LibraryExport.csvField(value) == RFC4180.field(value))
        }
        #expect(LibraryExport.csvField("a;b") == "\"a;b\"")
        #expect(LibraryExport.csvField("\t") == "\"\t\"")
        #expect(LibraryExport.csvField(";") == "\";\"")
        // Already quoted by the RFC rule: the quote is doubled once, not wrapped twice.
        #expect(LibraryExport.csvField("a;\"b\"") == "\"a;\"\"b\"\"\"")
        #expect(LibraryExport.csvField("a;b,c") == "\"a;b,c\"")
        // The RFC encoder itself is unchanged: it does not know about semicolons.
        #expect(RFC4180.field("a;b") == "a;b")
    }

    @Test func jsonSerialisationFailureIsRecordedAndTheFileIsAbsent() {
        let input = LibraryExportTests.twoWithoutMalId()
        let bundle = LibraryExport.build(
            input, formats: [.csv, .json], exportedAt: LibraryExportTests.now, timeZone: LibraryExportTests.berlin,
            jsonSerialiser: { _ in throw SerialiserFailure() }
        )
        #expect(bundle.files.map(\.name) == ["kuro-list-2026-11-09.csv"])
        #expect(bundle.summary.failedFormats == [.json])
        // The data itself was complete: a failed format is not a gap.
        #expect(bundle.summary.gaps.isEmpty)
    }

    @Test func aFormatThatWasNotRequestedIsNeverReportedAsFailed() {
        let input = LibraryExportTests.twoWithoutMalId()
        let csvOnly = LibraryExport.build(
            input, formats: [.csv, .malXML], exportedAt: LibraryExportTests.now, timeZone: LibraryExportTests.berlin,
            jsonSerialiser: { _ in throw SerialiserFailure() }
        )
        #expect(csvOnly.summary.failedFormats.isEmpty)
        #expect(csvOnly.files.count == 3)
    }

    @Test func theProductionSerialiserProducesTheJsonFileAndNoFailure() {
        let input = LibraryExportTests.twoWithoutMalId()
        let bundle = LibraryExport.build(input, formats: [.json], exportedAt: LibraryExportTests.now, timeZone: LibraryExportTests.berlin)
        #expect(bundle.files.map(\.name) == ["kuro-list-2026-11-09.json"])
        #expect(bundle.summary.failedFormats.isEmpty)
        let injected = LibraryExport.build(
            input, formats: [.json], exportedAt: LibraryExportTests.now, timeZone: LibraryExportTests.berlin,
            jsonSerialiser: LibraryExport.serialiseJSON
        )
        #expect(injected.files == bundle.files)
    }
}
