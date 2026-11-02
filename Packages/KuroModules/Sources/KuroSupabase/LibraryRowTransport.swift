import Foundation
import KuroLibrary

// The minimal typed seam between the list adapter and PostgREST. The adapter decides every
// request (table, columns, filters, body, order/range); an implementation only maps each request
// value onto the SDK and maps SDK failures onto `LibraryTransportError`.

/// One row of `anime_user_lists` / `manga_user_lists` as PostgREST returns it.
public struct LibraryRow: Sendable, Equatable, Decodable {
    public let id: Int
    public let userId: String
    public let animeId: Int?
    public let mangaId: Int?
    public let listType: String
    public let progress: Int
    public let rating: Int?
    public let notes: String?
    public let verdict: String?
    public let createdAt: Date
    public let updatedAt: Date
    /// Present once the series foundation migration is applied. Absent columns decode as `nil`.
    public let serverRevision: Int64?
    public let lifecycleId: UUID?
    public let progressLabel: String?
    public let unitId: UUID?
    public let volumesProgress: Int?
    public let repeatCount: Int?
    public let scoreRaw: LibraryStoredScore?
    public let scoreScale: String?
    public let startedRaw: String?
    public let finishedRaw: String?
    public let entryPrivate: Bool?
    public let sourceCustomLists: [String]?
    public let sourceHidden: Bool?
    public let sourceListOptions: String?


    public init(
        id: Int,
        userId: String,
        animeId: Int? = nil,
        mangaId: Int? = nil,
        listType: String,
        progress: Int,
        rating: Int? = nil,
        notes: String? = nil,
        verdict: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        serverRevision: Int64? = nil,
        lifecycleId: UUID? = nil,
        progressLabel: String? = nil,
        unitId: UUID? = nil,
        volumesProgress: Int? = nil,
        repeatCount: Int? = nil,
        scoreRaw: LibraryStoredScore? = nil,
        scoreScale: String? = nil,
        startedRaw: String? = nil,
        finishedRaw: String? = nil,
        entryPrivate: Bool? = nil,
        sourceCustomLists: [String]? = nil,
        sourceHidden: Bool? = nil,
        sourceListOptions: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.animeId = animeId
        self.mangaId = mangaId
        self.listType = listType
        self.progress = progress
        self.rating = rating
        self.notes = notes
        self.verdict = verdict
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverRevision = serverRevision
        self.lifecycleId = lifecycleId
        self.progressLabel = progressLabel
        self.unitId = unitId
        self.volumesProgress = volumesProgress
        self.repeatCount = repeatCount
        self.scoreRaw = scoreRaw
        self.scoreScale = scoreScale
        self.startedRaw = startedRaw
        self.finishedRaw = finishedRaw
        self.entryPrivate = entryPrivate
        self.sourceCustomLists = sourceCustomLists
        self.sourceHidden = sourceHidden
        self.sourceListOptions = sourceListOptions

    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case animeId = "anime_id"
        case mangaId = "manga_id"
        case listType = "list_type"
        case progress, rating, notes, verdict
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case serverRevision = "server_revision"
        case lifecycleId = "lifecycle_id"
        case progressLabel = "progress_label"
        case unitId = "unit_id"
        case volumesProgress = "volumes_progress"
        case repeatCount = "repeat_count"
        case scoreRaw = "score_raw"
        case scoreScale = "score_scale"
        case startedRaw = "started_raw"
        case finishedRaw = "finished_raw"
        case entryPrivate = "entry_private"
        case sourceCustomLists = "source_custom_lists"
        case sourceHidden = "source_hidden"
        case sourceListOptions = "source_list_options"

    }
}

/// A JSON body value. `.null` is encoded as an explicit JSON `null` (clears a nullable column);
/// a column that must not change is simply absent from the body.
public enum LibraryJSONValue: Sendable, Equatable, Encodable {
    case string(String)
    case int(Int)
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// `GET /<table>?select=<columns>&user_id=eq.<userId>[&<mediaColumn>=eq.<mediaId>]&order=<orderColumn>.asc`
/// with `Range: offset-(offset+limit-1)`.
public struct LibraryRowSelect: Sendable, Equatable {
    public let table: String
    public let columns: String
    public let userId: String
    public let mediaColumn: String
    public let mediaId: Int?
    public let orderColumn: String
    public let offset: Int
    public let limit: Int
}

/// `PATCH /<table>?user_id=eq.<userId>&<mediaColumn>=eq.<mediaId>&select=<columns>`,
/// `Prefer: return=representation`. Returns the updated rows (empty when no row matched).
public struct LibraryRowPatch: Sendable, Equatable {
    public let table: String
    public let columns: String
    public let userId: String
    public let mediaColumn: String
    public let mediaId: Int
    public let body: [String: LibraryJSONValue]
}

/// `POST /<table>?on_conflict=<onConflict>&select=<columns>`,
/// `Prefer: resolution=ignore-duplicates,return=representation` (supabase-swift:
/// `upsert(body, onConflict:, returning: .representation, ignoreDuplicates: true)`).
/// `onConflict` names the table's unique `(user_id, <media>_id)` key; without it PostgREST only
/// ignores primary-key (`id`) duplicates and a tracked title fails with 23505.
/// Returns the inserted row, or no row when a row with the same `(user_id, <media>_id)` exists.
public struct LibraryRowInsert: Sendable, Equatable {
    public let table: String
    public let columns: String
    public let onConflict: String
    public let body: [String: LibraryJSONValue]
}

/// `DELETE /<table>?user_id=eq.<userId>&<mediaColumn>=eq.<mediaId>`.
public struct LibraryRowDelete: Sendable, Equatable {
    public let table: String
    public let userId: String
    public let mediaColumn: String
    public let mediaId: Int
}

/// Failure reported by a transport implementation.
public enum LibraryTransportError: Error, Sendable, Equatable {
    /// The server answered with an error: HTTP status when known, PostgREST/PostgreSQL code
    /// (e.g. `PGRST301`, `23514`) when known.
    case server(status: Int?, code: String?, message: String)
    /// No usable answer: connection lost, DNS, timeout.
    case network(message: String)
}

/// PostgREST operations on the two list tables. Implemented by the app over supabase-swift.
public protocol LibraryRowTransport: Sendable {
    func select(_ request: LibraryRowSelect) async throws -> [LibraryRow]
    func patch(_ request: LibraryRowPatch) async throws -> [LibraryRow]
    func insertIgnoringDuplicates(_ request: LibraryRowInsert) async throws -> [LibraryRow]
    func delete(_ request: LibraryRowDelete) async throws
}

/// PostgREST emits numeric score columns as numbers; string wire forms are accepted losslessly too.
public struct LibraryStoredScore: Sendable, Equatable, Decodable {
    public let value: String
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { value = text }
        else { value = NSDecimalNumber(decimal: try container.decode(Decimal.self)).stringValue }
    }
}
