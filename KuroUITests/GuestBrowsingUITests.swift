//
//  GuestBrowsingUITests.swift
//  KuroUITests
//
//  W5 guest browsing, run WITHOUT network (`--kuro-fixture-host`: every request fails locally) and WITHOUT
//  `--kuro-skip-auth`: a signed-out launch with `guest_browsing_v1` forced on shows Discover, not the auth
//  wall; Search and Browse are reachable; Home, Taste, Collection and Clubs show an invitation to make an
//  account. Only identifiers that exist in Discover's offline/failed state are asserted.
//

import XCTest

final class GuestBrowsingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--kuro-fixture-host", "--ff-on=guest_browsing_v1",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]   // no --kuro-skip-auth
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// An edge drag turns a page even over a card's swipe-exclusion zone. Back = toward the previous page.
    private func page(back: Bool) {
        let from = CGVector(dx: back ? 0.02 : 0.98, dy: 0.5)
        let to = CGVector(dx: back ? 0.9 : 0.1, dy: 0.5)
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: to))
    }

    func testSignedOutLaunchShowsDiscoverNotAuthWall() throws {
        XCTAssertTrue(element("discover.page").waitForExistence(timeout: 20), "Discover shows for a signed-out launch")
        XCTAssertFalse(element("auth.wall").exists, "the auth wall must not show")
        XCTAssertFalse(app.buttons["Get started"].exists, "the welcome control must not show")

        // Search and Browse are available.
        let search = app.buttons["header.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(element("search.browseEntry").waitForExistence(timeout: 10), "Search offers the catalogue")
        app.buttons["journey.close"].firstMatch.tap()
        XCTAssertTrue(element("discover.page").waitForExistence(timeout: 10))

        // Home (1 page back) and Taste (2 pages back) are invitations.
        page(back: true)
        XCTAssertTrue(element("guest.invitation.home").waitForExistence(timeout: 5), "Home shows the invitation")
        page(back: true)
        XCTAssertTrue(element("guest.invitation.taste").waitForExistence(timeout: 5), "Taste shows the invitation")

        // Back to Discover, then Collection (1 forward) and Clubs (2 forward).
        page(back: false)
        page(back: false)
        XCTAssertTrue(element("discover.page").waitForExistence(timeout: 5))
        page(back: false)
        XCTAssertTrue(element("guest.invitation.collection").waitForExistence(timeout: 5), "Collection shows the invitation")
        page(back: false)
        XCTAssertTrue(element("guest.invitation.clubs").waitForExistence(timeout: 5), "Clubs shows the invitation")
    }
}
