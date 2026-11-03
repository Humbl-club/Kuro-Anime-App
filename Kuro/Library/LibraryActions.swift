import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)

// MARK: - Library actions (E6c2)
// The Library writer mapping and refresh paths of the former service facade (E3,
// `SupabaseService+Library.swift`), moved verbatim. This owner holds no tracking state: every writer
// is one `LibraryStore` operation and every reader is the store itself (`@Environment(LibraryStore)`).
// The legacy writers report through the legacy channel (`Bool` + `errorMessage`); the
// outcome-returning primitives (`save`, `apply`, `remove`, E8) hand back the store's own
// `LibraryOutcome` with no UI policy.
//
// Rating parameters are on the DATABASE scale 1...10 (`UserRating`); the 0-100 `UserList.score`
// is a display projection only.
//
// Follow-up effects of an applied change are the store's change sinks (Releases re-arm/cancel of
// airing reminders, the Collection page prune + refresh, the concierge parse cache, club bundles),
// which also run for the removal of a title the projection did not hold (F7).

@MainActor
@Observable
final class LibraryActions: AccountScopedState {
    enum ImportPublicationFailure: Error, Sendable, LocalizedError {
        case library(String), home(String), collection(String), releases(String)
        var errorDescription: String? {
            switch self {
            case .library(let message): return "Saved; refreshing your Library. \(message)"
            case .home(let message): return "Saved; Home refresh is pending. \(message)"
            case .collection(let message): return "Saved; Collection refresh is pending. \(message)"
            case .releases(let message): return "Saved; release schedule refresh is pending. \(message)"
            }
        }
    }
    /// The single authoritative tracking projection.
    @ObservationIgnored private let library: LibraryStore
    /// The shared account coordinator (every write and refresh is checked against it).
    @ObservationIgnored let accountSession: AccountSessionCoordinator
    /// Collection pages: a `removeFromList(skipRefresh: true)` suppresses the sink's page refresh.
    @ObservationIgnored private let collection: CollectionStore
    /// Holds tracking copies outside the store (the concierge parse cache's `existing_entry`).
    @ObservationIgnored private let imports: ImportsService
    /// The toggles' result banners.
    @ObservationIgnored private let banner: BannerCenter

    /// Last write or refresh failure of the current account (legacy channel).
    var errorMessage: String?
    @ObservationIgnored weak var home: HomeStore?
    @ObservationIgnored weak var releases: ReleasesStore?
    /// Library refreshes: view-path refreshes of one account join an in-flight one; refreshes after a
    /// server-side write start fresh. Cancelled on transitions.
    let libraryRefreshLoads = AccountScopedLoads<String, Void>()
    /// Library refresh started by the session funnel or a server-side writer (awaitable in tests).
    @ObservationIgnored var libraryRefreshTask: Task<Void, Never>? = nil
    /// Double-tap guard of the collection toggle ("<kind>-<id>").
    @ObservationIgnored var togglingMediaKeys: Set<String> = []

    init(
        library: LibraryStore,
        accountSession: AccountSessionCoordinator,
        collection: CollectionStore,
        imports: ImportsService,
        banner: BannerCenter
    ) {
        self.library = library
        self.accountSession = accountSession
        self.collection = collection
        self.imports = imports
        self.banner = banner
    }

    // MARK: AccountScopedState

    /// Cancels the account's Library refreshes (a toggle that outlives its account publishes nothing).
    func cancelAccountWork() {
        libraryRefreshLoads.cancelAll()
        libraryRefreshTask?.cancel()
        libraryRefreshTask = nil
    }

    func clearPrivateState() {
        errorMessage = nil
        togglingMediaKeys.removeAll()
    }

    // MARK: Title identity

    /// Typed identity for the free-form media type the callers pass ("anime", "ANIME", "manga");
    /// nil for anything else, so anime and manga with equal ids never mix.
    private func libraryKey(mediaType: String, mediaId: Int) -> MediaKey? {
        switch mediaType.lowercased() {
        case "anime": return MediaKey(kind: .anime, id: mediaId)
        case "manga": return MediaKey(kind: .manga, id: mediaId)
        default: return nil
        }
    }

    // MARK: Refresh

    /// `libraryRefreshLoads` key of the single Library refresh.
    static let libraryRefreshKey = "library"

    /// View-path refresh (kept under its old name): joins an in-flight refresh of the same account or
    /// starts one. Stale-protected: a refresh never overwrites a local mutation newer than its start.
    func fetchUserLists() async {
        guard let context = accountSession.current else { return }
        await startLibraryRefresh(for: context).value
    }

