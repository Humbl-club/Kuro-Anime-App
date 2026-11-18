import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Copy

/// EN/DE words of the tracking editor's repeat-count and date rows (pure).
enum TrackingDateCopy {
    static func started(german: Bool) -> String { german ? "Begonnen" : "Started" }
    static func finished(german: Bool) -> String { german ? "Beendet" : "Finished" }
    static func noDate(german: Bool) -> String { german ? "Nicht gesetzt" : "Not set" }
    /// A value the server has not confirmed yet (a cached row): shown instead of "Not set", never editable.
    static func unknown(german: Bool) -> String { german ? "Noch nicht geladen" : "Not loaded yet" }
    static func noMonth(german: Bool) -> String { german ? "Kein Monat" : "No month" }
    static func noDay(german: Bool) -> String { german ? "Kein Tag" : "No day" }
    static func clear(german: Bool) -> String { german ? "Datum entfernen" : "Clear date" }

    /// "Rewatched 2 times" / "2-mal erneut gesehen"; manga: "Reread" / "erneut gelesen".
    static func repeatCount(_ count: Int, medium: MediaKind, german: Bool) -> String {
        switch (medium, german) {
        case (.anime, false): return count == 1 ? "Rewatched once" : "Rewatched \(count) times"
        case (.anime, true): return "\(count)-mal erneut gesehen"
        case (.manga, false): return count == 1 ? "Reread once" : "Reread \(count) times"
        case (.manga, true): return "\(count)-mal erneut gelesen"
        }
    }

    /// "2024", "May 2024", "7 May 2024" (German: "Mai 2024", "7. Mai 2024"); the value's own precision.
    static func display(_ date: PartialDate, german: Bool) -> String {
        guard let month = date.month else { return String(date.year) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.locale = german ? Locale(identifier: "de_DE") : Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate(date.day == nil ? "yMMMM" : "yMMMMd")
        let components = DateComponents(calendar: calendar, timeZone: .gmt, year: date.year, month: month, day: date.day ?? 1)
        return calendar.date(from: components).map(formatter.string(from:)) ?? date.raw
    }

    /// VoiceOver label of a date row: "Started, May 2024" / "Started, not set".
    static func rowLabel(_ title: String, _ date: PartialDate?, german: Bool) -> String {
        "\(title), \(date.map { display($0, german: german) } ?? noDate(german: german).lowercased())"
    }
}

// MARK: - Picker

/// An inline year / month / day picker for a date that may be known only to the year or the month
/// (`PartialDate`). A month of "No month" removes the day; clearing the year removes the date.
struct PartialDatePicker: View {
    @Binding var value: PartialDate?
    let label: String
    var german: Bool = KuroLocale.isGerman

    private static let firstYear = 1900
    private static var lastYear: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) + 1 }

    private var year: Int { value?.year ?? 0 }
    private var month: Int { value?.month ?? 0 }
    private var day: Int { value?.day ?? 0 }

    private var years: [Int] {
        let last = max(Self.lastYear, year)
        return Array(min(Self.firstYear, year == 0 ? Self.firstYear : year)...last)
    }

    /// The valid days of the chosen month (February by the leap rule).
    private var days: [Int] {
        guard month > 0 else { return [] }
        return (1...31).filter { PartialDate(year: max(year, 1), month: month, day: $0) != nil }
    }

    private func set(year: Int, month: Int, day: Int) {
        guard year > 0 else { value = nil; return }
        let month: Int? = month > 0 ? month : nil
        var day: Int? = (month == nil || day == 0) ? nil : day
        // A day the new month does not have moves to its last day.
        if let m = month, let d = day, PartialDate(year: year, month: m, day: d) == nil {
            day = (1...31).last { PartialDate(year: year, month: m, day: $0) != nil }
        }
        value = PartialDate(year: year, month: month, day: day)
    }

    var body: some View {
        HStack(spacing: 0) {
            wheel(selection: Binding(get: { year }, set: { set(year: $0, month: month, day: day) })) {
                Text(TrackingDateCopy.noDate(german: german)).tag(0)
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .accessibilityLabel("\(label), \(german ? "Jahr" : "year")")

            wheel(selection: Binding(get: { month }, set: { set(year: year, month: $0, day: day) })) {
                Text(TrackingDateCopy.noMonth(german: german)).tag(0)
                ForEach(1...12, id: \.self) { Text(Self.monthName($0, german: german)).tag($0) }
            }
            .disabled(year == 0)
            .accessibilityLabel("\(label), \(german ? "Monat" : "month")")

            wheel(selection: Binding(get: { day }, set: { set(year: year, month: month, day: $0) })) {
                Text(TrackingDateCopy.noDay(german: german)).tag(0)
                ForEach(days, id: \.self) { Text(String($0)).tag($0) }
            }
            .disabled(month == 0)
            .accessibilityLabel("\(label), \(german ? "Tag" : "day")")
        }
        .frame(height: 120)
    }

    private func wheel<Content: View>(selection: Binding<Int>, @ViewBuilder content: () -> Content) -> some View {
        Picker("", selection: selection, content: content)
            .pickerStyle(.wheel)
            .labelsHidden()
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: .infinity)
            .clipped()
    }

    private static func monthName(_ month: Int, german: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = german ? Locale(identifier: "de_DE") : Locale(identifier: "en_GB")
        let names = formatter.shortMonthSymbols ?? []
        return names.indices.contains(month - 1) ? names[month - 1] : String(month)
    }
}
