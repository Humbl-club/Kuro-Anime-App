import Foundation

// MARK: - Release copy (spec D10, §3.3a, §3.5 KuroReleaseLine)
// Pure EN/DE wording for a `ReleaseScheduleItem`. Every input that changes the output (now, language,
// locale, time zone) is explicit, so tests pin all of them; views use `ReleaseCopy.current()`.
//
//   confirmed  "Ep. 7 · Thu 15 Oct, 18:30"          "F. 7 · Do. 15. Okt., 18:30"
//   announced  "Vol. 115 · November"                "Bd. 115 · November"
//   estimated  "Ch. 1197 · expected around Sun 9 Nov" "Kap. 1197 · voraussichtlich am So. 9. Nov."
//   relative   "Ep. 7 · Today, 18:30" / "Tomorrow"   "Heute, 18:30" / "Morgen"
//
// The row's precision (`effectivePrecision`, spec §3.3a) decides the shape, and a time of day is shown
// only for an instant: day "Thu 15 Oct", month "November" ("February 2027" in another year), quarter
// "Q1 2027", year "2027". Reading a date as a calendar day:
//   - instant: the reader's local day;
//   - a server-stated precision (day/month/quarter/year): the window starts at 00:00 in the source's
//     zone, so the day is taken from the nearest midnight (UTC date of `releaseAt` + 11:59:59). That
//     recovers the source date for every zone from UTC−12 to UTC+11 (JST, Europe, the Americas);
//   - an inferred precision (no `release_precision`, the older contract): announced rows read their UTC
//     calendar date (a day-only value stored at 00:00 or 12:00 UTC never shows the previous day west of
//     UTC); estimated rows read the reader's local day, exactly as before the column existed.
// "Today/tomorrow" compares that day with the reader's local calendar day. A row with no date gets no
// date phrase (the caller decides whether "Dates to come." fills an otherwise empty slot).

