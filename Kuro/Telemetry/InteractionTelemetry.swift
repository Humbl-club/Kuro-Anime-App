import Foundation
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Interaction telemetry (E6c2)
// Owner of the privacy-safe interaction events (`ConciergeAnalytics`: no PII in payloads, `user_id`
// is the auth UID only). Moved from `SupabaseService` (`beginInteractionTiming`,
// `trackInteractionEvent`); fire-and-forget semantics unchanged: tracking never blocks the caller.
//
// Account scope (LT-30): events queued while offline carry the account's id. When that account ends
// (sign-out, switch, deletion) its queued events are dropped: under another login the insert policy
// (`user_id IS NULL OR user_id = auth.uid()`) rejects them, and they must not outlive the account
// (GDPR). Anonymous events stay queued. The session funnel sets the attributed user id through this
// owner, after the drop.
//
// No relabeling (F70/F33 audit): an event is attributed to the account current when it is TRACKED. A
// timed interaction (`beginInteractionTiming` ... `trackInteractionEvent(startedAt:)`) remembers the
// attribution it began under; when it completes under another one (a sign-out, switch or new sign-in
// happened meanwhile) its event is dropped instead of being attributed to the new account. Untimed raw
// events (`track`) are attributed at call time: their callers fire them synchronously with the user's
// action. Best effort only: tracking never throws, never blocks, and no business path awaits it, so an
// analytics failure cannot abort a successful business transaction.

@MainActor
@Observable
final class InteractionTelemetry: AccountScopedState {
    typealias StartedAt = CFAbsoluteTime

    /// The event queue and sender (composition: `ConciergeAnalytics.shared`, the instance KuroApp's
    /// reconnect flush reaches).
    @ObservationIgnored let analytics: ConciergeAnalytics

    /// Moves on with every change of the attributed account (`setUserId`).
    @ObservationIgnored private var attributionGeneration = 0
    @ObservationIgnored private var attributedUserId: String?
    /// The attribution each timed interaction began under, keyed by its (unique) start value; bounded.
    @ObservationIgnored private var interactionAttributions: [StartedAt: Int] = [:]
    @ObservationIgnored private var interactionOrder: [StartedAt] = []
    /// Timed interactions remembered at most (the oldest is forgotten: its event is tracked as before).
    static let maxTrackedInteractions = 64

    /// `client`: the app's single SDK client; without one, events stay queued and are never sent.
    init(analytics: ConciergeAnalytics, client: SupabaseClient?) {
        self.analytics = analytics
        if let client { analytics.configure(client: client) }
    }

    /// The start of a timed interaction (a `CFAbsoluteTime`, unique per call), remembered with the
    /// attribution it began under.
    func beginInteractionTiming() -> StartedAt {
        var startedAt = CFAbsoluteTimeGetCurrent()
        while interactionAttributions[startedAt] != nil { startedAt = startedAt.nextUp }
        interactionAttributions[startedAt] = attributionGeneration
        interactionOrder.append(startedAt)
        if interactionOrder.count > Self.maxTrackedInteractions {
            interactionAttributions[interactionOrder.removeFirst()] = nil
        }
        return startedAt
    }

    func trackInteractionEvent(
        _ event: String,
        surface: String,
        result: String,
        startedAt: StartedAt? = nil,
        extra: [String: Any] = [:]
    ) {
        // An interaction that began under another account is never relabeled as this one's.
        if let startedAt, let began = interactionAttributions[startedAt], began != attributionGeneration {
            return
        }
        var payload = extra
        payload["surface"] = surface
        payload["result"] = result
        payload["market"] = Locale.current.region?.identifier.uppercased() ?? "US"
        if let startedAt {
            payload["latency_ms"] = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0)
        }
        analytics.track(event, payload: payload)
    }

    /// A raw event (the concierge surface's own events).
    @discardableResult
    func track(_ event: String, payload: [String: Any] = [:]) -> Task<Void, Never>? {
        analytics.track(event, payload: payload)
    }

    /// The account new events are attributed to (session funnel); a signed-in id flushes the queue.
    func setUserId(_ id: String?) {
        let unchanged: Bool
        switch (attributedUserId, id) {
        case (nil, nil): unchanged = true
        case let (previous?, next?): unchanged = previous.lowercased() == next.lowercased()
        default: unchanged = false
        }
        if !unchanged { attributionGeneration += 1 }
        attributedUserId = id
        analytics.setUserId(id)
    }

    /// Sends the queued events (on reconnect).
    @discardableResult
    func flushIfNeeded() -> [Task<Void, Never>] {
        analytics.flushIfNeeded()
    }

    // MARK: AccountScopedState

    /// Nothing to cancel: sends already started are fire-and-forget under the account that tracked them.
    func cancelAccountWork() {}

    /// The ending account's queued events are dropped (anonymous ones stay).
    func clearPrivateState() {
        analytics.dropQueuedAccountEvents()
    }
}
#endif
