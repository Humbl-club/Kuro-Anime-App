import Foundation
import KuroCore
import KuroLibrary

/// A list the Profile asked the Collection page to open: one status, optionally one medium.
struct CollectionListRequest: Equatable, Sendable {
    let medium: MediaKind?
    let status: ListStatus
}

/// How a list +1 was written, so its Undo takes the matching path.
enum CollectionAdvancePath: Equatable, Sendable {
    /// The durable progress outbox (`LibraryStore.advanceProgress` with the unit cap). Undo is the
    /// guarded `LibraryStore.undoProgress`: cancel an unsent intent, compensate an acknowledged one,
    /// refuse while a request is in flight.
    case durable
    /// A plain progress edit (the outbox is unavailable). Undo writes the prior position back.
    case direct
}

/// One +1 the Collection lists admitted: what Undo puts back, and for which account and lifecycle.
struct CollectionAdvanceReceipt: Equatable, Sendable {
    let key: MediaKey
    let title: String
    let lifecycleId: UUID?
    let prior: Int
    let advancedTo: Int
    let account: AccountContext
    let path: CollectionAdvancePath
}

/// What a list +1 did.
enum CollectionAdvanceResult: Equatable, Sendable {
    /// Admitted along `path` (the displayed position now moved).
    case admitted(CollectionAdvancePath)
    /// Nothing sent: the title is at its known total, untracked, or its next unit needs a choice.
    case refused
    /// The write failed (the store already rolled its projection back).
    case failed
}

/// What a list Undo did.
enum CollectionUndoResult: Equatable, Sendable {
    case undone
    /// The +1 is already being sent and has no receipt yet: it cannot be replaced (try again later).
    case alreadySending
    /// No current receipt, the title moved on since, or the write failed.
    case failed
}

#if canImport(Supabase)
import Supabase

// MARK: - Collection lists (Folio) support
// Owner-side state for the Collection lists and Profile's "Your lists" preview. Tracking values never
// live here: status, progress and rating are read from the Library store. The lists' +1 and its Undo
// are written here (`advanceFromList` / `undoListAdvance`) straight through the Library store's
// progress API, never through `HomeStore`, so an advance made in Collection never arms Home's own
// Undo and one advance has exactly one Undo path. Other writes go through `LibraryActions` from the
// views. Everything here is account-scoped and cleared by `cancelAccountWork` / `clearPrivateState`.

extension CollectionStore {
    /// Statuses Profile previews, in reading order.
    nonisolated static let previewStatuses: [ListStatus] = [.current, .planning, .completed]
    /// Covers per previewed status.
    nonisolated static let previewLimit = 6
    /// How long a loaded preview is reused before Profile reads it again.
    nonisolated static let previewTTL: TimeInterval = 120

    // MARK: Profile → Collection filter

    /// Asks the Collection page to open `status` (and `medium`, when given). The page consumes it.
    func requestList(_ request: CollectionListRequest) {
        guard accountSession.current != nil else { return }
        clearImportedTitles()
        requestedListFilter = request
    }

    /// The pending request, cleared (one consumer).
    func consumeListRequest() -> CollectionListRequest? {
        defer { requestedListFilter = nil }
        return requestedListFilter
    }

    // MARK: +1 and Undo

    /// +1 for a tracked title, capped at `cap` (the unit total, when known). The durable outbox when
    /// it accepts writes (its own caught-up guard applies the cap again at admission); otherwise one
    /// absolute progress edit from the displayed position, never past `cap`. No banner is shown here:
    /// the caller shows one notice for the result.
    func advanceFromList(_ key: MediaKey, cap: Int?) async -> CollectionAdvanceResult {
        guard let library, accountSession.current != nil, let entry = library.entry(for: key) else { return .refused }
        let current = library.displayedProgress(for: key, server: entry.progress, lifecycleId: entry.lifecycleId)
        if let cap, current >= cap { return .refused }
        if library.progressAvailable, entry.lifecycleId != nil, entry.revision != nil {
            let outcome = await library.advanceProgress(for: key, cap: cap)
            if case .failed(.invalidValue) = outcome { return .refused }
            return outcome.error == nil ? .admitted(.durable) : .failed
        }
        let outcome = await library.apply(LibraryEdit(progress: .set(current + 1)), to: key, createIfMissing: nil)
        return outcome.error == nil ? .admitted(.direct) : .failed
    }

