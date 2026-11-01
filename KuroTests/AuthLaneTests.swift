//
//  AuthLaneTests.swift
//  KuroTests
//
//  Overnight 2026-11-01 auth lane (spec D7, D12, D13): callback parsing, the pending email-link flow,
//  the signed-out callback guard, the PKCE exchange and recovery path through the real SDK client,
//  the set-new-password requirement, error copy by SDK code (EN/DE), form rules, per-account
//  onboarding completion and the single bootstrap Library read.
//

import Foundation
import KuroCore
import KuroLibrary
import Supabase
import Testing
@testable import Kuro

// MARK: - Fixtures

private enum AuthLaneFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let a = LifecycleFixtures.userA.lowercased()
    static let b = LifecycleFixtures.userB.lowercased()

    static func defaults() throws -> (UserDefaults, String) {
        let name = "kuro.tests.auth-lane.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    static func token(sub: String, email: String?, exp: TimeInterval?, iat: TimeInterval? = nil,
                      amr: String? = nil) -> String {
        var fields = [#""sub":"\#(sub)""#, #""role":"authenticated""#]
        if let email { fields.append(#""email":"\#(email)""#) }
        if let exp { fields.append(#""exp":\#(Int(exp))"#) }
        if let iat { fields.append(#""iat":\#(Int(iat))"#) }
        if let amr { fields.append(#""amr":[{"method":"\#(amr)","timestamp":1}]"#) }
        return AuthCallbackGuardTests.jwt("{" + fields.joined(separator: ",") + "}")
    }

    static func recovery(email: String = "a@example.com", createdAt: Date = now) -> PendingAuthFlow {
        PendingAuthFlow(kind: .recovery, email: email, createdAt: createdAt)
    }
}

// MARK: - Deep link parsing

@Suite("Auth lane: callback link parsing")
struct AuthCallbackParsingTests {
    private func payload(_ string: String) throws -> AuthCallbackPayload? {
        let url = try #require(URL(string: string))
        guard case .authCallback(let payload) = DeepLink.from(url: url) else { return nil }
        return payload
    }

    @Test("A PKCE redirect (?code=) is a payload with the code")
    func pkceCode() throws {
        let parsed = try #require(try payload("kuro://auth/callback?code=4c1d8f0e-aaaa-bbbb"))
        #expect(parsed.code == "4c1d8f0e-aaaa-bbbb")
        #expect(!parsed.hasTokens)
        #expect(!parsed.isErrorOnly)
    }

    @Test("An implicit fragment keeps both tokens and the flow type; values containing '=' survive")
    func implicitFragment() throws {
        let parsed = try #require(try payload("kuro://auth/callback#access_token=aaa.bbb.ccc==&refresh_token=r=1&type=Recovery&expires_in=3600"))
        #expect(parsed.accessToken == "aaa.bbb.ccc==")
        #expect(parsed.refreshToken == "r=1")
        #expect(parsed.type == "recovery")
        #expect(parsed.code == nil)
    }

    @Test("The legacy query-token form is still parsed")
    func legacyQueryTokens() throws {
        let parsed = try #require(try payload("kuro://auth/callback?access_token=x&refresh_token=y"))
        #expect(parsed.accessToken == "x")
        #expect(parsed.refreshToken == "y")
    }

    @Test("An expired-link redirect reaches the app as an error payload (fragment or query)")
    func errorPayload() throws {
        let fragment = try #require(try payload("kuro://auth/callback#error=access_denied&error_code=otp_expired&error_description=Email%20link%20is%20invalid"))
        #expect(fragment.errorCode == "otp_expired")
        #expect(fragment.errorDescription == "Email link is invalid")
        #expect(fragment.isErrorOnly)
        let query = try #require(try payload("kuro://auth/callback?error=access_denied"))
        #expect(query.errorCode == "access_denied")
    }

    @Test("A callback carrying nothing usable is not a deep link")
    func nothingUsable() throws {
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://auth/callback"))) == nil)
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://auth/callback#access_token=only"))) == nil)
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://auth/other?code=x"))) == nil)
    }
}

// MARK: - Pending flow store

@Suite("Auth lane: pending email-link flow")
struct PendingAuthFlowTests {
    @Test("begin records kind, hashed address, start and a one-hour expiry; consume is single use")
    func beginCurrentConsume() throws {
        let (defaults, name) = try AuthLaneFixtures.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PendingAuthFlowStore(defaults: defaults)
        let now = AuthLaneFixtures.now
        store.begin(.recovery, email: "  A@Example.com ", now: now)

        let flow = try #require(store.current(now: now.addingTimeInterval(10)))
        #expect(flow.kind == .recovery)
        #expect(flow.emailHash == PendingAuthFlow.emailHash("a@example.com"))
        #expect(flow.matches(email: "a@EXAMPLE.com"))
        #expect(!flow.matches(email: "b@example.com"))
        #expect(flow.expiresAt == now.addingTimeInterval(3_600))
        #expect(defaults.string(forKey: PendingAuthFlowStore.key) == nil, "stored as data, never as a readable address")
        let raw = try #require(defaults.data(forKey: PendingAuthFlowStore.key))
        #expect(!String(decoding: raw, as: UTF8.self).contains("example.com"), "the address itself is never stored")

        store.consume()
        #expect(store.current(now: now) == nil)
    }

    @Test("An expired or unreadable record is dropped; a newer request replaces the older one")
    func expiryAndReplacement() throws {
        let (defaults, name) = try AuthLaneFixtures.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PendingAuthFlowStore(defaults: defaults)
        let now = AuthLaneFixtures.now
        store.begin(.recovery, email: "a@example.com", now: now)
        #expect(store.current(now: now.addingTimeInterval(3_601)) == nil)
        #expect(defaults.data(forKey: PendingAuthFlowStore.key) == nil)

        store.begin(.recovery, email: "a@example.com", now: now)
        store.begin(.magicLink, email: "b@example.com", now: now.addingTimeInterval(5))
        #expect(store.current(now: now.addingTimeInterval(6))?.kind == .magicLink)

        defaults.set(Data("not json".utf8), forKey: PendingAuthFlowStore.key)
        #expect(store.current(now: now) == nil)
        #expect(defaults.data(forKey: PendingAuthFlowStore.key) == nil)
    }

    @Test("A link type must belong to the flow; a link without a type is allowed")
    func linkTypes() {
        #expect(PendingAuthFlowKind.recovery.matches(linkType: nil))
        #expect(PendingAuthFlowKind.recovery.matches(linkType: "RECOVERY"))
        #expect(!PendingAuthFlowKind.recovery.matches(linkType: "magiclink"))
        #expect(!PendingAuthFlowKind.recovery.matches(linkType: "signup"))
        #expect(PendingAuthFlowKind.magicLink.matches(linkType: "magiclink"))
    }

    @Test("The password-update requirement is per account, case-insensitive and clearable")
    func passwordRequirement() throws {
        let (defaults, name) = try AuthLaneFixtures.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PasswordUpdateRequirementStore(defaults: defaults)
        store.require(for: LifecycleFixtures.userA)
        #expect(store.isRequired(for: AuthLaneFixtures.a))
        #expect(!store.isRequired(for: LifecycleFixtures.userB))
        store.clear(for: AuthLaneFixtures.a)
        #expect(!store.isRequired(for: LifecycleFixtures.userA))
    }
}

// MARK: - Guard

@Suite("Auth lane: callback guard with pending flows")
struct PendingCallbackGuardTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let payload: AuthCallbackPayload
        let currentUserId: String?
        var currentUserEmail: String? = nil
        let pending: PendingAuthFlow?
        let expected: AuthCallbackDecision
        var testDescription: String { name }

        init(name: String, payload: AuthCallbackPayload, currentUserId: String?, currentUserEmail: String? = nil,
             pending: PendingAuthFlow?, expected: AuthCallbackDecision) {
            self.name = name
            self.payload = payload
            self.currentUserId = currentUserId
            self.currentUserEmail = currentUserEmail
            self.pending = pending
            self.expected = expected
        }
    }

    static let now = AuthLaneFixtures.now
    static let future = now.timeIntervalSince1970 + 3_600
    static let live = AuthLaneFixtures.recovery(createdAt: now.addingTimeInterval(-120))
    static let expired = AuthLaneFixtures.recovery(createdAt: now.addingTimeInterval(-3_700))

    static func tokens(_ token: String, type: String? = "recovery") -> AuthCallbackPayload {
        AuthCallbackPayload(accessToken: token, refreshToken: "refresh", type: type)
    }

    static let cases: [Case] = [
        Case(name: "signed out: code + live recovery flow -> exchange",
             payload: AuthCallbackPayload(code: "c"), currentUserId: nil, pending: live, expected: .exchangeCode(.recovery)),
        Case(name: "signed out: code without a pending flow -> reject (login CSRF)",
             payload: AuthCallbackPayload(code: "c"), currentUserId: nil, pending: nil, expected: .rejectNoPendingFlow),
        Case(name: "signed out: code + expired flow -> reject",
             payload: AuthCallbackPayload(code: "c"), currentUserId: nil, pending: expired, expected: .rejectNoPendingFlow),
        Case(name: "signed out: code typed for another flow -> reject",
             payload: AuthCallbackPayload(code: "c", type: "magiclink"), currentUserId: nil, pending: live, expected: .rejectNoPendingFlow),
        Case(name: "signed out: tokens for the flow's address, issued after it started -> apply",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: "A@example.com", exp: future, iat: now.timeIntervalSince1970)),
             currentUserId: nil, pending: live, expected: .applyPendingTokens(.recovery)),
        Case(name: "signed out: tokens for another address (attacker's own session) -> reject",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.b, email: "b@example.com", exp: future)),
             currentUserId: nil, pending: live, expected: .rejectNoPendingFlow),
        Case(name: "signed out: tokens without exp (SDK would trust the refresh token) -> reject",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: "a@example.com", exp: nil)),
             currentUserId: nil, pending: live, expected: .rejectNoPendingFlow),
        Case(name: "signed out: tokens issued before the flow started -> reject",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: "a@example.com", exp: future,
                                                    iat: now.timeIntervalSince1970 - 3_000)),
             currentUserId: nil, pending: live, expected: .rejectNoPendingFlow),
        Case(name: "signed out: tokens with no pending flow -> reject",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: "a@example.com", exp: future)),
             currentUserId: nil, pending: nil, expected: .rejectNoPendingFlow),
        Case(name: "signed out: undecodable token -> reject",
             payload: tokens("not-a-jwt"), currentUserId: nil, pending: live, expected: .rejectNoPendingFlow),
        Case(name: "error-only link -> link error (signed out)",
             payload: AuthCallbackPayload(errorCode: "otp_expired"), currentUserId: nil, pending: live, expected: .linkError),
        Case(name: "error-only link -> link error (signed in)",
             payload: AuthCallbackPayload(errorCode: "otp_expired"), currentUserId: LifecycleFixtures.userA, pending: nil, expected: .linkError),
        Case(name: "signed in: code + live flow requested for the signed-in address -> exchange (re-checked after)",
             payload: AuthCallbackPayload(code: "c"), currentUserId: LifecycleFixtures.userA,
             currentUserEmail: "A@example.com", pending: live, expected: .exchangeCode(.recovery)),
        Case(name: "signed in: code without a pending flow -> reject (signed in already, not 'other account')",
             payload: AuthCallbackPayload(code: "c"), currentUserId: LifecycleFixtures.userA,
             currentUserEmail: "a@example.com", pending: nil, expected: .rejectCodeWhileSignedIn),
        Case(name: "signed in: code + live flow for another address -> reject",
             payload: AuthCallbackPayload(code: "c"), currentUserId: LifecycleFixtures.userA,
             currentUserEmail: "b@example.com", pending: live, expected: .rejectCodeWhileSignedIn),
        Case(name: "signed in: code + flow but unknown signed-in address -> reject",
             payload: AuthCallbackPayload(code: "c"), currentUserId: LifecycleFixtures.userA,
             currentUserEmail: nil, pending: live, expected: .rejectCodeWhileSignedIn),
        Case(name: "signed in: code + expired flow -> reject",
             payload: AuthCallbackPayload(code: "c"), currentUserId: LifecycleFixtures.userA,
             currentUserEmail: "a@example.com", pending: expired, expected: .rejectCodeWhileSignedIn),
        Case(name: "signed out: sign-up confirmation nobody here started -> email confirmed, nothing adopted",
             payload: AuthCallbackPayload(code: "c", type: "signup"), currentUserId: nil, pending: nil, expected: .emailConfirmed),
        Case(name: "signed out: email-change confirmation with a recovery flow pending -> email confirmed",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: "a@example.com", exp: future), type: "email_change"),
             currentUserId: nil, pending: live, expected: .emailConfirmed),
        Case(name: "signed out: tokens from a password sign-in (amr) for the flow's address -> reject",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: "a@example.com", exp: future, amr: "password")),
             currentUserId: nil, pending: live, expected: .rejectNoPendingFlow),
        Case(name: "signed out: tokens from the recovery link (amr) for the flow's address -> apply",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: "a@example.com", exp: future, amr: "recovery")),
             currentUserId: nil, pending: live, expected: .applyPendingTokens(.recovery)),
        Case(name: "signed in: same-user tokens, future exp -> proceed (unchanged rule)",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.a, email: nil, exp: future), type: nil),
             currentUserId: LifecycleFixtures.userA, pending: nil, expected: .proceed),
        Case(name: "signed in: other-user tokens -> reject even with a pending flow",
             payload: tokens(AuthLaneFixtures.token(sub: AuthLaneFixtures.b, email: "a@example.com", exp: future)),
             currentUserId: LifecycleFixtures.userA, pending: live, expected: .rejectDifferentUser),
    ]

    @Test("Decision table", arguments: cases)
    func decision(_ testCase: Case) {
        #expect(AuthCallbackGuard.decision(
            payload: testCase.payload,
            currentUserId: testCase.currentUserId,
            currentUserEmail: testCase.currentUserEmail,
            pending: testCase.pending,
            now: Self.now
        ) == testCase.expected)
    }
}

