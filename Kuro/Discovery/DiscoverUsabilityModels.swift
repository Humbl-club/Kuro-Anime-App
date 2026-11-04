import Foundation
import KuroCore
import KuroLibrary

// MARK: - Discover usability (2026-11-04): data contracts and pure rules
// Value types and rules of the Discover contract R2 / R5 / R6 (spec
// docs/superpowers/specs/2026-11-04-discover-usability-design.md, "Data contracts"). Nothing here
// performs I/O: `DiscoveryStore` (franchise ids, mood pages, See all pages) and `TasteStore`
// (Not interested / Seen it memory) feed them and the views render the result.
//
// Backend (prepared, NOT deployed: supabase/prepared-migrations/20261104100000_discover_usability_v1.sql):
//   media_franchise_ids_v1(p_anime_ids, p_manga_ids)                      -> (media_type, media_id, franchise_id)
//   discover_section_page_v1(p_section, p_media_type, p_sort, p_format,
//                            p_length, p_status, p_limit, p_offset)       -> DiscoverPageRow
//   discover_mood_v1(p_mood, p_media_type, p_limit, p_offset)            -> DiscoverPageRow
// Live today (no deployment needed): the caller's own `taste_signal_events` rows (RLS select-own)
// and `record_taste_deck_signal` (the deck's writer, used through `TasteStore.submitSignal`).

// MARK: Feedback (R5)

/// The two "this is not for me right now" answers a Discover card offers in its long-press menu.
///
/// Each is stored as one Taste deck signal, so the Taste deck and Discover share one memory per
/// title (`record_taste_deck_signal` keeps one deck signal per user and title).
enum DiscoverFeedback: String, Codable, Sendable, CaseIterable {
    case notInterested = "not_interested"
    case seenIt = "seen_it"

    /// The deck action each answer is stored as. ONE constant on purpose (lead decision point):
    /// Not interested is the deck's own "not for me" (`.skip`, strength -0.45, teaches Taste, R5),
    /// NOT the deck's `.pass` ("dealt, undecided": strength 0, excluded from the profile, so it would
    /// teach nothing; 20260731090000). Seen it is the deck's "I know this" (`.known`, +0.25).
    var deckAction: TasteDeckAction {
        switch self {
        case .notInterested: return .skip
        case .seenIt: return .known
        }
    }

    /// The `taste_signal_events.event_type` of `deckAction`.
    var eventType: String { "deck_" + deckAction.rawValue }

    /// The answer a stored deck event means on Discover; nil for events that do not hide a title
    /// ('deck_love' lands on the list instead, 'deck_pass' is an undecided swipe and must not
    /// vanish from Discover).
    init?(eventType: String) {
        guard let match = Self.allCases.first(where: { $0.eventType == eventType }) else { return nil }
        self = match
    }

    /// The answer a deck action means on Discover (nil: not hiding).
    init?(deckAction: TasteDeckAction) {
        guard let match = Self.allCases.first(where: { $0.deckAction == deckAction }) else { return nil }
        self = match
    }

    /// How far back a stored answer still hides a title (same window as the server readers).
    static let memoryWindow: TimeInterval = 365 * 24 * 60 * 60
}

/// What `TasteStore.recordDiscoverFeedback` returns: everything its Undo needs (R4).
struct DiscoverFeedbackReceipt: Equatable, Sendable {
    let key: MediaKey
    let feedback: DiscoverFeedback
    /// The title's deck signal before this answer (re-sent by Undo; nil: Undo retracts).
    let priorAction: TasteDeckAction?
    /// The account the answer was recorded for (Undo of an ended account does nothing).
    let accountUserId: String
}

/// Storage form of a `MediaKey` (the package type is not `Codable`).
nonisolated struct DiscoverMediaRef: Codable, Hashable, Sendable {
    let kind: String
    let id: Int

    init(_ key: MediaKey) {
        kind = key.kind.rawValue
        id = key.id
    }

    var key: MediaKey? {
        guard let kind = MediaKind(rawValue: kind) else { return nil }
        return MediaKey(kind: kind, id: id)
    }
}

