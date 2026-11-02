import Foundation
import KuroCore
import KuroLibrary

// MARK: - Folio: the Collection lists (spec D9, rulebook §14.4)
// The vocabulary and pure rules of the lists. Rows come from the Collection feed (title, cover, totals)
// joined with the Library store (status, progress, rating: the one tracking authority) and the
// release schedule (`ReleasesStore`). Nothing here reads a network or writes tracking.

/// The status words of the strip. Watching/Reading also holds rewatches; Paused and Dropped are secondary.
enum FolioStatus: String, CaseIterable, Identifiable, Sendable {
    case watching
    case planned
    case completed
    case paused
    case dropped

    var id: String { rawValue }

    /// Library statuses the word covers.
    var listStatuses: Set<ListStatus> {
        switch self {
        case .watching: return [.current, .repeating]
        case .planned: return [.planning]
        case .completed: return [.completed]
        case .paused: return [.paused]
        case .dropped: return [.dropped]
        }
    }

    /// The status a batch change writes, and the feed's server-side filter.
    var listStatus: ListStatus {
        switch self {
        case .watching: return .current
        case .planned: return .planning
        case .completed: return .completed
        case .paused: return .paused
        case .dropped: return .dropped
        }
    }

    init(listStatus: ListStatus) {
        switch listStatus {
        case .current, .repeating: self = .watching
        case .planning: self = .planned
        case .completed: self = .completed
        case .paused: self = .paused
        case .dropped: self = .dropped
        }
    }

    /// The word on the strip and in the batch dialog: "Watching" / "Reading" / "Schaue ich" / "Lese ich".
    func title(medium: MediaKind, german: Bool) -> String {
        switch (self, german) {
        case (.watching, false): return medium == .manga ? "Reading" : "Watching"
        case (.watching, true): return medium == .manga ? "Lese ich" : "Schaue ich"
        case (.planned, false): return "Planned"
        case (.planned, true): return "Geplant"
        case (.completed, false): return "Completed"
        case (.completed, true): return "Abgeschlossen"
        case (.paused, false): return "Paused"
        case (.paused, true): return "Pausiert"
        case (.dropped, false): return "Dropped"
        case (.dropped, true): return "Abgebrochen"
        }
    }

    /// One honest line when the selected status has no titles.
    func emptyLine(medium: MediaKind, german: Bool) -> String {
        let anime = medium == .anime
        switch (self, german) {
        case (.watching, false): return anime ? "Nothing you're watching right now." : "Nothing you're reading right now."
        case (.watching, true): return anime ? "Gerade schaust du nichts." : "Gerade liest du nichts."
        case (.planned, false): return "Nothing planned yet."
        case (.planned, true): return "Noch nichts geplant."
        case (.completed, false): return "Nothing completed yet."
        case (.completed, true): return "Noch nichts abgeschlossen."
        case (.paused, false): return "Nothing paused."
        case (.paused, true): return "Nichts pausiert."
        case (.dropped, false): return "Nothing dropped."
        case (.dropped, true): return "Nichts abgebrochen."
        }
    }
}

/// Sort words (never icons alone).
enum FolioSort: String, CaseIterable, Identifiable, Sendable {
    case recent
    case title
    case score
    case nextRelease

    var id: String { rawValue }

    func title(german: Bool) -> String {
        switch (self, german) {
        case (.recent, false): return "Recent"
        case (.recent, true): return "Zuletzt"
        case (.title, false): return "Title"
        case (.title, true): return "Titel"
        case (.score, false): return "Score"
        case (.score, true): return "Wertung"
        case (.nextRelease, false): return "Next release"
        case (.nextRelease, true): return "Nächster Termin"
        }
    }
}

/// The two densities of one list.
enum FolioDensity: String, CaseIterable, Identifiable, Sendable {
    /// Equal manga covers / shallow anime scenes, adaptive columns.
    case shelf
    /// 64 pt rows: thumb, title, progress numeral, advance key, next release.
    case index

