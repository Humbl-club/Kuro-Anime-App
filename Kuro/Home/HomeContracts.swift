import Foundation

struct HomeMaterial: Codable, Equatable, Sendable {
    let imageDigest: String?
    let base: String?
    let deep: String?
    let wash: String?
    let edge: String?
    let ink: String?

    enum CodingKeys: String, CodingKey {
        case imageDigest = "image_digest"
        case base, deep, wash, edge, ink
    }
}

struct HomeCard: Codable, Equatable, Identifiable, Sendable {
    var id: String { seriesId ?? "entry:\(mediaId)" }
    let mediaId: Int
    let listType: String
    let progress: Int
    let progressLabel: String?
    let volumesProgress: Int?
    let serverRevision: Int64
    let lifecycleId: String
    let unitId: String?
    let title: String
    let bannerImage: String?
    let coverImage: String?
    let format: String?
    let episodes: Int?
    let chapters: Int?
    let volumes: Int?
    let catalogueStatus: String?
    let seriesId: String?
    let sectionOrdinal: Int?
    let sectionKind: String?
    let sectionName: String?
    let material: HomeMaterial?

    enum CodingKeys: String, CodingKey {
        case mediaId = "media_id"
        case listType = "list_type"
        case progress
        case progressLabel = "progress_label"
        case volumesProgress = "volumes_progress"
        case serverRevision = "server_revision"
        case lifecycleId = "lifecycle_id"
        case unitId = "unit_id"
        case title
        case bannerImage = "banner_image"
        case coverImage = "cover_image"
        case format, episodes, chapters, volumes
        case catalogueStatus = "catalogue_status"
        case seriesId = "series_id"
        case sectionOrdinal = "section_ordinal"
        case sectionKind = "section_kind"
        case sectionName = "section_name"
        case material
    }

    var seasonStamp: String? {
        guard let sectionOrdinal, sectionKind != "film" else {
            return sectionKind == "film" ? "Film" : nil
        }
        return "S\(sectionOrdinal)"
    }

    var seasonTitle: String? {
        if sectionKind == "film" { return "Film" }
        guard let sectionOrdinal else { return nil }
        return sectionName ?? "Season \(sectionOrdinal)"
    }
}

struct HomeEvent: Codable, Equatable, Identifiable, Sendable {
    let mediaId: Int
    let title: String
    let at: String?
    let precision: String?
    let sourceLocalDate: String?
    let unitLabel: String?
    let coverImage: String?
    let status: String?
    var eventId: String? = nil

    var id: String { eventId ?? "\(mediaId)-\(at ?? sourceLocalDate ?? unitLabel ?? "pending")" }

    enum CodingKeys: String, CodingKey {
        case mediaId = "media_id"
        case title, at, precision
        case sourceLocalDate = "source_local_date"
        case unitLabel = "unit_label"
        case coverImage = "cover_image"
        case status
        case eventId = "event_id"
    }
}

struct HomeClubItem: Decodable, Equatable, Identifiable, Sendable {
    let commentId: String
    let mediaId: Int
    let mediaType: String
    let spoilerScope: String?
    let text: String?
    let displayName: String?
    let createdAt: String?

    var id: String { commentId }

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case spoilerScope = "spoiler_scope"
        case text
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct HomeClubSlice: Decodable, Equatable, Sendable {
    let state: String
    let label: String
    let items: [HomeClubItem]
}

struct HomeProgressConflict: Equatable, Sendable {
    let key: String
    let title: String
    let localPosition: Int
    let serverPosition: Int
    let serverRevision: Int64
    let lifecycleId: UUID
    let medium: String
    let mediaId: Int
}

struct HomeConfirmedProgress: Sendable {
    let position: Int
    let revision: Int64
    let lifecycleId: UUID
}

struct HomeAck: Equatable, Sendable {
    let priorPosition: Int
    let revision: Int64
    let lifecycleId: UUID
}

struct HomeBundle: Decodable, Equatable, Sendable {
    let medium: String
    let windowDays: Int
    let homeRevision: Int64
    let active: [HomeCard]
    var upcoming: [HomeEvent]
    var pending: [HomeEvent]
    let scheduleState: String
    let nextCursor: String?
    let club: HomeClubSlice
    var upcomingTotal:Int? = nil
    var eventsCursor:String? = nil
    var pendingTotal: Int? = nil
    var pendingCursor: String? = nil

