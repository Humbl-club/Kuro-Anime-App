import Foundation

// MARK: - Club models
// Wire shapes of the club RPCs (`fetch_club_bundle`, `fetch_club_bundle_loading`,
// `fetch_my_clubs_loading` / `fetch_my_clubs_enriched`, `create_club`, `join_club`, `leave_club`,
// `add_club_rail_item`, `cast_club_vote`, `create_club_rail`, `create_club_poll`,
// `toggle_club_reaction`, `check_club_activity_since`), moved verbatim from the former
// `SupabaseService` nested types (field names are the JSON keys). Owner: `ClubsStore`.
// Every type here is account- and membership-scoped: the bundle carries the caller's role,
// `my_*` fields, other members' statuses and the invite code.

struct ClubInfo: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let sharing_level: String
    let max_members: Int
    let is_archived: Bool
    let invite_code: String?
    let created_at: String
}

struct ClubMember: Decodable, Sendable {
    let user_id: String
    let display_name: String?
    let role: String
    let sharing_level: String
    let joined_at: String
}

struct ClubRailItem: Decodable, Sendable, Identifiable {
    let id: String
    let media_type: String
    let media_id: Int
    let sort_order: Int
    let note: String?
    /// Nil when the member who added the item has been deleted.
    let added_by: String?
    let title_display: String
    let cover_image_medium: String?
    let average_score: Int?
    let year: Int?
    let format: String?
    let episode_count: Int?
    let chapter_count: Int?
    let my_status: String?
    let my_progress: Int?
    let my_rating: Int?
    let member_status_counts: [String: Int]?
    let member_statuses: [MemberItemStatus]?
    let reactions: [String: Int]?
    let my_reactions: [String]?

    /// Total count for the relevant media type (episodes for anime, chapters for manga).
    var totalCount: Int? {
        media_type.uppercased() == "ANIME" ? episode_count : chapter_count
    }

    struct MemberItemStatus: Decodable, Sendable {
        let user_id: String
        let display_name: String?
        let status: String?
        let progress: Int?
        let updated_at: String?
    }
}

struct ClubRail: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let is_locked: Bool
    let sort_order: Int
    /// Nil when the member who created the rail has been deleted.
    let created_by: String?
    let items: [ClubRailItem]
}

struct ClubPollOption: Decodable, Sendable, Identifiable {
    let id: String
    let label: String
    let media_type: String?
    let media_id: Int?
    let sort_order: Int
    let vote_count: Int
}

struct ClubPoll: Decodable, Sendable, Identifiable {
    let id: String
    let question: String
    let is_closed: Bool
    let closes_at: String?
    /// Nil when the member who asked the question has been deleted.
    let created_by: String?
    let created_at: String
    let options: [ClubPollOption]
    let my_vote_option_id: String?
}

struct ClubBundle: Decodable, Sendable {
    let club: ClubInfo
    let members: [ClubMember]
    let my_role: String
    let my_sharing_level: String
    let rails: [ClubRail]
    let polls: [ClubPoll]
    let member_count: Int
}

struct ClubLoadingState: Decodable, Sendable {
    let state: String
    let visibility: String
}

struct ClubBundleLoading: Decodable, Sendable {
    let club: ClubInfo
    let members: [ClubMember]
    let my_role: String
    let my_sharing_level: String
    let rails: [ClubRail]
    let polls: [ClubPoll]
    let member_count: Int
    let rail_count: Int?
    let poll_count: Int?
    let last_activity_at: String?
    let activity_preview: String?
    let loading_state: ClubLoadingState?
}

struct CreateClubResponse: Decodable, Sendable {
    let club_id: String
    let invite_code: String
    let name: String
}

struct JoinClubResponse: Decodable, Sendable {
    let club_id: String
    let club_name: String
    let role: String
}

struct SimpleSuccessResponse: Decodable, Sendable {
    let success: Bool
}

struct AddRailItemResponse: Decodable, Sendable {
    let item_id: String
    let sort_order: Int
}

struct CreateRailResponse: Decodable, Sendable {
    let rail_id: String
    let title: String
}

struct CreatePollResponse: Decodable, Sendable {
    let poll_id: String
    let question: String
}

// Lightweight row for "My Clubs" list (fetched via enriched RPC)
struct ClubListRow: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let sharing_level: String
    let is_archived: Bool
    let created_at: String
    let member_count: Int?
    let rail_count: Int?
    let poll_count: Int?
    let last_activity_at: String?
    let activity_preview: String?
    let cover_images: [String]?
    let member_names: [String]?
    let loading_state: ClubLoadingState?
}

/// The state of the current account's my-clubs read (`ClubsStore.myClubsPhase`). Account-scoped:
/// it returns to `.idle` on every account transition and on a disclosure reset.
nonisolated indirect enum MyClubsPhase: Equatable, Sendable {
    /// Nothing read yet for this account (or the rows were dropped and a reload is pending).
    case idle
    /// A read is in flight; `previous` is the settled phase before it.
    case loading(previous: MyClubsPhase)
    /// The last read succeeded at `at`.
    case loaded(at: Date)
    /// The last read failed. `transport`: a network failure (offline, timeout, connection lost).
    case failed(transport: Bool)

    /// The phase without an in-flight read.
    var settled: MyClubsPhase {
        if case let .loading(previous) = self { return previous.settled }
        return self
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Whether the Clubs page should ask the server: no successful read yet, the last read failed,
    /// or it is older than `staleness`. A read already in flight is not repeated.
    static func needsRefresh(_ phase: MyClubsPhase, now: Date, staleness: TimeInterval) -> Bool {
        switch phase {
        case .loading:
            return false
        case .idle, .failed:
            return true
        case let .loaded(at):
            return now.timeIntervalSince(at) >= staleness || now < at
        }
    }
}

struct ToggleReactionResponse: Decodable, Sendable {
    let action: String // "added" | "removed"
    let emoji: String
}

struct ClubMediaActivityMatch: Sendable {
    let rail: ClubRail
    let item: ClubRailItem
}

struct ClubMediaActivity: Sendable {
    let club: ClubInfo
    let memberCount: Int
    let sharingLevel: String
    let members: [ClubMember]
    let matchingItems: [ClubMediaActivityMatch]
}

struct ClubActivityCheckResponse: Decodable, Sendable {
    let has_new_activity: Bool
    let latest_activity_at: String?
}
