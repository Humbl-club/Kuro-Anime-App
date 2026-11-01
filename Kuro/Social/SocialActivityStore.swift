import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Social Activity (Friend Comments & Indicators)
// Owner of the title-level social layer: friend counts on cards (`friendTrackingCounts`, filled by
// `prefetchFriendCounts`), the friends' activity + comments of one title and the comment/reaction
// writes. A "friend" is a member of a club the caller belongs to (`shares_club_with` server-side).
//
// Account and permission scope: everything here derives from the current account's club
// memberships, so two generations guard it:
// - the account (`AccountContext`): the session funnel cancels the prefetch and empties the counts on
//   every transition (`AccountScopedState`);
// - the friend scope (`friendScopeGeneration`, F03): a club revocation (the caller left or was removed)
//   changes the friend set WITHOUT a transition; the Clubs owner calls `invalidateFriendProjection()`,
//   which bumps it. It is distinct from the account and from public catalog lifetime, and it is
//   observed: the detail section re-reads its friends' activity whenever it changes.
// Every read and write captures what it depends on before its first suspension and rechecks it before
// handing anything out: friend counts and the friends' activity need the account AND the friend scope;
// a reaction (on a friend's comment) needs both; the caller's own comment needs the account. A stale
// completion, success or failure, ends in `CancellationError`.
// Writes run as credential leases of their account (F33, `AccountSessionCoordinator.withCredentialLease`):
// never dispatched once their account ended, never with another account's token.

@MainActor
@Observable
final class SocialActivityStore: AccountScopedState {

    nonisolated struct TitleComment: Decodable, Sendable, Identifiable {
        let id: String
        let user_id: String
        let display_name: String?
        let text: String
        let created_at: String
        let updated_at: String
        let is_own: Bool
        let up_count: Int
        let down_count: Int
        let my_reaction: String?
        let spoiler_scope: String?
    }

    nonisolated struct FriendTitleActivity: Decodable, Sendable {
        let user_id: String
        let display_name: String?
        let status: String?
        let progress: Int?
        let rating: Int?
        let updated_at: String?
    }

    nonisolated struct FriendActivityResponse: Decodable, Sendable {
        let friends_tracking: [FriendTitleActivity]
        let comments: [TitleComment]
        let own_comment: TitleComment?
        let comments_next: CommentCursor?
        let friends_next: String?

        nonisolated struct CommentCursor: Decodable, Sendable { let at: String; let id: String }
    }

