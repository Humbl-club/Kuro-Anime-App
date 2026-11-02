import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
struct RPCCollectionAnimePageParams: Encodable, Sendable {
    let p_limit: Int
    let p_cursor_updated_at: Date?
    let p_cursor_row_id: Int?
    let p_list_type: String?

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_cursor_updated_at
        case p_cursor_row_id
        case p_list_type
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encodeIfPresent(p_cursor_updated_at, forKey: .p_cursor_updated_at)
        try c.encodeIfPresent(p_cursor_row_id, forKey: .p_cursor_row_id)
        try c.encodeIfPresent(p_list_type, forKey: .p_list_type)
    }
}

struct RPCCollectionMangaPageParams: Encodable, Sendable {
    let p_limit: Int
    let p_cursor_updated_at: Date?
    let p_cursor_row_id: Int?
    let p_list_type: String?

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_cursor_updated_at
        case p_cursor_row_id
        case p_list_type
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encodeIfPresent(p_cursor_updated_at, forKey: .p_cursor_updated_at)
        try c.encodeIfPresent(p_cursor_row_id, forKey: .p_cursor_row_id)
        try c.encodeIfPresent(p_list_type, forKey: .p_list_type)
    }
}

struct RPCCollectionFeedPageParams: Encodable, Sendable {
    let p_limit: Int
    let p_cursor_updated_at: Date?
    let p_cursor_source_rank: Int?
    let p_cursor_row_id: Int?
    let p_list_type_anime: String?
    let p_list_type_manga: String?

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_cursor_updated_at
        case p_cursor_source_rank
        case p_cursor_row_id
        case p_list_type_anime
        case p_list_type_manga
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encodeIfPresent(p_cursor_updated_at, forKey: .p_cursor_updated_at)
        try c.encodeIfPresent(p_cursor_source_rank, forKey: .p_cursor_source_rank)
        try c.encodeIfPresent(p_cursor_row_id, forKey: .p_cursor_row_id)
        try c.encodeIfPresent(p_list_type_anime, forKey: .p_list_type_anime)
        try c.encodeIfPresent(p_list_type_manga, forKey: .p_list_type_manga)
    }
}
