import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

extension SupabaseService {
// MARK: - Clubs

    struct ClubInfo: Decodable, Sendable {
        let id: String
        let name: String
        let description: String?
        let sharing_level: String
        let max_members: Int
        let is_archived: Bool
        let invite_code: String?
        let created_at: String
    }

    struct ClubMember: Decodable, Sendable {
        let user_id: String
        let display_name: String?
        let role: String
        let sharing_level: String
        let joined_at: String
    }

    struct ClubRailItem: Decodable, Sendable, Identifiable {
        let id: String
        let media_type: String
        let media_id: Int
        let sort_order: Int
        let note: String?
        let added_by: String
        let title_display: String
        let cover_image_medium: String?
        let average_score: Int?
        let year: Int?
        let format: String?
        let episode_count: Int?
        let chapter_count: Int?
        let my_status: String?
        let my_progress: Int?
        let my_rating: Int?
        let member_status_counts: [String: Int]?
        let member_statuses: [MemberItemStatus]?
        let reactions: [String: Int]?
        let my_reactions: [String]?

        /// Total count for the relevant media type (episodes for anime, chapters for manga).
        var totalCount: Int? {
            media_type.uppercased() == "ANIME" ? episode_count : chapter_count
        }

        struct MemberItemStatus: Decodable, Sendable {
            let user_id: String
            let display_name: String?
            let status: String?
            let progress: Int?
            let updated_at: String?
        }
    }

    struct ClubRail: Decodable, Sendable, Identifiable {
        let id: String
        let title: String
        let description: String?
        let is_locked: Bool
        let sort_order: Int
        let created_by: String
        let items: [ClubRailItem]
    }

    struct ClubPollOption: Decodable, Sendable, Identifiable {
        let id: String
        let label: String
        let media_type: String?
        let media_id: Int?
        let sort_order: Int
        let vote_count: Int
    }

    struct ClubPoll: Decodable, Sendable, Identifiable {
        let id: String
        let question: String
        let is_closed: Bool
        let closes_at: String?
        let created_by: String
        let created_at: String
        let options: [ClubPollOption]
        let my_vote_option_id: String?
    }

    struct ClubBundle: Decodable, Sendable {
        let club: ClubInfo
        let members: [ClubMember]
        let my_role: String
        let my_sharing_level: String
        let rails: [ClubRail]
        let polls: [ClubPoll]
        let member_count: Int
    }

    struct ClubLoadingState: Decodable, Sendable {
        let state: String
        let visibility: String
    }

    struct ClubBundleLoading: Decodable, Sendable {
        let club: ClubInfo
        let members: [ClubMember]
        let my_role: String
        let my_sharing_level: String
        let rails: [ClubRail]
        let polls: [ClubPoll]
        let member_count: Int
        let rail_count: Int?
        let poll_count: Int?
        let last_activity_at: String?
        let activity_preview: String?
        let loading_state: ClubLoadingState?
    }

    struct CreateClubResponse: Decodable, Sendable {
        let club_id: String
        let invite_code: String
        let name: String
    }

    struct JoinClubResponse: Decodable, Sendable {
        let club_id: String
        let club_name: String
        let role: String
    }

    struct SimpleSuccessResponse: Decodable, Sendable {
        let success: Bool
    }

    struct AddRailItemResponse: Decodable, Sendable {
        let item_id: String
        let sort_order: Int
    }

    struct CreateRailResponse: Decodable, Sendable {
        let rail_id: String
        let title: String
    }

    struct CreatePollResponse: Decodable, Sendable {
        let poll_id: String
        let question: String
    }

    // Lightweight row for "My Clubs" list (fetched via enriched RPC)
    struct ClubListRow: Decodable, Sendable, Identifiable {
        let id: String
        let name: String
        let sharing_level: String
        let is_archived: Bool
        let created_at: String
        let member_count: Int?
        let rail_count: Int?
        let poll_count: Int?
        let last_activity_at: String?
        let activity_preview: String?
        let cover_images: [String]?
        let member_names: [String]?
        let loading_state: ClubLoadingState?
    }

