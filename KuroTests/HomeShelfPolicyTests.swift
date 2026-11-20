import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

@MainActor
@Suite("Home shelf policy")
struct HomeShelfPolicyTests {
    @Test("A watching or reading card is in progress")
    func inProgress() {
        #expect(HomeShelfPolicy.scene(activeListTypes: ["WATCHING"], libraryStatuses: []) == .inProgress)
        #expect(HomeShelfPolicy.scene(activeListTypes: ["READING", "PLANNING"], libraryStatuses: []) == .inProgress)
        #expect(HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: [.current]) == .inProgress)
        #expect(HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: [.repeating]) == .inProgress)
    }

    @Test("Planned or completed titles are saved, not an empty library")
    func saved() {
        #expect(HomeShelfPolicy.scene(activeListTypes: ["PLANNING"], libraryStatuses: [.planning]) == .saved)
        #expect(HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: [.completed]) == .saved)
        #expect(HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: [.paused, .dropped]) == .saved)
    }

    @Test("No titles in the selected medium is the invitation")
    func invitation() {
        #expect(HomeShelfPolicy.scene(activeListTypes: [], libraryStatuses: []) == .invitation)
    }

    @Test("The other medium stays a shortcut and is not selected automatically")
    func otherMedium() {
        #expect(HomeShelfPolicy.otherMediumOccupied(selectedMedium: "anime", animeCount: 0, mangaCount: 2))
        #expect(!HomeShelfPolicy.otherMediumOccupied(selectedMedium: "anime", animeCount: 0, mangaCount: 0))
        #expect(HomeShelfPolicy.otherMediumOccupied(selectedMedium: "manga", animeCount: 1, mangaCount: 0))
    }

    @Test("Planned stage splits up to 6 items across two scenes and a folded grid")
    func plannedStageSplit() throws {
        let cards = try (1...8).map { try HomeLaneTests.card($0, "PLANNING") }
        let stage = HomeShelfPolicy.plannedStage(cards)
        #expect(stage.scenes.map(\.mediaId) == [1, 2])
        #expect(stage.grid.map(\.mediaId) == [3, 4, 5, 6])
        #expect(stage.overflow.map(\.mediaId) == [7, 8])

        let short = try (1...2).map { try HomeLaneTests.card($0, "PLANNING") }
        let shortStage = HomeShelfPolicy.plannedStage(short)
        #expect(shortStage.scenes.map(\.mediaId) == [1, 2])
        #expect(shortStage.grid.isEmpty)
        #expect(shortStage.overflow.isEmpty)

        // Strict in-progress rule for `scenes(_:)` remains untouched.
        #expect(HomeShelfPolicy.scenes(cards).scenes.isEmpty)
        #expect(HomeShelfPolicy.scenes(cards).alsoWatching.isEmpty)
    }

    @Test("Quiet metadata formats honest format and unit count without inventing nil values")
    func quietMetaFormatting() {
        #expect(HomeShelfPolicy.quietMeta(format: "TV", episodes: 26, chapters: nil, medium: .anime, german: false) == "TV · 26 episodes")
        #expect(HomeShelfPolicy.quietMeta(format: "TV", episodes: 1, chapters: nil, medium: .anime, german: true) == "TV · 1 Folge")
        #expect(HomeShelfPolicy.quietMeta(format: "MANGA", episodes: nil, chapters: 120, medium: .manga, german: false) == "Manga · 120 chapters")
        #expect(HomeShelfPolicy.quietMeta(format: nil, episodes: nil, chapters: nil, medium: .anime, german: false) == nil)
    }

