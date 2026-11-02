//
//  SharedInfrastructureTests.swift
//  KuroTests
//
//  The shared infrastructure moved out of the former service class (E6c2): the retry helper and timed
//  caches, the injected runtime flags, the transient banner owner and the interaction/outbound
//  telemetry owners (account-scoped offline queue). Requests go through the real SDK client to an
//  in-process stub (StubPostgREST); clocks and sleeps are injected; nothing reaches the network.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

// MARK: - Retry and timed caches

/// What one scripted attempt of the retried operation does.
enum RetryStep: Sendable, CustomStringConvertible {
    case transportFailure(URLError.Code)
    case serverRejection
    case success

    var description: String {
        switch self {
        case .transportFailure(let code): "URLError(\(code.rawValue))"
        case .serverRejection: "HTTP 4xx"
        case .success: "ok"
        }
    }
}

/// A non-transport failure, as a 4xx answer or a decoding error surfaces from the SDK.
struct ScriptedServerRejection: Error, Equatable {}

@MainActor
@Suite("Shared infrastructure: retry and timed caches", .timeLimit(.minutes(1)))
struct RetryAndTimedCacheTests {

    struct RetryCase: Sendable, CustomTestStringConvertible {
        let steps: [RetryStep]
        let attempts: Int
        let backoff: [Duration]
        let outcome: String
        var testDescription: String { "\(steps) -> \(outcome)" }
    }

    static let retryCases: [RetryCase] = [
        RetryCase(steps: [.success], attempts: 1, backoff: [], outcome: "value"),
        RetryCase(steps: [.transportFailure(.timedOut), .success], attempts: 2,
                  backoff: [.milliseconds(500)], outcome: "value"),
        RetryCase(steps: [.transportFailure(.networkConnectionLost), .transportFailure(.timedOut), .success], attempts: 3,
                  backoff: [.milliseconds(500), .milliseconds(1000)], outcome: "value"),
        RetryCase(steps: [.transportFailure(.timedOut), .transportFailure(.timedOut), .transportFailure(.notConnectedToInternet), .success],
                  attempts: 3, backoff: [.milliseconds(500), .milliseconds(1000)], outcome: "URLError(-1009)"),
        RetryCase(steps: [.serverRejection, .success], attempts: 1, backoff: [], outcome: "rejection"),
        RetryCase(steps: [.transportFailure(.timedOut), .serverRejection, .success], attempts: 2,
                  backoff: [.milliseconds(500)], outcome: "rejection"),
    ]

    @Test("withRetry retries URLError only, at most twice, after 500 ms then 1 s; anything else is thrown at once",
          arguments: retryCases)
    func retryPolicy(_ testCase: RetryCase) async {
        var attempts = 0
        var backoff: [Duration] = []
        let outcome: String
        do {
            let value = try await withRetry(sleep: { backoff.append($0) }) { () async throws -> String in
                let step = testCase.steps[attempts]
                attempts += 1
                switch step {
                case .transportFailure(let code): throw URLError(code)
                case .serverRejection: throw ScriptedServerRejection()
                case .success: return "value"
                }
            }
            outcome = value
        } catch let error as URLError {
            outcome = "URLError(\(error.code.rawValue))"
        } catch {
            outcome = error is ScriptedServerRejection ? "rejection" : "\(error)"
        }
        #expect(outcome == testCase.outcome)
        #expect(attempts == testCase.attempts)
        #expect(backoff == testCase.backoff)
    }

