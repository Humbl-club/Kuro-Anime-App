import Foundation
import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

// MARK: - Discover usability, lane B (preview, quick actions, See all, mood journeys; 2026-11-04)
// Pure rules and owner wiring of the long-press menu, the feedback toast and its Undo, the See all
// sort / chip mapping and the mood journey, plus the "after" renders. Renders go to
// docs/discover-usability-2026-11-04/after/du-preview-*.jpg (JPEG q80, ≤ 603 px wide) ONLY with
// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1` and `-only-testing:KuroTests/DUpreviewRenderTests`; ordinary runs
// render into a temporary folder. No network: the graphs run over an in-process stub PostgREST.

private enum DUP {
    static let userA = "AAAAAAAA-0000-4000-8000-0000000000B1"
    static let userB = "BBBBBBBB-0000-4000-8000-0000000000B2"
    static let signalRPC = "rpc/record_taste_deck_signal"
    static let signalOK = StubResponse.json(#"{"ok":true}"#)

    static func media(_ id: Int, kind: MediaKind = .anime, title: String = "Mushishi", episodes: Int? = 26,
                      format: String? = "TV", status: String? = "FINISHED") -> Media {
        Media(id: id, kind: kind, title: title, imageURL: nil, year: "2005", displayDescription: "",
              episodes: kind == .anime ? episodes : nil, chapters: kind == .manga ? 120 : nil, rating: 8.7,
              genres: ["Drama"], statusRaw: status, formatRaw: format, popularityValue: nil,
              trendingValue: nil, createdAtValue: nil)
    }

    static func card(_ id: Int, kind: MediaKind = .anime, title: String = "Mushishi") -> TasteCard {
        TasteCard(media: media(id, kind: kind, title: title))
    }

    static func entry(_ id: Int, status: ListStatus, kind: MediaKind = .anime) -> LibraryEntry {
        LibraryEntry(key: MediaKey(kind: kind, id: id), rowId: id, status: status, progress: 0,
                     createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }
}

/// A TasteStore over its own defaults suite and a stub signal endpoint (never `.standard`).
@MainActor
private struct DUPTaste {
    let server = StubServer()
    let accountSession = AccountSessionCoordinator()
    let suiteName = "kuro.tests.du-preview.\(UUID().uuidString)"
    let defaults: UserDefaults
    let taste: TasteStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        server.respond { request in
            switch request.resource {
            case DUP.signalRPC: return DUP.signalOK
            default: return .emptyArray
            }
        }
        taste = TasteStore(client: StubSupabase.makeClient(server: server), accountSession: accountSession,
                           libraryHook: LibraryRefreshHook(), retryBaseDelay: 10, defaults: defaults)
    }

    func sentSignals() -> [String] {
        server.requests.filter { $0.resource == DUP.signalRPC }.compactMap { request in
            guard let body = request.jsonObject, let action = body["p_action"] as? String,
                  let id = body["p_media_id"] as? Int else { return nil }
            return "\(action) \(id)"
        }
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}

// MARK: - Menu, toast, Undo

@MainActor
@Suite("Discover usability lane B: preview menu and feedback", .serialized, .timeLimit(.minutes(2)))
struct DUpreviewTests {
    @Test("The menu offers Seen it / Not interested only for a title off the list, with a session; Add to club only in a club")
    func menuOffer() {
        let off = DiscoverMenuOffer.offer(entry: nil, signedIn: true, inAClub: false)
        #expect(off.plan == .plan && off.answers && !off.addToClub)
        let planned = DiscoverMenuOffer.offer(entry: DUP.entry(1, status: .planning), signedIn: true, inAClub: true)
        #expect(planned.plan == .unplan && !planned.answers && planned.addToClub)
        let watching = DiscoverMenuOffer.offer(entry: DUP.entry(1, status: .current), signedIn: true, inAClub: false)
        #expect(watching.plan == .edit && !watching.answers)
        let signedOut = DiscoverMenuOffer.offer(entry: nil, signedIn: false, inAClub: false)
        #expect(!signedOut.answers)
    }

    @Test("Menu words: EXISTING strings byte-identical, every new string has German")
    func menuCopy() {
        #expect(DiscoverMenuCopy.planItem(.plan, medium: .anime, german: true) == "Vormerken")
        #expect(DiscoverMenuCopy.planItem(.plan, medium: .anime, german: false) == "Plan to watch")
        #expect(DiscoverMenuCopy.planItem(.plan, medium: .manga, german: false) == "Plan to read")
        #expect(DiscoverMenuCopy.planItem(.unplan, medium: .anime, german: false) == "Remove from Planned")
        #expect(DiscoverMenuCopy.planItem(.edit, medium: .anime, german: false) == "Edit list entry")
        #expect(DiscoverMenuCopy.planItem(.edit, medium: .anime, german: true) == "Listeneintrag bearbeiten")
        #expect(DiscoverMenuCopy.addToClub(german: false) == "Add to club\u{2026}")
        #expect(DiscoverMenuCopy.addToClub(german: true) == "Zu einem Club hinzufügen\u{2026}")
        #expect(DiscoverMenuCopy.seenIt(medium: .manga, german: false) == "Already read")
        #expect(DiscoverMenuCopy.seenIt(medium: .anime, german: true) == "Schon gesehen")
        #expect(DiscoverMenuCopy.notInterested(german: true) == "Kein Interesse")
        #expect(DiscoverMenuCopy.undone(german: false) == "Undone.")
        #expect(DiscoverMenuCopy.undo(german: true) == "Rückgängig")
        #expect(DiscoverMenuCopy.toast(.notInterested, german: false) == "Hidden. You'll see fewer like it.")
        #expect(DiscoverMenuCopy.toast(.seenIt, german: true) == "Als gesehen markiert.")
        #expect(DiscoverMenuCopy.hiddenAnnouncement(german: true) == "Ausgeblendet. Rückgängig möglich.")
        #expect(DiscoverMenuCopy.previewKicker(kind: .anime, section: "New to you.", german: false) == "ANIME · NEW TO YOU")
        #expect(DiscoverMenuCopy.previewKicker(kind: .manga, section: nil, german: true) == "MANGA")
        #expect(DiscoverMenuCopy.whyItsHere("in our canon", german: false) == "Why it's here: in our canon.")
        #expect(DiscoverMenuCopy.whyItsHere(nil, german: false) == nil)
        #expect(DiscoverMenuCopy.catalogStatusWord("FINISHED", kind: .anime, german: true) == "Fertig erschienen")
        #expect(DiscoverMenuCopy.catalogStatusWord("RELEASING", kind: .manga, german: false) == "Ongoing")
        #expect(DiscoverMenuCopy.previewFacts(kind: .anime, year: "2005", formatRaw: "TV", episodes: 26, chapters: nil,
                                              statusRaw: "FINISHED", german: false) == "2005 · TV · 26 eps · Finished")
        #expect(DiscoverMenuCopy.statusWord(.completed, medium: .anime, german: true) == "Abgeschlossen")
        for german in [false, true] {
            for text in [DiscoverMenuCopy.seenItSubtitle(german: german), DiscoverMenuCopy.notInterestedSubtitle(german: german),
                         DiscoverMenuCopy.open(german: german), DiscoverMenuCopy.addAsCompleted(german: german)] {
                #expect(!text.isEmpty)
            }
        }
        #expect(DiscoverMenuCopy.seenItSubtitle(german: false) != DiscoverMenuCopy.seenItSubtitle(german: true))
    }

