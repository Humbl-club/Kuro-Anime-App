//
//  IdentityCompositionTests.swift
//  KuroTests
//
//  E6c1: the user-list realtime owner (`LibraryRealtime`) driven through its channel seam, and the
//  single construction path of the object graph (`AppComposition.makeGraph`, used by the production
//  composition and by `AppComposition.testingGraph`). The session funnel's own behavior (restore,
//  sign-in, Apple, callback, SDK events, sign-out, deletion) is covered by the E1 lifecycle tables in
//  AccountLifecycleTests, now driving `SessionController` / `IdentityStore`.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Observation
import Supabase
@testable import Kuro

// MARK: - User-list channel seam

/// The user-list channel seam in tests: records subscribe/stop/unsubscribe and delivers change events
/// on demand. `deliver()` works even after `stopListening()`: it stands for an event that was already
/// on its way to the main actor when the channel was stopped.
@MainActor
final class FakeUserListChannels: UserListChannelFactory {
    final class Channel: UserListRealtimeChannel {
        let userId: String
        let listUserId: String
        /// "<userId>#<n>": the n-th channel made (1-based), for the event log.
        let name: String
        private let onEvent: @MainActor () -> Void
        private let log: @MainActor (String) -> Void
        private(set) var isSubscribed = false
        private(set) var isListening = true
        /// How often `unsubscribe()` was called (a channel is removed once).
        private(set) var unsubscribeCount = 0
        /// When set, `unsubscribe()` finishes only once the gate opens (a slow server leave).
        var teardownGate: StubGate?
        /// Called when `unsubscribe()` starts, before a held teardown waits (ordering assertions).
        var onTeardownStart: (@MainActor () -> Void)?

        init(userId: String, listUserId: String, name: String, onEvent: @escaping @MainActor () -> Void,
             log: @escaping @MainActor (String) -> Void) {
            self.userId = userId
            self.listUserId = listUserId
            self.name = name
            self.onEvent = onEvent
            self.log = log
        }

        func subscribe() async { isSubscribed = true }
        func stopListening() { isListening = false }
        func unsubscribe() async {
            unsubscribeCount += 1
            onTeardownStart?()
            if let gate = teardownGate {
                await withCheckedContinuation { continuation in gate.whenOpen { continuation.resume() } }
            }
            log("removed \(name)")
        }

        /// One change event on a list table.
        func deliver() { onEvent() }

        /// Listening and never removed (an open channel).
        var isOpen: Bool { isListening && unsubscribeCount == 0 }
    }

    private(set) var made: [Channel] = []
    private(set) var connects = 0
    /// "made <name>" / "removed <name>" in the order they happened.
    private(set) var log: [String] = []

    func connect() async { connects += 1 }

    func makeChannel(
        userId: String,
        listUserId: String,
        onEvent: @escaping @MainActor () -> Void
    ) -> (any UserListRealtimeChannel)? {
        let name = "\(userId)#\(made.count + 1)"
        let channel = Channel(userId: userId, listUserId: listUserId, name: name, onEvent: onEvent,
                              log: { [weak self] in self?.log.append($0) })
        made.append(channel)
        log.append("made \(name)")
        return channel
    }
}

/// A testing graph with the user-list channel fake, no refresh debounce and a fake Library backend.
@MainActor
struct RealtimeHarness {
    let graph: AppGraph
    let channels: FakeUserListChannels
    let backend: FakeLibraryBackend
    let defaults: UserDefaults
    private let suiteName: String

    var realtime: LibraryRealtime { graph.libraryRealtime }
    var session: SessionController { graph.session }

