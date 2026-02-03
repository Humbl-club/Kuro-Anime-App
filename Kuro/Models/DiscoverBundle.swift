import Foundation

struct DiscoverBundle: Decodable, Sendable {
    let anime: AnimeRails
    let manga: MangaRails

    struct AnimeRails: Decodable, Sendable {
        let essentials: [AnimeCard]
        let classics: [AnimeCard]
        let newToYou: [AnimeCard]
        let trending: [AnimeCard]
        let topRated: [AnimeCard]
        let newlyAdded: [AnimeCard]
        let airingToday: [AnimeCard]
        let currentSeason: [AnimeCard]

        enum CodingKeys: String, CodingKey {
            case essentials
            case classics
            case newToYou = "new_to_you"
            case trending
            case topRated = "top_rated"
            case newlyAdded = "newly_added"
            case airingToday = "airing_today"
            case currentSeason = "current_season"
        }
    }

    struct MangaRails: Decodable, Sendable {
        let essentials: [MangaCard]
        let classics: [MangaCard]
        let newToYou: [MangaCard]
        let trending: [MangaCard]
        let topRated: [MangaCard]
        let newlyAdded: [MangaCard]

        enum CodingKeys: String, CodingKey {
            case essentials
            case classics
            case newToYou = "new_to_you"
            case trending
            case topRated = "top_rated"
            case newlyAdded = "newly_added"
        }
    }
}