nonisolated struct ReleaseCopy {
    let now: Date
    let german: Bool
    let locale: Locale
    let timeZone: TimeZone
    /// "today" / "tomorrow" words. Off for text stored and shown later (the widget snapshot): a stored
    /// "Tomorrow" would still read "Tomorrow" on the release day, so stored days are always absolute.
    private(set) var relativeDays = true

    private let calendar: Calendar
    private let dayFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let monthFormatter: DateFormatter
    private let monthYearFormatter: DateFormatter
    private let longDayFormatter: DateFormatter
    /// Day-only and window dates: their UTC (or nearest-source-midnight) calendar date.
    private let utcCalendar: Calendar
    private let utcDayFormatter: DateFormatter
    private let utcLongDayFormatter: DateFormatter
    private let utcDayNumberFormatter: DateFormatter
    private let utcShortMonthFormatter: DateFormatter

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
        utcDayNumberFormatter = cache.formatter("d", locale: locale, timeZone: utc)
        utcShortMonthFormatter = cache.formatter("MMM", locale: locale, timeZone: utc)
    }

    /// The same wording with absolute days only ("Wed 26 Nov, 21:30", never "Tomorrow, 21:30").
    func withoutRelativeDays() -> ReleaseCopy {
        var copy = self
        copy.relativeDays = false
        return copy
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

    /// How a row's date becomes a calendar day (see the file header).
    private enum DayReading {
        case local
        case utc
        case source
    }

    private func reading(_ item: ReleaseScheduleItem) -> DayReading {
        if item.effectivePrecision == .instant { return .local }
        if item.precision == nil { return item.basis == .estimated ? .local : .utc }
        return .source
    }

    /// Nearest-midnight shift for a window stored at 00:00 in the source's zone.
    private static let sourceMidnightShift: TimeInterval = 43_199

    /// The date to format in UTC for a UTC or source reading.
    private func utcDate(_ date: Date, _ reading: DayReading) -> Date {
        reading == .source ? date.addingTimeInterval(Self.sourceMidnightShift) : date
    }

    /// The date phrase after the separator, or nil when the row has no date or may not be shown.
    func datePhrase(_ item: ReleaseScheduleItem) -> String? {
        guard item.isDisplayable, let date = item.releaseAt else { return nil }
        let precision = item.effectivePrecision
        let reading = reading(item)
        if item.isPast {
            let when = windowText(date, precision: precision, reading: reading)
                ?? dayPhrase(date, reading: reading, capitalized: false, long: false)
            return pick("released ", "erschienen ") + when
        }
        if let window = windowText(date, precision: precision, reading: reading) {
            return item.basis == .estimated ? estimatedWindow(window, precision: precision) : window
        }
        if item.basis == .estimated {
            if let relative = relative(date, reading: reading) {
                return pick("expected ", "voraussichtlich ") + relative
            }
            return pick("expected around ", "voraussichtlich am ") + dayPhrase(date, reading: reading, capitalized: false, long: false)
        }
        let day = dayPhrase(date, reading: reading, capitalized: true, long: false)
        return item.showsTime ? "\(day), \(timeFormatter.string(from: date))" : day
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
        let precision = item.effectivePrecision
        let reading = reading(item)
        if item.isPast {
            let when = windowText(date, precision: precision, reading: reading)
                ?? dayPhrase(date, reading: reading, capitalized: false, long: true)
            return "\(unit), " + pick("released ", "erschienen ") + when
        }
        if let window = windowText(date, precision: precision, reading: reading) {
            return "\(unit), " + (item.basis == .estimated ? estimatedWindow(window, precision: precision) : window)
        }
        if item.basis == .estimated {
            if let relative = relative(date, reading: reading) {
                return "\(unit), " + pick("expected ", "voraussichtlich ") + relative
            }
            return "\(unit), " + pick("expected around ", "voraussichtlich am ")
                + dayPhrase(date, reading: reading, capitalized: false, long: true)
        }
        let day = dayPhrase(date, reading: reading, capitalized: true, long: true)
        return item.showsTime ? "\(unit), \(day), \(timeFormatter.string(from: date))" : "\(unit), \(day)"
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

    // MARK: Calendar grouping (Home)

    /// The calendar day (year, month, day) a dated row falls on, read exactly as its date phrase reads
    /// it; nil for an undated row, a row that may not be shown, or a month/quarter/year window.
    func calendarDay(_ item: ReleaseScheduleItem) -> DateComponents? {
        guard item.isDisplayable, let date = item.releaseAt else { return nil }
        switch item.effectivePrecision {
        case .month, .quarter, .year: return nil
        case .instant, .day: break
        }
        let reading = reading(item)
        if reading == .local { return calendar.dateComponents([.year, .month, .day], from: date) }
        return utcCalendar.dateComponents([.year, .month, .day], from: utcDate(date, reading))
    }

    /// How many calendar days the row's day lies after the reader's today (negative: already past),
    /// read exactly as `calendarDay` reads it. nil for windows and undated rows.
    func daysFromToday(_ item: ReleaseScheduleItem) -> Int? {
        guard let parts = calendarDay(item), let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let todayYear = today.year, let todayMonth = today.month, let todayDay = today.day,
              let rowNoon = utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              let todayNoon = utcCalendar.date(from: DateComponents(year: todayYear, month: todayMonth, day: todayDay, hour: 12))
        else { return nil }
        return utcCalendar.dateComponents([.day], from: todayNoon, to: rowNoon).day
    }

    /// Whether the row still lies ahead of the reader: an exact time not yet reached, a day not before
    /// today, or any window. Rows without a date count as ahead (their date is still to come).
    func isAhead(_ item: ReleaseScheduleItem) -> Bool {
        guard item.isDisplayable, !item.isPast else { return false }
        guard let at = item.releaseAt else { return true }
        switch item.effectivePrecision {
        case .instant: return at >= now
        case .day: return (daysFromToday(item) ?? 0) >= 0
        case .month, .quarter, .year: return true
        }
    }

    /// A calendar day as a heading: "Today" / "Tomorrow" / "Thu 15 Oct" (capitalized), plus the day
    /// numeral and short month for the date column. nil for incomplete components.
    func dayHeading(_ day: DateComponents) -> (label: String, day: String, month: String)? {
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day,
              let noon = utcCalendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))
        else { return nil }
        let label = relativeDay(announcedDay: noon).map { $0.capitalized(with: locale) } ?? utcDayFormatter.string(from: noon)
        return (label, utcDayNumberFormatter.string(from: noon), utcShortMonthFormatter.string(from: noon))
    }

    // MARK: Helpers

    /// "today" / "tomorrow" (lower case) for the row's day under `reading`.
    private func relative(_ date: Date, reading: DayReading) -> String? {
        reading == .local ? relativeDay(date) : relativeDay(announcedDay: utcDate(date, reading))
    }

    /// The row's day: relative when it is today or tomorrow, else "Thu 15 Oct" (or "Thursday 15
    /// October" when `long`).
    private func dayPhrase(_ date: Date, reading: DayReading, capitalized: Bool, long: Bool) -> String {
        if let relative = relative(date, reading: reading) {
            return capitalized ? relative.capitalized(with: locale) : relative
        }
        switch reading {
        case .local: return (long ? longDayFormatter : dayFormatter).string(from: date)
        case .utc, .source: return (long ? utcLongDayFormatter : utcDayFormatter).string(from: utcDate(date, reading))
        }
    }

    /// "November" / "February 2027", "Q1 2027", "2027" for a window; nil for an instant or a day.
    private func windowText(_ date: Date, precision: ReleasePrecision, reading: DayReading) -> String? {
        let start = utcDate(date, reading == .local ? .utc : reading)
        switch precision {
        case .instant, .day: return nil
        case .month: return monthText(start)
        case .quarter:
            let parts = utcCalendar.dateComponents([.year, .month], from: start)
            guard let year = parts.year, let month = parts.month else { return nil }
            return "Q\((month - 1) / 3 + 1) \(year)"
        case .year:
            return utcCalendar.dateComponents([.year], from: start).year.map(String.init)
        }
    }

    /// "expected in November" / "voraussichtlich im November"; a year window has no preposition in
    /// German ("voraussichtlich 2027").
    private func estimatedWindow(_ window: String, precision: ReleasePrecision) -> String {
        if precision == .year { return pick("expected in ", "voraussichtlich ") + window }
        return pick("expected in ", "voraussichtlich im ") + window
    }

    /// "today" / "tomorrow" (lower case) when `date` falls on that calendar day in `timeZone`.
    private func relativeDay(_ date: Date) -> String? {
        guard relativeDays else { return nil }
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
        guard relativeDays else { return nil }
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

    /// The month (UTC calendar) with its year when that is not the reader's current year.
    private func monthText(_ date: Date) -> String {
        let sameYear = utcCalendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? monthFormatter.string(from: date) : monthYearFormatter.string(from: date)
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
