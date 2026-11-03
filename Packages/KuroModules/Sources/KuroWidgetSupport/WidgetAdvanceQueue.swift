import Foundation
import KuroCore

// MARK: - +1 hand-off queue (extension → app)
// The widget's +1 never writes tracking data. Its intent appends ONE request to this file in the App
// Group and returns; the app drains the file (`WidgetIntentInbox`) and applies each request through
// `LibraryActions` with the same caught-up guard and progress path (durable outbox + revision fence)
// as an in-app +1. The queue is only a hand-off: a request names the position it expects to reach
// (`targetUnit`) for one account and one Library lifecycle, and the app refuses anything that does not
// match the Library at drain time, so a replayed, stale or forged entry can do no more than a +1 the
// user could make in the app at that moment.
//
// Idempotency (per account, title, target unit): `enqueue` keeps one request per
// `idempotencyKey`, so a double tap on the same position queues once; the app's expected-position
// check (displayed progress == target − 1) makes an already-applied request a no-op.
// Both processes read-modify-write the file under `NSFileCoordinator`, atomically, with
// `completeUntilFirstUserAuthentication` protection (a widget must read it while the device is locked
// after the first unlock).

/// One queued +1 from the widget.
public struct WidgetAdvanceRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let account: WidgetAccountHash
    public let medium: MediaKind
    public let mediaId: Int
    /// The position this +1 reaches (displayed progress + 1 when it was tapped).
    public let targetUnit: Int
    /// The Library lifecycle the tap was made on (a re-added title has a new one).
    public let lifecycleId: String?
    /// The known unit total at tap time (the cap; the app re-reads its own).
    public let total: Int?
    public let createdAt: Date

    public init(id: UUID, account: WidgetAccountHash, medium: MediaKind, mediaId: Int, targetUnit: Int,
                lifecycleId: String?, total: Int?, createdAt: Date) {
        self.id = id
        self.account = account
        self.medium = medium
        self.mediaId = mediaId
        self.targetUnit = targetUnit
        self.lifecycleId = lifecycleId
        self.total = total
        self.createdAt = createdAt
    }

    /// One request per (account, title, target unit).
    public var idempotencyKey: String { "\(account.value)|\(medium.rawValue)|\(mediaId)|\(targetUnit)" }

    public var key: MediaKey { MediaKey(kind: medium, id: mediaId) }

    /// Structurally valid: a positive target, never past the known total.
    public var isWellFormed: Bool {
        guard targetUnit >= 1, mediaId > 0 else { return false }
        if let total, total > 0, targetUnit > total { return false }
        return true
    }
}

/// What `enqueue` did.
public enum WidgetEnqueueResult: Equatable, Sendable {
    case queued
    /// The same (account, title, target) is already queued: nothing added.
    case duplicate
    /// Malformed (no positive target, past the total) or the queue is full.
    case rejected
    /// The App Group file could not be written.
    case unavailable
}

/// The App Group queue file (`Widgets/advance-queue.json`).
public struct WidgetAdvanceQueue: Sendable {
    /// Requests older than this are dropped unread (the snapshot they were made on is long gone).
    public static let timeToLive: TimeInterval = 48 * 3600
    /// The most requests held at once (a +1 per title per unit; more means something is wrong).
    public static let capacity = 64

    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("advance-queue.json")
    }

    /// The queue in the App Group, or nil without the entitlement.
    public static func shared(fileManager: FileManager = .default) -> WidgetAdvanceQueue? {
        KuroAppGroup.widgetDirectory(fileManager: fileManager).map(WidgetAdvanceQueue.init(directory:))
    }

    // MARK: Extension side

    /// Appends `request` unless the same key is queued, it is malformed, or the queue is full.
    /// Expired entries are pruned in the same coordinated write.
    @discardableResult
    public func enqueue(_ request: WidgetAdvanceRequest, now: Date = Date()) -> WidgetEnqueueResult {
        guard request.isWellFormed else { return .rejected }
        var result = WidgetEnqueueResult.unavailable
        let ok = mutate { entries in
            entries.removeAll { now.timeIntervalSince($0.createdAt) > Self.timeToLive }
            if entries.contains(where: { $0.idempotencyKey == request.idempotencyKey }) {
                result = .duplicate
                return false
            }
            guard entries.count < Self.capacity else {
                result = .rejected
                return false
            }
            entries.append(request)
            result = .queued
            return true
        }
        return ok ? result : .unavailable
    }

    // MARK: App side

    /// Every queued request, oldest first (expired ones excluded).
    public func all(now: Date = Date()) -> [WidgetAdvanceRequest] {
        read().filter { now.timeIntervalSince($0.createdAt) <= Self.timeToLive }
            .sorted { lhs, rhs in
                lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.targetUnit < rhs.targetUnit
            }
    }

    /// The requests of `account`, oldest first; within one title lower targets first.
    public func pending(for account: WidgetAccountHash, now: Date = Date()) -> [WidgetAdvanceRequest] {
        all(now: now).filter { $0.account == account }
    }

    /// Removes the requests with these ids (after the app processed them).
    public func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        _ = mutate { entries in
            let before = entries.count
            entries.removeAll { ids.contains($0.id) }
            return entries.count != before
        }
    }

    /// Keeps only `account`'s requests (nil: removes everything). Used on sign-out / account switch.
    public func retainOnly(account: WidgetAccountHash?) {
        _ = mutate { entries in
            let before = entries.count
            if let account { entries.removeAll { $0.account != account } } else { entries.removeAll() }
            return entries.count != before
        }
    }

    // MARK: File access

    func read() -> [WidgetAdvanceRequest] {
        var entries: [WidgetAdvanceRequest] = []
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            entries = Self.decode(url)
        }
        return entries
    }

    /// Coordinated read-modify-write; `change` returns whether it changed anything (no write when not).
    /// Returns false when the file could not be written.
    func mutate(_ change: (inout [WidgetAdvanceRequest]) -> Bool) -> Bool {
        var success = true
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fileURL, options: [], error: &coordinationError) { url in
            var entries = Self.decode(url)
            guard change(&entries) else { return }
            do {
                let data = try WidgetJSON.encoder.encode(entries)
                try data.write(to: url, options: WidgetJSON.writeOptions)
            } catch {
                success = false
            }
        }
        return success && coordinationError == nil
    }

    private static func decode(_ url: URL) -> [WidgetAdvanceRequest] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        // One unreadable element never drops the others.
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { element in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? WidgetJSON.decoder.decode(WidgetAdvanceRequest.self, from: elementData)
        }
    }
}

/// Shared coders and write options for every App Group file.
enum WidgetJSON {
    static var encoder: JSONEncoder {
        // Dates as reference-date seconds (the default): they round-trip exactly, so a re-read
        // snapshot compares equal to the one that was written.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        JSONDecoder()
    }

    /// Atomic, readable after the first unlock (widgets render while the device is locked).
    static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return [.atomic]
        #endif
    }
}
