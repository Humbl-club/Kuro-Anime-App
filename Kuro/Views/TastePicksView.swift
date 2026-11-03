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
// shared with Discover) and the because-you rail; every card is a real title. Each shown pick is then
// read from the catalogue (`TasteCardDetails`, `CatalogStore`'s cached detail read) for what its rail
// row lacks: the premise (bundle rows carry no synopsis) and, for anime, the banner of the landscape
// card (because-you rows carry none). A premise is shown only where the catalogue has a real synopsis.
// The page waits at most a second for those reads before it shows the cards; later reads fill in.
// The story cards (`TasteStoryList`) are shared with the new-account Home (`HomeNewAccount`).

struct TastePicksView: View {
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(LibraryStore.self) private var library
    @Environment(NetworkMonitor.self) private var networkMonitor
    /// The picks' premise and banner (`TasteCardDetails`); nil in fixtures without one.
    @Environment(CatalogStore.self) private var catalog: CatalogStore?

    /// The selected medium, owned by the pager (`ContentView`) so its canvas and the header follow it.
    @Binding var medium: MediaKind

    init(medium: Binding<MediaKind>) {
        self._medium = medium
    }
    @State private var animePicks: [TasteCard] = []
    @State private var mangaPicks: [TasteCard] = []
    @State private var isLoading = true
    /// Per medium: the last load could not settle that medium's picks and nothing is on screen.
    @State private var animeFailed = false
    @State private var mangaFailed = false
    /// "A first favourite." is decided once (`TastePageCopy.latchNewAccount`): a Plan on this page
    /// never swaps the heading under the user's finger. It is cleared when the Library leaves `.loaded`
    /// (sign-out, account switch) and when the page is mounted again (the pager keeps the current page
    /// and its neighbours mounted, so it holds while the user stays near Taste).
    @State private var startedAsNewAccount: Bool?
    /// The Plan keys' writes, their double-tap guard and the result toast with Undo.
    @State private var plans = TastePlanController()

