//
//  LibraryRealtimeEchoTests.swift
//  KuroTests
//
//  Lane F foundation (overnight 2026-11-01): the realtime self-echo rule (api-surface headline 1).
//  A write this device made and confirmed comes back on the account's list channel; that echo must
//  not re-read the whole Library, while a change from another device must never be dropped.
//

import Foundation
import KuroCore
import KuroLibrary
import Supabase
import Testing
@testable import Kuro

@MainActor
@Suite("Library realtime: self-echo rule")
struct LibraryEchoPolicyTests {
    nonisolated static let key = MediaKey(kind: .anime, id: 101)
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    nonisolated static func local(progress: Int = 4, status: ListStatus = .current, rating: Int? = 8, notes: String? = nil,
                      revision: Int64? = nil) -> LibraryEntry {
        LibraryEntry(key: key, rowId: 55, status: status, progress: progress,
                     rating: rating.flatMap { UserRating(value: $0) }, notes: notes,
                     createdAt: now, updatedAt: now, revision: revision)
    }

    static func update(progress: Int = 4, listType: String = "WATCHING", rating: Int? = 8, notes: String? = nil,
                       revision: Int64? = nil, key: MediaKey? = key) -> LibraryRealtimeEvent {
        LibraryRealtimeEvent(action: .update, key: key, rowId: 55, listType: listType, progress: progress,
                             rating: rating, notes: notes, verdict: nil, serverRevision: revision)
    }

    static func isEcho(_ event: LibraryRealtimeEvent, inFlight: Bool = false, writtenAgo: TimeInterval? = 1,
                       local: LibraryEntry? = local()) -> Bool {
        LibraryEchoPolicy.isOwnEcho(event, resolvedKey: event.key, inFlight: inFlight,
                                    lastLocalWrite: writtenAgo.map { now.addingTimeInterval(-$0) },
                                    local: local, now: now)
    }

    @Test("A matching row right after a confirmed local write is this device's echo")
    func ownEcho() {
        #expect(Self.isEcho(Self.update()))
        #expect(Self.isEcho(Self.update(), inFlight: true, writtenAgo: nil))
        #expect(Self.isEcho(Self.update(listType: "WATCHING"), local: Self.local(status: .repeating)))
        #expect(Self.isEcho(Self.update(notes: "  "), local: Self.local(notes: nil)))
    }

    @Test("Outside the 5 s window, or with nothing in flight, every event refreshes")
    func window() {
        #expect(Self.isEcho(Self.update(), writtenAgo: 4.9))
        #expect(!Self.isEcho(Self.update(), writtenAgo: 5.1))
        #expect(!Self.isEcho(Self.update(), writtenAgo: nil))
    }

