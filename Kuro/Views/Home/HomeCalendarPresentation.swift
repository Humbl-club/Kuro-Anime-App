import Foundation

/// One group of the Home calendar: a calendar day, the later windows, or the undated releases.
/// Display only: it never creates a release instant or a certainty the row does not carry.
struct HomeCalendarDay: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A calendar day (instants on the reader's local day, day-precision rows on their source day).
        case day
        /// Month, quarter and year windows ("Vol. 115 · November").
        case later
        /// Rows without a date ("Dates to come.").
        case undated
    }

    let id: String
    let kind: Kind
    /// "Today", "Tomorrow", "Thu 15 Oct", "Later", "Dates to come".
    let label: String
    /// The date column: day numeral ("15") or "…".
    let day: String
    /// The date column: short month ("Oct") or "".
    let month: String
    var items: [ReleaseScheduleItem]
}

/// Groups the account's release schedule for the Home calendar (rulebook §14.1): dated rows by
/// calendar day (soonest first), then month/quarter/year windows, then the undated rows. The day a row
/// falls on is read exactly as its release line reads it (`ReleaseCopy.calendarDay`), so a heading
/// never disagrees with the row under it. Server order is kept inside each group.
enum HomeCalendarPresentation {
    static func groups(_ items: [ReleaseScheduleItem], copy: ReleaseCopy) -> [HomeCalendarDay] {
        var days: [HomeCalendarDay] = []
        var dayKeys: [String: (index: Int, sort: Int)] = [:]
        var later: [ReleaseScheduleItem] = []
        var undated: [ReleaseScheduleItem] = []
        // Only rows still ahead of the reader: an aired instant or a day before today never reads as
        // an upcoming calendar day (a stale fallback row can carry a past time).
        for item in items where copy.isAhead(item) {
            guard item.releaseAt != nil else { undated.append(item); continue }
            guard let parts = copy.calendarDay(item),
                  let year = parts.year, let month = parts.month, let day = parts.day else {
                later.append(item)
                continue
            }
            let key = String(format: "%04d-%02d-%02d", year, month, day)
            if let existing = dayKeys[key] {
                days[existing.index].items.append(item)
                continue
            }
            let heading = copy.dayHeading(parts)
            dayKeys[key] = (days.count, year * 10_000 + month * 100 + day)
            days.append(HomeCalendarDay(id: key, kind: .day, label: heading?.label ?? key,
                                        day: heading?.day ?? String(day), month: heading?.month ?? "",
                                        items: [item]))
        }
        var result = days.sorted { (dayKeys[$0.id]?.sort ?? 0) < (dayKeys[$1.id]?.sort ?? 0) }
        if !later.isEmpty {
            result.append(HomeCalendarDay(id: "later", kind: .later,
                                          label: copy.german ? "Später" : "Later",
                                          day: "…", month: "", items: later))
        }
        if !undated.isEmpty {
            result.append(HomeCalendarDay(id: "undated", kind: .undated,
                                          label: copy.german ? "Termine folgen" : "Dates to come",
                                          day: "…", month: "", items: undated))
        }
        return result
    }

    /// The Coming up glance (rulebook §14.1): how many dated releases fall in the next seven days.
    /// Exact times count from now; day-precision rows count from the reader's today (the release line's
    /// own day reading, in `KuroLocale`'s calendar), so something that aired yesterday never counts.
    static func countThisWeek(_ items: [ReleaseScheduleItem], copy: ReleaseCopy) -> Int {
        let end = copy.now.addingTimeInterval(7 * 86_400)
        return items.filter { item in
            guard copy.isAhead(item), let at = item.releaseAt else { return false }
            switch item.effectivePrecision {
            case .instant: return at < end
            case .day: return (copy.daysFromToday(item) ?? 7) < 7
            case .month, .quarter, .year: return false
            }
        }.count
    }

    /// The glance's status line: "3 this week" / "Dates still to come" / "Nothing scheduled". With no
    /// rows it claims "Nothing scheduled" only after the schedule answered for this medium (§9):
    /// offline, before the answer, after a failed read or without a source it says so instead.
    static func glanceCaption(items: [ReleaseScheduleItem], copy: ReleaseCopy, offline: Bool = false,
                              coverage: ReleaseScheduleCoverage = .complete) -> String {
        let german = copy.german
        let week = countThisWeek(items, copy: copy)
        if week > 0 { return german ? "\(week) diese Woche" : "\(week) this week" }
        if items.contains(where: copy.isAhead) {
            return german ? "Termine folgen" : "Dates still to come"
        }
        if offline { return german ? "Offline. Termine laden, wenn du verbunden bist" : "Offline. Dates load when you connect" }
        switch coverage {
        case .pending: return german ? "Termine werden geprüft" : "Checking dates"
        case .complete: return german ? "Nichts angekündigt" : "Nothing scheduled"
        case .nextSevenDays: return german ? "Diese Woche ist nichts angekündigt" : "Nothing scheduled this week"
        case .noSource: return german ? "Termine folgen" : "Dates to come"
        case .failed: return german ? "Termine konnten nicht geladen werden" : "Couldn't load dates"
        }
    }

