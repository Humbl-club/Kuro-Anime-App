import Foundation
import Observation
import KuroCore

#if canImport(Supabase)
import Supabase
#endif

// MARK: - FeatureFlags
// Server-controlled feature flags with local caching and deterministic rollout.
// Flags are fetched from the `feature_flags` table on app launch and cached
// in UserDefaults. Rollout is evaluated using a stable hash of the user ID
// so a given user always sees the same result for a given rollout percentage.
// Composition owns the single instance (E6c2: `AppComposition.flags`), injects it into the SwiftUI
// environment and into the owners that gate on a flag; the session funnel sets the user id and
// refreshes through that instance. Tests and previews construct their own instance.

@MainActor
@Observable
final class FeatureFlags {
    // MARK: - Flag state

    private var flags: [String: FlagRecord] = [:]
    private var userId: String?
    private var lastFetchDate: Date?
    // In-memory overrides belong to one generation; only two Home presentation flags
    // have bounded, exact-account offline eligibility cached separately.
    private var accountOverrides: [String: Bool] = [:]
    private var foundationHydrated = false
    @ObservationIgnored private var refreshGeneration = 0
    /// The local cache store (production: `.standard`).
    @ObservationIgnored private let userDefaults: UserDefaults
    /// The process launch arguments read by the DEBUG overrides (production: this process's).
    @ObservationIgnored private let launchArguments: [String]
    /// Thread-safe copy of `series_foundation_v1` for the library writer, which is not on the main actor.
    @ObservationIgnored nonisolated private let revisionFence = RevisionFenceSwitch()

    // MARK: - Convenience accessors

    var isRagAssistEnabled: Bool { evaluate("rag_assist_v1") }
    var isFmAssistEnabled: Bool { evaluate("fm_assist_v1") }
    var isClarifyV2Enabled: Bool { evaluate("clarify_v2") }
    var isClubsInteractionV2Enabled: Bool { evaluate("clubs_interaction_v2") }
    var isConciergePerfV2Enabled: Bool { evaluate("concierge_perf_v2") }
    var isConciergeEditorialV1Enabled: Bool { evaluate("concierge_editorial_v1") }
    var isSwipeTapGuardEnabled: Bool { evaluate("swipe_tap_guard_v1") }
    var isClubsListEnrichedV1Enabled: Bool { evaluate("clubs_list_enriched_v1") }
    var isClubsReactionsV1Enabled: Bool { evaluate("clubs_reactions_v1") }
    var isClubsPaceSyncV1Enabled: Bool { evaluate("clubs_pace_sync_v1") }
    var isClubsRealtimeV1Enabled: Bool { evaluate("clubs_realtime_v1") }
    var isClubsNotificationsV1Enabled: Bool { evaluate("clubs_notifications_v1") }
    var isSocialActivityV1Enabled: Bool { evaluate("social_activity_v1") }
    var isStreamingAvailabilityV1Enabled: Bool { evaluate("streaming_availability_v1") }
    var isCreditsCastV1Enabled: Bool { evaluate("credits_cast_v1") }
    var tasteDeckV1Enabled: Bool { evaluate("taste_deck_v1") }
    var seriesFoundationV1Enabled: Bool { evaluate("series_foundation_v1") }
    var seriesHomeNativeV1Enabled: Bool {
        foundationHydrated && seriesFoundationV1Enabled && evaluate("series_home_native_v1")
    }
    var personalizedNewToYouV1Enabled: Bool { evaluate("personalized_new_to_you_v1") }
    var discoverRealmRailsV1Enabled: Bool { evaluate("discover_realm_rails_v1") }

    // MARK: - Init

    init(
        userDefaults: UserDefaults = .standard,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.userDefaults = userDefaults
        self.launchArguments = launchArguments
        loadFromCache()
        publishRevisionFence()
    }