/// One of the caller's deck signals as stored (`taste_signal_events`, read-own under RLS).
nonisolated struct DiscoverDeckSignalRow: Decodable, Sendable {
    let mediaType: String
    let mediaId: Int
    let eventType: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case eventType = "event_type"
        case createdAt = "created_at"
    }

    var key: MediaKey? {
        switch mediaType.uppercased() {
        case "ANIME": return MediaKey(kind: .anime, id: mediaId)
        case "MANGA": return MediaKey(kind: .manga, id: mediaId)
        default: return nil
        }
    }

    /// The deck action of the event ('deck_love' -> .love ...); nil for non-deck events.
    var deckAction: TasteDeckAction? {
        guard eventType.hasPrefix("deck_") else { return nil }
        return TasteDeckAction(rawValue: String(eventType.dropFirst(5)))
    }
}

/// The per-account, on-device memory of Discover answers: the last server answer (shown before the
/// next read lands, so a hidden title never flashes back after a relaunch) plus the answers this
/// device made that the server does not reflect yet (an offline answer survives the app being killed).
///
/// Merge rule: hidden = snapshot, then every overlay entry in order (a hide adds, an undo removes).
/// An overlay entry is pruned once a server read shows the same state for its title, and after
/// `overlayLifetime` regardless (the outbox gives up after five attempts; the answer then stays
/// local for at most this long).
nonisolated struct DiscoverHiddenMemory: Codable, Equatable, Sendable {
    nonisolated struct Entry: Codable, Equatable, Sendable {
        let ref: DiscoverMediaRef
        /// The wanted Discover state of the title: hidden with this answer, or visible (nil, an Undo).
        let state: DiscoverFeedback?
        let at: Date
    }

    /// The hiding answers of the last successful server read.
    var snapshot: [DiscoverMediaRef: DiscoverFeedback] = [:]
    /// Answers made on this device, oldest first, one per title.
    var overlay: [Entry] = []
    /// When `snapshot` was read (nil: never).
    var refreshedAt: Date? = nil

    static let overlayLifetime: TimeInterval = 30 * 24 * 60 * 60
    static let overlayCapacity = 300

    /// The titles hidden right now, with their answer.
    var hidden: [MediaKey: DiscoverFeedback] {
        var result: [MediaKey: DiscoverFeedback] = [:]
        for (ref, feedback) in snapshot {
            if let key = ref.key { result[key] = feedback }
        }
        for entry in overlay {
            guard let key = entry.ref.key else { continue }
            result[key] = entry.state
        }
        return result
    }

    /// Records a device answer (replacing an earlier one for the same title).
    mutating func record(_ key: MediaKey, state: DiscoverFeedback?, at: Date) {
        let ref = DiscoverMediaRef(key)
        overlay.removeAll { $0.ref == ref }
        overlay.append(Entry(ref: ref, state: state, at: at))
        if overlay.count > Self.overlayCapacity {
            overlay.removeFirst(overlay.count - Self.overlayCapacity)
        }
    }

    /// Adopts a server read: the snapshot becomes `server`, overlay entries the server now reflects
    /// (same state) or that outlived `overlayLifetime` are dropped.
    mutating func adopt(server: [MediaKey: DiscoverFeedback], now: Date) {
        var next: [DiscoverMediaRef: DiscoverFeedback] = [:]
        for (key, feedback) in server { next[DiscoverMediaRef(key)] = feedback }
        snapshot = next
        refreshedAt = now
        overlay.removeAll { entry in
            if now.timeIntervalSince(entry.at) > Self.overlayLifetime { return true }
            return next[entry.ref] == entry.state
        }
    }

    var isEmpty: Bool { snapshot.isEmpty && overlay.isEmpty }

    /// Device storage key of one account's memory (lower-cased user id; nil when signed out).
    static func storageKey(userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return "kuro.discover.hidden.\(userId.lowercased())"
    }
}

// MARK: Sections, sorts and filters (R1, R6)

/// A Discover section as the data contract names it (`p_section`).
enum DiscoverSectionKey: String, CaseIterable, Sendable {
    case essentials
    case classics
    case newToYou = "new_to_you"
    case trending
    case topRated = "top_rated"
    case newlyAdded = "newly_added"
    case currentSeason = "current_season"
    case airingToday = "airing_today"
    /// "Because you finished X": personal, read from `fetch_because_you_rail`; never server-paged.
    case becauseYou = "because_you"

    /// R2: personal sections hide titles already on the list; editorial sections keep them and mark
    /// them with the status word.
    var ownedPolicy: DiscoverOwnedPolicy {
        switch self {
        case .newToYou, .becauseYou: return .hide
        default: return .mark
        }
    }

