import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

// MARK: - Supabase Service
// Connects to your existing comprehensive database schema

@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()
    
    // Supabase client
    private let client: SupabaseClient

    // Auth state
    var isAuthBootstrapping: Bool = true
    var isAuthenticated: Bool = false
    var authErrorMessage: String? = nil
    
    // Observable properties (no @Published needed with @Observable)
    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    // User's personal collection (server-driven; doesn't rely on global prefetch)
    var collectionAnimeItems: [Anime] = []
    var collectionMangaItems: [Manga] = []
    var isCollectionLoading: Bool = false
    var collectionErrorMessage: String? = nil
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    // Detail caches: cards/grids only carry minimal fields; we fetch full details by id on demand.
    private var animeDetailCache: [Int: Anime] = [:]
    private var mangaDetailCache: [Int: Manga] = [:]
    // Upcoming airings for user's saved anime (next X days)
    struct UpcomingAiring: Decodable, Sendable {
        let anime_id: Int
        let title_english: String?
        let title_romaji: String?
        let next_episode_number: Int?
        let next_airing_at: Date
    }
    var upcomingAirings: [UpcomingAiring] = []
    // Formatted countdowns keyed by anime_id
    var countdownByAnimeId: [Int: String] = [:]
    private var countdownTimer: Timer?
    var isLoading = false
    var errorMessage: String?

    private let animeProviderRanking: [String] = [
        "crunchyroll",
        "netflix",
        "hidive",
        "disney",
        "amazon",
        "prime",
        "hulu",
        "youtube",
        "apple",
        "max"
    ]

    private let mangaProviderRanking: [String] = [
        "manga plus",
        "viz",
        "bookwalker",
        "comixology",
        "kindle",
        "kodansha",
        "yen press",
        "azuki"
    ]

    // MARK: - Discovery policy
    struct DiscoveryPolicy: Sendable {
        var includeAdult: Bool = false
        var excludeEcchi: Bool = true
    }

    static let canonicalGenres: [String] = [
        "Action",
        "Adventure",
        "Comedy",
        "Drama",
        "Ecchi",
        "Fantasy",
        "Hentai",
        "Horror",
        "Mahou Shoujo",
        "Mecha",
        "Music",
        "Mystery",
        "Psychological",
        "Romance",
        "Sci-Fi",
        "Slice of Life",
        "Sports",
        "Supernatural",
        "Thriller"
    ]

    private func sanitizeAnimeForDiscovery(_ items: [Anime], policy: DiscoveryPolicy = .init()) -> [Anime] {
        items.filter { anime in
            if !policy.includeAdult {
                if anime.isAdult { return false }
                if anime.genres?.contains("Hentai") == true { return false }
            }
            if policy.excludeEcchi {
                if anime.genres?.contains("Ecchi") == true { return false }
            }
            return true
        }
    }

    private func sanitizeMangaForDiscovery(_ items: [Manga], policy: DiscoveryPolicy = .init()) -> [Manga] {
        items.filter { manga in
            if !policy.includeAdult {
                if manga.isAdult { return false }
                if manga.genres?.contains("Hentai") == true { return false }
            }
            if policy.excludeEcchi {
                if manga.genres?.contains("Ecchi") == true { return false }
            }
            return true
        }
    }

    // Search state (paged server-side text search)
    var searchAnimeItems: [Anime] = []
    var searchMangaItems: [Manga] = []
    private var currentSearchQuery: String = ""
    private enum SearchMode { case anime, manga, combined }
    private var searchMode: SearchMode = .anime
    private var currentSearchPage = 0
    private var currentSearchPageAnime = 0
    private var currentSearchPageManga = 0
    private var searchPageSize = 20
    var hasMoreSearch = true
    var isSearching = false
    private var hasMoreSearchAnime = true
    private var hasMoreSearchManga = true

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
    private var currentSearchFilters: SearchFilters? = nil

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

    // Pagination state
    private var currentAnimePage = 0
    private var currentMangaPage = 0
    private var pageSize = 50  // Increased for better performance with large datasets
    var hasMoreAnime = true
    var hasMoreManga = true
    
    init() {
        // Initialize Supabase client from configuration; fallback to embedded defaults to avoid breaking the app
        let fallbackURL = URL(string: "https://bkdifromsqxkndnllmdj.supabase.co")!
        // NOTE: keeping this hardcoded per current preference; move to Info.plist/env before shipping.
        let fallbackKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo"
        let url = AppConfig.supabaseURL ?? fallbackURL
        let key = AppConfig.supabaseAnonKey ?? fallbackKey

        if AppConfig.supabaseURL == nil || AppConfig.supabaseAnonKey == nil {
            print("⚠️ Using fallback Supabase config from code. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist or env.")
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key
        )
        print("🔥 Supabase client initialized: \(url.host ?? url.absoluteString)")

        Task { await restoreSession() }
    }
    
    // MARK: - Authentication
    func restoreSession() async {
        defer { isAuthBootstrapping = false }

        do {
            _ = try await client.auth.session
            isAuthenticated = true
            authErrorMessage = nil
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            isAuthenticated = false
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            _ = try await client.auth.session
            isAuthenticated = true
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = error.localizedDescription
            isAuthenticated = false
            throw error
        }
    }

    func signUpWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            // Depending on Supabase settings, user may need email confirmation. We still attempt bootstrap if a session exists.
            if (try? await client.auth.session) != nil {
                isAuthenticated = true
                await ensureProfileRow()
                await bootstrapAfterAuth()
            } else {
                isAuthenticated = false
            }
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            print("❌ signOut error: \(error)")
        }
        isAuthenticated = false
        authErrorMessage = nil
        stopCountdownUpdates()
        resetUserState()
    }

    private func resetUserState() {
        userLists = []
        collectionAnimeItems = []
        collectionMangaItems = []
        upcomingAirings = []
        countdownByAnimeId = [:]
    }

    private func ensureProfileRow() async {
        guard let user = try? await client.auth.session.user else { return }
        struct ProfilePayload: Encodable {
            let id: UUID
            let adult_opt_in: Bool
        }
        do {
            try await client
                .from("profiles")
                .upsert(ProfilePayload(id: user.id, adult_opt_in: false), onConflict: "id")
                .execute()
        } catch {
            print("⚠️ ensureProfileRow failed: \(error)")
        }
    }

    private func bootstrapAfterAuth() async {
        // Load user state early so collection indicators + progress are correct across the UI.
        await fetchUserLists()
        await fetchCollectionItems()
        await fetchUpcomingForUser(days: 7)
        startCountdownUpdates()
    }

    private func currentUserIdString() async -> String? {
        (try? await client.auth.session.user.id.uuidString)
    }
    
    // MARK: - Fetch Anime (API-backed pagination)
    func setPageSize(_ size: Int) {
        pageSize = max(1, size)
    }

    func resetAnimePaging() {
        currentAnimePage = 0
        hasMoreAnime = true
        animeItems = []
    }

    func fetchNextAnimePage() async {
        guard hasMoreAnime, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let offset = currentAnimePage * pageSize
            let response: [Anime] = try await client
                .from("anime")
                .select()
                .order("popularity", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value

            animeItems.append(contentsOf: response)
            hasMoreAnime = response.count == pageSize
            if hasMoreAnime { currentAnimePage += 1 }
            print("✅ Fetched page \(currentAnimePage) (\(response.count) items), total: \(animeItems.count)")
        } catch {
            errorMessage = "Failed to fetch anime: \(error.localizedDescription)"
            print("❌ Supabase error: \(error)")
        }

        isLoading = false
    }

    func prefetchAnime(total: Int) async {
        resetAnimePaging()
        let pages = Int(ceil(Double(max(0, total)) / Double(pageSize)))
        for _ in 0..<pages {
            await fetchNextAnimePage()
            if !hasMoreAnime { break }
        }
    }

    // Backwards-compat shim (deprecated)
    func fetchAnime(limit: Int = 20, reset: Bool = false) async {
        if reset {
            resetAnimePaging()
        }
        // Use pageSize for pagination regardless of provided limit
        await fetchNextAnimePage()
    }
    
    // MARK: - Fetch Manga (API-backed pagination)
    func resetMangaPaging() {
        currentMangaPage = 0
        hasMoreManga = true
        mangaItems = []
    }

    func fetchNextMangaPage() async {
        guard hasMoreManga, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let offset = currentMangaPage * pageSize
            let response: [Manga] = try await client
                .from("manga")
                .select()
                .order("popularity", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value

            mangaItems.append(contentsOf: response)
            hasMoreManga = response.count == pageSize
            if hasMoreManga { currentMangaPage += 1 }
            print("✅ Fetched manga page \(currentMangaPage) (\(response.count) items), total: \(mangaItems.count)")
        } catch {
            errorMessage = "Failed to fetch manga: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }

        isLoading = false
    }

    func prefetchManga(total: Int) async {
        resetMangaPaging()
        let pages = Int(ceil(Double(max(0, total)) / Double(pageSize)))
        for _ in 0..<pages {
            await fetchNextMangaPage()
            if !hasMoreManga { break }
        }
    }
    
    // MARK: - Search (using your full-text search index)
    func searchContent(query: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Search anime using your full-text search index
            let animeResponse: [Anime] = try await client
                .from("anime")
                .select()
                .textSearch("title_english,title_romaji,description_normalized", query: query)
                .execute()
                .value
            
            // Search manga
            let mangaResponse: [Manga] = try await client
                .from("manga")
                .select()
                .textSearch("title_english,title_romaji,description_normalized", query: query)
                .execute()
                .value
            
            animeItems = animeResponse
            mangaItems = mangaResponse
            print("✅ Found \(animeResponse.count) anime, \(mangaResponse.count) manga")
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
        
        isLoading = false
    }

    // MARK: - Server-side paged text search
    func setSearchPageSize(_ size: Int) { searchPageSize = max(1, size) }

    func resetSearch(query: String, isManga: Bool) {
        currentSearchQuery = query
        searchMode = isManga ? .manga : .anime
        currentSearchPage = 0
        hasMoreSearch = true
        hasMoreSearchAnime = true
        hasMoreSearchManga = true
        searchAnimeItems = []
        searchMangaItems = []
    }

    func setSearchFilters(_ filters: SearchFilters?) {
        currentSearchFilters = filters
    }

    private func newSeasonThresholdYear() -> Int {
        // "New season" is meant to feel current; keep it dynamic so the UI stays fresh year over year.
        max(1900, Calendar.current.component(.year, from: Date()) - 1)
    }

    func fetchNextSearchPage() async {
        if searchMode == .combined {
            await fetchNextCombinedSearchPage()
            return
        }

        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow "filters-only" searches (no text) for category browsing; but don't fetch anything if both are empty.
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }
        isSearching = true
        defer { isSearching = false }

        do {
            let offset = currentSearchPage * searchPageSize
            if searchMode == .manga {
                var query = client.from("manga").select()
                if !trimmedQuery.isEmpty {
                    query = query.textSearch("title_english,title_romaji,description_normalized", query: trimmedQuery)
                }

                if let f = currentSearchFilters {
                    if f.trending { query = query.gt("trending", value: 0) }
                    if f.newSeason { query = query.gte("start_date_year", value: newSeasonThresholdYear()) }
                    if f.classics { query = query.lt("start_date_year", value: 2010) }
                    if f.hiddenGems { query = query.gte("average_score", value: 85).lt("start_date_year", value: 2015) }
                    // airingOnly/seasonName not applicable to manga in AniList terms; skip
                }

                // Order: trending if facet on, else popularity
                let orderedQuery = (currentSearchFilters?.trending ?? false) ?
                    query.order("trending", ascending: false) :
                    query.order("popularity", ascending: false)

                let response: [Manga] = try await orderedQuery
                    .range(from: offset, to: offset + searchPageSize - 1)
                    .execute()
                    .value
                searchMangaItems.append(contentsOf: response)
                hasMoreSearch = response.count == searchPageSize
            } else {
                var query = client.from("anime").select()
                if !trimmedQuery.isEmpty {
                    query = query.textSearch("title_english,title_romaji,description_normalized", query: trimmedQuery)
                }

                if let f = currentSearchFilters {
                    if f.trending { query = query.gt("trending", value: 0) }
                    if f.newSeason { query = query.gte("season_year", value: newSeasonThresholdYear()) }
                    if f.classics { query = query.lt("season_year", value: 2010) }
                    if f.hiddenGems { query = query.gte("average_score", value: 85).lt("season_year", value: 2015) }
                    if f.airingOnly { query = query.eq("status", value: "RELEASING") }
                    if let s = f.seasonName, let y = f.seasonYear {
                        query = query.eq("season", value: s).eq("season_year", value: y)
                    }
                }

                let orderedQuery = (currentSearchFilters?.trending ?? false) ?
                    query.order("trending", ascending: false) :
                    query.order("popularity", ascending: false)

                let response: [Anime] = try await orderedQuery
                    .range(from: offset, to: offset + searchPageSize - 1)
                    .execute()
                    .value
                searchAnimeItems.append(contentsOf: response)
                hasMoreSearch = response.count == searchPageSize
            }
            if hasMoreSearch { currentSearchPage += 1 }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            hasMoreSearch = false
            print("❌ Search page error: \(error)")
        }
    }

    func resetCombinedSearch(query: String) {
        currentSearchQuery = query
        searchMode = .combined
        currentSearchPageAnime = 0
        currentSearchPageManga = 0
        hasMoreSearchAnime = true
        hasMoreSearchManga = true
        hasMoreSearch = true
        searchAnimeItems = []
        searchMangaItems = []
    }

    func fetchNextCombinedSearchPage() async {
        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            // Avoid `async let` here: Supabase builders and service state are MainActor-isolated.
            let filters = currentSearchFilters
            let orderByTrending = filters?.trending ?? false
            let seasonFloor = newSeasonThresholdYear()

            var animePage: [Anime] = []
            if hasMoreSearchAnime {
                var q = client.from("anime").select()
                if !trimmedQuery.isEmpty {
                    q = q.textSearch("title_english,title_romaji,description_normalized", query: trimmedQuery)
                }
                if let f = filters {
                    if f.trending { q = q.gt("trending", value: 0) }
                    if f.newSeason { q = q.gte("season_year", value: seasonFloor) }
                    if f.classics { q = q.lt("season_year", value: 2010) }
                    if f.hiddenGems { q = q.gte("average_score", value: 85).lt("season_year", value: 2015) }
                    if f.airingOnly { q = q.eq("status", value: "RELEASING") }
                    if let s = f.seasonName, let y = f.seasonYear {
                        q = q.eq("season", value: s).eq("season_year", value: y)
                    }
                }
                let ordered = orderByTrending ? q.order("trending", ascending: false) : q.order("popularity", ascending: false)
                let offset = currentSearchPageAnime * searchPageSize
                animePage = try await ordered.range(from: offset, to: offset + searchPageSize - 1).execute().value
            }

            var mangaPage: [Manga] = []
            if hasMoreSearchManga {
                var q = client.from("manga").select()
                if !trimmedQuery.isEmpty {
                    q = q.textSearch("title_english,title_romaji,description_normalized", query: trimmedQuery)
                }
                if let f = filters {
                    if f.trending { q = q.gt("trending", value: 0) }
                    if f.newSeason { q = q.gte("start_date_year", value: seasonFloor) }
                    if f.classics { q = q.lt("start_date_year", value: 2010) }
                    if f.hiddenGems { q = q.gte("average_score", value: 85).lt("start_date_year", value: 2015) }
                }
                let ordered = orderByTrending ? q.order("trending", ascending: false) : q.order("popularity", ascending: false)
                let offset = currentSearchPageManga * searchPageSize
                mangaPage = try await ordered.range(from: offset, to: offset + searchPageSize - 1).execute().value
            }

            if hasMoreSearchAnime {
                searchAnimeItems.append(contentsOf: animePage)
                hasMoreSearchAnime = animePage.count == searchPageSize
                if hasMoreSearchAnime { currentSearchPageAnime += 1 }
            }

            if hasMoreSearchManga {
                searchMangaItems.append(contentsOf: mangaPage)
                hasMoreSearchManga = mangaPage.count == searchPageSize
                if hasMoreSearchManga { currentSearchPageManga += 1 }
            }

            hasMoreSearch = hasMoreSearchAnime || hasMoreSearchManga
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            hasMoreSearch = false
            hasMoreSearchAnime = false
            hasMoreSearchManga = false
            print("❌ Combined search error: \(error)")
        }
    }

    // MARK: - Discover bundle (single call)
    func fetchDiscoverBundle(limit: Int = 30, hours: Int = 24) async -> DiscoverBundle? {
        let perf = KuroPerf.begin("rpc.discover_bundle")
        do {
            let params = RPCDiscoverBundleParams(
                p_limit: max(1, min(60, limit)),
                p_hours: max(1, min(168, hours))
            )
            let bundle: DiscoverBundle = try await client
                .rpc("discover_bundle", params: params)
                .execute()
                .value
            KuroPerf.end(perf, message: "ok")
            return bundle
        } catch {
            print("❌ discover_bundle rpc: \(error)")
            KuroPerf.end(perf, message: "error")
            return nil
        }
    }

    // MARK: - Detail fetch by id (full models)
    func fetchAnimeById(_ animeId: Int) async throws -> Anime? {
        if let cached = animeDetailCache[animeId] { return cached }
        let perf = KuroPerf.begin("db.anime_by_id")
        do {
            let rows: [Anime] = try await client
                .from("anime")
                .select()
                .eq("id", value: animeId)
                .limit(1)
                .execute()
                .value
            let item = rows.first
            if let item {
                animeDetailCache[animeId] = item
                // Keep cache bounded.
                if animeDetailCache.count > 200, let k = animeDetailCache.keys.first {
                    animeDetailCache.removeValue(forKey: k)
                }
            }
            KuroPerf.end(perf, message: item == nil ? "missing" : "ok")
            return item
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    func fetchMangaById(_ mangaId: Int) async throws -> Manga? {
        if let cached = mangaDetailCache[mangaId] { return cached }
        let perf = KuroPerf.begin("db.manga_by_id")
        do {
            let rows: [Manga] = try await client
                .from("manga")
                .select()
                .eq("id", value: mangaId)
                .limit(1)
                .execute()
                .value
            let item = rows.first
            if let item {
                mangaDetailCache[mangaId] = item
                if mangaDetailCache.count > 200, let k = mangaDetailCache.keys.first {
                    mangaDetailCache.removeValue(forKey: k)
                }
            }
            KuroPerf.end(perf, message: item == nil ? "missing" : "ok")
            return item
        } catch {
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    // MARK: - Server-driven Discover sections (Anime)
    func fetchTrendingAnime(limit: Int = 20, onlyAiring: Bool = false, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            var q = client.from("mv_anime_trending").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let statusQuery = onlyAiring ? q.eq("status", value: "RELEASING") : q
            let orderedQuery = statusQuery.order("trending", ascending: false)
            let rows: [Anime] = try await orderedQuery.range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ trending fetch: \(error)"); return [] }
    }

    func fetchCurrentSeasonAnime(limit: Int = 20, year: Int? = nil, onlyAiring: Bool = true, genre: String? = nil) async -> [Anime] {
        do {
            let yr = year ?? Calendar.current.component(.year, from: Date())
            var q = client.from("anime").select().eq("season_year", value: yr)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let statusQuery = onlyAiring ? q.eq("status", value: "RELEASING") : q
            let orderedQuery = statusQuery.order("popularity", ascending: false)
            let rows: [Anime] = try await orderedQuery.range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ current season fetch: \(error)"); return [] }
    }

    func fetchSeasonAnime(season: String, year: Int, limit: Int = 20, onlyAiring: Bool = true, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select().eq("season", value: season).eq("season_year", value: year)
            if onlyAiring { q = q.eq("status", value: "RELEASING") }
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("popularity", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ season fetch: \(error)"); return [] }
    }

    func fetchNewlyAddedAnime(limit: Int = 20, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            var q = client.from("mv_anime_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ newly added fetch: \(error)"); return [] }
    }

    func fetchTopRatedAnime(limit: Int = 20, minScore: Int = 80, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            // Still supports minScore by filtering the view.
            var q = client.from("mv_anime_top_rated").select().gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("average_score", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ top rated fetch: \(error)"); return [] }
    }

    // MARK: - Server-driven Discover sections (Manga)
    func fetchTrendingManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_trending").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("trending", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ manga trending fetch: \(error)"); return [] }
    }

    func fetchNewlyAddedManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ manga newly added fetch: \(error)"); return [] }
    }

    func fetchTopRatedManga(limit: Int = 20, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_top_rated").select().gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("average_score", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ manga top rated fetch: \(error)"); return [] }
    }

    // MARK: - Premium discovery rails (Essentials / Classics / New-to-you)
    func fetchEssentialsAnime(limit: Int = 20, minScore: Int = 85, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ essentials anime fetch: \(error)"); return [] }
    }

    func fetchClassicsAnime(limit: Int = 20, yearBefore: Int = 2015, minScore: Int = 80, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .lt("season_year", value: yearBefore)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ classics anime fetch: \(error)"); return [] }
    }

    func fetchNewToYouAnime(limit: Int = 20, candidateLimit: Int = 250, minScore: Int = 80, genre: String? = nil) async -> [Anime] {
        let saved: Set<Int> = Set(userLists.filter { $0.mediaType.lowercased() == "anime" }.map(\.mediaId))
        do {
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let candidates: [Anime] = try await q
                .order("popularity", ascending: false)
                .order("average_score", ascending: false)
                .range(from: 0, to: max(0, candidateLimit - 1))
                .execute()
                .value

            let filtered = sanitizeAnimeForDiscovery(candidates)
                .filter { !saved.contains($0.id) }

            // Deterministic daily reshuffle to avoid showing the same top items forever.
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            let shuffled = filtered.sorted { lhs, rhs in
                let a = (lhs.id &* 1103515245 &+ day) & 0x7fffffff
                let b = (rhs.id &* 1103515245 &+ day) & 0x7fffffff
                return a < b
            }
            return Array(shuffled.prefix(limit))
        } catch { print("❌ new-to-you anime fetch: \(error)"); return [] }
    }

    func fetchEssentialsManga(limit: Int = 20, minScore: Int = 85, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("manga").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ essentials manga fetch: \(error)"); return [] }
    }

    func fetchClassicsManga(limit: Int = 20, yearBefore: Int = 2015, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("manga").select()
                .eq("is_adult", value: false)
                .lt("start_date_year", value: yearBefore)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeMangaForDiscovery(rows)
        } catch { print("❌ classics manga fetch: \(error)"); return [] }
    }

    func fetchNewToYouManga(limit: Int = 20, candidateLimit: Int = 300, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        let saved: Set<Int> = Set(userLists.filter { $0.mediaType.lowercased() == "manga" }.map(\.mediaId))
        do {
            var q = client.from("manga").select()
                .eq("is_adult", value: false)
                .gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let candidates: [Manga] = try await q
                .order("popularity", ascending: false)
                .order("average_score", ascending: false)
                .range(from: 0, to: max(0, candidateLimit - 1))
                .execute()
                .value

            let filtered = sanitizeMangaForDiscovery(candidates)
                .filter { !saved.contains($0.id) }

            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            let shuffled = filtered.sorted { lhs, rhs in
                let a = (lhs.id &* 1103515245 &+ day) & 0x7fffffff
                let b = (rhs.id &* 1103515245 &+ day) & 0x7fffffff
                return a < b
            }
            return Array(shuffled.prefix(limit))
        } catch { print("❌ new-to-you manga fetch: \(error)"); return [] }
    }

    // Imminent airing within next N hours
    func fetchAiringSoonAnime(hours: Int = 24, limit: Int = 20, genre: String? = nil) async -> [Anime] {
        do {
            let now = Date()
            let end = now.addingTimeInterval(TimeInterval(hours * 3600))
            let iso = ISO8601DateFormatter()
            let nowStr = iso.string(from: now)
            let endStr = iso.string(from: end)
            var q = client.from("anime").select()
                .eq("is_adult", value: false)
                .gt("next_airing_at", value: nowStr)
                .lte("next_airing_at", value: endStr)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("next_airing_at", ascending: true)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch { print("❌ airing soon fetch: \(error)"); return [] }
    }

    // MARK: - Sub-genre (tag) insights for a genre
    private struct _TagNode: Decodable {
        let id: Int
        let name: String
        let category: String?
        let isAdult: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, category
            case isAdult = "is_adult"
        }
    }

    private struct _TagEdge: Decodable {
        let rank: Int?
        let tagId: Int?
        let tags: _TagNode?

        enum CodingKeys: String, CodingKey {
            case rank
            case tagId = "tag_id"
            case tags
        }
    }

    private struct _AnimeTagSampleRow: Decodable {
        let id: Int
        let animeTags: [_TagEdge]

        enum CodingKeys: String, CodingKey {
            case id
            case animeTags = "anime_tags"
        }
    }

    private struct _MangaTagSampleRow: Decodable {
        let id: Int
        let mangaTags: [_TagEdge]

        enum CodingKeys: String, CodingKey {
            case id
            case mangaTags = "manga_tags"
        }
    }

    private func isBlockedTag(_ t: _TagNode) -> Bool {
        if t.isAdult { return true }
        // Keep it simple: AniList already flags adult tags; category filters can be layered later.
        return false
    }

    func fetchTopTagsForAnimeGenre(genre: String, sampleLimit: Int = 180, limit: Int = 18) async -> (facets: [TagFacet], mediaToTagIds: [Int: Set<Int>]) {
        do {
            let rows: [_AnimeTagSampleRow] = try await client
                .from("anime")
                .select("id, anime_tags(rank, tag_id, tags(id, name, category, is_adult))")
                .eq("is_adult", value: false)
                .contains("genres", value: [genre])
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, sampleLimit - 1))
                .execute()
                .value

            var mediaToTagIds: [Int: Set<Int>] = [:]
            var tally: [Int: (name: String, category: String?, count: Int, rankSum: Int)] = [:]

            for row in rows {
                var tagIds: Set<Int> = []
                for edge in row.animeTags {
                    guard let t = edge.tags, !isBlockedTag(t) else { continue }
                    tagIds.insert(t.id)
                    var cur = tally[t.id] ?? (t.name, t.category, 0, 0)
                    cur.count += 1
                    cur.rankSum += (edge.rank ?? 0)
                    tally[t.id] = cur
                }
                mediaToTagIds[row.id] = tagIds
            }

            let sorted = tally
                .map { (id, v) in (id: id, name: v.name, category: v.category, count: v.count, rankSum: v.rankSum) }
                .sorted { a, b in
                    if a.count != b.count { return a.count > b.count }
                    return a.rankSum > b.rankSum
                }
                .prefix(max(0, limit))
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: $0.count) }

            return (Array(sorted), mediaToTagIds)
        } catch {
            print("❌ anime tag facets fetch: \(error)")
            return ([], [:])
        }
    }

    func fetchTopTagsForMangaGenre(genre: String, sampleLimit: Int = 180, limit: Int = 18) async -> (facets: [TagFacet], mediaToTagIds: [Int: Set<Int>]) {
        do {
            let rows: [_MangaTagSampleRow] = try await client
                .from("manga")
                .select("id, manga_tags(rank, tag_id, tags(id, name, category, is_adult))")
                .eq("is_adult", value: false)
                .contains("genres", value: [genre])
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, sampleLimit - 1))
                .execute()
                .value

            var mediaToTagIds: [Int: Set<Int>] = [:]
            var tally: [Int: (name: String, category: String?, count: Int, rankSum: Int)] = [:]

            for row in rows {
                var tagIds: Set<Int> = []
                for edge in row.mangaTags {
                    guard let t = edge.tags, !isBlockedTag(t) else { continue }
                    tagIds.insert(t.id)
                    var cur = tally[t.id] ?? (t.name, t.category, 0, 0)
                    cur.count += 1
                    cur.rankSum += (edge.rank ?? 0)
                    tally[t.id] = cur
                }
                mediaToTagIds[row.id] = tagIds
            }

            let sorted = tally
                .map { (id, v) in (id: id, name: v.name, category: v.category, count: v.count, rankSum: v.rankSum) }
                .sorted { a, b in
                    if a.count != b.count { return a.count > b.count }
                    return a.rankSum > b.rankSum
                }
                .prefix(max(0, limit))
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: $0.count) }

            return (Array(sorted), mediaToTagIds)
        } catch {
            print("❌ manga tag facets fetch: \(error)")
            return ([], [:])
        }
    }
    
    // MARK: - User Lists (normalized tables)
    private func statusFromDB(_ listType: String) -> ListStatus {
        switch listType.uppercased() {
        case "READING": return .current
        case "WATCHING": return .current
        case "PLANNING": return .planning
        case "COMPLETED": return .completed
        case "DROPPED": return .dropped
        case "PAUSED": return .paused
        default: return .planning
        }
    }

    private func dbListType(for status: ListStatus, mediaType: String) -> String {
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

    // MARK: - Collection (server-driven)
    func fetchCollectionItems() async {
        guard let userId = await currentUserIdString() else { return }
        isCollectionLoading = true
        collectionErrorMessage = nil
        defer { isCollectionLoading = false }

        struct AnimeListRow: Decodable {
            let updated_at: Date
            let anime: Anime
        }

        struct MangaListRow: Decodable {
            let updated_at: Date
            let manga: Manga
        }

        do {
            let animeRows: [AnimeListRow] = try await client
                .from("anime_user_lists")
                .select("updated_at, anime:anime_id(*)")
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .execute()
                .value

            let mangaRows: [MangaListRow] = try await client
                .from("manga_user_lists")
                .select("updated_at, manga:manga_id(*)")
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .execute()
                .value

            collectionAnimeItems = animeRows.map(\.anime)
            collectionMangaItems = mangaRows.map(\.manga)
        } catch {
            collectionErrorMessage = "Failed to load collection: \(error.localizedDescription)"
            print("❌ collection fetch: \(error)")
        }
    }

    // MARK: - Upsert user list entry (status/progress/rating/notes)
    func upsertUserListEntry(
        mediaId: Int,
        mediaType: String,
        status: ListStatus,
        progress: Int,
        rating: Int?,
        notes: String?
    ) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
        do {
            let table: String
            let onConflict: String
            let payload: Encodable

            struct AnimePayload: Encodable {
                let user_id: String
                let anime_id: Int
                let list_type: String
                let progress: Int
                let rating: Int?
                let notes: String?
            }

            struct MangaPayload: Encodable {
                let user_id: String
                let manga_id: Int
                let list_type: String
                let progress: Int
                let rating: Int?
                let notes: String?
            }

            if mediaType.lowercased() == "anime" {
                table = "anime_user_lists"
                onConflict = "user_id,anime_id"
                payload = AnimePayload(
                    user_id: userId,
                    anime_id: mediaId,
                    list_type: dbListType(for: status, mediaType: mediaType),
                    progress: max(0, progress),
                    rating: rating,
                    notes: notes
                )
            } else if mediaType.lowercased() == "manga" {
                table = "manga_user_lists"
                onConflict = "user_id,manga_id"
                payload = MangaPayload(
                    user_id: userId,
                    manga_id: mediaId,
                    list_type: dbListType(for: status, mediaType: mediaType),
                    progress: max(0, progress),
                    rating: rating,
                    notes: notes
                )
            } else {
                print("⚠️ Unknown mediaType: \(mediaType)")
                return
            }

            try await client
                .from(table)
                .upsert(payload, onConflict: onConflict)
                .execute()

            errorMessage = nil
            await fetchUserLists()
            await fetchCollectionItems()

            if mediaType.lowercased() == "anime" {
                await scheduleAiringNotifications(animeId: mediaId)
                await fetchUpcomingForUser(days: 7)
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ upsert list entry error: \(error)")
        }
    }

    func updateUserListProgress(mediaId: Int, mediaType: String, progress: Int) async {
        guard let userId = await currentUserIdString() else { return }
        do {
            let table = mediaType.lowercased() == "anime" ? "anime_user_lists" : "manga_user_lists"
            let idColumn = mediaType.lowercased() == "anime" ? "anime_id" : "manga_id"

            struct UpdateData: Encodable { let progress: Int }

            try await client
                .from(table)
                .update(UpdateData(progress: max(0, progress)))
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            await fetchUserLists()
        } catch {
            print("❌ Failed to update progress: \(error)")
        }
    }

    func fetchUserLists() async {
        guard let userId = await currentUserIdString() else { return }

        struct AnimeListRow: Decodable {
            let id: Int
            let user_id: String
            let anime_id: Int
            let list_type: String
            let progress: Int
            let rating: Int?
            let notes: String?
            let created_at: Date
            let updated_at: Date
        }

        struct MangaListRow: Decodable {
            let id: Int
            let user_id: String
            let manga_id: Int
            let list_type: String
            let progress: Int
            let rating: Int?
            let notes: String?
            let created_at: Date
            let updated_at: Date
        }

        do {
            // Avoid `async let`: some SDK builders are not Sendable under Swift 6 strict concurrency.
            let animeRows: [AnimeListRow] = try await client
                .from("anime_user_lists")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            let mangaRows: [MangaListRow] = try await client
                .from("manga_user_lists")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let mappedAnime = animeRows.map { row in
                UserList(
                    id: row.id,
                    userId: row.user_id,
                    mediaId: row.anime_id,
                    mediaType: "anime",
                    status: statusFromDB(row.list_type),
                    progress: row.progress,
                    progressVolumes: nil,
                    score: row.rating.map { $0 * 10 },
                    notes: row.notes,
                    startedAt: nil,
                    completedAt: nil,
                    isPrivate: false,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at
                )
            }

            let mappedManga = mangaRows.map { row in
                UserList(
                    id: row.id,
                    userId: row.user_id,
                    mediaId: row.manga_id,
                    mediaType: "manga",
                    status: statusFromDB(row.list_type),
                    progress: row.progress,
                    progressVolumes: nil,
                    score: row.rating.map { $0 * 10 },
                    notes: row.notes,
                    startedAt: nil,
                    completedAt: nil,
                    isPrivate: false,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at
                )
            }

            let combined = (mappedAnime + mappedManga).sorted { $0.updatedAt > $1.updatedAt }
            userLists = combined
            rebuildUserListCaches()
            print("✅ Fetched user lists: anime=\(mappedAnime.count), manga=\(mappedManga.count)")
        } catch {
            errorMessage = "Failed to fetch lists: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }
    
    // MARK: - Add/Remove in normalized user lists
    func addToList(mediaId: Int, mediaType: String, status: ListStatus) async {
        await upsertUserListEntry(
            mediaId: mediaId,
            mediaType: mediaType,
            status: status,
            progress: 0,
            rating: nil,
            notes: nil
        )
    }

    func removeFromList(mediaId: Int, mediaType: String) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
        do {
            let table: String
            let idColumn: String
            switch mediaType.lowercased() {
            case "anime": table = "anime_user_lists"; idColumn = "anime_id"
            case "manga": table = "manga_user_lists"; idColumn = "manga_id"
            default: return
            }

            try await client
                .from(table)
                .delete()
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            errorMessage = nil
            await fetchUserLists()
            await fetchCollectionItems()
            print("✅ Removed from user list")
            if mediaType.lowercased() == "anime" {
                cancelAiringNotifications(animeId: mediaId)
                // Remove countdown entry
                countdownByAnimeId[mediaId] = nil
                upcomingAirings.removeAll { $0.anime_id == mediaId }
            }
        } catch {
            errorMessage = "Failed to remove from list: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }

    // MARK: - Upcoming Airings (user-scoped)
    func fetchUpcomingForUser(days: Int = 7) async {
        guard let userId = await currentUserIdString() else { return }
        do {
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let untilISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(days) * 24 * 60 * 60))
            let rows: [UpcomingAiring] = try await client
                .from("user_airing_next")
                .select()
                .eq("user_id", value: userId)
                .gte("next_airing_at", value: nowISO)
                .lt("next_airing_at", value: untilISO)
                .order("next_airing_at", ascending: true)
                .limit(500)
                .execute()
                .value
            self.upcomingAirings = rows
            updateCountdowns()
        } catch {
            print("❌ Failed to fetch upcoming airings: \(error)")
        }
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "Now" }
        let minutes = Int(interval / 60)
        let days = minutes / (60 * 24)
        let hours = (minutes % (60 * 24)) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func updateCountdowns() {
        let now = Date()
        var map: [Int: String] = [:]
        for u in upcomingAirings {
            let interval = u.next_airing_at.timeIntervalSince(now)
            map[u.anime_id] = formatInterval(interval)
        }
        countdownByAnimeId = map
    }

    private func startCountdownUpdates() {
        countdownTimer?.invalidate()
        // Avoid passing an actor-isolated closure to Timer (Swift 6 strict concurrency warning).
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdowns()
            }
        }
    }

    private func stopCountdownUpdates() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Local Notifications for Airings (Anime only)
    private func ensureNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("⚠️ Notification permission request failed: \(error)")
            }
        }
    }

    private func scheduleNotification(id: String, title: String, body: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do { try await UNUserNotificationCenter.current().add(request) } catch { print("❌ Schedule notif failed: \(error)") }
    }

    func scheduleAiringNotifications(animeId: Int) async {
        do {
            struct Row: Decodable { let id: Int; let title_english: String?; let title_romaji: String?; let next_episode_number: Int?; let next_airing_at: Date? }
            let row: Row = try await client
                .from("anime")
                .select("id,title_english,title_romaji,next_episode_number,next_airing_at")
                .eq("id", value: animeId)
                .single()
                .execute()
                .value
            guard let airAt = row.next_airing_at, airAt > Date() else { return }
            await ensureNotificationPermission()
            let title = row.title_english ?? row.title_romaji ?? "Upcoming Episode"
            let ep = row.next_episode_number.map { "E\($0)" } ?? "Next"
            // Schedule "now airing"
            await scheduleNotification(id: "airing-\(animeId)-start", title: "\(title) airs now", body: "\(ep) is starting.", at: airAt)
            // Schedule 1 hour before if applicable
            let oneHourBefore = airAt.addingTimeInterval(-3600)
            if oneHourBefore > Date() {
                await scheduleNotification(id: "airing-\(animeId)-1h", title: "In 1 hour: \(title)", body: "\(ep) airs soon.", at: oneHourBefore)
            }
        } catch {
            print("⚠️ Could not schedule notifications: \(error)")
        }
    }

    func cancelAiringNotifications(animeId: Int) {
        let ids = ["airing-\(animeId)-start", "airing-\(animeId)-1h"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - External Links & Streaming Helpers
    func fetchExternalLinks(mediaType: String, mediaId: Int) async -> [ExternalLink] {
        do {
            return try await client
                .from("external_links")
                .select()
                .eq("media_type", value: mediaType.uppercased())
                .eq("media_id", value: mediaId)
                .eq("is_disabled", value: false)
                .order("priority", ascending: true)
                .execute()
                .value
        } catch {
            print("❌ Error fetching external links: \(error)")
            return []
        }
    }

    // MARK: - Episodes / Chapters (paged)
    func fetchEpisodesNext(animeId: Int, fromNumber: Int, limit: Int = 20) async -> [Episode] {
        do {
            var q = client.from("episodes").select()
                .eq("anime_id", value: animeId)

            if fromNumber > 1 {
                q = q.gte("number", value: fromNumber)
            }

            let ordered = q.order("number", ascending: true)
            return try await ordered.range(from: 0, to: max(0, limit - 1)).execute().value
        } catch {
            print("❌ fetch episodes next: \(error)")
            return []
        }
    }

    func fetchEpisodesPage(animeId: Int, offset: Int, limit: Int = 50) async -> [Episode] {
        do {
            let from = max(0, offset)
            let to = from + max(1, limit) - 1
            return try await client.from("episodes").select()
                .eq("anime_id", value: animeId)
                .order("number", ascending: true)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            print("❌ fetch episodes page: \(error)")
            return []
        }
    }

    func fetchChaptersNext(mangaId: Int, fromNumber: Int, limit: Int = 20) async -> [MangaChapter] {
        do {
            var q = client.from("chapters").select()
                .eq("manga_id", value: mangaId)

            if fromNumber > 1 {
                q = q.gte("number", value: fromNumber)
            }

            let ordered = q.order("number", ascending: true)
            return try await ordered.range(from: 0, to: max(0, limit - 1)).execute().value
        } catch {
            print("❌ fetch chapters next: \(error)")
            return []
        }
    }

    func fetchChaptersPage(mangaId: Int, offset: Int, limit: Int = 50) async -> [MangaChapter] {
        do {
            let from = max(0, offset)
            let to = from + max(1, limit) - 1
            return try await client.from("chapters").select()
                .eq("manga_id", value: mangaId)
                .order("number", ascending: true)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            print("❌ fetch chapters page: \(error)")
            return []
        }
    }

    func setUserProgress(mediaId: Int, mediaType: String, progress: Int) async {
        if let existing = userLists.first(where: { $0.mediaId == mediaId && $0.mediaType.lowercased() == mediaType.lowercased() }) {
            let rating = existing.score.map { $0 / 10 }
            await upsertUserListEntry(
                mediaId: mediaId,
                mediaType: mediaType,
                status: existing.status,
                progress: progress,
                rating: (rating ?? 0) > 0 ? rating : nil,
                notes: existing.notes
            )
        } else {
            await upsertUserListEntry(
                mediaId: mediaId,
                mediaType: mediaType,
                status: .current,
                progress: progress,
                rating: nil,
                notes: nil
            )
        }
    }

    func getStreamLinkForEpisode(animeId: Int, episodeNumber: Int) async -> (url: String, site: String)? {
        do {
            let rows: [Episode] = try await client
                .from("episodes")
                .select()
                .eq("anime_id", value: animeId)
                .eq("number", value: episodeNumber)
                .limit(1)
                .execute()
                .value
            if let ep = rows.first, let url = ep.streamUrl, let site = ep.streamSite {
                return (url, site)
            }
        } catch {
            print("❌ Error fetching episode stream: \(error)")
        }
        return nil
    }

    private func bestLink(from links: [ExternalLink], ranking: [String]) -> ExternalLink? {
        guard !links.isEmpty else { return nil }
        func weight(for link: ExternalLink) -> (Int, Int) {
            let priority = link.priority ?? 999
            let site = (link.site ?? "").lowercased()
            let rankIndex = ranking.firstIndex(where: { site.contains($0) }) ?? 999
            return (priority, rankIndex)
        }
        return links
            .filter { !$0.isDisabled && $0.url.lowercased().hasPrefix("http") }
            .min(by: { lhs, rhs in weight(for: lhs) < weight(for: rhs) })
    }

    func getProgress(for mediaId: Int) -> Int? {
        userLists.first { $0.mediaId == mediaId && $0.mediaType.lowercased() == "anime" }?.progress
    }

    func getBestWatchLink(anime: Anime, userProgress: Int?) async -> (url: String, site: String, label: String)? {
        let nextEpisode = max(1, (userProgress ?? 0) + 1)
        if let episodeLink = await getStreamLinkForEpisode(animeId: anime.id, episodeNumber: nextEpisode) {
            let label = "WATCH EP \(nextEpisode) ON \(episodeLink.site.uppercased())"
            return (episodeLink.url, episodeLink.site, label)
        }

        let links = await fetchExternalLinks(mediaType: "ANIME", mediaId: anime.id)
        guard let best = bestLink(from: links, ranking: animeProviderRanking) else {
            return nil
        }
        let siteLabel = (best.site ?? "PROVIDER").uppercased()
        let verb = (userProgress ?? 0) > 0 ? "CONTINUE" : "WATCH"
        return (best.url, best.site ?? "Provider", "\(verb) ON \(siteLabel)")
    }

    func getBestReadLink(manga: Manga) async -> (url: String, site: String, label: String)? {
        let links = await fetchExternalLinks(mediaType: "MANGA", mediaId: manga.id)
        guard let best = bestLink(from: links, ranking: mangaProviderRanking) else { return nil }
        let siteLabel = (best.site ?? "Reader").uppercased()
        return (best.url, best.site ?? "Reader", "READ ON \(siteLabel)")
    }

    // MARK: - Browse (server-driven paging + filters)
    func fetchBrowseAnimePageKeyset(
        genre: String?,
        status: String?,
        minEpisodes: Int?,
        maxEpisodes: Int?,
        sort: BrowseSort = .popular,
        cursorInt: Int?,
        cursorDate: Date?,
        cursorId: Int?,
        limit: Int
    ) async -> [AnimeCard] {
        do {
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
                p_limit: max(1, min(120, limit))
            )
            let rows: [AnimeCard] = try await client.rpc("browse_anime_page", params: params).execute().value
            KuroPerf.end(perf, message: "ok")
            return rows
        } catch {
            print("❌ browse_anime_page rpc: \(error)")
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
        limit: Int
    ) async -> [MangaCard] {
        do {
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
                p_limit: max(1, min(120, limit))
            )
            let rows: [MangaCard] = try await client.rpc("browse_manga_page", params: params).execute().value
            KuroPerf.end(perf, message: "ok")
            return rows
        } catch {
            print("❌ browse_manga_page rpc: \(error)")
            return []
        }
    }

    func fetchBrowseAnimePage(
        genre: String?,
        status: String?,
        minEpisodes: Int?,
        maxEpisodes: Int?,
        sort: BrowseSort = .popular,
        page: Int,
        pageSize: Int
    ) async -> [Anime] {
        do {
            let size = max(1, pageSize)
            let offset = max(0, page) * size
            var q = client.from("anime").select()

            if let genre, !genre.isEmpty {
                q = q.contains("genres", value: [genre])
            }
            if let status, !status.isEmpty {
                q = q.eq("status", value: status)
            }
            if let minEpisodes {
                q = q.gte("episodes", value: minEpisodes)
            }
            if let maxEpisodes {
                q = q.lte("episodes", value: maxEpisodes)
            }

            let ordered = q.order(sort.orderColumn, ascending: false).order("id", ascending: false)
            return try await ordered.range(from: offset, to: offset + size - 1).execute().value
        } catch {
            print("❌ browse anime fetch: \(error)")
            return []
        }
    }

    func fetchBrowseMangaPage(
        genre: String?,
        status: String?,
        minChapters: Int?,
        maxChapters: Int?,
        sort: BrowseSort = .popular,
        page: Int,
        pageSize: Int
    ) async -> [Manga] {
        do {
            let size = max(1, pageSize)
            let offset = max(0, page) * size
            var q = client.from("manga").select()

            if let genre, !genre.isEmpty {
                q = q.contains("genres", value: [genre])
            }
            if let status, !status.isEmpty {
                q = q.eq("status", value: status)
            }
            if let minChapters {
                q = q.gte("chapters", value: minChapters)
            }
            if let maxChapters {
                q = q.lte("chapters", value: maxChapters)
            }

            let ordered = q.order(sort.orderColumn, ascending: false).order("id", ascending: false)
            return try await ordered.range(from: offset, to: offset + size - 1).execute().value
        } catch {
            print("❌ browse manga fetch: \(error)")
            return []
        }
    }
    
    // MARK: - Filter by Genre (using your genres array)
    func filterByGenre(_ genre: String) async {
        isLoading = true
        
        do {
            let response: [Anime] = try await client
                .from("anime")
                .select()
                .contains("genres", value: [genre])
                .order("average_score", ascending: false)
                .limit(50)
                .execute()
                .value
            
            animeItems = response
            print("✅ Filtered by genre: \(genre)")
        } catch {
            errorMessage = "Filter failed: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Get by Mood (using your genre system)
    func getByMood(_ mood: String) -> [Anime] {
        switch mood {
        case "Contemplative":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Drama", "Psychological", "Mystery"].contains(genre)
                }) ?? false
            }
        case "Energetic":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Action", "Sports", "Adventure"].contains(genre)
                }) ?? false
            }
        case "Melancholic":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Drama", "Romance", "Slice of Life"].contains(genre)
                }) ?? false
            }
        case "Uplifting":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Comedy", "Adventure", "Music"].contains(genre)
                }) ?? false
            }
        case "Mysterious":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Thriller", "Horror", "Supernatural", "Mystery"].contains(genre)
                }) ?? false
            }
        default:
            return Array(animeItems.prefix(10))
        }
    }

    // MARK: - Concierge (Edge Functions)
    enum ConciergeScope: String, Sendable {
        case anime
        case manga
        case both
    }

    struct ConciergeCandidate: Decodable, Sendable, Hashable {
        let media_type: String
        let media_id: Int
        let variant_type: String
        let title_raw: String
        let score: Double
    }

    struct ConciergeParseItemParsed: Decodable, Sendable {
        let mediaTypeHint: String?
        let status: String?
        let progressEpisodes: Int?
        let progressChapters: Int?
        let progressVolumes: Int?
        let completed: Bool?
    }

    struct ConciergeParseItem: Decodable, Sendable, Identifiable {
        let raw: String
        let normalized: String
        let parsed: ConciergeParseItemParsed
        let candidates: [ConciergeCandidate]
        let candidateError: String?

        var id: String { raw + "|" + normalized }
    }

    struct ConciergeParseResponse: Decodable, Sendable {
        let success: Bool
        let userId: String?
        let items: [ConciergeParseItem]
    }

    func conciergeParse(text: String, scope: ConciergeScope = .both, limitPerItem: Int = 10) async throws -> ConciergeParseResponse {
        let payload = [
            "text": text,
            "scope": scope.rawValue,
            "limitPerItem": max(3, min(15, limitPerItem)),
        ] as [String : Any]

        // Encode payload as JSON (FunctionsClient encodes Encodable; use JSONSerialization here).
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        struct Raw: Encodable { let raw: Data }
        // Use Data body directly so we don't fight Encodable boxing.
        let options = FunctionInvokeOptions(method: .post, body: data)
        return try await client.functions.invoke("concierge-parse", options: options)
    }

    struct ConciergeApplyResponse: Decodable, Sendable {
        let success: Bool
        let sessionId: String?
        struct Applied: Decodable, Sendable {
            let mediaType: String
            let mediaId: Int
            let status: String
        }
        struct ApplyError: Decodable, Sendable {
            let mediaType: String?
            let mediaId: Int?
            let error: String
        }
        let applied: [Applied]?
        let errors: [ApplyError]?
    }

    func conciergeApply(items: [[String: Any]]) async throws -> ConciergeApplyResponse {
        let payload: [String: Any] = [
            "items": items,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let options = FunctionInvokeOptions(method: .post, body: data)
        return try await client.functions.invoke("concierge-apply", options: options)
    }

    struct ConciergeUndoResponse: Decodable, Sendable {
        let success: Bool
        let sessionId: String?
        struct Reverted: Decodable, Sendable {
            let mediaType: String
            let mediaId: Int
        }
        struct UndoError: Decodable, Sendable {
            let id: String?
            let error: String
        }
        let reverted: [Reverted]?
        let errors: [UndoError]?
    }

    func conciergeUndo(sessionId: String) async throws -> ConciergeUndoResponse {
        let payload: [String: Any] = [
            "sessionId": sessionId,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let options = FunctionInvokeOptions(method: .post, body: data)
        return try await client.functions.invoke("concierge-undo", options: options)
    }

    struct ConciergeRecommendResponse: Decodable, Sendable {
        let success: Bool
        let categories: [String]?
        struct Item: Decodable, Sendable, Identifiable {
            let mediaType: String
            let mediaId: Int
            let matchCount: Int?
            let title: String
            let coverImageMedium: String?
            let averageScore: Int?
            let year: Int?
            let format: String?
            let status: String?
            let siteUrl: String?

            var id: String { "\(mediaType)|\(mediaId)" }
        }
        let items: [Item]?
        let message: String?
        let error: String?
    }

    func conciergeRecommend(text: String, scope: ConciergeScope = .both, limit: Int = 8) async throws -> ConciergeRecommendResponse {
        let payload: [String: Any] = [
            "text": text,
            "scope": scope.rawValue,
            "limit": max(3, min(20, limit)),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let options = FunctionInvokeOptions(method: .post, body: data)
        return try await client.functions.invoke("concierge-recommend", options: options)
    }
    
    // MARK: - Real-time Subscriptions  
    func subscribeToUpdates() {
        // Optional: Add Supabase Realtime listeners here if your SDK version supports it.
        // Fallback: Lightweight polling to refresh content and user lists.
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                await self.fetchAnime(limit: 20)
                await self.fetchUserLists()
            }
        }
    }
    
    // MARK: - Collection Management Helpers
    // Fast lookup caches to keep scrolling snappy (avoid O(n) list scans per card render).
    private var collectionAnimeIds: Set<Int> = []
    private var collectionMangaIds: Set<Int> = []
    private var userListByTypeAndId: [String: [Int: UserList]] = [:]
    private var userIdsByTypeAndStatus: [String: [ListStatus: Set<Int>]] = [:]

    private func rebuildUserListCaches() {
        var anime: Set<Int> = []
        var manga: Set<Int> = []
        var byType: [String: [Int: UserList]] = ["anime": [:], "manga": [:]]
        var byTypeStatus: [String: [ListStatus: Set<Int>]] = ["anime": [:], "manga": [:]]

        for item in userLists {
            let t = item.mediaType.lowercased()
            if t == "anime" { anime.insert(item.mediaId) }
            if t == "manga" { manga.insert(item.mediaId) }
            byType[t, default: [:]][item.mediaId] = item
            byTypeStatus[t, default: [:]][item.status, default: []].insert(item.mediaId)
        }

        collectionAnimeIds = anime
        collectionMangaIds = manga
        userListByTypeAndId = byType
        userIdsByTypeAndStatus = byTypeStatus
    }

    func userMediaIds(mediaType: String, status: ListStatus? = nil) -> Set<Int> {
        let t = mediaType.lowercased()
        if let status {
            return userIdsByTypeAndStatus[t]?[status] ?? []
        }
        switch t {
        case "anime": return collectionAnimeIds
        case "manga": return collectionMangaIds
        default: return []
        }
    }

    func isInCollection(mediaId: Int, mediaType: String) -> Bool {
        switch mediaType.lowercased() {
        case "anime": return collectionAnimeIds.contains(mediaId)
        case "manga": return collectionMangaIds.contains(mediaId)
        default: return false
        }
    }

    func isInCollection(_ animeId: Int) -> Bool {
        isInCollection(mediaId: animeId, mediaType: "anime")
    }

    func isInCollectionManga(_ mangaId: Int) -> Bool {
        isInCollection(mediaId: mangaId, mediaType: "manga")
    }

    func userListProgress(mediaType: String, mediaId: Int) -> Int? {
        userListByTypeAndId[mediaType.lowercased()]?[mediaId]?.progress
    }

    func isFavorited(_ animeId: Int) -> Bool {
        // Check if anime has high score (favorited)
        return userListByTypeAndId["anime"]?[animeId]?.score ?? 0 >= 90
    }

    func toggleInCollection(mediaId: Int, mediaType: String) {
        let type = mediaType.lowercased()
        if isInCollection(mediaId: mediaId, mediaType: type) {
            Task { await removeFromList(mediaId: mediaId, mediaType: type) }
        } else {
            Task { await addToList(mediaId: mediaId, mediaType: type, status: .planning) }
        }
    }

    func toggleInCollection(_ animeId: Int) {
        toggleInCollection(mediaId: animeId, mediaType: "anime")
    }

    func toggleFavorite(for animeId: Int) {
        // Toggle by setting/removing high score
        Task {
            guard let entry = userLists.first(where: { $0.mediaId == animeId && $0.mediaType.lowercased() == "anime" }) else { return }
            let shouldUnfavorite = (entry.score ?? 0) >= 90
            let newRating: Int? = shouldUnfavorite ? nil : 10
            await updateListRating(mediaId: animeId, mediaType: "anime", rating: newRating)
        }
    }

    private func updateListRating(mediaId: Int, mediaType: String, rating: Int?) async {
        guard let userId = await currentUserIdString() else { return }
        do {
            let table = mediaType.lowercased() == "anime" ? "anime_user_lists" : "manga_user_lists"
            let idColumn = mediaType.lowercased() == "anime" ? "anime_id" : "manga_id"

            struct UpdateData: Encodable {
                let rating: Int?
            }

            try await client
                .from(table)
                .update(UpdateData(rating: rating))
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            await fetchUserLists()
        } catch {
            print("❌ Failed to update rating: \(error)")
        }
    }
}

