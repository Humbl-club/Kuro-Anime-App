import Foundation
import KuroCore

// MARK: - Discover P1 (daily feature + Because-You rail)
// Backend contract (supabase/migrations/20260731100000_discover_p1.sql):
//   fetch_daily_feature()           -> zero or one hero row for "The One Thing"
//   fetch_because_you_rail(p_limit) -> card rows + reason_title (0 rows when the
//                                      caller has < 2 distinct positive titles)

/// The daily editorial hero ("The One Thing"): one boosted title + its argument.
struct DailyFeature: Identifiable, Codable, Sendable {
    let mediaType: String // "ANIME" | "MANGA"
    let mediaId: Int
    let title: String
    let coverImageLarge: String?
    let bannerImage: String?
    let genres: [String]?
    let score: Int?
    let year: Int?
    let format: String?
    let argument: String?

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case title
        case coverImageLarge = "cover_image_large"
        case bannerImage = "banner_image"
        case genres
        case score
        case year
        case format
        case argument
    }

    var id: String { "\(mediaType.lowercased())-\(mediaId)" }

    var kind: MediaKind { mediaType.uppercased() == "MANGA" ? .manga : .anime }

    /// Hero art: banner wins (wide crop), cover as fallback.
    var artURL: URL? {
        guard let raw = bannerImage ?? coverImageLarge, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

/// One card row from `fetch_because_you_rail`: deck-batch shape minus meta
/// columns, plus `reason_title` (the #1 seed's display title, same per row).
struct BecauseYouCard: Identifiable, Codable, Sendable {
    let mediaType: String
    let mediaId: Int
    let title: String
    let coverImageLarge: String?
    let coverImageMedium: String?
    let coverImageColor: String?
    let genres: [String]?
    let averageScore: Int?
    let format: String?
    let year: Int?
    let synopsis: String?
    let episodes: Int?
    let chapters: Int?
    let volumes: Int?
    let reasonTitle: String?

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case title
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case coverImageColor = "cover_image_color"
        case genres
        case averageScore = "average_score"
        case format
        case year
        case synopsis
        case episodes
        case chapters
        case volumes
        case reasonTitle = "reason_title"
    }

    var id: String { "\(mediaType.lowercased())-\(mediaId)" }
}

// MARK: - RPC params

struct RPCFetchBecauseYouRailParams: Encodable, Sendable {
    let p_limit: Int
}

struct RPCFetchTonightShelfParams: Encodable, Sendable {
    let p_limit: Int
}

/// Discover Stage 4 — The Shelf ("tonight's realm") card row.
struct TonightShelfCard: Identifiable, Codable, Sendable {
    let realm: String?
    let displayName: String?
    let blurb: String?
    let mediaType: String
    let mediaId: Int
    let title: String
    let coverImageLarge: String?
    let coverImageMedium: String?
    let coverImageColor: String?
    let genres: [String]?
    let averageScore: Int?
    let format: String?
    let year: Int?
    let synopsis: String?
    let episodes: Int?
    let chapters: Int?
    let volumes: Int?

    enum CodingKeys: String, CodingKey {
        case realm
        case displayName = "display_name"
        case blurb
        case mediaType = "media_type"
        case mediaId = "media_id"
        case title
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case coverImageColor = "cover_image_color"
        case genres
        case averageScore = "average_score"
        case format
        case year
        case synopsis
        case episodes
        case chapters
        case volumes
    }

    var id: String { "\(mediaType.lowercased())-\(mediaId)" }
}

/// Discover Stage 4 — Hidden Gem (high-tier, low-popularity in tonight's realm).
struct RealmHiddenGem: Identifiable, Codable, Sendable {
    let realm: String?
    let displayName: String?
    let blurb: String?
    let mediaType: String
    let mediaId: Int
    let title: String
    let coverImageLarge: String?
    let bannerImage: String?
    let genres: [String]?
    let score: Int?
    let year: Int?
    let format: String?
    let argument: String?

    enum CodingKeys: String, CodingKey {
        case realm
        case displayName = "display_name"
        case blurb
        case mediaType = "media_type"
        case mediaId = "media_id"
        case title
        case coverImageLarge = "cover_image_large"
        case bannerImage = "banner_image"
        case genres
        case score
        case year
        case format
        case argument
    }

    var id: String { "\(mediaType.lowercased())-\(mediaId)" }
    var kind: MediaKind { mediaType.uppercased() == "MANGA" ? .manga : .anime }
    var artURL: URL? {
        guard let raw = bannerImage ?? coverImageLarge, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

// MARK: - Adapters

extension BecauseYouCard {
    /// Maps a rail row onto the neutral display model the Discover grids render
    /// (mixed anime + manga feed, so `Media` instead of AnimeCard).
    func toMedia() -> Media {
        Media(
            id: mediaId,
            kind: mediaType.uppercased() == "MANGA" ? .manga : .anime,
            title: title,
            imageURL: {
                guard let raw = coverImageLarge ?? coverImageMedium, !raw.isEmpty else { return nil }
                return raw
            }(),
            year: year.map(String.init) ?? "TBA",
            displayDescription: synopsis ?? "",
            episodes: episodes,
            chapters: chapters,
            rating: averageScore.map { Double($0) / 10.0 },
            genres: genres,
            statusRaw: nil,
            formatRaw: format,
            popularityValue: nil,
            trendingValue: nil,
            createdAtValue: nil
        )
    }
}

extension TonightShelfCard {
    func toMedia() -> Media {
        Media(
            id: mediaId,
            kind: mediaType.uppercased() == "MANGA" ? .manga : .anime,
            title: title,
            imageURL: {
                guard let raw = coverImageLarge ?? coverImageMedium, !raw.isEmpty else { return nil }
                return raw
            }(),
            year: year.map(String.init) ?? "TBA",
            displayDescription: synopsis ?? "",
            episodes: episodes,
            chapters: chapters,
            rating: averageScore.map { Double($0) / 10.0 },
            genres: genres,
            statusRaw: nil,
            formatRaw: format,
            popularityValue: nil,
            trendingValue: nil,
            createdAtValue: nil
        )
    }
}

extension RealmHiddenGem {
    func toDailyFeature() -> DailyFeature {
        DailyFeature(
            mediaType: mediaType,
            mediaId: mediaId,
            title: title,
            coverImageLarge: coverImageLarge,
            bannerImage: bannerImage,
            genres: genres,
            score: score,
            year: year,
            format: format,
            argument: argument
        )
    }
}