    @Test("trimTimedCache keeps the newest maxEntries and evicts the oldest; under the limit it is a no-op")
    func trimEvictsOldest() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var cache: [String: TimedCache<Int>] = [:]
        // Stored in the order a, b, c, d, e (inserted shuffled: eviction follows `storedAt` only).
        for (age, key) in [(2, "c"), (0, "a"), (4, "e"), (1, "b"), (3, "d")] {
            cache[key] = TimedCache(value: age, storedAt: base.addingTimeInterval(Double(age)))
        }
        trimTimedCache(&cache, maxEntries: 5)
        #expect(cache.count == 5)
        trimTimedCache(&cache, maxEntries: 3)
        #expect(Set(cache.keys) == ["c", "d", "e"])
        #expect(cache["e"]?.value == 4, "kept entries keep their values")
    }

    static let bundleJSON = """
        {"anime":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],
         "newly_added":[],"airing_today":[],"current_season":[]},
         "manga":{"essentials":[],"classics":[],"new_to_you":[],"trending":[],"top_rated":[],"newly_added":[]}}
        """

    @Test("TTL: a timed entry younger than its owner's TTL is served without a request; an older one is re-read",
          arguments: [(age: 60.0, requests: 0), (age: 121.0, requests: 1)])
    func ownerTTL(age: Double, requests: Int) async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/discover_bundle" ? .json(Self.bundleJSON) : .emptyArray
        }
        let discovery = harness.service.discovery
        discovery.discoverBundleCache["discover_bundle|anon|30|24"] = TimedCache(
            value: try LifecycleFixtures.decode(DiscoverBundle.self, Self.bundleJSON),
            storedAt: Date().addingTimeInterval(-age)
        )

        let bundle = await discovery.fetchDiscoverBundle(limit: 30, hours: 24)

        #expect(bundle != nil)
        #expect(harness.requests(to: "rpc/discover_bundle").count == requests)
        await harness.tearDown()
    }
}

// MARK: - Runtime flags

/// A flag row as `feature_flags` stores it (and as the local cache keeps it).
func flagRow(_ name: String, enabled: Bool = true, rollout: Int, markets: [String] = []) -> String {
    let marketList = markets.map { "\"\($0)\"" }.joined(separator: ",")
    return #"{"flag_name":"\#(name)","enabled":\#(enabled),"rollout_percentage":\#(rollout),"target_markets":[\#(marketList)],"description":null}"#
}

/// A private defaults suite (removed by `tearDown`).
@MainActor
final class TestDefaults {
    let suiteName = "kuro.tests.shared-infra.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// Seeds the flags cache exactly as `FeatureFlags.saveToCache` writes it.
    func seedFlags(_ rows: [String]) {
        defaults.set(Data("[\(rows.joined(separator: ","))]".utf8), forKey: "com.kuro.featureFlags.cache")
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
@Suite("Shared infrastructure: injected runtime flags", .timeLimit(.minutes(1)))
struct RuntimeFlagsTests {
    static let flag = "kuro_test_rollout_v1"

    struct RolloutCase: Sendable, CustomTestStringConvertible {
        let rollout: Int
        let enabled: Bool
        let expected: [String: Bool]
        var testDescription: String { "\(enabled ? "enabled" : "disabled") \(rollout)%" }
    }

    /// djb2(userId + flag) % 100 for kuro_test_rollout_v1: user-a 76, user-b 30, user-c 75, user-d 20
    /// (pinned from the implementation before the move); a bucket below the rollout is in.
    static let rolloutCases: [RolloutCase] = [
        RolloutCase(rollout: 50, enabled: true,
                    expected: ["user-a": false, "user-b": true, "user-c": false, "user-d": true, "": false]),
        RolloutCase(rollout: 30, enabled: true,
                    expected: ["user-a": false, "user-b": false, "user-c": false, "user-d": true, "": false]),
        RolloutCase(rollout: 0, enabled: true,
                    expected: ["user-a": false, "user-b": false, "user-c": false, "user-d": false, "": false]),
        RolloutCase(rollout: 100, enabled: true,
                    expected: ["user-a": true, "user-b": true, "user-c": true, "user-d": true, "": true]),
        RolloutCase(rollout: 100, enabled: false,
                    expected: ["user-a": false, "user-b": false, "user-c": false, "user-d": false, "": false]),
    ]

    @Test("Stable-hash rollout is unchanged (cached flags, per-user buckets, no user = out below 100%)",
          arguments: rolloutCases)
    func rolloutBuckets(_ testCase: RolloutCase) throws {
        let store = try TestDefaults()
        store.seedFlags([flagRow(Self.flag, enabled: testCase.enabled, rollout: testCase.rollout)])
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        for (user, expected) in testCase.expected.sorted(by: { $0.key < $1.key }) {
            flags.setUserId(user.isEmpty ? nil : user)
            #expect(flags.evaluate(Self.flag) == expected, "user '\(user)'")
        }
        store.tearDown()
    }

    struct OverrideCase: Sendable, CustomTestStringConvertible {
        let arguments: [String]
        let rollout: Int?
        let expected: Bool
        var testDescription: String { "\(arguments) over \(rollout.map { "\($0)%" } ?? "no row")" }
    }

    static let overrideCases: [OverrideCase] = [
        OverrideCase(arguments: ["--ff-on=\(flag)"], rollout: nil, expected: true),
        OverrideCase(arguments: ["--ff-on=\(flag)"], rollout: 0, expected: true),
        OverrideCase(arguments: ["--ff-off=\(flag)"], rollout: 100, expected: false),
        OverrideCase(arguments: ["--ff-off=\(flag)", "--ff-on=\(flag)"], rollout: 0, expected: true),
        OverrideCase(arguments: ["--ff-on=other_flag_v1"], rollout: 100, expected: true),
        OverrideCase(arguments: ["--ff-off=other_flag_v1"], rollout: nil, expected: false),
    ]

    @Test("DEBUG launch-argument overrides win over the server rows, per instance", arguments: overrideCases)
    func debugOverrides(_ testCase: OverrideCase) throws {
        let store = try TestDefaults()
        if let rollout = testCase.rollout { store.seedFlags([flagRow(Self.flag, rollout: rollout)]) }
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: testCase.arguments)
        flags.setUserId("user-a")
        #expect(flags.evaluate(Self.flag) == testCase.expected)
        #expect(!FeatureFlags(userDefaults: store.defaults, launchArguments: []).evaluate("other_flag_v1"),
                "another instance never sees these arguments")
        store.tearDown()
    }

