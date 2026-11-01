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
    /// "A first favourite." is decided once per visit (`TastePageCopy.latchNewAccount`): a Plan on
    /// this page never swaps the heading under the user's finger.
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
                    material: switchMaterial,
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
    var material: ArtworkMaterial?
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

    init(holdSeconds: Double = 4) {
        self.holdSeconds = holdSeconds
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

    private func show(_ message: String, undo: Undo?) {
        dismissTask?.cancel()
        let toast = Toast(message: message, undo: undo)
        self.toast = toast
        let hold = holdSeconds
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self, self.toast?.id == toast.id else { return }
            self.toast = nil
        }
    }
}

/// The prototype toast (§3.4): `#282f2bf5`, 12 pt white text, radius 18, padding 5/5/5/14, inset
/// 13/13/12 from the page foot, then "Undo" and a dismiss ×.
struct TastePlanToastView: View {
    let toast: TastePlanController.Toast
    let german: Bool
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(toast.message)
                .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 22))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.undo != nil {
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

/// The section heading ("Your next story."): SF 24 w550 −0.85 (manga w500 −0.65, at most 210 wide;
/// SwiftUI has no w550, so both media use `.medium`, w500).
struct TasteSectionHeading: View {
    let title: String
    let medium: MediaKind
    let metrics: TasteMetrics
    /// Nil: the section's own 32 pt top margin.
    var top: CGFloat? = nil

    var body: some View {
        Text(title)
            .font(.kuroCustom(metrics.compact ? 22 : 24, weight: .medium, relativeTo: .title2, maxSize: 40))
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

    @Environment(\.tasteGerman) private var germanOverride

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
                                                         german: germanOverride ?? KuroLocale.isGerman) {
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
    @Environment(\.tasteGerman) private var germanOverride
    /// The page's Plan controller (`tastePlanHost`); a key outside any host keeps its own, and its
    /// result goes to the app banner instead (no Undo there).
    @Environment(TastePlanController.self) private var hostController: TastePlanController?
    @Environment(BannerCenter.self) private var banner: BannerCenter?
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
            KuroAccessibility.impactHaptic(.light)
            controller.tap(card, library: library, actions: libraryActions, routes: routes, german: german)
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
        .onChange(of: localController.toast?.id) { _, _ in
            guard hostController == nil, let message = localController.toast?.message else { return }
            banner?.show(message)
        }
    }

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
        .foregroundStyle(Color.kuroMuted)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 28)
    }
}
