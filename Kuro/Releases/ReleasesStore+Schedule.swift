import Foundation
import KuroCore
import KuroLibrary

// MARK: - Release schedule and themes (spec §3.1–3.4)
// The three prepared RPCs, their silent fallbacks and the per-account 5-minute caches. State lives
// in `ReleasesStore` (stored properties cannot live in an extension); see that file's header for the
// account rules. Views read `schedule` / `scheduleItems(for:)` / `nextRelease(for:)` and call the
// async loaders from `.task`; nothing here shows a banner or error copy (spec §3.4).

/// The prepared release RPCs (not deployed live on 2026-11-01).
nonisolated enum ReleaseContract: String, Sendable, CaseIterable {
    case userSchedule = "user_release_schedule_v1"
    case mediaSchedule = "media_release_schedule_v1"
    case themes = "media_themes_v1"
}

/// What a failed release read means for the caller (spec §3.4).
nonisolated enum ReleaseFailure: Equatable, Sendable {
    /// The caller or its account went away: publish nothing, cache nothing.
    case cancelled
    /// The contract is missing or answers an unreadable payload: remember it, fall back, cache the
    /// fallback.
    case notDeployed
    /// Offline, timeout, 5xx, auth hiccup: fall back now, cache nothing (retry on the next load).
    case transient
}

/// RPC arguments (top-level so their `Encodable` conformance is not main-actor isolated).
struct RPCUserReleaseScheduleParams: Encodable, Sendable {
    let p_medium: String?
    let p_limit: Int
}

struct RPCMediaReleaseScheduleParams: Encodable, Sendable {
    let p_medium: String
    let p_media_id: Int
    let p_limit: Int
}

struct RPCMediaThemesParams: Encodable, Sendable {
    let p_anime_id: Int
}

#if canImport(Supabase)
import Supabase

/// Pure ordering and filtering shared by the loaders (testable without a client).
nonisolated enum ReleaseSchedulePolicy {
    /// Displayable rows only (estimates ≥ 0.7), past rows dropped unless `keepPast`, soonest first,
    /// undated last, ties by title then unit number.
    static func prepared(_ items: [ReleaseScheduleItem], keepPast: Bool) -> [ReleaseScheduleItem] {
        items
            .filter { $0.isDisplayable && (keepPast || !$0.isPast) }
            .sorted { lhs, rhs in
                if lhs.isPast != rhs.isPast { return lhs.isPast }
                switch (lhs.releaseAt, rhs.releaseAt) {
                case let (l?, r?) where l != r: return l < r
                case (.some, nil): return true
                case (nil, .some): return false
                default:
                    if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
                    return (lhs.unitNumber ?? 0) < (rhs.unitNumber ?? 0)
                }
            }
    }

    /// Songs in reading order: openings, endings, inserts; then sequence and version. Adult-flagged
    /// rows are never shown.
    static func preparedThemes(_ songs: [ThemeSong]) -> [ThemeSong] {
        let order: [ThemeSongKind: Int] = [.opening: 0, .ending: 1, .insert: 2]
        return songs
            .filter { !$0.isNSFW }
            .sorted { lhs, rhs in
                let l = order[lhs.kind] ?? 3, r = order[rhs.kind] ?? 3
                if l != r { return l < r }
                if (lhs.sequence ?? 0) != (rhs.sequence ?? 0) { return (lhs.sequence ?? 0) < (rhs.sequence ?? 0) }
                return (lhs.version ?? 0) < (rhs.version ?? 0)
            }
    }

    /// A `user_airing_next` row as a confirmed AniList episode release (the fallback path).
    @MainActor
    static func item(fromAiring airing: ReleasesStore.UpcomingAiring) -> ReleaseScheduleItem {
        ReleaseScheduleItem(
            medium: .anime,
            mediaId: airing.anime_id,
            title: airing.title_english ?? airing.title_romaji ?? "",
            unitKind: .episode,
            unitNumber: airing.next_episode_number.map(Double.init),
            releaseAt: airing.next_airing_at,
            basis: .confirmed,
            source: "anilist"
        )
    }
}