    var id: String { rawValue }

    func title(german: Bool) -> String {
        switch (self, german) {
        case (.shelf, false): return "Shelf"
        case (.shelf, true): return "Regal"
        case (.index, false): return "Index"
        case (.index, true): return "Liste"
        }
    }
}

/// Completed-only refinement (the verdict a title still needs is a real task, not decoration).
enum FolioVerdictFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unsorted
    case masterpiece
    case okay
    case bad

    var id: String { rawValue }

    func title(german: Bool) -> String {
        switch self {
        case .all: return german ? "Alle" : "All"
        case .unsorted: return german ? "Ohne Urteil" : "Unsorted"
        case .masterpiece: return Verdict.masterpiece.name(german: german)
        case .okay: return Verdict.okay.name(german: german)
        case .bad: return Verdict.bad.name(german: german)
        }
    }

    func includes(_ verdict: Verdict?) -> Bool {
        switch self {
        case .all: return true
        case .unsorted: return verdict == nil
        case .masterpiece: return verdict == .masterpiece
        case .okay: return verdict == .okay
        case .bad: return verdict == .bad
        }
    }
}

extension Verdict {
    func name(german: Bool) -> String { german ? displayNameDE : displayName }
}

/// What the advance key of a row shows (mapped onto `KuroAdvanceKey.Phase` by the view).
enum FolioKeyPhase: Equatable, Sendable {
    case advance
    case caughtUp
    case needsChoice
    case pending
}

/// One row of a list: the catalogue card, the Library entry and the next known release.
struct FolioItem: Identifiable {
    let media: Media
    let entry: LibraryEntry
    /// Progress as displayed (the durable pending position when a +1 is still on its way).
    let progress: Int
    let next: ReleaseScheduleItem?
    let banner: String?

    var id: String { media.stableKey }
    var key: MediaKey { entry.key }
    var status: FolioStatus { FolioStatus(listStatus: entry.status) }
    var total: Int? { FolioPolicy.total(of: media) }
}

/// The lists' pure rules (tested in `KuroTests/ProfileLaneTests.swift`).
enum FolioPolicy {
    /// The advance key's face, as the prototype keys its media (plan Task 9; LANE_AMENDMENTS 4): the
    /// light raised key on anime, the solid manga-leaf key (`.dark`, `#2b342e`, 38 × 38, radius 6,
    /// ink `#f8faf7`) on manga. The `#444a47 → #2c322f` gradient is not used on Poster screens. Folio
    /// rows have no artwork material, so neither uses `.material`.
    static func keyStyle(for medium: MediaKind) -> KuroAdvanceKey.Style {
        medium == .manga ? .dark : .light
    }

    /// The unit total for the medium, or nil when unknown (never 0; rulebook §10).
    static func total(of media: Media) -> Int? {
        let value = media.kind == .manga ? media.chapters : media.episodes
        guard let value, value > 0 else { return nil }
        return value
    }

    /// Titles per status word for one medium, from the whole Library (not a loaded page).
    static func counts(_ entries: [LibraryEntry], medium: MediaKind) -> [FolioStatus: Int] {
        var counts: [FolioStatus: Int] = [:]
        for entry in entries where entry.key.kind == medium {
            counts[FolioStatus(listStatus: entry.status), default: 0] += 1
        }
        return counts
    }

