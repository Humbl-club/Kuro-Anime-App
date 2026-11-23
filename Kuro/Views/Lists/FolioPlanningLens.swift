import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Shop Your Plan-to-Watch (Anti-Graveyard Lens, Tier 2.1)
// Pure on-device lens over hydrated FolioItem rows in Collection's Planned view (0 extra RPS).

enum FolioPlanningFilter: Hashable, Identifiable, Sendable {
    case all
    case weekendFinish
    case bingeReady
    case acclaimed
    case genre(String)

    var id: String {
        switch self {
        case .all: return "all"
        case .weekendFinish: return "weekend"
        case .bingeReady: return "binge"
        case .acclaimed: return "acclaimed"
        case .genre(let name): return "genre:\(name)"
        }
    }

    func title(medium: MediaKind, german: Bool) -> String {
        switch self {
        case .all: return german ? "Alle" : "All"
        case .weekendFinish: return german ? "Für ein Wochenende" : "Weekend finish"
        case .bingeReady: return german ? "Komplett draußen" : "Binge-ready"
        case .acclaimed: return german ? "Top bewertet" : "Acclaimed"
        case .genre(let g): return BrowseView.genreTitle(g, german: german)
        }
    }

    func matches(_ item: FolioItem) -> Bool {
        let m = item.media
        switch self {
        case .all:
            return true
        case .weekendFinish:
            if m.kind == .anime {
                if m.formatRaw?.uppercased() == "MOVIE" { return true }
                if let eps = m.episodes, eps > 0 { return eps <= 13 }
                return false
            } else {
                if m.formatRaw?.uppercased() == "ONE_SHOT" { return true }
                if let ch = m.chapters, ch > 0 { return ch <= 30 }
                return false
            }
        case .bingeReady:
            return m.statusRaw?.uppercased() == "FINISHED"
        case .acclaimed:
            return (m.rating ?? 0) >= 8.2
        case .genre(let g):
            return m.genres?.contains(where: { $0.caseInsensitiveCompare(g) == .orderedSame }) ?? false
        }
    }
}

enum FolioTonightShortlist {
    static func dayOrdinal(for date: Date = Date()) -> Int {
        Int(floor(date.timeIntervalSince1970 / 86_400))
    }

