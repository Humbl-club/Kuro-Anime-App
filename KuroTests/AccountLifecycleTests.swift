//
//  AccountLifecycleTests.swift
//  KuroTests
//
//  Account/permission lifecycle (E1): stale account completions, obsolete handles,
//  private-state reset, session entry points, callback guard and pending reminders.
//  No test here touches the network: services are built through the testing
//  initializer (no SDK client) and the Library store runs over a `FakeLibraryBackend`.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

// MARK: - Controlled responses and fakes

/// Responses keyed by a label that the test completes explicitly.
@MainActor
final class ControlledResponses<Value> {
    private var pending: [String: CheckedContinuation<Value, Error>] = [:]
    private var waiters: [String: [CheckedContinuation<Bool, Never>]] = [:]
    private var finishedCallers: Set<String> = []
    private(set) var requests: [String] = []

    func value(for label: String) async throws -> Value {
        requests.append(label)
        return try await withCheckedThrowingContinuation { continuation in
            pending[label] = continuation
            resumeWaiters(for: label, requested: true)
        }
    }

    /// Suspends until `label`'s request is pending (`true`), or until the caller
    /// registered for `label` finished without issuing a request (`false`).
    func waitForRequest(_ label: String) async -> Bool {
        if pending[label] != nil { return true }
        if finishedCallers.contains(label) { return false }
        return await withCheckedContinuation { waiters[label, default: []].append($0) }
    }

    func callerFinished(_ label: String) {
        finishedCallers.insert(label)
        resumeWaiters(for: label, requested: pending[label] != nil)
    }

    func complete(_ label: String, with result: Result<Value, Error>) {
        pending.removeValue(forKey: label)?.resume(with: result)
    }

    private func resumeWaiters(for label: String, requested: Bool) {
        for waiter in waiters.removeValue(forKey: label) ?? [] { waiter.resume(returning: requested) }
    }
}

struct ControlledFailure: Error {}

@MainActor
final class FakeNotificationCenter: PendingNotificationCenter {
    var pending: [String] = []
    /// Every `schedule` call, in order (ids).
    private(set) var scheduled: [String] = []
    /// When set, `pendingRequestIdentifiers()` answers only once the gate opens, with the pending
    /// requests at THAT moment (a slow lookup during which other work runs).
    var lookupGate: StubGate?
    /// `pendingRequestIdentifiers()` calls so far (started, also when still held).
    private(set) var lookups = 0
    /// `requestAuthorizationIfNeeded()` calls so far (the explicit, prompting request).
    private(set) var authorizationRequests = 0
    /// `currentPermission()` calls so far (the automatic, never-prompting read).
    private(set) var permissionReads = 0
    /// The payload of every scheduled request, by id.
    private(set) var userInfoById: [String: [String: String]] = [:]
    /// The fire date of every scheduled request, by id.
    private(set) var dateById: [String: Date] = [:]
    /// The device permission (Settings); `.notDetermined` until the user answered the prompt.
    var permission: NotificationPermission = .authorized
    /// What the user answers when prompted.
    var promptAnswer: NotificationPermission = .authorized
    /// Prompts shown so far (the system shows one only while undecided).
    private(set) var prompts = 0
    /// Whether the system accepts new requests.
    var acceptsRequests = true
    private var waiters: [(condition: @MainActor (FakeNotificationCenter) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []

    func pendingRequestIdentifiers() async -> [String] {
        lookups += 1
        changed()
        if let gate = lookupGate {
            await withCheckedContinuation { continuation in gate.whenOpen { continuation.resume() } }
        }
        return pending
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0) }
        changed()
    }

    func requestAuthorizationIfNeeded() async -> NotificationPermission {
        authorizationRequests += 1
        if permission == .notDetermined {
            prompts += 1
            permission = promptAnswer
        }
        changed()
        return permission
    }

    func currentPermission() async -> NotificationPermission {
        permissionReads += 1
        changed()
        return permission
    }

    func schedule(id: String, title: String, body: String, at date: Date, userInfo: [String: String]) async -> Bool {
        userInfoById[id] = userInfo
        return await schedule(id: id, title: title, body: body, at: date)
    }

    func schedule(id: String, title: String, body: String, at date: Date) async -> Bool {
        scheduled.append(id)
        dateById[id] = date
        guard acceptsRequests else { return false }
        if !pending.contains(id) { pending.append(id) }
        changed()
        return true
    }

    /// Suspends until `condition` holds (state-based; checked after every change of this fake).
    func waitUntil(_ condition: @escaping @MainActor (FakeNotificationCenter) -> Bool) async {
        if condition(self) { return }
        await withCheckedContinuation { waiters.append((condition, $0)) }
    }

    private func changed() {
        let ready = waiters.filter { $0.condition(self) }
        waiters.removeAll { $0.condition(self) }
        for waiter in ready { waiter.continuation.resume() }
    }
}

