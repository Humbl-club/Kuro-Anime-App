import Foundation
import KuroCore
import KuroWidgetSupport
import Testing

/// A fresh directory per test (the App Group is never touched by package tests).
private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("KuroWidgetSupportTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let accountA = WidgetAccountHash.make(userId: "AAAA-1111", salt: "salt")
private let accountB = WidgetAccountHash.make(userId: "bbbb-2222", salt: "salt")

private func request(_ account: WidgetAccountHash = accountA, id mediaId: Int = 42, target: Int,
                     lifecycle: String? = "L1", total: Int? = 12, at date: Date = Date()) -> WidgetAdvanceRequest {
    WidgetAdvanceRequest(id: UUID(), account: account, medium: .anime, mediaId: mediaId, targetUnit: target,
                         lifecycleId: lifecycle, total: total, createdAt: date)
}

private func watching(progress: Int, total: Int? = 12, lifecycle: String? = "L1") -> WidgetNowWatchingItem {
    WidgetNowWatchingItem(medium: .anime, mediaId: 42, title: "Frieren", progress: progress, total: total,
                          unitPrefix: "Ep. ", lifecycleId: lifecycle, revision: 3, artworkURL: nil,
                          thumbnail: nil, deepLink: URL(string: "kuro://anime/42"))
}

@Suite("Widget account tag")
struct WidgetAccountHashTests {
    @Test("the tag is stable, case-insensitive on the user id, salt-dependent and never contains the id")
    func tagProperties() {
        let one = WidgetAccountHash.make(userId: "AbC-123", salt: "s1")
        #expect(one == WidgetAccountHash.make(userId: "abc-123", salt: "s1"))
        #expect(one != WidgetAccountHash.make(userId: "abc-123", salt: "s2"))
        #expect(one != WidgetAccountHash.make(userId: "abc-124", salt: "s1"))
        #expect(!one.value.lowercased().contains("abc-123"))
        #expect(one.value.count == 64)
    }

    @Test("the install salt is created once and reused")
    func installSaltIsStable() throws {
        let suite = "KuroWidgetSupportTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = WidgetAccountHash.installSalt(in: defaults)
        #expect(first.count == 64)
        #expect(WidgetAccountHash.installSalt(in: defaults) == first)
    }
}

@Suite("Widget +1 hand-off queue")
struct WidgetAdvanceQueueTests {
    @Test("enqueue is idempotent per (account, title, target unit)")
    func idempotentPerTarget() throws {
        let queue = WidgetAdvanceQueue(directory: try temporaryDirectory())
        #expect(queue.enqueue(request(target: 8)) == .queued)
        #expect(queue.enqueue(request(target: 8)) == .duplicate, "a double tap on the same position queues once")
        #expect(queue.enqueue(request(target: 9)) == .queued, "the next position is a new request")
        #expect(queue.enqueue(request(accountB, target: 8)) == .queued, "another account is another key")
        #expect(queue.all().count == 3)
        #expect(queue.pending(for: accountA).map(\.targetUnit) == [8, 9])
    }

    @Test("malformed requests are rejected: no positive target, past the total")
    func rejectsMalformed() throws {
        let queue = WidgetAdvanceQueue(directory: try temporaryDirectory())
        #expect(queue.enqueue(request(target: 0)) == .rejected)
        #expect(queue.enqueue(request(target: 13, total: 12)) == .rejected)
        #expect(queue.enqueue(request(target: 12, total: 12)) == .queued)
        #expect(queue.all().map(\.targetUnit) == [12])
    }

    @Test("expired requests are dropped; the queue is bounded")
    func expiryAndCapacity() throws {
        let queue = WidgetAdvanceQueue(directory: try temporaryDirectory())
        let old = Date().addingTimeInterval(-WidgetAdvanceQueue.timeToLive - 60)
        #expect(queue.enqueue(request(target: 2, at: old), now: old) == .queued)
        #expect(queue.all().isEmpty, "an expired request is never handed to the app")
        for target in 1...WidgetAdvanceQueue.capacity {
            _ = queue.enqueue(request(id: target, target: 1, total: nil))
        }
        #expect(queue.enqueue(request(id: 999, target: 1, total: nil)) == .rejected)
        #expect(queue.all().count == WidgetAdvanceQueue.capacity)
    }

    @Test("remove(ids:) and retainOnly(account:) clear exactly what they name")
    func removalAndAccountClearing() throws {
        let queue = WidgetAdvanceQueue(directory: try temporaryDirectory())
        let a8 = request(target: 8), a9 = request(target: 9), b3 = request(accountB, target: 3)
        for item in [a8, a9, b3] { _ = queue.enqueue(item) }
        queue.remove(ids: [a8.id])
        #expect(Set(queue.all().map(\.id)) == [a9.id, b3.id])
        queue.retainOnly(account: accountB)
        #expect(queue.all().map(\.id) == [b3.id], "the switch keeps only the current account's requests")
        queue.retainOnly(account: nil)
        #expect(queue.all().isEmpty, "sign-out removes every request")
    }

    @Test("one corrupt element never drops the others")
    func lenientDecoding() throws {
        let directory = try temporaryDirectory()
        let queue = WidgetAdvanceQueue(directory: directory)
        _ = queue.enqueue(request(target: 4))
        var raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: queue.fileURL)) as? [Any])
        raw.append(["garbage": true])
        try JSONSerialization.data(withJSONObject: raw).write(to: queue.fileURL)
        #expect(queue.all().map(\.targetUnit) == [4])
    }
}

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    private func snapshot(_ items: [WidgetNowWatchingItem], releases: [WidgetReleaseItem] = []) -> WidgetSnapshot {
        WidgetSnapshot(account: accountA, generatedAt: Date(timeIntervalSince1970: 1_800_000_000), german: false,
                       releases: releases, nowWatching: items)
    }

    @Test("queued +1 taps overlay the shown position (same account and lifecycle only, never past the total)")
    func pendingOverlay() {
        let base = snapshot([watching(progress: 7)])
        let shown = base.applyingPending([request(target: 8), request(target: 9)])
        #expect(shown.nowWatching.first?.progress == 9)
        #expect(shown.nowWatching.first?.isQueued == true)
        #expect(base.applyingPending([request(accountB, target: 8)]).nowWatching.first?.progress == 7)
        #expect(base.applyingPending([request(target: 8, lifecycle: "L0")]).nowWatching.first?.progress == 7,
                "a tap on an earlier lifecycle of the title is not shown")
        let capped = snapshot([watching(progress: 11, total: 12)]).applyingPending([request(target: 12), request(target: 13, total: nil)])
        #expect(capped.nowWatching.first?.progress == 12)
        #expect(capped.nowWatching.first?.isCaughtUp == true)
    }

    @Test("a caught-up title offers no +1; otherwise the request names the next unit of this lifecycle")
    func advanceRequest() throws {
        #expect(watching(progress: 12, total: 12).advanceRequest(account: accountA, now: Date()) == nil)
        let next = try #require(watching(progress: 7).advanceRequest(account: accountA, now: Date()))
        #expect(next.targetUnit == 8)
        #expect(next.lifecycleId == "L1")
        #expect(next.account == accountA)
        #expect(watching(progress: 3, total: nil).advanceRequest(account: accountA, now: Date())?.targetUnit == 4)
    }

    @Test("write / read round-trips exactly; clear removes the snapshot and thumbnails")
    func storeRoundTrip() throws {
        let store = WidgetSnapshotStore(directory: try temporaryDirectory())
        let release = WidgetReleaseItem(id: "anime:42:episode:8", medium: .anime, mediaId: 42, title: "Frieren",
                                        unitLabel: "Ep. 8", datePhrase: "Fri 21 Nov, 21:30", line: "Ep. 8 · Fri 21 Nov, 21:30",
                                        accessibilityLine: "Episode 8, Friday 21 November, 21:30", basis: "confirmed",
                                        precision: "instant", countdownTarget: Date(timeIntervalSince1970: 1_800_100_000.25),
                                        expiresAt: Date(timeIntervalSince1970: 1_800_100_000.25), isEstimate: false,
                                        thumbnail: nil, deepLink: URL(string: "kuro://anime/42"))
        let written = snapshot([watching(progress: 7)], releases: [release])
        #expect(store.write(written))
        let read = try #require(store.read())
        #expect(read == written)
        #expect(read.hasSameContent(as: written))
        let name = WidgetSnapshotStore.thumbnailName(medium: "anime", mediaId: 42, artwork: try #require(URL(string: "https://img/x.jpg")))
        #expect(store.writeThumbnail(Data([1, 2, 3]), named: name))
        #expect(store.hasThumbnail(named: name))
        store.clear()
        #expect(store.read() == nil)
        #expect(!store.hasThumbnail(named: name))
    }

    @Test("a snapshot of another schema is ignored; thumbnail names cannot escape thumbs/")
    func schemaAndSafety() throws {
        let store = WidgetSnapshotStore(directory: try temporaryDirectory())
        var future = snapshot([])
        future.schema = WidgetSnapshot.currentSchema + 1
        #expect(store.write(future))
        #expect(store.read() == nil)
        #expect(store.thumbnailURL(named: "../snapshot.json") == nil)
        #expect(store.thumbnailURL(named: ".hidden") == nil)
        #expect(!store.writeThumbnail(Data(count: WidgetSnapshotStore.maxThumbnailBytes + 1), named: "anime-1-a.jpg"))
    }

    @Test("expired releases are dropped at render time; windows without an end stay")
    func releaseExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func item(_ id: String, expires: Date?) -> WidgetReleaseItem {
            WidgetReleaseItem(id: id, medium: .manga, mediaId: 1, title: "T", unitLabel: "Ch. 1", datePhrase: nil,
                              line: "Ch. 1", accessibilityLine: "Chapter 1", basis: "announced", precision: "month",
                              countdownTarget: nil, expiresAt: expires, isEstimate: false, thumbnail: nil, deepLink: nil)
        }
        let shown = snapshot([], releases: [item("past", expires: now.addingTimeInterval(-1)),
                                            item("ahead", expires: now.addingTimeInterval(60)),
                                            item("window", expires: nil)]).releases(at: now)
        #expect(shown.map(\.id) == ["ahead", "window"])
    }
}
