import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
// Social activity RPCs.
struct RPCFetchFriendActivityParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int

    enum CodingKeys: String, CodingKey { case p_media_type, p_media_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
    }
}

struct RPCUpsertTitleCommentParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int
    let p_text: String

    enum CodingKeys: String, CodingKey { case p_media_type, p_media_id, p_text }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
        try c.encode(p_text, forKey: .p_text)
    }
}

struct RPCDeleteTitleCommentParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int

    enum CodingKeys: String, CodingKey { case p_media_type, p_media_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
    }
}

struct RPCToggleCommentReactionParams: Encodable, Sendable {
    let p_comment_id: String
    let p_reaction_type: String

    enum CodingKeys: String, CodingKey { case p_comment_id, p_reaction_type }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_comment_id, forKey: .p_comment_id)
        try c.encode(p_reaction_type, forKey: .p_reaction_type)
    }
}

struct RPCCountFriendsTrackingParams: Encodable, Sendable {
    let p_items: String  // JSON string of [{media_type, media_id}, ...]

    enum CodingKeys: String, CodingKey { case p_items }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_items, forKey: .p_items)
    }
}
