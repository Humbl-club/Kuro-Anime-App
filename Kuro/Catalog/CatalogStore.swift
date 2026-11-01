import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Catalog (public data)
// Owner of the public catalog reads: full detail models, credits, works by entity, the adaptation
// ladder and relation refresh requests, external links, episodes/chapters and per-title tags.
// Public data is not account-scoped: none of these caches is cleared by sign-out or an account
// switch (contracts §2); only memory pressure trims them. Anime and manga with the same numeric id
// never share a cache entry (separate caches per kind; ladder keys carry the media type).

@MainActor
@Observable
final class CatalogStore: MemoryPressureTrimmable {
    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every read fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    // Detail caches: cards/grids only carry minimal fields; we fetch full details by id on demand.
    var animeDetailCache: [Int: Anime] = [:]
    var mangaDetailCache: [Int: Manga] = [:]

    // Entity inline caches (keyed by media ID, cap 100 each)
    var animeCharactersCache: [Int: [(character: Character, role: String)]] = [:]
    var animeStaffCache: [Int: [(staff: Staff, role: String)]] = [:]
    var animeStudiosCache: [Int: [Studio]] = [:]
    var mangaCharactersCache: [Int: [(character: Character, role: String)]] = [:]
    var mangaAuthorsCache: [Int: [(author: Author, role: String)]] = [:]

    // Entity sheet caches (keyed by entity ID, TTL 120s)
    var studioWorksCache: [String: TimedCache<[Media]>] = [:]
    var staffWorksCache: [String: TimedCache<[(media: Media, role: String)]>] = [:]
    var authorWorksCache: [String: TimedCache<[(media: Media, role: String)]>] = [:]
    var characterWorksCache: [String: TimedCache<[Media]>] = [:]
    var mediaLadderCache: [String: TimedCache<MediaLadderResponse>] = [:]
    var mediaLadderRefreshEnqueueCooldown: [String: Date] = [:]

    // Card-projection rows ("More like this" hydration). Kept apart from the detail caches: a card
    // row lacks the synopsis, banner and credits fields, so it must never be served as a detail model
    // (similar cards open their detail by id through `fetchAnimeById` / `fetchMangaById`).
    @ObservationIgnored private var animeCardCache: [Int: Anime] = [:]
    @ObservationIgnored private var mangaCardCache: [Int: Manga] = [:]

    // External links per media ("ANIME-42"), TTL `externalLinksTTL`; only successful reads are kept.
    @ObservationIgnored private var externalLinksCache: [String: TimedCache<[ExternalLink]>] = [:]
    // Stream link of one episode ("42#4"; a nil value = the episode has no stream link), TTL
    // `externalLinksTTL`; only successful reads are kept.
    @ObservationIgnored private var episodeStreamLinkCache: [String: TimedCache<EpisodeStreamLink?>] = [:]
    nonisolated static let externalLinksTTL: TimeInterval = 10 * 60

    // In-flight public loads: a concurrent duplicate read joins the running request instead of
    // issuing its own. Public data is not account-scoped, so these run with a nil context and are
    // never cancelled by an account transition.
    private let animeDetailLoads = AccountScopedLoads<Int, Anime?>()
    private let mangaDetailLoads = AccountScopedLoads<Int, Manga?>()
    private let animeCharactersLoads = AccountScopedLoads<Int, [(character: Character, role: String)]>()
    private let animeStaffLoads = AccountScopedLoads<Int, [(staff: Staff, role: String)]>()
    private let animeStudiosLoads = AccountScopedLoads<Int, [Studio]>()
    private let mangaCharactersLoads = AccountScopedLoads<Int, [(character: Character, role: String)]>()
    private let mangaAuthorsLoads = AccountScopedLoads<Int, [(author: Author, role: String)]>()
    private let mediaLadderLoads = AccountScopedLoads<String, MediaLadderResponse>()
    private let externalLinksLoads = AccountScopedLoads<String, [ExternalLink]>()
    private let studioWorksLoads = AccountScopedLoads<String, [Media]>()
    private let staffWorksLoads = AccountScopedLoads<String, [(media: Media, role: String)]>()
    private let authorWorksLoads = AccountScopedLoads<String, [(media: Media, role: String)]>()
    private let characterWorksLoads = AccountScopedLoads<String, [Media]>()

    /// Sheds the entity, ladder, link and detail caches under memory pressure.
    func trimCachesForMemoryPressure() {
        animeCardCache.removeAll()
        mangaCardCache.removeAll()
        externalLinksCache.removeAll()
        episodeStreamLinkCache.removeAll()
        animeCharactersCache.removeAll()
        animeStaffCache.removeAll()
        animeStudiosCache.removeAll()
        mangaCharactersCache.removeAll()
        mangaAuthorsCache.removeAll()
        studioWorksCache.removeAll()
        staffWorksCache.removeAll()
        authorWorksCache.removeAll()
        characterWorksCache.removeAll()
        mediaLadderCache.removeAll()
        mediaLadderRefreshEnqueueCooldown.removeAll()
        animeDetailCache.removeAll()
        mangaDetailCache.removeAll()
    }

