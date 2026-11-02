//
//  ClubsContractTests.swift
//  KuroTests
//
//  The Clubs owner (`ClubsStore` + `ClubRealtimeCoordinator`) asserted on the HTTP requests the
//  real supabase-swift client emits (StubPostgREST: in-process, no network), on what it publishes
//  across account transitions and club revocations, and on its realtime channel lifecycle through
//  the channel seam (`FakeClubChannels`: delivery and teardown without a websocket). Each test is
//  named by the risk it covers. The account-scoped club preferences (E1) are covered by
//  AccountLifecycleTests (PrivateStateResetTests), now running through the owner.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Supabase
import Synchronization
@testable import Kuro

// MARK: - Fixtures

/// Club RPC answers as the server sends them.
enum ClubJSON {
    /// A bundle of `clubId` with one rail (one item: anime `mediaId`) and one open poll.
    static func bundle(clubId: String, mediaId: Int = 101, role: String = "member", myStatus: String? = nil) -> String {
        let myStatusJSON = myStatus.map { "\"\($0)\"" } ?? "null"
        return """
        {"club":{"id":"\(clubId)","name":"Club \(clubId)","description":null,"sharing_level":"status","max_members":20,
         "is_archived":false,"invite_code":"SECRET","created_at":"2026-01-01T00:00:00Z"},
         "members":[{"user_id":"m1","display_name":"M","role":"\(role)","sharing_level":"status","joined_at":"2026-01-01T00:00:00Z"}],
         "my_role":"\(role)","my_sharing_level":"status",
         "rails":[{"id":"rail-\(clubId)","title":"Rail","description":null,"is_locked":false,"sort_order":0,"created_by":"m1",
           "items":[{"id":"item-\(clubId)","media_type":"ANIME","media_id":\(mediaId),"sort_order":0,"note":null,"added_by":"m1",
             "title_display":"T","cover_image_medium":null,"average_score":null,"year":null,"format":null,"episode_count":12,
             "chapter_count":null,"my_status":\(myStatusJSON),"my_progress":null,"my_rating":null,"member_status_counts":null,
             "member_statuses":null,"reactions":null,"my_reactions":null}]}],
         "polls":[{"id":"poll-\(clubId)","question":"Q","is_closed":false,"closes_at":null,"created_by":"m1",
           "created_at":"2026-01-01T00:00:00Z","options":[{"id":"opt-\(clubId)","label":"A","media_type":null,
           "media_id":null,"sort_order":0,"vote_count":0}],"my_vote_option_id":null}],
         "member_count":2}
        """
    }

    /// `fetch_my_clubs_loading` rows for `ids`.
    static func myClubs(_ ids: [String]) -> StubResponse {
        let rows = ids.map { #"{"id":"\#($0)","name":"Club \#($0)","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z"}"# }
        return .json("[" + rows.joined(separator: ",") + "]")
    }

    /// A PostgREST error body (`RAISE EXCEPTION` / RLS) as PostgREST serialises it.
    static func error(message: String, code: String = "P0001", details: String? = nil, hint: String? = nil, status: Int = 400) -> StubResponse {
        let detailsJSON = details.map { "\"\($0)\"" } ?? "null"
        let hintJSON = hint.map { "\"\($0)\"" } ?? "null"
        return .json(#"{"code":"\#(code)","details":\#(detailsJSON),"hint":\#(hintJSON),"message":"\#(message)"}"#, status: status)
    }

    static let sharedProviders = #"{"shared_services":[{"slug":"netflix","display_name":"Netflix"}],"member_count_total":2,"member_count_with_services":2,"coverage_pct":100}"#
}

/// The club channel seam in tests: records subscribe/stop/unsubscribe and delivers change events on
/// demand. `deliver()` works even after `stopListening()`: it stands for an event that was already
/// on its way to the main actor when the channel was stopped.
@MainActor
final class FakeClubChannels: ClubChannelFactory {
    final class Channel: ClubRealtimeChannel {
        let clubId: String
        /// "<clubId>#<n>": the n-th channel made (1-based), for the event log.
        let name: String
        private let onEvent: @MainActor () -> Void
        private let log: @MainActor (String) -> Void
        private(set) var isSubscribed = false
        private(set) var isListening = true
        private(set) var isUnsubscribed = false
        /// How often `unsubscribe()` was called (a channel is left once).
        private(set) var unsubscribeCount = 0
        /// When set, `unsubscribe()` finishes only once the gate opens (a slow server leave).
        var teardownGate: StubGate?

        init(clubId: String, name: String, onEvent: @escaping @MainActor () -> Void, log: @escaping @MainActor (String) -> Void) {
            self.clubId = clubId
            self.name = name
            self.onEvent = onEvent
            self.log = log
        }

        func subscribe() async { isSubscribed = true }
        func stopListening() { isListening = false }
        func unsubscribe() async {
            unsubscribeCount += 1
            if let gate = teardownGate {
                await withCheckedContinuation { continuation in gate.whenOpen { continuation.resume() } }
            }
            isUnsubscribed = true
            log("left \(name)")
        }

        /// One change event on any of the channel's tables.
        func deliver() { onEvent() }

        /// Listening and never left (an open channel).
        var isOpen: Bool { isListening && unsubscribeCount == 0 }
    }

    private(set) var made: [Channel] = []
    /// "made <name>" / "left <name>" in the order they happened.
    private(set) var log: [String] = []

    func makeChannel(clubId: String, onEvent: @escaping @MainActor () -> Void) -> (any ClubRealtimeChannel)? {
        let name = "\(clubId)#\(made.count + 1)"
        let channel = Channel(clubId: clubId, name: name, onEvent: onEvent, log: { [weak self] in self?.log.append($0) })
        made.append(channel)
        log.append("made \(name)")
        return channel
    }
}

/// A service over a stub PostgREST endpoint with the club channel fake and no refresh debounce.
@MainActor
struct ClubsHarness {
    let server: StubServer
    let service: AppGraph
    let channels: FakeClubChannels
    let defaults: UserDefaults
    private let suiteName: String

    var clubs: ClubsStore { service.clubs }

    init(responder: @escaping StubServer.Responder = { _ in .emptyArray }) throws {
        server = StubServer()
        server.respond(with: responder)
        suiteName = "kuro.tests.clubs.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        channels = FakeClubChannels()
        service = AppComposition.testingGraph(
            testingUserDefaults: defaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: server),
            clubChannels: channels,
            clubRefreshDebounce: .zero
        )
    }

    func requests(to resource: String) -> [RecordedRequest] {
        server.requests.filter { $0.resource == resource }
    }

    func bundleRequests(for clubId: String) -> [RecordedRequest] {
        requests(to: "rpc/fetch_club_bundle").filter { $0.jsonObject?["p_club_id"] as? String == clubId }
    }

    func tearDown() async {
        await service.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}

/// Increments and returns the call number (1-based).
private func nextCall(_ counter: borrowing Mutex<Int>) -> Int {
    counter.withLock { count in
        count += 1
        return count
    }
}

// MARK: - Account transitions

@MainActor
@Suite("Clubs: account transitions", .timeLimit(.minutes(1)))
struct ClubsAccountTransitionTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    enum Outcome: String, CaseIterable, Sendable { case success, failure }

    @Test("A -> B: bundles, my clubs and the badge are cleared, the channel is stopped and the in-flight bundle load cancelled; A's late answers never publish into B; B's own read runs",
          arguments: Outcome.allCases)
    func transitionClearsClubsAndDropsLateAnswers(outcome: Outcome) async throws {
        let slow = StubGate()
        let myClubsCalls = Mutex(0)
        // Signalled when A's second (slow) my-clubs read reaches the server.
        let (secondRead, secondReadArrived) = AsyncStream<Void>.makeStream()
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_my_clubs_loading":
                // No user filter (RLS): A's answers are told apart from B's by order.
                switch nextCall(myClubsCalls) {
                case 1: return ClubJSON.myClubs(["club-1"])
                case 2:
                    secondReadArrived.yield()
                    let late = outcome == .success ? ClubJSON.myClubs(["club-1", "club-late"]) : ClubJSON.error(message: "boom", code: "XX000", status: 500)
                    return late.held(by: slow)
                default: return ClubJSON.myClubs(["club-b"])
                }
            case "rpc/fetch_my_clubs_enriched":
                return ClubJSON.error(message: "boom", code: "XX000", status: 500)
            case "rpc/fetch_club_bundle":
                let clubId = request.jsonObject?["p_club_id"] as? String ?? ""
                guard clubId == "club-late" else { return .json(ClubJSON.bundle(clubId: clubId)) }
                let late = outcome == .success ? StubResponse.json(ClubJSON.bundle(clubId: clubId)) : ClubJSON.error(message: "NOT_A_MEMBER")
                return late.held(by: slow)
            default:
                return .emptyArray
            }
        }
        let service = harness.service
        let clubs = harness.clubs
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        await clubs.fetchMyClubs()
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        await clubs.realtime.subscribe(clubId: "club-1")
        clubs.hasUnseenClubActivity = true
        let channelA = try #require(harness.channels.made.first)
        #expect(clubs.myClubs.map(\.id) == ["club-1"])
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").count == 1)

