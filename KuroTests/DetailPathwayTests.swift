//
//  DetailPathwayTests.swift
//  KuroTests
//
//  Round-2 pathway fixes on the one detail page (prototype fidelity, Task 10 review):
//  - Up next +1 on a Planned title moves it to Watching/Reading in the same edit (Home then reaches
//    its in-progress scene), and Undo reverts the whole change.
//  - "Remove from list" asks first when there is something to lose, and its Undo restores the row.
//  - A failed ladder read is told apart from an empty one; rows without a target are not buttons.
//

import Foundation
import Testing
import KuroCore
import KuroLibrary
import SwiftUI
@testable import Kuro

@MainActor
@Suite("Detail pathways", .serialized)
struct DetailPathwayTests {

    // MARK: Up next +1 on a Planned title

    @Test("+1 on a Planned title names Watching in the same edit; other statuses stay progress-only")
    func advanceEditPromotesOnlyPlanned() {
        #expect(DetailAdvance.edit(status: .planning, to: 1) == LibraryEdit(status: .set(.current), progress: .set(1)))
        #expect(DetailAdvance.edit(status: .current, to: 7) == LibraryEdit(progress: .set(7)))
        #expect(DetailAdvance.edit(status: .completed, to: 3) == LibraryEdit(progress: .set(3)))
        #expect(DetailAdvance.edit(status: .paused, to: 3) == LibraryEdit(progress: .set(3)))
        #expect(DetailAdvance.edit(status: .dropped, to: 3) == LibraryEdit(progress: .set(3)))
        #expect(DetailAdvance.edit(status: .repeating, to: 3) == LibraryEdit(progress: .set(3)))
        // Untracked: the progress write creates the row as Watching (`createIfMissing: .current`).
        #expect(DetailAdvance.edit(status: nil, to: 1) == LibraryEdit(progress: .set(1)))
    }

