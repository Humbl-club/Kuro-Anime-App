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

    var inferredOriginalLanguageCode: String? {
        switch countryOfOrigin?.uppercased() {
        case "JP": return "ja"
        case "KR": return "ko"
        case "CN", "TW": return "zh"
        case "US", "GB", "CA", "AU", "NZ", "IE": return "en"
        case "DE", "AT": return "de"
        default: return nil
        }
    }

    var hasMeaningfulSynopsis: Bool {
        if let synopsisEnhanced,
           (synopsisEnhancedState ?? "ready").lowercased() == "ready",
           !synopsisEnhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let description,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }
    
    var displayDescription: String {
        if let synopsisEnhanced,
           (synopsisEnhancedState ?? "ready").lowercased() == "ready",
           !synopsisEnhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return synopsisEnhanced
        }
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

    var inferredOriginalLanguageCode: String? { nil }

    var hasMeaningfulSynopsis: Bool {
        if let synopsisEnhanced,
           (synopsisEnhancedState ?? "ready").lowercased() == "ready",
           !synopsisEnhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let description,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }
    
    var displayDescription: String {
        if let synopsisEnhanced,
           (synopsisEnhancedState ?? "ready").lowercased() == "ready",
           !synopsisEnhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return synopsisEnhanced
        }
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

// MARK: - Entity Models (Characters, Staff, Studios, Authors)

struct Character: Identifiable, Codable {
    let id: Int
    let anilistId: Int?
    let nameFull: String?
    let nameNative: String?
    let imageLarge: String?
    let description: String?
    let gender: String?
    let age: String?

    enum CodingKeys: String, CodingKey {
        case id
        case anilistId = "anilist_id"
        case nameFull = "name_full"
        case nameNative = "name_native"
        case imageLarge = "image_large"
        case description
        case gender, age
    }
}

struct Staff: Identifiable, Codable {
    let id: Int
    let anilistId: Int?
    let nameFull: String?
    let nameNative: String?
    let imageLarge: String?
    let description: String?
    let primaryOccupations: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case anilistId = "anilist_id"
        case nameFull = "name_full"
        case nameNative = "name_native"
        case imageLarge = "image_large"
        case description
        case primaryOccupations = "primary_occupations"
    }
}

struct Studio: Identifiable, Codable {
    let id: Int
    let anilistId: Int?
    let name: String?
    let isAnimationStudio: Bool?
    let siteUrl: String?
    let favourites: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case anilistId = "anilist_id"
        case name
        case isAnimationStudio = "is_animation_studio"
        case siteUrl = "site_url"
        case favourites
    }
}

struct Author: Identifiable, Codable {
    let id: Int
    let anilistId: Int?
    let nameFull: String?
    let nameNative: String?
    let imageLarge: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case anilistId = "anilist_id"
        case nameFull = "name_full"
        case nameNative = "name_native"
        case imageLarge = "image_large"
        case description
    }
}

// MARK: - Forward Join Wrappers (inline sections: join table → entity)

struct AnimeCharacterJoin: Codable {
    let role: String?
    let characters: Character

    enum CodingKeys: String, CodingKey {
        case role, characters
    }
}

struct AnimeStaffJoin: Codable {
    let role: String?
    let staff: Staff

    enum CodingKeys: String, CodingKey {
        case role, staff
    }
}

struct AnimeStudioJoin: Codable {
    let studios: Studio

    enum CodingKeys: String, CodingKey {
        case studios
    }
}

struct MangaCharacterJoin: Codable {
    let role: String?
    let characters: Character

    enum CodingKeys: String, CodingKey {
        case role, characters
    }
}

struct MangaAuthorJoin: Codable {
    let role: String?
    let authors: Author

    enum CodingKeys: String, CodingKey {
        case role, authors
    }
}

// MARK: - Lightweight DTOs for Reverse Joins (entity sheets: join table → media)

