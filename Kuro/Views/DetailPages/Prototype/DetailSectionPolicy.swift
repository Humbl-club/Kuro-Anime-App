import Foundation
import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Detail section policy (prototype fidelity, Task 6; spec §5.2, PROTOTYPE_SPEC.md §4 D1-D11)
// Pure rules for the one detail page: which sections exist for a title, how the franchise ladder
// becomes numbered seasons, and the status mark's words and actions. No section is shown without
// real data behind it (spec §4: a section without data is hidden, never filled with sample copy).

/// The prototype's sections, in page order (spec §5.2 table).
enum DetailSection: String, CaseIterable, Equatable, Sendable {
    case hero, story, clubPresence, seasons, progress, units, source, songs, characters, credits, moreLikeThis, betweenUs
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
    /// `social_activity_v1` (the server kill switch for title comments, reactions and the roster).
    /// Fail-closed: off unless the page passes the live flag.
    var socialEnabled = false
    /// The viewer's clubs that hold this title in a rail (`ClubsStore.clubActivityForMedia`). Shown in
    /// "Between us." whatever the social flag says, as the legacy club section was.
    var clubRailCount = 0
    /// "More like this." cards after the page's own ladder titles are dropped (details-songs §6.8).
    var similarCount = 0
    /// An upcoming release row exists (the hero's next row, the manga glance; details-songs §6.2, §7.3).
    var hasNextRelease = false
}

