import Foundation
import KuroCore

// MARK: - Widget copy (spec §15 "Widgets"; EN/DE)
// The sanctioned exception to `KuroLocale` (spec §10.4, §19.8): the extension cannot import the app,
// so the language comes from `WidgetSnapshot.german` (what the app rendered) and, with no snapshot,
// from the device's preferred language. Every certainty-dependent string (release lines, dates,
// "expected …") is pre-rendered by the app with `ReleaseCopy`; nothing here words a date or a time.

nonisolated enum WidgetCopy {
    /// The device language when no snapshot says which language the app rendered.
    static func preferredGerman(_ languages: [String] = Locale.preferredLanguages) -> Bool {
        languages.first?.lowercased().hasPrefix("de") == true
    }

    // MARK: Eyebrows

    static func nextEpisode(_ german: Bool) -> String { german ? "Nächste Folge" : "Next episode" }
    static func nextChapter(_ german: Bool) -> String { german ? "Nächstes Kapitel" : "Next chapter" }
    static func nextVolume(_ german: Bool) -> String { german ? "Nächster Band" : "Next volume" }
    /// Rows of both media (and the gallery name): the platform's shipped "Up next" / "Als Nächstes".
    static func upNext(_ german: Bool) -> String { german ? "Als Nächstes" : "Up next" }
    /// Home's opening kicker (`HomeOpeningLine.kicker`), copied verbatim.
    static func nowWatching(_ german: Bool) -> String { german ? "Du schaust gerade" : "Now watching" }
    /// Home's opening kicker for manga (`HomeOpeningLine.kicker`), copied verbatim.
    static func nowReading(_ german: Bool) -> String { german ? "Du liest gerade" : "Now reading" }

    // MARK: States

    static func signedOut(_ german: Bool) -> String {
        german ? "Öffne Kuro, um zu sehen, was als Nächstes kommt." : "Open Kuro to see what's next."
    }
    static func noDates(_ german: Bool) -> String { german ? "Noch keine Termine." : "No dates yet." }
    static func nothingInProgress(_ german: Bool) -> String { german ? "Gerade nichts angefangen." : "Nothing in progress." }

    // MARK: Rows

    /// The queued +1 caption: the widget shows the new position before Kuro saved it (spec D13).
    static func savedWhenKuroOpens(_ german: Bool) -> String {
        german ? "Wird gespeichert, wenn Kuro öffnet" : "Saved when Kuro opens"
    }
    static func estimate(_ german: Bool) -> String { german ? "Schätzung" : "Estimate" }
    static func caughtUp(_ german: Bool) -> String { german ? "Auf dem neuesten Stand" : "Caught up" }
    /// The prefix of a Now Watching row's next-release line: "Next · Ep. 8 · Fri 6 Nov, 21:30".
    static func nextPrefix(_ german: Bool) -> String { german ? "Als Nächstes" : "Next" }

    // MARK: VoiceOver (full words, spec §14.3 rule 4)

    /// The +1 key: "Mark episode 7 watched" / "Folge 7 als gesehen markieren",
    /// "Mark chapter 69 read" / "Kapitel 69 als gelesen markieren".
    static func markLabel(_ medium: MediaKind, next: Int, german: Bool) -> String {
        switch (medium, german) {
        case (.anime, false): return "Mark episode \(next) watched"
        case (.anime, true): return "Folge \(next) als gesehen markieren"
        case (.manga, false): return "Mark chapter \(next) read"
        case (.manga, true): return "Kapitel \(next) als gelesen markieren"
        }
    }

    /// "episode 6 of 23" / "Folge 6 von 23", "chapter 68" / "Kapitel 68".
    static func progressWords(_ medium: MediaKind, progress: Int, total: Int?, german: Bool) -> String {
        let unit: String
        switch (medium, german) {
        case (.anime, false): unit = "episode"
        case (.anime, true): unit = "Folge"
        case (.manga, false): unit = "chapter"
        case (.manga, true): unit = "Kapitel"
        }
        guard let total else { return "\(unit) \(progress)" }
        return "\(unit) \(progress) \(german ? "von" : "of") \(total)"
    }

    /// One Now Watching row as one element: "{title}, episode 6 of 23", then "Caught up" or the queued
    /// caption when they apply.
    static func nowWatchingRowLabel(title: String, medium: MediaKind, progress: Int, total: Int?,
                                    caughtUp: Bool, queued: Bool, german: Bool) -> String {
        var parts = [title, progressWords(medium, progress: progress, total: total, german: german)]
        if caughtUp { parts.append(Self.caughtUp(german)) }
        if queued { parts.append(savedWhenKuroOpens(german)) }
        return parts.joined(separator: ", ")
    }

    /// One release row as one element: "{title}, {ReleaseCopy.accessibilityLine}" (already full words,
    /// and an estimate already says "expected").
    static func releaseRowLabel(title: String, accessibilityLine: String) -> String {
        accessibilityLine.isEmpty ? title : "\(title), \(accessibilityLine)"
    }

    // MARK: Gallery (KuroWidgetsBundle)

    static func upNextDescription(_ german: Bool) -> String {
        german ? "Die nächsten Folgen und Kapitel deiner Titel." : "The next episodes and chapters of what you follow."
    }
    static func nowWatchingDescription(_ german: Bool) -> String {
        german ? "Was du gerade schaust und liest, mit +1." : "What you are watching and reading, with +1."
    }
}
