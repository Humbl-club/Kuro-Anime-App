import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

extension SupabaseService {
// MARK: - User Lists (normalized tables)
    private func statusFromDB(_ listType: String) -> ListStatus {
        switch listType.uppercased() {
        case "READING": return .current
        case "WATCHING": return .current
        case "PLANNING": return .planning
        case "COMPLETED": return .completed
        case "DROPPED": return .dropped
        case "PAUSED": return .paused
        default: return .planning
        }
    }

    func dbListType(for status: ListStatus, mediaType: String) -> String {
        let isManga = mediaType.lowercased() == "manga"
        switch status {
        case .current: return isManga ? "READING" : "WATCHING"
        case .planning: return "PLANNING"
        case .completed: return "COMPLETED"
        case .dropped: return "DROPPED"
        case .paused: return "PAUSED"
        case .repeating: return isManga ? "READING" : "WATCHING"
        }
    }

    // MARK: - Upsert user list entry (status/progress/rating/notes)
    func upsertUserListEntry(
        mediaId: Int,
        mediaType: String,
        status: ListStatus,
        progress: Int,
        rating: Int?,
        notes: String?
    ) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
        do {
            let table: String
            let onConflict: String
            let payload: Encodable

            struct AnimePayload: Encodable {
                let user_id: String
                let anime_id: Int
                let list_type: String
                let progress: Int
                let rating: Int?
                let notes: String?
            }

            struct MangaPayload: Encodable {
                let user_id: String
                let manga_id: Int
                let list_type: String
                let progress: Int
                let rating: Int?
                let notes: String?
            }

            if mediaType.lowercased() == "anime" {
                table = "anime_user_lists"
                onConflict = "user_id,anime_id"
                payload = AnimePayload(
                    user_id: userId,
                    anime_id: mediaId,
                    list_type: dbListType(for: status, mediaType: mediaType),
                    progress: max(0, progress),
                    rating: rating,
                    notes: notes
                )
            } else if mediaType.lowercased() == "manga" {
                table = "manga_user_lists"
                onConflict = "user_id,manga_id"
                payload = MangaPayload(
                    user_id: userId,
                    manga_id: mediaId,
                    list_type: dbListType(for: status, mediaType: mediaType),
                    progress: max(0, progress),
                    rating: rating,
                    notes: notes
                )
            } else {
                #if DEBUG
                print("⚠️ Unknown mediaType: \(mediaType)")
                #endif
                return
            }

            try await client
                .from(table)
                .upsert(payload, onConflict: onConflict)
                .execute()

            errorMessage = nil
            await fetchUserLists()
            await fetchCollectionItems(status: currentCollectionStatusFilter)
            await fetchCollectionFeed(status: currentCollectionStatusFilter)

            if mediaType.lowercased() == "anime" {
                await scheduleAiringNotifications(animeId: mediaId)
                await fetchUpcomingForUser(days: 7)
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            #if DEBUG
            print("❌ upsert list entry error: \(error)")
            #endif
        }
    }

