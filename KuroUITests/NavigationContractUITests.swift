//
//  NavigationContractUITests.swift
//  KuroUITests
//
//  Navigation contract (docs/superpowers/specs/2026-11-02-navigation-contract-design.md §5), run
//  WITHOUT network: `--kuro-fixture-host` makes every request fail locally, and `--kuro-nav-fixture`
//  opens a root journey over fixture pages built from the real navigation parts (JourneyHost, the
//  journey chrome with its hidden system bar + pop enabler, routes, the tool slot) and the real anime
//  detail page over preview content (Kuro/Views/Routing/NavigationFixture.swift).
//
//  Chains: Back pops one level with the scroll position kept (N1); edge swipe-back pops, a half swipe
//  stays (N2); ✕ on level 5 lands on the start page (N3/N4); swipe-down on level 3 collapses the
//  journey (N3); a tool's Close returns to its detail (N7); opening a page already in the stack pops
//  back to it and the top page is never pushed again (N5); a deep link collapses the journey first (N10),
//  also when a pager page's own sheet (Browse → Filters) is open.
//  Screenshots are attached; set TEST_RUNNER_KURO_NAV_SHOTS=<dir> to also write them as PNGs.
//

import XCTest

final class NavigationContractUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--kuro-fixture-host", "--kuro-skip-auth", "--kuro-nav-fixture",
                                "--kuro-start=discover", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(level(1).waitForExistence(timeout: 20), "the fixture journey opened on level 1")
    }

    // MARK: Helpers

    private var back: XCUIElement { app.buttons["journey.back"].firstMatch }
    private var close: XCUIElement { app.buttons["journey.close"].firstMatch }

    private func level(_ n: Int) -> XCUIElement { app.staticTexts["navfixture.level.\(n)"].firstMatch }
    private func row(_ n: Int) -> XCUIElement { app.staticTexts["navfixture.row.\(n)"].firstMatch }

    /// Scrolls the current page until `element` is hittable, then taps it.
    private func tapScrolling(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "exists: \(element)", file: file, line: line)
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "hittable: \(element)", file: file, line: line)
        element.tap()
    }

    private func fixtureButton(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }

    /// Pushes the next fixture level from the current one.
    private func pushNext(to n: Int, file: StaticString = #filePath, line: UInt = #line) {
        tapScrolling(fixtureButton("navfixture.next"), file: file, line: line)
        XCTAssertTrue(level(n).waitForExistence(timeout: 5), "level \(n) pushed", file: file, line: line)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "a pushed page shows Back", file: file, line: line)
    }

    /// The left-edge swipe: `fraction` of the width, released.
    private func edgeSwipe(to fraction: CGFloat, slow: Bool = false) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
        if slow {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        } else {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// The pager's header avatar: visible only once every journey is gone.
    private var pagerProfile: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Profile'")).firstMatch
    }

    private func assertOnStartPage(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(close.waitForNonExistence(timeout: 6), "the journey closed", file: file, line: line)
        XCTAssertFalse(back.exists, file: file, line: line)
        XCTAssertFalse(level(1).exists, "no fixture page is left", file: file, line: line)
        XCTAssertTrue(pagerProfile.waitForExistence(timeout: 5), "the start page (pager) is back", file: file, line: line)
        XCTAssertTrue(pagerProfile.isHittable, "nothing covers the pager", file: file, line: line)
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["KURO_NAV_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Delivers a link to the RUNNING app (`app.open` relaunches it, which would bypass the collapse);
    /// confirms the system's "Open in Kuro?" prompt when it appears.
    private func openLinkInProcess(_ string: String) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: string)))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    // MARK: N1 Back

    func testBackChevronPopsOneLevelKeepingScrollPosition() throws {
        XCTAssertTrue(close.exists, "the journey's first page shows ✕")
        XCTAssertFalse(back.exists, "the journey's first page shows no Back")

        // Scroll level 1 down to its buttons and remember where row 25 sits.
        let next = fixtureButton("navfixture.next")
        for _ in 0..<10 where !next.isHittable { app.swipeUp() }
        let anchor = row(25)
        XCTAssertTrue(anchor.isHittable)
        let before = anchor.frame.minY
        XCTAssertLessThan(before, app.frame.height * 0.8, "level 1 is scrolled")

        pushNext(to: 2)
        pushNext(to: 3)
        shot("nav-01-level3")

        back.tap()
        XCTAssertTrue(level(3).waitForNonExistence(timeout: 5), "Back pops level 3")
        XCTAssertTrue(level(2).exists, "…to level 2, exactly one level")
        XCTAssertTrue(back.exists, "level 2 is still pushed")

        back.tap()
        XCTAssertTrue(level(2).waitForNonExistence(timeout: 5), "Back pops level 2")
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "level 1 is the first page")
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))
        XCTAssertEqual(anchor.frame.minY, before, accuracy: 2, "level 1 kept its scroll position")
        shot("nav-02-back-to-level1-position-kept")
    }

    // MARK: N2 Edge swipe-back

    func testEdgeSwipeBackPopsAndHalfSwipeStays() throws {
        pushNext(to: 2)

        // Half way, released slowly: the swipe cancels and level 2 stays.
        edgeSwipe(to: 0.3, slow: true)
        sleep(1)
        XCTAssertTrue(level(2).exists, "a half swipe returns to the current page")
        XCTAssertTrue(back.exists)

        // A full swipe pops (the chrome hides the system bar: the pop enabler keeps the gesture alive).
        edgeSwipe(to: 0.9)
        XCTAssertTrue(level(2).waitForNonExistence(timeout: 5), "edge swipe-back pops level 2")
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))

        // The real anime detail page (its own hidden-bar chrome) pops by edge swipe too.
        tapScrolling(fixtureButton("navfixture.title"))
        XCTAssertTrue(back.waitForExistence(timeout: 8), "the fixture title is pushed")
        shot("nav-03-detail-pushed")
        edgeSwipe(to: 0.9)
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "edge swipe-back pops the detail page")
        XCTAssertTrue(level(1).waitForExistence(timeout: 5))
    }

    // MARK: N3/N4 ✕ from depth 5

    func testCloseOnLevelFiveLandsOnStartPage() throws {
        pushNext(to: 2)
        pushNext(to: 3)
        tapScrolling(fixtureButton("navfixture.title"))                     // level 4: the anime detail
        XCTAssertTrue(level(3).waitForNonExistence(timeout: 5))
        // The cast card reads "name, role" (details-songs spec §6: one element per card).
        let character = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fixture Character 1'")).firstMatch
        tapScrolling(character)                                             // level 5: the character page
        XCTAssertTrue(app.staticTexts["Appears in."].firstMatch.waitForExistence(timeout: 8), "the character page is pushed")
        XCTAssertTrue(back.exists, "the character page shows Back")
        XCTAssertTrue(close.exists, "…and ✕")
        shot("nav-04-character-level5")

        // Back from the character returns to the detail (one level).
        back.tap()
        XCTAssertTrue(app.staticTexts["Appears in."].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(character.waitForExistence(timeout: 5), "Back returns to the detail page")
        tapScrolling(character)
        XCTAssertTrue(app.staticTexts["Appears in."].firstMatch.waitForExistence(timeout: 8))

        close.tap()
        assertOnStartPage()
        shot("nav-05-closed-to-start-page")
    }

    // MARK: N3 swipe-down

    func testSwipeDownOnLevelThreeCollapsesJourney() throws {
        pushNext(to: 2)
        pushNext(to: 3)
        // Drag the sheet down from its top bar (where the grabber and the compact bar sit).
        let barY = close.frame.midY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: barY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        assertOnStartPage()
    }

    func testPullDownAtTopOfFirstPageDismisses() throws {
        // H4: the journey's first page at rest at the top: pull-down dismisses the sheet.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        assertOnStartPage()
    }

    func testPullDownOnSearchJourneyDismissesIt() throws {
        // H4 on a real journey root that used to install pull-to-refresh (Search): relaunch without the
        // fixture journey, open Search from the header, pull down from its content.
        app.terminate()
        app.launchArguments.removeAll { $0 == "--kuro-nav-fixture" }
        app.launch()
        let search = app.buttons["magnifyingglass"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let searchClose = app.buttons.matching(NSPredicate(format: "label == 'Close'")).firstMatch
        XCTAssertTrue(searchClose.waitForExistence(timeout: 10), "Search opened as a journey")
        sleep(1)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(searchClose.waitForNonExistence(timeout: 6), "pull-down dismissed Search (no refresh took it)")
        XCTAssertTrue(pagerProfile.waitForExistence(timeout: 5))
    }

    // MARK: N7 tool returns to its page

    func testToolCloseReturnsToItsDetail() throws {
        pushNext(to: 2)
        tapScrolling(fixtureButton("navfixture.title"))
        let add = app.buttons["Add to your list"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let toolClose = app.buttons["addToList.close"].firstMatch
        XCTAssertTrue(toolClose.waitForExistence(timeout: 8), "the tracking editor (tool) opened")
        shot("nav-06-tool-open")
        toolClose.tap()
        XCTAssertTrue(toolClose.waitForNonExistence(timeout: 5), "the tool closed")
        XCTAssertTrue(add.waitForExistence(timeout: 5), "…back to the same detail page")
        XCTAssertTrue(back.exists, "the detail is still the pushed page (the journey stayed)")
        XCTAssertTrue(close.exists)
        back.tap()
        XCTAssertTrue(level(2).waitForExistence(timeout: 5), "the stack below the detail is intact")
    }

    // MARK: N5 no duplicates

    func testOpeningAPageInTheStackPopsBackToIt() throws {
        pushNext(to: 2)
        pushNext(to: 3)

        // The top page is never pushed again.
        tapScrolling(fixtureButton("navfixture.again"))
        sleep(1)
        back.tap()
        XCTAssertTrue(level(3).waitForNonExistence(timeout: 5))
        XCTAssertTrue(level(2).exists, "one Back from level 3 reaches level 2: no copy was pushed")

        // Opening level 1 from level 3 pops back to it instead of pushing a copy.
        pushNext(to: 3)
        tapScrolling(fixtureButton("navfixture.first"))
        XCTAssertTrue(level(3).waitForNonExistence(timeout: 5))
        XCTAssertFalse(level(2).exists)
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "level 1 is the journey's first page again")
        XCTAssertTrue(level(1).exists)
    }

    // MARK: N10 deep link collapses first

    func testDeepLinkCollapsesJourneyThenOpensTarget() throws {
        pushNext(to: 2)
        pushNext(to: 3)
        try openLinkInProcess("kuro://anime/21")
        XCTAssertTrue(level(3).waitForNonExistence(timeout: 10), "the open journey collapsed")
        sleep(4)
        shot("nav-07-deep-link-target")
        // The detail loader's container sets its own identifier (`media_detail_sheet`) on its subtree,
        // so its chrome keys are found by their VoiceOver labels here.
        let targetClose = app.buttons.matching(NSPredicate(format: "label == 'Close'")).firstMatch
        XCTAssertTrue(targetClose.waitForExistence(timeout: 10), "the target opened as a new journey")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch.exists,
                       "the target is the new journey's first page")
        XCTAssertFalse(level(1).exists)
        targetClose.tap()
        XCTAssertTrue(targetClose.waitForNonExistence(timeout: 6))
        assertOnStartPage()
    }

    /// N10 from a pager page's OWN sheet (not a header journey, not the fixture's root journey): Browse →
    /// Filters is open when a link arrives. The filters close first, then the target opens as a journey;
    /// ✕ returns to the pager (before the fix the link was lost under the open sheet).
    func testDeepLinkCollapsesPagerPageSheetThenOpensTarget() throws {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--kuro-nav-fixture" || $0.hasPrefix("--kuro-start=") }
        app.launchArguments.append("--kuro-start=browse")
        app.launch()
        let filters = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filters'")).firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 20), "the Browse page shows its Filters control")
        filters.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "the page's own Filters sheet opened")
        shot("nav-09-pager-sheet-open")
        try openLinkInProcess("kuro://anime/21")
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 10), "the pager page's sheet collapsed first")
        sleep(3)
        shot("nav-10-pager-sheet-link-target")
        let targetClose = app.buttons.matching(NSPredicate(format: "label == 'Close'")).firstMatch
        XCTAssertTrue(targetClose.waitForExistence(timeout: 10), "…then the target opened as a new journey")
        targetClose.tap()
        XCTAssertTrue(targetClose.waitForNonExistence(timeout: 6))
        XCTAssertTrue(pagerProfile.waitForExistence(timeout: 5), "✕ returned to the pager")
        XCTAssertTrue(pagerProfile.isHittable, "nothing covers the pager")
        // The filters still open normally afterwards (their state was cleared, not left stuck).
        filters.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "Filters opens again after the collapse")
        cancel.tap()
    }

    /// N10 keep-journey: a link to the page already on top of the open journey keeps that journey (its
    /// Back stays). A rebuilt root (not the coordinator) would show a fresh journey without Back.
    func testDeepLinkToTopPageKeepsJourney() throws {
        pushNext(to: 2)
        tapScrolling(fixtureButton("navfixture.anime21"))
        let backByLabel = app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch
        XCTAssertTrue(level(2).waitForNonExistence(timeout: 8), "anime 21 is pushed over level 2")
        XCTAssertTrue(backByLabel.waitForExistence(timeout: 8), "the pushed title shows Back")
        try openLinkInProcess("kuro://anime/21")
        sleep(3)
        shot("nav-08-deep-link-keeps-journey")
        XCTAssertTrue(backByLabel.waitForExistence(timeout: 5), "the journey with the target on top was kept")
        backByLabel.tap()
        XCTAssertTrue(level(2).waitForExistence(timeout: 5), "…with its stack below intact")
    }
}