    /// Starts a Library refresh for `context` and registers it before returning (`Task.immediate`
    /// runs up to the first suspension), so a refresh requested right afterwards can join it. The
    /// refresh runs in its own task: cancelling a caller (e.g. the realtime debounce) never cancels it;
    /// session transitions do (`cancelAccountWork`).
    /// - `fresh == false` (session start, view path): joins an in-flight refresh of the same account.
    /// - `fresh == true` (after a server-side write): never joins a read that started before the
    ///   write; later joining refreshes join this one.
    @discardableResult
    func startLibraryRefresh(for context: AccountContext, fresh: Bool = false) -> Task<Void, Never> {
        let loads = libraryRefreshLoads
        let key = Self.libraryRefreshKey
        let work: @MainActor () async throws -> Void = { [weak self] in
            await self?.refreshLibrary(for: context)
        }
        let task = Task.immediate { @MainActor in
            if fresh {
                _ = try? await loads.runFresh(key: key, context: context, work: work)
            } else {
                _ = try? await loads.run(key: key, context: context, work: work)
            }
        }
        libraryRefreshTask = task
        return task
    }

    /// The lists changed server-side (concierge apply/undo, deck 'love', realtime): copies derived
    /// from the old state are dropped and the Library projection is re-read fresh. The single hook of
    /// the server-side writers (`LibraryRefreshHook`, used by `imports` and `taste`) and of the user
    /// realtime channel.
    @discardableResult
    func libraryChangedServerSide(for context: AccountContext) -> Task<Void, Never> {
        dropTrackingCopies()
        let refresh = startLibraryRefresh(for: context, fresh: true)
        return Task { [weak self] in
            await refresh.value
            guard let self, self.accountSession.isCurrent(context) else { return }
            await self.home?.load()
        }
    }

    func prepareImportHome(revisions: [String:Int64], for context: AccountContext) async throws {
        try await publishImport(revisions: revisions, for: context)
    }

    /// One deliberate import publication boundary, never a per-item or per-chunk fan-out.
    func publishImport(revisions: [String:Int64], for context: AccountContext) async throws {
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        dropTrackingCopies()
        do {
            try await libraryRefreshLoads.runFresh(key: Self.libraryRefreshKey, context: context) { [self] in
                guard accountSession.isCurrent(context) else { throw CancellationError() }
                try await library.refresh()
                guard accountSession.isCurrent(context) else { throw CancellationError() }
            }
        } catch { throw ImportPublicationFailure.library((error as? LibraryError).map(Self.libraryErrorDescription) ?? error.localizedDescription) }
        guard accountSession.isCurrent(context), let home, let releases else { throw CancellationError() }
        do { try await home.prepareImportHome(revisions: revisions, for: context) }
        catch { throw ImportPublicationFailure.home(error.localizedDescription) }
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        do { try await collection.publishImport(for: context) }
        catch { throw ImportPublicationFailure.collection(error.localizedDescription) }
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        do { try await releases.publishImport(for: context, entries: library.allEntries) }
        catch { throw ImportPublicationFailure.releases(error.localizedDescription) }
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        errorMessage = nil
    }

    func hasPendingTracking(for keys: Set<MediaKey>, account: AccountContext) async throws -> Bool {
        try await library.hasPendingTracking(for: keys, account: account)
    }

    func withImportMutationReservation<T: Sendable>(keys: Set<MediaKey>, account: AccountContext,
        operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        return try await library.withImportMutationReservation(keys: keys, account: account, operation: operation)
    }

    func withImportUndoReservation<T: Sendable>(keys: Set<MediaKey>, account: AccountContext,
        operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        try await library.withImportUndoReservation(keys: keys, account: account, operation: operation)
    }

    /// Account-scoped caches that embed tracking state outside the store. The concierge parse cache
    /// (`imports`) carries `existing_entry` (it gates auto-apply) and must not outlive a tracking change.
    /// (The club bundle's `my_status`/`my_progress`/`my_rating` are the same class: E6 follow-up.)
    func dropTrackingCopies() {
        imports.dropTrackingCopies()
    }

    private func refreshLibrary(for context: AccountContext) async {
        do {
            try await library.refresh()
        } catch {
            guard accountSession.isCurrent(context) else { return }
            errorMessage = "Failed to fetch lists: \(Self.libraryErrorDescription(error))"
            #if DEBUG
            print("❌ Library refresh failed: \(error)")
            #endif
        }
    }

