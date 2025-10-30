import Foundation

@MainActor
@Observable
final class DiscoverViewModel {
    var featured: Anime?
    var currentSeason: [Anime] = []
    var trending: [Anime] = []
    var topRated: [Anime] = []
    var newlyAdded: [Anime] = []

    var sections: [DiscoverSection] {
        [
            .featured(featured),
            .currentSeason(currentSeason),
            .trending(trending),
            .topRated(topRated),
            .newlyAdded(newlyAdded)
        ]
    }

    func update(with items: [Anime]) {
        // Featured: highest rated currently airing show
        featured = items
            .filter { $0.status == "RELEASING" && ($0.averageScore ?? 0) > 80 }
            .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }
            .first

        // Current season (this or previous year), airing TV, by popularity
        let currentYear = Calendar.current.component(.year, from: Date())
        currentSeason = items
            .filter { anime in
                (anime.seasonYear == currentYear || anime.seasonYear == currentYear - 1) &&
                anime.status == "RELEASING" &&
                anime.format == "TV"
            }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(10)
            .map { $0 }

        // Trending by popularity
        trending = items
            .filter { ($0.popularity ?? 0) > 1000 }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(10)
            .map { $0 }

        // Top rated by average score
        topRated = items
            .filter { ($0.averageScore ?? 0) >= 80 }
            .sorted { ($0.averageScore ?? 0) > ($1.averageScore ?? 0) }
            .prefix(8)
            .map { $0 }

        // Newly added by createdAt
        newlyAdded = items
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { $0 }
    }
}

enum DiscoverSection {
    case featured(Anime?)
    case currentSeason([Anime])
    case trending([Anime])
    case topRated([Anime])
    case newlyAdded([Anime])
}
