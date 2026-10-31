import Foundation
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Recommendations (read side, public data)
// "More like this" on the detail pages: similar ids from the similarity RPC, hydrated through the
// Catalog (detail cache first, batched by id, caller order preserved), then the discovery content
// rules. Public data: nothing here is account-scoped. Taste / personalised recommendation is not
// part of this reader.

@MainActor
@Observable
final class RecommendationsReader {
    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every read fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// Hydrates similar ids into full models through the public detail cache.
    let catalog: CatalogStore

    init(client: SupabaseClient?, catalog: CatalogStore) {
        self.client = client
        self.catalog = catalog
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
            return DiscoveryContentRules.sanitizeMangaForDiscovery(rows)
        } catch {
            return []
        }
    }
}
#endif
