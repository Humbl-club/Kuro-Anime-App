import Foundation
import KuroCore
import KuroLibrary

#if canImport(Supabase)
import Supabase

// MARK: - Discover usability reads (2026-11-04)
// Franchise identity (R2), the mood journeys (build item 4) and the See all pages (build item 5).
// Contracts and pure rules: `DiscoverUsabilityModels.swift`.
//
// Prepared readers first, silent fallback while they are not deployed: a "not deployed" answer
// (PGRST202/203/205, 42883, 42P01, HTTP 404, an unreadable payload: `ReleaseFailure.classify`) is
// remembered per contract for `discoverUndeployedRetryInterval` and the live path answers instead:
//   media_franchise_ids_v1    -> no component ids; `franchiseKeys` keeps the title-stem rule
//   discover_section_page_v1  -> trending / top rated / just added: live Browse keyset pages in the
//                                section's order (sort popular / top rated / section order, every
//                                filter); every other section, and `newest`: the caller's loaded rows
//                                sorted and filtered on the device (`DiscoverPage.Origin.local`)
//   discover_mood_v1          -> short: Browse FINISHED with 1-13 episodes / 1-50 chapters;
//                                cozy / intense: Browse by one genre (`DiscoverMood.fallbackGenre`);
//                                like_last_loved: `recommend_ids_similar_to_seeds` from the Library's
//                                latest COMPLETED title (rated 8+ first), hydrated by id
// A transient failure (offline, 5xx) answers nil: the journey shows its offline / failed state.
//
// Every page is per account (the server hides the caller's owned and answered titles; fallback
// pages do not): pages are not cached, a page read for an account that is no longer current is not
// handed out (nil), and callers ALWAYS pass pages through `DiscoverPageAccumulator` with the
// caller's hidden set (`TasteStore.discoverHidden`) and the Library, which applies the same rules
// to both origins.

@MainActor
extension DiscoveryStore {
    /// How long a "not deployed" answer suppresses calls to that prepared reader.
    nonisolated static let discoverUndeployedRetryInterval: TimeInterval = 30 * 60
    /// Largest id batch `media_franchise_ids_v1` accepts per medium.
    nonisolated static let franchiseBatchLimit = 300

    nonisolated enum DiscoverContract: String, CaseIterable {
        case franchiseIds = "media_franchise_ids_v1"
        case sectionPage = "discover_section_page_v1"
        case mood = "discover_mood_v1"
    }

    // MARK: Franchise identity (R2)

    /// The franchise key of a title: its server component when read (the catalogue's relations are
    /// the truth: two Gundam series without a relation stay two franchises), otherwise its title
    /// stem (before `loadFranchiseIds` answered, or while the reader is not deployed), otherwise
    /// the title itself. `loadFranchiseIds` answers every requested key (singletons label as
    /// themselves), so after one load a page's titles all compare by component.
    func franchiseKeys(for key: MediaKey, title: String, serverFranchiseId: Int? = nil) -> Set<DiscoverFranchiseKey> {
        if let component = serverFranchiseId ?? franchiseIds[key] {
            return [.component(key.kind, component)]
        }
        if let stem = DiscoverFranchiseStem.stem(title) {
            return [.stem(key.kind, stem)]
        }
        return [.component(key.kind, key.id)]
    }

    /// Franchise keys of a journey card (its row's component wins over the session map).
    func franchiseKeys(for item: DiscoverPageItem) -> Set<DiscoverFranchiseKey> {
        franchiseKeys(for: item.key, title: item.card.title, serverFranchiseId: item.franchiseId)
    }