/// Lightweight row for reverse-join queries (entity → anime).
/// Only includes columns we SELECT — avoids decoding failures on required Anime fields.
struct AnimeWorkRow: Codable, Identifiable {
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let coverImageLarge: String?
    let averageScore: Int?
    let seasonYear: Int?
    let format: String?
    let status: String?
    let genres: [String]?
    let isAdult: Bool
    let episodes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case coverImageLarge = "cover_image_large"
        case averageScore = "average_score"
        case seasonYear = "season_year"
        case format, status, genres
        case isAdult = "is_adult"
        case episodes
    }

    func toMedia() -> Media {
        Media(
            id: id, kind: .anime,
            title: titleEnglish ?? titleRomaji ?? "Unknown",
            imageURL: coverImageLarge,
            year: seasonYear.map(String.init) ?? "TBA",
            displayDescription: "",
            episodes: episodes, chapters: nil,
            rating: averageScore.map { Double($0) / 10.0 },
            genres: genres,
            statusRaw: status, formatRaw: format,
            popularityValue: nil, trendingValue: nil, createdAtValue: nil
        )
    }
}

/// Lightweight row for reverse-join queries (entity → manga).
struct MangaWorkRow: Codable, Identifiable {
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let coverImageLarge: String?
    let averageScore: Int?
    let startDateYear: Int?
    let format: String?
    let status: String?
    let genres: [String]?
    let isAdult: Bool
    let chapters: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case coverImageLarge = "cover_image_large"
        case averageScore = "average_score"
        case startDateYear = "start_date_year"
        case format, status, genres
        case isAdult = "is_adult"
        case chapters
    }

    func toMedia() -> Media {
        Media(
            id: id, kind: .manga,
            title: titleEnglish ?? titleRomaji ?? "Unknown",
            imageURL: coverImageLarge,
            year: startDateYear.map(String.init) ?? "TBA",
            displayDescription: "",
            episodes: nil, chapters: chapters,
            rating: averageScore.map { Double($0) / 10.0 },
            genres: genres,
            statusRaw: status, formatRaw: format,
            popularityValue: nil, trendingValue: nil, createdAtValue: nil
        )
    }
}

// MARK: - Reverse Join Wrappers (entity sheets: using DTOs)

struct StudioAnimeJoin: Codable {
    let anime: AnimeWorkRow
}

struct StaffAnimeJoin: Codable {
    let role: String?
    let anime: AnimeWorkRow
}

struct AuthorMangaJoin: Codable {
    let role: String?
    let manga: MangaWorkRow
}

struct CharacterAnimeJoin: Codable {
    let anime: AnimeWorkRow
}

struct CharacterMangaJoin: Codable {
    let manga: MangaWorkRow
}

// MARK: - Credit Role Normalization

enum CreditRole: Int, CaseIterable {
    case director = 0
    case originalCreator = 1
    case seriesComposition = 2
    case music = 3
    case characterDesign = 4
    case script = 5
    case storyboard = 6
    case animationDirector = 7
    case artDirector = 8
    case soundDirector = 9

    static func from(raw: String) -> CreditRole? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "director": return .director
        case "original creator", "original story", "original character design": return .originalCreator
        case "series composition": return .seriesComposition
        case "music", "theme song composition": return .music
        case "character design", "chief character design": return .characterDesign
        case "script", "screenplay": return .script
        case "storyboard": return .storyboard
        case "animation director", "chief animation director": return .animationDirector
        case "art director", "art design": return .artDirector
        case "sound director": return .soundDirector
        default: return nil
        }
    }

    var editorialPrefix: String {
        switch self {
        case .director: return "Directed by"
        case .originalCreator: return "Story by"
        case .seriesComposition: return "Series composition by"
        case .music: return "Music by"
        case .characterDesign: return "Character design by"
        case .script: return "Script by"
        case .storyboard: return "Storyboard by"
        case .animationDirector: return "Animation direction by"
        case .artDirector: return "Art direction by"
        case .soundDirector: return "Sound direction by"
        }
    }
}

// MARK: - Provider Availability Models

enum ProviderAvailabilityNoteKind: String, Sendable, Equatable {
    case dub
    case audio
    case subtitles
    case availability
}

struct ProviderAvailabilityNote: Sendable, Equatable {
    let kind: ProviderAvailabilityNoteKind
    let languageCode: String?
    let countries: [String]