    // MARK: - Detail fetch by id (full models)

    func fetchAnimeById(_ animeId: Int) async throws -> Anime? {
        if let cached = animeDetailCache[animeId] { return cached }
        return try await animeDetailLoads.run(key: animeId, context: nil) { [weak self] in
            guard let self else { return nil }
            return try await self.loadAnimeById(animeId)
        }
    }

    private func loadAnimeById(_ animeId: Int) async throws -> Anime? {
        let diskFallback: Anime? = await KuroDiskDetailCache.read(kind: .anime, id: animeId, as: Anime.self)
        let perf = KuroPerf.begin("db.anime_by_id")
        do {
            let client = try requiredClient()
            let rows: [Anime] = try await client
                .from("anime")
                .select(CatalogColumns.select(CatalogColumns.animeDetail))
                .eq("id", value: animeId)
                .limit(1)
                .execute()
                .value
            let item = rows.first
            if let item {
                animeDetailCache[animeId] = item
                // Keep cache bounded.
                if animeDetailCache.count > 200, let k = animeDetailCache.keys.first {
                    animeDetailCache.removeValue(forKey: k)
                }
                Task { await KuroDiskDetailCache.write(kind: .anime, id: animeId, value: item) }
            }
            KuroPerf.end(perf, message: item == nil ? "missing" : "ok")
            return item
        } catch {
            if let diskFallback {
                #if DEBUG
                print("⚠️ anime_by_id network error, using disk fallback: \(error)")
                #endif
                animeDetailCache[animeId] = diskFallback
                KuroPerf.end(perf, message: "disk_fallback")
                return diskFallback
            }
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    func fetchMangaById(_ mangaId: Int) async throws -> Manga? {
        if let cached = mangaDetailCache[mangaId] { return cached }
        return try await mangaDetailLoads.run(key: mangaId, context: nil) { [weak self] in
            guard let self else { return nil }
            return try await self.loadMangaById(mangaId)
        }
    }

    private func loadMangaById(_ mangaId: Int) async throws -> Manga? {
        let diskFallback: Manga? = await KuroDiskDetailCache.read(kind: .manga, id: mangaId, as: Manga.self)
        let perf = KuroPerf.begin("db.manga_by_id")
        do {
            let client = try requiredClient()
            let rows: [Manga] = try await client
                .from("manga")
                .select(CatalogColumns.select(CatalogColumns.mangaDetail))
                .eq("id", value: mangaId)
                .limit(1)
                .execute()
                .value
            let item = rows.first
            if let item {
                mangaDetailCache[mangaId] = item
                if mangaDetailCache.count > 200, let k = mangaDetailCache.keys.first {
                    mangaDetailCache.removeValue(forKey: k)
                }
                Task { await KuroDiskDetailCache.write(kind: .manga, id: mangaId, value: item) }
            }
            KuroPerf.end(perf, message: item == nil ? "missing" : "ok")
            return item
        } catch {
            if let diskFallback {
                #if DEBUG
                print("⚠️ manga_by_id network error, using disk fallback: \(error)")
                #endif
                mangaDetailCache[mangaId] = diskFallback
                KuroPerf.end(perf, message: "disk_fallback")
                return diskFallback
            }
            KuroPerf.end(perf, message: "error")
            throw error
        }
    }

    // MARK: - Batched card fetch (ids in caller order; detail cache, then card cache, then one batch)
    // "More like this" hydration. Missing ids are read in batches of 100 with the card projection
    // (`CatalogColumns.animeCard` / `.mangaCard`) and kept in the card caches, never in the detail
    // caches. An id the batch did not return is missing or adult-filtered on the server, so it is
    // not retried one by one (that was an N+1: one request per unresolved id on every load).

    func fetchAnimeByIdsPreservingOrder(_ ids: [Int]) async -> [Anime]? {
        if ids.isEmpty { return [] }

        var resultsById: [Int: Anime] = [:]
        resultsById.reserveCapacity(ids.count)
        for id in ids {
            if let cached = animeDetailCache[id] ?? animeCardCache[id] {
                resultsById[id] = cached
            }
        }

        let missing = Self.uniqueMissingIds(ids, resolved: Set(resultsById.keys))
        for chunk in Self.batchChunks(missing) {
            do {
                let client = try requiredClient()
                let rows: [Anime] = try await client
                    .from("anime")
                    .select(CatalogColumns.select(CatalogColumns.animeCard))
                    .in("id", values: chunk)
                    .execute()
                    .value
                for row in rows {
                    resultsById[row.id] = row
                    animeCardCache[row.id] = row
                }
                if animeCardCache.count > Self.cardCacheLimit {
                    for key in animeCardCache.keys.prefix(animeCardCache.count - Self.cardCacheLimit) {
                        animeCardCache.removeValue(forKey: key)
                    }
                }
            } catch {
                #if DEBUG
                print("❌ anime batch card fetch: \(error)")
                #endif
            }
        }

        let ordered = ids.compactMap { resultsById[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    func fetchMangaByIdsPreservingOrder(_ ids: [Int]) async -> [Manga]? {
        if ids.isEmpty { return [] }

        var resultsById: [Int: Manga] = [:]
        resultsById.reserveCapacity(ids.count)
        for id in ids {
            if let cached = mangaDetailCache[id] ?? mangaCardCache[id] {
                resultsById[id] = cached
            }
        }

        let missing = Self.uniqueMissingIds(ids, resolved: Set(resultsById.keys))
        for chunk in Self.batchChunks(missing) {
            do {
                let client = try requiredClient()
                let rows: [Manga] = try await client
                    .from("manga")
                    .select(CatalogColumns.select(CatalogColumns.mangaCard))
                    .in("id", values: chunk)
                    .execute()
                    .value
                for row in rows {
                    resultsById[row.id] = row
                    mangaCardCache[row.id] = row
                }
                if mangaCardCache.count > Self.cardCacheLimit {
                    for key in mangaCardCache.keys.prefix(mangaCardCache.count - Self.cardCacheLimit) {
                        mangaCardCache.removeValue(forKey: key)
                    }
                }
            } catch {
                #if DEBUG
                print("❌ manga batch card fetch: \(error)")
                #endif
            }
        }

        let ordered = ids.compactMap { resultsById[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    /// Upper bound of each card cache (oldest-unordered eviction, like the detail caches).
    nonisolated static let cardCacheLimit = 300
    /// Ids per batched `id=in.(...)` read.
    nonisolated static let batchSize = 100

    /// The ids of `ids` not in `resolved`, de-duplicated, in first-seen order.
    nonisolated static func uniqueMissingIds(_ ids: [Int], resolved: Set<Int>) -> [Int] {
        var seen = resolved
        return ids.filter { seen.insert($0).inserted }
    }

    /// `ids` split into consecutive batches of at most `size` (one request each).
    nonisolated static func batchChunks(_ ids: [Int], size: Int = batchSize) -> [[Int]] {
        guard size > 0, !ids.isEmpty else { return [] }
        return stride(from: 0, to: ids.count, by: size).map { start in
            Array(ids[start..<min(start + size, ids.count)])
        }
    }

    // MARK: - Tags (per-title "sub-genres"; row shapes shared with the genre facets in Discovery)

    struct TagNode: Decodable {
        let id: Int
        let name: String
        let category: String?
        let isAdult: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, category
            case isAdult = "is_adult"
        }
    }

    struct TagEdge: Decodable {
        let rank: Int?
        let tagId: Int?
        let tags: TagNode?

        enum CodingKeys: String, CodingKey {
            case rank
            case tagId = "tag_id"
            case tags
        }
    }

    struct AnimeTagSampleRow: Decodable {
        let id: Int
        let animeTags: [TagEdge]

        enum CodingKeys: String, CodingKey {
            case id
            case animeTags = "anime_tags"
        }
    }

    struct MangaTagSampleRow: Decodable {
        let id: Int
        let mangaTags: [TagEdge]

        enum CodingKeys: String, CodingKey {
            case id
            case mangaTags = "manga_tags"
        }
    }

    static func isBlockedTag(_ t: TagNode) -> Bool {
        if t.isAdult { return true }
        // Keep it simple: AniList already flags adult tags; category filters can be layered later.
        return false
    }

    /// Returns top non-adult tags for a specific anime (used for "sub-genres" on detail pages).
    func fetchTopTagsForAnime(animeId: Int, limit: Int = 12) async -> [TagFacet] {
        do {
            let client = try requiredClient()
            let rows: [AnimeTagSampleRow] = try await client
                .from("anime")
                .select("id,anime_tags(rank,tags(id,name,category,is_adult))")
                .eq("id", value: animeId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return [] }
            let tags = row.animeTags
                .compactMap { edge -> (id: Int, name: String, category: String?, isAdult: Bool, rank: Int)? in
                    guard let node = edge.tags else { return nil }
                    let r = edge.rank ?? 0
                    return (node.id, node.name, node.category, node.isAdult, r)
                }
                .filter { !$0.isAdult }
                .sorted { $0.rank > $1.rank }
                .prefix(limit)
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: 0) }
            return Array(tags)
        } catch {
            #if DEBUG
            print("❌ anime tag fetch: \(error)")
            #endif
            return []
        }
    }

    /// Returns top non-adult tags for a specific manga (used for "sub-genres" on detail pages).
    func fetchTopTagsForManga(mangaId: Int, limit: Int = 12) async -> [TagFacet] {
        do {
            let client = try requiredClient()
            let rows: [MangaTagSampleRow] = try await client
                .from("manga")
                .select("id,manga_tags(rank,tags(id,name,category,is_adult))")
                .eq("id", value: mangaId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return [] }
            let tags = row.mangaTags
                .compactMap { edge -> (id: Int, name: String, category: String?, isAdult: Bool, rank: Int)? in
                    guard let node = edge.tags else { return nil }
                    let r = edge.rank ?? 0
                    return (node.id, node.name, node.category, node.isAdult, r)
                }
                .filter { !$0.isAdult }
                .sorted { $0.rank > $1.rank }
                .prefix(limit)
                .map { TagFacet(id: $0.id, name: $0.name, category: $0.category, count: 0) }
            return Array(tags)
        } catch {
            #if DEBUG
            print("❌ manga tag fetch: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Entity Fetches (Characters, Staff, Studios, Authors)

    // -- Inline section fetches (forward joins: media → entity) --

    func fetchCharactersForAnime(animeId: Int) async -> [(character: Character, role: String)] {
        if let cached = animeCharactersCache[animeId] { return cached }
        let result = try? await animeCharactersLoads.run(key: animeId, context: nil) { [weak self] in
            await self?.loadCharactersForAnime(animeId: animeId) ?? []
        }
        return result ?? []
    }

    private func loadCharactersForAnime(animeId: Int) async -> [(character: Character, role: String)] {
        do {
            let client = try requiredClient()
            let joins: [AnimeCharacterJoin] = try await client
                .from("anime_characters")
                .select("role, \(CatalogColumns.characterEmbed)")
                .eq("anime_id", value: animeId)
                .order("id", ascending: true)
                .limit(CatalogColumns.creditsRowLimit)
                .execute()
                .value
            let result = joins.map { (character: $0.characters, role: $0.role ?? "SUPPORTING") }
            if animeCharactersCache.count > 100, let k = animeCharactersCache.keys.first {
                animeCharactersCache.removeValue(forKey: k)
            }
            animeCharactersCache[animeId] = result
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchCharactersForAnime error: \(error)")
            #endif
            return []
        }
    }

    func fetchStaffForAnime(animeId: Int) async -> [(staff: Staff, role: String)] {
        if let cached = animeStaffCache[animeId] { return cached }
        let result = try? await animeStaffLoads.run(key: animeId, context: nil) { [weak self] in
            await self?.loadStaffForAnime(animeId: animeId) ?? []
        }
        return result ?? []
    }

    private func loadStaffForAnime(animeId: Int) async -> [(staff: Staff, role: String)] {
        do {
            let client = try requiredClient()
            let joins: [AnimeStaffJoin] = try await client
                .from("anime_staff")
                .select("role, \(CatalogColumns.staffEmbed)")
                .eq("anime_id", value: animeId)
                .order("id", ascending: true)
                .limit(CatalogColumns.creditsRowLimit)
                .execute()
                .value
            let result = joins.map { (staff: $0.staff, role: $0.role ?? "") }
            if animeStaffCache.count > 100, let k = animeStaffCache.keys.first {
                animeStaffCache.removeValue(forKey: k)
            }
            animeStaffCache[animeId] = result
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchStaffForAnime error: \(error)")
            #endif
            return []
        }
    }

    func fetchStudiosForAnime(animeId: Int) async -> [Studio] {
        if let cached = animeStudiosCache[animeId] { return cached }
        let result = try? await animeStudiosLoads.run(key: animeId, context: nil) { [weak self] in
            await self?.loadStudiosForAnime(animeId: animeId) ?? []
        }
        return result ?? []
    }

    private func loadStudiosForAnime(animeId: Int) async -> [Studio] {
        do {
            let client = try requiredClient()
            let joins: [AnimeStudioJoin] = try await client
                .from("anime_studios")
                .select("studios(id, anilist_id, name, is_animation_studio, site_url, favourites)")
                .eq("anime_id", value: animeId)
                .order("id", ascending: true)
                .limit(CatalogColumns.creditsRowLimit)
                .execute()
                .value
            let result = joins.map(\.studios)
            if animeStudiosCache.count > 100, let k = animeStudiosCache.keys.first {
                animeStudiosCache.removeValue(forKey: k)
            }
            animeStudiosCache[animeId] = result
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchStudiosForAnime error: \(error)")
            #endif
            return []
        }
    }

    func fetchCharactersForManga(mangaId: Int) async -> [(character: Character, role: String)] {
        if let cached = mangaCharactersCache[mangaId] { return cached }
        let result = try? await mangaCharactersLoads.run(key: mangaId, context: nil) { [weak self] in
            await self?.loadCharactersForManga(mangaId: mangaId) ?? []
        }
        return result ?? []
    }

    private func loadCharactersForManga(mangaId: Int) async -> [(character: Character, role: String)] {
        do {
            let client = try requiredClient()
            let joins: [MangaCharacterJoin] = try await client
                .from("manga_characters")
                .select("role, \(CatalogColumns.characterEmbed)")
                .eq("manga_id", value: mangaId)
                .order("id", ascending: true)
                .limit(CatalogColumns.creditsRowLimit)
                .execute()
                .value
            let result = joins.map { (character: $0.characters, role: $0.role ?? "SUPPORTING") }
            if mangaCharactersCache.count > 100, let k = mangaCharactersCache.keys.first {
                mangaCharactersCache.removeValue(forKey: k)
            }
            mangaCharactersCache[mangaId] = result
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchCharactersForManga error: \(error)")
            #endif
            return []
        }
    }

    func fetchAuthorsForManga(mangaId: Int) async -> [(author: Author, role: String)] {
        if let cached = mangaAuthorsCache[mangaId] { return cached }
        let result = try? await mangaAuthorsLoads.run(key: mangaId, context: nil) { [weak self] in
            await self?.loadAuthorsForManga(mangaId: mangaId) ?? []
        }
        return result ?? []
    }

    private func loadAuthorsForManga(mangaId: Int) async -> [(author: Author, role: String)] {
        do {
            let client = try requiredClient()
            let joins: [MangaAuthorJoin] = try await client
                .from("manga_authors")
                .select("role, \(CatalogColumns.authorEmbed)")
                .eq("manga_id", value: mangaId)
                .order("id", ascending: true)
                .limit(CatalogColumns.creditsRowLimit)
                .execute()
                .value
            let result = joins.map { (author: $0.authors, role: $0.role ?? "") }
            if mangaAuthorsCache.count > 100, let k = mangaAuthorsCache.keys.first {
                mangaAuthorsCache.removeValue(forKey: k)
            }
            mangaAuthorsCache[mangaId] = result
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchAuthorsForManga error: \(error)")
            #endif
            return []
        }
    }

    // -- Entity sheet fetches (reverse joins: entity → media) --

    // Each sheet read joins a concurrent duplicate (in-flight join per entity key), is ordered on the
    // server by the embedded title's score (the sheets' default "rating" sort; join row id breaks ties)
    // and is bounded by `CatalogColumns.entityWorksRowLimit`, so a very large entity keeps its
    // highest-rated works rather than its first-imported ones.

    func fetchAnimeByStudio(studioId: Int) async -> [Media] {
        let key = "studio-\(studioId)"
        if let cached = studioWorksCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        let result = try? await studioWorksLoads.run(key: key, context: nil) { [weak self] in
            await self?.loadAnimeByStudio(studioId: studioId, key: key) ?? []
        }
        return result ?? []
    }

    private func loadAnimeByStudio(studioId: Int, key: String) async -> [Media] {
        do {
            let client = try requiredClient()
            let joins: [StudioAnimeJoin] = try await client
                .from("anime_studios")
                .select("anime!inner(id, title_english, title_romaji, cover_image_large, average_score, season_year, format, status, genres, is_adult, episodes)")
                .eq("studio_id", value: studioId)
                .eq("anime.is_adult", value: false)
                .order(CatalogColumns.entityWorksOrder(embed: "anime"), ascending: false)
                .order("id", ascending: true)
                .limit(CatalogColumns.entityWorksRowLimit)
                .execute()
                .value
            // Defense-in-depth: client-side filter in case nested eq is ignored
            let result = DiscoveryContentRules.sanitizeMediaForDiscovery(
                joins.filter { !$0.anime.isAdult }.map { $0.anime.toMedia() }
            )
            trimTimedCache(&studioWorksCache, maxEntries: 50)
            studioWorksCache[key] = TimedCache(value: result, storedAt: Date())
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchAnimeByStudio error: \(error)")
            #endif
            return []
        }
    }

    func fetchAnimeByStaff(staffId: Int) async -> [(media: Media, role: String)] {
        let key = "staff-\(staffId)"
        if let cached = staffWorksCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        let result = try? await staffWorksLoads.run(key: key, context: nil) { [weak self] in
            await self?.loadAnimeByStaff(staffId: staffId, key: key) ?? []
        }
        return result ?? []
    }

    private func loadAnimeByStaff(staffId: Int, key: String) async -> [(media: Media, role: String)] {
        do {
            let client = try requiredClient()
            let joins: [StaffAnimeJoin] = try await client
                .from("anime_staff")
                .select("role, anime!inner(id, title_english, title_romaji, cover_image_large, average_score, season_year, format, status, genres, is_adult, episodes)")
                .eq("staff_id", value: staffId)
                .eq("anime.is_adult", value: false)
                .order(CatalogColumns.entityWorksOrder(embed: "anime"), ascending: false)
                .order("id", ascending: true)
                .limit(CatalogColumns.entityWorksRowLimit)
                .execute()
                .value
            // Defense-in-depth: client-side filter in case nested eq is ignored
            let result = joins
                .filter { !$0.anime.isAdult }
                .compactMap { join -> (media: Media, role: String)? in
                    let media = join.anime.toMedia()
                    guard !(media.genres ?? []).contains("Hentai"),
                          !(media.genres ?? []).contains("Ecchi") else { return nil }
                    return (media: media, role: join.role ?? "")
                }
            trimTimedCache(&staffWorksCache, maxEntries: 50)
            staffWorksCache[key] = TimedCache(value: result, storedAt: Date())
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchAnimeByStaff error: \(error)")
            #endif
            return []
        }
    }

    func fetchMangaByAuthor(authorId: Int) async -> [(media: Media, role: String)] {
        let key = "author-\(authorId)"
        if let cached = authorWorksCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        let result = try? await authorWorksLoads.run(key: key, context: nil) { [weak self] in
            await self?.loadMangaByAuthor(authorId: authorId, key: key) ?? []
        }
        return result ?? []
    }

    private func loadMangaByAuthor(authorId: Int, key: String) async -> [(media: Media, role: String)] {
        do {
            let client = try requiredClient()
            let joins: [AuthorMangaJoin] = try await client
                .from("manga_authors")
                .select("role, manga!inner(id, title_english, title_romaji, cover_image_large, average_score, start_date_year, format, status, genres, is_adult, chapters)")
                .eq("author_id", value: authorId)
                .eq("manga.is_adult", value: false)
                .order(CatalogColumns.entityWorksOrder(embed: "manga"), ascending: false)
                .order("id", ascending: true)
                .limit(CatalogColumns.entityWorksRowLimit)
                .execute()
                .value
            // Defense-in-depth: client-side filter in case nested eq is ignored
            let result = joins
                .filter { !$0.manga.isAdult }
                .compactMap { join -> (media: Media, role: String)? in
                    let media = join.manga.toMedia()
                    guard !(media.genres ?? []).contains("Hentai"),
                          !(media.genres ?? []).contains("Ecchi") else { return nil }
                    return (media: media, role: join.role ?? "")
                }
            trimTimedCache(&authorWorksCache, maxEntries: 50)
            authorWorksCache[key] = TimedCache(value: result, storedAt: Date())
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchMangaByAuthor error: \(error)")
            #endif
            return []
        }
    }

    func fetchMediaByCharacter(characterId: Int) async -> [Media] {
        let key = "char-\(characterId)"
        if let cached = characterWorksCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        let result = try? await characterWorksLoads.run(key: key, context: nil) { [weak self] in
            await self?.loadMediaByCharacter(characterId: characterId, key: key) ?? []
        }
        return result ?? []
    }

    private func loadMediaByCharacter(characterId: Int, key: String) async -> [Media] {
        do {
            let client = try requiredClient()
            async let animeJoins: [CharacterAnimeJoin] = client
                .from("anime_characters")
                .select("anime!inner(id, title_english, title_romaji, cover_image_large, average_score, season_year, format, status, genres, is_adult, episodes)")
                .eq("character_id", value: characterId)
                .eq("anime.is_adult", value: false)
                .order(CatalogColumns.entityWorksOrder(embed: "anime"), ascending: false)
                .order("id", ascending: true)
                .limit(CatalogColumns.entityWorksRowLimit)
                .execute()
                .value
            async let mangaJoins: [CharacterMangaJoin] = client
                .from("manga_characters")
                .select("manga!inner(id, title_english, title_romaji, cover_image_large, average_score, start_date_year, format, status, genres, is_adult, chapters)")
                .eq("character_id", value: characterId)
                .eq("manga.is_adult", value: false)
                .order(CatalogColumns.entityWorksOrder(embed: "manga"), ascending: false)
                .order("id", ascending: true)
                .limit(CatalogColumns.entityWorksRowLimit)
                .execute()
                .value

            // Defense-in-depth: client-side filter in case nested eq is ignored
            let animeMedia = try await animeJoins
                .filter { !$0.anime.isAdult }
                .map { $0.anime.toMedia() }
            let mangaMedia = try await mangaJoins
                .filter { !$0.manga.isAdult }
                .map { $0.manga.toMedia() }

            let result = DiscoveryContentRules.sanitizeMediaForDiscovery(animeMedia + mangaMedia)
            trimTimedCache(&characterWorksCache, maxEntries: 50)
            characterWorksCache[key] = TimedCache(value: result, storedAt: Date())
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchMediaByCharacter error: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Adaptation ladder + relation refresh requests

    func fetchMediaLadder(mediaType: String, mediaId: Int) async -> MediaLadderResponse {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let cached = mediaLadderCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        let response = try? await mediaLadderLoads.run(key: key, context: nil) { [weak self] in
            await self?.loadMediaLadder(mediaType: mediaType, mediaId: mediaId, key: key) ?? .empty
        }
        return response ?? .empty
    }

    private func loadMediaLadder(mediaType: String, mediaId: Int, key: String) async -> MediaLadderResponse {
        do {
            let client = try requiredClient()
            let params = RPCGetMediaLadderParams(
                p_media_type: mediaType.uppercased(),
                p_media_id: mediaId
            )
            let response: MediaLadderResponse = try await client
                .rpc("get_media_ladder", params: params)
                .execute()
                .value
            trimTimedCache(&mediaLadderCache, maxEntries: 80)
            mediaLadderCache[key] = TimedCache(value: response, storedAt: Date())
            return response
        } catch {
            #if DEBUG
            print("[Ladder] fetchMediaLadder error: \(error)")
            #endif
            return .empty
        }
    }

    func enqueueMediaRelationRefresh(
        mediaType: String,
        mediaId: Int,
        reason: String
    ) async {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let last = mediaLadderRefreshEnqueueCooldown[key],
           Date().timeIntervalSince(last) < 12 * 60 * 60 {
            return
        }

        do {
            let client = try requiredClient()
            let params = RPCEnqueueMediaRelationRefreshParams(
                p_media_type: mediaType.uppercased(),
                p_media_id: mediaId,
                p_reason: reason
            )
            let _: AnyJSON = try await client
                .rpc("enqueue_media_relation_refresh", params: params)
                .execute()
                .value
            mediaLadderRefreshEnqueueCooldown[key] = Date()
        } catch {
            #if DEBUG
            print("[Ladder] enqueueMediaRelationRefresh error: \(error)")
            #endif
        }
    }

    func enqueueMediaRelationRefreshIfNeeded(
        mediaType: String,
        mediaId: Int,
        ladder: MediaLadderResponse,
        reason: String
    ) async {
        guard ladder.coverageStatus != .strong else { return }
        await enqueueMediaRelationRefresh(mediaType: mediaType, mediaId: mediaId, reason: reason)
    }

    func prefetchMediaRelationRefreshRequests(
        items: [(mediaType: String, mediaId: Int)],
        reason: String
    ) {
        let uniqueItems = Array(
            Dictionary(
                items.map { ("\($0.mediaType.uppercased())-\($0.mediaId)", $0) },
                uniquingKeysWith: { first, _ in first }
            ).values
        )

        guard !uniqueItems.isEmpty else { return }

        Task {
            for item in uniqueItems.prefix(12) {
                await enqueueMediaRelationRefresh(
                    mediaType: item.mediaType,
                    mediaId: item.mediaId,
                    reason: reason
                )
            }
        }
    }

    // MARK: - External Links
    // Cached per media for `externalLinksTTL` (the detail action bar re-resolves its links whenever the
    // viewer's progress changes; the links themselves do not change with it). A concurrent duplicate
    // joins the running read. A failed read returns [] and is not cached.

    func fetchExternalLinks(mediaType: String, mediaId: Int) async -> [ExternalLink] {
        let key = Self.externalLinksKey(mediaType: mediaType, mediaId: mediaId)
        if let cached = externalLinksCache[key],
           Date().timeIntervalSince(cached.storedAt) < Self.externalLinksTTL {
            return cached.value
        }
        do {
            return try await externalLinksLoads.run(key: key, context: nil) { [weak self] in
                guard let self else { return [] }
                return try await self.loadExternalLinks(mediaType: mediaType, mediaId: mediaId, key: key)
            }
        } catch {
            #if DEBUG
            print("❌ Error fetching external links: \(error)")
            #endif
            return []
        }
    }

    private func loadExternalLinks(mediaType: String, mediaId: Int, key: String) async throws -> [ExternalLink] {
        let client = try requiredClient()
        let links: [ExternalLink] = try await client
            .from("external_links")
            .select(CatalogColumns.select(CatalogColumns.externalLinks))
            .eq("media_type", value: mediaType.uppercased())
            .eq("media_id", value: mediaId)
            .eq("is_disabled", value: false)
            .order("priority", ascending: true)
            .limit(Self.externalLinksRowLimit)
            .execute()
            .value
        trimTimedCache(&externalLinksCache, maxEntries: 100)
        externalLinksCache[key] = TimedCache(value: links, storedAt: Date())
        return links
    }

    /// Row bound of one title's external links (a handful in practice).
    nonisolated static let externalLinksRowLimit = 100

    /// The external-links cache key: media type upper-cased, so "anime" and "ANIME" share an entry and
    /// an anime and a manga with the same id never do.
    nonisolated static func externalLinksKey(mediaType: String, mediaId: Int) -> String {
        "\(mediaType.uppercased())-\(mediaId)"
    }

    // MARK: - Episodes / Chapters (paged)

    func fetchEpisodesNext(animeId: Int, fromNumber: Int, limit: Int = 20) async -> [Episode] {
        do {
            let client = try requiredClient()
            var q = client.from("episodes").select(CatalogColumns.select(CatalogColumns.episodeList))
                .eq("anime_id", value: animeId)

            if fromNumber > 1 {
                q = q.gte("number", value: fromNumber)
            }

            let ordered = q.order("number", ascending: true)
            return try await ordered.range(from: 0, to: max(0, limit - 1)).execute().value
        } catch {
            #if DEBUG
            print("❌ fetch episodes next: \(error)")
            #endif
            return []
        }
    }

    func fetchEpisodesPage(animeId: Int, offset: Int, limit: Int = 50) async -> [Episode] {
        do {
            let client = try requiredClient()
            let from = max(0, offset)
            let to = from + max(1, limit) - 1
            return try await client.from("episodes").select(CatalogColumns.select(CatalogColumns.episodeList))
                .eq("anime_id", value: animeId)
                .order("number", ascending: true)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            #if DEBUG
            print("❌ fetch episodes page: \(error)")
            #endif
            return []
        }
    }

    func fetchChaptersNext(mangaId: Int, fromNumber: Int, limit: Int = 20) async -> [MangaChapter] {
        do {
            let client = try requiredClient()
            var q = client.from("chapters").select(CatalogColumns.select(CatalogColumns.chapterList))
                .eq("manga_id", value: mangaId)

            if fromNumber > 1 {
                q = q.gte("number", value: fromNumber)
            }

            let ordered = q.order("number", ascending: true)
            return try await ordered.range(from: 0, to: max(0, limit - 1)).execute().value
        } catch {
            #if DEBUG
            print("❌ fetch chapters next: \(error)")
            #endif
            return []
        }
    }

    func fetchChaptersPage(mangaId: Int, offset: Int, limit: Int = 50) async -> [MangaChapter] {
        do {
            let client = try requiredClient()
            let from = max(0, offset)
            let to = from + max(1, limit) - 1
            return try await client.from("chapters").select(CatalogColumns.select(CatalogColumns.chapterList))
                .eq("manga_id", value: mangaId)
                .order("number", ascending: true)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            #if DEBUG
            print("❌ fetch chapters page: \(error)")
            #endif
            return []
        }
    }

    func fetchMangaChapterStatus(mangaId: Int) async -> MangaChapterStatus? {
        do {
            let client = try requiredClient()
            let rows: [MangaChapterStatus] = try await client
                .rpc("get_manga_chapter_status", params: ["p_manga_id": mangaId])
                .execute()
                .value
            return rows.first
        } catch {
            #if DEBUG
            print("❌ fetch manga chapter status: \(error)")
            #endif
            return nil
        }
    }

    /// The stream link of one episode (two columns), cached per episode for `externalLinksTTL`,
    /// including "no link". The request stays a structured child of the caller, so a superseded detail
    /// run cancels it at the transport; a failed or cancelled read is not cached.
    func getStreamLinkForEpisode(animeId: Int, episodeNumber: Int) async -> (url: String, site: String)? {
        let key = "\(animeId)#\(episodeNumber)"
        if let cached = episodeStreamLinkCache[key],
           Date().timeIntervalSince(cached.storedAt) < Self.externalLinksTTL {
            return cached.value.flatMap(\.pair)
        }
        do {
            let client = try requiredClient()
            let rows: [EpisodeStreamLink] = try await client
                .from("episodes")
                .select(CatalogColumns.select(CatalogColumns.episodeStreamLink))
                .eq("anime_id", value: animeId)
                .eq("number", value: episodeNumber)
                .limit(1)
                .execute()
                .value
            let link = rows.first.flatMap { $0.pair == nil ? nil : $0 }
            trimTimedCache(&episodeStreamLinkCache, maxEntries: 200)
            episodeStreamLinkCache[key] = TimedCache(value: link, storedAt: Date())
            return link?.pair
        } catch {
            #if DEBUG
            print("❌ Error fetching episode stream: \(error)")
            #endif
        }
        return nil
    }
}

/// The two `episodes` columns behind an episode's watch link.
struct EpisodeStreamLink: Decodable, Sendable {
    let streamUrl: String?
    let streamSite: String?

    enum CodingKeys: String, CodingKey {
        case streamUrl = "stream_url"
        case streamSite = "stream_site"
    }

    /// The link when both the URL and the site are present.
    var pair: (url: String, site: String)? {
        guard let streamUrl, let streamSite else { return nil }
        return (streamUrl, streamSite)
    }
}
#endif