    /// Reads the franchise components of the titles not read yet (one request per 300 ids and
    /// medium). Public data. Silent while the reader is not deployed: the stem rule still dedupes.
    func loadFranchiseIds(for keys: [MediaKey]) async {
        let wanted = Array(Set(keys.filter { franchiseIds[$0] == nil }))
        guard !wanted.isEmpty, discoverContractAvailable(.franchiseIds) else { return }
        let anime = wanted.filter { $0.kind == .anime }.map(\.id).sorted()
        let manga = wanted.filter { $0.kind == .manga }.map(\.id).sorted()
        let batches = max(anime.count, manga.count) / Self.franchiseBatchLimit + 1
        for batch in 0..<batches {
            let range = (batch * Self.franchiseBatchLimit)..<((batch + 1) * Self.franchiseBatchLimit)
            let animeIds = Array(anime[min(range.lowerBound, anime.count)..<min(range.upperBound, anime.count)])
            let mangaIds = Array(manga[min(range.lowerBound, manga.count)..<min(range.upperBound, manga.count)])
            guard !animeIds.isEmpty || !mangaIds.isEmpty else { continue }
            do {
                let client = try requiredDiscoverClient()
                let rows: LenientRows<DiscoverFranchiseRow> = try await client
                    .rpc(DiscoverContract.franchiseIds.rawValue,
                         params: RPCMediaFranchiseIdsParams(p_anime_ids: animeIds, p_manga_ids: mangaIds))
                    .execute()
                    .value
                for row in rows.rows {
                    if let key = row.key { franchiseIds[key] = row.franchiseId }
                }
            } catch {
                noteDiscoverFailure(.franchiseIds, error)
                return
            }
        }
    }

    /// R2 for the whole Discover page with this store's franchise map and the injected Library:
    /// hidden titles out, the owned rule per section, one title per franchise (first wins).
    func placeSections<Item: MediaDisplayable>(
        _ sections: [DiscoverSectionInput<Item>],
        hidden: Set<MediaKey>
    ) -> [DiscoverPlacedSection<Item>] {
        DiscoverPageComposer.compose(
            sections,
            key: { MediaKey(kind: $0.kind, id: $0.id) },
            franchiseKeys: { self.franchiseKeys(for: MediaKey(kind: $0.kind, id: $0.id), title: $0.title) },
            isHidden: { hidden.contains($0) },
            ownedStatus: { self.library.entry(for: $0)?.status }
        )
    }

    /// Appends a journey page with this store's franchise map and the Library (see
    /// `DiscoverPageAccumulator`).
    func accumulate(_ page: DiscoverPage, into accumulator: inout DiscoverPageAccumulator, hidden: Set<MediaKey>) {
        accumulator.append(
            page,
            franchiseKeys: { self.franchiseKeys(for: $0) },
            isHidden: { hidden.contains($0) },
            ownedStatus: { self.library.entry(for: $0)?.status }
        )
    }

    // MARK: Mood journeys

    /// One page of a mood journey; nil when the read failed (offline, server error) or the account
    /// changed meanwhile. Pass the returned `next` to continue; nil `next` ends the journey.
    func moodPage(_ mood: DiscoverMood, medium: MediaKind, cursor: DiscoverPageCursor? = nil,
                  limit: Int = 24) async -> DiscoverPage? {
        let context = accountSession.current
        let limit = max(1, min(60, limit))
        if discoverContractAvailable(.mood), cursor == nil || cursor.map(Self.isOffsetCursor) == true {
            let offset = cursor.flatMap(Self.offset) ?? 0
            do {
                let client = try requiredDiscoverClient()
                let rows: [DiscoverPageRow] = try await client
                    .rpc(DiscoverContract.mood.rawValue, params: RPCDiscoverMoodParams(
                        p_mood: mood.rawValue, p_media_type: Self.mediumWord(medium), p_limit: limit, p_offset: offset))
                    .execute()
                    .value
                guard accountSession.isCurrent(context) else { return nil }
                return Self.serverPage(rows, offset: offset, limit: limit)
            } catch {
                guard noteDiscoverFailure(.mood, error) == .notDeployed else { return nil }
            }
        }
        let page = await moodFallbackPage(mood, medium: medium, cursor: cursor, limit: limit)
        guard accountSession.isCurrent(context) else { return nil }
        return page
    }

