import Foundation

// MARK: - Release copy (spec D10, §3.5 KuroReleaseLine)
// Pure EN/DE wording for a `ReleaseScheduleItem`. Every input that changes the output (now, language,
// locale, time zone) is explicit, so tests pin all of them; views use `ReleaseCopy.current()`.
//
//   confirmed  "Ep. 7 · Thu 15 Oct, 18:30"          "F. 7 · Do. 15. Okt., 18:30"
//   announced  "Vol. 115 · November"                "Bd. 115 · November"
//   estimated  "Ch. 1197 · expected around Sun 9 Nov" "Kap. 1197 · voraussichtlich am So. 9. Nov."
//   relative   "Ep. 7 · Today, 18:30" / "Tomorrow"   "Heute, 18:30" / "Morgen"
//
// An announced date stored as the first of a month at 00:00 UTC is a month window ("November");
// any other announced date is a day without a time, read as its UTC calendar date (a day-only
// value stored at 00:00 or 12:00 UTC never shows the previous day west of UTC); "today/tomorrow"
// compares that date with the reader's local calendar day. A row with no date gets no date phrase
// (the caller decides whether "Dates to come." fills an otherwise empty slot).

nonisolated struct ReleaseCopy {
    let now: Date
    let german: Bool
    let locale: Locale
    let timeZone: TimeZone

    private let calendar: Calendar
    private let dayFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let monthFormatter: DateFormatter
    private let monthYearFormatter: DateFormatter
    private let longDayFormatter: DateFormatter
    /// Day-only (announced) dates: their UTC calendar date.
    private let utcCalendar: Calendar
    private let utcDayFormatter: DateFormatter
    private let utcLongDayFormatter: DateFormatter

    init(now: Date, german: Bool, locale: Locale, timeZone: TimeZone) {
        self.now = now
        self.german = german
        self.locale = locale
        self.timeZone = timeZone
        self.calendar = KuroLocale.calendar(locale: locale, timeZone: timeZone)
        let utc = TimeZone(identifier: "UTC") ?? timeZone
        let cache = ReleaseFormatterCache.shared
        dayFormatter = cache.formatter("EEEdMMM", locale: locale, timeZone: timeZone)
        timeFormatter = cache.formatter("jmm", locale: locale, timeZone: timeZone)
        // Month windows are stored at 00:00 UTC on the 1st; read them in UTC so a zone west of UTC
        // never shows the previous month.
        monthFormatter = cache.formatter("MMMM", locale: locale, timeZone: utc)
        monthYearFormatter = cache.formatter("MMMMyyyy", locale: locale, timeZone: utc)
        longDayFormatter = cache.formatter("EEEEdMMMM", locale: locale, timeZone: timeZone)
        utcCalendar = KuroLocale.calendar(locale: locale, timeZone: utc)
        utcDayFormatter = cache.formatter("EEEdMMM", locale: locale, timeZone: utc)
        utcLongDayFormatter = cache.formatter("EEEEdMMMM", locale: locale, timeZone: utc)
    }

    /// The reader's language, locale and zone (`KuroLocale`), at `now`.
    static func current(now: Date = Date()) -> ReleaseCopy {
        ReleaseCopy(now: now, german: KuroLocale.isGerman, locale: KuroLocale.locale, timeZone: KuroLocale.timeZone)
    }

    private func pick(_ english: String, _ german: String) -> String {
        self.german ? german : english
    }

    // MARK: Unit

    /// "Ep. 7", "Ch. 1197", "Vol. 115", "Season 2" / "F. 7", "Kap. 1197", "Bd. 115", "Staffel 2".
    /// Without a number: the server label, else "Next episode" / "Nächste Folge" etc.
    func unitLabel(_ item: ReleaseScheduleItem) -> String {
        guard let number = numberText(item) else {
            if let label = item.unitLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty, !german {
                return label
            }
            switch item.unitKind {
            case .episode: return pick("Next episode", "Nächste Folge")
            case .chapter: return pick("Next chapter", "Nächstes Kapitel")
            case .volume: return pick("Next volume", "Nächster Band")
            case .season: return pick("Next season", "Nächste Staffel")
            }
        }
        switch item.unitKind {
        case .episode: return pick("Ep. ", "F. ") + number
        case .chapter: return pick("Ch. ", "Kap. ") + number
        case .volume: return pick("Vol. ", "Bd. ") + number
        case .season: return pick("Season ", "Staffel ") + number
        }
    }

    /// The unit spelled out for VoiceOver: "Episode 7" / "Folge 7".
    func unitSpokenLabel(_ item: ReleaseScheduleItem) -> String {
        guard let number = numberText(item) else { return unitLabel(item) }
        switch item.unitKind {
        case .episode: return pick("Episode ", "Folge ") + number
        case .chapter: return pick("Chapter ", "Kapitel ") + number
        case .volume: return pick("Volume ", "Band ") + number
        case .season: return pick("Season ", "Staffel ") + number
        }
    }

    private func numberText(_ item: ReleaseScheduleItem) -> String? {
        if let whole = item.wholeUnitNumber { return String(whole) }
        guard let number = item.unitNumber, number.isFinite else { return nil }
        let text = String(number)
        return german ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    // MARK: Date

    /// The date phrase after the separator, or nil when the row has no date or may not be shown.
    func datePhrase(_ item: ReleaseScheduleItem) -> String? {
        guard item.isDisplayable, let date = item.releaseAt else { return nil }
        if item.isPast {
            return pick("released ", "erschienen ") + dayText(date, relativeCapitalized: false)
        }
        switch item.basis {
        case .confirmed:
            return "\(dayText(date, relativeCapitalized: true)), \(timeFormatter.string(from: date))"
        case .announced:
            if isMonthWindow(date) { return monthText(date) }
            if let relative = relativeDay(announcedDay: date) { return relative.capitalized(with: locale) }
            return utcDayFormatter.string(from: date)
        case .estimated:
            if relativeDay(date) != nil {
                return pick("expected ", "voraussichtlich ") + dayText(date, relativeCapitalized: false)
            }
            return pick("expected around ", "voraussichtlich am ") + dayFormatter.string(from: date)
        }
    }

    /// "Ep. 7 · Thu 15 Oct, 18:30". Without a date: the unit, plus " · Dates to come." when
    /// `undatedFallback` is set (only where the slot would otherwise be empty).
    func line(_ item: ReleaseScheduleItem, undatedFallback: Bool = false) -> String {
        let unit = unitLabel(item)
        if let phrase = datePhrase(item) { return "\(unit) · \(phrase)" }
        return undatedFallback ? "\(unit) · \(datesToCome)" : unit
    }

    /// Full words for VoiceOver: "Episode 7, Thursday 15 October, 18:30".
    func accessibilityLine(_ item: ReleaseScheduleItem) -> String {
        let unit = unitSpokenLabel(item)
        guard item.isDisplayable, let date = item.releaseAt else { return "\(unit), \(datesToCome)" }
        let day = relativeDay(date).map { $0.capitalized(with: locale) } ?? longDayFormatter.string(from: date)
        if item.isPast { return "\(unit), " + pick("released ", "erschienen ") + day }
        switch item.basis {
        case .confirmed: return "\(unit), \(day), \(timeFormatter.string(from: date))"
        case .announced:
            if isMonthWindow(date) { return "\(unit), " + monthText(date) }
            let announcedDay = relativeDay(announcedDay: date).map { $0.capitalized(with: locale) }
                ?? utcLongDayFormatter.string(from: date)
            return "\(unit), " + announcedDay
        case .estimated:
            if let relative = relativeDay(date) {
                return "\(unit), " + pick("expected ", "voraussichtlich ") + relative
            }
            return "\(unit), " + pick("expected around ", "voraussichtlich am ") + longDayFormatter.string(from: date)
        }
    }

    /// "Dates to come." / "Termine folgen." (rulebook §9).
    var datesToCome: String { pick("Dates to come.", "Termine folgen.") }

    /// "via AniList" / "über AniList"; nil for an unknown source.
    func sourceAttribution(_ item: ReleaseScheduleItem) -> String? {
        let name: String
        switch item.source.lowercased() {
        case "anilist": name = "AniList"
        case "mangaupdates": name = "MangaUpdates"
        case "mangadex": name = "MangaDex"
        case "publisher": name = pick("the publisher", "den Verlag")
        case "kuro_estimate": return pick("Kuro estimate from recent releases", "Kuro-Schätzung aus den letzten Veröffentlichungen")
        default: return nil
        }
        return pick("via ", "über ") + name
    }

    // MARK: Helpers

    /// "today" / "tomorrow" (lower case) when `date` falls on that calendar day in `timeZone`.
    private func relativeDay(_ date: Date) -> String? {
        if calendar.isDate(date, inSameDayAs: now) { return pick("today", "heute") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return pick("tomorrow", "morgen")
        }
        return nil
    }

    /// "today" / "tomorrow" for a day-only date: its UTC calendar date against the reader's local
    /// calendar day of `now` and of the day after.
    private func relativeDay(announcedDay date: Date) -> String? {
        let day = utcCalendar.dateComponents([.year, .month, .day], from: date)
        func same(_ reference: Date) -> Bool {
            let local = calendar.dateComponents([.year, .month, .day], from: reference)
            return local.year == day.year && local.month == day.month && local.day == day.day
        }
        if same(now) { return pick("today", "heute") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), same(tomorrow) {
            return pick("tomorrow", "morgen")
        }
        return nil
    }

    private func dayText(_ date: Date, relativeCapitalized: Bool) -> String {
        guard let relative = relativeDay(date) else { return dayFormatter.string(from: date) }
        return relativeCapitalized ? relative.capitalized(with: locale) : relative
    }

    private func monthText(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? timeZone
        let sameYear = utc.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? monthFormatter.string(from: date) : monthYearFormatter.string(from: date)
    }

    /// First of a month at 00:00 UTC: the source announced a month, not a day.
    private func isMonthWindow(_ date: Date) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? timeZone
        let parts = utc.dateComponents([.day, .hour, .minute, .second], from: date)
        return parts.day == 1 && parts.hour == 0 && parts.minute == 0 && parts.second == 0
    }
}

/// Shared date formatters per (template, locale, zone): a release line in a 100-row list must not
/// build five formatters per row. `DateFormatter` formatting is thread-safe; creation is locked.
nonisolated final class ReleaseFormatterCache: @unchecked Sendable {
    static let shared = ReleaseFormatterCache()

    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func formatter(_ template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = KuroLocale.calendar(locale: locale, timeZone: timeZone)
        formatter.setLocalizedDateFormatFromTemplate(template)
        if formatters.count > 64 { formatters.removeAll() }
        formatters[key] = formatter
        return formatter
    }
}
