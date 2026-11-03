import Foundation
import KuroCore

// MARK: - Widget snapshot (app → extension, read-only for the extension)
// The app's `WidgetSnapshotWriter` builds one `WidgetSnapshot` for the CURRENT account and writes it
// into the App Group; the KuroWidgets extension only reads it. Every user-facing string that depends on
// release certainty is rendered by the app with `ReleaseCopy` (spec D10: a time of day only when the
// row is an instant and not an estimate; estimates are labelled "expected"), so the extension never
// re-implements the certainty rules. The extension may only:
//   - show `countdownTarget` with a system relative/timer text (set only when the app allows a time),
//   - drop releases whose `expiresAt` has passed,
//   - overlay its own queued +1 requests (`applyingPending`).
// No secrets, tokens or user ids are written: the account is an opaque `WidgetAccountHash`.

/// One schema version per incompatible change; a reader ignores a snapshot of another version.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchema = 1
    /// Most releases written (the large widget shows at most a handful).
    public static let maxReleases = 8
    /// Most Now Watching titles written.
    public static let maxNowWatching = 6

    public var schema: Int
    /// The account the snapshot belongs to (opaque). Requests the extension queues carry it back.
    public var account: WidgetAccountHash
    public var generatedAt: Date
    /// `true` when the app rendered the German strings (`KuroLocale.isGerman`).
    public var german: Bool
    /// Upcoming releases of the account's tracked titles, soonest first (displayable rows only).
    public var releases: [WidgetReleaseItem]
    /// Watching / reading titles, most recently updated first.
    public var nowWatching: [WidgetNowWatchingItem]

    public init(schema: Int = WidgetSnapshot.currentSchema, account: WidgetAccountHash, generatedAt: Date,
                german: Bool, releases: [WidgetReleaseItem], nowWatching: [WidgetNowWatchingItem]) {
        self.schema = schema
        self.account = account
        self.generatedAt = generatedAt
        self.german = german
        self.releases = releases
        self.nowWatching = nowWatching
    }

    /// Same account, language and rows (ignores `generatedAt`): the writer skips an unchanged write
    /// and the timeline reload it would cost.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        schema == other.schema && account == other.account && german == other.german
            && releases == other.releases && nowWatching == other.nowWatching
    }

    /// Releases still ahead at `now` (an `expiresAt` in the past drops the row).
    public func releases(at now: Date) -> [WidgetReleaseItem] {
        releases.filter { item in item.expiresAt.map { $0 > now } ?? true }
    }

    /// The snapshot as the extension shows it after its own queued +1 taps: each Now Watching title
    /// moves to the highest queued target of the same account and lifecycle (never past its total).
    /// Requests of another account are ignored.
    public func applyingPending(_ requests: [WidgetAdvanceRequest]) -> WidgetSnapshot {
        var copy = self
        copy.nowWatching = nowWatching.map { item in
            let targets = requests.filter {
                $0.account == account && $0.medium == item.medium && $0.mediaId == item.mediaId
                    && $0.lifecycleId == item.lifecycleId
            }.map(\.targetUnit)
            guard let highest = targets.max(), highest > item.progress else { return item }
            var advanced = item
            advanced.progress = item.total.map { min($0, highest) } ?? highest
            advanced.isQueued = true
            return advanced
        }
        return copy
    }
}

/// One upcoming release, pre-rendered by the app (`ReleaseCopy`).
public struct WidgetReleaseItem: Codable, Equatable, Sendable, Identifiable {
    /// `ReleaseScheduleItem.id` (medium, id, unit, number, date).
    public var id: String
    public var medium: MediaKind
    public var mediaId: Int
    public var title: String
    /// "Ep. 8" / "F. 8", "Ch. 68" / "Kap. 68".
    public var unitLabel: String
    /// The date phrase as of `WidgetSnapshot.generatedAt` ("Fri 21 Nov, 21:30", "expected around
    /// Wed 26 Nov", "November"); nil when no date is known.
    public var datePhrase: String?
    /// `unitLabel · datePhrase` ("Dates to come." when undated).
    public var line: String
    /// Full words for VoiceOver ("Episode 8, Friday 21 November, 21:30").
    public var accessibilityLine: String
    /// `confirmed` / `announced` / `estimated` (`ReleaseBasis`).
    public var basis: String
    /// `instant` / `day` / `month` / `quarter` / `year` (`ReleasePrecision`, effective).
    public var precision: String
    /// Set ONLY when a time of day may be shown (instant, not an estimate): the extension may count
    /// down to it. Never set for day/month/quarter/year windows or estimates.
    public var countdownTarget: Date?
    /// When the row stops being upcoming: the instant itself, or the end of the release day in the
    /// reader's zone; nil for windows and undated rows (they stay until the app rewrites).
    public var expiresAt: Date?
    /// Whether the row is a Kuro / source estimate (the UI labels it; never a time).
    public var isEstimate: Bool
    /// File name of a small cover in the snapshot's `thumbs/` directory, when cached.
    public var thumbnail: String?
    /// Opens the title journey (`kuro://anime/<id>` / `kuro://manga/<id>`); navigation only.
    public var deepLink: URL?