    @Test("Server refresh reads feature_flags and caches into the instance's own store only")
    func refreshCachesIntoInjectedStore() async throws {
        let server = StubServer()
        server.respond { request in
            request.resource == "feature_flags" ? .json("[\(flagRow(Self.flag, rollout: 50))]") : .emptyArray
        }
        let store = try TestDefaults()
        let other = try TestDefaults()
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        #expect(!flags.evaluate(Self.flag))

        await flags.refresh(client: StubSupabase.makeClient(server: server), userId: "user-b")

        let read = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(read.method == "GET" && read.resource == "feature_flags" && read.query("select") == "*")
        #expect(flags.evaluate(Self.flag), "user-b is in the 50% bucket")
        let reloaded = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        reloaded.setUserId("user-b")
        #expect(reloaded.evaluate(Self.flag), "the cache landed in the injected store")
        let isolated = FeatureFlags(userDefaults: other.defaults, launchArguments: [])
        isolated.setUserId("user-b")
        #expect(!isolated.evaluate(Self.flag), "another store never sees it")
        store.tearDown()
        other.tearDown()
        server.shutDown()
    }

    @Test("Owners and the session funnel use the injected instance", arguments: [false, true])
    func ownersReadInjectedFlags(enabled: Bool) async throws {
        let store = try TestDefaults()
        store.seedFlags([flagRow(Self.flag, rollout: 50)])
        let arguments = enabled
            ? ["--ff-on=clubs_realtime_v1", "--ff-on=clubs_notifications_v1", "--ff-on=streaming_availability_v1"]
            : []
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: arguments)
        let server = StubServer()
        server.respond { request in
            request.resource == "rpc/check_club_activity_since" ? .json(#"{"has_activity":false}"#) : .emptyArray
        }
        let channels = FakeClubChannels()
        let service = AppComposition.testingGraph(
            testingUserDefaults: store.defaults,
            notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: server),
            libraryBackend: FakeLibraryBackend(),
            clubChannels: channels,
            clubRefreshDebounce: .zero,
            flags: flags
        )
        #expect(service.flags === flags)