    @Test("New-account block stays hidden for saved plans unless starterHold is active")
    func starterHoldKeepsNewAccountOnlyInPlace() {
        #expect(!HomeShelfPolicy.showsNewAccount(latched: true, onlyPlannedTitles: true, scene: .saved,
                                                 otherMediumOccupied: false, starterHold: false))
        #expect(HomeShelfPolicy.showsNewAccount(latched: true, onlyPlannedTitles: true, scene: .saved,
                                                otherMediumOccupied: false, starterHold: true))
    }

    @Test("HomeBundle optimistic library patch updates status in place and removes completed/deleted cards")
    func bundleOptimisticLibraryPatch() throws {
        let animeCard = try HomeLaneTests.card(101, "PLANNING")
        let mangaCard = try HomeLaneTests.card(202, "PLANNING")
        let animeBundle = HomeBundle(medium: "anime", windowDays: 7, homeRevision: 4, active: [animeCard],
                                     upcoming: [], pending: [], scheduleState: "ready", nextCursor: nil,
                                     club: HomeClubSlice(state: "empty", label: "", items: []))
        let mangaBundle = HomeBundle(medium: "manga", windowDays: 7, homeRevision: 5, active: [mangaCard],
                                     upcoming: [], pending: [], scheduleState: "ready", nextCursor: nil,
                                     club: HomeClubSlice(state: "empty", label: "", items: []))

        let watching = try #require(animeBundle.applyingLibraryChange(mediaId: 101, status: .current, progress: 1))
        #expect(watching.active.first?.listType == "WATCHING")
        #expect(watching.active.first?.progress == 1)
        #expect(watching.homeRevision == 4)

        let reading = try #require(mangaBundle.applyingLibraryChange(mediaId: 202, status: .current, progress: 3))
        #expect(reading.active.first?.listType == "READING")
        #expect(reading.active.first?.progress == 3)

        let completed = try #require(watching.applyingLibraryChange(mediaId: 101, status: .completed, progress: 12))
        #expect(completed.active.isEmpty)

        let removed = try #require(reading.applyingLibraryChange(mediaId: 202, status: nil, progress: nil))
        #expect(removed.active.isEmpty)
    }

    @Test("HomeStore marks cross-medium library changes stale and patches cached manga while on anime")
    func homeStoreCrossMediumLibrarySync() async throws {
        let harness = try FacadeHarness()
        await harness.signIn()
        let account = try #require(harness.service.accountSession.current)
        let store = HomeStore(client: nil, accountSession: harness.service.accountSession, library: harness.service.library)
        let animeCard = try HomeLaneTests.card(11, "PLANNING")
        let mangaCard = try HomeLaneTests.card(22, "PLANNING")
        let animeBundle = HomeBundle(medium: "anime", windowDays: 7, homeRevision: 1, active: [animeCard],
                                     upcoming: [], pending: [], scheduleState: "ready", nextCursor: nil,
                                     club: HomeClubSlice(state: "empty", label: "", items: []))
        let mangaBundle = HomeBundle(medium: "manga", windowDays: 7, homeRevision: 1, active: [mangaCard],
                                     upcoming: [], pending: [], scheduleState: "ready", nextCursor: nil,
                                     club: HomeClubSlice(state: "empty", label: "", items: []))
        store.seedForVisualQA(anime: animeBundle, manga: mangaBundle, medium: "anime")

        let sink = HomeLibrarySink()
        sink.store = store
        let mangaKey = MediaKey(kind: .manga, id: 22)
        let updated = FakeLibraryBackend.entry(.manga, 22, status: .current, progress: 2)
        sink.libraryDidChange(LibraryChange(key: mangaKey, kind: .updated,
                                            previous: FakeLibraryBackend.entry(.manga, 22, status: .planning),
                                            current: updated, mutationId: UUID(), account: account))

        #expect(store.isStale(medium: "manga"))
        #expect(!store.isStale(medium: "anime"))
        #expect(store.manga?.active.first?.listType == "READING")
        #expect(store.manga?.active.first?.progress == 2)

        store.cancelAccountWork()
        await harness.tearDown()
    }

    @Test("Adding a first anime or manga populates an empty Home at 0ms and rapid add->remove never leaves a ghost card")
    func firstAddPopulatesHomeImmediatelyAndRemoveClears() async throws {
        let harness = try FacadeHarness()
        await harness.signIn()
        let account = try #require(harness.service.accountSession.current)
        let store = HomeStore(client: nil, accountSession: harness.service.accountSession, library: harness.service.library)
        store.cardSeedLookup = { key in
            switch key.kind {
            case .anime:
                return HomeCardSeed(title: "Frieren", coverImage: "https://example.invalid/f.jpg", bannerImage: nil,
                                    format: "TV", episodes: 28, chapters: nil, volumes: nil)
            case .manga:
                return HomeCardSeed(title: "Vagabond", coverImage: "https://example.invalid/v.jpg", bannerImage: nil,
                                    format: "MANGA", episodes: nil, chapters: 327, volumes: 37)
            }
        }
        let emptyAnime = HomeBundle(medium: "anime", windowDays: 7, homeRevision: 1, active: [],
                                    upcoming: [], pending: [], scheduleState: "ready", nextCursor: nil,
                                    club: HomeClubSlice(state: "empty", label: "", items: []))
        let emptyManga = HomeBundle(medium: "manga", windowDays: 7, homeRevision: 1, active: [],
                                    upcoming: [], pending: [], scheduleState: "ready", nextCursor: nil,
                                    club: HomeClubSlice(state: "empty", label: "", items: []))
        store.seedForVisualQA(anime: emptyAnime, manga: emptyManga, medium: "anime")

        let sink = HomeLibrarySink()
        sink.store = store

        // 1. Add first anime -> appears immediately on Home before any RPC returns.
        let animeKey = MediaKey(kind: .anime, id: 501)
        let addedAnime = FakeLibraryBackend.entry(.anime, 501, status: .planning)
        sink.libraryDidChange(LibraryChange(key: animeKey, kind: .added, previous: nil,
                                            current: addedAnime, mutationId: UUID(), account: account))
        #expect(store.anime?.active.map(\.mediaId) == [501])
        #expect(store.anime?.active.first?.title == "Frieren")
        #expect(store.anime?.active.first?.listType == "PLANNING")

        // 2. Add first manga while still on anime -> manga shelf populates immediately too.
        let mangaKey = MediaKey(kind: .manga, id: 601)
        let addedManga = FakeLibraryBackend.entry(.manga, 601, status: .current, progress: 1)
        sink.libraryDidChange(LibraryChange(key: mangaKey, kind: .added, previous: nil,
                                            current: addedManga, mutationId: UUID(), account: account))
        #expect(store.manga?.active.map(\.mediaId) == [601])
        #expect(store.manga?.active.first?.title == "Vagabond")
        #expect(store.manga?.active.first?.listType == "READING")

        // 3. Rapid remove immediately clears the optimistic card so no ghost remains.
        sink.libraryDidChange(LibraryChange(key: animeKey, kind: .removed, previous: addedAnime,
                                            current: nil, mutationId: UUID(), account: account))
        #expect(store.anime?.active.isEmpty == true)

        store.cancelAccountWork()
        await harness.tearDown()
    }
}
