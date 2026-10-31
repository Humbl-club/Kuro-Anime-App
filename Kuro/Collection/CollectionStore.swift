import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Collection (feed)
// Owner of the Collection screen's feed: the account's tracked anime and manga interleaved by last
// update (`collectionFeedItems`), paged by keyset in the server's list `updated_at` order
// (`collection_feed_page`; the RPC derives the user from the JWT). Feed entries carry no tracking
// fields: status, rating and progress belong to the Library store (the single tracking authority),
// where the views read them. Separate anime and manga card pages are not loaded; no screen reads them.
//
// Account scope: the feed is the current account's list. Every fetch captures its
// `AccountContext` and publishes only while that context is current and its generation is the latest
// (latest-wins: a new fetch cancels the previous one; a superseded page publishes nothing and leaves
// the loading flags to the fetch that replaced it). On every transition the session funnel cancels
// the in-flight fetch and the sink's refresh and bumps the generation (`cancelAccountWork`), then
// empties the feed, cursor, flags, filter and error (`clearPrivateState`).
//
// Library change sink (`CollectionLibrarySink`, registered by AppComposition): a removed title leaves
// the loaded feed at once; any applied change refreshes the feed for the active filter (one refresh
// at a time: a newer one cancels its predecessor). Inside `withCollectionRefreshDeferred` the refresh
// is deferred (one feed refresh per batch). `applyBatchStatusChange` is that batch for status edits:
// this owner refreshes the visible filter once when the outermost scope ends. Inside
// `withCollectionRefreshSkipped` (a removal whose caller refreshes the feed itself) it is not started.

