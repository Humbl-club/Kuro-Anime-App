import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Taste page (prototype-fidelity pass, plan Task 8)
// The prototype's Taste page (`ref-taste-{busy,new}-{anime,manga}-390.png`, PROTOTYPE_SPEC.md §4
// "Taste" and §8.10): the medium words, "FOR YOUR TASTE" with "Another world." / "Another chapter.",
// one heading ("Your next story." / "Turn to something new.", or "A first favourite." for a new
// account), then story cards with a separate Plan key. Anime: the first title with a banner is the
// wide landscape card, the rest are portrait cards (art beside the copy). Manga: a two-column grid
// of framed covers. The page reads the launch's Discover bundle (one `discover_bundle` per launch,
// shared with Discover) and the because-you rail; every card is a real title, and a premise is shown
// only where the read carries a real synopsis (the bundle cards carry none).
// The story cards (`TasteStoryList`) are shared with the new-account Home (`HomeNewAccount`).

struct TastePicksView: View {
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(LibraryStore.self) private var library
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(ArtworkMaterialStore.self) private var materials

    @State private var medium: MediaKind = .anime
    @State private var animePicks: [TasteCard] = []
    @State private var mangaPicks: [TasteCard] = []
    @State private var isLoading = true
    /// Per medium: the last load could not settle that medium's picks and nothing is on screen.
    @State private var animeFailed = false
    @State private var mangaFailed = false

    private let cap = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ScrollView(.vertical, showsIndicators: false) {
                TastePageContent(
                    medium: $medium,
                    state: state,
                    newAccount: TastePageCopy.isNewAccount(loaded: library.loadState == .loaded,
                                                           entryCount: library.allEntries.count),
                    material: switchMaterial,
                    width: width,
                    retry: { Task { await load() } }
                )
            }
            .scrollDisabled(false)
            .background(TastePageContent.canvas(for: medium))
        }
        .task { await load() }
        .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
            guard networkMonitor.isConnected, animeFailed || mangaFailed else { return }
            Task { await load() }
        }
    }

    private var picks: [TasteCard] { medium == .anime ? animePicks : mangaPicks }
    private var failed: Bool { medium == .anime ? animeFailed : mangaFailed }

    private var state: TastePageContent.State {
        if isLoading { return .loading }
        if failed { return .unavailable(offline: !networkMonitor.isConnected) }
        if picks.isEmpty { return .empty }
        return .cards(picks)
    }

    /// The selected medium word takes the first pick's artwork material (neutral until it is known).
    private var switchMaterial: ArtworkMaterial? {
        guard let raw = picks.first?.media.imageURL, let url = URL(string: raw) else { return nil }
        return materials.material(for: url, seedHex: nil)
    }

    private func load() async {
        isLoading = animePicks.isEmpty && mangaPicks.isEmpty
        animeFailed = false
        mangaFailed = false
        async let because = discovery.fetchBecauseYouRail(limit: 8)
        async let bundle = discovery.ensureDiscoverBundle()
        let becauseRows = await because
        let fetched = await bundle
        defer { isLoading = false }
        apply(because: becauseRows, bundle: fetched)
    }

    /// Writes each medium's choice only when the reads it depends on loaded (rulebook §9: a failed
    /// read never shows as the empty state). An unsettled medium keeps the picks already on screen
    /// and reports a failure only when it has none.
    private func apply(because: [BecauseYouCard]?, bundle: DiscoverBundle?) {
        let german = KuroLocale.isGerman
        let rows = because ?? []
        let animePersonal = open(rows.filter { $0.mediaType.uppercased() != "MANGA" }.map(TasteCard.init(because:)))
        let mangaPersonal = open(rows.filter { $0.mediaType.uppercased() == "MANGA" }.map(TasteCard.init(because:)))
        let animeChoice = TastePicksCopy.choose(
            personal: animePersonal,
            unseen: open((bundle?.anime.newToYou ?? []).map(TasteCard.init(anime:))),
            start: open((bundle?.anime.essentials ?? []).map(TasteCard.init(anime:))),
            cap: cap, german: german
        )
        let mangaChoice = TastePicksCopy.choose(
            personal: mangaPersonal,
            unseen: open((bundle?.manga.newToYou ?? []).map(TasteCard.init(manga:))),
            start: open((bundle?.manga.essentials ?? []).map(TasteCard.init(manga:))),
            cap: cap, german: german
        )
        let personalLoaded = because != nil
        let bundleLoaded = bundle != nil

        if TastePicksCopy.isSettled(
            personal: personalLoaded ? animePersonal.count : nil, bundleLoaded: bundleLoaded, chosen: animeChoice.items.count
        ) {
            animePicks = animeChoice.items
        } else {
            animeFailed = animePicks.isEmpty
        }
        if TastePicksCopy.isSettled(
            personal: personalLoaded ? mangaPersonal.count : nil, bundleLoaded: bundleLoaded, chosen: mangaChoice.items.count
        ) {
            mangaPicks = mangaChoice.items
        } else {
            mangaFailed = mangaPicks.isEmpty
        }
    }

    /// Real titles not on the list yet, once each (`FirstFavouritePicks`).
    private func open(_ cards: [TasteCard]) -> [TasteCard] {
        let tracked = Set(cards.map(\.key).filter { library.isTracked($0) })
        return FirstFavouritePicks.pick(from: cards, max: Int.max, excluding: tracked)
    }
}

