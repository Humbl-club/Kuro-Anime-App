import Foundation

#if canImport(Supabase)
import Supabase
#endif

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

// MARK: - SupabaseService

#if canImport(Supabase)
extension SupabaseService {

    /// nil on error OR empty rotation (no eligible boosts) — callers fall back
    /// to the legacy hero in both cases.
    func fetchDailyFeature() async -> DailyFeature? {
        do {
            let rows: [DailyFeature] = try await client
                .rpc("fetch_daily_feature")
                .execute()
                .value
            return rows.first
        } catch {
            #if DEBUG
            print("❌ fetchDailyFeature error: \(error)")
            #endif
            return nil
        }
    }

    /// nil on error, [] when the user is below the evidence floor — callers
    /// keep the editorial NEW TO YOU rail in both cases.
    func fetchBecauseYouRail(limit: Int = 12) async -> [BecauseYouCard]? {
        do {
            let rows: [BecauseYouCard] = try await client
                .rpc("fetch_because_you_rail", params: RPCFetchBecauseYouRailParams(p_limit: limit))
                .execute()
                .value
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchBecauseYouRail error: \(error)")
            #endif
            return nil
        }
    }

    /// Stage 4 The Shelf — tonight's realm rail. nil on error; [] when empty.
    func fetchTonightShelf(limit: Int = 12) async -> [TonightShelfCard]? {
        do {
            let rows: [TonightShelfCard] = try await client
                .rpc("fetch_tonight_shelf", params: RPCFetchTonightShelfParams(p_limit: limit))
                .execute()
                .value
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchTonightShelf error: \(error)")
            #endif
            return nil
        }
    }

    /// Stage 4 Hidden Gem — 0 or 1 weekly pick in tonight's realm.
    func fetchRealmHiddenGem() async -> RealmHiddenGem? {
        do {
            let rows: [RealmHiddenGem] = try await client
                .rpc("fetch_realm_hidden_gem")
                .execute()
                .value
            return rows.first
        } catch {
            #if DEBUG
            print("❌ fetchRealmHiddenGem error: \(error)")
            #endif
            return nil
        }
    }
}
#endif

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
