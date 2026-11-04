import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - The pages of one Discover journey list (See all, mood; spec 2026-11-04 §5.4, §5.5, §7)
// Reads pages through the data lane (`DiscoveryStore.seeAllPage` / `moodPage`) and appends each through
// `DiscoveryStore.accumulate` (hidden titles out, the owned rule, one title per franchise; a fallback
// page is not deduped by the server). A new query starts a new generation: a page of an older query is
// dropped. Hidden titles are filtered again when the rows are drawn (`DiscoverJourneyVisible`), so a
// hide leaves at once and its Undo brings the title back in its slot.

@MainActor
@Observable
final class DiscoverJourneyFeed {
    enum Phase: Equatable { case loading, ready, failed, offline }

    typealias Fetch = (DiscoverPageCursor?) async -> DiscoverPage?

    private(set) var accumulator: DiscoverPageAccumulator
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false
    /// A later page failed (the footer offers Try again).
    private(set) var pageFailed = false
    /// Pages read for the current query.
    private(set) var pages = 0

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fetch: Fetch?

    /// Pages read automatically after a page added fewer drawable rows than this (filters on the device).
    static let topUpRows = 12
    static let topUpPages = 4

    init(policy: DiscoverOwnedPolicy) {
        accumulator = DiscoverPageAccumulator(policy: policy)
    }

    /// Whether the list has ended (no further page).
    var isFinished: Bool { accumulator.isFinished }
    var hasMore: Bool { accumulator.next != nil }

    /// Reads the first page of a (new) query. `isOffline` decides between the offline and the failed
    /// state when the read fails; `visibleCount` is how many rows the page would draw now (top-up).
    func start(policy: DiscoverOwnedPolicy, fetch: @escaping Fetch, discovery: DiscoveryStore, taste: TasteStore,
               isOffline: () -> Bool, visibleCount: @escaping () -> Int) async {
        generation += 1
        let current = generation
        self.fetch = fetch
        phase = .loading
        pageFailed = false
        isLoadingMore = false
        guard let page = await fetch(nil) else {
            guard current == generation else { return }
            phase = isOffline() ? .offline : .failed
            return
        }
        guard current == generation, !Task.isCancelled else { return }
        await discovery.loadFranchiseIds(for: page.items.map(\.key))
        guard current == generation else { return }
        var fresh = DiscoverPageAccumulator(policy: policy)
        discovery.accumulate(page, into: &fresh, hidden: taste.discoverHiddenKeys)
        accumulator = fresh
        pages = 1
        phase = .ready
        await topUp(generation: current, discovery: discovery, taste: taste, visibleCount: visibleCount)
    }

    /// Reads the next page (the sentinel, Try again).
    func loadMore(discovery: DiscoveryStore, taste: TasteStore, visibleCount: @escaping () -> Int) async {
        let current = generation
        await readNext(generation: current, discovery: discovery, taste: taste)
        await topUp(generation: current, discovery: discovery, taste: taste, visibleCount: visibleCount)
    }

    private func topUp(generation current: Int, discovery: DiscoveryStore, taste: TasteStore,
                       visibleCount: () -> Int) async {
        var extra = 0
        while current == generation, hasMore, !pageFailed, visibleCount() < Self.topUpRows, extra < Self.topUpPages {
            extra += 1
            await readNext(generation: current, discovery: discovery, taste: taste)
        }
    }

    private func readNext(generation current: Int, discovery: DiscoveryStore, taste: TasteStore) async {
        guard current == generation, phase == .ready, let cursor = accumulator.next, !isLoadingMore,
              let fetch else { return }
        isLoadingMore = true
        pageFailed = false
        let page = await fetch(cursor)
        guard current == generation else { return }
        isLoadingMore = false
        guard let page else {
            pageFailed = true
            return
        }
        await discovery.loadFranchiseIds(for: page.items.map(\.key))
        guard current == generation else { return }
        discovery.accumulate(page, into: &accumulator, hidden: taste.discoverHiddenKeys)
        pages += 1
    }
}

