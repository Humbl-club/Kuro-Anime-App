import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

extension SupabaseService {
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

}
#endif
