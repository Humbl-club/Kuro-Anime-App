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
    let p_min_year: Int?
    let p_max_year: Int?
    let p_format: String?
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
        case p_min_year
        case p_max_year
        case p_format
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
        try c.encodeIfPresent(p_min_year, forKey: .p_min_year)
        try c.encodeIfPresent(p_max_year, forKey: .p_max_year)
        try c.encodeIfPresent(p_format, forKey: .p_format)
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
    let p_min_year: Int?
    let p_max_year: Int?
    let p_format: String?
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
        case p_min_year
        case p_max_year
        case p_format
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
        try c.encodeIfPresent(p_min_year, forKey: .p_min_year)
        try c.encodeIfPresent(p_max_year, forKey: .p_max_year)
        try c.encodeIfPresent(p_format, forKey: .p_format)
        try c.encode(p_limit, forKey: .p_limit)
    }
}

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

// Club chat RPCs.
struct RPCSendClubMessageParams: Encodable, Sendable {
    let p_club_id: String
    let p_text: String

    enum CodingKeys: String, CodingKey { case p_club_id, p_text }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_club_id, forKey: .p_club_id)
        try c.encode(p_text, forKey: .p_text)
    }
}

struct RPCFetchClubMessagesParams: Encodable, Sendable {
    let p_club_id: String
    let p_limit: Int
    let p_before: String?

    enum CodingKeys: String, CodingKey { case p_club_id, p_limit, p_before }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_club_id, forKey: .p_club_id)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encodeIfPresent(p_before, forKey: .p_before)
    }
}

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

// Tag-overlap similarity (detail pages / concierge).
struct RPCRecommendSimilarParams: Encodable, Sendable {
    let p_media_type: String // "ANIME" | "MANGA"
    let p_seed_ids: [Int]
    let p_limit: Int
    let p_allow_gimmicks: Bool

    enum CodingKeys: String, CodingKey {
        case p_media_type
        case p_seed_ids
        case p_limit
        case p_allow_gimmicks
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_seed_ids, forKey: .p_seed_ids)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encode(p_allow_gimmicks, forKey: .p_allow_gimmicks)
    }
}