    // MARK: Writers

    @discardableResult
    func removeFromList(mediaId: Int, mediaType: String) async -> Bool {
        await removeFromList(mediaId: mediaId, mediaType: mediaType, skipRefresh: false)
    }

    /// Removes the title. The sinks drop the card from the loaded Collection pages and the anime's
    /// reminders (also for a title the projection did not hold). `skipRefresh` (batch removal whose
    /// caller refreshes the pages once at the end): the Collection page refresh is not started
    /// (`CollectionStore.withCollectionRefreshSkipped`).
    @discardableResult
    func removeFromList(mediaId: Int, mediaType: String, skipRefresh: Bool) async -> Bool {
        guard let context = accountSession.current else { return false }
        errorMessage = nil
        guard let key = libraryKey(mediaType: mediaType, mediaId: mediaId) else { return false }
        let outcome: LibraryOutcome
        if skipRefresh {
            outcome = await collection.withCollectionRefreshSkipped { await library.remove(key) }
        } else {
            outcome = await library.remove(key)
        }
        return finishLibraryWrite(outcome, context: context, failure: "Failed to remove from list")
    }

    /// "+1 EP/CH": an absolute progress-only edit of a tracked title; no other field is re-sent.
    func incrementProgress(mediaId: Int, mediaType: String) async {
        guard let context = accountSession.current,
              let key = libraryKey(mediaType: mediaType, mediaId: mediaId),
              library.entry(for: key) != nil else { return }
        errorMessage = nil
        let outcome = await library.advanceProgress(for: key)
        _ = finishLibraryWrite(outcome, context: context, failure: "Failed to save")
    }

    /// Adds (as Planned) or removes the title. The store projects the change before this returns
    /// (`Task.immediate` runs up to the store's first suspension), so a caller that reads
    /// `LibraryStore.isTracked` right after sees the flip; a failure rolls it back. Returns the
    /// toggle's task. A second tap while the first toggle of the title is in flight is ignored (one
    /// write, one banner).
    @discardableResult
    func toggleInCollection(mediaId: Int, mediaType: String) -> Task<Void, Never>? {
        guard let context = accountSession.current,
              let key = libraryKey(mediaType: mediaType, mediaId: mediaId) else { return nil }
        let guardKey = "\(key.kind.rawValue)-\(key.id)"
        guard !togglingMediaKeys.contains(guardKey) else { return nil }
        togglingMediaKeys.insert(guardKey)
        let wasInCollection = library.isTracked(key)
        return Task.immediate { @MainActor [weak self] in
            guard let self else { return }
            // A toggle that outlives its account never releases the next account's guard.
            defer { if self.accountSession.isCurrent(context) { self.togglingMediaKeys.remove(guardKey) } }
            let success: Bool
            if wasInCollection {
                success = await self.removeFromList(mediaId: mediaId, mediaType: mediaType)
            } else {
                // Add as Planned; a title that is already tracked is never changed (`save`).
                self.errorMessage = nil
                let outcome = await self.save(key, status: .planning)
                success = self.finishLibraryWrite(outcome, context: context, failure: "Failed to save")
            }
            // A toggle that outlives its account shows nothing to the next account.
            guard self.accountSession.isCurrent(context) else { return }
            if success {
                self.banner.show(wasInCollection ? "Removed from collection" : "Added to collection")
            } else {
                self.banner.show("Couldn't update list. Try again.")
            }
        }
    }

    // MARK: Queued +1 (Home Screen widget hand-off)

    /// What `advanceQueuedProgress` did with one queued +1.
    enum QueuedAdvanceOutcome: Equatable, Sendable {
        /// Written along the same path as an in-app +1.
        case applied
        /// Nothing to do: the title already shows the target (or moved elsewhere since the tap), or the
        /// tap was made on an earlier lifecycle of the row. Drop the request.
        case stale
        /// The caught-up guard refused it (at its total) or the next unit needs a choice. Drop it.
        case refused
        /// No account, or the Library has not loaded this account's rows yet. Keep it for later.
        case notReady
        /// The title is not tracked any more. Drop it.
        case untracked
        /// The write failed; `retryable` keeps the request for the next drain.
        case failed(retryable: Bool)
    }

