import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Discovery + Browse
// Owner of the Discover page reads (single-call bundle, the Auth trending rail, the daily
// feature and the Stage 4 realm surfaces), of the Browse keyset pages, of the stated air times of
// the Airing today rail, and of the per-account recent searches on this device.
//
// One bundle per launch: `discover_bundle` writes (rail impressions, NEW TO YOU rotation), so the
// pages read it through `ensureDiscoverBundle()` (the launch bundle, whatever its age), only pull
// to refresh forces a new read, and the call is never wrapped in `withRetry` (only a failure that
// proves the request never left the device is repeated, once).
//
// Account scope: the rails over public tables are public data. Personalised results are
// account-scoped: the Discover bundle (NEW TO YOU), the because-you rail, tonight's shelf and the
// realm hidden gem. The bundle cache and its in-flight
// loads are keyed by user id and dropped by `AccountScopedState`; every personalised completion
// captures its `AccountContext` at start and is handed out only while that context is current.
//
// Default formats: anime Discover/Browse requests never ask for SPECIAL / MUSIC / TV_SHORT; the
// server excludes them unless Browse sends an explicit `p_format`.

@MainActor
@Observable
final class DiscoveryStore: AccountScopedState, MemoryPressureTrimmable {
    enum BrowseSort: String, CaseIterable {
        case popular = "POPULAR"
        case trending = "TRENDING"
        case topRated = "TOP RATED"
        case newlyAdded = "NEW"

        var orderColumn: String {
            switch self {
            case .popular: return "popularity"
            case .trending: return "trending"
            case .topRated: return "average_score"
            case .newlyAdded: return "created_at"
            }
        }

        var rpcKey: String {
            switch self {
            case .popular: return "popular"
            case .trending: return "trending"
            case .topRated: return "topRated"
            case .newlyAdded: return "newlyAdded"
            }
        }
    }

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every read fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// The shared account coordinator (personalised completions are checked against it).
    let accountSession: AccountSessionCoordinator
    /// The account Library. Composition injects it with this owner; no remaining Discovery read filters on it.
    let library: LibraryStore

    /// Device storage of the per-account recent searches (tests pass their own suite).
    @ObservationIgnored private let defaults: UserDefaults