/// A service built through the testing seam, with its own UserDefaults suite and Library backend.
@MainActor
struct LifecycleHarness {
    let service: AppGraph
    let defaults: UserDefaults
    let notifications: FakeNotificationCenter
    let backend: FakeLibraryBackend
    private let suiteName: String

    init(backend: FakeLibraryBackend = FakeLibraryBackend()) throws {
        suiteName = "kuro.tests.account-lifecycle.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        notifications = FakeNotificationCenter()
        self.backend = backend
        service = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: notifications, libraryBackend: backend)
    }

    func tearDown() async {
        await service.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

enum LifecycleFixtures {
    static let userA = "6F1C4C3E-0A7B-4D7E-9C55-3D2A1B0C9E8A"
    static let userB = "0B9E8D7C-6A5B-4C3D-8E2F-1A0B9C8D7E6F"

    /// A tracked anime as the backend stores it (rating 8 = legacy score 80).
    static func entry(mediaId: Int, kind: MediaKind = .anime, notes: String? = nil) -> LibraryEntry {
        FakeLibraryBackend.entry(kind, mediaId, rowId: mediaId, status: .current, progress: 3, rating: 8, notes: notes)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// Seeds one representative value in every account-private category for the current user.
    @MainActor
    static func seedPrivateState(on harness: LifecycleHarness) async throws {
        let service = harness.service
        let now = Date()
        // Library projection (single authority): A's rows on the backend, loaded through a refresh.
        let userId = try #require(service.accountSession.current?.userId)
        await service.libraryActions.libraryRefreshTask?.value
        harness.backend.setRows([entry(mediaId: 101, notes: "A's private note"), entry(mediaId: 7, kind: .manga)], for: userId)
        await service.libraryActions.fetchUserLists()
        try #require(service.library.isTracked(MediaKey(kind: .anime, id: 101)))
        service.libraryActions.togglingMediaKeys = ["anime-101"]
        service.libraryActions.errorMessage = "A's list error"
        // Collection feed, cursor, filter
        service.collection.collectionFeedItems = [Media(
            id: 101, kind: .anime, title: "A title", imageURL: nil, year: "2024",
            displayDescription: "", episodes: nil, chapters: nil, rating: nil, genres: nil,
            statusRaw: nil, formatRaw: nil, popularityValue: nil, trendingValue: nil, createdAtValue: nil
        )]
        service.collection.collectionFeedCursorRowId = 55
        service.collection.collectionFeedCursorUpdatedAt = now
        service.collection.collectionFeedCursorSourceRank = 2
        service.collection.hasMoreCollectionFeed = false
        service.collection.isCollectionLoading = true
        service.collection.isLoadingMoreCollectionFeed = true
        service.collection.currentCollectionStatusFilter = .planning
        service.collection.collectionErrorMessage = "A's collection error"
        // Releases (owner: `releases`)
        service.releases.upcomingAirings = [try decode(ReleasesStore.UpcomingAiring.self,
            #"{"anime_id":101,"title_english":"A title","next_episode_number":2,"next_airing_at":0}"#)]
        service.releases.countdownByAnimeId = [101: "1h"]
        service.releases.lastUpcomingFetchAt = now
        service.releases.upcomingBackoff.recordFailure(now: now)
        // Personalised Discover (owner: `discovery`, keyed by user) + Concierge
        service.discovery.discoverBundleCache["discover_bundle|\(userId)|30|24"] = .init(value: try decode(DiscoverBundle.self, """
            {"anime":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],
             "newly_added":[],"airing_today":[],"current_season":[]},
             "manga":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],"newly_added":[]}}
            """), storedAt: now)
        service.imports.conciergeParseCache["concierge_parse|\(userA)"] = .init(value: try decode(
            ConciergeParseResponse.self, #"{"success":true,"userId":"a","items":[]}"#
        ), storedAt: now)
        service.concierge.conciergeRecommendCache["concierge_recommend|\(userA)"] = .init(value: try decode(
            ConciergeRecommendResponse.self, #"{"success":true}"#
        ), storedAt: now)
        // Clubs + social
        service.clubs.clubBundleCache[ClubsStore.BundleKey(context: service.accountSession.current, clubId: "club-1")] = .init(value: try decode(ClubBundle.self, """
            {"club":{"id":"club-1","name":"A's club","description":null,"sharing_level":"status","max_members":20,
             "is_archived":false,"invite_code":"SECRET","created_at":"2026-01-01T00:00:00Z"},
             "members":[],"my_role":"owner","my_sharing_level":"progress","rails":[],"polls":[],"member_count":2}
            """), storedAt: now)
        service.clubs.myClubs = [try decode(ClubListRow.self, """
            {"id":"club-1","name":"A's club","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z"}
            """)]
        service.clubs.hasUnseenClubActivity = true
        service.social.friendTrackingCounts["ANIME-101"] = 3
        // Provider preferences (owner: `availability`)
        service.availability.userStreamingServices = ["netflix"]
        service.availability.clubSharedProvidersCache["club-1"] = try decode(ProviderAvailabilityStore.ClubSharedProvidersResponse.self, """
            {"shared_services":[{"slug":"netflix","display_name":"Netflix"}],
             "member_count_total":2,"member_count_with_services":2,"coverage_pct":100}
            """)
    }

    /// Names of private categories that still hold a value.
    @MainActor
    static func privateStateLeaks(in service: AppGraph) -> [String] {
        var leaks: [String] = []
        func check(_ name: String, _ isClear: Bool) { if !isClear { leaks.append(name) } }
        // The Library projection (the store; the facade readers that mirrored it were deleted in E6c2).
        check("library entries", service.library.allEntries.isEmpty)
        check("library anime keys", ListStatus.allCases.allSatisfy { service.library.keys(withStatus: $0, kind: .anime).isEmpty })
        check("library manga keys", ListStatus.allCases.allSatisfy { service.library.keys(withStatus: $0, kind: .manga).isEmpty })
        check("isTracked", !service.library.isTracked(MediaKey(kind: .anime, id: 101)))
        check("library entry", service.library.entry(for: MediaKey(kind: .anime, id: 101)) == nil)
        check("togglingMediaKeys", service.libraryActions.togglingMediaKeys.isEmpty)
        check("errorMessage", service.libraryActions.errorMessage == nil)
        check("collectionFeedItems", service.collection.collectionFeedItems.isEmpty)
        check("isCollectionLoading", !service.collection.isCollectionLoading)
        check("isLoadingMoreCollectionFeed", !service.collection.isLoadingMoreCollectionFeed)
        check("feed cursor", service.collection.collectionFeedCursorRowId == nil
              && service.collection.collectionFeedCursorUpdatedAt == nil
              && service.collection.collectionFeedCursorSourceRank == nil
              && service.collection.hasMoreCollectionFeed)
        check("currentCollectionStatusFilter", service.collection.currentCollectionStatusFilter == nil)
        check("collectionErrorMessage", service.collection.collectionErrorMessage == nil)
        check("upcomingAirings", service.releases.upcomingAirings.isEmpty)
        check("countdownByAnimeId", service.releases.countdownByAnimeId.isEmpty)
        check("upcoming throttle", service.releases.lastUpcomingFetchAt == nil)
        check("upcomingBackoff", service.releases.upcomingBackoff.failures == 0 && service.releases.upcomingBackoff.until == nil)
        check("discoverBundleCache", service.discovery.discoverBundleCache.isEmpty)
        check("conciergeParseCache", service.imports.conciergeParseCache.isEmpty)
        check("conciergeRecommendCache", service.concierge.conciergeRecommendCache.isEmpty)
        check("clubBundleCache", service.clubs.clubBundleCache.isEmpty)
        check("clubActivityForMedia", service.clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").isEmpty)
        check("myClubs", service.clubs.myClubs.isEmpty)
        check("hasUnseenClubActivity", !service.clubs.hasUnseenClubActivity)
        check("friendTrackingCounts", service.social.friendTrackingCounts.isEmpty)
        check("userStreamingServices", service.availability.userStreamingServices.isEmpty)
        check("clubSharedProvidersCache", service.availability.cachedClubSharedProviders(clubId: "club-1") == nil)
        return leaks
    }
}

// MARK: - 1. Coordinator transitions
// The transition table and the account-scoped load semantics are tested once, in the KuroCore
// package (Packages/KuroModules/Tests/KuroCoreTests), next to the primitives themselves.

// MARK: - 2. Stale account completion (headline defect)

@MainActor
@Suite("Account lifecycle: stale user-lists completion", .timeLimit(.minutes(1)))
struct StaleUserListsCompletionTests {

    enum Outcome: String, CaseIterable, Sendable { case success, failure }

    @Test("A's late completion cannot change B's state; B runs its own fetch", arguments: Outcome.allCases)
    func staleCompletionIsDropped(outcome: Outcome) async throws {
        let source = ControlledResponses<[LibraryEntry]>()
        let harness = try LifecycleHarness(backend: FakeLibraryBackend(fetchSource: source))
        let service = harness.service

        // A signs in; the session funnel starts A's list refresh, which is held open.
        await service.session.applySession(userId: "user-a", email: "a@example.com")
        let refreshA = try #require(service.libraryActions.libraryRefreshTask)
        #expect(await source.waitForRequest("user-a"))

        // A signs out, B signs in, and the funnel starts B's own refresh.
        await service.session.endSession()
        await service.session.applySession(userId: "user-b", email: "b@example.com")
        let refreshB = try #require(service.libraryActions.libraryRefreshTask)

        // A's request completes late.
        switch outcome {
        case .success:
            source.complete("user-a", with: .success([
                LifecycleFixtures.entry(mediaId: 101, notes: "A's private note")
            ]))
        case .failure:
            source.complete("user-a", with: .failure(ControlledFailure()))
        }
        await refreshA.value

        // Nothing from A is visible as B's state.
        #expect(service.library.allEntries.isEmpty)
        #expect(ListStatus.allCases.allSatisfy { service.library.keys(withStatus: $0, kind: .anime).isEmpty })
        #expect(service.library.entry(for: MediaKey(kind: .anime, id: 101)) == nil)
        #expect(service.libraryActions.errorMessage == nil)

        // B issued its own request and its result is what lands.
        let bRequested = await source.waitForRequest("user-b")
        try #require(bRequested, "B must start its own fetch instead of adopting A's")
        source.complete("user-b", with: .success([LifecycleFixtures.entry(mediaId: 202)]))
        await refreshB.value

        #expect(service.library.allEntries.map(\.key) == [MediaKey(kind: .anime, id: 202)])
        #expect(service.accountSession.current?.userId == "user-b")
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 202)))
        #expect(!service.library.isTracked(MediaKey(kind: .anime, id: 101)))
        #expect(source.requests == ["user-a", "user-b"])
        await harness.tearDown()
    }
}

// MARK: - 3. Private-state reset

@MainActor
@Suite("Account lifecycle: private-state reset")
struct PrivateStateResetTests {

    enum Transition: String, CaseIterable, Sendable { case switchToB, signOut }

    @Test("No private category or preference of A is visible after a transition", arguments: Transition.allCases)
    func transitionClearsPrivateState(transition: Transition) async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        let defaults = harness.defaults
        // Legacy device-global keys written before preferences were scoped.
        defaults.set("legacy-club", forKey: "com.kuro.rememberedAddToClubId")
        defaults.set(1.0, forKey: "com.kuro.clubNotificationLastCheck")
        defaults.set(1.0, forKey: "com.kuro.clubLastSeen.club-1")

        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        #expect(service.clubs.rememberedAddToClubId() == nil, "legacy unscoped value must be ignored")
        try await LifecycleFixtures.seedPrivateState(on: harness)
        service.clubs.setRememberedAddToClubId("club-a")
        service.clubs.markClubSeen(clubId: "club-1")
        service.clubs.clearClubNotificationBadge()
        #expect(service.clubs.rememberedAddToClubId() == "club-a")

        switch transition {
        case .switchToB:
            await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")
            #expect(service.identity.isAuthenticated)
            #expect(service.identity.currentUserId == LifecycleFixtures.userB)
        case .signOut:
            await service.session.endSession()
            #expect(!service.identity.isAuthenticated)
            #expect(service.identity.currentUserId == nil)
        }

        let leaks = LifecycleFixtures.privateStateLeaks(in: service)
        #expect(leaks.isEmpty, "A's state still visible: \(leaks)")
        #expect(service.clubs.rememberedAddToClubId() == nil)
        #expect(service.clubs.clubLastSeenAt(clubId: "club-1") == nil)
        let keys = Set(defaults.dictionaryRepresentation().keys)
        #expect(!keys.contains("com.kuro.rememberedAddToClubId"))
        #expect(!keys.contains("com.kuro.clubNotificationLastCheck"))
        #expect(!keys.contains("com.kuro.clubLastSeen.club-1"))

        // A's scoped preferences survive for A only.
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        #expect(service.clubs.rememberedAddToClubId() == "club-a")
        #expect(service.clubs.clubLastSeenAt(clubId: "club-1") != nil)
        await harness.tearDown()
    }

    @Test("Replacing user A with user B clears Concierge, Clubs, and Collection private state")
    func accountSwitchClearsConciergeClubsCollection() async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        try await LifecycleFixtures.seedPrivateState(on: harness)

        #expect(!service.imports.conciergeParseCache.isEmpty)
        #expect(!service.concierge.conciergeRecommendCache.isEmpty)
        #expect(!service.clubs.myClubs.isEmpty)
        #expect(!service.clubs.clubBundleCache.isEmpty)
        #expect(!service.collection.collectionFeedItems.isEmpty)

        await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")

        #expect(service.imports.conciergeParseCache.isEmpty)
        #expect(service.concierge.conciergeRecommendCache.isEmpty)
        #expect(service.clubs.myClubs.isEmpty)
        #expect(service.clubs.clubBundleCache.isEmpty)
        #expect(service.clubs.hasUnseenClubActivity == false)
        #expect(service.collection.collectionFeedItems.isEmpty)
        #expect(service.collection.collectionFeedCursorRowId == nil)
        #expect(service.collection.currentCollectionStatusFilter == nil)
        #expect(service.collection.collectionErrorMessage == nil)
        await harness.tearDown()
    }

    @Test("Deleting an account removes its scoped preferences")
    func deletedAccountPrefsAreRemoved() async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        service.clubs.setRememberedAddToClubId("club-a")
        service.clubs.markClubSeen(clubId: "club-1")
        await service.session.endSession()
        service.clubs.removeAccountScopedPrefs(userId: LifecycleFixtures.userA)

        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        #expect(service.clubs.rememberedAddToClubId() == nil)
        #expect(service.clubs.clubLastSeenAt(clubId: "club-1") == nil)
        await harness.tearDown()
    }
}

