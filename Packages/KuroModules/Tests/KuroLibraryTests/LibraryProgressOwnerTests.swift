import Foundation
import KuroCore
import KuroLibrary
import SQLite3
import Testing

@MainActor
@Suite("Library durable progress authority")
struct LibraryProgressOwnerTests {
    @Test("Overlapping actions share the Library projection and an older ACK cannot clear a newer action", .timeLimit(.minutes(1)))
    func overlappingActionsAndAcknowledgement() async throws {
        let h = try await ProgressHarness()
        defer { h.close() }
        let first = Task { await h.store.advanceProgress(for: h.key) }
        try await h.waitForCalls(1)
        #expect(h.sender.calls[0][0].position == 4)
        #expect(h.store.entry(for: h.key)?.progress == 4)
        let newer = await h.store.apply(LibraryEdit(status: .set(.completed), progress: .set(8)), to: h.key)
        #expect(newer.change?.current?.progress == 8)
        #expect(h.store.entry(for: h.key)?.status == .completed)
        #expect(h.store.allEntries.first?.progress == 8)
        h.sender.answer()
        try await h.waitForCalls(2)
        #expect(h.sender.calls[1][0].position == 8)
        #expect(h.sender.calls[1][0].baseRevision == 2)
        #expect(h.store.entry(for: h.key)?.progress == 8)
        h.sender.answer()
        _ = await first.value
        try await h.waitUntil { h.store.pendingProgress(for: h.key) == nil }
        #expect(h.store.entry(for: h.key)?.progress == 8)
        #expect(h.store.entry(for: h.key)?.status == .completed)
        #expect(h.store.entry(for: h.key)?.notes == "keep notes")
        #expect(h.store.entry(for: h.key)?.rating?.value == 8)
        #expect(h.sink.changes.contains { $0.previous?.status == .current && $0.current?.status == .completed })
    }

    @Test("A lost response retries the same body in process and then sends its newer successor", .timeLimit(.minutes(1)))
    func lostResponseRecoveryAndFractionalUnit() async throws {
        let h = try await ProgressHarness()
        defer { h.close() }
        let unit = UUID()
        _ = try await h.store.storeProgress(ProgressIntent(accountId: h.account.userId, medium: "anime", mediaId: h.key.id,
            lifecycleId: h.lifecycle, unitId: unit, baseRevision: 1, position: 4, positionLabel: "4.5", priorPosition: 3))
        try await h.waitForCalls(1)
        let original = h.sender.calls[0][0]
        h.sender.fail()
        try await h.waitUntil { try await h.box.pending(accountId: h.account.userId, limit: 50).count == 1 }
        _ = try await h.store.storeProgress(ProgressIntent(accountId: h.account.userId, medium: "anime", mediaId: h.key.id,
            lifecycleId: h.lifecycle, baseRevision: 1, position: 6, priorPosition: 4))
        let drain = Task { await h.store.drainProgress() }
        try await h.waitForCalls(2)
        #expect(h.sender.calls[1][0].mutationId == original.mutationId)
        #expect(h.sender.calls[1][0].baseRevision == original.baseRevision)
        #expect(h.sender.calls[1][0].positionLabel == "4.5" && h.sender.calls[1][0].unitId == unit)
        #expect(h.store.displayedProgressLabel(for: h.key, serverLabel: "3", lifecycleId: h.lifecycle) == "6")
        h.sender.answer()
        try await h.waitForCalls(3)
        #expect(h.sender.calls[2][0].position == 6)
        #expect(h.sender.calls[2][0].baseRevision == 2)
        h.sender.answer()
        await drain.value
        try await h.waitUntil { h.store.pendingProgress(for: h.key) == nil }
        #expect(h.store.entry(for: h.key)?.progress == 6)
    }

