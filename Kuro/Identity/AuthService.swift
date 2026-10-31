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

    // MARK: Calls views make directly

    /// Lightweight email existence check for inline sign-up validation.
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

    func resetPassword(email: String) async throws {
        guard let client else {
            identity.authErrorMessage = identity.configError
            throw missingConfiguration()
        }
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.authCallbackURL)
    }

    // MARK: User-facing auth errors

    nonisolated static func userFacingAuthErrorMessage(from error: Error) -> String {
        #if DEBUG
        let chain = authErrorChain(from: error)
            .map { "\($0.domain)(\($0.code)): \($0.localizedDescription)" }
            .joined(separator: " -> ")
        print("[Auth] error chain: \(chain)")
        #endif

        if let transportMessage = transportAuthErrorMessage(from: error) {
            return transportMessage
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("invalid login credentials") {
            return "Incorrect email or password. Please try again."
        } else if lower.contains("user already registered") {
            return "An account with this email already exists. Try signing in instead."
        } else if lower.contains("email not confirmed") {
            return "Please check your email to verify your account."
        } else if lower.contains("password should be at least") {
            return "Password must be at least 6 characters."
        }
        return "Something went wrong. Please try again."
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

    nonisolated private static func transportAuthErrorMessage(from error: Error) -> String? {
        for candidate in authErrorChain(from: error) {
            guard candidate.domain == NSURLErrorDomain else { continue }
            let code = URLError.Code(rawValue: candidate.code)
            switch code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return "No internet connection. Check your connection and try again."
            case .networkConnectionLost:
                return "The network connection was lost. Please try again."
            case .timedOut:
                return "The request timed out. Please try again."
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .secureConnectionFailed, .cannotLoadFromNetwork,
                 .appTransportSecurityRequiresSecureConnection, .badServerResponse:
                return "Can't reach the server right now. Please try again."
            default:
                continue
            }
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("internet connection appears to be offline") ||
            lower.contains("not connected to the internet") {
            return "No internet connection. Check your connection and try again."
        } else if lower.contains("network connection was lost") {
            return "The network connection was lost. Please try again."
        } else if lower.contains("timed out") {
            return "The request timed out. Please try again."
        } else if lower.contains("cannot connect to the server") ||
                    lower.contains("could not connect to the server") ||
                    lower.contains("cannot connect to host") {
            return "Can't reach the server right now. Please try again."
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
