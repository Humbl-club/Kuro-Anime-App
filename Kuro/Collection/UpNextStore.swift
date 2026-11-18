import Foundation
import KuroCore
import KuroLibrary
import Observation
import Supabase

// MARK: - W10 "Up next in your series": the account-scoped owner
// Reads `library_up_next_v1` (prepared, not deployed; a missing contract hides the section silently),
// filters the rows on the device (`LibraryStore.isTracked`, `TasteStore.isHiddenOnDiscover`) so Plan,
// Dismiss and both Undos need no refetch, plans through `LibraryActions.save` and dismisses through
// Discover's Not interested (`TasteStore.recordDiscoverFeedback`: a deck skip). The release switch
// `collection_up_next_v1` is read at call time: while it is off nothing is loaded or sent.

@MainActor
@Observable
final class UpNextStore: AccountScopedState {
    enum Phase: Equatable { case idle, loading, loaded, offline, hidden }

    /// Where the load stands per medium. `.hidden`: flag off, contract not deployed, or signed out.
    private(set) var phase: [MediaKind: Phase] = [:]

    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let accountSession: AccountSessionCoordinator
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let actions: LibraryActions
    @ObservationIgnored private let taste: TasteStore
    @ObservationIgnored private let flags: FeatureFlags
    /// The clock (tests move it to cross the cache and retry windows).
    @ObservationIgnored var now: () -> Date

    /// Server rows per medium for `rowsAccount`.
    private var rows: [MediaKind: [UpNextItem]] = [:]
    @ObservationIgnored private var rowsAccount: AccountContext?
    @ObservationIgnored private var loadedAt: [MediaKind: Date] = [:]
    @ObservationIgnored private var undeployedUntil: Date?
    @ObservationIgnored private var planning: Set<MediaKey> = []
    @ObservationIgnored private let loads = AccountScopedLoads<String, [UpNextItem]>()

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, library: LibraryStore,
         actions: LibraryActions, taste: TasteStore, flags: FeatureFlags, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.accountSession = accountSession
        self.library = library
        self.actions = actions
        self.taste = taste
        self.flags = flags
        self.now = now
    }

    /// The release switch, read at call time (flags hydrate after launch and carry per-account overrides).
    var isEnabled: Bool { flags.collectionUpNextV1Enabled }

    // MARK: Reading

    /// The rows still worth showing: the server answer minus what is tracked or hidden on Discover now.
    /// Empty while the switch is off or when the rows belong to another account.
    func visible(_ medium: MediaKind) -> [UpNextItem] {
        guard isEnabled, let account = accountSession.current, rowsAccount == account else { return [] }
        let items = rows[medium] ?? []
        // At most 30 lookups: never the whole (up to 2,000-entry) projection.
        let tracked = Set(items.map(\.key).filter { library.isTracked($0) })
        return UpNextPolicy.visible(items, tracked: tracked, hidden: taste.discoverHiddenKeys)
    }

    // MARK: Loading

    /// Loads one medium. Switch off or signed out: `.hidden`/no change and NO request. Never throws.
    func load(_ medium: MediaKind, force: Bool = false) async {
        guard isEnabled else {
            phase[medium] = .hidden
            return
        }
        guard let account = accountSession.current, let client else {
            phase[medium] = .hidden
            return
        }
        // Applies this account's dismissals (device memory) before the first render after a switch.
        taste.restoreDiscoverMemory()
        let start = now()
        if let until = undeployedUntil, start < until {
            phase[medium] = .hidden
            return
        }
        if rowsAccount != account {
            rows = [:]
            loadedAt = [:]
            rowsAccount = account
        }
        if !force, let at = loadedAt[medium], start.timeIntervalSince(at) < UpNextPolicy.ttl, phase[medium] == .loaded {
            return
        }
        if phase[medium] != .loaded { phase[medium] = .loading }
        do {
            let items = try await loads.run(key: "up_next|\(medium.rawValue)", context: account) { [accountSession] in
                let result: LenientRows<UpNextItem> = try await accountSession.withCredentialLease(for: account) {
                    try await client
                        .rpc("library_up_next_v1",
                             params: RPCLibraryUpNextParams(p_medium: medium.rawValue, p_limit: UpNextPolicy.limit))
                        .execute()
                        .value
                }
                return result.rows.filter { $0.key.kind == medium }
            }
            guard accountSession.isCurrent(account) else { return }
            rows[medium] = items
            loadedAt[medium] = now()
            phase[medium] = .loaded
        } catch {
            guard accountSession.isCurrent(account) else { return }
            switch ReleaseFailure.classify(error) {
            case .cancelled:
                if phase[medium] == .loading { phase[medium] = rows[medium] == nil ? .idle : .loaded }
            case .notDeployed:
                undeployedUntil = now().addingTimeInterval(UpNextPolicy.undeployedRetry)
                rows[medium] = []
                phase[medium] = .hidden
            case .transient:
                // Rows already on screen stay; with nothing to show the section says it is offline.
                phase[medium] = (rows[medium]?.isEmpty == false) ? .loaded : .offline
            }
            #if DEBUG
            print("up next load: \(error)")
            #endif
        }
    }

    // MARK: Plan / Undo

    /// Plans `item` (adds it to Planning). nil when the switch is off, signed out, or the write failed.
    func plan(_ item: UpNextItem) async -> UpNextPlanReceipt? {
        guard isEnabled, let account = accountSession.current, !planning.contains(item.key) else { return nil }
        planning.insert(item.key)
        defer { planning.remove(item.key) }
        let outcome = await actions.save(item.key, status: .planning)
        guard accountSession.isCurrent(account),
              case .applied(let change) = outcome, let entry = change.current else { return nil }
        return UpNextPlanReceipt(key: item.key, account: change.account, rowId: entry.rowId,
                                 lifecycleId: entry.lifecycleId, revision: entry.revision,
                                 created: change.kind == .added)
    }

    /// Removes the entry a Plan created, and only that: refused (nothing sent) when the Plan did not
    /// create it, the account ended, or the entry changed in any way since (identity, revision, or
    /// anything beyond a bare plan).
    func undoPlan(_ receipt: UpNextPlanReceipt) async -> Bool {
        guard receipt.created, accountSession.isCurrent(receipt.account),
              let entry = library.entry(for: receipt.key),
              entry.rowId == receipt.rowId,
              entry.lifecycleId == receipt.lifecycleId,
              entry.revision == receipt.revision,
              TastePlanAction.isBarePlan(entry) else { return false }
        let outcome = await actions.remove(receipt.key)
        if case .applied = outcome { return true }
        return false
    }

    // MARK: Dismiss / Undo

    /// Not interested (also hides the title on Discover and counts as a Taste skip). nil when the switch is off.
    func dismiss(_ item: UpNextItem) -> DiscoverFeedbackReceipt? {
        guard isEnabled else { return nil }
        return taste.recordDiscoverFeedback(.notInterested, for: item.key)
    }

    @discardableResult
    func undoDismiss(_ receipt: DiscoverFeedbackReceipt) -> Bool {
        taste.undoDiscoverFeedback(receipt)
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        loads.cancelAll()
    }

    func clearPrivateState() {
        loads.cancelAll()
        rows = [:]
        rowsAccount = nil
        phase = [:]
        loadedAt = [:]
        planning = []
    }
}
