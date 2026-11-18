import Foundation
import KuroCore

// MARK: - W5 guest browsing: pure rules
// No state, no requests. `GuestSession` holds the one in-memory intent; the root, the pager and the
// read guards consult these rules. The whole feature is behind `guest_browsing_v1` (0 %).

/// What a guest tried to do before signing up. Held in memory only; replayed once after sign-up.
nonisolated enum PendingGuestIntent: Equatable, Sendable {
    case plan(MediaKey, title: String)
    case discoverAnswer(MediaKey, DiscoverFeedback, title: String)
    case joinClub(code: String)
    /// Tracking editor, add to club, bell: re-open the title after sign-up.
    case openTitle(MediaKey)
}

/// The sign-up tool sheet's request: the intent to finish afterwards and the form's starting mode.
nonisolated struct GuestSignUpRequest: Equatable, Sendable, Identifiable {
    let intent: PendingGuestIntent?
    /// `.signUp` from actions, `.signIn` from the header.
    let mode: AuthFormRules.Mode
    var id: String { "signUp" }
}

/// Which surface the root shows. Pure: the same inputs always give the same answer.
nonisolated enum RootPresentation: Equatable {
    case configError, bootstrapping, setPassword, signedIn(userId: String), guest, authWall

    static func resolve(configError: Bool, isBootstrapping: Bool, isAuthenticated: Bool,
                        requiresPasswordUpdate: Bool, userId: String?, guestEnabled: Bool) -> RootPresentation {
        if configError { return .configError }
        if isBootstrapping { return .bootstrapping }
        if isAuthenticated && requiresPasswordUpdate { return .setPassword }
        if isAuthenticated { return .signedIn(userId: userId ?? "") }
        return guestEnabled ? .guest : .authWall
    }
}

/// The guest pager. It mirrors the live signed-in order; Browse is reached from Discover and Search.
enum GuestPager {
    static let order: [KuroMainView.Section] = [.taste, .home, .discover, .collection, .clubs]
    static let invitationSections: Set<KuroMainView.Section> = [.taste, .home, .collection, .clubs]
}

/// Swift mirror of the anonymous read surface (the SQL allowlist of
/// `20261118110000_guest_anon_allowlist_v1.sql`, guest pages only, plus the public catalogue tables).
/// A guest request outside this set is a bug and a wasted anonymous request.
nonisolated enum GuestReadAllowlist {
    static let rpcs: Set<String> = [
        "rpc/discover_bundle", "rpc/discover_section_page_v1", "rpc/discover_mood_v1",
        "rpc/media_franchise_ids_v1", "rpc/recommend_ids_similar_to_seeds", "rpc/media_similar_v1",
        "rpc/browse_anime_page", "rpc/browse_manga_page", "rpc/search_anime_page", "rpc/search_manga_page",
        "rpc/get_media_ladder", "rpc/get_manga_chapter_status", "rpc/media_release_schedule_v1",
        "rpc/media_themes_v1", "rpc/anime_cast_v1", "rpc/character_voice_actors_v1", "rpc/staff_voice_roles_v1",
        "rpc/search_anime_page_v2", "rpc/search_manga_page_v2",
    ]

    static let tables: Set<String> = [
        "anime", "manga", "episodes", "chapters", "anime_characters", "anime_staff", "anime_studios",
        "manga_characters", "manga_authors", "manga_staff", "external_links", "characters", "staff",
        "studios", "authors", "anime_tags", "manga_tags", "tags", "character_voice_actors", "theme_links",
        "feature_flags", "mv_anime_trending",
    ]

    /// True for an allowlisted RPC or a public catalogue table; a query string is ignored.
    static func permits(resource: String) -> Bool {
        let name = resource.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? resource
        return rpcs.contains(name) || tables.contains(name)
    }
}
