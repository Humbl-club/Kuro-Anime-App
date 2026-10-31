import Foundation
import KuroCore
import Testing

@MainActor
@Suite("Presentation action admission")
struct AccountActionScopeTests {
    @Test("A queued intent cannot dispatch under another account or a remounted screen",
          arguments: ["account", "remount"])
    func queuedIntent(change: String) async throws {
        let session = AccountSessionCoordinator()
        _ = session.begin(userId: "account-a")
        let scope = AccountActionScope()
        scope.activate(session: session)
        let renderedOrigin = try #require(scope.capture(session: session))
        let otherPresentation = AccountActionScope()
        otherPresentation.activate(session: session)
        #expect(!otherPresentation.isCurrent(renderedOrigin, session: session), "a ticket belongs to one presentation instance")
        var dispatches = 0
        let queued = try #require(scope.launch(origin: renderedOrigin, session: session) { ticket in
            // Exercise the real credential-admission owner too, rather than a replacement guard.
            _ = try? await session.withCredentialLease(for: ticket.account) {
                dispatches += 1
            }
        })
        // No suspension between scheduling and the transition: the action is still queued.
        if change == "account" {
            _ = session.begin(userId: "account-b")
            #expect(scope.capture(session: session) == nil)
        } else {
            scope.deactivate()
            scope.activate(session: session)
        }
        await queued.value
        #expect(dispatches == 0)
        #expect(scope.launch(origin: renderedOrigin, session: session) { _ in dispatches += 1 } == nil)

        scope.deactivate()
        scope.activate(session: session)
        let fresh = try #require(scope.launch(origin: scope.capture(session: session), session: session) { ticket in
            _ = try? await session.withCredentialLease(for: ticket.account) { dispatches += 1 }
        })
        await fresh.value
        #expect(dispatches == 1)
    }

    @Test("An operation ignoring cancellation cannot publish after its presentation ends")
    func heldCompletion() async throws {
        let session = AccountSessionCoordinator()
        _ = session.begin(userId: "account-a")
        let scope = AccountActionScope()
        scope.activate(session: session)
        var reply: CheckedContinuation<Void, Never>?
        var publications = 0
        let held = try #require(scope.launch(origin: scope.capture(session: session), session: session) { ticket in
            await withCheckedContinuation { reply = $0 }
            guard scope.isCurrent(ticket, session: session) else { return }
            publications += 1
        })
        while reply == nil { await Task.yield() }
        scope.deactivate()
        scope.activate(session: session)
        reply?.resume()
        await held.value
        #expect(publications == 0)
    }
}

@MainActor
@Suite("Account session coordinator")
struct AccountSessionCoordinatorTests {
    @Test("Stale contexts are rejected after switch, sign-out and re-sign-in; a same-user refresh keeps the context")
    func transitionTable() throws {
        let coordinator = AccountSessionCoordinator()
        #expect(coordinator.isCurrent(nil))

        guard case .started(let a) = coordinator.begin(userId: "user-a") else {
            Issue.record("signed-out -> A must be .started")
            return
        }
        // SDK uuidString (upper-case) vs JWT subject (lower-case): same user, same context.
        #expect(coordinator.begin(userId: "USER-A") == .unchanged(a))
        #expect(coordinator.current == a)
        #expect(coordinator.isCurrent(a))
        #expect(AccountSessionCoordinator.sameUser("6F1C4C3E-0A7B", "6f1c4c3e-0a7b"))
        #expect(!AccountSessionCoordinator.sameUser("user-a", "user-b"))

        guard case .switched(let from, let b) = coordinator.begin(userId: "user-b") else {
            Issue.record("A -> B must be .switched")
            return
        }
        #expect(from == a)
        #expect(b.generation > a.generation)
        #expect(!coordinator.isCurrent(a))
        #expect(coordinator.isCurrent(b))

        coordinator.end()
        coordinator.end()
        #expect(coordinator.current == nil)
        #expect(!coordinator.isCurrent(b))
        #expect(coordinator.isCurrent(nil))

        // A signs in again: a new generation, so work captured under the first A context stays stale.
        guard case .started(let aAgain) = coordinator.begin(userId: "user-a") else {
            Issue.record("signed-out -> A must be .started")
            return
        }
        #expect(aAgain != a)
        #expect(!coordinator.isCurrent(a))
        #expect(coordinator.isCurrent(aAgain))
    }
}

