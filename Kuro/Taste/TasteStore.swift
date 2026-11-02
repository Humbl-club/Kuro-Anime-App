import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase
import UIKit

// MARK: - Taste
// Owner of the Taste transport and of the deck's signal delivery:
// - reads: the deck batch, the caller's taste profile, the public realm display copy and the
//   personalised NEW TO YOU rail (`fetch_personalized_new_to_you`, flag `personalized_new_to_you_v1`);
// - writes: `record_taste_deck_signal`, directly (`recordTasteDeckSignal`) or through the signal
//   outbox (`submitSignal`). A delivered 'love' also adds the title to the lists server-side (SQL
//   writer, W-16), so it calls the single Library hook (`LibraryRefreshHook`) for the current account.
// The deck's screen/gesture state (queue of cards, undo chip, phases) stays in the view model.
//
// Account scope: the deck batch, the profile and the personalised rail are the caller's; each read
// captures its `AccountContext` and hands nothing out once that context ended (nil, the existing
// failure path). The outbox belongs to the signed-in account: cleared on every account transition
// (`AccountScopedState`), its delivery cancelled, and a delivery result of an ended account never
// touches the queue or fires the Library hook.
//
// Signal outbox (replaces the view model's in-memory retry queue):
// - one entry per deck card (`MediaKey`): the RPC keeps exactly one deck signal per (user, media),
//   a newer action replacing the older one and 'retract' deleting it, so a newer signal for a card
//   replaces its queued one; a superseded signal is never delivered after its successor (also when it
//   was in flight: results are applied by entry token, never by card);
// - bounded: at most `maxPendingSignals` entries (the oldest is dropped) and `maxDeliveryAttempts`
//   failed attempts per entry (then dropped); `signalsNeedAttention` is raised after
//   `attentionAfterFailures` failures of an entry or any drop, and lowered when a delivery empties
//   the queue (one outage = one banner);
// - delivery is serial (one drain at a time; a second trigger joins it), in queue order; a failed
//   entry waits `retryBaseDelay * 2^(failures-1)` before a non-forced retry; a successful delivery,
//   the app returning to the foreground (`installForegroundDrain`) and an explicit
//   `drainSignalOutbox(force: true)` (deck appear) retry every queued entry at once.

@MainActor
@Observable
final class TasteStore: AccountScopedState {
    /// Queue capacity: deck signals are taste hints, a longer outage keeps the newest ones.
    static let maxPendingSignals = 50
    /// Failed attempts after which an entry is dropped.
    static let maxDeliveryAttempts = 5
    /// Failed attempts of one entry after which the deck shows its "didn't save" banner.
    static let attentionAfterFailures = 3
    /// Backoff of the first retry (doubles per further failure).
    nonisolated static let defaultRetryBaseDelay: TimeInterval = 2

    /// One deck signal waiting for delivery.
    struct PendingSignal: Equatable, Sendable {
        /// Unique per submitted signal: a delivery result applies to exactly this entry.
        let token: Int
        /// The deck card (typed: anime 7 and manga 7 are different cards).
        let card: MediaKey
        let action: TasteDeckAction
        /// Failed delivery attempts so far.
        var failures: Int
        /// Earliest time of the next non-forced attempt.
        var notBefore: Date
    }

    /// The app's single SDK client (shared by every owner); nil when the configuration is
    /// missing, and then every read takes its failure path and every write fails.
    private let client: SupabaseClient?
    /// The shared account coordinator (every completion is checked against it).
    let accountSession: AccountSessionCoordinator
    /// The single Library hook after a server-side list write (deck 'love').
    @ObservationIgnored let libraryHook: LibraryRefreshHook
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let retryBaseDelay: TimeInterval

    init(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        libraryHook: LibraryRefreshHook,
        now: @escaping @MainActor () -> Date = Date.init,
        retryBaseDelay: TimeInterval = TasteStore.defaultRetryBaseDelay
    ) {
        self.client = client
        self.accountSession = accountSession
        self.libraryHook = libraryHook
        self.now = now
        self.retryBaseDelay = retryBaseDelay
    }

    /// The SDK client, or `MissingSupabaseConfiguration` when the app has none.
    private func requiredClient() throws -> SupabaseClient {
        guard let client else { throw MissingSupabaseConfiguration() }
        return client
    }

    // MARK: Outbox state

    /// Signals of the signed-in account waiting for delivery, oldest first.
    private(set) var pendingSignals: [PendingSignal] = []
    /// Raised when an entry failed `attentionAfterFailures` times or was dropped; lowered when a
    /// delivery empties the queue and on account transitions.
    private(set) var signalsNeedAttention = false
    /// The running delivery loop (awaitable in tests); nil when idle.
    @ObservationIgnored private(set) var drainTask: Task<Void, Never>? = nil
    @ObservationIgnored private var drainToken = 0
    @ObservationIgnored private var nextSignalToken = 0
    /// The one foreground observer of this store (replaced by a new install, removed with the store).
    @ObservationIgnored private var foregroundDrain: TasteForegroundDrain? = nil
    /// Foreground notifications handled so far (each forces one drain).
    @ObservationIgnored private(set) var foregroundDrainCount = 0