    private func moodFallbackPage(_ mood: DiscoverMood, medium: MediaKind, cursor: DiscoverPageCursor?,
                                  limit: Int) async -> DiscoverPage? {
        switch mood {
        case .short:
            return await browseFallback(
                medium: medium, sort: .popular, genre: nil, status: DiscoverStatusFilter.finished.catalogStatus,
                length: .short, format: nil, cursor: cursor, limit: limit)
        case .cozy, .intense:
            return await browseFallback(
                medium: medium, sort: .popular, genre: mood.fallbackGenre, status: nil,
                length: nil, format: nil, cursor: cursor, limit: limit)
        case .likeLastLoved:
            return await likeLastLovedFallback(medium: medium, cursor: cursor, limit: limit)
        }
    }

    /// The Library's latest COMPLETED title of `medium`, rated 8+ first (the server's seed rule
    /// without its deck-love step, which needs the caller's deck events).
    func likeLastLovedSeed(medium: MediaKind) -> MediaKey? {
        library.allEntries
            .filter { $0.key.kind == medium && $0.status == .completed }
            .sorted { lhs, rhs in
                let l = (lhs.rating?.value ?? 0) >= 8, r = (rhs.rating?.value ?? 0) >= 8
                if l != r { return l }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.key.id > rhs.key.id
            }
            .first?.key
    }

    private func likeLastLovedFallback(medium: MediaKind, cursor: DiscoverPageCursor?, limit: Int) async -> DiscoverPage? {
        guard let seed = likeLastLovedSeed(medium: medium) else {
            return DiscoverPage(items: [], next: nil, reason: nil, origin: .fallback)
        }
        let offset = cursor.flatMap(Self.offset) ?? 0
        do {
            let client = try requiredDiscoverClient()
            let ranked: [SimilarIdRow] = try await client
                .rpc("recommend_ids_similar_to_seeds", params: RPCRecommendSimilarParams(
                    p_media_type: Self.mediumWord(medium), p_seed_ids: [seed.id], p_limit: 60, p_allow_gimmicks: false))
                .execute()
                .value
            let ids = ranked.map(\.mediaId).filter { $0 != seed.id }
            let pageIds = Array(ids.dropFirst(offset).prefix(limit))
            let titles = try await hydrateCards(medium: medium, ids: pageIds + [seed.id])
            let byId = Dictionary(titles.map { ($0.key.id, $0) }, uniquingKeysWith: { first, _ in first })
            let items = pageIds.compactMap { byId[$0] }.map {
                DiscoverPageItem(card: $0, franchiseId: nil, serverListStatus: nil)
            }
            let reason = byId[seed.id].map { DiscoverReason(key: seed, title: $0.title) }
            let consumed = offset + pageIds.count
            return DiscoverPage(items: items, next: consumed < ids.count ? .offset(consumed) : nil,
                                reason: reason, origin: .fallback)
        } catch {
            #if DEBUG
            print("❌ like_last_loved fallback: \(error)")
            #endif
            return nil
        }
    }

    // MARK: See all

    /// One page of a section's See all journey; nil when the read failed or the account changed.
    /// `loadedRows` are the section's rows already on the page (the local fallback of sections the
    /// live catalogue cannot page, and of `newest` while the prepared reader is not deployed).
    func seeAllPage(_ query: DiscoverSeeAllQuery, cursor: DiscoverPageCursor? = nil, limit: Int = 24,
                    loadedRows: [DiscoverCardValue] = []) async -> DiscoverPage? {
        let context = accountSession.current
        let limit = max(1, min(60, limit))
        if query.section.isServerPaged(for: query.medium), discoverContractAvailable(.sectionPage),
           cursor == nil || cursor.map(Self.isOffsetCursor) == true {
            let offset = cursor.flatMap(Self.offset) ?? 0
            do {
                let client = try requiredDiscoverClient()
                let rows: [DiscoverPageRow] = try await client
                    .rpc(DiscoverContract.sectionPage.rawValue, params: RPCDiscoverSectionPageParams(
                        p_section: query.section.rawValue,
                        p_media_type: Self.mediumWord(query.medium),
                        p_sort: query.sort.rawValue,
                        p_format: query.format?.uppercased(),
                        p_length: query.length?.rawValue,
                        p_status: query.status?.rawValue,
                        p_limit: limit,
                        p_offset: offset))
                    .execute()
                    .value
                guard accountSession.isCurrent(context) else { return nil }
                return Self.serverPage(rows, offset: offset, limit: limit)
            } catch {
                guard noteDiscoverFailure(.sectionPage, error) == .notDeployed else { return nil }
            }
        }
        if let order = Self.browseFallbackOrder(query.section), query.sort != .newest {
            let sort: BrowseSort
            switch query.sort {
            case .sectionOrder: sort = order
            case .popular: sort = .popular
            case .topRated: sort = .topRated
            case .newest: sort = order
            }
            let page = await browseFallback(
                medium: query.medium, sort: sort, genre: nil, status: query.status?.catalogStatus,
                length: query.length, format: query.format, cursor: cursor, limit: limit)
            guard accountSession.isCurrent(context) else { return nil }
            return page
        }
        let cards = DiscoverLocalPage.page(loadedRows, query: query)
        return DiscoverPage(items: cards.map { DiscoverPageItem(card: $0, franchiseId: nil, serverListStatus: nil) },
                            next: nil, reason: nil, origin: .local)
    }

