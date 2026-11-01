import Foundation
import KuroCore
import KuroLibrary

// MARK: - Detail section policy (prototype fidelity, Task 6; spec §5.2, PROTOTYPE_SPEC.md §4 D1-D11)
// Pure rules for the one detail page: which sections exist for a title, how the franchise ladder
// becomes numbered seasons, and the status mark's words and actions. No section is shown without
// real data behind it (spec §4: a section without data is hidden, never filled with sample copy).

/// The prototype's sections, in page order (spec §5.2 table).
enum DetailSection: String, CaseIterable, Equatable, Sendable {
    case hero, story, clubPresence, seasons, progress, units, source, songs, characters, credits, betweenUs
}

/// What the page knows about a title, as counts and flags (no view state).
struct DetailInput: Equatable, Sendable {
    var kind: MediaKind = .anime
    var hasSynopsis = false
    /// An editorial hook from `detail_copy` (never sample copy).
    var hasHook = false
    /// People in the viewer's clubs who track this title.
    var clubPeopleCount = 0
    /// Entries in the proven season chain (numbered seasons and "Also in this story" extras).
    var seasonCount = 0
    var isTracked = false
    /// Unit rows loaded from the episodes/chapters table.
    var unitCount = 0
    /// A next unit exists to advance to (tracked and not caught up).
    var hasNextUnit = false
    /// The ladder names the original work (anime) or an adaptation (manga).
    var hasSource = false
    var songCount = 0
    var characterCount = 0
    /// Credit rows with a real name (original work, director, studio …).
    var creditCount = 0
    /// The viewer belongs to at least one club ("Between us." lives only inside clubs).
    var hasClubs = false
}

enum DetailSectionPolicy {
    /// The sections to render, in the prototype's order. The hero is always present.
    static func sections(for input: DetailInput) -> [DetailSection] {
        DetailSection.allCases.filter { section in
            switch section {
            case .hero: return true
            case .story: return input.hasSynopsis || input.hasHook
            case .clubPresence: return input.clubPeopleCount > 0
            // One entry is not a series: no "Seasons" heading for a single title.
            case .seasons: return input.seasonCount > 1
            // Untracked: the hero says "Not in your list" with Add; no progress until it is saved.
            case .progress: return input.isTracked
            case .units: return input.unitCount > 0 || showsUpNext(for: input)
            case .source: return input.hasSource
            case .songs: return input.songCount > 0
            case .characters: return input.characterCount > 0
            case .credits: return input.creditCount > 0
            case .betweenUs: return input.hasClubs
            }
        }
    }

    /// The raised "Up next" row with its +1 key: only for a tracked title with a unit still ahead.
    static func showsUpNext(for input: DetailInput) -> Bool {
        input.isTracked && input.hasNextUnit
    }

    /// The next unit to advance to, or nil when caught up: a known total is reached, or (airing) the
    /// next unit has not aired yet (`airedThrough` is the last aired unit). Never offers a future unit.
    static func nextUnit(progress: Int, total: Int?, airedThrough: Int? = nil) -> Int? {
        let next = max(1, progress + 1)
        if let total, total > 0, next > total { return nil }
        if let airedThrough, next > airedThrough { return nil }
        return next
    }

    /// The last aired episode of an airing title: the episode before its next scheduled airing.
    /// nil when nothing is scheduled ahead (no ceiling is invented).
    static func airedThrough(status: String?, nextEpisode: Int?, nextAiringAt: Date?, now: Date = Date()) -> Int? {
        guard status?.uppercased() == "RELEASING", let nextEpisode, nextEpisode > 0,
              let nextAiringAt, nextAiringAt > now else { return nil }
        return nextEpisode - 1
    }
}

// MARK: - Seasons from the franchise ladder

/// One entry of the season chain (from `get_media_ladder` prequels/sequels, or the open title).
struct LadderChainEntry: Equatable, Sendable {
    let mediaId: Int
    let title: String
    let format: String?
    let year: Int?
    let coverImage: String?

    init(mediaId: Int, title: String, format: String?, year: Int? = nil, coverImage: String? = nil) {
        self.mediaId = mediaId
        self.title = title
        self.format = format
        self.year = year
        self.coverImage = coverImage
    }

    init(_ item: MediaLadderItem) {
        self.init(mediaId: item.mediaId, title: item.title, format: item.format, year: item.year,
                  coverImage: item.coverImage)
    }

