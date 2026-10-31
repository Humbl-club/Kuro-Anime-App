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

    private static func inProgress(_ listTypes: [String]) -> Bool {
        listTypes.contains { value in
            switch value.uppercased() {
            case "WATCHING", "READING", "CURRENT", "REPEATING":
                return true
            default:
                return false
            }
        }
    }

    private static func isInProgress(_ status: ListStatus) -> Bool {
        status == .current || status == .repeating
    }
}
