import Foundation
import KuroCore

#if canImport(Supabase)
import Supabase

// MARK: - Club realtime
// The single owner of the club realtime channel (one open club at a time, `kuro.club.<id>`).
// Lifecycle:
// - `subscribe(clubId:)` opens the channel of the club on screen; opening another club first
//   removes the current channel (club change).
// - `stop(clubId:)` removes the channel of that club only (its view disappeared, or the club was
//   revoked: `ClubsStore.invalidateClub`); another club's channel is left alone.
// - `detach()` is the synchronous half of a session end/switch (called by the session funnel before
//   its first suspension point); the funnel awaits the returned handle's `unsubscribe()` in its tail.
// Ordering rules:
// - One request at a time wins: every subscribe, stop of the club being opened, and detach supersedes
//   an earlier subscribe still in flight (it opens nothing), and only one subscribe per club is in
//   flight (a second one for the same club returns at once).
// - A channel is never made while a removal of the same topic is pending: the SDK hands back the
//   still-registered channel for a topic (`RealtimeClientV2.channel(_:)`), which would drop the new
//   change registrations and be left by the old removal. A removal starts once (by whoever needs it
//   first: the funnel's tail, a stop, or a new subscribe of that club) and every other caller joins it.
// A change event schedules one debounced re-read of the club (`refresh`). Events of a replaced,
// stopped or detached channel, events captured under an ended account, and a pending debounce whose
// account ended never refresh anything.
//
// Membership revocation (F42): the contracted signals are `club_activity_signals` (filter
// `club_id=eq.<club>`) and `club_membership_signals` (filter `user_id=eq.<me>`, lower-case). Either
// event schedules the bounded re-read. The re-read is the revocation path: a removed member's
// `fetch_club_bundle` answers NOT_A_MEMBER, which revokes the club in `ClubsStore`
// (`invalidateClub`: cached bundle, my-clubs row, friend projection, shared providers and this
// channel). Payloads are never applied: every event is only a signal for an authorized aggregate
// re-read. `club_members` is not subscribed (it is unpublished, and publishing it would broadcast
// membership deletes). Until `20261005160000` is applied, production still publishes the raw content
// tables; `SupabaseClubChannel.listensToLegacyContentTables` keeps those four streams so a build
// running against the current server still refreshes. Flip that flag in the release that applies
// the signal migration.

/// One club channel as the coordinator sees it (seam: production wraps `RealtimeChannelV2`; tests
/// drive delivery and observe teardown without a websocket).
@MainActor
protocol ClubRealtimeChannel: AnyObject {
    /// Joins the channel; change events then reach the `onEvent` callback given at creation.
    func subscribe() async
    /// Stops delivering events at once (synchronous). The channel stays joined until `unsubscribe()`.
    func stopListening()
    /// Leaves the channel.
    func unsubscribe() async
}

/// Creates club channels (seam).
@MainActor
protocol ClubChannelFactory {
    /// The channel of `clubId`, delivering its change events to `onEvent` on the main actor; nil when
    /// the app has no SDK client (missing configuration).
    func makeChannel(clubId: String, onEvent: @escaping @MainActor () -> Void) -> (any ClubRealtimeChannel)?
}

/// Production factory over the app's single SDK client.
@MainActor
struct SupabaseClubChannelFactory: ClubChannelFactory {
    let client: SupabaseClient?
    let accountSession: AccountSessionCoordinator

    func makeChannel(clubId: String, onEvent: @escaping @MainActor () -> Void) -> (any ClubRealtimeChannel)? {
        guard let client else { return nil }
        let userId = accountSession.current?.userId.lowercased()
        return SupabaseClubChannel(client: client, clubId: clubId, userId: userId, onEvent: onEvent)
    }
}

/// Production channel. Contracted subscriptions (prepared migration `20261005160000`, not deployed):
/// - topic `kuro.club.<clubId>`, `postgres_changes` on `club_activity_signals` filtered
///   `club_id=eq.<clubId>`: one row per club, no user identifier. Any event refetches the bundle.
/// - topic `kuro.club.<clubId>.membership`, `postgres_changes` on `club_membership_signals` filtered
///   `user_id=eq.<lower-case user id>`: only that user's membership state. A non-member state is
///   observed by the authorized re-read (`NOT_A_MEMBER`), which drops the club. Its own channel so an
///   unpublished table cannot fail the activity join.
/// `club_members` is never subscribed.
///
/// Deployment bridge: production still publishes `club_rail_items`, `club_votes`,
/// `club_rail_item_reactions` and `club_polls`, and does not yet publish the signal tables. While
/// `listensToLegacyContentTables` is true those four streams stay on the activity topic (events are
/// still only refetch signals). Set to false once a live member receives `club_activity_signals` and a
/// non-member does not (proved 2026-10-06 on bkdifromsqxkndnllmdj).
/// The deprecated `club_messages` stream is not subscribed (club chat was removed).
@MainActor
final class SupabaseClubChannel: ClubRealtimeChannel {
    /// Legacy content table streams. Off: activity/membership signals are the live source of truth.
    static let listensToLegacyContentTables = false