    var displayText: String {
        let normalizedCountries = countries.sorted()
        switch kind {
        case .availability:
            return "Availability: \(normalizedCountries.joined(separator: ", "))"
        case .dub:
            return "\(displayLanguageCode) dub: \(normalizedCountries.joined(separator: ", "))"
        case .audio:
            return "\(displayLanguageCode) audio: \(normalizedCountries.joined(separator: ", "))"
        case .subtitles:
            return "\(displayLanguageCode) subtitles: \(normalizedCountries.joined(separator: ", "))"
        }
    }

    private var displayLanguageCode: String {
        guard let languageCode, !languageCode.isEmpty else { return "Unknown" }
        return languageCode.uppercased()
    }
}

enum ProviderAvailabilityNoteBuilder {
    static func normalizedLanguage(_ raw: String?) -> String {
        let source = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source.isEmpty { return "unknown" }
        if source.hasPrefix("de") || source.contains("german") || source.contains("deutsch") { return "de" }
        if source.hasPrefix("en") || source.contains("english") { return "en" }
        if source.hasPrefix("ja") || source.contains("japanese") { return "ja" }
        if source.hasPrefix("ko") || source.contains("korean") { return "ko" }
        if source.hasPrefix("zh") || source.contains("chinese") || source.contains("mandarin") { return "zh" }
        return "other"
    }

    static func bestNote(
        from providers: [ProviderAvailabilityProvider],
        preferredAudioLang: String?,
        preferredSubtitleLang: String? = nil,
        originalLanguage: String? = nil
    ) -> ProviderAvailabilityNote? {
        let preferredAudio = normalizedLanguage(preferredAudioLang)
        let preferredSubtitle = normalizedLanguage(preferredSubtitleLang ?? preferredAudioLang)
        let normalizedOriginal = normalizedLanguage(originalLanguage)

        func normalizedCountries(for language: String, in map: [String: [String]]) -> [String] {
            guard let countries = map[language], !countries.isEmpty else { return [] }
            return Array(Set(countries)).sorted()
        }

        func audioKind(for language: String) -> ProviderAvailabilityNoteKind {
            if normalizedOriginal == "en" || normalizedOriginal == "de" {
                return normalizedOriginal != language ? .dub : .audio
            }
            if normalizedOriginal == "ja" || normalizedOriginal == "ko" || normalizedOriginal == "zh" || normalizedOriginal == "other" {
                return .dub
            }
            return .audio
        }

        func bestNote(for provider: ProviderAvailabilityProvider) -> ProviderAvailabilityNote? {
            func audioNote(for language: String) -> ProviderAvailabilityNote? {
                guard language == "en" || language == "de" else { return nil }
                let countries = normalizedCountries(for: language, in: provider.countriesByAudioLang)
                guard !countries.isEmpty else { return nil }
                return ProviderAvailabilityNote(
                    kind: audioKind(for: language),
                    languageCode: language,
                    countries: countries
                )
            }

            func subtitleNote(for language: String) -> ProviderAvailabilityNote? {
                guard language == "en" || language == "de" else { return nil }
                let countries = normalizedCountries(for: language, in: provider.countriesBySubtitleLang)
                guard !countries.isEmpty else { return nil }
                return ProviderAvailabilityNote(kind: .subtitles, languageCode: language, countries: countries)
            }

            func availabilityNote() -> ProviderAvailabilityNote? {
                let audioCountries = provider.countriesByAudioLang.values.flatMap { $0 }
                let subtitleCountries = provider.countriesBySubtitleLang.values.flatMap { $0 }
                let countries = Array(Set(audioCountries + subtitleCountries)).sorted()
                guard !countries.isEmpty else { return nil }
                return ProviderAvailabilityNote(kind: .availability, languageCode: nil, countries: countries)
            }

            let noteCandidates: [ProviderAvailabilityNote?] = [
                audioNote(for: preferredAudio),
                subtitleNote(for: preferredSubtitle),
                audioNote(for: "en"),
                audioNote(for: "de"),
                subtitleNote(for: "en"),
                subtitleNote(for: "de"),
                availabilityNote()
            ]

            return noteCandidates.compactMap { $0 }.first
        }

        for provider in providers {
            if let note = bestNote(for: provider) {
                return note
            }
        }
        return nil
    }
}

