import Foundation

// MARK: - Catalog column lists (explicit PostgREST projections)
// Every catalog read names its columns instead of `select=*`, for two reasons (api-surface audit
// 2026-11-01, P1):
// - waste: the `anime` / `manga` rows carry ~65 columns, of which the app decodes about 50;
// - exposure: the extra columns include the internal moderation state (`safety_*`, including model
//   rationale and errors) and the synopsis pipeline state (`synopsis_enhanced_*`, including the last
//   error). Neither may ship to clients.
// Detail lists are derived from the decoders' `CodingKeys`, minus `omittedDetailColumns`, so a field
// added to a decoder is selected automatically and nothing a decoder needs is ever left out.
// Two synopsis columns are kept on purpose: `synopsis_enhanced` (the shown text) and
// `synopsis_enhanced_state` (the gate `displayDescription` checks; without it a pending or failed
// enhancement would be treated as ready). Card projections carry only what cards and rails read plus
// the decoders' non-optional fields (`id`, `is_adult`, `created_at`, `updated_at`).

enum CatalogColumns {

    /// Decoded by `Anime` / `Manga` but internal or unused by every view: never selected.
    static let omittedDetailColumns: Set<String> = [
        "description_normalized",
        "synopsis_enhanced_source",
        "synopsis_enhanced_model",
        "synopsis_enhanced_version",
        "synopsis_enhanced_updated_at",
    ]

    /// Whether `column` is internal pipeline or moderation state that no client read may select.
    nonisolated static func isInternalColumn(_ column: String) -> Bool {
        let name = column.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("safety_") { return true }
        if name.hasPrefix("synopsis_enhanced_") && name != "synopsis_enhanced_state" { return true }
        return name == "description_normalized"
    }

    /// The PostgREST `select` value for a column list.
    nonisolated static func select(_ columns: [String]) -> String {
        columns.joined(separator: ",")
    }

    // MARK: Anime / Manga

    /// Full detail model (`Anime`): every decoded column except the omitted ones.
    static let animeDetail: [String] = Anime.CodingKeys.allCases
        .map(\.rawValue)
        .filter { !omittedDetailColumns.contains($0) }

    /// Full detail model (`Manga`): every decoded column except the omitted ones.
    static let mangaDetail: [String] = Manga.CodingKeys.allCases
        .map(\.rawValue)
        .filter { !omittedDetailColumns.contains($0) }

    /// Card projection of `Anime` for rails ("More like this", next pick): titles, cover, format,
    /// status, counts, year, score, genres (content rules), plus the decoder's required fields.
    /// A row read with it is never put in the detail cache.
    static let animeCard: [String] = [
        "id", "title_english", "title_romaji", "title_native",
        "cover_image_large", "cover_image_medium", "banner_image",
        "format", "status", "episodes", "season", "season_year", "start_date_year",
        "next_episode_number", "next_airing_at",
        "average_score", "popularity", "trending", "favourites", "genres",
        "is_adult", "created_at", "updated_at",
    ]

    /// Card projection of `Manga` (see `animeCard`).
    static let mangaCard: [String] = [
        "id", "title_english", "title_romaji", "title_native",
        "cover_image_large", "cover_image_medium",
        "format", "status", "chapters", "volumes", "start_date_year",
        "average_score", "popularity", "trending", "favourites", "genres",
        "is_adult", "created_at", "updated_at",
    ]

    // MARK: Units, links

    /// Episode rows for the preview and the episode list: every decoded column but the long
    /// `description`, which no view shows.
    static let episodeList: [String] = Episode.CodingKeys.allCases
        .map(\.rawValue)
        .filter { $0 != "description" }

    /// Chapter rows for the preview and the chapter list (no `description`, as for episodes).
    static let chapterList: [String] = MangaChapter.CodingKeys.allCases
        .map(\.rawValue)
        .filter { $0 != "description" }

    /// The two columns the watch link of one episode needs.
    static let episodeStreamLink: [String] = ["stream_url", "stream_site"]

    /// External links (`ExternalLink`): every decoded column.
    static let externalLinks: [String] = ExternalLink.CodingKeys.allCases.map(\.rawValue)

    // MARK: Credits (inline sections; entity descriptions are not shown, so never fetched)

    static let characterEmbed = "characters(id, anilist_id, name_full, name_native, image_large, gender, age)"
    static let staffEmbed = "staff(id, anilist_id, name_full, name_native, image_large, primary_occupations)"
    static let authorEmbed = "authors(id, anilist_id, name_full, name_native, image_large)"

    /// Row bound for an inline credits read. The importers keep 10 characters and 10 staff per title
    /// (`perPage: 10`), so the bound never changes what is shown; it only caps a pathological title.
    static let creditsRowLimit = 50

    /// Row bound for an entity sheet's works (studio, staff, author, character). The sheets sort
    /// client-side; the bound caps a very large studio. The read is ordered by `entityWorksOrder`
    /// first, so the rows kept are the highest-rated, matching the sheets' default sort.
    static let entityWorksRowLimit = 500

    /// The server order of an entity works read: the parent join rows ordered by the embedded title's
    /// `average_score` (PostgREST to-one embed ordering, `order=anime(average_score).desc.nullslast`;
    /// the hosted PostgREST is v14). Not `referencedTable:`, which would order inside the embed only.
    static func entityWorksOrder(embed: String) -> String {
        "\(embed)(average_score)"
    }

    /// Every list above, for the internal-column guard test.
    static var allColumnLists: [String: [String]] {
        [
            "animeDetail": animeDetail, "mangaDetail": mangaDetail,
            "animeCard": animeCard, "mangaCard": mangaCard,
            "episodeList": episodeList, "chapterList": chapterList,
            "episodeStreamLink": episodeStreamLink, "externalLinks": externalLinks,
        ]
    }
}