    // Club bundle cache (5 min TTL per spec)

    func rememberedAddToClubId() -> String? {
        UserDefaults.standard.string(forKey: rememberedClubIdKey)
    }

    func setRememberedAddToClubId(_ clubId: String?) {
        if let clubId, !clubId.isEmpty {
            UserDefaults.standard.set(clubId, forKey: rememberedClubIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: rememberedClubIdKey)
        }
    }

    func fetchMyClubs() async {
        do {
            let clubs: [ClubListRow]
            do {
                clubs = try await client
                    .rpc("fetch_my_clubs_loading")
                    .execute()
                    .value
            } catch {
                clubs = try await client
                    .rpc("fetch_my_clubs_enriched")
                    .execute()
                    .value
            }
            myClubs = clubs
        } catch {
            #if DEBUG
            print("❌ fetchMyClubs: \(error)")
            #endif
        }
    }

    // MARK: - Club last-seen (UserDefaults per-club timestamps)

    private static var clubLastSeenPrefix: String { "com.kuro.clubLastSeen." }

    func clubLastSeenAt(clubId: String) -> Date? {
        let ts = UserDefaults.standard.double(forKey: Self.clubLastSeenPrefix + clubId)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    func markClubSeen(clubId: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.clubLastSeenPrefix + clubId)
    }

    func hasUnseenActivity(club: ClubListRow) -> Bool {
        guard let activityStr = club.last_activity_at else { return false }
        guard let activityDate = Self.parseISO8601(activityStr) else { return false }
        guard let lastSeen = clubLastSeenAt(clubId: club.id) else { return true }
        return activityDate > lastSeen
    }

    private static var isoFractional: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static var isoBasic: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    static func parseISO8601(_ str: String) -> Date? {
        isoFractional.date(from: str) ?? isoBasic.date(from: str)
    }

    func createClub(name: String, description: String? = nil, sharingLevel: String = "status") async throws -> CreateClubResponse {
        let params = RPCCreateClubParams(p_name: name, p_description: description, p_sharing_level: sharingLevel)
        let resp: CreateClubResponse = try await client
            .rpc("create_club", params: params)
            .execute()
            .value
        await fetchMyClubs()
        return resp
    }

    func joinClub(inviteCode: String) async throws -> JoinClubResponse {
        let params = RPCJoinClubParams(p_invite_code: inviteCode)
        let resp: JoinClubResponse = try await client
            .rpc("join_club", params: params)
            .execute()
            .value
        await fetchMyClubs()
        return resp
    }

    func leaveClub(clubId: String) async throws {
        let params = RPCClubIdParams(p_club_id: clubId)
        let _: SimpleSuccessResponse = try await client
            .rpc("leave_club", params: params)
            .execute()
            .value
        clubBundleCache.removeValue(forKey: clubId)
        await fetchMyClubs()
    }

    func fetchClubBundle(clubId: String, forceRefresh: Bool = false) async throws -> ClubBundle {
        let now = Date()
        if !forceRefresh, let cached = clubBundleCache[clubId], now.timeIntervalSince(cached.storedAt) < 300 {
            return cached.value
        }
        if let task = clubBundleInFlight[clubId] {
            return try await task.value
        }

        let client = self.client
        let cid = clubId
        let task = Task<ClubBundle, Error>(priority: .userInitiated) {
            let params = RPCClubIdParams(p_club_id: cid)
            let bundle: ClubBundle = try await client!
                .rpc("fetch_club_bundle", params: params)
                .execute()
                .value
            return bundle
        }
        clubBundleInFlight[clubId] = task
        defer { clubBundleInFlight[clubId] = nil }
        let bundle = try await task.value
        clubBundleCache[clubId] = TimedCache(value: bundle, storedAt: now)
        return bundle
    }

    func fetchClubBundleLoading(clubId: String) async throws -> ClubBundleLoading {
        let params = RPCClubIdParams(p_club_id: clubId)
        return try await client
            .rpc("fetch_club_bundle_loading", params: params)
            .execute()
            .value
    }

