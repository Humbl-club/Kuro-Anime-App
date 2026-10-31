import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
// Keyset-paged full-text search (rank, popularity, id cursor).
struct RPCSearchAnimePageParams: Encodable, Sendable {
    let p_query: String
    let p_limit: Int
    let p_cursor_rank: Double?
    let p_cursor_popularity: Int?
    let p_cursor_id: Int?
    let p_trending: Bool
    let p_new_season: Bool
    let p_classics: Bool
    let p_hidden_gems: Bool
    let p_airing_only: Bool
    let p_season: String?
    let p_season_year: Int?

    enum CodingKeys: String, CodingKey {
        case p_query
        case p_limit
        case p_cursor_rank
        case p_cursor_popularity
        case p_cursor_id
        case p_trending
        case p_new_season
        case p_classics
        case p_hidden_gems
        case p_airing_only
        case p_season
        case p_season_year
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_query, forKey: .p_query)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encodeIfPresent(p_cursor_rank, forKey: .p_cursor_rank)
        try c.encodeIfPresent(p_cursor_popularity, forKey: .p_cursor_popularity)
        try c.encodeIfPresent(p_cursor_id, forKey: .p_cursor_id)
        try c.encode(p_trending, forKey: .p_trending)
        try c.encode(p_new_season, forKey: .p_new_season)
        try c.encode(p_classics, forKey: .p_classics)
        try c.encode(p_hidden_gems, forKey: .p_hidden_gems)
        try c.encode(p_airing_only, forKey: .p_airing_only)
        try c.encodeIfPresent(p_season, forKey: .p_season)
        try c.encodeIfPresent(p_season_year, forKey: .p_season_year)
    }
}

struct RPCSearchMangaPageParams: Encodable, Sendable {
    let p_query: String
    let p_limit: Int
    let p_cursor_rank: Double?
    let p_cursor_popularity: Int?
    let p_cursor_id: Int?
    let p_trending: Bool
    let p_new_season: Bool
    let p_classics: Bool
    let p_hidden_gems: Bool

    enum CodingKeys: String, CodingKey {
        case p_query
        case p_limit
        case p_cursor_rank
        case p_cursor_popularity
        case p_cursor_id
        case p_trending
        case p_new_season
        case p_classics
        case p_hidden_gems
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_query, forKey: .p_query)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encodeIfPresent(p_cursor_rank, forKey: .p_cursor_rank)
        try c.encodeIfPresent(p_cursor_popularity, forKey: .p_cursor_popularity)
        try c.encodeIfPresent(p_cursor_id, forKey: .p_cursor_id)
        try c.encode(p_trending, forKey: .p_trending)
        try c.encode(p_new_season, forKey: .p_new_season)
        try c.encode(p_classics, forKey: .p_classics)
        try c.encode(p_hidden_gems, forKey: .p_hidden_gems)
    }
}