        // Session funnel: the user id for rollout goes to the injected instance (user-b: bucket 30).
        await service.session.applySession(userId: "user-b", email: "b@example.com")
        #expect(flags.evaluate(Self.flag))

        // Owners gate on the injected instance.
        await service.clubs.subscribeToClubUpdates(clubId: "club-1")
        #expect(channels.made.count == (enabled ? 1 : 0))
        await service.clubs.checkClubNotifications()
        #expect(server.requests.filter { $0.resource == "rpc/check_club_activity_since" }.count == (enabled ? 1 : 0))
        #expect(await service.availability.streamingObservabilitySnapshot().isStreamingAvailabilityEnabled == enabled)

        await service.session.endSession()
        #expect(!flags.evaluate(Self.flag), "signed out: no user, out of a partial rollout")
        store.tearDown()
        server.shutDown()
    }
}

// MARK: - Transient banner

/// Sleeps that end only when the test releases them (no wall-clock waits).
@MainActor
final class ManualSleeps {
    private(set) var requested: [Duration] = []
    private var pending: [CheckedContinuation<Void, Never>?] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep(_ delay: Duration) async {
        requested.append(delay)
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            let ready = waiters.filter { $0.count <= pending.count }
            waiters.removeAll { $0.count <= pending.count }
            for waiter in ready { waiter.continuation.resume() }
        }
    }

    /// Ends the `index`-th requested sleep (once it was requested).
    func release(_ index: Int) async {
        if pending.count <= index {
            await withCheckedContinuation { waiters.append((index + 1, $0)) }
        }
        pending[index]?.resume()
        pending[index] = nil
    }
}

@MainActor
@Suite("Shared infrastructure: transient banner", .timeLimit(.minutes(1)))
struct BannerCenterTests {

    @Test("Newest wins at once; a replaced message never clears its successor; each message auto-clears after its duration")
    func newestWinsAndAutoClears() async throws {
        let sleeps = ManualSleeps()
        let banner = BannerCenter(sleep: { await sleeps.sleep($0) })

        banner.show("Added to collection")
        #expect(banner.message == "Added to collection")
        let first = try #require(banner.dismissTask)
        banner.show("Couldn't update list. Try again.")
        #expect(banner.message == "Couldn't update list. Try again.", "newest wins at once")
        let second = try #require(banner.dismissTask)

        await sleeps.release(0)
        await first.value
        #expect(banner.message == "Couldn't update list. Try again.", "the replaced message's wait clears nothing")
        await sleeps.release(1)
        await second.value
        #expect(banner.message == nil, "auto-clear")

        // The same text twice: the first wait ends early and must not cut the second one short.
        banner.show("Signal didn't save — will retry")
        let repeatFirst = try #require(banner.dismissTask)
        banner.show("Signal didn't save — will retry", duration: 4)
        let repeatSecond = try #require(banner.dismissTask)
        await sleeps.release(2)
        await repeatFirst.value
        #expect(banner.message == "Signal didn't save — will retry")
        await sleeps.release(3)
        await repeatSecond.value
        #expect(banner.message == nil)

        #expect(sleeps.requested == [.seconds(2.4), .seconds(2.4), .seconds(2.4), .seconds(4)])
    }
}

// MARK: - Telemetry

/// Scripted connectivity for the analytics queue.
@MainActor
final class ScriptedConnectivity {
    var isOnline = false
}