    public init(id: String, medium: MediaKind, mediaId: Int, title: String, unitLabel: String,
                datePhrase: String?, line: String, accessibilityLine: String, basis: String, precision: String,
                countdownTarget: Date?, expiresAt: Date?, isEstimate: Bool, thumbnail: String?, deepLink: URL?) {
        self.id = id
        self.medium = medium
        self.mediaId = mediaId
        self.title = title
        self.unitLabel = unitLabel
        self.datePhrase = datePhrase
        self.line = line
        self.accessibilityLine = accessibilityLine
        self.basis = basis
        self.precision = precision
        self.countdownTarget = countdownTarget
        self.expiresAt = expiresAt
        self.isEstimate = isEstimate
        self.thumbnail = thumbnail
        self.deepLink = deepLink
    }
}

/// One title the account is watching (anime) or reading (manga).
public struct WidgetNowWatchingItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(medium.rawValue):\(mediaId)" }
    public var medium: MediaKind
    public var mediaId: Int
    public var title: String
    /// The displayed position (the Library's displayed progress, pending outbox writes included).
    public var progress: Int
    /// Units in the title when known (episodes / chapters).
    public var total: Int?
    /// "Ep. " / "F. ", "Ch. " / "Kap. " (the app's EN/DE unit prefix).
    public var unitPrefix: String
    /// The Library row lifecycle (a re-added title gets a new one); a +1 for an old lifecycle is refused.
    public var lifecycleId: String?
    /// The row's server revision when the snapshot was built (informational; the app's progress path
    /// applies its own fence).
    public var revision: Int64?
    /// Remote artwork (https only).
    public var artworkURL: URL?
    /// File name of the cached small thumbnail in `thumbs/`.
    public var thumbnail: String?
    /// Opens the title journey; navigation only (the +1 is the intent, never a URL).
    public var deepLink: URL?
    /// Set by `applyingPending`: the shown position includes a +1 the app has not applied yet.
    public var isQueued: Bool

    public init(medium: MediaKind, mediaId: Int, title: String, progress: Int, total: Int?, unitPrefix: String,
                lifecycleId: String?, revision: Int64?, artworkURL: URL?, thumbnail: String?, deepLink: URL?,
                isQueued: Bool = false) {
        self.medium = medium
        self.mediaId = mediaId
        self.title = title
        self.progress = progress
        self.total = total
        self.unitPrefix = unitPrefix
        self.lifecycleId = lifecycleId
        self.revision = revision
        self.artworkURL = artworkURL
        self.thumbnail = thumbnail
        self.deepLink = deepLink
        self.isQueued = isQueued
    }

    /// At (or past) the known total: the +1 is not offered (the app's caught-up guard refuses it too).
    public var isCaughtUp: Bool { total.map { progress >= $0 } ?? false }

    /// "Ep. 7 / 12", "Kap. 68".
    public var progressText: String {
        guard let total else { return "\(unitPrefix)\(progress)" }
        return "\(unitPrefix)\(progress) / \(total)"
    }

    /// The request a +1 tap queues: the next unit of this lifecycle (nil when caught up).
    public func advanceRequest(account: WidgetAccountHash, now: Date, id: UUID = UUID()) -> WidgetAdvanceRequest? {
        guard !isCaughtUp else { return nil }
        return WidgetAdvanceRequest(id: id, account: account, medium: medium, mediaId: mediaId,
                                    targetUnit: progress + 1, lifecycleId: lifecycleId, total: total,
                                    createdAt: now)
    }
}