    /// Live `series_foundation_v1` value. The library backend reads this off the main actor.
    nonisolated func seriesFoundationFenceEnabled() -> Bool {
        revisionFence.isOn
    }

    // MARK: - Fetch from server

    /// Call once after auth bootstrap. Fetches latest flags from Supabase and
    /// caches them locally. Failures are silently ignored (stale cache is used).
    func refresh(client: Any, userId: String?, accountSession: AccountSessionCoordinator? = nil) async {
        // An account's queued bootstrap can start after another account took over.
        // Reject it before it can change even the public rollout identity.
        if let accountSession {
            if let userId, let current = accountSession.current {
                guard AccountSessionCoordinator.sameUser(userId, current.userId) else { return }
            } else {
                guard userId == nil, accountSession.current == nil else { return }
            }
        }
        setUserId(userId)
        refreshGeneration += 1
        let generation = refreshGeneration
        let account = accountSession?.current
        func isCurrent() -> Bool {
            generation == refreshGeneration && self.userId == userId
                && (accountSession == nil || accountSession?.isCurrent(account) == true)
        }
        #if canImport(Supabase)
        guard let supabase = client as? SupabaseClient else { return }
        let retryDelays: [Duration] = [.seconds(10), .seconds(30), .seconds(60)]

        for attempt in 0...retryDelays.count {
            guard !Task.isCancelled, isCurrent() else { return }
            do {
                let records: [FlagRecord] = try await supabase
                    .from("feature_flags")
                    .select()
                    .execute()
                    .value
                guard !Task.isCancelled, isCurrent() else { return }
                var newFlags: [String: FlagRecord] = [:]
                for r in records { newFlags[r.flagName] = r }
                flags = newFlags
                lastFetchDate = Date()
                saveToCache()
                // The off-main library writer reads the fence: follow the server in every build,
                // whether or not the overrides lookup below runs (Release skips it).
                publishRevisionFence()
                // Tester cohort overrides (spec D14): read only in DEBUG builds, because the
                // `feature_flag_overrides` table is prepared, not deployed live. A successful lookup
                // (rows or none) replaces the cohort; ANY failure keeps the cached cohort and never
                // resets the bootstrap, so a missing table (PGRST205/404) cannot flip Home off.
                if Self.readsAccountOverrides, let userId, let accountSession, let account,
                   AccountSessionCoordinator.sameUser(userId, account.userId) {
                    do {
                        let records: [AccountFlagOverride] = try await accountSession.withCredentialLease(for: account) {
                            try await supabase.from("feature_flag_overrides")
                                .select("user_id,flag_name,enabled")
                                .eq("user_id", value: account.userId.lowercased())
                                .execute().value
                        }
                        guard !Task.isCancelled, isCurrent() else { return }
                        accountOverrides = [:]
                        for record in records where AccountSessionCoordinator.sameUser(record.userId, userId) {
                            accountOverrides[record.flagName] = record.enabled
                        }
                        saveHomeCohort(for: userId)
                        publishRevisionFence()
                    } catch {
                        switch Self.overridesFailure(for: error) {
                        case .cancelled:
                            // Refused/revoked lease is not a server answer.
                            return
                        case .keepCachedCohort:
                            guard !Task.isCancelled, isCurrent() else { return }
                            // Non-destructive: keep this account's overrides as they are
                            // (`setUserId` already scoped them); only an empty set falls back to
                            // the bounded cached Home cohort.
                            if accountOverrides.isEmpty { accountOverrides = cachedHomeCohort(for: userId) }
                            publishRevisionFence()
                            #if DEBUG
                            print("[FeatureFlags] overrides unavailable, keeping cached cohort: \(error.localizedDescription)")
                            #endif
                        }
                    }
                }
                #if DEBUG
                print("[FeatureFlags] refreshed \(records.count) flags")
                #endif
                return
            } catch is CancellationError {
                return
            } catch let error as URLError {
                guard !Task.isCancelled, isCurrent() else { return }
                if attempt < retryDelays.count {
                    #if DEBUG
                    print("[FeatureFlags] retry \(attempt + 1)/\(retryDelays.count) after URLError \(error.code.rawValue)")
                    #endif
                    try? await Task.sleep(for: retryDelays[attempt])
                }
            } catch {
                guard !Task.isCancelled, isCurrent() else { return }
                // Definitive public lookup rejection/decode failure cannot retain a
                // cached private tester cohort. Only transport outages use it.
                if let userId { removeHomeCohort(for: userId) }
                // Non-network error (decode, 4xx) — don't retry
                #if DEBUG
                print("[FeatureFlags] refresh failed (non-retryable), using cache: \(error.localizedDescription)")
                #endif
                return
            }
        }

        // All retries exhausted
        #if DEBUG
        if flags.isEmpty {
            print("[FeatureFlags] all retries failed and no cache available")
        } else {
            print("[FeatureFlags] all retries failed, using \(flags.count) cached flags")
        }
        #endif
        #endif
    }

