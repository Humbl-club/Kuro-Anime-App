import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Recommendations (read side)
// "More like this" on the detail pages. Primary (2026-11-03): `fetchSimilar(kind:id:limit:)` reads
// card rows in one call from the prepared `media_similar_v1` (a thin wrapper over
// `recommend_ids_similar_to_seeds`, the same precomputed `media_similar_titles` engine as Taste).
// While it is not deployed, the same ids come from `recommend_ids_similar_to_seeds` hydrated through
// the Catalog (detail cache first, batched by id, caller order preserved). Both exclude the
// CALLER's own list titles (auth.uid()), so answers are per account: the cache is keyed by account
// and cleared on every account transition (`AccountScopedState`).
// `fetchSimilarAnime(seed:)` / `fetchSimilarManga(seed:)` are the older two-step readers (kept).

/// One "More like this" title. A CARD projection: never present it as a detail model; open its
/// detail by `key` (`routes.openMedia(MediaRoute(item.key))`).
struct SimilarTitle: Identifiable {
    enum Model {
        case anime(Anime)
        case manga(Manga)
    }

    let model: Model
    /// 1-based position in the answer (the engine's order).
    let rank: Int

    var key: MediaKey {
        switch model {
        case .anime(let anime): return MediaKey(kind: .anime, id: anime.id)
        case .manga(let manga): return MediaKey(kind: .manga, id: manga.id)
        }
    }

    var id: String { "\(key.kind.rawValue)-\(key.id)" }

    /// Title, cover, year, format, episodes/chapters and score for the card.
    var display: any MediaDisplayable {
        switch model {
        case .anime(let anime): return anime
        case .manga(let manga): return manga
        }
    }

    var anime: Anime? { if case .anime(let anime) = model { return anime } else { return nil } }
    var manga: Manga? { if case .manga(let manga) = model { return manga } else { return nil } }
}

/// `media_similar_v1` arguments (top-level so the `Encodable` conformance is not main-actor isolated).
struct RPCMediaSimilarParams: Encodable, Sendable {
    let p_media_type: String // "ANIME" | "MANGA"
    let p_media_id: Int
    let p_limit: Int
}

@MainActor
@Observable
final class RecommendationsReader: AccountScopedState {
    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every read fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// Hydrates similar ids into full models through the public detail cache.
    let catalog: CatalogStore
    /// The account the similar answers are read for (the RPC excludes that account's list).
    private let accountSession: AccountSessionCoordinator?

    /// "More like this" answers keyed by account ("anon" signed out), kind, id and limit.
    @ObservationIgnored var similarCache: [String: TimedCache<[SimilarTitle]>] = [:]
    /// In-flight similar reads (joined only by the same key and account context).
    let similarLoads = AccountScopedLoads<String, [SimilarTitle]>()
    /// When `media_similar_v1` last answered "not deployed" (retried after `similarUndeployedRetry`).
    @ObservationIgnored var similarUndeployedAt: Date?

    nonisolated static let similarTTL: TimeInterval = 10 * 60
    nonisolated static let similarUndeployedRetry: TimeInterval = 30 * 60

    init(client: SupabaseClient?, catalog: CatalogStore, accountSession: AccountSessionCoordinator? = nil) {
        self.client = client
        self.catalog = catalog
        self.accountSession = accountSession
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        similarLoads.cancelAll()
    }

    func clearPrivateState() {
        similarCache.removeAll()
    }

    // MARK: - More like this (card rows, one call)

