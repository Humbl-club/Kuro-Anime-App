import Foundation

// MARK: - Locale (EN/DE)
// The one decision point for German copy and date formatting (spec D4). Every new user-facing
// string ships as an inline EN/DE pair through `KuroLocale.text(_:_:)`; no String Catalog yet.
// German uses `de_DE` and Europe/Berlin (CLAUDE.md quality standard); English follows the device.

nonisolated enum KuroLocale {
    /// True when the user's first preferred language is German.
    static var isGerman: Bool {
        isGerman(preferredLanguages: Locale.preferredLanguages)
    }

    /// Pure form of `isGerman` (testable).
    static func isGerman(preferredLanguages: [String]) -> Bool {
        if let first = preferredLanguages.first {
            return first.lowercased().hasPrefix("de")
        }
        return Locale.current.language.languageCode?.identifier.lowercased() == "de"
    }

    /// The German string when the user reads German, otherwise the English one.
    static func text(_ english: String, _ german: String) -> String {
        isGerman ? german : english
    }

    /// Formatting locale: `de_DE` for German readers, the device locale otherwise.
    static var locale: Locale {
        isGerman ? Locale(identifier: "de_DE") : .autoupdatingCurrent
    }

    /// Display time zone: Europe/Berlin for German readers, the device zone otherwise.
    static var timeZone: TimeZone {
        isGerman ? (TimeZone(identifier: "Europe/Berlin") ?? .autoupdatingCurrent) : .autoupdatingCurrent
    }

    /// A Gregorian calendar in `locale` and `timeZone`.
    static var calendar: Calendar {
        calendar(locale: locale, timeZone: timeZone)
    }

    /// A Gregorian calendar for explicit inputs (tests pin both).
    static func calendar(locale: Locale, timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }
}
