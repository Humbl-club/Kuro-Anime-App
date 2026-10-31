import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Discovery + Browse
// Owner of the Discover page reads (single-call bundle, the Auth trending rail, the daily
// feature and the Stage 4 realm surfaces) and of the Browse keyset pages.
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

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, library: LibraryStore) {
        self.client = client
        self.accountSession = accountSession
        self.library = library
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
    }

    /// Sheds the bundle cache under memory pressure.
    func trimCachesForMemoryPressure() {
        discoverBundleCache.removeAll()
    }

    // MARK: - Discover bundle (single call)

    func fetchDiscoverBundle(limit: Int = 30, hours: Int = 24, force: Bool = false) async -> DiscoverBundle? {
        // The bundle carries the per-user NEW TO YOU rail: cache entries and in-flight loads are
        // keyed by the account that asked (nil context = signed-out/anonymous request), and only
        // the account that started the request may cache it.
        let context = accountSession.current
        let user = context?.userId ?? "anon"
        let key = "discover_bundle|\(user)|\(max(1, min(60, limit)))|\(max(1, min(168, hours)))"
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
                let bundle: DiscoverBundle = try await withRetry {
                    try await client
                        .rpc("discover_bundle", params: params)
                        .execute()
                        .value
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
            return []
        }
    }

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
            return []
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
}
#endif
