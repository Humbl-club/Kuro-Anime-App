//
//  GuestModeTests.swift
//  KuroTests
//
//  W5 guest browsing (behind `guest_browsing_v1`, 0 %): the root decision, the pending intent and its
//  single replay after sign-up, the signed-out flag read, the read guards, the sign-up gate.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Supabase
@testable import Kuro

@MainActor
@Suite("W5: guest browsing", .timeLimit(.minutes(1)))
struct GuestModeTests {
    static let frieren = MediaKey(kind: .anime, id: 154587)

    static func guestFlags(on: Bool = true) throws -> (flags: FeatureFlags, suite: String, defaults: UserDefaults) {
        let suite = "kuro.tests.guest-flags.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let args = on ? ["--ff-on=guest_browsing_v1"] : []
        return (FeatureFlags(userDefaults: defaults, launchArguments: args), suite, defaults)
    }

    static let flagsOffJSON = #"[{"flag_name":"guest_browsing_v1","enabled":false,"rollout_percentage":0,"target_markets":[]}]"#
    static let flagsOnJSON = #"[{"flag_name":"guest_browsing_v1","enabled":true,"rollout_percentage":100,"target_markets":[]}]"#

    // MARK: Task 2: state and rules

    @Test("The root resolves guest after sign-out only while the switch is on")
    func rootResolvesGuestAfterSignOut() async throws {
        func resolve(config: Bool = false, boot: Bool = false, auth: Bool = false, pw: Bool = false,
                     user: String? = nil, guest: Bool) -> RootPresentation {
            RootPresentation.resolve(configError: config, isBootstrapping: boot, isAuthenticated: auth,
                                     requiresPasswordUpdate: pw, userId: user, guestEnabled: guest)
        }
        #expect(resolve(guest: true) == .guest)
        #expect(resolve(guest: false) == .authWall)
        #expect(resolve(auth: true, user: "u", guest: true) == .signedIn(userId: "u"))
        #expect(resolve(auth: true, pw: true, user: "u", guest: true) == .setPassword)
        #expect(resolve(boot: true, guest: true) == .bootstrapping)
        #expect(resolve(config: true, boot: true, guest: true) == .configError)

        let (flags, suite, defaults) = try Self.guestFlags()
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(), flags: flags)
        await graph.session.endSession()
        #expect(graph.guest.isGuest)
        let (offFlags, offSuite, offDefaults) = try Self.guestFlags(on: false)
        let offGraph = AppComposition.testingGraph(testingUserDefaults: offDefaults, notificationCenter: FakeNotificationCenter(), flags: offFlags)
        #expect(!offGraph.guest.isGuest)
        defaults.removePersistentDomain(forName: suite)
        offDefaults.removePersistentDomain(forName: offSuite)
    }

    @Test("The guest pager mirrors the live order with invitation pages; Browse comes from Discover")
    func guestPagerHasInvitationPages() {
        #expect(GuestPager.order == [.taste, .home, .discover, .collection, .clubs])
        #expect(GuestPager.invitationSections == [.taste, .home, .collection, .clubs])
        #expect(!GuestPager.order.contains(.browse))
    }

    @Test("A sheet teardown after sign-up keeps the intent; a cancelled sheet discards it")
    func intentSurvivesSheetTeardownAfterSignUp() throws {
        let (flags, suite, defaults) = try Self.guestFlags()
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(), flags: flags)
        let intent = PendingGuestIntent.plan(Self.frieren, title: "Frieren")
        graph.guest.begin(intent)
        graph.identity.isAuthenticated = true
        graph.guest.signUpSheetClosed()
        #expect(graph.guest.pendingIntent == intent)
        graph.identity.isAuthenticated = false
        graph.guest.signUpSheetClosed()
        #expect(graph.guest.pendingIntent == nil)
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: Task 3: replay once, discard on cancel, signed-out flag read

    static func signUpResponder() -> StubServer.Responder {
        StubAuth.signInResponder { request in
            StubAuth.isAuth(request, "signup")
                ? .json(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com")) : .emptyArray
        }
    }

    static func signUpResponderRest(_ rest: @escaping StubServer.Responder) -> StubServer.Responder {
        StubAuth.signInResponder { request in
            StubAuth.isAuth(request, "signup")
                ? .json(StubAuth.sessionJSON(StubAuth.userA, email: "a@example.com")) : rest(request)
        }
    }

    @Test("The pending Plan is replayed exactly once after sign-up, with a banner")
    func pendingIntentReplaysOnceAfterSignUp() async throws {
        let backend = FakeLibraryBackend()
        let h = try SessionSDKHarness(responder: Self.signUpResponder(), libraryBackend: backend)
        h.graph.guest.begin(.plan(Self.frieren, title: "Frieren"))
        try await h.session.signUpWithEmail(email: "a@example.com", password: "long-enough")

        #expect(backend.rows(for: StubAuth.userA)[Self.frieren]?.status == .planning)
        func inserts() -> Int {
            backend.writeCalls.filter { if case .insertIfMissing(Self.frieren, _) = $0 { true } else { false } }.count
        }
        #expect(inserts() == 1)
        #expect(h.graph.banner.message == "Added “Frieren” to Planning.")
        #expect(h.graph.guest.pendingIntent == nil)

        // A second bootstrap (the SDK's own `.signedIn`/`initialSession` event) must not replay again.
        await h.session.handleAuthEvent(.initialSession, sessionUserId: StubAuth.userA, email: "a@example.com",
                                        storedSessionUserId: StubAuth.userA)
        let context = try #require(h.graph.accountSession.current)
        await h.graph.guest.replayPendingIntent(for: context)
        #expect(inserts() == 1)
        await h.tearDown()
    }

    @Test("A cancelled sign-up forgets the intent; a later sign-in replays nothing")
    func pendingIntentDiscardedWhenSignUpCancelled() async throws {
        let backend = FakeLibraryBackend()
        let h = try SessionSDKHarness(responder: Self.signUpResponder(), libraryBackend: backend)
        h.graph.guest.begin(.plan(Self.frieren, title: "Frieren"))
        h.graph.guest.signUpSheetClosed()
        #expect(h.graph.guest.pendingIntent == nil)
        try await h.session.signInWithEmail(email: "a@example.com", password: "long-enough")
        await h.graph.libraryActions.libraryRefreshTask?.value
        #expect(backend.writeCalls.isEmpty)
        #expect(h.graph.banner.message == nil)
        await h.tearDown()
    }

    @Test("Signing in to an account that already tracks the title never downgrades it and says so")
    func replayOnTrackedTitleSaysAlreadyInList() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 154587, rowId: 1, status: .current)], for: StubAuth.userA)
        let h = try SessionSDKHarness(responder: Self.signUpResponder(), libraryBackend: backend)
        h.graph.guest.begin(.plan(Self.frieren, title: "Frieren"))
        try await h.session.signInWithEmail(email: "a@example.com", password: "long-enough")
        #expect(backend.rows(for: StubAuth.userA)[Self.frieren]?.status == .current)
        #expect(h.graph.banner.message == "“Frieren” is already in your list.")
        await h.tearDown()
    }

    @Test("Guest browsing switched off: a signed-out launch sends nothing but the flag read and shows the auth wall")
    func flagOffSendsNoRequest() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            request.resource == "feature_flags" ? .json(Self.flagsOffJSON) : .emptyArray
        })
        await h.session.restoreSession()
        #expect(RootPresentation.resolve(
            configError: false, isBootstrapping: false, isAuthenticated: h.identity.isAuthenticated,
            requiresPasswordUpdate: false, userId: nil, guestEnabled: h.graph.flags.guestBrowsingV1Enabled) == .authWall)
        #expect(!h.graph.guest.isGuest)
        let resources = Set(h.server.requests.compactMap(\.resource))
        #expect(resources.isSubset(of: ["feature_flags"]), "unexpected guest requests: \(resources)")
        let context = AccountContext(userId: StubAuth.userA, generation: 1)
        await h.graph.guest.replayPendingIntent(for: context)
        #expect(Set(h.server.requests.compactMap(\.resource)).isSubset(of: ["feature_flags"]))
        await h.tearDown()
    }

    @Test("The signed-out flag read returns within its wait and applies a late answer while still signed out")
    func signedOutLaunchReadsFlagsWithinTheWait() async throws {
        let gate = StubGate()
        let h = try PublicDataHarness(responder: { request in
            request.resource == "feature_flags" ? StubResponse.json(Self.flagsOnJSON).held(by: gate) : .emptyArray
        })
        let flags = h.service.flags
        let client = StubSupabase.makeClient(server: h.server)
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await flags.refreshSignedOut(client: client, accountSession: h.service.accountSession, timeout: .milliseconds(200))
        }
        #expect(elapsed < .seconds(1))
        #expect(!flags.guestBrowsingV1Enabled)
        gate.open()
        await SessionSDKHarness.waitUntil { flags.guestBrowsingV1Enabled }
        #expect(flags.guestBrowsingV1Enabled)
        await h.tearDown()
    }

    @Test("Positive: the replayed Plan goes out through the real list transport once, with the new account's bearer")
    func replayedPlanCarriesTheNewAccountsBearer() async throws {
        let script = ListTablesScript()
        let h = try SessionSDKHarness(
            responder: Self.signUpResponderRest(script.responder()),
            libraryBackendOverClient: { AppComposition.libraryBackend(client: $0, fenceEnabled: { false }) })
        h.graph.guest.begin(.plan(Self.frieren, title: "Frieren"))
        try await h.session.signUpWithEmail(email: "a@example.com", password: "long-enough")
        let writes = h.server.requests.filter { $0.resource == "anime_user_lists" && $0.method != "GET" }
        #expect(writes.count == 1, "\(writes)")
        #expect(writes.first?.bearerSubject == StubAuth.userA.lowercased())
        await h.tearDown()
    }

    @Test("A replay dropped by a pre-dispatch account switch sends nothing as the other account (real list transport)")
    func replayAfterAccountSwitchSendsNothingAsB() async throws {
        let script = ListTablesScript()
        let h = try SessionSDKHarness(
            responder: StubAuth.signInResponder(rest: script.responder()),
            libraryBackendOverClient: { AppComposition.libraryBackend(client: $0, fenceEnabled: { false }) })
        let sessionB = try await CredentialLeaseTests.signedInAsAKeepingBsSession(h)
        let contextA = try #require(h.graph.accountSession.current)
        h.graph.guest.begin(.plan(Self.frieren, title: "Frieren"))
        let writesBefore = h.server.requests.filter { $0.resource == "anime_user_lists" && $0.method != "GET" }.count

        let replay = Task.immediate { @MainActor in await h.graph.guest.replayPendingIntent(for: contextA) }
        // A's replay was admitted; before it dispatches, the SDK installs B's session and the funnel switches to B.
        h.storage.replace(with: sessionB)
        let switching = Task.immediate { @MainActor in
            _ = await h.session.applySession(userId: StubAuth.userB, email: "b@example.com")
        }
        await replay.value
        await switching.value

        let listRequests = h.server.requests.filter { $0.resource == "anime_user_lists" }
        #expect(!listRequests.contains { $0.method != "GET" && $0.bearerSubject == StubAuth.userB.lowercased() },
                "A's Plan was sent with B's credential: \(listRequests)")
        #expect(listRequests.filter { $0.method != "GET" }.count == writesBefore, "A's Plan was dispatched after A ended")
        #expect(h.graph.banner.message == nil)
        #expect(h.graph.guest.pendingIntent == nil)

        // The Discover answer: the lease closure never runs, so nothing is enqueued or sent.
        h.graph.guest.begin(.discoverAnswer(Self.frieren, .notInterested, title: "Frieren"))
        let answer = Task.immediate { @MainActor in await h.graph.guest.replayPendingIntent(for: contextA) }
        await answer.value
        #expect(h.server.requests.filter { $0.resource == "rpc/record_taste_deck_signal" }.isEmpty)
        #expect(h.graph.guest.pendingIntent == nil)
        await h.tearDown()
    }

    // MARK: Task 4: guests read only the allowlist

    static func guestHarness() throws -> PublicDataHarness {
        try PublicDataHarness(responder: { request in
            switch request.resource {
            case "feature_flags": return .json(Self.flagsOffJSON)
            default: return .emptyArray
            }
        })
    }

    static func assertOnlyAllowlistedAnonymousReads(_ h: PublicDataHarness, sourceLocation: SourceLocation = #_sourceLocation) {
        let resources = h.server.requests.compactMap(\.resource)
        let outside = resources.filter { !GuestReadAllowlist.permits(resource: $0) }
        #expect(outside.isEmpty, "a guest requested outside the allowlist: \(outside)", sourceLocation: sourceLocation)
        #expect(h.server.requests.allSatisfy { $0.header("Authorization") == "Bearer \(StubSupabase.anonKey)" },
                "a guest request carried a user credential", sourceLocation: sourceLocation)
    }

    @Test("Guests open title, character and season pages with public catalogue reads only")
    func guestCanOpenTitleEntityAndSeasonPages() async throws {
        let h = try Self.guestHarness()
        let g = h.service
        _ = try? await g.catalog.fetchAnimeById(154587)
        _ = await g.catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 154587)
        _ = await g.catalog.fetchCast(forAnime: 154587)
        _ = await g.catalog.fetchCharactersForAnime(animeId: 154587)
        _ = await g.catalog.fetchStaffForAnime(animeId: 154587)
        _ = await g.catalog.fetchStudiosForAnime(animeId: 154587)
        _ = await g.catalog.fetchEpisodesPage(animeId: 154587, offset: 0, limit: 50)
        _ = await g.catalog.fetchExternalLinks(mediaType: "ANIME", mediaId: 154587)
        _ = await g.availability.resolveWatchLinks(animeId: 154587, originalLanguage: "ja", progress: nil)
        _ = await g.releases.mediaSchedule(kind: .anime, id: 154587)
        _ = await g.releases.themes(animeId: 154587)
        _ = await g.recommendations.fetchSimilar(kind: .anime, id: 154587)
        _ = try? await g.social.fetchFriendActivityForTitle(mediaType: "ANIME", mediaId: 154587)
        await g.catalog.enqueueMediaRelationRefresh(mediaType: "ANIME", mediaId: 154587, reason: "probe")
        // The character page and the season page (the title page of the prequel season).
        _ = await g.catalog.fetchMediaByCharacter(characterId: 1)
        _ = await g.catalog.fetchVoiceActors(forCharacter: 1)
        _ = try? await g.catalog.fetchAnimeById(52991)
        _ = await g.catalog.fetchMediaLadder(mediaType: "ANIME", mediaId: 52991)

        Self.assertOnlyAllowlistedAnonymousReads(h)
        #expect(h.requests(to: "rpc/enqueue_media_relation_refresh").isEmpty)
        #expect(h.requests(to: "rpc/fetch_friend_activity_for_title").isEmpty)
        #expect(!h.requests(to: "rpc/get_media_ladder").isEmpty)
        #expect(!h.requests(to: "rpc/character_voice_actors_v1").isEmpty)
        #expect(!h.requests(to: "anime").isEmpty)
        await h.tearDown()
    }

    static func driveGuestDiscoverBrowseAndSearch(_ g: AppGraph) async {
        _ = await g.discovery.ensureDiscoverBundle()
        _ = await g.discovery.fetchDailyFeature()
        _ = await g.discovery.fetchBecauseYouRail()
        _ = await g.discovery.fetchTonightShelf()
        _ = await g.discovery.fetchRealmHiddenGem()
        _ = await g.taste.fetchPersonalizedNewToYou(limit: 20, mediaType: "ANIME")
        _ = await g.taste.loadDiscoverHidden()
        _ = await g.discovery.moodPage(.cozy, medium: .anime)
        _ = await g.discovery.browseAnimePage(genre: nil, status: nil, minEpisodes: nil, maxEpisodes: nil, cursorInt: nil,
                                              cursorDate: nil, cursorId: nil, limit: 24)
        g.search.resetCombinedSearch(query: "Frieren")
        await g.search.fetchNextCombinedSearchPage()
        g.social.prefetchFriendCounts(items: [("ANIME", 1)])
        await g.clubs.checkClubNotifications()
        await g.outboundLinks.recordOutboundLink(mediaType: "ANIME", mediaId: 1, linkKind: "watch", provider: "x").value
        g.discovery.recordRecentSearch("Frieren")
    }

    @Test("Guests browse Discover, Browse and Search with allowlisted reads only, and no personal request")
    func guestDiscoverBrowseAndSearchReadOnlyTheAllowlist() async throws {
        let h = try Self.guestHarness()
        await Self.driveGuestDiscoverBrowseAndSearch(h.service)
        // Let a detached friend-count prefetch (if any) reach the server before judging.
        try await Task.sleep(for: .milliseconds(100))
        Self.assertOnlyAllowlistedAnonymousReads(h)
        #expect(h.requests(to: "rpc/fetch_daily_feature").isEmpty)
        #expect(h.requests(to: "rpc/count_friends_tracking").isEmpty)
        #expect(h.requests(to: "rpc/record_outbound_link").isEmpty)
        #expect(h.requests(to: "concierge_events").isEmpty)
        #expect(!h.requests(to: "rpc/discover_bundle").isEmpty)
        await h.tearDown()
    }

    @Test("A guest writes no account-scoped device keys")
    func guestBrowsingWritesNoAccountKeys() async throws {
        let h = try Self.guestHarness()
        let before = Set(h.defaults.dictionaryRepresentation().keys)
        await Self.driveGuestDiscoverBrowseAndSearch(h.service)
        let after = Set(h.defaults.dictionaryRepresentation().keys)
        let added = after.subtracting(before)
        #expect(added.allSatisfy { $0.hasPrefix("com.kuro.featureFlags") },
                "a guest wrote account keys: \(added)")
        await h.tearDown()
    }

    // MARK: Task 5: the sign-up sheet and the gate

    @Test("A guest's Plan opens the sign-up sheet with the intent and the keeps-nothing note; signed in it goes on")
    func saveAsGuestOpensSignUpWithPendingIntent() throws {
        let (flags, suite, defaults) = try Self.guestFlags()
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(), flags: flags)
        var shown: [AppRoute] = []
        let routes = KuroRoutes { shown.append($0) }
        let intent = PendingGuestIntent.plan(Self.frieren, title: "Frieren")

        #expect(GuestGate.allows(intent, guest: graph.guest, routes: routes) == false)
        #expect(shown.map(\.id) == ["signUp"])
        guard case .signUp(let request) = shown.first else { Issue.record("no sign-up route"); return }
        #expect(request.intent == intent)
        #expect(request.mode == .signUp)
        #expect(GuestCopy.sheetNote(for: request.intent, german: false)
            == "Kuro keeps nothing on this phone until you have an account; the title you picked is added as soon as you sign up.")
        #expect(GuestCopy.sheetNote(for: request.intent, german: true).hasPrefix("Kuro speichert nichts auf diesem Gerät"))

        // The sheet appears: the intent is registered; the newest wins.
        graph.guest.begin(request.intent)
        #expect(graph.guest.pendingIntent == intent)
        graph.guest.begin(.joinClub(code: "ABC"))
        #expect(graph.guest.pendingIntent == .joinClub(code: "ABC"))

        // Signed in: the gate lets the action through and presents nothing.
        graph.identity.isAuthenticated = true
        #expect(GuestGate.allows(intent, guest: graph.guest, routes: routes) == true)
        #expect(shown.count == 1)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("For a guest the tracking editor and add-to-club tools become the sign-up sheet that re-opens the title")
    func guestToolRoutesBecomeSignUp() {
        guard case .signUp(let request) = RoutePolicy.toolDestination(for: .addToClub(Self.frieren), isGuest: true) else {
            Issue.record("add-to-club did not become the sign-up sheet"); return
        }
        #expect(request == GuestSignUpRequest(intent: .openTitle(Self.frieren), mode: .signUp))
        guard case .addToClub(let mediaId, let mediaType) = RoutePolicy.toolDestination(for: .addToClub(Self.frieren), isGuest: false) else {
            Issue.record("signed-in add-to-club changed"); return
        }
        #expect(mediaId == 154587)
        #expect(mediaType == "ANIME")
        #expect(RoutePolicy.journeyPage(for: .signUp(request)) == nil, "the sign-up sheet is a tool, never a page")
    }
}