    @Test("Not interested: one .skip signal, the hide toast with Undo; Undo reverses once and sends .retract")
    func notInterestedAndUndo() async throws {
        let fixture = try DUPTaste()
        defer { fixture.tearDown() }
        _ = fixture.accountSession.begin(userId: DUP.userA)
        let controller = DiscoverFeedbackController(assistiveTechnologyRunning: { true })
        let card = DUP.card(42)
        let receipt = try #require(controller.record(.notInterested, for: card.media, taste: fixture.taste, german: false))
        #expect(fixture.taste.isHiddenOnDiscover(card.key))
        let toast = try #require(controller.toast)
        #expect(toast.message == "Hidden. You'll see fewer like it.")
        #expect(toast.action == nil)
        #expect(toast.receipt == receipt)
        #expect(controller.hiddenCount == 1)
        await fixture.taste.drainTask?.value
        #expect(fixture.sentSignals() == ["skip 42"])

        let undone = controller.undo(taste: fixture.taste, german: false)
        #expect(undone == receipt)
        #expect(!fixture.taste.isHiddenOnDiscover(card.key))
        #expect(controller.toast?.message == "Undone.")
        #expect(controller.toast?.receipt == nil)
        #expect(controller.hiddenCount == 0)
        // Undo works once: the "Undone." toast carries no receipt.
        #expect(controller.undo(taste: fixture.taste, german: false) == nil)
        await fixture.taste.drainTask?.value
        #expect(fixture.sentSignals() == ["skip 42", "retract 42"])
    }

    @Test("Seen it: .known, the toast offers Add as Completed (the editor preset to Completed, nothing saved)")
    func seenItOffersCompleted() async throws {
        let fixture = try DUPTaste()
        defer { fixture.tearDown() }
        _ = fixture.accountSession.begin(userId: DUP.userA)
        let controller = DiscoverFeedbackController(assistiveTechnologyRunning: { true })
        let card = DUP.card(7, title: "Frieren")
        _ = try #require(controller.record(.seenIt, for: card.media, taste: fixture.taste, german: true))
        let toast = try #require(controller.toast)
        #expect(toast.message == "Als gesehen markiert.")
        #expect(toast.action == .addAsCompleted(card.key))
        let request = try #require(controller.completedRequest(for: card.key))
        #expect(request.initialStatus == .completed)
        #expect(request.media.libraryKey == card.key)
        #expect(controller.toast == nil)
        // The answer stays (the editor may still be cancelled).
        #expect(fixture.taste.discoverHidden[card.key] == .seenIt)
        await fixture.taste.drainTask?.value
        #expect(fixture.sentSignals() == ["known 7"])
    }

    @Test("Undo belongs to the account that answered: after a switch it does nothing")
    func undoSameAccountOnly() throws {
        let fixture = try DUPTaste()
        defer { fixture.tearDown() }
        _ = fixture.accountSession.begin(userId: DUP.userA)
        let controller = DiscoverFeedbackController(assistiveTechnologyRunning: { true })
        _ = try #require(controller.record(.notInterested, for: DUP.card(9).media, taste: fixture.taste, german: false))
        _ = fixture.accountSession.begin(userId: DUP.userB)
        #expect(controller.undo(taste: fixture.taste, german: false) == nil)
        #expect(controller.toast == nil)
    }

    @Test("Signed out: nothing is recorded and no toast shows")
    func signedOutRecordsNothing() throws {
        let fixture = try DUPTaste()
        defer { fixture.tearDown() }
        let controller = DiscoverFeedbackController(assistiveTechnologyRunning: { true })
        #expect(controller.record(.seenIt, for: DUP.card(3).media, taste: fixture.taste, german: false) == nil)
        #expect(controller.toast == nil)
    }

