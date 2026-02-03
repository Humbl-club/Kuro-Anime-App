import Foundation

// PostgREST RPC params must be `Encodable & Sendable` (Supabase Swift enforces this).
// Keep these types at top-level so they're not implicitly MainActor-isolated.

struct RPCDiscoverBundleParams: Encodable, Sendable {
    let p_limit: Int
    let p_hours: Int

    enum CodingKeys: String, CodingKey {
        case p_limit
        case p_hours
    }

    // `rpc(params:)` requires a `Sendable` param; with default isolation set to MainActor,
    // we provide a `nonisolated` encoder to keep this conformance usable from background contexts.
    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encode(p_hours, forKey: .p_hours)
    }
}

struct RPCBrowseAnimePageParams: Encodable, Sendable {
    let p_genre: String?
    let p_status: String?
    let p_min_episodes: Int?
    let p_max_episodes: Int?
    let p_sort: String
    let p_cursor_int: Int?
    let p_cursor_ts: Date?
    let p_cursor_id: Int?
    let p_limit: Int

    enum CodingKeys: String, CodingKey {
        case p_genre
        case p_status
        case p_min_episodes
        case p_max_episodes
        case p_sort
        case p_cursor_int
        case p_cursor_ts
        case p_cursor_id
        case p_limit
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(p_genre, forKey: .p_genre)
        try c.encodeIfPresent(p_status, forKey: .p_status)
        try c.encodeIfPresent(p_min_episodes, forKey: .p_min_episodes)
        try c.encodeIfPresent(p_max_episodes, forKey: .p_max_episodes)
        try c.encode(p_sort, forKey: .p_sort)
        try c.encodeIfPresent(p_cursor_int, forKey: .p_cursor_int)
        try c.encodeIfPresent(p_cursor_ts, forKey: .p_cursor_ts)
        try c.encodeIfPresent(p_cursor_id, forKey: .p_cursor_id)
        try c.encode(p_limit, forKey: .p_limit)
    }
}

struct RPCBrowseMangaPageParams: Encodable, Sendable {
    let p_genre: String?
    let p_status: String?
    let p_min_chapters: Int?
    let p_max_chapters: Int?
    let p_sort: String
    let p_cursor_int: Int?
    let p_cursor_ts: Date?
    let p_cursor_id: Int?
    let p_limit: Int

    enum CodingKeys: String, CodingKey {
        case p_genre
        case p_status
        case p_min_chapters
        case p_max_chapters
        case p_sort
        case p_cursor_int
        case p_cursor_ts
        case p_cursor_id
        case p_limit
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(p_genre, forKey: .p_genre)
        try c.encodeIfPresent(p_status, forKey: .p_status)
        try c.encodeIfPresent(p_min_chapters, forKey: .p_min_chapters)
        try c.encodeIfPresent(p_max_chapters, forKey: .p_max_chapters)
        try c.encode(p_sort, forKey: .p_sort)
        try c.encodeIfPresent(p_cursor_int, forKey: .p_cursor_int)
        try c.encodeIfPresent(p_cursor_ts, forKey: .p_cursor_ts)
        try c.encodeIfPresent(p_cursor_id, forKey: .p_cursor_id)
        try c.encode(p_limit, forKey: .p_limit)
    }
}
