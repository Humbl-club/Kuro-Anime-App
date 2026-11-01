//
//  CredentialLeaseTests.swift
//  KuroTests
//
//  F33: a private request must be sent with the credential of the account that originated it.
//  supabase-swift (2.54.1) reads the access token at DISPATCH time (`SupabaseClient.adapt(request:)`
//  overwrites `Authorization` with `auth.session.accessToken`), not when the app captured its account
//  context, so a result guard cannot prove binding. These tests drive the real SDK client against the
//  in-process stub server and look at the bearer each request actually carried:
//  - a controlled PRE-dispatch switch (the SDK's persisted session is replaced by B's and the funnel
//    switches to B after A's write was accepted but before it was dispatched);
//  - the funnel's credential change (sign-out, then B's sign-in) must wait until A's in-flight write
//    has finished, so the SDK never holds B's token while A's work can still be dispatched.
//

import Testing
import Foundation
import KuroCore
import Supabase
import Synchronization
@testable import Kuro

@MainActor
@Suite("F33: private requests carry their own account's credential", .timeLimit(.minutes(1)))
struct CredentialLeaseTests {
    static let userA = StubAuth.userA
    static let userB = StubAuth.userB

    nonisolated static let applyJSON = #"{"success":true,"sessionId":"s-1","applied":[],"skipped":[],"conflicts":[],"errors":[]}"#
    nonisolated static let commentJSON = #"{"id":"comment-a","user_id":"account-a","text":"A's draft","created_at":"2026-10-05","updated_at":"2026-10-05"}"#

    nonisolated static func isApply(_ request: RecordedRequest) -> Bool {
        request.path.hasSuffix("/functions/v1/concierge-apply")
    }

    /// Signs B in and out once (keeping the session the SDK persisted for B), then signs A in.
    static func signedInAsAKeepingBsSession(_ h: SessionSDKHarness) async throws -> [String: Data] {
        try await h.session.signInWithEmail(email: "b@example.com", password: "pw")
        let sessionB = h.storage.snapshot()
        await h.session.signOut()
        try await h.session.signInWithEmail(email: "a@example.com", password: "pw")
        await h.graph.libraryActions.libraryRefreshTask?.value
        #expect(h.graph.accountSession.current?.userId == userA)
        return sessionB
    }

