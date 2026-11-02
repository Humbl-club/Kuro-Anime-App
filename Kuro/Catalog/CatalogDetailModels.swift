import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
// MARK: - Catalog tag facets and detail units
struct TagFacet: Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String?
    let count: Int
}

struct Episode: Identifiable, Codable {
    let id: Int                           // SERIAL PRIMARY KEY
    let animeId: Int                      // References anime(id)
    let number: Int
    let title: String?
    let titleRomaji: String?
    let description: String?
    let airDate: Date?
    let airAt: Date?
    let thumbnail: String?
    let duration: Int?                    // Minutes
    let isFiller: Bool
    let isRecap: Bool
    let isMixed: Bool
    let fillerSource: String?
    let streamUrl: String?
    let streamSite: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case animeId = "anime_id"
        case number, title
        case titleRomaji = "title_romaji"
        case description
        case airDate = "air_date"
        case airAt = "air_at"
        case thumbnail, duration
        case isFiller = "is_filler"
        case isRecap = "is_recap"
        case isMixed = "is_mixed"
        case fillerSource = "filler_source"
        case streamUrl = "stream_url"
        case streamSite = "stream_site"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MangaChapter: Identifiable, Codable {
    let id: Int
    let mangaId: Int
    let number: Int
    let title: String?
    let titleRomaji: String?
    let description: String?
    let releaseDate: Date?
    let releaseAt: Date?
    let thumbnail: String?
    let pages: Int?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case mangaId = "manga_id"
        case number, title
        case titleRomaji = "title_romaji"
        case description
        case releaseDate = "release_date"
        case releaseAt = "release_at"
        case thumbnail, pages
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MangaChapterStatus: Codable, Sendable {
    let mangaId: Int
    let chapterRows: Int
    let chapterCountField: Int?
    let mappingStatus: String
    let lastSyncAt: Date?
    let nextRetryAt: Date?
    let lastReason: String?

    enum CodingKeys: String, CodingKey {
        case mangaId = "manga_id"
        case chapterRows = "chapter_rows"
        case chapterCountField = "chapter_count_field"
        case mappingStatus = "mapping_status"
        case lastSyncAt = "last_sync_at"
        case nextRetryAt = "next_retry_at"
        case lastReason = "last_reason"
    }
}

struct ExternalLink: Identifiable, Codable {
    let id: Int
    let mediaType: String
    let mediaId: Int
    let site: String?
    let url: String
    let language: String?
    let color: String?
    let priority: Int?
    let isDisabled: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case mediaType = "media_type"
        case mediaId = "media_id"
        case site, url, language, color, priority
        case isDisabled = "is_disabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
