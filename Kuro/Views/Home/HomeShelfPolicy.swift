import Foundation
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
    /// Anything else the server sends (paused): the same quiet row.
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
            } else {
                result.saved.append(card)
            }
        }
        return result
    }

    /// The card whose art may stand for the shelf (the medium word's picture): the first title in
    /// progress, never a planned one.
    static func leadCard(_ cards: [HomeCard]) -> HomeCard? {
        cards.first { isInProgress(listType: $0.listType) }
    }

    private static func inProgress(_ listTypes: [String]) -> Bool {
        listTypes.contains(where: isInProgress(listType:))
    }

    private static func isInProgress(_ status: ListStatus) -> Bool {
        status == .current || status == .repeating
    }
}
