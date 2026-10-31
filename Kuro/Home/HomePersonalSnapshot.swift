import Foundation
import KuroCore
import KuroLibrary

/// A whitelist of personal Home data. Club slices, comments, names, permission results and
/// pagination cursors have no representation here and can never be serialized by this cache.
struct HomePersonalSnapshot: Codable, Sendable {
    struct Tracking: Codable, Sendable {
        let mediaId: Int
        let rowId: Int
        let status: ListStatus
        let progress: Int
        let label: String?
        let unitId: UUID?
        let rating: Int?
        let notes: String?
        let verdict: Verdict?
        let createdAt: Date
        let updatedAt: Date
        let revision: Int64
        let lifecycle: UUID

        init?(_ row: LibraryEntry, card: HomeCard) {
            guard row.key.id == card.mediaId, row.rowId > 0,
                  let revision = row.revision, let lifecycle = row.lifecycleId,
                  lifecycle == UUID(uuidString: card.lifecycleId), revision == card.serverRevision,
                  row.progress == card.progress, row.progressLabel == card.progressLabel,
                  row.unitId == card.unitId.flatMap(UUID.init(uuidString:)) else { return nil }
            mediaId = row.key.id; rowId = row.rowId; status = row.status; progress = row.progress
            label = row.progressLabel; unitId = row.unitId; rating = row.rating?.value
            notes = row.notes; verdict = row.verdict; createdAt = row.createdAt; updatedAt = row.updatedAt
            self.revision = revision; self.lifecycle = lifecycle
        }

        func entry(medium: MediaKind) -> LibraryEntry {
            LibraryEntry(key: MediaKey(kind: medium, id: mediaId), rowId: rowId, status: status,
                progress: progress, rating: rating.flatMap(UserRating.init(value:)), notes: notes,
                verdict: verdict, createdAt: createdAt, updatedAt: updatedAt, revision: revision,
                lifecycleId: lifecycle, progressLabel: label, unitId: unitId)
        }
    }

    let version: Int
    let accountId: String
    let savedAt: Date
    let medium: String
    let windowDays: Int
    let revision: Int64
    let active: [HomeCard]
    let upcoming: [HomeEvent]
    let pending: [HomeEvent]
    let tracking: [Tracking]

    init?(accountId: String, bundle: HomeBundle, baselines: [MediaKey: LibraryEntry], now: Date = Date()) {
        guard let kind = MediaKind(rawValue: bundle.medium) else { return nil }
        let cards = Array(bundle.active.prefix(12))
        let rows = cards.compactMap { card in
            baselines[MediaKey(kind: kind, id: card.mediaId)].flatMap { Tracking($0, card: card) }
        }
        guard rows.count == cards.count else { return nil }
        version = 1; self.accountId = accountId.lowercased(); savedAt = now; medium = bundle.medium
        windowDays = bundle.windowDays; revision = bundle.homeRevision; active = cards
        upcoming = Array(bundle.upcoming.prefix(20)); pending = Array(bundle.pending.prefix(20)); tracking = rows
    }

    func isValid(for accountId: String, medium: String, now: Date) -> Bool {
        guard version == 1, self.accountId == accountId.lowercased(), self.medium == medium,
              MediaKind(rawValue: medium) != nil, revision >= 0,
              savedAt <= now.addingTimeInterval(300), now.timeIntervalSince(savedAt) <= 7 * 86_400,
              active.count <= 12, upcoming.count <= 20, pending.count <= 20,
              active.count == tracking.count, Set(active.map(\.mediaId)).count == active.count else { return false }
        for card in active {
            guard card.mediaId > 0, card.progress >= 0, card.serverRevision >= 0,
                  let lifecycle = UUID(uuidString: card.lifecycleId),
                  card.unitId == nil || UUID(uuidString: card.unitId!) != nil,
                  let row = tracking.first(where: { $0.mediaId == card.mediaId }), row.lifecycle == lifecycle,
                  row.rowId > 0, row.progress == card.progress, row.revision == card.serverRevision,
                  row.label == card.progressLabel, row.unitId == card.unitId.flatMap(UUID.init(uuidString:)),
                  row.rating == nil || UserRating(value: row.rating!) != nil else { return false }
        }
        return true
    }

    var bundle: HomeBundle {
        HomeBundle(medium: medium, windowDays: windowDays, homeRevision: revision, active: active,
            upcoming: upcoming, pending: pending, scheduleState: "cached", nextCursor: nil,
            club: HomeClubSlice(state: "reauthorizing", label: "Between us.", items: []))
    }
}

/// One bounded cache for this capability, serialized with deletion. Storage failure never changes
/// a tracking result; the Library outbox remains the commitment/replay authority.
actor HomePersonalSnapshotCache {
    static let maxBytes = 256 * 1024
    private let directory: URL
    private var deletedAccounts: Set<String> = []

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kuro/personal-home-v1", isDirectory: true)
    }

    func read(accountId: String, medium: String, now: Date = Date()) -> HomePersonalSnapshot? {
        guard !deletedAccounts.contains(accountId.lowercased()), MediaKind(rawValue: medium) != nil else { return nil }
        let url = file(accountId: accountId, medium: medium)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maxBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maxBytes,
              let snapshot = try? JSONDecoder().decode(HomePersonalSnapshot.self, from: data),
              snapshot.isValid(for: accountId, medium: medium, now: now) else { return nil }
        return snapshot
    }

    func write(_ snapshot: HomePersonalSnapshot) throws {
        guard !deletedAccounts.contains(snapshot.accountId), snapshot.isValid(for: snapshot.accountId, medium: snapshot.medium, now: Date()) else { return }
        if let previous = read(accountId: snapshot.accountId, medium: snapshot.medium), previous.revision > snapshot.revision { return }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= Self.maxBytes else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(values)
        let url = file(accountId: snapshot.accountId, medium: snapshot.medium)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        if files.count > 16 {
            let oldest = files.sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
            for expired in oldest.prefix(files.count - 16) { try manager.removeItem(at: expired) }
        }
    }

    func remove(accountId: String) throws {
        deletedAccounts.insert(accountId.lowercased())
        for medium in ["anime", "manga"] {
            let url = file(accountId: accountId, medium: medium)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private func file(accountId: String, medium: String) -> URL {
        // Hex encoding cannot escape the cache directory and remains collision-free for account IDs.
        let key = accountId.lowercased().utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(key)-\(medium).json")
    }
}