@MainActor
@Suite("Shared infrastructure: telemetry owners", .timeLimit(.minutes(1)))
struct TelemetryOwnerTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    enum Transition: String, CaseIterable, Sendable { case switchToB, signOut }

    /// `user_id` of every `concierge_events` row the server received ("anon" when absent).
    static func sentEvents(_ server: StubServer) -> [String] {
        server.requests.filter { $0.resource == "concierge_events" }.compactMap { request in
            guard let body = request.body,
                  let json = try? JSONSerialization.jsonObject(with: body) else { return nil }
            let row = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
            guard let row, let event = row["event_name"] as? String else { return nil }
            return "\(event):\(row["user_id"] as? String ?? "anon")"
        }
    }

    @Test("LT-30: an ended account's queued events are dropped; a late flush never sends them under the next login",
          arguments: Transition.allCases)
    func endedAccountEventsAreDropped(transition: Transition) async throws {
        let server = StubServer()
        server.respond { _ in .json("", status: 201) }
        let connectivity = ScriptedConnectivity()
        let client = StubSupabase.makeClient(server: server)
        let telemetry = InteractionTelemetry(
            analytics: ConciergeAnalytics(isConnected: { connectivity.isOnline }),
            client: client
        )
        let store = try TestDefaults()
        let service = AppComposition.testingGraph(
            testingUserDefaults: store.defaults,
            notificationCenter: FakeNotificationCenter(),
            client: client,
            libraryBackend: FakeLibraryBackend(),
            interactionTelemetry: telemetry
        )

        // Offline: an anonymous event, then A's events (attributed to A).
        #expect(telemetry.track("anon_open") == nil, "queued while offline")
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        telemetry.trackInteractionEvent("a_quick_add", surface: "discover", result: "ok")
        telemetry.track("a_parse_completed")

        switch transition {
        case .switchToB:
            await service.session.applySession(userId: Self.userB, email: "b@example.com")
        case .signOut:
            await service.session.endSession()
        }

        // Back online: the reconnect flush, then a new event of whoever is signed in now.
        connectivity.isOnline = true
        for send in telemetry.flushIfNeeded() { await send.value }
        await telemetry.track("after_transition")?.value

        let sent = Self.sentEvents(server)
        #expect(!sent.contains { $0.hasSuffix(":\(Self.userA)") }, "A's events were sent after A ended: \(sent)")
        let now = transition == .switchToB ? Self.userB : "anon"
        #expect(sent.sorted() == ["after_transition:\(now)", "anon_open:anon"], "sent: \(sent)")
        store.tearDown()
        server.shutDown()
    }

    @Test("Same-account events survive a same-user refresh and are flushed under that account")
    func currentAccountEventsAreKept() async throws {
        let server = StubServer()
        server.respond { _ in .json("", status: 201) }
        let connectivity = ScriptedConnectivity()
        let client = StubSupabase.makeClient(server: server)
        let telemetry = InteractionTelemetry(
            analytics: ConciergeAnalytics(isConnected: { connectivity.isOnline }),
            client: client
        )
        let store = try TestDefaults()
        let service = AppComposition.testingGraph(
            testingUserDefaults: store.defaults,
            notificationCenter: FakeNotificationCenter(),
            client: client,
            libraryBackend: FakeLibraryBackend(),
            interactionTelemetry: telemetry
        )
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        telemetry.track("a_event")
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        connectivity.isOnline = true
        for send in telemetry.flushIfNeeded() { await send.value }

        #expect(Self.sentEvents(server) == ["a_event:\(Self.userA)"])
        await service.session.endSession()
        store.tearDown()
        server.shutDown()
    }

    @Test("Outbound link: one record_outbound_link RPC with the tap's fields (no user id from the client)")
    func outboundLinkRequestShape() async throws {
        let server = StubServer()
        server.respond { _ in .json("null") }
        let outbound = OutboundLinkTelemetry(client: StubSupabase.makeClient(server: server))

        await outbound.recordOutboundLink(mediaType: "MANGA", mediaId: 7, linkKind: "read", provider: "mangaplus").value

        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == "POST" && request.resource == "rpc/record_outbound_link")
        #expect(request.canonicalBody == #"{"p_link_kind":"read","p_media_id":7,"p_media_type":"MANGA","p_provider":"mangaplus"}"#)
        server.shutDown()
    }
}