    @Test("A different row from another device is never dropped, even inside the window")
    func foreignChange() {
        #expect(!Self.isEcho(Self.update(progress: 5)))
        #expect(!Self.isEcho(Self.update(listType: "COMPLETED")))
        #expect(!Self.isEcho(Self.update(rating: 9)))
        #expect(!Self.isEcho(Self.update(notes: "from my iPad")))
        #expect(!Self.isEcho(Self.update(), local: nil), "a row for a title this device does not hold")
        #expect(!Self.isEcho(Self.update(revision: 8), local: Self.local(revision: 7)),
                "a newer server revision than the confirmed one is someone else's write")
        #expect(Self.isEcho(Self.update(revision: 7), local: Self.local(revision: 7)))
    }

    @Test("A re-added row (new row id or lifecycle) from another device is never the echo")
    func sameRowOnly() {
        let readded = LibraryRealtimeEvent(action: .insert, key: Self.key, rowId: 77, listType: "WATCHING",
                                           progress: 4, rating: 8)
        #expect(!Self.isEcho(readded), "same fields, different list row")
        let optimistic = LibraryEntry(key: Self.key, rowId: 0, status: .current, progress: 4,
                                      rating: UserRating(value: 8), createdAt: Self.now, updatedAt: Self.now)
        #expect(Self.isEcho(readded, inFlight: true, local: optimistic), "an unconfirmed add has no row id to compare")
        let lifecycle = UUID()
        var shown = Self.local()
        shown.lifecycleId = lifecycle
        let otherLifecycle = LibraryRealtimeEvent(action: .update, key: Self.key, rowId: 55, listType: "WATCHING",
                                                  progress: 4, rating: 8, lifecycleId: UUID())
        #expect(!Self.isEcho(otherLifecycle, local: shown))
        let sameLifecycle = LibraryRealtimeEvent(action: .update, key: Self.key, rowId: 55, listType: "WATCHING",
                                                 progress: 4, rating: 8, lifecycleId: lifecycle)
        #expect(Self.isEcho(sameLifecycle, local: shown))
    }

    @Test("Unknown titles and undescribed events always refresh")
    func unknown() {
        #expect(!Self.isEcho(Self.update(key: nil)))
        #expect(!Self.isEcho(.unknown, inFlight: true))
        #expect(!LibraryEchoPolicy.isOwnEcho(.unknown, resolvedKey: Self.key, inFlight: true,
                                             lastLocalWrite: Self.now, local: Self.local(), now: Self.now))
    }

    @Test("Deletes: an echo only when this device no longer shows the title")
    func deletes() {
        let delete = LibraryRealtimeEvent(action: .delete, key: Self.key, rowId: 55)
        #expect(Self.isEcho(delete, local: nil))
        #expect(!Self.isEcho(delete, local: Self.local()), "another device removed a title this device still shows")
    }

    @Test("Ledger: a key-less delete resolves through a recent write's row id; ambiguous ids resolve to nothing")
    func ledger() {
        var ledger = LibraryLocalWriteLedger()
        ledger.record(Self.key, rowIds: [55, 0], at: Self.now)
        let keyless = LibraryRealtimeEvent(action: .delete, key: nil, rowId: 55)
        #expect(LibraryEchoPolicy.resolvedKey(keyless, ledger: ledger) == Self.key)
        ledger.record(MediaKey(kind: .manga, id: 7), rowIds: [55], at: Self.now)
        #expect(LibraryEchoPolicy.resolvedKey(keyless, ledger: ledger) == nil, "anime and manga row ids are independent")
        ledger.prune(now: Self.now.addingTimeInterval(6))
        #expect(ledger.writes.isEmpty)
        #expect(ledger.lastWrite(for: Self.key) == nil)
    }
}

@Suite("Library realtime: payload description")
struct LibraryRealtimePayloadTests {
    static func record(_ json: String) throws -> [String: AnyJSON] {
        try JSONDecoder().decode([String: AnyJSON].self, from: Data(json.utf8))
    }

