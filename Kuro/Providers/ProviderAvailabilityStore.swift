import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Provider availability (streaming / reading services)
// Owner of where-to-watch / where-to-read data, in two halves:
// - PUBLIC (never account-scoped, survives sign-out): the service registry, the per-title provider
//   and availability caches with their batch prefetches, the refresh-enqueue cooldown, the
//   ranking/allowlist constants and the legal watch/read links (ProviderAvailabilityStore+LegalLinks).
// - PRIVATE (account-scoped, `AccountScopedState`): the account's own service selection
//   (`userStreamingServices`) and the club-shared provider aggregates (`clubSharedProvidersCache`).
//   Each private read/write captures its `AccountContext` and publishes only while it is current;
//   the session funnel clears both on every transition. A club revocation (the caller left or was
//   removed) drops that club's aggregate through `invalidateClubSharedProviders(clubId:)`.
// Feature gating is unchanged: the where-to-watch surfaces stay behind `streaming_availability_v1`
// (checked by the session bootstrap and the views; in this owner it is read by the detail-page link
// resolution, ProviderAvailabilityStore+DetailLinks, which gates on it as the detail views did, and
// reported by `streamingObservabilitySnapshot`). Provider notes keep the typed
// `ProviderAvailabilityNote` contract (dub / audio / subtitles / generic availability).

@MainActor
@Observable
final class ProviderAvailabilityStore: AccountScopedState {

    struct ProviderInfo: Decodable, Sendable {
        let slug: String
        let display_name: String
        let language: String?
    }