        // A asks again; both answers are slow.
        let lateMyClubs = Task.immediate { @MainActor in await clubs.fetchMyClubs() }
        let lateBundle = Task.immediate { @MainActor in try await clubs.fetchClubBundle(clubId: "club-late") }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/fetch_club_bundle" && $0.jsonObject?["p_club_id"] as? String == "club-late" }
        var secondReads = secondRead.makeAsyncIterator()
        _ = await secondReads.next()

        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(clubs.myClubs.isEmpty)
        #expect(clubs.clubBundleCache.isEmpty)
        #expect(!clubs.hasUnseenClubActivity)
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").isEmpty)
        // The channel was detached synchronously and removed in the funnel's tail.
        #expect(!channelA.isListening)
        #expect(channelA.isUnsubscribed)
        #expect(clubs.realtime.subscribedClubId == nil)
        // A's bundle load was cancelled at the transport (its held answer is never delivered).
        _ = await harness.server.waitForStop { $0.resource == "rpc/fetch_club_bundle" }

        // B has state of its own meanwhile; A's late answers arrive now.
        service.social.friendTrackingCounts["ANIME-202"] = 1
        slow.open()
        await lateMyClubs.value
        await #expect(throws: (any Error).self) { try await lateBundle.value }
        #expect(clubs.myClubs.isEmpty, "A's late my-clubs answer was published into B")
        #expect(clubs.clubBundleCache.isEmpty)
        #expect(service.social.friendTrackingCounts == ["ANIME-202": 1])

        // B reads its own clubs.
        await clubs.fetchMyClubs()
        #expect(clubs.myClubs.map(\.id) == ["club-b"])
        await harness.tearDown()
    }

    @Test("A's late membership-loss answer (a vote) never revokes the same club for B")
    func lateMembershipLossOfEndedAccountRevokesNothing() async throws {
        let slow = StubGate()
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_club_bundle":
                return .json(ClubJSON.bundle(clubId: request.jsonObject?["p_club_id"] as? String ?? ""))
            case "rpc/cast_club_vote":
                return ClubJSON.error(message: "NOT_A_MEMBER").held(by: slow)
            default:
                return .emptyArray
            }
        }
        let service = harness.service
        let clubs = harness.clubs
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        let lateVote = Task.immediate { @MainActor in try await clubs.castVote(pollId: "poll-club-1", optionId: "opt-club-1") }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/cast_club_vote" }

        // B is a member of the same club: bundle cached, channel open, friend counts and providers loaded.
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        await clubs.realtime.subscribe(clubId: "club-1")
        let channelB = try #require(harness.channels.made.last)
        service.social.friendTrackingCounts["ANIME-101"] = 2
        service.availability.clubSharedProvidersCache["club-1"] = try LifecycleFixtures.decode(
            ProviderAvailabilityStore.ClubSharedProvidersResponse.self, ClubJSON.sharedProviders)

        slow.open()
        // F04/F33: A's vote is a credential lease of A, cancelled by the switch; its outcome (and its
        // NOT_A_MEMBER answer) belongs to nobody current and never reaches B.
        await #expect(throws: CancellationError.self) { try await lateVote.value }
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").count == 1, "B's bundle was revoked by A's answer")
        #expect(clubs.realtime.subscribedClubId == "club-1")
        #expect(channelB.isListening && !channelB.isUnsubscribed)
        #expect(service.social.friendTrackingCounts == ["ANIME-101": 2])
        #expect(service.availability.cachedClubSharedProviders(clubId: "club-1") != nil)
        await harness.tearDown()
    }
}

// MARK: - Revocation

@MainActor
@Suite("Clubs: revocation", .timeLimit(.minutes(1)))
struct ClubsRevocationTests {
    static let userA = LifecycleFixtures.userA

    enum Trigger: String, CaseIterable, Sendable {
        case bundleNotAMember, bundleClubNotFound, leaveSucceeded, voteNotAMember
        /// RLS denial (SQLSTATE 42501, no code): a membership loss without a code.
        case bundlePermissionDenied
        /// Control: a non-membership error (the poll closed) revokes nothing.
        case votePollClosedControl
    }