    /// Whether `discover_section_page_v1` serves this section for `medium`.
    func isServerPaged(for medium: MediaKind) -> Bool {
        switch self {
        case .becauseYou: return false
        case .currentSeason, .airingToday: return medium == .anime
        default: return true
        }
    }

}

/// How a section treats titles already on the caller's list (R2).
enum DiscoverOwnedPolicy: Sendable {
    /// Removed from the section (personal / "new" sections).
    case hide
    /// Kept, carrying the list status word (essentials, trending, editorial sections).
    case mark
}

/// The See all sort (R6). `newest` is the RELEASE date, never the date a title entered Kuro.
enum DiscoverSeeAllSort: String, CaseIterable, Sendable {
    case sectionOrder = "default"
    case popular
    case newest
    case topRated = "top_rated"
}

/// The length quick filter (R6): anime episodes / manga chapters (volumes when chapters are unknown).
enum DiscoverLengthFilter: String, CaseIterable, Sendable {
    case short
    case standard
    case long

    /// Inclusive episode bounds (anime).
    var episodeRange: (min: Int, max: Int?) {
        switch self {
        case .short: return (1, 13)
        case .standard: return (14, 50)
        // D10: "Over 50 episodes" (the shipped long rule is > 50).
        case .long: return (51, nil)
        }
    }

    /// Inclusive chapter bounds (manga).
    var chapterRange: (min: Int, max: Int?) {
        switch self {
        case .short: return (1, 50)
        case .standard: return (51, 150)
        case .long: return (151, nil)
        }
    }

    /// Whether a card's count falls in this bucket (unknown counts never match; manga `short` also
    /// accepts 1-5 volumes when chapters are unknown, as the server does).
    func matches(kind: MediaKind, episodes: Int?, chapters: Int?, volumes: Int? = nil) -> Bool {
        switch kind {
        case .anime:
            guard let episodes else { return false }
            let range = episodeRange
            return episodes >= range.min && (range.max.map { episodes <= $0 } ?? true)
        case .manga:
            if let chapters {
                let range = chapterRange
                return chapters >= range.min && (range.max.map { chapters <= $0 } ?? true)
            }
            if self == .short, let volumes { return (1...5).contains(volumes) }
            return false
        }
    }
}

/// The status quick filter (R6).
enum DiscoverStatusFilter: String, CaseIterable, Sendable {
    case finished
    case releasing
    case upcoming

    /// The catalogue's AniList status word.
    var catalogStatus: String {
        switch self {
        case .finished: return "FINISHED"
        case .releasing: return "RELEASING"
        case .upcoming: return "NOT_YET_RELEASED"
        }
    }
}

/// One See all request. `format` is one AniList format word (TV, MOVIE, OVA, ONA, MANGA, ONE_SHOT
/// ...); nil keeps the default surface (anime SPECIAL / MUSIC / TV_SHORT hidden).
struct DiscoverSeeAllQuery: Hashable, Sendable {
    var section: DiscoverSectionKey
    var medium: MediaKind
    var sort: DiscoverSeeAllSort = .sectionOrder
    var format: String? = nil
    var length: DiscoverLengthFilter? = nil
    var status: DiscoverStatusFilter? = nil
}

/// The mood entry points at the top of Discover (`p_mood`).
enum DiscoverMood: String, CaseIterable, Sendable {
    case short
    case cozy
    case intense
    case likeLastLoved = "like_last_loved"

    /// The one Browse genre a mood falls back to while `discover_mood_v1` is not deployed.
    var fallbackGenre: String? {
        switch self {
        case .cozy: return "Slice of Life"
        case .intense: return "Thriller"
        case .short, .likeLastLoved: return nil
        }
    }
}

// MARK: Pages

/// A Discover card of either medium (the existing card models, unchanged).
enum DiscoverCardValue: Identifiable, Sendable {
    case anime(AnimeCard)
    case manga(MangaCard)

    var key: MediaKey {
        switch self {
        case .anime(let card): return MediaKey(kind: .anime, id: card.id)
        case .manga(let card): return MediaKey(kind: .manga, id: card.id)
        }
    }

    var id: String { "\(key.kind.rawValue)-\(key.id)" }

