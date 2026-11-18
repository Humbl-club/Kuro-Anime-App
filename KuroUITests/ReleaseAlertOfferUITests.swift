//
//  ReleaseAlertOfferUITests.swift
//  KuroUITests
//
//  W3a: the release alert offer is drawn only by the page the reader is looking at. Real pager, offline
//  (`--kuro-fixture-host`: every request fails locally), a DEBUG fixture offer (`--kuro-offer-fixture`,
//  one unbound offer for anime 501, episode 5). The pager keeps neighbour and visited pages mounted, so
//  several hosts exist at once; only the selected page's host may draw, and a journey over the pager
//  hides it without using it up.
//

import XCTest

final class ReleaseAlertOfferUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(extra: [String] = []) {
        app.launchArguments += ["--kuro-fixture-host", "--kuro-skip-auth", "--ff-on=taste_deck_v1", "--kuro-offer-fixture"]
        app.launchArguments += extra
        app.launchArguments += ["--kuro-start=discover", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private var offers: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "release-alert-offer")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["KURO_OFFER_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testOffscreenNeighbourPagesNeverShowTheOffer() throws {
        launch()
        // Discover is selected; Taste (its left neighbour, a host) is mounted offscreen.
        XCTAssertTrue(offers.firstMatch.waitForExistence(timeout: 25), "the offer appeared on Discover")
        XCTAssertEqual(offers.count, 1, "exactly one offer is on screen")
        let offer = offers.firstMatch
        XCTAssertTrue(offer.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(offer.frame), "the offer lies inside the window")
        shot("offer-on-discover")

        // Swipe to Taste (mounted all along): it shows none. Wait longer than the 10 s hold there.
        app.swipeRight()
        shot("taste-after-swipe")
        XCTAssertTrue(offers.firstMatch.waitForNonExistence(timeout: 6), "Taste drew the offer bound to Discover")
        Thread.sleep(forTimeInterval: 12)
        XCTAssertEqual(offers.count, 0, "Taste still shows no offer after the hold")

        // Back on Discover: the hidden host neither drew nor expired it.
        app.swipeLeft()
        XCTAssertTrue(offers.firstMatch.waitForExistence(timeout: 8), "the offer is back on Discover")
        XCTAssertEqual(offers.count, 1)
    }

    func testJourneySheetOnTopHidesThePagerOfferUntilItCloses() throws {
        launch(extra: ["--kuro-nav-fixture"])
        let close = app.buttons["journey.close"].firstMatch
        XCTAssertTrue(app.staticTexts["navfixture.level.1"].firstMatch.waitForExistence(timeout: 25), "the fixture journey opened")
        XCTAssertEqual(offers.count, 0, "a pager page drew the offer under the journey")
        // Longer than the 10 s hold, still inside the 30 s the offer waits to be drawn.
        Thread.sleep(forTimeInterval: 12)
        XCTAssertEqual(offers.count, 0, "an offer shows while the journey is open")
        XCTAssertTrue(close.exists)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 8), "the journey closed")
        XCTAssertTrue(offers.firstMatch.waitForExistence(timeout: 10), "the offer appears once the sheet closes")
        XCTAssertEqual(offers.count, 1)
        shot("offer-after-journey-closed")
    }
}