    /// Whether this build reads `feature_flag_overrides` (spec D14: DEBUG only; the table is
    /// prepared, not deployed live).
    nonisolated static var readsAccountOverrides: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// What a failed overrides lookup does (spec D14). Only cancellation stops the refresh; every
    /// server or transport failure keeps the overrides already held (or, when none are, the bounded
    /// cached cohort) and leaves the bootstrap alone.
    nonisolated enum OverridesFailure: Equatable, Sendable {
        case cancelled
        case keepCachedCohort
    }

    nonisolated static func overridesFailure(for error: any Error) -> OverridesFailure {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        return .keepCachedCohort
    }

    /// Update the user ID (e.g. after login/logout) without re-fetching.
    func setUserId(_ id: String?) {
        if userId != id {
            refreshGeneration += 1
            accountOverrides = [:]
            foundationHydrated = false
        }
        let transitioned = userId != id
        userId = id
        if transitioned, let id { accountOverrides = cachedHomeCohort(for: id) }
        publishRevisionFence()
    }

    /// Called by the session funnel only after the current Library has revision metadata.
    func completeFoundationBootstrap(userId: String) {
        guard self.userId.map({ AccountSessionCoordinator.sameUser($0, userId) }) == true else { return }
        foundationHydrated = true
    }

    /// Presentation eligibility only. This cache never grants database/club access.
    /// Reopened Home additionally requires exact-account revision/lifecycle metadata.
    private static let offlineCohortFlags: Set<String> = ["series_foundation_v1", "series_home_native_v1"]
    private struct CachedHomeCohort: Codable {
        let userId: String
        let confirmedAt: Date
        let overrides: [String: Bool]
    }
    private func cohortKey(for id: String) -> String? {
        UUID(uuidString: id).map { "kuro.home-cohort.v1." + $0.uuidString.lowercased() }
    }
    private func cachedHomeCohort(for id: String) -> [String: Bool] {
        guard let key = cohortKey(for: id), let data = userDefaults.data(forKey: key), data.count <= 4096,
              let saved = try? JSONDecoder().decode(CachedHomeCohort.self, from: data),
              AccountSessionCoordinator.sameUser(saved.userId, id),
              saved.confirmedAt <= Date(), Date().timeIntervalSince(saved.confirmedAt) <= 86400,
              saved.overrides.keys.allSatisfy(Self.offlineCohortFlags.contains) else { return [:] }
        return saved.overrides
    }
    private func saveHomeCohort(for id: String) {
        guard let key = cohortKey(for: id) else { return }
        let values = accountOverrides.filter { Self.offlineCohortFlags.contains($0.key) }
        guard !values.isEmpty else { userDefaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(CachedHomeCohort(userId: id, confirmedAt: Date(), overrides: values)) {
            userDefaults.set(data, forKey: key)
        }
    }
    func removeHomeCohort(for id: String) {
        if let key = cohortKey(for: id) { userDefaults.removeObject(forKey: key) }
        if userId.map({ AccountSessionCoordinator.sameUser($0, id) }) == true {
            accountOverrides = [:]; foundationHydrated = false; publishRevisionFence()
        }
    }

    private func publishRevisionFence() {
        revisionFence.set(evaluate("series_foundation_v1"))
    }

    // MARK: - Evaluation

    /// Deterministic evaluation: flag must be enabled AND user must fall within rollout %.
    /// Uses a stable hash of userId so the same user always gets the same bucket.
    func evaluate(_ flagName: String) -> Bool {
        if let localOverride = localOverride(for: flagName) {
            return localOverride
        }
        if userId != nil, let override = accountOverrides[flagName] { return override }
        guard let flag = flags[flagName], flag.enabled else { return false }

        // Optional market gate: if target_markets is set, the current region must match.
        if !flag.targetMarkets.isEmpty {
            let markets = Set(flag.targetMarkets.map { $0.uppercased() })
            if !markets.contains("*"), !markets.contains(Self.currentRegionCode()) {
                return false
            }
        }

        // 100% rollout — skip hash
        if flag.rolloutPercentage >= 100 { return true }
        if flag.rolloutPercentage <= 0 { return false }

        guard let uid = userId, !uid.isEmpty else { return false }

        let bucket = stableHash(uid + flagName) % 100
        return bucket < flag.rolloutPercentage
    }

    // MARK: - Stable hash

    /// Simple, deterministic hash producing a non-negative Int.
    /// Uses djb2 algorithm -- fast, stable across platforms, no crypto dependency.
    private func stableHash(_ input: String) -> Int {
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Int(hash % UInt64(Int.max))
    }

    nonisolated private static func currentRegionCode() -> String {
        Locale.current.region?.identifier.uppercased() ?? "US"
    }

    /// Debug-only launch arg override.
    /// Examples:
    /// - --ff-on=concierge_editorial_v1
    /// - --ff-off=concierge_editorial_v1
    private func localOverride(for flagName: String) -> Bool? {
        #if DEBUG
        let args = launchArguments
        if args.contains("--ff-on=\(flagName)") { return true }
        if args.contains("--ff-off=\(flagName)") { return false }
        #endif
        return nil
    }

    // MARK: - Local cache (UserDefaults)

    private static let cacheKey = "com.kuro.featureFlags.cache"

    private func saveToCache() {
        guard let data = try? JSONEncoder().encode(Array(flags.values)) else { return }
        userDefaults.set(data, forKey: Self.cacheKey)
    }

    private func loadFromCache() {
        guard let data = userDefaults.data(forKey: Self.cacheKey),
              let records = try? JSONDecoder().decode([FlagRecord].self, from: data) else { return }
        var loaded: [String: FlagRecord] = [:]
        for r in records { loaded[r.flagName] = r }
        flags = loaded
    }
}

/// Cross-actor snapshot of whether progress writes must use the revision fence.
final class RevisionFenceSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false

    func set(_ value: Bool) {
        lock.lock()
        on = value
        lock.unlock()
    }

    var isOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return on
    }
}

// MARK: - FlagRecord

private struct FlagRecord: Codable {
    let flagName: String
    let enabled: Bool
    let rolloutPercentage: Int
    let targetMarkets: [String]
    let description: String?

    enum CodingKeys: String, CodingKey {
        case flagName = "flag_name"
        case enabled
        case rolloutPercentage = "rollout_percentage"
        case targetMarkets = "target_markets"
        case description
    }
}

/// Administrator-owned cohort decision, protected by both RLS and a scoped query.
private struct AccountFlagOverride: Decodable, Sendable {
    let userId: String
    let flagName: String
    let enabled: Bool
    enum CodingKeys: String, CodingKey {
        case userId = "user_id", flagName = "flag_name", enabled
    }
}