/// The rows a journey draws right now (pure; DUpreviewTests).
enum DiscoverJourneyVisible {
    /// `items` without the hidden titles (R5, live), without titles of a franchise hidden as Not
    /// interested during this journey (D16; only while that answer stands), and without what the
    /// device-side rule leaves out (`include`).
    static func rows(_ items: [DiscoverPlacedItem<DiscoverPageItem>],
                     isHidden: (MediaKey) -> Bool,
                     hiddenFranchises: Set<DiscoverFranchiseKey>,
                     franchiseKeys: (DiscoverPageItem) -> Set<DiscoverFranchiseKey>,
                     include: (DiscoverPlacedItem<DiscoverPageItem>) -> Bool) -> [DiscoverPlacedItem<DiscoverPageItem>] {
        items.filter { placed in
            if isHidden(placed.item.key) { return false }
            if !hiddenFranchises.isEmpty, !franchiseKeys(placed.item).isDisjoint(with: hiddenFranchises) { return false }
            return include(placed)
        }
    }

    /// The franchises hidden as Not interested whose answer still stands (an Undo lifts its franchise).
    static func activeFranchises(_ hidden: [MediaKey: Set<DiscoverFranchiseKey>],
                                 isHidden: (MediaKey) -> Bool) -> Set<DiscoverFranchiseKey> {
        hidden.reduce(into: Set<DiscoverFranchiseKey>()) { result, entry in
            if isHidden(entry.key) { result.formUnion(entry.value) }
        }
    }
}

extension DiscoverCardValue {
    /// The Plan key's card for a journey row.
    var tasteCard: TasteCard {
        switch self {
        case .anime(let card): return TasteCard(anime: card)
        case .manga(let card): return TasteCard(manga: card)
        }
    }
}

/// The footer trigger: re-created whenever the list grows (its id), so it fires again while it stays on
/// screen (a short filtered list).
struct DiscoverPageTrigger: View {
    let itemCount: Int
    let action: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .id(itemCount)
            .onAppear(perform: action)
            .accessibilityHidden(true)
    }
}

/// The journey list's footer: Loading more (busy mark), the paging failure, or "That's all {n}."
struct DiscoverJourneyFooter: View {
    let isLoadingMore: Bool
    let pageFailed: Bool
    let finished: Bool
    let count: Int
    let retry: () -> Void

    var body: some View {
        let german = KuroLocale.isGerman
        Group {
            if isLoadingMore {
                HStack(spacing: 10) {
                    KuroBusyMark()
                    Text(DiscoverSeeAllCopy.loadingMore(german: german))
                        .font(.kuroCustom(11, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.kuroMuted)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            } else if pageFailed {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    retry()
                } label: {
                    Text(DiscoverSeeAllCopy.pageFailed(german: german))
                        .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
            } else if finished, count > 0 {
                Text(DiscoverSeeAllCopy.thatsAll(count, german: german))
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroMuted)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// The ink-rule text link ("Clear filters"): 12 pt medium ink over a 1 pt rule, a 44 pt target.
struct DiscoverInkRuleLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Text(title)
                .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 24))
                .foregroundStyle(Color.kuroInk)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.kuroInk).frame(height: 1).offset(y: 2)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
    }
}

/// Row skeletons under a journey heading while the first page loads (§7).
struct DiscoverJourneySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in KuroSkeleton(kind: .row) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroBrandedCopy.loadingLabel(german: KuroLocale.isGerman))
    }
}

/// The removal transition of a hidden row (§5.3.2): shrink to 0.9 and fade; a cross-fade under
/// Reduce Motion / Low Power.
extension AnyTransition {
    @MainActor
    static func discoverHide(reduceMotion: Bool) -> AnyTransition {
        KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
            ? .asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity))
            : .opacity
    }
}
