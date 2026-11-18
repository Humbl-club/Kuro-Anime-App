import Foundation
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Search (public data)
// Owner of the paged server-side text search: query, filters, keyset cursors and result pages.
// Search results are public (not account-scoped). Every reset starts a new query generation and
// cancels the previous query's in-flight page, so a late page of an earlier query never publishes.

@MainActor
@Observable
final class SearchStore {

    struct SearchFilters {
        var trending: Bool = false
        var newSeason: Bool = false
        var classics: Bool = false
        var hiddenGems: Bool = false
        // New: airing-only and precise season window
        var airingOnly: Bool = false
        var seasonName: String? = nil  // "WINTER", "SPRING", "SUMMER", "FALL"
        var seasonYear: Int? = nil
    }

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every read fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    // Search state (paged server-side text search)
    // NOTE: These are lightweight cards (rank included for keyset pagination).
    var searchAnimeItems: [AnimeCard] = []
    var searchMangaItems: [MangaCard] = []
    private var currentSearchQuery: String = ""
    private enum SearchMode { case anime, manga, combined }
    private var searchMode: SearchMode = .anime
    private let searchPageSize = 20
    var hasMoreSearch = true
    var isSearching = false
    private var hasMoreSearchAnime = true
    private var hasMoreSearchManga = true
    private var searchCursorAnimeRank: Double? = nil
    private var searchCursorAnimePopularity: Int? = nil
    private var searchCursorAnimeId: Int? = nil
    private var searchCursorMangaRank: Double? = nil
    private var searchCursorMangaPopularity: Int? = nil
    private var searchCursorMangaId: Int? = nil
    private var currentSearchFilters: SearchFilters? = nil
    /// Last search failure (owner-local; not the Library write channel).
    var errorMessage: String? = nil

    /// W4: how many 18+ titles the current query matched but Search does not list (page 1 only;
    /// anime and manga are summed in the combined scope). Always 0 while `adultNoticeEnabled()` is
    /// false or v2 is not deployed.
    private(set) var hiddenAdultAnime = 0
    private(set) var hiddenAdultManga = 0
    var hiddenAdultCount: Int { hiddenAdultAnime + hiddenAdultManga }
    /// `search_adult_notice_v1` (composition-configured). Off: no v2 request is ever sent.
    @ObservationIgnored var adultNoticeEnabled: @MainActor () -> Bool = { false }
    /// When v2 last answered "not deployed"; v2 is not asked again for `undeployedRetryInterval`.
    @ObservationIgnored private var searchV2UndeployedAt: Date? = nil
    nonisolated static let undeployedRetryInterval: TimeInterval = DiscoveryStore.discoverUndeployedRetryInterval

    /// Bumped by every reset: a page or refresh started for an earlier query never publishes.
    @ObservationIgnored private var queryGeneration = 0
    /// The page or refresh load in flight for the current query; a reset cancels it.
    @ObservationIgnored private var inFlight: Task<Void, Never>? = nil

    // MARK: - Query lifecycle

    func resetSearch(query: String, isManga: Bool) {
        beginNewQuery()
        errorMessage = nil
        currentSearchQuery = query
        searchMode = isManga ? .manga : .anime
        hasMoreSearch = true
        hasMoreSearchAnime = true
        hasMoreSearchManga = true
        searchAnimeItems = []
        searchMangaItems = []
        searchCursorAnimeRank = nil
        searchCursorAnimePopularity = nil
        searchCursorAnimeId = nil
        searchCursorMangaRank = nil
        searchCursorMangaPopularity = nil
        searchCursorMangaId = nil
    }

    func resetCombinedSearch(query: String) {
        beginNewQuery()
        errorMessage = nil
        currentSearchQuery = query
        searchMode = .combined
        hasMoreSearchAnime = true
        hasMoreSearchManga = true
        hasMoreSearch = true
        searchAnimeItems = []
        searchMangaItems = []
        searchCursorAnimeRank = nil
        searchCursorAnimePopularity = nil
        searchCursorAnimeId = nil
        searchCursorMangaRank = nil
        searchCursorMangaPopularity = nil
        searchCursorMangaId = nil
    }

