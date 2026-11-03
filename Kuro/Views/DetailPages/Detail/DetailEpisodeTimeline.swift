import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - D6 Episodes as a timeline (details-songs spec §6.4, D6, D20)
// The units block of the anime page: a 1 pt spine with one node per episode (watched ✓, Up next in the
// artwork's colour, later, estimate dashed), the guarded still, the episode's own title (generic
// "Episode 7" titles are left out) and its air day. The progress card and the Up next card with its
// material +1 key keep their path (`DetailAdvance` through `LibraryActions.apply`); watched runs of three
// or more fold into one line (`KuroFold`, `DetailFold.watched`); future rows come from the release
// schedule with `ReleaseCopy` words and their certainty mark, never an invented title, never a bell.
// Stills, titles and dates pass `EpisodeStillPolicy` first: a list that belongs to another season
// draws every row by number with branded tiles.

struct AnimeUnitsSection: View {
    let anime: Anime
    let episodes: [Episode]
    let progress: Int
    let total: Int?
    let isTracked: Bool
    let nextUnit: Int?
    let seasonNumber: Int?
    /// The schedule's rows still ahead (at most three are drawn after Up next).
    var upcoming: [ReleaseScheduleItem] = []
    let material: ArtworkMaterial
    let coverURL: URL?
    let savingNext: Bool
    let confirmTrigger: Int
    /// "More episodes" open or closed, kept for the session per title (F3, `DetailFold.units`).
    @Binding var showsAll: Bool
    /// The watched run open or closed (F3, `DetailFold.watched`).
    @Binding var showsWatched: Bool
    /// F2: the page scrolls the episodes back into view after they fold, when needed.
    var onCollapse: () -> Void = {}
    let onAdvance: (Int) -> Void

    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var allEpisodes: [Episode] = []
    @State private var hasMore = true
    @State private var loadingMore = false
    @State private var runEpisodes: [Episode] = []
    @State private var loadingRun = false
    @State private var openEpisode: Int?
    @State private var columnWidth: CGFloat = 0

    private var upNext: Int? { isTracked ? nextUnit : nil }
    private var german: Bool { KuroLocale.isGerman }
    /// Column ≤ 328 pt (a 320 pt phone): 72 × 40 stills.
    private var compact: Bool { columnWidth > 0 && columnWidth <= 328 }

    /// Every loaded source row (the first page, the paged list, the watched run's page).
    private var sourceRows: [Episode] {
        var seen = Set<Int>()
        return (episodes + allEpisodes + runEpisodes).filter { seen.insert($0.id).inserted }
    }

    private var verdict: EpisodeStillPolicy.Verdict {
        // The ladder carries no episode counts, so the earlier seasons' total is unknown here (open).
        EpisodeStillPolicy.verdict(numbers: sourceRows.map(\.number), total: total, priorEpisodes: nil)
    }

    /// Trusted source rows by this season's number; empty when the guard rejects the list.
    private var byNumber: [Int: Episode] {
        let verdict = verdict
        guard verdict.showsSourceRows else { return [:] }
        var map: [Int: Episode] = [:]
        for row in sourceRows { map[row.number - verdict.offset] = row }
        return map
    }

    /// Loaded numbers in this season's numbering (rows beyond a known total are never drawn).
    private var loadedNumbers: [Int] {
        let offset = verdict.offset
        let numbers = (showsAll && !allEpisodes.isEmpty ? allEpisodes : episodes).map { $0.number - offset }
        return numbers.filter { number in number >= 1 && (total.map { number <= $0 } ?? true) }
    }

    private var run: ClosedRange<Int>? {
        showsAll ? nil : DetailTimeline.watchedRun(progress: progress, isTracked: isTracked)
    }

    private var plainRows: [Int] {
        showsAll ? DetailTimeline.expandedRows(loaded: loadedNumbers, upNext: upNext)
                 : DetailTimeline.collapsedRows(progress: progress, isTracked: isTracked, upNext: upNext, loaded: loadedNumbers)
    }

    private var futureRows: [ReleaseScheduleItem] {
        var drawn = Set(plainRows)
        if let upNext { drawn.insert(upNext) }
        if let run { drawn.formUnion(run) }
        return DetailTimeline.futureRows(upcoming.filter { $0.unitKind == .episode }, drawn: drawn)
    }