    /// Guarded Undo of the latest list +1: only for the current account, the same lifecycle, and while
    /// the title still shows the advanced position. Takes the receipt's own path (see
    /// `CollectionAdvancePath`).
    func undoListAdvance() async -> CollectionUndoResult {
        guard let receipt = takeListAdvance(), let library, let entry = library.entry(for: receipt.key),
              entry.lifecycleId == receipt.lifecycleId,
              library.displayedProgress(for: receipt.key, server: entry.progress, lifecycleId: entry.lifecycleId)
                == receipt.advancedTo else { return .failed }
        switch receipt.path {
        case .durable:
            guard let lifecycle = receipt.lifecycleId else { return .failed }
            do {
                try await library.undoProgress(for: receipt.key, lifecycleId: lifecycle)
                return .undone
            } catch LibraryError.retryable {
                return .alreadySending
            } catch {
                return .failed
            }
        case .direct:
            let outcome = await library.apply(LibraryEdit(progress: .set(receipt.prior)), to: receipt.key,
                                              createIfMissing: nil)
            return outcome.error == nil ? .undone : .failed
        }
    }

    // MARK: Undo receipt

    /// Records the +1 the lists just admitted (replaces the previous one: Undo covers the latest).
    func recordListAdvance(_ receipt: CollectionAdvanceReceipt) {
        guard accountSession.isCurrent(receipt.account) else { return }
        lastListAdvance = receipt
    }

    /// The receipt, when it still belongs to the current account; cleared on read.
    func takeListAdvance() -> CollectionAdvanceReceipt? {
        guard let receipt = lastListAdvance else { return nil }
        lastListAdvance = nil
        return accountSession.isCurrent(receipt.account) ? receipt : nil
    }

    // MARK: Profile "Your lists" preview

    /// Loads the newest covers of each previewed status (both media) with one bounded feed read per
    /// status. Never touches the Collection page's feed, filter or paging. Reused for `previewTTL`
    /// unless `force`.
    func loadListPreview(force: Bool = false) async {
        guard let context = accountSession.current else { return }
        if !force, let loadedAt = listPreviewLoadedAt, Date().timeIntervalSince(loadedAt) < Self.previewTTL,
           !listPreviewFailed { return }
        listPreviewGeneration += 1
        let generation = listPreviewGeneration
        listPreviewTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.readListPreview(context: context, generation: generation)
        }
        listPreviewTask = task
        await task.value
    }

    private func readListPreview(context: AccountContext, generation: Int) async {
        do {
            let client = try requiredClient()
            var result: [ListStatus: [Media]] = [:]
            for status in Self.previewStatuses {
                let params = RPCCollectionFeedPageParams(
                    p_limit: Self.previewLimit,
                    p_cursor_updated_at: nil,
                    p_cursor_source_rank: nil,
                    p_cursor_row_id: nil,
                    p_list_type_anime: dbListType(for: status, mediaType: "anime"),
                    p_list_type_manga: dbListType(for: status, mediaType: "manga")
                )
                let rows: [CollectionFeedRow] = try await accountSession.withCredentialLease(for: context) {
                    try await client.rpc("collection_feed_page", params: params).execute().value
                }
                guard !Task.isCancelled, generation == listPreviewGeneration, accountSession.isCurrent(context) else { return }
                result[status] = rows.map(\.media)
            }
            guard generation == listPreviewGeneration, accountSession.isCurrent(context) else { return }
            listPreview = result
            listPreviewFailed = false
            listPreviewLoadedAt = Date()
        } catch {
            guard !(error is CancellationError), generation == listPreviewGeneration,
                  accountSession.isCurrent(context) else { return }
            // Earlier covers stay; Profile still shows the counts from the Library store.
            listPreviewFailed = true
            #if DEBUG
            print("❌ collection list preview: \(error)")
            #endif
        }
    }
}
#endif