// MARK: - Copy and form rules

@Suite("Auth lane: error copy by SDK code and form rules")
struct AuthCopyAndRulesTests {
    static func apiError(_ code: ErrorCode, status: Int = 400) -> AuthError {
        .api(
            message: "server text",
            errorCode: code,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)
                ?? HTTPURLResponse()
        )
    }

    @Test("Typed GoTrue codes map to specific EN and DE copy")
    func typedCodes() {
        let invalid = Self.apiError(.invalidCredentials)
        #expect(AuthService.userFacingAuthErrorMessage(from: invalid, german: false) == "Incorrect email or password.")
        #expect(AuthService.userFacingAuthErrorMessage(from: invalid, german: true) == "E-Mail-Adresse oder Passwort ist falsch.")
        #expect(AuthService.userFacingAuthErrorMessage(from: Self.apiError(.overEmailSendRateLimit, status: 429), german: false)
                == "Too many emails requested. Try again in a few minutes.")
        #expect(AuthService.userFacingAuthErrorMessage(from: Self.apiError(.unknown, status: 429), german: false)
                == "Too many attempts. Wait a moment and try again.")
        #expect(AuthService.userFacingAuthErrorMessage(from: Self.apiError(.flowStateExpired), german: false)
                == AuthCopy.linkMessage(.expired, german: false))
        #expect(AuthService.userFacingAuthErrorMessage(from: Self.apiError(.samePassword), german: true)
                == "Wähle ein anderes Passwort als dein bisheriges.")
        #expect(AuthService.userFacingAuthErrorMessage(from: AuthError.weakPassword(message: "x", reasons: ["pwned"]), german: false)
                == "This password appeared in a data breach. Choose another one.")
        #expect(AuthService.userFacingAuthErrorMessage(from: AuthError.pkceGrantCodeExchange(message: "no verifier"), german: false)
                == AuthCopy.linkMessage(.expired, german: false))
        #expect(AuthService.userFacingAuthErrorMessage(from: Self.apiError(.unknown, status: 500), german: true)
                == AuthCopy.generic(german: true))
    }

    @Test("A duplicate address is recognised from the typed code and from server wording")
    func accountExists() {
        #expect(AuthService.isAccountExistsError(Self.apiError(.userAlreadyExists)))
        #expect(AuthService.isAccountExistsError(Self.apiError(.emailExists)))
        #expect(AuthService.isAccountExistsError(NSError(domain: "Auth", code: 422,
            userInfo: [NSLocalizedDescriptionKey: "User already registered"])))
        #expect(!AuthService.isAccountExistsError(Self.apiError(.invalidCredentials)))
    }

    @Test("Sign-in accepts any non-empty password; sign-up keeps the 8-character rule")
    func formRules() {
        #expect(AuthFormRules.problem(mode: .signIn, email: "a@example.com", password: "secret") == nil)
        #expect(AuthFormRules.problem(mode: .signUp, email: "a@example.com", password: "secret1") == .passwordTooShort)
        #expect(AuthFormRules.problem(mode: .signUp, email: "a@example.com", password: "secret12") == nil)
        #expect(AuthFormRules.problem(mode: .signIn, email: "a@example.com", password: "") == .passwordMissing)
        #expect(AuthFormRules.problem(mode: .signIn, email: "  ", password: "x") == .emailMissing)
        #expect(AuthFormRules.problem(mode: .signIn, email: "a@b", password: "x") == .emailInvalid)
        #expect(AuthFormRules.problem(mode: .signIn, email: " a@example.com ", password: "x") == nil)
        #expect(AuthFormRules.newPasswordProblem("short", confirmation: "short") == .tooShort)
        #expect(AuthFormRules.newPasswordProblem("long enough", confirmation: "long enougH") == .mismatch)
        #expect(AuthFormRules.newPasswordProblem("long enough", confirmation: "long enough") == nil)
    }

    @Test("Every auth message ships in both languages and they differ")
    func bilingual() {
        let codes = ["invalid_credentials", "user_already_exists", "weak_password", "same_password",
                     "over_email_send_rate_limit", "over_request_rate_limit", "email_not_confirmed", "otp_expired",
                     "signup_disabled", "user_banned", "session_expired", "reauthentication_needed", "validation_failed"]
        for code in codes {
            let en = AuthCopy.message(forCode: code, german: false)
            let de = AuthCopy.message(forCode: code, german: true)
            #expect(en != nil && de != nil && en != de, "\(code)")
        }
        for failure in [AuthCopy.LinkFailure.expired, .notRequestedHere, .otherAccount, .signedInAlready, .failed] {
            #expect(AuthCopy.linkMessage(failure, german: false) != AuthCopy.linkMessage(failure, german: true))
        }
        #expect(AuthCopy.emailConfirmed(german: false) != AuthCopy.emailConfirmed(german: true))
        // Neither rejection tells the user to reopen the same link after signing out: sign-out ends the
        // pending flow, so only a new link can work.
        #expect(!AuthCopy.linkMessage(.otherAccount, german: false).contains("open the link again"))
        #expect(AuthCopy.linkMessage(.signedInAlready, german: false).contains("request a new link"))
        #expect(AuthCopy.resetSent(email: "a@example.com", german: true).contains("a@example.com"))
        #expect(AuthCopy.message(forCode: "something_new", german: false) == nil)
    }
}

