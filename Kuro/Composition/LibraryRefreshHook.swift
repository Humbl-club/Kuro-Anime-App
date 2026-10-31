import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)

/// The Library refresh paths offered to owners that sit outside the Library actions (Imports, Taste).
///
/// The server-side list writers (edge `concierge-apply` / `concierge-undo`, SQL
/// `record_taste_deck_signal('love')`) change the lists without the Library store; afterwards they
/// call ONE hook, `listsChangedServerSide(for:)`, which is `LibraryActions.libraryChangedServerSide`
/// (drops the tracking copies, then a fresh Library re-read). No second refresh path, no local write.
/// The owners are built before `LibraryActions`, so this bridge holds it weakly; composition
/// connects it once that exists (like `LibraryChangeSinks`).
@MainActor
final class LibraryRefreshHook {
    weak var actions: LibraryActions?

    func connect(to actions: LibraryActions) {
        self.actions = actions
    }

    /// The lists changed server-side for `context`: tracking copies dropped, Library re-read fresh.
    @discardableResult
    func listsChangedServerSide(for context: AccountContext) -> Task<Void, Never>? {
        assert(actions != nil, "LibraryRefreshHook used before connect(to:)")
        return actions?.libraryChangedServerSide(for: context)
    }

    func prepareImportHome(revisions:[String:Int64],for context:AccountContext) async throws {
        guard let actions else { throw CancellationError() }
        try await actions.prepareImportHome(revisions:revisions,for:context)
    }

    func publishImport(revisions: [String:Int64], for context: AccountContext) async throws {
        guard let actions else { throw CancellationError() }
        try await actions.publishImport(revisions: revisions, for: context)
    }

    func hasPendingTracking(for keys: Set<MediaKey>, account: AccountContext) async throws -> Bool {
        guard let actions else { throw CancellationError() }
        return try await actions.hasPendingTracking(for: keys, account: account)
    }

    func withImportMutationReservation<T: Sendable>(keys: Set<MediaKey>, account: AccountContext,
        operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        guard let actions else { throw CancellationError() }
        return try await actions.withImportMutationReservation(keys: keys, account: account, operation: operation)
    }

    func withImportUndoReservation<T: Sendable>(keys: Set<MediaKey>, account: AccountContext,
        operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        guard let actions else { throw CancellationError() }
        return try await actions.withImportUndoReservation(keys: keys, account: account, operation: operation)
    }

    /// View-path refresh: joins an in-flight Library refresh of the current account or starts one.
    func refreshLists() async {
        assert(actions != nil, "LibraryRefreshHook used before connect(to:)")
        await actions?.fetchUserLists()
    }
}
#endif