    func setSearchFilters(_ filters: SearchFilters?) {
        currentSearchFilters = filters
    }

    /// A new query: the previous query's in-flight load is cancelled and can no longer publish,
    /// and it no longer blocks the new query's first page.
    private func beginNewQuery() {
        queryGeneration += 1
        inFlight?.cancel()
        inFlight = nil
        isSearching = false
        hiddenAdultAnime = 0
        hiddenAdultManga = 0
    }

    /// Runs `load` for the current query as the owner's in-flight load. A reset cancels it, and so
    /// does the caller's cancellation (e.g. the view's debounce), as before the extraction.
    /// `isSearching` is cleared only while the query that started the load is still current.
    private func runLoad(_ load: @escaping @MainActor (_ generation: Int) async -> Void) async {
        let generation = queryGeneration
        isSearching = true
        let task = Task { await load(generation) }
        inFlight = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard generation == queryGeneration else { return }
        isSearching = false
        inFlight = nil
    }

    // MARK: - Server-side paged text search

    func fetchNextSearchPage() async {
        if searchMode == .combined {
            await fetchNextCombinedSearchPage()
            return
        }

        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow "filters-only" searches (no text) for category browsing; but don't fetch anything if both are empty.
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        // Avoid hammering the DB for 1-character incremental typing.
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }
        await runLoad { [weak self] generation in
            await self?.loadNextSearchPage(query: trimmedQuery, generation: generation)
        }
    }

    private func loadNextSearchPage(query trimmedQuery: String, generation: Int) async {
        do {
            if searchMode == .manga {
                let result = try await loadMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: searchCursorMangaRank,
                    cursorPopularity: searchCursorMangaPopularity,
                    cursorId: searchCursorMangaId,
                    limit: searchPageSize
                )
                guard generation == queryGeneration else { return }
                let page = result.cards
                if let hidden = result.hiddenAdult { hiddenAdultManga = hidden }
                searchMangaItems.append(contentsOf: page)
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            } else {
                let result = try await loadAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: searchCursorAnimeRank,
                    cursorPopularity: searchCursorAnimePopularity,
                    cursorId: searchCursorAnimeId,
                    limit: searchPageSize
                )
                guard generation == queryGeneration else { return }
                let page = result.cards
                if let hidden = result.hiddenAdult { hiddenAdultAnime = hidden }
                searchAnimeItems.append(contentsOf: page)
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
            }
        } catch {
            guard generation == queryGeneration else { return }
            errorMessage = "Search failed: \(error.localizedDescription)"
            hasMoreSearch = false
            #if DEBUG
            print("❌ Search page error: \(error)")
            #endif
        }
    }

    func fetchNextCombinedSearchPage() async {
        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }
        await runLoad { [weak self] generation in
            await self?.loadNextCombinedSearchPage(query: trimmedQuery, generation: generation)
        }
    }

    /// One combined page: the anime and manga pages run in parallel (they were sequential, so the
    /// "All" scope paid two round trips per page). Each successful side is published; any failure
    /// ends paging and surfaces the message, as before.
    private func loadNextCombinedSearchPage(query trimmedQuery: String, generation: Int) async {
        let filters = currentSearchFilters
        let loadAnime = hasMoreSearchAnime
        let loadManga = hasMoreSearchManga
        let animeCursor = (rank: searchCursorAnimeRank, popularity: searchCursorAnimePopularity, id: searchCursorAnimeId)
        let mangaCursor = (rank: searchCursorMangaRank, popularity: searchCursorMangaPopularity, id: searchCursorMangaId)
        let pageSize = searchPageSize

        async let animeResult: Result<SearchStore.PageResult<AnimeCard>, Error>? = loadAnime
            ? Self.capture {
                try await self.loadAnimePage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: animeCursor.rank,
                    cursorPopularity: animeCursor.popularity,
                    cursorId: animeCursor.id,
                    limit: pageSize
                )
            }
            : nil
        async let mangaResult: Result<SearchStore.PageResult<MangaCard>, Error>? = loadManga
            ? Self.capture {
                try await self.loadMangaPage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: mangaCursor.rank,
                    cursorPopularity: mangaCursor.popularity,
                    cursorId: mangaCursor.id,
                    limit: pageSize
                )
            }
            : nil
        let (anime, manga) = await (animeResult, mangaResult)
        guard generation == queryGeneration else { return }

        var failure: Error?
        switch anime {
        case .success(let result):
            let page = result.cards
            if let hidden = result.hiddenAdult { hiddenAdultAnime = hidden }
            searchAnimeItems.append(contentsOf: page)
            hasMoreSearchAnime = page.count == pageSize
            if let last = page.last {
                searchCursorAnimeRank = last.rank ?? 0
                searchCursorAnimePopularity = last.popularity ?? 0
                searchCursorAnimeId = last.id
            }
        case .failure(let error): failure = error
        case nil: break
        }
        switch manga {
        case .success(let result):
            let page = result.cards
            if let hidden = result.hiddenAdult { hiddenAdultManga = hidden }
            searchMangaItems.append(contentsOf: page)
            hasMoreSearchManga = page.count == pageSize
            if let last = page.last {
                searchCursorMangaRank = last.rank ?? 0
                searchCursorMangaPopularity = last.popularity ?? 0
                searchCursorMangaId = last.id
            }
        case .failure(let error): failure = failure ?? error
        case nil: break
        }

        if let failure {
            errorMessage = "Search failed: \(failure.localizedDescription)"
            hasMoreSearch = false
            hasMoreSearchAnime = false
            hasMoreSearchManga = false
            #if DEBUG
            print("❌ Combined search error: \(failure)")
            #endif
            return
        }
        hasMoreSearch = hasMoreSearchAnime || hasMoreSearchManga
    }

    /// Runs `work`, capturing its outcome (for the parallel combined pages).
    private static func capture<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    // MARK: - Search refresh (keeps old results on transient failures)

    func refreshSearch() async {
        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard !isSearching else { return }
        await runLoad { [weak self] generation in
            await self?.loadRefresh(query: trimmedQuery, generation: generation)
        }
    }

    private func loadRefresh(query trimmedQuery: String, generation: Int) async {
        let oldAnime = searchAnimeItems
        let oldManga = searchMangaItems
        let oldHasMore = hasMoreSearch
        let oldHasMoreAnime = hasMoreSearchAnime
        let oldHasMoreManga = hasMoreSearchManga

        do {
            switch searchMode {
            case .anime:
                searchCursorAnimeRank = nil
                searchCursorAnimePopularity = nil
                searchCursorAnimeId = nil
                let result = try await loadAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
                guard generation == queryGeneration else { return }
                let page = result.cards
                hiddenAdultAnime = result.hiddenAdult ?? 0
                searchAnimeItems = page
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
            case .manga:
                searchCursorMangaRank = nil
                searchCursorMangaPopularity = nil
                searchCursorMangaId = nil
                let result = try await loadMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
                guard generation == queryGeneration else { return }
                let page = result.cards
                hiddenAdultManga = result.hiddenAdult ?? 0
                searchMangaItems = page
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            case .combined:
                // Reset both cursors.
                searchCursorAnimeRank = nil
                searchCursorAnimePopularity = nil
                searchCursorAnimeId = nil
                searchCursorMangaRank = nil
                searchCursorMangaPopularity = nil
                searchCursorMangaId = nil

                // Both first pages in parallel (all-or-error, as before).
                let filters = currentSearchFilters
                let pageSize = searchPageSize
                async let animeFirst = loadAnimePage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: pageSize
                )
                async let mangaFirst = loadMangaPage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: pageSize
                )
                let (animeResult, mangaResult) = try await (animeFirst, mangaFirst)
                guard generation == queryGeneration else { return }
                let animePage = animeResult.cards
                let mangaPage = mangaResult.cards
                hiddenAdultAnime = animeResult.hiddenAdult ?? 0
                hiddenAdultManga = mangaResult.hiddenAdult ?? 0
                searchAnimeItems = animePage
                searchMangaItems = mangaPage
                hasMoreSearchAnime = animePage.count == searchPageSize
                hasMoreSearchManga = mangaPage.count == searchPageSize
                hasMoreSearch = hasMoreSearchAnime || hasMoreSearchManga

                if let last = animePage.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
                if let last = mangaPage.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            }
        } catch {
            guard generation == queryGeneration else { return }
            // Restore old state and surface a message.
            searchAnimeItems = oldAnime
            searchMangaItems = oldManga
            hasMoreSearch = oldHasMore
            hasMoreSearchAnime = oldHasMoreAnime
            hasMoreSearchManga = oldHasMoreManga
            errorMessage = "Search failed: \(error.localizedDescription)"
            #if DEBUG
            print("❌ search refresh: \(error)")
            #endif
        }
    }

    // MARK: - Owner paging: v2 first page (W4) with v1 fallback

    /// A page plus the hidden-18+ count (`nil` when v2 was not asked or carried no count).
    struct PageResult<Card: Sendable>: Sendable {
        let cards: [Card]
        let hiddenAdult: Int?
    }

    /// First pages (no cursor) of the owner's own paging ask v2 while the flag is on and v2 is not
    /// remembered as undeployed; page 2+ and every external caller stay on v1.
    private func useSearchV2(cursorId: Int?, now: Date = Date()) -> Bool {
        guard cursorId == nil, adultNoticeEnabled() else { return false }
        guard let at = searchV2UndeployedAt else { return true }
        if now.timeIntervalSince(at) < Self.undeployedRetryInterval { return false }
        searchV2UndeployedAt = nil
        return true
    }

    private func loadAnimePage(
        query: String, filters: SearchFilters?, cursorRank: Double?, cursorPopularity: Int?, cursorId: Int?, limit: Int
    ) async throws -> PageResult<AnimeCard> {
        if useSearchV2(cursorId: cursorId) {
            do {
                let client = try requiredClient()
                let params = RPCSearchAnimePageParams(
                    p_query: query, p_limit: max(1, min(50, limit)),
                    p_cursor_rank: cursorRank, p_cursor_popularity: cursorPopularity, p_cursor_id: cursorId,
                    p_trending: filters?.trending ?? false, p_new_season: filters?.newSeason ?? false,
                    p_classics: filters?.classics ?? false, p_hidden_gems: filters?.hiddenGems ?? false,
                    p_airing_only: filters?.airingOnly ?? false, p_season: filters?.seasonName, p_season_year: filters?.seasonYear
                )
                let perf = KuroPerf.begin("rpc.search_anime_page_v2")
                let page: SearchPageV2<AnimeCard>
                do {
                    page = try await client.rpc("search_anime_page_v2", params: params).execute().value
                    KuroPerf.end(perf, message: "ok \(page.items.count)")
                } catch {
                    KuroPerf.end(perf, message: "error")
                    throw error
                }
                return PageResult(cards: page.items, hiddenAdult: page.hiddenAdult)
            } catch {
                guard ReleaseFailure.classify(error) == .notDeployed else { throw error }
                searchV2UndeployedAt = Date()
            }
        }
        let cards = try await fetchSearchAnimePage(
            query: query, filters: filters, cursorRank: cursorRank,
            cursorPopularity: cursorPopularity, cursorId: cursorId, limit: limit
        )
        return PageResult(cards: cards, hiddenAdult: nil)
    }

    private func loadMangaPage(
        query: String, filters: SearchFilters?, cursorRank: Double?, cursorPopularity: Int?, cursorId: Int?, limit: Int
    ) async throws -> PageResult<MangaCard> {
        if useSearchV2(cursorId: cursorId) {
            do {
                let client = try requiredClient()
                let params = RPCSearchMangaPageParams(
                    p_query: query, p_limit: max(1, min(50, limit)),
                    p_cursor_rank: cursorRank, p_cursor_popularity: cursorPopularity, p_cursor_id: cursorId,
                    p_trending: filters?.trending ?? false, p_new_season: filters?.newSeason ?? false,
                    p_classics: filters?.classics ?? false, p_hidden_gems: filters?.hiddenGems ?? false
                )
                let perf = KuroPerf.begin("rpc.search_manga_page_v2")
                let page: SearchPageV2<MangaCard>
                do {
                    page = try await client.rpc("search_manga_page_v2", params: params).execute().value
                    KuroPerf.end(perf, message: "ok \(page.items.count)")
                } catch {
                    KuroPerf.end(perf, message: "error")
                    throw error
                }
                return PageResult(cards: page.items, hiddenAdult: page.hiddenAdult)
            } catch {
                guard ReleaseFailure.classify(error) == .notDeployed else { throw error }
                searchV2UndeployedAt = Date()
            }
        }
        let cards = try await fetchSearchMangaPage(
            query: query, filters: filters, cursorRank: cursorRank,
            cursorPopularity: cursorPopularity, cursorId: cursorId, limit: limit
        )
        return PageResult(cards: cards, hiddenAdult: nil)
    }

    // MARK: - Search pages (stateless transport; also used by the club rail search sheet)

    func fetchSearchAnimePage(
        query: String,
        filters: SearchFilters?,
        cursorRank: Double?,
        cursorPopularity: Int?,
        cursorId: Int?,
        limit: Int
    ) async throws -> [AnimeCard] {
        let perf = KuroPerf.begin("rpc.search_anime_page")
        do {
            let client = try requiredClient()
            let params = RPCSearchAnimePageParams(
                p_query: query,
                p_limit: max(1, min(50, limit)),
                p_cursor_rank: cursorRank,
                p_cursor_popularity: cursorPopularity,
                p_cursor_id: cursorId,
                p_trending: filters?.trending ?? false,
                p_new_season: filters?.newSeason ?? false,
                p_classics: filters?.classics ?? false,
                p_hidden_gems: filters?.hiddenGems ?? false,
                p_airing_only: filters?.airingOnly ?? false,
                p_season: filters?.seasonName,
                p_season_year: filters?.seasonYear
            )
            let page: [AnimeCard] = try await client
                .rpc("search_anime_page", params: params)
                .execute()
                .value
            KuroPerf.end(perf, message: "ok \(page.count)")
            return page
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    func fetchSearchMangaPage(
        query: String,
        filters: SearchFilters?,
        cursorRank: Double?,
        cursorPopularity: Int?,
        cursorId: Int?,
        limit: Int
    ) async throws -> [MangaCard] {
        let perf = KuroPerf.begin("rpc.search_manga_page")
        do {
            let client = try requiredClient()
            let params = RPCSearchMangaPageParams(
                p_query: query,
                p_limit: max(1, min(50, limit)),
                p_cursor_rank: cursorRank,
                p_cursor_popularity: cursorPopularity,
                p_cursor_id: cursorId,
                p_trending: filters?.trending ?? false,
                p_new_season: filters?.newSeason ?? false,
                p_classics: filters?.classics ?? false,
                p_hidden_gems: filters?.hiddenGems ?? false
            )
            let page: [MangaCard] = try await client
                .rpc("search_manga_page", params: params)
                .execute()
                .value
            KuroPerf.end(perf, message: "ok \(page.count)")
            return page
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }
}
#endif
