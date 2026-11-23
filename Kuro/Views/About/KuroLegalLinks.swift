import Foundation

// MARK: - Legal and credit links (one place)
// All legal pages are served from `legalSiteBase` (Vercel project kuro-legal). Switch `legalSiteBase`
// once a custom domain is attached, together with `ALLOWED_ORIGINS` in
// `supabase/functions/contact-submit/handler.ts`. Source hosts are fixed per source (spec §3.3a).

enum KuroLegalLinks {
    /// Production legal site hostname (Vercel project kuro-legal).
    static let legalSiteBase = "https://kuro-legal.vercel.app"

    static let privacy = URL(string: legalSiteBase + "/privacy")

    /// The privacy policy's contact-form section (Art. 13 GDPR information at the point of
    /// collection): the German section for German, the English one otherwise.
    static func privacyContactForm(german: Bool) -> URL? {
        URL(string: legalSiteBase + (german ? "/datenschutz#kontaktformular" : "/datenschutz#contact-form"))
    }

    static let terms: URL? = URL(string: legalSiteBase + "/terms")
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