    @Test("Insert/update/delete payloads decode into readable events (numbers as JSON integers)")
    func describesPayloads() throws {
        let lifecycle = UUID()
        let update = try Self.record("""
        {"id":55,"user_id":"u","anime_id":101,"list_type":"WATCHING","progress":4,"rating":8,"notes":null,
         "verdict":"keep","server_revision":9007199254,"lifecycle_id":"\(lifecycle.uuidString)","volumes_progress":null}
        """)
        let event = SupabaseUserListChannel.event(action: .update, record: update, kind: .anime)
        #expect(event.action == .update)
        #expect(event.key == MediaKey(kind: .anime, id: 101))
        #expect(event.rowId == 55)
        #expect(event.listType == "WATCHING")
        #expect(event.progress == 4)
        #expect(event.rating == 8)
        #expect(event.notes == nil)
        #expect(event.verdict == "keep")
        #expect(event.serverRevision == 9_007_199_254)
        #expect(event.lifecycleId == lifecycle)

        let insert = try Self.record(#"{"id":"12","manga_id":7.0,"list_type":"READING","progress":0}"#)
        let manga = SupabaseUserListChannel.event(action: .insert, record: insert, kind: .manga)
        #expect(manga.key == MediaKey(kind: .manga, id: 7))
        #expect(manga.rowId == 12)
        #expect(manga.lifecycleId == nil)

        // Default replica identity: a delete carries only the row id.
        let delete = SupabaseUserListChannel.event(action: .delete, record: try Self.record(#"{"id":55}"#), kind: .anime)
        #expect(delete.key == nil)
        #expect(delete.rowId == 55)
        #expect(SupabaseUserListChannel.event(action: .update, record: try Self.record(#"{"anime_id":1.5}"#), kind: .anime).key == nil)
    }
}

/// A list-channel fake that describes its events (the production factory's `onChange` path).
@MainActor
final class DescribingUserListChannels: UserListChannelFactory {
    final class Channel: UserListRealtimeChannel {
        let onChange: @MainActor (LibraryRealtimeEvent) -> Void
        init(onChange: @escaping @MainActor (LibraryRealtimeEvent) -> Void) { self.onChange = onChange }
        func subscribe() async {}
        func stopListening() {}
        func unsubscribe() async {}
    }

    private(set) var made: [Channel] = []

    func connect() async {}

    func makeChannel(userId: String, listUserId: String, onEvent: @escaping @MainActor () -> Void) -> (any UserListRealtimeChannel)? {
        makeChannel(userId: userId, listUserId: listUserId, onChange: { _ in onEvent() })
    }

    func makeChannel(userId: String, listUserId: String,
                     onChange: @escaping @MainActor (LibraryRealtimeEvent) -> Void) -> (any UserListRealtimeChannel)? {
        let channel = Channel(onChange: onChange)
        made.append(channel)
        return channel
    }
}

@MainActor
@Suite("Library realtime: echoes of this device's writes", .timeLimit(.minutes(1)))
struct LibraryRealtimeEchoIntegrationTests {
    static let userA = LifecycleFixtures.userA
    static let key = MediaKey(kind: .anime, id: 101)

    @Test("A confirmed +1 comes back as an echo: no Library re-read; another device's change still refreshes")
    func echoIsSuppressedForeignIsNot() async throws {
        let suite = "kuro.tests.realtime-echo.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let channels = DescribingUserListChannels()
        let backend = FakeLibraryBackend()
        let graph = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: FakeNotificationCenter(),
            libraryBackend: backend,
            userListChannels: channels,
            libraryRealtimeDebounce: .zero
        )
        defer { defaults.removePersistentDomain(forName: suite) }
        backend.setRows([FakeLibraryBackend.entry(.anime, 101, rowId: 55, progress: 3, rating: 8)], for: Self.userA)
        await graph.session.applySession(userId: Self.userA, email: "a@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
        await graph.libraryRealtime.startIfNeeded()
        let channel = try #require(channels.made.last)
        func fetches() -> Int {
            backend.calls.filter { if case .fetchAll = $0 { return true } else { return false } }.count
        }
        let fetchesBefore = fetches()

        let outcome = await graph.libraryActions.apply(LibraryEdit(progress: .set(4)), to: Self.key, createIfMissing: nil)
        guard case .applied = outcome else {
            Issue.record("the edit was not applied: \(outcome)")
            return
        }
        channel.onChange(LibraryRealtimeEvent(action: .update, key: Self.key, rowId: 55, listType: "WATCHING",
                                              progress: 4, rating: 8))
        #expect(graph.libraryRealtime.suppressedEchoCount == 1)
        #expect(graph.libraryRealtime.debounceTask == nil, "the echo schedules nothing")

        channel.onChange(LibraryRealtimeEvent(action: .update, key: Self.key, rowId: 55, listType: "WATCHING",
                                              progress: 9, rating: 8))
        let refresh = try #require(graph.libraryRealtime.debounceTask, "another device's change refreshes")
        await refresh.value
        await graph.libraryActions.libraryRefreshTask?.value
        #expect(fetches() > fetchesBefore)
        #expect(graph.libraryRealtime.suppressedEchoCount == 1)

        await graph.session.endSession()
        #expect(graph.libraryRealtime.localWrites.writes.isEmpty, "the ledger is forgotten with the session")
    }
}
