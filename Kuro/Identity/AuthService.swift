import Foundation
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Auth transport (E6c1)
// The SDK calls behind sign-in, sign-up, Sign in with Apple, password reset, the email existence
// check, the profile row and the `delete-account` function, moved from `SupabaseService` with their
// request shapes unchanged. This owner holds no session state: it returns what the SDK reports and the
// session funnel (`SessionController`) decides what the app does with it. It uses the app's single SDK
// client (shared with `SessionController`; never a second one).

/// The signed-in user the SDK reports after an auth call (the SDK `Session` stays in this file).
nonisolated struct AuthSessionIdentity: Sendable, Equatable {
    /// `session.user.id.uuidString` (upper-case, exactly as before; R-E3-4).
    let userId: String
    let email: String?
}

/// Typed failures of the auth transport. Their `localizedDescription` is the text the former
/// `NSError`s carried (ProfileView and AuthView show it).
nonisolated enum AuthFailure: LocalizedError, Equatable {
    /// The app has no SDK client (SUPABASE_URL / SUPABASE_ANON_KEY missing); carries the message.
    case missingConfiguration(String)
    /// `delete-account` answered 2xx without `success: true`; carries the server's message.
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message), .deletionFailed(let message):
            return message
        }
    }
}

@MainActor
@Observable
final class AuthService {
    /// Auth callback redirect URL — custom scheme so Supabase redirects straight into the app (no intermediate webpage).
    static let authCallbackURL = URL(string: "kuro://auth/callback")!

    /// The app's single SDK client (nil only when the configuration is missing).
    @ObservationIgnored private let client: SupabaseClient?
    /// Receives the configuration error as the auth message when a call cannot run.
    @ObservationIgnored private let identity: IdentityStore

    init(client: SupabaseClient?, identity: IdentityStore) {
        self.client = client
        self.identity = identity
    }

    /// The failure thrown when the app has no SDK client.
    func missingConfiguration() -> AuthFailure {
        .missingConfiguration(identity.configError ?? "Missing Supabase configuration.")
    }

    // MARK: Sign-in transport (the session funnel publishes the result)

    /// Email + password sign-in; the session the SDK then holds.
    func signIn(email: String, password: String) async throws -> AuthSessionIdentity {
        guard let client else { throw missingConfiguration() }
        _ = try await client.auth.signIn(email: email, password: password)
        let session = try await client.auth.session
        return AuthSessionIdentity(userId: session.user.id.uuidString, email: session.user.email)
    }

    /// Sign-up; the session the SDK holds afterwards, or nil when there is none (email confirmation on).
    func signUp(email: String, password: String) async throws -> AuthSessionIdentity? {
        guard let client else { throw missingConfiguration() }
        _ = try await client.auth.signUp(email: email, password: password)
        // With email confirmation disabled, the session is immediately available.
        guard let session = (try? await client.auth.session) else { return nil }
        return AuthSessionIdentity(userId: session.user.id.uuidString, email: session.user.email)
    }

