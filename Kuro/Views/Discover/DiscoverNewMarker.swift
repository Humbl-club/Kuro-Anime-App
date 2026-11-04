import CryptoKit
import Foundation
import KuroCore
import SwiftUI

// MARK: - "New since your last visit" (usability spec §5.8, D18)
// Per account and section, the titles seen in the last visit (a section counts as seen once at least
// half of it was on screen). NEW = shown now and absent from that section's last-visit snapshot; the
// first visit ever, or a section without a snapshot, shows none. Markers are computed against the
// snapshot taken when the visit began, so they stay for the whole visit and never blink; the visit's
// seen titles are committed when it ends. Nothing goes to the server; only kinds and ids are stored.
//
// Storage: one UserDefaults entry per account, keyed by the first 16 hex characters of the SHA-256 of
// the auth user id, so accounts on one device never share markers. (The data lane did not ship the
// `DiscoverVisitMemory` owner of spec §11, so this lives with the page; the account-deletion wipe
// through `clearPrivateState` is an open item for the integrator.)

nonisolated struct DiscoverVisitLedger: Codable, Equatable, Sendable {
    struct Snapshot: Codable, Equatable, Sendable {
        var keys: [DiscoverMediaRef]
        var at: Date
    }

    /// The last visit's seen titles per section id.
    var sections: [String: Snapshot] = [:]
    /// When the last visit ended (nil: never).
    var lastEnd: Date? = nil

    /// Keys kept per section snapshot.
    static let capacity = 120
    /// D18: Discover counts as a new visit after this long away.
    static let visitGap: TimeInterval = 30 * 60

    /// The section's NEW titles among `shown` (none without a snapshot).
    func newKeys(section: String, shown: [MediaKey]) -> Set<MediaKey> {
        guard let snapshot = sections[section] else { return [] }
        let seen = Set(snapshot.keys.compactMap(\.key))
        return Set(shown.filter { !seen.contains($0) })
    }

    /// When the section was last seen.
    func lastVisitDate(section: String) -> Date? { sections[section]?.at }

    /// Ends a visit: every section seen in it replaces its snapshot; sections not reached keep theirs.
    mutating func commit(seen: [String: [MediaKey]], at now: Date) {
        for (section, keys) in seen where !keys.isEmpty {
            var unique: [DiscoverMediaRef] = []
            var set: Set<DiscoverMediaRef> = []
            for key in keys {
                let ref = DiscoverMediaRef(key)
                if set.insert(ref).inserted { unique.append(ref) }
            }
            sections[section] = Snapshot(keys: Array(unique.prefix(Self.capacity)), at: now)
        }
        lastEnd = now
    }

    /// D18: a visit starts on the first time Discover becomes current this launch, or after
    /// `visitGap` away; otherwise the earlier visit resumes.
    static func startsVisit(firstThisLaunch: Bool, lastEnd: Date?, now: Date) -> Bool {
        if firstThisLaunch { return true }
        guard let lastEnd else { return true }
        return now.timeIntervalSince(lastEnd) >= visitGap
    }

    // MARK: Storage

    static func storageKey(userId: String) -> String {
        let digest = SHA256.hash(data: Data(userId.lowercased().utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "kuro.discover.visits." + String(hex.prefix(16))
    }

    static func load(defaults: UserDefaults, userId: String) -> DiscoverVisitLedger {
        guard let data = defaults.data(forKey: storageKey(userId: userId)),
              let ledger = try? JSONDecoder().decode(DiscoverVisitLedger.self, from: data) else {
            return DiscoverVisitLedger()
        }
        return ledger
    }

    func save(defaults: UserDefaults, userId: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey(userId: userId))
    }

    static func remove(defaults: UserDefaults, userId: String) {
        defaults.removeObject(forKey: storageKey(userId: userId))
    }
}

/// The NEW / NEU tab on a cover: the season-tab face (`HomeInk.tabFace`, `HomeInk.tabInk`), 7 pt caps,
/// top-left, 6 pt in.
struct DiscoverNewTab: View {
    var body: some View {
        Text(DiscoverIssueCopy.newTab(german: KuroLocale.isGerman))
            .font(.kuroCustom(7, weight: .semibold, relativeTo: .caption2, maxSize: 14))
            .tracking(0.6)
            .foregroundStyle(HomeInk.tabInk)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(HomeInk.tabFace, in: RoundedRectangle(cornerRadius: 3))
            .padding(6)
            .accessibilityHidden(true)
    }
}

/// The heading's NEW marker: a 5 pt ink dot (.7) and "{n} new since {weekday}".
struct DiscoverNewSince: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.kuroInk.opacity(0.7)).frame(width: 5, height: 5)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
