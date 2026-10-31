import Foundation
import Testing
@testable import Kuro

/// Actual ClubsStore + real SDK transport through the existing controlled HTTP
/// fixture. These are not hosted RLS or websocket proofs. Native execution is
/// blocked until Xcode's license is accepted; a syntax parse is not a test pass.
@MainActor
@Suite("Clubs: disclosure repair races", .timeLimit(.minutes(1)))
struct ClubDisclosureRepairTests {
    @Test("Own disclosure signal before create/join ACK does not turn committed success into failure", arguments: [false, true])
    func committedMembershipWriteSurvivesOwnSignal(join: Bool) async throws {
        let gate = StubGate()
        let rpc = join ? "rpc/join_club" : "rpc/create_club"
        let harness = try ClubsHarness { request in
            switch request.resource {
            case rpc:
                return StubResponse.json(join
                    ? #"{"club_id":"club-9","club_name":"Night Owls","role":"member"}"#
                    : #"{"club_id":"club-9","invite_code":"AB12CD34","name":"Night Owls"}"#).held(by: gate)
            case "rpc/fetch_my_clubs_loading":return ClubJSON.myClubs(["club-9"])
            default:return .emptyArray
            }
        }
        await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let write = Task { @MainActor in
            if join { return try await harness.clubs.joinClub(inviteCode: "AB12CD34").club_id }
            return try await harness.clubs.createClub(name: "Night Owls").club_id
        }
        _ = await harness.server.waitForRequest { $0.resource == rpc }
        harness.clubs.invalidateSharedDisclosure()
        gate.open()
        #expect(try await write.value == "club-9")
        #expect(harness.requests(to: rpc).count == 1)
        await harness.tearDown()
    }

    @Test("An old membership-loss write answer cannot revoke a room after a disclosure/rejoin")
    func staleFailureCannotRevokeRejoin() async throws {
        let gate = StubGate()
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_club_bundle":return .json(ClubJSON.bundle(clubId: "club-9"))
            case "rpc/cast_club_vote":return ClubJSON.error(message: "NOT_A_MEMBER").held(by: gate)
            case "rpc/join_club":return .json(#"{"club_id":"club-9","club_name":"Night Owls","role":"member"}"#)
            case "rpc/fetch_my_clubs_loading":return ClubJSON.myClubs(["club-9"])
            default:return .emptyArray
            }
        }
        await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        _ = try await harness.clubs.fetchClubBundle(clubId: "club-9")
        let vote = Task { @MainActor in try await harness.clubs.castVote(pollId: "poll-club-9", optionId: "opt-club-9") }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/cast_club_vote" }
        harness.clubs.invalidateSharedDisclosure()
        _ = try await harness.clubs.joinClub(inviteCode: "AB12CD34")
        _ = try await harness.clubs.fetchClubBundle(clubId: "club-9")
        let epoch = harness.clubs.revocationEpoch("club-9")
        gate.open()
        await #expect(throws: CancellationError.self) { try await vote.value }
        #expect(harness.clubs.revocationEpoch("club-9") == epoch)
        #expect(harness.clubs.myClubs.map(\.id) == ["club-9"])
        await harness.tearDown()
    }

    @Test("Disclosure clears enriched list names/activity/artwork immediately and keeps them absent after a failed reload")
    func failedRefreshLeavesNoOldDisclosure() async throws {
        let harness = try ClubsHarness { _ in ClubJSON.error(message: "temporary outage", code: "XX000", status: 500) }
        await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let body = #"[{"id":"club-9","name":"Night Owls","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z","member_names":["Peer"],"activity_preview":"Peer is reading","cover_images":["https://fixture.invalid/private.jpg"]}]"#
        harness.clubs.myClubs = try JSONDecoder().decode([ClubListRow].self, from: Data(body.utf8))
        harness.clubs.hasUnseenClubActivity = true
        let epoch = harness.clubs.revocationEpoch("club-9")
        harness.clubs.invalidateSharedDisclosure()
        #expect(harness.clubs.myClubs.isEmpty)
        #expect(!harness.clubs.hasUnseenClubActivity)
        #expect(harness.clubs.revocationEpoch("club-9") == epoch, "privacy refresh is not membership loss")
        await harness.clubs.fetchMyClubs()
        #expect(harness.clubs.myClubs.isEmpty)
        await harness.tearDown()
    }

    @Test("Disclosure rejects an in-flight provider aggregate before its club ever entered My Clubs/cache")
    func firstAggregateCannotRefillAfterDisclosure() async throws {
        let gate = StubGate()
        let harness = try ClubsHarness { request in
            request.resource == "rpc/club_shared_providers"
                ? StubResponse.json(ClubJSON.sharedProviders).held(by: gate) : .emptyArray
        }
        await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "a@example.com")
        let availability = harness.service.availability
        let read = Task { @MainActor in await availability.fetchClubSharedProviders(clubId: "uncached-club") }
        _ = await harness.server.waitForRequest { $0.resource == "rpc/club_shared_providers" }
        #expect(harness.clubs.myClubs.isEmpty)
        harness.clubs.invalidateSharedDisclosure()
        gate.open()
        #expect(await read.value == nil)
        #expect(availability.cachedClubSharedProviders(clubId: "uncached-club") == nil)
        await harness.tearDown()
    }
}