    /// Case- and diacritic-insensitive title match; an empty query matches everything.
    static func matches(_ item: FolioItem, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return item.media.title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The order of a list. `recent` keeps the feed order (last change first). `score` uses the
    /// user's rating, then the catalogue score. `nextRelease` puts dated titles first (soonest first),
    /// then undated ones in feed order.
    static func sorted(_ items: [FolioItem], by sort: FolioSort) -> [FolioItem] {
        let indexed = Array(items.enumerated())
        func feedOrder(_ a: (offset: Int, element: FolioItem), _ b: (offset: Int, element: FolioItem)) -> Bool {
            a.offset < b.offset
        }
        switch sort {
        case .recent:
            return items
        case .title:
            return indexed.sorted { a, b in
                let order = a.element.media.title.localizedStandardCompare(b.element.media.title)
                return order == .orderedSame ? feedOrder(a, b) : order == .orderedAscending
            }.map(\.element)
        case .score:
            return indexed.sorted { a, b in
                let ua = a.element.entry.rating?.value ?? 0, ub = b.element.entry.rating?.value ?? 0
                if ua != ub { return ua > ub }
                let ca = a.element.media.rating ?? 0, cb = b.element.media.rating ?? 0
                if ca != cb { return ca > cb }
                return feedOrder(a, b)
            }.map(\.element)
        case .nextRelease:
            return indexed.sorted { a, b in
                // Only a displayable date ranks: a hidden low-confidence estimate sorts as undated.
                switch (a.element.next.flatMap { $0.isDisplayable ? $0.releaseAt : nil },
                        b.element.next.flatMap { $0.isDisplayable ? $0.releaseAt : nil }) {
                case let (l?, r?) where l != r: return l < r
                case (.some, nil): return true
                case (nil, .some): return false
                default: return feedOrder(a, b)
                }
            }.map(\.element)
        }
    }

    /// The key a row shows, or nil when the status has no advance (Planned, Completed, Paused, Dropped).
    static func keyPhase(status: ListStatus, progress: Int, total: Int?, needsChoice: Bool, isPending: Bool) -> FolioKeyPhase? {
        guard status == .current || status == .repeating else { return nil }
        if isPending { return .pending }
        if let total, progress >= total { return .caughtUp }
        if needsChoice { return .needsChoice }
        return .advance
    }

    /// Whether a +1 from `progress` may be sent: never past a known total.
    static func mayAdvance(progress: Int, total: Int?) -> Bool {
        guard let total else { return true }
        return progress < total
    }

    /// "7 / 12", or "7" when the total is unknown, or nil before the first unit.
    static func progressNumeral(progress: Int, total: Int?) -> String? {
        if let total { return "\(progress) / \(total)" }
        return progress > 0 ? "\(progress)" : nil
    }

    /// Short unit word: "Ep." / "F." (anime), "Ch." / "Kap." (manga).
    static func unitShort(_ medium: MediaKind, german: Bool) -> String {
        switch (medium, german) {
        case (.anime, false): return "Ep."
        case (.anime, true): return "F."
        case (.manga, false): return "Ch."
        case (.manga, true): return "Kap."
        }
    }

    /// "Ep. 7 / 12" / "Kap. 141": the position line under a title, nil before the first unit with no total.
    static func positionLine(medium: MediaKind, progress: Int, total: Int?, german: Bool) -> String? {
        guard let numeral = progressNumeral(progress: progress, total: total) else { return nil }
        return "\(unitShort(medium, german: german)) \(numeral)"
    }

    /// "Ch. 141" / "Kap. 141": the short position under a Shelf cover (no total: the narrow cell keeps
    /// room for the 44 pt key; the total stays in the VoiceOver label). Nil before the first unit.
    static func shelfPositionLine(medium: MediaKind, progress: Int, german: Bool) -> String? {
        guard progress > 0 else { return nil }
        return "\(unitShort(medium, german: german)) \(progress)"
    }

    /// Shelf columns from the content width. Manga: equal covers of at least 96 pt, at least two
    /// columns (rulebook §6). Anime: shallow scenes of at least 300 pt, one column on a phone. At
    /// accessibility text sizes manga uses two columns and anime one.
    static func shelfColumns(width: CGFloat, medium: MediaKind, accessibilitySize: Bool, spacing: CGFloat = 12) -> Int {
        let usable = max(0, width)
        switch medium {
        case .manga:
            if accessibilitySize { return 2 }
            return max(2, Int((usable + spacing) / (96 + spacing)))
        case .anime:
            if accessibilitySize { return 1 }
            return max(1, Int((usable + spacing) / (300 + spacing)))
        }
    }

    /// Extra feed pages (of 120) a search or a non-recent sort reads before it stops and says so.
    static let localOrderingPageLimit = 12

    /// The outer gutter: 20 pt, 16 pt at a content width of 320 pt or less (rulebook §5).
    static func gutter(forWidth width: CGFloat) -> CGFloat {
        width <= 320 ? 16 : 20
    }
}

/// EN/DE copy of the lists that is not a status or sort word.
enum FolioCopy {
    static func searchPlaceholder(medium: MediaKind, german: Bool) -> String {
        switch (medium, german) {
        case (.anime, false): return "Search your anime"
        case (.anime, true): return "Deine Anime durchsuchen"
        case (.manga, false): return "Search your manga"
        case (.manga, true): return "Deine Manga durchsuchen"
        }
    }

