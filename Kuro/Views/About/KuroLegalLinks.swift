import Foundation

// MARK: - Legal and credit links (one place)
// `privacy` is the link the app has always shown (confirm it is live before release,
// docs/app-store-metadata.md). `terms` stays nil until the owner confirms a real Terms page: an
// invented URL is never shipped, and Profile hides the row while it is nil. Source hosts are fixed
// per source (spec §3.3a).

enum KuroLegalLinks {
    static let privacy = URL(string: "https://kuro.app/privacy")
    /// Owner request: set the confirmed Terms of service URL here; nil hides the row.
    static let terms: URL? = nil
}

/// A catalogue or release source Kuro credits (spec D11, sources.md).
struct KuroDataSource: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let url: URL?
    let englishUse: String
    let germanUse: String

    func use(german: Bool) -> String { german ? germanUse : englishUse }

    /// The sources in the order the screen lists them. Wording stays true while optional intake is
    /// not running: "where available" claims nothing about coverage.
    static let all: [KuroDataSource] = [
        KuroDataSource(
            id: "anilist", name: "AniList", host: "anilist.co", url: URL(string: "https://anilist.co"),
            englishUse: "Anime and manga catalogue: titles, artwork, episodes, chapters and airing times.",
            germanUse: "Anime- und Manga-Katalog: Titel, Bilder, Folgen, Kapitel und Sendezeiten."
        ),
        KuroDataSource(
            id: "mangadex", name: "MangaDex", host: "mangadex.org", url: URL(string: "https://mangadex.org"),
            englishUse: "Manga chapter information, where available.",
            germanUse: "Informationen zu Manga-Kapiteln, wo verfügbar."
        ),
        KuroDataSource(
            id: "mangaupdates", name: "MangaUpdates", host: "mangaupdates.com", url: URL(string: "https://www.mangaupdates.com"),
            englishUse: "Manga release information, where available.",
            germanUse: "Informationen zu Manga-Veröffentlichungen, wo verfügbar."
        ),
        KuroDataSource(
            id: "animethemes", name: "AnimeThemes", host: "animethemes.moe", url: URL(string: "https://animethemes.moe"),
            englishUse: "Opening and ending song information, where available.",
            germanUse: "Informationen zu Vor- und Abspannliedern, wo verfügbar."
        )
    ]
}