#else
// Fallback mock service when the Supabase SDK isn't available
@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()

    // Data stores
    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    var isLoading = false
    var errorMessage: String?

    init() {
        // No-op: mock environment
        print("⚠️ Supabase SDK not found. Running with mock SupabaseService.")
    }

    // Auth no-op
    func signInAnonymously() async throws {}

    // Data loading no-ops that simulate empty results
    func fetchAnime(limit: Int = 50) async {
        isLoading = true
        defer { isLoading = false }
        animeItems = []
    }

    func fetchManga(limit: Int = 50) async {
        isLoading = true
        defer { isLoading = false }
        mangaItems = []
    }

    func searchContent(query: String) async {
        isLoading = true
        defer { isLoading = false }
        // Keep whatever is already loaded (mock does nothing)
    }

    func fetchUserLists() async {
        userLists = []
    }

    func addToList(mediaId: Int, mediaType: String, status: ListStatus) async {
        // No persistence in mock
    }

    func filterByGenre(_ genre: String) async {
        isLoading = true
        defer { isLoading = false }
        // No-op
    }

    func getByMood(_ mood: String) -> [Anime] {
        return []
    }

    func subscribeToUpdates() {
        // No realtime in mock
    }

    func isInCollection(_ animeId: Int) -> Bool { false }
    func isFavorited(_ animeId: Int) -> Bool { false }
    func toggleInCollection(_ animeId: Int) {}
    func toggleFavorite(for animeId: Int) {}
}
#endif