    /// Sign in with Apple (ID token + raw nonce).
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthSessionIdentity {
        guard let client else { throw missingConfiguration() }
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )
        return AuthSessionIdentity(userId: session.user.id.uuidString, email: session.user.email)
    }

    /// Apple only provides the full name on the first sign-in; persists it (best effort).
    func saveFullName(_ fullName: String) async {
        guard let client else { return }
        _ = try? await client.auth.update(
            user: .init(data: ["full_name": .string(fullName)])
        )
    }

    /// Ensures the signed-in user's `profiles` row exists (best effort).
    func ensureProfileRow() async {
        guard let client, let user = try? await client.auth.session.user else { return }
        struct ProfilePayload: Encodable {
            let id: UUID
            let adult_opt_in: Bool
        }
        do {
            try await client
                .from("profiles")
                .upsert(ProfilePayload(id: user.id, adult_opt_in: false), onConflict: "id", ignoreDuplicates: true)
                .execute()
        } catch {
            #if DEBUG
            print("⚠️ ensureProfileRow failed: \(error)")
            #endif
            // Error logged in debug only
        }
    }

    // MARK: Account deletion transport

    /// Whether the signed-in user has an Apple identity (deletion then revokes its token).
    var isAppleUser: Bool {
        get async {
            guard let client else { return false }
            guard let user = try? await client.auth.user() else { return false }
            return user.identities?.contains(where: { $0.provider == "apple" }) ?? false
        }
    }

    /// GDPR-compliant account deletion. Calls the `delete-account` Edge Function
    /// which cascades through all user data tables, removes storage objects,
    /// then deletes the auth.users row.
    /// Invokes `delete-account` (request body unchanged). Any non-2xx response throws
    /// `FunctionsError.httpError`; a 2xx without `success: true` throws `AuthFailure.deletionFailed`.
    /// Returns only when the server confirmed the deletion.
    func requestAccountDeletion(appleAuthorizationCode: String?) async throws {
        guard let client else { throw missingConfiguration() }
        struct DeleteResponse: Decodable {
            let success: Bool?
            let error: String?
            let message: String?
        }
        var body: [String: String] = ["confirm": "true"]
        if let appleAuthorizationCode {
            body["apple_authorization_code"] = appleAuthorizationCode
        }
        let response: DeleteResponse = try await client.functions.invoke(
            "delete-account",
            options: .init(body: body)
        )
        if response.success != true {
            throw AuthFailure.deletionFailed(response.error ?? response.message ?? "Account deletion failed")
        }
    }

    /// Sets the signed-in user's new password (the set-new-password screen after a recovery link).
    /// Throws the SDK error (`same_password`, `weak_password`, `reauthentication_needed`, ...).
    func updatePassword(_ password: String) async throws {
        guard let client else { throw missingConfiguration() }
        _ = try await client.auth.update(user: UserAttributes(password: password))
    }

    // MARK: Calls views make directly

    /// Email existence check (`check_email_exists`). **Not called by the app since 2026-11-01**
    /// (spec D13: a live "taken" indicator lets anyone test addresses; a duplicate address is now
    /// reported by sign-up itself). Kept only for the fixture-host test that proves the composed
    /// client is denied locally; a prepared migration revokes the RPC from anon.
    func checkEmailExists(email: String) async -> Bool {
        guard let client else {
            identity.authErrorMessage = identity.configError
            return false
        }
        do {
            let result: Bool = try await client
                .rpc("check_email_exists", params: ["p_email": email])
                .execute()
                .value
            return result
        } catch {
            #if DEBUG
            print("[Auth] checkEmailExists error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Sends the reset email (PKCE: the SDK stores this device's code verifier first). The session
    /// funnel records the pending flow after this returns (`SessionController.requestPasswordReset`).
    func resetPassword(email: String) async throws {
        guard let client else {
            identity.authErrorMessage = identity.configError
            throw missingConfiguration()
        }
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.authCallbackURL)
    }

    // MARK: User-facing auth errors

    /// The user-facing text for an auth failure, in the reader's language (EN/DE). Order: transport
    /// failures, then the SDK's typed GoTrue code (`AuthError.errorCode`), then known server wording
    /// (errors that arrive without a code), then a generic line.
    nonisolated static func userFacingAuthErrorMessage(from error: Error, german: Bool = KuroLocale.isGerman) -> String {
        #if DEBUG
        let chain = authErrorChain(from: error)
            .map { "\($0.domain)(\($0.code)): \($0.localizedDescription)" }
            .joined(separator: " -> ")
        print("[Auth] error chain: \(chain)")
        #endif

        if let transport = transportFailure(from: error) {
            return AuthCopy.transport(transport, german: german)
        }
        if let code = authErrorCode(of: error),
           let message = AuthCopy.message(forCode: code, weakPasswordReasons: weakPasswordReasons(of: error), german: german) {
            return message
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("invalid login credentials") {
            return AuthCopy.message(forCode: "invalid_credentials", german: german) ?? AuthCopy.generic(german: german)
        } else if lower.contains("user already registered") {
            return AuthCopy.message(forCode: "user_already_exists", german: german) ?? AuthCopy.generic(german: german)
        } else if lower.contains("email not confirmed") {
            return AuthCopy.message(forCode: "email_not_confirmed", german: german) ?? AuthCopy.generic(german: german)
        } else if lower.contains("password should be at least") {
            return AuthCopy.message(forCode: "weak_password", german: german) ?? AuthCopy.generic(german: german)
        }
        return AuthCopy.generic(german: german)
    }

    /// The GoTrue error code the SDK reports (`AuthError.errorCode`), `pkce_grant_code_exchange` for a
    /// code exchange the SDK itself refused, `http_429` for a rate-limited answer without a code;
    /// nil for any other error.
    nonisolated static func authErrorCode(of error: Error) -> String? {
        guard let authError = error as? AuthError else { return nil }
        switch authError {
        case .pkceGrantCodeExchange:
            return "pkce_grant_code_exchange"
        case .api(_, let code, _, let response):
            if code == .unknown, response.statusCode == 429 { return "http_429" }
            return code == .unknown ? nil : code.rawValue
        default:
            let code = authError.errorCode
            return code == .unknown ? nil : code.rawValue
        }
    }

    /// Whether sign-up failed because the address already has an account (the form then offers
    /// sign-in; spec D13 reports a duplicate address on submit only).
    nonisolated static func isAccountExistsError(_ error: Error) -> Bool {
        if let code = authErrorCode(of: error) {
            return code == ErrorCode.userAlreadyExists.rawValue || code == ErrorCode.emailExists.rawValue
        }
        return error.localizedDescription.lowercased().contains("user already registered")
    }

    nonisolated private static func weakPasswordReasons(of error: Error) -> [String] {
        if case .weakPassword(_, let reasons) = error as? AuthError { return reasons }
        return []
    }

    /// Saved SDK identity may render personal offline data after a transport outage.
    /// HTTP/auth rejection and malformed responses never establish that identity.
    nonisolated static func permitsOfflineRestore(_ error: Error) -> Bool {
        authErrorChain(from: error).contains { candidate in
            guard candidate.domain == NSURLErrorDomain else { return false }
            switch URLError.Code(rawValue: candidate.code) {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff,
                 .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .cannotLoadFromNetwork:
                return true
            default: return false
            }
        }
    }

    nonisolated private static func transportFailure(from error: Error) -> AuthCopy.Transport? {
        for candidate in authErrorChain(from: error) {
            guard candidate.domain == NSURLErrorDomain else { continue }
            let code = URLError.Code(rawValue: candidate.code)
            switch code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .networkConnectionLost:
                return .connectionLost
            case .timedOut:
                return .timedOut
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .secureConnectionFailed, .cannotLoadFromNetwork,
                 .appTransportSecurityRequiresSecureConnection, .badServerResponse:
                return .unreachable
            default:
                continue
            }
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("internet connection appears to be offline") ||
            lower.contains("not connected to the internet") {
            return .offline
        } else if lower.contains("network connection was lost") {
            return .connectionLost
        } else if lower.contains("timed out") {
            return .timedOut
        } else if lower.contains("cannot connect to the server") ||
                    lower.contains("could not connect to the server") ||
                    lower.contains("cannot connect to host") {
            return .unreachable
        }
        return nil
    }

    nonisolated private static func authErrorChain(from error: Error) -> [NSError] {
        var queue: [NSError] = [error as NSError]
        var seen = Set<String>()
        var chain: [NSError] = []

        while let current = queue.first {
            queue.removeFirst()
            let key = "\(current.domain)#\(current.code)#\(current.localizedDescription)"
            if !seen.insert(key).inserted {
                continue
            }
            chain.append(current)
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                queue.append(underlying)
            } else if let underlying = current.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying as NSError)
            }
        }

        return chain
    }
}
#endif
