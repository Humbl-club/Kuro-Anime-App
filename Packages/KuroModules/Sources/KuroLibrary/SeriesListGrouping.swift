import Foundation
import KuroCore

/// Reviewed series membership of one catalogue title (one `series_entry_spans` row with its
/// `series` and `series_sections` data). A title belongs to at most one series.
public struct SeriesMembership: Equatable, Sendable {
    public enum SectionKind: String, Sendable { case season, film, extra, edition }

    /// `series.id` (uuid text).
    public let seriesId: String
    /// The span's medium.
    public let medium: MediaKind
    public let sectionKind: SectionKind
    /// Reviewed `series_sections.ordinal`; never a calendar season or a sort position.
    public let ordinal: Int?
    public let sortOrder: Int
    public let sectionName: String
    public let isReviewed: Bool

    public init(seriesId: String, medium: MediaKind, sectionKind: SectionKind, ordinal: Int?, sortOrder: Int,
                sectionName: String, isReviewed: Bool) {
        self.seriesId = seriesId
        self.medium = medium
        self.sectionKind = sectionKind
        self.ordinal = ordinal
        self.sortOrder = sortOrder
        self.sectionName = sectionName
        self.isReviewed = isReviewed
    }

    /// Reviewed = continuity verified AND series approved AND section approved AND same medium.
    /// A `series` row inserted with its defaults is approved but `singleton`, so it never counts.
    public static func isReviewed(continuity: String, groupingState: String, sectionState: String,
                                  seriesMedium: String, spanMedium: String) -> Bool {
        continuity == "verified" && groupingState == "approved" && sectionState == "approved"
            && seriesMedium == spanMedium
    }
}

/// One Collection row: a single entry or a reviewed series of two or more tracked members.
/// Display only: `members` are the caller's entries, never copies with changed fields.
public struct SeriesListRow: Identifiable, Equatable, Sendable {
    public enum ID: Hashable, Sendable {
        case entry(MediaKey)
        case series(MediaKind, String)
    }

    public let id: ID
    /// Byte-identical input entries, sorted by section sortOrder, then key.id.
    public let members: [LibraryEntry]
    /// The member that decides the status: the latest-updated Watching/Reading or
    /// Rewatching/Rereading member, else the latest-updated member. Placement and recency follow it.
    public let anchor: MediaKey
    /// The anchor's status.
    public let status: ListStatus
    /// The anchor when it is `.current`/`.repeating`, else nil.
    public let advanceTarget: MediaKey?

    public var displayMember: MediaKey { anchor }
    public var isGroup: Bool { members.count > 1 }

    public init(id: ID, members: [LibraryEntry], anchor: MediaKey, status: ListStatus, advanceTarget: MediaKey?) {
        self.id = id
        self.members = members
        self.anchor = anchor
        self.status = status
        self.advanceTarget = advanceTarget
    }
}

/// Lookup from a library key to its role in the rows.
public struct SeriesListIndex: Sendable {
    public enum Role: Equatable, Sendable {
        case single
        case anchor(SeriesListRow)
        case member(anchor: MediaKey)
    }

    private let roles: [MediaKey: Role]

    public init(rows: [SeriesListRow]) {
        var roles: [MediaKey: Role] = [:]
        for row in rows where row.isGroup {
            for member in row.members {
                roles[member.key] = member.key == row.anchor ? .anchor(row) : .member(anchor: row.anchor)
            }
        }
        self.roles = roles
    }

    public func role(of key: MediaKey) -> Role { roles[key] ?? .single }
}

public enum SeriesListGrouping {
    /// Proposed, confirm after baseline (W6 Task 2).
    public static let proposedBudget: Duration = .milliseconds(50)

    private static func format(for kind: SeriesMembership.SectionKind) -> String {
        switch kind {
        case .season, .edition: return "TV"
        case .film: return "MOVIE"
        case .extra: return "SPECIAL"
        }
    }

    private static func isActive(_ status: ListStatus) -> Bool { status == .current || status == .repeating }

    /// True when `a` should be the anchor instead of `b`: later `updatedAt`, then smaller
    /// `ListStatus` raw value, then larger `key.id`. Deterministic.
    private static func outranks(_ a: LibraryEntry, _ b: LibraryEntry) -> Bool {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        if a.status.rawValue != b.status.rawValue { return a.status.rawValue < b.status.rawValue }
        return a.key.id > b.key.id
    }

