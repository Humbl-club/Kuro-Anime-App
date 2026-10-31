import Foundation

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
// MARK: - Supabase Data Models
// Matching your existing database schema

struct Anime: Identifiable, Codable {
    let id: Int                           // INTEGER PRIMARY KEY (AniList ID)
    let idMal: Int?                       // MyAnimeList ID
    let idKitsu: Int?                     // Kitsu ID
    
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
    let format: String?                   // TV, MOVIE, OVA, etc.
    let status: String?                   // FINISHED, RELEASING, etc.
    let description: String?
    let descriptionNormalized: String?
    let synopsisEnhanced: String?
    let synopsisEnhancedSource: String?
    let synopsisEnhancedModel: String?
    let synopsisEnhancedVersion: String?
    let synopsisEnhancedUpdatedAt: Date?
    let synopsisEnhancedState: String?
    
    // Numbers
    let episodeCount: Int?
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
    let nextEpisodeNumber: Int?
    let nextAiringAt: Date?
    
    // Scores and popularity
    let averageScore: Int?
    let meanScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?
    
    // Categories
    let genreList: [String]?

    // Content rating
    let isAdult: Bool
    let ageRating: String?

    // External links
    let siteUrl: String?
    
    // Metadata
    let source: String?                   // MANGA, LIGHT_NOVEL, ORIGINAL, etc.
    let countryOfOrigin: String?
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    let lastSyncedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case idMal = "mal_id"
        case idKitsu = "kitsu_id"
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case titleSynonyms = "title_synonyms"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case coverImageColor = "cover_image_color"
        case bannerImage = "banner_image"
        case format, status, description
        case descriptionNormalized = "description_normalized"
        case synopsisEnhanced = "synopsis_enhanced"
        case synopsisEnhancedSource = "synopsis_enhanced_source"
        case synopsisEnhancedModel = "synopsis_enhanced_model"
        case synopsisEnhancedVersion = "synopsis_enhanced_version"
        case synopsisEnhancedUpdatedAt = "synopsis_enhanced_updated_at"
        case synopsisEnhancedState = "synopsis_enhanced_state"
        case episodeCount = "episodes", duration
        case totalDuration = "total_duration"
        case season
        case seasonYear = "season_year"
        case startDateYear = "start_date_year"
        case startDateMonth = "start_date_month"
        case startDateDay = "start_date_day"
        case endDateYear = "end_date_year"
        case endDateMonth = "end_date_month"
        case endDateDay = "end_date_day"
        case nextEpisodeNumber = "next_episode_number"
        case nextAiringAt = "next_airing_at"
        case averageScore = "average_score"
        case meanScore = "mean_score"
        case popularity, trending, favourites
        case genreList = "genres"
        case isAdult = "is_adult"
        case ageRating = "age_rating"
        case siteUrl = "site_url"
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
        if let episodes = episodeCount {
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
    let format: String?                   // MANGA, NOVEL, ONE_SHOT, etc.
    let status: String?
    let description: String?
    let descriptionNormalized: String?
    let synopsisEnhanced: String?
    let synopsisEnhancedSource: String?
    let synopsisEnhancedModel: String?
    let synopsisEnhancedVersion: String?
    let synopsisEnhancedUpdatedAt: Date?
    let synopsisEnhancedState: String?
    
    // Numbers
    let chapterCount: Int?
    let volumeCount: Int?
    
    // Release
    let startDateYear: Int?
    let startDateMonth: Int?
    
    // Scores
    let averageScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?
    
    // Categories
    let genreList: [String]?

    // Content rating
    let isAdult: Bool
    let ageRating: String?

    // External
    let siteUrl: String?

    // Timestamps
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case idMal = "mal_id"
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case coverImageColor = "cover_image_color"
        case format, status, description
        case descriptionNormalized = "description_normalized"
        case synopsisEnhanced = "synopsis_enhanced"
        case synopsisEnhancedSource = "synopsis_enhanced_source"
        case synopsisEnhancedModel = "synopsis_enhanced_model"
        case synopsisEnhancedVersion = "synopsis_enhanced_version"
        case synopsisEnhancedUpdatedAt = "synopsis_enhanced_updated_at"
        case synopsisEnhancedState = "synopsis_enhanced_state"
        case chapterCount = "chapters", volumeCount = "volumes"
        case startDateYear = "start_date_year"
        case startDateMonth = "start_date_month"
        case averageScore = "average_score"
        case popularity, trending, favourites
        case genreList = "genres"
        case isAdult = "is_adult"
        case ageRating = "age_rating"
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
        if let chapters = chapterCount {
            return "\(chapters) CH"
        }
        return "ONGOING"
    }
}