    init(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        library: LibraryStore,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.accountSession = accountSession
        self.library = library
        self.defaults = defaults
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    /// Personalised (NEW TO YOU) bundles, keyed by the requesting user ("anon" when signed out).
    var discoverBundleCache: [String: TimedCache<DiscoverBundle>] = [:]
    /// In-flight bundle loads: joined only by the same key and account context.
    let discoverBundleLoads = AccountScopedLoads<String, DiscoverBundle?>()

    // MARK: AccountScopedState

    func cancelAccountWork() {
        discoverBundleLoads.cancelAll()
    }

    func clearPrivateState() {
        discoverBundleCache.removeAll()
        recentSearches = []
        recentSearchesKey = nil
    }

    /// Sheds the bundle cache and the airing slots under memory pressure (both are re-read on demand).
    func trimCachesForMemoryPressure() {
        discoverBundleCache.removeAll()
        airingSlots.removeAll()
        airingSlotIdsRead.removeAll()
        airingSlotsDay = nil
    }

    // MARK: - Discover bundle (single call)

    /// The Discover page's bundle, read at most once per launch and account.
    ///
    /// `discover_bundle` is a writer (it records rail impressions and rotates NEW TO YOU), so the
    /// pages that show it (Discover, Taste) and the launch warm-up share one read: the account's last
    /// successful bundle is returned for the rest of the session regardless of its age, an in-flight
    /// load is joined, and only a missing bundle starts a read. A deliberate reload (pull to refresh)
    /// uses `fetchDiscoverBundle(force: true)`. The entry is dropped on account change
    /// (`clearPrivateState`) and under memory pressure.
    func ensureDiscoverBundle(limit: Int = 30, hours: Int = 24) async -> DiscoverBundle? {
        let key = Self.bundleKey(user: accountSession.current?.userId, limit: limit, hours: hours)
        if let loaded = discoverBundleCache[key] {
            return loaded.value
        }
        return await fetchDiscoverBundle(limit: limit, hours: hours)
    }

    /// The cache and in-flight key of one account's bundle request ("anon" when signed out).
    nonisolated static func bundleKey(user: String?, limit: Int, hours: Int) -> String {
        "discover_bundle|\(user ?? "anon")|\(max(1, min(60, limit)))|\(max(1, min(168, hours)))"
    }

    func fetchDiscoverBundle(limit: Int = 30, hours: Int = 24, force: Bool = false) async -> DiscoverBundle? {
        // The bundle carries the per-user NEW TO YOU rail: cache entries and in-flight loads are
        // keyed by the account that asked (nil context = signed-out/anonymous request), and only
        // the account that started the request may cache it.
        let context = accountSession.current
        let key = Self.bundleKey(user: context?.userId, limit: limit, hours: hours)
        let now = Date()
        if !force, let cached = discoverBundleCache[key], now.timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        let bundle = try? await discoverBundleLoads.run(key: key, context: context) { @MainActor [weak self] in
            guard let self else { return nil }
            let perf = KuroPerf.begin("rpc.discover_bundle")
            do {
                let client = try self.requiredClient()
                let params = RPCDiscoverBundleParams(
                    p_limit: max(1, min(60, limit)),
                    p_hours: max(1, min(168, hours))
                )
                // Not `withRetry`: the RPC writes impressions, and a timed-out attempt may already
                // have run on the server. Only a failure that proves the request never left the
                // device is repeated, once.
                let bundle: DiscoverBundle
                do {
                    bundle = try await client.rpc("discover_bundle", params: params).execute().value
                } catch where DiscoveryTransport.failedBeforeSending(error) {
                    try await Task.sleep(for: .milliseconds(500))
                    bundle = try await client.rpc("discover_bundle", params: params).execute().value
                }
                KuroPerf.end(perf, message: "ok")
                guard self.accountSession.isCurrent(context) else { return nil }
                self.discoverBundleCache[key] = TimedCache(value: bundle, storedAt: now)
                trimTimedCache(&self.discoverBundleCache, maxEntries: 6)
                return bundle
            } catch {
                #if DEBUG
                print("❌ discover_bundle rpc: \(error)")
                #endif
                KuroPerf.end(perf, message: "error")
                return nil
            }
        }
        return bundle ?? nil
    }

    // MARK: - Server-driven Discover sections (Anime)

    func fetchTrendingAnime(limit: Int = 20, onlyAiring: Bool = false, genre: String? = nil) async -> [Anime] {
        do {
            let client = try requiredClient()
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            var q = client.from("mv_anime_trending").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let statusQuery = onlyAiring ? q.eq("status", value: "RELEASING") : q
            let orderedQuery = statusQuery.order("trending", ascending: false)
            let rows: [Anime] = try await orderedQuery.range(from: 0, to: max(0, limit - 1)).execute().value
            return DiscoveryContentRules.sanitizeAnimeForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ trending fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    // MARK: - Browse (server-driven keyset paging + filters)
    // `format == nil` asks for the default surface (the server hides anime SPECIAL / MUSIC /
    // TV_SHORT); an explicit Browse format filter is sent as `p_format`.

    /// One Browse page, or `[]` on failure (kept for existing callers; the Browse page uses
    /// `browseAnimePage`, which tells a failure from an empty page).
    func fetchBrowseAnimePageKeyset(
        genre: String?,
        status: String?,
        minEpisodes: Int?,
        maxEpisodes: Int?,
        sort: BrowseSort = .popular,
        cursorInt: Int?,
        cursorDate: Date?,
        cursorId: Int?,
        minYear: Int? = nil,
        maxYear: Int? = nil,
        format: String? = nil,
        limit: Int
    ) async -> [AnimeCard] {
        await browseAnimePage(
            genre: genre, status: status, minEpisodes: minEpisodes, maxEpisodes: maxEpisodes, sort: sort,
            cursorInt: cursorInt, cursorDate: cursorDate, cursorId: cursorId,
            minYear: minYear, maxYear: maxYear, format: format, limit: limit
        ) ?? []
    }

    /// One Browse page; nil when the read failed (an empty array is a real empty page).
    func browseAnimePage(
        genre: String?,
        status: String?,
        minEpisodes: Int?,
        maxEpisodes: Int?,
        sort: BrowseSort = .popular,
        cursorInt: Int?,
        cursorDate: Date?,
        cursorId: Int?,
        minYear: Int? = nil,
        maxYear: Int? = nil,
        format: String? = nil,
        limit: Int
    ) async -> [AnimeCard]? {
        do {
            let client = try requiredClient()
            let perf = KuroPerf.begin("rpc.browse_anime_page")
            let params = RPCBrowseAnimePageParams(
                p_genre: genre,
                p_status: status,
                p_min_episodes: minEpisodes,
                p_max_episodes: maxEpisodes,
                p_sort: sort.rpcKey,
                p_cursor_int: cursorInt,
                p_cursor_ts: cursorDate,
                p_cursor_id: cursorId,
                p_min_year: minYear,
                p_max_year: maxYear,
                p_format: format,
                p_limit: max(1, min(120, limit))
            )
            let rows: [AnimeCard] = try await client.rpc("browse_anime_page", params: params).execute().value
            KuroPerf.end(perf, message: "ok")
            return rows
        } catch {
            #if DEBUG
            print("❌ browse_anime_page rpc: \(error)")
            #endif
            return nil
        }
    }

    /// One manga Browse page, or `[]` on failure (see `browseMangaPage`).
    func fetchBrowseMangaPageKeyset(
        genre: String?,
        status: String?,
        minChapters: Int?,
        maxChapters: Int?,
        sort: BrowseSort = .popular,
        cursorInt: Int?,
        cursorDate: Date?,
        cursorId: Int?,
        minYear: Int? = nil,
        maxYear: Int? = nil,
        format: String? = nil,
        limit: Int
    ) async -> [MangaCard] {
        await browseMangaPage(
            genre: genre, status: status, minChapters: minChapters, maxChapters: maxChapters, sort: sort,
            cursorInt: cursorInt, cursorDate: cursorDate, cursorId: cursorId,
            minYear: minYear, maxYear: maxYear, format: format, limit: limit
        ) ?? []
    }

    /// One manga Browse page; nil when the read failed (an empty array is a real empty page).
    func browseMangaPage(
        genre: String?,
        status: String?,
        minChapters: Int?,
        maxChapters: Int?,
        sort: BrowseSort = .popular,
        cursorInt: Int?,
        cursorDate: Date?,
        cursorId: Int?,
        minYear: Int? = nil,
        maxYear: Int? = nil,
        format: String? = nil,
        limit: Int
    ) async -> [MangaCard]? {
        do {
            let client = try requiredClient()
            let perf = KuroPerf.begin("rpc.browse_manga_page")
            let params = RPCBrowseMangaPageParams(
                p_genre: genre,
                p_status: status,
                p_min_chapters: minChapters,
                p_max_chapters: maxChapters,
                p_sort: sort.rpcKey,
                p_cursor_int: cursorInt,
                p_cursor_ts: cursorDate,
                p_cursor_id: cursorId,
                p_min_year: minYear,
                p_max_year: maxYear,
                p_format: format,
                p_limit: max(1, min(120, limit))
            )
            let rows: [MangaCard] = try await client.rpc("browse_manga_page", params: params).execute().value
            KuroPerf.end(perf, message: "ok")
            return rows
        } catch {
            #if DEBUG
            print("❌ browse_manga_page rpc: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Daily feature + realm surfaces (Discover P1 / Stage 4)

    /// nil on error OR empty rotation (no eligible boosts) — callers fall back
    /// to the legacy hero in both cases.
    func fetchDailyFeature() async -> DailyFeature? {
        do {
            let client = try requiredClient()
            let rows: [DailyFeature] = try await client
                .rpc("fetch_daily_feature")
                .execute()
                .value
            return rows.first
        } catch {
            #if DEBUG
            print("❌ fetchDailyFeature error: \(error)")
            #endif
            return nil
        }
    }

    /// nil on error, [] when the user is below the evidence floor — callers
    /// keep the editorial NEW TO YOU rail in both cases. Personalised: a rail fetched for an
    /// account that is no longer current is not handed out (nil).
    func fetchBecauseYouRail(limit: Int = 12) async -> [BecauseYouCard]? {
        let context = accountSession.current
        do {
            let client = try requiredClient()
            let rows: [BecauseYouCard] = try await client
                .rpc("fetch_because_you_rail", params: RPCFetchBecauseYouRailParams(p_limit: limit))
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return nil }
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchBecauseYouRail error: \(error)")
            #endif
            return nil
        }
    }

    /// Stage 4 The Shelf — tonight's realm rail. nil on error; [] when empty. Personalised: a shelf
    /// fetched for an account that is no longer current is not handed out (nil).
    func fetchTonightShelf(limit: Int = 12) async -> [TonightShelfCard]? {
        let context = accountSession.current
        do {
            let client = try requiredClient()
            let rows: [TonightShelfCard] = try await client
                .rpc("fetch_tonight_shelf", params: RPCFetchTonightShelfParams(p_limit: limit))
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return nil }
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchTonightShelf error: \(error)")
            #endif
            return nil
        }
    }

    /// Stage 4 Hidden Gem — 0 or 1 weekly pick in tonight's realm. Personalised: a pick fetched for
    /// an account that is no longer current is not handed out (nil).
    func fetchRealmHiddenGem() async -> RealmHiddenGem? {
        let context = accountSession.current
        do {
            let client = try requiredClient()
            let rows: [RealmHiddenGem] = try await client
                .rpc("fetch_realm_hidden_gem")
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return nil }
            return rows.first
        } catch {
            #if DEBUG
            print("❌ fetchRealmHiddenGem error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Airing today: stated air times (public catalogue data)

    /// Stated air times of the "Airing today" titles read this session, by anime id. Public data
    /// (not account-scoped); trimmed under memory pressure.
    private(set) var airingSlots: [Int: DiscoverAiringSlot] = [:]
    /// Ids already asked for on `airingSlotsDay` (a title without a stated time is not asked again
    /// that day).
    @ObservationIgnored private var airingSlotIdsRead: Set<Int> = []
    /// The rail day (Berlin) the slots were read on; a new day starts a fresh read.
    @ObservationIgnored private var airingSlotsDay: DateComponents? = nil

    private struct AiringRow: Decodable {
        let id: Int
        let nextAiringAt: Date?
        let nextEpisodeNumber: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case nextAiringAt = "next_airing_at"
            case nextEpisodeNumber = "next_episode_number"
        }
    }

    /// Reads the stated next air time of up to 20 rail titles not read yet this session. The bundle
    /// rows carry no time, so the rail can only be ordered by air time from this read. A failure
    /// leaves the ids unread (a later load asks again) and the rail in server order.
    func loadAiringSlots(for animeIds: [Int], now: Date = Date()) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DiscoverAiringOrder.railTimeZone
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        if day != airingSlotsDay {
            airingSlotsDay = day
            airingSlots.removeAll()
            airingSlotIdsRead.removeAll()
        }
        let wanted = Array(animeIds.filter { !airingSlotIdsRead.contains($0) }.prefix(20))
        guard !wanted.isEmpty else { return }
        do {
            let client = try requiredClient()
            let rows: [AiringRow] = try await client
                .from("anime")
                .select("id,next_airing_at,next_episode_number")
                .in("id", values: wanted)
                .execute()
                .value
            airingSlotIdsRead.formUnion(wanted)
            for row in rows {
                if let at = row.nextAiringAt {
                    airingSlots[row.id] = DiscoverAiringSlot(animeId: row.id, airingAt: at, episode: row.nextEpisodeNumber)
                } else {
                    airingSlots[row.id] = nil
                }
            }
        } catch {
            #if DEBUG
            print("❌ airing slots read: \(error)")
            #endif
        }
    }

    // MARK: - Recent searches (this device, per account)

    /// The signed-in account's recent searches on this device, newest first. Empty when signed out.
    private(set) var recentSearches: [String] = []
    /// The storage key `recentSearches` was loaded from (nil: not loaded / signed out).
    @ObservationIgnored private var recentSearchesKey: String? = nil

    /// Loads the current account's list (call when the search surface appears).
    func loadRecentSearches() {
        let key = RecentSearchList.storageKey(userId: accountSession.current?.userId)
        recentSearchesKey = key
        guard let key else {
            recentSearches = []
            return
        }
        recentSearches = RecentSearchList(defaults.stringArray(forKey: key) ?? []).queries
    }

    /// Records a search the person committed to (submitted, or opened a result of). Not called on
    /// the typing debounce, so partial words are never stored.
    func recordRecentSearch(_ query: String) {
        guard let key = RecentSearchList.storageKey(userId: accountSession.current?.userId) else { return }
        var list = RecentSearchList(key == recentSearchesKey ? recentSearches : (defaults.stringArray(forKey: key) ?? []))
        list.record(query)
        persistRecentSearches(list, key: key)
    }

    func removeRecentSearch(_ query: String) {
        guard let key = RecentSearchList.storageKey(userId: accountSession.current?.userId) else { return }
        var list = RecentSearchList(key == recentSearchesKey ? recentSearches : (defaults.stringArray(forKey: key) ?? []))
        list.remove(query)
        persistRecentSearches(list, key: key)
    }

    func clearRecentSearches() {
        guard let key = RecentSearchList.storageKey(userId: accountSession.current?.userId) else { return }
        persistRecentSearches(RecentSearchList(), key: key)
    }

    private func persistRecentSearches(_ list: RecentSearchList, key: String) {
        if list.queries.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(list.queries, forKey: key)
        }
        recentSearchesKey = key
        recentSearches = list.queries
    }
}
#endif
