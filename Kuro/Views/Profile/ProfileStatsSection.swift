import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - "Your numbers." (details-songs spec §12; Home grammar G§4, G§7, G§8.1, G§8.3)
// Order: the page heading (24 semibold −0.85) with "Counted on this device"; two glance cards
// (episodes, chapters); the time total on the cover line (34 semibold −1.1) with its caveat; the top
// genres as 36 pt rows with a monochrome Home scrub; the "your year" scene card and its honest note.
// Data: the current account's `LibraryStore` entries (counts and the year recompute at once) plus the
// catalogue card facts of those titles, read in batches only while the section is on screen, held in
// view state keyed by the account (dropped on a switch), and re-read only for titles not seen yet.
// A failed catalogue read keeps raw progress for the totals and shows the inline failed state (with
// retry) for time and genres, never zeros. `CatalogStore` is read optionally: a host that does not
// inject it (older snapshot hosts) gets the failed state instead of a crash.

struct ProfileStatsSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(IdentityStore.self) private var identity
    @Environment(CatalogStore.self) private var catalog: CatalogStore?
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Catalogue facts by title, for `factsAccount` only.
    @State private var facts: [MediaKey: ProfileTitleFacts] = [:]
    /// Titles whose facts were read (found or not), so only new titles are read again.
    @State private var requested: Set<MediaKey> = []
    @State private var factsAccount: String?
    @State private var catalogue: ProfileCatalogueState = .loading
    @State private var retryToken = 0

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        let entries = library.allEntries
        let stats = ProfileStats.make(entries: entries, facts: facts, catalogue: catalogue, now: Date(),
                                      calendar: KuroLocale.calendar, locale: KuroLocale.locale)
        VStack(alignment: .leading, spacing: 0) {
            DiscoverPageHeading(title: ProfileStatsCopy.heading(german: german),
                                summary: ProfileStatsCopy.summary(german: german))
                .padding(.bottom, 14)
            content(stats)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .task(id: LoadKey(account: identity.currentUserId, keys: Set(entries.map(\.key)), retry: retryToken)) {
            await loadFacts(entries: entries)
        }
    }

    @ViewBuilder
    private func content(_ stats: ProfileStats) -> some View {
        if stats.isEmpty {
            if library.loadState == .loaded {
                HomeQuietCard(text: ProfileStatsCopy.empty(german: german))
            } else {
                KuroSkeleton(kind: .row)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                totals(stats)
                switch catalogue {
                case .loading:
                    VStack(alignment: .leading, spacing: 10) {
                        KuroSkeleton(kind: .row)
                        KuroSkeleton(kind: .row)
                    }
                case .failed:
                    KuroStateView(.failed(hasCachedContent: false),
                                  title: ProfileStatsCopy.catalogueFailed(german: german), layout: .inline) {
                        retryToken += 1
                    }
                case .loaded:
                    if let time = stats.time { timeBlock(time) }
                    if !stats.genres.isEmpty { genreBlock(stats.genres) }
                }
                if let year = stats.year {
                    ProfileYearCard(year: year, onOpen: { key in routes.openMedia(MediaRoute(key)) })
                }
            }
        }
    }

    // MARK: Totals

    @ViewBuilder
    private func totals(_ stats: ProfileStats) -> some View {
        let cards = [stats.episodes.map { (ProfileStatsCopy.episodesKicker(german: german), $0,
                                           ProfileStatsCopy.acrossAnime($0.titles, german: german),
                                           ProfileStatsCopy.episodesSpoken($0, german: german, locale: KuroLocale.locale)) },
                     stats.chapters.map { (ProfileStatsCopy.chaptersKicker(german: german), $0,
                                           ProfileStatsCopy.acrossManga($0.titles, german: german),
                                           ProfileStatsCopy.chaptersSpoken($0, german: german, locale: KuroLocale.locale)) }]
            .compactMap { $0 }
        if !cards.isEmpty {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                ForEach(cards, id: \.0) { card in
                    ProfileTotalCard(kicker: card.0, value: ProfileStatsCopy.number(card.1.units, locale: KuroLocale.locale),
                                     caption: card.2, spoken: card.3)
                }
            }
        }
    }

    // MARK: Time

    @ViewBuilder
    private func timeBlock(_ time: ProfileStats.Time) -> some View {
        let caveat = ProfileStatsCopy.timeCaveat(missing: time.missing, german: german)
        if let value = ProfileStatsCopy.time(minutes: time.minutes, german: german, locale: KuroLocale.locale) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            VStack(alignment: .leading, spacing: 0) {
                layout {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(value)
                            .font(.kuroCustom(34, weight: .semibold, relativeTo: .largeTitle, maxSize: 52))
                            .tracking(-1.1)
                            .monospacedDigit()
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .kuroCountRoll(value: value)
                        Rectangle().fill(Color.kuroInk).frame(width: 46, height: 2)
                    }
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                    Text(caveat)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
                        .foregroundStyle(Color.kuroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ProfileStatsCopy.timeKicker(german: german)): \(value). \(caveat)")
        } else if time.missing > 0 {
            // No title has a length: only the caveat (never "0 h").
            Text(caveat)
                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
                .foregroundStyle(Color.kuroMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Genres

    private func genreBlock(_ genres: [ProfileStats.Genre]) -> some View {
        let top = max(1, genres.first?.count ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ProfileStatsCopy.genresHeading(german: german))
                    .accessibilityAddTraits(.isHeader)
                Text("·").accessibilityHidden(true)
                Text(ProfileStatsCopy.genresSummary(german: german))
            }
            .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
            .tracking(1.05)
            .textCase(.uppercase)
            .foregroundStyle(HomeInk.kicker)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(genres, id: \.name) { genre in
                HStack(spacing: 12) {
                    Text(genre.name)
                        .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(1)
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 104, alignment: .leading)
                    HomeScrub(fraction: Double(genre.count) / Double(top), track: HomeInk.tileTrack, trace: HomeInk.tileTrace)
                        .frame(maxWidth: .infinity)
                    Text("\(genre.count)")
                        .font(.kuroCustom(12, weight: .medium, relativeTo: .caption1, maxSize: 24))
                        .monospacedDigit()
                        .foregroundStyle(HomeInk.glanceMuted)
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .frame(minHeight: 36)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ProfileStatsCopy.genreSpoken(genre, german: german))
            }
        }
    }

    // MARK: Loading

    private struct LoadKey: Hashable {
        let account: String?
        let keys: Set<MediaKey>
        let retry: Int
    }

    private func loadFacts(entries: [LibraryEntry]) async {
        let account = identity.currentUserId
        if account != factsAccount {
            // Another account (or the first read): nothing of the last one stays.
            facts = [:]
            requested = []
            factsAccount = account
            catalogue = .loading
        }
        guard account != nil, !entries.isEmpty else {
            catalogue = .loaded
            return
        }
        let missing = ProfileStats.missingKeys(entries: entries, known: requested)
        guard !missing.isEmpty else {
            if catalogue != .failed { catalogue = .loaded }
            return
        }
        guard let catalog else {
            catalogue = .failed
            return
        }
        if catalogue == .failed { catalogue = .loading }
        let animeIds = missing.filter { $0.kind == .anime }.map(\.id)
        let mangaIds = missing.filter { $0.kind == .manga }.map(\.id)
        var read: [MediaKey: ProfileTitleFacts] = [:]
        var failed = false
        for chunk in Self.chunks(animeIds) {
            guard let rows = await catalog.fetchAnimeByIdsPreservingOrder(chunk) else { failed = true; continue }
            for row in rows { read[MediaKey(kind: .anime, id: row.id)] = Self.facts(row) }
        }
        for chunk in Self.chunks(mangaIds) {
            guard let rows = await catalog.fetchMangaByIdsPreservingOrder(chunk) else { failed = true; continue }
            for row in rows { read[MediaKey(kind: .manga, id: row.id)] = Self.facts(row) }
        }
        // The answer belongs to the account that asked; a switch while reading drops it.
        guard !Task.isCancelled, identity.currentUserId == account, factsAccount == account else { return }
        facts.merge(read) { _, new in new }
        if failed && read.isEmpty && facts.isEmpty {
            catalogue = .failed
            return
        }
        // A read that answered (even without a row for some title) is not asked again.
        requested.formUnion(failed ? Set(read.keys) : Set(missing))
        catalogue = .loaded
    }

    /// The spec's chunks of 50 ids.
    static func chunks(_ ids: [Int], size: Int = 50) -> [[Int]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }

    static func facts(_ anime: Anime) -> ProfileTitleFacts {
        ProfileTitleFacts(title: anime.displayTitle, total: anime.episodeCount, duration: anime.duration,
                          genres: anime.genreList ?? [],
                          artwork: URL(string: anime.bannerImage ?? "") ?? URL(string: anime.coverImageLarge ?? ""))
    }

    static func facts(_ manga: Manga) -> ProfileTitleFacts {
        ProfileTitleFacts(title: manga.displayTitle, total: manga.chapterCount, duration: nil,
                          genres: manga.genreList ?? [], artwork: URL(string: manga.coverImageLarge ?? ""))
    }
}

/// One total (G§8.1 glance card): eyebrow 9/1.05, the count 24 medium mono, the caption 10 pt.
private struct ProfileTotalCard: View {
    let kicker: String
    let value: String
    let caption: String
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(HomeInk.kicker)
            Text(value)
                .font(.kuroCustom(24, weight: .medium, relativeTo: .title2, maxSize: 40))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(HomeInk.glanceInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .kuroCountRoll(value: value)
            Text(caption)
                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
                .foregroundStyle(HomeInk.glanceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(HomeInk.glanceFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
        .shadow(color: HomeInk.glanceShadow, radius: 1, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
