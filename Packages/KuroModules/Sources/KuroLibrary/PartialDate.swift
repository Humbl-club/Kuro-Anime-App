import Foundation

/// A calendar date that may be known only to the year or to the month: the value behind a list entry's
/// started / finished dates (`started_raw`, `finished_raw`).
///
/// The stored column is free text and several writers spell the same date differently: MAL XML imports store
/// `2024-00-00` and `2024-05-00`, AniList's fuzzy date arrives as `2024` or `2024-05`, and the app writes
/// `2024`, `2024-05` or `2024-05-07`. `PartialDate(raw:)` accepts every one of those spellings and the value
/// is the parsed (year, month, day), so two spellings of one date are equal and an untouched editor save never
/// rewrites an imported value.
///
/// Parsing is by UTF-8 bytes (ASCII digits and `-` only), the same style as `MALExportParser`; there is no
/// `DateFormatter`, so nothing here depends on a locale or a time zone.
public struct PartialDate: Equatable, Hashable, Sendable, Codable, Comparable {
    /// How much of the date is known.
    public enum Precision: Sendable, Equatable {
        /// Only the year is known.
        case year
        /// The year and the month are known.
        case month
        /// The year, month and day are known.
        case day
    }

    /// The year, 1...9999.
    public let year: Int
    /// The month, 1...12; `nil` when only the year is known.
    public let month: Int?
    /// The day of the month; `nil` when the day is not known (`.year` and `.month` precision).
    /// A day always comes with a month.
    public let day: Int?

    /// Parses a stored raw date. Whitespace around the value is trimmed.
    ///
    /// Accepted forms: `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, and the zero-padded MAL spellings `YYYY-00-00`
    /// (year precision) and `YYYY-MM-00` (month precision).
    ///
    /// Returns `nil` for anything else: an empty string, `0000-00-00`, a year outside 1...9999, a month
    /// outside 1...12 (`YYYY-00` is not a stored form), a day that does not exist in its month (Gregorian leap
    /// rule), a day without a month (`YYYY-00-DD`), another separator, or any extra character.
    public init?(raw: String) {
        let bytes = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard bytes.count >= 4, let year = Self.number(bytes[0..<4]) else { return nil }
        switch bytes.count {
        case 4:
            self.init(year: year)
        case 7:
            guard bytes[4] == Self.hyphen, let month = Self.number(bytes[5..<7]) else { return nil }
            self.init(year: year, month: month)
        case 10:
            guard bytes[4] == Self.hyphen, bytes[7] == Self.hyphen,
                  let month = Self.number(bytes[5..<7]), let day = Self.number(bytes[8..<10]) else { return nil }
            if month == 0 {
                // `YYYY-00-00` is the year-only spelling; a day without a month is not a date.
                guard day == 0 else { return nil }
                self.init(year: year)
            } else if day == 0 {
                // `YYYY-MM-00` is the month-only spelling.
                self.init(year: year, month: month)
            } else {
                self.init(year: year, month: month, day: day)
            }
        default:
            return nil
        }
    }

    /// Builds a date from numeric parts, with the same rules as `init?(raw:)`: the year is 1...9999, a month
    /// is 1...12, a day must exist in its month, and a day requires a month. Pass `nil` (never `0`) for a part
    /// that is not known; a `0` is rejected. Returns `nil` when a rule is broken.
    public init?(year: Int, month: Int? = nil, day: Int? = nil) {
        guard (1...9999).contains(year) else { return nil }
        if let month {
            guard (1...12).contains(month) else { return nil }
            if let day {
                guard (1...Self.daysIn(month: month, year: year)).contains(day) else { return nil }
            }
        } else if day != nil {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day that `date` falls on: "today" for the status-change date fill.
    ///
    /// Only the time zone of `calendar` is used. Stored dates are Gregorian, so the day is always read in a
    /// Gregorian calendar set to that zone; a device calendar such as Buddhist or Japanese never shifts the
    /// year. Near midnight the zone decides the day (2026-03-01T23:30Z is 2026-03-02 in Europe/Berlin).
    public static func day(of date: Date, in calendar: Calendar) -> PartialDate {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        let year = min(max(parts.year ?? 1, 1), 9999)
        return PartialDate(year: year, month: parts.month, day: parts.day)
            ?? PartialDate(validYear: year)
    }

    /// How much of the date is known.
    public var precision: Precision {
        if day != nil { return .day }
        return month != nil ? .month : .year
    }

    /// The canonical stored spelling: `2024`, `2024-05` or `2024-05-07`.
    public var raw: String {
        var text = Self.padded(year, width: 4)
        if let month {
            text += "-" + Self.padded(month, width: 2)
            if let day { text += "-" + Self.padded(day, width: 2) }
        }
        return text
    }

    /// The MAL export spelling: `2024-00-00`, `2024-05-00` or `2024-05-07`.
    public var zeroPadded: String {
        switch precision {
        case .year: return "\(raw)-00-00"
        case .month: return "\(raw)-00"
        case .day: return raw
        }
    }

    /// Orders by (year, month, day), an unknown month or day sorting before any known one.
    public static func < (lhs: PartialDate, rhs: PartialDate) -> Bool {
        (lhs.year, lhs.month ?? 0, lhs.day ?? 0) < (rhs.year, rhs.month ?? 0, rhs.day ?? 0)
    }

    /// Decodes a single string through `init?(raw:)`; an invalid date is `DecodingError.dataCorrupted`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = PartialDate(raw: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a valid partial date.")
        }
        self = value
    }

    /// Encodes the canonical `raw` spelling as a single string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    // MARK: - Private

    private static let hyphen: UInt8 = 45

    /// Only for a year already clamped to 1...9999.
    private init(validYear year: Int) {
        self.year = year
        self.month = nil
        self.day = nil
    }

    /// The value of a run of ASCII digits, or `nil` when it is empty or holds any other byte.
    private static func number(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard !bytes.isEmpty else { return nil }
        var value = 0
        for byte in bytes {
            guard (48...57).contains(byte) else { return nil }
            value = value * 10 + Int(byte - 48)
        }
        return value
    }

    /// Days in a month under the Gregorian leap rule (as in `MALExportParser`).
    private static func daysIn(month: Int, year: Int) -> Int {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return days[month - 1]
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
