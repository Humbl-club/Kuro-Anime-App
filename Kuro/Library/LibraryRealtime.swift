import Foundation
import KuroCore
import KuroLibrary
import KuroSupabase

#if canImport(Supabase)
import Supabase

// MARK: - User-list realtime (E6c1)
// The single owner of the account's list-table channel (`kuro.user.<userId>`: inserts, updates and
// deletes on `anime_user_lists` / `manga_user_lists` filtered by the account's `user_id`), moved from
// `SupabaseService` (`subscribeToUpdates`, `startRealtimeSubscriptionsIfNeeded`,
// `scheduleRealtimeRefresh`, `refreshAfterRealtimeEvent`, `stopRealtimeSubscriptions`, the user half of
// the funnel's channel detach) with the same seam style as `ClubRealtimeCoordinator`.
// Lifecycle rules (E1/E3):
// - Every event carries the account context captured when its channel was made; a late event of an
//   ended or replaced account, and a pending debounce whose account ended, refresh nothing.
// - `detach()` is the synchronous half of a session end/switch (the funnel calls it before its first
//   suspension point): it cancels the pending refresh, stops event delivery and forgets the channel.
//   The funnel's tail awaits the returned handle, which can only remove THAT channel, never a newer
//   account's.
// - A channel is never made while a removal of the same topic is pending (same user signing in again
//   before the old session's tail finished): the SDK hands back the still-registered channel for a
//   topic (`RealtimeClientV2.channel(_:)`), which would drop the new change registrations and be
//   removed by the old tail (the E3-parked topic-reuse finding). The removal runs once, started by
//   whoever needs it first (the funnel's tail or the new subscribe); everyone else joins it.
// - Self-echo suppression (LibraryRealtimeEcho.swift): an event that is this device's own write
//   coming back (title has a write in flight or confirmed within 5 s AND the row matches what the
//   device shows) refreshes nothing. Anything else, including every event whose title is unknown,
//   refreshes as before. The confirmed-write ledger is fed by the Library store's change sink
//   (`RealtimeEchoLibrarySink`) and forgotten on every detach.

/// One list-table channel as the owner sees it (seam: production wraps `RealtimeChannelV2`; tests
/// drive delivery and observe teardown without a websocket).
@MainActor
protocol UserListRealtimeChannel: AnyObject {
    /// Joins the channel; change events then reach the `onEvent` callback given at creation.
    func subscribe() async
    /// Stops delivering events at once (synchronous). The channel stays joined until `unsubscribe()`.
    func stopListening()
    /// Leaves the channel and removes it from the client.
    func unsubscribe() async
}

/// Creates list-table channels (seam).
@MainActor
protocol UserListChannelFactory {
    /// Connects the realtime socket before a channel is made.
    func connect() async
    /// The channel of `userId` (topic `kuro.user.<userId>`) whose list-table streams are filtered on
    /// `listUserId`, delivering change events to `onEvent` on the main actor; nil when the app has no
    /// SDK client (missing configuration).
    func makeChannel(
        userId: String,
        listUserId: String,
        onEvent: @escaping @MainActor () -> Void
    ) -> (any UserListRealtimeChannel)?
    /// The same channel, describing each change (`LibraryRealtimeEvent`) so the owner can recognise
    /// its own echoes. Default: the plain channel, every change reported as `.unknown` (never
    /// suppressed).
    func makeChannel(
        userId: String,
        listUserId: String,
        onChange: @escaping @MainActor (LibraryRealtimeEvent) -> Void
    ) -> (any UserListRealtimeChannel)?
}

extension UserListChannelFactory {
    func makeChannel(
        userId: String,
        listUserId: String,
        onChange: @escaping @MainActor (LibraryRealtimeEvent) -> Void
    ) -> (any UserListRealtimeChannel)? {
        makeChannel(userId: userId, listUserId: listUserId, onEvent: { onChange(.unknown) })
    }
}

/// Production factory over the app's single SDK client.
@MainActor
struct SupabaseUserListChannelFactory: UserListChannelFactory {
    let client: SupabaseClient?