    @Test("Planned → +1 reaches Home's in-progress scene and ends the new-account block; Undo restores Planned")
    func plannedAdvanceReachesBusyHome() async throws {
        let graph = try await Self.graph(rows: [FakeLibraryBackend.entry(.anime, 5, rowId: 5, status: .planning, progress: 0)])
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .anime, id: 5)
        let before = try #require(graph.library.entry(for: key))
        #expect(before.status == .planning)
        #expect(HomeShelfPolicy.showsNewAccount(latched: true, onlyPlannedTitles: true,
                                                scene: HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: [before.status]),
                                                otherMediumOccupied: false))

        let outcome = await DetailAdvance.advance(key, from: before.status, to: 1, actions: graph.libraryActions)
        let change = try #require(outcome.change, "the +1 was not applied: \(String(describing: outcome.error))")
        let after = try #require(graph.library.entry(for: key))
        #expect(after.status == .current)
        #expect(after.progress == 1)
        let scene = HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: [after.status])
        #expect(scene == .inProgress)
        #expect(!HomeShelfPolicy.showsNewAccount(latched: true, onlyPlannedTitles: after.status == .planning,
                                                 scene: scene, otherMediumOccupied: false))

        // Undo reverts the whole change: the count and the saved status.
        let undoEdit = try #require(DetailAdvance.undoEdit(change, projection: graph.library.entry(for: key)))
        #expect(undoEdit == LibraryEdit(status: .set(.planning), progress: .set(0)))
        let undone = await graph.libraryActions.apply(undoEdit, to: key, createIfMissing: nil)
        #expect(undone.error == nil)
        let restored = try #require(graph.library.entry(for: key))
        #expect(restored.status == .planning)
        #expect(restored.progress == 0)
    }

    @Test("Durable branch: Planned → +1 projects Watching/Reading and sends WATCHING/READING",
          .timeLimit(.minutes(1)), arguments: [MediaKind.anime, MediaKind.manga])
    func plannedAdvanceThroughProgressOutbox(kind: MediaKind) async throws {
        let server = StubServer()
        defer { server.shutDown() }
        server.respond { request in
            guard request.resource == "rpc/apply_progress_mutations_v1" else { return .emptyArray }
            // Acknowledge every mutation the drain sends, as the server does.
            let mutations = (request.jsonObject?["p_mutations"] as? [[String: Any]]) ?? []
            let items = mutations.map { mutation -> String in
                let id = mutation["mutation_id"] as? String ?? ""
                let position = mutation["position"] as? Int ?? 0
                return #"{"mutation_id":"\#(id)","outcome":"applied","server_revision":2,"position":\#(position)}"#
            }
            return .json(#"{"items":[\#(items.joined(separator: ","))]}"#)
        }
        let suite = "detail-pathways-durable-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let outbox = try ProgressOutbox(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suite).sqlite").path)
        var row = FakeLibraryBackend.entry(kind, 9, rowId: 9, status: .planning, progress: 0)
        row.lifecycleId = UUID()
        row.revision = 1
        let backend = FakeLibraryBackend()
        backend.setRows([row], for: LifecycleFixtures.userA)
        let graph = AppComposition.testingGraph(
            testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
            client: StubSupabase.makeClient(server: server), libraryBackend: backend,
            flags: FeatureFlags(userDefaults: defaults, launchArguments: ["--ff-on=series_foundation_v1"]),
            progressOutbox: outbox)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        defer { Task { await graph.session.endSession() } }
        try await graph.library.refresh()
        #expect(graph.library.progressAvailable, "the durable branch needs the outbox and the series flag")

        let key = MediaKey(kind: kind, id: 9)
        let outcome = await DetailAdvance.advance(key, from: .planning, to: 1, actions: graph.libraryActions)
        #expect(outcome.change != nil, "the +1 was not applied: \(String(describing: outcome.error))")
        // The local projection: Watching/Reading at 1, so Home reaches its in-progress scene.
        let projected = try #require(graph.library.entry(for: key))
        #expect(projected.status == .current)
        #expect(projected.progress == 1)
        #expect(HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: [projected.status]) == .inProgress)
        // The stored intent carries the status (`status: nil` before the round-2 fix).
        let stored = try await outbox.latest(accountId: LifecycleFixtures.userA.lowercased(),
                                             medium: kind.rawValue.lowercased(), mediaId: 9)
        #expect(stored?.status == ListStatus.current.rawValue)
        #expect(stored?.position == 1)
        // The wire: HomeStore's sender maps it to the medium's server word.
        let request = await server.waitForRequest { $0.resource == "rpc/apply_progress_mutations_v1" }
        let mutation = try #require((request.jsonObject?["p_mutations"] as? [[String: Any]])?.first)
        #expect(mutation["status"] as? String == (kind == .manga ? "READING" : "WATCHING"))
        #expect(mutation["position"] as? Int == 1)
        #expect(mutation["media_id"] as? Int == 9)
    }

    @Test("Undo of a plain +1 moves only the count back")
    func undoOfPlainAdvanceIsProgressOnly() async throws {
        let graph = try await Self.graph(rows: [FakeLibraryBackend.entry(.anime, 6, rowId: 6, status: .current, progress: 4)])
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .anime, id: 6)
        let outcome = await DetailAdvance.advance(key, from: .current, to: 5, actions: graph.libraryActions)
        let change = try #require(outcome.change)
        #expect(graph.library.entry(for: key)?.status == .current)
        #expect(DetailAdvance.undoEdit(change, projection: graph.library.entry(for: key)) == LibraryEdit(progress: .set(4)))
    }

    // MARK: Remove from list

    @Test("The tracked menu item reads Remove from list (not Saved · remove)")
    func removeCopy() {
        #expect(DetailStatusCopy.actionTitle(.favourite, isTracked: true, kind: .anime, german: false) == "Remove from list")
        #expect(DetailStatusCopy.actionTitle(.favourite, isTracked: true, kind: .manga, german: true) == "Von der Liste entfernen")
        #expect(DetailStatusCopy.actionTitle(.favourite, isTracked: false, kind: .anime, german: false) == "Save")
    }

    @Test("Removal asks first whenever the entry holds anything beyond a bare plan")
    func removalConfirmation() {
        func entry(_ status: ListStatus, progress: Int = 0, rating: Int? = nil, notes: String? = nil) -> LibraryEntry {
            FakeLibraryBackend.entry(.anime, 1, rowId: 1, status: status, progress: progress, rating: rating, notes: notes)
        }
        #expect(!DetailRemoval.needsConfirmation(entry(.planning)))
        #expect(DetailRemoval.needsConfirmation(entry(.current)))
        #expect(DetailRemoval.needsConfirmation(entry(.planning, progress: 2)))
        #expect(DetailRemoval.needsConfirmation(entry(.planning, notes: "later")))
        #expect(DetailRemoval.needsConfirmation(entry(.planning, rating: 8)))
    }

    @Test("Undo after Remove restores the row with its progress and notes")
    func removalUndoRestoresTheRow() async throws {
        let graph = try await Self.graph(rows: [FakeLibraryBackend.entry(.manga, 9, rowId: 9, status: .current, progress: 12,
                                                                         rating: 7, notes: "keep")])
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .manga, id: 9)
        let previous = try #require(graph.library.entry(for: key))
        let account = try #require(graph.libraryActions.accountSession.current)
        let removed = await graph.libraryActions.remove(key)
        #expect(removed.error == nil)
        #expect(graph.library.entry(for: key) == nil)

        let restore = DetailRemoval.restoreEdit(previous)
        #expect(restore.status == .set(.current))
        #expect(restore.progress == .set(12))
        let outcome = await graph.libraryActions.apply(restore, to: key, createIfMissing: previous.status)
        #expect(outcome.error == nil)
        let back = try #require(graph.library.entry(for: key))
        #expect(back.status == .current)
        #expect(back.progress == 12)
        #expect(back.notes == "keep")
        #expect(back.rating == previous.rating)
    }

    // MARK: F2 review fixes: Undo never fills, restores everything, and removes only what the fill added

    private static func tracked(_ status: ListStatus, progress: Int = 0, metadata: LibrarySourceMetadata?) -> LibraryEntry {
        var entry = FakeLibraryBackend.entry(.anime, 5, rowId: 5, status: status, progress: progress)
        entry.sourceMetadata = metadata
        return entry
    }

    @Test("Removal Undo with the switch on restores the repeat count and the raw dates exactly, and fills nothing")
    func removalUndoRestoresEveryFieldAndNeverFills() async throws {
        let graph = try await Self.graph(
            rows: [Self.tracked(.completed, progress: 12,
                                metadata: LibrarySourceMetadata(repeatCount: 2, startedRaw: "2019-05-00", finishedRaw: "not-a-date"))],
            autofill: true)
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .anime, id: 5)
        let previous = try #require(graph.library.entry(for: key))
        let account = try #require(graph.libraryActions.accountSession.current)
        #expect((await graph.libraryActions.remove(key)).error == nil)

        let outcome = await graph.libraryActions.restore(DetailRemoval.restoreEdit(previous), to: key, createIfMissing: previous.status, account: account)
        #expect(outcome.error == nil)
        let back = try #require(graph.library.entry(for: key))
        #expect(back.sourceMetadata?.repeatCount == 2)
        #expect(back.sourceMetadata?.startedRaw == "2019-05-00")
        #expect(back.sourceMetadata?.finishedRaw == "not-a-date")
    }

    @Test("Removal Undo of a title with empty dates leaves them empty although the switch is on")
    func removalUndoDoesNotFillEmptyDates() async throws {
        let graph = try await Self.graph(rows: [Self.tracked(.current, metadata: LibrarySourceMetadata(repeatCount: 0))], autofill: true)
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .anime, id: 5)
        let previous = try #require(graph.library.entry(for: key))
        let account = try #require(graph.libraryActions.accountSession.current)
        _ = await graph.libraryActions.remove(key)
        let outcome = await graph.libraryActions.restore(DetailRemoval.restoreEdit(previous), to: key, createIfMissing: previous.status, account: account)
        #expect(outcome.error == nil)
        let back = try #require(graph.library.entry(for: key))
        #expect(back.sourceMetadata?.startedRaw == nil, "Undo filled today's date: \(String(describing: back.sourceMetadata))")
        #expect(back.sourceMetadata?.finishedRaw == nil)
    }

    @Test("A Planned title with dates or a repeat count is not a bare plan: removing it asks first")
    func removalConfirmationCountsDatesAndRepeats() {
        #expect(!DetailRemoval.needsConfirmation(Self.tracked(.planning, metadata: LibrarySourceMetadata(repeatCount: 0))))
        #expect(DetailRemoval.needsConfirmation(Self.tracked(.planning, metadata: LibrarySourceMetadata(repeatCount: 1))))
        #expect(DetailRemoval.needsConfirmation(Self.tracked(.planning, metadata: LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024"))))
        #expect(DetailRemoval.needsConfirmation(Self.tracked(.planning, metadata: LibrarySourceMetadata(repeatCount: 0, finishedRaw: "garbled"))))
    }

    @Test("+1 on a Planned title with no dates, then Undo: Planned, 0, no start date, a bare plan again")
    func plusOneUndoClearsTheDateTheFillAdded() async throws {
        let graph = try await Self.graph(rows: [Self.tracked(.planning, metadata: LibrarySourceMetadata(repeatCount: 0))], autofill: true)
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .anime, id: 5)
        let outcome = await DetailAdvance.advance(key, from: .planning, to: 1, actions: graph.libraryActions)
        let change = try #require(outcome.change)
        #expect(graph.library.entry(for: key)?.startedOn != nil, "the fill added a start date")

        let undoEdit = try #require(DetailAdvance.undoEdit(change, projection: graph.library.entry(for: key)))
        let undone = await DetailAdvance.undo(undoEdit, key, account: change.account, actions: graph.libraryActions)
        #expect(undone.error == nil)
        let restored = try #require(graph.library.entry(for: key))
        #expect(restored.status == .planning && restored.progress == 0)
        #expect(restored.sourceMetadata?.startedRaw == nil)
        #expect(TastePlanAction.isBarePlan(restored))
    }

    @Test("+1 Undo never clears a date the title already had, or that the user set")
    func plusOneUndoKeepsAnExistingDate() async throws {
        let graph = try await Self.graph(
            rows: [Self.tracked(.planning, metadata: LibrarySourceMetadata(repeatCount: 0, startedRaw: "2020-01-00"))], autofill: true)
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .anime, id: 5)
        let change = try #require((await DetailAdvance.advance(key, from: .planning, to: 1, actions: graph.libraryActions)).change)
        let undoEdit = try #require(DetailAdvance.undoEdit(change, projection: graph.library.entry(for: key)))
        #expect(undoEdit.startedOn == .unchanged && undoEdit.finishedOn == .unchanged)
        _ = await DetailAdvance.undo(undoEdit, key, account: change.account, actions: graph.libraryActions)
        #expect(graph.library.entry(for: key)?.sourceMetadata?.startedRaw == "2020-01-00")
    }

    @Test("+1 fills today, the user then saves another start date: Undo keeps the user's date")
    func plusOneUndoKeepsADateTheUserSetAfterwards() async throws {
        let graph = try await Self.graph(rows: [Self.tracked(.planning, metadata: LibrarySourceMetadata(repeatCount: 0))], autofill: true)
        defer { Task { await graph.session.endSession() } }
        let key = MediaKey(kind: .anime, id: 5)
        let change = try #require((await DetailAdvance.advance(key, from: .planning, to: 1, actions: graph.libraryActions)).change)
        let filled = try #require(graph.library.entry(for: key)?.sourceMetadata?.startedRaw)
        let chosen = try #require(PartialDate(raw: "2026-11-01"))
        #expect(filled != "2026-11-01")
        #expect((await graph.libraryActions.apply(LibraryEdit(startedOn: .set(chosen)), to: key, createIfMissing: nil)).error == nil)

        let undoEdit = try #require(DetailAdvance.undoEdit(change, projection: graph.library.entry(for: key)))
        #expect(undoEdit.startedOn == .unchanged, "Undo would wipe the date the user set")
        _ = await DetailAdvance.undo(undoEdit, key, account: change.account, actions: graph.libraryActions)
        #expect(graph.library.entry(for: key)?.sourceMetadata?.startedRaw == "2026-11-01")
    }

    @Test("Removal confirmation names dates and the repeat count only when the entry holds them")
    func removalMessageMentionsDatesAndRepeats() {
        let bare = Self.tracked(.current, progress: 3, metadata: LibrarySourceMetadata(repeatCount: 0))
        let dated = Self.tracked(.current, progress: 3, metadata: LibrarySourceMetadata(repeatCount: 0, startedRaw: "2024"))
        let repeated = Self.tracked(.current, progress: 3, metadata: LibrarySourceMetadata(repeatCount: 2))
        let both = Self.tracked(.completed, progress: 3, metadata: LibrarySourceMetadata(repeatCount: 2, finishedRaw: "garbled"))
        let unknown = Self.tracked(.current, progress: 3, metadata: nil)
        for german in [false, true] {
            let dates = german ? "Daten" : "dates"
            let repeats = german ? "Wiederholungen" : "rewatch count"
            let message = { (entry: LibraryEntry) in DetailRemoval.confirmMessage(kind: .anime, entry: entry, german: german) }
            #expect(!message(bare).contains(dates) && !message(bare).contains(repeats))
            #expect(!message(unknown).contains(dates) && !message(unknown).contains(repeats))
            #expect(message(dated).contains(dates) && !message(dated).contains(repeats))
            #expect(message(repeated).contains(repeats) && !message(repeated).contains(dates))
            #expect(message(both).contains(dates) && message(both).contains(repeats))
        }
        #expect(DetailRemoval.confirmMessage(kind: .manga, entry: repeated, german: false).contains("reread count"))
    }

    // MARK: Reads, rows, chrome

    @Test("A failed ladder read is told apart from a title without relations")
    func ladderFailureIsNotEmpty() throws {
        #expect(DetailReadState.ladderFailed(.empty))
        let json = #"{"source_material":[],"adaptations":[],"prequels":[],"sequels":[],"side_stories":[],"spin_offs":[],"coverage_status":"minimal"}"#
        let answered = try JSONDecoder().decode(MediaLadderResponse.self, from: Data(json.utf8))
        #expect(!DetailReadState.ladderFailed(answered))
    }

    @Test("Credit rows without a target and episode rows without details are not buttons")
    func rowsWithoutTargetAreStatic() {
        #expect(!DetailCreditRow(role: "Original work", name: "Gege Akutami", target: .none).isInteractive)
        let studio = Studio(id: 1, anilistId: nil, name: "MAPPA", isAnimationStudio: true, siteUrl: nil, favourites: nil)
        #expect(DetailCreditRow(role: "Animation", name: "MAPPA", target: .studio(studio)).isInteractive)
        #expect(!AnimeUnitsSection.isExpandable(description: nil, streamURL: nil))
        #expect(AnimeUnitsSection.isExpandable(description: "The barrier closes.", streamURL: nil))
    }

    @Test("The detail journey always shows the drag indicator (navigation contract N8)")
    func loaderChrome() {
        #expect(DetailLoaderChrome.dragIndicator == .visible)
    }

    @Test("Manga collapsed chapters: only the finished row follows Up next")
    func mangaCollapsedRows() {
        let chapters = (24...33).map { number in
            MangaChapter(id: number, mangaId: 30, number: number, title: "Chapter \(number)", titleRomaji: nil, description: nil,
                         releaseDate: Date(timeIntervalSince1970: 1_560_000_000), releaseAt: nil, thumbnail: nil, pages: nil,
                         createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
        }
        #expect(MangaChaptersSection.collapsedRows(chapters, progress: 24).map(\.number) == [24])
    }

    @Test("The story's disclosure exists only when it reveals something")
    func storyDisclosure() {
        // Hook-led: the synopsis sits behind "About this season +".
        #expect(DetailStoryDisclosure.showsToggle(hasHook: true, truncated: false, hasExpectation: false))
        // Synopsis-led and fully shown, nothing else to reveal: no dead "+".
        #expect(!DetailStoryDisclosure.showsToggle(hasHook: false, truncated: false, hasExpectation: false))
        #expect(DetailStoryDisclosure.showsToggle(hasHook: false, truncated: true, hasExpectation: false))
        #expect(DetailStoryDisclosure.showsToggle(hasHook: false, truncated: false, hasExpectation: true))
        #expect(DetailStoryDisclosure.label(hasHook: false, expanded: false, about: "About this season", german: false) == "More")
        #expect(DetailStoryDisclosure.label(hasHook: false, expanded: true, about: "About this season", german: false) == "Show less")
        #expect(DetailStoryDisclosure.label(hasHook: true, expanded: false, about: "About this season", german: false) == "About this season")
    }

    @Test("A note's byline names a club only when the author is provably in it")
    func noteClubIsProven() {
        // One club: every friend shares it.
        #expect(DetailBetweenUs.clubName(authorId: "u1", railClubs: [], myClubNames: ["Sunday Club"]) == "Sunday Club")
        // Several clubs: only a cached roster that lists the author names one.
        let rails = [(name: "Film Night", memberIds: ["u7"]), (name: "Sunday Club", memberIds: ["u1", "u2"])]
        #expect(DetailBetweenUs.clubName(authorId: "u1", railClubs: rails, myClubNames: ["Film Night", "Sunday Club"]) == "Sunday Club")
        #expect(DetailBetweenUs.clubName(authorId: "u9", railClubs: rails, myClubNames: ["Film Night", "Sunday Club"]) == nil)
    }

    @Test("Note reactions: titles carry counts, the tally exists only when there are reactions")
    func noteReactionCopy() {
        #expect(NoteReaction.title(.up, count: 0, german: false) == "Like thought")
        #expect(NoteReaction.title(.up, count: 3, german: false) == "Like thought (3)")
        #expect(NoteReaction.title(.down, count: 1, german: true) == "Gedanken nicht mögen (1)")
        #expect(NoteReaction.tally(up: 0, down: 0, mine: nil) == nil)
        #expect(NoteReaction.tally(up: 2, down: 1, mine: nil) == "↑2 ↓1")
        // The viewer's own reaction always shows, even before the count refreshes.
        #expect(NoteReaction.tally(up: 0, down: 0, mine: "up") == "↑1")
        #expect(NoteReaction.up.icon(active: true) == "hand.thumbsup.fill")
        #expect(NoteReaction.down.icon(active: false) == "hand.thumbsdown")
    }

    @Test("Club avatars cycle the prototype's three fills")
    func avatarFills() {
        #expect(DetailAvatars.fillHex(0) == "D3DED3")
        #expect(DetailAvatars.fillHex(1) == "E2E3D7")
        #expect(DetailAvatars.fillHex(2) == "C8D4CE")
        #expect(DetailAvatars.fillHex(3) == "D3DED3")
    }

    // MARK: Harness

    private static func graph(rows: [LibraryEntry], autofill: Bool = false) async throws -> AppGraph {
        let suite = "detail-pathways-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let backend = FakeLibraryBackend()
        backend.setRows(rows, for: LifecycleFixtures.userA)
        let flags = FeatureFlags(userDefaults: defaults, launchArguments: autofill ? ["--ff-on=library_date_autofill_v1"] : [])
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend, flags: flags)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        try await graph.library.refresh()
        return graph
    }
}
