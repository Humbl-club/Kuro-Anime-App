import Foundation

/// Whether two catalogue entries may share a verified continuity group.
/// A provider relation, a shared title or a calendar season is not membership.
public struct ContinuityEvidence: Equatable, Sendable {
    public enum Link: String, Sendable {
        case sequel
        case prequel
        case sideStory
        case adaptation
        case summary
        case spinOff
        case alternative
        case character
        case other
    }

    public var link: Link
    /// A reviewed override that this pair is the same story continuity.
    public var sameReviewedContinuity: Bool
    /// Catalogue format such as TV, MOVIE, MANGA, NOVEL. Not a calendar season.
    public var format: String

    public init(link: Link, sameReviewedContinuity: Bool, format: String) {
        self.link = link
        self.sameReviewedContinuity = sameReviewedContinuity
        self.format = format
    }
}

public enum ContinuityDecision: Equatable, Sendable {
    /// No approved group. The entry stays its own series.
    case singleton
    /// Approved membership. `label` is the visible kind (Film) and is never an invented season number.
    case join(label: String?)
    case distinct(reason: String)
}

public enum SeriesGrouping {
    public static func decide(_ evidence: ContinuityEvidence) -> ContinuityDecision {
        guard evidence.sameReviewedContinuity else {
            return .distinct(reason: "no approved continuity membership")
        }
        switch evidence.format.uppercased() {
        case "MOVIE", "FILM":
            return .join(label: "Film")
        case "SPECIAL", "OVA", "ONA", "MUSIC", "TV_SHORT":
            return .join(label: "Extra")
        default:
            return .join(label: nil)
        }
    }

    /// AniList's calendar MediaSeason is not an ordinal season.
    public static func ordinal(fromCalendarSeason season: String) -> Int? {
        _ = season
        return nil
    }
}
