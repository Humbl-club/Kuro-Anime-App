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

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none (also used by
    /// `DiscoveryStore+Usability.swift`).
    func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    /// Personalised (NEW TO YOU) bundles, keyed by the requesting user ("anon" when signed out).
    var discoverBundleCache: [String: TimedCache<DiscoverBundle>] = [:]
    /// In-flight bundle loads: joined only by the same key and account context.
    let discoverBundleLoads = AccountScopedLoads<String, DiscoverBundle?>()
    /// Per-account daily feature cache (Berlin rail day), so Discover opens warm at 0 ms.
    @ObservationIgnored private var dailyFeatureCache: [String: TimedCache<DailyFeature?>] = [:]

    /// Franchise component of each title read so far (`media_franchise_ids_v1`, public catalogue
    /// data: kept across sign-out, shed under memory pressure). See `DiscoveryStore+Usability.swift`.
    var franchiseIds: [MediaKey: Int] = [:]
    /// Prepared Discover readers that answered "not deployed", with the time (retried after
    /// `discoverUndeployedRetryInterval`).
    @ObservationIgnored var undeployedDiscoverContracts: [String: Date] = [:]

    /// Zero-I/O metadata lookup over the in-memory Discover bundle for 0 ms optimistic Home inserts.
    func cachedHomeCardSeed(for key: MediaKey) -> HomeCardSeed? {
        for entry in discoverBundleCache.values {
            let bundle = entry.value
            switch key.kind {
            case .anime:
                let pools = [
                    bundle.anime.currentSeason, bundle.anime.trending, bundle.anime.essentials,
                    bundle.anime.newToYou, bundle.anime.newlyAdded, bundle.anime.classics,
                    bundle.anime.topRated, bundle.anime.airingToday,
                ]
                for pool in pools {
                    if let card = pool.first(where: { $0.id == key.id }) {
                        return HomeCardSeed(
                            title: card.title,
                            coverImage: card.imageURL,
                            bannerImage: card.bannerImage,
                            format: card.format,
                            episodes: card.episodes,
                            chapters: nil,
                            volumes: nil
                        )
                    }
                }
            case .manga:
                let pools = [
                    bundle.manga.trending, bundle.manga.newlyAdded, bundle.manga.essentials,
                    bundle.manga.newToYou, bundle.manga.classics, bundle.manga.topRated,
                ]
                for pool in pools {
                    if let card = pool.first(where: { $0.id == key.id }) {
                        return HomeCardSeed(
                            title: card.title,
                            coverImage: card.imageURL,
                            bannerImage: nil,
                            format: card.format,
                            episodes: nil,
                            chapters: card.chapters,
                            volumes: nil
                        )
                    }
                }
            }
        }
        return nil
    }

    /// Zero-I/O deduplicated pool of in-memory Discover cards for 0 ms Search typing previews and
    /// the idle Popular strip (no extra network call).
    func cachedSearchPreviewCards() -> (anime: [AnimeCard], manga: [MangaCard]) {
        var animeSeen: Set<Int> = []
        var mangaSeen: Set<Int> = []
        var animeOut: [AnimeCard] = []
        var mangaOut: [MangaCard] = []
        for entry in discoverBundleCache.values.sorted(by: { $0.storedAt > $1.storedAt }) {
            let bundle = entry.value
            let animePools = [
                bundle.anime.trending, bundle.anime.currentSeason, bundle.anime.essentials,
                bundle.anime.newToYou, bundle.anime.newlyAdded, bundle.anime.classics,
                bundle.anime.topRated,
            ]
            for pool in animePools {
                for card in pool where animeSeen.insert(card.id).inserted {
                    animeOut.append(card)
                }
            }
            let mangaPools = [
                bundle.manga.trending, bundle.manga.essentials, bundle.manga.newToYou,
                bundle.manga.newlyAdded, bundle.manga.classics, bundle.manga.topRated,
            ]
            for pool in mangaPools {
                for card in pool where mangaSeen.insert(card.id).inserted {
                    mangaOut.append(card)
                }
            }
        }
        return (animeOut, mangaOut)
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        discoverBundleLoads.cancelAll()
    }

    func clearPrivateState() {
        discoverBundleCache.removeAll()
        dailyFeatureCache.removeAll()
        recentSearches = []
        recentSearchesKey = nil
    }

    /// Confirmed account deletion: removes the deleted account's recent searches from this device
    /// (they survive sign-out on purpose, so a returning account keeps them).
    func removeDeletedAccountData(userId: String) async throws {
        guard let key = RecentSearchList.storageKey(userId: userId) else { return }
        defaults.removeObject(forKey: key)
        if recentSearchesKey == key {
            recentSearches = []
            recentSearchesKey = nil
        }
    }

    /// Sheds the airing slots and other accounts' bundles under memory pressure. The current
    /// account's launch bundle is kept (it is small, and dropping it would make the next
    /// `ensureDiscoverBundle` call the impression-writing RPC again).
    func trimCachesForMemoryPressure() {
        let keep = Self.bundleKeyPrefix(user: accountSession.current?.userId)
        discoverBundleCache = discoverBundleCache.filter { $0.key.hasPrefix(keep) }
        airingSlots.removeAll()
        airingSlotIdsRead.removeAll()
        airingSlotsDay = nil
        franchiseIds.removeAll()
    }

    // MARK: - Discover bundle (single call)

    /// The Discover page's bundle, read at most once per launch and account.
    ///
    /// `discover_bundle` is a writer (it records rail impressions and rotates NEW TO YOU), so the
    /// pages that show it (Discover, Taste) and the launch warm-up share one read: the account's last
    /// successful bundle is returned for the rest of the session regardless of its age, an in-flight
    /// load is joined, and only a missing bundle starts a read. A deliberate reload (pull to refresh)
    /// uses `fetchDiscoverBundle(force: true)`. The entry is dropped on account change
    /// (`clearPrivateState`) and kept under memory pressure. A bundle stored on an earlier Berlin
    /// day counts as missing, so "Airing today" never shows yesterday's set after the app stayed
    /// alive past midnight (still at most one read per day and account).
    func ensureDiscoverBundle(limit: Int = 30, hours: Int = 24, now: Date = Date()) async -> DiscoverBundle? {
        let key = Self.bundleKey(user: accountSession.current?.userId, limit: limit, hours: hours)
        if let loaded = discoverBundleCache[key], Self.isSameRailDay(loaded.storedAt, now) {
            return loaded.value
        }
        return await fetchDiscoverBundle(limit: limit, hours: hours)
    }

    /// Synchronous 0 ms lookup for today's already-warmed Discover bundle (nil when not cached yet).
    func cachedCurrentDayBundle(limit: Int = 30, hours: Int = 24, now: Date = Date()) -> DiscoverBundle? {
        let key = Self.bundleKey(user: accountSession.current?.userId, limit: limit, hours: hours)
        guard let loaded = discoverBundleCache[key], Self.isSameRailDay(loaded.storedAt, now) else { return nil }
        return loaded.value
    }

    /// Synchronous 0 ms lookup for today's cached daily feature resolution (nil when not resolved yet).
    func cachedCurrentDayDailyFeature(now: Date = Date()) -> (resolved: Bool, feature: DailyFeature?) {
        guard let userId = accountSession.current?.userId else { return (true, nil) }
        guard let entry = dailyFeatureCache[userId], Self.isSameRailDay(entry.storedAt, now) else {
            return (false, nil)
        }
        return (true, entry.value)
    }

    /// Whether the signed-in account's bundle was stored on `now`'s rail day (false: none yet, or one
    /// from an earlier Berlin day). Discover asks this when a new visit starts (D18): a page left alive
    /// overnight reads the new day's issue instead of rebuilding yesterday's.
    func hasCurrentDayBundle(limit: Int = 30, hours: Int = 24, now: Date = Date()) -> Bool {
        let key = Self.bundleKey(user: accountSession.current?.userId, limit: limit, hours: hours)
        guard let loaded = discoverBundleCache[key] else { return false }
        return Self.isSameRailDay(loaded.storedAt, now)
    }

    /// The cache and in-flight key of one account's bundle request ("anon" when signed out).
    nonisolated static func bundleKey(user: String?, limit: Int, hours: Int) -> String {
        "\(bundleKeyPrefix(user: user))\(max(1, min(60, limit)))|\(max(1, min(168, hours)))"
    }

    /// The part of `bundleKey` that names the account.
    nonisolated static func bundleKeyPrefix(user: String?) -> String {
        "discover_bundle|\(user ?? "anon")|"
    }

    /// Whether two instants fall on the same rail day (Europe/Berlin).
    nonisolated static func isSameRailDay(_ a: Date, _ b: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DiscoverAiringOrder.railTimeZone
        return calendar.isDate(a, inSameDayAs: b)
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

    /// Direct cover-guaranteed "Just added" query over `public.anime` used when `discover_bundle`'s
    /// raw `newly_added` rail contains unhydrated rows without a renderable cover image.
    func fetchRenderableNewlyAddedAnime(limit: Int = 20) async -> [AnimeCard] {
        let clamped = max(1, min(40, limit))
        do {
            let client = try requiredClient()
            let rows: [AnimeCard] = try await client
                .from("anime")
                .select("id,title_english,title_romaji,title_native,cover_image_large,cover_image_medium,banner_image,format,status,episode_count:episodes,season_year,start_date_year,average_score,popularity,trending,favourites,genres,created_at")
                .eq("is_adult", value: false)
                .not("cover_image_large", operator: .is, value: "null")
                .not("cover_image_large", operator: .ilike, value: "%anilist.co%")
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .limit(clamped * 2)
                .execute()
                .value
            let filtered = rows.filter { card in
                let genres = Set((card.genres ?? []).map { $0.lowercased() })
                let format = card.format?.uppercased() ?? ""
                return ImagePipeline.hasRenderableArtwork(card.imageURL)
                    && !genres.contains("hentai")
                    && !genres.contains("ecchi")
                    && !["SPECIAL", "MUSIC", "TV_SHORT"].contains(format)
            }
            return Array(filtered.prefix(clamped))
        } catch {
            #if DEBUG
            print("❌ fetchRenderableNewlyAddedAnime error: \(error)")
            #endif
            return []
        }
    }

    /// Direct cover-guaranteed "Just added" query over `public.manga` used when `discover_bundle`'s
    /// raw `newly_added` rail contains unhydrated rows without a renderable cover image.
    func fetchRenderableNewlyAddedManga(limit: Int = 20) async -> [MangaCard] {
        let clamped = max(1, min(40, limit))
        do {
            let client = try requiredClient()
            let rows: [MangaCard] = try await client
                .from("manga")
                .select("id,title_english,title_romaji,title_native,cover_image_large,cover_image_medium,format,status,chapter_count:chapters,start_date_year,average_score,popularity,trending,favourites,genres,created_at")
                .eq("is_adult", value: false)
                .not("cover_image_large", operator: .is, value: "null")
                .not("cover_image_large", operator: .ilike, value: "%anilist.co%")
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .limit(clamped * 2)
                .execute()
                .value
            let filtered = rows.filter { card in
                let genres = Set((card.genres ?? []).map { $0.lowercased() })
                return ImagePipeline.hasRenderableArtwork(card.imageURL)
                    && !genres.contains("hentai")
                    && !genres.contains("ecchi")
            }
            return Array(filtered.prefix(clamped))
        } catch {
            #if DEBUG
            print("❌ fetchRenderableNewlyAddedManga error: \(error)")
            #endif
            return []
        }
    }

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
    func fetchDailyFeature(force: Bool = false, now: Date = Date()) async -> DailyFeature? {
        // W5: the RPC needs an account (it raises when signed out), so a guest never sends it.
        guard let context = accountSession.current else { return nil }
        if !force, let cached = dailyFeatureCache[context.userId], Self.isSameRailDay(cached.storedAt, now) {
            return cached.value
        }
        do {
            let client = try requiredClient()
            let rows: [DailyFeature] = try await client
                .rpc("fetch_daily_feature")
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return nil }
            let feature = rows.first
            dailyFeatureCache[context.userId] = TimedCache(value: feature, storedAt: now)
            return feature
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
        guard context != nil else { return nil }   // W5: personal; a guest never sends it
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
        guard context != nil else { return nil }   // W5: personal; a guest never sends it
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
        guard context != nil else { return nil }   // W5: personal; a guest never sends it
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

    /// Reads the stated next air time of the rail titles not read yet today (up to 60, the bundle's
    /// largest rail, in one request). The bundle
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
        let wanted = Array(animeIds.filter { !airingSlotIdsRead.contains($0) }.prefix(60))
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

    private struct UpcomingAnimeScheduleRow: Decodable {
        let id: Int
        let titleEnglish: String?
        let titleRomaji: String?
        let titleNative: String?
        let coverImageLarge: String?
        let coverImageMedium: String?
        let bannerImage: String?
        let format: String?
        let status: String?
        let episodeCount: Int?
        let seasonYear: Int?
        let startDateYear: Int?
        let averageScore: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genreList: [String]?
        let createdAt: Date?
        let nextAiringAt: Date?
        let nextEpisodeNumber: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case titleEnglish = "title_english"
            case titleRomaji = "title_romaji"
            case titleNative = "title_native"
            case coverImageLarge = "cover_image_large"
            case coverImageMedium = "cover_image_medium"
            case bannerImage = "banner_image"
            case format
            case status
            case episodeCount = "episode_count"
            case seasonYear = "season_year"
            case startDateYear = "start_date_year"
            case averageScore = "average_score"
            case popularity
            case trending
            case favourites
            case genreList = "genres"
            case createdAt = "created_at"
            case nextAiringAt = "next_airing_at"
            case nextEpisodeNumber = "next_episode_number"
        }

        var asAnimeCard: AnimeCard {
            AnimeCard(
                id: id,
                titleEnglish: titleEnglish,
                titleRomaji: titleRomaji,
                titleNative: titleNative,
                coverImageLarge: coverImageLarge,
                coverImageMedium: coverImageMedium,
                bannerImage: bannerImage,
                format: format,
                status: status,
                episodeCount: episodeCount,
                seasonYear: seasonYear,
                startDateYear: startDateYear,
                averageScore: averageScore,
                popularity: popularity,
                trending: trending,
                favourites: favourites,
                genreList: genreList,
                createdAt: createdAt,
                rank: nil
            )
        }
    }

    private struct MangaScheduleRow: Decodable {
        let id: Int
        let titleEnglish: String?
        let titleRomaji: String?
        let titleNative: String?
        let coverImageLarge: String?
        let coverImageMedium: String?
        let format: String?
        let status: String?
        let chapterCount: Int?
        let startDateYear: Int?
        let averageScore: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genreList: [String]?
        let createdAt: Date?
        let latestChapter: Double?
        let latestChapterAt: Date?
        let nextChapterNumber: Int?
        let nextChapterAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case titleEnglish = "title_english"
            case titleRomaji = "title_romaji"
            case titleNative = "title_native"
            case coverImageLarge = "cover_image_large"
            case coverImageMedium = "cover_image_medium"
            case format
            case status
            case chapterCount = "chapter_count"
            case startDateYear = "start_date_year"
            case averageScore = "average_score"
            case popularity
            case trending
            case favourites
            case genreList = "genres"
            case createdAt = "created_at"
            case latestChapter = "latest_chapter"
            case latestChapterAt = "latest_chapter_at"
            case nextChapterNumber = "next_chapter_number"
            case nextChapterAt = "next_chapter_at"
        }

        var asMangaCard: MangaCard {
            let derivedTotal = chapterCount ?? latestChapter.map { Int(floor($0)) }
            return MangaCard(
                id: id,
                titleEnglish: titleEnglish,
                titleRomaji: titleRomaji,
                titleNative: titleNative,
                coverImageLarge: coverImageLarge,
                coverImageMedium: coverImageMedium,
                format: format,
                status: status,
                chapterCount: derivedTotal,
                startDateYear: startDateYear,
                averageScore: averageScore,
                popularity: popularity,
                trending: trending,
                favourites: favourites,
                genreList: genreList,
                createdAt: createdAt,
                rank: nil
            )
        }
    }

    /// Reads releasing anime with confirmed upcoming `next_airing_at` within the next `days` days,
    /// sorted chronologically soonest-first. Public catalogue data.
    func fetchUpcomingAnimeSchedule(days: Int = 7, limit: Int = 60, now: Date = Date()) async -> (cards: [AnimeCard], slots: [Int: DiscoverAiringSlot]) {
        let clampedLimit = max(1, min(100, limit))
        let windowEnd = now.addingTimeInterval(TimeInterval(max(1, days) * 86_400))
        let isoNow = now.ISO8601Format()
        let isoEnd = windowEnd.ISO8601Format()
        do {
            let client = try requiredClient()
            let rows: [UpcomingAnimeScheduleRow] = try await client
                .from("anime")
                .select("id,title_english,title_romaji,title_native,cover_image_large,cover_image_medium,banner_image,format,status,episode_count:episodes,season_year,start_date_year,average_score,popularity,trending,favourites,genres,created_at,next_airing_at,next_episode_number")
                .eq("is_adult", value: false)
                .eq("status", value: "RELEASING")
                .gte("next_airing_at", value: isoNow)
                .lte("next_airing_at", value: isoEnd)
                .order("next_airing_at", ascending: true)
                .limit(clampedLimit * 2)
                .execute()
                .value

            var cards: [AnimeCard] = []
            var slots: [Int: DiscoverAiringSlot] = [:]
            for row in rows {
                let card = row.asAnimeCard
                let genres = Set((card.genres ?? []).map { $0.lowercased() })
                let format = card.format?.uppercased() ?? ""
                guard ImagePipeline.hasRenderableArtwork(card.imageURL),
                      !genres.contains("hentai"),
                      !genres.contains("ecchi"),
                      !["SPECIAL", "MUSIC", "TV_SHORT"].contains(format),
                      let airingAt = row.nextAiringAt else { continue }
                let slot = DiscoverAiringSlot(animeId: row.id, airingAt: airingAt, episode: row.nextEpisodeNumber)
                airingSlots[row.id] = slot
                slots[row.id] = slot
                cards.append(card)
                if cards.count >= clampedLimit { break }
            }
            return (cards, slots)
        } catch {
            #if DEBUG
            print("❌ fetchUpcomingAnimeSchedule error: \(error)")
            #endif
            return ([], [:])
        }
    }

    /// Reads ongoing manga with upcoming scheduled chapters (`next_chapter_at >= now`) first,
    /// followed by popular ongoing manga with freshly observed `latest_chapter` values.
    func fetchUpcomingAndFreshManga(limit: Int = 40, now: Date = Date()) async -> (cards: [MangaCard], slots: [Int: DiscoverMangaSlot]) {
        let clampedLimit = max(1, min(80, limit))
        let isoNow = now.ISO8601Format()
        do {
            let client = try requiredClient()
            let cols = "id,title_english,title_romaji,title_native,cover_image_large,cover_image_medium,format,status,chapter_count:chapters,start_date_year,average_score,popularity,trending,favourites,genres,created_at,latest_chapter,latest_chapter_at,next_chapter_number,next_chapter_at"
            async let upcomingRead: [MangaScheduleRow] = client
                .from("manga")
                .select(cols)
                .eq("is_adult", value: false)
                .eq("status", value: "RELEASING")
                .gte("next_chapter_at", value: isoNow)
                .order("next_chapter_at", ascending: true)
                .limit(20)
                .execute()
                .value
            async let freshRead: [MangaScheduleRow] = client
                .from("manga")
                .select(cols)
                .eq("is_adult", value: false)
                .eq("status", value: "RELEASING")
                .not("latest_chapter", operator: .is, value: "null")
                .order("latest_chapter_at", ascending: false, nullsFirst: false)
                .order("popularity", ascending: false, nullsFirst: false)
                .limit(clampedLimit * 2)
                .execute()
                .value

            let upcoming = (try? await upcomingRead) ?? []
            let fresh = try await freshRead
            var seen: Set<Int> = []
            var cards: [MangaCard] = []
            var slots: [Int: DiscoverMangaSlot] = [:]

            for row in upcoming + fresh {
                guard seen.insert(row.id).inserted else { continue }
                let card = row.asMangaCard
                let genres = Set((card.genres ?? []).map { $0.lowercased() })
                guard ImagePipeline.hasRenderableArtwork(card.imageURL),
                      !genres.contains("hentai"),
                      !genres.contains("ecchi") else { continue }
                cards.append(card)
                slots[row.id] = DiscoverMangaSlot(
                    mangaId: row.id,
                    latestChapter: row.latestChapter,
                    latestChapterAt: row.latestChapterAt,
                    nextChapterNumber: row.nextChapterNumber,
                    nextChapterAt: row.nextChapterAt
                )
                if cards.count >= clampedLimit { break }
            }
            return (cards, slots)
        } catch {
            #if DEBUG
            print("❌ fetchUpcomingAndFreshManga error: \(error)")
            #endif
            return ([], [:])
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
