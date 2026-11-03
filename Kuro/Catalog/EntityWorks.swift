import Foundation
import KuroCore

// MARK: - Entity works rules (pure)
//
// The person / studio journey pages (Kuro/Views/DetailPages/EntityDetailSheets.swift) list works read by
// `CatalogStore`. These rules shape what the readers return into what a page shows; they are pure and
// unit-tested (KuroTests/NaventityTests.swift).

enum EntityWorks {
    /// A staff member's filmography: anime credits first, then manga credits (navigation contract §6:
    /// a staff page lists their anime AND manga). The same title credited twice with the same role
    /// (a duplicate join row) is listed once; different roles on one title stay separate rows.
    static func staffWorks(
        anime: [(media: Media, role: String)],
        manga: [(media: Media, role: String)]
    ) -> [(media: Media, role: String)] {
        var seen = Set<String>()
        var result: [(media: Media, role: String)] = []
        for work in anime + manga {
            let key = "\(work.media.stableKey)|\(work.role.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(work)
        }
        return result
    }

    /// The medium filters a page offers: none unless the works span both anime and manga (a bar with a
    /// single medium filters nothing); otherwise All, Anime, Manga.
    static func mediumFilters(for kinds: [MediaKind]) -> [CharacterMediaFilter] {
        let present = Set(kinds)
        guard present.contains(.anime), present.contains(.manga) else { return [] }
        return [.all, .anime, .manga]
    }

    /// Whether a work passes a medium filter.
    static func matches(_ kind: MediaKind, filter: CharacterMediaFilter) -> Bool {
        switch filter {
        case .all: return true
        case .anime: return kind == .anime
        case .manga: return kind == .manga
        }
    }

    // MARK: Sorting and grouping (details-songs spec §9)

    /// The pages' shipped sorts: rating (highest first), year (newest first), era (newest era first, then
    /// year). Ties keep the reader's order (the server's score order).
    static func sorted<Item>(_ items: [Item], mode: EntitySortMode, media: (Item) -> Media) -> [Item] {
        func year(_ item: Item) -> Int { Int(media(item).year) ?? 0 }
        let indexed = Array(items.enumerated())
        let ordered: [(offset: Int, element: Item)]
        switch mode {
        case .rating:
            ordered = indexed.sorted {
                let l = media($0.element).rating ?? 0, r = media($1.element).rating ?? 0
                return l != r ? l > r : $0.offset < $1.offset
            }
        case .year:
            ordered = indexed.sorted {
                let l = year($0.element), r = year($1.element)
                return l != r ? l > r : $0.offset < $1.offset
            }
        case .era:
            ordered = indexed.sorted {
                let le = EntityEraBucket.from(yearString: media($0.element).year).rawValue
                let re = EntityEraBucket.from(yearString: media($1.element).year).rawValue
                if le != re { return le > re }
                let l = year($0.element), r = year($1.element)
                return l != r ? l > r : $0.offset < $1.offset
            }
        }
        return ordered.map(\.element)
    }

    /// A studio's works by year, newest year first; works keep their order inside a year. Works without a
    /// known year are left out (no "unknown" row is invented).
    static func byYear(_ works: [Media]) -> [EntityYearGroup] {
        var order: [Int] = []
        var groups: [Int: [Media]] = [:]
        for work in works {
            guard let year = Int(work.year.trimmingCharacters(in: .whitespaces)), year > 1900 else { continue }
            if groups[year] == nil { order.append(year) }
            groups[year, default: []].append(work)
        }
        return order.sorted(by: >).map { EntityYearGroup(year: $0, works: groups[$0] ?? []) }
    }
}

/// One "By year." row of a studio page.
struct EntityYearGroup: Identifiable {
    let year: Int
    let works: [Media]

    var id: Int { year }

    /// At most this many titles are separate buttons on the row; more push the year's works page.
    static let inlineTitles = 3
    var isInline: Bool { works.count <= Self.inlineTitles }
}
