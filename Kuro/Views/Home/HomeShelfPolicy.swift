import Foundation
import KuroCore
import KuroLibrary

/// Which Home shelf the selected medium should show.
/// Loading and failure stay on `HomeStore` and never become an empty library.
enum HomeShelfScene: Equatable {
    /// No saved titles in this medium.
    case invitation
    /// Saved, planned, paused, dropped, or completed titles, and nothing currently in progress.
    case saved
    /// At least one watching or reading title.
    case inProgress
}

/// Home cards grouped for display (see `HomeShelfPolicy.partition`).
struct HomeShelfPartition: Equatable {
    /// Watching / reading: scenes, books and +1 keys.
    var inProgress: [HomeCard] = []
    /// Planned: a quiet row that opens the title.
    var planned: [HomeCard] = []
    /// Paused: the same quiet row, labelled as paused.
    var paused: [HomeCard] = []
    /// Anything else the server sends: the same quiet row.
    var saved: [HomeCard] = []
}

enum HomeShelfPolicy {
    /// `activeListTypes` are the loaded Home cards for the selected medium.
    /// `libraryStatuses` are Library entries for that same medium only.
    static func scene(activeListTypes: [String], libraryStatuses: [ListStatus]) -> HomeShelfScene {
        if inProgress(activeListTypes) || libraryStatuses.contains(where: isInProgress) {
            return .inProgress
        }
        if !activeListTypes.isEmpty || !libraryStatuses.isEmpty {
            return .saved
        }
        return .invitation
    }

    /// Counts include Home cards and Library rows so a populated other medium stays visible.
    static func otherMediumOccupied(selectedMedium: String, animeCount: Int, mangaCount: Int) -> Bool {
        selectedMedium == "manga" ? animeCount > 0 : mangaCount > 0
    }

    /// Watching or reading (the only cards that get a scene, a book and a +1 key).
    static func isInProgress(listType: String) -> Bool {
        switch listType.uppercased() {
        case "WATCHING", "READING", "CURRENT", "REPEATING":
            return true
        default:
            return false
        }
    }

    /// The loaded Home cards split by what they may show. Planned titles never take an in-progress
    /// slot (a scene, a book or a +1 key); they get a quiet row that opens their page. Server order
    /// (most recently updated first) is kept inside each group.
    static func partition(_ cards: [HomeCard]) -> HomeShelfPartition {
        var result = HomeShelfPartition()
        for card in cards {
            if isInProgress(listType: card.listType) {
                result.inProgress.append(card)
            } else if card.listType.uppercased() == "PLANNING" {
                result.planned.append(card)
            } else if isPaused(listType: card.listType) {
                result.paused.append(card)
            } else {
                result.saved.append(card)
            }
        }
        return result
    }

    /// Paused / on hold.
    static func isPaused(listType: String) -> Bool {
        switch listType.uppercased() {
        case "PAUSED", "ON_HOLD":
            return true
        default:
            return false
        }
    }

    /// Pages `home_bundle_v1` returns per call. The Home page holds titles in progress and planned
    /// titles mixed, most recently updated first, so after an import page 1 can hold only planned ones.
    static let maxInProgressPages = 3

    /// Whether Home should fetch the next page by itself to find a title in progress: the Library
    /// says one exists in this medium (`scene == .inProgress`), none is loaded yet, more pages exist,
    /// and fewer than `maxInProgressPages` extra pages were already fetched for this shelf.
    static func shouldPageForInProgress(partition: HomeShelfPartition, scene: HomeShelfScene,
                                        nextCursor: String?, pagesFetched: Int) -> Bool {
        partition.inProgress.isEmpty
            && scene == .inProgress
            && nextCursor?.isEmpty == false
            && pagesFetched < maxInProgressPages
    }

    /// The card whose art may stand for the shelf (the medium word's picture): the first title in
    /// progress, never a planned one.
    static func leadCard(_ cards: [HomeCard]) -> HomeCard? {
        cards.first { isInProgress(listType: $0.listType) }
    }

    // MARK: Anime scenes (prototype Poster Home, PROTOTYPE_SPEC.md §4 "Scene card" / "Also watching")

    /// How many titles in progress get a scene card; the rest go to Also watching.
    static let sceneCount = 2

    /// The first `sceneCount` titles in progress become scene cards, the rest Also watching tiles.
    /// Only in-progress cards are accepted, so a planned title can never take either slot.
    static func scenes(_ cards: [HomeCard]) -> (scenes: [HomeCard], alsoWatching: [HomeCard]) {
        let active = cards.filter { isInProgress(listType: $0.listType) }
        return (Array(active.prefix(sceneCount)), Array(active.dropFirst(sceneCount)))
    }

