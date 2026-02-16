import Foundation
import Observation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - FeatureFlags
// Server-controlled feature flags with local caching and deterministic rollout.
// Flags are fetched from the `feature_flags` table on app launch and cached
// in UserDefaults. Rollout is evaluated using a stable hash of the user ID
// so a given user always sees the same result for a given rollout percentage.

@MainActor
@Observable
final class FeatureFlags {
    static let shared = FeatureFlags()

    // MARK: - Flag state

    private var flags: [String: FlagRecord] = [:]
    private var userId: String?
    private var lastFetchDate: Date?

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
    var isClubsChatV1Enabled: Bool { evaluate("clubs_chat_v1") }
    var isClubsNotificationsV1Enabled: Bool { evaluate("clubs_notifications_v1") }

    // MARK: - Init

    private init() {
        loadFromCache()
    }

    // MARK: - Fetch from server

    /// Call once after auth bootstrap. Fetches latest flags from Supabase and
    /// caches them locally. Failures are silently ignored (stale cache is used).
    func refresh(client: Any, userId: String?) async {
        self.userId = userId
        #if canImport(Supabase)
        guard let supabase = client as? SupabaseClient else { return }
        do {
            let records: [FlagRecord] = try await supabase
                .from("feature_flags")
                .select()
                .execute()
                .value
            var newFlags: [String: FlagRecord] = [:]
            for r in records { newFlags[r.flagName] = r }
            flags = newFlags
            lastFetchDate = Date()
            saveToCache()
            #if DEBUG
            print("[FeatureFlags] refreshed \(records.count) flags")
            #endif
        } catch {
            #if DEBUG
            print("[FeatureFlags] refresh failed, using cache: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    /// Update the user ID (e.g. after login/logout) without re-fetching.
    func setUserId(_ id: String?) {
        userId = id
    }

    // MARK: - Evaluation

    /// Deterministic evaluation: flag must be enabled AND user must fall within rollout %.
    /// Uses a stable hash of userId so the same user always gets the same bucket.
    func evaluate(_ flagName: String) -> Bool {
        if let localOverride = Self.localOverride(for: flagName) {
            return localOverride
        }
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
    nonisolated private static func localOverride(for flagName: String) -> Bool? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ff-on=\(flagName)") { return true }
        if args.contains("--ff-off=\(flagName)") { return false }
        #endif
        return nil
    }

    // MARK: - Local cache (UserDefaults)

    private static let cacheKey = "com.kuro.featureFlags.cache"

    private func saveToCache() {
        guard let data = try? JSONEncoder().encode(Array(flags.values)) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let records = try? JSONDecoder().decode([FlagRecord].self, from: data) else { return }
        var loaded: [String: FlagRecord] = [:]
        for r in records { loaded[r.flagName] = r }
        flags = loaded
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
