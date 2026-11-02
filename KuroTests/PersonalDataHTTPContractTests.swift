//
//  PersonalDataHTTPContractTests.swift
//  KuroTests
//
//  Releases, ProviderAvailability and SocialActivity owners asserted on the HTTP requests the real
//  supabase-swift client emits (StubPostgREST: in-process, no network) and on what they publish
//  across account transitions. Stale-account answers are tested both ways: cancelled by the session
//  funnel (`server.stoppedRequests`) and delivered after another account became current (only the
//  captured `AccountContext` protects). Each test is named by the risk it covers. ReminderDelivery is covered
//  by the E3 sink tests (LibraryFacadeTests: re-arm on update, manga never, removal cancels also for
//  an untracked title; N1) and AccountLifecycleTests (PendingReminderTests); the typed provider note
//  by ProviderAvailabilityNoteTests (KuroTests.swift).
//

import Testing
import Foundation
import KuroCore
import Synchronization
@testable import Kuro

// MARK: - Releases

@MainActor
@Suite("Personal data: Releases", .timeLimit(.minutes(1)))
struct ReleasesContractTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    /// A `user_airing_next` row: `animeId` airs in `hours`.
    nonisolated static func upcoming(_ animeId: Int, inHours hours: Double) -> StubResponse {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(hours * 3_600))
        return .json(#"[{"anime_id":\#(animeId),"title_english":"Show \#(animeId)","title_romaji":null,"next_episode_number":3,"next_airing_at":"\#(at)"}]"#)
    }

    @Test("Request regression: a cold start reads user_airing_next once for the account (concurrent callers join); a call inside the throttle window issues none")
    func coldStartReadsUpcomingOnce() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "user_airing_next" ? Self.upcoming(42, inHours: 5) : .emptyArray
        }
        let service = harness.service
        let releases = service.releases
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        // The session bootstrap and a mounting screen ask at the same time.
        let bootstrap = Task.immediate { @MainActor in await releases.fetchUpcomingForUser(days: 7) }
        let screen = Task.immediate { @MainActor in await releases.fetchUpcomingForUser(days: 7) }
        await bootstrap.value
        await screen.value

        let requests = harness.requests(to: "user_airing_next")
        #expect(requests.count == 1, "\(requests)")
        let request = try #require(requests.first)
        // Filtered by the single user-id decision point (UserIdText), one week ahead, soonest first.
        #expect(request.query("user_id") == "eq.\(Self.userA.lowercased())")
        let window = request.queryItems.filter { $0.name == "next_airing_at" }.compactMap(\.value)
        #expect(window.count == 2 && window[0].hasPrefix("gte.") && window[1].hasPrefix("lt."), "\(window)")
        #expect(request.query("order") == "next_airing_at.asc.nullslast")
        #expect(request.query("limit") == "500")
        #expect(releases.upcomingAirings.map(\.anime_id) == [42])
        #expect(releases.countdownByAnimeId[42] != nil)

        // Inside the 20 s throttle window: served as is, no request.
        await releases.fetchUpcomingForUser(days: 7)
        #expect(harness.requests(to: "user_airing_next").count == 1)
        await harness.tearDown()
    }

    @Test("A -> B: A's late upcoming answer never lands in B's schedule; B runs its own request")
    func lateUpcomingOfPreviousAccountIsDropped() async throws {
        let slow = StubGate()
        let harness = try PublicDataHarness { request in
            guard request.resource == "user_airing_next" else { return .emptyArray }
            switch request.query("user_id") {
            case "eq.\(Self.userA.lowercased())": return Self.upcoming(101, inHours: 5).held(by: slow)
            case "eq.\(Self.userB.lowercased())": return Self.upcoming(202, inHours: 9)
            default: return .emptyArray
            }
        }
        let service = harness.service
        let releases = service.releases
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let fetchA = Task.immediate { @MainActor in await releases.fetchUpcomingForUser(days: 14) }
        _ = await harness.server.waitForRequest { $0.resource == "user_airing_next" }
        #expect(releases.lastUpcomingDays == 14)

        // B signs in while A's request is still in flight: the funnel cancels it (the held answer is
        // never delivered) and resets the throttle state; B's own fetch is neither throttled nor
        // joined to A's.
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        let stopped = await harness.server.waitForStop { $0.resource == "user_airing_next" }
        #expect(stopped.query("user_id") == "eq.\(Self.userA.lowercased())")
        #expect(releases.lastUpcomingDays == 7)
        await releases.fetchUpcomingForUser(days: 7)
        slow.open()
        await fetchA.value

        #expect(harness.requests(to: "user_airing_next").map { $0.query("user_id") }
                == ["eq.\(Self.userA.lowercased())", "eq.\(Self.userB.lowercased())"])
        #expect(releases.upcomingAirings.map(\.anime_id) == [202])
        #expect(Array(releases.countdownByAnimeId.keys) == [202])
        #expect(releases.upcomingBackoff.failures == 0)
        #expect(harness.server.stoppedRequests.count == 1)
        await harness.tearDown()
    }

    enum Outcome: String, CaseIterable, Sendable { case success, failure }

    @Test("Stale guard: A's upcoming answer that arrives after B became current (nothing cancelled it) publishes nothing and records no backoff",
          arguments: Outcome.allCases)
    func lateUpcomingIsRejectedByItsContext(outcome: Outcome) async throws {
        let slow = StubGate()
        let harness = try PublicDataHarness { request in
            guard request.resource == "user_airing_next" else { return .emptyArray }
            switch outcome {
            case .success: return Self.upcoming(101, inHours: 5).held(by: slow)
            case .failure: return StubResponse.json(#"{"message":"unavailable"}"#, status: 503).held(by: slow)
            }
        }
        let service = harness.service
        let releases = service.releases
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let fetchA = Task.immediate { @MainActor in await releases.fetchUpcomingForUser(days: 7) }
        _ = await harness.server.waitForRequest { $0.resource == "user_airing_next" }

        // B becomes current WITHOUT the funnel's cancel: A's request stays in flight and its answer
        // (rows or an error) is delivered; only the context A's fetch captured protects B.
        _ = service.accountSession.begin(userId: Self.userB)
        slow.open()
        await fetchA.value

        #expect(harness.server.stoppedRequests.isEmpty, "the answer was delivered, not cancelled")
        #expect(releases.upcomingAirings.isEmpty)
        #expect(releases.countdownByAnimeId.isEmpty)
        #expect(releases.lastUpcomingFetchAt == nil)
        #expect(releases.upcomingBackoff.failures == 0 && releases.upcomingBackoff.until == nil)
        await harness.tearDown()
    }

    @Test("Countdown timer: stopped by the session end and by a switch; a late start for an ended account never re-arms it")
    func countdownTimerStopsAndStaysStopped() async throws {
        let harness = try PublicDataHarness()
        let service = harness.service
        let releases = service.releases

        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let contextA = try #require(service.accountSession.current)
        releases.startCountdownUpdates(for: contextA)
        let timerA = try #require(releases.countdownTimer)
        #expect(timerA.isValid)

        await service.session.endSession()
        #expect(releases.countdownTimer == nil)
        #expect(!timerA.isValid)
        // A's bootstrap finishes late and asks for the countdown: refused.
        releases.startCountdownUpdates(for: contextA)
        #expect(releases.countdownTimer == nil)

        // B signs in: A's late start is still refused, B's own start runs.
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        releases.startCountdownUpdates(for: contextA)
        #expect(releases.countdownTimer == nil)
        let contextB = try #require(service.accountSession.current)
        releases.startCountdownUpdates(for: contextB)
        let timerB = try #require(releases.countdownTimer)

        // A direct switch away from B stops B's timer too.
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        #expect(releases.countdownTimer == nil)
        #expect(!timerB.isValid)
        await harness.tearDown()
    }
}

