import Foundation

enum EditorialDiscoverRoute: Identifiable {
    case animeEssentials
    case animeClassics
    case animeNewToYou
    case animeAiringToday
    case animeCurrentSeason
    case animeTrending
    case animeTopRated
    case animeNewlyAdded
    case mangaEssentials
    case mangaClassics
    case mangaNewToYou

    var id: String {
        switch self {
        case .animeEssentials: return "animeEssentials"
        case .animeClassics: return "animeClassics"
        case .animeNewToYou: return "animeNewToYou"
        case .animeAiringToday: return "animeAiringToday"
        case .animeCurrentSeason: return "animeCurrentSeason"
        case .animeTrending: return "animeTrending"
        case .animeTopRated: return "animeTopRated"
        case .animeNewlyAdded: return "animeNewlyAdded"
        case .mangaEssentials: return "mangaEssentials"
        case .mangaClassics: return "mangaClassics"
        case .mangaNewToYou: return "mangaNewToYou"
        }
    }

    var title: String {
        switch self {
        case .animeEssentials: return "ESSENTIAL ANIME"
        case .animeClassics: return "CLASSICS"
        case .animeNewToYou: return "NEW TO YOU"
        case .animeAiringToday: return "AIRING TODAY"
        case .animeCurrentSeason: return "CURRENT SEASON"
        case .animeTrending: return "TRENDING"
        case .animeTopRated: return "TOP RATED"
        case .animeNewlyAdded: return "JUST ADDED"
        case .mangaEssentials: return "ESSENTIAL MANGA"
        case .mangaClassics: return "MANGA CLASSICS"
        case .mangaNewToYou: return "NEW TO YOU (MANGA)"
        }
    }
}