// MARK: - Onboarding completion

@Suite("Auth lane: per-account onboarding completion")
struct OnboardingCompletionTests {
    @Test("Completion is per account and case-insensitive")
    func perAccount() throws {
        let (defaults, name) = try AuthLaneFixtures.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!OnboardingCompletion.isCompleted(userId: LifecycleFixtures.userA, defaults: defaults))
        OnboardingCompletion.markCompleted(userId: LifecycleFixtures.userA, defaults: defaults)
        #expect(OnboardingCompletion.isCompleted(userId: AuthLaneFixtures.a, defaults: defaults))
        #expect(!OnboardingCompletion.isCompleted(userId: LifecycleFixtures.userB, defaults: defaults),
                "a second account on the device sees onboarding once too")
    }

    @Test("The legacy device flag counts once for the next account, then retires")
    func legacyMigration() throws {
        let (defaults, name) = try AuthLaneFixtures.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: OnboardingCompletion.legacyDeviceKey)
        #expect(OnboardingCompletion.isCompleted(userId: LifecycleFixtures.userA, defaults: defaults))
        #expect(defaults.object(forKey: OnboardingCompletion.legacyDeviceKey) == nil)
        #expect(OnboardingCompletion.isCompleted(userId: LifecycleFixtures.userA, defaults: defaults))
        #expect(!OnboardingCompletion.isCompleted(userId: LifecycleFixtures.userB, defaults: defaults))
    }

    @Test("Account deletion removes only that account's completion (GDPR)")
    func removeOnDeletion() throws {
        let (defaults, name) = try AuthLaneFixtures.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        OnboardingCompletion.markCompleted(userId: LifecycleFixtures.userA, defaults: defaults)
        OnboardingCompletion.markCompleted(userId: LifecycleFixtures.userB, defaults: defaults)
        OnboardingCompletion.remove(userId: LifecycleFixtures.userA.uppercased(), defaults: defaults)
        #expect(defaults.object(forKey: OnboardingCompletion.key(for: LifecycleFixtures.userA)) == nil)
        #expect(OnboardingCompletion.isCompleted(userId: LifecycleFixtures.userB, defaults: defaults))
    }

    @Test("Without a user id (DEBUG preview) the device flag is used and kept")
    func noUser() throws {
        let (defaults, name) = try AuthLaneFixtures.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!OnboardingCompletion.isCompleted(userId: nil, defaults: defaults))
        OnboardingCompletion.markCompleted(userId: nil, defaults: defaults)
        #expect(OnboardingCompletion.isCompleted(userId: nil, defaults: defaults))
        #expect(OnboardingCompletion.isCompleted(userId: nil, defaults: defaults))
    }
}