// MARK: - 4. Session entry points

@MainActor
@Suite("Account lifecycle: session entry points")
struct SessionEntryPointTests {

    /// Entry points that can run without the SDK. Restore, email sign-in, sign-up, Apple and the
    /// auth callback call `applySession` once the SDK returns a session; sign-out, deletion and
    /// failed sign-in/restore call `endSession`.
    enum Entry: String, CaseIterable, Sendable {
        case applySessionB, sdkSignedInB, endSession, sdkSignedOut
    }

    @Test("A different user or a sign-out applies the same reset policy", arguments: Entry.allCases)
    func entryResetsPrivateState(entry: Entry) async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        try await LifecycleFixtures.seedPrivateState(on: harness)

        switch entry {
        case .applySessionB:
            await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")
        case .sdkSignedInB:
            await service.session.handleAuthEvent(.signedIn, sessionUserId: LifecycleFixtures.userB,
                                          email: "b@example.com", storedSessionUserId: LifecycleFixtures.userB)
        case .endSession:
            await service.session.endSession()
        case .sdkSignedOut:
            await service.session.handleAuthEvent(.signedOut, sessionUserId: nil, email: nil, storedSessionUserId: nil)
        }

        let leaks = LifecycleFixtures.privateStateLeaks(in: service)
        #expect(leaks.isEmpty, "A's state still visible: \(leaks)")
        switch entry {
        case .applySessionB, .sdkSignedInB:
            #expect(service.identity.isAuthenticated)
            #expect(service.accountSession.current?.userId == LifecycleFixtures.userB)
        case .endSession, .sdkSignedOut:
            #expect(!service.identity.isAuthenticated)
            #expect(service.accountSession.current == nil)
        }
        await harness.tearDown()
    }

    /// Events for the account already in effect, and stale SDK events, must not erase state.
    enum KeepingEvent: String, CaseIterable, Sendable {
        case applySessionSameUser, sdkSignedInSameUser, sdkTokenRefreshed, staleSignedOut, staleSignedIn
    }

    @Test("Same-user refresh and stale SDK events keep the account context and state", arguments: KeepingEvent.allCases)
    func sameUserEventsKeepState(event: KeepingEvent) async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let context = service.accountSession.current
        try await LifecycleFixtures.seedPrivateState(on: harness)

        switch event {
        case .applySessionSameUser:
            await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        case .sdkSignedInSameUser:
            await service.session.handleAuthEvent(.signedIn, sessionUserId: LifecycleFixtures.userA.lowercased(),
                                          email: "a@example.com", storedSessionUserId: LifecycleFixtures.userA)
        case .sdkTokenRefreshed:
            await service.session.handleAuthEvent(.tokenRefreshed, sessionUserId: LifecycleFixtures.userA,
                                          email: "a@example.com", storedSessionUserId: LifecycleFixtures.userA)
        case .staleSignedOut:
            // Emitted before a newer sign-in; the SDK already stores the current user's session.
            await service.session.handleAuthEvent(.signedOut, sessionUserId: nil, email: nil,
                                          storedSessionUserId: LifecycleFixtures.userA)
        case .staleSignedIn:
            // A `.signedIn` for a session the SDK no longer stores.
            await service.session.handleAuthEvent(.signedIn, sessionUserId: LifecycleFixtures.userB,
                                          email: "b@example.com", storedSessionUserId: nil)
        }

        #expect(service.accountSession.current == context)
        #expect(service.identity.isAuthenticated)
        #expect(service.library.allEntries.map(\.key.id) == [101, 7])
        #expect(service.library.isTracked(MediaKey(kind: .anime, id: 101)))
        #expect(!service.clubs.clubBundleCache.isEmpty)
        #expect(!service.discovery.discoverBundleCache.isEmpty)
        await harness.tearDown()
    }
}