    func connect() async {
        await client?.realtimeV2.connect()
    }

    func makeChannel(
        userId: String,
        listUserId: String,
        onEvent: @escaping @MainActor () -> Void
    ) -> (any UserListRealtimeChannel)? {
        makeChannel(userId: userId, listUserId: listUserId, onChange: { _ in onEvent() })
    }

    func makeChannel(
        userId: String,
        listUserId: String,
        onChange: @escaping @MainActor (LibraryRealtimeEvent) -> Void
    ) -> (any UserListRealtimeChannel)? {
        guard let client else { return nil }
        return SupabaseUserListChannel(client: client, userId: userId, listUserId: listUserId, onChange: onChange)
    }
}

/// Production channel: the same topic, tables and filters as before E6c1.
@MainActor
final class SupabaseUserListChannel: UserListRealtimeChannel {
    private let client: SupabaseClient
    private let channel: RealtimeChannelV2
    private var listenTasks: [Task<Void, Never>] = []

    init(client: SupabaseClient, userId: String, listUserId: String, onChange: @escaping @MainActor (LibraryRealtimeEvent) -> Void) {
        self.client = client
        let channel = client.channel("kuro.user.\(userId)")
        self.channel = channel

        let animeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "anime_user_lists",
            filter: .eq("user_id", value: listUserId)
        )
        let mangaStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "manga_user_lists",
            filter: .eq("user_id", value: listUserId)
        )

        listenTasks = [(MediaKind.anime, animeStream), (MediaKind.manga, mangaStream)].map { kind, stream in
            Task {
                for await action in stream {
                    let event = Self.event(from: action, kind: kind)
                    await MainActor.run { onChange(event) }
                }
            }
        }
    }

    /// Describes one change of a list table (`kind` names the table's media column).
    nonisolated static func event(from action: AnyAction, kind: MediaKind) -> LibraryRealtimeEvent {
        switch action {
        case .insert(let insert): return event(action: .insert, record: insert.record, kind: kind)
        case .update(let update): return event(action: .update, record: update.record, kind: kind)
        case .delete(let delete): return event(action: .delete, record: delete.oldRecord, kind: kind)
        }
    }

    /// Describes one list-table row (`record`: the new row of an insert/update, the old row of a
    /// delete). Pure seam over the payload, so tests can feed decoded JSON (the SDK's action types
    /// have no public initializer).
    nonisolated static func event(action: LibraryRealtimeEvent.Action, record: [String: AnyJSON],
                                  kind: MediaKind) -> LibraryRealtimeEvent {
        let mediaColumn = kind == .anime ? "anime_id" : "manga_id"
        return LibraryRealtimeEvent(
            action: action,
            key: integer(record[mediaColumn]).map { MediaKey(kind: kind, id: $0) },
            rowId: integer(record["id"]),
            listType: record["list_type"]?.stringValue,
            progress: integer(record["progress"]),
            rating: integer(record["rating"]),
            notes: record["notes"]?.stringValue,
            verdict: record["verdict"]?.stringValue,
            serverRevision: integer(record["server_revision"]).map(Int64.init),
            lifecycleId: record["lifecycle_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        )
    }

    /// A whole number from a payload value: JSON integer, integral double or numeric string.
    nonisolated private static func integer(_ value: AnyJSON?) -> Int? {
        switch value {
        case .integer(let int)?: return int
        case .double(let double)?:
            guard double.isFinite, double.rounded() == double, abs(double) < 9.0e15 else { return nil }
            return Int(double)
        case .string(let text)?: return Int(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    func subscribe() async {
        do {
            _ = try await channel.subscribeWithError()
        } catch {
            #if DEBUG
            print("⚠️ realtime subscribe failed: \(error)")
            #endif
        }
    }

    func stopListening() {
        for task in listenTasks { task.cancel() }
        listenTasks.removeAll()
    }

    func unsubscribe() async {
        await client.removeChannel(channel)
    }
}

/// The removal of one detached list channel. It runs once, started by whoever needs it first, and
/// every caller joins it. It is also the handle the session funnel receives from `detach()`: the
/// funnel's `unsubscribe()` joins the removal (and never touches a channel made later).
@MainActor
final class UserListChannelRemoval: UserListRealtimeChannel {
    /// The account whose topic (`kuro.user.<userId>`) the removed channel used.
    let userId: String
    private let channel: any UserListRealtimeChannel
    private let onFinish: @MainActor (UserListChannelRemoval) -> Void
    private var task: Task<Void, Never>?

    init(userId: String, channel: any UserListRealtimeChannel, onFinish: @escaping @MainActor (UserListChannelRemoval) -> Void) {
        self.userId = userId
        self.channel = channel
        self.onFinish = onFinish
    }

    /// Starts the removal (once) and returns it.
    func start() -> Task<Void, Never> {
        if let task { return task }
        let channel = self.channel
        let task = Task { @MainActor [weak self] in
            await channel.unsubscribe()
            if let self { self.onFinish(self) }
        }
        self.task = task
        return task
    }

    /// A detached channel is never joined again.
    func subscribe() async {}

    /// Event delivery already stopped when the channel was detached.
    func stopListening() {
        channel.stopListening()
    }

    /// Runs (or joins) the removal.
    func unsubscribe() async {
        await start().value
    }
}

@MainActor
final class LibraryRealtime {
    /// Coalesces bursts of list changes (imports, batch edits) into a single refresh.
    nonisolated static let defaultRefreshDebounce: Duration = .milliseconds(350)

    private let channels: any UserListChannelFactory
    private let accountSession: AccountSessionCoordinator
    /// The tracking projection: in-flight writes and the entry this device shows (echo rule).
    private let library: LibraryStore
    /// The clock of the echo window (tests inject one).
    private let now: () -> Date
    /// The Library's server-side change hook (fresh re-read; drops tracking copies).
    private let libraryActions: LibraryActions
    /// Collection pages and feed, re-read after a list change.
    private let collection: CollectionStore
    /// Upcoming airings, re-read after a list change.
    private let releases: ReleasesStore
    private let refreshDebounce: Duration

    /// The account whose channel is open (or being opened).
    private(set) var subscribedUserId: String?
    private var channel: (userId: String, channel: any UserListRealtimeChannel)?
    /// Pending removals of detached channels, per account topic.
    private var removals: [String: [UserListChannelRemoval]] = [:]
    /// The pending debounced refresh.
    private(set) var debounceTask: Task<Void, Never>?
    /// Writes this device confirmed recently (the echo rule's window and row-id lookup).
    private(set) var localWrites = LibraryLocalWriteLedger()
    /// How many events were recognised as this device's own echo (diagnostics, tests).
    private(set) var suppressedEchoCount = 0

    init(
        channels: any UserListChannelFactory,
        accountSession: AccountSessionCoordinator,
        library: LibraryStore,
        libraryActions: LibraryActions,
        collection: CollectionStore,
        releases: ReleasesStore,
        refreshDebounce: Duration = LibraryRealtime.defaultRefreshDebounce,
        now: @escaping () -> Date = Date.init
    ) {
        self.channels = channels
        self.accountSession = accountSession
        self.library = library
        self.now = now
        self.libraryActions = libraryActions
        self.collection = collection
        self.releases = releases
        self.refreshDebounce = refreshDebounce
    }

    // MARK: - Real-time Subscriptions

    /// Opens the current account's channel in the background (fire-and-forget).
    func subscribe() {
        Task { [weak self] in
            guard let self else { return }
            await self.startIfNeeded()
        }
    }

    /// Opens the current account's channel unless it is already open.
    func startIfNeeded() async {
        guard let context = accountSession.current else { return }
        let userId = context.userId
        if subscribedUserId == userId, channel != nil { return }

        await stop()
        guard accountSession.isCurrent(context) else { return }
        subscribedUserId = userId

        await channels.connect()
        // A transition during connect already tore this subscription down.
        guard accountSession.isCurrent(context) else { return }

        // Never make a channel while a removal of the same topic is pending.
        while let pending = removals[userId]?.first {
            await pending.start().value
            removalFinished(pending)
        }
        guard accountSession.isCurrent(context) else { return }

        // Same `user_id` text as every list-table request (single decision point for finding F1).
        let listUserId = UserIdText.value(for: context)
        guard let channel = channels.makeChannel(userId: userId, listUserId: listUserId, onChange: { [weak self] event in
            self?.handle(event, for: context)
        }) else { return }
        self.channel = (userId, channel)
        await channel.subscribe()
    }

    /// Synchronous half of a session end/switch: cancels the pending refresh, stops event delivery and
    /// forgets the channel, whose removal is registered (not started) under its topic. The returned
    /// handle removes exactly that channel.
    @discardableResult
    func detach() -> (any UserListRealtimeChannel)? {
        debounceTask?.cancel()
        debounceTask = nil
        localWrites = LibraryLocalWriteLedger()
        let detached = channel
        channel = nil
        subscribedUserId = nil
        guard let detached else { return nil }
        detached.channel.stopListening()
        let removal = UserListChannelRemoval(userId: detached.userId, channel: detached.channel) { [weak self] removal in
            self?.removalFinished(removal)
        }
        removals[detached.userId, default: []].append(removal)
        return removal
    }

    /// Removes the open channel (detached first, so a subscription started meanwhile is not clobbered).
    func stop() async {
        guard let removal = detach() else { return }
        await removal.unsubscribe()
    }

    private func removalFinished(_ removal: UserListChannelRemoval) {
        removals[removal.userId]?.removeAll { $0 === removal }
        if removals[removal.userId]?.isEmpty == true { removals[removal.userId] = nil }
    }

    // MARK: - Self-echo suppression

    /// A Library change this device confirmed (the store's change sink): its title is in the echo
    /// window for the next `LibraryEchoPolicy.window` seconds.
    func recordLocalWrite(_ change: LibraryChange) {
        guard accountSession.isCurrent(change.account) else { return }
        let at = now()
        localWrites.prune(now: at)
        localWrites.record(change.key, rowIds: [change.previous?.rowId, change.current?.rowId].compactMap { $0 }, at: at)
    }

    /// A described change event of the channel made under `context`: dropped when it is this
    /// device's own echo, otherwise a (debounced) refresh as before.
    func handle(_ event: LibraryRealtimeEvent, for context: AccountContext) {
        guard accountSession.isCurrent(context) else { return }
        let at = now()
        localWrites.prune(now: at)
        let key = LibraryEchoPolicy.resolvedKey(event, ledger: localWrites)
        if let key, LibraryEchoPolicy.isOwnEcho(
            event,
            resolvedKey: key,
            inFlight: library.isMutating(key),
            lastLocalWrite: localWrites.lastWrite(for: key),
            local: library.entry(for: key),
            now: at
        ) {
            suppressedEchoCount += 1
            return
        }
        scheduleRefresh(for: context)
    }

    /// A change event of the channel made under `context`.
    func scheduleRefresh(for context: AccountContext) {
        // Late events from a previous account's channel are dropped.
        guard accountSession.isCurrent(context) else { return }
        // Coalesce bursts of changes (imports, batch edits) into a single refresh.
        debounceTask?.cancel()
        let debounce = refreshDebounce
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: debounce)
            guard let self, !Task.isCancelled, self.accountSession.isCurrent(context) else { return }
            await self.refreshAfterEvent(context: context)
        }
    }

    private func refreshAfterEvent(context: AccountContext) async {
        // These are all user-scoped. The lists changed server-side: a fresh Library read (its own
        // task, so cancelling this debounce never cancels it; stale-protected against newer local
        // mutations); the feed fetch is latest-wins.
        await libraryActions.libraryChangedServerSide(for: context).value
        await collection.fetchCollectionFeed(status: collection.currentCollectionStatusFilter)
        await releases.fetchUpcomingForUser(days: 7)
    }
}
#endif
