import Foundation

// MARK: - Concierge recommend model
// Wire shape of the `concierge-recommend` edge function (deterministic picks; the optional narration
// is server-side Groq copy only), moved verbatim from the former `SupabaseService` nested type.
// Owner: `ConciergeStore`. Account-scoped: the picks leave out the caller's tracked titles.

struct ConciergeRecommendResponse: Decodable, Sendable {
    let success: Bool
    let locale: String?
    let curatorNote: String?
    let categories: [String]?
    struct Mode: Decodable, Sendable, Identifiable {
        let id: String
        let title: String
        let confidence: Double?
        let reason: String?
    }
    struct Item: Decodable, Sendable, Identifiable {
        let mediaType: String
        let mediaId: Int
        let matchCount: Int?
        let title: String
        let coverImageMedium: String?
        let averageScore: Int?
        let year: Int?
        let format: String?
        let status: String?
        let siteUrl: String?
        let signals: [String]?
        let blurb: String?

        var id: String { "\(mediaType)|\(mediaId)" }
    }
    struct Set: Decodable, Sendable, Identifiable {
        let id: String
        let title: String
        let internalTitle: String?
        let displayTitle: String?
        let displaySubtitle: String?
        let curatorNote: String?
        let locale: String?
        let modeId: String?
        let confidence: Double?
        let reason: String?
        let items: [Item]?
    }
    struct Assist: Decodable, Sendable {
        let ragUsed: Bool?
        let seedEntityId: String?

        enum CodingKeys: String, CodingKey {
            case ragUsed
            case seedEntityId
        }
    }
    let modes: [Mode]?
    let sets: [Set]?
    let items: [Item]?
    let assist: Assist?
    let message: String?
    let narrated: Bool?
    let error: String?
}