    private let cap = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ScrollView(.vertical, showsIndicators: false) {
                TastePageContent(
                    medium: $medium,
                    state: state,
                    newAccount: startedAsNewAccount ?? false,
                    switchArt: switchArt,
                    width: width,
                    retry: { Task { await load() } }
                )
            }
            .scrollDisabled(false)
            .background(TastePageContent.canvas(for: medium).ignoresSafeArea())
        }
        .tastePlanHost(plans)
        .task {
            startedAsNewAccount = nil
            latchNewAccount()
            await load()
        }
        .onChange(of: library.loadState) { _, state in
            // Leaving `.loaded` (sign-out, account switch, reload) ends the latch and the toast.
            if state != .loaded {
                startedAsNewAccount = nil
                plans.dismiss()
            }
            latchNewAccount()
        }
        .onChange(of: networkMonitor.reconnectionGeneration) { _, _ in
            guard networkMonitor.isConnected, animeFailed || mangaFailed else { return }
            Task { await load() }
        }
    }

    private func latchNewAccount() {
        startedAsNewAccount = TastePageCopy.latchNewAccount(current: startedAsNewAccount,
                                                            loaded: library.loadState == .loaded,
                                                            entryCount: library.allEntries.count)
    }

    private var picks: [TasteCard] { medium == .anime ? animePicks : mangaPicks }
    private var failed: Bool { medium == .anime ? animeFailed : mangaFailed }

    private var state: TastePageContent.State {
        if isLoading { return .loading }
        if failed { return .unavailable(offline: !networkMonitor.isConnected) }
        if picks.isEmpty { return .empty }
        return .cards(Array(picks.prefix(TastePicksCopy.visibleCount(newAccount: startedAsNewAccount ?? false))))
    }

    /// The selected medium word shows the first pick's artwork clipped into its letters, as Home's
    /// does with its lead title (LANE_AMENDMENTS 7: Taste follows Home); the solid word until it is known.
    private var switchArt: String? {
        picks.first?.media.imageURL
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
        await completePicks()
    }

    /// The catalogue's premises and the landscape banner (`TasteCardDetails`). The medium on screen
    /// waits up to `TasteCardDetails.waitLimit` so its cards usually show complete (no reflow); a slow
    /// read never holds the page on its skeleton, and whatever lands later fills in. The other medium
    /// fills in whenever its reads land.
    private func completePicks() async {
        let anime = animePicks, manga = mangaPicks
        let animeTask = Task { await TasteCardDetails.hydrate(anime, catalog: catalog) }
        let mangaTask = Task { await TasteCardDetails.hydrate(manga, catalog: catalog) }
        let visible = medium == .anime ? animeTask : mangaTask
        if await TasteCardDetails.finishes(visible, within: TasteCardDetails.waitLimit) {
            fill(await visible.value, medium: medium)
        }
        Task { fill(await animeTask.value, medium: .anime) }
        Task { fill(await mangaTask.value, medium: .manga) }
    }

    /// Completed cards replace the shown ones only while they are still the same picks.
    private func fill(_ cards: [TasteCard], medium: MediaKind) {
        switch medium {
        case .anime: if cards.map(\.id) == animePicks.map(\.id) { animePicks = cards }
        case .manga: if cards.map(\.id) == mangaPicks.map(\.id) { mangaPicks = cards }
        }
    }

    /// Writes each medium's choice only when the reads it depends on loaded (rulebook §9: a failed
    /// read never shows as the empty state). An unsettled medium keeps the picks already on screen
    /// and reports a failure only when it has none.
    private func apply(because: [BecauseYouCard]?, bundle: DiscoverBundle?) {
        let german = KuroLocale.isGerman
        let rows = because ?? []
        // The because-you rows carry no banner; a title the launch's bundle also holds lends its banner
        // to the landscape card (no extra read).
        let banners = TasteBanners.map(bundle)
        let animePersonal = open(rows.filter { $0.mediaType.uppercased() != "MANGA" }
            .map { TasteCard(because: $0).withBanner(banners[$0.mediaId]) })
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
    /// The artwork the selected medium word shows (the first pick's), nil for the solid word.
    var switchArt: String?
    let width: CGFloat
    var retry: () -> Void = {}

    /// The page canvas: the warm Home canvas for anime, the manga Home canvas for manga
    /// (`ref-taste-*-manga-390.png`; amendment 8, "Taste follows its reference").
    static func canvas(for medium: MediaKind) -> Color {
        medium == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome
    }

    @Environment(\.tasteGerman) private var germanOverride

    private var metrics: TasteMetrics { TasteMetrics(pageWidth: width) }
    private var german: Bool { germanOverride ?? KuroLocale.isGerman }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TasteOpening(medium: $medium, artURL: switchArt, metrics: metrics,
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

    /// The new-account decision, made once: nil until the Library has loaded, then fixed (a Plan on
    /// the page that adds the first title keeps "A first favourite."). The caller clears it when the
    /// Library leaves `.loaded` (sign-out, account switch) and on the next page visit.
    static func latchNewAccount(current: Bool?, loaded: Bool, entryCount: Int) -> Bool? {
        if let current { return current }
        guard loaded else { return nil }
        return isNewAccount(loaded: loaded, entryCount: entryCount)
    }

    /// The Plan key's words for a title in `status` (nil: not on the list).
    static func planLabel(medium: MediaKind, status: ListStatus?, german: Bool) -> String {
        switch status {
        case .planning?: return german ? "Geplant" : "Planned"  // the app's status word (Folio, Profile)
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
        case "Historical": return "Historisch"
        case "Music": return "Musik"
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

    /// How many cards the page shows: a new account sees the reference's two (anime one landscape and
    /// one portrait card, manga one row of two leaves, PROTOTYPE_SPEC.md §8.10); a busy account up to
    /// four.
    static func visibleCount(newAccount: Bool) -> Int {
        newAccount ? 2 : 4
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

    /// The card with what a catalogue read adds: `banner` when it has none, and the first sentence of
    /// `synopsis` as the premise when it has none (never the catalogue's placeholder). Existing data
    /// always stays.
    func hydrated(banner: String?, synopsis: String?) -> TasteCard {
        TasteCard(media: media, bannerURL: bannerURL ?? banner,
                  premise: premise ?? synopsis.flatMap { TastePicksCopy.storySentence($0) })
    }

    /// The same card with `banner` when it has none yet (the because-you rows carry no banner).
    func withBanner(_ banner: String?) -> TasteCard {
        guard bannerURL == nil, let banner else { return self }
        // `premise` is already one sentence; `storySentence` leaves it as it is.
        return TasteCard(media: media, bannerURL: banner, premise: premise)
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

/// The catalogue read that completes the shown picks (`CatalogStore.fetchAnimeById` / `fetchMangaById`,
/// cached in memory and on disk, so a revisit costs nothing and the detail page opens warm). A card
/// that already has its premise (and, for anime, its banner) is not read. A failed read keeps the
/// card as it is: no premise is ever invented.
@MainActor
enum TasteCardDetails {
    /// How long a page waits for the reads before it shows the cards as they are.
    static let waitLimit: Duration = .seconds(1)

    /// Whether `task` finishes within `limit`. Returns at the limit at the latest; the task itself keeps
    /// running either way (a task group would wait for it, since awaiting a task's value ignores
    /// cancellation).
    static func finishes<T>(_ task: Task<T, Never>, within limit: Duration) async -> Bool {
        let race = FirstAnswer()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            let timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                race.answer(false)
            }
            Task { @MainActor in
                _ = await task.value
                timer.cancel()
                race.answer(true)
            }
        }
    }

    /// Resumes its continuation once, with the first answer.
    private final class FirstAnswer {
        var continuation: CheckedContinuation<Bool, Never>?
        func answer(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    static func hydrate(_ cards: [TasteCard], catalog: CatalogStore?) async -> [TasteCard] {
        guard let catalog, !cards.isEmpty else { return cards }
        return await withTaskGroup(of: (Int, TasteCard).self) { group in
            for (index, card) in cards.enumerated() {
                group.addTask { @MainActor in (index, await hydrate(card, catalog: catalog)) }
            }
            var filled = cards
            for await (index, card) in group { filled[index] = card }
            return filled
        }
    }

    private static func hydrate(_ card: TasteCard, catalog: CatalogStore) async -> TasteCard {
        switch card.media.kind {
        case .anime:
            guard card.premise == nil || card.bannerURL == nil else { return card }
            guard let anime = (try? await catalog.fetchAnimeById(card.media.id)) ?? nil else { return card }
            return card.hydrated(banner: anime.bannerImage,
                                 synopsis: anime.hasMeaningfulSynopsis ? anime.displayDescription : nil)
        case .manga:
            guard card.premise == nil else { return card }
            guard let manga = (try? await catalog.fetchMangaById(card.media.id)) ?? nil else { return card }
            return card.hydrated(banner: nil, synopsis: manga.hasMeaningfulSynopsis ? manga.displayDescription : nil)
        }
    }
}

/// Anime banners the launch's Discover bundle already holds, by AniList id, across every anime rail
/// (the first non-empty banner wins). Lets a because-you pick that the bundle also carries become the
/// landscape card without a second read; a title the bundle does not hold stays a portrait card.
nonisolated enum TasteBanners {
    static func map(_ bundle: DiscoverBundle?) -> [Int: String] {
        guard let rails = bundle?.anime else { return [:] }
        var result: [Int: String] = [:]
        for card in rails.essentials + rails.classics + rails.newToYou + rails.trending + rails.topRated
            + rails.newlyAdded + rails.airingToday + rails.currentSeason {
            guard result[card.id] == nil,
                  let banner = card.bannerImage?.trimmingCharacters(in: .whitespaces), !banner.isEmpty else { continue }
            result[card.id] = banner
        }
        return result
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

/// What one tap on a story card's Plan key does: plan a title that is not on the list, take a bare
/// plan off again (planned, no progress, no notes, rating or verdict: nothing a removal would lose),
/// or open the list editor for anything else (another status, or a plan the user has since added to;
/// never removed from here).
nonisolated enum TastePlanAction: Equatable {
    case plan, unplan, edit

    static func action(for entry: LibraryEntry?) -> TastePlanAction {
        guard let entry else { return .plan }
        return isBarePlan(entry) ? .unplan : .edit
    }

    static func isBarePlan(_ entry: LibraryEntry) -> Bool {
        entry.status == .planning
            && entry.progress == 0
            && (entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && entry.rating == nil
            && entry.verdict == nil
    }
}

/// The Plan key's result toast, EN/DE (PROTOTYPE_SPEC.md §3.4, §7.1 "Toasts").
nonisolated enum TastePlanCopy {
    enum Result: Equatable { case added, removed, undone, failed }

    static func message(_ result: Result, german: Bool) -> String {
        switch result {
        case .added: return german ? "Zu deiner Liste hinzugefügt." : "Added to your list."
        case .removed: return german ? "Von deiner Liste entfernt." : "Removed from your list."
        case .undone: return german ? "Rückgängig gemacht." : "Undone."
        case .failed: return german ? "Nicht gespeichert. Deine Liste ist unverändert." : "Not saved. Your list is unchanged."
        }
    }

    static func undo(german: Bool) -> String { german ? "Rückgängig" : "Undo" }
    static func dismiss(german: Bool) -> String { german ? "Schließen" : "Dismiss" }
}

/// The Plan keys' writer for one page (Taste, or the new-account Home): plans through
/// `LibraryActions.save(_:status: .planning)`, takes a bare plan off through `LibraryActions.remove`,
/// ignores a second tap while the title's write is in flight, and shows the result toast with Undo.
/// Undo acts only for the account that made the change (`AccountSessionCoordinator.isCurrent`) and
/// only while the title is still in the state the change left it in.
@MainActor
@Observable
final class TastePlanController {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let undo: Undo?
    }

    struct Undo: Equatable {
        enum Step: Equatable { case remove, replan }
        let key: MediaKey
        let step: Step
        let account: AccountContext
    }

    /// The toast on screen, if any.
    private(set) var toast: Toast?
    /// Titles whose Plan write (or its Undo) is in flight.
    private(set) var inFlight: Set<MediaKey> = []

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let holdSeconds: Double
    @ObservationIgnored private let assistiveTechnologyRunning: @MainActor () -> Bool

    init(holdSeconds: Double = 4,
         assistiveTechnologyRunning: @escaping @MainActor () -> Bool = KuroToastHold.assistiveTechnologyRunning) {
        self.holdSeconds = holdSeconds
        self.assistiveTechnologyRunning = assistiveTechnologyRunning
    }

    /// Runs one Plan key tap. Returns the write's task (nil for the editor, a tap while the title's
    /// write is in flight, or no session).
    @discardableResult
    func tap(_ card: TasteCard, library: LibraryStore, actions: LibraryActions, routes: KuroRoutes,
             german: Bool) -> Task<Void, Never>? {
        let key = card.key
        switch TastePlanAction.action(for: library.entry(for: key)) {
        case .edit:
            routes.presentTrackingEditor(TrackingEditorRequest(media: card.media))
            return nil
        case .plan:
            return write(key, step: .plan, actions: actions, german: german)
        case .unplan:
            return write(key, step: .remove, actions: actions, german: german)
        }
    }

    /// The toast's Undo: reverses the change it reports, once.
    @discardableResult
    func undo(library: LibraryStore, actions: LibraryActions, german: Bool) -> Task<Void, Never>? {
        guard let undo = toast?.undo else { return nil }
        toast = nil
        guard actions.accountSession.isCurrent(undo.account) else { return nil }
        switch undo.step {
        case .remove:
            // Only the bare plan this toast reported; anything the user has added since stays.
            guard let entry = library.entry(for: undo.key), TastePlanAction.isBarePlan(entry) else { return nil }
            return write(undo.key, step: .undoRemove, actions: actions, german: german)
        case .replan:
            guard library.entry(for: undo.key) == nil else { return nil }
            return write(undo.key, step: .undoPlan, actions: actions, german: german)
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        toast = nil
    }

    private enum WriteStep { case plan, remove, undoPlan, undoRemove }

    private func write(_ key: MediaKey, step: WriteStep, actions: LibraryActions, german: Bool) -> Task<Void, Never>? {
        guard let account = actions.accountSession.current, !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        return Task.immediate { @MainActor [weak self] in
            let outcome: LibraryOutcome
            switch step {
            case .plan, .undoPlan: outcome = await actions.save(key, status: .planning)
            case .remove, .undoRemove: outcome = await actions.remove(key)
            }
            guard let self else { return }
            self.inFlight.remove(key)
            // A write that outlives its account shows nothing to the next account.
            guard actions.accountSession.isCurrent(account) else { return }
            guard case .applied = outcome else {
                self.show(TastePlanCopy.message(.failed, german: german), undo: nil)
                return
            }
            switch step {
            case .plan:
                self.show(TastePlanCopy.message(.added, german: german),
                          undo: Undo(key: key, step: .remove, account: account))
            case .remove:
                self.show(TastePlanCopy.message(.removed, german: german),
                          undo: Undo(key: key, step: .replan, account: account))
            case .undoPlan, .undoRemove:
                self.show(TastePlanCopy.message(.undone, german: german), undo: nil)
            }
        }
    }

    /// Shows one result. With VoiceOver or Switch Control on it waits for × or the next result
    /// (`KuroToastHold`); otherwise it leaves after the hold.
    func show(_ message: String, undo: Undo?) {
        dismissTask?.cancel()
        let toast = Toast(message: message, undo: undo)
        self.toast = toast
        guard !assistiveTechnologyRunning() else { dismissTask = nil; return }
        let hold = holdSeconds
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self, self.toast?.id == toast.id else { return }
            self.toast = nil
        }
    }
}

/// The prototype toast (§3.4): `#282f2bf5`, 12 pt white text, radius 18, padding 5/5/5/14, inset
/// 13/13/12 from the page foot, then "Undo" and a dismiss ×. Shared by the Taste Plan keys and the
/// Home +1 (`HomeProgressToasts`), so every result toast reads the same.
struct TastePlanToastView: View {
    let message: String
    let showsUndo: Bool
    let german: Bool
    let onUndo: () -> Void
    let onDismiss: () -> Void

    init(message: String, showsUndo: Bool, german: Bool, onUndo: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.message = message
        self.showsUndo = showsUndo
        self.german = german
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    init(toast: TastePlanController.Toast, german: Bool, onUndo: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.init(message: toast.message, showsUndo: toast.undo != nil, german: german,
                  onUndo: onUndo, onDismiss: onDismiss)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(message)
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 22))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsUndo {
                Button(action: onUndo) {
                    Text(TastePlanCopy.undo(german: german))
                        .font(.kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 22))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle(pressedScale: 0.97))
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle(pressedScale: 0.97))
            .accessibilityLabel(TastePlanCopy.dismiss(german: german))
        }
        .padding(.leading, 14)
        .padding([.top, .bottom, .trailing], 5)
        .background(Color(hex: "282F2B", opacity: Double(0xF5) / 255),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: "18241C", opacity: Double(0x30) / 255), radius: 15, y: 8)
        .padding(.horizontal, 13)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }
}

/// Installs a page's Plan controller for the story cards below it and draws its toast at the foot of
/// the modified view (put it outside the page's ScrollView so the toast stays put).
struct TastePlanHost: ViewModifier {
    let controller: TastePlanController

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(\.tasteGerman) private var germanOverride

    func body(content: Content) -> some View {
        let german = germanOverride ?? KuroLocale.isGerman
        content
            .environment(controller)
            .overlay(alignment: .bottom) {
                if let toast = controller.toast {
                    TastePlanToastView(toast: toast, german: german,
                                       onUndo: { controller.undo(library: library, actions: actions, german: german) },
                                       onDismiss: { controller.dismiss() })
                        .id(toast.id)
                        .transition(.opacity)
                        .onAppear { AccessibilityNotification.Announcement(toast.message).post() }
                }
            }
            .kuroAnimation(KuroMotion.contact, value: controller.toast?.id)
    }
}

extension View {
    func tastePlanHost(_ controller: TastePlanController) -> some View {
        modifier(TastePlanHost(controller: controller))
    }
}

extension EnvironmentValues {
    /// Fixture override for the first-run lane's words (nil: the reader's language, `KuroLocale`).
    @Entry var tasteGerman: Bool? = nil
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
    /// The manga leaf's frame height: 2 : 3 on the prototype's unsnapped column (`164.5px` at 390, so
    /// 246.75), on whole points as the browser draws it (246), the same for both columns. Nil before
    /// the page is measured.
    var leafArtHeight: CGFloat? {
        let column = (pageWidth - paperGutter * 2 - mangaColumnSpacing) / 2
        return pageWidth > 0 && column > 0 ? (column * 1.5).rounded(.down) : nil
    }
}

/// The leaf frame at `TasteMetrics.leafArtHeight`, or 2 : 3 of its width when there is none
/// (accessibility sizes, where a leaf takes the full width).
private struct TasteLeafArtSize: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(maxWidth: .infinity).frame(height: height)
        } else {
            content.aspectRatio(2 / 3, contentMode: .fit)
        }
    }
}

// MARK: - Opening block

/// The medium words over the hairline, then the kicker and the right-aligned opening line.
struct TasteOpening: View {
    @Binding var medium: MediaKind
    /// The artwork clipped into the selected word (the first pick's), nil for the solid word.
    let artURL: String?
    let metrics: TasteMetrics
    let kicker: String
    let headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Home's switch (art-filled selected word, two-column grid, hairline and rule).
            KuroPosterMediumSwitch(selection: medium,
                                   contentWidth: max(0, metrics.pageWidth - metrics.openingGutter * 2),
                                   onSelect: { medium = $0 }) {
                KuroArtWordFill(raw: artURL)
            }
            // The prototype's row (kicker left, line right); stacked when the two do not fit side by
            // side (large text sizes, long German words), so the kicker is never cut.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    kickerText
                    Spacer(minLength: 8)
                    headlineText.multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    kickerText.fixedSize(horizontal: false, vertical: true)
                    headlineText.multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, metrics.openingGutter)
        .padding(.top, 7)
        .padding(.bottom, 18)
    }

    private var kickerText: some View {
        Text(kicker)
            .font(.kuroCustom(metrics.compact ? 8 : 9, relativeTo: .caption2, maxSize: 16))
            .tracking(1.05)
            .foregroundStyle(Color(hex: "666C68"))
            .lineLimit(1)
    }

    private var headlineText: some View {
        Text(headline)
            .font(.kuroCustom(metrics.compact ? 13 : 14, weight: .semibold, relativeTo: .subheadline, maxSize: 24))
            .tracking(-0.3)
            .foregroundStyle(Color.kuroInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The section heading ("Your next story."): SF 24/26.4 w550 −0.85 (manga w500 −0.65, at most 210 wide).
/// SwiftUI has no w550: anime takes `.semibold` (the system's nearest heavier weight; the reference's
/// glyphs measure wider than w500), manga keeps `.medium`.
///
/// Lines follow each other at the prototype's 1.1 pitch (26.4 at 24 pt, on whole points: 26) while
/// every word keeps SF's own line box (FR-C). SwiftUI `Text` ignores a negative line spacing, and an
/// exact line height clips the last line's descenders ("story." loses the foot of its y), so the
/// words are laid out by `TasteHeadingLines`, which wraps them as the browser does.
struct TasteSectionHeading: View {
    let title: String
    let medium: MediaKind
    let metrics: TasteMetrics
    /// Nil: the section's own 32 pt top margin.
    var top: CGFloat? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var baseSize: CGFloat { metrics.compact ? 22 : 24 }
    private var weight: Font.Weight { medium == .manga ? .medium : .semibold }
    private var tracking: CGFloat { medium == .manga ? -0.65 : -0.85 }
    private var size: CGFloat { min(KuroTypeScale.current.scaled(baseSize, relativeTo: .title2), 40) }

    var body: some View {
        _ = dynamicTypeSize
        let font = UIFont.systemFont(ofSize: size, weight: weight == .medium ? .medium : .semibold)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width + tracking
        return TasteHeadingLines(wordSpacing: space, pitch: (size * 1.1).rounded()) {
            ForEach(Array(title.split(separator: " ").enumerated()), id: \.offset) { _, word in
                Text(String(word))
                    .font(.kuroCustom(baseSize, weight: weight, relativeTo: .title2, maxSize: 40))
                    .tracking(tracking)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: medium == .manga ? 210 : .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, top ?? metrics.headingTop)
        // 17 in CSS under a 26.4 line box; SF's last line box is 2.24 pt taller, and 16⅓ puts the
        // cards on the reference's row under one line and under two (measured at 1 px = 1 pt).
        .padding(.bottom, 17 - 2.0 / 3.0)
    }
}

/// Words left to right, wrapping when the next one does not fit (the browser's greedy wrap), with
/// each line `pitch` below the one before. The block is as tall as its last line's own box, so a
/// single-line heading keeps SF's line box and nothing is clipped.
struct TasteHeadingLines: Layout {
    let wordSpacing: CGFloat
    let pitch: CGFloat

    private func positions(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], proposals: [ProposedViewSize], size: CGSize) {
        var points: [CGPoint] = [], proposals: [ProposedViewSize] = []
        var x: CGFloat = 0, row = 0, lastHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let natural = subview.sizeThatFits(.unspecified)
            let proposal = natural.width > width ? ProposedViewSize(width: width, height: nil) : ProposedViewSize(natural)
            let size = natural.width > width ? subview.sizeThatFits(proposal) : natural
            if x > 0 && x + size.width > width {
                x = 0
                row += 1
            }
            points.append(CGPoint(x: x, y: CGFloat(row) * pitch))
            proposals.append(proposal)
            x += size.width + wordSpacing
            widest = max(widest, x - wordSpacing)
            lastHeight = size.height
        }
        return (points, proposals, CGSize(width: widest, height: CGFloat(row) * pitch + lastHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .greatestFiniteMagnitude
        return positions(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = positions(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + laid.points[index].x, y: bounds.minY + laid.points[index].y),
                          anchor: .topLeading, proposal: laid.proposals[index])
        }
    }
}

// MARK: - Story list (shared with HomeNewAccount)

/// The story cards. Anime: the first card with a banner is the landscape card, the others portrait
/// cards. Manga: a two-column grid of framed covers.
struct TasteStoryList: View {
    let cards: [TasteCard]
    let medium: MediaKind
    let metrics: TasteMetrics

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if medium == .manga && dynamicTypeSize.isAccessibilitySize {
            // Accessibility sizes: one leaf per row, so titles and keys keep the full width.
            VStack(alignment: .leading, spacing: 28) {
                ForEach(cards) { card in
                    TasteLeafCard(card: card, metrics: metrics)
                }
            }
        } else if medium == .manga {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { index in
                    TasteLeafRowLayout(spacing: metrics.mangaColumnSpacing) {
                        TasteLeafCard(card: cards[index], metrics: metrics)
                        if index + 1 < cards.count {
                            TasteLeafCard(card: cards[index + 1], metrics: metrics)
                        } else {
                            Color.clear
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

/// A row of two manga leaves on whole points, as the browser snaps the prototype's `164.5px 164.5px`
/// grid (165 and 164 at 390): the first column takes the extra half point, so both frames' borders
/// fall on the pixel grid instead of straddling it. Both leaves take the row's height, so their Plan
/// keys stay level.
struct TasteLeafRowLayout: Layout {
    let spacing: CGFloat

    func columns(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let lead = max(0, ((total - spacing) / 2).rounded(.up))
        return (lead, max(0, total - spacing - lead))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 346
        let (lead, trail) = columns(total)
        var height: CGFloat = 0
        for (subview, width) in zip(subviews, [lead, trail]) {
            height = max(height, subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (lead, trail) = columns(bounds.width)
        for (index, subview) in subviews.prefix(2).enumerated() {
            let x = index == 0 ? bounds.minX : bounds.minX + lead + spacing
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: index == 0 ? lead : trail, height: bounds.height))
        }
    }
}

/// Story-card text roles (PROTOTYPE_SPEC.md §4 "Taste").
private enum TasteType {
    /// The kind kicker and the premise are a step darker than the prototype's `#626b63` / `#575c59`:
    /// iOS draws the 8–12 pt strokes thinner than the browser the references were captured in (a 3x
    /// device capture, block-averaged, carries about 20% less ink than the reference at the same
    /// colour), so the slightly deeper ink keeps the line's weight (FIDELITY_REVIEW round 3).
    static let kindInk = Color(hex: "5A635B")
    static let premiseInk = Color(hex: "4F5451")

    static func kind(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        Text(text)
            .font(.kuroCustom(size, relativeTo: .caption2, maxSize: 16))
            .tracking(tracking)
            .foregroundStyle(kindInk)
            .lineLimit(1)
    }

    /// Titles are w550 in every card: `.semibold`, the system's nearest weight that keeps the
    /// reference's glyph width (w500 sets them about 2% narrow).
    static func title(_ text: String, size: CGFloat, tracking: CGFloat) -> some View {
        Text(KuroCardText.sanitizeTitleForCard(text))
            .font(.kuroCustom(size, weight: .semibold, relativeTo: .title2, maxSize: size * 1.6))
            .tracking(tracking)
            .foregroundStyle(Color.kuroInk)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func premise(_ text: String, size: CGFloat, lineSpacing: CGFloat) -> some View {
        TastePremiseText(text: text, baseSize: size, lineSpacing: lineSpacing, ink: UIColor(premiseInk), lineLimit: 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A premise wrapped as the prototype's browser wraps it: each line takes every word that fits.
/// iOS's standard line-break strategy pushes a word down to avoid a one-word last line ("… in each /
/// other's lives."), which SwiftUI `Text` cannot turn off; a label with `lineBreakStrategy = []` sets
/// "… in each other's / lives." on the same 29ch measure (FIDELITY_REVIEW FR-B). Same face, size,
/// scaling (`KuroTypeScale`, footnote, at most 1.8 ×), line spacing and ink as the `Text` it replaces.
struct TastePremiseText: UIViewRepresentable {
    let text: String
    let baseSize: CGFloat
    let lineSpacing: CGFloat
    let ink: UIColor
    let lineLimit: Int

    /// Re-sets the label when the text size changes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.lineBreakStrategy = []
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        _ = dynamicTypeSize
        label.attributedText = Self.attributed(text, size: fontSize, lineSpacing: lineSpacing, ink: ink)
        label.numberOfLines = lineLimit
        label.lineBreakMode = .byTruncatingTail
        label.lineBreakStrategy = []
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 10_000
        label.preferredMaxLayoutWidth = width
        let fit = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ceil(fit.width), height: ceil(fit.height))
    }

    private var fontSize: CGFloat {
        min(KuroTypeScale.current.scaled(baseSize, relativeTo: .footnote), baseSize * 1.8)
    }

    static func attributed(_ text: String, size: CGFloat, lineSpacing: CGFloat, ink: UIColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        style.lineBreakStrategy = []
        return NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: ink,
                                                             .paragraphStyle: style])
    }
}

/// The artwork inside a story card (cover or banner), on the prototype's `#f0f0ed` well.
private struct TasteArt: View {
    let url: String?
    var fill: Bool = false
    /// The well behind a contained cover: `#f0f0ed` on the anime cards, white inside the manga leaf.
    var well: Color = Color(hex: "F0F0ED")

    var body: some View {
        well
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
    @Environment(\.tasteGerman) private var germanOverride

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
        .accessibilityHint((germanOverride ?? KuroLocale.isGerman) ? "Öffnet die Details" : "Opens details")
        .accessibilityAddTraits(.isButton)
    }
}

/// The wide anime card: banner over the copy, the Plan key across the foot.
private struct TasteLandscapeCard: View {
    let card: TasteCard
    let metrics: TasteMetrics

    @Environment(\.tasteGerman) private var germanOverride
    /// `max-width: 29ch` at 12 pt, growing with the premise's text size.
    @ScaledMetric(relativeTo: .footnote) private var premiseWidth: CGFloat = 245

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TasteOpenButton(card: card) {
                VStack(alignment: .leading, spacing: 0) {
                    TasteArt(url: card.bannerURL ?? card.media.imageURL, fill: true)
                        .aspectRatio(2.8, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        if let kind = TastePageCopy.kind(format: card.media.formatRaw, genres: card.media.genres,
                                                         german: germanOverride ?? KuroLocale.isGerman) {
                            TasteType.kind(kind, size: 8, tracking: 0.5)
                        }
                        TasteType.title(card.media.title, size: 26, tracking: -0.6)
                            .padding(.top, 6)
                        if let premise = card.premise {
                            TasteType.premise(premise, size: 12, lineSpacing: 3.6)
                                .frame(maxWidth: premiseWidth, alignment: .leading)
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

/// The portrait anime card: the cover beside the copy, the Plan key under the copy. At accessibility
/// text sizes the cover sits above the copy so the title and the key keep the card's full width.
private struct TastePortraitCard: View {
    let card: TasteCard
    let metrics: TasteMetrics

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.tasteGerman) private var germanOverride

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    art
                    copy.padding(.horizontal, 4)
                    TastePlanKey(card: card, variant: .portrait, compact: metrics.compact)
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    art
                    VStack(alignment: .leading, spacing: 0) {
                        copy.padding(.trailing, 9)
                        Spacer(minLength: 12)
                        TastePlanKey(card: card, variant: .portrait, compact: metrics.compact)
                            .padding(.trailing, 4)
                            .padding(.bottom, 4)
                    }
                    .padding(.leading, metrics.portraitCopyLeading)
                    .frame(minHeight: 180)
                }
            }
        }
        .padding(8)
        .background { TasteCardFace() }
    }

    private var art: some View {
        TasteOpenButton(card: card) {
            TasteArt(url: card.media.imageURL)
                .frame(width: metrics.portraitArtWidth, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        // The copy is the same open target; VoiceOver hears the title once.
        .accessibilityHidden(true)
    }

    private var copy: some View {
        TasteOpenButton(card: card) {
            VStack(alignment: .leading, spacing: 0) {
                if let kind = TastePageCopy.kind(format: card.media.formatRaw, genres: card.media.genres,
                                                 german: germanOverride ?? KuroLocale.isGerman) {
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
        }
    }
}

/// The white story-card face and its soft drop (`0 4px 14px -11px #14222540`), behind the content so
/// the text never carries the shadow. The −11 spread is a shadow cast by a shape 11 pt smaller on
/// every side (blur 14, so radius 7), so the drop shows under the card only, never at its sides.
private struct TasteCardFace: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.white)
                .padding(11)
                .shadow(color: Color(hex: "142225", opacity: Double(0x40) / 255), radius: 7, y: 4)
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.white)
        }
    }
}

/// The manga leaf: a framed cover on white paper, the copy, then the Plan key.
private struct TasteLeafCard: View {
    let card: TasteCard
    let metrics: TasteMetrics

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Environment(\.tasteGerman) private var germanOverride

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TasteOpenButton(card: card) {
                VStack(alignment: .leading, spacing: 0) {
                    // `.story-art`: white, a 1 pt #d9dbd3 border, then 9 pt padding (the border is drawn
                    // inside the frame, so the cover sits 10 pt in), the cover contained on white.
                    TasteArt(url: card.media.imageURL, well: .white)
                        .padding(10)
                        .modifier(TasteLeafArtSize(height: dynamicTypeSize.isAccessibilitySize ? nil : metrics.leafArtHeight))
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color(hex: "D9DBD3"), lineWidth: 1))
                        .background(alignment: .topLeading) {
                            // The leaf behind the cover (`#fafbf6 2px 2px 0 -1px, #e1e3da 2px 2px 0 0`):
                            // a 1 pt light line against the border, then the 1 pt #e1e3da edge.
                            ZStack {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(hex: "E1E3DA"))
                                    .offset(x: 2, y: 2)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(hex: "FAFBF6"))
                                    .padding(1)
                                    .offset(x: 2, y: 2)
                            }
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        if let kind = TastePageCopy.kind(format: card.media.formatRaw, genres: card.media.genres,
                                                         german: germanOverride ?? KuroLocale.isGerman) {
                            TasteType.kind(kind, size: 9, tracking: 0.2)
                        }
                        // SF's own line boxes are shorter than the prototype's (kind 10.7 against 12.6,
                        // premise lines 13.1 against 15.95): the copy starts 14 pt under the frame (13 in
                        // CSS) and the key sits 14 pt under the copy (12), so the kicker, title, premise
                        // and key land on the reference's rows (measured).
                        TasteType.title(card.media.title, size: metrics.compact ? 18 : 20, tracking: -0.5)
                            .padding(.top, 7)
                        if let premise = card.premise {
                            TasteType.premise(premise, size: 11, lineSpacing: 2.8)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
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
    @Environment(\.tasteGerman) private var germanOverride
    /// The page's Plan controller (`tastePlanHost`); a key outside any host keeps its own, and its
    /// result goes to the app banner instead (no Undo there).
    @Environment(TastePlanController.self) private var hostController: TastePlanController?
    @Environment(BannerCenter.self) private var banner: BannerCenter?
    /// The root pager's tap guard: a horizontal swipe that starts on the key must not plan or unplan.
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @State private var localController = TastePlanController()

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
        let action = TastePlanAction.action(for: library.entry(for: card.key))
        let saved = status != nil
        let german = germanOverride ?? KuroLocale.isGerman
        let controller = hostController ?? localController
        Button {
            guard Self.acceptsTap(suppressCardTaps: suppressCardTaps) else { return }
            KuroAccessibility.impactHaptic(.light)
            controller.tap(card, library: library, actions: libraryActions, routes: routes, german: german)
        } label: {
            HStack(spacing: 5) {
                Text(TastePageCopy.planLabel(medium: card.media.kind, status: status, german: german))
                    .font(.kuroCustom(variant == .leaf ? (compact ? 9 : 10) : 11, weight: .medium,
                                      relativeTo: .caption1, maxSize: 20))
                    .lineLimit(1)
                    // The compact leaf key (98 pt in a detail More-like-this rail, 84–96 pt in Discover's
                    // index) gives its label more room so "Plan to watch" never truncates.
                    .minimumScaleFactor(variant == .leaf && compact ? 0.7 : 0.85)
                Spacer(minLength: variant == .leaf && compact ? 2 : 4)
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .light))
                    .frame(width: variant == .leaf && compact ? 18 : 26, height: 28)
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
        .onChange(of: localController.toast?.id) { _, _ in
            guard hostController == nil, let message = localController.toast?.message else { return }
            banner?.show(message)
        }
    }

    /// The key writes to the library, so it honours the pager's tap suppression like every card tap
    /// (the `.edit` route is gated again by `KuroPagerTapGate`; plan / unplan are not routes).
    static func acceptsTap(suppressCardTaps: Bool) -> Bool { !suppressCardTaps }

    static func spokenLabel(action: TastePlanAction, title: String, german: Bool) -> String {
        switch action {
        case .plan: return german ? "\(title) vormerken" : "Plan \(title)"
        case .unplan: return german ? "Geplant. \(title) aus Geplant entfernen" : "Planned. Remove \(title) from Planned"
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

    /// Black at 0.08: visible on the white story cards and on both canvases (`kuroCanvasQuiet` vanished
    /// on the manga canvas, #F6F6F6 on #F5F5F3).
    private var block: Color { Color.kuroBlack08 }

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
    @Environment(\.tasteGerman) private var germanOverride

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text((germanOverride ?? KuroLocale.isGerman) ? "Dein Tempo. Dein Ort." : "Your pace. Your place.")
            Spacer(minLength: 8)
            Text(verbatim: "KURO")
                .fontWeight(.bold)
                .tracking(2)
                .accessibilityHidden(true)
        }
        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 18))
        // A step deeper than `kuroMuted` (#696c6b), for the same reason as `TasteType.premiseInk`.
        .foregroundStyle(Color(hex: "606362"))
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 28)
    }
}