    /// Whether the glance should offer Try again: the last read failed and nothing upcoming is shown.
    static func offersRetry(items: [ReleaseScheduleItem], copy: ReleaseCopy, offline: Bool,
                            coverage: ReleaseScheduleCoverage) -> Bool {
        coverage == .failed && !offline && !items.contains(where: copy.isAhead)
    }

    // MARK: Prototype calendar card (PROTOTYPE_SPEC.md §4 "Calendar", "Dates to come")

    /// Day groups the card shows before "Next N dates" (the prototype's four).
    static let visibleDayGroups = 4
    /// Rows an open day shows before "Show N more releases" (the prototype's three).
    static let visibleRowsPerDay = 3

    /// The date chip's month: "OCT" / "OKT". The short month comes from `ReleaseCopy.dayHeading`
    /// ("Oct" / "Okt."); the chip drops the abbreviation point and sets it in capitals.
    static func chipMonth(_ month: String, locale: Locale) -> String {
        var trimmed = month.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed.uppercased(with: locale)
    }

    /// "1 release" / "3 releases"; German "1 Veröffentlichung" / "3 Veröffentlichungen" (PROTOTYPE_SPEC
    /// §7.1). The one release count of Home: the glance, the calendar heading, its days and its rows.
    static func releaseCount(_ count: Int, german: Bool) -> String {
        if german { return count == 1 ? "1 Veröffentlichung" : "\(count) Veröffentlichungen" }
        return count == 1 ? "1 release" : "\(count) releases"
    }

    /// "3 announcements" for the Dates to come group.
    static func announcementCount(_ count: Int, german: Bool) -> String {
        if german { return count == 1 ? "1 Ankündigung" : "\(count) Ankündigungen" }
        return count == 1 ? "1 announcement" : "\(count) announcements"
    }

    /// The heading's summary: "6 releases · 7 days", "48 releases · 6 weeks", or "From your list"
    /// when nothing is dated. The span is what the rows themselves cover (the next seven days for
    /// the airing fallback); a month/quarter/year window drops the span rather than guess one.
    /// The span comes from `HomeScheduleSpan`, the same rule the Coming up glance labels its count
    /// with, so the glance and this heading never disagree.
    static func summary(_ groups: [HomeCalendarDay], coverage: ReleaseScheduleCoverage, copy: ReleaseCopy) -> String {
        let german = copy.german
        let count = groups.filter { $0.kind != .undated }.reduce(0) { $0 + $1.items.count }
        guard count > 0 else { return german ? "Aus deiner Liste" : "From your list" }
        let releases = releaseCount(count, german: german)
        guard let span = HomeScheduleSpan.of(groups, coverage: coverage, copy: copy).summarySpan(german: german) else {
            return releases
        }
        return "\(releases) · \(span)"
    }

    /// The right-hand column of one release row, in the row's own certainty: the time of an exact
    /// release ("16:00"), the window of a later one ("November"), "expected" for an estimate, the
    /// unit's kind of release for a manga day ("Chapter release"), "Time TBA" for an anime day and
    /// "Date TBA" for an undated row. Never a time the row does not carry.
    static func rowWhen(_ item: ReleaseScheduleItem, copy: ReleaseCopy) -> String {
        let german = copy.german
        guard item.releaseAt != nil else { return german ? "Datum offen" : "Date TBA" }
        if item.basis == .estimated { return german ? "Voraussichtlich" : "Expected" }
        switch item.effectivePrecision {
        case .instant:
            if item.showsTime, let phrase = copy.datePhrase(item), let comma = phrase.lastIndex(of: ",") {
                return phrase[phrase.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            }
            return german ? "Uhrzeit offen" : "Time TBA"
        case .day:
            switch item.unitKind {
            case .chapter: return german ? "Neues Kapitel" : "Chapter release"
            case .volume: return german ? "Neuer Band" : "Volume release"
            case .episode, .season: return german ? "Uhrzeit offen" : "Time TBA"
            }
        case .month, .quarter, .year:
            return copy.datePhrase(item) ?? (german ? "Datum offen" : "Date TBA")
        }
    }

    /// The groups shown before "Next N dates", the hidden dated groups, and the undated group (always
    /// last and always shown: "Dates to come" exists only when rows without a date exist).
    static func paged(_ groups: [HomeCalendarDay], showAll: Bool)
        -> (visible: [HomeCalendarDay], hidden: [HomeCalendarDay], undated: HomeCalendarDay?) {
        let undated = groups.first { $0.kind == .undated }
        let dated = groups.filter { $0.kind != .undated }
        guard !showAll, dated.count > visibleDayGroups else { return (dated, [], undated) }
        return (Array(dated.prefix(visibleDayGroups)), Array(dated.dropFirst(visibleDayGroups)), undated)
    }
}