    @Test("The toast leaves after its hold, and waits while assistive technology runs")
    func toastHold() async throws {
        let fixture = try DUPTaste()
        defer { fixture.tearDown() }
        _ = fixture.accountSession.begin(userId: DUP.userA)
        let quick = DiscoverFeedbackController(holdSeconds: 0.05, assistiveTechnologyRunning: { false })
        _ = quick.record(.notInterested, for: DUP.card(11).media, taste: fixture.taste, german: false)
        #expect(quick.toast != nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(quick.toast == nil)
        let held = DiscoverFeedbackController(holdSeconds: 0.05, assistiveTechnologyRunning: { true })
        _ = held.record(.notInterested, for: DUP.card(12).media, taste: fixture.taste, german: false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(held.toast != nil)
    }

    @Test("One toast slot (D12): the feedback toast wins while set, else the Plan toast")
    func toastSlot() {
        let a = UUID(), b = UUID()
        #expect(DiscoverToastSlot.visible(feedback: nil, plan: nil) == .none)
        #expect(DiscoverToastSlot.visible(feedback: a, plan: nil) == .feedback(a))
        #expect(DiscoverToastSlot.visible(feedback: nil, plan: b) == .plan(b))
        #expect(DiscoverToastSlot.visible(feedback: a, plan: b) == .feedback(a))
    }

    @Test("Menu Plan telemetry: a menu plan is consumed once, a key plan reads as `key`")
    func menuPlanVia() {
        let controller = DiscoverFeedbackController()
        let key = MediaKey(kind: .anime, id: 5)
        #expect(!controller.consumeMenuPlan(key))
        controller.noteMenuPlan(key)
        #expect(controller.consumeMenuPlan(key))
        #expect(!controller.consumeMenuPlan(key))
        #expect(DiscoverPlanTelemetry.resultName(.added) == "added")
        #expect(DiscoverPlanTelemetry.resultName(.failed) == "failed")
        let extra = DiscoverMenuTelemetry.titleExtra(section: "animeTrending", position: 2, key: key)
        #expect(extra["media_type"] as? String == "ANIME")
        #expect(extra["media_id"] as? Int == 5)
        #expect(extra["position"] as? Int == 2)
        #expect(extra.count == 4)
    }

    // MARK: Plan stamp (additive TastePicksView API)

    @Test("Plan key stamp triggers: monotonic per title, confirm on added, failure on failed, never stepping back")
    func stampTokens() {
        let none = TastePlanKey.stampTokens(nil)
        #expect(none.confirm == 0 && none.failure == 0 && none.restore == 0)
        var count = TastePlanController.StampCount()
        count.added = 1
        let added = TastePlanKey.stampTokens(count)
        #expect(added.confirm == 1 && added.failure == 0 && added.restore == 1)
        count.failed = 1
        let failed = TastePlanKey.stampTokens(count)
        #expect(failed.confirm == 1 && failed.failure == 1 && failed.restore == 2)
        count.added = 2
        let next = TastePlanKey.stampTokens(count)
        #expect(next.confirm == 2 && next.restore == 3)
    }

    // MARK: Tracking editor preset (additive KuroRoutes / TrackingDraft / AddToListSheet API)

    @Test("Add as Completed: a title not on the list starts at Completed; the baseline stays Planned (N7 guard)")
    func trackingPreset() {
        let preset = TrackingDraft(entry: nil, initialStatus: .completed)
        let baseline = TrackingDraft(entry: nil)
        #expect(preset.status == .completed)
        #expect(baseline.status == .planning)
        #expect(preset.hasChanges(from: baseline))
        // An entry's own status always wins.
        let tracked = TrackingDraft(entry: DUP.entry(4, status: .current), initialStatus: .completed)
        #expect(tracked.status == .current)
        // The default keeps every call site (and the route id) unchanged.
        let plain = TrackingEditorRequest(media: DUP.media(4))
        #expect(plain.initialStatus == nil)
        var request = TrackingEditorRequest(media: DUP.media(4))
        request.initialStatus = .completed
        let route = AppRoute.trackingEditor(request)
        #expect(route.id == AppRoute.trackingEditor(plain).id)
        #expect(ToolDestinationView.initialStatus(of: route) == .completed)
        #expect(ToolDestinationView.initialStatus(of: .addToClub(MediaKey(kind: .anime, id: 4))) == nil)
    }

    @Test("journey_close payload: root kind, a title's id only, rounded seconds and depth")
    func journeyClose() {
        let title = JourneyCloseEvent.extra(root: .media(MediaRoute(kind: .manga, id: 77)), seconds: 3.6, depth: 2)
        #expect(title["root_kind"] as? String == "manga")
        #expect(title["media_id"] as? Int == 77)
        #expect(title["seconds"] as? Int == 4)
        #expect(title["depth"] as? Int == 2)
        let page = JourneyCloseEvent.extra(root: .browse, seconds: -1, depth: 0)
        #expect(page["root_kind"] as? String == "page")
        #expect(page["media_id"] == nil)
        #expect(page["seconds"] as? Int == 0)
        #expect(JourneyCloseEvent.rootKind(.club(id: "c")) == "club")
    }
}

// MARK: - See all

@MainActor
@Suite("Discover usability lane B: See all", .serialized, .timeLimit(.minutes(2)))
struct DUpreviewSeeAllTests {
    @Test("Every route maps to its section, medium and list kind; the sort words follow the list kind")
    func sections() {
        for route in EditorialDiscoverRoute.allCases {
            let section = DiscoverSeeAllSection.of(route)
            #expect(section.medium == (route.isManga ? .manga : .anime))
            #expect(section.sortWords.contains(section.defaultSort), "\(route.id)")
            if section.isCatalogue {
                #expect(section.sortWords == [.trending, .popular, .topRated, .justAdded])
            } else {
                #expect(section.sortWords.count == 4)
                #expect(section.sortWords.first == .ownOrder(section.order))
            }
        }
        #expect(DiscoverSeeAllSection.of(.animeTrending).isCatalogue)
        #expect(DiscoverSeeAllSection.of(.mangaNewlyAdded).defaultSort == .justAdded)
        #expect(DiscoverSeeAllSection.of(.animeTopRated).defaultSort == .topRated)
        #expect(!DiscoverSeeAllSection.of(.animeEssentials).isCatalogue)
        #expect(DiscoverSeeAllSection.of(.animeAiringToday).order == .airing)
        #expect(DiscoverSeeAllSection.of(.animeBecauseYou).order == .personal)
        #expect(DiscoverSeeAllSection.of(.animeNewToYou).ownedPolicy == .hide)
        #expect(DiscoverSeeAllSection.of(.animeEssentials).ownedPolicy == .mark)
        // Format and length are anime only.
        #expect(DiscoverSeeAllSection.of(.mangaTrending).chipGroups == [[.finished, .releasing], [.hideMyList]])
        #expect(DiscoverSeeAllSection.of(.animeTrending).chipGroups.count == 4)
    }

    @Test("Sort words map onto the data contract: Trending and Just added pick the catalogue order")
    func sortMapping() {
        let trending = DiscoverSeeAllSection.of(.animeTrending)
        var selection = DiscoverSeeAllSelection(sort: .justAdded)
        #expect(selection.query(for: trending).section == .newlyAdded)
        #expect(selection.query(for: trending).sort == .sectionOrder)
        selection.sort = .trending
        #expect(selection.query(for: DiscoverSeeAllSection.of(.animeTopRated)).section == .trending)
        selection.sort = .popular
        #expect(selection.query(for: trending).section == .trending)
        #expect(selection.query(for: trending).sort == .popular)
        let essentials = DiscoverSeeAllSection.of(.mangaEssentials)
        var own = DiscoverSeeAllSelection(sort: essentials.defaultSort)
        #expect(own.query(for: essentials) == DiscoverSeeAllQuery(section: .essentials, medium: .manga, sort: .sectionOrder))
        own.sort = .newest
        #expect(own.query(for: essentials).sort == .newest)
        own.sort = .topRated
        #expect(own.query(for: essentials).sort == .topRated)
    }