    /// Top 4 genres represented inside the user's current Planned list, stable by frequency then name.
    static func topGenres(from items: [FolioItem], limit: Int = 4) -> [String] {
        var counts: [String: Int] = [:]
        for item in items {
            for genre in item.media.genres ?? [] where !genre.isEmpty && genre != "Hentai" {
                counts[genre, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map(\.key)
    }

    /// Deterministic daily shortlist of up to 3 Planned items blending quick finishes, finished binge picks, and acclaimed titles.
    static func picks(
        from items: [FolioItem],
        accountId: String?,
        dayOrdinal: Int = dayOrdinal(),
        reshuffleSeed: Int = 0,
        limit: Int = 3
    ) -> [FolioItem] {
        guard !items.isEmpty, limit > 0 else { return [] }
        let sorted = items.sorted { lhs, rhs in
            let lScore = lhs.media.rating ?? 0
            let rScore = rhs.media.rating ?? 0
            if abs(lScore - rScore) > 0.05 { return lScore > rScore }
            return lhs.key.id < rhs.key.id
        }

        let seedInput = "\(accountId?.lowercased() ?? "anon")-\(dayOrdinal)-\(reshuffleSeed)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seedInput.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let step = max(1, sorted.count)
        let offset = Int(hash % UInt64(step))

        var chosen: [FolioItem] = []
        var chosenIds: Set<String> = []
        func takeFirst(matching predicate: (FolioItem) -> Bool) {
            for idx in 0..<sorted.count where chosen.count < limit {
                let candidate = sorted[(idx + offset) % sorted.count]
                if !chosenIds.contains(candidate.id), predicate(candidate) {
                    chosen.append(candidate)
                    chosenIds.insert(candidate.id)
                    return
                }
            }
        }

        takeFirst { FolioPlanningFilter.weekendFinish.matches($0) }
        takeFirst { FolioPlanningFilter.bingeReady.matches($0) }
        takeFirst { FolioPlanningFilter.acclaimed.matches($0) }
        while chosen.count < min(limit, sorted.count) {
            let before = chosen.count
            takeFirst { _ in true }
            if chosen.count == before { break }
        }
        return chosen
    }
}

struct FolioPlanningTrayView: View {
    let allPlannedItems: [FolioItem]
    let medium: MediaKind
    let accountId: String?
    @Binding var activeFilter: FolioPlanningFilter
    @Binding var reshuffleSeed: Int
    let startingKeys: Set<MediaKey>
    let gutter: CGFloat
    let onOpen: (FolioItem) -> Void
    let onStart: (FolioItem) -> Void

    private var german: Bool { KuroLocale.isGerman }

    private var filterOptions: [FolioPlanningFilter] {
        var list: [FolioPlanningFilter] = [.all]
        if allPlannedItems.contains(where: { FolioPlanningFilter.weekendFinish.matches($0) }) {
            list.append(.weekendFinish)
        }
        if allPlannedItems.contains(where: { FolioPlanningFilter.bingeReady.matches($0) }) {
            list.append(.bingeReady)
        }
        if allPlannedItems.contains(where: { FolioPlanningFilter.acclaimed.matches($0) }) {
            list.append(.acclaimed)
        }
        for genre in FolioTonightShortlist.topGenres(from: allPlannedItems, limit: 3) {
            list.append(.genre(genre))
        }
        return list
    }

    private var shortlist: [FolioItem] {
        FolioTonightShortlist.picks(
            from: allPlannedItems,
            accountId: accountId,
            reshuffleSeed: reshuffleSeed,
            limit: 3
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            if filterOptions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterOptions) { option in
                            let selected = activeFilter == option
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
                                    activeFilter = option
                                }
                            } label: {
                                Text(option.title(medium: medium, german: german))
                                    .font(.kuroMeta(weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.kuroWhite : Color.kuroInk)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(Capsule(style: .continuous).fill(selected ? Color.kuroControlInk : Color.kuroControlFill))
                                    .overlay(Capsule(style: .continuous).strokeBorder(selected ? Color.kuroControlInk : Color.kuroHairline, lineWidth: 0.8))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(KuroPressStyle())
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, gutter)
                }
                .kuroSwipeExclusionZone()
            }

            if allPlannedItems.count >= 4, !shortlist.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(german ? "DREI FÜR HEUTE ABEND" : "THREE FOR TONIGHT")
                            .kuroKicker()
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
                                reshuffleSeed += 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.kuroCustom(10, weight: .medium, relativeTo: .caption2, maxSize: 16))
                                Text(german ? "Mischen" : "Shuffle")
                                    .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 20))
                            }
                            .foregroundStyle(Color.kuroInk)
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(KuroPressStyle())
                    }

                    HStack(alignment: .top, spacing: 10) {
                        ForEach(shortlist) { item in
                            tonightCard(item)
                        }
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.top, 4)
            }
        }
    }

    private func tonightCard(_ item: FolioItem) -> some View {
        let starting = startingKeys.contains(item.key)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button {
                    onOpen(item)
                } label: {
                    FolioArtwork(
                        url: item.media.imageURL,
                        width: 96,
                        height: 138,
                        cornerRadius: 7,
                        maxPixelSize: 320
                    )
                }
                .buttonStyle(HomeArtworkPressStyle())
                .accessibilityLabel(item.media.title)
                .accessibilityHint(KuroLocale.text("Opens details", "Öffnet Details"))

                KuroAdvanceKey(
                    style: medium == .manga ? .dark : .light,
                    phase: starting ? .pending : .advance,
                    accessibilityText: german
                        ? "\(item.media.title) jetzt starten"
                        : "Start \(item.media.title) now"
                ) {
                    onStart(item)
                }
                .scaleEffect(0.86)
                .padding(2)
            }

            Button {
                onOpen(item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.media.title)
                        .font(.kuroCustom(11.5, weight: .medium, relativeTo: .caption1, maxSize: 22))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let meta = tonightMeta(item) {
                        Text(meta)
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 18))
                            .foregroundStyle(Color.kuroMuted)
                            .lineLimit(1)
                    }
                }
                .frame(width: 96, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func tonightMeta(_ item: FolioItem) -> String? {
        if let total = item.total {
            return "\(total) \(medium == .manga ? (german ? "Kap." : "ch") : (german ? "Fol." : "ep"))"
        }
        return item.media.year.isEmpty ? nil : item.media.year
    }
}