    private let channel: RealtimeChannelV2
    private let activityChannel: RealtimeChannelV2
    private let membershipChannel: RealtimeChannelV2
    private let joinsLegacyContentChannel: Bool
    private var listenTasks: [Task<Void, Never>] = []

    init(client: SupabaseClient, clubId: String, userId: String?, onEvent: @escaping @MainActor () -> Void) {
        let channel = client.channel("kuro.club.\(clubId)")
        self.channel = channel
        // Own topics: an unpublished signal table must not fail the join of the other streams.
        let activityChannel = client.channel("kuro.club.\(clubId).activity")
        self.activityChannel = activityChannel
        let membershipChannel = client.channel("kuro.club.\(clubId).membership")
        self.membershipChannel = membershipChannel
        joinsLegacyContentChannel = Self.listensToLegacyContentTables

        var streams: [AsyncStream<AnyAction>] = [
            activityChannel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "club_activity_signals",
                filter: .eq("club_id", value: clubId)
            ),
        ]
        if Self.listensToLegacyContentTables {
            streams.append(channel.postgresChange(AnyAction.self, schema: "public", table: "club_rail_items"))
            streams.append(channel.postgresChange(AnyAction.self, schema: "public", table: "club_votes"))
            streams.append(channel.postgresChange(AnyAction.self, schema: "public", table: "club_rail_item_reactions"))
            streams.append(channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "club_polls",
                filter: .eq("club_id", value: clubId)
            ))
        }
        if let userId {
            streams.append(membershipChannel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "club_membership_signals",
                filter: .eq("user_id", value: userId)
            ))
        }

        listenTasks = streams.map { stream in
            Task {
                for await _ in stream {
                    await MainActor.run { onEvent() }
                }
            }
        }
    }

    func subscribe() async {
        if joinsLegacyContentChannel {
            do {
                _ = try await channel.subscribeWithError()
            } catch {
                #if DEBUG
                print("⚠️ club realtime subscribe failed: \(error)")
                #endif
            }
        }
        do {
            _ = try await activityChannel.subscribeWithError()
        } catch {
            #if DEBUG
            print("⚠️ club activity signal unavailable (club_activity_signals not published yet?): \(error)")
            #endif
        }
        do {
            _ = try await membershipChannel.subscribeWithError()
        } catch {
            #if DEBUG
            print("⚠️ club membership signal unavailable (club_membership_signals not published yet?): \(error)")
            #endif
        }
    }

    func stopListening() {
        for task in listenTasks { task.cancel() }
        listenTasks.removeAll()
    }

    func unsubscribe() async {
        await channel.unsubscribe()
        await activityChannel.unsubscribe()
        await membershipChannel.unsubscribe()
    }
}

/// The removal of one detached club channel. It runs once, started by whoever needs it first, and
/// every caller joins it. It is also the handle the session funnel receives from `detach()`: the
/// funnel's `unsubscribe()` joins the removal (and never touches a channel opened later).
/// One account-wide permission signal, independent of whichever club detail is open.
/// The stream contains only the viewer's metadata rows, never comments/member content.
@MainActor
final class SupabaseDisclosureChannel: ClubRealtimeChannel {
    private let channel: RealtimeChannelV2
    private var listener: Task<Void,Never>?
    init(client: SupabaseClient, userId: String, onEvent: @escaping @MainActor () -> Void) {
        channel=client.channel("kuro.permissions.\(userId).\(UUID().uuidString)")
        let stream=channel.postgresChange(AnyAction.self,schema:"public",table:"club_membership_signals",filter:.eq("user_id",value:userId))
        listener=Task { for await _ in stream { guard !Task.isCancelled else { return }; onEvent() } }
    }
    func subscribe() async { _ = try? await channel.subscribeWithError() }
    func stopListening() { listener?.cancel(); listener=nil }
    func unsubscribe() async { stopListening(); await channel.unsubscribe() }
}

@MainActor
final class DetachedClubChannels: ClubRealtimeChannel {
    private let channels: [any ClubRealtimeChannel]
    init(_ channels: [any ClubRealtimeChannel]) { self.channels=channels; channels.forEach { $0.stopListening() } }
    func subscribe() async {}
    func stopListening() { channels.forEach { $0.stopListening() } }
    func unsubscribe() async { for channel in channels { await channel.unsubscribe() } }
}

@MainActor
final class ClubChannelRemoval: ClubRealtimeChannel {
    let clubId: String
    private let channel: any ClubRealtimeChannel
    private let onFinish: @MainActor (ClubChannelRemoval) -> Void
    private var task: Task<Void, Never>?