/// Holds work closures open until the test releases them; reports each start in order.
@MainActor
private final class WorkGate {
    private var waiting: [String: CheckedContinuation<String, Never>] = [:]
    private let startedStream: AsyncStream<String>
    private let started: AsyncStream<String>.Continuation
    private var startedIterator: AsyncStream<String>.Iterator
    private(set) var invocations: [String] = []

    init() {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        startedStream = stream
        started = continuation
        startedIterator = stream.makeAsyncIterator()
    }

    func work(_ id: String) async -> String {
        invocations.append(id)
        return await withCheckedContinuation { continuation in
            waiting[id] = continuation
            started.yield(id)
        }
    }

    func nextStarted() async -> String? {
        // The iterator shares its stream storage; a local copy avoids an inout across `await`.
        var iterator = startedIterator
        let next = await iterator.next(isolation: MainActor.shared)
        startedIterator = iterator
        return next
    }

    func release(_ id: String, with value: String) {
        waiting.removeValue(forKey: id)?.resume(returning: value)
    }
}

@MainActor
@Suite("Account-scoped in-flight loads")
struct AccountScopedLoadsTests {
    let a = AccountContext(userId: "user-a", generation: 1)
    let b = AccountContext(userId: "user-b", generation: 2)

    @Test("An obsolete completion cannot clear or cancel its successor's slot", .timeLimit(.minutes(1)))
    func predecessorCannotClearSuccessor() async throws {
        let loads = AccountScopedLoads<String, String>()
        let gate = WorkGate()

        let first = Task { try await loads.run(key: "lists", context: a) { await gate.work("A") } }
        #expect(await gate.nextStarted() == "A")
        let second = Task { try await loads.run(key: "lists", context: b) { await gate.work("B") } }
        #expect(await gate.nextStarted() == "B")
        #expect(loads.isRunning("lists", for: b))

        gate.release("A", with: "rows of A")
        // The replaced load still completes with its own value for its own caller.
        #expect(try await first.value == "rows of A")
        #expect(loads.isRunning("lists", for: b), "A's completion must not clear B's slot")
        #expect(!loads.isRunning("lists", for: a))

        gate.release("B", with: "rows of B")
        #expect(try await second.value == "rows of B")
        #expect(!loads.isRunning("lists"))
    }

    @Test("runFresh never joins an earlier entry, leaves it running, and later run calls join the fresh one",
          .timeLimit(.minutes(1)))
    func runFreshStartsNewWorkAndBecomesJoinable() async throws {
        let loads = AccountScopedLoads<String, String>()
        let gate = WorkGate()

        let earlier = Task {
            try await loads.run(key: "lists", context: a) {
                let value = await gate.work("read-before-write")
                return Task.isCancelled ? "cancelled" : value
            }
        }
        #expect(await gate.nextStarted() == "read-before-write")
        let fresh = Task { try await loads.runFresh(key: "lists", context: a) { await gate.work("read-after-write") } }
        #expect(await gate.nextStarted() == "read-after-write", "a fresh read must not join the earlier one")
        let joiner = Task { try await loads.run(key: "lists", context: a) { await gate.work("unexpected") } }

        gate.release("read-before-write", with: "old rows")
        #expect(try await earlier.value == "old rows", "the earlier read is not cancelled")
        #expect(loads.isRunning("lists", for: a), "the earlier completion must not clear the fresh slot")

        gate.release("read-after-write", with: "new rows")
        #expect(try await fresh.value == "new rows")
        #expect(try await joiner.value == "new rows")
        #expect(gate.invocations == ["read-before-write", "read-after-write"])
        #expect(!loads.isRunning("lists"))
    }

    @Test("A load is joined only for the same key and the same account context", .timeLimit(.minutes(1)))
    func joinsOnlySameKeyAndContext() async throws {
        let loads = AccountScopedLoads<String, String>()
        let gate = WorkGate()

        let leader = Task { try await loads.run(key: "lists", context: a) { await gate.work("lists-A") } }
        #expect(await gate.nextStarted() == "lists-A")
        let joiner = Task { try await loads.run(key: "lists", context: a) { await gate.work("lists-A-again") } }
        let otherKey = Task { try await loads.run(key: "upcoming", context: a) { await gate.work("upcoming-A") } }
        #expect(await gate.nextStarted() == "upcoming-A", "same key + same context must join, not start new work")

        gate.release("lists-A", with: "lists")
        gate.release("upcoming-A", with: "upcoming")
        #expect(try await leader.value == "lists")
        #expect(try await joiner.value == "lists")
        #expect(try await otherKey.value == "upcoming")
        #expect(gate.invocations == ["lists-A", "upcoming-A"])
        #expect(!loads.isRunning("lists"))
        #expect(!loads.isRunning("upcoming"))
    }
}