struct ProviderAvailabilityProvider: Decodable, Sendable {
    let slug: String
    let displayName: String
    let url: String?
    let languages: [String]
    let audioLanguages: [String]
    let subtitleLanguages: [String]
    let countriesByAudioLang: [String: [String]]
    let countriesBySubtitleLang: [String: [String]]
    let isStale: Bool

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case url
        case languages
        case audioLanguages = "audio_languages"
        case subtitleLanguages = "subtitle_languages"
        case countriesByAudioLang = "countries_by_audio_lang"
        case countriesBySubtitleLang = "countries_by_sub_lang"
        case isStale = "is_stale"
    }
}

struct ProviderAvailabilityBatchItem: Decodable, Sendable {
    let mediaType: String
    let mediaId: Int
    let providers: [ProviderAvailabilityProvider]

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case providers
    }
}

struct MediaAvailabilityStatus: Decodable, Sendable {
    let hasRows: Bool
    let status: String
    let lastRefreshedAt: Date?
    let nextRefreshAt: Date?
    let staleDays: Int?

    enum CodingKeys: String, CodingKey {
        case hasRows = "has_rows"
        case status
        case lastRefreshedAt = "last_refreshed_at"
        case nextRefreshAt = "next_refresh_at"
        case staleDays = "stale_days"
    }
}

struct MediaLadderItem: Decodable, Identifiable, Sendable {
    let mediaType: String
    let mediaId: Int
    let title: String
    let coverImage: String?
    let year: Int?
    let format: String?
    let rating: Double?
    let reasonLabel: String?
    let sourceAuthorName: String?

    var id: String { "\(mediaType)-\(mediaId)" }

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case title
        case coverImage = "cover_image"
        case year
        case format
        case rating
        case reasonLabel = "reason_label"
        case sourceAuthorName = "source_author_name"
    }

    func toMedia() -> Media {
        Media(
            id: mediaId,
            kind: mediaType.uppercased() == "MANGA" ? .manga : .anime,
            title: title,
            imageURL: coverImage,
            year: year.map(String.init) ?? "TBA",
            displayDescription: "",
            episodes: nil,
            chapters: nil,
            rating: rating,
            genres: nil,
            statusRaw: nil,
            formatRaw: format,
            popularityValue: nil,
            trendingValue: nil,
            createdAtValue: nil
        )
    }
}

enum MediaLadderCoverageStatus: String, Decodable, Sendable {
    case strong
    case partial
    case minimal
}

struct MediaLadderResponse: Decodable, Sendable {
    let sourceMaterial: [MediaLadderItem]
    let adaptations: [MediaLadderItem]
    let prequels: [MediaLadderItem]
    let sequels: [MediaLadderItem]
    let sideStories: [MediaLadderItem]
    let spinOffs: [MediaLadderItem]
    let entryPoint: MediaLadderItem?
    let nextStep: MediaLadderItem?
    let primarySource: MediaLadderItem?
    let primaryAdaptation: MediaLadderItem?
    let franchiseNote: String?
    let coverageStatus: MediaLadderCoverageStatus?
    let totalFranchiseCount: Int?
    let alternateAdaptationSummary: String?

    static let empty = MediaLadderResponse(
        sourceMaterial: [],
        adaptations: [],
        prequels: [],
        sequels: [],
        sideStories: [],
        spinOffs: [],
        entryPoint: nil,
        nextStep: nil,
        primarySource: nil,
        primaryAdaptation: nil,
        franchiseNote: nil,
        coverageStatus: nil,
        totalFranchiseCount: nil,
        alternateAdaptationSummary: nil
    )

    var hasContent: Bool {
        entryPoint != nil
            || nextStep != nil
            || primarySource != nil
            || primaryAdaptation != nil
            || !sourceMaterial.isEmpty
            || !adaptations.isEmpty
            || !prequels.isEmpty
            || !sequels.isEmpty
            || !sideStories.isEmpty
            || !spinOffs.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case sourceMaterial = "source_material"
        case adaptations
        case prequels
        case sequels
        case sideStories = "side_stories"
        case spinOffs = "spin_offs"
        case entryPoint = "entry_point"
        case nextStep = "next_step"
        case primarySource = "primary_source"
        case primaryAdaptation = "primary_adaptation"
        case franchiseNote = "franchise_note"
        case coverageStatus = "coverage_status"
        case totalFranchiseCount = "total_franchise_count"
        case alternateAdaptationSummary = "alternate_adaptation_summary"
    }
}
