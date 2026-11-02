import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Session funnel (E6c1)
// The E1 account/permission lifecycle (independently approved; R-E1-1..3), moved verbatim from
// `SupabaseService`: launch restore, the SDK auth-event listener and its event mapping, email/Apple
// sign-in and sign-up, the auth-callback guard (`AuthCallbackGuard`, fail closed, re-checked after
// `setSession`), sign-out and deletion ordering, `applySession` / `endSession` (+ failed restore), the
// ONE account-scoped invalidation list, the Library bind/reset before the first suspension point
// (R-E1-3), the reminder/flag/telemetry user-id side effects and the post-auth bootstrap.
// Pass 2 additions (order of the funnel unchanged):
// - F01 authentication attempts: every restore, sign-in, sign-up, Apple sign-in and callback is an
//   attempt with a generation; sign-out and deletion supersede attempts in flight. Only the newest
//   attempt's success or failure is published, cleared, reported or bootstrapped (`authenticate`, the
//   one shared completion); a newer attempt cancels and waits for the older attempt's SDK leg first.
// - F33 credential gate: every SDK call that installs a session runs inside
//   `AccountSessionCoordinator.beginCredentialChange` / `endCredentialChange` (`installCredentials`),
//   so no private request (credential lease) is in flight or admitted while the SDK token changes.
// - F05: reminder cleanups are issued synchronously with the transition they belong to.
// - F71: an SDK `.tokenRefreshed` for another account while one is current fails closed.
// Overnight 2026-11-01 (spec D12, api-surface P1):
// - Email links: a signed-out `kuro://auth/callback` is applied only for the live flow this device
//   started (`PendingAuthFlowStore`, single use, 1 h); PKCE `?code=` links are exchanged
//   (`exchangeCodeForSession`) inside the same credential gate; a recovery link leads to the
//   set-new-password screen (`identity.requiresPasswordUpdate`, persisted per account).
// - Bootstrap reads the Library once: the foundation-fence re-read runs only when the session's
//   first read came back without the fence columns.
// Identity is published to `IdentityStore` (its only holder); SDK auth calls that are pure transport go
// through `AuthService`; the user-list channel belongs to `LibraryRealtime`. The SDK client is the
// app's single one (shared with `AuthService`; never a second one).

@MainActor
@Observable
final class SessionController {
    /// The app's single SDK client (nil only when the configuration is missing).
    @ObservationIgnored private let client: SupabaseClient?
    /// The identity the UI shows; written only here (and by `AuthService` for configuration errors).
    @ObservationIgnored let identity: IdentityStore
    /// The auth transport.
    @ObservationIgnored private let auth: AuthService
    /// The current account context (KuroCore), shared by every account-scoped owner.
    @ObservationIgnored let accountSession: AccountSessionCoordinator
    /// The single authoritative tracking projection: rebound on start/switch, reset first on end.
    @ObservationIgnored private let library: LibraryStore
    /// The Library refresh paths (the funnel starts the session's Library refresh through them).
    @ObservationIgnored private let libraryActions: LibraryActions
    /// The account's user-list realtime channel.
    @ObservationIgnored private let libraryRealtime: LibraryRealtime
    /// Device airing reminders (account rules: removed on end/switch, kept for the restored owner).
    @ObservationIgnored private let reminders: ReminderScheduler
    /// Upcoming airings + countdowns (bootstrap).
    @ObservationIgnored private let releases: ReleasesStore
    /// Collection pages + feed (bootstrap).
    @ObservationIgnored private let collection: CollectionStore
    /// Clubs: the club channel (detached on transitions) and the deleted account's club preferences.
    @ObservationIgnored private let clubs: ClubsStore
    /// Provider registry + the account's streaming services (bootstrap, behind the flag).
    @ObservationIgnored private let availability: ProviderAvailabilityStore
    /// Runtime flags: the account's user id for rollout, refreshed after sign-in.
    @ObservationIgnored private let flags: FeatureFlags
    /// Interaction events: the attributed user id.
    @ObservationIgnored private let interactionTelemetry: InteractionTelemetry
    /// The transient banner (rejected auth callbacks).
    @ObservationIgnored private let banner: BannerCenter
    /// The ONE list of owners holding account-scoped state (`AppComposition.makeAccountScopedStates`);
    /// cancelled and cleared on every transition, in this order.
    @ObservationIgnored let accountScopedStates: [any AccountScopedState]
    @ObservationIgnored private var authStateTask: Task<Void, Never>?
    /// Generation of the newest authentication attempt (F01). Every attempt (restore, email sign-in,
    /// sign-up, Apple, auth callback) and every deliberate session end (sign-out, deletion) starts a
    /// new one; an older attempt's success AND failure are then stale: nothing is published, cleared,
    /// reported or bootstrapped for it.
    @ObservationIgnored private var authAttempt = 0
    /// The SDK leg (the call that installs a session in the SDK) of the newest attempt. A newer attempt
    /// cancels it and waits for it to finish before installing its own session, so a superseded
    /// attempt can never install a session after the newer one.
    @ObservationIgnored private var authAttemptLeg: Task<Void, Never>?
    /// The pending email-link flow slot (D12). Settable so tests can use their own defaults suite.
    @ObservationIgnored var pendingFlows = PendingAuthFlowStore()
    /// The per-account "choose a new password" requirement after a recovery link (D12).
    @ObservationIgnored var passwordUpdates = PasswordUpdateRequirementStore()
    /// True while an accepted recovery link is being applied: any session published meanwhile
    /// (including the SDK's own `.signedIn` event from the exchange) opens on the set-password screen.
    @ObservationIgnored private var recoveryLinkInFlight = false
    /// The attempt of the link whose progress `identity.isOpeningAuthLink` shows.
    @ObservationIgnored private var openingLinkAttempt: Int?

