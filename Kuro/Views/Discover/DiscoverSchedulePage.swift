import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - 7-Day Release Schedule Journey Page (Build 30)
// Opened from Discover's "Airing & coming up." / "Chapters out & upcoming." rails or the header
// Schedule button (`routes.openPage(.seeAll(AnyJourneyPage(id: "discover:schedule", ...)))`).
// Follows navigation contract §1-§2: no own NavigationStack, no media .sheet (taps push via
// `routes.openMedia`), .kuroJourneyChrome with collapse tracking, and DiscoverPlanKey for quick adds.

struct DiscoverSchedulePage: View {
    enum Tab: Hashable {
        case day(Int) // 0 = today ... 6 = +6 days in KuroLocale.timeZone
        case manga
    }

    let initialTab: Tab
    let initialAnime: [AnimeCard]
    let initialAnimeSlots: [Int: DiscoverAiringSlot]
    let initialManga: [MangaCard]
    let initialMangaSlots: [Int: DiscoverMangaSlot]

    @Environment(DiscoveryStore.self) private var discovery
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: Tab
    @State private var animeItems: [AnimeCard]
    @State private var animeSlots: [Int: DiscoverAiringSlot]
    @State private var mangaItems: [MangaCard]
    @State private var mangaSlots: [Int: DiscoverMangaSlot]
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var collapse: CGFloat = 0
    @State private var feedback = DiscoverFeedbackController()
    @State private var plans = TastePlanController()
    @State private var didSelectInitialBestDay = false

    init(
        initialIsManga: Bool = false,
        initialAnime: [AnimeCard] = [],
        initialAnimeSlots: [Int: DiscoverAiringSlot] = [:],
        initialManga: [MangaCard] = [],
        initialMangaSlots: [Int: DiscoverMangaSlot] = [:]
    ) {
        self.initialTab = initialIsManga ? .manga : .day(0)
        self.initialAnime = initialAnime
        self.initialAnimeSlots = initialAnimeSlots
        self.initialManga = initialManga
        self.initialMangaSlots = initialMangaSlots
        _selectedTab = State(initialValue: initialIsManga ? .manga : .day(0))
        _animeItems = State(initialValue: initialAnime)
        _animeSlots = State(initialValue: initialAnimeSlots)
        _mangaItems = State(initialValue: initialManga)
        _mangaSlots = State(initialValue: initialMangaSlots)
    }

    private var german: Bool { KuroLocale.isGerman }

    private var pageTitle: String {
        german ? "Release-Kalender" : "Release schedule"
    }