    @Test("A membership loss of club-1 drops its bundle, my-clubs row, the friend projection, its shared providers and its channel; club-2 keeps its own",
          arguments: Trigger.allCases)
    func membershipLossInvalidatesTheClub(trigger: Trigger) async throws {
        let revoked = Mutex(false)
        let harness = try ClubsHarness { request in
            let isRevoked = revoked.withLock { $0 }
            let clubId = request.jsonObject?["p_club_id"] as? String
            switch request.resource {
            case "rpc/fetch_my_clubs_loading":
                return ClubJSON.myClubs(isRevoked ? ["club-2"] : ["club-1", "club-2"])
            case "rpc/fetch_club_bundle":
                if isRevoked, clubId == "club-1" {
                    switch trigger {
                    case .bundleClubNotFound: return ClubJSON.error(message: "CLUB_NOT_FOUND")
                    case .bundlePermissionDenied:
                        return ClubJSON.error(message: "permission denied for table club_members", code: "42501", status: 403)
                    default: return ClubJSON.error(message: "NOT_A_MEMBER")
                    }
                }
                return .json(ClubJSON.bundle(clubId: clubId ?? "", mediaId: clubId == "club-1" ? 101 : 202))
            case "rpc/leave_club":
                return .json(#"{"success":true}"#)
            case "rpc/cast_club_vote":
                return ClubJSON.error(message: trigger == .votePollClosedControl ? "POLL_CLOSED" : "NOT_A_MEMBER")
            default:
                return .emptyArray
            }
        }
        let service = harness.service
        let clubs = harness.clubs
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        await clubs.fetchMyClubs()
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        _ = try await clubs.fetchClubBundle(clubId: "club-2")
        await clubs.realtime.subscribe(clubId: "club-1")
        let channel = try #require(harness.channels.made.first)
        service.social.friendTrackingCounts["ANIME-101"] = 3
        for club in ["club-1", "club-2"] {
            service.availability.clubSharedProvidersCache[club] = try LifecycleFixtures.decode(
                ProviderAvailabilityStore.ClubSharedProvidersResponse.self, ClubJSON.sharedProviders)
        }

        revoked.withLock { $0 = true }
        switch trigger {
        case .bundleNotAMember, .bundleClubNotFound, .bundlePermissionDenied:
            let expected: ClubError = switch trigger {
            case .bundleClubNotFound: .clubNotFound
            case .bundlePermissionDenied: .permissionDenied
            default: .notAMember
            }
            await #expect(throws: expected) { try await clubs.refreshClubBundle(clubId: "club-1") }
        case .leaveSucceeded:
            try await clubs.leaveClub(clubId: "club-1")
        case .voteNotAMember, .votePollClosedControl:
            let expected: ClubError = trigger == .votePollClosedControl ? .pollClosed : .notAMember
            await #expect(throws: expected) { try await clubs.castVote(pollId: "poll-club-1", optionId: "opt-club-1") }
        }
        await clubs.realtime.teardownTask?.value

        // club-2 keeps its own state in every case.
        #expect(clubs.clubActivityForMedia(mediaId: 202, mediaType: "ANIME").count == 1)
        #expect(clubs.myClubs.contains { $0.id == "club-2" })
        #expect(service.availability.cachedClubSharedProviders(clubId: "club-2") != nil)
        #expect(service.accountSession.current?.userId == Self.userA)

        if trigger == .votePollClosedControl {
            #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").count == 1)
            #expect(clubs.myClubs.map(\.id) == ["club-1", "club-2"])
            #expect(service.social.friendTrackingCounts == ["ANIME-101": 3])
            #expect(service.availability.cachedClubSharedProviders(clubId: "club-1") != nil)
            #expect(clubs.realtime.subscribedClubId == "club-1")
            #expect(channel.isListening && !channel.isUnsubscribed)
        } else {
            #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").isEmpty, "the lost club's bundle is still cached")
            #expect(!clubs.clubBundleCache.keys.contains { $0.clubId == "club-1" })
            #expect(!clubs.myClubs.contains { $0.id == "club-1" })
            #expect(service.social.friendTrackingCounts.isEmpty, "friend counts derived from the lost membership survive")
            #expect(service.availability.cachedClubSharedProviders(clubId: "club-1") == nil)
            #expect(clubs.realtime.subscribedClubId == nil)
            #expect(!channel.isListening)
            #expect(channel.isUnsubscribed)
        }
        await harness.tearDown()
    }

    @Test("leaveClub: a bundle read in flight before the leave never re-caches the left club and is not joined by a later read")
    func inFlightBundleOfLeftClubIsDropped() async throws {
        let slow = StubGate()
        let bundleCalls = Mutex(0)
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_club_bundle":
                // The first read was served before the leave reached the server; later reads come after it.
                return nextCall(bundleCalls) == 1
                    ? StubResponse.json(ClubJSON.bundle(clubId: "club-1")).held(by: slow)
                    : ClubJSON.error(message: "NOT_A_MEMBER")
            case "rpc/leave_club":
                return .json(#"{"success":true}"#)
            default:
                return .emptyArray
            }
        }
        let service = harness.service
        let clubs = harness.clubs
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let staleRead = Task.immediate { @MainActor in try await clubs.fetchClubBundle(clubId: "club-1", forceRefresh: true) }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/fetch_club_bundle" }

        try await clubs.leaveClub(clubId: "club-1")
        // A read after the leave sends its own request (it does not join the detached one).
        await #expect(throws: ClubError.notAMember) { try await clubs.fetchClubBundle(clubId: "club-1") }
        #expect(harness.bundleRequests(for: "club-1").count == 2)

        slow.open()
        await #expect(throws: CancellationError.self) { try await staleRead.value }
        #expect(clubs.clubBundleCache.isEmpty, "the left club's bundle was cached again")
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").isEmpty)
        await harness.tearDown()
    }
}

// MARK: - Realtime seam

@MainActor
@Suite("Clubs: realtime channel", .timeLimit(.minutes(1)))
struct ClubsRealtimeTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    @Test("Subscribe -> event -> one club re-read; session end tears the channel down; late events schedule nothing; B re-subscribes and its events refresh B")
    func channelLifecycleAcrossAccounts() async throws {
        let roles = Mutex(["member", "owner"])
        let harness = try ClubsHarness { request in
            guard request.resource == "rpc/fetch_club_bundle" else { return .emptyArray }
            let role = roles.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
            return .json(ClubJSON.bundle(clubId: request.jsonObject?["p_club_id"] as? String ?? "", role: role))
        }
        let service = harness.service
        let clubs = harness.clubs
        let realtime = clubs.realtime
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        await realtime.subscribe(clubId: "club-1")
        #expect(harness.channels.made.map(\.clubId) == ["club-1"])
        let channelA = try #require(harness.channels.made.first)
        #expect(channelA.isSubscribed)
        // Subscribing to the open club again opens nothing.
        await realtime.subscribe(clubId: "club-1")
        #expect(harness.channels.made.count == 1)

        channelA.deliver()
        await realtime.debounceTask?.value
        #expect(harness.bundleRequests(for: "club-1").count == 1)
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").first?.club.id == "club-1")

        await service.session.endSession()
        #expect(!channelA.isListening)
        #expect(channelA.isUnsubscribed)
        #expect(realtime.subscribedClubId == nil)

        // A's channel delivers late, after the end and again after B signed in: nothing is scheduled.
        channelA.deliver()
        #expect(realtime.debounceTask == nil)
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        channelA.deliver()
        #expect(realtime.debounceTask == nil)
        #expect(harness.bundleRequests(for: "club-1").count == 1)

        // B opens the club: a new channel; its events refresh B's bundle.
        await realtime.subscribe(clubId: "club-1")
        #expect(harness.channels.made.count == 2)
        let channelB = try #require(harness.channels.made.last)
        #expect(channelB.isSubscribed && channelB.isListening)
        channelB.deliver()
        await realtime.debounceTask?.value
        #expect(harness.bundleRequests(for: "club-1").count == 2)
        let keys = Array(clubs.clubBundleCache.keys)
        #expect(keys == [ClubsStore.BundleKey(context: service.accountSession.current, clubId: "club-1")])
        #expect(clubs.clubBundleCache.values.first?.value.my_role == "owner")
        await harness.tearDown()
    }

    @Test("Club change: opening club-2 removes club-1's channel; club-1's late event is dropped")
    func clubChangeDropsTheOldChannelsEvents() async throws {
        let harness = try ClubsHarness { request in
            guard request.resource == "rpc/fetch_club_bundle" else { return .emptyArray }
            return .json(ClubJSON.bundle(clubId: request.jsonObject?["p_club_id"] as? String ?? ""))
        }
        let clubs = harness.clubs
        let realtime = clubs.realtime
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")

        await realtime.subscribe(clubId: "club-1")
        await realtime.subscribe(clubId: "club-2")
        let (first, second) = (harness.channels.made[0], harness.channels.made[1])
        #expect(!first.isListening && first.isUnsubscribed)
        #expect(second.isSubscribed && realtime.subscribedClubId == "club-2")

        first.deliver()
        #expect(realtime.debounceTask == nil, "an event of the removed club-1 channel was scheduled")
        second.deliver()
        await realtime.debounceTask?.value
        #expect(harness.requests(to: "rpc/fetch_club_bundle").compactMap { $0.jsonObject?["p_club_id"] as? String } == ["club-2"])
        await harness.tearDown()
    }

    @Test("F42 membership signal: an event on the open club's channel (a club_members change) re-reads the bundle; a NOT_A_MEMBER answer revokes the club (bundle, my-clubs row, friend projection) and closes its channel; a later event of that channel schedules nothing")
    func membershipSignalRevokesThroughTheBoundedReRead() async throws {
        let removed = Mutex(false)
        let reauthorization = StubGate()
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_club_bundle":
                return removed.withLock { $0 } ? ClubJSON.error(message: "NOT_A_MEMBER") : .json(ClubJSON.bundle(clubId: "club-1"))
            case "rpc/fetch_my_clubs_loading":
                return removed.withLock { $0 }
                    ? ClubJSON.myClubs(["club-2"]).held(by: reauthorization)
                    : ClubJSON.myClubs(["club-1", "club-2"])
            default:
                return .emptyArray
            }
        }
        let service = harness.service
        let clubs = harness.clubs
        let realtime = clubs.realtime
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        await clubs.fetchMyClubs()
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        await realtime.subscribe(clubId: "club-1")
        let channel = try #require(harness.channels.made.first)
        service.social.friendTrackingCounts["ANIME-101"] = 2
        let epoch = clubs.revocationEpoch("club-1")

        // An owner/admin removed the caller: the server signal arrives on the open club's channel.
        removed.withLock { $0 = true }
        channel.deliver()
        await realtime.debounceTask?.value
        await realtime.teardownTask?.value

        #expect(clubs.revocationEpoch("club-1") != epoch)
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").isEmpty)
        #expect(clubs.myClubs.isEmpty, "unconfirmed club disclosure is cleared before reauthorization")
        reauthorization.open()
        await clubs.fetchMyClubs()
        #expect(clubs.myClubs.map(\.id) == ["club-2"], "only currently authorized clubs return after the fresh read")
        #expect(service.social.friendTrackingCounts.isEmpty)
        #expect(realtime.subscribedClubId == nil)
        #expect(!channel.isListening && channel.isUnsubscribed)
        channel.deliver()
        #expect(realtime.debounceTask == nil, "an event of the revoked club's channel was scheduled")
        await harness.tearDown()
    }

    @Test("F42 rejoin after a revocation: the revoked channel's teardown (held) completes before the rejoined club's channel is made, and never drops the new channel; the old channel's late event is dropped")
    func rejoinAfterRevocationKeepsTheNewChannel() async throws {
        let harness = try ClubsHarness { request in
            guard request.resource == "rpc/fetch_club_bundle" else { return .emptyArray }
            return .json(ClubJSON.bundle(clubId: "club-1"))
        }
        let clubs = harness.clubs
        let realtime = clubs.realtime
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await realtime.subscribe(clubId: "club-1")
        let old = try #require(harness.channels.made.first)
        let teardown = StubGate()
        old.teardownGate = teardown

        clubs.invalidateClub("club-1")
        let rejoin = Task.immediate { @MainActor in await realtime.subscribe(clubId: "club-1") }
        #expect(harness.channels.made.count == 1, "the rejoined club's channel was made while the old one's removal was pending")
        teardown.open()
        await rejoin.value
        await realtime.teardownTask?.value

        #expect(harness.channels.log == ["made club-1#1", "left club-1#1", "made club-1#2"], "\(harness.channels.log)")
        let new = try #require(harness.channels.made.last)
        #expect(new.isOpen && new.isSubscribed)
        #expect(realtime.subscribedClubId == "club-1")
        old.deliver()
        #expect(realtime.debounceTask == nil, "the revoked channel's late event was scheduled")
        new.deliver()
        await realtime.debounceTask?.value
        #expect(harness.bundleRequests(for: "club-1").count == 1)
        await harness.tearDown()
    }
}

