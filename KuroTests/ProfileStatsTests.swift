import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

/// Details-songs spec §12.2 (D15): every formula of "Your numbers.", the year boundary in the device
/// calendar, missing lengths, a failed catalogue and an empty Library.
@Suite("Profile numbers (pure)")
@MainActor
struct ProfileStatsTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
    private var calendar: Calendar { KuroLocale.calendar(locale: Locale(identifier: "en_GB"), timeZone: berlin) }
    private let en = Locale(identifier: "en_GB")
    private let de = Locale(identifier: "de_DE")

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func entry(_ kind: MediaKind, _ id: Int, _ status: ListStatus, progress: Int,
                       created: Date, updated: Date? = nil) -> LibraryEntry {
        LibraryEntry(key: MediaKey(kind: kind, id: id), rowId: id, status: status, progress: progress,
                     createdAt: created, updatedAt: updated ?? created)
    }

    private func key(_ kind: MediaKind, _ id: Int) -> MediaKey { MediaKey(kind: kind, id: id) }

    @Test("Episodes and chapters: Σ min(progress, total), raw progress when the total is unknown")
    func totals() throws {
        let old = try date("2024-03-01T10:00:00Z")
        let entries = [
            entry(.anime, 1, .completed, progress: 30, created: old),   // total 24 → 24
            entry(.anime, 2, .current, progress: 7, created: old),      // total unknown → 7
            entry(.anime, 3, .planning, progress: 0, created: old),     // not counted
            entry(.manga, 10, .current, progress: 68, created: old),    // total 120 → 68
            entry(.manga, 11, .completed, progress: 200, created: old)  // total 162 → 162
        ]
        let facts: [MediaKey: ProfileTitleFacts] = [
            key(.anime, 1): .init(title: "A", total: 24, duration: 24),
            key(.anime, 2): .init(title: "B", total: nil, duration: 23),
            key(.manga, 10): .init(title: "M", total: 120),
            key(.manga, 11): .init(title: "N", total: 162)
        ]
        let stats = ProfileStats.make(entries: entries, facts: facts, catalogue: .loaded, now: old,
                                      calendar: calendar, locale: en)
        #expect(stats.episodes == ProfileStats.Total(units: 31, titles: 2))
        #expect(stats.chapters == ProfileStats.Total(units: 230, titles: 2))
        #expect(!stats.isEmpty)
    }

    @Test("Time: episodes × length; titles without a length are counted in the caveat, never padded")
    func time() throws {
        let old = try date("2024-03-01T10:00:00Z")
        let entries = [
            entry(.anime, 1, .completed, progress: 30, created: old),
            entry(.anime, 2, .current, progress: 10, created: old),
            entry(.anime, 3, .current, progress: 4, created: old),
            entry(.anime, 4, .current, progress: 2, created: old)
        ]
        let facts: [MediaKey: ProfileTitleFacts] = [
            key(.anime, 1): .init(title: "A", total: 24, duration: 24),   // 24 × 24 = 576
            key(.anime, 2): .init(title: "B", total: 12, duration: 23),   // 10 × 23 = 230
            key(.anime, 3): .init(title: "C", total: 12, duration: nil),  // missing
            key(.anime, 4): .init(title: "D", total: 12, duration: 0)     // missing
        ]
        let stats = ProfileStats.make(entries: entries, facts: facts, catalogue: .loaded, now: old,
                                      calendar: calendar, locale: en)
        #expect(stats.time == ProfileStats.Time(minutes: 806, missing: 2))
        #expect(ProfileStatsCopy.time(minutes: 806, german: false, locale: en) == "≈ 13 h")
        #expect(ProfileStatsCopy.time(minutes: 806, german: true, locale: de) == "≈ 13 Std.")
        #expect(ProfileStatsCopy.timeCaveat(missing: 2, german: false)
                == "Episodes watched × each title's episode length. 2 titles have no length and aren't counted.")
        #expect(ProfileStatsCopy.timeCaveat(missing: 0, german: true) == "Gesehene Folgen × die Folgenlänge jedes Titels.")
        #expect(ProfileStatsCopy.timeCaveat(missing: 1, german: false)
                == "Episodes watched × each title's episode length. 1 title has no length and isn't counted.")
        #expect(ProfileStatsCopy.timeCaveat(missing: 4, german: true)
                == "Gesehene Folgen × die Folgenlänge jedes Titels. 4 Titel haben keine Länge und zählen nicht mit.")
    }

    @Test("Time wording: below 48 h in hours, else days and hours; never a zero")
    func timeWording() {
        #expect(ProfileStatsCopy.time(minutes: 0, german: false, locale: en) == nil)
        #expect(ProfileStatsCopy.time(minutes: 20, german: false, locale: en) == "≈ 1 h")
        #expect(ProfileStatsCopy.time(minutes: 47 * 60, german: false, locale: en) == "≈ 47 h")
        #expect(ProfileStatsCopy.time(minutes: 48 * 60, german: false, locale: en) == "2 d 0 h")
        #expect(ProfileStatsCopy.time(minutes: 513 * 60, german: false, locale: en) == "21 d 9 h")
        #expect(ProfileStatsCopy.time(minutes: 513 * 60, german: true, locale: de) == "21 T 9 Std.")
    }

    @Test("Numbers use the reader's locale")
    func numbers() {
        #expect(ProfileStatsCopy.number(1284, locale: en) == "1,284")
        #expect(ProfileStatsCopy.number(1284, locale: de) == "1.284")
        let total = ProfileStats.Total(units: 1284, titles: 61)
        #expect(ProfileStatsCopy.episodesSpoken(total, german: false, locale: en) == "1,284 episodes across 61 anime")
        #expect(ProfileStatsCopy.episodesSpoken(total, german: true, locale: de) == "1.284 Folgen aus 61 Anime")
        #expect(ProfileStatsCopy.acrossManga(18, german: false) == "across 18 manga")
        #expect(ProfileStatsCopy.acrossManga(18, german: true) == "aus 18 Manga")
    }

    @Test("Top genres: started, completed, paused and repeating titles; top five; ties by locale order")
    func genres() throws {
        let old = try date("2024-03-01T10:00:00Z")
        let entries = [
            entry(.anime, 1, .completed, progress: 1, created: old),
            entry(.anime, 2, .current, progress: 1, created: old),
            entry(.anime, 3, .paused, progress: 1, created: old),
            entry(.anime, 4, .planning, progress: 0, created: old),   // not counted
            entry(.anime, 5, .dropped, progress: 1, created: old),    // not counted
            entry(.manga, 6, .repeating, progress: 1, created: old)
        ]
        let facts: [MediaKey: ProfileTitleFacts] = [
            key(.anime, 1): .init(title: "A", genres: ["Action", "Drama", "Drama"]),
            key(.anime, 2): .init(title: "B", genres: ["Action", "Comedy"]),
            key(.anime, 3): .init(title: "C", genres: ["Ecchi", "Fantasy", "Action"]),
            key(.anime, 4): .init(title: "D", genres: ["Horror"]),
            key(.anime, 5): .init(title: "E", genres: ["Horror"]),
            key(.manga, 6): .init(title: "F", genres: ["Drama", "Bunny"])
        ]
        let stats = ProfileStats.make(entries: entries, facts: facts, catalogue: .loaded, now: old,
                                      calendar: calendar, locale: en)
        #expect(stats.genres.map(\.name) == ["Action", "Drama", "Bunny", "Comedy", "Ecchi"])
        #expect(stats.genres.map(\.count) == [3, 2, 1, 1, 1])
        #expect(ProfileStatsCopy.genreSpoken(.init(name: "Action", count: 31), german: false) == "Action, 31 titles")
        #expect(ProfileStatsCopy.genreSpoken(.init(name: "Action", count: 31), german: true) == "Action, 31 Titel")
    }

    @Test("Your year: saved or changed in the device calendar's year; completed among them; most time")
    func year() throws {
        // 2026-01-01 00:30 in Berlin is still 2025-12-31 in UTC: the device calendar decides.
        let now = try date("2026-11-03T12:00:00Z")
        let newYearBerlin = try date("2025-12-31T23:30:00Z")
        let lastYear = try date("2025-12-31T22:30:00Z")
        let entries = [
            entry(.anime, 1, .completed, progress: 12, created: newYearBerlin),            // in 2026 (Berlin)
            entry(.anime, 2, .current, progress: 20, created: lastYear),                   // 2025 only
            entry(.anime, 3, .current, progress: 5, created: lastYear, updated: now),      // changed in 2026
            entry(.manga, 4, .completed, progress: 40, created: now)                       // in 2026
        ]
        let facts: [MediaKey: ProfileTitleFacts] = [
            key(.anime, 1): .init(title: "Frieren", total: 12, duration: 24, artwork: URL(string: "https://example.com/f.jpg")),
            key(.anime, 2): .init(title: "Long", total: 24, duration: 24),
            key(.anime, 3): .init(title: "Short", total: 12, duration: 24)
        ]
        let stats = ProfileStats.make(entries: entries, facts: facts, catalogue: .loaded, now: now,
                                      calendar: calendar, locale: en)
        let year = try #require(stats.year)
        #expect(year.year == 2026)
        #expect(year.titles == 3)
        #expect(year.completed == 2)
        #expect(year.mostTime?.key == key(.anime, 1))
        #expect(year.mostTime?.minutes == 288)
        #expect(ProfileYearCard.factLine(year, german: false) == "3 titles saved or changed · 2 of them now completed")
        #expect(ProfileYearCard.factLine(year, german: true) == "3 Titel gespeichert oder geändert · 2 davon abgeschlossen")
        #expect(ProfileStatsCopy.yearTitle(3, german: false) == "3 titles this year")
        #expect(ProfileStatsCopy.yearTitle(3, german: true) == "3 Titel dieses Jahr")
        #expect(ProfileStatsCopy.mostTime("Frieren", german: false) == "Most time: Frieren")
        #expect(ProfileStatsCopy.yearNote(2026, german: false)
                == "Kuro doesn't record finish dates, so 2026 counts titles you saved or changed this year.")
        #expect(ProfileStatsCopy.yearNote(2026, german: true)
                == "Kuro speichert kein Enddatum. 2026 zählt Titel, die du dieses Jahr gespeichert oder geändert hast.")

        // In UTC the first entry belongs to 2025.
        let utc = KuroLocale.calendar(locale: en, timeZone: try #require(TimeZone(identifier: "UTC")))
        let utcStats = ProfileStats.make(entries: entries, facts: facts, catalogue: .loaded, now: now, calendar: utc, locale: en)
        #expect(utcStats.year?.titles == 2)
    }

    @Test("Your year is hidden when nothing was saved or changed this year; completed is omitted at 0")
    func yearHidden() throws {
        let now = try date("2026-11-03T12:00:00Z")
        let old = try date("2024-05-01T12:00:00Z")
        let stats = ProfileStats.make(entries: [entry(.anime, 1, .current, progress: 3, created: old)], facts: [:],
                                      catalogue: .loaded, now: now, calendar: calendar, locale: en)
        #expect(stats.year == nil)
        let year = ProfileStats.Year(year: 2026, titles: 1, completed: 0, mostTime: nil)
        #expect(ProfileYearCard.factLine(year, german: false) == "1 title saved or changed")
    }

    @Test("A failed catalogue keeps raw progress and shows no time or genres (never zeros)")
    func failedCatalogue() throws {
        let old = try date("2024-03-01T10:00:00Z")
        let entries = [entry(.anime, 1, .completed, progress: 30, created: old)]
        let facts: [MediaKey: ProfileTitleFacts] = [key(.anime, 1): .init(title: "A", total: 24, duration: 24, genres: ["Action"])]
        for state in [ProfileCatalogueState.failed, .loading] {
            let stats = ProfileStats.make(entries: entries, facts: facts, catalogue: state, now: old,
                                          calendar: calendar, locale: en)
            #expect(stats.episodes == ProfileStats.Total(units: 30, titles: 1))
            #expect(stats.time == nil)
            #expect(stats.genres.isEmpty)
        }
    }

    @Test("Empty Library: the quiet card; no totals, no year")
    func empty() throws {
        let stats = ProfileStats.make(entries: [], facts: [:], catalogue: .loaded, now: Date(), calendar: calendar, locale: en)
        #expect(stats.isEmpty)
        #expect(stats.episodes == nil && stats.chapters == nil && stats.time == nil && stats.year == nil)
        #expect(ProfileStatsCopy.empty(german: false) == "Your numbers appear once you save a title.")
        #expect(ProfileStatsCopy.empty(german: true) == "Deine Zahlen erscheinen, sobald du einen Titel speicherst.")
    }

    @Test("Only titles not read yet are asked for again; ids go in chunks of 50")
    func missingAndChunks() throws {
        let old = try date("2024-03-01T10:00:00Z")
        let entries = [entry(.anime, 1, .current, progress: 1, created: old), entry(.manga, 1, .current, progress: 1, created: old),
                       entry(.anime, 2, .current, progress: 1, created: old)]
        #expect(ProfileStats.missingKeys(entries: entries, known: [key(.anime, 1)]) == [key(.manga, 1), key(.anime, 2)])
        let chunks = ProfileStatsSection.chunks(Array(1...120))
        #expect(chunks.map(\.count) == [50, 50, 20])
        #expect(ProfileStatsSection.chunks([]).isEmpty)
    }

    @Test("Copy: heading, summary and reminder lines in EN and DE")
    func copy() {
        #expect(ProfileStatsCopy.heading(german: false) == "Your numbers.")
        #expect(ProfileStatsCopy.heading(german: true) == "Deine Zahlen.")
        #expect(ProfileStatsCopy.summary(german: false) == "Counted on this device")
        #expect(ProfileStatsCopy.summary(german: true) == "Auf diesem Gerät gezählt")
        #expect(ProfileStatsCopy.genresSummary(german: true) == "nach Titeln auf deinen Listen")
        #expect(ProfileStatsCopy.remindersTitle(german: false) == "Release reminders")
        #expect(ProfileStatsCopy.remindersTitle(german: true) == "Erinnerungen an Neuerscheinungen")
        #expect(ProfileStatsCopy.remindersDenied(german: false) == "Notifications are off for Kuro. Turn them on in Settings.")
        #expect(ProfileStatsCopy.openSettings(german: true) == "Einstellungen öffnen")
        #expect(ProfileStatsCopy.remindersSubtitle(german: false).contains("never estimates"))
        #expect(ProfileStatsCopy.remindersSubtitle(german: true).contains("nie Schätzungen"))
    }
}
