import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
struct RPCGetMediaLadderParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int

    enum CodingKeys: String, CodingKey {
        case p_media_type
        case p_media_id
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
    }
}

struct RPCEnqueueMediaRelationRefreshParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int
    let p_reason: String

    enum CodingKeys: String, CodingKey {
        case p_media_type
        case p_media_id
        case p_reason
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
        try c.encode(p_reason, forKey: .p_reason)
    }
}
