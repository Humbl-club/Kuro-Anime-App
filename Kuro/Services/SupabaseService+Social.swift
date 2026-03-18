import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

extension SupabaseService {
// MARK: - Social Activity (Friend Comments & Indicators)

    struct TitleComment: Decodable, Sendable, Identifiable {
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
    }

    struct FriendTitleActivity: Decodable, Sendable {
        let user_id: String
        let display_name: String?
        let status: String?
        let progress: Int?
        let rating: Int?
        let updated_at: String?
    }

    struct FriendActivityResponse: Decodable, Sendable {
        let friends_tracking: [FriendTitleActivity]
        let comments: [TitleComment]
    }

    struct FriendCountItem: Decodable, Sendable {
        let media_type: String
        let media_id: Int
        let count: Int
    }

    struct UpsertCommentResponse: Decodable, Sendable {
        let id: String
        let user_id: String
        let text: String
        let created_at: String
        let updated_at: String
    }

    struct ToggleCommentReactionResponse: Decodable, Sendable {
        let toggled_on: Bool
        let reaction_type: String
    }

    func fetchFriendActivityForTitle(mediaType: String, mediaId: Int) async throws -> FriendActivityResponse {
        let params = RPCFetchFriendActivityParams(p_media_type: mediaType, p_media_id: mediaId)
        return try await client
            .rpc("fetch_friend_activity_for_title", params: params)
            .execute()
            .value
    }

    func upsertTitleComment(mediaType: String, mediaId: Int, text: String) async throws -> UpsertCommentResponse {
        let params = RPCUpsertTitleCommentParams(p_media_type: mediaType, p_media_id: mediaId, p_text: text)
        return try await client
            .rpc("upsert_title_comment", params: params)
            .execute()
            .value
    }

    func deleteTitleComment(mediaType: String, mediaId: Int) async throws {
        let params = RPCDeleteTitleCommentParams(p_media_type: mediaType, p_media_id: mediaId)
        try await client
            .rpc("delete_title_comment", params: params)
            .execute()
    }

    func toggleCommentReaction(commentId: String, reactionType: String) async throws -> ToggleCommentReactionResponse {
        let params = RPCToggleCommentReactionParams(p_comment_id: commentId, p_reaction_type: reactionType)
        return try await client
            .rpc("toggle_comment_reaction", params: params)
            .execute()
            .value
    }

    // Friend count cache for card indicators

    func friendCount(mediaId: Int, mediaType: String) -> Int {
        friendTrackingCounts["\(mediaType)-\(mediaId)"] ?? 0
    }

    func prefetchFriendCounts(items: [(mediaType: String, mediaId: Int)]) {
        friendCountPrefetchTask?.cancel()
        friendCountPrefetchTask = Task { [weak self] in
            guard let self, !items.isEmpty else { return }
            let payload = items.map { ["media_type": $0.mediaType, "media_id": "\($0.mediaId)"] }
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            do {
                let params = RPCCountFriendsTrackingParams(p_items: jsonString)
                let counts: [FriendCountItem] = try await client
                    .rpc("count_friends_tracking", params: params)
                    .execute()
                    .value
                guard !Task.isCancelled else { return }
                for item in counts {
                    self.friendTrackingCounts["\(item.media_type)-\(item.media_id)"] = item.count
                }
            } catch {
                #if DEBUG
                print("[SocialActivity] prefetchFriendCounts error: \(error.localizedDescription)")
                #endif
            }
        }
    }

}
#endif
