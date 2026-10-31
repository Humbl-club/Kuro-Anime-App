import Foundation
import KuroCore

// Capability-owned contract. Declaration bodies and wire names are preserved from the shared collection.
struct MediaLadderItem: Decodable, Identifiable, Sendable {
    let mediaType: String
    let mediaId: Int
    let title: String
    let coverImage: String?
    let year: Int?
    let format: String?
    let rating: Double?
    let reasonLabel: String?
    let sourceAuthorName: String?

    var id: String { "\(mediaType)-\(mediaId)" }

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case title
        case coverImage = "cover_image"
        case year
        case format
        case rating
        case reasonLabel = "reason_label"
        case sourceAuthorName = "source_author_name"
    }

    func toMedia() -> Media {
        Media(
            id: mediaId,
            kind: mediaType.uppercased() == "MANGA" ? .manga : .anime,
            title: title,
            imageURL: coverImage,
            year: year.map(String.init) ?? "TBA",
            displayDescription: "",
            episodes: nil,
            chapters: nil,
            rating: rating,
            genres: nil,
            statusRaw: nil,
            formatRaw: format,
            popularityValue: nil,
            trendingValue: nil,
            createdAtValue: nil
        )
    }
}

enum MediaLadderCoverageStatus: String, Decodable, Sendable {
    case strong
    case partial
    case minimal
}

struct MediaLadderResponse: Decodable, Sendable {
    let sourceMaterial: [MediaLadderItem]
    let adaptations: [MediaLadderItem]
    let prequels: [MediaLadderItem]
    let sequels: [MediaLadderItem]
    let sideStories: [MediaLadderItem]
    let spinOffs: [MediaLadderItem]
    let entryPoint: MediaLadderItem?
    let nextStep: MediaLadderItem?
    let primarySource: MediaLadderItem?
    let primaryAdaptation: MediaLadderItem?
    let franchiseNote: String?
    let coverageStatus: MediaLadderCoverageStatus?
    let totalFranchiseCount: Int?
    let alternateAdaptationSummary: String?

    static let empty = MediaLadderResponse(
        sourceMaterial: [],
        adaptations: [],
        prequels: [],
        sequels: [],
        sideStories: [],
        spinOffs: [],
        entryPoint: nil,
        nextStep: nil,
        primarySource: nil,
        primaryAdaptation: nil,
        franchiseNote: nil,
        coverageStatus: nil,
        totalFranchiseCount: nil,
        alternateAdaptationSummary: nil
    )

    var hasContent: Bool {
        entryPoint != nil
            || nextStep != nil
            || primarySource != nil
            || primaryAdaptation != nil
            || !sourceMaterial.isEmpty
            || !adaptations.isEmpty
            || !prequels.isEmpty
            || !sequels.isEmpty
            || !sideStories.isEmpty
            || !spinOffs.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case sourceMaterial = "source_material"
        case adaptations
        case prequels
        case sequels
        case sideStories = "side_stories"
        case spinOffs = "spin_offs"
        case entryPoint = "entry_point"
        case nextStep = "next_step"
        case primarySource = "primary_source"
        case primaryAdaptation = "primary_adaptation"
        case franchiseNote = "franchise_note"
        case coverageStatus = "coverage_status"
        case totalFranchiseCount = "total_franchise_count"
        case alternateAdaptationSummary = "alternate_adaptation_summary"
    }
}