    /// TV and ONA entries are a story's seasons; films, OVAs and specials are not numbered.
    var isSeasonFormat: Bool {
        switch format?.uppercased() {
        case "TV", "ONA", "TV_SHORT": return true
        default: return false
        }
    }
}

/// A season tile: numbered ("2"), a split-cour part ("Part 2") or an extra ("Film").
struct LadderSeason: Equatable, Identifiable, Sendable {
    let entry: LadderChainEntry
    /// "Season N"; nil for a split-cour part and for extras.
    let number: Int?
    /// "Part 2" for a split-cour entry, which keeps its own label.
    let partLabel: String?
    let isCurrent: Bool

    var id: Int { entry.mediaId }
}

enum LadderSeasons {
    /// Seasons of an ordered chain (oldest first). TV/ONA entries are numbered in order; a split-cour
    /// "Part N" (N ≥ 2) keeps its label and takes no new number; films, OVAs and specials go to
    /// `extras`, unnumbered.
    static func seasons(chain: [LadderChainEntry], current: Int) -> (numbered: [LadderSeason], extras: [LadderSeason]) {
        var numbered: [LadderSeason] = []
        var extras: [LadderSeason] = []
        var nextNumber = 1
        var seen = Set<Int>()
        for entry in chain where seen.insert(entry.mediaId).inserted {
            let isCurrent = entry.mediaId == current
            guard entry.isSeasonFormat else {
                extras.append(LadderSeason(entry: entry, number: nil, partLabel: nil, isCurrent: isCurrent))
                continue
            }
            if let part = partNumber(in: entry.title), part >= 2, !numbered.isEmpty {
                numbered.append(LadderSeason(entry: entry, number: nil, partLabel: "Part \(part)", isCurrent: isCurrent))
            } else {
                numbered.append(LadderSeason(entry: entry, number: nextNumber, partLabel: nil, isCurrent: isCurrent))
                nextNumber += 1
            }
        }
        return (numbered, extras)
    }

    /// Seasons from one ladder answer: its prequels, the open title, then its sequels (the RPC orders
    /// both by year). Only a proven chain may be numbered; see `chain(walking:)` for the page.
    static func seasons(from ladder: MediaLadderResponse, current: LadderChainEntry) -> (numbered: [LadderSeason], extras: [LadderSeason]) {
        let chain = ladder.prequels.map(LadderChainEntry.init) + [current] + ladder.sequels.map(LadderChainEntry.init)
        return seasons(chain: chain, current: current.mediaId)
    }

    /// The neighbour a chain walk follows: a season-format entry first (the nearest by year), so a film
    /// between two seasons is reached as an extra, not as the path.
    static func step(_ items: [MediaLadderItem], excluding seen: Set<Int>, towardsOlder: Bool) -> MediaLadderItem? {
        let candidates = items.filter { !seen.contains($0.mediaId) && $0.mediaType.uppercased() == "ANIME" }
        let seasonal = candidates.filter { LadderChainEntry($0).isSeasonFormat }
        let pool = seasonal.isEmpty ? candidates : seasonal
        // Nearest neighbour: the newest prequel, the oldest sequel (the RPC lists by year ascending).
        return towardsOlder ? pool.last : pool.first
    }

    /// The season number of the open title, when it has one and the chain has more than one season.
    static func currentNumber(_ numbered: [LadderSeason]) -> Int? {
        guard numbered.filter({ $0.number != nil }).count > 1 else { return nil }
        return numbered.first(where: \.isCurrent)?.number
    }

    /// "Part 2" / "2nd Cour" / "Cour 2" in a title; nil otherwise.
    static func partNumber(in title: String) -> Int? {
        let lower = title.lowercased()
        let patterns = [#"\bpart\s*(\d+)\b"#, #"\bcour\s*(\d+)\b"#, #"\b(\d+)(?:st|nd|rd|th)\s+(?:part|cour)\b"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: lower),
                  let value = Int(lower[range]) else { continue }
            return value
        }
        return nil
    }
}

// MARK: - Status mark

/// The actions folded into the hero status mark (spec §3b: nothing live users have today is removed).
enum DetailStatusAction: String, CaseIterable, Equatable, Sendable {
    case listSettings, favourite, verdict, providers, addToClub, share
}

