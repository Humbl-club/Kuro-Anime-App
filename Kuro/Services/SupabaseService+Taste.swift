import Foundation
import Observation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Taste Deck (deck signals + taste profile)
// Backend contract (ADR 2026-07-31 — Taste learning + representation):
//   fetch_taste_deck_batch(p_limit)              -> rows of deck cards
//   record_taste_deck_signal(type, id, action)   -> jsonb (fire-and-forget)
//   fetch_my_taste_profile()                     -> zero or one profile row
//   fetch_personalized_new_to_you(p_limit, type) -> same row shape as deck batch

enum TasteDeckAction: String, Codable, Sendable {
    case love
    case known
    case skip
    case pass
    case retract
}

struct TasteDeckCard: Identifiable, Codable, Sendable {
    let mediaType: String // "ANIME" | "MANGA"
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
    // Deck v1.1 meta strip (all optional: absent on rows from older RPC shapes).
    let episodes: Int?
    let chapters: Int?
    let volumes: Int?
    let seasonsCount: Int?
    /// Tri-state: true/false from availability rows, nil when unknown. Unknown ≠ false.
    let hasDub: Bool?
    let hasSub: Bool?

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
        case seasonsCount = "seasons_count"
        case hasDub = "has_dub"
        case hasSub = "has_sub"
    }

    var id: String { stableKey }

    /// Stable identity across mixed feeds, MediaDisplayable-style ("anime-123").
    var stableKey: String { "\(mediaType.lowercased())-\(mediaId)" }

    var imageURL: URL? {
        guard let raw = coverImageLarge ?? coverImageMedium, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// One quiet caption line: "Drama · Sci-Fi · 2019 · TV".
    var captionLine: String {
        var parts: [String] = []
        if let genres, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: " · "))
        }
        if let year { parts.append(String(year)) }
        if let format, !format.isEmpty { parts.append(format) }
        return parts.joined(separator: " · ")
    }

    /// Modern meta strip on the deck image — the only chrome the art carries:
    /// the medium first ("ANIME" / "MANGA" — unmistakable in the unified deck),
    /// then length/format capsules, then one language capsule on positive
    /// knowledge only ("DUB" wins over "SUB"; nothing when availability is unknown).
    var metaChips: [String] {
        var chips: [String] = [mediaType.uppercased() == "MANGA" ? "MANGA" : "ANIME"]
        guard mediaType.uppercased() == "ANIME" else {
            if let volumes, volumes > 0 {
                chips.append("VOL \(volumes)")
            } else if let chapters, chapters > 0 {
                chips.append(chapters == 1 ? "1 CH" : "\(chapters) CH")
            }
            return chips
        }
        if format?.uppercased() == "MOVIE" {
            chips.append("FILM")
        } else {
            if let episodes, episodes > 0 {
                chips.append(episodes == 1 ? "1 EP" : "\(episodes) EP")
            }
            if format?.uppercased() == "TV", let seasonsCount, seasonsCount > 0 {
                chips.append(seasonsCount == 1 ? "1 SEASON" : "\(seasonsCount) SEASONS")
            }
        }
        if hasDub == true {
            chips.append("DUB")
        } else if hasSub == true {
            chips.append("SUB")
        }
        return chips
    }

    var cleanSynopsis: String? {
        guard let synopsis else { return nil }
        guard let cleaned = TextNormalization.sanitizeMediaDescription(synopsis), !cleaned.isEmpty else { return nil }
        return cleaned
    }
}

/// Decoded form of the `vector` jsonb column returned by `fetch_my_taste_profile`.
/// Tolerant of missing fields so a partially-computed profile never breaks decoding.
struct TasteProfileVector: Decodable, Sendable {
    var genres: [String: Double]
    var tags: [String: Double]
    var avoidedTags: [String]
    var confidence: Double
    var eventCount: Int
    var computedAt: Date?

    enum CodingKeys: String, CodingKey {
        case genres
        case tags
        case avoidedTags = "avoided_tags"
        case confidence
        case eventCount = "event_count"
        case computedAt = "computed_at"
    }

    init(
        genres: [String: Double] = [:],
        tags: [String: Double] = [:],
        avoidedTags: [String] = [],
        confidence: Double = 0,
        eventCount: Int = 0,
        computedAt: Date? = nil
    ) {
        self.genres = genres
        self.tags = tags
        self.avoidedTags = avoidedTags
        self.confidence = confidence
        self.eventCount = eventCount
        self.computedAt = computedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genres = (try? container.decodeIfPresent([String: Double].self, forKey: .genres)) ?? [:]
        tags = (try? container.decodeIfPresent([String: Double].self, forKey: .tags)) ?? [:]
        avoidedTags = (try? container.decodeIfPresent([String].self, forKey: .avoidedTags)) ?? []
        confidence = (try? container.decodeIfPresent(Double.self, forKey: .confidence)) ?? 0
        eventCount = (try? container.decodeIfPresent(Int.self, forKey: .eventCount)) ?? 0
        computedAt = try? container.decodeIfPresent(Date.self, forKey: .computedAt)
    }
}