extension ReleaseFailure {
    /// Classifies a release read failure. PostgREST answers a missing function with PGRST202
    /// (HTTP 404), a missing relation with PGRST205 / 42P01, an undefined or ambiguous overload with
    /// 42883 / PGRST203; an unreadable payload is a contract mismatch too.
    nonisolated static func classify(_ error: any Error) -> ReleaseFailure {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .transient
        }
        if let postgrest = error as? PostgrestError {
            let missing: Set<String> = ["PGRST202", "PGRST203", "PGRST205", "42883", "42P01"]
            return postgrest.code.map(missing.contains) == true ? .notDeployed : .transient
        }
        if let http = error as? HTTPError {
            return http.response.statusCode == 404 ? .notDeployed : .transient
        }
        if error is DecodingError { return .notDeployed }
        return .transient
    }
}

@MainActor
extension ReleasesStore {
    /// Lifetime of a cached schedule or theme answer.
    nonisolated static let scheduleTTL: TimeInterval = 300
    /// How long a "not deployed" answer suppresses calls to that contract.
    nonisolated static let undeployedRetryInterval: TimeInterval = 1800
    /// Default number of titles `loadSchedule` asks for.
    nonisolated static let defaultScheduleLimit = 100

    // MARK: Reading

    /// The loaded schedule rows of one medium (nil: both), soonest first.
    func scheduleItems(for medium: MediaKind?) -> [ReleaseScheduleItem] {
        guard let medium else { return schedule }
        return schedule.filter { $0.medium == medium }
    }

    /// The next known release of one tracked title: the loaded schedule first, then (anime) the
    /// `user_airing_next` rows. nil when nothing is known (the UI shows nothing, spec D10).
    func nextRelease(for key: MediaKey) -> ReleaseScheduleItem? {
        if let item = schedule.first(where: { $0.key == key && !$0.isPast }) { return item }
        guard key.kind == .anime,
              let airing = upcomingAirings.first(where: { $0.anime_id == key.id }) else { return nil }
        return ReleaseSchedulePolicy.item(fromAiring: airing)
    }

    // MARK: Loading

