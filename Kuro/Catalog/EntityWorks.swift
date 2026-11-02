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
}
