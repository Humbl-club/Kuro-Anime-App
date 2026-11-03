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
//      it works on the deployed backend today). 'deck_skip' / 'deck_known' hide; 'deck_love' (the
//      title is on the list) and 'deck_pass' (undecided swipe) do not, but are remembered as the
//      prior action an Undo restores.
// Undo (`undoDiscoverFeedback`) re-sends the title's prior deck action (a deck 'love' is never
// erased by Discover), or 'retract' when there was none. The title is hidden / shown at once,
// whatever the delivery does (a RATE_LIMITED or dropped signal keeps the local answer for
// `DiscoverHiddenMemory.overlayLifetime`).
//
// Account scope: every read captures its `AccountContext` and applies nothing once it ended; the
// in-memory copy is cleared on account transitions (`clearPrivateState`); the device copy is removed
// on confirmed account deletion (`removeDeletedAccountData`).

@MainActor
extension TasteStore {
    /// How long a successful server read is reused before `loadDiscoverHidden` reads again.
    nonisolated static let discoverHiddenTTL: TimeInterval = 5 * 60
    /// Rows read at most (one deck signal per title, so this is the newest 2,000 answered titles).
    nonisolated static let discoverHiddenReadLimit = 2_000

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
            let since = start.addingTimeInterval(-DiscoverFeedback.memoryWindow)
            let rows: LenientRows<DiscoverDeckSignalRow> = try await client
                .from("taste_signal_events")
                .select("media_type,media_id,event_type,created_at")
                .eq("user_id", value: context.userId.lowercased())
                .in("event_type", values: ["deck_love", "deck_known", "deck_skip", "deck_pass"])
                .gte("created_at", value: Self.isoTimestamp(since))
                .order("created_at", ascending: false)
                .limit(Self.discoverHiddenReadLimit)
                .execute()
                .value
            guard accountSession.isCurrent(context) else { return false }
            applyDiscoverServerRows(rows.rows, now: currentDate)
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
        submitSignal(mediaType: receipt.key.kind.rawValue, mediaId: receipt.key.id, action: restored ?? .retract)
        return true
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
    func applyDiscoverServerRows(_ rows: [DiscoverDeckSignalRow], now: Date) {
        var actions: [MediaKey: TasteDeckAction] = [:]
        var hidden: [MediaKey: DiscoverFeedback] = [:]
        // Newest first: the first row of a title is its current deck signal.
        for row in rows.sorted(by: { $0.createdAt > $1.createdAt }) {
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
