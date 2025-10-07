import Foundation

// MARK: - Media Protocol for UI compatibility
protocol MediaDisplayable {
    var id: Int { get }
    var title: String { get }
    var imageURL: String? { get }
    var year: String { get }
    var description: String { get }
}

// MARK: - Media struct for UI components
struct Media: MediaDisplayable {
    let id: Int
    let title: String
    let imageURL: String?
    let year: String
    let description: String
}

// MARK: - Extensions to make existing models conform to MediaDisplayable
extension Anime: MediaDisplayable {
    var title: String { displayTitle }
    var imageURL: String? { displayImage.isEmpty ? nil : displayImage }
    var year: String { displayYear }
    var description: String { self.description ?? "No description available" }
}

extension Manga: MediaDisplayable {
    var title: String { displayTitle }
    var imageURL: String? { displayImage.isEmpty ? nil : displayImage }
    var year: String { 
        if let year = startDateYear {
            return String(year)
        }
        return "TBA"
    }
    var description: String { self.description ?? "No description available" }
}

// MARK: - Supabase Data Models
// Matching your existing database schema

struct Anime: Identifiable, Codable {
    let id: Int                           // INTEGER PRIMARY KEY (AniList ID)
    let idMal: Int?                       // MyAnimeList ID
    let idKitsu: String?                  // Kitsu ID
    
    // Titles
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let titleSynonyms: [String]?
    
    // Images (Supabase CDN)
    let coverImageLarge: String?
    let coverImageMedium: String?
    let coverImageColor: String?
    let bannerImage: String?
    
    // Basic info
    let type: String                      // 'ANIME'
    let format: String?                   // TV, MOVIE, OVA, etc.
    let status: String?                   // FINISHED, RELEASING, etc.
    let description: String?
    let descriptionNormalized: String?
    
    // Numbers
    let episodes: Int?
    let duration: Int?                    // Episode duration in minutes
    let totalDuration: Int?
    
    // Release info
    let season: String?                   // WINTER, SPRING, SUMMER, FALL
    let seasonYear: Int?
    let startDateYear: Int?
    let startDateMonth: Int?
    let startDateDay: Int?
    let endDateYear: Int?
    let endDateMonth: Int?
    let endDateDay: Int?
    
    // Next episode (for airing shows)
    let nextAiringEpisode: Int?
    let nextAiringAt: Date?
    
    // Scores and popularity
    let averageScore: Int?
    let meanScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?
    
    // Categories
    let genres: [String]?
    let tags: [String: Any]?              // JSONB tags from AniList
    
    // Content rating
    let isAdult: Bool
    let ageRating: String?
    
    // External links
    let siteUrl: String?
    let trailerUrl: String?
    
    // Metadata
    let source: String?                   // MANGA, LIGHT_NOVEL, ORIGINAL, etc.
    let countryOfOrigin: String?
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    let lastSyncedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case idMal = "id_mal"
        case idKitsu = "id_kitsu"
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case titleSynonyms = "title_synonyms"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case coverImageColor = "cover_image_color"
        case bannerImage = "banner_image"
        case type, format, status, description
        case descriptionNormalized = "description_normalized"
        case episodes, duration
        case totalDuration = "total_duration"
        case season
        case seasonYear = "season_year"
        case startDateYear = "start_date_year"
        case startDateMonth = "start_date_month"
        case startDateDay = "start_date_day"
        case endDateYear = "end_date_year"
        case endDateMonth = "end_date_month"
        case endDateDay = "end_date_day"
        case nextAiringEpisode = "next_airing_episode"
        case nextAiringAt = "next_airing_at"
        case averageScore = "average_score"
        case meanScore = "mean_score"
        case popularity, trending, favourites, genres, tags
        case isAdult = "is_adult"
        case ageRating = "age_rating"
        case siteUrl = "site_url"
        case trailerUrl = "trailer_url"
        case source
        case countryOfOrigin = "country_of_origin"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSyncedAt = "last_synced_at"
    }
    
    // Computed properties for UI
    var displayTitle: String {
        titleEnglish ?? titleRomaji ?? titleNative ?? "Unknown"
    }
    
    var displayImage: String {
        coverImageLarge ?? coverImageMedium ?? ""
    }
    
    var displayYear: String {
        if let year = seasonYear {
            return String(year)
        }
        return "TBA"
    }
    
    var episodeText: String {
        if let episodes = episodes {
            return episodes == 1 ? "FILM" : "\(episodes) EPS"
        }
        return "ONGOING"
    }
}

struct Manga: Identifiable, Codable {
    let id: Int                           // INTEGER PRIMARY KEY
    let idMal: Int?
    
    // Titles
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    
    // Images
    let coverImageLarge: String?
    let coverImageMedium: String?
    let coverImageColor: String?
    
    // Info
    let type: String                      // 'MANGA'
    let format: String?                   // MANGA, NOVEL, ONE_SHOT, etc.
    let status: String?
    let description: String?
    let descriptionNormalized: String?
    
    // Numbers
    let chapters: Int?
    let volumes: Int?
    
    // Release
    let startDateYear: Int?
    let startDateMonth: Int?
    
    // Scores
    let averageScore: Int?
    let popularity: Int?
    
    // Categories
    let genres: [String]?
    
    // External
    let siteUrl: String?
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case idMal = "id_mal"
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case coverImageColor = "cover_image_color"
        case type, format, status, description
        case descriptionNormalized = "description_normalized"
        case chapters, volumes
        case startDateYear = "start_date_year"
        case startDateMonth = "start_date_month"
        case averageScore = "average_score"
        case popularity, genres
        case siteUrl = "site_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Computed properties for UI
    var displayTitle: String {
        titleEnglish ?? titleRomaji ?? titleNative ?? "Unknown"
    }
    
    var displayImage: String {
        coverImageLarge ?? coverImageMedium ?? ""
    }
    
    var chapterText: String {
        if let chapters = chapters {
            return "\(chapters) CH"
        }
        return "ONGOING"
    }
}

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
    
    // User ratings
    let score: Int?                       // 0-100
    let notes: String?
    
    // Timing
    let startedAt: Date?
    let completedAt: Date?
    
    // Privacy
    let isPrivate: Bool
    
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
        case score, notes
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case isPrivate = "private"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum ListStatus: String, Codable, CaseIterable {
    case current = "CURRENT"
    case planning = "PLANNING"
    case completed = "COMPLETED"
    case dropped = "DROPPED"
    case paused = "PAUSED"
    case repeating = "REPEATING"
    
    var displayName: String {
        switch self {
        case .current: return "Watching"
        case .planning: return "Planned"
        case .completed: return "Completed"
        case .dropped: return "Dropped"
        case .paused: return "Paused"
        case .repeating: return "Rewatching"
        }
    }
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
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}