    init(
        client: SupabaseClient?,
        identity: IdentityStore,
        auth: AuthService,
        accountSession: AccountSessionCoordinator,
        library: LibraryStore,
        libraryActions: LibraryActions,
        libraryRealtime: LibraryRealtime,
        reminders: ReminderScheduler,
        releases: ReleasesStore,
        collection: CollectionStore,
        clubs: ClubsStore,
        availability: ProviderAvailabilityStore,
        shell: ShellOwners,
        accountScopedStates: [any AccountScopedState]
    ) {
        self.client = client
        self.identity = identity
        self.auth = auth
        self.accountSession = accountSession
        self.library = library
        self.libraryActions = libraryActions
        self.libraryRealtime = libraryRealtime
        self.reminders = reminders
        self.releases = releases
        self.collection = collection
        self.clubs = clubs
        self.availability = availability
        flags = shell.flags
        interactionTelemetry = shell.interactionTelemetry
        banner = shell.banner
        self.accountScopedStates = accountScopedStates
    }

    private var isGermanLocale: Bool {
        KuroLocale.isGerman
    }

    /// Production launch (`AppComposition`): the root shows its loading screen while the stored
    /// session is restored; without an SDK client nothing is restored (the root shows the
    /// configuration error).
    func startLaunchRestore() {
        guard client != nil else { return }
        identity.isAuthBootstrapping = true
        Task { await restoreSession() }
    }

    // MARK: - Authentication attempts (F01, F33)

    /// Starts a new authentication attempt (or a deliberate session end): every older attempt becomes
    /// stale and its SDK leg is cancelled.
    private func beginAuthAttempt() -> Int {
        authAttempt += 1
        authAttemptLeg?.cancel()
        return authAttempt
    }

    private func isCurrentAttempt(_ attempt: Int) -> Bool {
        attempt == authAttempt
    }

