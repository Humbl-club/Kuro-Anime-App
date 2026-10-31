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

    /// Sheds the entity, ladder and detail caches under memory pressure.
    func trimCachesForMemoryPressure() {
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
                .select()
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
                .select()
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

    // MARK: - Batched detail fetch (ids in caller order; detail cache first)

    func fetchAnimeByIdsPreservingOrder(_ ids: [Int]) async -> [Anime]? {
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
                    let client = try requiredClient()
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

    func fetchMangaByIdsPreservingOrder(_ ids: [Int]) async -> [Manga]? {
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
                    let client = try requiredClient()
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
                .select("role, characters(id, anilist_id, name_full, name_native, image_large, description, gender, age)")
                .eq("anime_id", value: animeId)
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
                .select("role, staff(id, anilist_id, name_full, name_native, image_large, description, primary_occupations)")
                .eq("anime_id", value: animeId)
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
                .select("role, characters(id, anilist_id, name_full, name_native, image_large, description, gender, age)")
                .eq("manga_id", value: mangaId)
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
                .select("role, authors(id, anilist_id, name_full, name_native, image_large, description)")
                .eq("manga_id", value: mangaId)
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

    func fetchAnimeByStudio(studioId: Int) async -> [Media] {
        let key = "studio-\(studioId)"
        if let cached = studioWorksCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        do {
            let client = try requiredClient()
            let joins: [StudioAnimeJoin] = try await client
                .from("anime_studios")
                .select("anime!inner(id, title_english, title_romaji, cover_image_large, average_score, season_year, format, status, genres, is_adult, episodes)")
                .eq("studio_id", value: studioId)
                .eq("anime.is_adult", value: false)
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
        do {
            let client = try requiredClient()
            let joins: [StaffAnimeJoin] = try await client
                .from("anime_staff")
                .select("role, anime!inner(id, title_english, title_romaji, cover_image_large, average_score, season_year, format, status, genres, is_adult, episodes)")
                .eq("staff_id", value: staffId)
                .eq("anime.is_adult", value: false)
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
        do {
            let client = try requiredClient()
            let joins: [AuthorMangaJoin] = try await client
                .from("manga_authors")
                .select("role, manga!inner(id, title_english, title_romaji, cover_image_large, average_score, start_date_year, format, status, genres, is_adult, chapters)")
                .eq("author_id", value: authorId)
                .eq("manga.is_adult", value: false)
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
        do {
            let client = try requiredClient()
            async let animeJoins: [CharacterAnimeJoin] = client
                .from("anime_characters")
                .select("anime!inner(id, title_english, title_romaji, cover_image_large, average_score, season_year, format, status, genres, is_adult, episodes)")
                .eq("character_id", value: characterId)
                .eq("anime.is_adult", value: false)
                .execute()
                .value
            async let mangaJoins: [CharacterMangaJoin] = client
                .from("manga_characters")
                .select("manga!inner(id, title_english, title_romaji, cover_image_large, average_score, start_date_year, format, status, genres, is_adult, chapters)")
                .eq("character_id", value: characterId)
                .eq("manga.is_adult", value: false)
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

    func fetchExternalLinks(mediaType: String, mediaId: Int) async -> [ExternalLink] {
        do {
            let client = try requiredClient()
            return try await client
                .from("external_links")
                .select()
                .eq("media_type", value: mediaType.uppercased())
                .eq("media_id", value: mediaId)
                .eq("is_disabled", value: false)
                .order("priority", ascending: true)
                .execute()
                .value
        } catch {
            #if DEBUG
            print("❌ Error fetching external links: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Episodes / Chapters (paged)

    func fetchEpisodesNext(animeId: Int, fromNumber: Int, limit: Int = 20) async -> [Episode] {
        do {
            let client = try requiredClient()
            var q = client.from("episodes").select()
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
            return try await client.from("episodes").select()
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
            var q = client.from("chapters").select()
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
            return try await client.from("chapters").select()
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

    func getStreamLinkForEpisode(animeId: Int, episodeNumber: Int) async -> (url: String, site: String)? {
        do {
            let client = try requiredClient()
            let rows: [Episode] = try await client
                .from("episodes")
                .select()
                .eq("anime_id", value: animeId)
                .eq("number", value: episodeNumber)
                .limit(1)
                .execute()
                .value
            if let ep = rows.first, let url = ep.streamUrl, let site = ep.streamSite {
                return (url, site)
            }
        } catch {
            #if DEBUG
            print("❌ Error fetching episode stream: \(error)")
            #endif
            // Error logged in debug only
        }
        return nil
    }
}
#endif