    @Test("Cancellation and account replacement never publish an old receipt to the next account", .timeLimit(.minutes(1)))
    func accountReplacementAndLifecycle() async throws {
        let h = try await ProgressHarness()
        defer { h.close() }
        _ = await h.store.advanceProgress(for: h.key)
        try await h.waitForCalls(1)
        let replacement = AccountContext(userId: "account-b", generation: 2)
        h.store.bind(replacement)
        h.sender.answer()
        try await h.waitUntil { try await h.box.pending(accountId: h.account.userId, limit: 50).count == 1 }
        #expect(h.store.entry(for: h.key) == nil)
        #expect(h.store.pendingProgress(for: h.key) == nil)
        #expect(h.store.progressConflict == nil)
    }

    @Test("An online notes leg cannot reorder later progress/status gestures", .timeLimit(.minutes(1)))
    func mixedPatchPreservesGestureOrder() async throws {
        let h = try await ProgressHarness(holdingPatch: true)
        defer { h.close() }
        let mixed = Task { await h.store.apply(LibraryEdit(status: .set(.completed), progress: .set(8), notes: .set("new note")), to: h.key) }
        try await h.waitUntil { h.patch?.calls == 1 && h.store.pendingProgress(for: h.key)?.position == 8 }
        #expect(h.sender.calls.isEmpty, "Progress dispatch waits on the same Library key reservation")
        _ = await h.store.advanceProgress(for: h.key)
        _ = await h.store.apply(LibraryEdit(status: .set(.current)), to: h.key)
        #expect(h.store.entry(for: h.key)?.progress == 9)
        #expect(h.store.entry(for: h.key)?.status == .current)
        h.patch?.answer()
        #expect(await mixed.value.change != nil)
        try await h.waitForCalls(1)
        #expect(h.sender.calls[0][0].position == 9)
        #expect(h.sender.calls[0][0].status == "CURRENT")
        #expect(h.sender.calls[0][0].baseRevision == 2)
        h.sender.answer()
        try await h.waitUntil { h.store.pendingProgress(for: h.key) == nil }
        #expect(h.store.entry(for: h.key)?.notes == "new note")
        #expect(h.store.entry(for: h.key)?.status == .current)
    }