// MARK: - Page content (pure presentation; also the fixture renders)

/// The Taste page below the header: the opening block, then the state or the story cards, then the
/// page footer. Everything it shows comes in as values.
struct TastePageContent: View {
    enum State {
        case loading
        case unavailable(offline: Bool)
        case empty
        case cards([TasteCard])
    }

    @Binding var medium: MediaKind
    let state: State
    let newAccount: Bool
    var material: ArtworkMaterial?
    let width: CGFloat
    var retry: () -> Void = {}

    /// The page canvas: the warm Home canvas for anime, the manga Home canvas for manga
    /// (`ref-taste-*-manga-390.png`; amendment 8, "Taste follows its reference").
    static func canvas(for medium: MediaKind) -> Color {
        medium == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome
    }

    private var metrics: TasteMetrics { TasteMetrics(pageWidth: width) }
    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TasteOpening(medium: $medium, material: material, metrics: metrics,
                         kicker: TastePageCopy.kicker(german: german),
                         headline: TastePageCopy.opening(medium: medium, german: german))

            Group {
                switch state {
                case .loading:
                    TasteStorySkeleton(medium: medium, metrics: metrics)
                        .padding(.top, metrics.headingTopAfterOpening)
                case .unavailable(let offline):
                    KuroStateView(offline ? .offline(hasCachedContent: false) : .failed(hasCachedContent: false),
                                  layout: .inline, retry: retry)
                case .empty:
                    KuroEmptyView(headline: TastePicksCopy.emptyTitle(german: german),
                                  message: TastePicksCopy.emptyMessage(german: german))
                case .cards(let cards):
                    VStack(alignment: .leading, spacing: 0) {
                        TasteSectionHeading(
                            title: TastePageCopy.heading(medium: medium, newAccount: newAccount, german: german),
                            medium: medium, metrics: metrics, top: metrics.headingTopAfterOpening
                        )
                        TasteStoryList(cards: cards, medium: medium, metrics: metrics)
                    }
                }
            }
            .padding(.horizontal, metrics.paperGutter)
            .padding(.bottom, 24)

