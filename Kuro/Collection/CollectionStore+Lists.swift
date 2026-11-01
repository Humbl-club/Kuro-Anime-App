import Foundation
import KuroCore
import KuroLibrary

/// A list the Profile asked the Collection page to open: one status, optionally one medium.
struct CollectionListRequest: Equatable, Sendable {
    let medium: MediaKind?
    let status: ListStatus
}

/// One +1 the Collection lists admitted: what Undo puts back, and for which account and lifecycle.
struct CollectionAdvanceReceipt: Equatable, Sendable {
    let key: MediaKey
    let title: String
    let lifecycleId: UUID?
    let prior: Int
    let advancedTo: Int
    let account: AccountContext
}

#if canImport(Supabase)
import Supabase

// MARK: - Collection lists (Folio) support
// Owner-side state for the Collection lists and Profile's "Your lists" preview. Tracking values never
// live here: status, progress and rating are read from the Library store; writes go through
// `LibraryActions` / `HomeStore.advance` from the views. Everything here is account-scoped and cleared
// by `cancelAccountWork` / `clearPrivateState`.

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
