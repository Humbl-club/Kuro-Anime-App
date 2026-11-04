import Foundation
import KuroCore

#if canImport(Supabase)
import Supabase

// MARK: - Discover answers: Not interested / Seen it (R4, R5; 2026-11-04)
// One memory for the Taste deck and Discover: each answer is ONE deck signal
// (`record_taste_deck_signal`, live) delivered through this store's outbox (`submitSignal`), so it
// teaches Taste and the deck never deals the title again. `DiscoverFeedback.deckAction` is the one
// mapping (Not interested -> 'skip', Seen it -> 'known').
//
// Hidden set (`discoverHidden`), per signed-in account:
//   1. on-device memory (`DiscoverHiddenMemory`, one UserDefaults entry per account): the last
//      server answers plus this device's answers not yet reflected by the server. Restored
//      synchronously (`restoreDiscoverMemory`), so a hidden title never flashes back after a launch
//      and an offline answer survives the app being killed;
//   2. the server read (`loadDiscoverHidden`): the caller's own `taste_signal_events` deck rows of
//      the last 365 days, read directly (RLS select-own + grant select to authenticated; no RPC, so
//      it works on the deployed backend today), in TWO reads: the hiding answers ('deck_skip' /
//      'deck_known') paged until exhausted (`discoverHiddenPageSize` rows a page, at most
//      `discoverHiddenMaxPages` pages), so an active deck user's love/pass rows can never push an
//      older answer out of the set; and the newest `discoverPriorReadLimit` 'deck_love' /
//      'deck_pass' rows, which never hide and are only remembered as the prior action of a title.
// Undo (`undoDiscoverFeedback`) re-sends the title's prior deck action when replaying it writes
// nothing but the signal ('skip' / 'known' / 'pass'), and 'retract' otherwise: a prior 'love' is
// NEVER replayed, because `record_taste_deck_signal` inserts every love into the list as PLANNING
// (20260731095000) and Discover only offers the answers for titles that are not on the list, so a
// replayed love would silently put back a title the user removed (D13). The deck love's taste
// weight is lost instead (the skip already replaced it on the server). An unknown prior (no
// successful read yet) also retracts: the skip / known was already sent and must not stay. The
// title is hidden / shown at once, whatever the delivery does (a RATE_LIMITED or dropped signal
// keeps the local answer for `DiscoverHiddenMemory.overlayLifetime`).
//
// Account scope: every read captures its `AccountContext` and applies nothing once it ended; the
// in-memory copy is cleared on account transitions (`clearPrivateState`); the device copy is removed
// on confirmed account deletion (`removeDeletedAccountData`).

@MainActor
extension TasteStore {
    /// How long a successful server read is reused before `loadDiscoverHidden` reads again.
    nonisolated static let discoverHiddenTTL: TimeInterval = 5 * 60
    /// Rows of one page of the hiding read (PostgREST's default `max_rows` is 1,000).
    nonisolated static let discoverHiddenPageSize = 1_000
    /// Pages of the hiding read at most (10,000 answered titles; the deck allows 300 signals a day).
    nonisolated static let discoverHiddenMaxPages = 10
    /// Love / pass rows read for the prior action (they never hide; newest first).
    nonisolated static let discoverPriorReadLimit = 1_000
    /// The deck events that hide a title on Discover, and those only remembered as a prior action.
    nonisolated static let discoverHidingEvents = ["deck_skip", "deck_known"]
    nonisolated static let discoverPriorEvents = ["deck_love", "deck_pass"]

    /// The hidden titles as a set (the composer and the accumulator take a set).
    var discoverHiddenKeys: Set<MediaKey> { Set(discoverHidden.keys) }

    func isHiddenOnDiscover(_ key: MediaKey) -> Bool { discoverHidden[key] != nil }