            TasteFooter()
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Copy (pure)

/// The Taste page's words, EN/DE (PROTOTYPE_SPEC.md §7.1).
nonisolated enum TastePageCopy {
    static func kicker(german: Bool) -> String {
        german ? "FÜR DEINEN GESCHMACK" : "FOR YOUR TASTE"
    }

    static func opening(medium: MediaKind, german: Bool) -> String {
        switch medium {
        case .anime: return german ? "Eine andere Welt." : "Another world."
        case .manga: return german ? "Ein anderes Kapitel." : "Another chapter."
        }
    }

    /// The section heading. "A first favourite." only for an account whose Library has answered and
    /// holds nothing; while the Library is unknown the ordinary heading stands.
    static func heading(medium: MediaKind, newAccount: Bool, german: Bool) -> String {
        if newAccount { return firstFavourite(german: german) }
        switch medium {
        case .anime: return german ? "Deine nächste Geschichte." : "Your next story."
        case .manga: return german ? "Zeit für etwas Neues." : "Turn to something new."
        }
    }

    static func firstFavourite(german: Bool) -> String {
        german ? "Ein erster Favorit." : "A first favourite."
    }

    /// A new account: the Library loaded and holds no title.
    static func isNewAccount(loaded: Bool, entryCount: Int) -> Bool {
        loaded && entryCount == 0
    }

    /// The Plan key's words for a title in `status` (nil: not on the list).
    static func planLabel(medium: MediaKind, status: ListStatus?, german: Bool) -> String {
        switch status {
        case .planning?: return german ? "Vorgemerkt" : "Planned"
        case nil:
            if german { return "Vormerken" }
            return medium == .manga ? "Plan to read" : "Plan to watch"
        default: return german ? "Auf deiner Liste" : "On your list"
        }
    }

    /// The kind kicker over a story card's title ("FILM · ROMANCE", "MANGA · HISTORICAL"): the
    /// title's format and first genre, both real; nil when neither is known.
    static func kind(format: String?, genres: [String]?, german: Bool) -> String? {
        var parts: [String] = []
        if let format = format?.trimmingCharacters(in: .whitespaces), !format.isEmpty {
            parts.append(format.uppercased() == "MOVIE" ? "Film" : DiscoverFrameCopy.formatName(format, german: german))
        }
        if let genre = genres?.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            parts.append(genreName(genre, german: german))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ").uppercased()
    }

    /// AniList genres in reading form (the same words Browse uses).
    static func genreName(_ genre: String, german: Bool) -> String {
        guard german else { return genre }
        switch genre {
        case "Adventure": return "Abenteuer"
        case "Comedy": return "Komödie"
        case "Psychological": return "Psychologisch"
        case "Romance": return "Romantik"
        case "Slice of Life": return "Alltag"
        case "Sports": return "Sport"
        case "Supernatural": return "Übernatürlich"
        default: return genre
        }
    }
}

/// Which set the page shows, EN/DE. (Kept from the first Taste page: the choice and its settle rule.)
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

