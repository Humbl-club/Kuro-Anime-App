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
    
    // Apple Foundation Models service (on-device classification/condensation)
    let fmService = AppleFMService()

    // Concierge telemetry (fire-and-forget, privacy-safe)
    let analytics = ConciergeAnalytics.shared

    // Supabase client
    private let client: SupabaseClient
    // Realtime (user-scoped) subscriptions
    private var realtimeChannel: RealtimeChannelV2? = nil
    private var realtimeListenTasks: [Task<Void, Never>] = []
    private var realtimeDebounceTask: Task<Void, Never>? = nil
    private var realtimeSubscribedUserId: String? = nil

    // Auth state
    var isAuthBootstrapping: Bool = true
    var isAuthenticated: Bool = false
    var authErrorMessage: String? = nil
    // Lightweight identity for UI (header menus, etc.)
    var currentUserEmail: String? = nil
    // Used for local-only UI labeling (e.g. Clubs member list "You").
    var currentUserId: String? = nil

    var currentUserInitial: String {
        let c = currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).first
        return c.map { String($0).uppercased() } ?? "M"
    }

    // MARK: - Shared interaction telemetry helpers

    typealias InteractionStartedAt = CFAbsoluteTime

    func beginInteractionTiming() -> InteractionStartedAt {
        CFAbsoluteTimeGetCurrent()
    }

    func trackInteractionEvent(
        _ event: String,
        surface: String,
        result: String,
        startedAt: InteractionStartedAt? = nil,
        extra: [String: Any] = [:]
    ) {
        var payload = extra
        payload["surface"] = surface
        payload["result"] = result
        payload["market"] = Locale.current.region?.identifier.uppercased() ?? "US"
        if let startedAt {
            payload["latency_ms"] = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0)
        }
        analytics.track(event, payload: payload)
    }
    
    // Observable properties (no @Published needed with @Observable)
    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    // User's personal collection (server-driven; doesn't rely on global prefetch)
    // Lightweight cards for collection grids; details are loaded on demand.
    var collectionAnimeItems: [AnimeCard] = []
    var collectionMangaItems: [MangaCard] = []
    // Unified feed used by the main Collection screen (anime + manga interleaved by last updated).
    var collectionFeedItems: [Media] = []
    var isCollectionLoading: Bool = false
    var collectionErrorMessage: String? = nil
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    // Detail caches: cards/grids only carry minimal fields; we fetch full details by id on demand.
    private var animeDetailCache: [Int: Anime] = [:]
    private var mangaDetailCache: [Int: Manga] = [:]
    // De-dupe frequently called network fetches so multiple screens mounting doesn't fan-out.
    private var userListsFetchInFlight: Task<Void, Never>? = nil
    private var collectionFetchInFlight: Task<Void, Never>? = nil
    private var collectionFetchGeneration: Int = 0
    private var collectionFetchInFlightGeneration: Int = 0
    private var collectionFeedFetchInFlight: Task<Void, Never>? = nil
    private var collectionFeedFetchGeneration: Int = 0
    private var collectionFeedFetchInFlightGeneration: Int = 0
    private var upcomingFetchInFlight: Task<Void, Never>? = nil

    // Lightweight response caches (avoid refetching the same rails/recs when a view reappears).
    private struct TimedCache<T>: Sendable {
        let value: T
        let storedAt: Date
    }

    private var discoverBundleCache: [String: TimedCache<DiscoverBundle>] = [:]
    private var discoverBundleInFlight: [String: Task<DiscoverBundle?, Never>] = [:]

    private var conciergeRecommendCache: [String: TimedCache<ConciergeRecommendResponse>] = [:]
    private var conciergeRecommendInFlight: [String: Task<ConciergeRecommendResponse, Error>] = [:]

    private var conciergeParseCache: [String: TimedCache<ConciergeParseResponse>] = [:]
    private var conciergeParseInFlight: [String: Task<ConciergeParseResponse, Error>] = [:]

    private func trimCache<T>(_ cache: inout [String: TimedCache<T>], maxEntries: Int) {
        guard cache.count > maxEntries else { return }
        let sorted = cache.sorted { $0.value.storedAt < $1.value.storedAt }
        let removeCount = max(0, sorted.count - maxEntries)
        for (k, _) in sorted.prefix(removeCount) { cache.removeValue(forKey: k) }
    }

    /// Retry helper for transient network failures (URLError only).
    /// Non-network errors (e.g. HTTP 4xx, decoding) are thrown immediately.
    /// Static so it's callable from any isolation context (including Task.detached).
    private static func withRetry<T>(
        maxRetries: Int = 2,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch let error as URLError {
                lastError = error
                if attempt < maxRetries {
                    #if DEBUG
                    print("⟳ retry \(attempt + 1)/\(maxRetries) after URLError \(error.code.rawValue)")
                    #endif
                    try await Task.sleep(for: .milliseconds(Int(500 * pow(2.0, Double(attempt)))))
                }
            } catch {
                throw error // Non-network errors are not retried
            }
        }
        throw lastError!
    }

    private struct BackoffState: Sendable {
        var failures: Int = 0
        var until: Date? = nil

        mutating func canAttempt(now: Date = Date()) -> Bool {
            guard let until else { return true }
            return now >= until
        }

        mutating func recordSuccess() {
            failures = 0
            until = nil
        }

        mutating func recordFailure(now: Date = Date()) {
            failures = min(failures + 1, 6)
            let base: Double = 2.0
            let delay = min(60.0, base * pow(2.0, Double(failures - 1)))
            until = now.addingTimeInterval(delay)
        }
    }

    private var upcomingBackoff = BackoffState()
    private var lastUpcomingFetchAt: Date? = nil
    private var lastUpcomingDays: Int = 7

    // Collection pagination state (keyset by list updated_at + list row id).
    var hasMoreCollectionAnime: Bool = true
    var hasMoreCollectionManga: Bool = true
    var isLoadingMoreCollectionAnime: Bool = false
    var isLoadingMoreCollectionManga: Bool = false
    private var collectionAnimeCursorUpdatedAt: Date? = nil
    private var collectionAnimeCursorRowId: Int? = nil
    private var collectionMangaCursorUpdatedAt: Date? = nil
    private var collectionMangaCursorRowId: Int? = nil

    // Collection feed pagination state (keyset by updated_at + source_rank + list row id).
    var hasMoreCollectionFeed: Bool = true
    var isLoadingMoreCollectionFeed: Bool = false
    private var collectionFeedCursorUpdatedAt: Date? = nil
    private var collectionFeedCursorSourceRank: Int? = nil
    private var collectionFeedCursorRowId: Int? = nil

    private var currentCollectionStatusFilter: ListStatus? = nil
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

    private func sanitizeAnimeForDiscovery(_ items: [Anime]) -> [Anime] {
        sanitizeAnimeForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    private func sanitizeAnimeForDiscovery(_ items: [Anime], policy: DiscoveryPolicy) -> [Anime] {
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

    private func sanitizeMangaForDiscovery(_ items: [Manga]) -> [Manga] {
        sanitizeMangaForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    private func sanitizeMangaForDiscovery(_ items: [Manga], policy: DiscoveryPolicy) -> [Manga] {
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
    // NOTE: These are lightweight cards (rank included for keyset pagination).
    var searchAnimeItems: [AnimeCard] = []
    var searchMangaItems: [MangaCard] = []
    private var currentSearchQuery: String = ""
    private enum SearchMode { case anime, manga, combined }
    private var searchMode: SearchMode = .anime
    private var searchPageSize = 20
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
            #if DEBUG
            print("⚠️ Using fallback Supabase config from code. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist or env.")
            #endif
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key
        )
        analytics.configure(client: client)
        #if DEBUG
        print("🔥 Supabase client initialized: \(url.host ?? url.absoluteString)")
        #endif

        Task { await restoreSession() }
    }
    
    // MARK: - Authentication
    func restoreSession() async {
        defer { isAuthBootstrapping = false }

        do {
            let session = try await client.auth.session
            isAuthenticated = true
            authErrorMessage = nil
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)
            await ensureProfileRow()
            // Fire bootstrap without blocking — the UI can show immediately
            // with shimmer/skeleton placeholders while data loads in parallel.
            Task { await bootstrapAfterAuth() }
        } catch {
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            let session = try await client.auth.session
            isAuthenticated = true
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = error.localizedDescription
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
            throw error
        }
    }

    func signUpWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            // Depending on Supabase settings, user may need email confirmation. We still attempt bootstrap if a session exists.
            if let session = (try? await client.auth.session) {
                isAuthenticated = true
                currentUserEmail = session.user.email
                currentUserId = session.user.id.uuidString
                analytics.setUserId(currentUserId)
                await ensureProfileRow()
                await bootstrapAfterAuth()
            } else {
                isAuthenticated = false
                currentUserId = nil
                analytics.setUserId(nil)
            }
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {
        authErrorMessage = nil
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
            isAuthenticated = true
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)

            // Apple only provides full name on first sign-in; persist it.
            if let fullName, !fullName.isEmpty {
                try? await client.auth.update(
                    user: .init(data: ["full_name": .string(fullName)])
                )
            }

            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = error.localizedDescription
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
            throw error
        }
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    /// GDPR-compliant account deletion. Calls the `delete-account` Edge Function
    /// which cascades through all user data tables, removes storage objects,
    /// then deletes the auth.users row.
    var isAppleUser: Bool {
        get async {
            guard let user = try? await client.auth.user() else { return false }
            return user.identities?.contains(where: { $0.provider == "apple" }) ?? false
        }
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        struct DeleteResponse: Decodable {
            let success: Bool?
            let error: String?
            let message: String?
        }
        var body: [String: String] = ["confirm": "true"]
        if let appleAuthorizationCode {
            body["apple_authorization_code"] = appleAuthorizationCode
        }
        let response: DeleteResponse = try await client.functions.invoke(
            "delete-account",
            options: .init(body: body)
        )
        if response.success != true {
            throw NSError(
                domain: "KuroAccountDeletion",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: response.error ?? response.message ?? "Account deletion failed"]
            )
        }
        // Clear local state (same as sign out).
        await stopRealtimeSubscriptions()
        isAuthenticated = false
        currentUserEmail = nil
        currentUserId = nil
        authErrorMessage = nil
        stopCountdownUpdates()
        resetUserState()
        analytics.setUserId(nil)
        FeatureFlags.shared.setUserId(nil)
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            #if DEBUG
            print("❌ signOut error: \(error)")
            #endif
            // Error logged in debug only
        }
        await stopRealtimeSubscriptions()
        isAuthenticated = false
        currentUserEmail = nil
        currentUserId = nil
        authErrorMessage = nil
        stopCountdownUpdates()
        resetUserState()
        analytics.setUserId(nil)
        FeatureFlags.shared.setUserId(nil)
    }

    private func resetUserState() {
        userLists = []
        collectionAnimeItems = []
        collectionMangaItems = []
        collectionFeedItems = []
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
            #if DEBUG
            print("⚠️ ensureProfileRow failed: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    private func bootstrapAfterAuth() async {
        // Fetch all independent user data in parallel to cut startup latency.
        // Each fetch updates @Observable properties, so the UI fills progressively.
        async let lists: () = fetchUserLists()
        async let collection: () = fetchCollectionItems()
        async let feed: () = fetchCollectionFeed()
        async let upcoming: () = fetchUpcomingForUser(days: 7)
        _ = await (lists, collection, feed, upcoming)

        startCountdownUpdates()
        subscribeToUpdates()

        // Feature flags are non-critical; fire without blocking.
        Task { await FeatureFlags.shared.refresh(client: client, userId: currentUserId) }
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
            let response: [Anime] = try await Self.withRetry {
                try await self.client
                    .from("anime")
                    .select()
                    .order("popularity", ascending: false)
                    .range(from: offset, to: offset + self.pageSize - 1)
                    .execute()
                    .value
            }

            animeItems.append(contentsOf: response)
            hasMoreAnime = response.count == pageSize
            if hasMoreAnime { currentAnimePage += 1 }
            #if DEBUG
            print("✅ Fetched page \(currentAnimePage) (\(response.count) items), total: \(animeItems.count)")
            #endif
        } catch {
            errorMessage = "Failed to fetch anime: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Supabase error: \(error)")
            #endif
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
            let response: [Manga] = try await Self.withRetry {
                try await self.client
                    .from("manga")
                    .select()
                    .order("popularity", ascending: false)
                    .range(from: offset, to: offset + self.pageSize - 1)
                    .execute()
                    .value
            }

            mangaItems.append(contentsOf: response)
            hasMoreManga = response.count == pageSize
            if hasMoreManga { currentMangaPage += 1 }
            #if DEBUG
            print("✅ Fetched manga page \(currentMangaPage) (\(response.count) items), total: \(mangaItems.count)")
            #endif
        } catch {
            errorMessage = "Failed to fetch manga: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error: \(error)")
            #endif
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
            #if DEBUG
            print("✅ Found \(animeResponse.count) anime, \(mangaResponse.count) manga")
            #endif
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Search error: \(error)")
            #endif
        }
        
        isLoading = false
    }

    // MARK: - Server-side paged text search
    func setSearchPageSize(_ size: Int) { searchPageSize = max(1, size) }

    func resetSearch(query: String, isManga: Bool) {
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
        // Avoid hammering the DB for 1-character incremental typing.
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }
        isSearching = true
        defer { isSearching = false }

        do {
            if searchMode == .manga {
                let page = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: searchCursorMangaRank,
                    cursorPopularity: searchCursorMangaPopularity,
                    cursorId: searchCursorMangaId,
                    limit: searchPageSize
                )
                searchMangaItems.append(contentsOf: page)
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            } else {
                let page = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: searchCursorAnimeRank,
                    cursorPopularity: searchCursorAnimePopularity,
                    cursorId: searchCursorAnimeId,
                    limit: searchPageSize
                )
                searchAnimeItems.append(contentsOf: page)
                hasMoreSearch = page.count == searchPageSize
                if let last = page.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
            }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            hasMoreSearch = false
            #if DEBUG
            print("❌ Search page error: \(error)")
            #endif
        }
    }

    func resetCombinedSearch(query: String) {
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

    func fetchNextCombinedSearchPage() async {
        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard hasMoreSearch, !isSearching else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let filters = currentSearchFilters

            if hasMoreSearchAnime {
                let page = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: searchCursorAnimeRank,
                    cursorPopularity: searchCursorAnimePopularity,
                    cursorId: searchCursorAnimeId,
                    limit: searchPageSize
                )
                searchAnimeItems.append(contentsOf: page)
                hasMoreSearchAnime = page.count == searchPageSize
                if let last = page.last {
                    searchCursorAnimeRank = last.rank ?? 0
                    searchCursorAnimePopularity = last.popularity ?? 0
                    searchCursorAnimeId = last.id
                }
            }

            if hasMoreSearchManga {
                let page = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: filters,
                    cursorRank: searchCursorMangaRank,
                    cursorPopularity: searchCursorMangaPopularity,
                    cursorId: searchCursorMangaId,
                    limit: searchPageSize
                )
                searchMangaItems.append(contentsOf: page)
                hasMoreSearchManga = page.count == searchPageSize
                if let last = page.last {
                    searchCursorMangaRank = last.rank ?? 0
                    searchCursorMangaPopularity = last.popularity ?? 0
                    searchCursorMangaId = last.id
                }
            }

            hasMoreSearch = hasMoreSearchAnime || hasMoreSearchManga
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            hasMoreSearch = false
            hasMoreSearchAnime = false
            hasMoreSearchManga = false
            #if DEBUG
            print("❌ Combined search error: \(error)")
            #endif
        }
    }

    // MARK: - Search refresh (keeps old results on transient failures)
    func refreshSearch() async {
        let trimmedQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty && currentSearchFilters == nil { return }
        if trimmedQuery.count < 2 && currentSearchFilters == nil { return }
        guard !isSearching else { return }

        let oldAnime = searchAnimeItems
        let oldManga = searchMangaItems
        let oldHasMore = hasMoreSearch
        let oldHasMoreAnime = hasMoreSearchAnime
        let oldHasMoreManga = hasMoreSearchManga

        isSearching = true
        defer { isSearching = false }

        do {
            switch searchMode {
            case .anime:
                searchCursorAnimeRank = nil
                searchCursorAnimePopularity = nil
                searchCursorAnimeId = nil
                let page = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
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
                let page = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
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

                let animePage = try await fetchSearchAnimePage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
                let mangaPage = try await fetchSearchMangaPage(
                    query: trimmedQuery,
                    filters: currentSearchFilters,
                    cursorRank: nil,
                    cursorPopularity: nil,
                    cursorId: nil,
                    limit: searchPageSize
                )
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

    private func fetchSearchAnimePage(
        query: String,
        filters: SearchFilters?,
        cursorRank: Double?,
        cursorPopularity: Int?,
        cursorId: Int?,
        limit: Int
    ) async throws -> [AnimeCard] {
        let perf = KuroPerf.begin("rpc.search_anime_page")
        do {
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

    private func fetchSearchMangaPage(
        query: String,
        filters: SearchFilters?,
        cursorRank: Double?,
        cursorPopularity: Int?,
        cursorId: Int?,
        limit: Int
    ) async throws -> [MangaCard] {
        let perf = KuroPerf.begin("rpc.search_manga_page")
        do {
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

    // MARK: - Discover bundle (single call)
    func fetchDiscoverBundle(limit: Int = 30, hours: Int = 24, force: Bool = false) async -> DiscoverBundle? {
        let key = "discover_bundle|\(max(1, min(60, limit)))|\(max(1, min(168, hours)))"
        let now = Date()
        if !force, let cached = discoverBundleCache[key], now.timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        if let task = discoverBundleInFlight[key] {
            return await task.value
        }

        let task = Task<DiscoverBundle?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            let perf = KuroPerf.begin("rpc.discover_bundle")
            do {
                let params = RPCDiscoverBundleParams(
                    p_limit: max(1, min(60, limit)),
                    p_hours: max(1, min(168, hours))
                )
                let bundle: DiscoverBundle = try await Self.withRetry {
                    try await self.client
                        .rpc("discover_bundle", params: params)
                        .execute()
                        .value
                }
                KuroPerf.end(perf, message: "ok")
                self.discoverBundleCache[key] = TimedCache(value: bundle, storedAt: now)
                self.trimCache(&self.discoverBundleCache, maxEntries: 6)
                return bundle
            } catch {
                #if DEBUG
                print("❌ discover_bundle rpc: \(error)")
                #endif
                KuroPerf.end(perf, message: "error")
                return nil
            }
        }

        discoverBundleInFlight[key] = task
        let value = await task.value
        discoverBundleInFlight[key] = nil
        return value
    }

    // MARK: - Detail fetch by id (full models)
    func fetchAnimeById(_ animeId: Int) async throws -> Anime? {
        if let cached = animeDetailCache[animeId] { return cached }
        if let disk: Anime = await KuroDiskDetailCache.read(kind: .anime, id: animeId, as: Anime.self) {
            animeDetailCache[animeId] = disk
            return disk
        }
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
                Task { await KuroDiskDetailCache.write(kind: .anime, id: animeId, value: item) }
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
        if let disk: Manga = await KuroDiskDetailCache.read(kind: .manga, id: mangaId, as: Manga.self) {
            mangaDetailCache[mangaId] = disk
            return disk
        }
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
                Task { await KuroDiskDetailCache.write(kind: .manga, id: mangaId, value: item) }
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
        } catch {
            #if DEBUG
            print("❌ trending fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ current season fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchSeasonAnime(season: String, year: Int, limit: Int = 20, onlyAiring: Bool = true, genre: String? = nil) async -> [Anime] {
        do {
            var q = client.from("anime").select().eq("season", value: season).eq("season_year", value: year)
            if onlyAiring { q = q.eq("status", value: "RELEASING") }
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("popularity", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ season fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchNewlyAddedAnime(limit: Int = 20, genre: String? = nil) async -> [Anime] {
        do {
            // Uses materialized view for fast, stable results (refreshed nightly by cron).
            var q = client.from("mv_anime_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Anime] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeAnimeForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ newly added fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ top rated fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    // MARK: - Server-driven Discover sections (Manga)
    func fetchTrendingManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_trending").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("trending", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ manga trending fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchNewlyAddedManga(limit: Int = 20, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_newly_added").select()
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("created_at", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ manga newly added fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
    }

    func fetchTopRatedManga(limit: Int = 20, minScore: Int = 80, genre: String? = nil) async -> [Manga] {
        do {
            var q = client.from("mv_manga_top_rated").select().gte("average_score", value: minScore)
            if let genre, !genre.isEmpty { q = q.contains("genres", value: [genre]) }
            let rows: [Manga] = try await q.order("average_score", ascending: false).order("id", ascending: false)
                .range(from: 0, to: max(0, limit - 1)).execute().value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            #if DEBUG
            print("❌ manga top rated fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ essentials anime fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ classics anime fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ new-to-you anime fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ essentials manga fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ classics manga fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ new-to-you manga fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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
        } catch {
            #if DEBUG
            print("❌ airing soon fetch: \(error)")
            #endif
            // Error logged in debug only
            return []
        }
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

    /// Returns top non-adult tags for a specific anime (used for "sub-genres" on detail pages).
    func fetchTopTagsForAnime(animeId: Int, limit: Int = 12) async -> [TagFacet] {
        do {
            let rows: [_AnimeTagSampleRow] = try await client
                .from("anime")
                .select("id,anime_tags(rank,tags(id,name,category,is_adult))")
                .eq("id", value: animeId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return [] }
            let tags = row.animeTags
                .compactMap { edge -> (id: Int, name: String, category: String?, isAdult: Bool, rank: Int)? in
                    guard let node = edge.tags else { return nil }
                    let r = edge.rank ?? 0
                    return (node.id, node.name, node.category, node.isAdult, r)
                }
                .filter { !$0.isAdult }
                .sorted { $0.rank > $1.rank }
                .prefix(limit)
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: 0) }
            return Array(tags)
        } catch {
            #if DEBUG
            print("❌ anime tag fetch: \(error)")
            #endif
            return []
        }
    }

    /// Returns top non-adult tags for a specific manga (used for "sub-genres" on detail pages).
    func fetchTopTagsForManga(mangaId: Int, limit: Int = 12) async -> [TagFacet] {
        do {
            let rows: [_MangaTagSampleRow] = try await client
                .from("manga")
                .select("id,manga_tags(rank,tags(id,name,category,is_adult))")
                .eq("id", value: mangaId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return [] }
            let tags = row.mangaTags
                .compactMap { edge -> (id: Int, name: String, category: String?, isAdult: Bool, rank: Int)? in
                    guard let node = edge.tags else { return nil }
                    let r = edge.rank ?? 0
                    return (node.id, node.name, node.category, node.isAdult, r)
                }
                .filter { !$0.isAdult }
                .sorted { $0.rank > $1.rank }
                .prefix(limit)
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: 0) }
            return Array(tags)
        } catch {
            #if DEBUG
            print("❌ manga tag fetch: \(error)")
            #endif
            return []
        }
    }

    /// Minimal "More like this" fetcher for detail pages (Swiss minimal: deterministic, no LLM).
    /// Primary path uses the DB similarity RPC (tag overlap + editorial boosts/penalties).
    /// Falls back to a lightweight genre anchor if the RPC isn't available.
    func fetchSimilarAnime(seed: Anime, limit: Int = 14) async -> [Anime] {
        let rpc = await fetchSimilarIdsViaRPC(mediaType: "ANIME", seedIds: [seed.id], limit: limit, allowGimmicks: false)
        if !rpc.isEmpty, let items = await fetchAnimeByIdsPreservingOrder(rpc.map(\.mediaId)) {
            return sanitizeAnimeForDiscovery(items)
        }
        return await fetchSimilarAnimeFallbackByGenre(seed: seed, limit: limit)
    }

    func fetchSimilarManga(seed: Manga, limit: Int = 14) async -> [Manga] {
        let rpc = await fetchSimilarIdsViaRPC(mediaType: "MANGA", seedIds: [seed.id], limit: limit, allowGimmicks: false)
        if !rpc.isEmpty, let items = await fetchMangaByIdsPreservingOrder(rpc.map(\.mediaId)) {
            return sanitizeMangaForDiscovery(items)
        }
        return await fetchSimilarMangaFallbackByGenre(seed: seed, limit: limit)
    }

    private struct _RecommendSimilarRow: Decodable {
        let mediaId: Int
        let overlapCount: Int
        let score: Double

        enum CodingKeys: String, CodingKey {
            case mediaId = "media_id"
            case overlapCount = "overlap_count"
            case score
        }
    }

    private func fetchSimilarIdsViaRPC(
        mediaType: String,
        seedIds: [Int],
        limit: Int,
        allowGimmicks: Bool
    ) async -> [_RecommendSimilarRow] {
        // This RPC is a production-grade deterministic similarity engine (tag overlap + editorial weights).
        // It may be missing in some DBs (or require auth, depending on migration state), so treat failure as "no results".
        let perf = KuroPerf.begin("rpc.recommend_ids_similar_to_seeds")
        do {
            let params = RPCRecommendSimilarParams(
                p_media_type: mediaType,
                p_seed_ids: seedIds,
                p_limit: max(1, min(50, limit)),
                p_allow_gimmicks: allowGimmicks
            )
            let rows: [_RecommendSimilarRow] = try await client
                .rpc("recommend_ids_similar_to_seeds", params: params)
                .execute()
                .value
            KuroPerf.end(perf, message: "ok \(rows.count)")
            return rows
        } catch {
            KuroPerf.end(perf, message: "error")
            return []
        }
    }

    private func fetchAnimeByIdsPreservingOrder(_ ids: [Int]) async -> [Anime]? {
        if ids.isEmpty { return [] }
        // Avoid hammering the API: fetch via cache first, then fill in missing ones concurrently.
        // Keep ordering identical to the RPC output.
        var resultsById: [Int: Anime] = [:]
        resultsById.reserveCapacity(ids.count)

        for id in ids {
            if let cached = animeDetailCache[id] {
                resultsById[id] = cached
            }
        }

        let missing = ids.filter { resultsById[$0] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: Anime?.self) { group in
                for id in missing {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return try? await self.fetchAnimeById(id)
                    }
                }
                for await item in group {
                    if let item { resultsById[item.id] = item }
                }
            }
        }

        let ordered = ids.compactMap { resultsById[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    private func fetchMangaByIdsPreservingOrder(_ ids: [Int]) async -> [Manga]? {
        if ids.isEmpty { return [] }
        var resultsById: [Int: Manga] = [:]
        resultsById.reserveCapacity(ids.count)

        for id in ids {
            if let cached = mangaDetailCache[id] {
                resultsById[id] = cached
            }
        }

        let missing = ids.filter { resultsById[$0] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: Manga?.self) { group in
                for id in missing {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return try? await self.fetchMangaById(id)
                    }
                }
                for await item in group {
                    if let item { resultsById[item.id] = item }
                }
            }
        }

        let ordered = ids.compactMap { resultsById[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    private func fetchSimilarAnimeFallbackByGenre(seed: Anime, limit: Int) async -> [Anime] {
        guard let primaryGenre = seed.genreList?.first, !primaryGenre.isEmpty else { return [] }
        do {
            let rows: [Anime] = try await client
                .from("anime")
                .select()
                .eq("is_adult", value: false)
                .contains("genres", value: [primaryGenre])
                .neq("id", value: seed.id)
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeAnimeForDiscovery(rows)
        } catch {
            return []
        }
    }

    private func fetchSimilarMangaFallbackByGenre(seed: Manga, limit: Int) async -> [Manga] {
        guard let primaryGenre = seed.genreList?.first, !primaryGenre.isEmpty else { return [] }
        do {
            let rows: [Manga] = try await client
                .from("manga")
                .select()
                .eq("is_adult", value: false)
                .contains("genres", value: [primaryGenre])
                .neq("id", value: seed.id)
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return sanitizeMangaForDiscovery(rows)
        } catch {
            return []
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
            #if DEBUG
            print("❌ anime tag facets fetch: \(error)")
            #endif
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
            #if DEBUG
            print("❌ manga tag facets fetch: \(error)")
            #endif
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
    func fetchCollectionItems(status: ListStatus? = nil) async {
        currentCollectionStatusFilter = status
        collectionFetchGeneration += 1
        let gen = collectionFetchGeneration

        collectionFetchInFlight?.cancel()
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchCollectionItemsImpl(status: status, generation: gen)
        }
        collectionFetchInFlight = t
        collectionFetchInFlightGeneration = gen
        await t.value
        if collectionFetchInFlightGeneration == gen { collectionFetchInFlight = nil }
    }

    func fetchCollectionItems() async {
        await fetchCollectionItems(status: nil)
    }

    // MARK: - Collection feed (anime + manga interleaved)
    func fetchCollectionFeed(status: ListStatus? = nil) async {
        currentCollectionStatusFilter = status
        collectionFeedFetchGeneration += 1
        let gen = collectionFeedFetchGeneration

        collectionFeedFetchInFlight?.cancel()
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchCollectionFeedImpl(status: status, generation: gen)
        }
        collectionFeedFetchInFlight = t
        collectionFeedFetchInFlightGeneration = gen
        await t.value
        if collectionFeedFetchInFlightGeneration == gen { collectionFeedFetchInFlight = nil }
    }

    private struct CollectionPagingSnapshot: Sendable {
        let anime: [AnimeCard]
        let manga: [MangaCard]
        let feed: [Media]
        let animeHasMore: Bool
        let mangaHasMore: Bool
        let feedHasMore: Bool
        let animeCursorUpdatedAt: Date?
        let animeCursorRowId: Int?
        let mangaCursorUpdatedAt: Date?
        let mangaCursorRowId: Int?
        let feedCursorUpdatedAt: Date?
        let feedCursorSourceRank: Int?
        let feedCursorRowId: Int?
    }

    private func _fetchCollectionItemsImpl(status: ListStatus?, generation: Int) async {
        guard let userId = await currentUserIdString() else { return }
        _ = userId // user_id is derived via JWT in the RPCs.
        isCollectionLoading = true
        collectionErrorMessage = nil
        defer { isCollectionLoading = false }

        let snapshot = CollectionPagingSnapshot(
            anime: collectionAnimeItems,
            manga: collectionMangaItems,
            feed: collectionFeedItems,
            animeHasMore: hasMoreCollectionAnime,
            mangaHasMore: hasMoreCollectionManga,
            feedHasMore: hasMoreCollectionFeed,
            animeCursorUpdatedAt: collectionAnimeCursorUpdatedAt,
            animeCursorRowId: collectionAnimeCursorRowId,
            mangaCursorUpdatedAt: collectionMangaCursorUpdatedAt,
            mangaCursorRowId: collectionMangaCursorRowId,
            feedCursorUpdatedAt: collectionFeedCursorUpdatedAt,
            feedCursorSourceRank: collectionFeedCursorSourceRank,
            feedCursorRowId: collectionFeedCursorRowId
        )

        do {
            resetCollectionPaging()

            let listTypeAnime = status.map { dbListType(for: $0, mediaType: "anime") }
            let listTypeManga = status.map { dbListType(for: $0, mediaType: "manga") }

            _ = try await fetchNextCollectionAnimePage(
                limit: 80,
                listType: listTypeAnime,
                generation: generation
            )
            _ = try await fetchNextCollectionMangaPage(
                limit: 80,
                listType: listTypeManga,
                generation: generation
            )
        } catch {
            // Avoid blanking the UI on transient failures (e.g. pull-to-refresh).
            // Keep the previous content and surface an error message.
            collectionErrorMessage = "Failed to load collection: \(error.localizedDescription)"
            #if DEBUG
            print("❌ collection fetch: \(error)")
            #endif
            restoreCollectionSnapshot(snapshot)
        }
    }

    private func _fetchCollectionFeedImpl(status: ListStatus?, generation: Int) async {
        guard (await currentUserIdString()) != nil else { return }
        isCollectionLoading = true
        collectionErrorMessage = nil
        defer { isCollectionLoading = false }

        let snapshot = CollectionPagingSnapshot(
            anime: collectionAnimeItems,
            manga: collectionMangaItems,
            feed: collectionFeedItems,
            animeHasMore: hasMoreCollectionAnime,
            mangaHasMore: hasMoreCollectionManga,
            feedHasMore: hasMoreCollectionFeed,
            animeCursorUpdatedAt: collectionAnimeCursorUpdatedAt,
            animeCursorRowId: collectionAnimeCursorRowId,
            mangaCursorUpdatedAt: collectionMangaCursorUpdatedAt,
            mangaCursorRowId: collectionMangaCursorRowId,
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
                generation: generation
            )
        } catch {
            collectionErrorMessage = "Failed to load collection: \(error.localizedDescription)"
            #if DEBUG
            print("❌ collection feed fetch: \(error)")
            #endif
            restoreCollectionSnapshot(snapshot)
        }
    }

    private func restoreCollectionSnapshot(_ snapshot: CollectionPagingSnapshot) {
        collectionAnimeItems = snapshot.anime
        collectionMangaItems = snapshot.manga
        collectionFeedItems = snapshot.feed
        hasMoreCollectionAnime = snapshot.animeHasMore
        hasMoreCollectionManga = snapshot.mangaHasMore
        hasMoreCollectionFeed = snapshot.feedHasMore
        collectionAnimeCursorUpdatedAt = snapshot.animeCursorUpdatedAt
        collectionAnimeCursorRowId = snapshot.animeCursorRowId
        collectionMangaCursorUpdatedAt = snapshot.mangaCursorUpdatedAt
        collectionMangaCursorRowId = snapshot.mangaCursorRowId
        collectionFeedCursorUpdatedAt = snapshot.feedCursorUpdatedAt
        collectionFeedCursorSourceRank = snapshot.feedCursorSourceRank
        collectionFeedCursorRowId = snapshot.feedCursorRowId
    }

    private func resetCollectionPaging() {
        collectionAnimeItems = []
        collectionMangaItems = []
        hasMoreCollectionAnime = true
        hasMoreCollectionManga = true
        isLoadingMoreCollectionAnime = false
        isLoadingMoreCollectionManga = false
        collectionAnimeCursorUpdatedAt = nil
        collectionAnimeCursorRowId = nil
        collectionMangaCursorUpdatedAt = nil
        collectionMangaCursorRowId = nil
    }

    private func resetCollectionFeedPaging() {
        collectionFeedItems = []
        hasMoreCollectionFeed = true
        isLoadingMoreCollectionFeed = false
        collectionFeedCursorUpdatedAt = nil
        collectionFeedCursorSourceRank = nil
        collectionFeedCursorRowId = nil
    }

    struct CollectionAnimeRow: Decodable, Sendable {
        let list_updated_at: Date
        let list_row_id: Int
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
        let season_year: Int?
        let start_date_year: Int?
        let average_score: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genres: [String]?
        let created_at: Date?

        var card: AnimeCard {
            AnimeCard(
                id: id,
                titleEnglish: title_english,
                titleRomaji: title_romaji,
                titleNative: title_native,
                coverImageLarge: cover_image_large,
                coverImageMedium: cover_image_medium,
                bannerImage: banner_image,
                format: format,
                status: status,
                episodeCount: episode_count,
                seasonYear: season_year,
                startDateYear: start_date_year,
                averageScore: average_score,
                popularity: popularity,
                trending: trending,
                favourites: favourites,
                genreList: genres,
                createdAt: created_at,
                rank: nil
            )
        }
    }

    struct CollectionMangaRow: Decodable, Sendable {
        let list_updated_at: Date
        let list_row_id: Int
        let id: Int
        let title_english: String?
        let title_romaji: String?
        let title_native: String?
        let cover_image_large: String?
        let cover_image_medium: String?
        let format: String?
        let status: String?
        let chapter_count: Int?
        let start_date_year: Int?
        let average_score: Int?
        let popularity: Int?
        let trending: Int?
        let favourites: Int?
        let genres: [String]?
        let created_at: Date?

        var card: MangaCard {
            MangaCard(
                id: id,
                titleEnglish: title_english,
                titleRomaji: title_romaji,
                titleNative: title_native,
                coverImageLarge: cover_image_large,
                coverImageMedium: cover_image_medium,
                format: format,
                status: status,
                chapterCount: chapter_count,
                startDateYear: start_date_year,
                averageScore: average_score,
                popularity: popularity,
                trending: trending,
                favourites: favourites,
                genreList: genres,
                createdAt: created_at,
                rank: nil
            )
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

    @discardableResult
    func fetchNextCollectionFeedPage(limit: Int = 90) async -> Bool {
        do {
            let listTypeAnime = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "anime") }
            let listTypeManga = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "manga") }
            return try await fetchNextCollectionFeedPage(
                limit: limit,
                listTypeAnime: listTypeAnime,
                listTypeManga: listTypeManga,
                generation: collectionFeedFetchGeneration
            )
        } catch {
            collectionErrorMessage = "Failed to load more: \(error.localizedDescription)"
            #if DEBUG
            print("❌ collection feed page: \(error)")
            #endif
            return false
        }
    }

    @discardableResult
    func fetchNextCollectionAnimePage(limit: Int = 80) async -> Bool {
        do {
            let listType = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "anime") }
            return try await fetchNextCollectionAnimePage(limit: limit, listType: listType, generation: collectionFetchGeneration)
        } catch {
            collectionErrorMessage = "Failed to load more: \(error.localizedDescription)"
            #if DEBUG
            print("❌ collection anime page: \(error)")
            #endif
            return false
        }
    }

    @discardableResult
    func fetchNextCollectionMangaPage(limit: Int = 80) async -> Bool {
        do {
            let listType = currentCollectionStatusFilter.map { dbListType(for: $0, mediaType: "manga") }
            return try await fetchNextCollectionMangaPage(limit: limit, listType: listType, generation: collectionFetchGeneration)
        } catch {
            collectionErrorMessage = "Failed to load more: \(error.localizedDescription)"
            #if DEBUG
            print("❌ collection manga page: \(error)")
            #endif
            return false
        }
    }

    private func fetchNextCollectionFeedPage(
        limit: Int,
        listTypeAnime: String?,
        listTypeManga: String?,
        generation: Int
    ) async throws -> Bool {
        guard hasMoreCollectionFeed, !isLoadingMoreCollectionFeed else { return false }
        isLoadingMoreCollectionFeed = true
        defer { isLoadingMoreCollectionFeed = false }
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
        let rows: [CollectionFeedRow] = try await client
            .rpc("collection_feed_page", params: params)
            .execute()
            .value
        if Task.isCancelled || generation != collectionFeedFetchGeneration {
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

    private func fetchNextCollectionAnimePage(limit: Int, listType: String?, generation: Int) async throws -> Bool {
        guard hasMoreCollectionAnime, !isLoadingMoreCollectionAnime else { return false }
        isLoadingMoreCollectionAnime = true
        defer { isLoadingMoreCollectionAnime = false }
        if Task.isCancelled { return false }

        let perf = KuroPerf.begin("rpc.collection_anime_page")
        let params = RPCCollectionAnimePageParams(
            p_limit: max(1, min(120, limit)),
            p_cursor_updated_at: collectionAnimeCursorUpdatedAt,
            p_cursor_row_id: collectionAnimeCursorRowId,
            p_list_type: listType
        )
        let rows: [CollectionAnimeRow] = try await client
            .rpc("collection_anime_page", params: params)
            .execute()
            .value
        if Task.isCancelled || generation != collectionFetchGeneration {
            KuroPerf.end(perf, message: "cancelled")
            return false
        }

        let cards = rows.map(\.card)
        collectionAnimeItems.append(contentsOf: cards)
        hasMoreCollectionAnime = rows.count == params.p_limit
        if let last = rows.last {
            collectionAnimeCursorUpdatedAt = last.list_updated_at
            collectionAnimeCursorRowId = last.list_row_id
        }
        KuroPerf.end(perf, message: "ok \(rows.count)")
        return true
    }

    private func fetchNextCollectionMangaPage(limit: Int, listType: String?, generation: Int) async throws -> Bool {
        guard hasMoreCollectionManga, !isLoadingMoreCollectionManga else { return false }
        isLoadingMoreCollectionManga = true
        defer { isLoadingMoreCollectionManga = false }
        if Task.isCancelled { return false }

        let perf = KuroPerf.begin("rpc.collection_manga_page")
        let params = RPCCollectionMangaPageParams(
            p_limit: max(1, min(120, limit)),
            p_cursor_updated_at: collectionMangaCursorUpdatedAt,
            p_cursor_row_id: collectionMangaCursorRowId,
            p_list_type: listType
        )
        let rows: [CollectionMangaRow] = try await client
            .rpc("collection_manga_page", params: params)
            .execute()
            .value
        if Task.isCancelled || generation != collectionFetchGeneration {
            KuroPerf.end(perf, message: "cancelled")
            return false
        }

        let cards = rows.map(\.card)
        collectionMangaItems.append(contentsOf: cards)
        hasMoreCollectionManga = rows.count == params.p_limit
        if let last = rows.last {
            collectionMangaCursorUpdatedAt = last.list_updated_at
            collectionMangaCursorRowId = last.list_row_id
        }
        KuroPerf.end(perf, message: "ok \(rows.count)")
        return true
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
                #if DEBUG
                print("⚠️ Unknown mediaType: \(mediaType)")
                #endif
                return
            }

            try await client
                .from(table)
                .upsert(payload, onConflict: onConflict)
                .execute()

            errorMessage = nil
            await fetchUserLists()
            await fetchCollectionItems(status: currentCollectionStatusFilter)
            await fetchCollectionFeed(status: currentCollectionStatusFilter)

            if mediaType.lowercased() == "anime" {
                await scheduleAiringNotifications(animeId: mediaId)
                await fetchUpcomingForUser(days: 7)
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            #if DEBUG
            print("❌ upsert list entry error: \(error)")
            #endif
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
            #if DEBUG
            print("❌ Failed to update progress: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    func fetchUserLists() async {
        if let t = userListsFetchInFlight {
            await t.value
            return
        }
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchUserListsImpl()
        }
        userListsFetchInFlight = t
        await t.value
        userListsFetchInFlight = nil
    }

    private func _fetchUserListsImpl() async {
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
            #if DEBUG
            print("✅ Fetched user lists: anime=\(mappedAnime.count), manga=\(mappedManga.count)")
            #endif
        } catch {
            errorMessage = "Failed to fetch lists: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error: \(error)")
            #endif
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
            await fetchCollectionItems(status: currentCollectionStatusFilter)
            await fetchCollectionFeed(status: currentCollectionStatusFilter)
            #if DEBUG
            print("✅ Removed from user list")
            #endif
            if mediaType.lowercased() == "anime" {
                cancelAiringNotifications(animeId: mediaId)
                // Remove countdown entry
                countdownByAnimeId[mediaId] = nil
                upcomingAirings.removeAll { $0.anime_id == mediaId }
            }
        } catch {
            errorMessage = "Failed to remove from list: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error: \(error)")
            #endif
        }
    }

    // MARK: - Upcoming Airings (user-scoped)
    func fetchUpcomingForUser(days: Int = 7) async {
        if let t = upcomingFetchInFlight {
            await t.value
            return
        }

        // Don't hammer the API when multiple screens mount or when realtime emits bursts.
        let now = Date()
        if days == lastUpcomingDays, let last = lastUpcomingFetchAt, now.timeIntervalSince(last) < 20 {
            return
        }
        guard upcomingBackoff.canAttempt(now: now) else { return }

        lastUpcomingDays = days
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchUpcomingForUserImpl(days: days)
        }
        upcomingFetchInFlight = t
        await t.value
        upcomingFetchInFlight = nil
    }

    private func _fetchUpcomingForUserImpl(days: Int) async {
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
            lastUpcomingFetchAt = Date()
            upcomingBackoff.recordSuccess()
        } catch {
            upcomingBackoff.recordFailure()
            #if DEBUG
            print("❌ Failed to fetch upcoming airings: \(error)")
            #endif
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
	            guard let strongSelf = self else { return }
	            Task { @MainActor in
	                strongSelf.updateCountdowns()
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
                #if DEBUG
                print("⚠️ Notification permission request failed: \(error)")
                #endif
                // Error logged in debug only
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
        do { try await UNUserNotificationCenter.current().add(request) } catch {
            #if DEBUG
            print("❌ Schedule notif failed: \(error)")
            #endif
            // Error logged in debug only
        }
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
            #if DEBUG
            print("⚠️ Could not schedule notifications: \(error)")
            #endif
            // Error logged in debug only
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
            #if DEBUG
            print("❌ Error fetching external links: \(error)")
            #endif
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
            #if DEBUG
            print("❌ fetch episodes next: \(error)")
            #endif
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
            #if DEBUG
            print("❌ fetch episodes page: \(error)")
            #endif
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
            #if DEBUG
            print("❌ fetch chapters next: \(error)")
            #endif
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
            #if DEBUG
            print("❌ fetch chapters page: \(error)")
            #endif
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
            #if DEBUG
            print("❌ Error fetching episode stream: \(error)")
            #endif
            // Error logged in debug only
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
            #if DEBUG
            print("❌ browse_manga_page rpc: \(error)")
            #endif
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
            #if DEBUG
            print("❌ browse anime fetch: \(error)")
            #endif
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
            #if DEBUG
            print("❌ browse manga fetch: \(error)")
            #endif
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
            #if DEBUG
            print("✅ Filtered by genre: \(genre)")
            #endif
        } catch {
            errorMessage = "Filter failed: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error: \(error)")
            #endif
        }
        
        isLoading = false
    }


    // MARK: - Concierge (Edge Functions)
    enum ConciergeScope: String, Sendable {
        case anime
        case manga
        case both
    }

    enum ConciergeGuardrailsError: LocalizedError, Sendable, Equatable {
        case rateLimited(retryAfterSeconds: Int?)

        var errorDescription: String? {
            switch self {
            case .rateLimited(let s):
                if let s, s > 0 { return "Too many requests. Try again in \(s)s." }
                return "Too many requests. Try again in a moment."
            }
        }
    }

    private func decodeRetryAfterSeconds(from data: Data) -> Int? {
        // Edge functions return: { "error": "Rate limited", "retry_after_s": 30 }
        guard !data.isEmpty else { return nil }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let n = obj["retry_after_s"] as? Int { return n }
            if let d = obj["retry_after_s"] as? Double { return Int(d.rounded()) }
            if let s = obj["retry_after_s"] as? String, let n = Int(s) { return n }
        }
        return nil
    }

    private func translateConciergeFunctionError(_ error: Error) -> Error {
        if case let FunctionsError.httpError(code, data) = error, code == 429 {
            return ConciergeGuardrailsError.rateLimited(retryAfterSeconds: decodeRetryAfterSeconds(from: data))
        }
        return error
    }

    struct ConciergeCandidate: Decodable, Sendable, Hashable {
        let media_type: String
        let media_id: Int
        let variant_type: String
        let title_raw: String
        let score: Double
        let year: Int?
        let format: String?
        let cover_image_medium: String?
    }

    struct ConciergeParseItemParsed: Decodable, Sendable {
        let mediaTypeHint: String?
        let status: String?
        let progressEpisodes: Int?
        let progressChapters: Int?
        let progressVolumes: Int?
        let seasonNumber: Int?
        let episodeInSeason: Int?
        let caughtUp: Bool?
        let lastEpisode: Bool?
        let completed: Bool?
        let yearMention: Int?
    }

    struct ConciergeExistingEntry: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let status: String
        let progress_episodes: Int?
        let progress_chapters: Int?
        let progress_volumes: Int?
        let rating: Int?
        let updated_at: String
    }

    struct ConciergeAmbiguity: Decodable, Sendable {
        let kind: String             // "status_unclear", "unit_unclear", "intent_unclear"
        let options: [String]?       // e.g. ["COMPLETED", "CURRENT"] or ["episode", "season", "chapter", "volume"]
        let suggested_question: String?
        let title_context: String?   // title the ambiguity relates to
        let number_context: String?  // the ambiguous number (for unit_unclear)
    }

    struct ConciergeParseItem: Decodable, Sendable, Identifiable {
        let raw: String
        let normalized: String
        let parsed: ConciergeParseItemParsed
        let candidates: [ConciergeCandidate]
        let candidateError: String?
        let existing_entry: ConciergeExistingEntry?
        let ambiguity: ConciergeAmbiguity?

        var id: String { raw + "|" + normalized }
    }

    struct ConciergeParseResponse: Decodable, Sendable {
        let success: Bool
        let userId: String?
        let items: [ConciergeParseItem]
    }

    /// Fire-and-forget edge function warmup — warms the Deno isolate without auth/rate-limit.
    func conciergeWarmup() async {
        do {
            let client = self.client
            _ = try await Task.detached(priority: .background) {
                let data = try JSONSerialization.data(withJSONObject: ["text": ""], options: [])
                let options = FunctionInvokeOptions(
                    method: .post,
                    query: [URLQueryItem(name: "warmup", value: "true")],
                    body: data
                )
                let _: [String: Bool] = try await client.functions.invoke("concierge-parse", options: options)
            }.value
        } catch {
            // Best-effort warmup — silently ignore failures
        }
    }

    func conciergeParse(text: String, scope: ConciergeScope = .both, limitPerItem: Int = 10, clarification: [String: String]? = nil) async throws -> ConciergeParseResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(3, min(15, limitPerItem))
        let user = await currentUserIdString() ?? "anon"
        let clarifyKey = clarification.map { $0.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "&") } ?? ""
        let key = "concierge_parse|\(user)|\(scope.rawValue)|\(lim)|\(normalized)|\(clarifyKey)"

        let now = Date()
        // Very short TTL: just enough to make back-to-back retries feel instant.
        if let cached = conciergeParseCache[key], now.timeIntervalSince(cached.storedAt) < 600 {
            return cached.value
        }
        if let task = conciergeParseInFlight[key] {
            return try await task.value
        }

        // Keep the request in a Task so callers can share in-flight work.
        // This runs on the main actor; the network call is async and should not block the UI thread.
        let client = self.client
        let clarify = clarification
        let task = Task<ConciergeParseResponse, Error>(priority: .userInitiated) {
            var payload: [String: Any] = [
                "text": text,
                "scope": scope.rawValue,
                "limitPerItem": lim,
            ]
            if let clarify {
                payload["clarification"] = clarify
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            return try await SupabaseService.withRetry {
                try await client.functions.invoke("concierge-parse", options: options)
            }
        }
        conciergeParseInFlight[key] = task
        defer { conciergeParseInFlight[key] = nil }
        do {
            let resp = try await task.value
            conciergeParseCache[key] = TimedCache(value: resp, storedAt: now)
            trimCache(&conciergeParseCache, maxEntries: 50)
            return resp
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    struct ConciergeApplyResponse: Decodable, Sendable {
        let success: Bool
        let sessionId: String?
        struct Applied: Decodable, Sendable {
            let mediaType: String
            let mediaId: Int
            let status: String
            let action: String?
        }
        struct Skipped: Decodable, Sendable {
            let mediaType: String
            let mediaId: Int
        }
        struct Conflict: Decodable, Sendable {
            let mediaType: String?
            let mediaId: Int?
            let error: String
        }
        struct ApplyError: Decodable, Sendable {
            let mediaType: String?
            let mediaId: Int?
            let error: String
        }
        let applied: [Applied]?
        let skipped: [Skipped]?
        let conflicts: [Conflict]?
        let errors: [ApplyError]?
    }

    func conciergeApply(items: [[String: Any]]) async throws -> ConciergeApplyResponse {
        do {
            let payload: [String: Any] = [
                "items": items,
            ]
            let client = self.client
            let task = Task<ConciergeApplyResponse, Error>(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client.functions.invoke("concierge-apply", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
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
        do {
            let payload: [String: Any] = [
                "sessionId": sessionId,
            ]
            let client = self.client
            let task = Task<ConciergeUndoResponse, Error>(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client.functions.invoke("concierge-undo", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    // MARK: - Concierge: Import from AniList (public lists)

    struct ConciergeAniListImportResponse: Decodable, Sendable {
        let success: Bool
        let source: String?
        let username: String?
        let itemCount: Int?
        let truncated: Bool?
        let text: String?
        let error: String?
    }

    func conciergeImportAniList(
        username: String,
        types: [String] = ["ANIME", "MANGA"],
        statuses: [String] = ["CURRENT", "COMPLETED", "PLANNING"],
        maxItems: Int = 200
    ) async throws -> ConciergeAniListImportResponse {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { throw NSError(domain: "Concierge", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing AniList username"]) }
        let cap = max(25, min(400, maxItems))

        do {
            let payload: [String: Any] = [
                "username": u,
                "types": types,
                "statuses": statuses,
                "maxItems": cap,
            ]
            let client = self.client
            let task = Task<ConciergeAniListImportResponse, Error>(priority: .userInitiated) {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                let options = FunctionInvokeOptions(method: .post, body: data)
                return try await client.functions.invoke("concierge-import-anilist", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }


	    struct ConciergeRecommendResponse: Decodable, Sendable {
	        let success: Bool
	        let locale: String?
	        let curatorNote: String?
	        let categories: [String]?
	        struct Mode: Decodable, Sendable, Identifiable {
	            let id: String
	            let title: String
            let confidence: Double?
            let reason: String?
        }
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
            let signals: [String]?
            let blurb: String?

            var id: String { "\(mediaType)|\(mediaId)" }
        }
	        struct Set: Decodable, Sendable, Identifiable {
	            let id: String
	            let title: String
	            let internalTitle: String?
	            let displayTitle: String?
	            let displaySubtitle: String?
	            let curatorNote: String?
	            let locale: String?
	            let modeId: String?
	            let confidence: Double?
	            let reason: String?
	            let items: [Item]?
	        }
        struct Assist: Decodable, Sendable {
            let ragUsed: Bool?
            let seedEntityId: String?

            enum CodingKeys: String, CodingKey {
                case ragUsed
                case seedEntityId
            }
        }
        let modes: [Mode]?
        let sets: [Set]?
        let items: [Item]?
        let assist: Assist?
        let message: String?
        let narrated: Bool?
        let error: String?
    }

    func conciergeRecommend(text: String, scope: ConciergeScope = .both, limit: Int = 8, narrate: Bool = true) async throws -> ConciergeRecommendResponse {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(3, min(20, limit))
        let user = await currentUserIdString() ?? "anon"
        let key = "concierge_recommend|\(user)|\(scope.rawValue)|\(lim)|\(narrate ? 1 : 0)|\(normalized)"

        let now = Date()
        if let cached = conciergeRecommendCache[key], now.timeIntervalSince(cached.storedAt) < 3600 {
            return cached.value
        }
        if let task = conciergeRecommendInFlight[key] {
            return try await task.value
        }

        // Keep the request in a Task so callers can share in-flight work.
        // This runs on the main actor; the network call is async and should not block the UI thread.
        let client = self.client
        let task = Task<ConciergeRecommendResponse, Error>(priority: .userInitiated) {
            let payload: [String: Any] = [
                "text": text,
                "scope": scope.rawValue,
                "limit": lim,
                "narrate": narrate,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let resp: ConciergeRecommendResponse = try await SupabaseService.withRetry {
                try await client.functions.invoke("concierge-recommend", options: options)
            }
            return resp
        }
        conciergeRecommendInFlight[key] = task
        defer { conciergeRecommendInFlight[key] = nil }
        do {
            let resp = try await task.value
            conciergeRecommendCache[key] = TimedCache(value: resp, storedAt: now)
            trimCache(&conciergeRecommendCache, maxEntries: 60)
            return resp
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    /// Best-effort feedback for server-side RAG retrieval.
    /// Never throws to callers by design; failures are debug-logged only.
    func conciergeRetrieveFeedback(
        query: String,
        locale: String,
        selectedEntityId: String?,
        accepted: Bool,
        rejectedReason: String? = nil
    ) async {
        do {
            var payload: [String: Any] = [
                "query": query,
                "locale": locale,
                "accepted": accepted,
            ]
            if let selectedEntityId, !selectedEntityId.isEmpty {
                payload["selected_entity_id"] = selectedEntityId
            }
            if let rejectedReason, !rejectedReason.isEmpty {
                payload["rejected_reason"] = rejectedReason
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let options = FunctionInvokeOptions(method: .post, body: data)
            let _: [String: Bool] = try await client.functions.invoke(
                "concierge-retrieve-feedback",
                options: options
            )
        } catch {
            #if DEBUG
            print("[SupabaseService] conciergeRetrieveFeedback failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Real-time Subscriptions  
    func subscribeToUpdates() {
        Task { [weak self] in
            guard let self else { return }
            await self.startRealtimeSubscriptionsIfNeeded()
        }
    }

    private func startRealtimeSubscriptionsIfNeeded() async {
        guard let userId = await currentUserIdString() else { return }
        if realtimeSubscribedUserId == userId, realtimeChannel != nil { return }

        await stopRealtimeSubscriptions()
        realtimeSubscribedUserId = userId

        await client.realtimeV2.connect()

        let channel = client.channel("kuro.user.\(userId)")
        realtimeChannel = channel

        let animeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "anime_user_lists",
            filter: .eq("user_id", value: userId)
        )
        let mangaStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "manga_user_lists",
            filter: .eq("user_id", value: userId)
        )

        realtimeListenTasks = [
            Task { [weak self] in
                guard let self else { return }
                for await _ in animeStream {
                    await MainActor.run { self.scheduleRealtimeRefresh() }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in mangaStream {
                    await MainActor.run { self.scheduleRealtimeRefresh() }
                }
            },
        ]

        do {
            _ = try await channel.subscribeWithError()
        } catch {
            #if DEBUG
            print("⚠️ realtime subscribe failed: \(error)")
            #endif
        }
    }

    @MainActor
    private func scheduleRealtimeRefresh() {
        // Coalesce bursts of changes (imports, batch edits) into a single refresh.
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.refreshAfterRealtimeEvent()
        }
    }

    private func refreshAfterRealtimeEvent() async {
        // These are all user-scoped; in-flight de-dupe + cancellation keep this cheap.
        await fetchUserLists()
        await fetchCollectionFeed(status: currentCollectionStatusFilter)
        await fetchCollectionItems(status: currentCollectionStatusFilter)
        await fetchUpcomingForUser(days: 7)
    }

    private func stopRealtimeSubscriptions() async {
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = nil
        for t in realtimeListenTasks { t.cancel() }
        realtimeListenTasks = []

        if let channel = realtimeChannel {
            await client.removeChannel(channel)
        }
        realtimeChannel = nil
        realtimeSubscribedUserId = nil
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

    // MARK: - Concierge: Library export helper

    struct ConciergeLibraryExportResult: Sendable {
        let text: String
        let exportedItemCount: Int
        let truncated: Bool
    }

    /// Build plain-text concierge payload from the user's current library list.
    /// Useful for one-tap import from within the app.
    func conciergeLibraryExportText(
        includeStatus: Set<ListStatus>? = nil,
        includeMediaTypes: Set<String> = ["anime", "manga"],
        maxItems: Int = 400
    ) async -> ConciergeLibraryExportResult? {
        if userLists.isEmpty {
            await fetchUserLists()
        }

        guard !userLists.isEmpty else { return nil }

        let allowedStatuses = includeStatus.map(Set.init) ?? Set(ListStatus.allCases)
        let allowedTypes = Set(includeMediaTypes.map { $0.lowercased() })

        let filtered = userLists.filter {
            allowedTypes.contains($0.mediaType.lowercased()) && allowedStatuses.contains($0.status)
        }

        guard !filtered.isEmpty else { return nil }

        let capped = Array(filtered.prefix(max(0, maxItems)))
        guard !capped.isEmpty else { return nil }

        // 1) Resolve titles for this snapshot.
        let lookup = await resolveLibraryTitles(for: capped)

        // 2) Keep list in server order (updatedAt desc from fetchUserLists).
        let lines: [String] = capped.compactMap { entry in
            guard let title = lookup[entry.mediaId] else { return nil }
            let suffix = conciergeLibrarySuffix(for: entry)
            return suffix.isEmpty ? title : "\(title) \(suffix)"
        }

        guard !lines.isEmpty else { return nil }
        return ConciergeLibraryExportResult(
            text: lines.joined(separator: "\n"),
            exportedItemCount: lines.count,
            truncated: filtered.count > capped.count
        )
    }

    private func conciergeLibrarySuffix(for entry: UserList) -> String {
        let isAnime = entry.mediaType.lowercased() == "anime"
        let progress = max(0, entry.progress)
        switch entry.status {
        case .completed:
            return "(completed)"
        case .dropped:
            return "(dropped)"
        case .paused:
            return "(paused)"
        case .planning:
            return "(planning)"
        case .repeating:
            return isAnime ? "(rewatching)" : "(re-reading)"
        case .current:
            if progress > 0 {
                return isAnime ? "(watching ep \(progress))" : "(reading ch \(progress))"
            }
            return isAnime ? "(watching)" : "(reading)"
        }
    }

    private func resolveLibraryTitles(for items: [UserList]) async -> [Int: String] {
        let animeIds = Set(items.filter { $0.mediaType.lowercased() == "anime" }.map(\.mediaId))
        let mangaIds = Set(items.filter { $0.mediaType.lowercased() == "manga" }.map(\.mediaId))

        var titlesById: [Int: String] = [:]

        for (table, ids) in [("anime", animeIds), ("manga", mangaIds)] as [(String, Set<Int>)] {
            let idList = Array(ids).sorted()
            guard !idList.isEmpty else { continue }

            struct MediaTitleRow: Decodable {
                let id: Int
                let titleEnglish: String?
                let titleRomaji: String?
                let titleNative: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case titleEnglish = "title_english"
                    case titleRomaji = "title_romaji"
                    case titleNative = "title_native"
                }
            }

            for start in stride(from: 0, through: max(0, idList.count), by: 200) {
                let end = min(start + 200, idList.count)
                guard start < end else { continue }
                let chunk = Array(idList[start..<end])

                do {
                    let rows: [MediaTitleRow] = try await client
                        .from(table)
                        .select("id,title_english,title_romaji,title_native")
                        .in("id", values: chunk)
                        .execute()
                        .value

                    for row in rows {
                        let title = row.titleEnglish?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? row.titleRomaji?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? row.titleNative?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? ""
                        if !title.isEmpty {
                            titlesById[row.id] = title
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[SupabaseService] Failed to resolve titles for \(table): \(error)")
                    #endif
                }

            }
        }

        // Use local detail cache as a fallback if table lookups failed.
        var localAnimeLookup: [Int: String] = [:]
        for item in animeItems {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title.lowercased() != "unknown" {
                localAnimeLookup[item.id] = title
            }
        }

        var localMangaLookup: [Int: String] = [:]
        for item in mangaItems {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title.lowercased() != "unknown" {
                localMangaLookup[item.id] = title
            }
        }

        for item in items {
            if titlesById[item.mediaId] == nil {
                let fallback = item.mediaType.lowercased() == "anime"
                    ? localAnimeLookup[item.mediaId]
                    : localMangaLookup[item.mediaId]
                if let fallback, !fallback.isEmpty {
                    titlesById[item.mediaId] = fallback
                }
            }
        }

        return titlesById
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

    func userListEntry(mediaType: String, mediaId: Int) -> UserList? {
        userListByTypeAndId[mediaType.lowercased()]?[mediaId]
    }

    func incrementProgress(mediaId: Int, mediaType: String) async {
        guard let entry = userListByTypeAndId[mediaType.lowercased()]?[mediaId] else { return }
        let newProgress = entry.progress + 1
        await upsertUserListEntry(
            mediaId: mediaId,
            mediaType: mediaType,
            status: entry.status,
            progress: newProgress,
            rating: entry.score,
            notes: entry.notes
        )
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
            #if DEBUG
            print("❌ Failed to update rating: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    // MARK: - Clubs

    struct ClubInfo: Decodable, Sendable {
        let id: String
        let name: String
        let description: String?
        let sharing_level: String
        let max_members: Int
        let is_archived: Bool
        let invite_code: String?
        let created_at: String
    }

    struct ClubMember: Decodable, Sendable {
        let user_id: String
        let display_name: String?
        let role: String
        let sharing_level: String
        let joined_at: String
    }

    struct ClubRailItem: Decodable, Sendable, Identifiable {
        let id: String
        let media_type: String
        let media_id: Int
        let sort_order: Int
        let note: String?
        let added_by: String
        let title_display: String
        let cover_image_medium: String?
        let average_score: Int?
        let year: Int?
        let format: String?
        let episode_count: Int?
        let chapter_count: Int?
        let my_status: String?
        let my_progress: Int?
        let my_rating: Int?
        let member_status_counts: [String: Int]?
        let member_statuses: [MemberItemStatus]?

        /// Total count for the relevant media type (episodes for anime, chapters for manga).
        var totalCount: Int? {
            media_type.uppercased() == "ANIME" ? episode_count : chapter_count
        }

        struct MemberItemStatus: Decodable, Sendable {
            let user_id: String
            let display_name: String?
            let status: String?
            let progress: Int?
            let updated_at: String?
        }
    }

    struct ClubRail: Decodable, Sendable, Identifiable {
        let id: String
        let title: String
        let description: String?
        let is_locked: Bool
        let sort_order: Int
        let created_by: String
        let items: [ClubRailItem]
    }

    struct ClubPollOption: Decodable, Sendable, Identifiable {
        let id: String
        let label: String
        let media_type: String?
        let media_id: Int?
        let sort_order: Int
        let vote_count: Int
    }

    struct ClubPoll: Decodable, Sendable, Identifiable {
        let id: String
        let question: String
        let is_closed: Bool
        let closes_at: String?
        let created_by: String
        let created_at: String
        let options: [ClubPollOption]
        let my_vote_option_id: String?
    }

    struct ClubBundle: Decodable, Sendable {
        let club: ClubInfo
        let members: [ClubMember]
        let my_role: String
        let my_sharing_level: String
        let rails: [ClubRail]
        let polls: [ClubPoll]
        let member_count: Int
    }

    struct CreateClubResponse: Decodable, Sendable {
        let club_id: String
        let invite_code: String
        let name: String
    }

    struct JoinClubResponse: Decodable, Sendable {
        let club_id: String
        let club_name: String
        let role: String
    }

    struct SimpleSuccessResponse: Decodable, Sendable {
        let success: Bool
    }

    struct AddRailItemResponse: Decodable, Sendable {
        let item_id: String
        let sort_order: Int
    }

    struct CreateRailResponse: Decodable, Sendable {
        let rail_id: String
        let title: String
    }

    struct CreatePollResponse: Decodable, Sendable {
        let poll_id: String
        let question: String
    }

    // Lightweight row for "My Clubs" list (fetched via direct table query)
    struct ClubListRow: Decodable, Sendable, Identifiable {
        let id: String
        let name: String
        let sharing_level: String
        let is_archived: Bool
        let created_at: String
    }

    // Club bundle cache (5 min TTL per spec)
    private var clubBundleCache: [String: TimedCache<ClubBundle>] = [:]
    private var clubBundleInFlight: [String: Task<ClubBundle, Error>] = [:]
    private let rememberedClubIdKey = "com.kuro.rememberedAddToClubId"
    var myClubs: [ClubListRow] = []

    func rememberedAddToClubId() -> String? {
        UserDefaults.standard.string(forKey: rememberedClubIdKey)
    }

    func setRememberedAddToClubId(_ clubId: String?) {
        if let clubId, !clubId.isEmpty {
            UserDefaults.standard.set(clubId, forKey: rememberedClubIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: rememberedClubIdKey)
        }
    }

    func fetchMyClubs() async {
        guard let userId = await currentUserIdString() else { return }
        do {
            struct MembershipRow: Decodable { let club_id: String }
            let memberships: [MembershipRow] = try await client
                .from("club_members")
                .select("club_id")
                .eq("user_id", value: userId)
                .execute()
                .value

            let clubIds = memberships.map(\.club_id)
            guard !clubIds.isEmpty else {
                myClubs = []
                return
            }

            // Fetch the club rows for these IDs
            let clubs: [ClubListRow] = try await client
                .from("clubs")
                .select("id, name, sharing_level, is_archived, created_at")
                .in("id", values: clubIds)
                .eq("is_archived", value: false)
                .order("created_at", ascending: false)
                .execute()
                .value

            myClubs = clubs
        } catch {
            #if DEBUG
            print("❌ fetchMyClubs: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    func createClub(name: String, description: String? = nil, sharingLevel: String = "status") async throws -> CreateClubResponse {
        let params = RPCCreateClubParams(p_name: name, p_description: description, p_sharing_level: sharingLevel)
        let resp: CreateClubResponse = try await client
            .rpc("create_club", params: params)
            .execute()
            .value
        await fetchMyClubs()
        return resp
    }

    func joinClub(inviteCode: String) async throws -> JoinClubResponse {
        let params = RPCJoinClubParams(p_invite_code: inviteCode)
        let resp: JoinClubResponse = try await client
            .rpc("join_club", params: params)
            .execute()
            .value
        await fetchMyClubs()
        return resp
    }

    func leaveClub(clubId: String) async throws {
        let params = RPCClubIdParams(p_club_id: clubId)
        let _: SimpleSuccessResponse = try await client
            .rpc("leave_club", params: params)
            .execute()
            .value
        clubBundleCache.removeValue(forKey: clubId)
        await fetchMyClubs()
    }

    func fetchClubBundle(clubId: String, forceRefresh: Bool = false) async throws -> ClubBundle {
        let now = Date()
        if !forceRefresh, let cached = clubBundleCache[clubId], now.timeIntervalSince(cached.storedAt) < 300 {
            return cached.value
        }
        if let task = clubBundleInFlight[clubId] {
            return try await task.value
        }

        let client = self.client
        let cid = clubId
        let task = Task<ClubBundle, Error>(priority: .userInitiated) {
            let params = RPCClubIdParams(p_club_id: cid)
            let bundle: ClubBundle = try await client
                .rpc("fetch_club_bundle", params: params)
                .execute()
                .value
            return bundle
        }
        clubBundleInFlight[clubId] = task
        defer { clubBundleInFlight[clubId] = nil }
        let bundle = try await task.value
        clubBundleCache[clubId] = TimedCache(value: bundle, storedAt: now)
        return bundle
    }

    func refreshClubBundle(clubId: String) async throws -> ClubBundle {
        try await fetchClubBundle(clubId: clubId, forceRefresh: true)
    }

    func addRailItem(railId: String, mediaType: String, mediaId: Int, note: String? = nil) async throws -> AddRailItemResponse {
        let params = RPCAddRailItemParams(p_rail_id: railId, p_media_type: mediaType, p_media_id: mediaId, p_note: note)
        return try await client
            .rpc("add_club_rail_item", params: params)
            .execute()
            .value
    }

    func castVote(pollId: String, optionId: String) async throws {
        let params = RPCCastVoteParams(p_poll_id: pollId, p_option_id: optionId)
        let _: SimpleSuccessResponse = try await client
            .rpc("cast_club_vote", params: params)
            .execute()
            .value
    }

    func createClubRail(clubId: String, title: String, description: String? = nil) async throws -> CreateRailResponse {
        let params = RPCCreateClubRailParams(p_club_id: clubId, p_title: title, p_description: description)
        let resp: CreateRailResponse = try await client
            .rpc("create_club_rail", params: params)
            .execute()
            .value
        clubBundleCache.removeValue(forKey: clubId)
        return resp
    }

    func createClubPoll(clubId: String, question: String, options: [String]) async throws -> CreatePollResponse {
        let params = RPCCreateClubPollParams(p_club_id: clubId, p_question: question, p_options: options)
        let resp: CreatePollResponse = try await client
            .rpc("create_club_poll", params: params)
            .execute()
            .value
        clubBundleCache.removeValue(forKey: clubId)
        return resp
    }

    struct ToggleReactionResponse: Decodable, Sendable {
        let action: String // "added" | "removed"
        let emoji: String
    }

    func toggleReaction(railItemId: String, emoji: String) async throws -> ToggleReactionResponse {
        let params = RPCToggleReactionParams(p_rail_item_id: railItemId, p_emoji: emoji)
        return try await client
            .rpc("toggle_club_reaction", params: params)
            .execute()
            .value
    }

    func clubMemberCount(clubId: String) -> Int {
        clubBundleCache[clubId]?.value.member_count ?? 0
    }

    struct ClubMediaActivityMatch: Sendable {
        let rail: ClubRail
        let item: ClubRailItem
    }

    struct ClubMediaActivity: Sendable {
        let club: ClubInfo
        let memberCount: Int
        let sharingLevel: String
        let members: [ClubMember]
        let matchingItems: [ClubMediaActivityMatch]
    }

    /// Scans cached club bundles to find clubs that have this media item in a rail.
    func clubActivityForMedia(mediaId: Int, mediaType: String) -> [ClubMediaActivity] {
        let mt = mediaType.uppercased()
        var results: [ClubMediaActivity] = []
        for (_, cached) in clubBundleCache {
            let bundle = cached.value
            var matches: [ClubMediaActivityMatch] = []
            for rail in bundle.rails {
                for item in rail.items {
                    if item.media_id == mediaId && item.media_type.uppercased() == mt {
                        matches.append(ClubMediaActivityMatch(rail: rail, item: item))
                    }
                }
            }
            if !matches.isEmpty {
                results.append(ClubMediaActivity(
                    club: bundle.club,
                    memberCount: bundle.member_count,
                    sharingLevel: bundle.club.sharing_level,
                    members: bundle.members,
                    matchingItems: matches
                ))
            }
        }
        return results
    }
}

#else
// Fallback mock service when the Supabase SDK isn't available.
// Kept minimal: no model-type references (Anime, Manga, UserList,
// Episode, ListStatus) so this block compiles standalone.
@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()

    let fmService = AppleFMService()

    // Observable state used by views
    var isLoading = false
    var errorMessage: String?

    init() {
        #if DEBUG
        print("[Mock] Supabase SDK not found. Running with mock SupabaseService.")
        #endif
    }

    // Auth
    func signInAnonymously() async throws {}

    // Data loading no-ops
    func fetchAnime(limit: Int = 50) async {
        isLoading = true
        isLoading = false
    }

    func fetchManga(limit: Int = 50) async {
        isLoading = true
        isLoading = false
    }

    func searchContent(query: String) async {
        isLoading = true
        isLoading = false
    }

    func fetchUserLists() async {}

    func filterByGenre(_ genre: String) async {
        isLoading = true
        isLoading = false
    }

    func subscribeToUpdates() {}

    func isInCollection(_ animeId: Int) -> Bool { false }
    func isInCollection(mediaId: Int, mediaType: String) -> Bool { false }
    func isFavorited(_ animeId: Int) -> Bool { false }
    func toggleInCollection(_ animeId: Int) {}
    func toggleInCollection(mediaId: Int, mediaType: String) {}
    func toggleFavorite(for animeId: Int) {}
    func userMediaIds(mediaType: String, status: ListStatus? = nil) -> Set<Int> { [] }
}
#endif