    init(clubId: String, channel: any ClubRealtimeChannel, onFinish: @escaping @MainActor (ClubChannelRemoval) -> Void) {
        self.clubId = clubId
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
final class ClubRealtimeCoordinator {
    /// Coalesces a burst of club changes into one re-read.
    nonisolated static let defaultRefreshDebounce: Duration = .milliseconds(500)

    private let channels: any ClubChannelFactory
    private let accountSession: AccountSessionCoordinator
    private let refreshDebounce: Duration

    /// Re-reads a club after its channel reported changes (set once by `ClubsStore`).
    var refresh: (@MainActor (String) async -> Void)?

    /// The club whose channel is open.
    private(set) var subscribedClubId: String?
    private var channel: (any ClubRealtimeChannel)?
    /// Bumped whenever the channel is replaced, removed or detached: events of an older channel are
    /// dropped even if they were already on their way to the main actor.
    private var channelGeneration = 0
    /// Bumped by every subscribe, by a stop of the club being opened and by `detach()`: a subscribe
    /// still in flight whose request is no longer the latest opens nothing.
    private var requestGeneration = 0
    /// The club whose subscribe is in flight (one per club).
    private(set) var subscribingClubId: String?
    /// Pending removals of detached channels, per club (topic `kuro.club.<id>`).
    private var removals: [String: [ClubChannelRemoval]] = [:]
    /// The pending debounced re-read.
    private(set) var debounceTask: Task<Void, Never>?
    /// The last removal started by `stop(clubId:)` (awaitable in tests).
    private(set) var teardownTask: Task<Void, Never>?

    init(
        channels: any ClubChannelFactory,
        accountSession: AccountSessionCoordinator,
        refreshDebounce: Duration = ClubRealtimeCoordinator.defaultRefreshDebounce
    ) {
        self.channels = channels
        self.accountSession = accountSession
        self.refreshDebounce = refreshDebounce
    }

    func subscribe(clubId: String) async {
        // The club's channel is open, or its subscribe is already in flight.
        guard subscribedClubId != clubId, subscribingClubId != clubId else { return }
        let context = accountSession.current
        requestGeneration += 1
        let request = requestGeneration
        subscribingClubId = clubId
        defer {
            if requestGeneration == request { subscribingClubId = nil }
        }

        // Club change: leave the open channel first.
        if let previous = detachChannel() {
            await previous.unsubscribe()
        }
        // Never make a channel while a removal of the same topic is pending.
        while let pending = removals[clubId]?.first {
            await pending.start().value
            removalFinished(pending)
        }
        // A later subscribe, a stop of this club or a session end/switch superseded this request.
        guard requestGeneration == request, accountSession.isCurrent(context) else { return }

        channelGeneration += 1
        let generation = channelGeneration
        guard let channel = channels.makeChannel(clubId: clubId, onEvent: { [weak self] in
            self?.channelDidChange(clubId: clubId, context: context, generation: generation)
        }) else { return }
        subscribedClubId = clubId
        self.channel = channel
        await channel.subscribe()
    }

    /// Synchronous half of a session end/switch: supersedes a subscribe in flight, cancels the pending
    /// re-read, stops event delivery and forgets the channel. The returned handle removes it.
    @discardableResult
    func detach() -> (any ClubRealtimeChannel)? {
        supersedeSubscribe()
        return detachChannel()
    }

    /// Removes the channel of `clubId` if it is the open one, and supersedes a subscribe of `clubId`
    /// still in flight (its view disappeared, or the club was revoked). Another club is left alone.
    func stop(clubId: String) {
        if subscribingClubId == clubId { supersedeSubscribe() }
        guard subscribedClubId == clubId, let removal = detachChannel() else { return }
        teardownTask = removal.start()
    }

    private func supersedeSubscribe() {
        requestGeneration += 1
        subscribingClubId = nil
    }

    /// Cancels the pending re-read, stops event delivery and forgets the open channel, whose removal
    /// is registered (not started) under its club.
    private func detachChannel() -> ClubChannelRemoval? {
        debounceTask?.cancel()
        debounceTask = nil
        channelGeneration += 1
        let channel = self.channel
        let clubId = subscribedClubId
        self.channel = nil
        subscribedClubId = nil
        guard let channel, let clubId else { return nil }
        channel.stopListening()
        let removal = ClubChannelRemoval(clubId: clubId, channel: channel) { [weak self] removal in
            self?.removalFinished(removal)
        }
        removals[clubId, default: []].append(removal)
        return removal
    }

    private func removalFinished(_ removal: ClubChannelRemoval) {
        removals[removal.clubId]?.removeAll { $0 === removal }
        if removals[removal.clubId]?.isEmpty == true { removals[removal.clubId] = nil }
    }

    private func channelDidChange(clubId: String, context: AccountContext?, generation: Int) {
        guard generation == channelGeneration else { return }
        scheduleRefresh(clubId: clubId, context: context)
    }

    func scheduleRefresh(clubId: String, context: AccountContext?) {
        // Late events from a previous account's club channel are dropped.
        guard accountSession.isCurrent(context) else { return }
        debounceTask?.cancel()
        let debounce = refreshDebounce
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: debounce)
            guard let self, !Task.isCancelled, self.accountSession.isCurrent(context) else { return }
            await self.refresh?(clubId)
        }
    }
}
#endif