    @Test("A mixed action cannot resume under a replacement account or lifecycle", .timeLimit(.minutes(1)), arguments: [false, true])
    func mixedPatchReplacement(replaceAccount: Bool) async throws {
        let h = try await ProgressHarness(holdingPatch: true)
        defer { h.close() }
        let mixed = Task { await h.store.apply(LibraryEdit(progress: .set(8), notes: .set("new note")), to: h.key) }
        try await h.waitUntil { h.patch?.calls == 1 && h.store.pendingProgress(for: h.key) != nil }
        if replaceAccount { h.store.bind(AccountContext(userId: "account-b", generation: 2)) }
        h.patch?.answer(replaceLifecycle: !replaceAccount)
        #expect(await mixed.value.error == (replaceAccount ? .notAuthenticated : .notFound))
        if replaceAccount { #expect(h.store.entry(for: h.key) == nil) }
        else { #expect(h.store.pendingProgress(for: h.key) == nil) }
        #expect(h.sender.calls.isEmpty)
    }

    @Test("Failed disk admission reports failure before projection and a later write remains usable", .timeLimit(.minutes(1)))
    func failedDiskAdmission() async throws {
        let h = try await ProgressHarness()
        defer { h.close() }
        var connection: OpaquePointer?
        #expect(sqlite3_open(h.url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        #expect(sqlite3_exec(connection,"create trigger fail_insert before insert on intents begin select raise(abort, 'injected'); end;",nil,nil,nil) == SQLITE_OK)
        #expect((await h.store.advanceProgress(for: h.key)).error != nil)
        #expect(h.store.entry(for: h.key)?.progress == 3)
        #expect(h.sender.calls.isEmpty)
        #expect(sqlite3_exec(connection,"drop trigger fail_insert",nil,nil,nil) == SQLITE_OK)
        #expect((await h.store.advanceProgress(for: h.key)).change?.current?.progress == 4)
        try await h.waitForCalls(1)
        h.sender.answer()
        try await h.waitUntil { h.store.pendingProgress(for: h.key) == nil }
    }
}

@MainActor
private final class ProgressHarness {
    let key = MediaKey(kind: .anime, id: 7)
    let lifecycle = UUID()
    let account = AccountContext(userId: "account-a", generation: 1)
    let url: URL
    let box: ProgressOutbox
    let store: LibraryStore
    let sender = HeldProgressSender()
    let sink = ProgressSink()
    let patch: HeldPatchBackend?
    init(holdingPatch: Bool = false) async throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-owner-\(UUID()).sqlite")
        box = try ProgressOutbox(path: url.path)
        let row = LibraryEntry(key: key, rowId: 1, status: .current, progress: 3, rating: UserRating(value: 8),
            notes: "keep notes", createdAt: .distantPast, updatedAt: .distantPast, revision: 1, lifecycleId: lifecycle)
        patch = holdingPatch ? HeldPatchBackend(row: row) : nil
        let backend: any LibraryBackend
        if let patch { backend = patch } else { backend = ProgressBackend(rows: [row]) }
        store = LibraryStore(backend: backend, sinks: [sink])
        store.bind(account)
        try await store.refresh()
        let sender = sender
        store.configureProgress(outbox: box) { items, _ in try await sender.send(items) }
    }
    func close() { store.cancelProgressWork(); sender.fail(); patch?.fail(); try? FileManager.default.removeItem(at: url) }
    func waitForCalls(_ count: Int) async throws { try await waitUntil { self.sender.calls.count >= count } }
    func waitUntil(_ predicate: @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !predicate() {
            if ContinuousClock.now > deadline { throw LibraryError.unavailable(message: "Expected owner transition did not occur") }
            await Task.yield()
        }
    }
}

@MainActor
private final class HeldProgressSender {
    var calls: [[ProgressIntent]] = []
    var continuation: CheckedContinuation<[LibraryProgressReceipt], Error>?
    func send(_ items: [ProgressIntent]) async throws -> [LibraryProgressReceipt] {
        calls.append(items)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func answer() {
        guard let continuation, let items = calls.last else { return }
        self.continuation = nil
        continuation.resume(returning: items.map { LibraryProgressReceipt(mutationId: $0.mutationId, outcome: "applied", position: $0.position, revision: ($0.baseRevision ?? 0) + 1) })
    }
    func fail() { let held = continuation; continuation = nil; held?.resume(throwing: URLError(.networkConnectionLost)) }
}

private struct ProgressBackend: LibraryBackend {
    let rows: [LibraryEntry]
    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] { rows }
    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message: "Unexpected insert") }
    func edit(_ edit: LibraryEdit, key: MediaKey, createIfMissing: ListStatus?, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message: "Unexpected direct write") }
    func remove(_ key: MediaKey, account: AccountContext) async throws { throw LibraryError.unavailable(message: "Unexpected remove") }
}

@MainActor
private final class ProgressSink: LibraryChangeSink {
    var changes: [LibraryChange] = []
    func libraryDidChange(_ change: LibraryChange) { changes.append(change) }
}

