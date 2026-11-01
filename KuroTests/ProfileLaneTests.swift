//
//  ProfileLaneTests.swift
//  KuroTests
//
//  The Profile and Lists lane (overnight 2026-11-01): the Folio lists' pure rules (counts from the
//  whole Library, sorts, the capped +1 key, adaptive shelf columns, EN/DE words), the medium-scoped
//  Collection feed arguments, Profile's "Your lists" rules, the tracking editor's words, the import
//  copy and the credited data sources. Pure: no network, no simulator state.
//

import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

@MainActor
struct ProfileLaneTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func entry(_ kind: MediaKind, _ id: Int, _ status: ListStatus, progress: Int = 0,
                              rating: Int? = nil, verdict: Verdict? = nil) -> LibraryEntry {
        LibraryEntry(key: MediaKey(kind: kind, id: id), rowId: id, status: status, progress: progress,
                     rating: rating.flatMap(UserRating.init(value:)), verdict: verdict,
                     createdAt: now, updatedAt: now, revision: 1, lifecycleId: UUID())
    }

    private static func media(_ kind: MediaKind, _ id: Int, title: String, episodes: Int? = nil,
                              chapters: Int? = nil, rating: Double? = nil) -> Media {
        Media(id: id, kind: kind, title: title, imageURL: nil, year: "2020", displayDescription: "",
              episodes: episodes, chapters: chapters, rating: rating, genres: nil, statusRaw: nil,
              formatRaw: nil, popularityValue: nil, trendingValue: nil, createdAtValue: nil)
    }

    private static func item(_ kind: MediaKind, _ id: Int, title: String, status: ListStatus = .current,
                             progress: Int = 0, total: Int? = nil, rating: Int? = nil, catalogue: Double? = nil,
                             releaseIn hours: Double? = nil) -> FolioItem {
        let media = media(kind, id, title: title, episodes: kind == .anime ? total : nil,
                          chapters: kind == .manga ? total : nil, rating: catalogue)
        let next = hours.map {
            ReleaseScheduleItem(medium: kind, mediaId: id, title: title, unitKind: kind == .anime ? .episode : .chapter,
                                unitNumber: Double(progress + 1), releaseAt: now.addingTimeInterval($0 * 3600),
                                basis: .confirmed, source: "anilist")
        }
        return FolioItem(media: media, entry: entry(kind, id, status, progress: progress, rating: rating),
                         progress: progress, next: next, banner: nil)
    }

    // MARK: Status words and counts

    @Test("Counts come from the whole Library, per medium; rewatches count as Watching")
    func countsPerMedium() {
        let entries = [
            Self.entry(.anime, 1, .current), Self.entry(.anime, 2, .repeating), Self.entry(.anime, 3, .planning),
            Self.entry(.anime, 4, .completed), Self.entry(.anime, 5, .dropped), Self.entry(.manga, 1, .current),
            Self.entry(.manga, 2, .paused)
        ]
        let anime = FolioPolicy.counts(entries, medium: .anime)
        #expect(anime[.watching] == 2 && anime[.planned] == 1 && anime[.completed] == 1 && anime[.dropped] == 1)
        #expect(anime[.paused] == nil)
        let manga = FolioPolicy.counts(entries, medium: .manga)
        #expect(manga[.watching] == 1 && manga[.paused] == 1 && manga.values.reduce(0, +) == 2)
    }

    @Test("Status words follow the medium in EN and DE; every status maps back to one word")
    func statusWords() {
        #expect(FolioStatus.watching.title(medium: .anime, german: false) == "Watching")
        #expect(FolioStatus.watching.title(medium: .manga, german: false) == "Reading")
        #expect(FolioStatus.watching.title(medium: .anime, german: true) == "Schaue ich")
        #expect(FolioStatus.watching.title(medium: .manga, german: true) == "Lese ich")
        #expect(FolioStatus.dropped.title(medium: .manga, german: true) == "Abgebrochen")
        for status in ListStatus.allCases {
            #expect(FolioStatus(listStatus: status).listStatuses.contains(status))
        }
        #expect(FolioStatus.allCases.map(\.listStatus) == [.current, .planning, .completed, .paused, .dropped],
                "the batch menu offers Dropped")
    }

    // MARK: Sorting and search

    @Test("Sorts: Recent keeps feed order; Title is localized; Score uses my rating then the catalogue; Next release puts dated first")
    func sorts() {
        let rows = [
            Self.item(.anime, 1, title: "Zeta", rating: 7, catalogue: 9.0),
            Self.item(.anime, 2, title: "alpha", rating: 9, releaseIn: 30),
            Self.item(.anime, 3, title: "Beta", catalogue: 8.5, releaseIn: 2),
            Self.item(.anime, 4, title: "Gamma", catalogue: 9.5)
        ]
        #expect(FolioPolicy.sorted(rows, by: .recent).map(\.media.id) == [1, 2, 3, 4])
        #expect(FolioPolicy.sorted(rows, by: .title).map(\.media.id) == [2, 3, 4, 1])
        #expect(FolioPolicy.sorted(rows, by: .score).map(\.media.id) == [2, 1, 4, 3])
        #expect(FolioPolicy.sorted(rows, by: .nextRelease).map(\.media.id) == [3, 2, 1, 4],
                "soonest first, undated last in feed order")
    }

    @Test("Search matches case- and accent-insensitively; an empty query matches all")
    func search() {
        let row = Self.item(.anime, 1, title: "Pokémon Horizons")
        #expect(FolioPolicy.matches(row, query: "pokemon"))
        #expect(FolioPolicy.matches(row, query: "  "))
        #expect(!FolioPolicy.matches(row, query: "digimon"))
        #expect(FolioCopy.noMatches("x", german: true) == "Keine Titel passen zu „x“.")
    }

    // MARK: The +1 key

    @Test("The key: none outside Watching; caught up at the total; a choice when the unit is labelled; pending while a write runs")
    func keyPhase() {
        #expect(FolioPolicy.keyPhase(status: .planning, progress: 0, total: 12, needsChoice: false, isPending: false) == nil)
        #expect(FolioPolicy.keyPhase(status: .completed, progress: 12, total: 12, needsChoice: false, isPending: false) == nil)
        #expect(FolioPolicy.keyPhase(status: .current, progress: 11, total: 12, needsChoice: false, isPending: false) == .advance)
        #expect(FolioPolicy.keyPhase(status: .current, progress: 12, total: 12, needsChoice: false, isPending: false) == .caughtUp)
        #expect(FolioPolicy.keyPhase(status: .repeating, progress: 3, total: nil, needsChoice: true, isPending: false) == .needsChoice)
        #expect(FolioPolicy.keyPhase(status: .current, progress: 3, total: 12, needsChoice: false, isPending: true) == .pending)
    }

    @Test("A +1 never passes a known total (the series Collection +1 used to omit the cap)")
    func capGuard() {
        #expect(FolioPolicy.mayAdvance(progress: 11, total: 12))
        #expect(!FolioPolicy.mayAdvance(progress: 12, total: 12))
        #expect(!FolioPolicy.mayAdvance(progress: 13, total: 12))
        #expect(FolioPolicy.mayAdvance(progress: 500, total: nil), "unknown total: no cap to enforce")
        let row = Self.item(.manga, 9, title: "Book", progress: 3, total: 0)
        #expect(row.total == nil, "a zero total is unknown, never 0")
    }

    @Test("Position words: Ep./F. and Ch./Kap.; unknown totals are omitted")
    func positions() {
        #expect(FolioPolicy.positionLine(medium: .anime, progress: 7, total: 12, german: false) == "Ep. 7 / 12")
        #expect(FolioPolicy.positionLine(medium: .manga, progress: 141, total: nil, german: true) == "Kap. 141")
        #expect(FolioPolicy.positionLine(medium: .manga, progress: 0, total: nil, german: false) == nil)
        #expect(FolioCopy.advanced(medium: .anime, to: 8, german: true) == "F. 8 markiert.")
    }

    // MARK: Adaptivity

    @Test("Shelf columns come from the content width: manga 2 at 320, 3 at 390, more on iPad; anime scenes 1 on phones")
    func shelfColumns() {
        // 320 pt screen, 16 pt gutters → 288 pt content; 390 → 350; 430 → 390; iPad column 680 → 640.
        #expect(FolioPolicy.shelfColumns(width: 288, medium: .manga, accessibilitySize: false) == 2)
        #expect(FolioPolicy.shelfColumns(width: 350, medium: .manga, accessibilitySize: false) == 3)
        #expect(FolioPolicy.shelfColumns(width: 390, medium: .manga, accessibilitySize: false) == 3)
        #expect(FolioPolicy.shelfColumns(width: 640, medium: .manga, accessibilitySize: false) == 5)
        #expect(FolioPolicy.shelfColumns(width: 640, medium: .manga, accessibilitySize: true) == 2)
        #expect(FolioPolicy.shelfColumns(width: 350, medium: .anime, accessibilitySize: false) == 1)
        #expect(FolioPolicy.shelfColumns(width: 640, medium: .anime, accessibilitySize: false) == 2)
        #expect(FolioPolicy.shelfColumns(width: 0, medium: .manga, accessibilitySize: false) == 2)
        #expect(FolioPolicy.gutter(forWidth: 320) == 16 && FolioPolicy.gutter(forWidth: 390) == 20)
    }

    // MARK: Collection feed scoping

    @Test("Medium scoping: the other medium gets a list type no row has; nil medium keeps both (existing callers)")
    func feedListTypes() {
        let store = CollectionStore(client: nil, accountSession: AccountSessionCoordinator())
        let sentinel = CollectionStore.excludedMediumListType
        let both = store.feedListTypes(status: .current, medium: nil)
        #expect(both.anime == "WATCHING" && both.manga == "READING")
        let anime = store.feedListTypes(status: nil, medium: .anime)
        #expect(anime.anime == nil && anime.manga == sentinel)
        let manga = store.feedListTypes(status: .planning, medium: .manga)
        #expect(manga.anime == sentinel && manga.manga == "PLANNING")
        for status in ListStatus.allCases {
            #expect(store.dbListType(for: status, mediaType: "anime") != sentinel)
            #expect(store.dbListType(for: status, mediaType: "manga") != sentinel)
        }
    }

    @Test("A Profile list request is consumed once and needs a signed-in account")
    func listRequest() {
        let store = CollectionStore(client: nil, accountSession: AccountSessionCoordinator())
        store.requestList(CollectionListRequest(medium: .manga, status: .planning))
        #expect(store.requestedListFilter == nil, "signed out: no request is kept")
        store.requestedListFilter = CollectionListRequest(medium: .manga, status: .planning)
        #expect(store.consumeListRequest() == CollectionListRequest(medium: .manga, status: .planning))
        #expect(store.consumeListRequest() == nil)
    }

    // MARK: Profile

    @Test("Your lists: counts across both media, the summary line, and the request opens the newest cover's medium")
    func profileLists() {
        let entries = [
            Self.entry(.anime, 1, .current), Self.entry(.manga, 2, .repeating), Self.entry(.manga, 3, .completed),
            Self.entry(.anime, 4, .planning)
        ]
        #expect(ProfileListsPolicy.count(entries, status: .current) == 2)
        #expect(ProfileListsPolicy.count(entries, status: .completed) == 1)
        #expect(ProfileListsPolicy.summary(entries, german: false) == "2 anime · 2 manga · 1 completed")
        #expect(ProfileListsPolicy.summary(entries, german: true) == "2 Anime · 2 Manga · 1 abgeschlossen")
        let covers = [Self.media(.manga, 2, title: "B"), Self.media(.anime, 1, title: "A")]
        #expect(ProfileListsPolicy.request(for: .current, covers: covers) == CollectionListRequest(medium: .manga, status: .current))
        #expect(ProfileListsPolicy.request(for: .planning, covers: []).medium == nil)
        #expect(ProfileListsPolicy.rows.map(\.status) == [.current, .planning, .completed])
    }

    @Test("Data sources: four credited sources on their fixed hosts, every use line in EN and DE")
    func dataSources() {
        #expect(KuroDataSource.all.map(\.name) == ["AniList", "MangaDex", "MangaUpdates", "AnimeThemes"])
        for source in KuroDataSource.all {
            #expect(source.url?.host()?.hasSuffix(source.host) == true)
            #expect(!source.use(german: true).isEmpty && source.use(german: true) != source.use(german: false))
        }
        #expect(KuroLegalLinks.privacy?.absoluteString == "https://kuro.app/privacy")
    }

    // MARK: Editor and imports

    @Test("Tracking editor score words in EN and DE, with an unrated fallback")
    func scoreWords() {
        #expect(AddToListCopy.scoreWord(0, german: false) == "Tap to rate")
        #expect(AddToListCopy.scoreWord(10, german: false) == "Canon")
        #expect(AddToListCopy.scoreWord(7, german: true) == "Herausragend")
        #expect(AddToListCopy.scoreWord(42, german: true) == "Zum Bewerten tippen")
    }

    @Test("Import copy never shows raw enum values")
    func importCopy() {
        let phases: [ImportPhase] = [.preparing, .reviewing, .applying, .finalizing, .ready, .cancelled, .failed, .undoing, .undone]
        for phase in phases {
            for german in [false, true] {
                let text = ImportCopy.phase(phase, german: german)
                #expect(text != phase.rawValue && !text.isEmpty)
            }
        }
        #expect(ImportCopy.provider(.myanimelist) == "MyAnimeList")
        #expect(ImportCopy.disposition(.sourceChanged, german: true) == "Zu prüfen")
        #expect(ImportCopy.failure(.reconnect, german: true).hasPrefix("Verbinde"))
    }
}