    var display: any MediaDisplayable {
        switch self {
        case .anime(let card): return card
        case .manga(let card): return card
        }
    }

    var title: String { display.title }
    var anime: AnimeCard? { if case .anime(let card) = self { return card } else { return nil } }
    var manga: MangaCard? { if case .manga(let card) = self { return card } else { return nil } }
}

/// One card of a mood or See all page.
struct DiscoverPageItem: Identifiable, Sendable {
    let card: DiscoverCardValue
    /// The server's franchise component (nil: not known; the composer then uses the title stem).
    let franchiseId: Int?
    /// The caller's list status as the server saw it (editorial sections only). Views should prefer
    /// the Library's live entry (`LibraryStore.entry(for:)`), which also knows a Plan made a second ago.
    let serverListStatus: ListStatus?

    var key: MediaKey { card.key }
    var id: String { card.id }
}

/// Why a personal page shows what it shows ("Because you loved X", R1).
struct DiscoverReason: Equatable, Sendable {
    let key: MediaKey
    let title: String
}

/// Where the next page of a journey continues.
enum DiscoverPageCursor: Hashable, Sendable {
    /// `discover_section_page_v1` / `discover_mood_v1` offset (rows already served, deduped order).
    case offset(Int)
    /// Live Browse keyset (fallback while the prepared readers are not deployed).
    case browse(cursorInt: Int?, cursorDate: Date?, cursorId: Int)
}

/// One page of a mood journey or a See all page.
struct DiscoverPage: Sendable {
    enum Origin: Equatable, Sendable {
        /// The prepared server reader (hidden, owned and franchise rules applied server-side too).
        case server
        /// A live fallback read (Browse / similar titles); the client applied the rules.
        case fallback
        /// The section's loaded rows, sorted and filtered on the device (no further pages).
        case local
    }

    let items: [DiscoverPageItem]
    /// nil: the journey ends here (R7 for the page, "no more" for See all).
    let next: DiscoverPageCursor?
    let reason: DiscoverReason?
    let origin: Origin
}

/// One row of `discover_section_page_v1` / `discover_mood_v1`.
struct DiscoverPageRow: Decodable, Sendable {
    let mediaType: String
    let rank: Int
    let id: Int
    let titleEnglish: String?
    let titleRomaji: String?
    let titleNative: String?
    let coverImageLarge: String?
    let coverImageMedium: String?
    let bannerImage: String?
    let format: String?
    let status: String?
    let episodeCount: Int?
    let chapterCount: Int?
    let volumes: Int?
    let seasonYear: Int?
    let startDateYear: Int?
    let averageScore: Int?
    let popularity: Int?
    let trending: Int?
    let favourites: Int?
    let genres: [String]?
    let createdAt: Date?
    let franchiseId: Int?
    let listStatus: String?
    let reasonMediaId: Int?
    let reasonTitle: String?

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case rank, id
        case titleEnglish = "title_english"
        case titleRomaji = "title_romaji"
        case titleNative = "title_native"
        case coverImageLarge = "cover_image_large"
        case coverImageMedium = "cover_image_medium"
        case bannerImage = "banner_image"
        case format, status
        case episodeCount = "episode_count"
        case chapterCount = "chapter_count"
        case volumes
        case seasonYear = "season_year"
        case startDateYear = "start_date_year"
        case averageScore = "average_score"
        case popularity, trending, favourites, genres
        case createdAt = "created_at"
        case franchiseId = "franchise_id"
        case listStatus = "list_status"
        case reasonMediaId = "reason_media_id"
        case reasonTitle = "reason_title"
    }

    var kind: MediaKind? {
        switch mediaType.uppercased() {
        case "ANIME": return .anime
        case "MANGA": return .manga
        default: return nil
        }
    }

    var item: DiscoverPageItem? {
        guard let kind else { return nil }
        let card: DiscoverCardValue
        switch kind {
        case .anime:
            card = .anime(AnimeCard(
                id: id, titleEnglish: titleEnglish, titleRomaji: titleRomaji, titleNative: titleNative,
                coverImageLarge: coverImageLarge, coverImageMedium: coverImageMedium, bannerImage: bannerImage,
                format: format, status: status, episodeCount: episodeCount, seasonYear: seasonYear,
                startDateYear: startDateYear, averageScore: averageScore, popularity: popularity,
                trending: trending, favourites: favourites, genreList: genres, createdAt: createdAt, rank: nil))
        case .manga:
            card = .manga(MangaCard(
                id: id, titleEnglish: titleEnglish, titleRomaji: titleRomaji, titleNative: titleNative,
                coverImageLarge: coverImageLarge, coverImageMedium: coverImageMedium,
                format: format, status: status, chapterCount: chapterCount, startDateYear: startDateYear,
                averageScore: averageScore, popularity: popularity, trending: trending, favourites: favourites,
                genreList: genres, createdAt: createdAt, rank: nil))
        }
        return DiscoverPageItem(card: card, franchiseId: franchiseId,
                                serverListStatus: listStatus.flatMap(ListStatus.init(rawValue:)))
    }

    var reason: DiscoverReason? {
        guard let kind, let reasonMediaId, let reasonTitle, !reasonTitle.isEmpty else { return nil }
        return DiscoverReason(key: MediaKey(kind: kind, id: reasonMediaId), title: reasonTitle)
    }
}

