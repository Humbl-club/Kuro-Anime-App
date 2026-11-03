import Foundation

// MARK: - Profile numbers copy (details-songs spec §12, §15; EN/DE)
// Every string of the "Your numbers." section and the release-reminders row. Numbers use the
// reader's locale ("1,284" / "1.284"). Pure: `german` and `locale` are explicit so tests pin both.

nonisolated enum ProfileStatsCopy {
    static func heading(german: Bool) -> String { german ? "Deine Zahlen." : "Your numbers." }
    static func summary(german: Bool) -> String { german ? "Auf diesem Gerät gezählt" : "Counted on this device" }

    static func episodesKicker(german: Bool) -> String { german ? "Folgen" : "Episodes" }
    static func chaptersKicker(german: Bool) -> String { german ? "Kapitel" : "Chapters" }

    static func number(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale).grouping(.automatic))
    }

    static func acrossAnime(_ count: Int, german: Bool) -> String {
        german ? "aus \(count) Anime" : "across \(count) anime"
    }

    static func acrossManga(_ count: Int, german: Bool) -> String {
        german ? "aus \(count) Manga" : "across \(count) manga"
    }

    /// "1,284 episodes across 61 anime" (one VoiceOver element per total).
    static func episodesSpoken(_ total: ProfileStats.Total, german: Bool, locale: Locale) -> String {
        let n = number(total.units, locale: locale)
        return german ? "\(n) Folgen aus \(total.titles) Anime" : "\(n) episodes across \(total.titles) anime"
    }

    static func chaptersSpoken(_ total: ProfileStats.Total, german: Bool, locale: Locale) -> String {
        let n = number(total.units, locale: locale)
        return german ? "\(n) Kapitel aus \(total.titles) Manga" : "\(n) chapters across \(total.titles) manga"
    }

    /// Below 48 hours "≈ 37 h" / "≈ 37 Std.", otherwise "21 d 9 h" / "21 T 9 Std.". Nil for no minutes.
    static func time(minutes: Int, german: Bool, locale: Locale) -> String? {
        guard minutes > 0 else { return nil }
        let hours = max(1, Int((Double(minutes) / 60).rounded()))
        if hours < 48 {
            return german ? "≈ \(number(hours, locale: locale)) Std." : "≈ \(number(hours, locale: locale)) h"
        }
        let days = hours / 24
        let rest = hours % 24
        return german ? "\(number(days, locale: locale)) T \(rest) Std." : "\(number(days, locale: locale)) d \(rest) h"
    }

    /// The caveat, always shown under the time; it names the titles without a length.
    static func timeCaveat(missing: Int, german: Bool) -> String {
        let base = german ? "Gesehene Folgen × die Folgenlänge jedes Titels." : "Episodes watched × each title's episode length."
        guard missing > 0 else { return base }
        if missing == 1 {
            return base + (german ? " 1 Titel hat keine Länge und zählt nicht mit." : " 1 title has no length and isn't counted.")
        }
        return base + (german ? " \(missing) Titel haben keine Länge und zählen nicht mit."
                              : " \(missing) titles have no length and aren't counted.")
    }

    static func timeKicker(german: Bool) -> String { german ? "Zeit" : "Time" }

    static func genresHeading(german: Bool) -> String { german ? "Top-Genres" : "Top genres" }
    static func genresSummary(german: Bool) -> String { german ? "nach Titeln auf deinen Listen" : "by titles on your lists" }

    /// "Action, 31 titles".
    static func genreSpoken(_ genre: ProfileStats.Genre, german: Bool) -> String {
        german ? "\(genre.name), \(genre.count) Titel" : "\(genre.name), \(genre.count) \(genre.count == 1 ? "title" : "titles")"
    }

    // MARK: Your year

    static func yearTab(german: Bool) -> String { german ? "Jahr" : "Year" }

    static func yearTitle(_ count: Int, german: Bool) -> String {
        german ? "\(count) Titel dieses Jahr" : "\(count) \(count == 1 ? "title" : "titles") this year"
    }

    static func savedOrChanged(_ count: Int, german: Bool) -> String {
        german ? "\(count) Titel gespeichert oder geändert" : "\(count) \(count == 1 ? "title" : "titles") saved or changed"
    }

    static func completed(_ count: Int, german: Bool) -> String {
        german ? "\(count) davon abgeschlossen" : "\(count) of them now completed"
    }

    static func mostTime(_ title: String, german: Bool) -> String {
        german ? "Meiste Zeit: \(title)" : "Most time: \(title)"
    }

    /// The honest note under the card (Kuro has no finish dates).
    static func yearNote(_ year: Int, german: Bool) -> String {
        german
            ? "Kuro speichert kein Enddatum. \(year) zählt Titel, die du dieses Jahr gespeichert oder geändert hast."
            : "Kuro doesn't record finish dates, so \(year) counts titles you saved or changed this year."
    }

    /// The year card as one VoiceOver element.
    static func yearSpoken(_ year: ProfileStats.Year, german: Bool) -> String {
        var parts = [(german ? "Jahr \(year.year)" : "Year \(year.year)"), savedOrChanged(year.titles, german: german)]
        if year.completed > 0 { parts.append(completed(year.completed, german: german)) }
        return parts.joined(separator: ". ")
    }

    static func empty(german: Bool) -> String {
        german ? "Deine Zahlen erscheinen, sobald du einen Titel speicherst." : "Your numbers appear once you save a title."
    }

    static func catalogueFailed(german: Bool) -> String {
        german ? "Zeit und Genres konnten nicht geladen werden." : "Time and genres couldn't load."
    }

    // MARK: Release reminders (§11.4, §12.3)

    static func remindersTitle(german: Bool) -> String {
        german ? "Erinnerungen an Neuerscheinungen" : "Release reminders"
    }

    /// The row's subtitle. Worded for the merged platform planner, which notifies confirmed and
    /// announced releases (an exact time, or the release day in the morning) and never an estimate.
    static func remindersSubtitle(german: Bool) -> String {
        german
            ? "Neue Folgen und Kapitel von dem, was du schaust oder liest. Nur bestätigte und angekündigte Termine, nie Schätzungen."
            : "New episodes and chapters of what you're watching or reading. Confirmed and announced dates only, never estimates."
    }

    static func remindersDenied(german: Bool) -> String {
        german ? "Mitteilungen für Kuro sind aus. Du kannst sie in den Einstellungen einschalten."
               : "Notifications are off for Kuro. Turn them on in Settings."
    }

    static func openSettings(german: Bool) -> String { german ? "Einstellungen öffnen" : "Open Settings" }

    static func remindersFailed(german: Bool) -> String {
        german ? "Erinnerung konnte nicht gesetzt werden." : "Couldn't set the reminder."
    }
}