    /// Up to `limit` (1-30) titles like one anime or manga, in the engine's order, adult and
    /// coverless titles excluded, the caller's own list excluded. Empty when the engine knows none
    /// or every path failed (the rail hides). Cached 10 minutes per account.
    func fetchSimilar(kind: MediaKind, id: Int, limit: Int = 12) async -> [SimilarTitle] {
        let context = accountSession?.current
        let bounded = max(1, min(30, limit))
        let key = "\(context?.userId.lowercased() ?? "anon")|\(kind.rawValue)|\(id)|\(bounded)"
        if let cached = similarCache[key], Date().timeIntervalSince(cached.storedAt) < Self.similarTTL {
            return cached.value
        }
        let items = try? await similarLoads.run(key: key, context: context) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.loadSimilar(kind: kind, id: id, limit: bounded, context: context, key: key)
        }
        guard let items, accountSession?.isCurrent(context) ?? true else { return [] }
        return items
    }

    private func loadSimilar(kind: MediaKind, id: Int, limit: Int, context: AccountContext?,
                             key: String) async throws -> [SimilarTitle] {
        var cacheable = true
        if similarContractAvailable() {
            do {
                let items = try await readMediaSimilar(kind: kind, id: id, limit: limit)
                return try storeSimilar(items, key: key, context: context)
            } catch {
                switch ReleaseFailure.classify(error) {
                case .cancelled: throw CancellationError()
                case .notDeployed: similarUndeployedAt = Date()
                case .transient: cacheable = false
                }
                #if DEBUG
                print("[Recommendations] media_similar_v1 unavailable, using fallback: \(error)")
                #endif
            }
        }
        // Fallback: the same engine through the ids-only RPC, hydrated by the Catalog.
        let rows = await fetchSimilarIdsViaRPC(mediaType: kind == .anime ? "ANIME" : "MANGA", seedIds: [id],
                                               limit: limit, allowGimmicks: false)
        let ids = rows.map(\.mediaId).filter { $0 != id }
        let items: [SimilarTitle]
        switch kind {
        case .anime:
            let models = DiscoveryContentRules.sanitizeAnimeForDiscovery(await catalog.fetchAnimeByIdsPreservingOrder(ids) ?? [])
            items = Self.similarTitles(anime: models, limit: limit)
        case .manga:
            let models = DiscoveryContentRules.sanitizeMangaForDiscovery(await catalog.fetchMangaByIdsPreservingOrder(ids) ?? [])
            items = Self.similarTitles(manga: models, limit: limit)
        }
        guard cacheable else {
            guard accountSession?.isCurrent(context) ?? true else { throw CancellationError() }
            return items
        }
        return try storeSimilar(items, key: key, context: context)
    }

    private func readMediaSimilar(kind: MediaKind, id: Int, limit: Int) async throws -> [SimilarTitle] {
        guard let client else { throw MissingSupabaseConfiguration() }
        let params = RPCMediaSimilarParams(p_media_type: kind == .anime ? "ANIME" : "MANGA", p_media_id: id, p_limit: limit)
        let perf = KuroPerf.begin("rpc.media_similar_v1")
        defer { KuroPerf.end(perf, message: "done") }
        switch kind {
        case .anime:
            let rows: [Anime] = try await client.rpc("media_similar_v1", params: params).execute().value
            return Self.similarTitles(anime: DiscoveryContentRules.sanitizeAnimeForDiscovery(rows.filter { $0.id != id }), limit: limit)
        case .manga:
            let rows: [Manga] = try await client.rpc("media_similar_v1", params: params).execute().value
            return Self.similarTitles(manga: DiscoveryContentRules.sanitizeMangaForDiscovery(rows.filter { $0.id != id }), limit: limit)
        }
    }

    static func similarTitles(anime: [Anime], limit: Int) -> [SimilarTitle] {
        anime.prefix(limit).enumerated().map { SimilarTitle(model: .anime($0.element), rank: $0.offset + 1) }
    }

    static func similarTitles(manga: [Manga], limit: Int) -> [SimilarTitle] {
        manga.prefix(limit).enumerated().map { SimilarTitle(model: .manga($0.element), rank: $0.offset + 1) }
    }

    /// Caches and returns `items` while `context` is still the current account.
    private func storeSimilar(_ items: [SimilarTitle], key: String, context: AccountContext?) throws -> [SimilarTitle] {
        guard accountSession?.isCurrent(context) ?? true else { throw CancellationError() }
        similarCache[key] = TimedCache(value: items, storedAt: Date())
        trimTimedCache(&similarCache, maxEntries: 60)
        return items
    }

    private func similarContractAvailable(now: Date = Date()) -> Bool {
        guard let at = similarUndeployedAt else { return true }
        if now.timeIntervalSince(at) < Self.similarUndeployedRetry { return false }
        similarUndeployedAt = nil
        return true
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    /// Minimal "More like this" fetcher for detail pages (Swiss minimal: deterministic, no LLM).
    /// Primary path uses the DB similarity RPC (tag overlap + editorial boosts/penalties).
    /// Falls back to a lightweight genre anchor if the RPC isn't available.
    func fetchSimilarAnime(seed: Anime, limit: Int = 14) async -> [Anime] {
        let rpc = await fetchSimilarIdsViaRPC(mediaType: "ANIME", seedIds: [seed.id], limit: limit, allowGimmicks: false)
        if !rpc.isEmpty, let items = await catalog.fetchAnimeByIdsPreservingOrder(rpc.map(\.mediaId)) {
            return DiscoveryContentRules.sanitizeAnimeForDiscovery(items)
        }
        return await fetchSimilarAnimeFallbackByGenre(seed: seed, limit: limit)
    }

    func fetchSimilarManga(seed: Manga, limit: Int = 14) async -> [Manga] {
        let rpc = await fetchSimilarIdsViaRPC(mediaType: "MANGA", seedIds: [seed.id], limit: limit, allowGimmicks: false)
        if !rpc.isEmpty, let items = await catalog.fetchMangaByIdsPreservingOrder(rpc.map(\.mediaId)) {
            return DiscoveryContentRules.sanitizeMangaForDiscovery(items)
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
        let perf = KuroPerf.begin("rpc.recommend_ids_similar_to_seeds")
        do {
            let client = try requiredClient()
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

    private func fetchSimilarAnimeFallbackByGenre(seed: Anime, limit: Int) async -> [Anime] {
        guard let primaryGenre = seed.genreList?.first, !primaryGenre.isEmpty else { return [] }
        do {
            let client = try requiredClient()
            let rows: [Anime] = try await client
                .from("anime")
                .select(CatalogColumns.select(CatalogColumns.animeCard))
                .eq("is_adult", value: false)
                .contains("genres", value: [primaryGenre])
                .neq("id", value: seed.id)
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return DiscoveryContentRules.sanitizeAnimeForDiscovery(rows)
        } catch {
            return []
        }
    }

    private func fetchSimilarMangaFallbackByGenre(seed: Manga, limit: Int) async -> [Manga] {
        guard let primaryGenre = seed.genreList?.first, !primaryGenre.isEmpty else { return [] }
        do {
            let client = try requiredClient()
            let rows: [Manga] = try await client
                .from("manga")
                .select(CatalogColumns.select(CatalogColumns.mangaCard))
                .eq("is_adult", value: false)
                .contains("genres", value: [primaryGenre])
                .neq("id", value: seed.id)
                .order("favourites", ascending: false)
                .order("average_score", ascending: false)
                .order("popularity", ascending: false)
                .range(from: 0, to: max(0, limit - 1))
                .execute()
                .value
            return DiscoveryContentRules.sanitizeMangaForDiscovery(rows)
        } catch {
            return []
        }
    }
}
#endif