    /// Loads the account's next release per tracked title into `schedule` (both media). Cached for
    /// 5 minutes per account; `force` skips the cache. Never throws and never shows an error: a
    /// missing contract or a failed read falls back to the anime airing rows.
    @discardableResult
    func loadSchedule(limit: Int = ReleasesStore.defaultScheduleLimit, force: Bool = false) async -> [ReleaseScheduleItem] {
        guard let context = accountSession.current else { return [] }
        let key = cacheKey(context, "user", String(limit))
        if !force, let cached = freshSchedule(key) {
            return publishSchedule(cached, context: context)
        }
        let items = try? await scheduleLoads.run(key: key, context: context) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.readUserSchedule(limit: limit, context: context, cacheKey: key)
        }
        guard let items, accountSession.isCurrent(context) else { return [] }
        return items
    }

    /// Upcoming units of one title (plus the last released one, `isPast`), for detail pages.
    /// Cached for 5 minutes per account. Fallback: anime next episode from `anime.next_airing_at`;
    /// manga empty (the section hides).
    func mediaSchedule(kind: MediaKind, id: Int, limit: Int = 6, force: Bool = false) async -> [ReleaseScheduleItem] {
        guard let context = accountSession.current else { return [] }
        let key = cacheKey(context, "media", kind.rawValue, String(id), String(limit))
        if !force, let cached = freshSchedule(key) { return cached }
        let items = try? await scheduleLoads.run(key: key, context: context) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.readMediaSchedule(kind: kind, id: id, limit: limit, context: context, cacheKey: key)
        }
        guard let items, accountSession.isCurrent(context) else { return [] }
        return items
    }

    /// An anime's opening, ending and insert songs. Cached for 5 minutes per account. Empty when the
    /// contract is missing or the read fails (the section hides).
    func themes(animeId: Int, force: Bool = false) async -> [ThemeSong] {
        guard let context = accountSession.current else { return [] }
        let key = cacheKey(context, "themes", String(animeId))
        if !force, let cached = themesCache[key], Date().timeIntervalSince(cached.storedAt) < Self.scheduleTTL {
            return cached.value
        }
        let songs = try? await themeLoads.run(key: key, context: context) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.readThemes(animeId: animeId, context: context, cacheKey: key)
        }
        guard let songs, accountSession.isCurrent(context) else { return [] }
        return songs
    }

    // MARK: Library change

    /// A membership or status change: the account's schedule answer is stale. A title that left (or
    /// was completed/dropped) leaves `schedule` at once; an added one appears on the next load.
    func scheduleMembershipDidChange(_ change: LibraryChange) {
        let prefix = change.account.userId.lowercased() + "|user|"
        for key in scheduleCache.keys where key.hasPrefix(prefix) { scheduleCache[key] = nil }
        let status = change.current?.status
        if change.current == nil || status == .completed || status == .dropped {
            schedule.removeAll { $0.key == change.key }
        }
    }

    // MARK: Reads

    private func readUserSchedule(limit: Int, context: AccountContext, cacheKey key: String) async throws -> [ReleaseScheduleItem] {
        var cacheable = true
        if let client, contractAvailable(.userSchedule) {
            do {
                let rows: LenientRows<ReleaseScheduleItem> = try await accountSession.withCredentialLease(for: context) {
                    try await client
                        .rpc(ReleaseContract.userSchedule.rawValue,
                             params: RPCUserReleaseScheduleParams(p_medium: nil, p_limit: limit))
                        .execute()
                        .value
                }
                guard accountSession.isCurrent(context) else { throw CancellationError() }
                let items = ReleaseSchedulePolicy.prepared(rows.rows, keepPast: false)
                scheduleSource = .schedule
                storeSchedule(items, key: key)
                return publishSchedule(items, context: context)
            } catch {
                switch ReleaseFailure.classify(error) {
                case .cancelled: throw CancellationError()
                case .notDeployed: markUndeployed(.userSchedule)
                case .transient: cacheable = false
                }
                logFallback(.userSchedule, error)
            }
        }
        // Fallback: confirmed AniList next episodes of the account's anime (`user_airing_next`).
        // Cached only when that read succeeded (now, or within its throttle window): a failed or
        // backed-off read leaves stale or empty rows that must not be served for 5 minutes.
        let airingsFresh = await refreshUpcomingForUser(days: max(lastUpcomingDays, 7))
        guard accountSession.isCurrent(context) else { throw CancellationError() }
        let items = ReleaseSchedulePolicy.prepared(
            upcomingAirings.map(ReleaseSchedulePolicy.item(fromAiring:)), keepPast: false)
        scheduleSource = .airingFallback
        if cacheable && airingsFresh { storeSchedule(items, key: key) }
        return publishSchedule(items, context: context)
    }

    private func readMediaSchedule(kind: MediaKind, id: Int, limit: Int, context: AccountContext,
                                   cacheKey key: String) async throws -> [ReleaseScheduleItem] {
        var cacheable = true
        if let client, contractAvailable(.mediaSchedule) {
            do {
                // Public catalog read: no account lease needed.
                let rows: LenientRows<ReleaseScheduleItem> = try await client
                    .rpc(ReleaseContract.mediaSchedule.rawValue,
                         params: RPCMediaReleaseScheduleParams(p_medium: kind.rawValue, p_media_id: id, p_limit: limit))
                    .execute()
                    .value
                guard accountSession.isCurrent(context) else { throw CancellationError() }
                let items = ReleaseSchedulePolicy.prepared(
                    rows.rows.filter { $0.key == MediaKey(kind: kind, id: id) }, keepPast: true)
                storeSchedule(items, key: key)
                return items
            } catch {
                switch ReleaseFailure.classify(error) {
                case .cancelled: throw CancellationError()
                case .notDeployed: markUndeployed(.mediaSchedule)
                case .transient: cacheable = false
                }
                logFallback(.mediaSchedule, error)
            }
        }
        guard kind == .anime, let client else {
            if cacheable { storeSchedule([], key: key) }
            return []
        }
        // Fallback: the title's own next airing (AniList via the bulk import), confirmed.
        struct Row: Decodable, Sendable {
            let id: Int
            let title_english: String?
            let title_romaji: String?
            let next_episode_number: Int?
            let next_airing_at: Date?
        }
        do {
            let rows: [Row] = try await client
                .from("anime")
                .select("id,title_english,title_romaji,next_episode_number,next_airing_at")
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            let items: [ReleaseScheduleItem] = rows.compactMap { row in
                guard let at = row.next_airing_at, at > Date() else { return nil }
                return ReleaseSchedulePolicy.item(fromAiring: UpcomingAiring(
                    anime_id: row.id, title_english: row.title_english, title_romaji: row.title_romaji,
                    next_episode_number: row.next_episode_number, next_airing_at: at))
            }
            if cacheable { storeSchedule(items, key: key) }
            return items
        } catch {
            if ReleaseFailure.classify(error) == .cancelled { throw CancellationError() }
            logFallback(.mediaSchedule, error)
            return []
        }
    }

    private func readThemes(animeId: Int, context: AccountContext, cacheKey key: String) async throws -> [ThemeSong] {
        guard let client, contractAvailable(.themes) else { return storeThemes([], key: key) }
        do {
            // Public catalog read: no account lease needed.
            let rows: LenientRows<ThemeSong> = try await client
                .rpc(ReleaseContract.themes.rawValue, params: RPCMediaThemesParams(p_anime_id: animeId))
                .execute()
                .value
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            return storeThemes(ReleaseSchedulePolicy.preparedThemes(rows.rows), key: key)
        } catch {
            switch ReleaseFailure.classify(error) {
            case .cancelled: throw CancellationError()
            case .notDeployed:
                markUndeployed(.themes)
                logFallback(.themes, error)
                return storeThemes([], key: key)
            case .transient:
                logFallback(.themes, error)
                return []
            }
        }
    }

    // MARK: Cache helpers

    private func cacheKey(_ context: AccountContext, _ parts: String...) -> String {
        ([context.userId.lowercased()] + parts).joined(separator: "|")
    }

    private func freshSchedule(_ key: String) -> [ReleaseScheduleItem]? {
        guard let cached = scheduleCache[key], Date().timeIntervalSince(cached.storedAt) < Self.scheduleTTL else { return nil }
        return cached.value
    }

    private func storeSchedule(_ items: [ReleaseScheduleItem], key: String) {
        scheduleCache[key] = TimedCache(value: items, storedAt: Date())
        trimTimedCache(&scheduleCache, maxEntries: 60)
    }

    @discardableResult
    private func storeThemes(_ songs: [ThemeSong], key: String) -> [ThemeSong] {
        themesCache[key] = TimedCache(value: songs, storedAt: Date())
        trimTimedCache(&themesCache, maxEntries: 60)
        return songs
    }

    /// Publishes the account's schedule while `context` is still current.
    private func publishSchedule(_ items: [ReleaseScheduleItem], context: AccountContext) -> [ReleaseScheduleItem] {
        guard accountSession.isCurrent(context) else { return [] }
        if schedule != items { schedule = items }
        return items
    }

    private func contractAvailable(_ contract: ReleaseContract, now: Date = Date()) -> Bool {
        guard let at = undeployedContracts[contract] else { return true }
        if now.timeIntervalSince(at) < Self.undeployedRetryInterval { return false }
        undeployedContracts[contract] = nil
        return true
    }

    private func markUndeployed(_ contract: ReleaseContract) {
        undeployedContracts[contract] = Date()
    }

    private func logFallback(_ contract: ReleaseContract, _ error: any Error) {
        #if DEBUG
        print("[Releases] \(contract.rawValue) unavailable, using fallback: \(error)")
        #endif
    }
}
#endif