    /// Units released so far, when Home can know it; nil when it cannot (never a guess):
    /// - a finished (or cancelled) title: its total, when the catalogue has one
    /// - a releasing title: one before the next known, non-estimated release of this title
    ///   (`ReleasesStore.nextRelease(for:)`), never more than the total
    /// - anything else (not yet released, hiatus, no schedule): unknown
    static func availableUnits(catalogueStatus: String?, total: Int?, nextUnit: Int?) -> Int? {
        let knownTotal = total.flatMap { $0 > 0 ? $0 : nil }
        switch catalogueStatus?.uppercased() {
        case "FINISHED", "CANCELLED":
            return knownTotal
        case "RELEASING":
            guard let nextUnit, nextUnit >= 1 else { return nil }
            let aired = nextUnit - 1
            return knownTotal.map { min($0, aired) } ?? aired
        default:
            return nil
        }
    }

    /// The next release's unit number for availability: the first candidate row (soonest first) that
    /// counts the unit Home tracks (episodes for anime, chapters for manga), is not an estimate and
    /// carries a whole number. A volume or season row never stands in for a chapter or an episode.
    static func nextUnitNumber(_ candidates: [ReleaseScheduleItem], medium: MediaKind) -> Int? {
        let unit: ReleaseUnitKind = medium == .manga ? .chapter : .episode
        return candidates.first { $0.unitKind == unit && $0.basis != .estimated && $0.wholeUnitNumber != nil }?
            .wholeUnitNumber
    }

    /// A released unit the reader has not reached yet, on a title that is still releasing. A finished
    /// title's backlog is not "new", so it is never counted or called new.
    static func hasNewUnit(progress: Int, available: Int?, catalogueStatus: String?) -> Bool {
        guard let available, catalogueStatus?.uppercased() == "RELEASING" else { return false }
        return progress < available
    }

    /// Caught up only when the released count is known and reached; unknown is never caught up.
    static func isKnownCaughtUp(progress: Int, available: Int?) -> Bool {
        guard let available else { return false }
        return progress >= available
    }

    /// One title in progress, as the opening line reads it.
    struct OpeningEntry: Equatable {
        let progress: Int
        /// `availableUnits(...)`: nil when Home cannot know how many units are out.
        let available: Int?
        let catalogueStatus: String?
    }

    /// What the opening line may claim, over EVERY title in progress (scenes and Also watching alike):
    /// - `newUnits`: released units the reader has not reached, summed over titles still releasing
    ///   (`max(0, available − progress)`), so "3 new episodes" counts episodes, not titles. A finished
    ///   title's backlog is never new.
    /// - `nothingNew`: no new unit anywhere, and no title that may be releasing (RELEASING, or a status
    ///   Home does not know) has an unknown released count. Unknown is never "nothing new". Finished,
    ///   hiatus and not-yet-released titles cannot have a new unit today, so they never block it.
    static func opening(_ entries: [OpeningEntry]) -> (newUnits: Int, nothingNew: Bool) {
        guard !entries.isEmpty else { return (0, false) }
        var newUnits = 0
        var unknown = false
        for entry in entries {
            let status = entry.catalogueStatus?.uppercased()
            let mayRelease = status == nil || status == "RELEASING"
            if status == "RELEASING", let available = entry.available {
                newUnits += max(0, available - entry.progress)
            } else if mayRelease, entry.available == nil {
                unknown = true
            }
        }
        return (newUnits, newUnits == 0 && !unknown)
    }

    /// A scene or Also watching key on Home: caught up when the catalogue total is reached, or when
    /// the released count is known and reached (a releasing title whose next episode has not aired).
    /// Home then shows the quiet ✓ and "Caught up", never a +1 that would mark an unaired unit.
    /// Manual edits stay on the detail page.
    static func homeKeyCaughtUp(progress: Int, total: Int?, available: Int?) -> Bool {
        if let total, total > 0, progress >= total { return true }
        return isKnownCaughtUp(progress: progress, available: available)
    }

    /// The +1 key plays its confirm / restore stamp only after a save that raised progress, for the
    /// same account presentation (ticket still current) and the medium it was pressed on.
    static func shouldStamp(before: Int, after: Int, ticketCurrent: Bool, mediumUnchanged: Bool) -> Bool {
        ticketCurrent && mediumUnchanged && after > before
    }

    /// Club notes about a title: the same id AND the same medium (a manga note never lands on an anime
    /// scene that shares the numeric id). Real display names only, in order, without repeats.
    static func clubNames(_ items: [HomeClubItem], mediaId: Int, medium: String) -> [String] {
        var names: [String] = []
        for item in items where item.mediaId == mediaId && item.mediaType.lowercased() == medium.lowercased() {
            guard let name = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }

    private static func inProgress(_ listTypes: [String]) -> Bool {
        listTypes.contains(where: isInProgress(listType:))
    }

    private static func isInProgress(_ status: ListStatus) -> Bool {
        status == .current || status == .repeating
    }
}