    // MARK: AccountScopedState

    func cancelAccountWork() {
        drainTask?.cancel()
        drainTask = nil
        drainToken += 1
    }

    func clearPrivateState() {
        pendingSignals = []
        signalsNeedAttention = false
    }

    // MARK: - Reads

    /// nil on error (distinct from an empty-but-successful deal, so callers can
    /// avoid marking the deck exhausted on transport failures). Personalised: a batch dealt for an
    /// account that is no longer current is not handed out (nil).
    func fetchTasteDeckBatch(limit: Int = 12) async -> [TasteDeckCard]? {
        let context = accountSession.current
        do {
            let client = try requiredClient()
            let rows: [TasteDeckCard] = try await client
                .rpc("fetch_taste_deck_batch", params: RPCFetchTasteDeckBatchParams(p_limit: limit))
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return nil }
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchTasteDeckBatch error: \(error)")
            #endif
            return nil
        }
    }

    /// Zero rows means the profile hasn't been computed yet -> nil. Personalised: a profile read for
    /// an account that is no longer current is not handed out (nil).
    func fetchMyTasteProfile() async -> TasteProfile? {
        let context = accountSession.current
        do {
            let client = try requiredClient()
            let rows: [TasteProfileRow] = try await client
                .rpc("fetch_my_taste_profile")
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return nil }
            guard let row = rows.first else { return nil }
            return TasteProfile(vector: row.vector, updatedAt: row.updatedAt)
        } catch {
            #if DEBUG
            print("❌ fetchMyTasteProfile error: \(error)")
            #endif
            return nil
        }
    }

    /// nil on error, [] when the RPC has no personalized candidates — callers
    /// fall back to bundle data in both cases. Personalised: a rail fetched for an account that is
    /// no longer current is not handed out (nil).
    func fetchPersonalizedNewToYou(limit: Int = 20, mediaType: String = "ANIME") async -> [TasteDeckCard]? {
        let context = accountSession.current
        do {
            let client = try requiredClient()
            let params = RPCFetchPersonalizedNewToYouParams(p_limit: limit, p_media_type: mediaType)
            let rows: [TasteDeckCard] = try await client
                .rpc("fetch_personalized_new_to_you", params: params)
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return nil }
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchPersonalizedNewToYou error: \(error)")
            #endif
            return nil
        }
    }

    /// Realm display copy. realm_meta is a public-read catalog table (RLS
    /// `select using (true)`), so a plain PostgREST select — no RPC needed.
    /// Returns [] on error; callers fall back to humanizing the stable realm keys.
    func fetchRealmMeta() async -> [RealmMeta] {
        do {
            let client = try requiredClient()
            let rows: [RealmMeta] = try await client
                .from("realm_meta")
                .select()
                .order("sort")
                .execute()
                .value
            return rows
        } catch {
            #if DEBUG
            print("❌ fetchRealmMeta error: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Signals

    /// Records one deck signal now (no queue): `true` when the server accepted it FOR THE ACCOUNT STILL
    /// CURRENT (F04: an ended account's acceptance is reported as `false`, never as a success of the
    /// next account). The write runs as a credential lease of its account (F33). A delivered 'love'
    /// calls the Library hook (the RPC added the title server-side).
    @discardableResult
    func recordTasteDeckSignal(mediaType: String, mediaId: Int, action: TasteDeckAction) async -> Bool {
        let context = accountSession.current
        do {
            let params = RPCRecordTasteDeckSignalParams(
                p_media_type: mediaType.uppercased(),
                p_media_id: mediaId,
                p_action: action.rawValue
            )
            let client = try requiredClient()
            let _: AnyJSON = try await accountSession.withCredentialLease(for: context) {
                try await client
                    .rpc("record_taste_deck_signal", params: params)
                    .execute()
                    .value
            }
            guard accountSession.isCurrent(context) else { return false }
            // 'love' also adds the title to the list server-side: fresh Library read, stale copies dropped.
            if action == .love, let context {
                libraryHook.listsChangedServerSide(for: context)
            }
            return true
        } catch {
            #if DEBUG
            print("❌ recordTasteDeckSignal error: \(error)")
            #endif
            return false
        }
    }

    /// Queues a deck signal of the signed-in account and starts (or joins) delivery; returns the
    /// delivery task. A queued signal for the same card is replaced. Nothing is queued while signed
    /// out or for a media type other than anime/manga (the RPC rejects those, a retry cannot succeed).
    @discardableResult
    func submitSignal(mediaType: String, mediaId: Int, action: TasteDeckAction) -> Task<Void, Never>? {
        guard accountSession.current != nil, let card = Self.cardKey(mediaType: mediaType, mediaId: mediaId) else {
            return nil
        }
        pendingSignals.removeAll { $0.card == card }
        if pendingSignals.count >= Self.maxPendingSignals {
            pendingSignals.removeFirst(pendingSignals.count - Self.maxPendingSignals + 1)
            signalsNeedAttention = true
        }
        nextSignalToken += 1
        pendingSignals.append(PendingSignal(token: nextSignalToken, card: card, action: action, failures: 0, notBefore: now()))
        return drainSignalOutbox()
    }

    /// Delivers the queued signals of the signed-in account; joins a running delivery. `force`
    /// (foreground, deck appear) retries every entry now instead of waiting for its backoff.
    @discardableResult
    func drainSignalOutbox(force: Bool = false) -> Task<Void, Never>? {
        if force { waiveBackoff() }
        if let drainTask { return drainTask }
        guard let context = accountSession.current, !pendingSignals.isEmpty else { return nil }
        drainToken += 1
        let token = drainToken
        let task = Task { [weak self] in
            guard let self else { return }
            await self.deliverPendingSignals(for: context, token: token)
        }
        drainTask = task
        return task
    }

    /// Forces a drain whenever `notificationCenter` posts `name` (default: the app is about to enter
    /// the foreground). One registration per store: a new install replaces the previous one. The
    /// observer holds the store weakly; it is removed by `TasteForegroundDrain.cancel()`, by the next
    /// install, or when the store goes away.
    @discardableResult
    func installForegroundDrain(
        notificationCenter: NotificationCenter = .default,
        name: Notification.Name? = nil
    ) -> TasteForegroundDrain {
        foregroundDrain?.cancel()
        let observer = notificationCenter.addObserver(
            forName: name ?? UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let store = self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { store.handleForeground() }
            } else {
                Task { @MainActor in store.handleForeground() }
            }
        }
        let drain = TasteForegroundDrain(center: notificationCenter, observer: observer)
        foregroundDrain = drain
        return drain
    }

    private func handleForeground() {
        foregroundDrainCount += 1
        drainSignalOutbox(force: true)
    }

    private func deliverPendingSignals(for context: AccountContext, token: Int) async {
        defer {
            if drainToken == token { drainTask = nil }
        }
        while !Task.isCancelled, accountSession.isCurrent(context), let signal = nextDueSignal() {
            let delivered = await recordTasteDeckSignal(
                mediaType: signal.card.kind.rawValue,
                mediaId: signal.card.id,
                action: signal.action
            )
            // A result of an ended account never touches the next account's queue.
            guard !Task.isCancelled, accountSession.isCurrent(context) else { return }
            settle(signal.token, delivered: delivered)
        }
    }

    private func nextDueSignal() -> PendingSignal? {
        let current = now()
        return pendingSignals.first { $0.notBefore <= current }
    }

    /// Applies one delivery result to the entry it was made for (a superseded or cleared entry is gone).
    private func settle(_ token: Int, delivered: Bool) {
        guard let index = pendingSignals.firstIndex(where: { $0.token == token }) else { return }
        if delivered {
            pendingSignals.remove(at: index)
            if pendingSignals.isEmpty {
                signalsNeedAttention = false
            } else {
                // The server answers again: the remaining entries need not wait for their backoff.
                waiveBackoff()
            }
            return
        }
        pendingSignals[index].failures += 1
        let failures = pendingSignals[index].failures
        if failures >= Self.attentionAfterFailures {
            signalsNeedAttention = true
        }
        if failures >= Self.maxDeliveryAttempts {
            pendingSignals.remove(at: index)
        } else {
            pendingSignals[index].notBefore = now().addingTimeInterval(retryBaseDelay * pow(2, Double(failures - 1)))
        }
    }

    private func waiveBackoff() {
        let current = now()
        for index in pendingSignals.indices where pendingSignals[index].notBefore > current {
            pendingSignals[index].notBefore = current
        }
    }

    /// The deck card of a signal ("ANIME" / "MANGA", any case); nil for anything else.
    private static func cardKey(mediaType: String, mediaId: Int) -> MediaKey? {
        switch mediaType.lowercased() {
        case "anime": return MediaKey(kind: .anime, id: mediaId)
        case "manga": return MediaKey(kind: .manga, id: mediaId)
        default: return nil
        }
    }
}

/// One registered foreground observer of a `TasteStore`; `cancel()` (or releasing the last
/// reference) removes it. Removal is idempotent.
nonisolated final class TasteForegroundDrain: @unchecked Sendable {
    private let center: NotificationCenter
    private let observer: any NSObjectProtocol

    init(center: NotificationCenter, observer: any NSObjectProtocol) {
        self.center = center
        self.observer = observer
    }

    func cancel() {
        center.removeObserver(observer)
    }

    deinit {
        center.removeObserver(observer)
    }
}
#endif