    /// Single pass, O(n). `entries` is newest first; row order follows each row's anchor.
    public static func rows(_ entries: [LibraryEntry], membership: [MediaKey: SeriesMembership],
                            enabled: Bool = true) -> [SeriesListRow] {
        func single(_ entry: LibraryEntry) -> SeriesListRow {
            SeriesListRow(id: .entry(entry.key), members: [entry], anchor: entry.key, status: entry.status,
                          advanceTarget: isActive(entry.status) ? entry.key : nil)
        }
        guard enabled else { return entries.map(single) }

        struct Joined { var entries: [LibraryEntry]; var sort: [MediaKey: Int] }
        var groups: [String: Joined] = [:]
        var slots: [(position: Int, groupKey: String?, entry: LibraryEntry)] = []
        slots.reserveCapacity(entries.count)
        for (position, entry) in entries.enumerated() {
            guard let m = membership[entry.key], m.medium == entry.key.kind,
                  case .join = SeriesGrouping.decide(ContinuityEvidence(
                    link: .other, sameReviewedContinuity: m.isReviewed, format: format(for: m.sectionKind)))
            else {
                slots.append((position, nil, entry))
                continue
            }
            let groupKey = "\(entry.key.kind.rawValue):\(m.seriesId)"
            var joined = groups[groupKey] ?? Joined(entries: [], sort: [:])
            joined.entries.append(entry)
            joined.sort[entry.key] = m.sortOrder
            groups[groupKey] = joined
            slots.append((position, groupKey, entry))
        }

        var built: [(position: Int, row: SeriesListRow)] = []
        built.reserveCapacity(slots.count)
        var emitted: Set<String> = []
        // Anchor positions need the group's anchor entry's input position.
        var positionOf: [MediaKey: Int] = [:]
        for slot in slots { positionOf[slot.entry.key] = slot.position }
        for slot in slots {
            guard let groupKey = slot.groupKey, let joined = groups[groupKey], joined.entries.count > 1 else {
                built.append((slot.position, single(slot.entry)))
                continue
            }
            guard emitted.insert(groupKey).inserted else { continue }
            let active = joined.entries.filter { isActive($0.status) }
            let pool = active.isEmpty ? joined.entries : active
            var anchor = pool[0]
            for candidate in pool.dropFirst() where outranks(candidate, anchor) { anchor = candidate }
            let sorted = joined.entries.sorted {
                let l = joined.sort[$0.key] ?? 0, r = joined.sort[$1.key] ?? 0
                return l != r ? l < r : $0.key.id < $1.key.id
            }
            let seriesId = String(groupKey.drop { $0 != ":" }.dropFirst())
            let row = SeriesListRow(id: .series(anchor.key.kind, seriesId), members: sorted, anchor: anchor.key,
                                    status: anchor.status, advanceTarget: isActive(anchor.status) ? anchor.key : nil)
            built.append((positionOf[anchor.key] ?? slot.position, row))
        }
        return built.sorted { $0.position < $1.position }.map(\.row)
    }

    /// Every entry of every row in row order (members in their row order), unchanged.
    public static func ungrouped(_ rows: [SeriesListRow]) -> [LibraryEntry] {
        rows.flatMap(\.members)
    }

    public static func sectionLabel(_ membership: SeriesMembership?, german: Bool) -> String? {
        guard let membership else { return nil }
        switch membership.sectionKind {
        case .season:
            guard let n = membership.ordinal else { return nil }
            return german ? "St. \(n)" : "S\(n)"
        case .film: return "Film"
        case .extra: return "Extra"
        case .edition: return nil
        }
    }

    public static func rowLabel(_ row: SeriesListRow, membership: [MediaKey: SeriesMembership],
                                progress: Int, total: Int?, german: Bool) -> String? {
        var parts: [String] = []
        if let section = sectionLabel(membership[row.displayMember], german: german) { parts.append(section) }
        if let total { parts.append("\(progress)/\(total)") } else if progress > 0 { parts.append("\(progress)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func counts(_ rows: [SeriesListRow]) -> [ListStatus: Int] {
        var out: [ListStatus: Int] = [:]
        for row in rows { out[row.status, default: 0] += 1 }
        return out
    }
}