    private var hasMoreToShow: Bool {
        if showsAll { return false }
        let shown = plainRows.count + (upNext == nil ? 0 : 1) + (run?.count ?? 0)
        if let total { return total > shown }
        return episodes.count > plainRows.count
    }

    var body: some View {
        let rows = plainRows
        let before = rows.filter { upNext == nil || $0 < (upNext ?? 0) }
        let after = rows.filter { upNext != nil && $0 > (upNext ?? 0) }
        VStack(alignment: .leading, spacing: 0) {
            if let seasonNumber {
                DetailEyebrow(text: DetailPageCopy.seasonEyebrow(seasonNumber, german: german), tracking: 1.2)
                    .padding(.bottom, 14)
            }
            DetailSectionHeading(title: KuroLocale.text("Episodes", "Folgen"),
                                 note: DetailTimeline.note(progress: progress, total: total, isTracked: isTracked, german: german))
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 0) {
                if let run {
                    runLine(run)
                    if showsWatched {
                        ForEach(Array(run), id: \.self) { number in row(number) }
                    }
                }
                ForEach(before, id: \.self) { number in row(number) }
                if let upNext { upNextRow(upNext) }
                ForEach(after, id: \.self) { number in row(number) }
                ForEach(futureRows) { item in futureRow(item) }
            }
            .background(alignment: .leading) {
                Rectangle().fill(Color(hex: "CFD6CF")).frame(width: 1).padding(.leading, 7)
                    .padding(.vertical, 18)
                    .accessibilityHidden(true)
            }
            if loadingMore || loadingRun {
                KuroSkeleton(kind: .row).padding(.vertical, 8)
            }
            if hasMoreToShow || showsAll {
                KuroFoldButton(isExpanded: $showsAll,
                               expandLabel: KuroLocale.text("More episodes", "Mehr Folgen"),
                               collapseLabel: KuroLocale.text("Fewer episodes", "Weniger Folgen"),
                               onCollapse: onCollapse) { title, open in
                    HStack {
                        Text(title)
                            .font(.detailSF(11, relativeTo: .footnote))
                        Spacer()
                        Image(systemName: open ? "arrow.up" : "arrow.down")
                            .font(.detailSF(14, .light, relativeTo: .body))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(DetailInk.moreLink)
                    .frame(minHeight: 44)
                }
                .padding(.top, 4)
            }
            if showsAll, hasMore, !allEpisodes.isEmpty, !loadingMore {
                Color.clear.frame(height: 1).onAppear { Task { await loadAll() } }
            }
        }
        .padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if abs(columnWidth - width) > 0.5 { columnWidth = width }
        }
        // Opened by the fold, or restored open from the session's memory (F3): load the full list.
        .task(id: showsAll) {
            guard DetailFold.loadsAllUnits(expanded: showsAll, loadedCount: allEpisodes.count,
                                           hasMore: hasMore, loading: loadingMore) else { return }
            await loadAll()
        }
        .task(id: showsWatched) {
            guard showsWatched, runEpisodes.isEmpty, let run else { return }
            await loadRun(through: run.upperBound)
        }
    }

    // MARK: Rows

    private enum Node { case watched, upNext, later, estimate }

    private func node(_ state: Node) -> some View {
        ZStack {
            switch state {
            case .watched:
                Circle().fill(Color(hex: "3B443D"))
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white)
            case .upNext:
                Circle().fill(Color.white)
                Circle().strokeBorder(material.base.color, lineWidth: 2)
            case .later:
                Circle().fill(Color.kuroPaper)
                Circle().strokeBorder(Color(hex: "AEB7AF"), lineWidth: 1)
            case .estimate:
                Circle().fill(Color.kuroPaper)
                Circle().strokeBorder(Color(hex: "AEB7AF"), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }

    private var stillSize: CGSize { compact ? CGSize(width: 72, height: 40) : CGSize(width: 84, height: 47) }

    @ViewBuilder
    private func still(_ number: Int, episode: Episode?) -> some View {
        if !dynamicTypeSize.isAccessibilitySize {
            let tile = DetailBrandedTile(kind: DetailTimeline.smallLine(number, watched: false, german: german), cornerRadius: 3)
            Color.clear
                .frame(width: stillSize.width, height: stillSize.height)
                .overlay {
                    if let url = episode?.thumbnail.flatMap(AnimeDetailPage.webURL) {
                        KuroCachedAsyncImage(url: url, maxPixelSize: 260) { phase in
                            if case .success(let image) = phase { image.resizable().scaledToFill() } else { tile }
                        }
                    } else {
                        tile
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private func dayText(_ episode: Episode?, long: Bool) -> String? {
        guard let episode else { return nil }
        return DetailTimeline.dayText(airAt: episode.airAt, airDate: episode.airDate, long: long,
                                      locale: KuroLocale.locale, timeZone: KuroLocale.timeZone)
    }

    private func row(_ number: Int) -> some View {
        let episode = byNumber[number]
        let watched = DetailTimeline.isWatched(number, progress: progress, isTracked: isTracked)
        let title = DetailTimeline.shownTitle(episode?.title ?? episode?.titleRomaji)
        let description = episode?.description?.trimmingCharacters(in: .whitespacesAndNewlines).detailNonEmpty
        let streamURL = ProviderAvailabilityStore.validatedOutboundURL(episode?.streamUrl)
        let expandable = Self.isExpandable(description: description, streamURL: streamURL)
        let isOpen = openEpisode == number
        let offset = verdict.offset
        let dateLine = [dayText(episode, long: false),
                        offset > 0 ? DetailTimeline.absoluteNumber(number + offset, german: german) : nil]
            .compactMap { $0 }.joined(separator: " · ")
        let spoken = DetailTimeline.spokenRow(number: number, title: title, date: dayText(episode, long: true),
                                              watched: watched, german: german)
        let line = HStack(alignment: .center, spacing: 12) {
            node(watched ? .watched : .later)
            still(number, episode: episode)
            VStack(alignment: .leading, spacing: 2) {
                Text(DetailTimeline.smallLine(number, watched: watched, german: german))
                    .font(.detailSF(9, relativeTo: .caption2))
                    .foregroundStyle(Color(hex: "6B776D"))
                if let title {
                    Text(title)
                        .font(.detailSF(12, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(watched ? DetailInk.finished : Color.kuroInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dateLine.isEmpty {
                    Text(dateLine)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(Color.kuroMuted)
                }
            }
            Spacer(minLength: 8)
            if expandable {
                Image(systemName: "chevron.down")
                    .font(.detailSF(9, relativeTo: .caption2))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .foregroundStyle(DetailInk.finished)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 9)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        return VStack(alignment: .leading, spacing: 0) {
            // Only a row with details to show is a button (no dead press feedback, no button trait).
            if expandable {
                Button {
                    withAnimation(KuroMotion.detail(KuroMotion.settle, reduceMotion: reduceMotion)) { openEpisode = isOpen ? nil : number }
                } label: { line }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(KuroLocale.text("Shows the episode's details", "Zeigt Details zur Folge"))
            } else {
                line.accessibilityElement(children: .ignore).accessibilityLabel(spoken)
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    if let description {
                        Text(description)
                            .font(.detailSF(12, relativeTo: .footnote))
                            .foregroundStyle(DetailInk.synopsis)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let streamURL {
                        Button {
                            openURL(streamURL)
                        } label: {
                            Text(KuroLocale.text("Watch ↗", "Ansehen ↗"))
                                .font(.detailSF(11, .medium, relativeTo: .footnote))
                                .foregroundStyle(Color.kuroInk)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 27)
                .padding(.bottom, 10)
            }
        }
    }

    private func runLine(_ run: ClosedRange<Int>) -> some View {
        let words = DetailTimeline.runLine(run, german: german)
        return KuroFoldButton(isExpanded: $showsWatched, expandLabel: words, collapseLabel: words) { _, open in
            HStack(spacing: 12) {
                node(.watched)
                Text(words)
                    .font(.detailSF(11, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.finished)
                Spacer(minLength: 8)
                Text(open ? DetailTimeline.hide(german: german) : DetailTimeline.show(german: german))
                    .font(.detailSF(11, .medium, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.moreLink)
            }
            .frame(minHeight: 44)
        }
    }

    private func futureRow(_ item: ReleaseScheduleItem) -> some View {
        let copy = ReleaseCopy.current()
        let number = item.wholeUnitNumber
        return HStack(alignment: .center, spacing: 12) {
            node(item.basis == .estimated ? .estimate : .later)
            if let number { still(number, episode: nil) }
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.line(item, undatedFallback: true))
                    .font(.detailSF(12, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                if DetailNextRelease.showsMark(item) {
                    DetailCertaintyMark(basis: item.basis, tone: .paper)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 9)
        .frame(minHeight: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.accessibilityLine(item))
        .accessibilityValue(DetailNextRelease.spokenValue(item, copy: copy))
    }

    /// The Up next card (the wash card and its material +1 key, unchanged), on the spine with its node
    /// and the guarded still.
    private func upNextRow(_ number: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let episode = byNumber[number]
        let title = DetailTimeline.shownTitle(episode?.title ?? episode?.titleRomaji)
        return HStack(alignment: .center, spacing: 12) {
            node(.upNext)
            HStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    EmptyView()
                } else if episode?.thumbnail.flatMap(AnimeDetailPage.webURL) != nil {
                    still(number, episode: episode)
                } else {
                    // No trusted still: the title's cover, as the card always showed.
                    Color.clear
                        .frame(width: 32, height: 44)
                        .overlay {
                            if let coverURL {
                                KuroCachedAsyncImage(url: coverURL, maxPixelSize: 160) { phase in
                                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color.clear }
                                }
                            }
                        }
                        .background(material.edge.color)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(KuroLocale.text("UP NEXT", "ALS NÄCHSTES"))
                        .font(.detailSF(7, .semibold, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(DetailInk.upNextKicker)
                    Text(DetailPageCopy.episode(number, german: german))
                        .font(.detailSF(12, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.kuroInk)
                    if let title {
                        Text(title)
                            .font(.detailSF(9, relativeTo: .caption2))
                            .foregroundStyle(DetailInk.progressCaption)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                DetailUpNextKey(material: material, pending: savingNext, confirmTrigger: confirmTrigger,
                                accessibilityText: KuroAdvanceCopy.label(medium: .anime, nextUnit: number, title: anime.displayTitle,
                                                                         current: progress, total: total, german: german)) {
                    onAdvance(number)
                }
            }
            // The prototype's 58 pt summary (padding 7/9 → 74): the key sits centred, 14 pt from each edge.
            .frame(minHeight: 58)
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background {
                // The shadow belongs to the row's shape only (on the container it would shadow every child).
                shape.fill(material.wash.color)
                    .shadow(color: Color(hex: "344D38", opacity: 0x05 / 255.0), radius: 4, x: 0, y: 3)
            }
            .overlay(shape.strokeBorder(material.edge.color, lineWidth: 1))
            .overlay(alignment: .top) {
                shape.stroke(Color.white, lineWidth: 1).mask(alignment: .top) { Rectangle().frame(height: 1) }
            }
            .padding(.trailing, -9)
        }
        .padding(.vertical, 6)
    }

    /// An episode row opens only when it has something to show.
    static func isExpandable(description: String?, streamURL: URL?) -> Bool {
        description?.detailNonEmpty != nil || streamURL != nil
    }

    // MARK: Loading

    private func loadAll() async {
        guard !loadingMore, hasMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let page = await catalog.fetchEpisodesPage(animeId: anime.id, offset: allEpisodes.count, limit: 50)
        guard !Task.isCancelled else { return }
        allEpisodes += page.filter { item in !allEpisodes.contains(where: { $0.id == item.id }) }
        hasMore = page.count == 50
    }

    /// The watched run's rows (episode 1 to `last`), at most four pages.
    private func loadRun(through last: Int) async {
        guard !loadingRun else { return }
        loadingRun = true
        defer { loadingRun = false }
        var loaded: [Episode] = []
        for _ in 0..<4 {
            let page = await catalog.fetchEpisodesPage(animeId: anime.id, offset: loaded.count, limit: 50)
            guard !Task.isCancelled else { return }
            loaded += page
            if page.count < 50 || (loaded.map(\.number).max() ?? 0) >= last { break }
        }
        runEpisodes = loaded
    }
}
