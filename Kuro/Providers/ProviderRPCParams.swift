import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
// Streaming availability RPCs.
struct RPCBatchProvidersParams: Encodable, Sendable {
    let p_items: String

    enum CodingKeys: String, CodingKey { case p_items }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_items, forKey: .p_items)
    }
}

struct RPCSaveStreamingServicesParams: Encodable, Sendable {
    let p_services: [String]

    enum CodingKeys: String, CodingKey { case p_services }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_services, forKey: .p_services)
    }
}

struct RPCBatchProviderAvailabilityV2Params: Encodable, Sendable {
    let p_items: String
    let p_audio_lang: String?
    let p_sub_lang: String?
    let p_include_unknown: Bool

    enum CodingKeys: String, CodingKey {
        case p_items
        case p_audio_lang
        case p_sub_lang
        case p_include_unknown
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_items, forKey: .p_items)
        try c.encodeIfPresent(p_audio_lang, forKey: .p_audio_lang)
        try c.encodeIfPresent(p_sub_lang, forKey: .p_sub_lang)
        try c.encode(p_include_unknown, forKey: .p_include_unknown)
    }
}
struct RPCEnqueueMediaAvailabilityRefreshParams: Encodable, Sendable {
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

struct RPCGetMediaAvailabilityStatusParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int

    enum CodingKeys: String, CodingKey { case p_media_type, p_media_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_media_id, forKey: .p_media_id)
    }
}