    @Test("Chips → query: TV / Film format, Up to 13 → short (1–13), Over 50 → long + > 50 on the device, Finished / Airing")
    func chipMapping() {
        let section = DiscoverSeeAllSection.of(.animeTrending)
        var selection = DiscoverSeeAllSelection(sort: .trending)
        selection.toggle(.film)
        selection.toggle(.upTo13)
        selection.toggle(.finished)
        var query = selection.query(for: section)
        #expect(query.format == "MOVIE")
        #expect(query.length == .short)
        #expect(query.length?.episodeRange.max == 13)
        #expect(query.status == .finished)
        #expect(selection.activeCount == 3)
        // Exclusive within a group.
        selection.toggle(.tv)
        selection.toggle(.over50)
        selection.toggle(.releasing)
        query = selection.query(for: section)
        #expect(query.format == "TV")
        #expect(query.length == .long)
        #expect(query.status == .releasing)
        #expect(!selection.isOn(.film) && !selection.isOn(.upTo13) && !selection.isOn(.finished))
        // A second tap clears; Hide my list is independent and never reaches the server query.
        selection.toggle(.tv)
        #expect(selection.query(for: section).format == nil)
        selection.toggle(.hideMyList)
        #expect(selection.hideMyList)
        #expect(selection.query(for: section) == {
            var expected = DiscoverSeeAllQuery(section: .trending, medium: .anime, sort: .sectionOrder)
            expected.length = .long
            expected.status = .releasing
            return expected
        }())
        // The device-side rules: > 50 (the server's `long` bucket, 51+), Hide my list, and the status
        // chip checked again on the row.
        #expect(!selection.includes(kind: .anime, episodes: 30, onList: false))
        #expect(selection.includes(kind: .anime, episodes: 51, statusRaw: "RELEASING", onList: false))
        #expect(!selection.includes(kind: .anime, episodes: 51, statusRaw: "FINISHED", onList: false))
        #expect(!selection.includes(kind: .anime, episodes: 64, onList: true))
        var short = DiscoverSeeAllSelection(sort: .trending)
        short.toggle(.upTo13)
        short.toggle(.film)
        #expect(short.includes(kind: .anime, episodes: 1, formatRaw: "MOVIE", onList: false))
        #expect(!short.includes(kind: .anime, episodes: 26, formatRaw: "MOVIE", onList: false))
        #expect(!short.includes(kind: .anime, episodes: 12, formatRaw: "TV", onList: false))
        #expect(!short.includes(kind: .anime, episodes: nil, formatRaw: "MOVIE", onList: false))
        selection.clearFilters()
        #expect(selection.activeCount == 0)
        #expect(selection.includes(kind: .anime, episodes: 30, onList: true))
    }

    @Test("Chip flow: a group separator stands only between two chips of one line, never at a line break")
    func chipFlow() {
        let chip = CGSize(width: 60, height: 44)
        let sizes = [chip, chip, DiscoverChipFlow.separatorSize, chip, chip]
        let separators = [false, false, true, false, false]
        // Wide: one line, the separator between the 2nd and 3rd chip, centred on the line.
        let wide = DiscoverChipFlow.arrange(sizes: sizes, separators: separators, maxWidth: 400)
        let separator = wide.frames[2]
        #expect(separator != nil)
        #expect(separator?.minX == CGFloat(132))
        #expect(separator.map { $0.midY } == 22)
        #expect(wide.size.height == 44)
        // Narrow: the group wraps, the separator is dropped and the next chip starts the new line.
        let narrow = DiscoverChipFlow.arrange(sizes: sizes, separators: separators, maxWidth: 150)
        #expect(narrow.frames[2] == nil)
        #expect(narrow.frames[3].map { $0.minX } == 0)
        #expect(narrow.frames[3].map { $0.minY } == 44)
        #expect(narrow.size.height == 88)
    }

    @Test("Copy: the D10 chip words, the sort words and the end line in both languages")
    func copy() {
        #expect(DiscoverSeeAllCopy.chip(.upTo13, medium: .anime, german: false) == "Up to 13 episodes")
        #expect(DiscoverSeeAllCopy.chip(.over50, medium: .anime, german: true) == "Über 50 Folgen")
        #expect(DiscoverSeeAllCopy.chip(.finished, medium: .anime, german: true) == "Fertig erschienen")
        #expect(DiscoverSeeAllCopy.chip(.releasing, medium: .anime, german: true) == "Läuft")
        #expect(DiscoverSeeAllCopy.chip(.releasing, medium: .manga, german: true) == "Erscheint noch")
        #expect(DiscoverSeeAllCopy.chip(.hideMyList, medium: .anime, german: true) == "Meine Liste ausblenden")
        #expect(DiscoverSeeAllCopy.sortWord(.trending, german: true) == "Gerade beliebt")
        #expect(DiscoverSeeAllCopy.sortWord(.justAdded, german: true) == "Neu hinzugefügt")
        #expect(DiscoverSeeAllCopy.sortWord(.ownOrder(.airing), german: false) == "Next to air")
        #expect(DiscoverSeeAllCopy.sortWord(.ownOrder(.personal), german: true) == "Für dich")
        #expect(DiscoverSeeAllCopy.sortWord(.popular, german: true) == "Am beliebtesten")
        #expect(DiscoverSeeAllCopy.thatsAll(8, german: false) == "That's all 8.")
        #expect(DiscoverSeeAllCopy.thatsAll(8, german: true) == "Das sind alle 8.")
        #expect(DiscoverSeeAllCopy.matches(3, german: false) == "3 match")
        #expect(DiscoverSeeAllCopy.matches(3, german: true) == "3 Treffer")
        #expect(DiscoverSeeAllCopy.titles(1, german: false) == "1 title")
        #expect(DiscoverSeeAllCopy.pageFailed(german: false) == "Couldn't load more. Try again \u{2192}")
    }

    @Test("The bounded lists sort on the device: Newest by release year, Top rated by score, own order kept")
    func localSort() {
        let rows = DiscoverUsabilityFixtures.page(kind: .anime, count: 6).items.map(\.card)
        let newest = DiscoverLocalPage.page(rows, query: DiscoverSeeAllQuery(section: .essentials, medium: .anime, sort: .newest))
        let years = newest.compactMap { $0.anime?.startDateYear }
        #expect(years == years.sorted(by: >))
        let own = DiscoverLocalPage.page(rows, query: DiscoverSeeAllQuery(section: .essentials, medium: .anime))
        #expect(own.map(\.id) == rows.map(\.id))
    }

    @Test("Drawn rows: hidden titles out (live), a Not-interested franchise out while the answer stands, device rules applied")
    func visibleRows() {
        let page = DiscoverUsabilityFixtures.page(kind: .anime, count: 5)
        let placed = page.items.map { DiscoverPlacedItem(item: $0, ownedStatus: nil) }
        let keys = page.items.map(\.key)
        let hidden: Set<MediaKey> = [keys[0]]
        let franchise = DiscoverFranchiseKey.component(.anime, 77)
        let franchises = DiscoverJourneyVisible.activeFranchises([keys[0]: [franchise], keys[4]: [.component(.anime, 99)]],
                                                                 isHidden: { hidden.contains($0) })
        #expect(franchises == [franchise])
        let rows = DiscoverJourneyVisible.rows(
            placed, isHidden: { hidden.contains($0) }, hiddenFranchises: franchises,
            franchiseKeys: { $0.key == keys[2] ? [franchise] : [.component(.anime, $0.key.id)] },
            include: { $0.item.key != keys[3] })
        #expect(rows.map(\.item.key) == [keys[1], keys[4]])
    }

    @Test("A journey feed: the first page, then the end (\"That's all\"); a failed read shows failed or offline")
    func feedEnds() async throws {
        let harness = try DCDiscoverHarness(responder: { _ in .emptyArray })
        await harness.signIn()
        defer { Task { await harness.tearDown() } }
        let graph = harness.graph
        let feed = DiscoverJourneyFeed(policy: .mark)
        let first = DiscoverUsabilityFixtures.page(kind: .anime, count: 4)
        let more = DiscoverPage(items: first.items, next: .offset(4), reason: nil, origin: .server)
        var reads: [DiscoverPageCursor?] = []
        let second = DiscoverUsabilityFixtures.page(kind: .anime, count: 6)
        await feed.start(key: "trending", policy: .mark, fetch: { cursor in
            reads.append(cursor)
            if cursor == nil { return more }
            return DiscoverPage(items: Array(second.items.suffix(2)), next: nil, reason: nil, origin: .server)
        }, discovery: graph.discovery, taste: graph.taste, isOffline: { false }, visibleCount: { 100 })
        #expect(feed.phase == .ready)
        #expect(feed.accumulator.items.count == 4)
        #expect(feed.hasMore)
        await feed.loadMore(discovery: graph.discovery, taste: graph.taste, visibleCount: { 100 })
        #expect(feed.accumulator.items.count == 6)
        #expect(feed.isFinished)
        #expect(feed.pages == 2)
        #expect(reads.count == 2)

        // Top-up: a page that draws too few rows reads the next one automatically.
        let topped = DiscoverJourneyFeed(policy: .mark)
        await topped.start(key: "topped", policy: .mark, fetch: { cursor in
            cursor == nil ? more : DiscoverPage(items: Array(second.items.suffix(2)), next: nil, reason: nil, origin: .server)
        }, discovery: graph.discovery, taste: graph.taste, isOffline: { false }, visibleCount: { 0 })
        #expect(topped.isFinished)
        #expect(topped.pages == 2)

        let failed = DiscoverJourneyFeed(policy: .mark)
        await failed.start(key: "f", policy: .mark, fetch: { _ in nil }, discovery: graph.discovery, taste: graph.taste,
                           isOffline: { false }, visibleCount: { 0 })
        #expect(failed.phase == .failed)
        await failed.start(key: "f", policy: .mark, fetch: { _ in nil }, discovery: graph.discovery, taste: graph.taste,
                           isOffline: { true }, visibleCount: { 0 })
        #expect(failed.phase == .offline)
    }

    @Test("A page that comes back on screen keeps its rows (N1, R8): the same query reads once; Try again forces")
    func feedKeepsRowsOnReturn() async throws {
        let harness = try DCDiscoverHarness(responder: { _ in .emptyArray })
        await harness.signIn()
        defer { Task { await harness.tearDown() } }
        let graph = harness.graph
        let page = DiscoverUsabilityFixtures.page(kind: .anime, count: 4)
        var reads = 0
        let feed = DiscoverJourneyFeed(policy: .mark)
        let fetch: DiscoverJourneyFeed.Fetch = { _ in
            reads += 1
            return page
        }
        await feed.start(key: "q", policy: .mark, fetch: fetch, discovery: graph.discovery, taste: graph.taste,
                         isOffline: { false }, visibleCount: { 100 })
        await feed.start(key: "q", policy: .mark, fetch: fetch, discovery: graph.discovery, taste: graph.taste,
                         isOffline: { false }, visibleCount: { 100 })
        #expect(reads == 1)
        #expect(feed.phase == .ready)
        await feed.start(key: "q", force: true, policy: .mark, fetch: fetch, discovery: graph.discovery,
                         taste: graph.taste, isOffline: { false }, visibleCount: { 100 })
        #expect(reads == 2)
        await feed.start(key: "other", policy: .mark, fetch: fetch, discovery: graph.discovery, taste: graph.taste,
                         isOffline: { false }, visibleCount: { 100 })
        #expect(reads == 3)

        // A read cancelled because the page left the screen is not a failure: it stays loading and
        // reads again on return.
        let cancelled = DiscoverJourneyFeed(policy: .mark)
        let task = Task { @MainActor in
            await cancelled.start(key: "c", policy: .mark, fetch: { _ in
                try? await Task.sleep(for: .milliseconds(200))
                return nil
            }, discovery: graph.discovery, taste: graph.taste, isOffline: { false }, visibleCount: { 0 })
        }
        task.cancel()
        await task.value
        #expect(cancelled.phase == .loading)
        #expect(cancelled.loadedKey == nil)
    }

    @Test("See all → a title → Back: the list is read once and its rows stay (journey round trip)")
    func seeAllRoundTrip() async throws {
        let harness = try DCDiscoverHarness(responder: { request in
            request.resource == "rpc/discover_section_page_v1"
                ? .json(DiscoverUsabilityFixtures.pageRowsJSON(kind: .anime, count: 6)) : .emptyArray
        })
        await harness.signIn()
        let title = "Trending"
        let navigator = JourneyNavigator(root: .seeAll(AnyJourneyPage(id: DiscoverSeeAllPolicy.pageID(.animeTrending), title: title) {
            DiscoverSeeAllPage(source: .route(.animeTrending), title: title, purpose: "", animeItems: [], mangaItems: [])
        }))
        let window = DUPHosting.window(DUPHosting.inject(AnyView(JourneyHost(navigator: navigator)), graph: harness.graph),
                                       width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_200))
        let reads = { harness.server.requests.filter { $0.resource == "rpc/discover_section_page_v1" }.count }
        #expect(reads() == 1)
        navigator.open(JourneyPage.media(MediaRoute(kind: .anime, id: 991_000)))
        try? await Task.sleep(for: .milliseconds(900))
        navigator.pop()
        try? await Task.sleep(for: .milliseconds(1_200))
        #expect(reads() == 1)
        #expect(navigator.path.isEmpty)
        DUPHosting.close(window)
        await harness.tearDown()
    }
}