    init() throws {
        suiteName = "kuro.tests.library-realtime.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        channels = FakeUserListChannels()
        backend = FakeLibraryBackend()
        graph = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: FakeNotificationCenter(),
            libraryBackend: backend,
            userListChannels: channels,
            libraryRealtimeDebounce: .zero
        )
    }

    /// `userId` signs in (the funnel's Library refresh finished) and its list channel is open.
    func signInAndSubscribe(_ userId: String) async {
        await session.applySession(userId: userId, email: "\(userId)@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
        await realtime.startIfNeeded()
    }

    var listFetches: [String] {
        backend.calls.compactMap { if case .fetchAll(let userId) = $0 { return userId } else { return nil } }
    }

    func tearDown() async {
        await session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - LibraryRealtime

@MainActor
@Suite("Library realtime: the account's list channel", .timeLimit(.minutes(1)))
struct LibraryRealtimeTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    enum Transition: String, CaseIterable, Sendable { case signOut, switchToB }

    @Test("An event of the ended account's channel (already on its way) schedules nothing after a sign-out or switch; the current account's event re-reads its lists",
          arguments: Transition.allCases)
    func lateEventOfEndedAccountSchedulesNothing(transition: Transition) async throws {
        let harness = try RealtimeHarness()
        await harness.signInAndSubscribe(Self.userA)
        let channelA = try #require(harness.channels.made.first)
        // F16: the list channel's filter carries the canonical lower-case TEXT user_id (UserIdText).
        #expect(channelA.isSubscribed && channelA.listUserId == Self.userA.lowercased())

        // Control: a current event re-reads A's lists (fresh Library read).
        channelA.deliver()
        let refresh = try #require(harness.realtime.debounceTask)
        await refresh.value
        await harness.graph.libraryActions.libraryRefreshTask?.value
        #expect(harness.listFetches == [Self.userA, Self.userA])

        switch transition {
        case .signOut: await harness.session.endSession()
        case .switchToB: await harness.session.applySession(userId: Self.userB, email: "b@example.com")
        }
        #expect(!channelA.isListening, "the funnel stops A's listeners synchronously")
        #expect(channelA.unsubscribeCount == 1, "the funnel's tail removed A's channel")

        channelA.deliver()
        #expect(harness.realtime.debounceTask == nil, "A's late event scheduled a refresh")
        await harness.graph.libraryActions.libraryRefreshTask?.value
        let expected = transition == .switchToB ? [Self.userA, Self.userA, Self.userB] : [Self.userA, Self.userA]
        #expect(harness.listFetches == expected)
        await harness.tearDown()
    }

    @Test("Old session's teardown never stops a new account's channel: A's tail runs after B subscribed and removes only A's")
    func oldTeardownLeavesTheNewAccountsChannel() async throws {
        let harness = try RealtimeHarness()
        await harness.signInAndSubscribe(Self.userA)
        let channelA = try #require(harness.channels.made.first)

        // Sign-out: the synchronous half detaches A's channel; the tail has not run yet.
        let ended = harness.session.endSessionState()
        #expect(harness.realtime.subscribedUserId == nil)
        await harness.signInAndSubscribe(Self.userB)
        let channelB = try #require(harness.channels.made.last)
        #expect(channelB.userId == Self.userB && channelB.isSubscribed)

        // The old session's tail runs late.
        await harness.session.finishSessionEnd(ended)
        #expect(channelA.unsubscribeCount == 1)
        #expect(channelB.isOpen, "A's teardown stopped B's channel")
        #expect(harness.realtime.subscribedUserId == Self.userB)
        await harness.tearDown()
    }

    @Test("Same user signs in again before the old teardown ran: the new channel is made only after the old one of the same topic is removed, and the late tail never touches it")
    func remountWaitsForThePendingTeardown() async throws {
        let harness = try RealtimeHarness()
        await harness.signInAndSubscribe(Self.userA)
        let first = try #require(harness.channels.made.first)
        let slowRemoval = StubGate()
        first.teardownGate = slowRemoval

        let ended = harness.session.endSessionState()
        await harness.session.applySession(userId: Self.userA, email: "a@example.com")
        // Bootstrap remounts the channel (same topic `kuro.user.<A>`: the SDK would hand back the
        // still-registered channel).
        let remount = Task.immediate { @MainActor in await harness.realtime.startIfNeeded() }
        #expect(harness.channels.made.count == 1, "a channel was made while the old one of the same topic was still registered")

        slowRemoval.open()
        await remount.value
        #expect(harness.channels.log == ["made \(Self.userA)#1", "removed \(Self.userA)#1", "made \(Self.userA)#2"])
        // The funnel's tail runs late: it joins the finished removal and leaves the new channel alone.
        await harness.session.finishSessionEnd(ended)
        let second = try #require(harness.channels.made.last)
        #expect(second.isOpen && second.isSubscribed)
        #expect(first.unsubscribeCount == 1)
        #expect(harness.realtime.subscribedUserId == Self.userA)
        await harness.tearDown()
    }
}

// MARK: - MAL credentials: a test graph never touches the device Keychain

@Suite("MAL credentials: per-graph store")
struct MALCredentialStoreTests {
    @Test("The in-memory store keeps one record per account (case-insensitive) and deleting a missing record is not an error")
    func inMemoryStoreRoundTrip() throws {
        let store = InMemoryMALCredentialStore()
        let account = "4F3C0B6E-0000-4000-8000-000000000001"
        #expect(try store.read(account: account) == nil)
        try store.save(Data("a".utf8), account: account)
        #expect(try store.read(account: account.lowercased()) == Data("a".utf8))
        #expect(try InMemoryMALCredentialStore().read(account: account) == nil, "stores never share records")
        try store.delete(account: account)
        #expect(try store.read(account: account) == nil)
        try store.delete(account: account)
    }
}

// MARK: - Composition: the single construction path

@MainActor
@Suite("Composition: one construction path and one account-scoped list")
struct CompositionGraphTests {
    enum Graph: String, CaseIterable, Sendable { case production, testing }

    static func graph(_ kind: Graph, defaults: UserDefaults) -> AppGraph {
        switch kind {
        case .production:
            return AppComposition.shared.graph
        case .testing:
            return AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        }
    }

    /// The account-scoped owners of `graph`, in the order the funnel must cancel and clear them: the
    /// Library actions first, the interaction telemetry last (its queue is dropped before the funnel
    /// sets the next user id).
    static func expectedAccountScopedStates(_ g: AppGraph) -> [ObjectIdentifier] {
        let owners: [any AccountScopedState] = [
            g.libraryActions, g.home, g.collection, g.discovery, g.releases, g.social, g.availability,
            g.clubs, g.imports, g.concierge, g.taste, g.interactionTelemetry,
        ]
        return owners.map { ObjectIdentifier($0) }
    }

    @Test("The session funnel clears exactly the graph's account-scoped owners, Library actions first and interaction telemetry last",
          arguments: Graph.allCases)
    func accountScopedListMembership(kind: Graph) throws {
        let store = try TestDefaults()
        let g = Self.graph(kind, defaults: store.defaults)
        #expect(g.session.accountScopedStates.map { ObjectIdentifier($0) } == Self.expectedAccountScopedStates(g))
        store.tearDown()
    }

    @Test("Production and KuroTests graphs come from the same builder: every bridge points at its own graph's owners",
          arguments: Graph.allCases)
    func singleConstructionPath(kind: Graph) throws {
        let store = try TestDefaults()
        let g = Self.graph(kind, defaults: store.defaults)
        #expect(g.librarySinks.releases.store === g.releases)
        #expect(g.librarySinks.collection.store === g.collection)
        #expect(g.librarySinks.concierge.imports === g.imports)
        #expect(g.librarySinks.clubs.store === g.clubs)
        #expect(g.libraryHook.actions === g.libraryActions)
        #expect(g.session.identity === g.identity)
        #expect(g.session.accountSession === g.accountSession)
        #expect(g.memoryPressure.owners.map { ObjectIdentifier($0) }
                == [ObjectIdentifier(g.catalog), ObjectIdentifier(g.discovery), ObjectIdentifier(g.imports), ObjectIdentifier(g.concierge)])
        if kind == .testing {
            #expect(!g.identity.isAuthBootstrapping, "a testing graph never starts a launch restore")
            #expect(g.flags !== AppComposition.shared.flags, "a testing graph never shares the app's flags")
        }
        store.tearDown()
    }
}