    @Test("Pre-dispatch switch: A's apply, accepted while A was current, is never sent once the SDK holds B's session and the funnel switched to B before dispatch")
    func preDispatchSwitchSendsNothingAsB() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            Self.isApply(request) ? .json(Self.applyJSON) : .emptyArray
        })
        let sessionB = try await Self.signedInAsAKeepingBsSession(h)

        let apply = Task.immediate { @MainActor in
            try await h.graph.imports.conciergeApply(items: [["mediaType": "ANIME", "mediaId": 101, "status": "CURRENT"]])
        }
        // A's apply was accepted; before it is dispatched the SDK installs B's session and the funnel
        // switches to B (its synchronous half runs here, before any suspension).
        h.storage.replace(with: sessionB)
        let switching = Task.immediate { @MainActor in
            _ = await h.session.applySession(userId: Self.userB, email: "b@example.com")
        }
        await #expect(throws: CancellationError.self) { _ = try await apply.value }
        await switching.value

        let applies = h.server.requests.filter(Self.isApply)
        #expect(!applies.contains { $0.bearerSubject == Self.userB.lowercased() },
                "A's apply was sent with B's credential: \(applies)")
        #expect(applies.isEmpty, "A's apply was dispatched after its account ended: \(applies)")
        await h.tearDown()
    }

    @Test("Sign-out then B's sign-in: A's private write still in flight is cancelled and has finished before B's credentials are requested; nothing of A's is sent with B's credential")
    func credentialChangeWaitsForObsoleteWrites() async throws {
        let held = StubGate()
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            request.resource == "rpc/upsert_title_comment" ? StubResponse.json(Self.commentJSON).held(by: held) : .emptyArray
        })
        try await h.session.signInWithEmail(email: "a@example.com", password: "pw")
        let write = Task.immediate { @MainActor in
            try await h.graph.social.upsertTitleComment(mediaType: "ANIME", mediaId: 101, text: "A's draft")
        }
        let sent = await h.server.waitForRequest { $0.resource == "rpc/upsert_title_comment" }
        #expect(sent.bearerSubject == Self.userA.lowercased())

        await h.session.signOut()
        let signInB = Task.immediate { @MainActor in
            try await h.session.signInWithEmail(email: "b@example.com", password: "pw")
        }
        _ = await h.server.waitForRequest { StubAuth.isPasswordGrant($0, for: StubAuth.userB) }
        held.open()
        try await signInB.value
        let outcome = await write.result

        #expect(throws: CancellationError.self, "A's write outcome was handed out after A's session ended") {
            _ = try outcome.get()
        }
        var stopOfA: Int?
        var grantOfB: Int?
        for (index, event) in h.server.timeline.enumerated() {
            switch event {
            case .stopped(let request) where request.resource == "rpc/upsert_title_comment":
                stopOfA = stopOfA ?? index
            case .arrived(let request) where StubAuth.isPasswordGrant(request, for: Self.userB):
                grantOfB = grantOfB ?? index
            default:
                break
            }
        }
        let stop = try #require(stopOfA, "A's in-flight write was not cancelled with A's session: \(h.server.timeline)")
        let grant = try #require(grantOfB)
        #expect(stop < grant, "B's credentials were requested while A's write could still be dispatched: \(h.server.timeline)")
        #expect(!h.server.requests.contains { $0.resource == "rpc/upsert_title_comment" && $0.bearerSubject == Self.userB.lowercased() })
        #expect(h.graph.accountSession.current?.userId == Self.userB)
        await h.tearDown()
    }

    /// A private write family of the app, started for the signed-in account.
    enum Family: String, CaseIterable, Sendable {
        case socialComment, socialReaction, clubJoin, clubCreate, tasteSignal, importsUndo, aniListImport

        /// The request the family sends (its edge function or RPC).
        func matches(_ request: RecordedRequest) -> Bool {
            switch self {
            case .socialComment: return request.resource == "rpc/upsert_title_comment"
            case .socialReaction: return request.resource == "rpc/toggle_comment_reaction"
            case .clubJoin: return request.resource == "rpc/join_club"
            case .clubCreate: return request.resource == "rpc/create_club"
            case .tasteSignal: return request.resource == "rpc/record_taste_deck_signal"
            case .importsUndo: return request.path.hasSuffix("/functions/v1/concierge-undo")
            case .aniListImport: return request.path.hasSuffix("/functions/v1/concierge-import-anilist")
            }
        }

        /// Starts the write; its outcome is "sent" (a value) or the thrown error's description.
        @MainActor
        func start(on graph: AppGraph) -> Task<String, Never> {
            Task.immediate { @MainActor in
                do {
                    switch self {
                    case .socialComment:
                        _ = try await graph.social.upsertTitleComment(mediaType: "ANIME", mediaId: 101, text: "A's draft")
                    case .socialReaction:
                        _ = try await graph.social.toggleCommentReaction(commentId: "c-1", reactionType: "thumbs_up")
                    case .clubJoin:
                        _ = try await graph.clubs.joinClub(inviteCode: "AB12CD34")
                    case .clubCreate:
                        _ = try await graph.clubs.createClub(name: "A's club")
                    case .tasteSignal:
                        // `false`: not accepted for the account current now.
                        return await graph.taste.recordTasteDeckSignal(mediaType: "ANIME", mediaId: 101, action: .love)
                            ? "accepted" : "not accepted"
                    case .importsUndo:
                        _ = try await graph.imports.conciergeUndo(sessionId: "s-1")
                    case .aniListImport:
                        _ = try await graph.imports.conciergeImportAniList(username: "someone")
                    }
                    return "sent"
                } catch is CancellationError {
                    return "dropped"
                } catch {
                    return "failed: \(error)"
                }
            }
        }
    }

    @Test("Pre-dispatch switch, every private write family: accepted while A was current, none is dispatched once the SDK holds B's session and the funnel switched to B; none reports success",
          arguments: Family.allCases)
    func preDispatchSwitchForEveryFamily(family: Family) async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { _ in .json("{}") })
        let sessionB = try await Self.signedInAsAKeepingBsSession(h)

        let write = family.start(on: h.graph)
        h.storage.replace(with: sessionB)
        let switching = Task.immediate { @MainActor in
            _ = await h.session.applySession(userId: Self.userB, email: "b@example.com")
        }
        let outcome = await write.value
        await switching.value

        #expect(outcome == (family == .tasteSignal ? "not accepted" : "dropped"), "\(family): \(outcome)")
        let sent = h.server.requests.filter(family.matches)
        #expect(sent.isEmpty, "\(family) was dispatched after its account ended: \(sent)")
        await h.tearDown()
    }

    @Test("Outbound-link tap: sent as a lease of the account current at the tap (never with B's credential after a pre-dispatch switch); sent normally while that account is current")
    func outboundLinkTapIsBoundToItsAccount() async throws {
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { _ in .json("null") })
        let sessionB = try await Self.signedInAsAKeepingBsSession(h)
        let outbound = OutboundLinkTelemetry(client: h.client, accountSession: h.graph.accountSession)
        let isTap: @Sendable (RecordedRequest) -> Bool = { $0.resource == "rpc/record_outbound_link" }

        await outbound.recordOutboundLink(mediaType: "ANIME", mediaId: 1, linkKind: "watch", provider: "crunchyroll").value
        let current = try #require(h.server.requests.first(where: isTap))
        #expect(current.bearerSubject == Self.userA.lowercased())

        let tap = outbound.recordOutboundLink(mediaType: "ANIME", mediaId: 2, linkKind: "watch", provider: "crunchyroll")
        h.storage.replace(with: sessionB)
        _ = Task.immediate { @MainActor in _ = await h.session.applySession(userId: Self.userB, email: "b@example.com") }
        await tap.value
        let taps = h.server.requests.filter(isTap)
        #expect(taps.count == 1, "A's tap was sent after A ended: \(taps)")
        #expect(!taps.contains { $0.bearerSubject == Self.userB.lowercased() })
        await h.tearDown()
    }

    @Test("F04 (post-dispatch): A's club create/join and Taste 'love' answered after A -> B hand out nothing: no outcome, no my-clubs refresh and no Library refresh for B",
          arguments: [Family.clubCreate, Family.clubJoin, Family.tasteSignal])
    func lateSuccessOfEndedAccountHandsOutNothing(family: Family) async throws {
        let held = StubGate()
        let h = try SessionSDKHarness(responder: StubAuth.signInResponder { request in
            if family.matches(request) {
                let body = family == .tasteSignal ? "null" : #"{"club_id":"club-a","club_name":"A's club","name":"A's club","role":"owner","invite_code":"AB12CD34"}"#
                return StubResponse.json(body).held(by: held)
            }
            return .emptyArray
        })
        try await h.session.signInWithEmail(email: "a@example.com", password: "pw")
        await h.graph.libraryActions.libraryRefreshTask?.value
        let write = family.start(on: h.graph)
        _ = await h.server.waitForRequest(where: family.matches)
        let myClubsReads = h.server.requests.filter { $0.resource?.hasPrefix("rpc/fetch_my_clubs") == true }.count

        _ = await h.session.applySession(userId: Self.userB, email: "b@example.com")
        await h.graph.libraryActions.libraryRefreshTask?.value
        let refreshB = h.graph.libraryActions.libraryRefreshTask
        held.open()
        let outcome = await write.value

        #expect(outcome == (family == .tasteSignal ? "not accepted" : "dropped"), "\(family): \(outcome)")
        #expect(h.server.requests.filter { $0.resource?.hasPrefix("rpc/fetch_my_clubs") == true }.count == myClubsReads,
                "A's late success refreshed B's clubs")
        #expect(h.graph.libraryActions.libraryRefreshTask == refreshB, "A's late 'love' refreshed B's Library")
        #expect(h.graph.clubs.myClubs.isEmpty)
        await h.tearDown()
    }
}