@MainActor
private final class HeldPatchBackend: LibraryBackend {
    var row: LibraryEntry
    var calls = 0
    var continuation: CheckedContinuation<LibraryWriteResult, Error>?
    init(row: LibraryEntry) { self.row = row }
    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] { [row] }
    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message: "Unexpected insert") }
    func edit(_ edit: LibraryEdit, key: MediaKey, createIfMissing: ListStatus?, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws -> LibraryWriteResult {
        #expect(edit.progress == .unchanged && edit.status == .unchanged)
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func remove(_ key: MediaKey, account: AccountContext) async throws { throw LibraryError.unavailable(message: "Unexpected removal") }
    func answer(replaceLifecycle: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        row.notes = "new note"; row.revision = 2
        if replaceLifecycle { row.lifecycleId = UUID() }
        continuation.resume(returning: LibraryWriteResult(entry: row, created: false))
    }
    func fail() { let held = continuation; continuation = nil; held?.resume(throwing: URLError(.networkConnectionLost)) }
}

@Test func unsentFieldMasksPreserveExplicitStatusAndUnitIdentity() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-mask-\(UUID()).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path), lifecycle = UUID(), unit = UUID()
    _ = try await box.enqueue(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1, lifecycleId: lifecycle,
        unitId: unit, baseRevision: 1, position: 7, positionLabel: "7.5", status: "COMPLETED", priorPosition: 3))
    let status = try await box.enqueue(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1, lifecycleId: lifecycle,
        baseRevision: 1, position: 3, writesPosition: false, status: "CURRENT", priorPosition: 3))
    #expect(status.position == 7 && status.unitId == unit && status.positionLabel == "7.5")
    #expect(status.writesPosition && status.status == "CURRENT")
    let next = try await box.advance(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1, lifecycleId: lifecycle,
        baseRevision: 1, position: 3, priorPosition: 3))
    #expect(next.position == 8 && next.status == "CURRENT")
    #expect(next.unitId == nil && next.positionLabel == nil)
    #expect(try await box.pending(accountId: "a", limit: 50).first == next)
    _ = try await box.claim(accountId: "a")
    try await box.acknowledge(next.mutationId, revision: 2, position: 8)
    let statusOnly = try await box.enqueue(ProgressIntent(accountId: "a", medium: "manga", mediaId: 1, lifecycleId: lifecycle,
        baseRevision: 2, position: 8, writesPosition: false, status: "COMPLETED", priorPosition: 8))
    #expect(!statusOnly.writesPosition)
    let reopened = try ProgressOutbox(path: url.path)
    #expect(try await reopened.pending(accountId: "a", limit: 50).first?.writesPosition == false)
}

@Test func confirmedAccountDeletionPurgesOnlyThatAccountsProgress() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kuro-purge-\(UUID()).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let box = try ProgressOutbox(path: url.path)
    _ = try await box.enqueue(ProgressIntent(accountId: "account-a", medium: "manga", mediaId: 1,
        lifecycleId: UUID(), unitId: UUID(), baseRevision: 1, position: 7, positionLabel: "private 7.5"))
    _ = try await box.enqueue(ProgressIntent(accountId: "account-b", medium: "anime", mediaId: 1,
        lifecycleId: UUID(), baseRevision: 1, position: 4))
    try await box.removeAccount(accountId: "ACCOUNT-A")
    #expect(try await box.count(accountId: "account-a") == 0)
    #expect(try await box.pending(accountId: "account-b", limit: 50).first?.position == 4)
    let reopened = try ProgressOutbox(path: url.path)
    #expect(try await reopened.count(accountId: "account-a") == 0)
    #expect(try await reopened.count(accountId: "account-b") == 1)
}

@MainActor
@Test func authoritativeNilClearsHeldDetailIdentity() async throws {
    let key = MediaKey(kind: .manga, id: 7), life = UUID(), oldUnit = UUID()
    let row = LibraryEntry(key: key, rowId: 1, status: .current, progress: 8,
        createdAt: .distantPast, updatedAt: .distantPast, revision: 3, lifecycleId: life)
    let store = LibraryStore(backend: ProgressBackend(rows: [row]))
    store.bind(AccountContext(userId: "a", generation: 1)); try await store.refresh()
    #expect(store.displayedProgressLabel(for: key, serverLabel: "7.5", lifecycleId: life, serverRevision: 2) == nil)
    #expect(store.displayedUnitId(for: key, serverUnitId: oldUnit, lifecycleId: life, serverRevision: 2) == nil)
    #expect(store.displayedProgressLabel(for: key, serverLabel: "9.5", lifecycleId: life, serverRevision: 4) == "9.5")
    #expect(store.displayedUnitId(for: key, serverUnitId: oldUnit, lifecycleId: UUID(), serverRevision: 2) == nil)
}