// MARK: - Through the real SDK client

@MainActor
@Suite("Auth lane: email links and password recovery through the SDK", .timeLimit(.minutes(1)))
struct AuthLaneSessionTests {
    /// GoTrue answers for these scenarios on top of the password grant.
    static func responder(pkceEmail: String = "a@example.com") -> StubServer.Responder {
        StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "pkce" {
                return .json(StubAuth.sessionJSON(StubAuth.user(forEmail: pkceEmail), email: pkceEmail))
            }
            if StubAuth.isAuth(request, "recover") { return .json("{}") }
            if StubAuth.isAuth(request, "user"), request.method == "PUT" {
                return .json(StubAuth.userJSON(StubAuth.userA, email: "a@example.com"))
            }
            return .emptyArray
        }
    }

    static func harness(_ responder: StubServer.Responder? = nil) throws -> SessionSDKHarness {
        let h = try SessionSDKHarness(responder: responder ?? Self.responder())
        h.session.pendingFlows = PendingAuthFlowStore(defaults: h.defaults)
        h.session.passwordUpdates = PasswordUpdateRequirementStore(defaults: h.defaults)
        return h
    }

    private func authRequests(_ h: SessionSDKHarness) -> Int {
        h.requests { $0.path.contains("/auth/v1/") }.count
    }

    @Test("Signed out, an unsolicited token link is never adopted and nothing reaches the server")
    func unsolicitedTokensRejected() async throws {
        let h = try Self.harness()
        let before = authRequests(h)

        await h.session.handleAuthCallback(accessToken: StubAuth.accessToken(StubAuth.userB), refreshToken: "refresh-b")

        #expect(authRequests(h) == before)
        #expect(!h.identity.isAuthenticated)
        #expect(h.client.auth.currentSession == nil)
        #expect(h.identity.authErrorMessage == AuthCopy.linkMessage(.notRequestedHere, german: KuroLocale.isGerman))
        #expect(h.graph.banner.message == nil, "signed out: no banner (the auth screen shows the message)")
        await h.tearDown()
    }

    @Test("Signed out, an unsolicited code link is rejected without an exchange")
    func unsolicitedCodeRejected() async throws {
        let h = try Self.harness()

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "attacker-code"))

        #expect(h.requests { StubAuth.isAuth($0, "token") }.isEmpty)
        #expect(!h.identity.isAuthenticated)
        await h.tearDown()
    }

    @Test("Forgot password sends one recover request with the app redirect, then records the pending flow")
    func resetRecordsPendingFlow() async throws {
        let h = try Self.harness()

        try await h.session.requestPasswordReset(email: " A@example.com ")

        let recover = try #require(h.requests { StubAuth.isAuth($0, "recover") }.first)
        #expect(recover.jsonObject?["email"] as? String == "A@example.com")
        #expect(recover.query("redirect_to") == "kuro://auth/callback")
        let flow = try #require(h.session.pendingFlows.current())
        #expect(flow.kind == .recovery)
        #expect(flow.matches(email: "a@example.com"))
        await h.tearDown()
    }

    @Test("A failed reset request records no pending flow")
    func failedResetRecordsNothing() async throws {
        let h = try Self.harness(StubAuth.signInResponder { request in
            StubAuth.isAuth(request, "recover")
                ? .json(#"{"error_code":"over_email_send_rate_limit","msg":"rate limited"}"#, status: 429)
                : .emptyArray
        })

        await #expect(throws: (any Error).self) { try await h.session.requestPasswordReset(email: "a@example.com") }

        #expect(h.session.pendingFlows.current() == nil)
        await h.tearDown()
    }

    @Test("A recovery code link from this device is exchanged once (PKCE) and opens the set-password screen, persisted for the account")
    func recoveryCodeExchange() async throws {
        let h = try Self.harness()
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "real-code"))

        let exchange = try #require(h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "pkce" }.first)
        #expect(exchange.jsonObject?["auth_code"] as? String == "real-code")
        #expect(h.identity.isAuthenticated)
        #expect(h.identity.currentUserId == StubAuth.userA)
        #expect(h.identity.requiresPasswordUpdate)
        #expect(h.session.passwordUpdates.isRequired(for: StubAuth.userA))
        #expect(h.session.pendingFlows.current() == nil, "single use")
        #expect(!h.identity.isOpeningAuthLink)

        // The same link again: no pending flow any more, so it is refused before any exchange.
        let exchanges = h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "pkce" }.count
        await h.session.endSession()
        await h.session.handleAuthCallback(AuthCallbackPayload(code: "real-code"))
        #expect(h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "pkce" }.count == exchanges)
        await h.tearDown()
    }

    @Test("A code that yields another address than the flow's is signed out locally and reported")
    func exchangeForForeignAddressIsDropped() async throws {
        let h = try Self.harness(Self.responder(pkceEmail: "b@example.com"))
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "code"))

        #expect(!h.identity.isAuthenticated)
        #expect(!h.identity.requiresPasswordUpdate)
        #expect(h.client.auth.currentSession == nil)
        #expect(!h.session.passwordUpdates.isRequired(for: StubAuth.userB))
        #expect(h.identity.authErrorMessage == AuthCopy.linkMessage(.notRequestedHere, german: KuroLocale.isGerman))
        await h.tearDown()
    }

    @Test("A failed exchange reports the expired-link message and leaves no requirement behind")
    func failedExchange() async throws {
        let h = try Self.harness(StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "pkce" {
                return .json(#"{"error_code":"flow_state_not_found","msg":"invalid flow state"}"#, status: 404)
            }
            return .emptyArray
        })
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "stale"))

        #expect(!h.identity.isAuthenticated)
        #expect(!h.identity.requiresPasswordUpdate)
        #expect(!h.identity.isOpeningAuthLink)
        #expect(h.identity.authErrorMessage == AuthCopy.linkMessage(.expired, german: KuroLocale.isGerman))
        await h.tearDown()
    }

    @Test("A transport failure during the exchange keeps the pending flow, so the same link works once online")
    func transportFailureKeepsFlow() async throws {
        let h = try Self.harness(StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "pkce" {
                return .failure(.notConnectedToInternet)
            }
            return .emptyArray
        })
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "real-code"))

        #expect(!h.identity.isAuthenticated)
        #expect(!h.identity.requiresPasswordUpdate)
        #expect(h.session.pendingFlows.current() != nil, "kept for a retry of the same link")
        #expect(h.identity.authErrorMessage == AuthCopy.transport(.offline, german: KuroLocale.isGerman))
        await h.tearDown()
    }

    @Test("An exchange the server answers with an expired flow keeps the pending flow (a stale or crafted expired code must not void the real link)")
    func expiredCodeKeepsFlow() async throws {
        let h = try Self.harness(StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "pkce" {
                return .json(#"{"error_code":"flow_state_expired","msg":"flow state has expired"}"#, status: 400)
            }
            return .emptyArray
        })
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "stale"))

        #expect(!h.identity.isAuthenticated)
        #expect(!h.identity.requiresPasswordUpdate)
        let kept = try #require(h.session.pendingFlows.current(), "only a successful leg or the flow's own lifetime ends it")
        #expect(kept.kind == .recovery)
        await h.tearDown()
    }

    @Test("An exchange the server answers with otp_expired keeps the pending flow")
    func otpExpiredKeepsFlow() async throws {
        let h = try Self.harness(StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "pkce" {
                return .json(#"{"error_code":"otp_expired","msg":"Email link is invalid or has expired"}"#, status: 403)
            }
            return .emptyArray
        })
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "expired"))

        #expect(!h.identity.isAuthenticated)
        #expect(h.session.pendingFlows.current() != nil)
        await h.tearDown()
    }

    @Test("A stale or crafted code (bad_code_verifier) keeps the pending reset flow, so the real email link still opens")
    func foreignCodeKeepsFlow() async throws {
        let h = try Self.harness(StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "pkce" {
                return .json(#"{"error_code":"bad_code_verifier","msg":"code challenge does not match previously saved code verifier"}"#, status: 400)
            }
            return .emptyArray
        })
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "x"))

        #expect(!h.identity.isAuthenticated)
        #expect(!h.identity.requiresPasswordUpdate)
        let kept = try #require(h.session.pendingFlows.current(), "a failed exchange must not void the real link")
        #expect(kept.kind == .recovery)
        await h.tearDown()
    }

    @Test("Signed in, the account's own reset link is exchanged and opens the set-password screen")
    func signedInOwnRecoveryLink() async throws {
        let h = try Self.harness()
        try await h.signIn()
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "real-code"))

        #expect(h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "pkce" }.count == 1)
        #expect(h.identity.isAuthenticated)
        #expect(h.identity.currentUserId == StubAuth.userA)
        #expect(h.identity.requiresPasswordUpdate)
        #expect(h.session.passwordUpdates.isRequired(for: StubAuth.userA))
        #expect(h.session.pendingFlows.current() == nil)
        await h.tearDown()
    }

    @Test("Signed in, a code link with no flow for this account is refused with 'signed in already', without an exchange")
    func signedInCodeWithoutFlow() async throws {
        let h = try Self.harness()
        try await h.signIn()

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "some-code"))

        #expect(h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "pkce" }.isEmpty)
        #expect(h.identity.isAuthenticated)
        #expect(h.graph.banner.message == AuthCopy.linkMessage(.signedInAlready, german: KuroLocale.isGerman))
        await h.tearDown()
    }

    @Test("Signed out, an unsolicited sign-up confirmation reports the confirmed address and adopts nothing")
    func unsolicitedConfirmation() async throws {
        let h = try Self.harness()
        let before = authRequests(h)

        await h.session.handleAuthCallback(AuthCallbackPayload(code: "confirm-code", type: "signup"))

        #expect(authRequests(h) == before)
        #expect(!h.identity.isAuthenticated)
        #expect(h.identity.authErrorMessage == nil)
        #expect(h.identity.authNoticeMessage == AuthCopy.emailConfirmed(german: KuroLocale.isGerman))
        await h.tearDown()
    }

    @Test("An expired-link redirect shows its message and sends nothing")
    func errorLink() async throws {
        let h = try Self.harness()
        let before = authRequests(h)

        await h.session.handleAuthCallback(AuthCallbackPayload(errorCode: "otp_expired", errorDescription: "expired"))

        #expect(authRequests(h) == before)
        #expect(h.identity.authErrorMessage == AuthCopy.linkMessage(.expired, german: KuroLocale.isGerman))
        await h.tearDown()
    }

    @Test("The requirement survives a relaunch: restoring the account opens on the set-password screen")
    func requirementSurvivesRelaunch() async throws {
        let h = try Self.harness()
        h.session.passwordUpdates.require(for: StubAuth.userA)

        await h.session.applySession(userId: StubAuth.userA, email: "a@example.com")

        #expect(h.identity.isAuthenticated)
        #expect(h.identity.requiresPasswordUpdate)
        await h.tearDown()
    }

    @Test("Saving the new password sends it with the account's bearer, lifts the requirement and confirms")
    func updatePassword() async throws {
        let h = try Self.harness()
        try await h.signIn()
        h.session.passwordUpdates.require(for: StubAuth.userA)
        h.identity.requiresPasswordUpdate = true

        try await h.session.updatePassword("a-new-password")

        let update = try #require(h.requests { StubAuth.isAuth($0, "user") && $0.method == "PUT" }.last)
        #expect(update.jsonObject?["password"] as? String == "a-new-password")
        #expect(update.bearerSubject == StubAuth.userA.lowercased())
        #expect(!h.identity.requiresPasswordUpdate)
        #expect(!h.session.passwordUpdates.isRequired(for: StubAuth.userA))
        #expect(h.graph.banner.message == AuthCopy.passwordUpdated(german: KuroLocale.isGerman))
        await h.tearDown()
    }

    @Test("Sign-out forgets a started flow and the account's requirement")
    func signOutClears() async throws {
        let h = try Self.harness()
        try await h.signIn()
        h.session.pendingFlows.begin(.recovery, email: "a@example.com")
        h.session.passwordUpdates.require(for: StubAuth.userA)

        await h.session.signOut()

        #expect(h.session.pendingFlows.current() == nil)
        #expect(!h.session.passwordUpdates.isRequired(for: StubAuth.userA))
        #expect(!h.identity.requiresPasswordUpdate)
        await h.tearDown()
    }

    @Test("Sign-up without a session (email confirmation on) reports .noSession instead of failing silently")
    func signUpWithoutSession() async throws {
        let h = try Self.harness(StubAuth.signInResponder { request in
            StubAuth.isAuth(request, "signup")
                ? .json(StubAuth.userJSON(StubAuth.userA, email: "a@example.com"))
                : .emptyArray
        })

        let outcome = try await h.session.signUpWithEmail(email: "a@example.com", password: "long-enough")

        #expect(outcome == .noSession)
        #expect(!h.identity.isAuthenticated)
        await h.tearDown()
    }
}

