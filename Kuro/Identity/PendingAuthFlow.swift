import CryptoKit
import Foundation

// MARK: - Pending email-link flow (spec D12)
// The device that starts an email-link flow (password reset; magic link reserved) is the only device
// that may finish it, only for that flow, within its lifetime, once. PKCE gives the server-side binding
// (the code verifier lives in this device's SDK keychain); this record supplies what a PKCE redirect
// does not carry reliably: the flow kind, the expiry and the address it was requested for. It holds no
// secret (the address is stored only as a SHA-256 hash), so `UserDefaults` is enough. One slot, like
// the SDK's single code-verifier slot: a newer request replaces the older one.

/// The email-link flows this device can start.
nonisolated enum PendingAuthFlowKind: String, Codable, Sendable {
    /// "Forgot password": the link leads to the set-new-password screen.
    case recovery
    /// Passwordless sign-in (reserved; the app offers no magic-link request yet).
    case magicLink

    /// Whether a link's `type` parameter (when present) belongs to this flow.
    func matches(linkType: String?) -> Bool {
        guard let linkType = linkType?.lowercased(), !linkType.isEmpty else { return true }
        switch self {
        case .recovery: return linkType == "recovery"
        case .magicLink: return linkType == "magiclink"
        }
    }
}

/// One started email-link flow.
nonisolated struct PendingAuthFlow: Codable, Equatable, Sendable {
    /// Matches "This link expires in 1 hour." in the email templates (GoTrue OTP expiry, dashboard).
    static let lifetime: TimeInterval = 3_600

    let kind: PendingAuthFlowKind
    /// SHA-256 (hex) of the trimmed, lower-cased address the flow was requested for.
    let emailHash: String
    let createdAt: Date
    let expiresAt: Date

    init(kind: PendingAuthFlowKind, email: String, createdAt: Date) {
        self.kind = kind
        emailHash = Self.emailHash(email)
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(Self.lifetime)
    }

    /// Live: started no later than `now` (a small clock skew allowed) and not yet expired.
    func isLive(at now: Date) -> Bool {
        now < expiresAt && now.addingTimeInterval(60) >= createdAt
    }

    /// Whether `email` is the address this flow was requested for (case and whitespace ignored).
    func matches(email: String?) -> Bool {
        guard let email, !email.isEmpty else { return false }
        return Self.emailHash(email) == emailHash
    }

    static func emailHash(_ email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The single persisted pending-flow slot. `defaults` is injectable for tests.
nonisolated struct PendingAuthFlowStore {
    static let key = "kuro.auth.pendingFlow"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records a flow this device just started (replaces any older one).
    @discardableResult
    func begin(_ kind: PendingAuthFlowKind, email: String, now: Date = Date()) -> PendingAuthFlow {
        let flow = PendingAuthFlow(kind: kind, email: email, createdAt: now)
        if let data = try? JSONEncoder().encode(flow) {
            defaults.set(data, forKey: Self.key)
        }
        return flow
    }

    /// The live flow, if any. An expired or unreadable record is removed.
    func current(now: Date = Date()) -> PendingAuthFlow? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        guard let flow = try? JSONDecoder().decode(PendingAuthFlow.self, from: data), flow.isLive(at: now) else {
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        return flow
    }

    /// Single use: removes the flow once a link for it was accepted.
    func consume() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Sign-out and deletion forget any started flow.
    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

// MARK: - Password update requirement
// A recovery link signs the user in; until they choose a new password the root shows the
// set-new-password screen instead of the app. Persisted per account, so killing the app between the
// code exchange and the update still lands on that screen after a relaunch.

nonisolated struct PasswordUpdateRequirementStore {
    static let keyPrefix = "kuro.auth.requiresPasswordUpdate."

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(for userId: String) -> String {
        keyPrefix + userId.lowercased()
    }

    func isRequired(for userId: String) -> Bool {
        defaults.bool(forKey: Self.key(for: userId))
    }

    func require(for userId: String) {
        defaults.set(true, forKey: Self.key(for: userId))
    }

    func clear(for userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }
}