enum DetailStatusCopy {
    /// "Watching" / "Reading" / … for a tracked entry; "Not in your list" otherwise.
    static func label(status: ListStatus?, kind: MediaKind, german: Bool) -> String {
        guard let status else { return german ? "Nicht in deiner Liste" : "Not in your list" }
        switch status {
        case .current: return kind == .manga ? (german ? "Liest du" : "Reading") : (german ? "Schaust du" : "Watching")
        case .planning: return german ? "Vorgemerkt" : "Planned"
        case .completed: return german ? "Abgeschlossen" : "Completed"
        case .dropped: return german ? "Abgebrochen" : "Dropped"
        case .paused: return german ? "Pausiert" : "Paused"
        case .repeating: return kind == .manga ? (german ? "Liest du erneut" : "Rereading") : (german ? "Schaust du erneut" : "Rewatching")
        }
    }

    /// The menu under the mark, in order. List settings is also the mark's own tap.
    static func actions(isTracked: Bool) -> [DetailStatusAction] {
        [.listSettings, .favourite, .verdict, .providers, .addToClub, .share]
    }

    static func actionTitle(_ action: DetailStatusAction, isTracked: Bool, kind: MediaKind, german: Bool) -> String {
        switch action {
        case .listSettings:
            return isTracked ? (german ? "Listeneinstellungen" : "List settings")
                             : (german ? "Zur Liste hinzufügen" : "Add to your list")
        case .favourite:
            // The live heart: saves to Planned, or removes a saved title (the legacy dock's toggle).
            return isTracked ? (german ? "Gemerkt · entfernen" : "Saved · remove")
                             : (german ? "Merken" : "Save")
        case .verdict: return german ? "Urteil" : "Verdict"
        case .providers:
            return kind == .manga ? (german ? "Wo lesen" : "Where to read") : (german ? "Wo schauen" : "Where to watch")
        case .addToClub: return german ? "Zu einem Club hinzufügen" : "Add to a club"
        case .share: return german ? "Teilen" : "Share"
        }
    }
}

// MARK: - Page copy (PROTOTYPE_SPEC.md §7.1)

enum DetailPageCopy {
    static func kindKicker(_ kind: MediaKind, german: Bool) -> String { kind == .manga ? "Manga" : "Anime" }

    static func seasonEyebrow(_ number: Int, german: Bool) -> String { german ? "Staffel \(number)" : "Season \(number)" }

    static func aboutTitle(isSeason: Bool, german: Bool) -> String {
        isSeason ? (german ? "Über diese Staffel" : "About this season")
                 : (german ? "Über diese Geschichte" : "About this story")
    }

    static func clubPeople(_ count: Int, german: Bool) -> String {
        if german { return count == 1 ? "1 Person aus deinen Clubs" : "\(count) Personen aus deinen Clubs" }
        return count == 1 ? "1 person in your clubs" : "\(count) people in your clubs"
    }

    static func seasonsCount(_ count: Int, german: Bool) -> String {
        if german { return count == 1 ? "1 Staffel" : "\(count) Staffeln" }
        return count == 1 ? "1 season" : "\(count) seasons"
    }

    static func progressLabel(season: Int?, german: Bool) -> String {
        guard let season else { return german ? "Dein Fortschritt" : "Your progress" }
        return german ? "Fortschritt Staffel \(season)" : "Season \(season) progress"
    }

    /// The caption under the progress label: the real total, or that it is still running.
    static func progressCaption(total: Int?, releasing: Bool, german: Bool) -> String? {
        if let total, total > 0 {
            if german { return total == 1 ? "1 Folge" : "\(total) Folgen" }
            return total == 1 ? "1 episode" : "\(total) episodes"
        }
        guard releasing else { return nil }
        return german ? "Laufend · Gesamtzahl unbekannt" : "Ongoing · total unknown"
    }

    static func episode(_ number: Int, german: Bool) -> String { german ? "Folge \(number)" : "Episode \(number)" }

    static func formatWord(_ format: String?, german: Bool) -> String {
        switch format?.uppercased() {
        case "MOVIE": return "Film"
        case "OVA": return "OVA"
        case "SPECIAL": return german ? "Special" : "Special"
        case "MUSIC": return german ? "Musik" : "Music"
        case "ONA": return "ONA"
        case "TV", "TV_SHORT": return "TV"
        default: return german ? "Weiteres" : "Extra"
        }
    }

    static func sourceExplore(format: String?, german: Bool) -> String {
        switch format?.uppercased() {
        case "NOVEL", "LIGHT_NOVEL": return german ? "Zum Roman" : "Explore the novel"
        default: return german ? "Zum Manga" : "Explore the manga"
        }
    }
}
