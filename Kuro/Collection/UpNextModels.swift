import Foundation
import KuroCore

// MARK: - W10 "Up next in your series": data contract and pure rules
// Backend (prepared, NOT deployed: supabase/prepared-migrations/20261118130000_library_up_next_v1.sql):
//   library_up_next_v1(p_medium, p_limit) -> (media_type, media_id, title, cover_image, format, status,
//                                             start_year, total_units, after_media_id, after_title, link)
// Nothing here performs I/O. `UpNextStore` reads and writes; `FolioUpNextSection` renders.

/// One suggested continuation: the sequel (or next reviewed season) of a title the account completed.
nonisolated struct UpNextItem: Identifiable, Equatable, Sendable, Decodable {
    enum Link: String, Sendable, Decodable { case reviewed, sequel }

    let key: MediaKey
    let title: String
    let coverImage: String?
    let format: String?
    let status: String?
    let startYear: Int?
    let totalUnits: Int?
    let afterKey: MediaKey
    let afterTitle: String
    let link: Link

    var id: MediaKey { key }
    /// An announced sequel is listed on purpose (planning it is useful); the card says "Announced".
    var isAnnounced: Bool { status == "NOT_YET_RELEASED" }

    private enum CodingKeys: String, CodingKey {
        case mediaType = "media_type", mediaId = "media_id", title, coverImage = "cover_image", format, status
        case startYear = "start_year", totalUnits = "total_units"
        case afterMediaId = "after_media_id", afterTitle = "after_title", link
    }

    init(key: MediaKey, title: String, coverImage: String? = nil, format: String? = nil, status: String? = nil,
         startYear: Int? = nil, totalUnits: Int? = nil, afterKey: MediaKey, afterTitle: String, link: Link) {
        self.key = key; self.title = title; self.coverImage = coverImage; self.format = format
        self.status = status; self.startYear = startYear; self.totalUnits = totalUnits
        self.afterKey = afterKey; self.afterTitle = afterTitle; self.link = link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try c.decode(String.self, forKey: .mediaType)
        guard let kind = MediaKind(rawValue: rawKind.lowercased()) else {
            throw DecodingError.dataCorruptedError(forKey: .mediaType, in: c, debugDescription: "unknown media_type \(rawKind)")
        }
        key = MediaKey(kind: kind, id: try c.decode(Int.self, forKey: .mediaId))
        afterKey = MediaKey(kind: kind, id: try c.decode(Int.self, forKey: .afterMediaId))
        title = try c.decode(String.self, forKey: .title)
        coverImage = try c.decodeIfPresent(String.self, forKey: .coverImage)
        format = try c.decodeIfPresent(String.self, forKey: .format)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        startYear = try c.decodeIfPresent(Int.self, forKey: .startYear)
        totalUnits = try c.decodeIfPresent(Int.self, forKey: .totalUnits)
        afterTitle = try c.decode(String.self, forKey: .afterTitle)
        link = try c.decode(Link.self, forKey: .link)
    }
}

nonisolated enum UpNextPolicy {
    /// The server cap; the client asks for exactly this many.
    static let limit = 30
    /// How long a successful read is reused per account and medium.
    static let ttl: TimeInterval = 300
    /// After a "not deployed" answer the section stays hidden and the store does not ask again for this long.
    static let undeployedRetry: TimeInterval = 1800

    /// Server rows minus anything tracked now or hidden on Discover now; the server order is kept.
    static func visible(_ items: [UpNextItem], tracked: Set<MediaKey>, hidden: Set<MediaKey>) -> [UpNextItem] {
        items.filter { !tracked.contains($0.key) && !hidden.contains($0.key) }
    }
}

/// What a Plan from the section created. Undo removes only an entry this Plan created and nobody changed since.
struct UpNextPlanReceipt: Equatable, Sendable {
    let key: MediaKey
    let account: AccountContext
    /// The created entry's identity as the save returned it.
    let rowId: Int
    let lifecycleId: UUID?
    let revision: Int64?
    /// `false` when the save returned a pre-existing entry: no Undo is offered.
    let created: Bool

    var offersUndo: Bool { created }
}

nonisolated enum UpNextCopy {
    static func heading(german: Bool) -> String { german ? "Als Nächstes in deinen Reihen" : "Up next in your series" }
    static func after(_ title: String, german: Bool) -> String { german ? "Fortsetzung von \(title)" : "Sequel to \(title)" }
    static func announced(german: Bool) -> String { german ? "Angekündigt" : "Announced" }
    static func plan(german: Bool) -> String { german ? "Planen" : "Plan" }
    static func dismissSubtitle(german: Bool) -> String { german ? "Auch auf Entdecken ausgeblendet." : "Also hidden on Discover." }
    static func alreadyInLibrary(german: Bool) -> String { german ? "Schon in deiner Bibliothek." : "Already in your library." }
}