    func withoutClubContent() -> HomeBundle {
        HomeBundle(medium: medium, windowDays: windowDays, homeRevision: homeRevision,
                   active: active, upcoming: upcoming, pending: pending, scheduleState: scheduleState,
                   nextCursor: nextCursor, club: HomeClubSlice(state: "reauthorizing", label: "Between us.", items: []),upcomingTotal:upcomingTotal,eventsCursor:eventsCursor,pendingTotal:pendingTotal,pendingCursor:pendingCursor)
    }

    func appendingActive(_ more: [HomeCard], cursor: String?) -> HomeBundle {
        HomeBundle(
            medium: medium,
            windowDays: windowDays,
            homeRevision: homeRevision,
            active: active + more.filter { item in !active.contains(where: { $0.id == item.id }) },
            upcoming: upcoming,
            pending: pending,
            scheduleState: scheduleState,
            nextCursor: cursor,
            club: club,upcomingTotal:upcomingTotal,eventsCursor:eventsCursor,pendingTotal:pendingTotal,pendingCursor:pendingCursor
        )
    }

    enum CodingKeys: String, CodingKey {
        case medium
        case windowDays = "window_days"
        case homeRevision = "home_revision"
        case active, upcoming, pending
        case scheduleState = "schedule_state"
        case nextCursor = "next_cursor"
        case club
        case upcomingTotal="upcoming_total",eventsCursor="events_cursor"
        case pendingTotal="pending_total",pendingCursor="pending_cursor"
    }
}

struct SeriesDetailBundle: Decodable, Equatable, Sendable {
    struct Header: Decodable, Equatable, Sendable {
        let mediaId: Int
        let title: String
        let bannerImage: String?
        let coverImage: String?
        let format: String?
        let catalogueStatus: String?
        let episodes: Int?
        let chapters: Int?
        let volumes: Int?
        let description: String?
        let artworkScope: String?

        enum CodingKeys: String, CodingKey {
            case mediaId = "media_id"
            case title
            case bannerImage = "banner_image"
            case coverImage = "cover_image"
            case format
            case catalogueStatus = "catalogue_status"
            case episodes, chapters, volumes, description
            case artworkScope = "artwork_scope"
        }
    }

    struct Section: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        let kind: String
        let ordinal: Int?
        let name: String
        let sortOrder: Int
        var entries: [Entry]? = nil
        struct Entry: Decodable, Equatable, Identifiable, Sendable {
            var id: Int { mediaId }
            let mediaId: Int
            let title: String?
            let bannerImage: String?
            let coverImage: String?
            let episodes: Int?
            enum CodingKeys: String,CodingKey { case mediaId="media_id",title,bannerImage="banner_image",coverImage="cover_image",episodes }
        }

        enum CodingKeys: String, CodingKey {
            case id, kind, ordinal, name
            case sortOrder = "sort_order"
            case entries
        }
    }

    struct Unit: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        let label: String
        let exactOrderKey: String
        /// Numeric conversion is used for presentation and legacy integer progress only.
        var orderKey: Double { Double(exactOrderKey) ?? .nan }
        let available: Bool
        let editionKey: String
        var title: String? = nil
        var synopsis: String? = nil
        var imageURL: String? = nil

