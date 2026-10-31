import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
// Club RPCs.
struct RPCCreateClubParams: Encodable, Sendable {
    let p_name: String
    let p_description: String?
    let p_sharing_level: String

    enum CodingKeys: String, CodingKey {
        case p_name, p_description, p_sharing_level
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_name, forKey: .p_name)
        try c.encodeIfPresent(p_description, forKey: .p_description)
        try c.encode(p_sharing_level, forKey: .p_sharing_level)
    }
}

struct RPCJoinClubParams: Encodable, Sendable {
    let p_invite_code: String

    enum CodingKeys: String, CodingKey { case p_invite_code }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_invite_code, forKey: .p_invite_code)
    }
}

struct RPCClubIdParams: Encodable, Sendable {
    let p_club_id: String

    enum CodingKeys: String, CodingKey { case p_club_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_club_id, forKey: .p_club_id)
    }
}

struct RPCAddRailItemParams: Encodable, Sendable {
    let p_rail_id: String
    let p_media_type: String
    let p_media_id: Int
    let p_note: String?

    enum CodingKeys: String, CodingKey {
        case p_rail_id, p_media_type, p_media_id, p_note
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_rail_id, forKey: .p_rail_id)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
        try c.encodeIfPresent(p_note, forKey: .p_note)
    }
}

struct RPCCastVoteParams: Encodable, Sendable {
    let p_poll_id: String
    let p_option_id: String

    enum CodingKeys: String, CodingKey { case p_poll_id, p_option_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_poll_id, forKey: .p_poll_id)
        try c.encode(p_option_id, forKey: .p_option_id)
    }
}

struct RPCCreateClubRailParams: Encodable, Sendable {
    let p_club_id: String
    let p_title: String
    let p_description: String?

    enum CodingKeys: String, CodingKey { case p_club_id, p_title, p_description }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_club_id, forKey: .p_club_id)
        try c.encode(p_title, forKey: .p_title)
        try c.encodeIfPresent(p_description, forKey: .p_description)
    }
}

struct RPCCreateClubPollParams: Encodable, Sendable {
    let p_club_id: String
    let p_question: String
    let p_options: [String]

    enum CodingKeys: String, CodingKey { case p_club_id, p_question, p_options }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_club_id, forKey: .p_club_id)
        try c.encode(p_question, forKey: .p_question)
        try c.encode(p_options, forKey: .p_options)
    }
}

struct RPCToggleReactionParams: Encodable, Sendable {
    let p_rail_item_id: String
    let p_emoji: String

    enum CodingKeys: String, CodingKey { case p_rail_item_id, p_emoji }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_rail_item_id, forKey: .p_rail_item_id)
        try c.encode(p_emoji, forKey: .p_emoji)
    }
}
