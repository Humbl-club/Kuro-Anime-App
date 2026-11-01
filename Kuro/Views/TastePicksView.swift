import KuroCore
import KuroLibrary
import SwiftUI

/// The left-hand Taste page: a short set of titles the person has not really met (rulebook §14.9).
/// Personal picks when the account has enough signal, otherwise a few unseen catalogue titles.
/// Up to four picks per medium, picture first; a story sentence only on these new recommendations,
/// and a separate 44 pt Plan key per pick. It reads the launch's Discover bundle (one
/// `discover_bundle` per launch, shared with Discover) and the because-you rail.
struct TastePicksView: View {
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(LibraryStore.self) private var library
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var medium: MediaKind = .anime
    @State private var animePicks: [Media] = []
    @State private var mangaPicks: [Media] = []
    @State private var animeNote = ""
    @State private var mangaNote = ""
    @State private var isLoading = true
    @State private var failed = false

    private let cap = 4

    var body: some View {
        GeometryReader { geo in
            let width = DiscoverLayout.contentWidth(container: geo.size.width, regularWidth: horizontalSizeClass == .regular)
            let gutter = DiscoverLayout.gutter(for: width)
            let inner = max(0, width - gutter * 2)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    KuroMediumSwitch(selection: $medium, size: .compact)

                    if isLoading {
                        TastePicksSkeleton(width: inner)
                    } else if failed {
                        KuroStateView(
                            networkMonitor.isConnected ? .failed(hasCachedContent: false) : .offline(hasCachedContent: false),
                            layout: .inline,
                            retry: { Task { await load() } }
                        )
                    } else if picks.isEmpty {
                        KuroStateView(
                            .empty,
                            title: TastePicksCopy.emptyTitle(german: KuroLocale.isGerman),
                            message: TastePicksCopy.emptyMessage(german: KuroLocale.isGerman),
                            layout: .inline
                        )
                    } else {
                        Text(note)
                            .font(.kuroTitle(weight: .light))
                            .foregroundStyle(Color.kuroInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        let columns = DiscoverLayout.columnCount(for: inner, minimum: 150, spacing: KuroDesignSpacing.md)
                        let frameWidth = DiscoverLayout.gridFrameWidth(for: inner, columns: columns, spacing: KuroDesignSpacing.md)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(frameWidth), spacing: KuroDesignSpacing.md, alignment: .top), count: columns),
                            alignment: .leading,
                            spacing: KuroDesignSpacing.xl
                        ) {
                            ForEach(picks, id: \.stableKey) { item in
                                TastePickFrame(media: item, width: frameWidth)
                            }
                        }
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.top, KuroDesignSpacing.sm)
                .padding(.bottom, KuroDesignSpacing.xl)
                .frame(width: width)
                .frame(maxWidth: .infinity)
            }
            .scrollDisabled(false)
            .background(Color.kuroCanvasPage)
        }
        .task { await load() }
        .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
            guard networkMonitor.isConnected, failed else { return }
            Task { await load() }
        }
    }

    private var picks: [Media] { medium == .anime ? animePicks : mangaPicks }
    private var note: String { medium == .anime ? animeNote : mangaNote }

    private func load() async {
        isLoading = animePicks.isEmpty && mangaPicks.isEmpty
        failed = false
        async let because = discovery.fetchBecauseYouRail(limit: 8)
        async let bundle = discovery.ensureDiscoverBundle()
        let becauseRows = await because
        let fetched = await bundle
        defer { isLoading = false }
        if fetched == nil && becauseRows == nil {
            // Keep picks already on screen; a failure only replaces an empty page.
            failed = animePicks.isEmpty && mangaPicks.isEmpty
            return
        }
        apply(because: becauseRows ?? [], bundle: fetched)
    }

    private func apply(because: [BecauseYouCard], bundle: DiscoverBundle?) {
        let animePersonal = because
            .filter { $0.mediaType.uppercased() != "MANGA" }
            .map { $0.toMedia() }
        let mangaPersonal = because
            .filter { $0.mediaType.uppercased() == "MANGA" }
            .map { $0.toMedia() }
        let animeUnseen = (bundle?.anime.newToYou ?? []).map { Media(card: $0) }
        let mangaUnseen = (bundle?.manga.newToYou ?? []).map { Media(card: $0) }
        let animeStart = (bundle?.anime.essentials ?? []).map { Media(card: $0) }
        let mangaStart = (bundle?.manga.essentials ?? []).map { Media(card: $0) }

        let german = KuroLocale.isGerman
        let animeChoice = TastePicksCopy.choose(
            personal: open(animePersonal), unseen: open(animeUnseen), start: open(animeStart), cap: cap, german: german
        )
        let mangaChoice = TastePicksCopy.choose(
            personal: open(mangaPersonal), unseen: open(mangaUnseen), start: open(mangaStart), cap: cap, german: german
        )
        animePicks = animeChoice.items
        mangaPicks = mangaChoice.items
        animeNote = animeChoice.note
        mangaNote = mangaChoice.note
    }

    /// Titles not on the list yet.
    private func open(_ items: [Media]) -> [Media] {
        items.filter { !library.isTracked($0.libraryKey) }
    }
}

