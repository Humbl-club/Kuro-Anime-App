import Foundation

/// A display-only grouping of the already-served Home events. Date-only releases retain their
/// source day; timed releases group in the viewer's calendar, without creating a release instant.
struct HomeCalendarDay: Identifiable {
    let id: String
    let label: String
    let day: String
    let month: String
    var events: [HomeEvent]
}

enum HomeCalendarPresentation {
    static func groups(_ events: [HomeEvent], calendar: Calendar = .current, now: Date = Date()) -> [HomeCalendarDay] {
        var groups: [HomeCalendarDay] = []
        var positions: [String: Int] = [:]
        // Source dates and wire group keys are Gregorian ISO dates even when the viewer
        // uses a Buddhist, Islamic or other calendar. Only their timezone is viewer-local.
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = calendar.timeZone
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.calendar = sourceCalendar; dayFormat.timeZone = calendar.timeZone
        dayFormat.dateFormat = "yyyy-MM-dd"
        for event in events {
            let date: Date?
            let key: String
            if event.precision == "day", let source = event.sourceLocalDate {
                key = source; date = dayFormat.date(from: source)
            } else if let raw = event.at, let instant = instant(raw) {
                date = instant; key = dayFormat.string(from: instant)
            } else {
                date = nil; key = "unknown-" + event.id
            }
            if let index = positions[key] { groups[index].events.append(event); continue }
            let display = DateFormatter(); display.calendar = calendar; display.timeZone = calendar.timeZone
            let label: String
            if let date {
                if calendar.isDate(date, inSameDayAs: now) { label = "Today" }
                else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { label = "Tomorrow" }
                else { display.dateFormat = "EEE, d MMM"; label = display.string(from: date) }
            } else { label = "Date to come" }
            display.dateFormat = "d"; let day = date.map { display.string(from: $0) } ?? "…"
            display.dateFormat = "MMM"; let month = date.map { display.string(from: $0) } ?? ""
            positions[key] = groups.count
            groups.append(HomeCalendarDay(id: key, label: label, day: day, month: month, events: [event]))
        }
        return groups
    }

    private static func instant(_ raw: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: raw) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: raw)
    }
}