/// One row of `media_franchise_ids_v1`.
nonisolated struct DiscoverFranchiseRow: Decodable, Sendable {
    let mediaType: String
    let mediaId: Int
    let franchiseId: Int

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mediaId = "media_id"
        case franchiseId = "franchise_id"
    }

    var key: MediaKey? {
        switch mediaType.uppercased() {
        case "ANIME": return MediaKey(kind: .anime, id: mediaId)
        case "MANGA": return MediaKey(kind: .manga, id: mediaId)
        default: return nil
        }
    }
}

// MARK: Franchise identity (R2)

/// One way two titles can be "the same series": the server component (`media_franchise_components`,
/// same medium) when read, else the title stem (the device rule, so dedupe works before the
/// prepared reader is deployed). Two titles are the same franchise when they share a key. Keys
/// carry the medium: an anime and its manga are never merged (R11 labels them instead).
nonisolated enum DiscoverFranchiseKey: Hashable, Sendable {
    case component(MediaKind, Int)
    case stem(MediaKind, String)
}

/// The title stem rule: the series name without its sequel / season / part / subtitle markers.
/// "Demon Slayer: Kimetsu no Yaiba Swordsmith Village Arc" and "Demon Slayer: Kimetsu no Yaiba"
/// -> "demon slayer"; "Attack on Titan Season 3 Part 2" -> "attack on titan". Stems shorter than
/// `minimumLength` characters are not used (too likely to collide).
nonisolated enum DiscoverFranchiseStem {
    static let minimumLength = 4

    static func stem(_ title: String) -> String? {
        var text = title.lowercased()
        // Subtitle separators: "Title: Subtitle", "Title - Subtitle", "Title – Subtitle".
        for separator in [": ", " - ", " – ", " — "] {
            if let range = text.range(of: separator) { text = String(text[..<range.lowerBound]) }
        }
        // Bracketed qualifiers: "(TV)", "(2019)", "[Oshi no Ko]" keeps its words.
        text = text.replacingOccurrences(of: #"\((tv|ova|ona|movie|\d{4})\)"#, with: " ", options: .regularExpression)
        // Non-alphanumerics to spaces (keeps letters of every script).
        text = text.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        // Trailing sequel markers, repeatedly ("season 3 part 2", "2nd season", "final season", "ii").
        let markers = [
            #"\s+(the\s+)?final(\s+season)?$"#, #"\s+season\s+\d+$"#, #"\s+\d+(st|nd|rd|th)\s+season$"#,
            #"\s+part\s+\d+$"#, #"\s+cour\s+\d+$"#, #"\s+s\d+$"#, #"\s+(ii|iii|iv|v|vi)$"#, #"\s+\d{1,2}$"#,
            #"\s+season$"#, #"\s+the\s+movie$"#, #"\s+movie$"#,
        ]
        var changed = true
        while changed {
            changed = false
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            for marker in markers {
                let next = trimmed.replacingOccurrences(of: marker, with: "", options: .regularExpression)
                if next != trimmed, !next.isEmpty {
                    text = next
                    changed = true
                    break
                }
            }
            if !changed { text = trimmed }
        }
        let collapsed = text.split(separator: " ").joined(separator: " ")
        return collapsed.count >= minimumLength ? collapsed : nil
    }
}

// MARK: Page composition (R2): one pure rule for the whole page

/// One section as the page wants to show it, before the R2 rules.
struct DiscoverSectionInput<Item> {
    let id: String
    let policy: DiscoverOwnedPolicy
    /// The section's rows in its own order (the bundle gives up to 30: room to backfill).
    let items: [Item]
    /// How many cards the section shows.
    let displayCount: Int
}

/// One card placed on the page.
struct DiscoverPlacedItem<Item> {
    let item: Item
    /// The list status word to show (mark policy only; nil when not on the list).
    let ownedStatus: ListStatus?
}

/// One section after the R2 rules.
struct DiscoverPlacedSection<Item> {
    let id: String
    let items: [DiscoverPlacedItem<Item>]
    /// Rows left for See all after the shown ones (same rules applied).
    let remainingCount: Int
}

/// R2 for the whole Discover page: never the same series twice on one page.
///
/// Order of operations, per section in page order: drop hidden titles (R5) -> the owned rule of the
/// section (hide or mark) -> franchise dedupe across the page AND within the section (the first
/// occurrence in page order wins; later sections backfill from their tail up to `displayCount`).
/// Every item is keyed by `MediaKey` (anime 7 and manga 7 are different titles).
enum DiscoverPageComposer {
    static func compose<Item>(
        _ sections: [DiscoverSectionInput<Item>],
        key: (Item) -> MediaKey,
        franchiseKeys: (Item) -> Set<DiscoverFranchiseKey>,
        isHidden: (MediaKey) -> Bool,
        ownedStatus: (MediaKey) -> ListStatus?
    ) -> [DiscoverPlacedSection<Item>] {
        var seenTitles: Set<MediaKey> = []
        var seenFranchises: Set<DiscoverFranchiseKey> = []
        var result: [DiscoverPlacedSection<Item>] = []
        for section in sections {
            var placed: [DiscoverPlacedItem<Item>] = []
            var remaining = 0
            let limit = max(0, section.displayCount)
            for item in section.items {
                let itemKey = key(item)
                guard !isHidden(itemKey), !seenTitles.contains(itemKey) else { continue }
                let status = ownedStatus(itemKey)
                if section.policy == .hide, status != nil { continue }
                let franchises = franchiseKeys(item)
                guard seenFranchises.isDisjoint(with: franchises) else { continue }
                if placed.count < limit {
                    placed.append(DiscoverPlacedItem(item: item, ownedStatus: section.policy == .mark ? status : nil))
                    seenTitles.insert(itemKey)
                    seenFranchises.formUnion(franchises)
                } else {
                    remaining += 1
                }
            }
            result.append(DiscoverPlacedSection(id: section.id, items: placed, remainingCount: remaining))
        }
        return result
    }
}

/// The cards of one journey (mood page or See all) across its pages: appends a page without
/// repeating a title or a franchise already shown (a fallback page is not deduped server-side, and
/// two server pages can overlap when the catalogue changed between them), hides answered titles and
/// applies the owned rule.
struct DiscoverPageAccumulator {
    let policy: DiscoverOwnedPolicy
    private(set) var items: [DiscoverPlacedItem<DiscoverPageItem>] = []
    private(set) var next: DiscoverPageCursor? = nil
    private(set) var reason: DiscoverReason? = nil
    /// false until the first page arrived.
    private(set) var started = false
    private var seenTitles: Set<MediaKey> = []
    private var seenFranchises: Set<DiscoverFranchiseKey> = []

    init(policy: DiscoverOwnedPolicy) {
        self.policy = policy
    }

    /// Whether the journey has ended (R7: "You're caught up").
    var isFinished: Bool { started && next == nil }

    mutating func append(
        _ page: DiscoverPage,
        franchiseKeys: (DiscoverPageItem) -> Set<DiscoverFranchiseKey>,
        isHidden: (MediaKey) -> Bool,
        ownedStatus: (MediaKey) -> ListStatus?
    ) {
        started = true
        next = page.next
        if reason == nil { reason = page.reason }
        for item in page.items {
            guard !isHidden(item.key), !seenTitles.contains(item.key) else { continue }
            let status = ownedStatus(item.key) ?? item.serverListStatus
            if policy == .hide, status != nil { continue }
            let franchises = franchiseKeys(item)
            guard seenFranchises.isDisjoint(with: franchises) else { continue }
            items.append(DiscoverPlacedItem(item: item, ownedStatus: policy == .mark ? status : nil))
            seenTitles.insert(item.key)
            seenFranchises.formUnion(franchises)
        }
    }

    /// Removes one title at once (Not interested / Seen it on a See all card, R5).
    mutating func remove(_ key: MediaKey) {
        items.removeAll { $0.item.key == key }
    }
}

// MARK: Local sort / filter (fallback of curated and personal sections)

enum DiscoverLocalPage {
    /// The section's loaded rows sorted and filtered like the server would (no paging).
    static func page(_ cards: [DiscoverCardValue], query: DiscoverSeeAllQuery) -> [DiscoverCardValue] {
        let filtered = cards.filter { card in
            let display = card.display
            guard card.key.kind == query.medium else { return false }
            if let format = query.format, (display.formatRaw ?? "").uppercased() != format.uppercased() { return false }
            if let length = query.length,
               !length.matches(kind: card.key.kind, episodes: display.episodes, chapters: display.chapters) { return false }
            if let status = query.status, (display.statusRaw ?? "").uppercased() != status.catalogStatus { return false }
            return true
        }
        let indexed = filtered.enumerated().map { (offset: $0.offset, card: $0.element) }
        let sorted: [(offset: Int, card: DiscoverCardValue)]
        switch query.sort {
        case .sectionOrder:
            sorted = indexed
        case .popular:
            sorted = indexed.sorted { order($0.card.display.popularityValue, $1.card.display.popularityValue, $0, $1) }
        case .topRated:
            sorted = indexed.sorted { order(score($0.card), score($1.card), $0, $1) }
        case .newest:
            sorted = indexed.sorted { order(releaseYear($0.card), releaseYear($1.card), $0, $1) }
        }
        return sorted.map(\.card)
    }

    private static func score(_ card: DiscoverCardValue) -> Int? {
        switch card {
        case .anime(let anime): return anime.averageScore
        case .manga(let manga): return manga.averageScore
        }
    }

    private static func releaseYear(_ card: DiscoverCardValue) -> Int? {
        switch card {
        case .anime(let anime): return anime.startDateYear ?? anime.seasonYear
        case .manga(let manga): return manga.startDateYear
        }
    }

    /// Descending by value (nil last), then the section's own order.
    private static func order(_ a: Int?, _ b: Int?, _ lhs: (offset: Int, card: DiscoverCardValue),
                              _ rhs: (offset: Int, card: DiscoverCardValue)) -> Bool {
        switch (a, b) {
        case let (a?, b?) where a != b: return a > b
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.offset < rhs.offset
        }
    }
}

// MARK: RPC params (top-level: their `Encodable` conformance must not be main-actor isolated)

struct RPCMediaFranchiseIdsParams: Encodable, Sendable {
    let p_anime_ids: [Int]
    let p_manga_ids: [Int]

    enum CodingKeys: String, CodingKey { case p_anime_ids, p_manga_ids }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_anime_ids, forKey: .p_anime_ids)
        try c.encode(p_manga_ids, forKey: .p_manga_ids)
    }
}

struct RPCDiscoverSectionPageParams: Encodable, Sendable {
    let p_section: String
    let p_media_type: String
    let p_sort: String
    let p_format: String?
    let p_length: String?
    let p_status: String?
    let p_limit: Int
    let p_offset: Int

    enum CodingKeys: String, CodingKey {
        case p_section, p_media_type, p_sort, p_format, p_length, p_status, p_limit, p_offset
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_section, forKey: .p_section)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_sort, forKey: .p_sort)
        try c.encodeIfPresent(p_format, forKey: .p_format)
        try c.encodeIfPresent(p_length, forKey: .p_length)
        try c.encodeIfPresent(p_status, forKey: .p_status)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encode(p_offset, forKey: .p_offset)
    }
}

struct RPCDiscoverMoodParams: Encodable, Sendable {
    let p_mood: String
    let p_media_type: String
    let p_limit: Int
    let p_offset: Int

    enum CodingKeys: String, CodingKey { case p_mood, p_media_type, p_limit, p_offset }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_mood, forKey: .p_mood)
        try c.encode(p_media_type, forKey: .p_media_type)
        try c.encode(p_limit, forKey: .p_limit)
        try c.encode(p_offset, forKey: .p_offset)
    }
}