// MARK: - Bundle cache

@MainActor
@Suite("Clubs: bundle cache", .timeLimit(.minutes(1)))
struct ClubsBundleCacheTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    @Test("Bundles are cached per (account, club) for 300 s: warm reads send nothing, an expired entry is re-read, B never reads A's entry")
    func bundleCacheIsKeyedByAccountAndClub() async throws {
        let calls = Mutex(0)
        let harness = try ClubsHarness { request in
            guard request.resource == "rpc/fetch_club_bundle" else { return .emptyArray }
            // Calls 1-2 answer A (member), later calls answer B (owner).
            return .json(ClubJSON.bundle(clubId: "club-1", role: nextCall(calls) <= 2 ? "member" : "owner"))
        }
        let service = harness.service
        let clubs = harness.clubs
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let keyA = ClubsStore.BundleKey(context: service.accountSession.current, clubId: "club-1")

        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        #expect(harness.bundleRequests(for: "club-1").count == 1, "a warm read went to the network")

        // Older than the TTL: read again.
        let cachedA = try #require(clubs.clubBundleCache[keyA])
        clubs.clubBundleCache[keyA] = .init(value: cachedA.value, storedAt: Date().addingTimeInterval(-(ClubsStore.bundleTTL + 1)))
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        #expect(harness.bundleRequests(for: "club-1").count == 2)

        // B is current; an entry of A is planted (as if a write had escaped the guards).
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        clubs.clubBundleCache[keyA] = cachedA
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").isEmpty, "B sees A's cached bundle")
        let bundleB = try await clubs.fetchClubBundle(clubId: "club-1")
        #expect(harness.bundleRequests(for: "club-1").count == 3)
        #expect(bundleB.my_role == "owner")
        #expect(clubs.clubBundleCache[ClubsStore.BundleKey(context: service.accountSession.current, clubId: "club-1")]?.value.my_role == "owner")
        await harness.tearDown()
    }
}

// MARK: - RPC contract

@MainActor
@Suite("Clubs: RPC requests and error codes", .timeLimit(.minutes(1)))
struct ClubsRPCContractTests {
    static let userA = LifecycleFixtures.userA

    enum Operation: String, CaseIterable, Sendable {
        case createClub, createClubWithDescription, joinClub, leaveClub, addRailItem, addRailItemWithNote,
             castVote, toggleReaction, createRail, createPoll, fetchBundle, fetchBundleLoading
    }

    nonisolated static let answers: [String: String] = [
        "rpc/create_club": #"{"club_id":"club-9","invite_code":"AB12CD34","name":"Night Owls"}"#,
        "rpc/join_club": #"{"club_id":"club-9","club_name":"Night Owls","role":"member"}"#,
        "rpc/leave_club": #"{"success":true}"#,
        "rpc/cast_club_vote": #"{"success":true}"#,
        "rpc/add_club_rail_item": #"{"item_id":"item-9","sort_order":3}"#,
        "rpc/toggle_club_reaction": #"{"action":"added","emoji":"fire"}"#,
        "rpc/create_club_rail": #"{"rail_id":"rail-9","title":"Winter"}"#,
        "rpc/create_club_poll": #"{"poll_id":"poll-9","question":"Next?"}"#,
        "rpc/fetch_club_bundle": ClubJSON.bundle(clubId: "club-1"),
        "rpc/fetch_club_bundle_loading": ClubJSON.bundle(clubId: "club-1"),
    ]

