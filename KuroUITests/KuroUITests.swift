//
//  KuroUITests.swift
//  KuroUITests
//
//  Created by Max Dev on 29.09.25.
//

import XCTest

final class KuroUITests: XCTestCase {
    private func writeScreenshot(_ screenshot: XCUIScreenshot, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try screenshot.pngRepresentation.write(to: url, options: [.atomic])
    }

    private func attachScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // Lightweight smoke to verify that swipe paging works and to generate reference screenshots.
    // Writes to /tmp so it's easy to grab from the host after the test run.
    @MainActor
    func testSwipePagingScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // Launch view animates for ~2s in Debug.
        sleep(4)
        let discover = XCUIScreen.main.screenshot()
        attachScreenshot(discover, name: "discover")
        try writeScreenshot(discover, to: "/tmp/kuro_ui_discover.png")

        // Discover -> Concierge is a right-swipe (Concierge lives to the left).
        app.swipeRight()
        sleep(1)
        let concierge = XCUIScreen.main.screenshot()
        attachScreenshot(concierge, name: "concierge")
        try writeScreenshot(concierge, to: "/tmp/kuro_ui_concierge.png")

        // Back to Discover.
        app.swipeLeft()
        sleep(1)
        let discoverAfter = XCUIScreen.main.screenshot()
        attachScreenshot(discoverAfter, name: "discover_after")
        try writeScreenshot(discoverAfter, to: "/tmp/kuro_ui_discover_after.png")
    }

    @MainActor
    func testClubsScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(4)

        // Discover -> Clubs
        app.swipeLeft()
        app.swipeLeft()
        app.swipeLeft()
        app.swipeLeft()
        sleep(1)
        let clubs = XCUIScreen.main.screenshot()
        attachScreenshot(clubs, name: "clubs")
        try writeScreenshot(clubs, to: "/tmp/kuro_ui_clubs.png")
    }

    // Regression guard: a horizontal page swipe over cards should not open a detail sheet.
    @MainActor
    func testSwipeDoesNotOpenCardDetail() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(4)

        let detailSheet = app.otherElements["media_detail_sheet"]
        XCTAssertFalse(detailSheet.waitForExistence(timeout: 0.5))

        // Swipe gesture across likely card area; this used to trigger accidental opens.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.58))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.58))
        start.press(forDuration: 0.02, thenDragTo: end)
        XCTAssertFalse(detailSheet.waitForExistence(timeout: 1.0))
    }

    @MainActor
    func testConciergeEditorialVisualDelta() throws {
        func captureConcierge(_ app: XCUIApplication, name: String, path: String) throws {
            app.launch()
            sleep(4)
            let shot = XCUIScreen.main.screenshot()
            attachScreenshot(shot, name: name)
            try writeScreenshot(shot, to: path)
            app.terminate()
        }

        let legacy = XCUIApplication()
        legacy.launchArguments += ["--kuro-start=concierge", "--ff-off=concierge_editorial_v1"]
        try captureConcierge(
            legacy,
            name: "concierge_legacy",
            path: "/tmp/kuro_ui_concierge_legacy.png"
        )

        let editorial = XCUIApplication()
        editorial.launchArguments += ["--kuro-start=concierge", "--ff-on=concierge_editorial_v1"]
        try captureConcierge(
            editorial,
            name: "concierge_editorial",
            path: "/tmp/kuro_ui_concierge_editorial.png"
        )
    }
}
