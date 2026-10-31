import Foundation
import KuroCore

// The auth-callback decision of the session funnel (`SessionController.handleAuthCallback`), moved
// verbatim from `Kuro/Services/AccountSession.swift` (E6c1). Account lifecycle primitives
// (`AccountContext`, `AccountSessionCoordinator`, `AccountScopedLoads`) live in the KuroCore package.

// MARK: - Auth callback guard

nonisolated enum AuthCallbackDecision: Equatable, Sendable {
    case proceed
    /// While someone is signed in, the link cannot be shown to belong to that user
    /// (fail closed: another, missing or unreadable subject, or no usable expiry).
    case rejectDifferentUser
}

nonisolated enum AuthCallbackGuard {
    /// Minimum remaining access-token lifetime required while signed in. `setSession` re-reads the
    /// clock after this guard; the margin keeps the token unexpired at that point.
    static let minimumRemainingValidity: TimeInterval = 60

    /// Decides whether a `kuro://auth/callback` session may be applied (R-E1-2, fail closed).
    /// The token is decoded locally only (its signature is NOT verified here); no PKCE/nonce
    /// protection is implied.
    /// - Signed out: proceed (`setSession` validates the tokens with the server).
    /// - Signed in: proceed only when the token's `sub` equals the current user AND its `exp` lies
    ///   at least `minimumRemainingValidity` in the future. supabase-swift 2.54.1 `setSession`
    ///   verifies an unexpired access token with the server (`/user`) but replaces the session from
    ///   the link's refresh token alone when `exp` is missing or past, so a forged `sub` is only
    ///   harmless on the first path.
    static func decision(accessToken: String, currentUserId: String?, now: Date = Date()) -> AuthCallbackDecision {
        guard let currentUserId else { return .proceed }
        guard let payload = jwtPayload(accessToken),
              let subject = payload["sub"] as? String, !subject.isEmpty,
              AccountSessionCoordinator.sameUser(subject, currentUserId),
              let exp = payload["exp"] as? TimeInterval,
              Date(timeIntervalSince1970: exp) > now.addingTimeInterval(minimumRemainingValidity)
        else { return .rejectDifferentUser }
        return .proceed
    }

    /// The JWT payload, parsed like supabase-swift's `JWT.decodePayload` (empty segments dropped,
    /// exactly three parts) but with strict base64, so any payload read here is the one the SDK reads.
    static func jwtPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
