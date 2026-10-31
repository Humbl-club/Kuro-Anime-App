import Foundation
import KuroCore

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
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
            return TextNormalization.sanitizeMediaDescription(synopsisEnhanced) ?? "No description available"
        }
        return TextNormalization.sanitizeMediaDescription(description) ?? "No description available"
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
            return TextNormalization.sanitizeMediaDescription(synopsisEnhanced) ?? "No description available"
        }
        return TextNormalization.sanitizeMediaDescription(description) ?? "No description available"
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
