//
//  NavshellUITests.swift
//  KuroUITests
//
//  Navigation contract, shell lane (spec §5): Profile is a journey whose rows push (Back, edge
//  swipe-back) and whose ✕ collapses the whole sheet; Search's ✕ sits top-right; a deep link while
//  Profile and a pushed page are open lands on the target, and ✕ there returns to the pager.
//  Runs signed out of the backend (`--kuro-skip-auth`). Screenshots are attached to the result; set
//  KURO_NAVSHELL_SHOTS=<dir> in the test runner environment to also write them as PNGs.
//

import XCTest

final class NavshellUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--kuro-skip-auth", "--kuro-start=discover", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["KURO_NAVSHELL_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func openProfile() {
        // The header avatar is a menu (Profile, Sign out): open it, then pick the menu's Profile item
        // (the one just above Sign out).
        let avatar = app.buttons.matching(NSPredicate(format: "label == 'Profile'")).firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 15))
        let signOut = app.buttons.matching(NSPredicate(format: "label == 'Sign out'")).firstMatch
        for _ in 0..<3 where !signOut.exists {
            avatar.tap()
            _ = signOut.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(signOut.exists, "the avatar menu opened")
        let items = app.buttons.matching(NSPredicate(format: "label == 'Profile'")).allElementsBoundByIndex
        let menuItem = items.filter { $0.frame.minY < signOut.frame.minY }.max { $0.frame.minY < $1.frame.minY }
        (menuItem ?? avatar).tap()
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Delivers a link to the RUNNING app (`app.open` relaunches it, which would bypass the collapse);
    /// confirms the system's "Open in Kuro?" prompt when it appears.
    private func openLinkInProcess(_ string: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: string)))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    func testProfileJourneyPushesBacksAndCollapses() throws {
        openProfile()
        let close = button("Close")
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertFalse(button("Back").exists, "the journey's first page shows ✕ only")
        shot("01-profile-root")

        // About → Data sources pushes (Back appears), edge swipe-back returns.
        let sources = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Data sources'")).firstMatch
        for _ in 0..<6 where !sources.isHittable { app.swipeUp() }
        sources.tap()
        XCTAssertTrue(button("Back").waitForExistence(timeout: 5))
        shot("02-data-sources-pushed")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(button("Back").waitForNonExistence(timeout: 5), "edge swipe-back pops to Profile")
        shot("03-after-swipe-back")

        // Push again and use the chevron.
        for _ in 0..<6 where !sources.isHittable { app.swipeUp() }
        sources.tap()
        XCTAssertTrue(button("Back").waitForExistence(timeout: 5))
        button("Back").tap()
        XCTAssertTrue(button("Back").waitForNonExistence(timeout: 5))

        // Push, then ✕ collapses the whole journey to Discover.
        for _ in 0..<6 where !sources.isHittable { app.swipeUp() }
        sources.tap()
        XCTAssertTrue(button("Back").waitForExistence(timeout: 5))
        button("Close").tap()
        XCTAssertTrue(button("Close").waitForNonExistence(timeout: 5))
        shot("04-collapsed-to-pager")
    }

    func testSearchJourneyCloseTopRight() throws {
        let search = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search' OR label CONTAINS[c] 'suche'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let close = button("Close")
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(close.frame.midX, app.frame.midX, "Search's ✕ sits top-right")
        shot("05-search-journey")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    func testDeepLinkCollapsesProfileJourneyThenOpensTarget() throws {
        openProfile()
        let sources = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Data sources'")).firstMatch
        XCTAssertTrue(button("Close").waitForExistence(timeout: 10))
        for _ in 0..<6 where !sources.isHittable { app.swipeUp() }
        sources.tap()
        XCTAssertTrue(button("Back").waitForExistence(timeout: 5))

        try openLinkInProcess("kuro://anime/21")
        // Profile + Data sources collapse; the title opens as a new journey (✕ only, no Back).
        XCTAssertTrue(sources.waitForNonExistence(timeout: 10))
        sleep(3)
        shot("06-deep-link-target")
        // The detail page's own ✕ ("Close" with the journey chrome, "Close details" before the detail
        // lane migrates it); no Back: the target is a new journey's first page.
        let close = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Close'")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertFalse(button("Back").exists)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Profile'")).firstMatch.waitForExistence(timeout: 5),
                      "✕ lands on the pager")
        shot("07-deep-link-closed")
    }

    func testSeeAllAndProfileConciergeJourneys() throws {
        // Discover "See all" opens as a journey's first page: ✕ only, ✕ returns to Discover.
        let seeAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'See all'")).firstMatch
        for _ in 0..<4 where !(seeAll.exists && seeAll.isHittable) { app.swipeUp() }
        XCTAssertTrue(seeAll.waitForExistence(timeout: 15))
        seeAll.tap()
        XCTAssertTrue(button("Close").waitForExistence(timeout: 10))
        XCTAssertFalse(button("Back").exists)
        shot("08-see-all-journey")
        button("Close").tap()
        XCTAssertTrue(button("Close").waitForNonExistence(timeout: 5))

        // Profile → Concierge pushes (Back + ✕, laid out under the compact bar).
        app.swipeDown(); app.swipeDown()
        openProfile()
        XCTAssertTrue(button("Close").waitForExistence(timeout: 10))
        let concierge = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Concierge'")).firstMatch
        for _ in 0..<6 where !(concierge.exists && concierge.isHittable) { app.swipeUp() }
        concierge.tap()
        XCTAssertTrue(button("Back").waitForExistence(timeout: 5))
        sleep(2)
        shot("09-profile-concierge-pushed")
        button("Back").tap()
        XCTAssertTrue(button("Back").waitForNonExistence(timeout: 5))
        button("Close").tap()
    }
}