    /// The live Browse order that reproduces a section's own order while the prepared reader is not
    /// deployed (nil: the section falls back to its loaded rows).
    nonisolated static func browseFallbackOrder(_ section: DiscoverSectionKey) -> BrowseSort? {
        switch section {
        case .trending: return .trending
        case .topRated: return .topRated
        case .newlyAdded: return .newlyAdded
        default: return nil
        }
    }

    // MARK: Shared fallback reads

    private func browseFallback(medium: MediaKind, sort: BrowseSort, genre: String?, status: String?,
                                length: DiscoverLengthFilter?, format: String?, cursor: DiscoverPageCursor?,
                                limit: Int) async -> DiscoverPage? {
        var cursorInt: Int?
        var cursorDate: Date?
        var cursorId: Int?
        if case .browse(let int, let date, let id)? = cursor {
            cursorInt = int
            cursorDate = date
            cursorId = id
        }
        switch medium {
        case .anime:
            let range = length?.episodeRange
            guard let rows = await browseAnimePage(
                genre: genre, status: status, minEpisodes: range?.min, maxEpisodes: range?.max, sort: sort,
                cursorInt: cursorInt, cursorDate: cursorDate, cursorId: cursorId, format: format?.uppercased(),
                limit: limit) else { return nil }
            let next: DiscoverPageCursor? = rows.count < limit ? nil : rows.last.map {
                Self.browseCursor(sort: sort, int: Self.sortValue(sort, popularity: $0.popularity, trending: $0.trending,
                                                                  score: $0.averageScore),
                                  date: $0.createdAt, id: $0.id)
            }
            return DiscoverPage(items: rows.map { DiscoverPageItem(card: .anime($0), franchiseId: nil, serverListStatus: nil) },
                                next: next, reason: nil, origin: .fallback)
        case .manga:
            let range = length?.chapterRange
            guard let rows = await browseMangaPage(
                genre: genre, status: status, minChapters: range?.min, maxChapters: range?.max, sort: sort,
                cursorInt: cursorInt, cursorDate: cursorDate, cursorId: cursorId, format: format?.uppercased(),
                limit: limit) else { return nil }
            let next: DiscoverPageCursor? = rows.count < limit ? nil : rows.last.map {
                Self.browseCursor(sort: sort, int: Self.sortValue(sort, popularity: $0.popularity, trending: $0.trending,
                                                                  score: $0.averageScore),
                                  date: $0.createdAt, id: $0.id)
            }
            return DiscoverPage(items: rows.map { DiscoverPageItem(card: .manga($0), franchiseId: nil, serverListStatus: nil) },
                                next: next, reason: nil, origin: .fallback)
        }
    }

    nonisolated static func sortValue(_ sort: BrowseSort, popularity: Int?, trending: Int?, score: Int?) -> Int {
        switch sort {
        case .trending: return trending ?? 0
        case .topRated: return score ?? 0
        case .popular, .newlyAdded: return popularity ?? 0
        }
    }

    nonisolated static func browseCursor(sort: BrowseSort, int: Int, date: Date?, id: Int) -> DiscoverPageCursor {
        sort == .newlyAdded ? .browse(cursorInt: nil, cursorDate: date, cursorId: id)
                            : .browse(cursorInt: int, cursorDate: nil, cursorId: id)
    }