        enum CodingKeys: String, CodingKey {
            case id, label
            case exactOrderKey = "order_key"
            case available
            case editionKey = "edition_key"
            case title, synopsis, imageURL="image_url"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            label = try values.decode(String.self, forKey: .label)
            exactOrderKey = try values.numericString(forKey: .exactOrderKey)
            available = try values.decode(Bool.self, forKey: .available)
            editionKey = try values.decode(String.self, forKey: .editionKey)
            title = try values.decodeIfPresent(String.self, forKey: .title)
            synopsis = try values.decodeIfPresent(String.self, forKey: .synopsis)
            imageURL = try values.decodeIfPresent(String.self, forKey: .imageURL)
        }
    }

    struct Copy: Decodable, Equatable, Sendable {
        let premise: String?
        let hook: String?
        let synopsis: String?
        let provenance: String?
        let storyState: String?

        enum CodingKeys: String, CodingKey {
            case premise, hook, synopsis, provenance
            case storyState = "story_state"
        }
    }

    struct Theme: Decodable, Equatable, Sendable {
        let role: String
        let songTitle: String?
        let artist: String?
        let externalURL: String?
        let matchState: String

        enum CodingKeys: String, CodingKey {
            case role
            case songTitle = "song_title"
            case artist
            case externalURL = "external_url"
            case matchState = "match_state"
        }
    }

    struct Coverage: Decodable, Equatable, Sendable {
        let sourceKind: String
        let mappingState: String
        let startsAt: String?
        let endsAt: String?
        let readNext: String?
        let sourceMangaId: Int?
        var animeId: Int? = nil
        var sectionId: String? = nil
        var season: String? = nil

        enum CodingKeys: String, CodingKey {
            case sourceKind = "source_kind"
            case mappingState = "mapping_state"
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case readNext = "read_next"
            case sourceMangaId = "source_manga_id"
            case animeId="anime_id", sectionId="section_id", season
        }
    }

    struct Cast: Decodable, Equatable, Identifiable, Sendable {
        let id: Int
        let name: String?
        let role: String?
        var imageURL: String? = nil
        var description: String? = nil
        enum CodingKeys:String,CodingKey { case id,name,role,imageURL="image_url",description }
    }
    struct Principal: Decodable, Equatable, Identifiable, Sendable {
        let id: Int
        let kind: String
        let name: String?
        let role: String?
        let imageURL: String?
        let description: String?
        var stableId: String { "\(kind):\(id):\(role ?? "")" }
        enum CodingKeys:String,CodingKey { case id,kind,name,role,imageURL="image_url",description }
    }

    struct UserState: Decodable, Equatable, Sendable {
        let serverRevision: Int64
        let lifecycleId: String
        let progress: Int
        let progressLabel: String?
        let listType: String
        let notes: String?
        var unitId: String? = nil

        enum CodingKeys: String, CodingKey {
            case serverRevision = "server_revision"
            case lifecycleId = "lifecycle_id"
            case progress
            case progressLabel = "progress_label"
            case unitId = "unit_id"
            case listType = "list_type"
            case notes
        }
    }

    let medium: String
    let mediaId: Int
    let seriesId: String?
    let header: Header
    let sections: [Section]
    let units: [Unit]
    let unitsState: String
    var unitsNext: SeriesUnitPage.Cursor? = nil
    var editions: [String]? = nil
    var edition: String? = nil
    var editionsNext: String? = nil
    let copy: Copy
    let themes: [Theme]
    let coverage: Coverage?
    let cast: [Cast]
    let user: UserState?
    var material: HomeMaterial? = nil
    var principals: [Principal]? = nil
    var adaptations: [Coverage]? = nil

    enum CodingKeys: String, CodingKey {
        case medium
        case mediaId = "media_id"
        case seriesId = "series_id"
        case header, sections, units
        case unitsState = "units_state"
        case unitsNext = "units_next"
        case editions, edition
        case editionsNext = "editions_next"
        case copy, themes, coverage, cast, user, material, principals, adaptations
    }
}

struct SeriesUnitPage: Decodable, Sendable {
    struct Cursor: Decodable, Equatable, Sendable {
        let order: String
        let id: String
        enum CodingKeys: String, CodingKey { case order, id }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            order = try values.numericString(forKey: .order)
            id = try values.decode(String.self, forKey: .id)
        }
    }
    let items: [SeriesDetailBundle.Unit]
    let next: Cursor?
}
struct RPCSeriesUnitPage: Encodable, Sendable {
    let p_medium: String
    let p_media_id: Int
    let p_section_id: String?
    let p_edition_key: String?
    let p_after_order: String?
    let p_after_id: String?
    let p_limit = 20
}

struct ProgressMutationResult: Decodable, Equatable, Sendable {
    struct Item: Decodable, Equatable, Sendable {
        let mutationId: String
        let outcome: String
        let serverRevision: Int64?
        let position: Int?

