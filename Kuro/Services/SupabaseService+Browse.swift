import Foundation

#if canImport(Supabase)
import Supabase

@MainActor
extension SupabaseService {
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
        minYear: Int? = nil,
        maxYear: Int? = nil,
        format: String? = nil,
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
                p_min_year: minYear,
                p_max_year: maxYear,
                p_format: format,
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
        minYear: Int? = nil,
        maxYear: Int? = nil,
        format: String? = nil,
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
                p_min_year: minYear,
                p_max_year: maxYear,
                p_format: format,
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
}
#endif
