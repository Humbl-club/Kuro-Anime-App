import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

/// Round-3 (strict recheck) fixes for the Home +1 toast: Undo works once the drain has attempted the
/// save (offline, and while the request is on its way), a failed Undo says what really happened, the
/// "Saved on this device." line follows the outbox rather than connectivity, and a toast waits for a
/// VoiceOver or Switch Control user instead of leaving after 4 s.
@Suite("Home +1 toast, round 3")
@MainActor
struct HomeToastRound3Tests {

    // MARK: Undo after the drain has attempted the +1

    /// A signed-in fixture account with one Library row (Jujutsu Kaisen, episode 6) and a progress
    /// outbox. The test graph has no Supabase client, so every drain attempt fails like an offline send.
    private struct Fixture {
        let graph: AppGraph
        let outbox: ProgressOutbox
        let card: HomeCard
        let account: AccountContext
        let cleanup: () -> Void
    }

    private func fixture() async throws -> Fixture {
        let suite = "home-undo-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).sqlite").path
        let outbox = try ProgressOutbox(path: path)
        let backend = FakeLibraryBackend()
        let lifecycle = try #require(UUID(uuidString: "11111113-1111-4111-8111-111111111111"))
        backend.setRows([LibraryEntry(key: MediaKey(kind: .anime, id: 3), rowId: 3, status: .current, progress: 6,
                                      createdAt: Date(), updatedAt: Date(), revision: 2, lifecycleId: lifecycle)],
                        for: LifecycleFixtures.userA)
        let graph = AppComposition.testingGraph(
            testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
            libraryBackend: backend,
            flags: FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=series_foundation_v1"]),
            progressOutbox: outbox)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "home@example.com")
        await graph.libraryActions.libraryRefreshTask?.value
        graph.home.seedForVisualQA(anime: HomeAnimeLaneTests.bundle(.busy), manga: nil, medium: "anime")
        let card = try #require(graph.home.bundle?.active.first { $0.mediaId == 3 })
        let account = try #require(graph.accountSession.current)
        return Fixture(graph: graph, outbox: outbox, card: card, account: account) {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func undo(_ f: Fixture, before: Int, after: Int) -> HomeProgressToasts.Undo {
        HomeProgressToasts.Undo(medium: "anime", mediaId: f.card.mediaId, lifecycleId: f.card.lifecycleId,
                                before: before, after: after, account: f.account)
    }

    @Test("Offline: Undo after the drain attempted the +1 puts the count back and queues the reversal behind it")
    func undoAfterAFailedAttempt() async throws {
        let f = try await fixture()
        defer { f.cleanup() }
        let before = f.graph.home.displayedProgress(for: f.card)
        await f.graph.home.advance(f.card)
        let after = f.graph.home.displayedProgress(for: f.card)
        #expect(after == before + 1)
        // The drain the +1 scheduled is held back, so this test attempts the send itself: with no
        // connection it fails and the intent stays, attempted (Library will no longer cancel it).
        f.graph.library.cancelProgressWork()
        await f.graph.home.drain()
        let attempted = try await f.outbox.active(accountId: f.account.userId.lowercased())
        #expect(attempted.count == 1)

        let result = await HomeProgressToasts.performUndo(undo(f, before: before, after: after), card: f.card,
                                                          home: f.graph.home, session: f.graph.accountSession)
        #expect(result == .undone)
        #expect(f.graph.home.displayedProgress(for: f.card) == before)
        // The +1 stays queued (it may already be on the server); the reversal follows it in order.
        let queued = try await f.outbox.active(accountId: f.account.userId.lowercased())
        #expect(queued.count == 2)
        #expect(queued.last?.position == before)
        #expect(f.graph.home.statusMessage != HomeCopy.libraryMessage("That save is already on its way."),
                "A working Undo leaves no 'already on its way' line behind.")
        await f.graph.session.endSession()
    }

    @Test("Online: Undo while the +1 is on its way (attempted, no receipt yet) works, and survives the receipt")
    func undoWhileTheSendIsInFlight() async throws {
        let f = try await fixture()
        defer { f.cleanup() }
        let before = f.graph.home.displayedProgress(for: f.card)
        await f.graph.home.advance(f.card)
        let after = f.graph.home.displayedProgress(for: f.card)
        // The drain has claimed the +1 and the request is out (in flight, attempted, no receipt).
        f.graph.library.cancelProgressWork()
        let claimed = try await f.outbox.claim(accountId: f.account.userId.lowercased(), limit: 50)
        let plusOne = try #require(claimed.first)
        #expect(plusOne.position == after)

        let result = await HomeProgressToasts.performUndo(undo(f, before: before, after: after), card: f.card,
                                                          home: f.graph.home, session: f.graph.accountSession)
        #expect(result == .undone)
        #expect(f.graph.home.displayedProgress(for: f.card) == before)
        // The receipt for the +1 arrives: the reversal is still queued behind it, so the count stays back.
        try await f.outbox.acknowledge(plusOne.mutationId, revision: 3, position: after)
        try await f.graph.library.restoreProgress()
        #expect(f.graph.home.displayedProgress(for: f.card) == before)
        let queued = try await f.outbox.active(accountId: f.account.userId.lowercased())
        #expect(queued.map(\.position) == [before])
        // Never sent while the +1 was out, the reversal is rebased on the +1's receipt.
        #expect(queued.first?.baseRevision == 3)
        await f.graph.session.endSession()
    }

    @Test("Undo before the drain has attempted the +1 cancels it: nothing is queued")
    func undoBeforeTheDrain() async throws {
        let f = try await fixture()
        defer { f.cleanup() }
        let before = f.graph.home.displayedProgress(for: f.card)
        await f.graph.home.advance(f.card)
        let after = f.graph.home.displayedProgress(for: f.card)
        f.graph.library.cancelProgressWork()
        let result = await HomeProgressToasts.performUndo(undo(f, before: before, after: after), card: f.card,
                                                          home: f.graph.home, session: f.graph.accountSession)
        #expect(result == .undone)
        #expect(f.graph.home.displayedProgress(for: f.card) == before)
        let queued = try await f.outbox.active(accountId: f.account.userId.lowercased())
        #expect(queued.isEmpty)
        await f.graph.session.endSession()
    }

    @Test("Undo never reverses a count that moved on since the +1; it says where the progress stays")
    func undoLeavesALaterChange() async throws {
        let f = try await fixture()
        defer { f.cleanup() }
        let before = f.graph.home.displayedProgress(for: f.card)
        await f.graph.home.advance(f.card)
        let after = f.graph.home.displayedProgress(for: f.card)
        f.graph.library.cancelProgressWork()
        await f.graph.home.drain()
        // While the toast is up, the title's page sets episode 10 (an unsent edit of its own).
        let user = SeriesDetailBundle.UserState(serverRevision: f.card.serverRevision, lifecycleId: f.card.lifecycleId,
                                                progress: f.card.progress, progressLabel: nil, listType: f.card.listType,
                                                notes: nil)
        await f.graph.home.setPosition(medium: "anime", mediaId: f.card.mediaId, user: user, position: 10)
        f.graph.library.cancelProgressWork()
        #expect(f.graph.home.displayedProgress(for: f.card) == 10)
        let result = await HomeProgressToasts.performUndo(undo(f, before: before, after: after), card: f.card,
                                                          home: f.graph.home, session: f.graph.accountSession)
        #expect(result == .undoFailed(position: 10, manga: false))
        #expect(f.graph.home.displayedProgress(for: f.card) == 10, "The page's edit is neither cancelled nor wound back.")
        let queued = try await f.outbox.active(accountId: f.account.userId.lowercased())
        #expect(queued.map(\.position) == [after, 10])
        await f.graph.session.endSession()
    }

    // MARK: Copy

    @Test("A failed Undo says the +1 stands and where the progress stays, EN and DE")
    func undoFailedCopy() {
        #expect(HomeProgressToastCopy.message(.undoFailed(position: 7, manga: false), german: false)
                == "Couldn't undo. Your progress stays at Ep. 7.")
        #expect(HomeProgressToastCopy.message(.undoFailed(position: 7, manga: true), german: false)
                == "Couldn't undo. Your progress stays at Ch. 7.")
        #expect(HomeProgressToastCopy.message(.undoFailed(position: 7, manga: false), german: true)
                == "Rückgängig nicht möglich. Dein Stand bleibt bei Folge 7.")
        #expect(HomeProgressToastCopy.message(.undoFailed(position: 7, manga: true), german: true)
                == "Rückgängig nicht möglich. Dein Stand bleibt bei Kapitel 7.")
        // "Not saved." stays only for a +1 that was not saved.
        #expect(HomeProgressToastCopy.undoResult(before: 4, after: 4, manga: false) == .undone)
        #expect(HomeProgressToastCopy.undoResult(before: 4, after: 5, manga: false) == .undoFailed(position: 5, manga: false))
        #expect(HomeProgressToastCopy.undoResult(before: 4, after: 5, manga: true) != .failed)
    }

    // MARK: Status line

    @Test("'Saved on this device.' shows while a save is still pending, online or offline")
    func statusLineFollowsTheOutbox() {
        func shows(_ status: String, pending: Bool = false, offline: Bool = false, toast: Bool = false) -> Bool {
            HomeProgressToastCopy.statusLineShows(status, savedOnDevice: "Saved on this device", notSaved: "Not saved",
                                                  onItsWay: "On its way", savePending: pending, offline: offline,
                                                  toastShowing: toast)
        }
        // A save stuck in the outbox while online is shown once the toast has gone.
        #expect(shows("Saved on this device", pending: true))
        #expect(shows("Saved on this device", pending: true, offline: true))
        #expect(shows("Saved on this device", pending: true, offline: true, toast: true))
        // Online, while the toast says "Progress saved.", the line waits for the toast to go.
        #expect(!shows("Saved on this device", pending: true, toast: true))
        // Acknowledged: Library still holds the message, but nothing is pending, so the line is gone.
        #expect(!shows("Saved on this device"))
        #expect(!shows("Saved on this device", offline: true))
        #expect(!shows("Not saved", toast: true))
        #expect(shows("Not saved"))
        #expect(!shows("On its way", toast: true))
        #expect(shows("Choose the next episode on its page."))
    }

    // MARK: Hold with assistive technology

    @Test("With VoiceOver or Switch Control on, the +1 toast and the Plan toast stay until dismissed")
    func toastsWaitForAssistiveTechnology() async throws {
        let account = AccountContext(userId: "a", generation: 1)
        let undo = HomeProgressToasts.Undo(medium: "anime", mediaId: 7, lifecycleId: "L", before: 4, after: 5,
                                           account: account)
        let held = HomeProgressToasts(holdSeconds: 0.05, assistiveTechnologyRunning: { true })
        held.show("Progress saved.", undo: undo)
        let plans = TastePlanController(holdSeconds: 0.05, assistiveTechnologyRunning: { true })
        plans.show("Added to your list.", undo: nil)
        let timed = HomeProgressToasts(holdSeconds: 0.05, assistiveTechnologyRunning: { false })
        timed.show("Progress saved.", undo: undo)
        try await Task.sleep(for: .milliseconds(300))
        #expect(held.toast != nil, "VoiceOver: the +1 toast waits for Undo or ×.")
        #expect(plans.toast != nil, "VoiceOver: the Plan toast waits for Undo or ×.")
        #expect(timed.toast == nil, "Without assistive technology the toast leaves after its hold.")
        held.dismiss()
        plans.dismiss()
        #expect(held.toast == nil && plans.toast == nil)
        #expect(KuroToastHold.holdsUntilDismissed(voiceOver: true, switchControl: false))
        #expect(KuroToastHold.holdsUntilDismissed(voiceOver: false, switchControl: true))
        #expect(!KuroToastHold.holdsUntilDismissed(voiceOver: false, switchControl: false))
    }

    // MARK: Medium word ink (round 3)

    @Test("The selected word stays decisively darker than the unselected word, and white art never shows pale")
    func selectedWordReadsDark() {
        func luma(_ c: KuroRGB) -> Double { 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
        let unselected = luma(HomeMediumWordInk.unselected)
        // At least 30 levels (of 255) darker than #6e786f, as the reference's pair (about 36).
        #expect((unselected - HomeMediumWordInk.targetLuma) * 255 >= 30)
        #expect(HomeMediumWordInk.targetLuma <= 0.33)
        // No channel of the art lighter than about #8e938c: a white page reads as a mid-tone.
        #expect(luma(HomeMediumWordInk.highlightCeiling) <= 0.58)
        #expect(luma(HomeMediumWordInk.highlightCeiling) > HomeMediumWordInk.targetLuma)
    }
}