// MARK: - Session funnel through the real SDK auth client

/// GoTrue / Functions answers for a real supabase-swift client (StubPostgREST: in-process, no network).
enum StubAuth {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    /// An access token whose `sub` is `userId` (lower-case, as GoTrue issues it), valid for an hour.
    static func accessToken(_ userId: String) -> String {
        let exp = Int(Date().timeIntervalSince1970) + 3_600
        return AuthCallbackGuardTests.jwt(#"{"sub":"\#(userId.lowercased())","exp":\#(exp),"role":"authenticated"}"#)
    }

    static func userJSON(_ userId: String, email: String) -> String {
        #"{"id":"\#(userId.lowercased())","aud":"authenticated","role":"authenticated","email":"\#(email)","app_metadata":{"provider":"email"},"user_metadata":{},"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}"#
    }

    /// The token endpoint's answer: a session for `userId`.
    static func sessionJSON(_ userId: String, email: String) -> String {
        let expiresAt = Int(Date().timeIntervalSince1970) + 3_600
        return #"{"access_token":"\#(accessToken(userId))","token_type":"bearer","expires_in":3600,"expires_at":\#(expiresAt),"refresh_token":"refresh-\#(userId.lowercased())","user":\#(userJSON(userId, email: email))}"#
    }

    static func isAuth(_ request: RecordedRequest, _ endpoint: String) -> Bool {
        request.path.hasSuffix("/auth/v1/\(endpoint)")
    }

    static func isDeleteAccount(_ request: RecordedRequest) -> Bool {
        request.path.hasSuffix("/functions/v1/delete-account")
    }

    /// The user an email names in these tests ("a@..." is A, "b@..." is B).
    static func user(forEmail email: String?) -> String {
        email?.hasPrefix("b") == true ? userB : userA
    }

    /// A password grant for the account its email names.
    static func isPasswordGrant(_ request: RecordedRequest, for userId: String) -> Bool {
        isAuth(request, "token") && request.query("grant_type") == "password"
            && user(forEmail: request.jsonObject?["email"] as? String) == userId
    }

    /// Password grants answer with a session for the account the email names; logout answers 204;
    /// `rest` answers everything else (default: an empty array).
    static func signInResponder(
        rest: @escaping StubServer.Responder = { _ in .emptyArray }
    ) -> StubServer.Responder {
        { request in
            if isAuth(request, "token"), request.query("grant_type") == "password" {
                let email = request.jsonObject?["email"] as? String ?? "a@example.com"
                return .json(sessionJSON(user(forEmail: email), email: email))
            }
            if isAuth(request, "logout") { return .json("", status: 204) }
            return rest(request)
        }
    }
}

/// A testing graph over a real SDK client whose requests a `StubServer` answers, with a fake Library
/// backend and fake list channels (no websocket).
@MainActor
struct SessionSDKHarness {
    let server: StubServer
    let client: SupabaseClient
    /// The SDK's persisted session (in memory).
    let storage: InMemoryAuthStorage
    let graph: AppGraph
    let channels: FakeUserListChannels
    let defaults: UserDefaults
    private let suiteName: String

    var session: SessionController { graph.session }
    var identity: IdentityStore { graph.identity }

    init(responder: @escaping StubServer.Responder, libraryBackend: any LibraryBackend = FakeLibraryBackend()) throws {
        server = StubServer()
        server.respond(with: responder)
        storage = InMemoryAuthStorage()
        client = StubSupabase.makeClient(server: server, storage: storage)
        suiteName = "kuro.tests.session-sdk.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        channels = FakeUserListChannels()
        // Concurrent SDK scenarios need separate real SQLite/WAL stores. Sharing the
        // app's default file makes another test's connection block deletion cleanup.
        let outbox = try ProgressOutbox(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suiteName).sqlite").path)
        graph = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: FakeNotificationCenter(),
            client: client,
            libraryBackend: libraryBackend,
            userListChannels: channels,
            progressOutbox: outbox
        )
    }

    /// What reached its destination first once the account ended.
    enum EndStep: Sendable, Equatable {
        /// The SDK's logout request reached the server.
        case logoutRequest
        /// The ended account's list-channel teardown started.
        case channelTeardown
    }

    /// The order observed by `endWithChannelTeardownHeld`.
    struct EndOrder {
        /// What happened first after the account ended.
        let first: EndStep?
        /// Channel teardowns started before the (held) logout answer was released.
        let teardownsBeforeLogoutAnswered: Int
        /// The logout request's `scope`.
        let logoutScope: String?
        /// Teardowns of the ended account's channel once `end` finished.
        let teardowns: Int
        /// What `end` threw.
        let error: (any Error)?
    }

