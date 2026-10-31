import Foundation
import KuroCore
import KuroLibrary
import Observation
import Synchronization
import Testing

/// Resumes a continuation at most once, from any thread.
final class OnceContinuation<Value: Sendable>: Sendable {
    private let slot: Mutex<CheckedContinuation<Value, Never>?>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        slot = Mutex(continuation)
    }

    func resume(returning value: Value) {
        let continuation = slot.withLock { slot -> CheckedContinuation<Value, Never>? in
            let taken = slot
            slot = nil
            return taken
        }
        continuation?.resume(returning: value)
    }
}

/// Releases every outstanding wait once the test is cancelled (its time limit), so a regression
/// that leaves a call unanswered or a condition unmet fails the test instead of hanging the run.
final class Abandonment: Sendable {
    private struct State {
        var fired = false
        var actions: [@Sendable () -> Void] = []
    }

    private let state = Mutex(State())

    func onAbandon(_ action: @escaping @Sendable () -> Void) {
        let runNow = state.withLock { state -> Bool in
            if state.fired { return true }
            state.actions.append(action)
            return false
        }
        if runNow { action() }
    }

    func fire() {
        let actions = state.withLock { state -> [@Sendable () -> Void] in
            state.fired = true
            defer { state.actions = [] }
            return state.actions
        }
        for action in actions { action() }
    }
}

/// A `LibraryBackend` that models only external outcomes: every call is reported in order and
/// waits until the test answers it with rows, a write result or an error. It holds no library
/// policy (no ordering, merging, validation or account checks).
final class ControlledBackend: LibraryBackend {
    enum Request: Sendable, Equatable {
        case fetchAll
        case edit(LibraryEdit, createIfMissing: ListStatus?, baseRevision: Int64?)
        case insertIfMissing(ListStatus)
        case remove
    }

    enum Answer: Sendable {
        case entries([LibraryEntry])
        case write(LibraryWriteResult)
        case removed
        case failure(LibraryError)
    }

    struct Call: Sendable {
        let request: Request
        let key: MediaKey?
        let account: AccountContext
        let mutationId: UUID?
        fileprivate let reply: OnceContinuation<Answer>

        func answer(_ answer: Answer) {
            reply.resume(returning: answer)
        }
    }

    let calls: AsyncStream<Call>
    private let callSink: AsyncStream<Call>.Continuation
    private let abandonment: Abandonment

    init(abandonment: Abandonment) {
        self.abandonment = abandonment
        (calls, callSink) = AsyncStream<Call>.makeStream()
    }

    private func call(_ request: Request, key: MediaKey?, account: AccountContext, mutationId: UUID? = nil) async -> Answer {
        await withCheckedContinuation { continuation in
            let reply = OnceContinuation(continuation)
            abandonment.onAbandon { reply.resume(returning: .failure(.unavailable(message: "unanswered when the test ended"))) }
            callSink.yield(Call(request: request, key: key, account: account, mutationId: mutationId, reply: reply))
        }
    }

    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] {
        switch await call(.fetchAll, key: nil, account: account) {
        case .entries(let entries): return entries
        case .failure(let error): throw error
        default: throw LibraryError.unavailable(message: "test answered fetchAll with a non-row answer")
        }
    }

    func edit(
        _ edit: LibraryEdit,
        key: MediaKey,
        createIfMissing: ListStatus?,
        mutationId: UUID,
        baseRevision: Int64?,
        account: AccountContext
    ) async throws -> LibraryWriteResult {
        let request = Request.edit(edit, createIfMissing: createIfMissing, baseRevision: baseRevision)
        return try Self.writeResult(await call(request, key: key, account: account, mutationId: mutationId))
    }

    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult {
        try Self.writeResult(await call(.insertIfMissing(status), key: key, account: account))
    }

    func remove(_ key: MediaKey, account: AccountContext) async throws {
        switch await call(.remove, key: key, account: account) {
        case .removed: return
        case .failure(let error): throw error
        default: throw LibraryError.unavailable(message: "test answered remove with a non-removal answer")
        }
    }

    private static func writeResult(_ answer: Answer) throws -> LibraryWriteResult {
        switch answer {
        case .write(let result): return result
        case .failure(let error): throw error
        default: throw LibraryError.unavailable(message: "test answered a write with a non-write answer")
        }
    }
}