    private struct SimilarIdRow: Decodable {
        let mediaId: Int
        enum CodingKeys: String, CodingKey { case mediaId = "media_id" }
    }

    /// Card rows by id (public tables; adult titles left out), in no particular order.
    private func hydrateCards(medium: MediaKind, ids: [Int]) async throws -> [DiscoverCardValue] {
        guard !ids.isEmpty else { return [] }
        let client = try requiredDiscoverClient()
        switch medium {
        case .anime:
            let rows: [AnimeCard] = try await client.from("anime")
                .select("id,title_english,title_romaji,title_native,cover_image_large,cover_image_medium,banner_image,format,status,episode_count:episodes,season_year,start_date_year,average_score,popularity,trending,favourites,genres,created_at")
                .in("id", values: ids)
                .eq("is_adult", value: false)
                .execute()
                .value
            return rows.map(DiscoverCardValue.anime)
        case .manga:
            let rows: [MangaCard] = try await client.from("manga")
                .select("id,title_english,title_romaji,title_native,cover_image_large,cover_image_medium,format,status,chapter_count:chapters,start_date_year,average_score,popularity,trending,favourites,genres,created_at")
                .in("id", values: ids)
                .eq("is_adult", value: false)
                .execute()
                .value
            return rows.map(DiscoverCardValue.manga)
        }
    }

    // MARK: Contract state

    func discoverContractAvailable(_ contract: DiscoverContract, now: Date = Date()) -> Bool {
        guard let at = undeployedDiscoverContracts[contract.rawValue] else { return true }
        if now.timeIntervalSince(at) < Self.discoverUndeployedRetryInterval { return false }
        undeployedDiscoverContracts[contract.rawValue] = nil
        return true
    }

    /// Classifies a prepared-reader failure and remembers a "not deployed" answer.
    @discardableResult
    func noteDiscoverFailure(_ contract: DiscoverContract, _ error: any Error, now: Date = Date()) -> ReleaseFailure {
        let failure = ReleaseFailure.classify(error)
        if failure == .notDeployed { undeployedDiscoverContracts[contract.rawValue] = now }
        #if DEBUG
        print("❌ \(contract.rawValue): \(failure) \(error)")
        #endif
        return failure
    }

    private func requiredDiscoverClient() throws -> SupabaseClient {
        try requiredClient()
    }

    // MARK: Helpers

    nonisolated static func mediumWord(_ medium: MediaKind) -> String { medium == .manga ? "MANGA" : "ANIME" }

    /// Rows each server page re-reads from the previous one (at most 8, a third of the page).
    nonisolated static func pageOverlap(limit: Int) -> Int { min(8, max(0, limit / 3)) }

    nonisolated static func isOffsetCursor(_ cursor: DiscoverPageCursor) -> Bool {
        if case .offset = cursor { return true }
        return false
    }

    nonisolated static func offset(_ cursor: DiscoverPageCursor) -> Int? {
        if case .offset(let value) = cursor { return value }
        return nil
    }

    /// A server page: rows in rank order; a full page continues `pageOverlap(limit:)` rows before
    /// its last rank. The server filters on mutable per-account state (answered and owned titles)
    /// BEFORE the offset, so every title hidden or planned during a journey shifts the pool by one;
    /// the overlap re-reads the boundary and `DiscoverPageAccumulator` drops the repeats, so no title
    /// is skipped for up to that many changes per page.
    static func serverPage(_ rows: [DiscoverPageRow], offset: Int, limit: Int) -> DiscoverPage {
        let ordered = rows.sorted { $0.rank < $1.rank }
        let items = ordered.compactMap(\.item)
        let last = ordered.last?.rank ?? offset
        let next: DiscoverPageCursor? = rows.count < limit || last >= 440
            ? nil : .offset(max(offset + 1, last - pageOverlap(limit: limit)))
        return DiscoverPage(items: items, next: next, reason: ordered.lazy.compactMap(\.reason).first, origin: .server)
    }
}
#endif