// MARK: - Mood

@MainActor
@Suite("Discover usability lane B: mood journeys", .serialized)
struct DUpreviewMoodTests {
    @Test("Moods: Like only with a seed; one page per mood (N5)")
    func moods() {
        #expect(DiscoverMoodRoute.moods(hasSeed: false) == [.short, .cozy, .intense])
        #expect(DiscoverMoodRoute.moods(hasSeed: true) == [.short, .cozy, .intense, .likeLastLoved])
        #expect(DiscoverMoodRoute.pageID(.cozy) == "discover:mood:cozy")
        let page = DiscoverMoodRoute.journeyPage(.short, kind: .anime, german: false)
        #expect(page.id == "custom:discover:mood:short")
        #expect(page.title == "Something short")
        #expect(DiscoverMoodRoute.page(.likeLastLoved, kind: .anime, german: false, seedTitle: "Frieren").title == "Like Frieren")
    }

    @Test("Mood chips: Films = MOVIE, Series = TV / TV_SHORT / ONA, Up to 13 episodes for anime")
    func filters() {
        var filters = DiscoverMoodFilters()
        #expect(filters.includes(kind: .anime, formatRaw: "MOVIE", episodes: 1))
        filters.format = .films
        #expect(filters.includes(kind: .anime, formatRaw: "MOVIE", episodes: 1))
        #expect(!filters.includes(kind: .anime, formatRaw: "TV", episodes: 12))
        filters.format = .series
        #expect(filters.includes(kind: .anime, formatRaw: "ONA", episodes: 10))
        #expect(!filters.includes(kind: .anime, formatRaw: "OVA", episodes: 2))
        #expect(filters.includes(kind: .manga, formatRaw: "MANGA", episodes: nil))
        filters.upTo13 = true
        #expect(!filters.includes(kind: .anime, formatRaw: "TV", episodes: 24))
        #expect(!filters.includes(kind: .anime, formatRaw: "TV", episodes: nil))
        #expect(filters.includes(kind: .anime, formatRaw: "TV", episodes: 13))
        #expect(filters.activeCount == 2)
        filters.clear()
        #expect(filters.activeCount == 0)
    }