    func refreshClubBundle(clubId: String) async throws -> ClubBundle {
        try await fetchClubBundle(clubId: clubId, forceRefresh: true)
    }

    private func evictClubBundleCache(containingRailId railId: String) {
        guard !railId.isEmpty else { return }
        for (clubId, cached) in clubBundleCache {
            if cached.value.rails.contains(where: { $0.id == railId }) {
                clubBundleCache.removeValue(forKey: clubId)
                break
            }
        }
    }

    private func evictClubBundleCache(containingPollId pollId: String) {
        guard !pollId.isEmpty else { return }
        for (clubId, cached) in clubBundleCache {
            if cached.value.polls.contains(where: { $0.id == pollId }) {
                clubBundleCache.removeValue(forKey: clubId)
                break
            }
        }
    }

    func addRailItem(railId: String, mediaType: String, mediaId: Int, note: String? = nil) async throws -> AddRailItemResponse {
        let params = RPCAddRailItemParams(p_rail_id: railId, p_media_type: mediaType, p_media_id: mediaId, p_note: note)
        let response: AddRailItemResponse = try await client
            .rpc("add_club_rail_item", params: params)
            .execute()
            .value
        evictClubBundleCache(containingRailId: railId)
        return response
    }

    func castVote(pollId: String, optionId: String) async throws {
        let params = RPCCastVoteParams(p_poll_id: pollId, p_option_id: optionId)
        let _: SimpleSuccessResponse = try await client
            .rpc("cast_club_vote", params: params)
            .execute()
            .value
        evictClubBundleCache(containingPollId: pollId)
    }

    func createClubRail(clubId: String, title: String, description: String? = nil) async throws -> CreateRailResponse {
        let params = RPCCreateClubRailParams(p_club_id: clubId, p_title: title, p_description: description)
        let resp: CreateRailResponse = try await client
            .rpc("create_club_rail", params: params)
            .execute()
            .value
        clubBundleCache.removeValue(forKey: clubId)
        return resp
    }

    func createClubPoll(clubId: String, question: String, options: [String]) async throws -> CreatePollResponse {
        let params = RPCCreateClubPollParams(p_club_id: clubId, p_question: question, p_options: options)
        let resp: CreatePollResponse = try await client
            .rpc("create_club_poll", params: params)
            .execute()
            .value
        clubBundleCache.removeValue(forKey: clubId)
        return resp
    }

    struct ToggleReactionResponse: Decodable, Sendable {
        let action: String // "added" | "removed"
        let emoji: String
    }

    func toggleReaction(railItemId: String, emoji: String) async throws -> ToggleReactionResponse {
        let params = RPCToggleReactionParams(p_rail_item_id: railItemId, p_emoji: emoji)
        return try await client
            .rpc("toggle_club_reaction", params: params)
            .execute()
            .value
    }

    func clubMemberCount(clubId: String) -> Int {
        clubBundleCache[clubId]?.value.member_count ?? 0
    }

    struct ClubMediaActivityMatch: Sendable {
        let rail: ClubRail
        let item: ClubRailItem
    }

    struct ClubMediaActivity: Sendable {
        let club: ClubInfo
        let memberCount: Int
        let sharingLevel: String
        let members: [ClubMember]
        let matchingItems: [ClubMediaActivityMatch]
    }

    // MARK: - Club Notifications


    private static var clubNotificationLastCheckKey: String { "com.kuro.clubNotificationLastCheck" }

    struct ClubActivityCheckResponse: Decodable, Sendable {
        let has_new_activity: Bool
        let latest_activity_at: String?
    }

