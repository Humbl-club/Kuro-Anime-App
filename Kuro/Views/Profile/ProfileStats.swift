import Foundation
import KuroCore
import KuroLibrary

// MARK: - Profile numbers (details-songs spec §12.2, D15; pure, tested in ProfileStatsTests)
// Everything is counted on the device from the current account's Library entries plus the catalogue
// facts the section read for them. Nothing is padded or estimated:
//   - Episodes / Chapters: Σ min(progress, total ?? progress) over entries with progress > 0.
//   - Time: Σ min(progress, total) × the title's episode length; titles without a length are counted
//     in the caveat, never filled in.
//   - Top genres: titles (current, completed, repeating, paused) per catalogue genre, top five, ties by
//     the reader's locale.
//   - Your year: entries saved or changed (`createdAt` / `updatedAt`) in the device calendar's year;
//     Kuro stores no finish date, so the card never says "finished".
// A catalogue failure keeps the Library-only numbers (raw progress) and marks time and genres failed.

/// The catalogue facts one Library title contributes (card projection values).
nonisolated struct ProfileTitleFacts: Equatable, Sendable {
    var title: String
    /// Episodes (anime) or chapters (manga) in the catalogue; nil when unknown or still running.
    var total: Int?
    /// Minutes per episode (anime only); nil or 0 means "no length".
    var duration: Int?
    var genres: [String]
    /// Banner first, then cover (the year card's artwork and material).
    var artwork: URL?

    init(title: String, total: Int? = nil, duration: Int? = nil, genres: [String] = [], artwork: URL? = nil) {
        self.title = title
        self.total = total
        self.duration = duration
        self.genres = genres
        self.artwork = artwork
    }
}

/// The catalogue read behind the section.
nonisolated enum ProfileCatalogueState: Equatable, Sendable {
    /// Not read yet (the section shows its skeletons for time and genres).
    case loading
    /// Read; `facts` holds what came back (a title missing from it simply has no facts).
    case loaded
    /// The read failed with nothing to show: time and genres show the inline failed state.
    case failed
}

nonisolated struct ProfileStats: Equatable, Sendable {
    nonisolated struct Total: Equatable, Sendable {
        /// Units done (episodes or chapters).
        let units: Int
        /// Titles with progress > 0.
        let titles: Int
    }

    nonisolated struct Time: Equatable, Sendable {
        let minutes: Int
        /// Anime with progress and no episode length (not counted).
        let missing: Int
    }

    nonisolated struct Genre: Equatable, Sendable {
        let name: String
        let count: Int
    }

    nonisolated struct Year: Equatable, Sendable {
        let year: Int
        /// Entries saved or changed in `year`.
        let titles: Int
        /// Of them, completed now.
        let completed: Int
        /// The anime in `year` with the most watched minutes (nil when no length is known).
        let mostTime: MostTime?
    }

    nonisolated struct MostTime: Equatable, Sendable {
        let key: MediaKey
        let title: String
        let minutes: Int
        let artwork: URL?
    }

    /// Anime totals; nil when no anime has progress.
    let episodes: Total?
    /// Manga totals; nil when no manga has progress.
    let chapters: Total?
    /// Nil while the catalogue is loading or failed, or when no anime has progress.
    let time: Time?
    /// Empty while the catalogue is loading or failed, or when no counted title has a genre.
    let genres: [Genre]
    /// Nil when nothing was saved or changed this year.
    let year: Year?
    /// The Library holds no entries at all (the quiet card).
    let isEmpty: Bool

    static let genreLimit = 5
    /// Statuses whose titles count toward the genres ("started, completed, paused, repeating").
    static let genreStatuses: Set<ListStatus> = [.current, .completed, .repeating, .paused]

    /// Units of `entry` that count: its progress, capped at the catalogue total when one is known.
    static func countedUnits(progress: Int, total: Int?) -> Int {
        guard progress > 0 else { return 0 }
        guard let total, total > 0 else { return progress }
        return min(progress, total)
    }

    static func make(
        entries: [LibraryEntry],
        facts: [MediaKey: ProfileTitleFacts],
        catalogue: ProfileCatalogueState,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> ProfileStats {
        // Library-only totals: a failed (or loading) catalogue still caps nothing, so raw progress.
        let useFacts = catalogue == .loaded
        func fact(_ key: MediaKey) -> ProfileTitleFacts? { useFacts ? facts[key] : nil }

        let anime = entries.filter { $0.key.kind == .anime && $0.progress > 0 }
        let manga = entries.filter { $0.key.kind == .manga && $0.progress > 0 }
        let episodes = anime.isEmpty ? nil : Total(
            units: anime.reduce(0) { $0 + countedUnits(progress: $1.progress, total: fact($1.key)?.total) },
            titles: anime.count)
        let chapters = manga.isEmpty ? nil : Total(
            units: manga.reduce(0) { $0 + countedUnits(progress: $1.progress, total: fact($1.key)?.total) },
            titles: manga.count)

        var time: Time?
        if useFacts, !anime.isEmpty {
            var minutes = 0
            var missing = 0
            for entry in anime {
                if let length = facts[entry.key]?.duration, length > 0 {
                    minutes += countedUnits(progress: entry.progress, total: facts[entry.key]?.total) * length
                } else {
                    missing += 1
                }
            }
            time = Time(minutes: minutes, missing: missing)
        }

        var genres: [Genre] = []
        if useFacts {
            var counts: [String: Int] = [:]
            for entry in entries where genreStatuses.contains(entry.status) {
                for genre in Set(facts[entry.key]?.genres ?? []) where !genre.isEmpty {
                    counts[genre, default: 0] += 1
                }
            }
            genres = counts
                .map { Genre(name: $0.key, count: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    return lhs.name.compare(rhs.name, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending
                }
            genres = Array(genres.prefix(genreLimit))
        }

        let currentYear = calendar.component(.year, from: now)
        let inYear = entries.filter {
            calendar.component(.year, from: $0.createdAt) == currentYear
                || calendar.component(.year, from: $0.updatedAt) == currentYear
        }
        var year: Year?
        if !inYear.isEmpty {
            var most: MostTime?
            if useFacts {
                for entry in inYear where entry.key.kind == .anime && entry.progress > 0 {
                    guard let info = facts[entry.key], let length = info.duration, length > 0 else { continue }
                    let minutes = countedUnits(progress: entry.progress, total: info.total) * length
                    guard minutes > 0 else { continue }
                    if let best = most, best.minutes > minutes || (best.minutes == minutes && best.key.id < entry.key.id) {
                        continue
                    }
                    most = MostTime(key: entry.key, title: info.title, minutes: minutes, artwork: info.artwork)
                }
            }
            year = Year(year: currentYear, titles: inYear.count,
                        completed: inYear.filter { $0.status == .completed }.count, mostTime: most)
        }

        return ProfileStats(episodes: episodes, chapters: chapters, time: time, genres: genres, year: year,
                            isEmpty: entries.isEmpty)
    }

    /// The keys whose catalogue facts the section still needs (only missing ones are read again).
    static func missingKeys(entries: [LibraryEntry], known: Set<MediaKey>) -> [MediaKey] {
        var seen = Set<MediaKey>()
        return entries.compactMap { entry in
            guard !known.contains(entry.key), seen.insert(entry.key).inserted else { return nil }
            return entry.key
        }
    }
}