enum DetailSectionPolicy {
    /// The sections to render, in the prototype's order. The hero is always present.
    static func sections(for input: DetailInput) -> [DetailSection] {
        DetailSection.allCases.filter { section in
            switch section {
            case .hero: return true
            case .story: return input.hasSynopsis || input.hasHook
            // The roster comes from title activity: off with the social kill switch.
            case .clubPresence: return input.socialEnabled && input.clubPeopleCount > 0
            // One entry is not a series: no "Seasons" heading for a single title.
            case .seasons: return input.seasonCount > 1
            // Untracked: the hero says "Not in your list" with Add; no progress until it is saved.
            case .progress: return input.isTracked
            case .units: return input.unitCount > 0 || showsUpNext(for: input)
            case .source: return input.hasSource
            case .songs: return input.songCount > 0
            case .characters: return input.characterCount > 0
            case .credits: return input.creditCount > 0
            // A recommendation rail, not a primary read: hidden when the engine has nothing.
            case .moreLikeThis: return input.similarCount > 0
            // Notes need the social flag; the club-rail presence keeps the card for rail members.
            case .betweenUs: return input.hasClubs && (input.socialEnabled || input.clubRailCount > 0)
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

    /// The last aired unit of a title, as a ceiling for `nextUnit`; nil means no ceiling (a finished
    /// title is capped by its total). Never offers a unit that has not been released:
    /// - not yet released: 0 (nothing to advance to);
    /// - airing: the unit before the next scheduled one (`scheduledNext`, from the release schedule,
    ///   wins over the catalogue row); a catalogue airing time already past means `nextEpisode` has
    ///   aired; a next episode without a time is treated as not yet aired.
    static func airedThrough(status: String?, nextEpisode: Int?, nextAiringAt: Date?,
                             scheduledNext: Int? = nil, now: Date = Date()) -> Int? {
        switch status?.uppercased() {
        case "NOT_YET_RELEASED":
            return 0
        case "RELEASING":
            if let scheduledNext, scheduledNext > 0 { return scheduledNext - 1 }
            guard let nextEpisode, nextEpisode > 0 else { return nil }
            if let nextAiringAt, nextAiringAt <= now { return nextEpisode }
            return nextEpisode - 1
        default:
            return nil
        }
    }

    /// The next scheduled unit number of the given kind from a title's upcoming release rows.
    static func scheduledNext(_ upcoming: [ReleaseScheduleItem], kind: ReleaseUnitKind) -> Int? {
        upcoming.lazy
            .filter { $0.unitKind == kind }
            .compactMap { $0.unitNumber.map { Int($0.rounded(.down)) } }
            .first { $0 > 0 }
    }
}

/// The first reads a detail page waits for before it shows its lower sections (spec: branded loading,
/// no sections popping in under the reader).
enum DetailLoadPart: CaseIterable, Hashable, Sendable {
    /// The ladder walk (seasons, the source card) and, alongside it, the series bundle.
    case ladder
    /// The first episode or chapter rows.
    case units
    /// Characters, staff, studios or authors (credits_cast_v1).
    case credits
    /// Manga: the legal read links ("Read with the publisher", chapter rows).
    case links

    static let anime: Set<DetailLoadPart> = [.ladder, .units, .credits]
    static let manga: Set<DetailLoadPart> = [.ladder, .units, .credits, .links]

    /// The sections drawn under the hero: only the story while reads are pending (the skeleton holds
    /// the rest), everything once they settle.
    static func visibleSections(_ sections: [DetailSection], settled: Bool) -> [DetailSection] {
        sections.filter { $0 != .hero && (settled || $0 == .story) }
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

    nonisolated init(mediaId: Int, title: String, format: String?, year: Int? = nil, coverImage: String? = nil) {
        self.mediaId = mediaId
        self.title = title
        self.format = format
        self.year = year
        self.coverImage = coverImage
    }

    nonisolated init(_ item: MediaLadderItem) {
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

    /// True when a prequel's own ladder names the title the walk came from among its sequels. A failed
    /// read (`fetchMediaLadder` answers `.empty`) or relations not yet computed server-side fail this,
    /// so the chain stays unproven and no season numbers are shown.
    static func confirmsLink(_ prequelLadder: MediaLadderResponse, from childId: Int) -> Bool {
        prequelLadder.sequels.contains { $0.mediaId == childId }
    }

    /// Walks a title's ladder back to the first season and on to the last (at most `maxHops` each way).
    /// The chain is proven only when every backward hop was confirmed by the prequel's own ladder and
    /// the walk ended at a title without prequels; a failed or unconfirmed hop keeps the entries found
    /// so far but leaves the chain unproven (no numbers are invented).
    static func walk(from ladder: MediaLadderResponse, current: LadderChainEntry, maxHops: Int = 8,
                     fetch: (Int) async -> MediaLadderResponse) async -> (entries: [LadderChainEntry], proven: Bool) {
        var seen: Set<Int> = [current.mediaId]
        var older: [LadderChainEntry] = []
        var newer: [LadderChainEntry] = []
        var proven = false
        var node = ladder
        var child = current.mediaId
        for _ in 0..<maxHops {
            guard let previous = step(node.prequels, excluding: seen, towardsOlder: true) else { proven = true; break }
            seen.insert(previous.mediaId)
            older.insert(LadderChainEntry(previous), at: 0)
            let fetched = await fetch(previous.mediaId)
            if Task.isCancelled { return ([current], false) }
            guard confirmsLink(fetched, from: child) else { break }
            child = previous.mediaId
            node = fetched
        }
        node = ladder
        for _ in 0..<maxHops {
            guard let following = step(node.sequels, excluding: seen, towardsOlder: false) else { break }
            seen.insert(following.mediaId)
            newer.append(LadderChainEntry(following))
            node = await fetch(following.mediaId)
            if Task.isCancelled { return ([current], false) }
        }
        return (older + [current] + newer, proven)
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
            // The live heart: saves to Planned, or removes a saved title. Removing asks first when the
            // entry holds anything (`DetailRemoval`) and its toast offers Undo.
            return isTracked ? (german ? "Von der Liste entfernen" : "Remove from list")
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

// MARK: - Up next +1 (round-2 pathway blocker)

/// The detail's +1 write. A Planned title that gets its first unit becomes Watching/Reading in the same
/// edit, so Home reaches its in-progress scene (`HomeShelfPolicy`) without a trip to List settings. Every
/// other status keeps its own value (a progress-only edit, the live `markProgress` path); an untracked
/// title is created as Watching/Reading by `createIfMissing: .current`.
enum DetailAdvance {
    static func edit(status: ListStatus?, to progress: Int) -> LibraryEdit {
        let value = max(0, progress)
        guard status == .planning else { return LibraryEdit(progress: .set(value)) }
        return LibraryEdit(status: .set(.current), progress: .set(value))
    }

    /// Sends the +1 through `LibraryActions.apply`, the one view-facing writer (no new write path).
    @MainActor
    static func advance(_ key: MediaKey, from status: ListStatus?, to progress: Int,
                        actions: LibraryActions) async -> LibraryOutcome {
        await actions.apply(edit(status: status, to: progress), to: key, createIfMissing: .current)
    }

    /// The compensating edit for an applied +1: the count and, when the +1 promoted the title, its
    /// saved status. nil when nothing differs (or the change created the row: Undo removes it).
    static func undoEdit(_ change: LibraryChange) -> LibraryEdit? {
        guard let previous = change.previous, let current = change.current else { return nil }
        var edit = LibraryEdit()
        var touched = false
        if current.status != previous.status { edit.status = .set(previous.status); touched = true }
        if current.progress != previous.progress { edit.progress = .set(previous.progress); touched = true }
        return touched ? edit : nil
    }
}

// MARK: - Remove from list (round-2 pathway)

enum DetailRemoval {
    /// Removing drops progress, notes, score and verdict: ask first unless the entry is a bare plan.
    static func needsConfirmation(_ entry: LibraryEntry) -> Bool {
        entry.status != .planning || entry.progress > 0 || entry.rating != nil
            || entry.notes?.detailNonEmpty != nil || entry.verdict != nil
    }

    static func confirmTitle(german: Bool) -> String { german ? "Von deiner Liste entfernen?" : "Remove from your list?" }
    static func confirmAction(german: Bool) -> String { german ? "Entfernen" : "Remove" }
    static func confirmMessage(kind: MediaKind, german: Bool) -> String {
        german ? "Fortschritt, Wertung, Notizen und Urteil zu diesem Titel werden mit entfernt. Direkt danach kannst du es rückgängig machen."
               : "Your progress, score, notes and verdict for this title go with it. You can undo right after."
    }

    /// The Undo after a removal: every field of the removed row, re-saved (the store's own restore rule).
    static func restoreEdit(_ entry: LibraryEntry) -> LibraryEdit {
        LibraryEdit(status: .set(entry.status),
                    progress: .set(entry.progress),
                    rating: entry.rating.map { .set($0) } ?? .clear,
                    notes: entry.notes.map { .set($0) } ?? .clear,
                    verdict: entry.verdict.map { .set($0) } ?? .clear)
    }
}

// MARK: - Read failures (round-2 pathway)

enum DetailReadState {
    /// The owners answer a failed ladder read with `.empty`. A real answer always carries a coverage
    /// status (`get_media_ladder` yields at least `minimal`), so its absence means the read failed and
    /// the page shows a branded failed state with Try again instead of a page that looks complete.
    static func ladderFailed(_ ladder: MediaLadderResponse) -> Bool { ladder.coverageStatus == nil }
}

// MARK: - Story disclosure

enum DetailStoryDisclosure {
    /// Hook-led: the synopsis sits behind the disclosure. Synopsis-led: the row exists only when the
    /// text is cut or an expectation line waits behind it (never a "+" that reveals nothing).
    static func showsToggle(hasHook: Bool, truncated: Bool, hasExpectation: Bool) -> Bool {
        hasHook || truncated || hasExpectation
    }

    static func label(hasHook: Bool, expanded: Bool, about: String, german: Bool) -> String {
        if hasHook { return about }
        return expanded ? (german ? "Weniger zeigen" : "Show less") : (german ? "Mehr" : "More")
    }
}

// MARK: - Loader chrome

enum DetailLoaderChrome {
    /// The sheet's grabber (navigation contract N8): always visible on a detail journey, loading, failed
    /// or loaded, so swipe-down to collapse the journey is never a hidden gesture.
    static let dragIndicator: Visibility = .visible
}