    /// Loads the signed-in account's on-device memory into `discoverHidden` (synchronous; call
    /// before the first Discover render). Signed out: empty.
    func restoreDiscoverMemory() {
        guard let context = accountSession.current else {
            discoverHidden = [:]
            return
        }
        ensureDiscoverMemory(for: context.userId)
    }

    /// Reads the account's deck answers from the server and merges them with this device's
    /// answers. `true` when the hidden set reflects a read of the current account (cached within
    /// `discoverHiddenTTL` unless `force`); `false` on failure or when the account changed (the
    /// device memory stays in effect).
    @discardableResult
    func loadDiscoverHidden(force: Bool = false) async -> Bool {
        guard let context = accountSession.current else {
            discoverHidden = [:]
            return false
        }
        ensureDiscoverMemory(for: context.userId)
        let start = currentDate
        if !force, let at = discoverHiddenReadAt, start.timeIntervalSince(at) < Self.discoverHiddenTTL {
            return true
        }
        do {
            let client = try requiredClient()
            let since = Self.isoTimestamp(start.addingTimeInterval(-DiscoverFeedback.memoryWindow))
            let user = context.userId.lowercased()
            // The hiding answers, paged to the end.
            var hiding: [DiscoverDeckSignalRow] = []
            for page in 0..<Self.discoverHiddenMaxPages {
                let from = page * Self.discoverHiddenPageSize
                let rows: LenientRows<DiscoverDeckSignalRow> = try await client
                    .from("taste_signal_events")
                    .select("media_type,media_id,event_type,created_at")
                    .eq("user_id", value: user)
                    .in("event_type", values: Self.discoverHidingEvents)
                    .gte("created_at", value: since)
                    .order("created_at", ascending: false)
                    .order("media_id", ascending: false)
                    .range(from: from, to: from + Self.discoverHiddenPageSize - 1)
                    .execute()
                    .value
                guard accountSession.isCurrent(context) else { return false }
                hiding += rows.rows
                if rows.rows.count + rows.skipped < Self.discoverHiddenPageSize { break }
            }
            // The prior actions: one bounded read (they never hide).
            let priors: LenientRows<DiscoverDeckSignalRow> = try await client
                .from("taste_signal_events")
                .select("media_type,media_id,event_type,created_at")
                .eq("user_id", value: user)
                .in("event_type", values: Self.discoverPriorEvents)
                .gte("created_at", value: since)
                .order("created_at", ascending: false)
                .limit(Self.discoverPriorReadLimit)
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return false }
            applyDiscoverServerRows(hiding: hiding, priors: priors.rows, now: currentDate)
            discoverHiddenReadAt = currentDate
            return true
        } catch {
            #if DEBUG
            print("❌ loadDiscoverHidden error: \(error)")
            #endif
            return false
        }
    }

    /// Records Not interested / Seen it for `key`: hidden at once, remembered on this device,
    /// delivered as one deck signal through the outbox. nil when signed out (nothing recorded).
    @discardableResult
    func recordDiscoverFeedback(_ feedback: DiscoverFeedback, for key: MediaKey) -> DiscoverFeedbackReceipt? {
        guard let context = accountSession.current else { return nil }
        ensureDiscoverMemory(for: context.userId)
        let receipt = DiscoverFeedbackReceipt(
            key: key, feedback: feedback, priorAction: discoverDeckActions[key], accountUserId: context.userId)
        discoverDeckActions[key] = feedback.deckAction
        discoverMemory.record(key, state: feedback, at: currentDate)
        persistDiscoverMemory()
        submitSignal(mediaType: key.kind.rawValue, mediaId: key.id, action: feedback.deckAction)
        return receipt
    }

    /// Undoes one answer: the title's prior state comes back at once (shown again, or still hidden
    /// by an earlier answer) and its prior deck action is re-sent ('retract' when there was none).
    /// `false` when the receipt belongs to another account than the signed-in one (nothing changes).
    @discardableResult
    func undoDiscoverFeedback(_ receipt: DiscoverFeedbackReceipt) -> Bool {
        guard let context = accountSession.current, context.userId == receipt.accountUserId else { return false }
        ensureDiscoverMemory(for: context.userId)
        let restored = receipt.priorAction
        if let restored {
            discoverDeckActions[receipt.key] = restored
        } else {
            discoverDeckActions[receipt.key] = nil
        }
        discoverMemory.record(receipt.key, state: restored.flatMap(DiscoverFeedback.init(deckAction:)), at: currentDate)
        persistDiscoverMemory()
        submitSignal(mediaType: receipt.key.kind.rawValue, mediaId: receipt.key.id,
                     action: Self.undoAction(prior: restored))
        return true
    }

    /// The deck action an Undo sends for a title whose signal before the answer was `prior`: replayed
    /// only when replaying writes nothing but the signal; a love (it inserts the title into the list)
    /// and an unknown prior retract the answer instead.
    nonisolated static func undoAction(prior: TasteDeckAction?) -> TasteDeckAction {
        switch prior {
        case .skip?, .known?, .pass?: return prior ?? .retract
        case .love?, .retract?, nil: return .retract
        }
    }

    // MARK: Memory

    /// Loads `userId`'s device memory unless it is the loaded one, then publishes the hidden set.
    func ensureDiscoverMemory(for userId: String) {
        let account = userId.lowercased()
        if discoverMemoryAccount != account {
            discoverMemoryAccount = account
            discoverHiddenReadAt = nil
            discoverDeckActions = [:]
            discoverMemory = Self.readDiscoverMemory(defaults: defaults, userId: userId) ?? DiscoverHiddenMemory()
            for (ref, feedback) in discoverMemory.snapshot {
                if let key = ref.key { discoverDeckActions[key] = feedback.deckAction }
            }
            applyOverlayToDeckActions()
        }
        discoverHidden = discoverMemory.hidden
    }

    /// The server rows -> snapshot (hiding answers), believed deck actions, overlay pruning.
    /// `hiding` is the complete set of hiding rows; `priors` (love / pass, bounded) only names the
    /// prior action of the titles it holds and never hides or un-hides one.
    func applyDiscoverServerRows(hiding: [DiscoverDeckSignalRow], priors: [DiscoverDeckSignalRow] = [], now: Date) {
        var actions: [MediaKey: TasteDeckAction] = [:]
        var hidden: [MediaKey: DiscoverFeedback] = [:]
        // Newest first: the first row of a title is its current deck signal (one per title on the
        // server; the newest wins should two reads ever disagree).
        for row in (hiding + priors).sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let key = row.key, actions[key] == nil, let action = row.deckAction else { continue }
            actions[key] = action
            if let feedback = DiscoverFeedback(deckAction: action) { hidden[key] = feedback }
        }
        discoverMemory.adopt(server: hidden, now: now)
        discoverDeckActions = actions
        applyOverlayToDeckActions()
        persistDiscoverMemory()
    }

    /// Device answers the server does not reflect yet override the believed deck action.
    private func applyOverlayToDeckActions() {
        for entry in discoverMemory.overlay {
            guard let key = entry.ref.key else { continue }
            if let state = entry.state {
                discoverDeckActions[key] = state.deckAction
            } else if let action = discoverDeckActions[key], DiscoverFeedback(deckAction: action) != nil {
                discoverDeckActions[key] = nil
            }
        }
    }

    private func persistDiscoverMemory() {
        discoverHidden = discoverMemory.hidden
        guard let account = discoverMemoryAccount, let key = DiscoverHiddenMemory.storageKey(userId: account) else { return }
        if discoverMemory.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(discoverMemory) {
            defaults.set(data, forKey: key)
        }
    }

    nonisolated static func readDiscoverMemory(defaults: UserDefaults, userId: String) -> DiscoverHiddenMemory? {
        guard let key = DiscoverHiddenMemory.storageKey(userId: userId),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DiscoverHiddenMemory.self, from: data)
    }

    nonisolated static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
#endif