        enum CodingKeys: String, CodingKey {
            case mutationId = "mutation_id"
            case outcome
            case serverRevision = "server_revision"
            case position
        }
    }

    let items: [Item]
}

struct RPCHomeBundleParams: Encodable, Sendable {
    let p_medium: String
    let p_window_days: Int
    let p_active_limit: Int
    let p_event_limit: Int
    let p_cursor: String?

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_medium, forKey: .p_medium)
        try c.encode(p_window_days, forKey: .p_window_days)
        try c.encode(p_active_limit, forKey: .p_active_limit)
        try c.encode(p_event_limit, forKey: .p_event_limit)
        try c.encodeIfPresent(p_cursor, forKey: .p_cursor)
    }

    private enum CodingKeys: String, CodingKey {
        case p_medium, p_window_days, p_active_limit, p_event_limit, p_cursor
    }
}

struct RPCSeriesDetailParams: Encodable, Sendable {
    let p_medium: String
    let p_media_id: Int
    let p_section_id: String?

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_medium, forKey: .p_medium)
        try c.encode(p_media_id, forKey: .p_media_id)
        try c.encodeIfPresent(p_section_id, forKey: .p_section_id)
    }

    private enum CodingKeys: String, CodingKey {
        case p_medium, p_media_id, p_section_id
    }
}

struct RPCProgressMutationsParams: Encodable, Sendable {
    let p_mutations: [Mutation]

    struct Mutation: Encodable, Sendable {
        let mutation_id: String
        let medium: String
        let media_id: Int
        let lifecycle_id: String
        let base_revision: Int64
        let position: Int?
        let position_label: String?
        var unit_id: String? = nil
        var status: String? = nil

        nonisolated func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(mutation_id, forKey: .mutation_id)
            try c.encode(medium, forKey: .medium)
            try c.encode(media_id, forKey: .media_id)
            try c.encode(lifecycle_id, forKey: .lifecycle_id)
            try c.encode(base_revision, forKey: .base_revision)
            try c.encodeIfPresent(position, forKey: .position)
            try c.encodeIfPresent(position_label, forKey: .position_label)
            try c.encodeIfPresent(unit_id, forKey: .unit_id)
            try c.encodeIfPresent(status, forKey: .status)
        }

        private enum CodingKeys: String, CodingKey {
            case mutation_id, medium, media_id, lifecycle_id, base_revision, position, position_label, unit_id, status
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_mutations, forKey: .p_mutations)
    }

    private enum CodingKeys: String, CodingKey { case p_mutations }
}

struct HomeEventPage: Decodable, Sendable {
    let items:[HomeEvent]
    let total:Int
    let nextCursor:String?
    enum CodingKeys:String,CodingKey { case items,total; case nextCursor="next_cursor" }
}
struct RPCHomeEventPage: Encodable, Sendable {
    let p_medium:String
    let p_window_days:Int
    let p_limit:Int=20
    let p_cursor:String?
}

/// Transport seam only; Library owns durable progress execution and projection.
/// The production adapter uses the composition's single SDK client. Tests inject response
/// loss/conflict/cancellation into this same drain path rather than copying its algorithm.
@MainActor
protocol HomeProgressSending {
    func apply(_ mutations: [RPCProgressMutationsParams.Mutation]) async throws -> ProgressMutationResult
}

struct RPCHomePendingPage: Encodable, Sendable {
    let p_medium: String
    let p_limit = 20
    let p_cursor: String
}

/// New database cursors carry numeric text verbatim. Decode older numeric rows
/// through Decimal for compatibility; never round-trip new cursors through Double.
private extension KeyedDecodingContainer {
    func numericString(forKey key: Key) throws -> String {
        if let text = try? decode(String.self, forKey: key) { return text }
        return NSDecimalNumber(decimal: try decode(Decimal.self, forKey: key)).stringValue
    }
}

struct SeriesEditionPage: Decodable, Sendable {
    let items: [String]
    let next: String?
}
struct RPCSeriesEditionPage: Encodable, Sendable {
    let p_medium: String
    let p_media_id: Int
    let p_section_id: String?
    let p_after_key: String?
    let p_limit = 50
}