    /// One +1 handed over by the Home Screen widget (`WidgetIntentInbox`), applied exactly like the
    /// Collection lists' +1 (`CollectionStore.advanceFromList`): the durable progress outbox with the
    /// unit cap when it accepts writes (its own caught-up guard and revision fence apply at admission),
    /// otherwise one absolute progress edit from the displayed position, never past `cap`. The request
    /// is honoured only while the title still shows `target - 1` on the same lifecycle, so a replayed,
    /// stale or forged request can never do more than the +1 the user could make in the app now.
    /// No banner, no Undo receipt (Home's and Collection's Undo paths stay untouched).
    func advanceQueuedProgress(_ key: MediaKey, to target: Int, lifecycleId: UUID?, cap: Int?) async -> QueuedAdvanceOutcome {
        guard let context = accountSession.current else { return .notReady }
        guard let entry = library.entry(for: key) else {
            return library.loadState == .loaded ? .untracked : .notReady
        }
        if let lifecycleId, entry.lifecycleId != lifecycleId { return .stale }
        let current = library.displayedProgress(for: key, server: entry.progress, lifecycleId: entry.lifecycleId)
        guard current == target - 1 else { return .stale }
        if let cap, cap > 0, current >= cap { return .refused }
        let outcome: LibraryOutcome
        if library.progressAvailable, entry.lifecycleId != nil, entry.revision != nil {
            outcome = await library.advanceProgress(for: key, cap: cap)
            if case .failed(.invalidValue) = outcome { return .refused }
        } else {
            outcome = await library.apply(LibraryEdit(progress: .set(current + 1)), to: key, createIfMissing: nil)
        }
        guard accountSession.isCurrent(context) else { return .notReady }
        switch outcome {
        case .applied: return .applied
        case .failed(let error):
            #if DEBUG
            print("⚠️ Queued +1 failed: \(error)")
            #endif
            switch error {
            case .retryable, .unavailable: return .failed(retryable: true)
            case .notAuthenticated: return .notReady
            case .notFound: return .untracked
            case .conflict, .invalidValue: return .failed(retryable: false)
            }
        }
    }

    // MARK: Outcome-returning primitives (E8)
    // The views' explicit Library edits (mark progress, batch status change, concierge quick-save, the
    // detail pages' save toggle, QuickVerdict, AddToListSheet) branch on the typed outcome: `change.kind`
    // or the `LibraryError` case each shows its own copy for. These primitives hand them exactly the
    // store's `LibraryOutcome` for exactly the store's write: no double-tap guard (those paths never had
    // one; the guarded toggle is `toggleInCollection`), no `errorMessage` and no
    // banner (failure UI policy stays with the caller). Without a session the store answers
    // `.failed(.notAuthenticated)` and sends nothing.

    /// Ensures the title is tracked, adding it with `status` when it is missing; an entry that already
    /// exists is never changed (`.applied` with `change.kind == .updated` and the stored entry unchanged).
    func save(_ key: MediaKey, status: ListStatus) async -> LibraryOutcome {
        await library.save(key, status: status)
    }

    /// ONE edit naming only the fields it sets; a missing entry is created with `createIfMissing` (nil:
    /// a missing entry is never created).
    func apply(_ edit: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus?) async -> LibraryOutcome {
        await library.apply(edit, to: key, createIfMissing: createIfMissing)
    }

    /// Removes the title (idempotent: removing an untracked title is applied). The change sinks drop it
    /// from the loaded Collection pages and cancel the anime's reminders.
    func remove(_ key: MediaKey) async -> LibraryOutcome {
        await library.remove(key)
    }

    /// Maps a store outcome onto the legacy channel: `true` when the write was applied; on failure
    /// `errorMessage` describes it. Nothing is published once `context` is no longer current.
    private func finishLibraryWrite(_ outcome: LibraryOutcome, context: AccountContext, failure: String) -> Bool {
        switch outcome {
        case .applied:
            if accountSession.isCurrent(context) { errorMessage = nil }
            return true
        case .failed(let error):
            if accountSession.isCurrent(context) {
                errorMessage = "\(failure): \(Self.libraryErrorDescription(error))"
                #if DEBUG
                print("❌ Library write failed: \(error)")
                #endif
            }
            return false
        }
    }

    static func libraryErrorDescription(_ error: LibraryError) -> String {
        switch error {
        case .notAuthenticated: return "You're signed out. Sign in and try again."
        case .invalidValue(let field): return "Invalid \(field)."
        case .notFound: return "This title is no longer in your list."
        case .conflict: return "This entry changed elsewhere. Try again."
        case .retryable(let message), .unavailable(let message): return message
        }
    }
}
#endif