// MARK: - Provider availability

@MainActor
@Suite("Personal data: Provider availability", .timeLimit(.minutes(1)))
struct ProviderAvailabilityContractTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    nonisolated static let availabilityBatch = """
        [{"media_type":"ANIME","media_id":42,"providers":[{"slug":"crunchyroll","display_name":"Crunchyroll",
          "url":null,"languages":["ja","en"],"audio_languages":["ja","en"],"subtitle_languages":["en","de"],
          "countries_by_audio_lang":{"en":["US"]},"countries_by_sub_lang":{"de":["DE"]},"is_stale":false}]}]
        """
    nonisolated static let missingStatus = #"[{"has_rows":false,"status":"missing","last_refreshed_at":null,"next_refresh_at":null,"stale_days":null}]"#
    nonisolated static let registry = #"[{"slug":"crunchyroll","display_name":"Crunchyroll","media_types":["ANIME"],"priority":1,"is_active":true}]"#
    static let publicResources: Set<String> = [
        "rpc/batch_provider_availability_for_media_v2", "rpc/get_media_availability_status",
        "rpc/enqueue_media_availability_refresh", "streaming_services",
    ]

    nonisolated static func clubShared(_ slug: String) -> StubResponse {
        .json(#"{"shared_services":[{"slug":"\#(slug)","display_name":"\#(slug)"}],"member_count_total":2,"member_count_with_services":2,"coverage_pct":100}"#)
    }

    @Test("Public caches: warm reads and a cooled-down refresh enqueue issue no request, and survive sign-out and a new account")
    func publicCachesStayWarmAcrossAccounts() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/batch_provider_availability_for_media_v2": return .json(Self.availabilityBatch)
            case "rpc/get_media_availability_status": return .json(Self.missingStatus)
            case "rpc/enqueue_media_availability_refresh": return .json("true")
            case "streaming_services": return .json(Self.registry)
            default: return .emptyArray
            }
        }
        let service = harness.service
        let availability = service.availability
        func publicRequests() -> Int {
            harness.server.requests.filter { Self.publicResources.contains($0.resource ?? "") }.count
        }
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        await availability.fetchStreamingServiceRegistry()
        await availability.fetchProviderAvailabilityV2(items: [(mediaType: "ANIME", mediaId: 42)])
        #expect(await availability.enqueueAvailabilityRefreshIfStale(mediaType: "ANIME", mediaId: 42))
        let cold = publicRequests()
        #expect(cold == 4, "\(harness.server.requests)")

        func readWarm(_ moment: Comment) async {
            #expect(availability.providerAvailability(mediaId: 42, mediaType: "anime").map(\.slug) == ["crunchyroll"], moment)
            #expect(availability.providers(mediaId: 42, mediaType: "ANIME").map(\.slug) == ["crunchyroll"], moment)
            #expect(availability.bestProviderDisplayName(mediaId: 42, mediaType: "ANIME") == "Crunchyroll", moment)
            #expect(availability.collectionItemsAvailableOn(slug: "crunchyroll") == ["ANIME-42"], moment)
            #expect(availability.streamingServiceRegistry.map(\.slug) == ["crunchyroll"], moment)
            #expect(await availability.enqueueAvailabilityRefreshIfStale(mediaType: "ANIME", mediaId: 42) == false, moment)
            #expect(publicRequests() == cold, moment)
        }
        await readWarm("warm, signed in")
        await service.session.endSession()
        await readWarm("after sign-out")
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        await readWarm("after another account signed in")
        await harness.tearDown()
    }

    @Test("Private: A's services and club-shared providers are cleared on A -> B; A's late answers never publish")
    func privateSelectionIsAccountScoped() async throws {
        let slow = StubGate()
        let serviceReads = Mutex(0)
        // Signalled when A's second (slow) services read reaches the server.
        let (secondRead, secondReadArrived) = AsyncStream<Void>.makeStream()
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "user_streaming_services":
                // No user filter (RLS): answers are told apart by order.
                let call = serviceReads.withLock { count in
                    count += 1
                    return count
                }
                switch call {
                case 1: return .json(#"[{"service":"netflix"}]"#)
                case 2:
                    secondReadArrived.yield()
                    return StubResponse.json(#"[{"service":"hidive"}]"#).held(by: slow)
                default: return .json(#"[{"service":"crunchyroll"}]"#)
                }
            case "rpc/club_shared_providers":
                let late = request.jsonObject?["p_club_id"] as? String == "club-late"
                return late ? Self.clubShared("hidive").held(by: slow) : Self.clubShared("netflix")
            default:
                return .emptyArray
            }
        }
        let service = harness.service
        let availability = service.availability
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        await availability.fetchUserStreamingServices()
        #expect(availability.userStreamingServices == ["netflix"])
        #expect(await availability.fetchClubSharedProviders(clubId: "club-a") != nil)
        #expect(availability.clubSharedProvidersCache.keys.sorted() == ["club-a"])

        // A asks again; both answers are slow.
        let lateServices = Task.immediate { @MainActor in await availability.fetchUserStreamingServices() }
        let lateClub = Task.immediate { @MainActor in await availability.fetchClubSharedProviders(clubId: "club-late") }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/club_shared_providers"
            && $0.jsonObject?["p_club_id"] as? String == "club-late" }
        var secondReads = secondRead.makeAsyncIterator()
        _ = await secondReads.next()

        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(availability.userStreamingServices.isEmpty)
        #expect(availability.clubSharedProvidersCache.isEmpty)

        // A's answers are delivered now (nothing cancelled them): the captured context drops them.
        slow.open()
        await lateServices.value
        #expect(await lateClub.value == nil)
        #expect(availability.userStreamingServices.isEmpty)
        #expect(availability.clubSharedProvidersCache.isEmpty)

        // B reads its own selection.
        await availability.fetchUserStreamingServices()
        #expect(availability.userStreamingServices == ["crunchyroll"])
        #expect(harness.requests(to: "user_streaming_services").count == 3)
        await harness.tearDown()
    }

    @Test("invalidateClubSharedProviders(clubId:) (club revocation, same account) drops that club's aggregate; its in-flight read does not refill it; other clubs keep theirs")
    func clubInvalidationDropsOnlyThatClub() async throws {
        let slow = StubGate()
        let clubXReads = Mutex(0)
        // Signalled when the second (slow) read of club X reaches the server.
        let (secondRead, secondReadArrived) = AsyncStream<Void>.makeStream()
        let harness = try PublicDataHarness { request in
            guard request.resource == "rpc/club_shared_providers" else { return .emptyArray }
            guard request.jsonObject?["p_club_id"] as? String == "club-x" else { return Self.clubShared("netflix") }
            let call = clubXReads.withLock { count in
                count += 1
                return count
            }
            guard call == 2 else { return Self.clubShared("crunchyroll") }
            secondReadArrived.yield()
            return Self.clubShared("hidive").held(by: slow)
        }
        let service = harness.service
        let availability = service.availability
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        #expect(await availability.fetchClubSharedProviders(clubId: "club-x") != nil)
        #expect(await availability.fetchClubSharedProviders(clubId: "club-y") != nil)

        let lateX = Task.immediate { @MainActor in await availability.fetchClubSharedProviders(clubId: "club-x") }
        var secondReads = secondRead.makeAsyncIterator()
        _ = await secondReads.next()

        // The caller leaves club X (or is removed) while X's read is in flight.
        availability.invalidateClubSharedProviders(clubId: "club-x")
        #expect(availability.clubSharedProvidersCache["club-x"] == nil)
        slow.open()
        #expect(await lateX.value == nil, "the revoked club's late read is not handed out")
        #expect(harness.server.stoppedRequests.isEmpty, "the answer was delivered, not cancelled")
        #expect(availability.clubSharedProvidersCache["club-x"] == nil)
        #expect(availability.clubSharedProvidersCache["club-y"]?.shared_services.map(\.slug) == ["netflix"])

        // A read started after the invalidation (e.g. the user rejoined) caches again.
        #expect(await availability.fetchClubSharedProviders(clubId: "club-x")?.shared_services.map(\.slug) == ["crunchyroll"])
        #expect(availability.clubSharedProvidersCache["club-x"] != nil)
        await harness.tearDown()
    }
}

