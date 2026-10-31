import KuroLibrary

#if canImport(Supabase)

/// Clubs (G2): a club bundle copies the caller's tracking of each rail title (`my_status`,
/// `my_progress`, `my_rating`). After an applied list change of a title, the current account's cached
/// bundles holding it are re-read (`ClubsStore.libraryDidChange`). Same weak-bridge pattern as the
/// other Library sinks (the Library store is created before the owners it notifies).
///
/// Registration (app composition, `LibraryChangeSinks`): hold one `ClubsLibrarySink()`, list it in
/// `all`, and point it at the owner in `connect(releases:collection:imports:clubs:)`.
@MainActor
final class ClubsLibrarySink: LibraryChangeSink {
    weak var store: ClubsStore?

    init(store: ClubsStore? = nil) {
        self.store = store
    }

    func libraryDidChange(_ change: LibraryChange) {
        store?.libraryDidChange(change)
    }
}
#endif
