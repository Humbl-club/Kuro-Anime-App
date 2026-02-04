import Foundation

enum MediaKind: String, Codable, Sendable {
    case anime
    case manga
}

// MARK: - Media Protocol for UI compatibility
protocol MediaDisplayable {
    var id: Int { get }
    var kind: MediaKind { get }
    var title: String { get }
    var imageURL: String? { get }
    var year: String { get }
    var displayDescription: String { get }
    var episodes: Int? { get }
    var chapters: Int? { get }
    var rating: Double? { get }
    var genres: [String]? { get }

    // Optional metadata used for filtering/paging without requiring full models.
    var statusRaw: String? { get }
    var formatRaw: String? { get }
    var popularityValue: Int? { get }
    var trendingValue: Int? { get }
    var createdAtValue: Date? { get }
}

extension MediaDisplayable {
    /// Stable identity across mixed feeds (anime + manga).
    var stableKey: String { "\(kind.rawValue)-\(id)" }
}

// MARK: - Media struct for UI components
struct Media: MediaDisplayable {
    let id: Int
    let kind: MediaKind
    let title: String
    let imageURL: String?
    let year: String
    let displayDescription: String
    let episodes: Int?
    let chapters: Int?
    let rating: Double?
    let genres: [String]?

    let statusRaw: String?
    let formatRaw: String?
    let popularityValue: Int?
    let trendingValue: Int?
    let createdAtValue: Date?
}

// MARK: - Extensions to make existing models conform to MediaDisplayable
extension Anime: MediaDisplayable {
    var kind: MediaKind { .anime }
    var title: String { displayTitle }
    var imageURL: String? { displayImage.isEmpty ? nil : displayImage }
    var year: String { displayYear }
    
    var displayDescription: String { 
        return description ?? "No description available" 
    }
    
    var episodes: Int? {
        if let episodeCount, episodeCount > 0 { return episodeCount }
        // Some long-running series don't have a total episode count from AniList.
        // If we have a next airing episode number, treat (next - 1) as the number aired so far.
        if let nextEpisodeNumber, nextEpisodeNumber > 1 {
            return nextEpisodeNumber - 1
        }
        return nil
    }
    var chapters: Int? { nil } // Anime doesn't have chapters
    var rating: Double? { 
        if let score = averageScore {
            return Double(score) / 10.0 // Convert from 0-100 to 0-10 scale
        }
        return nil
    }
    var genres: [String]? { genreList }
    var statusRaw: String? { status }
    var formatRaw: String? { format }
    var popularityValue: Int? { popularity }
    var trendingValue: Int? { trending }
    var createdAtValue: Date? { createdAt }
}

extension Manga: MediaDisplayable {
    var kind: MediaKind { .manga }
    var title: String { displayTitle }
    var imageURL: String? { displayImage.isEmpty ? nil : displayImage }
    var year: String { 
        if let year = startDateYear {
            return String(year)
        }
        return "TBA"
    }
    
    var displayDescription: String { 
        return description ?? "No description available" 
    }
    
    var episodes: Int? { nil } // Manga doesn't have episodes
    var chapters: Int? { chapterCount }
    var rating: Double? { 
        if let score = averageScore {
            return Double(score) / 10.0 // Convert from 0-100 to 0-10 scale
        }
        return nil
    }
    var genres: [String]? { genreList }
    var statusRaw: String? { status }
    var formatRaw: String? { format }
    var popularityValue: Int? { popularity }
    var trendingValue: Int? { trending }
    var createdAtValue: Date? { createdAt }
}