/// Records delivered changes and what the store projected for the key at delivery time.
@MainActor
final class RecordingSink: LibraryChangeSink {
    weak var store: LibraryStore?
    private(set) var changes: [LibraryChange] = []
    private(set) var projectionAtDelivery: [LibraryEntry?] = []

    func libraryDidChange(_ change: LibraryChange) {
        changes.append(change)
        projectionAtDelivery.append(store?.entry(for: change.key))
    }
}

/// Runs `body` with a fresh harness; when the test is cancelled (time limit) every outstanding
/// backend call and wait is released so the test fails instead of hanging.
@MainActor
func withHarness(_ body: (Harness) async throws -> Void) async throws {
    let harness = Harness()
    let abandonment = harness.abandonment
    try await withTaskCancellationHandler {
        try await body(harness)
    } onCancel: {
        abandonment.fire()
    }
}

/// One store wired to a controlled backend, a recording sink and a real session coordinator.
@MainActor
final class Harness {
    let abandonment = Abandonment()
    let backend: ControlledBackend
    let sink = RecordingSink()
    let coordinator = AccountSessionCoordinator()
    let store: LibraryStore
    private var calls: AsyncStream<ControlledBackend.Call>.Iterator

    init() {
        backend = ControlledBackend(abandonment: abandonment)
        store = LibraryStore(backend: backend, sinks: [sink], now: { Fixture.now })
        calls = backend.calls.makeAsyncIterator()
        sink.store = store
    }

    /// The next call the store sent to the backend (waits until it arrives).
    func nextCall() async throws -> ControlledBackend.Call {
        // The iterator shares its stream storage; a local copy avoids an inout across `await`.
        var iterator = calls
        let call = await iterator.next(isolation: MainActor.shared)
        calls = iterator
        return try #require(call, "the store sent no further backend call")
    }

    /// Runs the app's session-funnel equivalent: begin the session, bind the store.
    @discardableResult
    func signIn(_ userId: String) -> AccountContext {
        let context: AccountContext
        switch coordinator.begin(userId: userId) {
        case .started(let next), .unchanged(let next), .switched(_, let next): context = next
        }
        store.bind(context)
        return context
    }

    func signOut() {
        coordinator.end()
        store.reset()
    }

    /// Completes one refresh with `entries` as the backend's rows.
    func load(_ entries: [LibraryEntry]) async throws {
        let refresh = Task { try await store.refresh() }
        let call = try await nextCall()
        #expect(call.request == .fetchAll)
        call.answer(.entries(entries))
        try await refresh.value
    }

    /// Waits until `condition` holds, re-checking on every observed change of the store.
    func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        while !condition() {
            if Task.isCancelled {
                Issue.record("the awaited store state never appeared")
                return
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resume = OnceContinuation(continuation)
                abandonment.onAbandon { resume.resume(returning: ()) }
                withObservationTracking {
                    _ = condition()
                } onChange: {
                    resume.resume(returning: ())
                }
            }
        }
    }
}

enum Fixture {
    static let userA = "6f1c2a9e-4b7d-4f1e-9a51-0c2d3e4f5a6b"
    static let userB = "0a9b8c7d-6e5f-4a3b-8c2d-1e0f9a8b7c6d"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let earlier = Date(timeIntervalSince1970: 1_700_000_000)

    static let anime42 = MediaKey(kind: .anime, id: 42)
    static let anime7 = MediaKey(kind: .anime, id: 7)
    static let manga7 = MediaKey(kind: .manga, id: 7)

    static func rating(_ value: Int) -> UserRating? {
        UserRating(value: value)
    }

    static func entry(
        _ key: MediaKey,
        rowId: Int = 1,
        status: ListStatus = .current,
        progress: Int = 0,
        rating: Int? = nil,
        notes: String? = nil,
        verdict: Verdict? = nil,
        updatedAt: Date = earlier,
        revision: Int64? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            key: key,
            rowId: rowId,
            status: status,
            progress: progress,
            rating: rating.flatMap { UserRating(value: $0) },
            notes: notes,
            verdict: verdict,
            createdAt: earlier,
            updatedAt: updatedAt,
            revision: revision
        )
    }
}