    /// Runs `leg`, the SDK call that installs a session (sign-in, sign-up, Apple, callback
    /// `setSession`), as the SDK leg of `attempt`:
    /// 1. the previous attempt's leg (cancelled by `beginAuthAttempt`) finishes first, so a superseded
    ///    attempt can never install its session after this one;
    /// 2. the credential gate closes and every private request in flight finishes first (F33,
    ///    `AccountSessionCoordinator.beginCredentialChange`): none of them can be dispatched with the
    ///    session installed here, and none starts until the change ends.
    /// Returns the leg's value and the open credential change, which the caller ends right after the
    /// funnel published (or dropped) the outcome. Throws `CancellationError` when `attempt` was
    /// superseded before its leg started; a failed leg ends the change itself.
    private func installCredentials<T: Sendable>(
        attempt: Int,
        _ leg: @escaping @MainActor () async throws -> T
    ) async throws -> (value: T, change: AccountSessionCoordinator.CredentialChange) {
        if let previous = authAttemptLeg { await previous.value }
        guard isCurrentAttempt(attempt) else { throw CancellationError() }
        let change = await accountSession.beginCredentialChange()
        guard isCurrentAttempt(attempt) else {
            accountSession.endCredentialChange(change)
            throw CancellationError()
        }
        let task = Task<T, Error> { @MainActor in try await leg() }
        // The handle a newer attempt cancels and awaits: cancelling it cancels the leg itself.
        authAttemptLeg = Task { @MainActor in
            await withTaskCancellationHandler {
                _ = await task.result
            } onCancel: {
                task.cancel()
            }
        }
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            return (value, change)
        } catch {
            accountSession.endCredentialChange(change)
            throw error
        }
    }

    /// The ONE completion of a sign-in attempt (email sign-in, sign-up, Apple). The SDK leg runs through
    /// `installCredentials`; its outcome is rechecked against the attempt generation before every side
    /// effect:
    /// - superseded (a newer attempt or a deliberate session end started meanwhile): success and failure
    ///   alike end in `CancellationError`; nothing is published, cleared, reported or bootstrapped;
    /// - current failure: the session ends when `endsSessionOnFailure` (email, Apple: as before) and the
    ///   user-facing message is published, then the error is rethrown;
    /// - current success: the session funnel publishes it (`applySession`), the credential change ends,
    ///   then `afterPublish` (Apple's full name), the profile row and the bootstrap, each only while the
    ///   attempt and its account are still current. A sign-up that yields no session ends the session
    ///   and reports `.noSession` (email confirmation is on: the caller tells the user to check mail).
    @discardableResult
    private func authenticate(
        attempt: Int,
        endsSessionOnFailure: Bool,
        sdkLeg: @escaping @MainActor () async throws -> AuthSessionIdentity?,
        afterPublish: @MainActor () async -> Void = {}
    ) async throws -> AuthOutcome {
        let installed: (value: AuthSessionIdentity?, change: AccountSessionCoordinator.CredentialChange)
        do {
            installed = try await installCredentials(attempt: attempt, sdkLeg)
        } catch {
            guard isCurrentAttempt(attempt) else { throw CancellationError() }
            if endsSessionOnFailure { await endSession() }
            guard isCurrentAttempt(attempt) else { throw CancellationError() }
            identity.authErrorMessage = AuthService.userFacingAuthErrorMessage(from: error)
            throw error
        }
        guard isCurrentAttempt(attempt) else {
            accountSession.endCredentialChange(installed.change)
            throw CancellationError()
        }
        guard let session = installed.value else {
            accountSession.endCredentialChange(installed.change)
            await endSession()
            guard isCurrentAttempt(attempt) else { throw CancellationError() }
            return .noSession
        }
        let transition = await applySession(userId: session.userId, email: session.email)
        accountSession.endCredentialChange(installed.change)
        let context = Self.context(of: transition)
        guard isCurrentAttempt(attempt), accountSession.isCurrent(context) else { return .signedIn }
        await afterPublish()
        guard isCurrentAttempt(attempt), accountSession.isCurrent(context) else { return .signedIn }
        await ensureProfileRow(for: context)
        guard isCurrentAttempt(attempt), accountSession.isCurrent(context) else { return .signedIn }
        await bootstrapAfterAuth()
        return .signedIn
    }

    /// What a completed sign-in attempt produced.
    enum AuthOutcome: Sendable, Equatable {
        /// A session was published.
        case signedIn
        /// The SDK holds no session afterwards (sign-up with email confirmation on).
        case noSession
    }

    private static func context(of transition: AccountSessionCoordinator.Transition) -> AccountContext {
        switch transition {
        case .started(let context), .unchanged(let context): return context
        case .switched(_, let context): return context
        }
    }

    /// Profile bootstrap dispatches with the credentials of the account that requested it.
    private func ensureProfileRow(for context: AccountContext) async {
        let auth = self.auth
        try? await accountSession.withCredentialLease(for: context) {
            await auth.ensureProfileRow()
        }
    }

    // MARK: - Authentication
    func restoreSession() async {
        let attempt = beginAuthAttempt()
        defer { identity.isAuthBootstrapping = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--kuro-skip-auth") {
            identity.isAuthenticated = true
            identity.authErrorMessage = nil
            identity.currentUserEmail = "preview@kuro.local"
            identity.currentUserId = nil
            interactionTelemetry.setUserId(nil)
            if let client {
                Task { await flags.refresh(client: client, userId: nil) }
            }
            return
        }
        #endif
        guard let client else {
            identity.isAuthenticated = false
            identity.authErrorMessage = identity.configError
            identity.currentUserId = nil
            identity.currentUserEmail = nil
            interactionTelemetry.setUserId(nil)
            return
        }

        do {
            let installed = try await installCredentials(attempt: attempt) {
                try await client.auth.session
            }
            let session = installed.value
            // A newer attempt (e.g. an auth callback opened during the launch) owns the session now.
            if isCurrentAttempt(attempt) {
                let transition = await applySession(userId: session.user.id.uuidString, email: session.user.email)
                let context = Self.context(of: transition)
                accountSession.endCredentialChange(installed.change)
                guard isCurrentAttempt(attempt), accountSession.isCurrent(context) else { return }
                identity.authErrorMessage = nil
                await ensureProfileRow(for: context)
                guard isCurrentAttempt(attempt), accountSession.isCurrent(context) else { return }
                // Fire bootstrap without blocking — the UI can show immediately
                // with shimmer/skeleton placeholders while data loads in parallel.
                Task { await bootstrapAfterAuth() }
            } else {
                accountSession.endCredentialChange(installed.change)
            }
        } catch {
            if isCurrentAttempt(attempt) {
                if !Task.isCancelled, AuthService.permitsOfflineRestore(error),
                   let stored = client.auth.currentSession {
                    // The saved SDK identity is only a presentation restore; private
                    // requests still need its real SDK session and current lease.
                    let transition = await applySession(userId: stored.user.id.uuidString, email: stored.user.email)
                    guard isCurrentAttempt(attempt), accountSession.isCurrent(Self.context(of: transition)) else { return }
                    identity.authErrorMessage = nil
                    Task { await bootstrapAfterAuth() }
                } else {
                    await endSessionAfterFailedRestore(storedSessionUserId: client.auth.currentSession?.user.id.uuidString)
                }
            }
        }

        // Listen for auth state changes (token refresh failure, server-side revocation, etc.)
        startAuthStateListener()
    }

    private func startAuthStateListener() {
        guard let client else { return }
        authStateTask?.cancel()
        let listenerAttempt = authAttempt
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                await handleAuthEvent(
                    Self.eventKind(event),
                    sessionUserId: session?.user.id.uuidString,
                    email: session?.user.email,
                    storedSessionUserId: client.auth.currentSession?.user.id.uuidString,
                    listenerAttempt: listenerAttempt
                )
            }
        }
    }

    /// SDK auth events reduced to what the session policy needs (keeps the SDK type out of tests).
    enum AuthEventKind: Sendable {
        case initialSession, signedIn, signedOut, tokenRefreshed, other
    }

    /// The listener's reduction of an SDK event (F46: checked against the events the real SDK emits).
    /// `.userUpdated`, `.passwordRecovery`, `.mfaChallengeVerified` and
    /// `.userDeleted` change nothing here.
    nonisolated static func eventKind(_ event: AuthChangeEvent) -> AuthEventKind {
        switch event {
        case .initialSession: return .initialSession
        case .signedIn: return .signedIn
        case .signedOut: return .signedOut
        case .tokenRefreshed: return .tokenRefreshed
        default: return .other
        }
    }

    /// Routes SDK auth events through the session funnel.
    /// `storedSessionUserId` is the user of the session the SDK holds when the event is handled;
    /// the SDK stores a session before emitting `.signedIn` and removes it before `.signedOut`,
    /// so an event that disagrees with the stored session is stale and ignored.
    func handleAuthEvent(
        _ kind: AuthEventKind,
        sessionUserId: String?,
        email: String?,
        storedSessionUserId: String?,
        listenerAttempt: Int? = nil
    ) async {
        switch kind {
        case .initialSession:
            // Reconcile the restore-to-listener gap without replacing a newer deliberate attempt.
            guard listenerAttempt == nil || listenerAttempt == authAttempt,
                  !accountSession.isChangingCredentials else { return }
            guard let sessionUserId else {
                if storedSessionUserId == nil { await endSession() }
                return
            }
            guard let storedSessionUserId,
                  AccountSessionCoordinator.sameUser(sessionUserId, storedSessionUserId) else { return }
            let transition = await applySession(userId: sessionUserId, email: email)
            if case .unchanged = transition { return }
            let context = Self.context(of: transition)
            guard accountSession.isCurrent(context), listenerAttempt == nil || listenerAttempt == authAttempt else { return }
            await ensureProfileRow(for: context)
            guard accountSession.isCurrent(context), listenerAttempt == nil || listenerAttempt == authAttempt else { return }
            await bootstrapAfterAuth()
        case .signedIn:
            guard let sessionUserId, let storedSessionUserId,
                  AccountSessionCoordinator.sameUser(sessionUserId, storedSessionUserId) else { return }
            await applySession(userId: sessionUserId, email: email)
        case .signedOut:
            guard identity.isAuthenticated || accountSession.current != nil else { return }
            if let storedSessionUserId, let current = accountSession.current,
               AccountSessionCoordinator.sameUser(storedSessionUserId, current.userId) {
                return
            }
            await endSession()
        case .tokenRefreshed:
            guard let current = accountSession.current else { return }
            // Same-user refresh keeps the account context (R-E1-1); only the email may change.
            if let sessionUserId, AccountSessionCoordinator.sameUser(sessionUserId, current.userId) {
                identity.currentUserEmail = email
                return
            }
            // F71: the SDK refreshed, and now STORES, another account's session while this account is
            // current: an older account's refresh that completed after this sign-in (supabase-swift
            // stores a refresh result unconditionally). Its token would be attached to this account's
            // requests, so the session fails closed: ended, and the foreign session removed from the SDK.
            guard let storedSessionUserId,
                  !AccountSessionCoordinator.sameUser(storedSessionUserId, current.userId) else { return }
            await endSessionWithForeignCredential()
        case .other:
            break
        }
    }

    /// F71: the SDK holds another account's session while an account is current. Ends the session
    /// (synchronously first, R-E1-3), supersedes any attempt in flight and drops the SDK's stored session
    /// locally, so nothing is ever sent under the current account with the foreign token.
    private func endSessionWithForeignCredential() async {
        _ = beginAuthAttempt()
        let ended = endSessionState()
        try? await client?.auth.signOut(scope: .local)
        await finishSessionEnd(ended)
    }

    /// Lightweight session check on foreground — if the token expired while backgrounded,
    /// catch it early rather than waiting for the next API call to fail.
    func refreshSessionIfNeeded() async {
        guard let client else {
            identity.authErrorMessage = identity.configError
            return
        }
        do {
            _ = try await client.auth.session
        } catch {
            #if DEBUG
            print("⚠️ Session refresh failed on foreground: \(error.localizedDescription)")
            #endif
            // The authStateChanges listener will handle .signedOut if the session is truly gone.
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        let attempt = beginAuthAttempt()
        identity.authErrorMessage = nil
        guard client != nil else {
            identity.authErrorMessage = identity.configError
            throw auth.missingConfiguration()
        }
        let auth = self.auth
        try await authenticate(attempt: attempt, endsSessionOnFailure: true) {
            try await auth.signIn(email: email, password: password)
        }
    }

    /// Sign-up. `.noSession` means the account was created (or the address is taken, which GoTrue
    /// does not reveal while confirmation is on) and a confirmation email is on its way.
    @discardableResult
    func signUpWithEmail(email: String, password: String) async throws -> AuthOutcome {
        let attempt = beginAuthAttempt()
        identity.authErrorMessage = nil
        guard client != nil else {
            identity.authErrorMessage = identity.configError
            throw auth.missingConfiguration()
        }
        // With email confirmation disabled, the session is immediately available; without one the
        // session ends (as before). A failed sign-up publishes only its message (as before).
        let auth = self.auth
        return try await authenticate(attempt: attempt, endsSessionOnFailure: false) {
            try await auth.signUp(email: email, password: password)
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {
        let attempt = beginAuthAttempt()
        identity.authErrorMessage = nil
        guard client != nil else {
            identity.authErrorMessage = identity.configError
            throw auth.missingConfiguration()
        }
        let auth = self.auth
        try await authenticate(attempt: attempt, endsSessionOnFailure: true) {
            try await auth.signInWithApple(idToken: idToken, rawNonce: rawNonce)
        } afterPublish: {
            // Apple only provides full name on first sign-in; persist it.
            if let fullName, !fullName.isEmpty {
                await auth.saveFullName(fullName)
            }
        }
    }

    // MARK: - Email links (D12)

    /// "Forgot password": sends the reset email, then records the pending recovery flow on this
    /// device (only after the request succeeded; a newer request replaces the older record, like the
    /// SDK's single code-verifier slot).
    func requestPasswordReset(email: String) async throws {
        let address = AuthFormRules.trimmedEmail(email)
        try await auth.resetPassword(email: address)
        pendingFlows.begin(.recovery, email: address)
    }

    /// The pre-D12 entry point (implicit token pair); routes through the payload funnel.
    func handleAuthCallback(accessToken: String, refreshToken: String) async {
        await handleAuthCallback(AuthCallbackPayload(accessToken: accessToken, refreshToken: refreshToken))
    }

    /// Applies a `kuro://auth/callback` link when `AuthCallbackGuard` allows it (fail closed):
    /// - signed in: an implicit token pair naming the signed-in user (R-E1-2, unchanged), or a code for
    ///   the live flow this device started for the signed-in account's address;
    /// - signed out: only a link for the live flow this device started. A PKCE code is exchanged, a
    ///   token pair applied, both inside the credential gate (F33) as the newest attempt (F01); the
    ///   account it yields must be the flow's address. The flow is consumed once the SDK leg succeeded
    ///   (single use) or the server answered that the flow expired; any other failure keeps it, so a
    ///   stale or crafted link cannot void the real email link, and a transport failure can be retried.
    /// A recovery link opens the set-new-password screen before the app ever renders.
    func handleAuthCallback(_ payload: AuthCallbackPayload) async {
        // While the launch restore is still running, the SDK's stored session is the signed-in account.
        let bootstrapSession = identity.isAuthBootstrapping ? client?.auth.currentSession : nil
        let signedInUserId = accountSession.current?.userId ?? bootstrapSession?.user.id.uuidString
        let signedInEmail = accountSession.current != nil ? identity.currentUserEmail : bootstrapSession?.user.email
        let pending = pendingFlows.current()
        let flowKind: PendingAuthFlowKind?
        switch AuthCallbackGuard.decision(
            payload: payload,
            currentUserId: signedInUserId,
            currentUserEmail: signedInEmail,
            pending: pending
        ) {
        case .linkError:
            let message = AuthCopy.message(forCode: payload.errorCode, german: isGermanLocale)
                ?? AuthCopy.linkMessage(.expired, german: isGermanLocale)
            reportAuthLinkFailure(message, signedIn: signedInUserId != nil)
            return
        case .rejectDifferentUser:
            reportRejectedAuthCallback()
            return
        case .rejectCodeWhileSignedIn:
            reportAuthLinkFailure(AuthCopy.linkMessage(.signedInAlready, german: isGermanLocale), signedIn: true)
            return
        case .rejectNoPendingFlow:
            reportAuthLinkFailure(AuthCopy.linkMessage(.notRequestedHere, german: isGermanLocale), signedIn: false)
            return
        case .emailConfirmed:
            identity.authErrorMessage = nil
            identity.authNoticeMessage = AuthCopy.emailConfirmed(german: isGermanLocale)
            return
        case .proceed:
            flowKind = nil
        case .applyPendingTokens(let kind), .exchangeCode(let kind):
            flowKind = kind
        }
        guard let client else {
            identity.authErrorMessage = identity.configError
            return
        }
        let attempt = beginAuthAttempt()
        identity.isOpeningAuthLink = true
        openingLinkAttempt = attempt
        defer {
            // A newer link owns the progress state; any other newer attempt does not.
            if openingLinkAttempt == attempt {
                identity.isOpeningAuthLink = false
                openingLinkAttempt = nil
            }
        }
        if flowKind == .recovery {
            recoveryLinkInFlight = true
            identity.requiresPasswordUpdate = true
        }
        let installed: (value: AuthSessionIdentity, change: AccountSessionCoordinator.CredentialChange)
        do {
            installed = try await installCredentials(attempt: attempt) {
                if let code = payload.code {
                    let session = try await client.auth.exchangeCodeForSession(authCode: code)
                    return AuthSessionIdentity(userId: session.user.id.uuidString, email: session.user.email)
                }
                guard let accessToken = payload.accessToken, let refreshToken = payload.refreshToken else {
                    throw URLError(.badURL)
                }
                try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
                let session = try await client.auth.session
                return AuthSessionIdentity(userId: session.user.id.uuidString, email: session.user.email)
            }
        } catch {
            settleRecoveryLink()
            // A failed leg never uses the flow up (SEC-2): every error describes the code in the link,
            // not this device's flow. A stale or crafted `?code=` (even an expired one, which GoTrue
            // answers with `flow_state_expired` before it checks the verifier), another device's code
            // and any transport failure keep it, so the real email link still works afterwards. The
            // SDK keeps its code verifier until a successful exchange; `PendingAuthFlow.lifetime`
            // bounds the local flow, and only a successful leg (below) consumes it.
            // A superseded attempt reports nothing (F01).
            guard isCurrentAttempt(attempt) else { return }
            reportAuthLinkFailure(Self.linkFailureMessage(for: error, german: isGermanLocale),
                                  signedIn: signedInUserId != nil)
            #if DEBUG
            print("handleAuthCallback failed: \(error.localizedDescription)")
            #endif
            return
        }
        // The SDK leg succeeded: the flow is used up (also when the account turns out foreign below).
        if flowKind != nil { pendingFlows.consume() }
        guard isCurrentAttempt(attempt) else {
            accountSession.endCredentialChange(installed.change)
            settleRecoveryLink()
            return
        }
        let session = installed.value
        // Defense in depth (the guard should make these unreachable): while signed in, never adopt
        // another user's session; signed out, never adopt an account other than the flow's address.
        let foreignWhileSignedIn = signedInUserId.map { !AccountSessionCoordinator.sameUser(session.userId, $0) } ?? false
        let foreignToFlow = flowKind != nil && pending?.matches(email: session.email) != true
        if foreignWhileSignedIn || foreignToFlow {
            // The SDK's own `.signedIn` event may already have published (and persisted the
            // set-password requirement for) the foreign account during the exchange.
            if flowKind == .recovery { passwordUpdates.clear(for: session.userId) }
            settleRecoveryLink()
            let ended = endSessionState()
            accountSession.endCredentialChange(installed.change)
            try? await client.auth.signOut(scope: .local)
            await finishSessionEnd(ended)
            if foreignWhileSignedIn {
                reportRejectedAuthCallback()
            } else {
                reportAuthLinkFailure(AuthCopy.linkMessage(.notRequestedHere, german: isGermanLocale), signedIn: false)
            }
            return
        }
        if flowKind == .recovery {
            // Persisted before the session is published, so a relaunch also lands on the set-password
            // screen (`applySession` also persists it when the SDK's `.signedIn` event publishes first).
            passwordUpdates.require(for: session.userId)
        }
        let transition = await applySession(userId: session.userId, email: session.email)
        recoveryLinkInFlight = false
        accountSession.endCredentialChange(installed.change)
        let context = Self.context(of: transition)
        guard isCurrentAttempt(attempt), accountSession.isCurrent(context) else { return }
        identity.authErrorMessage = nil
        await ensureProfileRow(for: context)
        guard isCurrentAttempt(attempt), accountSession.isCurrent(context) else { return }
        await bootstrapAfterAuth()
    }

    /// Ends an accepted recovery link that did not publish a session: the in-memory requirement falls
    /// back to the current account's persisted one (normally none).
    private func settleRecoveryLink() {
        guard recoveryLinkInFlight else { return }
        recoveryLinkInFlight = false
        identity.requiresPasswordUpdate = accountSession.current.map { passwordUpdates.isRequired(for: $0.userId) } ?? false
    }

    /// The message for a link whose exchange or verification failed.
    nonisolated static func linkFailureMessage(for error: Error, german: Bool) -> String {
        if let code = AuthService.authErrorCode(of: error), let message = AuthCopy.message(forCode: code, german: german) {
            return message
        }
        if AuthService.permitsOfflineRestore(error) {
            return AuthService.userFacingAuthErrorMessage(from: error, german: german)
        }
        return AuthCopy.linkMessage(.failed, german: german)
    }

    /// A link that was not applied: the auth screen shows `authErrorMessage`; signed-in screens don't
    /// render it, so the transient banner ContentView shows carries it too (signed in only).
    private func reportAuthLinkFailure(_ message: String, signedIn: Bool) {
        identity.authErrorMessage = message
        if signedIn { banner.show(message, duration: 4) }
    }

    /// Rejected `kuro://auth/callback`: signed-in screens don't render `authErrorMessage`,
    /// so the same EN/DE message also goes to the transient banner ContentView shows.
    private func reportRejectedAuthCallback() {
        reportAuthLinkFailure(AuthCopy.linkMessage(.otherAccount, german: isGermanLocale), signedIn: true)
    }

    // MARK: - Set new password (after a recovery link)

    /// Saves the new password for the signed-in account and lifts the set-password requirement.
    /// Throws the SDK error (mapped by `AuthService.userFacingAuthErrorMessage`).
    func updatePassword(_ password: String) async throws {
        guard client != nil else {
            identity.authErrorMessage = identity.configError
            throw auth.missingConfiguration()
        }
        guard let context = accountSession.current else { throw CancellationError() }
        let auth = self.auth
        try await accountSession.withCredentialLease(for: context) {
            try await auth.updatePassword(password)
        }
        guard accountSession.isCurrent(context) else { return }
        passwordUpdates.clear(for: context.userId)
        identity.requiresPasswordUpdate = false
        banner.show(AuthCopy.passwordUpdated(german: isGermanLocale), duration: 3)
    }

    /// GDPR-compliant account deletion: the `delete-account` Edge Function (`AuthService`), then the
    /// session end.
    func deleteAccount(appleAuthorizationCode: String? = nil, expectedAccount: AccountContext? = nil) async throws {
        if let expectedAccount, !accountSession.isCurrent(expectedAccount) { throw CancellationError() }
        try Task.checkCancellation()
        guard let client else {
            identity.authErrorMessage = identity.configError
            throw auth.missingConfiguration()
        }
        guard let context = accountSession.current else { throw CancellationError() }
        // Any non-2xx response throws FunctionsError.httpError here (a 2xx without `success: true`
        // throws `AuthFailure.deletionFailed`), so a failed deletion leaves the session and local
        // state untouched (the user can retry).
        let auth = self.auth
        var deletionConfirmed = false
        do {
            try await accountSession.withCredentialLease(for: context) {
                try await auth.requestAccountDeletion(appleAuthorizationCode: appleAuthorizationCode)
                deletionConfirmed = true
            }
        } catch {
            // A revoked lease deliberately drops its result; observed remote success
            // still requires exact-account cleanup. A lost response is never success.
            guard deletionConfirmed else { throw error }
        }
        // Invalidate and cancel the deleted account before serialized device cleanup.
        passwordUpdates.clear(for: context.userId)
        pendingFlows.clear()
        OnboardingCompletion.remove(userId: context.userId)
        clubs.removeAccountScopedPrefs(userId: context.userId)
        flags.removeHomeCohort(for: context.userId)
        if accountSession.isCurrent(context) {
            let attempt = beginAuthAttempt()
            let ended = endSessionState()
            do {
                let installed = try await installCredentials(attempt: attempt) {
                    try await client.auth.signOut(scope: .local)
                }
                accountSession.endCredentialChange(installed.change)
            } catch {
                // A newer attempt owns credentials; local state is already ended.
            }
            await finishSessionEnd(ended)
        }
        // Hooks receive the deleted identity, never whichever account is visible now.
        // Async journal actors serialize the purge behind already admitted local writes.
        var cleanupError: Error?
        for owner in accountScopedStates {
            do { try await owner.removeDeletedAccountData(userId: context.userId) }
            catch { cleanupError = error }
        }
        if let cleanupError { throw cleanupError }
    }

    func signOut(expectedAccount: AccountContext? = nil) async {
        if let expectedAccount, !accountSession.isCurrent(expectedAccount) { return }
        guard !Task.isCancelled else { return }
        guard let client else {
            identity.authErrorMessage = identity.configError
            return
        }
        // R-E1-3: the account context is invalidated and private state cleared before the first
        // suspension point; the SDK sign-out follows at once, before the (slow) channel teardown. A
        // sign-in attempt still in flight is superseded (F01): its late success never signs in again.
        // A started email-link flow and the account's set-password requirement end with the session.
        if let userId = accountSession.current?.userId { passwordUpdates.clear(for: userId) }
        pendingFlows.clear()
        let attempt = beginAuthAttempt()
        let ended = endSessionState()
        do {
            let installed = try await installCredentials(attempt: attempt) {
                try await client.auth.signOut()
            }
            accountSession.endCredentialChange(installed.change)
        } catch {
            #if DEBUG
            print("❌ signOut error: \(error)")
            #endif
            // Error logged in debug only
        }
        await finishSessionEnd(ended)
    }

    // MARK: - Session funnel
    // Every session entry point goes through `applySession` (restore, email sign-in/sign-up,
    // Apple, auth callback, SDK `.signedIn`) or `endSession` (sign-out, deletion, SDK
    // `.signedOut`, failed sign-in/restore). Same user: identity refresh only (R-E1-1).
    // New or different user, or sign-out: previous work is cancelled and private state cleared
    // synchronously, before the first suspension point (R-E1-3).

    /// Publishes the session the SDK reports for `userId`. Same user: identity refresh only.
    /// New or different user: rebinds the Library store, cancels the previous account's work, clears
    /// private state and detaches its channels, publishes the new identity and starts the Library
    /// refresh, then removes the previous account's channels.
    @discardableResult
    func applySession(userId: String, email: String?) async -> AccountSessionCoordinator.Transition {
        let transition = accountSession.begin(userId: userId)
        let context: AccountContext
        switch transition {
        case .unchanged:
            if recoveryLinkInFlight { passwordUpdates.require(for: userId) }
            identity.requiresPasswordUpdate = identity.requiresPasswordUpdate
                || recoveryLinkInFlight || passwordUpdates.isRequired(for: userId)
            identity.isAuthenticated = true
            identity.currentUserEmail = email
            return transition
        case .started(let started):
            context = started
        case .switched(_, let next):
            context = next
        }
        // R-E1-3: the Library projection is rebound before the first suspension point.
        library.bind(context)
        cancelAccountWork()
        clearPrivateState()
        let channels = detachAccountChannels()
        // Read before the identity is published, so the root never renders the app first (D12). A
        // recovery link in flight persists the requirement here too: the SDK's `.signedIn` event can
        // publish (and Keychain-store) the recovery session before the exchange returns, and a kill in
        // that window must still relaunch onto the set-password screen.
        if recoveryLinkInFlight { passwordUpdates.require(for: userId) }
        identity.requiresPasswordUpdate = recoveryLinkInFlight || passwordUpdates.isRequired(for: userId)
        identity.isAuthenticated = true
        identity.currentUserEmail = email
        identity.currentUserId = userId
        interactionTelemetry.setUserId(userId)
        flags.setUserId(userId)
        libraryActions.startLibraryRefresh(for: context)
        // Reminders of another account go; a restored (`.started`) account keeps its own. The removal is
        // issued now, synchronously with the transition (F05): it runs before anything the new account
        // schedules, so it can never remove the new account's reminders.
        let reminderCleanup: Task<Void, Never>?
        if case .switched = transition {
            reminderCleanup = reminders.enqueueAiringRemindersRemoval()
        } else if reminders.airingRemindersBelongToAnotherAccount(than: userId) {
            reminderCleanup = reminders.enqueueAiringRemindersRemoval()
        } else {
            reminderCleanup = nil
        }
        await removeDetachedChannels(channels)
        await reminderCleanup?.value
        return transition
    }

    /// Ends the session (SDK `.signedOut`, failed sign-in/restore; sign-out and deletion use the two
    /// halves directly so the SDK call sits between them).
    func endSession() async {
        let ended = endSessionState()
        await finishSessionEnd(ended)
    }

    /// What the synchronous part of a session end hands to its asynchronous tail.
    struct SessionEnd {
        /// Whether an account session actually ended.
        let endedAccount: Bool
        /// The ended account's realtime channels, already detached from their owners.
        let channels: DetachedAccountChannels
        /// The removal of the ended account's reminders, issued with the transition (nil when no
        /// account ended, e.g. a failed sign-in or an offline restore: the user's own stay).
        let reminderCleanup: Task<Void, Never>?
    }

    /// Synchronous part of a session end (R-E1-3: runs before any suspension): drops the Library
    /// projection first, invalidates the account context, cancels its work, clears private state,
    /// detaches its realtime channels and clears the published identity.
    @discardableResult
    func endSessionState() -> SessionEnd {
        library.reset()
        let endedAccount = accountSession.current != nil
        accountSession.end()
        cancelAccountWork()
        clearPrivateState()
        let channels = detachAccountChannels()
        identity.isAuthenticated = false
        identity.requiresPasswordUpdate = false
        recoveryLinkInFlight = false
        identity.currentUserEmail = nil
        identity.currentUserId = nil
        identity.authErrorMessage = nil
        interactionTelemetry.setUserId(nil)
        flags.setUserId(nil)
        // The ended account's reminders: issued now, ordered before anything a later account schedules (F05).
        let reminderCleanup = endedAccount ? reminders.enqueueAiringRemindersRemoval() : nil
        return SessionEnd(endedAccount: endedAccount, channels: channels, reminderCleanup: reminderCleanup)
    }

    /// Asynchronous tail of a session end: removal of the channels detached by `endSessionState`,
    /// then the completion of the ended account's reminder removal (issued by `endSessionState`; a
    /// failed offline restore issues none and keeps the user's own). The tail can run after a new
    /// sign-in (e.g. while the SDK sign-out was in flight): it never touches the new account's
    /// channels (only the detached ones are removed) or reminders (the removal was ordered before
    /// anything the new account scheduled).
    func finishSessionEnd(_ ended: SessionEnd) async {
        await removeDetachedChannels(ended.channels)
        await ended.reminderCleanup?.value
    }

    /// Failed launch restore. No account session was active, so `endSession` keeps pending
    /// reminders: an offline failure leaves the SDK's stored session (their owner) in place. When the
    /// SDK holds no session any more (e.g. it removed a revoked one), no account remains on this
    /// device to own them, so the `airing-*` requests and the owner marker are removed.
    func endSessionAfterFailedRestore(storedSessionUserId: String?) async {
        await endSession()
        if storedSessionUserId == nil {
            await reminders.removePendingAiringNotifications()
        }
    }

    /// Cancels every account-owned load and task; obsolete completions are also rejected by
    /// their captured context (and Collection pages by their bumped generations).
    private func cancelAccountWork() {
        // Account-scoped work of the owners (Library refreshes, Collection page fetches + the sink's
        // page refresh, Discover bundle, upcoming airings + countdown timer, club bundle loads,
        // concierge parse/recommend loads, the deck signal delivery, ...).
        for owner in accountScopedStates { owner.cancelAccountWork() }
    }

    /// The single cleared-by-name list of account-private state.
    /// The Library projection is not listed here: `applySession` rebinds and `endSessionState` resets
    /// the store (the single authority), which drops it with its pending mutations' bookkeeping.
    private func clearPrivateState() {
        // Account-scoped state held by the owners: the Library write error and toggle guard
        // (`libraryActions`), the Collection pages, cursors, flags, filter and
        // error (`collection`), personalised Discover (`discovery`), Releases
        // (upcoming airings, countdowns, throttle/backoff: `releases`), friend counts (`social`),
        // the account's provider preferences and club-shared providers (`availability`), club
        // bundles, my clubs, the unseen badge and legacy unscoped club prefs (`clubs`), the concierge
        // parse cache (`imports`), the recommendation cache (`concierge`), the deck signal outbox
        // (`taste`) and the account's queued interaction events (`interactionTelemetry`). Public catalog data
        // (detail, entity and ladder caches in `catalog`) is not account-scoped and survives
        // (contracts §2).
        for owner in accountScopedStates { owner.clearPrivateState() }
    }

    /// The private user and club realtime channels of an account, detached from their owners.
    struct DetachedAccountChannels {
        let user: (any UserListRealtimeChannel)?
        let club: (any ClubRealtimeChannel)?
    }

    /// Synchronous part of a transition: cancels the listeners and detaches the user and club
    /// channels, so a later teardown can only remove these channels, never a newer account's.
    private func detachAccountChannels() -> DetachedAccountChannels {
        // The user channel's owner (`libraryRealtime`) cancels its pending refresh and stops its
        // listeners.
        let user = libraryRealtime.detach()

        // The club channel's owner (`clubs.realtime`) stops its listeners and pending re-read.
        let club = clubs.detachRealtime()
        return DetachedAccountChannels(user: user, club: club)
    }

    /// Asynchronous part of a transition: removes channels detached by `detachAccountChannels`.
    private func removeDetachedChannels(_ channels: DetachedAccountChannels) async {
        if let user = channels.user {
            await user.unsubscribe()
        }
        if let club = channels.club {
            await club.unsubscribe()
        }
    }

    /// The Library projection is loaded and every row carries the foundation fence (revision + lifecycle).
    private var libraryHoldsFencedRows: Bool {
        library.loadState == .loaded
            && library.allEntries.allSatisfy { $0.revision != nil && $0.lifecycleId != nil }
    }

    private func bootstrapAfterAuth() async {
        let context = accountSession.current
        if let context, let home = libraryActions.home {
            await home.restorePersonalSnapshot(for: context)
            guard accountSession.isCurrent(context) else { return }
            if home.hasCachedFoundationMetadata && flags.seriesFoundationV1Enabled {
                flags.completeFoundationBootstrap(userId: context.userId)
            }
        }
        // Fetch all independent user data in parallel to cut startup latency.
        // Each fetch updates @Observable properties, so the UI fills progressively.
        // The Library projection is refreshed by the session funnel (`applySession`).
        async let feed: () = collection.fetchCollectionFeed()
        async let upcoming: () = releases.fetchUpcomingForUser(days: 7)
        _ = await (feed, upcoming)

        // A bootstrap that outlives its account must not re-arm timers or subscriptions.
        guard let context, accountSession.isCurrent(context) else { return }
        releases.startCountdownUpdates(for: context)
        libraryRealtime.subscribe()
        clubs.startSharedDisclosureUpdates()

        // Foundation metadata must arrive before Home can issue revision-fenced writes.
        if let client {
            await flags.refresh(client: client, userId: context.userId, accountSession: accountSession)
            guard accountSession.isCurrent(context) else { return }
            if flags.seriesFoundationV1Enabled {
                // One Library read per bootstrap (api-surface P1): the session's first read (started by
                // `applySession`) is joined while in flight and reused when it already carries the fence
                // columns; only a read that ran before the fence was on (or failed) is repeated fresh.
                if library.loadState == .loading {
                    await libraryActions.startLibraryRefresh(for: context).value
                    guard accountSession.isCurrent(context) else { return }
                }
                if !libraryHoldsFencedRows {
                    await libraryActions.startLibraryRefresh(for: context, fresh: true).value
                    guard accountSession.isCurrent(context) else { return }
                }
                guard libraryHoldsFencedRows else { return }
                flags.completeFoundationBootstrap(userId: context.userId)
            }
        }

        // Streaming availability: load registry + user services (non-blocking)
        if flags.isStreamingAvailabilityV1Enabled {
            Task {
                await availability.fetchStreamingServiceRegistry()
                await availability.fetchUserStreamingServices()
            }
        }
    }
}
#endif
