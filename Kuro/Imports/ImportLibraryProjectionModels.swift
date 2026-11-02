import Foundation
import KuroCore
import KuroLibrary

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
struct UserList: Identifiable, Codable {
    let id: Int                           // SERIAL PRIMARY KEY
    let userId: String                    // UUID (from auth.users)
    let mediaId: Int                      // References anime(id) or manga(id)
    let mediaType: String                 // 'anime' or 'manga'
    
    // Status
    let status: ListStatus                // CURRENT, PLANNING, COMPLETED, etc.
    
    // Progress
    let progress: Int                     // Episodes/chapters watched
    let progressVolumes: Int?
    var progressLabel: String? = nil
    var unitId: UUID? = nil
    
    // User ratings
    let verdict: Verdict?
    let score: Int?                       // 0-100
    let notes: String?
    
    // Timing
    let startedAt: Date?
    let completedAt: Date?
    
    // Privacy
    let isPrivate: Bool?
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case mediaId = "media_id"
        case mediaType = "media_type"
        case status
        case progress
        case progressVolumes = "progress_volumes"
        case progressLabel = "progress_label"
        case unitId = "unit_id"
        case verdict, score, notes
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case isPrivate = "private"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension UserList {
    /// LEGACY display projection of a Library entry for views not yet migrated (E3-V); never a stored
    /// copy. `score` is the 0-100 projection of the 1...10 rating; `id` is the medium's own row id
    /// (0 while the entry is optimistic). Unknown privacy remains nil; this display value never
    /// authorizes sharing. Partial source dates remain raw values on LibrarySourceMetadata.
    init(legacy entry: LibraryEntry, userId: String) {
        self.init(
            id: entry.rowId,
            userId: userId,
            mediaId: entry.key.id,
            mediaType: entry.key.kind.rawValue,
            status: entry.status,
            progress: entry.progress,
            progressVolumes: entry.sourceMetadata?.volumesProgress,
            progressLabel: entry.progressLabel,
            unitId: entry.unitId,
            verdict: entry.verdict,
            score: entry.rating?.score100,
            notes: entry.notes,
            startedAt: nil,
            completedAt: nil,
            isPrivate: entry.sourceMetadata?.isPrivate,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
        )
    }
}

// `Verdict` and `ListStatus` live in the KuroLibrary package (`MediaKind` in KuroCore).
