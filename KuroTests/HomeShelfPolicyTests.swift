import KuroLibrary
import Testing
@testable import Kuro

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
}
