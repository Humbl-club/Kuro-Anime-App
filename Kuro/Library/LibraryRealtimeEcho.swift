import Foundation
import KuroCore
import KuroLibrary

// MARK: - Realtime self-echo suppression (api-surface headline 1)
// Every list write this device makes comes back on the account's realtime channel. Before this rule,
// each echo re-read the whole Library, Home, the Collection feed and the airing schedule, even for a
// "+1 episode" tap whose change sinks had deliberately skipped those reads.
//
// The rule (pure, `LibraryEchoPolicy.isOwnEcho`): an event is this device's own echo, and is dropped,
// only when ALL of these hold:
//   1. its title is known (from `anime_id`/`manga_id`, or a recent local write's list row id for a
//      key-less delete) — an event whose title is unknown is never dropped;
//   2. that title has a write in flight here, or one confirmed within `window` (5 s);
//   3. its content matches what this device already shows: a delete of a title the projection no
//      longer holds, or an insert/update of the same list row (row id, when both sides know it;
//      lifecycle id, when both sides carry it) whose status, progress, rating, notes and verdict
//      equal the projection (and whose server revision is not newer than the confirmed one).
// A change from another device differs in (3) or arrives outside (2), so it is never dropped. A
// dropped echo never cancels or reschedules a pending refresh of another event.
// Known limit: columns the projection does not hold (`volumes_progress`, `repeat_count`,
// `entry_private`, `source_*`) cannot be compared; a foreign change of only those columns inside the
// window of a local write of the same row is taken for the echo (LibraryEntry lives in Packages).

/// One list-table change as the realtime owner sees it (no SDK types; built in LibraryRealtime).
nonisolated struct LibraryRealtimeEvent: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case insert, update, delete
        /// The channel could not describe the change (test fakes, unexpected payloads).
        case unknown
    }

    let action: Action
    /// The title named by the payload (`anime_id` / `manga_id`); nil when absent (a delete under the
    /// default replica identity carries only the row id).
    let key: MediaKey?
    /// The list row id (`id`), when present.
    let rowId: Int?
    let listType: String?
    let progress: Int?
    let rating: Int?
    let notes: String?
    let verdict: String?
    let serverRevision: Int64?
    /// The row's `lifecycle_id` (changes on removal and re-add), when the payload carries it.
    let lifecycleId: UUID?

    init(action: Action, key: MediaKey?, rowId: Int? = nil, listType: String? = nil, progress: Int? = nil,
         rating: Int? = nil, notes: String? = nil, verdict: String? = nil, serverRevision: Int64? = nil,
         lifecycleId: UUID? = nil) {
        self.action = action
        self.key = key
        self.rowId = rowId
        self.listType = listType
        self.progress = progress
        self.rating = rating
        self.notes = notes
        self.verdict = verdict
        self.serverRevision = serverRevision
        self.lifecycleId = lifecycleId
    }

    /// An event the channel could not describe: always refreshes.
    static let unknown = LibraryRealtimeEvent(action: .unknown, key: nil)
}

/// Titles this device wrote recently (confirmed by the Library store's change sink), with their list
/// row ids so a key-less delete can still be attributed.
nonisolated struct LibraryLocalWriteLedger: Sendable {
    struct Write: Equatable, Sendable {
        let at: Date
        let rowIds: Set<Int>
    }

    private(set) var writes: [MediaKey: Write] = [:]

    init() {}

    /// Records a confirmed local write of `key` at `at` (row id 0 marks an unconfirmed row; ignored).
    mutating func record(_ key: MediaKey, rowIds: [Int], at: Date) {
        let known = writes[key]?.rowIds ?? []
        writes[key] = Write(at: at, rowIds: known.union(rowIds.filter { $0 > 0 }))
    }

    /// Forgets writes older than `window` before `now`.
    mutating func prune(now: Date, window: TimeInterval = LibraryEchoPolicy.window) {
        writes = writes.filter { now.timeIntervalSince($0.value.at) <= window }
    }

    func lastWrite(for key: MediaKey) -> Date? { writes[key]?.at }

    /// The title of a recently written list row. Anime and manga row ids are independent sequences,
    /// so an id that matches titles of both media is ambiguous and resolves to nothing.
    func key(forRowId rowId: Int?) -> MediaKey? {
        guard let rowId else { return nil }
        let matches = writes.filter { $0.value.rowIds.contains(rowId) }.map(\.key)
        return matches.count == 1 ? matches.first : nil
    }
}

nonisolated enum LibraryEchoPolicy {
    /// How long after a confirmed local write an identical event still counts as its echo.
    static let window: TimeInterval = 5

    /// The title an event is about: its own key, else a recent local write's row id.
    static func resolvedKey(_ event: LibraryRealtimeEvent, ledger: LibraryLocalWriteLedger) -> MediaKey? {
        event.key ?? ledger.key(forRowId: event.rowId)
    }

    /// Whether `event` is this device's own write coming back (see the file header).
    /// - `inFlight`: the title has a write in flight or a pending progress receipt here.
    /// - `lastLocalWrite`: when this device last confirmed a write of the title.
    /// - `local`: the title as this device currently shows it (nil: not tracked here).
    static func isOwnEcho(
        _ event: LibraryRealtimeEvent,
        resolvedKey: MediaKey?,
        inFlight: Bool,
        lastLocalWrite: Date?,
        local: LibraryEntry?,
        now: Date
    ) -> Bool {
        guard resolvedKey != nil else { return false }
        let recent = lastLocalWrite.map { now.timeIntervalSince($0) <= window && now >= $0.addingTimeInterval(-1) } ?? false
        guard inFlight || recent else { return false }
        switch event.action {
        case .unknown:
            return false
        case .delete:
            return local == nil
        case .insert, .update:
            guard let local else { return false }
            if !inFlight, let echoed = event.serverRevision, let confirmed = local.revision, echoed > confirmed {
                return false
            }
            return matches(event, local)
        }
    }

    /// The echoed row is the shown row and equals it in every field the projection holds.
    static func matches(_ event: LibraryRealtimeEvent, _ local: LibraryEntry) -> Bool {
        // Same list row: a re-add elsewhere (new row id / lifecycle) is never this device's echo.
        // Row id 0 is an optimistic local entry whose id is not known yet: no comparison.
        if let rowId = event.rowId, rowId > 0, local.rowId > 0, rowId != local.rowId { return false }
        if let lifecycle = event.lifecycleId, let shown = local.lifecycleId, lifecycle != shown { return false }
        guard let listType = event.listType, statusMatches(listType: listType, local: local.status),
              let progress = event.progress, progress == local.progress else { return false }
        guard event.rating == local.rating?.value else { return false }
        guard normalized(event.notes) == normalized(local.notes) else { return false }
        return event.verdict?.uppercased() == local.verdict?.rawValue
    }

    /// The list tables store `.current` and `.repeating` as WATCHING/READING.
    static func statusMatches(listType: String, local: ListStatus) -> Bool {
        switch listType.uppercased() {
        case "WATCHING", "READING", "CURRENT": return local == .current || local == .repeating
        case "PLANNING": return local == .planning
        case "COMPLETED": return local == .completed
        case "DROPPED": return local == .dropped
        case "PAUSED": return local == .paused
        default: return false
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