@MainActor
extension RuntimeFlagsTests {
    @Test("Release cohort restores only exact-account bounded offline eligibility and waits for metadata")
    func privateReleaseCohort() async throws {
        let server = StubServer()
        let account = AccountSessionCoordinator()
        let user = UUID().uuidString
        _ = account.begin(userId: user)
        server.respond { request in
            if request.resource == "feature_flags" {
                return .json("[\(flagRow("series_foundation_v1", rollout: 0)),\(flagRow("series_home_native_v1", rollout: 0))]")
            }
            if request.resource == "feature_flag_overrides" {
                return .json("[{\"user_id\":\"\(user.lowercased())\",\"flag_name\":\"series_foundation_v1\",\"enabled\":true},{\"user_id\":\"\(user.lowercased())\",\"flag_name\":\"series_home_native_v1\",\"enabled\":true}]")
            }
            return .emptyArray
        }
        let store = try TestDefaults()
        defer { store.tearDown(); server.shutDown() }
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        await flags.refresh(client: StubSupabase.makeClient(server: server), userId: user, accountSession: account)
        #expect(!flags.seriesHomeNativeV1Enabled, "Home waits for revision metadata even when the tester flags arrived")
        flags.completeFoundationBootstrap(userId: user)
        #expect(flags.seriesHomeNativeV1Enabled)
        #expect(flags.seriesFoundationFenceEnabled())
        let read = try #require(server.requests.first { $0.resource == "feature_flag_overrides" })
        #expect(read.query("user_id") == "eq.\(user.lowercased())")
        let reopened = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        reopened.setUserId(user)
        #expect(!reopened.seriesHomeNativeV1Enabled, "Offline eligibility alone cannot expose Home without valid tracking metadata")
        reopened.completeFoundationBootstrap(userId: user)
        #expect(reopened.seriesHomeNativeV1Enabled)
        reopened.setUserId(UUID().uuidString)
        #expect(!reopened.seriesHomeNativeV1Enabled)
        reopened.removeHomeCohort(for: user)
        let afterDeletion = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        afterDeletion.setUserId(user)
        afterDeletion.completeFoundationBootstrap(userId: user)
        #expect(!afterDeletion.seriesHomeNativeV1Enabled)
        flags.setUserId(UUID().uuidString)
        #expect(!flags.seriesHomeNativeV1Enabled && !flags.seriesFoundationFenceEnabled())
    }

    @Test("Late private flag response from ended account cannot enable Home for new account")
    func staleReleaseCohortResponse() async throws {
        let server = StubServer()
        let gate = StubGate()
        let account = AccountSessionCoordinator()
        let user = UUID().uuidString
        _ = account.begin(userId: user)
        server.respond { request in
            if request.resource == "feature_flags" { return .emptyArray }
            if request.resource == "feature_flag_overrides" {
                return StubResponse.json("[{\"user_id\":\"\(user.lowercased())\",\"flag_name\":\"series_foundation_v1\",\"enabled\":true}]").held(by: gate)
            }
            return .emptyArray
        }
        let store = try TestDefaults()
        defer { store.tearDown(); server.shutDown() }
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        let client = StubSupabase.makeClient(server: server)
        let refresh = Task { await flags.refresh(client: client, userId: user, accountSession: account) }
        _ = await server.waitForRequest { $0.resource == "feature_flag_overrides" }
        let next = UUID().uuidString
        _ = account.begin(userId: next)
        flags.setUserId(next)
        gate.open()
        await refresh.value
        #expect(!flags.seriesFoundationV1Enabled && !flags.seriesFoundationFenceEnabled())
    }
}

@MainActor
extension RuntimeFlagsTests {
    @Test("Queued flags bootstrap from an ended account performs no request or rollout identity change")
    func obsoleteFlagsBootstrapDoesNothing() async throws {
        let server = StubServer()
        server.respond { _ in .emptyArray }
        let account = AccountSessionCoordinator()
        _ = account.begin(userId: "user-b")
        let store = try TestDefaults()
        defer { store.tearDown(); server.shutDown() }
        store.seedFlags([flagRow(Self.flag, rollout: 50)])
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        flags.setUserId("user-b")
        #expect(flags.evaluate(Self.flag))
        await flags.refresh(client: StubSupabase.makeClient(server: server), userId: "user-a", accountSession: account)
        #expect(server.requests.isEmpty)
        #expect(flags.evaluate(Self.flag))
    }
}
