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

    nonisolated struct ProviderInfo: Decodable, Sendable {
        let slug: String
        let display_name: String
        let language: String?
    }

    nonisolated struct BatchProviderResult: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let providers: [ProviderInfo]
    }

    nonisolated struct StreamingServiceRecord: Decodable, Sendable, Identifiable {
        let slug: String
        let display_name: String
        let media_types: [String]
        let priority: Int
        let is_active: Bool
        var id: String { slug }
    }

    nonisolated struct ClubSharedProvidersResponse: Decodable, Sendable {
        let shared_services: [SharedService]
        let member_count_total: Int
        let member_count_with_services: Int
        let coverage_pct: Int

        nonisolated struct SharedService: Decodable, Sendable {
            let slug: String
            let display_name: String
        }
    }

    nonisolated struct ProviderAvailabilityQueueSummary: Decodable, Sendable {
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
    /// The most recently started catalog-provider prefetch (callers and tests may await it).
    @ObservationIgnored var providerPrefetchTask: Task<Void, Never>?
    var providerAvailabilityCache: [String: [ProviderAvailabilityProvider]] = [:]
    /// The most recently started provider v2 prefetch (callers and tests may await it).
    @ObservationIgnored var providerAvailabilityPrefetchTask: Task<Void, Never>?
    /// Every batch prefetch still running, by id. Prefetches of different screens no longer cancel
    /// each other (a Collection refresh used to drop a Club page's batch, and vice versa).
    @ObservationIgnored private var providerPrefetchTasks: [UUID: Task<Void, Never>] = [:]
    /// Prefetch keys being requested right now, with the prefetch that owns them
    /// (`providerPrefetchKey` / `providerAvailabilityPrefetchKey`).
    @ObservationIgnored private var providerPrefetchInFlight: [String: UUID] = [:]
    /// When each prefetch key last answered successfully (`providerPrefetchTTL`): a fresh key is not
    /// requested again.
    @ObservationIgnored private var providerPrefetchFetchedAt: [String: Date] = [:]
    /// How long a batch prefetch answer is reused (matches `detailAvailabilityTTL`).
    nonisolated static let providerPrefetchTTL: TimeInterval = 10 * 60
    var availabilityRefreshEnqueueCooldown: [String: Date] = [:]
    var streamingServiceRegistry: [StreamingServiceRecord] = []
    /// When the registry was last read successfully (`streamingServiceRegistryTTL`).
    @ObservationIgnored var streamingServiceRegistryLoadedAt: Date?
    /// Availability status rows per media ("ANIME-42") read by the detail link resolution, kept for
    /// `detailAvailabilityTTL`: one status read per media id while its page is open.
    @ObservationIgnored var detailAvailabilityStatusCache: [String: TimedCache<[MediaAvailabilityStatus]>] = [:]
    /// When the detail link resolution last fetched provider v2 for a media and audio language
    /// ("ANIME-42|en").
    @ObservationIgnored var detailProviderAvailabilityFetchedAt: [String: Date] = [:]

    /// Lifetime of the detail resolution's status and provider v2 reads (matches the enqueue cooldown).
    nonisolated static let detailAvailabilityTTL: TimeInterval = 10 * 60
    /// The service registry is static reference data: one read per 30 minutes is enough.
    nonisolated static let streamingServiceRegistryTTL: TimeInterval = 30 * 60
    /// The columns `StreamingServiceRecord` decodes.
    nonisolated static let streamingServiceColumns = "slug,display_name,media_types,priority,is_active"

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
        await loadProviderAvailabilityV2(
            items: items,
            preferredAudioLang: preferredAudioLang,
            preferredSubLang: preferredSubLang,
            includeUnknown: includeUnknown
        )
    }

    /// `fetchProviderAvailabilityV2`, reporting whether the read succeeded (the detail resolution
    /// marks a media fresh only after a successful read).
    @discardableResult
    func loadProviderAvailabilityV2(
        items: [(mediaType: String, mediaId: Int)],
        preferredAudioLang: String? = nil,
        preferredSubLang: String? = nil,
        includeUnknown: Bool = true
    ) async -> Bool {
        guard !items.isEmpty else { return false }
        let payload = items.map { ["media_type": $0.mediaType.uppercased(), "media_id": "\($0.mediaId)"] }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return false }
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
            return true
        } catch {
            #if DEBUG
            print("[Streaming] fetchProviderAvailabilityV2 error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Prefetches provider v2 for `items`. Keys answered within `providerPrefetchTTL` (for the same
    /// languages and unknown policy) or already being requested by another prefetch are skipped;
    /// when nothing is left, no request is made. A key is marked fresh only after a successful read.
    func prefetchProviderAvailabilityV2(
        items: [(mediaType: String, mediaId: Int)],
        preferredAudioLang: String? = nil,
        preferredSubLang: String? = nil,
        includeUnknown: Bool = true
    ) {
        let keyOf: ((mediaType: String, mediaId: Int)) -> String = { item in
            Self.providerAvailabilityPrefetchKey(
                mediaType: item.mediaType,
                mediaId: item.mediaId,
                audio: preferredAudioLang,
                sub: preferredSubLang,
                includeUnknown: includeUnknown
            )
        }
        guard let claim = beginProviderPrefetch(items: items, key: keyOf) else { return }
        let (id, keys, requested) = claim
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishProviderPrefetch(id, keys: keys) }
            let loaded = await self.loadProviderAvailabilityV2(
                items: requested,
                preferredAudioLang: preferredAudioLang,
                preferredSubLang: preferredSubLang,
                includeUnknown: includeUnknown
            )
            if loaded { self.markProviderPrefetchFresh(keys) }
        }
        providerPrefetchTasks[id] = task
        providerAvailabilityPrefetchTask = task
    }

    /// Prefetches the catalog providers of `items` with the freshness and in-flight rules of
    /// `prefetchProviderAvailabilityV2`. Every requested key is marked fresh after a successful
    /// answer, including titles the server omitted (no providers), so they are not asked again.
    func prefetchProviders(items: [(mediaType: String, mediaId: Int)]) {
        let keyOf: ((mediaType: String, mediaId: Int)) -> String = { item in
            Self.providerPrefetchKey(mediaType: item.mediaType, mediaId: item.mediaId)
        }
        guard let claim = beginProviderPrefetch(items: items, key: keyOf) else { return }
        let (id, keys, requested) = claim
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishProviderPrefetch(id, keys: keys) }
            let payload = requested.map { ["media_type": $0.mediaType, "media_id": "\($0.mediaId)"] }
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
                self.markProviderPrefetchFresh(keys)
            } catch {
                #if DEBUG
                print("[Streaming] prefetchProviders error: \(error.localizedDescription)")
                #endif
            }
        }
        providerPrefetchTasks[id] = task
        providerPrefetchTask = task
    }

    /// Claims the stale, not-in-flight keys of `items` for a new prefetch: returns its id, the
    /// claimed keys and the de-duplicated items to request, or nil when nothing needs requesting.
    private func beginProviderPrefetch(
        items: [(mediaType: String, mediaId: Int)],
        key: ((mediaType: String, mediaId: Int)) -> String
    ) -> (UUID, [String], [(mediaType: String, mediaId: Int)])? {
        let pending = Self.providerPrefetchKeysToRequest(
            items.map(key),
            fetchedAt: providerPrefetchFetchedAt,
            inFlight: Set(providerPrefetchInFlight.keys),
            now: Date(),
            ttl: Self.providerPrefetchTTL
        )
        guard !pending.isEmpty else { return nil }
        let pendingSet = Set(pending)
        var seen = Set<String>()
        let requested = items.filter { item in
            let itemKey = key(item)
            return pendingSet.contains(itemKey) && seen.insert(itemKey).inserted
        }
        let id = UUID()
        for pendingKey in pending { providerPrefetchInFlight[pendingKey] = id }
        return (id, pending, requested)
    }

    /// Releases the keys a prefetch still owns.
    private func finishProviderPrefetch(_ id: UUID, keys: [String]) {
        providerPrefetchTasks[id] = nil
        for key in keys where providerPrefetchInFlight[key] == id {
            providerPrefetchInFlight[key] = nil
        }
    }

    private func markProviderPrefetchFresh(_ keys: [String]) {
        let now = Date()
        if providerPrefetchFetchedAt.count > 1_000 {
            let cutoff = now.addingTimeInterval(-Self.providerPrefetchTTL)
            providerPrefetchFetchedAt = providerPrefetchFetchedAt.filter { $0.value > cutoff }
        }
        for key in keys { providerPrefetchFetchedAt[key] = now }
    }

    /// The freshness key of one catalog-provider prefetch ("v1|ANIME-42").
    nonisolated static func providerPrefetchKey(mediaType: String, mediaId: Int) -> String {
        "v1|\(availabilityKey(mediaType: mediaType, mediaId: mediaId))"
    }

    /// The freshness key of one provider v2 prefetch: the media plus every parameter that changes the
    /// answer ("v2|ANIME-42|a=en|s=|u=1").
    nonisolated static func providerAvailabilityPrefetchKey(
        mediaType: String,
        mediaId: Int,
        audio: String?,
        sub: String?,
        includeUnknown: Bool
    ) -> String {
        "v2|\(availabilityKey(mediaType: mediaType, mediaId: mediaId))|a=\(audio ?? "")|s=\(sub ?? "")|u=\(includeUnknown ? 1 : 0)"
    }

    /// The keys of `keys` a prefetch should request: de-duplicated in first-seen order, without keys
    /// being requested (`inFlight`) or answered less than `ttl` ago.
    nonisolated static func providerPrefetchKeysToRequest(
        _ keys: [String],
        fetchedAt: [String: Date],
        inFlight: Set<String>,
        now: Date,
        ttl: TimeInterval
    ) -> [String] {
        var seen = Set<String>()
        return keys.filter { key in
            guard seen.insert(key).inserted, !inFlight.contains(key) else { return false }
            if let answered = fetchedAt[key], now.timeIntervalSince(answered) < ttl { return false }
            return true
        }
    }

    func enqueueAvailabilityRefreshIfStale(
        mediaType: String,
        mediaId: Int,
        reason: String = "on_demand_open"
    ) async -> Bool {
        if isAvailabilityRefreshCoolingDown(mediaType: mediaType, mediaId: mediaId) { return false }
        let rows: [MediaAvailabilityStatus]
        do {
            rows = try await fetchMediaAvailabilityStatusRows(mediaType: mediaType, mediaId: mediaId)
        } catch {
            #if DEBUG
            print("[Streaming] enqueueAvailabilityRefreshIfStale error: \(error.localizedDescription)")
            #endif
            return false
        }
        return await enqueueAvailabilityRefresh(
            mediaType: mediaType,
            mediaId: mediaId,
            reason: reason,
            knownStatusRows: rows
        )
    }

    /// The refresh-enqueue write decided from status rows the caller already read (the detail link
    /// resolution passes its own read instead of reading the status a second time). Cooldown-gated;
    /// true only when the write went through.
    func enqueueAvailabilityRefresh(
        mediaType: String,
        mediaId: Int,
        reason: String,
        knownStatusRows rows: [MediaAvailabilityStatus]
    ) async -> Bool {
        if isAvailabilityRefreshCoolingDown(mediaType: mediaType, mediaId: mediaId) { return false }
        guard Self.shouldQueueAvailabilityRefresh(rows.first) else { return false }
        do {
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
            availabilityRefreshEnqueueCooldown[Self.availabilityKey(mediaType: mediaType, mediaId: mediaId)] = Date()
            return true
        } catch {
            #if DEBUG
            print("[Streaming] enqueueAvailabilityRefresh error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Whether a refresh of this media was enqueued within the last 10 minutes (the detail caption
    /// keeps saying "Refreshing" while the status still looks stale).
    func isAvailabilityRefreshCoolingDown(mediaType: String, mediaId: Int) -> Bool {
        guard let last = availabilityRefreshEnqueueCooldown[Self.availabilityKey(mediaType: mediaType, mediaId: mediaId)] else {
            return false
        }
        return Date().timeIntervalSince(last) < 10 * 60
    }

    /// A refresh is queued when the title has no availability rows (or no status row at all) or its
    /// rows are at least 30 days old.
    nonisolated static func shouldQueueAvailabilityRefresh(_ status: MediaAvailabilityStatus?) -> Bool {
        guard let status else { return true }
        return !status.hasRows || (status.staleDays ?? 999) >= 30
    }

    /// The per-media key of the availability caches ("ANIME-42").
    nonisolated static func availabilityKey(mediaType: String, mediaId: Int) -> String {
        "\(mediaType.uppercased())-\(mediaId)"
    }

    // MARK: Detail link resolution caches

    /// The status rows of one media for the detail link resolution: served from
    /// `detailAvailabilityStatusCache` within `detailAvailabilityTTL`, otherwise read once and kept.
    /// nil when the read failed (nothing is cached then).
    func detailAvailabilityStatusRows(mediaType: String, mediaId: Int) async -> [MediaAvailabilityStatus]? {
        let key = Self.availabilityKey(mediaType: mediaType, mediaId: mediaId)
        if let cached = detailAvailabilityStatusCache[key],
           Date().timeIntervalSince(cached.storedAt) < Self.detailAvailabilityTTL {
            return cached.value
        }
        do {
            let rows = try await fetchMediaAvailabilityStatusRows(mediaType: mediaType, mediaId: mediaId)
            trimTimedCache(&detailAvailabilityStatusCache, maxEntries: 100)
            detailAvailabilityStatusCache[key] = TimedCache(value: rows, storedAt: Date())
            return rows
        } catch {
            #if DEBUG
            print("[Streaming] detailAvailabilityStatusRows error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Whether the detail resolution should fetch provider v2 for this media and audio language: not
    /// within `detailAvailabilityTTL` of its last fetch.
    func shouldFetchDetailProviderAvailability(mediaType: String, mediaId: Int, audio: String) -> Bool {
        let key = "\(Self.availabilityKey(mediaType: mediaType, mediaId: mediaId))|\(audio)"
        guard let last = detailProviderAvailabilityFetchedAt[key] else { return true }
        return Date().timeIntervalSince(last) >= Self.detailAvailabilityTTL
    }

    func markDetailProviderAvailabilityFetched(mediaType: String, mediaId: Int, audio: String) {
        if detailProviderAvailabilityFetchedAt.count > 200 {
            let cutoff = Date().addingTimeInterval(-Self.detailAvailabilityTTL)
            detailProviderAvailabilityFetchedAt = detailProviderAvailabilityFetchedAt.filter { $0.value > cutoff }
        }
        detailProviderAvailabilityFetchedAt["\(Self.availabilityKey(mediaType: mediaType, mediaId: mediaId))|\(audio)"] = Date()
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

    /// The active service registry (static reference data): read at most once per
    /// `streamingServiceRegistryTTL` once it has loaded.
    func fetchStreamingServiceRegistry() async {
        if let loadedAt = streamingServiceRegistryLoadedAt, !streamingServiceRegistry.isEmpty,
           Date().timeIntervalSince(loadedAt) < Self.streamingServiceRegistryTTL {
            return
        }
        do {
            let client = try requiredClient()
            let records: [StreamingServiceRecord] = try await client
                .from("streaming_services")
                .select(Self.streamingServiceColumns)
                .eq("is_active", value: true)
                .order("priority", ascending: true)
                .execute()
                .value
            streamingServiceRegistry = records
            streamingServiceRegistryLoadedAt = Date()
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