@MainActor
@Observable
final class CollectionStore: AccountScopedState {
    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every page request fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// The shared account coordinator (every publication is checked against it).
    let accountSession: AccountSessionCoordinator

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator) {
        self.client = client
        self.accountSession = accountSession
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    // Unified feed used by the main Collection screen (anime + manga interleaved by last updated).
    var collectionFeedItems: [Media] = []
    var isCollectionLoading: Bool = false
    var collectionErrorMessage: String? = nil

    // Collection feed pagination state (keyset by updated_at + source_rank + list row id).
    var hasMoreCollectionFeed: Bool = true
    var isLoadingMoreCollectionFeed: Bool = false
    var collectionFeedCursorUpdatedAt: Date? = nil
    var collectionFeedCursorSourceRank: Int? = nil
    var collectionFeedCursorRowId: Int? = nil

    var currentCollectionStatusFilter: ListStatus? = nil
    private(set) var importPublicationRevision = 0
    weak var home: HomeStore?
    weak var library: LibraryStore?
    var importedTitleKeys: Set<MediaKey>?
    var importedAccount: AccountContext?
    var importedMedia: [Media] = []
    var importedOffset = 0
    var importedHasMore = false
    var importedGeneration = 0
    var importedLoadTask: Task<Void, Never>?
    var seriesGroups: [CollectionSeriesGroup] = []
    var seriesNextCursor: String?
    private var seriesGeneration = 0
    private var seriesScope: (medium: String, status: String?, query: String?)?
    private var seriesChildrenLoading: Set<String> = []
    private var seriesPageLoading = false

    // De-dupe frequently called network fetches so multiple screens mounting doesn't fan-out.
    // The feed is latest-wins (a new status filter cancels the previous fetch).
    var collectionFeedFetchInFlight: Task<Void, Never>? = nil
    var collectionFeedFetchGeneration: Int = 0
    var collectionFeedFetchInFlightGeneration: Int = 0

    /// Latest page refresh started by the Library change sink (one at a time: latest wins).
    @ObservationIgnored var collectionChangeTask: Task<Void, Never>? = nil
    /// Open scopes that defer (or skip) the sink's page refresh, and whether a change arrived
    /// meanwhile.
    @ObservationIgnored var collectionRefreshDeferrals = 0
    @ObservationIgnored var collectionRefreshDeferred = false
    @ObservationIgnored private var collectionRefreshScopeGeneration = 0

    // MARK: AccountScopedState

    /// Cancels the in-flight feed fetch and the sink's refresh; the bumped generation also rejects
    /// any page of the previous account that is still under way (load-more included).
    func cancelAccountWork() {
        importedGeneration += 1
        importedLoadTask?.cancel(); importedLoadTask = nil
        collectionRefreshScopeGeneration += 1
        collectionRefreshDeferrals = 0
        collectionRefreshDeferred = false
        collectionChangeTask?.cancel()
        collectionChangeTask = nil
        collectionFeedFetchInFlight?.cancel()
        collectionFeedFetchInFlight = nil
        collectionFeedFetchGeneration += 1
        seriesGeneration += 1
        seriesPageLoading = false
        seriesChildrenLoading = []
    }

    /// Empties the feed, cursor, flags, filter and error. Account cancellation already invalidated
    /// open refresh scopes, so an old batch completion cannot alter the next account's counters.
    func clearPrivateState() {
        importPublicationRevision = 0
        importedTitleKeys = nil; importedAccount = nil; importedMedia = []; importedOffset = 0; importedHasMore = false
        collectionRefreshDeferred = false
        resetCollectionFeedPaging()
        currentCollectionStatusFilter = nil
        isCollectionLoading = false
        collectionErrorMessage = nil
        seriesGroups = []
        seriesNextCursor = nil
        seriesScope = nil
    }

    // MARK: - Collection feed (anime + manga interleaved)
    func fetchCollectionFeed(status: ListStatus? = nil) async {
        if importedTitleKeys != nil { await fetchImportedTitles(medium: nil, reset: true); return }
        seriesScope = nil
        currentCollectionStatusFilter = status
        collectionFeedFetchGeneration += 1
        let gen = collectionFeedFetchGeneration

        collectionFeedFetchInFlight?.cancel()
        let context = accountSession.current
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchCollectionFeedImpl(status: status, generation: gen, context: context)
        }
        collectionFeedFetchInFlight = t
        collectionFeedFetchInFlightGeneration = gen
        await t.value
        if collectionFeedFetchInFlightGeneration == gen { collectionFeedFetchInFlight = nil }
    }

    private struct CollectionPagingSnapshot: Sendable {
        let feed: [Media]
        let feedHasMore: Bool
        let feedCursorUpdatedAt: Date?
        let feedCursorSourceRank: Int?
        let feedCursorRowId: Int?
    }

    private func _fetchCollectionFeedImpl(status: ListStatus?, generation: Int, context: AccountContext?) async {
        guard let context, accountSession.isCurrent(context), generation == collectionFeedFetchGeneration else { return }
        isCollectionLoading = true
        collectionErrorMessage = nil
        defer { if accountSession.isCurrent(context), generation == collectionFeedFetchGeneration { isCollectionLoading = false } }

        let snapshot = CollectionPagingSnapshot(
            feed: collectionFeedItems,
            feedHasMore: hasMoreCollectionFeed,
            feedCursorUpdatedAt: collectionFeedCursorUpdatedAt,
            feedCursorSourceRank: collectionFeedCursorSourceRank,
            feedCursorRowId: collectionFeedCursorRowId
        )

        do {
            resetCollectionFeedPaging()

            let listTypeAnime = status.map { dbListType(for: $0, mediaType: "anime") }
            let listTypeManga = status.map { dbListType(for: $0, mediaType: "manga") }

            _ = try await fetchNextCollectionFeedPage(
                limit: 90,
                listTypeAnime: listTypeAnime,
                listTypeManga: listTypeManga,
                generation: generation,
                context: context
            )
        } catch {
            guard accountSession.isCurrent(context), generation == collectionFeedFetchGeneration else { return }
            collectionErrorMessage = "Failed to load collection: \(error.localizedDescription)"
            #if DEBUG
            print("❌ collection feed fetch: \(error)")
            #endif
            restoreCollectionSnapshot(snapshot)
        }
    }

    private func restoreCollectionSnapshot(_ snapshot: CollectionPagingSnapshot) {
        collectionFeedItems = snapshot.feed
        hasMoreCollectionFeed = snapshot.feedHasMore
        collectionFeedCursorUpdatedAt = snapshot.feedCursorUpdatedAt
        collectionFeedCursorSourceRank = snapshot.feedCursorSourceRank
        collectionFeedCursorRowId = snapshot.feedCursorRowId
    }

    func resetCollectionFeedPaging() {
        collectionFeedItems = []
        hasMoreCollectionFeed = true
        isLoadingMoreCollectionFeed = false
        collectionFeedCursorUpdatedAt = nil
        collectionFeedCursorSourceRank = nil
        collectionFeedCursorRowId = nil
    }

    /// `list_type` filter value of the Collection page RPCs (same mapping as the Library adapter).
    func dbListType(for status: ListStatus, mediaType: String) -> String {
        let isManga = mediaType.lowercased() == "manga"
        switch status {
        case .current: return isManga ? "READING" : "WATCHING"
        case .planning: return "PLANNING"
        case .completed: return "COMPLETED"
        case .dropped: return "DROPPED"
        case .paused: return "PAUSED"
        case .repeating: return isManga ? "READING" : "WATCHING"
        }
    }

    struct CollectionFeedRow: Decodable, Sendable {
        let list_updated_at: Date
        let source_rank: Int
        let list_row_id: Int
        let media_type: String
        let id: Int
        let title_english: String?
        let title_romaji: String?
        let title_native: String?
        let cover_image_large: String?
        let cover_image_medium: String?
        let banner_image: String?
        let format: String?
        let status: String?
        let episode_count: Int?
        let chapter_count: Int?
        let season_year: Int?
        let start_date_year: Int?
        let average_score: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genres: [String]?
        let created_at: Date?

        var media: Media {
            let kind: MediaKind = media_type.uppercased() == "MANGA" ? .manga : .anime
            let yearInt: Int? = kind == .anime ? (season_year ?? start_date_year) : start_date_year
            let rating: Double? = average_score.map { Double($0) / 10.0 }
            let image = cover_image_large ?? cover_image_medium
            let title = (title_english?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title_english : nil)
                ?? title_romaji
                ?? title_native
                ?? "Untitled"

            return Media(
                id: id,
                kind: kind,
                title: title,
                imageURL: image,
                year: yearInt.map(String.init) ?? "TBA",
                displayDescription: "",
                episodes: episode_count,
                chapters: chapter_count,
                rating: rating,
                genres: genres,
                statusRaw: status,
                formatRaw: format,
                popularityValue: popularity,
                trendingValue: trending,
                createdAtValue: created_at
            )
        }
    }

    /// Next feed page for the active filter (the Collection screen's load-more).
    @discardableResult
    func fetchNextCollectionFeedPage(limit: Int = 90) async -> Bool {
        if importedTitleKeys != nil { await fetchImportedTitles(medium: nil, reset: false); return importedHasMore }
        let context = accountSession.current
        do {
            let listTypeAnime = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "anime") }
            let listTypeManga = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "manga") }
            return try await fetchNextCollectionFeedPage(
                limit: limit,
                listTypeAnime: listTypeAnime,
                listTypeManga: listTypeManga,
                generation: collectionFeedFetchGeneration,
                context: context
            )
        } catch {
            guard accountSession.isCurrent(context) else { return false }
            collectionErrorMessage = "Failed to load more: \(error.localizedDescription)"
            #if DEBUG
            print("❌ collection feed page: \(error)")
            #endif
            return false
        }
    }

    // A page publishes only for its own generation and while the account it was started for
    // (`context`) is still current; otherwise it is dropped and leaves the loading flag to the
    // generation that replaced it.

    private func fetchNextCollectionFeedPage(
        limit: Int,
        listTypeAnime: String?,
        listTypeManga: String?,
        generation: Int,
        context: AccountContext?
    ) async throws -> Bool {
        guard generation == collectionFeedFetchGeneration, hasMoreCollectionFeed, !isLoadingMoreCollectionFeed else { return false }
        isLoadingMoreCollectionFeed = true
        // A superseded page leaves the flag to the generation that replaced it.
        defer { if generation == collectionFeedFetchGeneration { isLoadingMoreCollectionFeed = false } }
        if Task.isCancelled { return false }

        let perf = KuroPerf.begin("rpc.collection_feed_page")
        let params = RPCCollectionFeedPageParams(
            p_limit: max(1, min(120, limit)),
            p_cursor_updated_at: collectionFeedCursorUpdatedAt,
            p_cursor_source_rank: collectionFeedCursorSourceRank,
            p_cursor_row_id: collectionFeedCursorRowId,
            p_list_type_anime: listTypeAnime,
            p_list_type_manga: listTypeManga
        )
        let client = try requiredClient()
        let rows: [CollectionFeedRow] = try await client
            .rpc("collection_feed_page", params: params)
            .execute()
            .value
        if Task.isCancelled || generation != collectionFeedFetchGeneration || !accountSession.isCurrent(context) {
            KuroPerf.end(perf, message: "cancelled")
            return false
        }

        let items = rows.map(\.media)
        collectionFeedItems.append(contentsOf: items)
        hasMoreCollectionFeed = rows.count == params.p_limit
        if let last = rows.last {
            collectionFeedCursorUpdatedAt = last.list_updated_at
            collectionFeedCursorSourceRank = last.source_rank
            collectionFeedCursorRowId = last.list_row_id
        }
        KuroPerf.end(perf, message: "ok \(rows.count)")
        return true
    }

    // MARK: - Library change sink (registered by AppComposition, see LibraryChangeSinks.swift)

    /// A removed title leaves the loaded feed at once; any applied change then refreshes the feed for
    /// the active filter (one refresh at a time: a newer one cancels its predecessor; deferred inside
    /// `withCollectionRefreshDeferred`, not started inside `withCollectionRefreshSkipped`). The list
    /// projection itself is never re-fetched: the Library store holds it.
    func libraryDidChange(_ change: LibraryChange) {
        guard accountSession.isCurrent(change.account) else { return }
        guard !change.isProgressOnly else { return }
        if change.kind == .removed {
            dropFromCollectionPages(change.key)
        }
        if collectionRefreshDeferrals > 0 {
            collectionRefreshDeferred = true
            return
        }
        refreshCollectionPages()
    }

    /// Which filter the deferred refresh reads. `.active` keeps `currentCollectionStatusFilter`.
    /// `.visible` is the filter the Collection screen is showing, including All (`nil`).
    private enum DeferredFeedFilter {
        case active
        case visible(ListStatus?)
        case skipped
    }

    /// Runs `body` (e.g. a batch removal of N titles) with the Collection sink's feed refresh deferred:
    /// removed titles still leave the loaded feed at once, and ONE feed refresh of the active filter
    /// follows when anything changed meanwhile (instead of one per change).
    func withCollectionRefreshDeferred(_ body: () async -> Void) async {
        await deferCollectionRefresh(filter: .active, body)
    }

    /// The Collection screen's batch status change (`EditorialCollectionView.batchChangeStatus`).
    /// Each key is one status-only edit (`createIfMissing` is the new status). Writes run while the
    /// sink's feed refresh is deferred; when this scope is the outermost and anything changed, this
    /// owner refreshes `visibleFilter` once. Nested inside another deferral, that outer scope still
    /// owns the single refresh. Per-item outcomes come back in `keys` order.
    func applyBatchStatusChange(
        _ status: ListStatus,
        to keys: [MediaKey],
        visibleFilter: ListStatus?,
        write: (LibraryEdit, MediaKey, ListStatus?) async -> LibraryOutcome
    ) async -> [LibraryOutcome] {
        let edit = LibraryEdit(status: .set(status))
        return await applyCollectionBatch(to: keys, filter: .visible(visibleFilter)) { key in
            await write(edit, key, status)
        }
    }

    /// Removal uses the same originating-account fence and single-refresh scope as status edits.
    func applyBatchRemoval(to keys: [MediaKey], remove: (MediaKey) async -> Bool) async -> Int {
        let outcomes = await applyCollectionBatch(to: keys, filter: .active, write: remove)
        return outcomes.filter { $0 }.count
    }

    private func applyCollectionBatch<Outcome>(
        to keys: [MediaKey],
        filter: DeferredFeedFilter,
        write: (MediaKey) async -> Outcome
    ) async -> [Outcome] {
        guard let context = accountSession.current, !Task.isCancelled else { return [] }
        let generation = collectionRefreshScopeGeneration
        return await deferCollectionRefresh(filter: filter) {
            var outcomes: [Outcome] = []
            outcomes.reserveCapacity(keys.count)
            for key in keys {
                guard !Task.isCancelled, accountSession.isCurrent(context),
                      collectionRefreshScopeGeneration == generation else { break }
                let outcome = await write(key)
                guard !Task.isCancelled, accountSession.isCurrent(context),
                      collectionRefreshScopeGeneration == generation else { break }
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    private func deferCollectionRefresh<Result>(
        filter: DeferredFeedFilter,
        _ body: () async -> Result
    ) async -> Result {
        let context = accountSession.current
        let generation = collectionRefreshScopeGeneration
        collectionRefreshDeferrals += 1
        home?.beginLibraryBatch()
        let result = await body()
        // The account funnel resets both owners' batch counts. An obsolete scope must not end a
        // newer account's Home batch, decrement its Collection counter or replace its filter.
        guard accountSession.isCurrent(context), collectionRefreshScopeGeneration == generation else { return result }
        home?.endLibraryBatch()
        collectionRefreshDeferrals -= 1
        guard collectionRefreshDeferrals == 0 else { return result }
        if case .skipped = filter {
            collectionRefreshDeferred = false
            return result
        }
        guard collectionRefreshDeferred else { return result }
        collectionRefreshDeferred = false
        if !Task.isCancelled, case .visible(let status) = filter {
            currentCollectionStatusFilter = status
        }
        await refreshCollectionPages().value
        return result
    }

    /// Suppresses the sink refresh for a removal whose caller refreshes the feed itself. Nested
    /// inside a deferred batch, it keeps that outer scope's pending refresh. Account changes
    /// invalidate this scope just like a deferred scope.
    func withCollectionRefreshSkipped<Result>(_ body: () async -> Result) async -> Result {
        await deferCollectionRefresh(filter: .skipped, body)
    }

    @discardableResult
    private func refreshCollectionPages() -> Task<Void, Never> {
        let context = accountSession.current
        collectionChangeTask?.cancel()
        let task = Task { [weak self] in
            guard let self, !Task.isCancelled, self.accountSession.isCurrent(context) else { return }
            let filter = self.currentCollectionStatusFilter
            let activeSeries = self.seriesScope
            if let activeSeries {
                await self.fetchSeriesPage(medium: activeSeries.medium, status: activeSeries.status, query: activeSeries.query, reset: true)
            } else { await self.fetchCollectionFeed(status: filter) }
        }
        collectionChangeTask = task
        return task
    }

    func publishImport(for context: AccountContext) async throws {
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        await refreshCollectionPages().value
        guard accountSession.isCurrent(context), !Task.isCancelled else { throw CancellationError() }
        if let message = collectionErrorMessage { throw LibraryError.unavailable(message: message) }
        importPublicationRevision += 1
    }

    func fetchSeriesPage(medium: String, status: String?, query: String?, reset: Bool) async {
        if importedTitleKeys != nil { await fetchImportedTitles(medium: nil, reset: reset); return }
        guard reset || (!seriesPageLoading && seriesNextCursor != nil) else { return }
        if reset { seriesScope = (medium,status,query) }
        seriesPageLoading = true
        seriesChildrenLoading = []
        collectionErrorMessage = nil
        seriesGeneration += 1
        let generation = seriesGeneration
        let context = accountSession.current
        if reset {
            seriesGroups = []
            seriesNextCursor = nil
            isCollectionLoading = true
        }
        defer { if generation == seriesGeneration { isCollectionLoading = false; seriesPageLoading = false } }
        do {
            let client = try requiredClient()
            let cursor = reset ? nil : seriesNextCursor
            let page: CollectionSeriesPage = try await accountSession.withCredentialLease(for: context) {
                try await client.rpc("collection_series_page_v1", params: CollectionSeriesPageParams(
                    p_medium: medium,
                    p_status: status,
                    p_query: query,
                    p_limit: 30,
                    p_cursor: cursor
                )).execute().value
            }
            guard generation == seriesGeneration, accountSession.isCurrent(context) else { return }
            seriesGroups.append(contentsOf: page.groups.filter { item in !seriesGroups.contains(where: { $0.id == item.id }) })
            seriesNextCursor = page.nextCursor
        } catch {
            guard generation == seriesGeneration, accountSession.isCurrent(context) else { return }
            collectionErrorMessage = "Collection could not be loaded."
        }
    }

    func fetchMoreSeriesChildren(groupKey: String) async {
        guard let scope = seriesScope, !seriesChildrenLoading.contains(groupKey),
            let group = seriesGroups.first(where: { $0.groupKey == groupKey }), let cursor = group.childrenNext else { return }
        let context = accountSession.current, generation = seriesGeneration
        seriesChildrenLoading.insert(groupKey)
        defer { if generation == seriesGeneration { seriesChildrenLoading.remove(groupKey) } }
        do {
            struct Params: Encodable {
                let p_medium: String; let p_group_key: String; let p_status: String?; let p_query: String?; let p_after_id: Int
            }
            struct Page: Decodable { let children: [CollectionSeriesChild]; let next: Int? }
            let client = try requiredClient()
            let page: Page = try await accountSession.withCredentialLease(for: context) {
                try await client.rpc("collection_series_children_v1", params: Params(p_medium: scope.medium, p_group_key: groupKey,
                    p_status: scope.status,p_query: scope.query,p_after_id: cursor)).execute().value
            }
            guard generation == seriesGeneration, accountSession.isCurrent(context),
                let index = seriesGroups.firstIndex(where: { $0.groupKey == groupKey }),seriesGroups[index].childrenNext == cursor else { return }
            let old = seriesGroups[index]
            seriesGroups[index] = CollectionSeriesGroup(groupKey: old.groupKey,updatedAt: old.updatedAt,
                children: old.children + page.children.filter { child in !old.children.contains(where: { $0.id == child.id }) },
                childCount: old.childCount, childrenNext: page.next)
        } catch { if generation == seriesGeneration, accountSession.isCurrent(context) { collectionErrorMessage = "More seasons could not be loaded. Try again." } }
    }

    private func dropFromCollectionPages(_ key: MediaKey) {
        collectionFeedItems.removeAll { $0.kind == key.kind && $0.id == key.id }
        guard (key.kind == .manga ? "manga" : "anime") == seriesScope?.medium else { return }
        seriesGroups = seriesGroups.compactMap { group in
            let children = group.children.filter { $0.mediaId != key.id }
            guard !children.isEmpty else { return nil }
            return CollectionSeriesGroup(groupKey: group.groupKey, updatedAt: group.updatedAt, children: children, childCount: group.childCount.map { max(0,$0-(group.children.count-children.count)) }, childrenNext: group.childrenNext)
        }
    }
}

struct CollectionSeriesChild: Decodable, Identifiable, Equatable, Sendable {
    var id: Int { mediaId }
    let mediaId: Int
    let listType: String
    let progress: Int
    let serverRevision: Int64
    let lifecycleId: String
    let title: String
    var mediaKind: MediaKind? = nil

    enum CodingKeys: String, CodingKey {
        case mediaId = "media_id"
        case listType = "list_type"
        case progress
        case serverRevision = "server_revision"
        case lifecycleId = "lifecycle_id"
        case title
    }
}

struct CollectionSeriesGroup: Decodable, Identifiable, Equatable, Sendable {
    var id: String { groupKey }
    let groupKey: String
    let updatedAt: String
    let children: [CollectionSeriesChild]
    let childCount: Int?
    let childrenNext: Int?

    enum CodingKeys: String, CodingKey {
        case groupKey = "group_key"
        case updatedAt = "updated_at"
        case children
        case childCount = "child_count", childrenNext = "children_next"
    }
}

struct CollectionSeriesPage: Decodable, Sendable {
    let groups: [CollectionSeriesGroup]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case groups
        case nextCursor = "next_cursor"
    }
}

private struct CollectionSeriesPageParams: Encodable {
    let p_medium: String
    let p_status: String?
    let p_query: String?
    let p_limit: Int
    let p_cursor: String?
}
#endif