    private var dayCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = KuroLocale.timeZone
        cal.locale = KuroLocale.locale
        return cal
    }

    private func dayDate(offset: Int, from now: Date) -> Date {
        let start = dayCalendar.startOfDay(for: now)
        return dayCalendar.date(byAdding: .day, value: offset, to: start) ?? start.addingTimeInterval(TimeInterval(offset * 86_400))
    }

    private func animeForDay(offset: Int, now: Date) -> [(card: AnimeCard, slot: DiscoverAiringSlot)] {
        let cal = dayCalendar
        let target = dayDate(offset: offset, from: now)
        return animeItems
            .compactMap { card -> (AnimeCard, DiscoverAiringSlot)? in
                guard let slot = animeSlots[card.id],
                      cal.isDate(slot.airingAt, inSameDayAs: target) else { return nil }
                return (card, slot)
            }
            .sorted { lhs, rhs in
                if lhs.1.airingAt != rhs.1.airingAt { return lhs.1.airingAt < rhs.1.airingAt }
                return lhs.0.id < rhs.0.id
            }
    }

    private func dayLabel(offset: Int, now: Date) -> String {
        if offset == 0 { return german ? "Heute" : "Today" }
        if offset == 1 { return german ? "Morgen" : "Tomorrow" }
        let date = dayDate(offset: offset, from: now)
        let formatter = DateFormatter()
        formatter.locale = KuroLocale.locale
        formatter.timeZone = KuroLocale.timeZone
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    var body: some View {
        let now = Date()
        GeometryReader { geo in
            let width = DiscoverLayout.contentWidth(
                container: geo.size.width,
                regularWidth: horizontalSizeClass == .regular
            )
            let gutter = DiscoverLayout.gutter(for: width)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header(now: now)
                    tabStrip(now: now, gutter: gutter)
                        .padding(.top, 14)

                    bodyContent(now: now, width: width, gutter: gutter)
                        .padding(.horizontal, gutter)
                        .padding(.top, 18)
                }
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroDesignSpacing.xl + 56)
                .frame(width: width, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .kuroCollapseTracking($collapse, start: 0, distance: KuroJourneyChrome.barHeight)
            .refreshable { await reload() }
            .background(Color.kuroCanvasHome)
            .environment(\.discoverMissingArt, HomeInk.posterFill)
        }
        .discoverFeedbackHost(feedback, plans: plans)
        .kuroJourneyChrome(title: pageTitle, collapseProgress: collapse)
        .task {
            if animeItems.isEmpty || mangaItems.isEmpty {
                await reload()
            } else {
                autoPickNonEmptyDayIfNeeded(now: Date())
            }
        }
    }

    private func header(now: Date) -> some View {
        let count: Int = {
            switch selectedTab {
            case .day(let offset): return animeForDay(offset: offset, now: now).count
            case .manga: return mangaItems.count
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text(pageTitle)
                .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.5)
                .foregroundStyle(Color.kuroInk)
                .accessibilityAddTraits(.isHeader)
            Text(selectedTab == .manga
                 ? (german ? "Aktuelle und angekündigte Manga-Kapitel." : "Latest released and upcoming manga chapters.")
                 : (german ? "Ausstrahlungstermine der nächsten 7 Tage." : "Confirmed episode broadcasts over the next 7 days."))
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                .foregroundStyle(Color.kuroMuted)
            if count > 0 {
                Text(german ? "\(count) Titel" : (count == 1 ? "1 title" : "\(count) titles"))
                    .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 20))
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroMuted)
            }
        }
        .padding(.horizontal, 20)
    }

    private func tabStrip(now: Date, gutter: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    let itemsCount = animeForDay(offset: offset, now: now).count
                    let title = itemsCount > 0
                        ? "\(dayLabel(offset: offset, now: now)) · \(itemsCount)"
                        : dayLabel(offset: offset, now: now)
                    pillButton(title: title, isSelected: selectedTab == .day(offset)) {
                        KuroAccessibility.selectionHaptic()
                        selectedTab = .day(offset)
                    }
                }
                let mangaLabel = mangaItems.isEmpty
                    ? "Manga"
                    : "Manga · \(mangaItems.count)"
                pillButton(title: mangaLabel, isSelected: selectedTab == .manga) {
                    KuroAccessibility.selectionHaptic()
                    selectedTab = .manga
                }
            }
            .padding(.horizontal, gutter)
        }
    }

    private func pillButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kuroCustom(11, weight: isSelected ? .semibold : .medium, relativeTo: .caption1, maxSize: 18))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.kuroCanvasHome : Color.kuroInk)
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.kuroInk : Color.kuroPaper)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Color.kuroInk : Color.kuroLine, lineWidth: 1)
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func bodyContent(now: Date, width: CGFloat, gutter: CGFloat) -> some View {
        if isLoading && animeItems.isEmpty && mangaItems.isEmpty {
            VStack(spacing: 16) {
                KuroLoadingView(scope: .inline)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if loadFailed && animeItems.isEmpty && mangaItems.isEmpty {
            if network?.isConnected == false {
                KuroOfflineView(hasContent: false) { Task { await reload() } }
            } else {
                KuroErrorView(headline: german ? "Kalender nicht erreichbar." : "Couldn't load schedule.") {
                    Task { await reload() }
                }
            }
        } else {
            switch selectedTab {
            case .day(let offset):
                let dayEntries = animeForDay(offset: offset, now: now)
                if dayEntries.isEmpty {
                    KuroEmptyView(
                        headline: german ? "Keine Folgen für diesen Tag." : "No episodes scheduled for this day.",
                        message: german ? "Wähle einen anderen Tag in der Woche oder prüfe Manga-Kapitel."
                                        : "Pick another day above or switch to the Manga tab."
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(dayEntries, id: \.card.id) { entry in
                            animeRow(entry.card, slot: entry.slot, now: now)
                        }
                    }
                }
            case .manga:
                if mangaItems.isEmpty {
                    KuroEmptyView(
                        headline: german ? "Keine aktuellen Kapiteldaten." : "No manga chapter updates yet.",
                        message: german ? "Ziehe nach unten zum Aktualisieren." : "Pull down to refresh."
                    )
                } else {
                    let upcoming = mangaItems.filter {
                        if let nextAt = mangaSlots[$0.id]?.nextChapterAt { return nextAt >= now }
                        return false
                    }
                    let freshOut = mangaItems.filter {
                        if let nextAt = mangaSlots[$0.id]?.nextChapterAt { return nextAt < now }
                        return true
                    }
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !upcoming.isEmpty {
                            mangaSection(
                                title: german ? "Demnächst erwartet" : "Expected soon",
                                cards: upcoming,
                                now: now
                            )
                        }
                        if !freshOut.isEmpty {
                            mangaSection(
                                title: german ? "Aktuelle Kapitel laufender Reihen" : "Latest ongoing chapters",
                                cards: freshOut,
                                now: now
                            )
                        }
                    }
                }
            }
        }
    }

    private func mangaSection(title: String, cards: [MangaCard], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.kuroCustom(9, weight: .semibold, relativeTo: .caption2, maxSize: 16))
                .tracking(1.1)
                .foregroundStyle(Color.kuroMuted)
                .accessibilityAddTraits(.isHeader)
            ForEach(cards) { card in
                mangaRow(card, slot: mangaSlots[card.id], now: now)
            }
        }
    }

    private func animeRow(_ card: AnimeCard, slot: DiscoverAiringSlot, now: Date) -> some View {
        let tasteCard = TasteCard(anime: card)
        let timeStr = DiscoverIssueCopy.clock(slot.airingAt, timeZone: KuroLocale.timeZone)
        let item = ReleaseScheduleItem(
            medium: .anime,
            mediaId: card.id,
            title: card.title,
            coverImage: card.imageURL,
            unitKind: .episode,
            unitNumber: slot.episode.map(Double.init),
            unitLabel: slot.episode.map { "Ep. \($0)" },
            releaseAt: slot.airingAt,
            basis: .confirmed,
            confidence: nil,
            source: "anilist",
            sourceURL: nil,
            isPast: slot.airingAt <= now,
            precision: .instant
        )
        let countdown = ReleaseCopy(now: now, german: german, locale: KuroLocale.locale, timeZone: KuroLocale.timeZone)
            .countdownPhrase(item)
        let subtitleParts = [
            slot.episode.map { german ? "Folge \($0)" : "Ep. \($0)" },
            timeStr,
            countdown
        ].compactMap { $0 }

        return HStack(spacing: 12) {
            Button {
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(kind: .anime, id: card.id))
            } label: {
                HStack(spacing: 12) {
                    HomeArtwork(
                        url: card.imageURL.flatMap(URL.init(string:)),
                        maxPixelSize: 180,
                        placeholder: HomeInk.posterFill,
                        seedHex: card.coverImageColor,
                        usesMaterialWash: true
                    )
                    .frame(width: 48, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(KuroCardText.sanitizeTitleForCard(card.title))
                            .font(.kuroCustom(14, weight: .semibold, relativeTo: .subheadline, maxSize: 26))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if !subtitleParts.isEmpty {
                            Text(subtitleParts.joined(separator: " · "))
                                .font(.kuroMeta())
                                .monospacedDigit()
                                .foregroundStyle(Color.kuroInkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())

            DiscoverPlanKey(card: tasteCard, variant: .leaf, compact: true, badge: true)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
        }
    }

    private func mangaRow(_ card: MangaCard, slot: DiscoverMangaSlot?, now: Date) -> some View {
        let tasteCard = TasteCard(manga: card)
        let chapterDisplay = DiscoverIssueCopy.mangaChapterPresentation(
            slot: slot,
            now: now,
            german: german,
            locale: KuroLocale.locale,
            timeZone: KuroLocale.timeZone
        )
        let line = chapterDisplay?.line
            ?? DiscoverIssueCopy.facts(kind: .manga, year: card.year, formatRaw: card.format, episodes: nil, chapters: card.chapters, length: true, german: german)

        return HStack(spacing: 12) {
            Button {
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(kind: .manga, id: card.id))
            } label: {
                HStack(spacing: 12) {
                    HomeArtwork(
                        url: card.imageURL.flatMap(URL.init(string:)),
                        maxPixelSize: 180,
                        placeholder: HomeInk.posterFill,
                        seedHex: card.coverImageColor,
                        usesMaterialWash: true
                    )
                    .frame(width: 48, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(KuroCardText.sanitizeTitleForCard(card.title))
                            .font(.kuroCustom(14, weight: .semibold, relativeTo: .subheadline, maxSize: 26))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let line {
                            Text(line)
                                .font(.kuroMeta())
                                .monospacedDigit()
                                .foregroundStyle(Color.kuroInkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())

            DiscoverPlanKey(card: tasteCard, variant: .leaf, compact: true, badge: true)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
        }
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        async let animeRead = discovery.fetchUpcomingAnimeSchedule(days: 7, limit: 80)
        async let mangaRead = discovery.fetchUpcomingAndFreshManga(limit: 50)
        let (aCards, aSlots) = await animeRead
        let (mCards, mSlots) = await mangaRead
        if aCards.isEmpty && mCards.isEmpty && animeItems.isEmpty && mangaItems.isEmpty {
            loadFailed = true
        } else {
            animeItems = aCards
            animeSlots.merge(aSlots) { _, new in new }
            mangaItems = mCards
            mangaSlots = mSlots
            autoPickNonEmptyDayIfNeeded(now: Date())
        }
    }

    private func autoPickNonEmptyDayIfNeeded(now: Date) {
        guard !didSelectInitialBestDay else { return }
        didSelectInitialBestDay = true
        guard case .day(0) = selectedTab else { return }
        if animeForDay(offset: 0, now: now).isEmpty {
            if let first = (1..<7).first(where: { !animeForDay(offset: $0, now: now).isEmpty }) {
                selectedTab = .day(first)
            }
        }
    }
}