    @Test("Mood copy: words, purposes, the Like eyebrow and the empty line in both languages")
    func copy() {
        #expect(DiscoverMoodCopy.word(.short, seedTitle: nil, german: false) == "Something short")
        #expect(DiscoverMoodCopy.word(.cozy, seedTitle: nil, german: true) == "Gemütlich")
        #expect(DiscoverMoodCopy.word(.likeLastLoved, seedTitle: "Frieren", german: true) == "Wie Frieren")
        #expect(DiscoverMoodCopy.subtitle(.intense, german: false) == "Dark and gripping")
        #expect(DiscoverMoodCopy.purpose(.cozy, seedTitle: nil, german: false) == "Warm, low-stakes stories to unwind with.")
        #expect(DiscoverMoodCopy.purpose(.likeLastLoved, seedTitle: "Frieren", german: true) == "Nah an Frieren in Ton und Themen.")
        #expect(DiscoverMoodCopy.becauseEyebrow("Frieren", german: false) == "BECAUSE YOU FINISHED FRIEREN")
        #expect(DiscoverMoodCopy.becauseEyebrow("Frieren", german: true) == "WEIL DU FRIEREN BEENDET HAST")
        #expect(DiscoverMoodCopy.empty(.short, seedTitle: nil, german: false) == "Nothing short left that you haven't seen.")
        #expect(DiscoverMoodCopy.empty(.intense, seedTitle: nil, german: true) == "Nichts Intensives mehr, das du noch nicht kennst.")
        #expect(DiscoverMoodCopy.startHere(german: true) == "Fang hier an")
    }
}

// MARK: - Renders