    nonisolated struct FriendCountItem: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let count: Int
    }

    nonisolated struct UpsertCommentResponse: Decodable, Sendable {
        let id: String
        let user_id: String
        let text: String
        let created_at: String
        let updated_at: String
    }

    nonisolated struct ToggleCommentReactionResponse: Decodable, Sendable {
        let toggled_on: Bool
        let reaction_type: String
    }

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every request fails like a transport error (`requiredClient()`).
    private let client: SupabaseClient?
    /// The shared account coordinator (every completion is checked against it).
    let accountSession: AccountSessionCoordinator

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator) {
        self.client = client
        self.accountSession = accountSession
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    /// Club-mates tracking each title, keyed "<mediaType>-<id>" (case-sensitive, as requested).
    var friendTrackingCounts: [String: Int] = [:]
    /// The most recently started friend-count prefetch (callers and tests may await it).
    @ObservationIgnored var friendCountPrefetchTask: Task<Void, Never>?
    /// Every friend-count prefetch still running, by id. Prefetches of different screens no longer
    /// cancel each other (Discover's counts used to be dropped by a Browse page, and vice versa); the
    /// account funnel and a club revocation cancel all of them.
    @ObservationIgnored private var friendCountPrefetchTasks: [UUID: Task<Void, Never>] = [:]
    /// Keys being requested right now, with the prefetch that owns them.
    @ObservationIgnored private var friendCountInFlight: [String: UUID] = [:]
    /// When each key's count was last stored (`friendCountTTL`): a fresh key is not requested again.
    @ObservationIgnored private var friendCountFetchedAt: [String: Date] = [:]
    /// How long a friend count is reused before a prefetch asks for it again.
    nonisolated static let friendCountTTL: TimeInterval = 120
    /// The friend-scope (permission) generation (F03): changes on every club revocation and every
    /// account transition, never returns to an earlier value. Views compare it for equality only.
    private(set) var friendScopeGeneration = 0

    // MARK: AccountScopedState

    func cancelAccountWork() {
        friendCountPrefetchTask?.cancel()
        friendCountPrefetchTask = nil
        for task in friendCountPrefetchTasks.values { task.cancel() }
        friendCountPrefetchTasks.removeAll()
        friendCountInFlight.removeAll()
    }

    func clearPrivateState() {
        friendTrackingCounts.removeAll()
        friendCountFetchedAt.removeAll()
        friendScopeGeneration += 1
    }

    /// Drops the friend projection after a club revocation (the caller left a club or was removed
    /// from one, so the set of friends shrank while the account stayed signed in): cancels the
    /// in-flight count prefetch (its result derives from the old memberships), empties the counts and
    /// moves the friend scope on, so no read or reaction started under the old memberships hands
    /// anything out and the detail section re-reads its friends' activity. Wired by the Clubs owner.
    func invalidateFriendProjection() {
        cancelAccountWork()
        clearPrivateState()
    }

    /// What a friend-scoped call was started under: the account and the friend scope.
    private struct FriendScope {
        let context: AccountContext?
        let generation: Int
    }

    private var currentFriendScope: FriendScope {
        FriendScope(context: accountSession.current, generation: friendScopeGeneration)
    }

    private func isCurrent(_ scope: FriendScope) -> Bool {
        accountSession.isCurrent(scope.context) && scope.generation == friendScopeGeneration
    }

    // MARK: - Title activity and comments

    /// The friends' activity and comments of one title. Throws `CancellationError` when the account
    /// that asked, or its friend scope (a club revocation meanwhile), is no longer current by the time
    /// the answer (or a failure) arrives.
    func fetchFriendActivityForTitle(mediaType: String, mediaId: Int, paged: Bool = false, commentCursor: FriendActivityResponse.CommentCursor? = nil, friendCursor: String? = nil) async throws -> FriendActivityResponse {
        let scope = currentFriendScope
        do {
            let client = try requiredClient()
            let params = RPCFetchFriendActivityParams(p_media_type: mediaType, p_media_id: mediaId)
            let response: FriendActivityResponse = try await accountSession.withCredentialLease(for: accountSession.current) {
                if paged {
                    struct Page: Encodable {
                        let p_media_type: String; let p_media_id: Int
                        let p_after_comment_at: String?; let p_after_comment_id: String?; let p_after_friend: String?
                    }
                    return try await client.rpc("friend_activity_page_v1", params: Page(p_media_type: mediaType, p_media_id: mediaId,
                        p_after_comment_at: commentCursor?.at, p_after_comment_id: commentCursor?.id, p_after_friend: friendCursor)).execute().value
                }
                return try await client.rpc("fetch_friend_activity_for_title", params: params).execute().value
            }
            // Derived from this account's club memberships at that time: never handed out after the
            // account or its memberships changed.
            guard isCurrent(scope) else { throw CancellationError() }
            return response
        } catch {
            guard isCurrent(scope) else { throw CancellationError() }
            throw error
        }
    }

    /// The caller's own comment on a title. A success or failure of an account that is no longer
    /// current ends in `CancellationError`.
    func upsertTitleComment(mediaType: String, mediaId: Int, text: String, spoilerScope: String? = nil) async throws -> UpsertCommentResponse {
        let context = accountSession.current
        let params = RPCUpsertTitleCommentParams(p_media_type: mediaType, p_media_id: mediaId, p_text: text)
        return try await accountWrite(context) { client in
            if let spoilerScope {
                struct Scoped: Encodable { let p_media_type: String; let p_media_id: Int; let p_text: String; let p_spoiler_scope: String }
                return try await client.rpc("upsert_title_comment_scoped_v1", params: Scoped(p_media_type: mediaType, p_media_id: mediaId, p_text: text, p_spoiler_scope: spoilerScope)).execute().value
            }
            return try await client
                .rpc("upsert_title_comment", params: params)
                .execute()
                .value
        }
    }

    func deleteTitleComment(mediaType: String, mediaId: Int) async throws {
        let context = accountSession.current
        let params = RPCDeleteTitleCommentParams(p_media_type: mediaType, p_media_id: mediaId)
        try await accountWrite(context) { client in
            _ = try await client
                .rpc("delete_title_comment", params: params)
                .execute()
        }
    }

    /// A reaction on a friend's comment: needs the account AND the friend scope (after a revocation
    /// the comment's author may no longer be a friend, so its outcome is not handed out).
    func toggleCommentReaction(commentId: String, reactionType: String) async throws -> ToggleCommentReactionResponse {
        let scope = currentFriendScope
        let params = RPCToggleCommentReactionParams(p_comment_id: commentId, p_reaction_type: reactionType)
        do {
            let response: ToggleCommentReactionResponse = try await accountWrite(scope.context) { client in
                try await client
                    .rpc("toggle_comment_reaction", params: params)
                    .execute()
                    .value
            }
            guard isCurrent(scope) else { throw CancellationError() }
            return response
        } catch {
            guard isCurrent(scope) else { throw CancellationError() }
            throw error
        }
    }

    /// One private write of `context` as a credential lease (F33); its success and failure are handed
    /// out only while `context` is still current (`CancellationError` otherwise).
    private func accountWrite<T: Sendable>(
        _ context: AccountContext?,
        _ write: @escaping @MainActor (SupabaseClient) async throws -> T
    ) async throws -> T {
        do {
            let client = try requiredClient()
            let value = try await accountSession.withCredentialLease(for: context) { try await write(client) }
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            return value
        } catch {
            guard accountSession.isCurrent(context) else { throw CancellationError() }
            throw error
        }
    }

    // Friend count cache for card indicators

    func friendCount(mediaId: Int, mediaType: String) -> Int {
        friendTrackingCounts["\(mediaType)-\(mediaId)"] ?? 0
    }

    /// Requests the friend counts of `items` in batches of 100. Keys stored within `friendCountTTL` or
    /// already being requested by another prefetch are skipped; when nothing is left, no request is
    /// made. A key is marked fresh only after its batch answered under the current account and friend
    /// scope.
    func prefetchFriendCounts(items: [(mediaType: String, mediaId: Int)]) {
        let pending = Self.friendCountKeysToRequest(
            items.map { Self.friendCountKey(mediaType: $0.mediaType, mediaId: $0.mediaId) },
            fetchedAt: friendCountFetchedAt,
            inFlight: Set(friendCountInFlight.keys),
            now: Date(),
            ttl: Self.friendCountTTL
        )
        guard !pending.isEmpty else { return }
        let pendingSet = Set(pending)
        var seen = Set<String>()
        let requested = items.filter { item in
            let key = Self.friendCountKey(mediaType: item.mediaType, mediaId: item.mediaId)
            return pendingSet.contains(key) && seen.insert(key).inserted
        }
        let scope = currentFriendScope
        let id = UUID()
        for key in pending { friendCountInFlight[key] = id }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishFriendCountPrefetch(id, keys: pending) }
            do {
                let client = try requiredClient()
                // Each batch is bounded before entering the RPC; never one request per card.
                for start in stride(from: 0, to: requested.count, by: 100) {
                    guard !Task.isCancelled, self.isCurrent(scope) else { return }
                    let batch = requested[start..<min(start + 100, requested.count)]
                    let payload = batch.map { ["media_type": $0.mediaType, "media_id": "\($0.mediaId)"] }
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    guard let jsonString = String(data: data, encoding: .utf8) else { return }
                    let counts: [FriendCountItem] = try await accountSession.withCredentialLease(for: scope.context) {
                        try await client.rpc("count_friends_tracking", params: RPCCountFriendsTrackingParams(p_items: jsonString)).execute().value
                    }
                    guard !Task.isCancelled, self.isCurrent(scope) else { return }
                    // Zero-result titles are omitted by the server. Replace this batch's
                    // projection rather than retaining an earlier member's count.
                    let now = Date()
                    for item in batch {
                        let key = Self.friendCountKey(mediaType: item.mediaType, mediaId: item.mediaId)
                        self.friendTrackingCounts[key] = 0
                        self.friendCountFetchedAt[key] = now
                    }
                    for item in counts {
                        self.friendTrackingCounts[Self.friendCountKey(mediaType: item.media_type, mediaId: item.media_id)] = item.count
                    }
                }
            } catch {
                #if DEBUG
                print("[SocialActivity] prefetchFriendCounts error: \(error.localizedDescription)")
                #endif
            }
        }
        friendCountPrefetchTasks[id] = task
        friendCountPrefetchTask = task
    }

    /// Releases the keys a prefetch still owns (a newer prefetch after a reset may own them now).
    private func finishFriendCountPrefetch(_ id: UUID, keys: [String]) {
        friendCountPrefetchTasks[id] = nil
        for key in keys where friendCountInFlight[key] == id {
            friendCountInFlight[key] = nil
        }
    }

    /// The count key of one title ("<mediaType>-<id>", case-sensitive, as requested).
    nonisolated static func friendCountKey(mediaType: String, mediaId: Int) -> String {
        "\(mediaType)-\(mediaId)"
    }

    /// The keys of `keys` a prefetch should request: de-duplicated in first-seen order, without keys
    /// being requested (`inFlight`) or stored less than `ttl` ago.
    nonisolated static func friendCountKeysToRequest(
        _ keys: [String],
        fetchedAt: [String: Date],
        inFlight: Set<String>,
        now: Date,
        ttl: TimeInterval
    ) -> [String] {
        var seen = Set<String>()
        return keys.filter { key in
            guard seen.insert(key).inserted, !inFlight.contains(key) else { return false }
            if let stored = fetchedAt[key], now.timeIntervalSince(stored) < ttl { return false }
            return true
        }
    }
}
#endif