    /// Whether one medium's choice can be shown as it is. `personal` is the count of open personal
    /// rows (nil: the because-you read failed); `bundleLoaded` says the Discover bundle read
    /// succeeded; `chosen` is the size of the resulting choice. A choice is settled when it is the
    /// personal set (enough rows, whatever the bundle did), when both reads loaded (an empty choice
    /// is then a true empty state), or when the bundle loaded and gave picks. Anything else may be
    /// hiding a failure and must not render as empty.
    static func isSettled(personal: Int?, bundleLoaded: Bool, chosen: Int) -> Bool {
        if let personal, personal >= 2 { return true }
        guard bundleLoaded else { return false }
        return personal != nil || chosen > 0
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

    /// The first sentence of a synopsis, without markup (the story line under a new pick). Nil for
    /// an empty synopsis and for the catalogue's "no description" placeholder.
    static func storySentence(_ raw: String) -> String? {
        let plain = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty, !TasteCard.isPlaceholderText(plain) else { return nil }
        if let end = plain.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            return String(plain[..<end.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return plain
    }
}

// MARK: - Cards (pure)

/// One recommendation as a story card shows it: the title, its cover, a banner for the landscape
/// card (anime bundle rows only), and a premise only when the read carried a real synopsis.
struct TasteCard: Identifiable {
    let media: Media
    let bannerURL: String?
    let premise: String?

    var id: String { media.stableKey }
    var key: MediaKey { media.libraryKey }

    init(media: Media, bannerURL: String? = nil, premise: String? = nil) {
        self.media = media
        let banner = bannerURL?.trimmingCharacters(in: .whitespaces)
        self.bannerURL = (banner?.isEmpty ?? true) ? nil : banner
        self.premise = premise.flatMap { TastePicksCopy.storySentence($0) }
    }

    /// A Discover bundle anime row. Its `displayDescription` is a placeholder, so there is no premise.
    init(anime card: AnimeCard) {
        self.init(media: Self.media(kind: .anime, id: card.id, title: card.title, imageURL: card.imageURL,
                                    year: card.year, episodes: card.episodes, chapters: nil, rating: card.rating,
                                    genres: card.genres, statusRaw: card.statusRaw, formatRaw: card.formatRaw),
                  bannerURL: card.bannerImage, premise: nil)
    }

    /// A Discover bundle manga row (no premise, no banner).
    init(manga card: MangaCard) {
        self.init(media: Self.media(kind: .manga, id: card.id, title: card.title, imageURL: card.imageURL,
                                    year: card.year, episodes: nil, chapters: card.chapters, rating: card.rating,
                                    genres: card.genres, statusRaw: card.statusRaw, formatRaw: card.formatRaw),
                  bannerURL: nil, premise: nil)
    }

    /// A because-you row: carries the synopsis, so its first sentence is the premise.
    init(because card: BecauseYouCard) {
        self.init(media: card.toMedia(), bannerURL: nil, premise: card.synopsis)
    }

    /// The catalogue's stand-ins for a missing title or description (never shown as content).
    nonisolated static func isPlaceholderText(_ text: String) -> Bool {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return plain.isEmpty || plain == "unknown" || plain == "no description available" || plain == "no description available."
    }

    private static func media(kind: MediaKind, id: Int, title: String, imageURL: String?, year: String,
                              episodes: Int?, chapters: Int?, rating: Double?, genres: [String]?,
                              statusRaw: String?, formatRaw: String?) -> Media {
        Media(id: id, kind: kind, title: title, imageURL: imageURL, year: year, displayDescription: "",
              episodes: episodes, chapters: chapters, rating: rating, genres: genres, statusRaw: statusRaw,
              formatRaw: formatRaw, popularityValue: nil, trendingValue: nil, createdAtValue: nil)
    }
}

/// The starter titles for a new account ("A first favourite.") and the Taste page's open set: only
/// cards that were actually loaded, each once, never one without a real title, never one already
/// on the list, at most `max`. An empty input gives an empty row (the row is then hidden).
nonisolated enum FirstFavouritePicks {
    static func pick(from cards: [TasteCard], max: Int, excluding tracked: Set<MediaKey> = []) -> [TasteCard] {
        guard max > 0 else { return [] }
        var seen: Set<String> = []
        var result: [TasteCard] = []
        for card in cards {
            guard !TasteCard.isPlaceholderText(card.media.title),
                  !tracked.contains(card.key),
                  seen.insert(card.id).inserted else { continue }
            result.append(card)
            if result.count >= max { break }
        }
        return result
    }
}

// MARK: - Plan key rule (pure) and write

/// What one tap on a story card's Plan key does for a title in `status`: plan it (not on the list),
/// take it off again (it was planned here), or open the list editor (another status; never removed).
nonisolated enum TastePlanAction: Equatable {
    case plan, unplan, edit

    static func action(for status: ListStatus?) -> TastePlanAction {
        switch status {
        case nil: return .plan
        case .planning?: return .unplan
        default: return .edit
        }
    }
}

@MainActor
enum TastePlan {
    /// Runs one Plan key tap. Plan and un-plan go through `LibraryActions` (the guarded toggle: a
    /// missing title is saved as `.planning`; a planned one is removed); another status opens the
    /// list editor. Returns the write's task (nil for the editor, a duplicate tap or no session).
    @discardableResult
    static func perform(_ action: TastePlanAction, card: TasteCard, actions: LibraryActions,
                        routes: KuroRoutes) -> Task<Void, Never>? {
        switch action {
        case .plan, .unplan:
            return LibraryViewActions.toggleTracked(card.key, actions: actions)
        case .edit:
            routes.presentTrackingEditor(TrackingEditorRequest(media: card.media))
            return nil
        }
    }
}

// MARK: - Metrics

/// The prototype's measured geometry (PROTOTYPE_SPEC.md §4 "Taste"), with its `max-width:360px`
/// small-phone values.
struct TasteMetrics {
    let pageWidth: CGFloat

    var compact: Bool { pageWidth > 0 && pageWidth <= 360 }
    /// `.home-opening` side margin.
    var openingGutter: CGFloat { compact ? 16 : 20 }
    /// `#feed > .suggestions` side padding.
    var paperGutter: CGFloat { compact ? 18 : 22 }
    /// `.section-head` top margin. On Taste it collapses with the opening block's 18 pt bottom margin
    /// (CSS margin collapsing), so the visible gap there is 32, i.e. 14 beyond the opening's padding.
    var headingTop: CGFloat { 32 }
    var headingTopAfterOpening: CGFloat { 32 - 18 }
    var listSpacing: CGFloat { compact ? 14 : 16 }
    var mangaColumnSpacing: CGFloat { compact ? 14 : 17 }
    var portraitArtWidth: CGFloat { compact ? 90 : 103 }
    var portraitCopyLeading: CGFloat { compact ? 12 : 16 }
}

// MARK: - Opening block

/// The medium words over the hairline, then the kicker and the right-aligned opening line.
struct TasteOpening: View {
    @Binding var medium: MediaKind
    let material: ArtworkMaterial?
    let metrics: TasteMetrics
    let kicker: String
    let headline: String

    /// `.family-control` bottom border (`#20302744`).
    private static let rule = Color(hex: "203027", opacity: Double(0x44) / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KuroMediumSwitch(selection: $medium, size: .large, material: material)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Self.rule).frame(height: 1).accessibilityHidden(true)
                }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(kicker)
                    .font(.kuroCustom(metrics.compact ? 8 : 9, relativeTo: .caption2, maxSize: 16))
                    .tracking(1.05)
                    .foregroundStyle(Color(hex: "666C68"))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(headline)
                    .font(.kuroCustom(metrics.compact ? 13 : 14, weight: .semibold, relativeTo: .subheadline, maxSize: 24))
                    .tracking(-0.3)
                    .foregroundStyle(Color.kuroInk)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, metrics.openingGutter)
        .padding(.top, 7)
        .padding(.bottom, 18)
    }
}

