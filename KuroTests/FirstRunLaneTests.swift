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

    @Test("Plan key rule: plan when missing, un-plan when planned, edit for any other status")
    func planKeyRule() {
        #expect(TastePlanAction.action(for: nil) == .plan)
        #expect(TastePlanAction.action(for: .planning) == .unplan)
        for status in [ListStatus.current, .completed, .paused, .dropped] {
            #expect(TastePlanAction.action(for: status) == .edit)
        }
        #expect(TastePageCopy.planLabel(medium: .anime, status: nil, german: false) == "Plan to watch")
        #expect(TastePageCopy.planLabel(medium: .manga, status: nil, german: false) == "Plan to read")
        #expect(TastePageCopy.planLabel(medium: .anime, status: .planning, german: false) == "Planned")
        #expect(TastePageCopy.planLabel(medium: .manga, status: nil, german: true) == "Vormerken")
        #expect(TastePageCopy.planLabel(medium: .anime, status: .planning, german: true) == "Geplant")
        #expect(TastePageCopy.planLabel(medium: .anime, status: .current, german: false) == "On your list")
    }

    @Test("One-tap Plan saves through LibraryActions with .planning; a second tap takes it off; another status edits")
    func oneTapPlanSaves() async throws {
        let harness = try FacadeHarness()
        let service = harness.service
        await harness.signIn()
        let card = try TasteCard(anime: Self.animeCard(42, title: "Your Name."))
        var edited: [Int] = []
        var routes = KuroRoutes.unhandled
        routes.presentTrackingEditor = { edited.append($0.media.id) }

        let plan = TastePlan.perform(TastePlanAction.action(for: service.library.entry(for: card.key)?.status),
                                     card: card, actions: service.libraryActions, routes: routes)
        #expect(plan != nil)
        await plan?.value
        #expect(service.library.entry(for: card.key)?.status == .planning)
        #expect(harness.backend.writeCalls.count == 1)

        let unplan = TastePlan.perform(TastePlanAction.action(for: service.library.entry(for: card.key)?.status),
                                       card: card, actions: service.libraryActions, routes: routes)
        await unplan?.value
        #expect(service.library.isTracked(card.key) == false)

        // Another status: the editor opens, nothing is written or removed.
        let writesBefore = harness.backend.writeCalls.count
        let none = TastePlan.perform(TastePlanAction.action(for: .current), card: card,
                                     actions: service.libraryActions, routes: routes)
        #expect(none == nil)
        #expect(edited == [42])
        #expect(harness.backend.writeCalls.count == writesBefore)
        await harness.settleSinks()
        await harness.tearDown()
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