    struct BatchProviderResult: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let providers: [ProviderInfo]
    }

    struct StreamingServiceRecord: Decodable, Sendable, Identifiable {
        let slug: String
        let display_name: String
        let media_types: [String]
        let priority: Int
        let is_active: Bool
        var id: String { slug }
    }

    struct ClubSharedProvidersResponse: Decodable, Sendable {
        let shared_services: [SharedService]
        let member_count_total: Int
        let member_count_with_services: Int
        let coverage_pct: Int

        struct SharedService: Decodable, Sendable {
            let slug: String
            let display_name: String
        }
    }

    struct ProviderAvailabilityQueueSummary: Decodable, Sendable {
        let urgentPendingCount: Int
        let oldestPendingRequestAgeSeconds: Int
        let requestReasonMix: [String: Int]

        enum CodingKeys: String, CodingKey {
            case urgentPendingCount = "urgent_pending_count"
            case oldestPendingRequestAgeSeconds = "oldest_pending_request_age_seconds"
            case requestReasonMix = "request_reason_mix"
        }
    }

    struct StreamingObservabilitySnapshot: Sendable {
        let isStreamingAvailabilityEnabled: Bool
        let configuredServiceCount: Int
        let registryServiceCount: Int
        let cachedCatalogTitleCount: Int
        let cachedVerifiedTitleCount: Int
        let queueSummary: ProviderAvailabilityQueueSummary?
    }

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every request fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// The shared account coordinator (private completions are checked against it).
    let accountSession: AccountSessionCoordinator
    /// Public catalog reads behind the legal links (external links).
    let catalog: CatalogStore
    /// The app's runtime flags (composition's single instance): `streaming_availability_v1`.
    @ObservationIgnored let flags: FeatureFlags

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, catalog: CatalogStore, flags: FeatureFlags) {
        self.client = client
        self.accountSession = accountSession
        self.catalog = catalog
        self.flags = flags
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
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

    // MARK: Public state (not account-scoped; survives sign-out)

    var providerCache: [String: [ProviderInfo]] = [:]
    @ObservationIgnored var providerPrefetchTask: Task<Void, Never>?
    var providerAvailabilityCache: [String: [ProviderAvailabilityProvider]] = [:]
    @ObservationIgnored var providerAvailabilityPrefetchTask: Task<Void, Never>?
    var availabilityRefreshEnqueueCooldown: [String: Date] = [:]
    var streamingServiceRegistry: [StreamingServiceRecord] = []

    // MARK: Private state (account-scoped)

    var userStreamingServices: [String] = []
    var clubSharedProvidersCache: [String: ClubSharedProvidersResponse] = [:]
    /// Per-club invalidation generation, bumped by `invalidateClubSharedProviders(clubId:)` and
    /// checked where `fetchClubSharedProviders` publishes.
    @ObservationIgnored private var clubSharedProvidersGeneration: [String: Int] = [:]
    @ObservationIgnored private var clubDisclosureGeneration = 0

    // MARK: AccountScopedState

    /// Deliberately empty: no account-scoped work is tracked. The private reads and the save are
    /// awaited by their callers and rejected by their captured context; the batch prefetches fill
    /// public caches only and are left running.
    func cancelAccountWork() {}

    func clearPrivateState() {
        userStreamingServices = []
        clubSharedProvidersCache.removeAll()
        clubSharedProvidersGeneration.removeAll()
        clubDisclosureGeneration += 1
    }

    /// Drops the shared-provider aggregate of `clubId` after a club revocation (the caller left the
    /// club or was removed from it while staying signed in). A `fetchClubSharedProviders` for that
    /// club still in flight does not refill the entry: it returns nil instead. Other clubs keep theirs.
    /// Called by the Clubs owner.
    func invalidateClubSharedProviders(clubId: String) {
        clubSharedProvidersGeneration[clubId, default: 0] += 1
        clubSharedProvidersCache[clubId] = nil
    }

    /// A disclosure signal can arrive before the first club list/aggregate has
    /// loaded. Guard every outstanding read, including a not-yet-cached club.
    func invalidateAllClubSharedProviders() {
        clubDisclosureGeneration += 1
        clubSharedProvidersCache.removeAll()
    }

    // MARK: - Streaming Availability

    func providers(mediaId: Int, mediaType: String) -> [ProviderInfo] {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let cached = providerCache[key], !cached.isEmpty {
            return cached
        }
        if let availability = providerAvailabilityCache[key], !availability.isEmpty {
            return availability.map { provider in
                ProviderInfo(
                    slug: provider.slug,
                    display_name: provider.displayName,
                    language: provider.languages.first
                )
            }
        }
        return []
    }

    func providerAvailability(mediaId: Int, mediaType: String) -> [ProviderAvailabilityProvider] {
        providerAvailabilityCache["\(mediaType.uppercased())-\(mediaId)"] ?? []
    }

    func bestProviderDisplayName(mediaId: Int, mediaType: String) -> String? {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let provider = providerAvailabilityCache[key]?.first {
            return provider.displayName
        }
        return providers(mediaId: mediaId, mediaType: mediaType).first?.display_name
    }

    func bestProviderAvailabilityNote(
        mediaId: Int,
        mediaType: String,
        preferredAudioLang: String?,
        preferredSubtitleLang: String? = nil,
        originalLanguage: String? = nil
    ) -> ProviderAvailabilityNote? {
        guard mediaType.uppercased() == "ANIME" else { return nil }
        let key = "\(mediaType.uppercased())-\(mediaId)"
        guard let providers = providerAvailabilityCache[key], !providers.isEmpty else { return nil }
        return ProviderAvailabilityNoteBuilder.bestNote(
            from: providers,
            preferredAudioLang: preferredAudioLang,
            preferredSubtitleLang: preferredSubtitleLang,
            originalLanguage: originalLanguage
        )
    }

    func collectionItemsAvailableOn(slug: String) -> Set<String> {
        var result = Set<String>()
        for (key, providers) in providerCache {
            if providers.contains(where: { $0.slug == slug }) {
                result.insert(key)
            }
        }
        for (key, providers) in providerAvailabilityCache {
            if providers.contains(where: { $0.slug == slug }) {
                result.insert(key)
            }
        }
        return result
    }

    func collectionItemsWithLanguage(lang: String, includeUnknown: Bool) -> Set<String> {
        var result = Set<String>()
        for (key, providers) in providerCache {
            if providers.contains(where: {
                let normalized = normalizedExternalLanguage($0.language)
                return normalized == lang || (includeUnknown && normalized == "unknown")
            }) {
                result.insert(key)
            }
        }
        for (key, providers) in providerAvailabilityCache {
            if providers.contains(where: { provider in
                if provider.languages.contains(lang) { return true }
                if includeUnknown && provider.languages.contains("unknown") { return true }
                return false
            }) {
                result.insert(key)
            }
        }
        return result
    }

    func fetchProviderAvailabilityV2(
        items: [(mediaType: String, mediaId: Int)],
        preferredAudioLang: String? = nil,
        preferredSubLang: String? = nil,
        includeUnknown: Bool = true
    ) async {
        guard !items.isEmpty else { return }
        let payload = items.map { ["media_type": $0.mediaType.uppercased(), "media_id": "\($0.mediaId)"] }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        do {
            let client = try requiredClient()
            let params = RPCBatchProviderAvailabilityV2Params(
                p_items: jsonString,
                p_audio_lang: preferredAudioLang,
                p_sub_lang: preferredSubLang,
                p_include_unknown: includeUnknown
            )
            let raw: [ProviderAvailabilityBatchItem] = try await client
                .rpc("batch_provider_availability_for_media_v2", params: params)
                .execute()
                .value
            for item in raw {
                let key = "\(item.mediaType)-\(item.mediaId)"
                providerAvailabilityCache[key] = item.providers
                providerCache[key] = item.providers.map {
                    ProviderInfo(slug: $0.slug, display_name: $0.displayName, language: $0.languages.first)
                }
            }
        } catch {
            #if DEBUG
            print("[Streaming] fetchProviderAvailabilityV2 error: \(error.localizedDescription)")
            #endif
        }
    }

    func prefetchProviderAvailabilityV2(
        items: [(mediaType: String, mediaId: Int)],
        preferredAudioLang: String? = nil,
        preferredSubLang: String? = nil,
        includeUnknown: Bool = true
    ) {
        providerAvailabilityPrefetchTask?.cancel()
        providerAvailabilityPrefetchTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchProviderAvailabilityV2(
                items: items,
                preferredAudioLang: preferredAudioLang,
                preferredSubLang: preferredSubLang,
                includeUnknown: includeUnknown
            )
        }
    }

    func prefetchProviders(items: [(mediaType: String, mediaId: Int)]) {
        providerPrefetchTask?.cancel()
        providerPrefetchTask = Task { [weak self] in
            guard let self, !items.isEmpty else { return }
            let payload = items.map { ["media_type": $0.mediaType, "media_id": "\($0.mediaId)"] }
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            do {
                let client = try requiredClient()
                let params = RPCBatchProvidersParams(p_items: jsonString)
                let raw: [BatchProviderResult] = try await client
                    .rpc("batch_providers_for_media", params: params)
                    .execute()
                    .value
                guard !Task.isCancelled else { return }
                for item in raw {
                    self.providerCache["\(item.media_type)-\(item.media_id)"] = item.providers
                }
            } catch {
                #if DEBUG
                print("[Streaming] prefetchProviders error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func enqueueAvailabilityRefreshIfStale(
        mediaType: String,
        mediaId: Int,
        reason: String = "on_demand_open"
    ) async -> Bool {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let last = availabilityRefreshEnqueueCooldown[key],
           Date().timeIntervalSince(last) < 10 * 60 {
            return false
        }
        do {
            let rows = try await fetchMediaAvailabilityStatusRows(
                mediaType: mediaType,
                mediaId: mediaId
            )
            let shouldQueue: Bool
            if let status = rows.first {
                shouldQueue = (!status.hasRows) || ((status.staleDays ?? 999) >= 30)
            } else {
                shouldQueue = true
            }

            guard shouldQueue else { return false }
            let client = try requiredClient()
            let enqueueParams = RPCEnqueueMediaAvailabilityRefreshParams(
                p_media_type: mediaType.uppercased(),
                p_media_id: mediaId,
                p_reason: reason
            )
            let _: AnyJSON = try await client
                .rpc("enqueue_media_availability_refresh", params: enqueueParams)
                .execute()
                .value
            availabilityRefreshEnqueueCooldown[key] = Date()
            return true
        } catch {
            #if DEBUG
            print("[Streaming] enqueueAvailabilityRefreshIfStale error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func mediaAvailabilityStatus(
        mediaId: Int,
        mediaType: String
    ) async -> MediaAvailabilityStatus? {
        do {
            return try await fetchMediaAvailabilityStatusRows(
                mediaType: mediaType,
                mediaId: mediaId
            ).first
        } catch {
            #if DEBUG
            print("[Streaming] mediaAvailabilityStatus error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    func fetchProviderAvailabilityQueueSummary() async -> ProviderAvailabilityQueueSummary? {
        do {
            let client = try requiredClient()
            return try await client
                .rpc("get_provider_availability_refresh_queue_summary")
                .execute()
                .value
        } catch {
            #if DEBUG
            print("[Streaming] fetchProviderAvailabilityQueueSummary error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    func streamingObservabilitySnapshot() async -> StreamingObservabilitySnapshot {
        let queueSummary = await fetchProviderAvailabilityQueueSummary()
        let verifiedTitleCount = providerAvailabilityCache.values.filter { !$0.isEmpty }.count
        let catalogTitleCount = providerCache.values.filter { !$0.isEmpty }.count
        return StreamingObservabilitySnapshot(
            isStreamingAvailabilityEnabled: flags.isStreamingAvailabilityV1Enabled,
            configuredServiceCount: userStreamingServices.count,
            registryServiceCount: streamingServiceRegistry.count,
            cachedCatalogTitleCount: catalogTitleCount,
            cachedVerifiedTitleCount: verifiedTitleCount,
            queueSummary: queueSummary
        )
    }

    private func fetchMediaAvailabilityStatusRows(
        mediaType: String,
        mediaId: Int
    ) async throws -> [MediaAvailabilityStatus] {
        let client = try requiredClient()
        let params = RPCGetMediaAvailabilityStatusParams(
            p_media_type: mediaType.uppercased(),
            p_media_id: mediaId
        )
        return try await client
            .rpc("get_media_availability_status", params: params)
            .execute()
            .value
    }

    func fetchStreamingServiceRegistry() async {
        do {
            let client = try requiredClient()
            let records: [StreamingServiceRecord] = try await client
                .from("streaming_services")
                .select()
                .eq("is_active", value: true)
                .order("priority", ascending: true)
                .execute()
                .value
            streamingServiceRegistry = records
        } catch {
            #if DEBUG
            print("[Streaming] fetchStreamingServiceRegistry error: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - The account's services and club-shared providers (account-scoped)

    func fetchUserStreamingServices() async {
        let context = accountSession.current
        do {
            struct Row: Decodable { let service: String }
            let client = try requiredClient()
            let rows: [Row] = try await accountSession.withCredentialLease(for: context) {
                try await client
                    .from("user_streaming_services")
                    .select("service")
                    .execute()
                    .value
            }
            guard accountSession.isCurrent(context) else { return }
            userStreamingServices = rows.map(\.service)
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            print("[Streaming] fetchUserStreamingServices error: \(error.localizedDescription)")
            #endif
        }
    }

    @discardableResult
    func saveUserStreamingServices(_ slugs: [String]) async -> Bool {
        let context = accountSession.current
        do {
            let client = try requiredClient()
            let params = RPCSaveStreamingServicesParams(p_services: slugs)
            let _: AnyJSON = try await accountSession.withCredentialLease(for: context) {
                try await client
                    .rpc("save_user_streaming_services", params: params)
                    .execute()
                    .value
            }
            guard accountSession.isCurrent(context), !Task.isCancelled else { return false }
            userStreamingServices = slugs
            return true
        } catch is CancellationError {
            return false
        } catch {
            #if DEBUG
            print("[Streaming] saveUserStreamingServices error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func fetchClubSharedProviders(clubId: String) async -> ClubSharedProvidersResponse? {
        let context = accountSession.current
        let generation = clubSharedProvidersGeneration[clubId, default: 0]
        let disclosure = clubDisclosureGeneration
        do {
            struct Params: Encodable, Sendable {
                let p_club_id: String
                enum CodingKeys: String, CodingKey { case p_club_id }
                nonisolated func encode(to encoder: Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(p_club_id, forKey: .p_club_id)
                }
            }
            let client = try requiredClient()
            let response: ClubSharedProvidersResponse = try await accountSession.withCredentialLease(for: context) {
                try await client
                    .rpc("club_shared_providers", params: Params(p_club_id: clubId))
                    .execute()
                    .value
            }
            guard accountSession.isCurrent(context) else { return nil }
            // The club was invalidated (left / removed) while this read was in flight.
            guard clubSharedProvidersGeneration[clubId, default: 0] == generation,
                  clubDisclosureGeneration == disclosure else { return nil }
            clubSharedProvidersCache[clubId] = response
            return response
        } catch is CancellationError {
            return nil
        } catch {
            #if DEBUG
            print("[Streaming] fetchClubSharedProviders error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    func cachedClubSharedProviders(clubId: String) -> ClubSharedProvidersResponse? {
        clubSharedProvidersCache[clubId]
    }
}
#endif
