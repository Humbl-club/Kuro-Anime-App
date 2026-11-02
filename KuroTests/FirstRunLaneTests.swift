import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

/// Plan Task 8 (first run, Taste and empty states; amendments 5 and 10): the new-account Home copy, the
/// starter picks' data honesty, the Plan key's one-tap write, the Taste headings, the Collection
/// empty block and the Search no-history line.
@MainActor
@Suite("First-run lane", .timeLimit(.minutes(1)))
struct FirstRunLaneTests {
    // MARK: Fixtures

    static func animeCard(_ id: Int, title: String?, banner: String? = nil, format: String = "MOVIE",
                          genres: [String] = ["Romance"]) throws -> AnimeCard {
        var object: [String: Any] = ["id": id, "format": format, "genres": genres,
                                     "cover_image_large": "https://example.invalid/a\(id).jpg"]
        if let title { object["title_english"] = title }
        if let banner { object["banner_image"] = banner }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(AnimeCard.self, from: data)
    }

    static func mangaCard(_ id: Int, title: String) throws -> MangaCard {
        let object: [String: Any] = ["id": id, "title_english": title, "format": "MANGA", "genres": ["Supernatural"],
                                     "cover_image_large": "https://example.invalid/m\(id).jpg"]
        return try JSONDecoder().decode(MangaCard.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func becauseCard(_ id: Int, title: String, synopsis: String?) throws -> BecauseYouCard {
        var object: [String: Any] = ["media_type": "ANIME", "media_id": id, "title": title, "format": "TV",
                                     "genres": ["Drama"]]
        if let synopsis { object["synopsis"] = synopsis }
        return try JSONDecoder().decode(BecauseYouCard.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: New-account Home

    @Test("New-account Home copy, EN and DE")
    func newAccountHomeCopy() {
        #expect(HomeNewAccountCopy.headline(german: false) == "Your stories belong here.")
        #expect(HomeNewAccountCopy.line(german: false) == "Import your list to bring your place with you.")
        #expect(HomeNewAccountCopy.exploreTaste(german: false) == "Explore Taste ←")
        #expect(HomeNewAccountCopy.exploreTasteSpoken(german: false) == "Explore Taste")
        #expect(HomeNewAccountCopy.importList(german: false) == "Import your list")
        #expect(HomeNewAccountCopy.headline(german: true) == "Hier gehören deine Geschichten hin.")
        #expect(HomeNewAccountCopy.line(german: true) == "Importiere deine Liste und nimm deinen Stand mit.")
        #expect(HomeNewAccountCopy.exploreTaste(german: true) == "Geschmack entdecken ←")
        #expect(HomeNewAccountCopy.importList(german: true) == "Liste importieren")
        #expect(TastePageCopy.firstFavourite(german: false) == "A first favourite.")
        #expect(TastePageCopy.firstFavourite(german: true) == "Ein erster Favorit.")
        // Spec §5.3: 3–4 starter cards.
        #expect(HomeNewAccountCopy.pickCount(.anime) == 3)
        #expect(HomeNewAccountCopy.pickCount(.manga) == 4)
    }

    // MARK: Starter picks

    @Test("First favourite picks come only from loaded cards, at most 4, real titles once, never tracked")
    func firstFavouritePicks() throws {
        let cards = try [
            TasteCard(anime: Self.animeCard(1, title: "Your Name.")),
            TasteCard(anime: Self.animeCard(2, title: nil)),                  // "Unknown": never shown
            TasteCard(anime: Self.animeCard(3, title: "A Silent Voice")),
            TasteCard(anime: Self.animeCard(1, title: "Your Name.")),        // duplicate
            TasteCard(anime: Self.animeCard(4, title: "Tracked")),
            TasteCard(anime: Self.animeCard(5, title: "Mushishi")),
            TasteCard(anime: Self.animeCard(6, title: "Frieren")),
            TasteCard(anime: Self.animeCard(7, title: "Ping Pong"))
        ]
        let picked = FirstFavouritePicks.pick(from: cards, max: 4, excluding: [MediaKey(kind: .anime, id: 4)])
        #expect(picked.map(\.media.id) == [1, 3, 5, 6])
        #expect(FirstFavouritePicks.pick(from: [], max: 4).isEmpty, "no loaded cards: the row is hidden")
        #expect(FirstFavouritePicks.pick(from: cards, max: 0).isEmpty)
        // Anime 1 and manga 1 are different titles.
        let mixed = try [TasteCard(anime: Self.animeCard(1, title: "A")), TasteCard(manga: Self.mangaCard(1, title: "B"))]
        #expect(FirstFavouritePicks.pick(from: mixed, max: 4).count == 2)
    }

    @Test("A premise appears only from a real synopsis; bundle placeholders never show")
    func premiseIsReal() throws {
        let bundle = try TasteCard(anime: Self.animeCard(1, title: "Your Name.", banner: "https://example.invalid/b.jpg"))
        #expect(bundle.premise == nil, "AnimeCard.displayDescription is a placeholder, never a premise")
        #expect(bundle.media.displayDescription.isEmpty)
        #expect(bundle.bannerURL == "https://example.invalid/b.jpg")
        let personal = try TasteCard(because: Self.becauseCard(9, title: "Frieren",
                                                               synopsis: "An elf mage <i>outlives</i> her party. Then she travels."))
        #expect(personal.premise == "An elf mage outlives her party.")
        #expect(try TasteCard(because: Self.becauseCard(9, title: "F", synopsis: nil)).premise == nil)
        #expect(TastePicksCopy.storySentence("No description available") == nil)
        #expect(TastePicksCopy.storySentence("  ") == nil)
        #expect(try TasteCard(manga: Self.mangaCard(3, title: "Vinland Saga")).bannerURL == nil)
    }

    // MARK: Plan key

    @Test("Plan key rule: plan when missing, un-plan only a bare plan, edit anything else")
    func planKeyRule() {
        typealias E = FakeLibraryBackend
        #expect(TastePlanAction.action(for: nil) == .plan)
        #expect(TastePlanAction.action(for: E.entry(.anime, 1, status: .planning)) == .unplan)
        // A plan the user has since added to is never removed from Taste: the editor opens.
        #expect(TastePlanAction.action(for: E.entry(.anime, 1, status: .planning, notes: "for the weekend")) == .edit)
        #expect(TastePlanAction.action(for: E.entry(.anime, 1, status: .planning, notes: "  ")) == .unplan)
        #expect(TastePlanAction.action(for: E.entry(.anime, 1, status: .planning, rating: 8)) == .edit)
        #expect(TastePlanAction.action(for: E.entry(.anime, 1, status: .planning, progress: 2)) == .edit)
        for status in [ListStatus.current, .completed, .paused, .dropped] {
            #expect(TastePlanAction.action(for: E.entry(.anime, 1, status: status)) == .edit)
        }
        #expect(TastePageCopy.planLabel(medium: .anime, status: nil, german: false) == "Plan to watch")
        #expect(TastePageCopy.planLabel(medium: .manga, status: nil, german: false) == "Plan to read")
        #expect(TastePageCopy.planLabel(medium: .anime, status: .planning, german: false) == "Planned")
        #expect(TastePageCopy.planLabel(medium: .manga, status: nil, german: true) == "Vormerken")
        #expect(TastePageCopy.planLabel(medium: .anime, status: .planning, german: true) == "Geplant")
        #expect(TastePageCopy.planLabel(medium: .anime, status: .current, german: false) == "On your list")
    }

    @Test("The new-account block ends once a planned title is started (only bare plans keep it)")
    func newAccountEndsOnAStartedPlan() {
        typealias E = FakeLibraryBackend
        #expect(HomeShelfPolicy.onlyBarePlans([]))
        #expect(HomeShelfPolicy.onlyBarePlans([E.entry(.anime, 1, status: .planning), E.entry(.manga, 2, status: .planning)]))
        // Up next on the detail page writes progress and keeps PLANNING: that title is started.
        let started = [E.entry(.anime, 1, status: .planning), E.entry(.anime, 3, status: .planning, progress: 1)]
        #expect(!HomeShelfPolicy.onlyBarePlans(started))
        #expect(!HomeShelfPolicy.onlyBarePlans([E.entry(.anime, 1, status: .planning, rating: 8)]))
        #expect(!HomeShelfPolicy.onlyBarePlans([E.entry(.anime, 1, status: .current)]))
        // So the block gives way while latched, even though the shelf scene is not "in progress".
        #expect(!HomeShelfPolicy.showsNewAccount(latched: true, onlyPlannedTitles: HomeShelfPolicy.onlyBarePlans(started),
                                                 scene: .saved, otherMediumOccupied: false))
    }

    @Test("Plan toast copy follows the prototype, EN and DE")
    func planToastCopy() {
        #expect(TastePlanCopy.message(.added, german: false) == "Added to your list.")
        #expect(TastePlanCopy.message(.removed, german: false) == "Removed from your list.")
        #expect(TastePlanCopy.message(.undone, german: false) == "Undone.")
        #expect(TastePlanCopy.message(.failed, german: false) == "Not saved. Your list is unchanged.")
        #expect(TastePlanCopy.message(.added, german: true) == "Zu deiner Liste hinzugefügt.")
        #expect(TastePlanCopy.message(.removed, german: true) == "Von deiner Liste entfernt.")
        #expect(TastePlanCopy.message(.undone, german: true) == "Rückgängig gemacht.")
        #expect(TastePlanCopy.message(.failed, german: true) == "Nicht gespeichert. Deine Liste ist unverändert.")
        #expect(TastePlanCopy.undo(german: false) == "Undo")
        #expect(TastePlanCopy.undo(german: true) == "Rückgängig")
    }

    @Test("One-tap Plan saves .planning through LibraryActions; a double tap writes once; Undo removes (German toasts)")
    func oneTapPlanSaves() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        await harness.signIn()
        let card = try TasteCard(anime: Self.animeCard(42, title: "Your Name."))
        let plans = TastePlanController()
        var edited: [Int] = []
        var routes = KuroRoutes.unhandled
        routes.presentTrackingEditor = { edited.append($0.media.id) }

        let plan = plans.tap(card, library: service.library, actions: service.libraryActions, routes: routes, german: true)
        #expect(plan != nil)
        // A second tap while the first write is in flight does nothing.
        let second = plans.tap(card, library: service.library, actions: service.libraryActions, routes: routes, german: true)
        #expect(second == nil)
        await plan?.value
        #expect(service.library.entry(for: card.key)?.status == .planning)
        #expect(harness.backend.writeCalls == [.insertIfMissing(card.key, .planning)])
        #expect(plans.toast?.message == "Zu deiner Liste hinzugefügt.")
        #expect(plans.toast?.undo?.step == .remove)
        // The banner the other cards use is not raised (no English "Added to collection").
        #expect(service.banner.message == nil)

        let undo = plans.undo(library: service.library, actions: service.libraryActions, german: true)
        #expect(undo != nil)
        await undo?.value
        #expect(service.library.isTracked(card.key) == false)
        #expect(harness.backend.writeCalls.last == .remove(card.key))
        #expect(plans.toast?.message == "Rückgängig gemacht.")
        #expect(plans.toast?.undo == nil, "an Undo is not undone again")
        #expect(edited.isEmpty)
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("A bare plan comes off with one tap and Undo plans it again; a plan with notes opens the editor")
    func unplanAndUndo() async throws {
        let backend = FakeLibraryBackend()
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        let bare = try TasteCard(anime: Self.animeCard(42, title: "Your Name."))
        let noted = try TasteCard(anime: Self.animeCard(43, title: "A Silent Voice"))
        backend.setRows([FakeLibraryBackend.entry(.anime, 42, rowId: 1, status: .planning),
                         FakeLibraryBackend.entry(.anime, 43, rowId: 2, status: .planning, notes: "with Sam")],
                        for: FacadeHarness.userA)
        await harness.signIn()
        let plans = TastePlanController()
        var edited: [Int] = []
        var routes = KuroRoutes.unhandled
        routes.presentTrackingEditor = { edited.append($0.media.id) }

        let unplan = plans.tap(bare, library: service.library, actions: service.libraryActions, routes: routes, german: false)
        await unplan?.value
        #expect(service.library.isTracked(bare.key) == false)
        #expect(plans.toast?.message == "Removed from your list.")
        let undo = plans.undo(library: service.library, actions: service.libraryActions, german: false)
        await undo?.value
        #expect(service.library.entry(for: bare.key)?.status == .planning)
        #expect(plans.toast?.message == "Undone.")

        let writes = backend.writeCalls.count
        let none = plans.tap(noted, library: service.library, actions: service.libraryActions, routes: routes, german: false)
        #expect(none == nil)
        #expect(edited == [43])
        #expect(backend.writeCalls.count == writes, "a plan with notes is never removed from Taste")
        #expect(service.library.entry(for: noted.key)?.notes == "with Sam")
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("A failed Plan says so and offers no Undo; Undo after an account switch writes nothing")
    func planFailureAndAccountSwitch() async throws {
        let backend = FakeLibraryBackend()
        let harness = try FacadeHarness(backend: backend)
        let service = harness.service
        await harness.signIn()
        let card = try TasteCard(anime: Self.animeCard(42, title: "Your Name."))
        let plans = TastePlanController()

        backend.failNextWrite(with: .unavailable(message: "offline"))
        await plans.tap(card, library: service.library, actions: service.libraryActions, routes: .unhandled, german: true)?.value
        #expect(service.library.isTracked(card.key) == false)
        #expect(plans.toast?.message == "Nicht gespeichert. Deine Liste ist unverändert.")
        #expect(plans.toast?.undo == nil)

        await plans.tap(card, library: service.library, actions: service.libraryActions, routes: .unhandled, german: false)?.value
        #expect(plans.toast?.undo != nil)
        // Another account signs in before Undo: nothing is written for it.
        await harness.signIn(FacadeHarness.userB)
        let writes = backend.writeCalls.count
        let undo = plans.undo(library: service.library, actions: service.libraryActions, german: false)
        #expect(undo == nil)
        #expect(backend.writeCalls.count == writes)
        #expect(plans.toast == nil)
        await harness.settleSinks()
        await harness.tearDown()
    }

    @Test("The new-account heading is decided once: a first Plan keeps \"A first favourite.\"")
    func newAccountLatch() {
        #expect(TastePageCopy.latchNewAccount(current: nil, loaded: false, entryCount: 0) == nil)
        #expect(TastePageCopy.latchNewAccount(current: nil, loaded: true, entryCount: 0) == true)
        #expect(TastePageCopy.latchNewAccount(current: nil, loaded: true, entryCount: 2) == false)
        // After the first Plan the Library holds one title; the latched decision stands.
        #expect(TastePageCopy.latchNewAccount(current: true, loaded: true, entryCount: 1) == true)
        #expect(TastePageCopy.latchNewAccount(current: false, loaded: true, entryCount: 0) == false)
    }

    @Test("Because-you picks borrow a banner only from a title the loaded bundle holds")
    func bannerJoin() throws {
        let empty: [[String: Any]] = []
        let object: [String: Any] = [
            "anime": ["essentials": empty, "classics": empty,
                      "new_to_you": [["id": 7, "title_english": "A", "banner_image": "https://example.invalid/b7.jpg"]],
                      "trending": [["id": 8, "title_english": "B", "banner_image": "  "]],
                      "top_rated": [["id": 9, "title_english": "C", "banner_image": "https://example.invalid/b9.jpg"]],
                      "newly_added": empty, "airing_today": empty, "current_season": empty],
            "manga": ["essentials": empty, "classics": empty, "new_to_you": empty, "trending": empty, "top_rated": empty,
                      "newly_added": empty]
        ]
        let bundle = try JSONDecoder().decode(DiscoverBundle.self, from: JSONSerialization.data(withJSONObject: object))
        let map = TasteBanners.map(bundle)
        #expect(map == [7: "https://example.invalid/b7.jpg", 9: "https://example.invalid/b9.jpg"])
        #expect(TasteBanners.map(nil).isEmpty)

        let joined = try TasteCard(because: Self.becauseCard(9, title: "C", synopsis: "A quiet story. More."))
            .withBanner(map[9])
        #expect(joined.bannerURL == "https://example.invalid/b9.jpg")
        #expect(joined.premise == "A quiet story.")
        let alone = try TasteCard(because: Self.becauseCard(10, title: "D", synopsis: nil)).withBanner(map[10])
        #expect(alone.bannerURL == nil)
    }

    // MARK: Taste page

    @Test("Taste headings and opening line follow the prototype; a new account needs a loaded, empty Library")
    func tasteHeadings() {
        #expect(TastePageCopy.kicker(german: false) == "FOR YOUR TASTE")
        #expect(TastePageCopy.opening(medium: .anime, german: false) == "Another world.")
        #expect(TastePageCopy.opening(medium: .manga, german: false) == "Another chapter.")
        #expect(TastePageCopy.heading(medium: .anime, newAccount: false, german: false) == "Your next story.")
        #expect(TastePageCopy.heading(medium: .manga, newAccount: false, german: false) == "Turn to something new.")
        #expect(TastePageCopy.heading(medium: .manga, newAccount: true, german: false) == "A first favourite.")
        #expect(TastePageCopy.heading(medium: .anime, newAccount: false, german: true) == "Deine nächste Geschichte.")
        #expect(TastePageCopy.opening(medium: .manga, german: true) == "Ein anderes Kapitel.")
        #expect(TastePageCopy.isNewAccount(loaded: true, entryCount: 0))
        #expect(!TastePageCopy.isNewAccount(loaded: false, entryCount: 0), "an unanswered Library is not a new account")
        #expect(!TastePageCopy.isNewAccount(loaded: true, entryCount: 3))
    }

    @Test("Story card kind kicker: real format and first genre, nothing invented")
    func kindKicker() {
        #expect(TastePageCopy.kind(format: "MOVIE", genres: ["Romance", "Drama"], german: false) == "FILM · ROMANCE")
        #expect(TastePageCopy.kind(format: "MOVIE", genres: ["Romance"], german: true) == "FILM · ROMANTIK")
        #expect(TastePageCopy.kind(format: "MANGA", genres: ["Supernatural"], german: false) == "MANGA · SUPERNATURAL")
        #expect(TastePageCopy.kind(format: "MANGA", genres: ["Historical"], german: true) == "MANGA · HISTORISCH")
        #expect(TastePageCopy.kind(format: nil, genres: ["Drama"], german: false) == "DRAMA")
        #expect(TastePageCopy.kind(format: nil, genres: nil, german: false) == nil)
        #expect(TastePageCopy.kind(format: " ", genres: [], german: false) == nil)
    }

    // MARK: Collection empty block

    @Test("Collection empty shows the invitation, never a blank page")
    func collectionEmptyInvitation() {
        func resolve(known: Bool = true, failed: Bool = false, empty: Bool = true, imported: Bool = false,
                     query: Bool = false, statusCount: Int = 0, total: Int = 0, error: Bool = false,
                     offline: Bool = false, feedEmpty: Bool = true) -> CollectionEmptyState {
            CollectionEmptyState.resolve(libraryKnown: known, libraryFailed: failed, libraryIsEmpty: empty,
                                         isImportedView: imported, hasQuery: query, statusCount: statusCount,
                                         mediumTotal: total, hasError: error, offline: offline, feedIsEmpty: feedEmpty)
        }
        // A loaded, empty Library: the invitation, online or offline.
        #expect(resolve() == .invitation)
        #expect(resolve(offline: true) == .invitation)
        // Unanswered: stable loading geometry, never an "empty" claim.
        #expect(resolve(known: false) == .awaitingLibrary)
        // A failed read never reads as the invitation.
        #expect(resolve(known: false, failed: true) == .unavailable(offline: false))
        #expect(resolve(error: true) == .unavailable(offline: false))
        // Other statuses hold titles: an honest empty line for this status, even offline.
        #expect(resolve(empty: false, total: 3, offline: true) == .statusEmpty)
        // Nothing in this medium, titles in the other: the medium shortcut.
        #expect(resolve(empty: false, total: 0) == .otherMediumEmpty)
        #expect(resolve(empty: false, query: true, statusCount: 0, total: 3) == .noMatches)
        #expect(resolve(empty: false, imported: true) == .importedEmpty)
    }

    // MARK: Search

    @Test("Search with no history invites a first title, EN and DE")
    func searchNoHistory() {
        #expect(SearchIdleCopy.noHistory(german: false) == "Start with a title you love.")
        #expect(SearchIdleCopy.noHistory(german: true) == "Fang mit einem Titel an, den du liebst.")
    }
}
