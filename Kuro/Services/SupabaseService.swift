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

    // Supabase client (nil only when config is missing)
    let client: SupabaseClient!
    // Surface configuration errors to UI instead of crashing
    var configError: String? = nil
    // Realtime (user-scoped) subscriptions
    private var realtimeChannel: RealtimeChannelV2? = nil
    private var realtimeListenTasks: [Task<Void, Never>] = []
    private var realtimeDebounceTask: Task<Void, Never>? = nil
    private var realtimeSubscribedUserId: String? = nil

    // Auth state
    var isAuthBootstrapping: Bool = true
    var isAuthenticated: Bool = false
    var authErrorMessage: String? = nil
    private var authStateTask: Task<Void, Never>?
    // Lightweight identity for UI (header menus, etc.)
    var currentUserEmail: String? = nil
    // Used for local-only UI labeling (e.g. Clubs member list "You").
    var currentUserId: String? = nil

    var currentUserInitial: String {
        let c = currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).first
        return c.map { String($0).uppercased() } ?? "M"
    }

    nonisolated static func userFacingAuthErrorMessage(from error: Error) -> String {
        #if DEBUG
        let chain = authErrorChain(from: error)
            .map { "\($0.domain)(\($0.code)): \($0.localizedDescription)" }
            .joined(separator: " -> ")
        print("[Auth] error chain: \(chain)")
        #endif

        if let transportMessage = transportAuthErrorMessage(from: error) {
            return transportMessage
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("invalid login credentials") {
            return "Incorrect email or password. Please try again."
        } else if lower.contains("user already registered") {
            return "An account with this email already exists. Try signing in instead."
        } else if lower.contains("email not confirmed") {
            return "Please check your email to verify your account."
        } else if lower.contains("password should be at least") {
            return "Password must be at least 6 characters."
        }
        return "Something went wrong. Please try again."
    }

    nonisolated private static func transportAuthErrorMessage(from error: Error) -> String? {
        for candidate in authErrorChain(from: error) {
            guard candidate.domain == NSURLErrorDomain else { continue }
            let code = URLError.Code(rawValue: candidate.code)
            switch code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return "No internet connection. Check your connection and try again."
            case .networkConnectionLost:
                return "The network connection was lost. Please try again."
            case .timedOut:
                return "The request timed out. Please try again."
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .secureConnectionFailed, .cannotLoadFromNetwork,
                 .appTransportSecurityRequiresSecureConnection, .badServerResponse:
                return "Can't reach the server right now. Please try again."
            default:
                continue
            }
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("internet connection appears to be offline") ||
            lower.contains("not connected to the internet") {
            return "No internet connection. Check your connection and try again."
        } else if lower.contains("network connection was lost") {
            return "The network connection was lost. Please try again."
        } else if lower.contains("timed out") {
            return "The request timed out. Please try again."
        } else if lower.contains("cannot connect to the server") ||
                    lower.contains("could not connect to the server") ||
                    lower.contains("cannot connect to host") {
            return "Can't reach the server right now. Please try again."
        }
        return nil
    }

    nonisolated private static func authErrorChain(from error: Error) -> [NSError] {
        var queue: [NSError] = [error as NSError]
        var seen = Set<String>()
        var chain: [NSError] = []

        while let current = queue.first {
            queue.removeFirst()
            let key = "\(current.domain)#\(current.code)#\(current.localizedDescription)"
            if !seen.insert(key).inserted {
                continue
            }
            chain.append(current)
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                queue.append(underlying)
            } else if let underlying = current.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying as NSError)
            }
        }

        return chain
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
    var transientBannerMessage: String? = nil
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    // Detail caches: cards/grids only carry minimal fields; we fetch full details by id on demand.
    var animeDetailCache: [Int: Anime] = [:]
    var mangaDetailCache: [Int: Manga] = [:]

    // Entity inline caches (keyed by media ID, cap 100 each)
    var animeCharactersCache: [Int: [(character: Character, role: String)]] = [:]
    var animeStaffCache: [Int: [(staff: Staff, role: String)]] = [:]
    var animeStudiosCache: [Int: [Studio]] = [:]
    var mangaCharactersCache: [Int: [(character: Character, role: String)]] = [:]
    var mangaAuthorsCache: [Int: [(author: Author, role: String)]] = [:]

    // Entity sheet caches (keyed by entity ID, TTL 120s)
    var studioWorksCache: [String: TimedCache<[Media]>] = [:]
    var staffWorksCache: [String: TimedCache<[(media: Media, role: String)]>] = [:]
    var authorWorksCache: [String: TimedCache<[(media: Media, role: String)]>] = [:]
    var characterWorksCache: [String: TimedCache<[Media]>] = [:]
    var mediaLadderCache: [String: TimedCache<MediaLadderResponse>] = [:]
    var mediaLadderRefreshEnqueueCooldown: [String: Date] = [:]
    // De-dupe frequently called network fetches so multiple screens mounting doesn't fan-out.
    var userListsFetchInFlight: Task<Void, Never>? = nil
    var collectionFetchInFlight: Task<Void, Never>? = nil
    var collectionFetchGeneration: Int = 0
    var collectionFetchInFlightGeneration: Int = 0
    var collectionFeedFetchInFlight: Task<Void, Never>? = nil
    var collectionFeedFetchGeneration: Int = 0
    var collectionFeedFetchInFlightGeneration: Int = 0
    var upcomingFetchInFlight: Task<Void, Never>? = nil

    // Lightweight response caches (avoid refetching the same rails/recs when a view reappears).
    struct TimedCache<T>: Sendable {
        let value: T
        let storedAt: Date
    }

    private var discoverBundleCache: [String: TimedCache<DiscoverBundle>] = [:]
    private var discoverBundleInFlight: [String: Task<DiscoverBundle?, Never>] = [:]

    private var conciergeRecommendCache: [String: TimedCache<ConciergeRecommendResponse>] = [:]
    private var conciergeRecommendInFlight: [String: Task<ConciergeRecommendResponse, Error>] = [:]

    private var conciergeParseCache: [String: TimedCache<ConciergeParseResponse>] = [:]
    private var conciergeParseInFlight: [String: Task<ConciergeParseResponse, Error>] = [:]

    func trimCache<T>(_ cache: inout [String: TimedCache<T>], maxEntries: Int) {
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
        throw lastError ?? URLError(.unknown)
    }

    struct BackoffState: Sendable {
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

    var upcomingBackoff = BackoffState()
    var lastUpcomingFetchAt: Date? = nil
    var lastUpcomingDays: Int = 7

    // Collection pagination state (keyset by list updated_at + list row id).
    var hasMoreCollectionAnime: Bool = true
    var hasMoreCollectionManga: Bool = true
    var isLoadingMoreCollectionAnime: Bool = false
    var isLoadingMoreCollectionManga: Bool = false
    var collectionAnimeCursorUpdatedAt: Date? = nil
    var collectionAnimeCursorRowId: Int? = nil
    var collectionMangaCursorUpdatedAt: Date? = nil
    var collectionMangaCursorRowId: Int? = nil

    // Collection feed pagination state (keyset by updated_at + source_rank + list row id).
    var hasMoreCollectionFeed: Bool = true
    var isLoadingMoreCollectionFeed: Bool = false
    var collectionFeedCursorUpdatedAt: Date? = nil
    var collectionFeedCursorSourceRank: Int? = nil
    var collectionFeedCursorRowId: Int? = nil

    var currentCollectionStatusFilter: ListStatus? = nil

    // User list derived caches
    var collectionAnimeIds: Set<Int> = []
    var collectionMangaIds: Set<Int> = []
    var userListByTypeAndId: [String: [Int: UserList]] = [:]
    var userIdsByTypeAndStatus: [String: [ListStatus: Set<Int>]] = [:]
    var togglingMediaKeys: Set<String> = []

    // Clubs and social state
    var clubBundleCache: [String: TimedCache<ClubBundle>] = [:]
    var clubBundleInFlight: [String: Task<ClubBundle, Error>] = [:]
    let rememberedClubIdKey = "com.kuro.rememberedAddToClubId"
    var myClubs: [ClubListRow] = []
    var hasUnseenClubActivity: Bool = false
    var friendTrackingCounts: [String: Int] = [:]
    var friendCountPrefetchTask: Task<Void, Never>?

    // Club realtime state
    var clubRealtimeChannel: RealtimeChannelV2?
    var clubRealtimeListenTasks: [Task<Void, Never>] = []
    var clubRealtimeDebounceTask: Task<Void, Never>?
    var clubRealtimeSubscribedId: String?
    var clubOnlineMemberCount: Int = 0
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
    var countdownTimer: Timer?
    var isLoading = false
    var errorMessage: String?
    private var transientBannerDismissTask: Task<Void, Never>? = nil

    func showTransientBanner(_ message: String, duration: Double = 2.4) {
        transientBannerDismissTask?.cancel()
        transientBannerMessage = message
        transientBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if transientBannerMessage == message {
                transientBannerMessage = nil
            }
        }
    }

    // TODO: remove when streaming_availability_v1 reaches 100% — replaced by streaming_services registry
    let animeProviderRanking: [String] = [
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

    // Strict legal provider allowlist for watch links.
    let animeLegalProviderAllowlist: [String] = [
        "crunchyroll",
        "netflix",
        "hidive",
        "disney",
        "amazon",
        "prime video",
        "hulu",
        "youtube",
        "apple tv",
        "apple",
        "max"
    ]

    let mangaProviderRanking: [String] = [
        "manga plus",
        "mangaplus",
        "viz",
        "viz media",
        "bookwalker",
        "global bookwalker",
        "comixology",
        "kindle",
        "kobo",
        "j-novel club",
        "manga up",
        "kodansha",
        "yen press",
        "azuki"
    ]

    // Strict legal provider allowlist for read/buy links.
    let mangaLegalProviderAllowlist: [String] = [
        "manga plus",
        "mangaplus",
        "viz",
        "viz media",
        "bookwalker",
        "global bookwalker",
        "comixology",
        "kindle",
        "kobo",
        "kodansha",
        "yen press",
        "azuki",
        "j-novel club",
        "manga up",
        "google play books",
        "apple books"
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

    func sanitizeAnimeForDiscovery(_ items: [Anime]) -> [Anime] {
        sanitizeAnimeForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    func sanitizeAnimeForDiscovery(_ items: [Anime], policy: DiscoveryPolicy) -> [Anime] {
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

    func sanitizeMangaForDiscovery(_ items: [Manga]) -> [Manga] {
        sanitizeMangaForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    func sanitizeMangaForDiscovery(_ items: [Manga], policy: DiscoveryPolicy) -> [Manga] {
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
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else {
            client = nil
            configError = "Missing SUPABASE_URL or SUPABASE_ANON_KEY in configuration"
            isAuthBootstrapping = false
            return
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

    private func missingConfigError() -> NSError {
        NSError(
            domain: "KuroConfig",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: configError ?? "Missing Supabase configuration."]
        )
    }
    
    // MARK: - Authentication
    func restoreSession() async {
        defer { isAuthBootstrapping = false }
        guard let client else {
            isAuthenticated = false
            authErrorMessage = configError
            currentUserId = nil
            currentUserEmail = nil
            analytics.setUserId(nil)
            return
        }

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

        // Listen for auth state changes (token refresh failure, server-side revocation, etc.)
        startAuthStateListener()
    }

    private func startAuthStateListener() {
        guard let client else { return }
        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                switch event {
                case .signedIn:
                    if !isAuthenticated, let session {
                        isAuthenticated = true
                        currentUserEmail = session.user.email
                        currentUserId = session.user.id.uuidString
                        analytics.setUserId(currentUserId)
                    }
                case .signedOut:
                    if isAuthenticated {
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
                case .tokenRefreshed:
                    if let session {
                        currentUserEmail = session.user.email
                    }
                default:
                    break
                }
            }
        }
    }

    /// Lightweight session check on foreground — if the token expired while backgrounded,
    /// catch it early rather than waiting for the next API call to fail.
    func refreshSessionIfNeeded() async {
        guard let client else {
            authErrorMessage = configError
            return
        }
        do {
            _ = try await client.auth.session
        } catch {
            #if DEBUG
            print("⚠️ Session refresh failed on foreground: \(error.localizedDescription)")
            #endif
            // The authStateChanges listener will handle .signedOut if the session is truly gone.
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
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
            authErrorMessage = Self.userFacingAuthErrorMessage(from: error)
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
            throw error
        }
    }

    /// Auth callback redirect URL — custom scheme so Supabase redirects straight into the app (no intermediate webpage).
    static let authCallbackURL = URL(string: "kuro://auth/callback")!

    func signUpWithEmail(email: String, password: String) async throws {
        authErrorMessage = nil
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
        do {
            _ = try await client.auth.signUp(email: email, password: password)
            // With email confirmation disabled, the session is immediately available.
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
            authErrorMessage = Self.userFacingAuthErrorMessage(from: error)
            throw error
        }
    }

    /// Lightweight email existence check for inline sign-up validation.
    func checkEmailExists(email: String) async -> Bool {
        guard let client else {
            authErrorMessage = configError
            return false
        }
        do {
            let result: Bool = try await client
                .rpc("check_email_exists", params: ["p_email": email])
                .execute()
                .value
            return result
        } catch {
            #if DEBUG
            print("[Auth] checkEmailExists error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {
        authErrorMessage = nil
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
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
                _ = try? await client.auth.update(
                    user: .init(data: ["full_name": .string(fullName)])
                )
            }

            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = Self.userFacingAuthErrorMessage(from: error)
            isAuthenticated = false
            currentUserId = nil
            analytics.setUserId(nil)
            throw error
        }
    }

    func resetPassword(email: String) async throws {
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.authCallbackURL)
    }

    /// Handle auth callback deep link — set session from tokens received via email verification redirect.
    func handleAuthCallback(accessToken: String, refreshToken: String) async {
        guard let client else {
            authErrorMessage = configError
            return
        }
        do {
            try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
            let session = try await client.auth.session
            isAuthenticated = true
            currentUserEmail = session.user.email
            currentUserId = session.user.id.uuidString
            analytics.setUserId(currentUserId)
            await ensureProfileRow()
            await bootstrapAfterAuth()
        } catch {
            authErrorMessage = "Verification failed. Please request a new link."
            #if DEBUG
            print("handleAuthCallback failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// GDPR-compliant account deletion. Calls the `delete-account` Edge Function
    /// which cascades through all user data tables, removes storage objects,
    /// then deletes the auth.users row.
    var isAppleUser: Bool {
        get async {
            guard let client else { return false }
            guard let user = try? await client.auth.user() else { return false }
            return user.identities?.contains(where: { $0.provider == "apple" }) ?? false
        }
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        guard let client else {
            authErrorMessage = configError
            throw missingConfigError()
        }
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
        guard let client else {
            authErrorMessage = configError
            return
        }
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
        togglingMediaKeys.removeAll()
        // Entity caches
        animeCharactersCache.removeAll()
        animeStaffCache.removeAll()
        animeStudiosCache.removeAll()
        mangaCharactersCache.removeAll()
        mangaAuthorsCache.removeAll()
        studioWorksCache.removeAll()
        staffWorksCache.removeAll()
        authorWorksCache.removeAll()
        characterWorksCache.removeAll()
        mediaLadderCache.removeAll()
        mediaLadderRefreshEnqueueCooldown.removeAll()
    }

    /// Shed non-essential entity caches under memory pressure without
    /// touching user-facing state (lists, collection, auth).
    func trimCachesForMemoryPressure() {
        animeCharactersCache.removeAll()
        animeStaffCache.removeAll()
        animeStudiosCache.removeAll()
        mangaCharactersCache.removeAll()
        mangaAuthorsCache.removeAll()
        studioWorksCache.removeAll()
        staffWorksCache.removeAll()
        authorWorksCache.removeAll()
        characterWorksCache.removeAll()
        mediaLadderCache.removeAll()
        mediaLadderRefreshEnqueueCooldown.removeAll()
        discoverBundleCache.removeAll()
        conciergeRecommendCache.removeAll()
        conciergeParseCache.removeAll()
        animeDetailCache.removeAll()
        mangaDetailCache.removeAll()
        Task { await ImagePipeline.shared.clearMemoryCache() }
        #if DEBUG
        print("[MemoryPressure] Trimmed entity + image caches")
        #endif
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
        if let client {
            Task { await FeatureFlags.shared.refresh(client: client, userId: currentUserId) }
        }

        // Streaming availability: load registry + user services (non-blocking)
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
            Task {
                await fetchStreamingServiceRegistry()
                await fetchUserStreamingServices()
            }
        }
    }

    func currentUserIdString() async -> String? {
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
        let diskFallback: Anime? = await KuroDiskDetailCache.read(kind: .anime, id: animeId, as: Anime.self)
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
            if let diskFallback {
                #if DEBUG
                print("⚠️ anime_by_id network error, using disk fallback: \(error)")
                #endif
                animeDetailCache[animeId] = diskFallback
                KuroPerf.end(perf, message: "disk_fallback")
                return diskFallback
            }
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    func fetchMangaById(_ mangaId: Int) async throws -> Manga? {
        if let cached = mangaDetailCache[mangaId] { return cached }
        let diskFallback: Manga? = await KuroDiskDetailCache.read(kind: .manga, id: mangaId, as: Manga.self)
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
            if let diskFallback {
                #if DEBUG
                print("⚠️ manga_by_id network error, using disk fallback: \(error)")
                #endif
                mangaDetailCache[mangaId] = diskFallback
                KuroPerf.end(perf, message: "disk_fallback")
                return diskFallback
            }
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

    // MARK: - Similar title recommendations

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
    // Extracted to SupabaseService+UserLists.swift

    // MARK: - Collection (server-driven)
    // Extracted to SupabaseService+Collection.swift

    // MARK: - User List mutation + sync helpers
    // Extracted to SupabaseService+UserLists.swift

// MARK: - Browse (server-driven paging + filters)
    // Extracted to SupabaseService+Browse.swift


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

    func decodeRetryAfterSeconds(from data: Data) -> Int? {
        // Edge functions return: { "error": "Rate limited", "retry_after_s": 30 }
        guard !data.isEmpty else { return nil }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let n = obj["retry_after_s"] as? Int { return n }
            if let d = obj["retry_after_s"] as? Double { return Int(d.rounded()) }
            if let s = obj["retry_after_s"] as? String, let n = Int(s) { return n }
        }
        return nil
    }

    func translateConciergeFunctionError(_ error: Error) -> Error {
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
        let rating: Double?
        let progressTotal: Int?
        let progressUnit: String?
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
                let _: [String: Bool] = try await client!.functions.invoke("concierge-parse", options: options)
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
            return try await SupabaseService.withRetry { [client] in
                try await client!.functions.invoke("concierge-parse", options: options)
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
                return try await client!.functions.invoke("concierge-apply", options: options)
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
                return try await client!.functions.invoke("concierge-undo", options: options)
            }
            return try await task.value
        } catch {
            throw translateConciergeFunctionError(error)
        }
    }

    // MARK: - Concierge: AniList import
    // Extracted to SupabaseService+Concierge.swift


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
            let resp: ConciergeRecommendResponse = try await SupabaseService.withRetry { [client] in
                try await client!.functions.invoke("concierge-recommend", options: options)
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
    // Extracted to SupabaseService+UserLists.swift

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
            notes: entry.notes,
            verdict: entry.verdict
        )
    }

    func isFavorited(_ animeId: Int) -> Bool {
        // Check if anime has high score (favorited)
        return userListByTypeAndId["anime"]?[animeId]?.score ?? 0 >= 90
    }

    func toggleInCollection(mediaId: Int, mediaType: String) {
        let type = mediaType.lowercased()
        let key = "\(type)-\(mediaId)"
        guard !togglingMediaKeys.contains(key) else { return }
        togglingMediaKeys.insert(key)

        let wasInCollection = isInCollection(mediaId: mediaId, mediaType: type)

        // Optimistic: flip local set immediately so UI reflects the change
        if type == "anime" {
            if wasInCollection { collectionAnimeIds.remove(mediaId) } else { collectionAnimeIds.insert(mediaId) }
        } else {
            if wasInCollection { collectionMangaIds.remove(mediaId) } else { collectionMangaIds.insert(mediaId) }
        }

        Task {
            if wasInCollection {
                let success = await removeFromList(mediaId: mediaId, mediaType: type)
                if !success {
                    // Rollback: re-insert the ID
                    if type == "anime" { collectionAnimeIds.insert(mediaId) } else { collectionMangaIds.insert(mediaId) }
                    showTransientBanner("Couldn't update list. Try again.")
                } else {
                    showTransientBanner("Removed from collection")
                }
            } else {
                let success = await addToList(mediaId: mediaId, mediaType: type, status: .planning)
                if !success {
                    // Rollback: remove the optimistically inserted ID
                    if type == "anime" { collectionAnimeIds.remove(mediaId) } else { collectionMangaIds.remove(mediaId) }
                    showTransientBanner("Couldn't update list. Try again.")
                } else {
                    showTransientBanner("Added to collection")
                }
            }
            togglingMediaKeys.remove(key)
        }
    }

    func toggleInCollection(_ animeId: Int) {
        toggleInCollection(mediaId: animeId, mediaType: "anime")
    }

    func toggleFavorite(for animeId: Int) {
        let key = "fav-\(animeId)"
        guard !togglingMediaKeys.contains(key) else { return }
        togglingMediaKeys.insert(key)
        Task {
            defer { togglingMediaKeys.remove(key) }
            guard let entry = userLists.first(where: { $0.mediaId == animeId && $0.mediaType.lowercased() == "anime" }) else { return }
            let shouldUnfavorite = (entry.score ?? 0) >= 90
            let newRating: Int? = shouldUnfavorite ? nil : 100
            await updateListRating(mediaId: animeId, mediaType: "anime", rating: newRating)
        }
    }

    private func updateListRating(mediaId: Int, mediaType: String, rating: Int?) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
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

            errorMessage = nil
            await fetchUserLists()
        } catch {
            errorMessage = "Couldn't update rating: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to update rating: \(error)")
            #endif
        }
    }

        // MARK: - Clubs
    // Extracted to SupabaseService+Clubs.swift

    // MARK: - Social Activity (Friend Comments & Indicators)
    // Extracted to SupabaseService+Social.swift

// MARK: - Streaming Availability state

    // Stored on the main service; behavior lives in SupabaseService+Streaming.swift.
    var providerCache: [String: [ProviderInfo]] = [:]
    var providerPrefetchTask: Task<Void, Never>?
    var providerAvailabilityCache: [String: [ProviderAvailabilityProvider]] = [:]
    var providerAvailabilityPrefetchTask: Task<Void, Never>?
    var availabilityRefreshEnqueueCooldown: [String: Date] = [:]
    var userStreamingServices: [String] = []
    var clubSharedProvidersCache: [String: ClubSharedProvidersResponse] = [:]
    var streamingServiceRegistry: [StreamingServiceRecord] = []

        // MARK: - Club Realtime
    // Extracted to SupabaseService+ClubRealtime.swift


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
    var configError: String? = nil
    var isAuthBootstrapping: Bool = false
    var isAuthenticated: Bool = false
    var authErrorMessage: String? = nil
    var currentUserEmail: String? = nil
    var currentUserId: String? = nil

    init() {
        #if DEBUG
        print("[Mock] Supabase SDK not found. Running with mock SupabaseService.")
        #endif
    }

    // Auth
    func signInAnonymously() async throws {}
    func handleAuthCallback(accessToken: String, refreshToken: String) async {}
    func refreshSessionIfNeeded() async {}

    // Memory pressure
    func trimCachesForMemoryPressure() {}

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
}
#endif