    /// Opens the signed-in account's list channel, holds its teardown (a slow server leave) and the
    /// SDK's logout answer (`logoutGate`, the responder's), runs `end` (sign-out or deletion) and
    /// reports what reached its destination first. The funnel must hand the SDK its sign-out before it
    /// awaits the channel teardown, so the logout request has to arrive while the teardown is held.
    /// Both gates are opened on every path before `end` is awaited: a swapped order fails the
    /// caller's assertions instead of hanging.
    func endWithChannelTeardownHeld(logoutGate: StubGate, _ end: @escaping @MainActor () async -> (any Error)?) async throws -> EndOrder {
        await graph.libraryRealtime.startIfNeeded()
        #expect(channels.made.count == 1, "\(channels.log)")
        let channel = try #require(channels.made.first)
        #expect(channel.isOpen)
        let teardown = StubGate()
        channel.teardownGate = teardown
        let (steps, step) = AsyncStream.makeStream(of: EndStep.self)
        channel.onTeardownStart = { step.yield(.channelTeardown) }
        let server = self.server
        let logoutSeen = Task {
            let request = await server.waitForRequest { StubAuth.isAuth($0, "logout") }
            step.yield(.logoutRequest)
            return request
        }

        let ending = Task.immediate { @MainActor in await end() }
        var arrivals = steps.makeAsyncIterator()
        let first = await arrivals.next()
        let teardownsBeforeLogoutAnswered = channel.unsubscribeCount
        logoutGate.open()
        teardown.open()
        let error = await ending.value
        let logout = await logoutSeen.value
        step.finish()
        return EndOrder(
            first: first,
            teardownsBeforeLogoutAnswered: teardownsBeforeLogoutAnswered,
            logoutScope: logout.query("scope"),
            teardowns: channel.unsubscribeCount,
            error: error
        )
    }

    /// Answers: email sign-in (a session for A, or `signInStatus` with GoTrue's error body), logout,
    /// `delete-account` (`deletion`), everything else an empty array.
    static func responder(
        signInStatus: Int = 200,
        logoutGate: StubGate? = nil,
        deletion: StubResponse = .json(#"{"success":true}"#)
    ) -> StubServer.Responder {
        { request in
            if StubAuth.isAuth(request, "token") {
                return signInStatus == 200
                    ? .json(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com"))
                    : .json(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#, status: signInStatus)
            }
            if StubAuth.isAuth(request, "logout") {
                let answer = StubResponse.json("", status: 204)
                return logoutGate.map(answer.held(by:)) ?? answer
            }
            if StubAuth.isDeleteAccount(request) { return deletion }
            return .emptyArray
        }
    }

    func requests(_ predicate: (RecordedRequest) -> Bool) -> [RecordedRequest] {
        server.requests.filter(predicate)
    }

    /// Suspends until `condition` (which reads observable state) holds. State-based: re-checked on every
    /// change of what it read, never on a timer.
    static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        while !condition() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = condition()
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    func signIn() async throws {
        try await session.signInWithEmail(email: "a@example.com", password: "pw")
        await graph.libraryActions.libraryRefreshTask?.value
    }

    func tearDown() async {
        await session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}

@MainActor
@Suite("Session funnel through the real SDK auth client", .timeLimit(.minutes(1)))
struct SessionSDKTests {
    @Test("A stale account confirmation cannot delete or sign out the newly active account")
    func staleAccountConfirmationCannotEndNewAccount() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder())
        try await h.signIn()
        let original = try #require(h.graph.accountSession.current)
        try await h.session.signInWithEmail(email: "b@example.com", password: "pw")
        let current = try #require(h.graph.accountSession.current)
        #expect(current != original)

        do {
            try await h.session.deleteAccount(expectedAccount: original)
            Issue.record("The obsolete deletion confirmation was admitted")
        } catch is CancellationError {
            // Rejected before any backend or local cleanup work.
        }
        await h.session.signOut(expectedAccount: original)

        #expect(h.requests(StubAuth.isDeleteAccount).isEmpty)
        #expect(h.requests { StubAuth.isAuth($0, "logout") }.isEmpty)
        #expect(h.graph.accountSession.current == current)
        #expect(h.identity.currentUserId == StubAuth.userB)
        #expect(h.client.auth.currentSession?.user.id.uuidString == StubAuth.userB)
        await h.tearDown()
    }

    @Test("Email sign-in: the SDK's session is published through the funnel (identity, account context, Library bound and loaded) and the profile row is ensured")
    func emailSignInGoesThroughTheFunnel() async throws {
        let h = try SessionSDKHarness(responder: SessionSDKHarness.responder())
        try await h.signIn()

        #expect(h.identity.isAuthenticated)
        #expect(h.identity.currentUserId == StubAuth.userA)
        #expect(h.identity.currentUserEmail == "a@example.com")
        #expect(h.identity.authErrorMessage == nil)
        #expect(h.graph.accountSession.current?.userId == StubAuth.userA)
        #expect(h.graph.library.loadState == .loaded)
        let token = try #require(h.requests { StubAuth.isAuth($0, "token") }.first)
        #expect(token.query("grant_type") == "password")
        let profile = try #require(h.requests { $0.resource == "profiles" }.first)
        #expect(profile.method == "POST")
        // `UUID` encodes upper-case (unchanged; a Postgres `uuid` column accepts either case).
        #expect(profile.jsonObject?["id"] as? String == StubAuth.userA)
        #expect(profile.jsonObject?["adult_opt_in"] as? Bool == false)
        #expect(profile.preferences.contains("resolution=ignore-duplicates"),
            "Session bootstrap must not reset an existing adult-content preference")
        await h.tearDown()
    }

    @Test("Failed email sign-in: the user-facing message is published, nothing else; no profile request")
    func failedEmailSignInPublishesOnlyTheMessage() async throws {
        let h = try SessionSDKHarness(responder: SessionSDKHarness.responder(signInStatus: 400))
        await #expect(throws: (any Error).self) { try await h.session.signInWithEmail(email: "a@example.com", password: "bad") }

        #expect(h.identity.authErrorMessage == AuthCopy.message(forCode: "invalid_credentials", german: KuroLocale.isGerman))
        #expect(!h.identity.isAuthenticated)
        #expect(h.graph.accountSession.current == nil)
        #expect(h.requests { $0.resource == "profiles" }.isEmpty)
        await h.tearDown()
    }

    @Test("F01: A's sign-in failure that answers after B signed in is stale: B stays signed in with its identity, Library and (empty) error; nothing is cleared, reported or bootstrapped for A")
    func staleFailedSignInLeavesTheNewerAccount() async throws {
        let slowA = StubGate()
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder())
        h.server.respond { request in
            if StubAuth.isPasswordGrant(request, for: StubAuth.userA) {
                return StubResponse.json(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#, status: 400)
                    .held(by: slowA)
            }
            return StubAuth.signInResponder()(request)
        }
        let attemptA = Task.immediate { @MainActor in
            do {
                try await h.session.signInWithEmail(email: "a@example.com", password: "bad")
                return nil as (any Error)?
            } catch {
                return error
            }
        }
        _ = await h.server.waitForRequest { StubAuth.isPasswordGrant($0, for: StubAuth.userA) }

        try await h.session.signInWithEmail(email: "b@example.com", password: "good")
        await h.graph.libraryActions.libraryRefreshTask?.value
        let contextB = try #require(h.graph.accountSession.current)
        #expect(contextB.userId == StubAuth.userB)

        slowA.open()
        let errorA = await attemptA.value
        #expect(errorA is CancellationError, "A's superseded attempt must end as dropped work, not as a sign-in failure: \(String(describing: errorA))")
        #expect(h.identity.isAuthenticated)
        #expect(h.identity.currentUserId == StubAuth.userB)
        #expect(h.identity.authErrorMessage == nil, "A's stale failure was reported over B's session")
        #expect(h.graph.accountSession.current == contextB)
        #expect(h.graph.library.loadState == .loaded)
        #expect(h.client.auth.currentSession?.user.id.uuidString == StubAuth.userB)
        await h.tearDown()
    }

    // MARK: F46: each SDK credential/session mechanism once, at the HTTP seam

    @Test("F46 launch restore: the SDK's persisted session is restored through the funnel without a token request; the restored account's private request carries its own bearer and the anon apikey")
    func launchRestoreThroughTheSDK() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder())
        try await h.signIn()
        // The process ends: the app's state is gone, the SDK's persisted session stays.
        let ended = h.session.endSessionState()
        await h.session.finishSessionEnd(ended)
        let before = h.server.requests.count

