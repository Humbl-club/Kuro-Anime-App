import Foundation

// MARK: - Supabase Data Models
// Single source of truth for all data structures

struct Media: Identifiable, Codable {
    let id: String
    let title: String
    let year: Int
    let description: String
    let imageURL: String?
    let type: MediaType
    let genres: [String]
    let episodes: Int?
    let chapters: Int?
    let status: String
    let rating: Double?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case description
        case imageURL = "image_url"
        case type
        case genres
        case episodes
        case chapters
        case status
        case rating
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum MediaType: String, Codable, CaseIterable {
    case anime = "anime"
    case manga = "manga"
    case manhwa = "manhwa"
    
    var displayName: String {
        switch self {
        case .anime: return "Anime"
        case .manga: return "Manga"
        case .manhwa: return "Manhwa"
        }
    }
}

struct UserList: Identifiable, Codable {
    let id: String
    let userId: String
    let name: String
    let type: ListType
    let mediaItems: [String]
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case mediaItems = "media_items"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum ListType: String, Codable, CaseIterable {
    case watching = "watching"
    case completed = "completed"
    case planned = "planned"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .watching: return "Watching"
        case .completed: return "Completed"
        case .planned: return "Planned"
        case .custom: return "Custom"
        }
    }
}

struct SearchFilters: Codable {
    let type: MediaType?
    let genres: [String]
    let yearRange: ClosedRange<Int>?
    let rating: Double?
    let status: String?
    
    init(type: MediaType? = nil,
         genres: [String] = [],
         yearRange: ClosedRange<Int>? = nil,
         rating: Double? = nil,
         status: String? = nil) {
        self.type = type
        self.genres = genres
        self.yearRange = yearRange
        self.rating = rating
        self.status = status
    }
}