// MARK: - Telemetry attribution (F70 / F33 audit)

@MainActor
@Suite("Telemetry: an obsolete event is never relabeled as the new account's", .timeLimit(.minutes(1)))
struct TelemetryAttributionTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    @Test("A timed interaction begun under A that completes after A -> B is dropped (not attributed to B); B's own interaction is tracked as B")
    func interactionAcrossTransitionIsDropped() async throws {
        let server = StubServer()
        server.respond { _ in .json("", status: 201) }
        let client = StubSupabase.makeClient(server: server)
        let telemetry = InteractionTelemetry(analytics: ConciergeAnalytics(isConnected: { true }), client: client)
        let store = try TestDefaults()
        let service = AppComposition.testingGraph(
            testingUserDefaults: store.defaults,
            notificationCenter: FakeNotificationCenter(),
            client: client,
            libraryBackend: FakeLibraryBackend(),
            interactionTelemetry: telemetry
        )
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        let startedUnderA = telemetry.beginInteractionTiming()

        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        telemetry.trackInteractionEvent("a_vote_success", surface: "club_detail_polls", result: "ok", startedAt: startedUnderA)
        let startedUnderB = telemetry.beginInteractionTiming()
        telemetry.trackInteractionEvent("b_vote_success", surface: "club_detail_polls", result: "ok", startedAt: startedUnderB)
        // Same account across a same-user refresh: kept.
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        telemetry.trackInteractionEvent("b_still_b", surface: "club_detail_polls", result: "ok", startedAt: startedUnderB)
        // Each event is its own fire-and-forget send, so the two B events can arrive in either order:
        // wait for both (waiting only for the last one tracked raced the first one's request).
        for name in ["b_vote_success", "b_still_b"] {
            _ = await server.waitForRequest { request in
                request.resource == "concierge_events" && (request.canonicalBody?.contains(name) ?? false)
            }
        }

        let sent = TelemetryOwnerTests.sentEvents(server)
        #expect(!sent.contains { $0.hasPrefix("a_vote_success") }, "A's interaction was relabeled: \(sent)")
        #expect(sent.contains("b_vote_success:\(Self.userB)"), "\(sent)")
        #expect(sent.contains("b_still_b:\(Self.userB)"), "\(sent)")
        await service.session.endSession()
        store.tearDown()
        server.shutDown()
    }
}