@MainActor
@Suite("Credential leases (F33)")
struct CredentialLeaseTests {
    @Test("A lease runs only while its context is current: refused at admission when obsolete, and never started when its context ended after admission (it starts on a later turn)",
          .timeLimit(.minutes(1)))
    func leaseIsRevalidatedBeforeItStarts() async throws {
        let coordinator = AccountSessionCoordinator()
        guard case .started(let a) = coordinator.begin(userId: "user-a") else {
            Issue.record("signed-out -> A must be .started")
            return
        }
        var ran: [String] = []

        // Admitted while A is current; A's session ends before the lease's work started.
        let admitted = Task.immediate { @MainActor in
            try await coordinator.withCredentialLease(for: a) { ran.append("admitted"); return "sent" }
        }
        _ = coordinator.begin(userId: "user-b")
        await #expect(throws: CancellationError.self) { _ = try await admitted.value }

        // Refused at admission: A is not current.
        await #expect(throws: CancellationError.self) {
            _ = try await coordinator.withCredentialLease(for: a) { ran.append("obsolete"); return "sent" }
        }
        #expect(ran.isEmpty, "an obsolete lease ran: \(ran)")
        #expect(!coordinator.hasCredentialLeases)

        // The current context's lease runs.
        let b = try #require(coordinator.current)
        #expect(try await coordinator.withCredentialLease(for: b) { ran.append("current"); return "sent" } == "sent")
        #expect(ran == ["current"])
    }

    @Test("A transition cancels a running lease of the replaced context; it ends in CancellationError whatever its request reported",
          .timeLimit(.minutes(1)))
    func transitionCancelsRunningLease() async throws {
        let coordinator = AccountSessionCoordinator()
        _ = coordinator.begin(userId: "user-a")
        let a = try #require(coordinator.current)
        let gate = WorkGate()
        var sawCancellation = false
        let running = Task { @MainActor in
            try await coordinator.withCredentialLease(for: a) {
                let value = await gate.work("request-of-A")
                sawCancellation = Task.isCancelled
                return value
            }
        }
        #expect(await gate.nextStarted() == "request-of-A")
        #expect(coordinator.hasCredentialLeases)

        coordinator.end()
        gate.release("request-of-A", with: "success of A")
        await #expect(throws: CancellationError.self) { _ = try await running.value }
        #expect(sawCancellation, "the ended account's request was not cancelled")
        #expect(!coordinator.hasCredentialLeases)
    }

    @Test("A credential change waits until every lease in flight has finished and admits none until it ends",
          .timeLimit(.minutes(1)))
    func credentialChangeDrainsLeases() async throws {
        let coordinator = AccountSessionCoordinator()
        _ = coordinator.begin(userId: "user-a")
        let a = try #require(coordinator.current)
        let gate = WorkGate()
        let inFlight = Task { @MainActor in
            try await coordinator.withCredentialLease(for: a) { await gate.work("in-flight") }
        }
        #expect(await gate.nextStarted() == "in-flight")

        var changed: AccountSessionCoordinator.CredentialChange?
        let change = Task { @MainActor in
            let started = await coordinator.beginCredentialChange()
            changed = started
            return started
        }
        await Task.yield()
        #expect(changed == nil, "the change began while a lease could still be dispatched")
        #expect(coordinator.isChangingCredentials)
        await #expect(throws: CancellationError.self, "a lease was admitted during the credential change") {
            _ = try await coordinator.withCredentialLease(for: a) { "late" }
        }

        gate.release("in-flight", with: "done")
        #expect(try await inFlight.value == "done", "the current account's lease finishes normally")
        let token = await change.value
        #expect(!coordinator.hasCredentialLeases)

        coordinator.endCredentialChange(token)
        #expect(!coordinator.isChangingCredentials)
        #expect(try await coordinator.withCredentialLease(for: a) { "after" } == "after")
    }
}