    func updateUserListProgress(mediaId: Int, mediaType: String, progress: Int) async {
        guard let userId = await currentUserIdString() else { return }
        errorMessage = nil
        do {
            let table = mediaType.lowercased() == "anime" ? "anime_user_lists" : "manga_user_lists"
            let idColumn = mediaType.lowercased() == "anime" ? "anime_id" : "manga_id"

            struct UpdateData: Encodable { let progress: Int }

            try await client
                .from(table)
                .update(UpdateData(progress: max(0, progress)))
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            errorMessage = nil
            await fetchUserLists()
        } catch {
            errorMessage = "Couldn't update progress: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to update progress: \(error)")
            #endif
        }
    }

    func fetchUserLists() async {
        if let t = userListsFetchInFlight {
            await t.value
            return
        }
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchUserListsImpl()
        }
        userListsFetchInFlight = t
        await t.value
        userListsFetchInFlight = nil
    }

    private func _fetchUserListsImpl() async {
        guard let userId = await currentUserIdString() else { return }

        struct AnimeListRow: Decodable {
            let id: Int
            let user_id: String
            let anime_id: Int
            let list_type: String
            let progress: Int
            let rating: Int?
            let notes: String?
            let created_at: Date
            let updated_at: Date
        }

        struct MangaListRow: Decodable {
            let id: Int
            let user_id: String
            let manga_id: Int
            let list_type: String
            let progress: Int
            let rating: Int?
            let notes: String?
            let created_at: Date
            let updated_at: Date
        }

        do {
            // Avoid `async let`: some SDK builders are not Sendable under Swift 6 strict concurrency.
            let animeRows: [AnimeListRow] = try await client
                .from("anime_user_lists")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            let mangaRows: [MangaListRow] = try await client
                .from("manga_user_lists")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let mappedAnime = animeRows.map { row in
                UserList(
                    id: row.id,
                    userId: row.user_id,
                    mediaId: row.anime_id,
                    mediaType: "anime",
                    status: statusFromDB(row.list_type),
                    progress: row.progress,
                    progressVolumes: nil,
                    score: row.rating.map { $0 * 10 },
                    notes: row.notes,
                    startedAt: nil,
                    completedAt: nil,
                    isPrivate: false,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at
                )
            }

            let mappedManga = mangaRows.map { row in
                UserList(
                    id: row.id,
                    userId: row.user_id,
                    mediaId: row.manga_id,
                    mediaType: "manga",
                    status: statusFromDB(row.list_type),
                    progress: row.progress,
                    progressVolumes: nil,
                    score: row.rating.map { $0 * 10 },
                    notes: row.notes,
                    startedAt: nil,
                    completedAt: nil,
                    isPrivate: false,
                    createdAt: row.created_at,
                    updatedAt: row.updated_at
                )
            }

            let combined = (mappedAnime + mappedManga).sorted { $0.updatedAt > $1.updatedAt }
            userLists = combined
            rebuildUserListCaches()
            #if DEBUG
            print("✅ Fetched user lists: anime=\(mappedAnime.count), manga=\(mappedManga.count)")
            #endif
        } catch {
            errorMessage = "Failed to fetch lists: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error: \(error)")
            #endif
        }
    }
    // MARK: - Add/Remove in normalized user lists
    func addToList(mediaId: Int, mediaType: String, status: ListStatus) async {
        await upsertUserListEntry(
            mediaId: mediaId,
            mediaType: mediaType,
            status: status,
            progress: 0,
            rating: nil,
            notes: nil
        )
    }

    @discardableResult
    func removeFromList(mediaId: Int, mediaType: String) async -> Bool {
        await removeFromList(mediaId: mediaId, mediaType: mediaType, skipRefresh: false)
    }

    /// Remove with optional refresh skip (for batch operations that refresh once at the end).
    @discardableResult
    func removeFromList(mediaId: Int, mediaType: String, skipRefresh: Bool) async -> Bool {
        guard let userId = await currentUserIdString() else { return false }
        errorMessage = nil
        do {
            let table: String
            let idColumn: String
            let normalizedMediaType = mediaType.lowercased()
            switch normalizedMediaType {
            case "anime": table = "anime_user_lists"; idColumn = "anime_id"
            case "manga": table = "manga_user_lists"; idColumn = "manga_id"
            default: return false
            }

            try await client
                .from(table)
                .delete()
                .eq("user_id", value: userId)
                .eq(idColumn, value: mediaId)
                .execute()

            errorMessage = nil
            if skipRefresh {
                userLists.removeAll { $0.mediaId == mediaId && $0.mediaType.lowercased() == normalizedMediaType }
                rebuildUserListCaches()
                if normalizedMediaType == "anime" {
                    collectionAnimeItems.removeAll { $0.id == mediaId }
                    collectionFeedItems.removeAll { $0.kind == .anime && $0.id == mediaId }
                } else {
                    collectionMangaItems.removeAll { $0.id == mediaId }
                    collectionFeedItems.removeAll { $0.kind == .manga && $0.id == mediaId }
                }
            } else {
                await fetchUserLists()
                await fetchCollectionItems(status: currentCollectionStatusFilter)
                await fetchCollectionFeed(status: currentCollectionStatusFilter)
            }
            #if DEBUG
            print("✅ Removed from user list")
            #endif
            if normalizedMediaType == "anime" {
                cancelAiringNotifications(animeId: mediaId)
                // Remove countdown entry
                countdownByAnimeId[mediaId] = nil
                upcomingAirings.removeAll { $0.anime_id == mediaId }
            }
            return true
        } catch {
            errorMessage = "Failed to remove from list: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Upcoming Airings (user-scoped)
    func fetchUpcomingForUser(days: Int = 7) async {
        if let t = upcomingFetchInFlight {
            await t.value
            return
        }

        // Don't hammer the API when multiple screens mount or when realtime emits bursts.
        let now = Date()
        if days == lastUpcomingDays, let last = lastUpcomingFetchAt, now.timeIntervalSince(last) < 20 {
            return
        }
        guard upcomingBackoff.canAttempt(now: now) else { return }

        lastUpcomingDays = days
        let t = Task { [weak self] in
            guard let self else { return }
            await self._fetchUpcomingForUserImpl(days: days)
        }
        upcomingFetchInFlight = t
        await t.value
        upcomingFetchInFlight = nil
    }

    private func _fetchUpcomingForUserImpl(days: Int) async {
        guard let userId = await currentUserIdString() else { return }
        do {
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let untilISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(days) * 24 * 60 * 60))
            let rows: [UpcomingAiring] = try await client
                .from("user_airing_next")
                .select()
                .eq("user_id", value: userId)
                .gte("next_airing_at", value: nowISO)
                .lt("next_airing_at", value: untilISO)
                .order("next_airing_at", ascending: true)
                .limit(500)
                .execute()
                .value
            self.upcomingAirings = rows
            updateCountdowns()
            lastUpcomingFetchAt = Date()
            upcomingBackoff.recordSuccess()
        } catch {
            upcomingBackoff.recordFailure()
            #if DEBUG
            print("❌ Failed to fetch upcoming airings: \(error)")
            #endif
        }
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "Now" }
        let minutes = Int(interval / 60)
        let days = minutes / (60 * 24)
        let hours = (minutes % (60 * 24)) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func updateCountdowns() {
        let now = Date()
        var map: [Int: String] = [:]
        for u in upcomingAirings {
            let interval = u.next_airing_at.timeIntervalSince(now)
            map[u.anime_id] = formatInterval(interval)
        }
        countdownByAnimeId = map
    }

    func startCountdownUpdates() {
	        countdownTimer?.invalidate()
	        // Avoid passing an actor-isolated closure to Timer (Swift 6 strict concurrency warning).
	        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
	            guard let strongSelf = self else { return }
	            Task { @MainActor in
	                strongSelf.updateCountdowns()
	            }
	        }
	    }

    func stopCountdownUpdates() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Local Notifications for Airings (Anime only)
    private func ensureNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                #if DEBUG
                print("⚠️ Notification permission request failed: \(error)")
                #endif
                // Error logged in debug only
            }
        }
    }

    private func scheduleNotification(id: String, title: String, body: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do { try await UNUserNotificationCenter.current().add(request) } catch {
            #if DEBUG
            print("❌ Schedule notif failed: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    func scheduleAiringNotifications(animeId: Int) async {
        do {
            struct Row: Decodable { let id: Int; let title_english: String?; let title_romaji: String?; let next_episode_number: Int?; let next_airing_at: Date? }
            let row: Row = try await client
                .from("anime")
                .select("id,title_english,title_romaji,next_episode_number,next_airing_at")
                .eq("id", value: animeId)
                .single()
                .execute()
                .value
            guard let airAt = row.next_airing_at, airAt > Date() else { return }
            await ensureNotificationPermission()
            let title = row.title_english ?? row.title_romaji ?? "Upcoming Episode"
            let ep = row.next_episode_number.map { "E\($0)" } ?? "Next"
            // Schedule "now airing"
            await scheduleNotification(id: "airing-\(animeId)-start", title: "\(title) airs now", body: "\(ep) is starting.", at: airAt)
            // Schedule 1 hour before if applicable
            let oneHourBefore = airAt.addingTimeInterval(-3600)
            if oneHourBefore > Date() {
                await scheduleNotification(id: "airing-\(animeId)-1h", title: "In 1 hour: \(title)", body: "\(ep) airs soon.", at: oneHourBefore)
            }
        } catch {
            #if DEBUG
            print("⚠️ Could not schedule notifications: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    func cancelAiringNotifications(animeId: Int) {
        let ids = ["airing-\(animeId)-start", "airing-\(animeId)-1h"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - External Links & Streaming Helpers
    func fetchExternalLinks(mediaType: String, mediaId: Int) async -> [ExternalLink] {
        do {
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

    func setUserProgress(mediaId: Int, mediaType: String, progress: Int) async {
        if let existing = userLists.first(where: { $0.mediaId == mediaId && $0.mediaType.lowercased() == mediaType.lowercased() }) {
            let rating = existing.score.map { $0 / 10 }
            await upsertUserListEntry(
                mediaId: mediaId,
                mediaType: mediaType,
                status: existing.status,
                progress: progress,
                rating: (rating ?? 0) > 0 ? rating : nil,
                notes: existing.notes
            )
        } else {
            await upsertUserListEntry(
                mediaId: mediaId,
                mediaType: mediaType,
                status: .current,
                progress: progress,
                rating: nil,
                notes: nil
            )
        }
    }

    func getStreamLinkForEpisode(animeId: Int, episodeNumber: Int) async -> (url: String, site: String)? {
        do {
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

    private func bestLink(from links: [ExternalLink], ranking: [String]) -> ExternalLink? {
        guard !links.isEmpty else { return nil }
        func weight(for link: ExternalLink) -> (Int, Int) {
            let priority = link.priority ?? 999
            let site = (link.site ?? "").lowercased()
            let rankIndex = ranking.firstIndex(where: { site.contains($0) }) ?? 999
            return (priority, rankIndex)
        }
        return links
            .filter { !$0.isDisabled && $0.url.lowercased().hasPrefix("http") }
            .min(by: { lhs, rhs in weight(for: lhs) < weight(for: rhs) })
    }

    private func normalizedLocaleLanguage(_ locale: String?) -> String {
        let source = (locale ?? Locale.current.identifier).lowercased()
        if source.hasPrefix("de") { return "de" }
        return "en"
    }

    func normalizedExternalLanguage(_ raw: String?) -> String {
        let source = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source.isEmpty { return "unknown" }
        if source.hasPrefix("de") || source.contains("german") || source.contains("deutsch") { return "de" }
        if source.hasPrefix("en") || source.contains("english") { return "en" }
        if source.hasPrefix("ja") || source.contains("japanese") { return "ja" }
        if source.hasPrefix("ko") || source.contains("korean") { return "ko" }
        if source.hasPrefix("zh") || source.contains("chinese") || source.contains("mandarin") { return "zh" }
        return "other"
    }

    private func isAllowedMangaLegalProvider(_ site: String?) -> Bool {
        guard let site, !site.isEmpty else { return false }
        let normalized = site.lowercased()
        return mangaLegalProviderAllowlist.contains(where: { normalized.contains($0) })
    }

    private func isAllowedAnimeLegalProvider(_ site: String?) -> Bool {
        guard let site, !site.isEmpty else { return false }
        let normalized = site.lowercased()
        return animeLegalProviderAllowlist.contains(where: { normalized.contains($0) })
    }

    private func languageRank(for link: ExternalLink, locale: String?) -> Int {
        let target = normalizedLocaleLanguage(locale)
        let language = normalizedExternalLanguage(link.language)
        if language == target { return 0 }
        if language == "en" || language == "de" { return 1 }
        if language == "unknown" { return 2 }
        return 3
    }

    private func providerRank(for link: ExternalLink, ranking: [String]) -> Int {
        let site = (link.site ?? "").lowercased()
        return ranking.firstIndex(where: { site.contains($0) }) ?? 999
    }

    private func isValidHttpURL(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("http://") || normalized.hasPrefix("https://")
    }

    func getProgress(for mediaId: Int) -> Int? {
        userLists.first { $0.mediaId == mediaId && $0.mediaType.lowercased() == "anime" }?.progress
    }

    func fetchLegalWatchLinks(mediaId: Int, locale: String? = nil) async -> [ExternalLink] {
        let links = await fetchExternalLinks(mediaType: "ANIME", mediaId: mediaId)
        return links
            .filter { !$0.isDisabled }
            .filter { isValidHttpURL($0.url) }
            .filter { isAllowedAnimeLegalProvider($0.site) }
            .sorted { lhs, rhs in
                let lhsTuple = (lhs.priority ?? 999, languageRank(for: lhs, locale: locale), providerRank(for: lhs, ranking: animeProviderRanking))
                let rhsTuple = (rhs.priority ?? 999, languageRank(for: rhs, locale: locale), providerRank(for: rhs, ranking: animeProviderRanking))
                if lhsTuple != rhsTuple { return lhsTuple < rhsTuple }
                return (lhs.site ?? "").localizedCaseInsensitiveCompare(rhs.site ?? "") == .orderedAscending
            }
    }

    func getBestLegalWatchLink(
        anime: Anime,
        userProgress: Int?,
        locale: String? = nil
    ) async -> (url: String, site: String, label: String)? {
        let nextEpisode = max(1, (userProgress ?? 0) + 1)
        if let episodeLink = await getStreamLinkForEpisode(animeId: anime.id, episodeNumber: nextEpisode) {
            guard isValidHttpURL(episodeLink.url), isAllowedAnimeLegalProvider(episodeLink.site) else {
                return nil
            }
            let label = "WATCH EP \(nextEpisode) ON \(episodeLink.site.uppercased())"
            return (episodeLink.url, episodeLink.site, label)
        }

        let links = await fetchLegalWatchLinks(mediaId: anime.id, locale: locale)
        guard let best = links.first else {
            return nil
        }
        let siteLabel = (best.site ?? "PROVIDER").uppercased()
        let verb = (userProgress ?? 0) > 0 ? "CONTINUE" : "WATCH"
        return (best.url, best.site ?? "Provider", "\(verb) ON \(siteLabel)")
    }

    func getBestWatchLink(anime: Anime, userProgress: Int?) async -> (url: String, site: String, label: String)? {
        await getBestLegalWatchLink(anime: anime, userProgress: userProgress, locale: Locale.current.identifier)
    }

    func fetchLegalReadLinks(mediaType: String = "MANGA", mediaId: Int, locale: String? = nil) async -> [ExternalLink] {
        guard mediaType.uppercased() == "MANGA" else { return [] }
        let links = await fetchExternalLinks(mediaType: "MANGA", mediaId: mediaId)
        return links
            .filter { !$0.isDisabled }
            .filter { isValidHttpURL($0.url) }
            .filter { isAllowedMangaLegalProvider($0.site) }
            .sorted { lhs, rhs in
                let lhsTuple = (lhs.priority ?? 999, languageRank(for: lhs, locale: locale), providerRank(for: lhs, ranking: mangaProviderRanking))
                let rhsTuple = (rhs.priority ?? 999, languageRank(for: rhs, locale: locale), providerRank(for: rhs, ranking: mangaProviderRanking))
                if lhsTuple != rhsTuple { return lhsTuple < rhsTuple }
                return (lhs.site ?? "").localizedCaseInsensitiveCompare(rhs.site ?? "") == .orderedAscending
            }
    }

    func getBestLegalReadLink(manga: Manga, locale: String? = nil) async -> (url: String, site: String, label: String)? {
        let links = await fetchLegalReadLinks(mediaId: manga.id, locale: locale)
        guard let best = links.first else { return nil }
        let siteLabel = (best.site ?? "Reader").uppercased()
        return (best.url, best.site ?? "Reader", "READ ON \(siteLabel)")
    }

    func getBestReadLink(manga: Manga) async -> (url: String, site: String, label: String)? {
        await getBestLegalReadLink(manga: manga, locale: Locale.current.identifier)
    }

    // MARK: - Collection Management Helpers
    // Fast lookup caches to keep scrolling snappy (avoid O(n) list scans per card render).
    /// Guards against double-tap races on toggle operations.

    private func rebuildUserListCaches() {
        var anime: Set<Int> = []
        var manga: Set<Int> = []
        var byType: [String: [Int: UserList]] = ["anime": [:], "manga": [:]]
        var byTypeStatus: [String: [ListStatus: Set<Int>]] = ["anime": [:], "manga": [:]]

        for item in userLists {
            let t = item.mediaType.lowercased()
            if t == "anime" { anime.insert(item.mediaId) }
            if t == "manga" { manga.insert(item.mediaId) }
            byType[t, default: [:]][item.mediaId] = item
            byTypeStatus[t, default: [:]][item.status, default: []].insert(item.mediaId)
        }

        collectionAnimeIds = anime
        collectionMangaIds = manga
        userListByTypeAndId = byType
        userIdsByTypeAndStatus = byTypeStatus
    }

}
#endif