// MARK: - Social activity

@MainActor
@Suite("Personal data: Social activity", .timeLimit(.minutes(1)))
struct SocialActivityContractTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    /// `count_friends_tracking`: anime 101 (3 friends) at once, anime 102 (4) held by `slow`,
    /// anime 202 (1) at once.
    static func countsResponder(slow: StubGate) -> StubServer.Responder {
        { request in
            guard request.resource == "rpc/count_friends_tracking",
                  let items = request.jsonObject?["p_items"] as? String else { return .emptyArray }
            if items.contains(#""101""#) { return .json(#"[{"media_type":"ANIME","media_id":101,"count":3}]"#) }
            if items.contains(#""102""#) { return StubResponse.json(#"[{"media_type":"ANIME","media_id":102,"count":4}]"#).held(by: slow) }
            if items.contains(#""202""#) { return .json(#"[{"media_type":"ANIME","media_id":202,"count":1}]"#) }
            return .emptyArray
        }
    }

    static func isCountRequest(for id: Int) -> @Sendable (RecordedRequest) -> Bool {
        { request in
            request.resource == "rpc/count_friends_tracking"
                && (request.jsonObject?["p_items"] as? String)?.contains("\"\(id)\"") == true
        }
    }

    @Test("A -> B: friend counts are emptied and A's prefetch is cancelled; its late answer never lands; B's prefetch runs")
    func transitionEmptiesFriendCounts() async throws {
        let slow = StubGate()
        let harness = try PublicDataHarness(responder: Self.countsResponder(slow: slow))
        let service = harness.service
        let social = service.social
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 101)])
        await social.friendCountPrefetchTask?.value
        #expect(social.friendCount(mediaId: 101, mediaType: "ANIME") == 3)

        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 102)])
        let staleTask = try #require(social.friendCountPrefetchTask)
        _ = await harness.server.waitForRequest(where: Self.isCountRequest(for: 102))

        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(social.friendTrackingCounts.isEmpty)
        #expect(social.friendCountPrefetchTask == nil)
        #expect(staleTask.isCancelled)
        // The cancel reached the request: its held answer is never delivered.
        _ = await harness.server.waitForStop(where: Self.isCountRequest(for: 102))
        #expect(harness.server.stoppedRequests.count == 1)
        slow.open()
        await staleTask.value
        #expect(social.friendTrackingCounts.isEmpty)

        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 202)])
        await social.friendCountPrefetchTask?.value
        #expect(social.friendTrackingCounts == ["ANIME-202": 1])
        await harness.tearDown()
    }

    @Test("Stale guard: A's friend counts that arrive after B became current (nothing cancelled them) are not published")
    func lateFriendCountsAreRejectedByTheirContext() async throws {
        let slow = StubGate()
        let harness = try PublicDataHarness(responder: Self.countsResponder(slow: slow))
        let service = harness.service
        let social = service.social
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 102)])
        let prefetchA = try #require(social.friendCountPrefetchTask)
        _ = await harness.server.waitForRequest(where: Self.isCountRequest(for: 102))

        // B becomes current WITHOUT the funnel's cancel: A's counts are delivered; only the context
        // the prefetch captured protects B.
        _ = service.accountSession.begin(userId: Self.userB)
        slow.open()
        await prefetchA.value

        #expect(!prefetchA.isCancelled)
        #expect(harness.server.stoppedRequests.isEmpty, "the answer was delivered, not cancelled")
        #expect(social.friendTrackingCounts.isEmpty)
        await harness.tearDown()
    }

    @Test("invalidateFriendProjection() (club revocation, same account) empties the counts and drops the in-flight prefetch")
    func invalidationEmptiesFriendCounts() async throws {
        let slow = StubGate()
        let harness = try PublicDataHarness(responder: Self.countsResponder(slow: slow))
        let service = harness.service
        let social = service.social
        await service.session.applySession(userId: Self.userA, email: "a@example.com")

        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 101)])
        await social.friendCountPrefetchTask?.value
        #expect(social.friendCount(mediaId: 101, mediaType: "ANIME") == 3)
        social.prefetchFriendCounts(items: [(mediaType: "ANIME", mediaId: 102)])
        let staleTask = try #require(social.friendCountPrefetchTask)
        _ = await harness.server.waitForRequest(where: Self.isCountRequest(for: 102))

        social.invalidateFriendProjection()
        #expect(social.friendTrackingCounts.isEmpty)
        #expect(social.friendCount(mediaId: 101, mediaType: "ANIME") == 0)
        #expect(social.friendCountPrefetchTask == nil)
        slow.open()
        await staleTask.value
        #expect(social.friendTrackingCounts.isEmpty, "a count from before the revocation must not come back")
        #expect(service.accountSession.current?.userId == Self.userA)
        await harness.tearDown()
    }

    @Test("A's friends' activity for a title that arrives after A -> B is not handed out")
    func lateFriendActivityIsNotHandedOut() async throws {
        let slow = StubGate()
        let harness = try PublicDataHarness { request in
            guard request.resource == "rpc/fetch_friend_activity_for_title" else { return .emptyArray }
            return StubResponse.json(#"{"friends_tracking":[{"user_id":"friend-of-a","display_name":"F","status":"CURRENT","progress":3,"rating":null,"updated_at":null}],"comments":[]}"#).held(by: slow)
        }
        let service = harness.service
        let social = service.social
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let read = Task.immediate { @MainActor in
            try await social.fetchFriendActivityForTitle(mediaType: "ANIME", mediaId: 101)
        }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/fetch_friend_activity_for_title" }

        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        let stopped = await harness.server.waitForStop { $0.resource == "rpc/fetch_friend_activity_for_title" }
        slow.open()
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(stopped.canonicalBody == #"{"p_media_id":101,"p_media_type":"ANIME"}"#,
                "The previous account's exact friend request is canceled by its credential lease.")
        await harness.tearDown()
    }

    /// `fetch_friend_activity_for_title` answers: the first one (sent before the revocation) names the
    /// revoked club's member and is held by `slow`; later ones name only the remaining club's member.
    nonisolated static func activityResponder(slow: StubGate, calls: CallCounter) -> StubServer.Responder {
        { request in
            guard request.resource == "rpc/fetch_friend_activity_for_title" else { return .emptyArray }
            let call = calls.next()
            if call == 1 {
                return StubResponse.json(#"{"friends_tracking":[{"user_id":"revoked-friend","display_name":"F","status":"CURRENT","progress":3,"rating":null,"updated_at":null}],"comments":[{"id":"c-revoked","user_id":"revoked-friend","display_name":"F","text":"from the revoked club","created_at":"2026-10-05","updated_at":"2026-10-05","is_own":false,"up_count":0,"down_count":0,"my_reaction":null}]}"#)
                    .held(by: slow)
            }
            return .json(#"{"friends_tracking":[{"user_id":"kept-friend","display_name":"K","status":"CURRENT","progress":1,"rating":null,"updated_at":null}],"comments":[]}"#)
        }
    }

    @Test("F03: a friends' activity read answered after a club revocation of the SAME account (another club kept) is not handed out; the current friends' activity can be read again")
    func lateRevokedFriendActivityIsNotHandedOut() async throws {
        let slow = StubGate()
        let calls = CallCounter()
        let harness = try PublicDataHarness(responder: Self.activityResponder(slow: slow, calls: calls))
        let service = harness.service
        let social = service.social
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let read = Task.immediate { @MainActor in
            try await social.fetchFriendActivityForTitle(mediaType: "ANIME", mediaId: 101)
        }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/fetch_friend_activity_for_title" }

        // The caller left (or was removed from) one club; it still belongs to another one.
        service.clubs.invalidateClub("revoked-club")
        slow.open()
        await #expect(throws: CancellationError.self, "a response from before the revocation was handed out") {
            try await read.value
        }
        #expect(service.accountSession.current?.userId == Self.userA)

        let current = try await social.fetchFriendActivityForTitle(mediaType: "ANIME", mediaId: 101)
        #expect(current.friends_tracking.map(\.user_id) == ["kept-friend"])
        await harness.tearDown()
    }

    @Test("F04: A's comment write that answers after A -> B is not handed out (success of an ended account)")
    func staleCommentWriteIsNotHandedOut() async throws {
        let slow = StubGate()
        let harness = try PublicDataHarness { request in
            guard request.resource == "rpc/upsert_title_comment" else { return .emptyArray }
            return StubResponse.json(#"{"id":"comment-a","user_id":"account-a","text":"A private draft","created_at":"2026-10-05","updated_at":"2026-10-05"}"#)
                .held(by: slow)
        }
        let service = harness.service
        let social = service.social
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let write = Task.immediate { @MainActor in
            try await social.upsertTitleComment(mediaType: "ANIME", mediaId: 101, text: "A private draft")
        }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/upsert_title_comment" }

        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        slow.open()
        await #expect(throws: CancellationError.self, "A's private write result was handed out after B signed in") {
            _ = try await write.value
        }
        #expect(service.identity.currentUserId == Self.userB)
        await harness.tearDown()
    }
}

// MARK: - Imports: parse snapshot vs tracking changes (F06)

@MainActor
@Suite("Personal data: Imports parse snapshot", .timeLimit(.minutes(1)))
struct ImportsParseSnapshotTests {
    static let userA = LifecycleFixtures.userA

    nonisolated static func isParse(_ request: RecordedRequest) -> Bool {
        request.path.hasSuffix("/functions/v1/concierge-parse")
    }

    /// Parse answers tagged by call: the first (sent before the tracking change) is held by `slow`.
    nonisolated static func parseResponder(slow: StubGate, calls: CallCounter) -> StubServer.Responder {
        { request in
            guard isParse(request) else { return .emptyArray }
            let call = calls.next()
            let body = #"{"success":true,"userId":"parse-\#(call)","items":[]}"#
            return call == 1 ? StubResponse.json(body).held(by: slow) : .json(body)
        }
    }

    @Test("F06: a parse begun before a tracking change neither refills the cache nor reaches the caller; the caller gets a snapshot requested after the change, and a later identical parse is served from that one")
    func preChangeParseIsSuperseded() async throws {
        let slow = StubGate()
        let calls = CallCounter()
        let harness = try PublicDataHarness(responder: Self.parseResponder(slow: slow, calls: calls))
        let imports = harness.service.imports
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        let read = Task.immediate { @MainActor in try await imports.conciergeParse(text: "naruto") }
        _ = await harness.server.waitForRequest(where: Self.isParse)

        // A Library change of the account (applied list write / server-side writer).
        imports.dropTrackingCopies()
        #expect(imports.conciergeParseCache.isEmpty)
        slow.open()
        let result = try await read.value

        #expect(result.userId != "parse-1", "the pre-change snapshot drove the caller's preview")
        #expect(!imports.conciergeParseCache.values.contains { $0.value.userId == "parse-1" },
                "the pre-change snapshot refilled the cache")
        #expect(harness.server.requests.filter(Self.isParse).count == 2)

        // The post-change snapshot is the cached one.
        let again = try await imports.conciergeParse(text: "naruto")
        #expect(again.userId == result.userId)
        #expect(harness.server.requests.filter(Self.isParse).count == 2)
        await harness.tearDown()
    }
}
