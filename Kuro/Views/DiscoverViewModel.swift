import Foundation

@MainActor
@Observable
final class DiscoverViewModel {
    var featured: AnimeCard?
    var currentSeason: [AnimeCard] = []
    var essentials: [AnimeCard] = []
    var classics: [AnimeCard] = []
    var newToYou: [AnimeCard] = []
    var trending: [AnimeCard] = []
    var topRated: [AnimeCard] = []
    var airingToday: [AnimeCard] = []
    var newlyAdded: [AnimeCard] = []

    // Discover P1 — The One Thing (nil until resolved; falls back to `featured`).
    var dailyFeature: DailyFeature?
    var dailyFeatureResolved = false

    // Discover P1 — Because-You rail (mixed feed; replaces NEW TO YOU when set).
    var becauseYou: [Media] = []
    var becauseYouReason: String? = nil

    // Manga sections
    var essentialsManga: [MangaCard] = []
    var classicsManga: [MangaCard] = []
    var newToYouManga: [MangaCard] = []
    var trendingManga: [MangaCard] = []
    var topRatedManga: [MangaCard] = []
    var newlyAddedManga: [MangaCard] = []

    var sections: [DiscoverVMSection] {
        [
            .featured(featured),
            .currentSeason(currentSeason),
            .trending(trending),
            .topRated(topRated),
            .newlyAdded(newlyAdded)
        ]
    }

    // Legacy APIs removed: Discover is now server-driven via `discover_bundle`.
}

enum DiscoverVMSection {
    case featured(AnimeCard?)
    case currentSeason([AnimeCard])
    case trending([AnimeCard])
    case topRated([AnimeCard])
    case newlyAdded([AnimeCard])
}

extension DiscoverViewModel {
    // Legacy API removed.
}
