import Foundation
import KuroCore

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
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

struct StaffMangaJoin: Codable {
    let role: String?
    let manga: MangaWorkRow
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
