import Foundation
import KuroLibrary
import Testing

@Suite("PartialDate: stored forms, validation, precision")
struct PartialDateTests {
    @Test func rejectsImpossibleDatesAndKeepsPrecision() {
        #expect(PartialDate(raw: "2024-02-30") == nil)
        #expect(PartialDate(raw: "2023-02-29") == nil)
        #expect(PartialDate(raw: "2024-02-29")?.precision == .day)
        #expect(PartialDate(raw: "2024")?.precision == .year)
        #expect(PartialDate(raw: "2024")?.raw == "2024")
        #expect(PartialDate(raw: "2024-02")?.precision == .month)
        #expect(PartialDate(raw: "2024-02")?.raw == "2024-02")
        #expect(PartialDate(raw: "2024-13") == nil)
        #expect(PartialDate(raw: "0000-00-00") == nil)
        #expect(PartialDate(raw: "2024-00-15") == nil)
        #expect(PartialDate(raw: "24-02-01") == nil)
        #expect(PartialDate(raw: "2024/02/01") == nil)
    }

    @Test func acceptsEveryStoredImportForm() {
        let yearOnly = PartialDate(raw: "2024-00-00")
        #expect(yearOnly?.precision == .year)
        #expect(yearOnly?.raw == "2024")
        let monthOnly = PartialDate(raw: "2024-05-00")
        #expect(monthOnly?.precision == .month)
        #expect(monthOnly?.raw == "2024-05")
        #expect(PartialDate(raw: " 2024-05-07 ")?.precision == .day)
        #expect(PartialDate(raw: "2024-05")?.zeroPadded == "2024-05-00")
    }

    @Test func equalityIsByValueNotSpelling() {
        #expect(PartialDate(raw: "2024-00-00") == PartialDate(raw: "2024"))
        #expect(PartialDate(raw: "2024-05-00") == PartialDate(raw: "2024-05"))
    }

    @Test func codableRoundTripsRawAndRejectsGarbage() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let value = try #require(PartialDate(raw: "2024-05"))
        let data = try encoder.encode(["d": value])
        #expect(String(decoding: data, as: UTF8.self) == #"{"d":"2024-05"}"#)
        let back = try JSONDecoder().decode([String: PartialDate].self, from: data)
        #expect(back["d"] == value)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode([String: PartialDate].self, from: Data(#"{"d":"2024-02-30"}"#.utf8))
        }
    }

    @Test func dayOfDateUsesTheGivenCalendar() throws {
        // 2026-03-01T23:30:00Z is already 2026-03-02 in Europe/Berlin (UTC+1 in early March).
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-03-01T23:30:00Z"))
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(PartialDate.day(of: instant, in: berlin).raw == "2026-03-02")
        #expect(PartialDate.day(of: instant, in: utc).raw == "2026-03-01")
    }
}
