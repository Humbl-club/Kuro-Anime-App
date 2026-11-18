//
//  DateFillCredentialLeaseTests.swift
//  KuroTests
//
//  F2.3: the auto-filled date leg of a status change is a new private request. It runs inside the
//  account's credential lease, so a switch between acceptance and dispatch sends nothing as the other
//  account. The Library store itself takes no lease for its existing writes; only this leg does.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import Supabase
@testable import Kuro

@MainActor
@Suite("Date fill: the added PATCH leg carries its own account's credential", .timeLimit(.minutes(1)))
struct DateFillCredentialLeaseTests {
    static let userA = StubAuth.userA
    static let userB = StubAuth.userB

    /// A's `.planning` anime row, with the server revision and lifecycle the durable branch needs and
    /// known (empty) dates.
    static func plannedRow() -> [String: Any] {
        var row = ListRowJSON.anime(1, rowId: 1, userId: userA.lowercased(), listType: "PLANNING")
        row["server_revision"] = 1
        row["lifecycle_id"] = UUID().uuidString.lowercased()
        row["repeat_count"] = 0
        row["started_raw"] = NSNull()
        row["finished_raw"] = NSNull()
        return row
    }

    @Test("Pre-dispatch switch: A's status change is accepted, the SDK then holds B's session and the funnel switched to B: no list PATCH is sent, none with B's bearer, and the outcome is not a success")
    func preDispatchSwitchSendsNoDateLegAsB() async throws {
        let script = ListTablesScript(anime: [Self.plannedRow()])
        let suite = "kuro.tests.date-fill-lease.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: [
            "--ff-on=library_date_autofill_v1", "--ff-on=series_foundation_v1",
        ])
        let h = try SessionSDKHarness(
            responder: StubAuth.signInResponder(rest: script.responder()),
            flags: flags,
            libraryBackendOverClient: { AppComposition.libraryBackend(client: $0, fenceEnabled: { true }) }
        )
        let sessionB = try await CredentialLeaseTests.signedInAsAKeepingBsSession(h)
        let key = MediaKey(kind: .anime, id: 1)
        let seeded = try #require(h.graph.library.entry(for: key), "A's row was not loaded")
        #expect(seeded.datesKnown && seeded.startedOn == nil)
        #expect(h.graph.library.progressAvailable, "the durable branch needs the outbox and the series flag")
        let patchesBefore = h.server.requests.filter { $0.method == "PATCH" }.count

        let apply = Task.immediate { @MainActor in
            await h.graph.libraryActions.apply(LibraryEdit(status: .set(.current)), to: key, createIfMissing: nil)
        }
        // The status change was accepted for A; before the date leg is dispatched the SDK installs B's
        // session and the funnel switches to B (its synchronous half runs here).
        h.storage.replace(with: sessionB)
        let switching = Task.immediate { @MainActor in
            _ = await h.session.applySession(userId: Self.userB, email: "b@example.com")
        }
        let outcome = await apply.value
        await switching.value

        let patches = h.server.requests.filter { $0.method == "PATCH" }
        #expect(!patches.contains { $0.bearerSubject == Self.userB.lowercased() },
                "A's date leg was sent with B's credential: \(patches)")
        #expect(patches.count == patchesBefore, "A's date leg was dispatched after its account ended: \(patches)")
        #expect(outcome.change == nil, "a change of A's must not be reported as applied once A ended: \(outcome)")
        #expect(h.graph.library.entry(for: key) == nil, "A's title must not appear in B's library")
        await h.tearDown()
    }

    @Test("Composition wiring: while a credential change holds the gate closed the date leg is refused by the lease (nothing is sent); the durable status change stands")
    func closedCredentialGateSendsNoDateLeg() async throws {
        let script = ListTablesScript(anime: [Self.plannedRow()])
        let suite = "kuro.tests.date-fill-gate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: [
            "--ff-on=library_date_autofill_v1", "--ff-on=series_foundation_v1",
        ])
        let h = try SessionSDKHarness(
            responder: StubAuth.signInResponder(rest: script.responder()),
            flags: flags,
            libraryBackendOverClient: { AppComposition.libraryBackend(client: $0, fenceEnabled: { true }) }
        )
        _ = try await CredentialLeaseTests.signedInAsAKeepingBsSession(h)
        let key = MediaKey(kind: .anime, id: 1)
        #expect(h.graph.library.progressAvailable)
        let patchesBefore = h.server.requests.filter { $0.method == "PATCH" }.count

        // A stays the current account, but a credential change is in progress: no lease is admitted.
        let change = await h.graph.accountSession.beginCredentialChange()
        let outcome = await h.graph.libraryActions.apply(LibraryEdit(status: .set(.current)), to: key, createIfMissing: nil)
        h.graph.accountSession.endCredentialChange(change)

        #expect(h.server.requests.filter { $0.method == "PATCH" }.count == patchesBefore,
                "the added date leg was sent without a lease")
        #expect(outcome.change != nil, "the durable status change is the outcome; the date leg is best effort: \(outcome)")
        #expect(h.graph.library.entry(for: key)?.status == .current)
        #expect(h.graph.library.entry(for: key)?.startedOn == nil)
        await h.tearDown()
    }
}
