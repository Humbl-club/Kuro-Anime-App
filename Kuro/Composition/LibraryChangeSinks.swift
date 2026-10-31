import KuroLibrary

#if canImport(Supabase)

// Explicit change fan-out of the Library store (no global bus). The store is created before the
// owners it notifies, so each sink is a small bridge that holds its owner weakly; the work itself
// lives in the owner (`ReleasesStore`, `CollectionStore`, `ImportsService`, `ClubsStore`).

/// Releases: an anime that is tracked after a change (re-)arms its airing reminders (an added one
/// also refreshes upcoming airings); an anime leaving the library cancels its reminders.
@MainActor
final class ReleasesLibrarySink: LibraryChangeSink {
    weak var store: ReleasesStore?

    func libraryDidChange(_ change: LibraryChange) {
        store?.libraryDidChange(change)
    }
}

/// Collection: a removal drops the card from the loaded pages; any applied change refreshes the
/// Collection card pages (`CollectionStore`; never the list projection, which the store already holds).
@MainActor
final class CollectionLibrarySink: LibraryChangeSink {
    weak var store: CollectionStore?

    func libraryDidChange(_ change: LibraryChange) {
        store?.libraryDidChange(change)
    }
}

/// Concierge: any applied change drops the concierge parse cache (`ImportsService`), whose
/// `existing_entry` copies tracking state and gates auto-apply.
@MainActor
final class ConciergeLibrarySink: LibraryChangeSink {
    weak var imports: ImportsService?

    func libraryDidChange(_ change: LibraryChange) {
        imports?.libraryDidChange(change)
    }
}

/// The sinks registered with one `LibraryStore`; `connect(...)` points them at the owners once
/// composition has built them.
@MainActor
final class HomeLibrarySink: LibraryChangeSink {
    weak var store: HomeStore?
    func libraryDidChange(_ change: LibraryChange) {
        // Flag-off / never-mounted Home does not make calls to an undeployed contract.
        if store?.bundle != nil { store?.libraryDidChange(change) }
    }
}

@MainActor
final class LibraryChangeSinks {
    let releases = ReleasesLibrarySink()
    let collection = CollectionLibrarySink()
    let concierge = ConciergeLibrarySink()
    let clubs = ClubsLibrarySink()
    let home = HomeLibrarySink()

    var all: [any LibraryChangeSink] { [releases, collection, concierge, clubs, home] }

    func connect(releases: ReleasesStore, collection: CollectionStore, imports: ImportsService, clubs: ClubsStore) {
        self.releases.store = releases
        self.collection.store = collection
        concierge.imports = imports
        self.clubs.store = clubs
    }
}
#endif