    static func noMatches(_ query: String, german: Bool) -> String {
        german ? "Keine Titel passen zu „\(query)“." : "No titles match '\(query)'."
    }

    static func selectedCount(_ count: Int, german: Bool) -> String {
        german ? "\(count) ausgewählt" : "\(count) selected"
    }

    static func updated(_ count: Int, of total: Int, german: Bool) -> String {
        if count == total {
            return german ? (total == 1 ? "1 Titel geändert." : "\(total) Titel geändert.")
                          : (total == 1 ? "1 title updated." : "\(total) titles updated.")
        }
        if count == 0 {
            return german ? "Nichts geändert. Prüf deine Verbindung." : "Nothing changed. Check your connection."
        }
        return german ? "\(count) von \(total) geändert. Versuch den Rest erneut."
                      : "\(count) of \(total) updated. Try the rest again."
    }

    static func removed(_ count: Int, of total: Int, german: Bool) -> String {
        if count == total {
            return german ? (total == 1 ? "1 Titel entfernt." : "\(total) Titel entfernt.")
                          : (total == 1 ? "1 title removed." : "\(total) titles removed.")
        }
        if count == 0 {
            return german ? "Nichts entfernt. Prüf deine Verbindung." : "Nothing removed. Check your connection."
        }
        return german ? "\(count) von \(total) entfernt. Versuch den Rest erneut."
                      : "\(count) of \(total) removed. Try the rest again."
    }

    /// "Ep. 8 marked." / "F. 8 markiert."
    static func advanced(medium: MediaKind, to unit: Int, german: Bool) -> String {
        german ? "\(FolioPolicy.unitShort(medium, german: true)) \(unit) markiert."
               : "\(FolioPolicy.unitShort(medium, german: false)) \(unit) marked."
    }

    static func undoTitle(german: Bool) -> String { german ? "Rückgängig" : "Undo" }

    static func advanceFailed(german: Bool) -> String {
        german ? "Fortschritt nicht gespeichert. Versuch es erneut." : "Progress wasn't saved. Try again."
    }

    static func undoFailed(german: Bool) -> String {
        german ? "Konnte nicht rückgängig gemacht werden." : "Couldn't undo that."
    }

    /// The +1 is already being sent and has no receipt yet, so it cannot be replaced.
    static func undoInFlight(german: Bool) -> String {
        german ? "Diese Speicherung ist schon unterwegs. Versuch es gleich noch einmal."
               : "That save is already on its way. Try again in a moment."
    }

    /// The bounded read for search or sort stopped with titles still unread.
    static func showingFirst(_ count: Int, german: Bool) -> String {
        german ? "Berücksichtigt nur deine ersten \(count) Titel."
               : "Covers your first \(count) titles only."
    }

    static func needsChoice(german: Bool) -> String {
        german ? "Wähle den nächsten Teil in den Details." : "Choose the next episode or chapter in its details."
    }
}
