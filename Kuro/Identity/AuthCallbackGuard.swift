import Foundation
import KuroCore

// The auth-callback decision of the session funnel (`SessionController.handleAuthCallback`), moved
// from `Kuro/Services/AccountSession.swift` (E6c1); since 2026-11-01 (spec D12) it also binds a
// signed-out link to the pending flow this device started (`PendingAuthFlow`). Account lifecycle primitives
// (`AccountContext`, `AccountSessionCoordinator`, `AccountScopedLoads`) live in the KuroCore package.

// MARK: - Auth callback guard

nonisolated enum AuthCallbackDecision: Equatable, Sendable {
    /// Signed in: the link's implicit token pair belongs to the signed-in user (unchanged rule).
    case proceed
    /// Signed out: an implicit token pair that matches the live flow this device started (same
    /// address, same flow, issued after it started, unexpired). Applied with `setSession`.
    case applyPendingTokens(PendingAuthFlowKind)
    /// Signed out: a PKCE code for the live flow this device started. Exchanged with this device's
    /// code verifier (the server rejects any other device's code).
    case exchangeCode(PendingAuthFlowKind)
    /// While someone is signed in, the link cannot be shown to belong to that user
    /// (fail closed: another, missing or unreadable subject, no usable expiry, or a code link).
    case rejectDifferentUser
    /// Signed out and no live flow this device started matches the link (login CSRF, spec D12).
    case rejectNoPendingFlow
    /// The link reports a failure (expired, already used) and carries nothing to apply.
    case linkError
}

nonisolated enum AuthCallbackGuard {
    /// Minimum remaining access-token lifetime required before a token pair is applied.
    /// `setSession` re-reads the clock after this guard; the margin keeps the token unexpired at
    /// that point (so the SDK verifies it with the server instead of trusting the refresh token).
    static let minimumRemainingValidity: TimeInterval = 60
    /// Clock skew allowed between the device and the token issuer.
    static let allowedClockSkew: TimeInterval = 60

    /// Decides whether a `kuro://auth/callback` link may be applied (R-E1-2 and D12, fail closed).
    /// Tokens are decoded locally only (their signature is NOT verified here); the server verifies
    /// them afterwards and the funnel re-checks the account it got.
    /// - Error-only link: `.linkError`.
    /// - Signed in: a token pair proceeds only when its `sub` equals the current user AND its `exp`
    ///   lies at least `minimumRemainingValidity` ahead (supabase-swift 2.54.1 `setSession` verifies an
    ///   unexpired access token with `/user` but replaces the session from the refresh token alone when
    ///   `exp` is missing or past). A code link is rejected (it cannot be shown to be this user's).
    /// - Signed out: nothing is adopted unless a live flow this device started matches: a code is
    ///   exchanged for it; a token pair must also carry that flow's address (`email`), be issued
    ///   after it started (`iat`, when present) and be unexpired. A link `type` must match the flow.
    static func decision(
        payload: AuthCallbackPayload,
        currentUserId: String?,
        pending: PendingAuthFlow?,
        now: Date = Date()
    ) -> AuthCallbackDecision {
        if payload.isErrorOnly { return .linkError }
        if let currentUserId {
            guard payload.code == nil, let accessToken = payload.accessToken else { return .rejectDifferentUser }
            return signedInDecision(accessToken: accessToken, currentUserId: currentUserId, now: now)
        }
        guard let pending, pending.isLive(at: now), pending.kind.matches(linkType: payload.type) else {
            return .rejectNoPendingFlow
        }
        if payload.code != nil { return .exchangeCode(pending.kind) }
        guard let accessToken = payload.accessToken,
              let claims = jwtPayload(accessToken),
              pending.matches(email: claims["email"] as? String),
              let exp = claims["exp"] as? TimeInterval,
              Date(timeIntervalSince1970: exp) > now.addingTimeInterval(minimumRemainingValidity)
        else { return .rejectNoPendingFlow }
        if let iat = claims["iat"] as? TimeInterval,
           Date(timeIntervalSince1970: iat).addingTimeInterval(allowedClockSkew) < pending.createdAt {
            return .rejectNoPendingFlow
        }
        return .applyPendingTokens(pending.kind)
    }

    /// The token-pair rule without a pending flow (the pre-D12 entry point; tests and the signed-in
    /// path). Signed out, a token pair is never adopted without a matching pending flow.
    static func decision(accessToken: String, currentUserId: String?, now: Date = Date()) -> AuthCallbackDecision {
        decision(
            payload: AuthCallbackPayload(accessToken: accessToken, refreshToken: "-"),
            currentUserId: currentUserId,
            pending: nil,
            now: now
        )
    }

    private static func signedInDecision(accessToken: String, currentUserId: String, now: Date) -> AuthCallbackDecision {
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