/// The section heading ("Your next story."): SF 24 w550 −0.85 (manga w500 −0.65, at most 210 wide).
struct TasteSectionHeading: View {
    let title: String
    let medium: MediaKind
    let metrics: TasteMetrics
    /// Nil: the section's own 32 pt top margin.
    var top: CGFloat? = nil

    var body: some View {
        Text(title)
            .font(.kuroCustom(metrics.compact ? 22 : 24, weight: medium == .manga ? .regular : .medium,
                              relativeTo: .title2, maxSize: 40))
            .tracking(medium == .manga ? -0.65 : -0.85)
            .foregroundStyle(Color.kuroInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: medium == .manga ? 210 : .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, top ?? metrics.headingTop)
            .padding(.bottom, 17)
    }
}

// MARK: - Story list (shared with HomeNewAccount)

/// The story cards. Anime: the first card with a banner is the landscape card, the others portrait
/// cards. Manga: a two-column grid of framed covers.
struct TasteStoryList: View {
    let cards: [TasteCard]
    let medium: MediaKind
    let metrics: TasteMetrics

    var body: some View {
        if medium == .manga {
            Grid(horizontalSpacing: metrics.mangaColumnSpacing, verticalSpacing: 28) {
                ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { index in
                    GridRow(alignment: .top) {
                        TasteLeafCard(card: cards[index], metrics: metrics)
                        if index + 1 < cards.count {
                            TasteLeafCard(card: cards[index + 1], metrics: metrics)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.vertical])
                        }
                    }
                }
            }
        } else {
            let landscapeId = cards.first(where: { $0.bannerURL != nil })?.id
            VStack(alignment: .leading, spacing: metrics.listSpacing) {
                ForEach(cards) { card in
                    if card.id == landscapeId {
                        TasteLandscapeCard(card: card, metrics: metrics)
                    } else {
                        TastePortraitCard(card: card, metrics: metrics)
                    }
                }
            }
        }
    }
}

/// Story-card text roles (PROTOTYPE_SPEC.md §4 "Taste").
private enum TasteType {
    static let kindInk = Color(hex: "626B63")
    static let premiseInk = Color(hex: "575C59")

    static func kind(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        Text(text)
            .font(.kuroCustom(size, relativeTo: .caption2, maxSize: 16))
            .tracking(tracking)
            .foregroundStyle(kindInk)
            .lineLimit(1)
    }

