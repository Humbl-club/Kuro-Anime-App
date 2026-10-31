import Foundation
import KuroCore
import KuroLibrary

// MARK: - Typed identity at the view boundary

extension MediaDisplayable {
    /// Typed Library identity of this title (anime 7 and manga 7 are different keys).
    var libraryKey: MediaKey { MediaKey(kind: kind, id: id) }
}

extension MediaKey {
    /// Typed identity for the free-form media type strings some views carry ("anime", "ANIME",
    /// "manga"); nil for anything else, so anime and manga with equal ids never mix.
    init?(mediaType: String, id: Int) {
        switch mediaType.lowercased() {
        case "anime": self.init(kind: .anime, id: id)
        case "manga": self.init(kind: .manga, id: id)
        default: return nil
        }
    }
}

// MARK: - Library writes shared by several views

/// Typed-key adapters from the views to `LibraryActions`, the ONE writer mapping over `LibraryStore`
/// (E6c2 ruling, G2/G6/G7; E8: no view writes the store directly): its per-title double-tap guard, its
/// account checks and its result banners (`BannerCenter`) apply to every view that writes through
/// here. Follow-up effects (airing reminders, Collection pages) belong to the store's change sinks,
/// which also run for the removal of a title the projection did not hold.
@MainActor
enum LibraryViewActions {
    /// The cards' "Quick Add (Planned)" / "Remove from List" toggle (`LibraryActions.toggleInCollection`).
    ///
    /// Runs immediately up to the store's first suspension, so the optimistic flip is visible to a
    /// caller that reads `isTracked` right after; a failure rolls it back. A second tap while the
    /// title's toggle is in flight is ignored (one write, one banner: `nil` is returned). Shows the
    /// transient banner the cards have always shown; a toggle without a session (or whose account
    /// changed while it ran) shows nothing.
    @discardableResult
    static func toggleTracked(_ key: MediaKey, actions: LibraryActions) -> Task<Void, Never>? {
        actions.toggleInCollection(mediaId: key.id, mediaType: key.kind.rawValue)
    }

    /// "+1 EP/CH" (`LibraryActions.incrementProgress`): an absolute progress-only edit of a tracked
    /// title (one past what the projection holds when the tap is handled); no other field is sent.
    /// Untracked titles are left alone.
    static func incrementProgress(_ key: MediaKey, actions: LibraryActions) async {
        await actions.incrementProgress(mediaId: key.id, mediaType: key.kind.rawValue)
    }

    /// Removes the title (`LibraryActions.removeFromList`); `true` when the removal was applied.
    @discardableResult
    static func remove(_ key: MediaKey, actions: LibraryActions) async -> Bool {
        await actions.removeFromList(mediaId: key.id, mediaType: key.kind.rawValue)
    }

    /// Marks progress from an episode/chapter row (`LibraryActions.apply`): an absolute progress-only
    /// edit; a title that is not tracked yet is created as Watching/Reading. The caller branches on the
    /// returned outcome (its own toast; no banner).
    static func markProgress(_ key: MediaKey, to progress: Int, actions: LibraryActions) async -> LibraryOutcome {
        await actions.apply(LibraryEdit(progress: .set(max(0, progress))), to: key, createIfMissing: .current)
    }
}