@MainActor
@Suite("Discover usability lane B: after renders", .serialized, .timeLimit(.minutes(6)))
struct DUpreviewRenderTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-du-preview-after", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/discover-usability-2026-11-04/after")
    }()

    @Test("Preview (banner, cover, loading) and the feedback toasts (EN / DE, 390 / 320)")
    func previewAndToasts() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: { _ in .emptyArray })
        await harness.signIn()
        let graph = harness.graph

        let banner = TasteCard(media: Self.seedMedia(0), bannerURL: Self.art("journal-anime-22-banner.jpg"))
        let preview = Self.canvas(DiscoverTitlePreview(
            card: banner, section: "New to you", reason: DiscoverMenuCopy.Reason.unseen.text(german: KuroLocale.isGerman),
            knownSynopsis: "A wandering doctor of strange life forms called mushi travels the countryside, quietly helping the people they touch."))
        await render(preview, graph: graph, name: "du-preview-preview-banner-390", width: 390, height: 520)

        let cover = TasteCard(media: Self.seedMedia(4, kind: .manga))
        let coverPreview = Self.canvas(DiscoverTitlePreview(
            card: cover, section: "Essential manga", reason: DiscoverMenuCopy.Reason.canon.text(german: KuroLocale.isGerman),
            knownSynopsis: "A young swordsman leaves his village to become the strongest under heaven, and learns what strength costs."))
        await render(coverPreview, graph: graph, name: "du-preview-preview-cover-390", width: 390, height: 620)

        // Loading: the catalogue read is held, so the synopsis area shows the scrub line on the material.
        let gate = StubGate()
        let held = try DCDiscoverHarness(responder: { request in
            request.resource == "anime" ? StubResponse.json("[]").held(by: gate) : .emptyArray
        })
        await held.signIn()
        let loading = Self.canvas(DiscoverTitlePreview(card: banner, section: "Trending", reason: nil))
        await render(loading, graph: held.graph, name: "du-preview-preview-loading-390", width: 390, height: 440)
        gate.open()
        await held.tearDown()

        for (german, suffix) in [(false, ""), (true, "-de")] {
            for width in [CGFloat(390), 320] {
                let toasts = VStack(spacing: 18) {
                    DiscoverFeedbackToastView(message: DiscoverMenuCopy.toast(.notInterested, german: german), actionTitle: nil,
                                              actionSpoken: "", showsUndo: true, german: german,
                                              onAction: {}, onUndo: {}, onDismiss: {})
                    DiscoverFeedbackToastView(message: DiscoverMenuCopy.toast(.seenIt, german: german),
                                              actionTitle: DiscoverMenuCopy.addAsCompleted(german: german),
                                              actionSpoken: DiscoverMenuCopy.addAsCompletedSpoken(german: german),
                                              showsUndo: true, german: german, onAction: {}, onUndo: {}, onDismiss: {})
                    DiscoverFeedbackToastView(message: DiscoverMenuCopy.undone(german: german), actionTitle: nil,
                                              actionSpoken: "", showsUndo: false, german: german,
                                              onAction: {}, onUndo: {}, onDismiss: {})
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(Color.kuroCanvasHome)
                await render(AnyView(toasts), graph: graph, name: "du-preview-toasts\(suffix)-\(Int(width))", width: width,
                             height: 300)
            }
        }
        await harness.tearDown()
    }

    @Test("See all: catalogue list with chips, a filtered list with its match line, a bounded list's end, and empty")
    func seeAll() async throws {
        await Self.seedArtwork()
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 9_102, rowId: 1, status: .planning, progress: 0, verdict: nil),
                         FakeLibraryBackend.entry(.anime, 9_104, rowId: 2, status: .current, progress: 5, verdict: nil)],
                        for: LifecycleFixtures.userA)
        let harness = try DCDiscoverHarness(responder: Self.responder(), libraryBackend: backend)
        await harness.signIn()
        try? await harness.graph.library.refresh()
        let graph = harness.graph
        let german = KuroLocale.isGerman

        let trending = Self.seeAll(.animeTrending, german: german)
        await render(trending, graph: graph, name: "du-preview-see-all-trending-390", width: 390, height: 844, wait: 1_800)
        await render(trending, graph: graph, name: "du-preview-see-all-trending-320", width: 320, height: 700, wait: 1_800)

        let essentials = Self.seeAll(.animeEssentials, german: german)
        await render(essentials, graph: graph, name: "du-preview-see-all-essentials-full-390", width: 390, height: 1_700,
                     wait: 1_800)

        let empty = try DCDiscoverHarness(responder: { _ in .emptyArray })
        await empty.signIn()
        await render(Self.seeAll(.mangaTrending, german: german), graph: empty.graph, name: "du-preview-see-all-empty-390",
                     width: 390, height: 700, wait: 1_400)
        await empty.tearDown()

        // Chips on: Up to 13 episodes + Hide my list (✓ faces, the match line).
        var filtered = DiscoverSeeAllSelection(sort: .trending)
        filtered.toggle(.upTo13)
        filtered.toggle(.hideMyList)
        await render(Self.seeAll(.animeTrending, german: german, selection: filtered), graph: graph,
                     name: "du-preview-see-all-filtered-390", width: 390, height: 844, wait: 1_800)

        // Nothing matches: Over 50 episodes + Film (no fixture row is both).
        var none = DiscoverSeeAllSelection(sort: .trending)
        none.toggle(.over50)
        none.toggle(.film)
        await render(Self.seeAll(.animeTrending, german: german, selection: none), graph: graph,
                     name: "du-preview-see-all-no-match-390", width: 390, height: 700, wait: 1_600)

        let failed = try DCDiscoverHarness(responder: { request in
            request.resource == "rpc/discover_section_page_v1"
                ? StubResponse.json(#"{"code":"XX000","message":"boom","details":null,"hint":null}"#, status: 500) : .emptyArray
        })
        await failed.signIn()
        await render(Self.seeAll(.animeTrending, german: german), graph: failed.graph, name: "du-preview-see-all-failed-390",
                     width: 390, height: 700, wait: 1_400)
        await failed.tearDown()

        let offline = try DCDiscoverHarness(responder: { _ in .failure(.notConnectedToInternet) })
        await offline.signIn()
        let monitor = NetworkMonitor()
        try? await Task.sleep(for: .milliseconds(300))
        monitor.isConnected = false
        await render(Self.seeAll(.animeTrending, german: german), graph: offline.graph, name: "du-preview-see-all-offline-390",
                     width: 390, height: 700, wait: 1_400, monitor: monitor)
        await offline.tearDown()

        // The list footer: Loading more, and the paging failure.
        let footers = VStack(alignment: .leading, spacing: 18) {
            DiscoverJourneyFooter(isLoadingMore: true, pageFailed: false, finished: false, count: 12, retry: {})
            DiscoverJourneyFooter(isLoadingMore: false, pageFailed: true, finished: false, count: 12, retry: {})
            DiscoverJourneyFooter(isLoadingMore: false, pageFailed: false, finished: true, count: 12, retry: {})
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.kuroCanvasHome)
        await render(AnyView(footers), graph: graph, name: "du-preview-see-all-footers-390", width: 390, height: 240)

        let gate = StubGate()
        let held = try DCDiscoverHarness(responder: { request in
            request.resource == "rpc/discover_section_page_v1" ? StubResponse.json("[]").held(by: gate) : .emptyArray
        })
        await held.signIn()
        await render(Self.seeAll(.animeTrending, german: german), graph: held.graph, name: "du-preview-see-all-loading-390",
                     width: 390, height: 700, wait: 900)
        gate.open()
        await held.tearDown()
        await harness.tearDown()
    }

    @Test("Mood journey: Something short on Anime")
    func mood() async throws {
        await Self.seedArtwork()
        let harness = try DCDiscoverHarness(responder: Self.responder())
        await harness.signIn()
        let page = DiscoverMoodRoute.journeyPage(.short, kind: .anime, german: KuroLocale.isGerman)
        let host = JourneyHost(navigator: JourneyNavigator(root: page))
        await render(AnyView(host), graph: harness.graph, name: "du-preview-mood-short-390", width: 390, height: 1_300,
                     wait: 1_800)
        let manga = JourneyHost(navigator: JourneyNavigator(root: DiscoverMoodRoute.journeyPage(.cozy, kind: .manga,
                                                                                                 german: KuroLocale.isGerman)))
        await render(AnyView(manga), graph: harness.graph, name: "du-preview-mood-cozy-manga-390", width: 390, height: 844,
                     wait: 1_800)
        // Empty with a chip on (Films on manga): the quiet card and Clear filters.
        var films = DiscoverMoodFilters()
        films.format = .films
        let empty = JourneyHost(navigator: JourneyNavigator(root: .custom(AnyJourneyPage(id: DiscoverMoodRoute.pageID(.intense)) {
            DiscoverMoodPage(mood: .intense, kind: .manga, filters: films)
        })))
        await render(AnyView(empty), graph: harness.graph, name: "du-preview-mood-empty-390", width: 390, height: 700,
                     wait: 1_600)
        await harness.tearDown()
    }

    // MARK: Hosting

    private static func seeAll(_ route: EditorialDiscoverRoute, german: Bool,
                               selection: DiscoverSeeAllSelection? = nil) -> AnyView {
        let title = route.title(german: german, reason: nil)
        let purpose: String
        switch route {
        case .animeEssentials:
            purpose = german ? "10 Titel, an denen man Anime kennt. Unsere Reihenfolge, kein Ranking."
                             : "10 titles to know anime by. Our order, not a ranking."
        case .mangaTrending:
            purpose = german ? "Was Manga-Fans gerade lesen." : "What manga readers are reading right now."
        default:
            purpose = german ? "Was Anime-Fans gerade schauen." : "What anime fans are watching right now."
        }
        let navigator = JourneyNavigator(root: .seeAll(AnyJourneyPage(id: DiscoverSeeAllPolicy.pageID(route), title: title) {
            DiscoverSeeAllPage(source: .route(route), title: title, purpose: purpose, animeItems: [], mangaItems: [],
                               initialSelection: selection)
        }))
        return AnyView(JourneyHost(navigator: navigator))
    }

    private static func canvas<V: View>(_ view: V) -> AnyView {
        AnyView(view
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kuroInk.opacity(0.35))
            .background(Color.kuroCanvasHome))
    }

    private func render(_ view: AnyView, graph: AppGraph, name: String, width: CGFloat, height: CGFloat,
                        wait: Int = 900, monitor: NetworkMonitor? = nil) async {
        let window = DUPHosting.window(DUPHosting.inject(view, graph: graph, monitor: monitor), width: width, height: height)
        try? await Task.sleep(for: .milliseconds(wait))
        await capture(window, name: name)
        DUPHosting.close(window)
    }

    private func capture(_ window: UIWindow, name: String) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        window.layoutIfNeeded()
        guard let png = FixtureRaster.png(of: window, size: window.bounds.size, diagnosticScale: nil),
              let image = UIImage(data: png), let jpeg = image.jpegData(compressionQuality: 0.8) else {
            Issue.record("\(name): encoding failed")
            return
        }
        #expect(image.size.width * image.scale <= 603, "\(name) is wider than 603 px")
        do {
            try jpeg.write(to: Self.outDir.appendingPathComponent("\(name).jpg"))
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
    }

    // MARK: Fixtures

    nonisolated static func art(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static let artFiles = [
        "anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg", "anime0-banner.jpg", "anime1-banner.jpg",
        "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg",
        "journal-anime-12-cover.jpg", "journal-anime-16-cover.jpg", "journal-anime-22-cover.jpg", "journal-anime-22-banner.jpg",
        "journal-manga-13-cover.jpg", "journal-manga-16-cover.jpg", "journal-manga-23-cover.jpg"
    ]

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: art(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }

    nonisolated private static let animeSeeds: [(String, String, String, Int, Int, Int)] = [
        ("Mushishi", "journal-anime-12-cover.jpg", "TV", 26, 2005, 87),
        ("Frieren: Beyond Journey's End", "anime2.jpg", "TV", 28, 2023, 91),
        ("Mob Psycho 100", "anime3.jpg", "TV", 12, 2016, 86),
        ("Cowboy Bebop", "journal-anime-16-cover.jpg", "TV", 26, 1998, 88),
        ("Your Name.", "anime1.jpg", "MOVIE", 1, 2016, 85),
        ("Dandadan", "journal-anime-22-cover.jpg", "TV", 12, 2024, 83),
        ("Ping Pong the Animation", "anime0.jpg", "TV", 11, 2014, 86),
        ("Monster", "journal-anime-16-cover.jpg", "TV", 74, 2004, 88),
        ("Mononoke", "anime2.jpg", "TV", 12, 2007, 82),
        ("Haikyu!!", "anime3.jpg", "TV", 25, 2014, 84)
    ]

    nonisolated private static let mangaSeeds: [(String, String, Int, Int, Int)] = [
        ("Goodnight Punpun", "journal-manga-13-cover.jpg", 147, 2007, 90),
        ("Monster", "journal-manga-16-cover.jpg", 162, 1994, 91),
        ("Blue Period", "journal-manga-23-cover.jpg", 60, 2017, 85),
        ("Chainsaw Man", "manga0.jpg", 120, 2018, 86),
        ("Vagabond", "manga3.jpg", 327, 1998, 92),
        ("Berserk", "manga2.jpg", 370, 1989, 93)
    ]

    private static func seedMedia(_ index: Int, kind: MediaKind = .anime) -> Media {
        if kind == .manga {
            let seed = mangaSeeds[index % mangaSeeds.count]
            return Media(id: 9_200 + index, kind: .manga, title: seed.0, imageURL: art(seed.1), year: String(seed.3),
                         displayDescription: "", episodes: nil, chapters: seed.2, rating: Double(seed.4) / 10,
                         genres: ["Seinen"], statusRaw: "FINISHED", formatRaw: "MANGA", popularityValue: nil,
                         trendingValue: nil, createdAtValue: nil)
        }
        let seed = animeSeeds[index % animeSeeds.count]
        return Media(id: 9_100 + index, kind: .anime, title: seed.0, imageURL: art(seed.1), year: String(seed.4),
                     displayDescription: "", episodes: seed.3, chapters: nil, rating: Double(seed.5) / 10,
                     genres: ["Drama"], statusRaw: "FINISHED", formatRaw: seed.2, popularityValue: nil,
                     trendingValue: nil, createdAtValue: nil)
    }

    nonisolated private static func rowsJSON(kind: MediaKind) -> String {
        var rows: [String] = []
        if kind == .anime {
            for (i, seed) in animeSeeds.enumerated() {
                rows.append(#"{"media_type":"ANIME","rank":\#(i + 1),"id":\#(9_100 + i),"title_english":"\#(seed.0)","title_romaji":null,"title_native":null,"cover_image_large":"\#(art(seed.1))","cover_image_medium":"\#(art(seed.1))","banner_image":null,"format":"\#(seed.2)","status":"\#(i == 5 ? "RELEASING" : "FINISHED")","episode_count":\#(seed.3),"chapter_count":null,"volumes":null,"season_year":\#(seed.4),"start_date_year":\#(seed.4),"average_score":\#(seed.5),"popularity":\#(90_000 - i * 1_000),"trending":\#(50 - i),"favourites":5000,"genres":["Drama"],"created_at":"2026-01-01T00:00:00+00:00","franchise_id":\#(9_100 + i),"list_status":null,"reason_media_id":null,"reason_title":null}"#)
            }
        } else {
            for (i, seed) in mangaSeeds.enumerated() {
                rows.append(#"{"media_type":"MANGA","rank":\#(i + 1),"id":\#(9_200 + i),"title_english":"\#(seed.0)","title_romaji":null,"title_native":null,"cover_image_large":"\#(art(seed.1))","cover_image_medium":"\#(art(seed.1))","banner_image":null,"format":"MANGA","status":"FINISHED","episode_count":null,"chapter_count":\#(seed.2),"volumes":null,"season_year":null,"start_date_year":\#(seed.3),"average_score":\#(seed.4),"popularity":\#(60_000 - i * 1_000),"trending":\#(30 - i),"favourites":3000,"genres":["Seinen"],"created_at":"2026-01-01T00:00:00+00:00","franchise_id":\#(9_200 + i),"list_status":null,"reason_media_id":null,"reason_title":null}"#)
            }
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    nonisolated private static func responder() -> StubServer.Responder {
        let anime = rowsJSON(kind: .anime)
        let manga = rowsJSON(kind: .manga)
        return { request in
            switch request.resource ?? "" {
            case "rpc/discover_section_page_v1", "rpc/discover_mood_v1":
                let body = request.jsonObject
                return .json((body?["p_media_type"] as? String) == "MANGA" ? manga : anime)
            default: return .emptyArray
            }
        }
    }
}

/// Hosting for the lane's window-based tests and renders.
@MainActor
enum DUPHosting {
    static func inject(_ view: AnyView, graph: AppGraph, monitor: NetworkMonitor? = nil) -> AnyView {
        AnyView(view
            .environment(graph.identity)
            .environment(graph.auth)
            .environment(graph.session)
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(graph.home)
            .environment(graph.search)
            .environment(graph.discovery)
            .environment(graph.recommendations)
            .environment(graph.releases)
            .environment(graph.social)
            .environment(graph.availability)
            .environment(graph.clubs)
            .environment(graph.collection)
            .environment(graph.imports)
            .environment(graph.concierge)
            .environment(graph.taste)
            .environment(graph.deviceIntelligence)
            .environment(graph.support)
            .environment(graph.banner)
            .environment(graph.flags)
            .environment(graph.interactionTelemetry)
            .environment(graph.outboundLinks)
            .environment(graph.artworkMaterials)
            .environment(graph.catalog)
            .environment(monitor ?? NetworkMonitor()))
    }

    static func window(_ view: AnyView, width: CGFloat, height: CGFloat) -> UIWindow {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        host.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.isHidden = false
        window.makeKey()
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = .white
        host.view.layoutIfNeeded()
        return window
    }

    static func close(_ window: UIWindow) {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
    }
}
