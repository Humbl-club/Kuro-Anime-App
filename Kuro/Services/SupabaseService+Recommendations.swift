import Foundation

#if canImport(Supabase)
import Supabase

@MainActor
extension SupabaseService {
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

        var resultsById: [Int: Anime] = [:]
        resultsById.reserveCapacity(ids.count)

        for id in ids {
            if let cached = animeDetailCache[id] {
                resultsById[id] = cached
            }
        }

        let missing = ids.filter { resultsById[$0] == nil }
        if !missing.isEmpty {
            for start in stride(from: 0, to: missing.count, by: 100) {
                let end = min(start + 100, missing.count)
                let chunk = Array(missing[start..<end])
                do {
                    let rows: [Anime] = try await client
                        .from("anime")
                        .select()
                        .in("id", values: chunk)
                        .execute()
                        .value
                    for row in rows {
                        resultsById[row.id] = row
                        animeDetailCache[row.id] = row
                    }
                } catch {
                    #if DEBUG
                    print("❌ anime batch detail fetch: \(error)")
                    #endif
                }
            }

            let unresolved = missing.filter { resultsById[$0] == nil }
            if !unresolved.isEmpty {
                await withTaskGroup(of: Anime?.self) { group in
                    for id in unresolved {
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
            for start in stride(from: 0, to: missing.count, by: 100) {
                let end = min(start + 100, missing.count)
                let chunk = Array(missing[start..<end])
                do {
                    let rows: [Manga] = try await client
                        .from("manga")
                        .select()
                        .in("id", values: chunk)
                        .execute()
                        .value
                    for row in rows {
                        resultsById[row.id] = row
                        mangaDetailCache[row.id] = row
                    }
                } catch {
                    #if DEBUG
                    print("❌ manga batch detail fetch: \(error)")
                    #endif
                }
            }

            let unresolved = missing.filter { resultsById[$0] == nil }
            if !unresolved.isEmpty {
                await withTaskGroup(of: Manga?.self) { group in
                    for id in unresolved {
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
}
#endif
