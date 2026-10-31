//
//  ClubsViewRulesTests.swift
//  KuroTests
//
//  What the club views rely on from the Clubs owner (E6a-V):
//  - `ClubsStore.revocationEpoch(_:)` is an observable per-club signal: it changes when (and only
//    when) that club is revoked, so `ClubDetailView` / `AddToClubRailSheet` can drop their own copies
//    of the club's data (bundle, optimistic votes and reactions, shared providers);
//  - the realtime stop a club view sends when it disappears is keyed by its club: it never closes the
//    channel another club's view opened meanwhile.
//  Runs on the `ClubsHarness` of ClubsContractTests (stub PostgREST, fake channels).
//

import Testing
import Foundation
import Observation
import Synchronization
@testable import Kuro

@MainActor
@Suite("Clubs: what the club views rely on", .timeLimit(.minutes(1)))
struct ClubsViewRulesTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    enum Trigger: String, CaseIterable, Sendable {
        case leaveSucceeded, bundleNotAMember, voteNotAMember
        /// Control: a non-membership error (the poll closed) revokes nothing.
        case votePollClosedControl
    }

    @Test("revocationEpoch(club-1) is observed and changes when club-1 is revoked, never for club-2 or a non-membership error",
          arguments: Trigger.allCases)
    func revocationSignalIsObservablePerClub(trigger: Trigger) async throws {
        let revoked = Mutex(false)
        let harness = try ClubsHarness { request in
            let isRevoked = revoked.withLock { $0 }
            let clubId = request.jsonObject?["p_club_id"] as? String
            switch request.resource {
            case "rpc/fetch_club_bundle":
                if isRevoked, clubId == "club-1" { return ClubJSON.error(message: "NOT_A_MEMBER") }
                return .json(ClubJSON.bundle(clubId: clubId ?? ""))
            case "rpc/leave_club":
                return .json(#"{"success":true}"#)
            case "rpc/cast_club_vote":
                return ClubJSON.error(message: trigger == .votePollClosedControl ? "POLL_CLOSED" : "NOT_A_MEMBER")
            default:
                return .emptyArray
            }
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        _ = try await clubs.fetchClubBundle(clubId: "club-1")
        _ = try await clubs.fetchClubBundle(clubId: "club-2")
        let club1Before = clubs.revocationEpoch("club-1")
        let club2Before = clubs.revocationEpoch("club-2")

        // What a view body does: read the club's signal under observation tracking.
        let changes = Mutex(0)
        withObservationTracking {
            _ = clubs.revocationEpoch("club-1")
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        revoked.withLock { $0 = true }
        switch trigger {
        case .leaveSucceeded:
            try await clubs.leaveClub(clubId: "club-1")
        case .bundleNotAMember:
            await #expect(throws: (any Error).self) { try await clubs.refreshClubBundle(clubId: "club-1") }
        case .voteNotAMember, .votePollClosedControl:
            await #expect(throws: (any Error).self) { try await clubs.castVote(pollId: "poll-club-1", optionId: "opt-club-1") }
        }

        if trigger == .votePollClosedControl {
            #expect(changes.withLock { $0 } == 0, "a non-membership error signalled a revocation")
            #expect(clubs.revocationEpoch("club-1") == club1Before)
        } else {
            #expect(changes.withLock { $0 } == 1, "the club views were not told about the revocation")
            #expect(clubs.revocationEpoch("club-1") != club1Before)
        }
        #expect(clubs.revocationEpoch("club-2") == club2Before, "club-2's views would drop their data")
        await harness.tearDown()
    }

    @Test("An account transition changes every club's signal, also one never revoked, and tells the observing views (they drop their copies)")
    func accountTransitionSignalsTheViews() async throws {
        let harness = try ClubsHarness()
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        // club-1 was never revoked: only the account transition can change its signal.
        let beforeSwitch = clubs.revocationEpoch("club-1")

        let changes = Mutex(0)
        withObservationTracking {
            _ = clubs.revocationEpoch("club-1")
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        await harness.service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(changes.withLock { $0 } == 1)
        #expect(clubs.revocationEpoch("club-1") != beforeSwitch, "a view of club-1 keeps A's copies after A -> B")

        // Sign-out changes it again.
        let beforeSignOut = clubs.revocationEpoch("club-1")
        await harness.service.session.endSession()
        #expect(clubs.revocationEpoch("club-1") != beforeSignOut, "a view of club-1 keeps B's copies after sign-out")
        await harness.tearDown()
    }

    @Test("A club view's disappear-stop is keyed: stopping club-1 after club-2 opened leaves club-2's channel open")
    func keyedStopNeverClosesAnotherClubsChannel() async throws {
        let harness = try ClubsHarness()
        let realtime = harness.clubs.realtime
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")

        // club-1's view opened its channel; club-2's view then opened its own (club change).
        await realtime.subscribe(clubId: "club-1")
        await realtime.subscribe(clubId: "club-2")
        let channel2 = try #require(harness.channels.made.last)
        #expect(channel2.clubId == "club-2")

        // club-1's view disappears afterwards.
        realtime.stop(clubId: "club-1")
        await realtime.teardownTask?.value
        #expect(realtime.subscribedClubId == "club-2")
        #expect(channel2.isListening && !channel2.isUnsubscribed)

        // club-2's own view disappears.
        realtime.stop(clubId: "club-2")
        await realtime.teardownTask?.value
        #expect(realtime.subscribedClubId == nil)
        #expect(!channel2.isListening)
        #expect(channel2.isUnsubscribed)
        await harness.tearDown()
    }
}

// MARK: - Pure lifecycle rules (E6a-V fix round 1)
// `ClubDetailLifecycle` (used by ClubDetailView): when the club's realtime channel is opened and
// stopped, and how a membership loss / revocation is answered (drop the view's copies of the club's
// data, one notice, one dismissal), table-driven over event sequences. `ClubSelectionRevocation`
// (used by AddToClubRailSheet): a club switch is not a revocation.

/// One event the club detail view feeds to `ClubDetailLifecycle`.
enum ClubLifecycleStep: Sendable {
    case appear
    case disappear
    /// The task is about to open the channel (after its initial load).
    case subscribe(cancelled: Bool)
    /// The subscribe returned.
    case subscribed(cancelled: Bool)
    /// A load starts, or a load's answer arrives.
    case load
    /// A club request answered NOT_A_MEMBER / permission denied.
    case lost(showsClub: Bool)
    /// A club request answered CLUB_NOT_FOUND.
    case gone
    /// `ClubsStore` revoked the club (its signal changed).
    case revoked(showsClub: Bool)
    /// The settings sheet started (true) or failed (false) to leave.
    case leaving(Bool)
}

@MainActor
@Suite("Clubs: club detail lifecycle rules")
struct ClubDetailLifecycleRulesTests {
    enum Scenario: String, CaseIterable, Sendable {
        case subscribeOnScreen
        case disappearWhileLoadingNeverSubscribes
        case cancelledTaskOffScreenStopsItsChannel
        case reappearKeepsTheChannel
        case noSubscribeOrLoadAfterMembershipEnd
        case membershipEndsWhileSubscribing
        case ownAnswerThenSignalNoticesOnce
        case signalThenLateAnswerNoticesOnce
        case leaveFromSettingsHasNoRemovedToast
        case failedLeaveThenRemovalIsARemoval
        case clubGoneStaysOpenWithoutChannel
        case revocationWhileNothingShownOnlyDrops

        var steps: [ClubLifecycleStep] {
            switch self {
            case .subscribeOnScreen:
                return [.appear, .load, .subscribe(cancelled: false), .subscribed(cancelled: false)]
            case .disappearWhileLoadingNeverSubscribes:
                return [.appear, .load, .disappear, .subscribe(cancelled: true)]
            case .cancelledTaskOffScreenStopsItsChannel:
                return [.appear, .subscribe(cancelled: false), .disappear, .subscribed(cancelled: true)]
            case .reappearKeepsTheChannel:
                // The old task's subscribe returns after the view came back; the new task subscribes again.
                return [.appear, .subscribe(cancelled: false), .disappear, .appear, .subscribed(cancelled: true),
                        .subscribe(cancelled: false), .subscribed(cancelled: false)]
            case .noSubscribeOrLoadAfterMembershipEnd:
                return [.appear, .load, .lost(showsClub: false), .subscribe(cancelled: false), .load]
            case .membershipEndsWhileSubscribing:
                return [.appear, .subscribe(cancelled: false), .revoked(showsClub: true), .subscribed(cancelled: false)]
            case .ownAnswerThenSignalNoticesOnce:
                // The view's own refresh answers NOT_A_MEMBER (its catch runs first), then the store's signal.
                return [.appear, .lost(showsClub: true), .revoked(showsClub: false)]
            case .signalThenLateAnswerNoticesOnce:
                return [.appear, .revoked(showsClub: true), .lost(showsClub: false), .load]
            case .leaveFromSettingsHasNoRemovedToast:
                return [.appear, .leaving(true), .revoked(showsClub: true), .revoked(showsClub: false)]
            case .failedLeaveThenRemovalIsARemoval:
                return [.appear, .leaving(true), .leaving(false), .revoked(showsClub: true)]
            case .clubGoneStaysOpenWithoutChannel:
                return [.appear, .gone, .revoked(showsClub: false), .subscribe(cancelled: false), .load]
            case .revocationWhileNothingShownOnlyDrops:
                // The initial load is still in flight: its own answer decides what is shown.
                return [.appear, .revoked(showsClub: false), .load]
            }
        }

        /// What the view does, step by step (steps without a decision are skipped).
        var expected: [String] {
            switch self {
            case .subscribeOnScreen:
                return ["load", "subscribe", "keep+continue"]
            case .disappearWhileLoadingNeverSubscribes:
                return ["load", "stop", "no-subscribe"]
            case .cancelledTaskOffScreenStopsItsChannel:
                return ["subscribe", "stop", "stop+end"]
            case .reappearKeepsTheChannel:
                return ["subscribe", "stop", "keep+end", "subscribe", "keep+continue"]
            case .noSubscribeOrLoadAfterMembershipEnd:
                return ["load", "drop,notYetMember+toast,dismiss", "no-subscribe", "no-load"]
            case .membershipEndsWhileSubscribing:
                return ["subscribe", "drop,removed+toast,dismiss", "stop+end"]
            case .ownAnswerThenSignalNoticesOnce:
                return ["drop,removed+toast,dismiss", "drop"]
            case .signalThenLateAnswerNoticesOnce:
                return ["drop,removed+toast,dismiss", "drop", "no-load"]
            case .leaveFromSettingsHasNoRemovedToast:
                return ["drop,left,dismiss", "drop"]
            case .failedLeaveThenRemovalIsARemoval:
                return ["drop,removed+toast,dismiss"]
            case .clubGoneStaysOpenWithoutChannel:
                return ["drop,clubGone", "drop", "no-subscribe", "no-load"]
            case .revocationWhileNothingShownOnlyDrops:
                return ["drop", "load"]
            }
        }
    }

    /// Feeds `steps` to a fresh lifecycle and describes each decision.
    static func run(_ steps: [ClubLifecycleStep]) -> [String] {
        var lifecycle = ClubDetailLifecycle()
        var trace: [String] = []
        for step in steps {
            switch step {
            case .appear:
                lifecycle.appeared()
            case .disappear:
                trace.append(lifecycle.disappeared() ? "stop" : "keep")
            case .subscribe(let cancelled):
                trace.append(lifecycle.shouldSubscribe(taskCancelled: cancelled) ? "subscribe" : "no-subscribe")
            case .subscribed(let cancelled):
                let next = lifecycle.afterSubscribe(taskCancelled: cancelled)
                trace.append((next.stopsOwnChannel ? "stop" : "keep") + (next.continuesTask ? "+continue" : "+end"))
            case .load:
                trace.append(lifecycle.acceptsLoads ? "load" : "no-load")
            case .lost(let showsClub):
                trace.append(describe(lifecycle.membershipLost(showsClub: showsClub)))
            case .gone:
                trace.append(describe(lifecycle.clubGone()))
            case .revoked(let showsClub):
                trace.append(describe(lifecycle.revoked(showsClub: showsClub)))
            case .leaving(let leaving):
                lifecycle.leavingChanged(leaving)
            }
        }
        return trace
    }

    /// A loss/revocation answer: "drop" (or "keep-state"), then the notice (+toast), then "dismiss".
    static func describe(_ response: ClubDetailLifecycle.LossResponse) -> String {
        var parts = [response.dropsLocalState ? "drop" : "keep-state"]
        if let notice = response.notice {
            parts.append(String(describing: notice) + (notice.showsToast ? "+toast" : ""))
        }
        if response.dismisses {
            parts.append("dismiss")
        }
        return parts.joined(separator: ",")
    }

    @Test("Club detail lifecycle: channel, loads, notices and dismissals per event sequence", arguments: Scenario.allCases)
    func lifecycleDecisions(scenario: Scenario) {
        let trace = Self.run(scenario.steps)
        #expect(trace == scenario.expected)
        // Invariants: at most one toast and one dismissal per view; every loss/revocation answer drops
        // the view's copies of the club's data (bundle, optimistic votes; reactions go with the bundle).
        #expect(trace.filter { $0.contains("+toast") }.count <= 1, "a second toast")
        #expect(trace.filter { $0.contains("dismiss") }.count <= 1, "a second dismissal")
        #expect(!trace.contains { $0.hasPrefix("keep-state") }, "a loss answer kept the club's data")
    }

    enum Selection: String, CaseIterable, Sendable {
        case noClubSelected, freshClubPicked, previouslyRevokedClubPicked, selectedClubRevoked, accountReset

        /// The selected club's epoch now, its epoch when it was selected, and whether that is a revocation.
        var values: (current: Int?, captured: Int?, isRevocation: Bool) {
            switch self {
            case .noClubSelected: return (nil, nil, false)
            case .freshClubPicked: return (0, 0, false)
            case .previouslyRevokedClubPicked: return (2, 2, false)
            case .selectedClubRevoked: return (1, 0, true)
            case .accountReset: return (0, 3, true)
            }
        }
    }

    @Test("Add-to-club sheet: only a change of the selected club's own epoch is a revocation, never a club switch",
          arguments: Selection.allCases)
    func addToClubSheetRevocationRule(selection: Selection) {
        let (current, captured, isRevocation) = selection.values
        #expect(ClubSelectionRevocation.isRevocation(current: current, captured: captured) == isRevocation)
    }

    @Test("Private clubs never show member-name initials; status and progress keep them")
    func privateClubHidesMemberInitials() {
        let names = ["Ada", "Ben", "Cara"]
        #expect(ClubsListCardRules.memberInitials(sharingLevel: "private", memberNames: names) == [])
        #expect(ClubsListCardRules.memberInitials(sharingLevel: "PRIVATE", memberNames: names) == [])
        #expect(ClubsListCardRules.memberInitials(sharingLevel: "status", memberNames: names) == ["A", "B", "C"])
        #expect(ClubsListCardRules.memberInitials(sharingLevel: "progress", memberNames: names) == ["A", "B", "C"])
        #expect(ClubsListCardRules.memberInitials(sharingLevel: "status", memberNames: nil) == [])
    }
}
