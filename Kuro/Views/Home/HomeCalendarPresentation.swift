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
        for item in items where item.isDisplayable && !item.isPast {
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
    static func countThisWeek(_ items: [ReleaseScheduleItem], now: Date) -> Int {
        let end = now.addingTimeInterval(7 * 86_400)
        let startOfToday = Calendar.current.startOfDay(for: now)
        return items.filter { item in
            guard item.isDisplayable, !item.isPast, let at = item.releaseAt else { return false }
            switch item.effectivePrecision {
            case .instant, .day: return at >= startOfToday.addingTimeInterval(-86_400) && at < end
            case .month, .quarter, .year: return false
            }
        }.count
    }

    /// The glance's status line: "3 this week" / "Dates still to come" / "Nothing scheduled".
    static func glanceCaption(items: [ReleaseScheduleItem], now: Date, german: Bool) -> String {
        let week = countThisWeek(items, now: now)
        if week > 0 { return german ? "\(week) diese Woche" : "\(week) this week" }
        if items.contains(where: { $0.isDisplayable && !$0.isPast }) {
            return german ? "Termine folgen" : "Dates still to come"
        }
        return german ? "Nichts angekündigt" : "Nothing scheduled"
    }
}
