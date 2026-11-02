import Foundation

// MARK: - Discovery policy
// Catalog-wide content rules applied to every public discovery surface (rails, similar titles,
// entity works): no adult titles, no Hentai, and no Ecchi unless a policy opts in.

struct DiscoveryPolicy: Sendable {
    var includeAdult: Bool = false
    var excludeEcchi: Bool = true
}

enum DiscoveryContentRules {

    static func sanitizeAnimeForDiscovery(_ items: [Anime]) -> [Anime] {
        sanitizeAnimeForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    static func sanitizeAnimeForDiscovery(_ items: [Anime], policy: DiscoveryPolicy) -> [Anime] {
        items.filter { anime in
            if !policy.includeAdult {
                if anime.isAdult { return false }
                if anime.genres?.contains("Hentai") == true { return false }
            }
            if policy.excludeEcchi {
                if anime.genres?.contains("Ecchi") == true { return false }
            }
            return true
        }
    }

    static func sanitizeMangaForDiscovery(_ items: [Manga]) -> [Manga] {
        sanitizeMangaForDiscovery(items, policy: DiscoveryPolicy(includeAdult: false, excludeEcchi: true))
    }

    static func sanitizeMangaForDiscovery(_ items: [Manga], policy: DiscoveryPolicy) -> [Manga] {
        items.filter { manga in
            if !policy.includeAdult {
                if manga.isAdult { return false }
                if manga.genres?.contains("Hentai") == true { return false }
            }
            if policy.excludeEcchi {
                if manga.genres?.contains("Ecchi") == true { return false }
            }
            return true
        }
    }

    /// Entity works (studio / staff / author / character sheets): no Hentai, no Ecchi.
    static func sanitizeMediaForDiscovery(_ items: [Media]) -> [Media] {
        items.filter { media in
            let genres = media.genres ?? []
            if genres.contains("Hentai") { return false }
            if genres.contains("Ecchi") { return false }
            return true
        }
    }
}