// MARK: - Lightweight "card" models (minimal payload for rails/grids)
// These are returned by RPCs like `discover_bundle` and `browse_*_page`.
struct AnimeCard: Identifiable, Codable, Sendable, MediaDisplayable {
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let coverImageLarge: String?
    let coverImageMedium: String?
    let bannerImage: String?
    let format: String?
    let status: String?
    let episodeCount: Int?
    let seasonYear: Int?
    let startDateYear: Int?
    let averageScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?
    let genreList: [String]?
    let createdAt: Date?
    // Present only for search RPCs (used for keyset pagination).
    let rank: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case bannerImage = "banner_image"
        case format
        case status
        case episodeCount = "episode_count"
        case seasonYear = "season_year"
        case startDateYear = "start_date_year"
        case averageScore = "average_score"
        case popularity
        case trending
        case favourites
        case genreList = "genres"
        case createdAt = "created_at"
        case rank
    }

    // MediaDisplayable
    var kind: MediaKind { .anime }
    var title: String { titleEnglish ?? titleRomaji ?? titleNative ?? "Unknown" }
    var imageURL: String? { (coverImageLarge ?? coverImageMedium)?.isEmpty == false ? (coverImageLarge ?? coverImageMedium) : nil }
    var year: String { seasonYear.map(String.init) ?? startDateYear.map(String.init) ?? "TBA" }
    var displayDescription: String { "No description available" }
    var episodes: Int? { episodeCount }
    var chapters: Int? { nil }
    var rating: Double? { averageScore.map { Double($0) / 10.0 } }
    var genres: [String]? { genreList }
    var statusRaw: String? { status }
    var formatRaw: String? { format }
    var popularityValue: Int? { popularity }
    var trendingValue: Int? { trending }
    var createdAtValue: Date? { createdAt }
}

struct MangaCard: Identifiable, Codable, Sendable, MediaDisplayable {
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let coverImageLarge: String?
    let coverImageMedium: String?
    let format: String?
    let status: String?
    let chapterCount: Int?
    let startDateYear: Int?
    let averageScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?
    let genreList: [String]?
    let createdAt: Date?
    // Present only for search RPCs (used for keyset pagination).
    let rank: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case format
        case status
        case chapterCount = "chapter_count"
        case startDateYear = "start_date_year"
        case averageScore = "average_score"
        case popularity
        case trending
        case favourites
        case genreList = "genres"
        case createdAt = "created_at"
        case rank
    }

    // MediaDisplayable
    var kind: MediaKind { .manga }
    var title: String { titleEnglish ?? titleRomaji ?? titleNative ?? "Unknown" }
    var imageURL: String? { (coverImageLarge ?? coverImageMedium)?.isEmpty == false ? (coverImageLarge ?? coverImageMedium) : nil }
    var year: String { startDateYear.map(String.init) ?? "TBA" }
    var displayDescription: String { "No description available" }
    var episodes: Int? { nil }
    var chapters: Int? { chapterCount }
    var rating: Double? { averageScore.map { Double($0) / 10.0 } }
    var genres: [String]? { genreList }
    var statusRaw: String? { status }
    var formatRaw: String? { format }
    var popularityValue: Int? { popularity }
    var trendingValue: Int? { trending }
    var createdAtValue: Date? { createdAt }
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
    let format: String?                   // TV, MOVIE, OVA, etc.
    let status: String?                   // FINISHED, RELEASING, etc.
    let description: String?
    let descriptionNormalized: String?
    
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
    let tags: String?              // JSONB tags from AniList stored as JSON string
    
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
        case format, status, description
        case descriptionNormalized = "description_normalized"
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
        case genreList = "genres", tags
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
        if let episodes = episodeCount {
            return episodes == 1 ? "FILM" : "\(episodes) EPS"
        }
        return "ONGOING"
    }
    
    // Helper property to decode tags as dictionary when needed
    var tagsAsDictionary: [String: Any]? {
        guard let tags = tags,
              let data = tags.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
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
    let tags: String?              // Optional JSONB tags (if present)

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
        case idMal = "id_mal"
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case coverImageColor = "cover_image_color"
        case format, status, description
        case descriptionNormalized = "description_normalized"
        case chapterCount = "chapters", volumeCount = "volumes"
        case startDateYear = "start_date_year"
        case startDateMonth = "start_date_month"
        case averageScore = "average_score"
        case popularity, trending, favourites
        case genreList = "genres"
        case tags
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

// MARK: - Discovery Facets (UI models)
struct TagFacet: Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String?
    let count: Int
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
    let streamUrl: String?
    let streamSite: String?
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

    enum CodingKeys: String, CodingKey {
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

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case mediaId = "media_id"
        case site, url, language, color, priority
        case isDisabled = "is_disabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
