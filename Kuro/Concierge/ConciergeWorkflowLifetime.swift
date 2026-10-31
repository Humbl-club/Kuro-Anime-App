import Foundation
import KuroCore
import Observation

/// Retains chat actions and rejects their continuations after the originating chat/account ends.
/// Service credential leases still protect dispatch; this fence protects the intent before dispatch.
enum ConciergeWorkflowScope {
    struct Ticket: Equatable, Sendable {
        let account: AccountContext
        let generation: UInt64
    }

    @TaskLocal static var ticket: Ticket?
}

@MainActor
@Observable
final class ConciergeWorkflowLifetime {
    private var generation: UInt64 = 0
    private var visible = false
    private var mountedAccount: AccountContext?
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    func activate(session: AccountSessionCoordinator) {
        visible = true
        mountedAccount = session.current
    }

    func invalidate() {
        generation &+= 1
        let obsolete = Array(tasks.values)
        tasks.removeAll()
        for task in obsolete { task.cancel() }
    }

    func deactivate() {
        visible = false
        invalidate()
    }

    func capture(session: AccountSessionCoordinator) -> ConciergeWorkflowScope.Ticket? {
        guard visible, let account = mountedAccount, session.isCurrent(account) else { return nil }
        return .init(account: account, generation: generation)
    }

    func isCurrent(_ ticket: ConciergeWorkflowScope.Ticket?, session: AccountSessionCoordinator) -> Bool {
        guard let ticket else { return false }
        return visible && ticket.generation == generation && session.isCurrent(ticket.account) && !Task.isCancelled
    }

    @discardableResult
    func launch(
        origin: ConciergeWorkflowScope.Ticket?,
        session: AccountSessionCoordinator,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never>? {
        guard isCurrent(origin, session: session), let origin else { return nil }
        let id = UUID()
        let task = Task { @MainActor in
            await ConciergeWorkflowScope.$ticket.withValue(origin) {
                guard self.isCurrent(origin, session: session) else { return }
                await operation()
            }
            self.tasks.removeValue(forKey: id)
        }
        tasks[id] = task
        return task
    }
}
