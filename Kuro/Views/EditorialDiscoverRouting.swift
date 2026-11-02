import Foundation

/// The Discover rails' "See all" sheets. Titles are sentence case, EN/DE (rulebook §4, §10).
enum EditorialDiscoverRoute: Identifiable, CaseIterable {
    case animeEssentials
    case animeClassics
    case animeNewToYou
    case animeBecauseYou
    case animeAiringToday
    case animeCurrentSeason
    case animeTrending
    case animeTopRated
    case animeNewlyAdded
    case mangaEssentials
    case mangaClassics
    case mangaNewToYou
    case mangaTrending
    case mangaTopRated
    case mangaNewlyAdded

    var id: String {
        switch self {
        case .animeEssentials: return "animeEssentials"
        case .animeClassics: return "animeClassics"
        case .animeNewToYou: return "animeNewToYou"
        case .animeBecauseYou: return "animeBecauseYou"
        case .animeAiringToday: return "animeAiringToday"
        case .animeCurrentSeason: return "animeCurrentSeason"
        case .animeTrending: return "animeTrending"
        case .animeTopRated: return "animeTopRated"
        case .animeNewlyAdded: return "animeNewlyAdded"
        case .mangaEssentials: return "mangaEssentials"
        case .mangaClassics: return "mangaClassics"
        case .mangaNewToYou: return "mangaNewToYou"
        case .mangaTrending: return "mangaTrending"
        case .mangaTopRated: return "mangaTopRated"
        case .mangaNewlyAdded: return "mangaNewlyAdded"
        }
    }

    var isManga: Bool {
        switch self {
        case .mangaEssentials, .mangaClassics, .mangaNewToYou, .mangaTrending, .mangaTopRated, .mangaNewlyAdded:
            return true
        default:
            return false
        }
    }

    /// The section's name in the reader's language.
    var title: String { title(german: KuroLocale.isGerman) }

    func title(german: Bool, reason: String? = nil) -> String {
        switch self {
        case .animeEssentials: return german ? "Unverzichtbare Anime" : "Essential anime"
        case .animeClassics: return german ? "Klassiker" : "Classics"
        case .animeNewToYou: return german ? "Neu für dich" : "New to you"
        case .animeBecauseYou:
            if let reason, !reason.isEmpty {
                return german ? "Weil du \(reason) mochtest" : "Because you loved \(reason)"
            }
            return german ? "Ähnlich wie deine Favoriten" : "Close to your favourites"
        case .animeAiringToday: return german ? "Läuft heute" : "Airing today"
        case .animeCurrentSeason: return german ? "Diese Season" : "This season"
        case .animeTrending: return german ? "Gerade beliebt" : "Trending"
        case .animeTopRated: return german ? "Am besten bewertet" : "Top rated"
        case .animeNewlyAdded: return german ? "Neu hinzugefügt" : "Just added"
        case .mangaEssentials: return german ? "Unverzichtbare Manga" : "Essential manga"
        case .mangaClassics: return german ? "Manga-Klassiker" : "Manga classics"
        case .mangaNewToYou: return german ? "Manga, neu für dich" : "Manga new to you"
        case .mangaTrending: return german ? "Beliebte Manga" : "Trending manga"
        case .mangaTopRated: return german ? "Bestbewertete Manga" : "Top rated manga"
        case .mangaNewlyAdded: return german ? "Neue Manga" : "Manga just added"
        }
    }
}