    func checkClubNotifications() async {
        guard FeatureFlags.shared.isClubsNotificationsV1Enabled else { return }
        let lastCheck = UserDefaults.standard.double(forKey: Self.clubNotificationLastCheckKey)
        let since = lastCheck > 0 ? Date(timeIntervalSince1970: lastCheck) : Date().addingTimeInterval(-86400)

        struct CheckParams: Encodable, Sendable {
            let p_since: String

            enum CodingKeys: String, CodingKey { case p_since }
            nonisolated func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_since, forKey: .p_since)
            }
        }

        let isoStr = ISO8601DateFormatter().string(from: since)
        let params = CheckParams(p_since: isoStr)

        do {
            let resp: ClubActivityCheckResponse = try await client
                .rpc("check_club_activity_since", params: params)
                .execute()
                .value
            hasUnseenClubActivity = resp.has_new_activity
        } catch {
            #if DEBUG
            print("❌ checkClubNotifications: \(error)")
            #endif
        }
    }

    func clearClubNotificationBadge() {
        hasUnseenClubActivity = false
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.clubNotificationLastCheckKey)
    }

    // MARK: - Club Chat

    struct ClubMessage: Decodable, Sendable, Identifiable {
        let id: String
        let user_id: String
        let display_name: String?
        let text: String
        let created_at: String
    }

    struct SendMessageResponse: Decodable, Sendable {
        let message_id: String
        let created_at: String
    }

    func sendClubMessage(clubId: String, text: String) async throws -> SendMessageResponse {
        let params = RPCSendClubMessageParams(p_club_id: clubId, p_text: text)
        return try await client
            .rpc("send_club_message", params: params)
            .execute()
            .value
    }

    func fetchClubMessages(clubId: String, limit: Int = 50, before: String? = nil) async throws -> [ClubMessage] {
        let params = RPCFetchClubMessagesParams(p_club_id: clubId, p_limit: limit, p_before: before)
        return try await client
            .rpc("fetch_club_messages", params: params)
            .execute()
            .value
    }

    // MARK: - Entity Fetches (Characters, Staff, Studios, Authors)

    // -- Inline section fetches (forward joins: media → entity) --

    func fetchCharactersForAnime(animeId: Int) async -> [(character: Character, role: String)] {
        if let cached = animeCharactersCache[animeId] { return cached }
        do {
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
        do {
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
        do {
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
        do {
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
        do {
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

    private func sanitizeMediaForDiscovery(_ items: [Media]) -> [Media] {
        items.filter { media in
            let genres = media.genres ?? []
            if genres.contains("Hentai") { return false }
            if genres.contains("Ecchi") { return false }
            return true
        }
    }

    func fetchAnimeByStudio(studioId: Int) async -> [Media] {
        let key = "studio-\(studioId)"
        if let cached = studioWorksCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }
        do {
            let joins: [StudioAnimeJoin] = try await client
                .from("anime_studios")
                .select("anime!inner(id, title_english, title_romaji, cover_image_large, average_score, season_year, format, status, genres, is_adult, episodes)")
                .eq("studio_id", value: studioId)
                .eq("anime.is_adult", value: false)
                .execute()
                .value
            // Defense-in-depth: client-side filter in case nested eq is ignored
            let result = sanitizeMediaForDiscovery(
                joins.filter { !$0.anime.isAdult }.map { $0.anime.toMedia() }
            )
            trimCache(&studioWorksCache, maxEntries: 50)
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
            trimCache(&staffWorksCache, maxEntries: 50)
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
            trimCache(&authorWorksCache, maxEntries: 50)
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

            let result = sanitizeMediaForDiscovery(animeMedia + mangaMedia)
            trimCache(&characterWorksCache, maxEntries: 50)
            characterWorksCache[key] = TimedCache(value: result, storedAt: Date())
            return result
        } catch {
            #if DEBUG
            print("[EntityFetch] fetchMediaByCharacter error: \(error)")
            #endif
            return []
        }
    }

    func fetchMediaLadder(mediaType: String, mediaId: Int) async -> MediaLadderResponse {
        let key = "\(mediaType.uppercased())-\(mediaId)"
        if let cached = mediaLadderCache[key], Date().timeIntervalSince(cached.storedAt) < 120 {
            return cached.value
        }

        do {
            let params = RPCGetMediaLadderParams(
                p_media_type: mediaType.uppercased(),
                p_media_id: mediaId
            )
            let response: MediaLadderResponse = try await client
                .rpc("get_media_ladder", params: params)
                .execute()
                .value
            trimCache(&mediaLadderCache, maxEntries: 80)
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

}
#endif