// MARK: - 5. Auth callback guard

@Suite("Account lifecycle: auth callback guard")
struct AuthCallbackGuardTests {

    static func jwt(_ payload: String) -> String {
        func base64URL(_ string: String) -> String {
            Data(string.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return base64URL(#"{"alg":"HS256","typ":"JWT"}"#) + "." + base64URL(payload) + ".signature"
    }

    /// Fixed clock for the decision table.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let a = LifecycleFixtures.userA.lowercased()
    static let b = LifecycleFixtures.userB.lowercased()
    static let futureExp = Int(now.timeIntervalSince1970) + 3_600
    static let pastExp = Int(now.timeIntervalSince1970) - 3_600
    static let withinMarginExp = Int(now.timeIntervalSince1970) + 30

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let token: String
        let currentUserId: String?
        let expected: AuthCallbackDecision
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "signed in: same sub (JWT lower-case, SDK upper-case) + future exp -> proceed",
             token: jwt(#"{"sub":"\#(a)","exp":\#(futureExp),"role":"authenticated"}"#),
             currentUserId: LifecycleFixtures.userA, expected: .proceed),
        Case(name: "signed in: same sub + missing exp -> reject",
             token: jwt(#"{"sub":"\#(a)"}"#),
             currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        Case(name: "signed in: same sub + past exp -> reject",
             token: jwt(#"{"sub":"\#(a)","exp":\#(pastExp)}"#),
             currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        Case(name: "signed in: same sub + exp inside the safety margin -> reject",
             token: jwt(#"{"sub":"\#(a)","exp":\#(withinMarginExp)}"#),
             currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        Case(name: "signed in: same sub + non-numeric exp -> reject",
             token: jwt(#"{"sub":"\#(a)","exp":"\#(futureExp)"}"#),
             currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        Case(name: "signed in: different sub + future exp -> reject",
             token: jwt(#"{"sub":"\#(b)","exp":\#(futureExp)}"#),
             currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        Case(name: "signed in: no sub + future exp -> reject",
             token: jwt(#"{"exp":\#(futureExp)}"#),
             currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        Case(name: "signed in: undecodable token -> reject",
             token: "not-a-jwt", currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        Case(name: "signed in: empty header/signature segments (SDK would not read exp) -> reject",
             token: "." + String(jwt(#"{"sub":"\#(a)","exp":\#(futureExp)}"#).split(separator: ".")[1]) + ".",
             currentUserId: LifecycleFixtures.userA, expected: .rejectDifferentUser),
        // Spec D12 (login CSRF): signed out, a token pair is never adopted without a matching pending
        // flow started on this device (the pending-flow cases live in AuthLaneTests).
        Case(name: "signed out: other user, future exp -> reject (no pending flow)",
             token: jwt(#"{"sub":"\#(b)","exp":\#(futureExp)}"#),
             currentUserId: nil, expected: .rejectNoPendingFlow),
        Case(name: "signed out: missing exp -> reject (no pending flow)",
             token: jwt(#"{"sub":"\#(b)"}"#),
             currentUserId: nil, expected: .rejectNoPendingFlow),
        Case(name: "signed out: undecodable token -> reject (no pending flow)",
             token: "not-a-jwt", currentUserId: nil, expected: .rejectNoPendingFlow),
    ]

    @Test("Decision table", arguments: cases)
    func decision(_ testCase: Case) {
        #expect(AuthCallbackGuard.decision(
            accessToken: testCase.token,
            currentUserId: testCase.currentUserId,
            now: Self.now
        ) == testCase.expected)
    }

    /// Tokens the service must reject while A is signed in (wall clock: no `exp` / another user).
    static let rejectedWhileSignedIn: [String] = [
        jwt(#"{"sub":"\#(b)"}"#),
        jwt(#"{"sub":"\#(a)"}"#),
    ]

    @MainActor
    @Test("The service rejects such a callback before any session change and shows the banner",
          arguments: rejectedWhileSignedIn)
    func serviceRejectsCallback(token: String) async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let context = service.accountSession.current
        try await LifecycleFixtures.seedPrivateState(on: harness)

        await service.session.handleAuthCallback(accessToken: token, refreshToken: "attacker-refresh")

        #expect(service.identity.authErrorMessage != nil)
        // Signed-in screens do not render authErrorMessage; the existing transient banner carries it.
        #expect(service.banner.message == service.identity.authErrorMessage)
        #expect(service.accountSession.current == context)
        #expect(service.identity.isAuthenticated)
        #expect(service.library.allEntries.map(\.key.id) == [101, 7])
        await harness.tearDown()
    }
}

// MARK: - 6. Pending airing reminders

@MainActor
@Suite("Account lifecycle: pending reminders")
struct PendingReminderTests {

    enum Transition: String, CaseIterable, Sendable {
        case signOut, switchAccount, restoreSameOwner, failedSignInWhileSignedOut,
             failedRestoreOffline, failedRestoreSessionGone, startAsAnotherAccount
    }

    @Test("Reminders go with their account: removed on end/switch/new owner, kept for their own account",
          arguments: Transition.allCases)
    func airingReminders(transition: Transition) async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        let scheduled = ["airing-1-start", "airing-1-1h", "unrelated-x"]
        let removed = ["unrelated-x"]
        let ownerKey = ReminderScheduler.airingRemindersOwnerKey

        switch transition {
        case .signOut:
            await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
            harness.notifications.pending = scheduled
            await service.session.endSession()
            #expect(harness.notifications.pending == removed)
        case .switchAccount:
            await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
            harness.notifications.pending = scheduled
            await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")
            #expect(harness.notifications.pending == removed)
        case .restoreSameOwner:
            // Scheduled by A in an earlier launch; the launch restore starts A's session again.
            harness.notifications.pending = scheduled
            harness.defaults.set(LifecycleFixtures.userA.lowercased(), forKey: ownerKey)
            await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
            #expect(harness.notifications.pending == scheduled)
        case .failedSignInWhileSignedOut:
            // A failed sign-in ends no account session: pending reminders are left alone.
            harness.notifications.pending = scheduled
            harness.defaults.set(LifecycleFixtures.userA.lowercased(), forKey: ownerKey)
            await service.session.endSession()
            #expect(harness.notifications.pending == scheduled)
        case .failedRestoreOffline:
            // Offline launch: restore fails but the SDK still stores A's session, so A's reminders stay.
            harness.notifications.pending = scheduled
            harness.defaults.set(LifecycleFixtures.userA.lowercased(), forKey: ownerKey)
            await service.session.endSessionAfterFailedRestore(storedSessionUserId: LifecycleFixtures.userA)
            #expect(harness.notifications.pending == scheduled)
            #expect(harness.defaults.string(forKey: ownerKey) != nil)
        case .failedRestoreSessionGone:
            // The SDK removed A's revoked session: nobody on this device owns the reminders any more.
            harness.notifications.pending = scheduled
            harness.defaults.set(LifecycleFixtures.userA.lowercased(), forKey: ownerKey)
            await service.session.endSessionAfterFailedRestore(storedSessionUserId: nil)
            #expect(harness.notifications.pending == removed)
            #expect(harness.defaults.string(forKey: ownerKey) == nil)
        case .startAsAnotherAccount:
            // A's session vanished while the app was closed; B signs in on the same device.
            harness.notifications.pending = scheduled
            harness.defaults.set(LifecycleFixtures.userA.lowercased(), forKey: ownerKey)
            await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")
            #expect(harness.notifications.pending == removed)
            #expect(harness.defaults.string(forKey: ownerKey) == nil)
        }
        await harness.tearDown()
    }

    /// The `anime` row a reminder is scheduled from: airs in `hours`.
    nonisolated static func animeRow(_ id: Int, inHours hours: Double) -> StubResponse {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(hours * 3_600))
        return .json(#"{"id":\#(id),"title_english":"Show \#(id)","title_romaji":null,"next_episode_number":3,"next_airing_at":"\#(at)"}"#)
    }

    /// Answers the `anime` read of whichever title the request names (airing in 5 h).
    nonisolated static func animeResponder(_ request: RecordedRequest) -> StubResponse {
        guard request.resource == "anime", let raw = request.query("id"), let id = Int(raw.dropFirst("eq.".count)) else {
            return .emptyArray
        }
        return animeRow(id, inHours: 5)
    }

    struct PermissionCase: Sendable, CustomTestStringConvertible {
        let name: String
        let permission: NotificationPermission
        let promptAnswer: NotificationPermission
        let acceptsRequests: Bool
        let expected: ReminderScheduler.ScheduleOutcome
        var testDescription: String { name }
    }

    nonisolated static let permissionCases: [PermissionCase] = [
        PermissionCase(name: "authorized -> scheduled", permission: .authorized, promptAnswer: .authorized,
                       acceptsRequests: true, expected: .scheduled),
        // Automatic scheduling never prompts (item 10: permission is asked only from an explicit user
        // action), so an undecided permission schedules nothing whatever the user would answer.
        PermissionCase(name: "undecided -> notAuthorized, no prompt (automatic scheduling never asks)", permission: .notDetermined,
                       promptAnswer: .authorized, acceptsRequests: true, expected: .notAuthorized),
        PermissionCase(name: "denied in Settings -> notAuthorized, no prompt", permission: .denied,
                       promptAnswer: .authorized, acceptsRequests: true, expected: .notAuthorized),
        PermissionCase(name: "authorized but the system refuses the request -> failed (never success)", permission: .authorized,
                       promptAnswer: .authorized, acceptsRequests: false, expected: .failed),
    ]

    @Test("F19: the outcome follows the device permission and the system's answer; anything but scheduled adds nothing and sets no owner marker; never a prompt",
          arguments: permissionCases)
    func scheduleOutcomeFollowsPermission(_ permissionCase: PermissionCase) async throws {
        let notifications = FakeNotificationCenter()
        notifications.permission = permissionCase.permission
        notifications.promptAnswer = permissionCase.promptAnswer
        notifications.acceptsRequests = permissionCase.acceptsRequests
        let harness = try PublicDataHarness(notifications: notifications, responder: Self.animeResponder)
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let context = try #require(service.accountSession.current)

        let first = await service.reminders.scheduleAiringNotifications(animeId: 7, context: context)
        let second = await service.reminders.scheduleAiringNotifications(animeId: 7, context: context)

        #expect(first == permissionCase.expected)
        #expect(second == permissionCase.expected)
        #expect(notifications.prompts == 0, "automatic scheduling prompted")
        let marker = harness.defaults.string(forKey: ReminderScheduler.airingRemindersOwnerKey)
        if permissionCase.expected == .scheduled {
            #expect(Set(notifications.pending) == ["airing-7-start", "airing-7-1h"])
            #expect(marker == LifecycleFixtures.userA.lowercased())
        } else {
            #expect(notifications.pending.isEmpty)
            #expect(marker == nil, "an owner marker names reminders that do not exist")
        }
        await harness.tearDown()
    }

    @Test("F19: a permission revoked in Settings after reminders were scheduled is seen on the next schedule: notAuthorized, nothing added, no prompt; the restored owner keeps its reminders")
    func revokedPermissionIsSeenWithoutANewPrompt() async throws {
        let notifications = FakeNotificationCenter()
        notifications.permission = .authorized
        notifications.promptAnswer = .authorized
        let harness = try PublicDataHarness(notifications: notifications, responder: Self.animeResponder)
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let context = try #require(service.accountSession.current)

        #expect(await service.reminders.scheduleAiringNotifications(animeId: 7, context: context) == .scheduled)
        notifications.permission = .denied
        #expect(await service.reminders.scheduleAiringNotifications(animeId: 8, context: context) == .notAuthorized)

        #expect(notifications.prompts == 0)
        #expect(Set(notifications.pending) == ["airing-7-start", "airing-7-1h"])
        #expect(!notifications.scheduled.contains { $0.hasPrefix("airing-8") })
        // A later launch of the same owner keeps them (restored-own-account behavior intact).
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        #expect(Set(notifications.pending) == ["airing-7-start", "airing-7-1h"])
        await harness.tearDown()
    }

    @Test("F05: A's reminder cleanup, paused on its pending-request lookup, never removes B's reminders or owner marker scheduled meanwhile; A's reminders are removed")
    func pausedCleanupKeepsTheNextAccountsReminders() async throws {
        let notifications = FakeNotificationCenter()
        let harness = try PublicDataHarness(notifications: notifications) { request in
            request.resource == "anime" ? Self.animeRow(7, inHours: 5) : .emptyArray
        }
        let service = harness.service
        let ownerKey = ReminderScheduler.airingRemindersOwnerKey
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        notifications.pending = ["airing-1-start", "airing-1-1h", "unrelated-x"]
        harness.defaults.set(LifecycleFixtures.userA.lowercased(), forKey: ownerKey)

        // A's session ends; its cleanup is paused on the lookup of the pending requests.
        let lookup = StubGate()
        notifications.lookupGate = lookup
        let ending = Task.immediate { @MainActor in await service.session.endSession() }
        await notifications.waitUntil { $0.lookups == 1 }

        // Meanwhile B signs in and saves an airing title: its reminders are scheduled.
        await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")
        let contextB = try #require(service.accountSession.current)
        let schedulingB = Task.immediate { @MainActor in
            await service.reminders.scheduleAiringNotifications(animeId: 7, context: contextB)
        }
        await notifications.waitUntil { $0.permissionReads == 1 }

        // A's cleanup resumes.
        lookup.open()
        await ending.value
        _ = await schedulingB.value

        #expect(Set(notifications.pending) == ["unrelated-x", "airing-7-start", "airing-7-1h"],
                "A's late cleanup removed B's reminders (or kept A's): \(notifications.pending)")
        #expect(harness.defaults.string(forKey: ownerKey) == LifecycleFixtures.userB.lowercased())
        await harness.tearDown()
    }
}

// MARK: - 7. Late realtime events

@MainActor
@Suite("Account lifecycle: late realtime events")
struct LateRealtimeEventTests {

    @Test("Events captured under an ended account schedule no refresh; current ones do")
    func staleEventsScheduleNothing() async throws {
        let harness = try LifecycleHarness()
        let service = harness.service
        await service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let stale = try #require(service.accountSession.current)
        await service.session.endSession()
        await service.session.applySession(userId: LifecycleFixtures.userB, email: "b@example.com")

        // A's channels deliver late events after B signed in.
        service.libraryRealtime.scheduleRefresh(for: stale)
        service.clubs.realtime.scheduleRefresh(clubId: "club-1", context: stale)
        #expect(service.libraryRealtime.debounceTask == nil)
        #expect(service.clubs.realtime.debounceTask == nil)

        // Control: the same calls for the current account do schedule (cancelled before they fire).
        let current = try #require(service.accountSession.current)
        service.libraryRealtime.scheduleRefresh(for: current)
        service.clubs.realtime.scheduleRefresh(clubId: "club-1", context: current)
        #expect(service.libraryRealtime.debounceTask != nil)
        #expect(service.clubs.realtime.debounceTask != nil)
        service.libraryRealtime.debounceTask?.cancel()
        service.clubs.realtime.debounceTask?.cancel()
        await harness.tearDown()
    }
}