        await h.session.restoreSession()

        #expect(h.identity.isAuthenticated)
        #expect(h.identity.currentUserId == StubAuth.userA)
        #expect(!h.identity.isAuthBootstrapping)
        #expect(h.graph.accountSession.current?.userId == StubAuth.userA)
        let restored = Array(h.server.requests.dropFirst(before))
        #expect(!restored.contains { StubAuth.isAuth($0, "token") }, "a valid persisted session needs no token request: \(restored)")
        let profile = try #require(restored.first { $0.resource == "profiles" })
        #expect(profile.bearerSubject == StubAuth.userA.lowercased())
        #expect(profile.header("apikey") == StubSupabase.anonKey)
        await h.tearDown()
    }

    @Test("F46 sign-up: one POST /signup with the credentials and the anon apikey; the returned session goes through the funnel and the profile row is written with that account's bearer")
    func signUpThroughTheSDK() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            StubAuth.isAuth(request, "signup") ? .json(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com")) : .emptyArray
        })

        try await h.session.signUpWithEmail(email: "a@example.com", password: "secret1")

        let signup = try #require(h.requests { StubAuth.isAuth($0, "signup") }.first)
        #expect(signup.method == "POST")
        #expect(signup.jsonObject?["email"] as? String == "a@example.com")
        #expect(signup.header("apikey") == StubSupabase.anonKey)
        #expect(h.identity.currentUserId == StubAuth.userA)
        #expect(h.graph.accountSession.current?.userId == StubAuth.userA)
        let profile = try #require(h.requests { $0.resource == "profiles" }.first)
        #expect(profile.bearerSubject == StubAuth.userA.lowercased())
        await h.tearDown()
    }

    @Test("F46 Sign in with Apple: one id_token grant (provider apple, the ID token, the raw nonce); the session goes through the funnel; the first sign-in's full name is saved with that account's bearer")
    func appleSignInThroughTheSDK() async throws {
        let email = "a@privaterelay.appleid.com"
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "id_token" {
                return .json(StubAuth.sessionJSON(StubAuth.userA, email: email))
            }
            if StubAuth.isAuth(request, "user") { return .json(StubAuth.userJSON(StubAuth.userA, email: email)) }
            return .emptyArray
        })

        try await h.session.signInWithApple(idToken: "apple-id-token", rawNonce: "raw-nonce", fullName: "Ada Lovelace")

        let grant = try #require(h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "id_token" }.first)
        #expect(grant.jsonObject?["provider"] as? String == "apple")
        #expect(grant.jsonObject?["id_token"] as? String == "apple-id-token")
        #expect(grant.jsonObject?["nonce"] as? String == "raw-nonce")
        #expect(grant.header("apikey") == StubSupabase.anonKey)
        #expect(h.identity.currentUserId == StubAuth.userA)
        let update = try #require(h.requests { StubAuth.isAuth($0, "user") && $0.method == "PUT" }.first)
        #expect(update.bearerSubject == StubAuth.userA.lowercased())
        #expect((update.jsonObject?["data"] as? [String: Any])?["full_name"] as? String == "Ada Lovelace")
        await h.tearDown()
    }

    @Test("F46 same-user auth callback: setSession verifies the link's own token with GET /user, the funnel keeps the account context (R-E1-1) and the SDK holds the link's session")
    func sameUserCallbackSetSession() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            StubAuth.isAuth(request, "user") ? .json(StubAuth.userJSON(StubAuth.userA, email: "a@example.com")) : .emptyArray
        })
        try await h.signIn()
        let context = h.graph.accountSession.current
        let exp = Int(Date().timeIntervalSince1970) + 3_600
        let linkToken = AuthCallbackGuardTests.jwt(
            #"{"sub":"\#(StubAuth.userA.lowercased())","exp":\#(exp),"role":"authenticated","session_id":"from-link"}"#
        )

        await h.session.handleAuthCallback(accessToken: linkToken, refreshToken: "refresh-link")

        let verify = try #require(h.requests { StubAuth.isAuth($0, "user") && $0.method == "GET" }.last)
        #expect(verify.header("Authorization") == "Bearer \(linkToken)")
        #expect(verify.header("apikey") == StubSupabase.anonKey)
        #expect(h.graph.accountSession.current == context)
        #expect(h.client.auth.currentSession?.accessToken == linkToken)
        #expect(h.identity.authErrorMessage == nil)
        await h.tearDown()
    }

    @Test("F46 SDK event mapping: the events the real SDK emits for a same-user token refresh and a sign-out map through the funnel: the refresh keeps the context and only refreshes the email; the sign-out ends the session")
    func sdkEventMapping() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "refresh_token" {
                return .json(StubAuth.sessionJSON(StubAuth.userA, email: "a.new@example.com"))
            }
            return .emptyArray
        })
        try await h.signIn()
        let context = try #require(h.graph.accountSession.current)
        // The SDK's own events, observed through an awaited registration (the funnel's listener attaches
        // asynchronously inside the SDK, so the test feeds it the same events itself).
        let (events, sink) = AsyncStream<(AuthChangeEvent, Session?)>.makeStream()
        let registration = await h.client.auth.onAuthStateChange { event, session in sink.yield((event, session)) }
        var iterator = events.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial?.0 == .initialSession)
        #expect(SessionController.eventKind(.initialSession) == .initialSession)
        func deliver(_ event: (AuthChangeEvent, Session?)?) async throws {
            let (kind, session) = try #require(event)
            await h.session.handleAuthEvent(
                SessionController.eventKind(kind),
                sessionUserId: session?.user.id.uuidString,
                email: session?.user.email,
                storedSessionUserId: h.client.auth.currentSession?.user.id.uuidString
            )
        }

        _ = try await h.client.auth.refreshSession()
        let refreshed = await iterator.next()
        #expect(refreshed?.0 == .tokenRefreshed)
        try await deliver(refreshed)
        #expect(h.graph.accountSession.current == context)
        #expect(h.identity.currentUserEmail == "a.new@example.com")
        let refresh = try #require(h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "refresh_token" }.first)
        #expect(refresh.jsonObject?["refresh_token"] as? String == "refresh-\(StubAuth.userA.lowercased())")

        try await h.client.auth.signOut(scope: .local)
        let signedOut = await iterator.next()
        #expect(signedOut?.0 == .signedOut)
        try await deliver(signedOut)
        #expect(h.graph.accountSession.current == nil)
        #expect(!h.identity.isAuthenticated && h.identity.currentUserId == nil)
        registration.remove()
        await h.tearDown()
    }

    @Test("F71: A's token refresh still in flight when A signs out and B signs in completes last and re-stores A's session in the SDK; the funnel fails closed on that .tokenRefreshed: B's session ends and A's foreign session is removed, nothing runs as B with A's token")
    func lateRefreshOfAnotherAccountFailsClosed() async throws {
        let heldRefresh = StubGate()
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "refresh_token" {
                return StubResponse.json(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com")).held(by: heldRefresh)
            }
            return .emptyArray
        })
        try await h.signIn()
        let (events, sink) = AsyncStream<(AuthChangeEvent, Session?)>.makeStream()
        let registration = await h.client.auth.onAuthStateChange { event, session in sink.yield((event, session)) }
        var iterator = events.makeAsyncIterator()

        // A's refresh is in flight (the SDK's auto-refresh, or a request that found A's token expiring).
        let client = h.client
        let refreshA = Task { try await client.auth.refreshSession() }
        _ = await h.server.waitForRequest { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "refresh_token" }
        await h.session.signOut()
        try await h.session.signInWithEmail(email: "b@example.com", password: "pw")
        #expect(h.graph.accountSession.current?.userId == StubAuth.userB)

        heldRefresh.open()
        _ = try? await refreshA.value
        // The SDK's defect: its store holds A again while the app is B.
        #expect(h.client.auth.currentSession?.user.id.uuidString == StubAuth.userA)
        var refreshed: (AuthChangeEvent, Session?)?
        while let event = await iterator.next() {
            if event.0 == .tokenRefreshed { refreshed = event; break }
        }
        let (kind, session) = try #require(refreshed)
        await h.session.handleAuthEvent(
            SessionController.eventKind(kind),
            sessionUserId: session?.user.id.uuidString,
            email: session?.user.email,
            storedSessionUserId: h.client.auth.currentSession?.user.id.uuidString
        )

        #expect(h.graph.accountSession.current == nil, "B stayed signed in while the SDK holds A's credential")
        #expect(!h.identity.isAuthenticated)
        #expect(h.client.auth.currentSession == nil, "A's resurrected session stayed in the SDK store")
        registration.remove()
        await h.tearDown()
    }

    @Test("F01: A's sign-in success that would answer after B's newer attempt never installs A's session behind B: the newer attempt cancels A's SDK leg first; B is published and the SDK holds B")
    func staleSuccessfulSignInNeverInstallsBehindTheNewerAccount() async throws {
        let slowA = StubGate()
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder())
        h.server.respond { request in
            if StubAuth.isPasswordGrant(request, for: StubAuth.userA) {
                return StubResponse.json(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com")).held(by: slowA)
            }
            return StubAuth.signInResponder()(request)
        }
        let attemptA = Task.immediate { @MainActor in
            do {
                try await h.session.signInWithEmail(email: "a@example.com", password: "pw")
                return nil as (any Error)?
            } catch {
                return error
            }
        }
        _ = await h.server.waitForRequest { StubAuth.isPasswordGrant($0, for: StubAuth.userA) }

        try await h.session.signInWithEmail(email: "b@example.com", password: "pw")
        slowA.open()
        let errorA = await attemptA.value

        #expect(errorA is CancellationError, "\(String(describing: errorA))")
        #expect(h.graph.accountSession.current?.userId == StubAuth.userB)
        #expect(h.identity.currentUserId == StubAuth.userB)
        #expect(h.client.auth.currentSession?.user.id.uuidString == StubAuth.userB,
                "A's superseded sign-in installed its session behind B (the SDK would send B's requests as A)")
        await h.tearDown()
    }

    @Test("Sign-out (R-E1-3): the account context, identity and Library are gone before the SDK logout answers; the SDK session is removed")
    func signOutEndsStateBeforeTheSDKCall() async throws {
        let logout = StubGate()
        let h = try SessionSDKHarness(responder: SessionSDKHarness.responder(logoutGate: logout))
        try await h.signIn()
        #expect(h.client.auth.currentSession != nil)

        let signingOut = Task.immediate { @MainActor in await h.session.signOut() }
        // The synchronous half ran before the first suspension point.
        #expect(h.graph.accountSession.current == nil)
        #expect(!h.identity.isAuthenticated && h.identity.currentUserId == nil)
        #expect(h.graph.library.loadState == .notLoaded)
        let request = await h.server.waitForRequest { StubAuth.isAuth($0, "logout") }
        #expect(request.query("scope") == "global")

        logout.open()
        await signingOut.value
        #expect(h.client.auth.currentSession == nil)
        await h.tearDown()
    }

    @Test("Sign-out (E1 S1): the SDK sign-out is issued before the awaited channel teardown: with the ended account's list channel teardown held, the logout request (scope global) still arrives, and the teardown starts only after the SDK answered")
    func signOutReachesTheSDKBeforeTheChannelTeardown() async throws {
        let logout = StubGate()
        let h = try SessionSDKHarness(responder: SessionSDKHarness.responder(logoutGate: logout))
        try await h.signIn()

        let order = try await h.endWithChannelTeardownHeld(logoutGate: logout) {
            await h.session.signOut()
            return nil
        }

        #expect(order.first == .logoutRequest, "the funnel awaited the channel teardown before the SDK sign-out")
        #expect(order.teardownsBeforeLogoutAnswered == 0, "the channel teardown started before the SDK sign-out returned")
        #expect(order.logoutScope == "global")
        #expect(order.teardowns == 1, "the ended account's channel was removed once")
        #expect(h.client.auth.currentSession == nil)
        #expect(h.graph.accountSession.current == nil)
        await h.tearDown()
    }

    @Test("Account deletion (E1 S1): the local SDK sign-out (scope local) is issued before the awaited channel teardown: with the teardown held, the logout request still arrives")
    func deletionReachesTheSDKBeforeTheChannelTeardown() async throws {
        let logout = StubGate()
        let h = try SessionSDKHarness(responder: SessionSDKHarness.responder(logoutGate: logout))
        try await h.signIn()

        let order = try await h.endWithChannelTeardownHeld(logoutGate: logout) {
            do {
                try await h.session.deleteAccount()
                return nil
            } catch {
                return error
            }
        }

        #expect(order.error == nil, "\(String(describing: order.error))")
        #expect(h.requests(StubAuth.isDeleteAccount).count == 1)
        #expect(order.first == .logoutRequest, "the funnel awaited the channel teardown before the local SDK sign-out")
        #expect(order.teardownsBeforeLogoutAnswered == 0, "the channel teardown started before the SDK sign-out returned")
        #expect(order.logoutScope == "local")
        #expect(order.teardowns == 1, "the ended account's channel was removed once")
        #expect(h.client.auth.currentSession == nil, "the SDK's persisted session survived the deletion")
        #expect(h.graph.accountSession.current == nil)
        await h.tearDown()
    }

    enum Deletion: String, CaseIterable, Sendable {
        case confirmed, serverError, notConfirmed

        var answer: StubResponse {
            switch self {
            case .confirmed: return .json(#"{"success":true}"#)
            case .serverError: return .json(#"{"error":"cleanup failed","failed_steps":["anime_user_lists"]}"#, status: 500)
            case .notConfirmed: return .json(#"{"success":false,"error":"Account deletion failed: try again"}"#)
            }
        }
    }

    @Test("Account deletion: only a confirmed deletion ends the session and removes the SDK session; a failure leaves session, identity and Library untouched (retryable)",
          arguments: Deletion.allCases)
    func deletionEndsTheSessionOnlyWhenConfirmed(deletion: Deletion) async throws {
        let h = try SessionSDKHarness(responder: SessionSDKHarness.responder(deletion: deletion.answer))
        try await h.signIn()
        let context = h.graph.accountSession.current

        var thrown: (any Error)?
        do {
            try await h.session.deleteAccount()
        } catch {
            thrown = error
        }

        let request = try #require(h.requests(StubAuth.isDeleteAccount).first)
        #expect(request.jsonObject?["confirm"] as? String == "true")
        switch deletion {
        case .confirmed:
            #expect(thrown == nil, "\(String(describing: thrown))")
            #expect(h.graph.accountSession.current == nil)
            #expect(!h.identity.isAuthenticated)
            #expect(h.client.auth.currentSession == nil, "the SDK's persisted session survived the deletion")
            #expect(h.requests { StubAuth.isAuth($0, "logout") }.first?.query("scope") == "local")
        case .serverError, .notConfirmed:
            #expect(thrown != nil)
            if deletion == .notConfirmed {
                #expect(thrown?.localizedDescription == "Account deletion failed: try again")
            }
            #expect(h.graph.accountSession.current == context)
            #expect(h.identity.isAuthenticated)
            #expect(h.graph.library.loadState == .loaded)
            #expect(h.client.auth.currentSession != nil)
            #expect(h.requests { StubAuth.isAuth($0, "logout") }.isEmpty)
        }
        await h.tearDown()
    }

    @Test("A callback for another user while signed in reaches neither the SDK nor the funnel")
    func foreignCallbackSendsNothing() async throws {
        let h = try SessionSDKHarness(responder: SessionSDKHarness.responder())
        try await h.signIn()
        let context = h.graph.accountSession.current
        let authRequests = h.requests { $0.path.contains("/auth/v1/") }.count

        await h.session.handleAuthCallback(accessToken: StubAuth.accessToken(StubAuth.userB), refreshToken: "refresh-b")

        #expect(h.requests { $0.path.contains("/auth/v1/") }.count == authRequests, "the callback reached the SDK")
        #expect(h.graph.accountSession.current == context)
        #expect(h.client.auth.currentSession?.user.id.uuidString == StubAuth.userA)
        #expect(h.identity.authErrorMessage != nil && h.graph.banner.message == h.identity.authErrorMessage)
        await h.tearDown()
    }
}

@MainActor
extension SessionSDKTests {
    @Test("Initial SDK session restores a session missed before listener registration; stale initial event cannot replace newer attempt")
    func initialSessionReconcilesRegistrationGap() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { _ in .emptyArray })
        // SDK state changed before the funnel listener attached.
        _ = try await h.client.auth.signIn(email: "a@example.com", password: "password")
        let sdk = try #require(h.client.auth.currentSession)
        await h.session.handleAuthEvent(.initialSession, sessionUserId: sdk.user.id.uuidString,
            email: sdk.user.email, storedSessionUserId: sdk.user.id.uuidString)
        #expect(h.identity.isAuthenticated)
        #expect(h.graph.accountSession.current?.userId.lowercased() == sdk.user.id.uuidString.lowercased())
        let context = h.graph.accountSession.current
        await h.session.handleAuthEvent(.initialSession, sessionUserId: nil, email: nil,
            storedSessionUserId: nil, listenerAttempt: -1)
        #expect(h.graph.accountSession.current == context)
        await h.tearDown()
    }
}