// MARK: - Copy and choice (pure)

/// Which set the page shows and how it introduces it, EN/DE.
nonisolated enum TastePicksCopy {
    enum Source: Equatable {
        case personal, unseen, start, none
    }

    static func source(personal: Int, unseen: Int, start: Int) -> Source {
        if personal >= 2 { return .personal }
        if unseen > 0 { return .unseen }
        if start > 0 { return .start }
        return .none
    }

    static func note(_ source: Source, german: Bool) -> String {
        switch source {
        case .personal: return german ? "Nah an dem, was du magst." : "Close to what you already like."
        case .unseen: return german ? "Ein paar, die du noch nicht kennst." : "A few you have not really looked at."
        case .start: return german ? "Ein kurzer Anfang, bis Kuro dich besser kennt." : "A short start, until there is more to go on."
        case .none: return emptyTitle(german: german)
        }
    }

    static func emptyTitle(german: Bool) -> String {
        german ? "Gerade nichts Neues für dich." : "Nothing new to put in front of you right now."
    }

    static func emptyMessage(german: Bool) -> String {
        german ? "Speichere ein paar Titel, dann wird die Auswahl persönlicher." : "Save a few titles and the picks get more personal."
    }

    static func choose<Item>(personal: [Item], unseen: [Item], start: [Item], cap: Int, german: Bool) -> (items: [Item], note: String) {
        let source = source(personal: personal.count, unseen: unseen.count, start: start.count)
        let items: [Item]
        switch source {
        case .personal: items = Array(personal.prefix(cap))
        case .unseen: items = Array(unseen.prefix(cap))
        case .start: items = Array(start.prefix(cap))
        case .none: items = []
        }
        return (items, note(source, german: german))
    }

    /// The first sentence of a synopsis, without markup (the story line under a new pick).
    static func storySentence(_ raw: String) -> String? {
        let plain = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        if let end = plain.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            return String(plain[..<end.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return plain
    }
}

// MARK: - Pick frame

/// One pick: the cover (opens the title), the title, one story sentence, and a separate Plan key.
/// The key adds the title as Planned; on a title it planned it removes it again; a title saved with
/// another status shows that it is on the list and opens the list editor instead (never removes it).
private struct TastePickFrame: View {
    let media: Media
    let width: CGFloat

    @State private var isPressed = false
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private var status: ListStatus? { library.entry(for: media.libraryKey)?.status }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                DiscoverPicture(url: URL(string: media.imageURL ?? ""), maxPixelSize: 420)
                    .frame(width: width, height: floor(width / KuroCardMetrics.imageAspectRatio))
                    .clipShape(RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous))
                Text(KuroCardText.sanitizeTitleForCard(media.title))
                    .font(.kuroBody(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let story = TastePicksCopy.storySentence(media.displayDescription) {
                    Text(story)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .kuroDeliberateTap {
                guard !suppressCardTaps else { return }
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(media.libraryKey))
            }
            .scaleEffect(isPressed ? 0.985 : 1)
            .kuroAnimation(KuroMotion.contact, value: isPressed)
            .pressable($isPressed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(media.title))
            .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
            .accessibilityAddTraits(.isButton)

            planKey
        }
        .frame(width: width, alignment: .topLeading)
    }

    private var planKey: some View {
        let planned = status == .planning
        let otherStatus = status != nil && !planned
        let title: String = {
            if planned { return KuroLocale.text("Planned", "Geplant") }
            if otherStatus { return KuroLocale.text("On your list", "Auf deiner Liste") }
            return KuroLocale.text("Plan", "Vormerken")
        }()
        return Button {
            KuroAccessibility.impactHaptic(.light)
            if otherStatus {
                routes.presentTrackingEditor(TrackingEditorRequest(media: media))
            } else {
                LibraryViewActions.toggleTracked(media.libraryKey, actions: libraryActions)
            }
        } label: {
            HStack(spacing: KuroDesignSpacing.sm) {
                Image(systemName: planned || otherStatus ? "checkmark" : "plus")
                    .font(.kuroMeta(weight: .medium))
                Text(title)
                    .font(.kuroMeta(weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.kuroInk)
            .padding(.horizontal, KuroDesignSpacing.md)
            .frame(minWidth: 44, minHeight: 44)
            .overlay(
                Capsule().stroke(Color.kuroKeyRim, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(
            planned
                ? KuroLocale.text("Planned. Remove \(media.title) from Planned", "Geplant. \(media.title) aus Geplant entfernen")
                : otherStatus
                    ? KuroLocale.text("\(media.title) is on your list. Edit list entry", "\(media.title) ist auf deiner Liste. Listeneintrag bearbeiten")
                    : KuroLocale.text("Plan \(media.title)", "\(media.title) vormerken")
        )
        .accessibilityAddTraits(planned ? [.isSelected] : [])
    }
}

/// Stable placeholder geometry for the picks (two frames per row).
private struct TastePicksSkeleton: View {
    let width: CGFloat

    var body: some View {
        let columns = DiscoverLayout.columnCount(for: width, minimum: 150, spacing: KuroDesignSpacing.md)
        let frameWidth = DiscoverLayout.gridFrameWidth(for: width, columns: columns, spacing: KuroDesignSpacing.md)
        VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.kuroBlack05)
                .frame(width: min(width, 260), height: 20)
            HStack(alignment: .top, spacing: KuroDesignSpacing.md) {
                ForEach(0..<columns, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                            .fill(Color.kuroBlack05)
                            .frame(width: frameWidth, height: floor(frameWidth / KuroCardMetrics.imageAspectRatio))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.kuroBlack05)
                            .frame(width: frameWidth * 0.8, height: 12)
                        Capsule()
                            .fill(Color.kuroBlack05)
                            .frame(width: 96, height: 44)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading", "Wird geladen"))
    }
}

private extension Media {
    init(card: AnimeCard) {
        self.init(
            id: card.id,
            kind: .anime,
            title: card.title,
            imageURL: card.imageURL,
            year: card.year,
            displayDescription: card.displayDescription,
            episodes: card.episodes,
            chapters: card.chapters,
            rating: card.rating,
            genres: card.genres,
            statusRaw: card.statusRaw,
            formatRaw: card.formatRaw,
            popularityValue: card.popularityValue,
            trendingValue: card.trendingValue,
            createdAtValue: card.createdAtValue
        )
    }

    init(card: MangaCard) {
        self.init(
            id: card.id,
            kind: .manga,
            title: card.title,
            imageURL: card.imageURL,
            year: card.year,
            displayDescription: card.displayDescription,
            episodes: card.episodes,
            chapters: card.chapters,
            rating: card.rating,
            genres: card.genres,
            statusRaw: card.statusRaw,
            formatRaw: card.formatRaw,
            popularityValue: card.popularityValue,
            trendingValue: card.trendingValue,
            createdAtValue: card.createdAtValue
        )
    }
}
