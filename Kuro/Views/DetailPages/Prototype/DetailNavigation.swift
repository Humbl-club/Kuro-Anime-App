import KuroCore
import SwiftUI

// MARK: - Detail pages inside a journey (navigation contract, docs/superpowers/specs/2026-11-02-navigation-contract-design.md)
// The anime and manga detail pages are journey pages:
// - Chrome (N1-N3, H1-H4): `.kuroJourneyChrome` draws Back (pushed pages only) and ✕ over the hero as
//   round material keys and, once the hero has scrolled under the 52 pt bar, as ink glyphs in the paper
//   compact bar with the title. The old pinned ✕ (`DetailCloseButton`) is gone from the pages.
// - Every tap inside the page pushes (N5 dedupe through the journey): season tiles, the original story /
//   "Seen the anime?" cards, the characters rail, the "Behind the frames/pages." rows (staff, studio,
//   author, and the ladder's "Original work" when it maps to a title), and the club rail cards (N9).
// - Tools (list settings, add to a club) come from the journey's tool slot over the page (N7); the
//   verdict and provider sheets stay page-local tool sheets with their own close.
// - Folding sections (F1-F3) keep their state in the session's `KuroFoldMemory` per title and section.
// The rules below are pure and unit-tested (KuroTests/NavdetailTests.swift).

enum DetailNavigation {
    /// A season tile (anime ladder chain): always another anime.
    static func seasonPage(id: Int) -> JourneyPage {
        .media(MediaRoute(kind: .anime, id: id))
    }

    /// The title a ladder item opens (the original story card, "Seen the anime?", a credit row), or nil
    /// when the ladder names no catalogue row.
    nonisolated static func ladderKey(_ item: MediaLadderItem) -> MediaKey? {
        guard item.mediaId > 0 else { return nil }
        return MediaKey(kind: item.mediaType.uppercased() == "MANGA" ? .manga : .anime, id: item.mediaId)
    }

    /// The page a ladder item opens.
    static func ladderPage(_ item: MediaLadderItem) -> JourneyPage? {
        ladderKey(item).map { .media(MediaRoute($0)) }
    }

    /// The page a "Behind the frames/pages." row opens (nil: plain text, no target).
    static func creditPage(_ target: DetailCreditRow.Target) -> JourneyPage? {
        switch target {
        case .staff(let staff): return .staff(staff)
        case .studio(let studio): return .studio(studio)
        case .author(let author): return .author(author)
        case .media(let key): return .media(MediaRoute(key))
        case .none: return nil
        }
    }

    /// A character card of "The characters.".
    static func characterPage(_ character: Character) -> JourneyPage {
        .character(character)
    }

    /// A "More like this." card (details-songs §6.8): another title, pushed in the journey.
    static func similarPage(_ key: MediaKey) -> JourneyPage {
        .media(MediaRoute(key))
    }

    /// A cast card's voice chip (details-songs §6.7): the voice actor's staff page.
    static func voicePage(_ staff: Staff) -> JourneyPage {
        .staff(staff)
    }

    /// A club card under "In your club rails" (N9: it opens the club).
    static func clubPage(_ activity: ClubMediaActivity) -> JourneyPage {
        .club(id: activity.club.id)
    }
}

// MARK: - Shrinking header (H1-H3)

enum DetailCollapse {
    /// The scroll distance over which the hero hands over to the compact bar: the hero's height less the
    /// bar it collapses into (at least 1 pt, so a hero that is not measured yet never divides by zero).
    static func distance(heroHeight: CGFloat, barHeight: CGFloat = KuroJourneyChrome.barHeight) -> CGFloat {
        max(1, heroHeight - barHeight)
    }
}

// MARK: - Folding sections (F1-F3)

enum DetailFold {
    /// The fold memory's page identity for a title (`anime:7`, `manga:7`).
    nonisolated static func page(_ key: MediaKey) -> String {
        KuroFold.page(kind: key.kind.rawValue, id: key.id)
    }

    /// Section ids inside a title's fold memory.
    static let story = "story"
    static let units = "units"
    static let songs = "songs"
    static let coverage = "coverage"
    static let adaptationGuide = "adaptationGuide"
    /// The timeline's watched run ("✓ Episodes 1–4 · watched", details-songs §6.4.1).
    static let watched = "watched"

    /// F2: after a collapse the page scrolls the section back into view only when its top has gone above
    /// the visible area (otherwise the user still sees the control and nothing moves).
    nonisolated static func scrollsBack(sectionMinY: CGFloat) -> Bool {
        sectionMinY < 0
    }

    /// An expanded "More episodes/chapters" list loads its full pages when it is open and nothing is
    /// loaded yet (also when the open state was restored from the session's memory, not tapped).
    nonisolated static func loadsAllUnits(expanded: Bool, loadedCount: Int, hasMore: Bool, loading: Bool) -> Bool {
        expanded && loadedCount == 0 && hasMore && !loading
    }
}

extension View {
    /// Reports whether this section's top has scrolled above the visible area (F2's scroll-back test).
    /// Fires only when the answer changes, so it costs nothing while scrolling inside the section.
    func detailFoldAnchor(_ section: DetailSection, above: Binding<Set<DetailSection>>) -> some View {
        onGeometryChange(for: Bool.self) { geometry in
            DetailFold.scrollsBack(sectionMinY: geometry.frame(in: .scrollView).minY)
        } action: { isAbove in
            if isAbove { above.wrappedValue.insert(section) } else { above.wrappedValue.remove(section) }
        }
    }
}

/// The page's collapse progress, kept outside the page's own state: the scroll offset updates it every
/// frame while the hero hands over, and only the chrome reads it (the heavy page body is not re-run).
@Observable
final class DetailCollapseState {
    var progress: CGFloat = 0
    /// The hero's measured height (the collapse distance follows it).
    var heroHeight: CGFloat = 0
}

extension View {
    /// The detail page's journey chrome over its scroll view: Back (pushed) and ✕ as round keys over
    /// the hero, then the compact bar with `title` once the hero has scrolled under it (H1-H3), and the
    /// sheet's grabber (N8). Apply `detailCollapseTracking` to the page's ScrollView with the same state.
    func detailJourneyChrome(title: String, material: ArtworkMaterial?, collapse: DetailCollapseState) -> some View {
        modifier(DetailJourneyChromeModifier(title: title, material: material, collapse: collapse))
    }

    /// Feeds the page's scroll offset into `collapse` (the foundation's `kuroCollapseTracking`).
    func detailCollapseTracking(_ collapse: DetailCollapseState) -> some View {
        modifier(DetailCollapseTrackingModifier(collapse: collapse))
    }

    /// Measures the hero for the collapse distance.
    func detailCollapseHero(_ collapse: DetailCollapseState) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if abs(collapse.heroHeight - height) > 0.5 { collapse.heroHeight = height }
        }
    }
}

private struct DetailJourneyChromeModifier: ViewModifier {
    let title: String
    let material: ArtworkMaterial?
    let collapse: DetailCollapseState

    func body(content: Content) -> some View {
        content
            .kuroJourneyChrome(title: title, collapseProgress: collapse.progress, material: material)
            #if os(iOS)
            .presentationDragIndicator(DetailLoaderChrome.dragIndicator)
            #endif
    }
}

private struct DetailCollapseTrackingModifier: ViewModifier {
    let collapse: DetailCollapseState

    func body(content: Content) -> some View {
        content.kuroCollapseTracking(Binding(get: { collapse.progress }, set: { collapse.progress = $0 }),
                                     distance: DetailCollapse.distance(heroHeight: collapse.heroHeight))
    }
}
