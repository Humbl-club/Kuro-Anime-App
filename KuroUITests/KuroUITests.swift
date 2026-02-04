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
        try writeScreenshot(XCUIScreen.main.screenshot(), to: "/tmp/kuro_ui_discover.png")

        // Discover -> Concierge is a right-swipe (Concierge lives to the left).
        app.swipeRight()
        sleep(1)
        try writeScreenshot(XCUIScreen.main.screenshot(), to: "/tmp/kuro_ui_concierge.png")

        // Back to Discover.
        app.swipeLeft()
        sleep(1)
        try writeScreenshot(XCUIScreen.main.screenshot(), to: "/tmp/kuro_ui_discover_after.png")
    }
}