struct TasteProfile: Sendable {
    var genres: [String: Double]
    var tags: [String: Double]
    var avoidedTags: [String]
    var confidence: Double
    var eventCount: Int
    var computedAt: Date?
    var updatedAt: Date?

    init(vector: TasteProfileVector?, updatedAt: Date?) {
        genres = vector?.genres ?? [:]
        tags = vector?.tags ?? [:]
        avoidedTags = vector?.avoidedTags ?? []
        confidence = vector?.confidence ?? 0
        eventCount = vector?.eventCount ?? 0
        computedAt = vector?.computedAt ?? nil
        self.updatedAt = updatedAt
    }

    /// Strong-signal tiers from the contract end at 0.15+ (15+ strong events).
    var confidenceWord: String { confidence >= 0.15 ? "confident" : "emerging" }

    var topGenres: [(name: String, weight: Double)] {
        genres.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var topTags: [(name: String, weight: Double)] {
        tags.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

private struct TasteProfileRow: Decodable {
    let vector: TasteProfileVector?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case vector
        case updatedAt = "updated_at"
    }
}

// MARK: - RPC params

struct RPCFetchTasteDeckBatchParams: Encodable, Sendable {
    let p_limit: Int
}

struct RPCRecordTasteDeckSignalParams: Encodable, Sendable {
    let p_media_type: String
    let p_media_id: Int
    let p_action: String
}

struct RPCFetchPersonalizedNewToYouParams: Encodable, Sendable {
    let p_limit: Int
    let p_media_type: String
}

// MARK: - SupabaseService

#if canImport(Supabase)
extension SupabaseService {

    /// nil on error (distinct from an empty-but-successful deal, so callers can
    /// avoid marking the deck exhausted on transport failures).
    func fetchTasteDeckBatch(limit: Int = 12) async -> [TasteDeckCard]? {
        do {
            let rows: [TasteDeckCard] = try await client
                .rpc("fetch_taste_deck_batch", params: RPCFetchTasteDeckBatchParams(p_limit: limit))
                .execute()
                .value
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchTasteDeckBatch error: \(error)")
            #endif
            return nil
        }
    }

    @discardableResult
    func recordTasteDeckSignal(mediaType: String, mediaId: Int, action: TasteDeckAction) async -> Bool {
        do {
            let params = RPCRecordTasteDeckSignalParams(
                p_media_type: mediaType.uppercased(),
                p_media_id: mediaId,
                p_action: action.rawValue
            )
            let _: AnyJSON = try await client
                .rpc("record_taste_deck_signal", params: params)
                .execute()
                .value
            return true
        } catch {
            #if DEBUG
            print("❌ recordTasteDeckSignal error: \(error)")
            #endif
            return false
        }
    }

    /// Zero rows means the profile hasn't been computed yet -> nil.
    func fetchMyTasteProfile() async -> TasteProfile? {
        do {
            let rows: [TasteProfileRow] = try await client
                .rpc("fetch_my_taste_profile")
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return TasteProfile(vector: row.vector, updatedAt: row.updatedAt)
        } catch {
            #if DEBUG
            print("❌ fetchMyTasteProfile error: \(error)")
            #endif
            return nil
        }
    }

    /// nil on error, [] when the RPC has no personalized candidates — callers
    /// fall back to bundle data in both cases.
    func fetchPersonalizedNewToYou(limit: Int = 20, mediaType: String = "ANIME") async -> [TasteDeckCard]? {
        do {
            let params = RPCFetchPersonalizedNewToYouParams(p_limit: limit, p_media_type: mediaType)
            let rows: [TasteDeckCard] = try await client
                .rpc("fetch_personalized_new_to_you", params: params)
                .execute()
                .value
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchPersonalizedNewToYou error: \(error)")
            #endif
            return nil
        }
    }
}
#endif

// MARK: - Adapters

extension TasteDeckCard {
    /// Maps a personalized row onto the card model the Discover rails render.
    /// Only meaningful for ANIME rows (the rail is anime-only).
    func toAnimeCard() -> AnimeCard {
        AnimeCard(
            id: mediaId,
            titleEnglish: title,
            titleRomaji: nil,
            titleNative: nil,
            coverImageLarge: coverImageLarge,
            coverImageMedium: coverImageMedium,
            bannerImage: nil,
            format: format,
            status: nil,
            episodeCount: nil,
            seasonYear: year,
            startDateYear: nil,
            averageScore: averageScore,
            popularity: nil,
            trending: nil,
            favourites: nil,
            genreList: genres,
            createdAt: nil,
            rank: nil
        )
    }
}