@MainActor
private final class ImportUndoGate {
    var entered = false
    var continuation: CheckedContinuation<Void,Never>?
    func hold() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
@Test func importUndoReservationClosesOnlyAffectedAdmissionAndReleasesOnFailure() async throws {
    let h = try await ProgressHarness(); defer { h.close() }
    let gate = ImportUndoGate()
    let undo = Task {
        try await h.store.withImportMutationReservation(keys: [h.key], account: h.account) {
            await gate.hold(); throw LibraryError.retryable(message: "compensation response lost")
        }
    }
    try await h.waitUntil { gate.entered }
    let blocked = await h.store.apply(LibraryEdit(notes: .set("must not dispatch")), to: h.key)
    #expect(blocked.error == .retryable(message: "This title is being changed by an import. Try again after Apply or Undo finishes."))
    let unrelated = await h.store.save(MediaKey(kind: .manga, id: 99), status: .planning)
    #expect(unrelated.error == .unavailable(message: "Unexpected insert"))
    await #expect(throws: LibraryError.self) {
        _ = try await h.store.storeProgress(ProgressIntent(accountId: h.account.userId, medium: "anime",
            mediaId: h.key.id, lifecycleId: h.lifecycle, baseRevision: 1, position: 4))
    }
    gate.release(); _ = await undo.result
    let allowed = await h.store.apply(LibraryEdit(notes: .set("allowed after failure")), to: h.key)
    #expect(allowed.error == .unavailable(message: "Unexpected direct write"))
    let cancelledGate = ImportUndoGate()
    var cancelledDispatch = false
    let cancelledUndo = Task {
        try await h.store.withImportUndoReservation(keys: [h.key], account: h.account) {
            await cancelledGate.hold()
            try Task.checkCancellation()
            cancelledDispatch = true
        }
    }
    try await h.waitUntil { cancelledGate.entered }
    cancelledUndo.cancel()
    // A noncooperative response must finish before its affected-title reservation is released.
    let stillBlocked = await h.store.apply(LibraryEdit(notes: .set("too early")), to: h.key)
    #expect(stillBlocked.error == .retryable(message: "This title is being changed by an import. Try again after Apply or Undo finishes."))
    cancelledGate.release(); _ = await cancelledUndo.result
    #expect(!cancelledDispatch)
    let afterCancellation = await h.store.apply(LibraryEdit(notes: .set("allowed after cancellation")), to: h.key)
    #expect(afterCancellation.error == .unavailable(message: "Unexpected direct write"))
    _ = try await h.box.enqueue(ProgressIntent(accountId: h.account.userId, medium: "anime",
        mediaId: h.key.id, lifecycleId: h.lifecycle, baseRevision: 1, position: 4))
    var dispatched = false
    await #expect(throws: ImportFailure.pendingTracking) {
        try await h.store.withImportMutationReservation(keys: [h.key], account: h.account) { dispatched = true }
    }
    #expect(!dispatched)
}

@MainActor
private final class ImportUndoRefreshBackend: LibraryBackend {
    var rows: [LibraryEntry] = []
    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] { rows }
    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message:"unexpected insert") }
    func edit(_ edit: LibraryEdit, key: MediaKey, createIfMissing: ListStatus?, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws -> LibraryWriteResult { throw LibraryError.unavailable(message:"unexpected edit") }
    func remove(_ key: MediaKey, account: AccountContext) async throws { throw LibraryError.unavailable(message:"unexpected remove") }
}

@MainActor
@Test func importUndoAuthoritativeRefreshReplacesRowsInsideReservation() async throws {
    let backend = ImportUndoRefreshBackend(), account = AccountContext(userId:"a",generation:1)
    let anime = MediaKey(kind:.anime,id:7), manga = MediaKey(kind:.manga,id:7)
    let imported = LibraryEntry(key:anime,rowId:1,status:.completed,progress:12,notes:"imported",
        createdAt:.distantPast,updatedAt:.distantPast,revision:2,lifecycleId:UUID())
    let added = LibraryEntry(key:manga,rowId:2,status:.current,progress:8,
        createdAt:.distantPast,updatedAt:.distantPast,revision:1,lifecycleId:UUID())
    backend.rows = [imported,added]
    let store = LibraryStore(backend:backend); store.bind(account); try await store.refresh()
    try await store.withImportUndoReservation(keys:[anime,manga],account:account) {
        var restored = imported; restored.status = .planning; restored.progress = 0
        restored.notes = "original"; restored.revision = 3
        backend.rows = [restored]
        try await store.refresh()
        #expect(store.entry(for:manga) == nil)
        #expect(store.entry(for:anime)?.notes == "original")
        #expect(store.entry(for:anime)?.progress == 0)
    }
}