// MARK: - Bootstrap Library reads (api-surface P1)

@MainActor
@Suite("Auth lane: one Library read per bootstrap", .timeLimit(.minutes(1)))
struct BootstrapLibraryReadTests {
    static func foundationResponder() -> StubServer.Responder {
        StubAuth.signInResponder { request in
            request.resource == "feature_flags"
                ? .json("[\(flagRow("series_foundation_v1", rollout: 100))]")
                : .emptyArray
        }
    }

    @Test("With the foundation on and the first read already fenced, bootstrap reads the Library once")
    func singleRead() async throws {
        let backend = FakeLibraryBackend()
        // A fenced row (revision + lifecycle id): an empty Library would pass whether or not the first
        // read carried the fence columns.
        var row = FakeLibraryBackend.entry(.anime, 7)
        row.revision = 1
        row.lifecycleId = UUID()
        backend.setRows([row], for: StubAuth.userA)
        let h = try SessionSDKHarness(responder: Self.foundationResponder(), libraryBackend: backend)

        try await h.signIn()

        #expect(h.graph.flags.seriesFoundationV1Enabled)
        #expect(backend.calls.filter { $0 == .fetchAll(userId: StubAuth.userA) }.count == 1, "\(backend.calls)")
        await h.tearDown()
    }

    @Test("A first read without the fence columns is repeated once, fresh")
    func unfencedReadRepeats() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 7)], for: StubAuth.userA)
        let h = try SessionSDKHarness(responder: Self.foundationResponder(), libraryBackend: backend)

        try await h.signIn()

        #expect(backend.calls.filter { $0 == .fetchAll(userId: StubAuth.userA) }.count == 2, "\(backend.calls)")
        await h.tearDown()
    }
}