@MainActor
extension SessionSDKTests {
    @Test("Held sign-out/deletion cannot clear a newer SDK sign-in", arguments: [false, true])
    func credentialEndSerializesWithNewSignIn(deletion: Bool) async throws {
        let logout = StubGate()
        let h = try SessionSDKHarness(responder: { request in
            if StubAuth.isAuth(request, "logout") {
                return .json("", status: 204).held(by: logout)
            }
            if StubAuth.isDeleteAccount(request) { return .json(#"{"success":true}"#) }
            return StubAuth.signInResponder()(request)
        })
        try await h.signIn()
        let ending = Task.immediate { @MainActor () -> (any Error)? in
            do {
                if deletion { try await h.session.deleteAccount() }
                else { await h.session.signOut() }
                return nil
            } catch { return error }
        }
        _ = await h.server.waitForRequest { StubAuth.isAuth($0, "logout") }
        #expect(h.graph.accountSession.current == nil)
        let newer = Task.immediate { @MainActor in
            try await h.session.signInWithEmail(email: "b@example.com", password: "pw")
        }
        logout.open()
        let endError = await ending.value
        #expect(endError == nil, "\(String(describing: endError))")
        try await newer.value
        #expect(h.graph.accountSession.current?.userId == StubAuth.userB)
        #expect(h.client.auth.currentSession?.user.id.uuidString == StubAuth.userB)
        await h.tearDown()
    }
}

@MainActor
extension SessionSDKTests {
    @Test("Expired saved SDK identity restores offline presentation only after transport failure", arguments: [true, false])
    func expiredSavedSessionRestore(offline: Bool) async throws {
        let h = try SessionSDKHarness(responder: { request in
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "password" {
                var body = try! JSONSerialization.jsonObject(with: Data(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com").utf8)) as! [String: Any]
                body["expires_at"] = Int(Date().timeIntervalSince1970) - 3600
                body["expires_in"] = 0
                return .json(String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self))
            }
            if StubAuth.isAuth(request, "token"), request.query("grant_type") == "refresh_token" {
                if offline { return .failure(.notConnectedToInternet) }
                return .json(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#, status: 400)
            }
            return .failure(.notConnectedToInternet)
        })
        // Store a real SDK session before starting the app's launch funnel.
        _ = try await h.client.auth.signIn(email: "a@example.com", password: "pw")
        #expect(h.client.auth.currentSession?.isExpired == true)
        await h.session.restoreSession()
        #expect(h.identity.isAuthenticated == offline)
        #expect(h.graph.accountSession.current?.userId == (offline ? StubAuth.userA : nil))
        #expect(h.requests { StubAuth.isAuth($0, "token") && $0.query("grant_type") == "refresh_token" }.count > 0)
        await h.tearDown()
    }
}
