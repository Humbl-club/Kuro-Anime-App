import Foundation
import Observation

/// Admission for a presentation's user intent, before an owner captures credentials at dispatch.
/// Tickets belong to the mounted account and presentation lifetime; callers check again after awaits.
@MainActor
@Observable
public final class AccountActionScope {
    public struct Ticket: Equatable, Sendable {
        public let account: AccountContext
        fileprivate let scopeId: UUID
        fileprivate let generation: UInt64
    }

    private var mountedAccount: AccountContext?
    private let scopeId = UUID()
    private var generation: UInt64 = 0
    private var visible = false
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public func activate(session: AccountSessionCoordinator) {
        mountedAccount = session.current
        visible = true
    }

    public func deactivate() {
        visible = false
        generation &+= 1
        let obsolete = Array(tasks.values)
        tasks.removeAll()
        for task in obsolete { task.cancel() }
    }

    public func capture(session: AccountSessionCoordinator) -> Ticket? {
        guard visible, let account = mountedAccount, session.isCurrent(account) else { return nil }
        return Ticket(account: account, scopeId: scopeId, generation: generation)
    }

    public func isCurrent(_ ticket: Ticket?, session: AccountSessionCoordinator) -> Bool {
        guard let ticket else { return false }
        return visible && scopeId == ticket.scopeId && generation == ticket.generation && session.isCurrent(ticket.account) && !Task.isCancelled
    }

    @discardableResult
    public func launch(
        origin: Ticket?, session: AccountSessionCoordinator,
        operation: @escaping @MainActor (Ticket) async -> Void
    ) -> Task<Void, Never>? {
        guard let origin, isCurrent(origin, session: session) else { return nil }
        let id = UUID()
        let task = Task { @MainActor in
            guard self.isCurrent(origin, session: session) else {
                self.tasks.removeValue(forKey: id)
                return
            }
            await operation(origin)
            self.tasks.removeValue(forKey: id)
        }
        tasks[id] = task
        return task
    }
}