    static func title(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        Text(KuroCardText.sanitizeTitleForCard(text))
            .font(.kuroCustom(size, weight: .medium, relativeTo: .title2, maxSize: size * 1.6))
            .tracking(tracking)
            .foregroundStyle(Color.kuroInk)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func premise(_ text: String, size: CGFloat, lineSpacing: CGFloat) -> some View {
        Text(text)
            .font(.kuroCustom(size, relativeTo: .footnote, maxSize: size * 1.8))
            .lineSpacing(lineSpacing)
            .foregroundStyle(premiseInk)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The artwork inside a story card (cover or banner), on the prototype's `#f0f0ed` well.
private struct TasteArt: View {
    let url: String?
    var fill: Bool = false

    var body: some View {
        Color(hex: "F0F0ED")
            .overlay {
                KuroCachedAsyncImage(url: url.flatMap(URL.init(string:)), maxPixelSize: 520) { phase in
                    switch phase {
                    case .success(let image):
                        if fill {
                            image.resizable().scaledToFill()
                        } else {
                            image.resizable().scaledToFit()
                        }
                    default:
                        Color.clear
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// The open target of a card: the whole card except the Plan key opens the title.
private struct TasteOpenButton<Label: View>: View {
    let card: TasteCard
    @ViewBuilder let label: () -> Label

    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        // A Button so the press state cancels on scroll/drag (rulebook §7).
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(card.key))
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.987))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.media.title))
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The wide anime card: banner over the copy, the Plan key across the foot.
private struct TasteLandscapeCard: View {
    let card: TasteCard
    let metrics: TasteMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TasteOpenButton(card: card) {
                VStack(alignment: .leading, spacing: 0) {
                    TasteArt(url: card.bannerURL ?? card.media.imageURL, fill: true)
                        .aspectRatio(2.8, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        if let kind = TastePageCopy.kind(format: card.media.formatRaw, genres: card.media.genres,
                                                         german: KuroLocale.isGerman) {
                            TasteType.kind(kind, size: 8, tracking: 0.5)
                        }
                        TasteType.title(card.media.title, size: 26, tracking: -0.6)
                            .padding(.top, 6)
                        if let premise = card.premise {
                            TasteType.premise(premise, size: 12, lineSpacing: 3.6)
                                // `max-width: 29ch` at 12 pt.
                                .frame(maxWidth: 245, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 17)
                    .padding(.top, 17)
                    .padding(.bottom, 12)
                }
            }
            TastePlanKey(card: card, variant: .landscape, compact: metrics.compact)
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .background { TasteCardFace() }
    }
}

/// The portrait anime card: the cover beside the copy, the Plan key under the copy.
private struct TastePortraitCard: View {
    let card: TasteCard
    let metrics: TasteMetrics

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TasteOpenButton(card: card) {
                TasteArt(url: card.media.imageURL)
                    .frame(width: metrics.portraitArtWidth, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 0) {
                TasteOpenButton(card: card) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let kind = TastePageCopy.kind(format: card.media.formatRaw, genres: card.media.genres,
                                                         german: KuroLocale.isGerman) {
                            TasteType.kind(kind, size: 9, tracking: 0.5)
                        }
                        TasteType.title(card.media.title, size: metrics.compact ? 19 : 21, tracking: -0.6)
                            .padding(.top, 8)
                        if let premise = card.premise {
                            TasteType.premise(premise, size: metrics.compact ? 11 : 12, lineSpacing: 3.6)
                                .padding(.top, 9)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .padding(.trailing, 9)
                }
                Spacer(minLength: 12)
                TastePlanKey(card: card, variant: .portrait, compact: metrics.compact)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            }
            .padding(.leading, metrics.portraitCopyLeading)
            .frame(minHeight: 180)
        }
        .padding(8)
        .background { TasteCardFace() }
    }
}

/// The white story-card face and its soft drop (`0 4px 14px -11px #14222540`), behind the content so
/// the text never carries the shadow.
private struct TasteCardFace: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .fill(Color.white)
            .shadow(color: Color(hex: "142225").opacity(0.14), radius: 4, y: 4)
    }
}

/// The manga leaf: a framed cover on white paper, the copy, then the Plan key.
private struct TasteLeafCard: View {
    let card: TasteCard
    let metrics: TasteMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TasteOpenButton(card: card) {
                VStack(alignment: .leading, spacing: 0) {
                    TasteArt(url: card.media.imageURL)
                        .padding(9)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color(hex: "D9DBD3"), lineWidth: 1))
                        .background(alignment: .topLeading) {
                            // The leaf behind the cover (`2px 2px 0 #e1e3da`).
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color(hex: "E1E3DA"))
                                .offset(x: 2, y: 2)
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        if let kind = TastePageCopy.kind(format: card.media.formatRaw, genres: card.media.genres,
                                                         german: KuroLocale.isGerman) {
                            TasteType.kind(kind, size: 9, tracking: 0.2)
                        }
                        TasteType.title(card.media.title, size: metrics.compact ? 18 : 20, tracking: -0.5)
                            .padding(.top, 7)
                        if let premise = card.premise {
                            TasteType.premise(premise, size: 11, lineSpacing: 2.8)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 13)
                    .padding(.bottom, 12)
                }
            }
            Spacer(minLength: 0)
            TastePlanKey(card: card, variant: .leaf, compact: metrics.compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The story card's separate Plan key: the label, then a bookmark. Planned: dark face, white ink.
struct TastePlanKey: View {
    enum Variant { case landscape, portrait, leaf }

    let card: TasteCard
    let variant: Variant
    var compact: Bool = false

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(\.kuroRoutes) private var routes

    private static let ink = Color(hex: "36433A")

    private var status: ListStatus? { library.entry(for: card.key)?.status }

    private var face: (fill: Color, border: Color) {
        switch variant {
        case .landscape: return (Color(hex: "F4F6F5"), Color(hex: "E0E5E1"))
        case .portrait: return (Color(hex: "F7F9F6"), Color(hex: "BCC5BE"))
        case .leaf: return (Color(hex: "FFFFFC"), Color(hex: "BEC5B8"))
        }
    }

    private var savedFace: Color { variant == .leaf ? Color(hex: "30352B") : Color(hex: "303932") }

    var body: some View {
        let status = status
        let action = TastePlanAction.action(for: status)
        let saved = status != nil
        let german = KuroLocale.isGerman
        Button {
            KuroAccessibility.impactHaptic(.light)
            TastePlan.perform(action, card: card, actions: libraryActions, routes: routes)
        } label: {
            HStack(spacing: 5) {
                Text(TastePageCopy.planLabel(medium: card.media.kind, status: status, german: german))
                    .font(.kuroCustom(variant == .leaf ? (compact ? 9 : 10) : 11, weight: .medium,
                                      relativeTo: .caption1, maxSize: 20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .light))
                    .frame(width: 26, height: 28)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(saved ? Color.white : Self.ink)
            .padding(.horizontal, variant == .leaf && compact ? 8 : 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(saved ? savedFace : face.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(saved ? savedFace : face.border, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // `box-shadow: inset 0 1px #fff` (the raised top edge), only on the light face.
                if !saved {
                    Rectangle().fill(Color.white).frame(height: 1).padding(.horizontal, 10).padding(.top, 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .kuroAnimation(KuroMotion.contact, value: saved)
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.97))
        .accessibilityLabel(Self.spokenLabel(action: action, title: card.media.title, german: german))
        .accessibilityAddTraits(status == .planning ? [.isSelected] : [])
    }

    static func spokenLabel(action: TastePlanAction, title: String, german: Bool) -> String {
        switch action {
        case .plan: return german ? "\(title) vormerken" : "Plan \(title)"
        case .unplan: return german ? "Vorgemerkt. \(title) wieder entfernen" : "Planned. Remove \(title) from Planned"
        case .edit: return german ? "\(title) ist auf deiner Liste. Listeneintrag bearbeiten"
                                  : "\(title) is on your list. Edit list entry"
        }
    }
}

// MARK: - Loading and footer

/// Loading: blocks in the story cards' shape with the travelling scrub line (branded state family).
private struct TasteStorySkeleton: View {
    let medium: MediaKind
    let metrics: TasteMetrics

    private var block: Color { Color.kuroCanvasQuiet }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.listSpacing) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(block).frame(width: 190, height: 24)
                .padding(.bottom, 1)
            if medium == .manga {
                HStack(alignment: .top, spacing: metrics.mangaColumnSpacing) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            Rectangle().fill(Color.white).aspectRatio(2 / 3, contentMode: .fit)
                                .overlay(Rectangle().strokeBorder(Color(hex: "D9DBD3"), lineWidth: 1))
                            line(width: 90, height: 9)
                            line(width: nil, height: 16)
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(block).frame(height: 44)
                        }
                    }
                }
            } else {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(alignment: .top, spacing: metrics.portraitCopyLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(block)
                            .frame(width: metrics.portraitArtWidth, height: 180)
                        VStack(alignment: .leading, spacing: 10) {
                            line(width: 80, height: 9)
                            line(width: nil, height: 18)
                            line(width: 120, height: 10)
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(block).frame(height: 44)
                        }
                        .padding(.vertical, 12)
                    }
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                }
            }
            KuroScrubLine().frame(maxWidth: 96)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroBrandedCopy.loadingLabel(german: KuroLocale.isGerman))
    }

    private func line(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(block)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// The page footer (`.app-end`): "Your pace. Your place." and the KURO mark.
struct TasteFooter: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(KuroLocale.text("Your pace. Your place.", "Dein Tempo. Dein Ort."))
            Spacer(minLength: 8)
            Text(verbatim: "KURO")
                .fontWeight(.bold)
                .tracking(2)
                .accessibilityHidden(true)
        }
        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 18))
        .foregroundStyle(Color.kuroMuted)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 28)
    }
}
