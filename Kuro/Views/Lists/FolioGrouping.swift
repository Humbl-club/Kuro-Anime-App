import Foundation
import KuroCore
import KuroLibrary

// MARK: - Folio grouping (W6): one row per reviewed series
// Pure mapping from the loaded feed items and the reviewed rows (`SeriesListGrouping`) to list items.
// Display only: a group item wears its display member (the anchor: the season that decides the status),
// so title, cover, sorts, the open tap, the context menu and +1 all act on that ONE season. Nothing here
// reads a network or writes tracking.

/// One season of a group, with the label of its reviewed section ("S2", "Film", nil without a reviewed ordinal).
struct FolioMember: Identifiable {
    let item: FolioItem
    let sectionLabel: String?
    var id: String { item.id }
    /// Its catalogue card has not loaded yet (the title is empty): the row shows a busy mark.
    var isLoading: Bool { item.media.title.isEmpty }
}

/// A reviewed series row: the rule's row, every tracked season, and the row label ("S2 · 5/12").
struct FolioGroup {
    let row: SeriesListRow
    let members: [FolioMember]
    let label: String?
    /// "series:<kind>:<seriesId>".
    var id: String {
        if case .series(let kind, let seriesId) = row.id { return "series:\(kind.rawValue):\(seriesId)" }
        return "entry:\(row.anchor.kind.rawValue)-\(row.anchor.id)"
    }
}

enum FolioGrouping {
    /// The feed's items with each reviewed group collapsed into its anchor's item (the anchor decides the
    /// strip, so it is on the status-filtered feed). A non-anchor member is not an item of its own while
    /// grouping is on. `member` resolves any member key to an item (feed first, then the member cards).
    static func items(
        feed: [FolioItem], index: SeriesListIndex, member: (MediaKey) -> FolioItem?,
        membership: [MediaKey: SeriesMembership], german: Bool
    ) -> [FolioItem] {
        var out: [FolioItem] = []
        out.reserveCapacity(feed.count)
        for item in feed {
            switch index.role(of: item.key) {
            case .single:
                out.append(item)
            case .member:
                continue
            case .anchor(let row):
                let members: [FolioMember] = row.members.compactMap { entry in
                    let resolved = entry.key == item.key ? item : member(entry.key)
                    return resolved.map {
                        FolioMember(item: $0, sectionLabel: SeriesListGrouping.sectionLabel(membership[entry.key], german: german))
                    }
                }
                let label = SeriesListGrouping.rowLabel(row, membership: membership, progress: item.progress,
                                                        total: item.total, german: german)
                var grouped = item
                grouped.group = FolioGroup(row: row, members: members, label: label)
                out.append(grouped)
            }
        }
        return out
    }

    /// Strip counts: rows (groups + singles), so a count never disagrees with what the strip shows.
    static func rowCounts(_ rows: [SeriesListRow]) -> [FolioStatus: Int] {
        var counts: [FolioStatus: Int] = [:]
        for row in rows { counts[FolioStatus(listStatus: row.status), default: 0] += 1 }
        return counts
    }

    /// +1 of a group row: the anchor with its OWN catalogue total (never another season's). Nil when no
    /// season is active (the row has no +1) or the anchor's total is unknown (the key stays hidden).
    static func advanceRequest(group: FolioGroup) -> (key: MediaKey, cap: Int)? {
        guard let target = group.row.advanceTarget,
              let member = group.members.first(where: { $0.item.key == target }),
              let total = member.item.total else { return nil }
        return (target, total)
    }

    /// Selection ids of an item: a group offers its seasons only, never the group (a group row has no
    /// selection id, so a batch never acts on a whole series silently).
    static func selectableIds(for item: FolioItem) -> [String] {
        if let group = item.group { return group.members.map(\.id) }
        return [item.id]
    }

    /// The keys of the selected ids, looking inside groups.
    static func selectedKeys(items: [FolioItem], selected: Set<String>) -> [MediaKey] {
        var keys: [MediaKey] = []
        for item in items {
            if let group = item.group {
                keys += group.members.filter { selected.contains($0.id) }.map(\.item.key)
            } else if selected.contains(item.id) {
                keys.append(item.key)
            }
        }
        return keys
    }

    /// A search matches a group when any season's loaded title matches.
    static func matches(_ item: FolioItem, query: String) -> Bool {
        if let group = item.group {
            return group.members.contains { FolioPolicy.matches($0.item, query: query) }
        }
        return FolioPolicy.matches(item, query: query)
    }

    /// The fold-memory section of a group (page "collection").
    static func foldSection(_ group: FolioGroup) -> String { group.id }
    static let foldPage = "collection"
}

/// Manga shelf: the expanded group's seasons render as a full-width band after its grid row.
enum FolioShelfChunks {
    enum Chunk: Equatable {
        case grid([String])
        case band(String)
    }

    static func split(ids: [String], columns: Int, expanded: Set<String>) -> [Chunk] {
        let width = max(1, columns)
        var chunks: [Chunk] = []
        var pending: [String] = []
        var rowIds: [String] = []
        for (position, id) in ids.enumerated() {
            pending.append(id)
            rowIds.append(id)
            guard rowIds.count == width || position == ids.count - 1 else { continue }
            let open = rowIds.filter { expanded.contains($0) }
            if !open.isEmpty {
                chunks.append(.grid(pending))
                pending = []
                chunks += open.map { .band($0) }
            }
            rowIds = []
        }
        if !pending.isEmpty { chunks.append(.grid(pending)) }
        return chunks
    }
}

/// EN/DE copy of the grouped row.
enum FolioGroupCopy {
    static func switchTitle(german: Bool) -> String { german ? "Staffeln bündeln" : "Group seasons" }

    static func showSeasons(_ count: Int, german: Bool) -> String {
        german ? "\(count) Staffeln zeigen" : "Show \(count) seasons"
    }

    static func hideSeasons(german: Bool) -> String { german ? "Staffeln ausblenden" : "Hide seasons" }

    static func menuEdit(section: String, german: Bool) -> String {
        german ? "\(section) bearbeiten" : "Edit \(section)"
    }

    static func menuClassify(section: String, german: Bool) -> String {
        german ? "\(section) einordnen" : "Classify \(section)"
    }

    static func menuRemove(section: String, german: Bool) -> String {
        german ? "\(section) aus der Liste entfernen" : "Remove \(section) from list"
    }

    static func memberAccessibility(_ member: FolioMember, german: Bool) -> String {
        var parts: [String] = []
        if let label = member.sectionLabel { parts.append(label) }
        parts.append(member.item.media.title)
        parts.append(member.item.status.title(medium: member.item.media.kind, german: german))
        if let position = FolioPolicy.positionLine(medium: member.item.media.kind, progress: member.item.progress,
                                                   total: member.item.total, german: german) {
            parts.append(position)
        }
        return parts.joined(separator: ", ")
    }

    static func switchValue(on: Bool, german: Bool) -> String {
        german ? (on ? "Ein" : "Aus") : (on ? "On" : "Off")
    }
}