    @Test("Each club write/read sends one POST to its RPC with exactly these parameters", arguments: Operation.allCases)
    func requestShape(operation: Operation) async throws {
        let harness = try ClubsHarness { request in
            .json(Self.answers[request.resource ?? ""] ?? "[]")
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")

        let rpc: String
        let body: String
        switch operation {
        case .createClub:
            #expect(try await clubs.createClub(name: "Night Owls").invite_code == "AB12CD34")
            (rpc, body) = ("create_club", #"{"p_name":"Night Owls","p_sharing_level":"status"}"#)
        case .createClubWithDescription:
            _ = try await clubs.createClub(name: "Night Owls", description: "Late shows", sharingLevel: "progress")
            (rpc, body) = ("create_club", #"{"p_description":"Late shows","p_name":"Night Owls","p_sharing_level":"progress"}"#)
        case .joinClub:
            #expect(try await clubs.joinClub(inviteCode: "AB12CD34").club_id == "club-9")
            (rpc, body) = ("join_club", #"{"p_invite_code":"AB12CD34"}"#)
        case .leaveClub:
            try await clubs.leaveClub(clubId: "club-1")
            (rpc, body) = ("leave_club", #"{"p_club_id":"club-1"}"#)
        case .addRailItem:
            #expect(try await clubs.addRailItem(railId: "rail-1", mediaType: "ANIME", mediaId: 101).item_id == "item-9")
            (rpc, body) = ("add_club_rail_item", #"{"p_media_id":101,"p_media_type":"ANIME","p_rail_id":"rail-1"}"#)
        case .addRailItemWithNote:
            _ = try await clubs.addRailItem(railId: "rail-1", mediaType: "MANGA", mediaId: 101, note: "Read this")
            (rpc, body) = ("add_club_rail_item", #"{"p_media_id":101,"p_media_type":"MANGA","p_note":"Read this","p_rail_id":"rail-1"}"#)
        case .castVote:
            try await clubs.castVote(pollId: "poll-1", optionId: "opt-1")
            (rpc, body) = ("cast_club_vote", #"{"p_option_id":"opt-1","p_poll_id":"poll-1"}"#)
        case .toggleReaction:
            #expect(try await clubs.toggleReaction(railItemId: "item-1", emoji: "fire").action == "added")
            (rpc, body) = ("toggle_club_reaction", #"{"p_emoji":"fire","p_rail_item_id":"item-1"}"#)
        case .createRail:
            _ = try await clubs.createClubRail(clubId: "club-1", title: "Winter")
            (rpc, body) = ("create_club_rail", #"{"p_club_id":"club-1","p_title":"Winter"}"#)
        case .createPoll:
            _ = try await clubs.createClubPoll(clubId: "club-1", question: "Next?", options: ["A", "B"])
            (rpc, body) = ("create_club_poll", #"{"p_club_id":"club-1","p_options":["A","B"],"p_question":"Next?"}"#)
        case .fetchBundle:
            #expect(try await clubs.fetchClubBundle(clubId: "club-1").club.id == "club-1")
            (rpc, body) = ("fetch_club_bundle", #"{"p_club_id":"club-1"}"#)
        case .fetchBundleLoading:
            #expect(try await clubs.fetchClubBundleLoading(clubId: "club-1").club.id == "club-1")
            (rpc, body) = ("fetch_club_bundle_loading", #"{"p_club_id":"club-1"}"#)
        }

        let sent = harness.requests(to: "rpc/\(rpc)")
        #expect(sent.count == 1, "\(harness.server.requests)")
        let request = try #require(sent.first)
        #expect(request.method == "POST")
        #expect(request.path.hasSuffix("/rest/v1/rpc/\(rpc)"))
        #expect(request.canonicalBody == body)
        // Membership writes re-read the caller's clubs.
        let reread = harness.requests(to: "rpc/fetch_my_clubs_loading").count
        let rereads: Set<Operation> = [.createClub, .createClubWithDescription, .joinClub, .leaveClub]
        #expect(reread == (rereads.contains(operation) ? 1 : 0))
        await harness.tearDown()
    }

    struct ErrorCase: Sendable, CustomTestStringConvertible {
        let name: String
        let rpc: String
        let response: StubResponse
        let expected: ClubError
        let isMembershipLoss: Bool
        var testDescription: String { name }
    }

    /// Error answers as the server sends them (code in the message: `RAISE EXCEPTION '<CODE>'`).
    nonisolated static let errorCases: [ErrorCase] = [
        ErrorCase(name: "fetch_club_bundle NOT_A_MEMBER -> membership loss", rpc: "fetch_club_bundle",
                  response: ClubJSON.error(message: "NOT_A_MEMBER"), expected: .notAMember, isMembershipLoss: true),
        ErrorCase(name: "fetch_club_bundle CLUB_NOT_FOUND -> membership loss", rpc: "fetch_club_bundle",
                  response: ClubJSON.error(message: "CLUB_NOT_FOUND"), expected: .clubNotFound, isMembershipLoss: true),
        ErrorCase(name: "cast_club_vote POLL_CLOSED -> not a membership loss", rpc: "cast_club_vote",
                  response: ClubJSON.error(message: "POLL_CLOSED"), expected: .pollClosed, isMembershipLoss: false),
        ErrorCase(name: "leave_club UNAUTHENTICATED -> not a membership loss", rpc: "leave_club",
                  response: ClubJSON.error(message: "UNAUTHENTICATED"), expected: .unauthenticated, isMembershipLoss: false),
        ErrorCase(name: "RLS permission denied (42501) -> membership loss", rpc: "fetch_club_bundle",
                  response: ClubJSON.error(message: "permission denied for table club_members", code: "42501", status: 403),
                  expected: .permissionDenied, isMembershipLoss: true),
        // PostgREST sends the DETAIL code as `details`; ClubError (via postgrestDecoder / postgrestJSON)
        // recovers it as DUPLICATE_ITEM.
        ErrorCase(name: "add_club_rail_item duplicate: details DUPLICATE_ITEM reaches the views",
                  rpc: "add_club_rail_item",
                  response: ClubJSON.error(message: "Duplicate rail item", code: "23505", details: "DUPLICATE_ITEM", status: 409),
                  expected: .duplicateItem, isMembershipLoss: false),
        // Its DETAIL code is recovered the same way.
        ErrorCase(name: "add_club_rail_item UNAUTHENTICATED: details code reaches the views",
                  rpc: "add_club_rail_item",
                  response: ClubJSON.error(message: "Unauthenticated", details: "UNAUTHENTICATED"),
                  expected: .unauthenticated, isMembershipLoss: false),
        // F17: HINT is a carrier the SDK does decode (the server-side repair moves DETAIL-only codes there).
        ErrorCase(name: "add_club_rail_item duplicate with its code in HINT (and DETAIL): the code reaches the views",
                  rpc: "add_club_rail_item",
                  response: ClubJSON.error(message: "Duplicate rail item", code: "23505", details: "DUPLICATE_ITEM",
                                           hint: "DUPLICATE_ITEM", status: 409),
                  expected: .duplicateItem, isMembershipLoss: false),
        ErrorCase(name: "fetch_club_bundle NOT_A_MEMBER in HINT with a prose message -> membership loss",
                  rpc: "fetch_club_bundle",
                  response: ClubJSON.error(message: "You are no longer a member of this club", hint: "NOT_A_MEMBER"),
                  expected: .notAMember, isMembershipLoss: true),
        ErrorCase(name: "prose HINT is never read as a membership-loss code",
                  rpc: "fetch_club_bundle",
                  response: ClubJSON.error(message: "Try again later", hint: "not a member? ask for an invite"),
                  expected: .other(message: "Try again later"), isMembershipLoss: false),
    ]

    @Test("Server error answers reach the caller as the classified ClubError (no SDK error type), and a membership loss of the addressed club revokes it",
          arguments: errorCases)
    func errorCodeMapping(errorCase: ErrorCase) async throws {
        let harness = try ClubsHarness { request in
            request.resource == "rpc/\(errorCase.rpc)" ? errorCase.response : .emptyArray
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        let epoch = clubs.revocationEpoch("club-1")
        let thrown: Error?
        do {
            switch errorCase.rpc {
            case "fetch_club_bundle": _ = try await clubs.fetchClubBundle(clubId: "club-1")
            case "cast_club_vote": try await clubs.castVote(pollId: "poll-1", optionId: "opt-1")
            case "leave_club": try await clubs.leaveClub(clubId: "club-1")
            default: _ = try await clubs.addRailItem(railId: "rail-1", mediaType: "ANIME", mediaId: 101)
            }
            thrown = nil
        } catch {
            thrown = error
        }
        #expect(!(thrown is PostgrestError), "an SDK error crossed the Clubs boundary")
        let error = try #require(thrown as? ClubError, "\(String(describing: thrown))")
        #expect(error == errorCase.expected)
        #expect(error.isMembershipLoss == errorCase.isMembershipLoss)
        // Only requests addressed to club-1 by id resolve their club (the vote's poll and the item's rail
        // are not in a cached bundle here).
        let addressesTheClub = errorCase.rpc == "fetch_club_bundle" || errorCase.rpc == "leave_club"
        #expect((clubs.revocationEpoch("club-1") != epoch) == (errorCase.isMembershipLoss && addressesTheClub))
        await harness.tearDown()
    }

    struct CarrierCase: Sendable, CustomTestStringConvertible {
        let name: String
        let error: PostgrestError
        let expected: ClubError
        var testDescription: String { name }
    }

    /// The token rule of the one classifier, for every carrier (detail, hint, message).
    nonisolated static let carrierCases: [CarrierCase] = [
        CarrierCase(name: "detail DUPLICATE_ITEM", error: PostgrestError(detail: "DUPLICATE_ITEM", message: "Duplicate rail item"), expected: .duplicateItem),
        CarrierCase(name: "detail RAIL_LOCKED", error: PostgrestError(detail: " RAIL_LOCKED ", message: "Rail is locked"), expected: .railLocked),
        CarrierCase(name: "hint NOT_A_MEMBER", error: PostgrestError(hint: "NOT_A_MEMBER", message: "Not a club member"), expected: .notAMember),
        CarrierCase(name: "message token before ':'", error: PostgrestError(message: "NOT_A_MEMBER: removed by an admin"), expected: .notAMember),
        // The store's former rule upper-cased the token (this read as NOT_A_MEMBER and revoked the club);
        // codes are upper-case identifiers, so the one classifier matches case-sensitively. Documented
        // divergence on an answer the server never sends (ClubErrorTests.revocationDivergence).
        CarrierCase(name: "lower-case token is prose, not a code", error: PostgrestError(message: "not_a_member: removed by an admin"),
                    expected: .other(message: "not_a_member: removed by an admin")),
        CarrierCase(name: "prose message only", error: PostgrestError(message: "Not a club member"), expected: .other(message: "Not a club member")),
    ]

    @Test("Error-code lookup reads detail, hint and message with the token rule", arguments: carrierCases)
    func errorCodeCarriers(carrier: CarrierCase) {
        #expect(ClubError(carrier.error) == carrier.expected)
    }

    @Test("Failure contract: URLError, CancellationError (an answer the store dropped) and ClubError leave unchanged; an SDK error is classified")
    func boundaryKeepsTransportAndCancellation() throws {
        let timeout = try #require(ClubsStore.boundaryError(URLError(.timedOut)) as? URLError)
        #expect(timeout.code == .timedOut)
        #expect(ClubsStore.boundaryError(CancellationError()) is CancellationError)
        #expect(ClubsStore.boundaryError(ClubError.pollClosed) as? ClubError == .pollClosed)
        #expect(ClubsStore.boundaryError(PostgrestError(code: "P0001", message: "NOT_A_MEMBER")) as? ClubError == .notAMember)
        let configuration = MissingSupabaseConfiguration()
        #expect(ClubsStore.boundaryError(configuration) as? ClubError == .other(message: configuration.localizedDescription))
    }

    enum Method: String, CaseIterable, Sendable {
        case createClub, joinClub, leaveClub, fetchClubBundle, fetchClubBundleLoading, refreshClubBundle,
             addRailItem, castVote, createClubRail, createClubPoll, toggleReaction
    }

    enum Failure: String, CaseIterable, Sendable {
        /// A coded server answer (PostgREST JSON: the SDK's `PostgrestError`).
        case codedAnswer
        /// A non-JSON error page (the SDK's `HTTPError`).
        case errorPage
        /// A transport failure (`URLError`).
        case offline
    }

    @MainActor
    static func call(_ method: Method, on clubs: ClubsStore) async throws {
        switch method {
        case .createClub: _ = try await clubs.createClub(name: "Night Owls")
        case .joinClub: _ = try await clubs.joinClub(inviteCode: "AB12CD34")
        case .leaveClub: try await clubs.leaveClub(clubId: "club-1")
        case .fetchClubBundle: _ = try await clubs.fetchClubBundle(clubId: "club-1")
        case .fetchClubBundleLoading: _ = try await clubs.fetchClubBundleLoading(clubId: "club-1")
        case .refreshClubBundle: _ = try await clubs.refreshClubBundle(clubId: "club-1")
        case .addRailItem: _ = try await clubs.addRailItem(railId: "rail-1", mediaType: "ANIME", mediaId: 101)
        case .castVote: try await clubs.castVote(pollId: "poll-1", optionId: "opt-1")
        case .createClubRail: _ = try await clubs.createClubRail(clubId: "club-1", title: "Winter")
        case .createClubPoll: _ = try await clubs.createClubPoll(clubId: "club-1", question: "Next?", options: ["A", "B"])
        case .toggleReaction: _ = try await clubs.toggleReaction(railItemId: "item-1", emoji: "fire")
        }
    }

    @Test("Failure contract (G3): every throwing method throws a ClubError for a server answer and for an SDK error page; a transport failure stays a URLError; no SDK error type crosses the boundary",
          arguments: Method.allCases)
    func everyMethodThrowsClubErrors(method: Method) async throws {
        for failure in Failure.allCases {
            let harness = try ClubsHarness { request in
                guard request.resource?.hasPrefix("rpc/") == true, request.resource != "rpc/fetch_my_clubs_loading" else {
                    return .emptyArray
                }
                switch failure {
                case .codedAnswer: return ClubJSON.error(message: "RATE_LIMITED")
                case .errorPage: return .text("Bad Gateway", status: 502)
                case .offline: return .failure(.notConnectedToInternet)
                }
            }
            await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
            var thrown: (any Error)?
            do {
                try await Self.call(method, on: harness.clubs)
            } catch {
                thrown = error
            }
            #expect(!(thrown is PostgrestError), "\(failure): an SDK error crossed the Clubs boundary: \(String(describing: thrown))")
            switch failure {
            case .codedAnswer:
                #expect(thrown as? ClubError == .rateLimited, "\(failure): \(String(describing: thrown))")
            case .errorPage:
                // The SDK's `HTTPError` (not importable here: `Helpers` is not re-exported) is classified.
                let other = thrown as? ClubError
                #expect(other != nil && other?.isMembershipLoss == false, "\(failure): \(String(describing: thrown))")
                if case .other = other {} else { Issue.record("\(failure): \(String(describing: thrown))") }
            case .offline:
                #expect((thrown as? URLError)?.code == .notConnectedToInternet, "\(failure): \(String(describing: thrown))")
            }
            await harness.tearDown()
        }
    }
}

// MARK: - Realtime serialization (fix round 1)

@MainActor
@Suite("Clubs: realtime serialization", .timeLimit(.minutes(1)))
struct ClubsRealtimeSerializationTests {
    static let userA = LifecycleFixtures.userA

    @Test("Same user signs in again and reopens the club before the funnel's teardown ran: the old channel is left first, the funnel's late teardown never touches the new one")
    func resubscribeWaitsForThePendingTeardown() async throws {
        let harness = try ClubsHarness()
        let service = harness.service
        let realtime = harness.clubs.realtime
        let channels = harness.channels
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        await realtime.subscribe(clubId: "club-1")
        let first = try #require(channels.made.first)
        let slowLeave = StubGate()
        first.teardownGate = slowLeave

        // Sign-out: the synchronous half detaches the channel; the tail (its removal) has not run yet.
        let ended = service.session.endSessionState()
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        // The club screen opens again (same topic `kuro.club.club-1`: the SDK would hand back the
        // still-registered channel).
        let reopen = Task.immediate { @MainActor in await realtime.subscribe(clubId: "club-1") }
        #expect(channels.made.count == 1, "a channel was made while the old one of the same topic was still registered")

        slowLeave.open()
        await reopen.value
        #expect(channels.log == ["made club-1#1", "left club-1#1", "made club-1#2"])
        // The funnel's tail runs late: it joins the finished removal and leaves the new channel alone.
        await service.session.finishSessionEnd(ended)
        let second = try #require(channels.made.last)
        #expect(second.isOpen && second.isSubscribed)
        #expect(first.unsubscribeCount == 1)
        #expect(realtime.subscribedClubId == "club-1")
        await harness.tearDown()
    }

    enum Second: String, CaseIterable, Sendable { case sameClub, otherClub }

    @Test("Two subscribes in flight at once leave exactly one open channel: the later request wins, nothing leaks",
          arguments: Second.allCases)
    func concurrentSubscribesOpenOneChannel(second: Second) async throws {
        let harness = try ClubsHarness()
        let realtime = harness.clubs.realtime
        let channels = harness.channels
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await realtime.subscribe(clubId: "club-0")
        let slowLeave = StubGate()
        try #require(channels.made.first).teardownGate = slowLeave

        // Opening club-1 waits for club-0's channel to be left; a second open arrives meanwhile.
        let firstOpen = Task.immediate { @MainActor in await realtime.subscribe(clubId: "club-1") }
        let target = second == .sameClub ? "club-1" : "club-2"
        let secondOpen = Task.immediate { @MainActor in await realtime.subscribe(clubId: target) }
        slowLeave.open()
        await firstOpen.value
        await secondOpen.value

        #expect(realtime.subscribedClubId == target)
        #expect(channels.made.filter(\.isOpen).map(\.clubId) == [target], "\(channels.log)")
        #expect(channels.made.filter { $0.clubId == target }.count == 1, "\(channels.log)")
        await harness.tearDown()
    }

    enum Superseder: String, CaseIterable, Sendable { case viewStop, revocation }

    @Test("A stop of the club (its view disappeared, or it was revoked) while its subscribe is in flight wins: no channel stays open",
          arguments: Superseder.allCases)
    func stopDuringSubscribeWins(superseder: Superseder) async throws {
        let harness = try ClubsHarness()
        let clubs = harness.clubs
        let realtime = clubs.realtime
        let channels = harness.channels
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await realtime.subscribe(clubId: "club-0")
        let slowLeave = StubGate()
        try #require(channels.made.first).teardownGate = slowLeave

        let open = Task.immediate { @MainActor in await realtime.subscribe(clubId: "club-1") }
        switch superseder {
        case .viewStop: realtime.stop(clubId: "club-1")
        case .revocation: clubs.invalidateClub("club-1")
        }
        slowLeave.open()
        await open.value
        await realtime.teardownTask?.value

        #expect(realtime.subscribedClubId == nil)
        #expect(channels.made.filter(\.isOpen).isEmpty, "\(channels.log)")
        await harness.tearDown()
    }
}

// MARK: - Revocation reaches every entry point (fix round 1)

@MainActor
@Suite("Clubs: revocation counters", .timeLimit(.minutes(1)))
struct ClubsRevocationCounterTests {
    static let userA = LifecycleFixtures.userA

    enum Revocation: String, CaseIterable, Sendable { case leave, removedByAdmin }

    @Test("A my-clubs read answered before the revocation never brings the club back",
          arguments: Revocation.allCases)
    func myClubsReadOfBeforeTheRevocationIsDropped(revocation: Revocation) async throws {
        let slow = StubGate()
        let myClubsCalls = Mutex(0)
        let (lateRead, lateReadArrived) = AsyncStream<Void>.makeStream()
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_my_clubs_loading":
                switch nextCall(myClubsCalls) {
                case 1: return ClubJSON.myClubs(["club-1", "club-2"])
                case 2:
                    // Served before the revocation reached the server, delivered after it.
                    lateReadArrived.yield()
                    return ClubJSON.myClubs(["club-1", "club-2"]).held(by: slow)
                default: return ClubJSON.myClubs(["club-2"])
                }
            case "rpc/fetch_club_bundle":
                return ClubJSON.error(message: "NOT_A_MEMBER")
            case "rpc/leave_club":
                return .json(#"{"success":true}"#)
            default:
                return .emptyArray
            }
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await clubs.fetchMyClubs()
        let staleRead = Task.immediate { @MainActor in await clubs.fetchMyClubs() }
        var arrivals = lateRead.makeAsyncIterator()
        _ = await arrivals.next()

        switch revocation {
        case .leave:
            try await clubs.leaveClub(clubId: "club-1")
        case .removedByAdmin:
            await #expect(throws: ClubError.notAMember) { try await clubs.fetchClubBundle(clubId: "club-1") }
        }
        #expect(clubs.myClubs.map(\.id) == ["club-2"])

        slow.open()
        await staleRead.value
        #expect(clubs.myClubs.map(\.id) == ["club-2"], "the revoked club came back from a read answered before the revocation")
        await harness.tearDown()
    }

    @Test("A loading snapshot answered before the leave is not handed out")
    func loadingSnapshotOfBeforeTheLeaveIsDropped() async throws {
        let slow = StubGate()
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_club_bundle_loading": return StubResponse.json(ClubJSON.bundle(clubId: "club-1")).held(by: slow)
            case "rpc/leave_club": return .json(#"{"success":true}"#)
            default: return .emptyArray
            }
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        let snapshot = Task.immediate { @MainActor in try await clubs.fetchClubBundleLoading(clubId: "club-1") }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/fetch_club_bundle_loading" }
        try await clubs.leaveClub(clubId: "club-1")
        slow.open()
        await #expect(throws: CancellationError.self) { try await snapshot.value }
        await harness.tearDown()
    }

    @Test("Leave and rejoin within one round trip: a vote sent before the leave and answered NOT_A_MEMBER does not revoke the rejoined club")
    func staleMembershipLossDoesNotRevokeTheRejoinedClub() async throws {
        let slow = StubGate()
        let joined = Mutex(false)
        let harness = try ClubsHarness { request in
            let isJoined = joined.withLock { $0 }
            switch request.resource {
            case "rpc/fetch_club_bundle": return .json(ClubJSON.bundle(clubId: "club-1"))
            case "rpc/fetch_my_clubs_loading": return ClubJSON.myClubs(isJoined ? ["club-1"] : [])
            case "rpc/cast_club_vote": return ClubJSON.error(message: "NOT_A_MEMBER").held(by: slow)
            case "rpc/leave_club": return .json(#"{"success":true}"#)
            case "rpc/join_club":
                joined.withLock { $0 = true }
                return .json(#"{"club_id":"club-1","club_name":"Club club-1","role":"member"}"#)
            default: return .emptyArray
            }
        }
        let service = harness.service
        let clubs = harness.clubs
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        let staleVote = Task.immediate { @MainActor in try await clubs.castVote(pollId: "poll-club-1", optionId: "opt-club-1") }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/cast_club_vote" }

        try await clubs.leaveClub(clubId: "club-1")
        _ = try await clubs.joinClub(inviteCode: "AB12CD34")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        await clubs.realtime.subscribe(clubId: "club-1")
        service.social.friendTrackingCounts["ANIME-101"] = 2
        let epoch = clubs.revocationEpoch("club-1")

        slow.open()
        // F04: the answer predates the revocation (leave) and belongs to no current membership: it is
        // dropped (`CancellationError`), neither revoking the rejoined club nor reaching a screen.
        await #expect(throws: CancellationError.self) { try await staleVote.value }
        #expect(clubs.myClubs.map(\.id) == ["club-1"], "the rejoined club was revoked by a stale answer")
        #expect(clubs.clubActivityForMedia(mediaId: 101, mediaType: "ANIME").count == 1)
        #expect(clubs.realtime.subscribedClubId == "club-1")
        #expect(service.social.friendTrackingCounts == ["ANIME-101": 2])
        #expect(clubs.revocationEpoch("club-1") == epoch)
        await harness.tearDown()
    }
}

// MARK: - Library changes (fix round 1, G2)

@MainActor
@Suite("Clubs: Library changes", .timeLimit(.minutes(1)))
struct ClubsLibraryChangeTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    static func change(_ key: MediaKey, account: AccountContext) -> LibraryChange {
        LibraryChange(key: key, kind: .updated, previous: nil, current: nil, mutationId: UUID(), account: account)
    }

    static func myStatus(in clubs: ClubsStore, mediaId: Int) -> String? {
        clubs.clubActivityForMedia(mediaId: mediaId, mediaType: "ANIME").first?.matchingItems.first?.item.my_status
    }

    @Test("A list change of a title re-reads the bundles holding it (fresh my_status) without joining a load from before the change; other clubs and the other medium are untouched; the older load's late answer never replaces the fresh one")
    func libraryChangeRefreshesBundlesHoldingTheTitle() async throws {
        let slow = StubGate()
        let club1Calls = Mutex(0)
        let (earlyRead, earlyReadArrived) = AsyncStream<Void>.makeStream()
        let harness = try ClubsHarness { request in
            guard request.resource == "rpc/fetch_club_bundle" else { return .emptyArray }
            guard request.jsonObject?["p_club_id"] as? String == "club-1" else {
                return .json(ClubJSON.bundle(clubId: "club-2", mediaId: 202, myStatus: "PLANNING"))
            }
            switch nextCall(club1Calls) {
            case 1: return .json(ClubJSON.bundle(clubId: "club-1", mediaId: 101, myStatus: "PLANNING"))
            case 2:
                // Served before the list write, delivered after it.
                earlyReadArrived.yield()
                return StubResponse.json(ClubJSON.bundle(clubId: "club-1", mediaId: 101, myStatus: "PLANNING")).held(by: slow)
            default: return .json(ClubJSON.bundle(clubId: "club-1", mediaId: 101, myStatus: "CURRENT"))
            }
        }
        let service = harness.service
        let clubs = harness.clubs
        let sink = ClubsLibrarySink(store: clubs)
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let contextA = try #require(service.accountSession.current)
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        _ = try await clubs.fetchClubBundle(clubId: "club-2")
        let early = Task.immediate { @MainActor in try await clubs.refreshClubBundle(clubId: "club-1") }
        var arrivals = earlyRead.makeAsyncIterator()
        _ = await arrivals.next()

        // Manga 101 is another title: nothing is re-read.
        sink.libraryDidChange(Self.change(MediaKey(kind: .manga, id: 101), account: contextA))
        #expect(clubs.libraryRefreshTask == nil)

        // Anime 101 changed: club-1 (holds it) is re-read with its own request; club-2 is not.
        sink.libraryDidChange(Self.change(MediaKey(kind: .anime, id: 101), account: contextA))
        await clubs.libraryRefreshTask?.value
        #expect(harness.bundleRequests(for: "club-1").count == 3, "\(harness.server.requests)")
        #expect(harness.bundleRequests(for: "club-2").count == 1)
        #expect(Self.myStatus(in: clubs, mediaId: 101) == "CURRENT")
        #expect(Self.myStatus(in: clubs, mediaId: 202) == "PLANNING")

        // F07: the load from before the write answers last. Its caller gets the accepted newest
        // snapshot (never the superseded one), and the cache keeps the fresh one.
        slow.open()
        #expect(try await early.value.rails.first?.items.first?.my_status == "CURRENT",
                "the caller of a superseded load got an older status than the accepted snapshot")
        #expect(Self.myStatus(in: clubs, mediaId: 101) == "CURRENT", "an answer from before the write replaced the fresh bundle")
        await harness.tearDown()
    }

    @Test("F07: a club write's post-write refresh never joins a load started before the write: it reads after the write, and the pre-write load answering last cannot replace it")
    func postWriteRefreshNeverReturnsAPreWriteBundle() async throws {
        let slow = StubGate()
        let calls = Mutex(0)
        let (pullRead, pullReadArrived) = AsyncStream<Void>.makeStream()
        let harness = try ClubsHarness { request in
            if request.resource == "rpc/cast_club_vote" { return .json(#"{"success":true}"#) }
            guard request.resource == "rpc/fetch_club_bundle" else { return .emptyArray }
            switch nextCall(calls) {
            case 1: return .json(ClubJSON.bundle(clubId: "club-1", myStatus: "PLANNING"))
            case 2:
                pullReadArrived.yield()
                return StubResponse.json(ClubJSON.bundle(clubId: "club-1", myStatus: "PLANNING")).held(by: slow)
            default: return .json(ClubJSON.bundle(clubId: "club-1", myStatus: "COMPLETED"))
            }
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        // A pull-to-refresh is in flight (its answer held) when the vote is cast.
        let pull = Task.immediate { @MainActor in try await clubs.refreshClubBundle(clubId: "club-1") }
        var arrivals = pullRead.makeAsyncIterator()
        _ = await arrivals.next()
        try await clubs.castVote(pollId: "poll-club-1", optionId: "opt-club-1")
        // The screen's post-write refresh (ClubDetailView.voteOnPoll).
        let postWrite = Task.immediate { @MainActor in try await clubs.refreshClubBundle(clubId: "club-1") }

        slow.open()
        _ = try await pull.value
        let fresh = try await postWrite.value
        #expect(fresh.rails.first?.items.first?.my_status == "COMPLETED",
                "the post-write refresh joined a load from before the write")
        #expect(harness.bundleRequests(for: "club-1").count == 3)
        #expect(Self.myStatus(in: clubs, mediaId: 101) == "COMPLETED", "a pre-write answer replaced the post-write bundle")
        await harness.tearDown()
    }

    @Test("A Library change delivered for an ended account touches nothing of the next account")
    func libraryChangeOfEndedAccountIsIgnored() async throws {
        let harness = try ClubsHarness { request in
            guard request.resource == "rpc/fetch_club_bundle" else { return .emptyArray }
            return .json(ClubJSON.bundle(clubId: "club-1", mediaId: 101, myStatus: "CURRENT"))
        }
        let service = harness.service
        let clubs = harness.clubs
        let sink = ClubsLibrarySink(store: clubs)
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let contextA = try #require(service.accountSession.current)
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        let keyB = ClubsStore.BundleKey(context: service.accountSession.current, clubId: "club-1")
        let storedAt = try #require(clubs.clubBundleCache[keyB]?.storedAt)

        sink.libraryDidChange(Self.change(MediaKey(kind: .anime, id: 101), account: contextA))
        await clubs.libraryRefreshTask?.value
        #expect(clubs.libraryRefreshTask == nil)
        #expect(clubs.clubBundleCache[keyB]?.storedAt == storedAt, "B's bundle was expired by A's change")
        #expect(harness.bundleRequests(for: "club-1").count == 1)
        await harness.tearDown()
    }
}
