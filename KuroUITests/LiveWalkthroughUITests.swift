//
//  LiveWalkthroughUITests.swift
//  KuroUITests
//
//  Owner walkthrough of the navigation contract on LIVE data (docs/superpowers/specs/
//  2026-11-02-navigation-contract-design.md). Needs network and a signed-in account on the
//  simulator, so it is skipped unless TEST_RUNNER_KURO_WALK=1. Screenshots: TEST_RUNNER_KURO_WALK_DIR.
//  Each chain checks Back (N1), edge swipe-back (N2), ✕ / swipe-down collapse (N3), the shrinking
//  header (H1/H2) and folds (F1) on the real screens.
//

import XCTest

final class LiveWalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!
    private var step = 0

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KURO_WALK"] == "1", "live walkthrough only")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ff-on=series_foundation_v1", "--ff-on=series_home_native_v1",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        XCTAssertTrue(pagerProfile.waitForExistence(timeout: 30), "the pager is up (signed in)")
    }

    // MARK: Helpers

    private var back: XCUIElement { app.buttons["journey.back"].firstMatch }
    private var close: XCUIElement { app.buttons["journey.close"].firstMatch }
    private var pagerProfile: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Profile'")).firstMatch
    }

    private func shot(_ name: String) {
        step += 1
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["KURO_WALK_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        let prefix = name
        try? screenshot.pngRepresentation.write(to: base.appendingPathComponent("\(prefix).png"))
        try? app.debugDescription.write(to: base.appendingPathComponent("\(prefix).tree.txt"), atomically: true, encoding: .utf8)
    }

    private func tapScrolling(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "exists: \(what)", file: file, line: line)
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "hittable: \(what)", file: file, line: line)
        element.tap()
    }

    private func edgeSwipeBack() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipeSheetDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func assertBackOnPager(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(close.waitForNonExistence(timeout: 8), "\(what): journey closed", file: file, line: line)
        XCTAssertTrue(pagerProfile.waitForExistence(timeout: 5) && pagerProfile.isHittable,
                      "\(what): back on the pager", file: file, line: line)
    }

    // MARK: W1 Home → title → character → appearance → … (Back, swipe-back, ✕)

    func testW1HomeTitleCharacterChain() throws {
        shot("w1-00-home")
        tapScrolling(app.buttons["Open Cowboy Bebop"].firstMatch, "Home: Cowboy Bebop")
        XCTAssertTrue(close.waitForExistence(timeout: 15), "detail journey opened with ✕")
        XCTAssertFalse(back.exists, "journey root has no Back")
        sleep(2)
        shot("w1-01-detail-top")
        app.swipeUp()
        shot("w1-02-detail-scrolled-1")
        XCTAssertTrue(close.isHittable, "✕ stays visible while scrolled (H2)")
        app.swipeUp(); app.swipeUp()
        shot("w1-03-detail-scrolled-3")

        // F1: fold "More episodes" open and closed.
        let more = app.buttons["More episodes"].firstMatch
        if more.exists {
            app.swipeDown()
            tapScrolling(more, "More episodes")
            sleep(1); shot("w1-04-episodes-unfolded")
            let fewer = app.buttons["Fewer episodes"].firstMatch
            XCTAssertTrue(fewer.waitForExistence(timeout: 5), "label flips to Fewer episodes (F2)")
            XCTAssertEqual(fewer.value as? String, "Expanded", "fold reports expanded")
            tapScrolling(fewer, "Fewer episodes")
            sleep(1); shot("w1-05-episodes-folded")
            XCTAssertTrue(more.waitForExistence(timeout: 5) && more.isHittable, "after folding, the control is still in view (F2)")
        }

        // Staff page pushed (N1/N2/N9).
        tapScrolling(app.buttons["Director, Shinichirou Watanabe"].firstMatch, "Director row")
        XCTAssertTrue(back.waitForExistence(timeout: 15), "staff page is pushed: Back shows")
        XCTAssertTrue(close.exists, "pushed page keeps ✕")
        sleep(2); shot("w1-06-staff-pushed")
        app.swipeUp(); sleep(1); shot("w1-07-staff-scrolled")

        // Level 3: one of his works (pushed title page).
        let work = app.buttons["Carole & Tuesday"].firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10), "filmography lists Carole & Tuesday")
        let row = app.scrollViews.containing(.button, identifier: "Carole & Tuesday").element(boundBy: 0)
        for _ in 0..<12 where !work.isHittable { row.swipeLeft() }
        work.tap()
        XCTAssertTrue(app.staticTexts["Carole & Tuesday"].firstMatch.waitForExistence(timeout: 15), "work opened")
        sleep(2); shot("w1-08-work-pushed")
        XCTAssertTrue(back.exists && close.exists, "level 3 shows Back and ✕")

        // Level 4: that title's studio.
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        shot("w1-09-work-scrolled")
        let studio = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Animation, '")).firstMatch
        if studio.exists {
            tapScrolling(studio, "studio row")
            sleep(2); shot("w1-10-studio-pushed")
            // N1: Back pops exactly one level (to the work).
            back.tap()
            XCTAssertTrue(app.staticTexts["Carole & Tuesday"].firstMatch.waitForExistence(timeout: 8), "Back returns to the work")
            sleep(1); shot("w1-11-back-to-work")
        }

        // N2: edge swipe-back from the work to the staff page.
        edgeSwipeBack()
        XCTAssertTrue(app.staticTexts["Shinichirou Watanabe"].firstMatch.waitForExistence(timeout: 8), "edge swipe pops to the staff page")
        sleep(1); shot("w1-12-swiped-back-to-staff")

        // Go deep again, then N3: ✕ from level 3 lands on Home.
        work.tap()
        XCTAssertTrue(app.staticTexts["Carole & Tuesday"].firstMatch.waitForExistence(timeout: 15))
        close.tap()
        assertBackOnPager("✕ from level 3")
        shot("w1-13-closed-to-home")
        XCTAssertTrue(app.buttons["Open Cowboy Bebop"].firstMatch.exists, "landed on Home")

        // N3: swipe-down on a pushed level collapses the whole journey too.
        app.buttons["Open Cowboy Bebop"].firstMatch.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        tapScrolling(app.buttons["Director, Shinichirou Watanabe"].firstMatch, "Director row")
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        sleep(1)
        swipeSheetDown()
        assertBackOnPager("swipe-down from level 2")
        shot("w1-14-swiped-down-to-home")
    }

    // MARK: Exploratory chains (soft: keep going, screenshot everything)

    private func soft(_ ok: Bool, _ what: String) { if !ok { XCTFail("walk: \(what)") } }

    /// A quick page swipe on the header row (never starts on a card).
    private func swipePager(times: Int) {
        for _ in 0..<times {
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.155))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.155))
            a.press(forDuration: 0.01, thenDragTo: b, withVelocity: .fast, thenHoldForDuration: 0)
            sleep(2)
        }
    }

    private func firstHittable(_ query: XCUIElementQuery, timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for e in query.allElementsBoundByIndex where e.exists && e.isHittable { return e }
            usleep(300_000)
        } while Date() < deadline
        return nil
    }

    private func openProfile() {
        pagerProfile.tap()
        let items = app.buttons.matching(NSPredicate(format: "label == 'Profile'"))
        sleep(1)
        if let item = items.allElementsBoundByIndex.last(where: { $0.isHittable && $0.frame.minX < 300 }) { item.tap() }
        _ = close.waitForExistence(timeout: 10)
    }

    private func closeJourneyIfOpen() {
        if close.exists { close.tap(); _ = close.waitForNonExistence(timeout: 6) }
    }

    func testW0SwipeOnCardsTurnsPage() throws {
        continueAfterFailure = true
        // A quick horizontal swipe on plain space (the "Coming up" card) …
        app.buttons["Open Cowboy Bebop"].firstMatch.waitForExistence(timeout: 10)
        let empty = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.27))
        empty.press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.27)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(2); shot("w0-00-swipe-on-coming-up")
        soft(!close.exists, "a swipe on plain space opens nothing")
        closeJourneyIfOpen()
        // … and a quick swipe that starts on the artwork card.
        app.terminate(); app.launch(); _ = pagerProfile.waitForExistence(timeout: 30)
        let art = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.48))
        art.press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.48)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(2); shot("w0-01-swipe-on-artwork")
        soft(!close.exists, "a swipe that starts on a card must not open it")
        soft(app.staticTexts["Discover"].firstMatch.exists, "the swipe turned the page to Discover")
        closeJourneyIfOpen()
        // A plain tap on the same card still opens it (the gate resets after the swipe).
        app.terminate(); app.launch(); _ = pagerProfile.waitForExistence(timeout: 30)
        app.buttons["Open Cowboy Bebop"].firstMatch.tap()
        soft(close.waitForExistence(timeout: 15), "a tap on the card still opens it")
        sleep(1); shot("w0-02-tap-still-opens")
    }

    func testW2Search() throws {
        continueAfterFailure = true
        app.buttons["Search"].firstMatch.tap()
        let field = app.textFields.firstMatch
        soft(field.waitForExistence(timeout: 8), "search field")
        field.tap(); sleep(1); field.typeText("Frieren")
        sleep(4); shot("w2-01-results")
        guard let result = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Frieren'"))) else {
            XCTFail("walk: no visible Frieren result"); return
        }
        result.tap(); sleep(3); shot("w2-02-result-detail")
        soft(back.exists, "result detail is pushed inside Search (Back)")
        app.swipeUp(); app.swipeUp(); sleep(1); shot("w2-03-detail-scrolled")
        app.swipeUp(); app.swipeUp(); sleep(1); shot("w2-04-detail-lower")
        edgeSwipeBack(); sleep(2); shot("w2-05-swiped-back-to-results")
        soft(app.textFields.firstMatch.exists, "swipe-back returns to the results")
        closeJourneyIfOpen(); sleep(1); shot("w2-06-closed")
        soft(pagerProfile.isHittable, "Search ✕ returns to the pager")
    }

    func testW3Discover() throws {
        continueAfterFailure = true
        swipePager(times: 1); shot("w3-00-discover")
        guard let seeAll = firstHittable(app.buttons.matching(NSPredicate(format: "label == 'See all'"))) else {
            XCTFail("walk: no See all"); return
        }
        seeAll.tap(); sleep(3); shot("w3-01-see-all")
        soft(close.exists, "See all is a journey with ✕")
        if let card = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS ' eps' OR label CONTAINS ' ch'")), timeout: 6) {
            card.tap(); sleep(3); shot("w3-02-see-all-card")
            soft(back.exists, "a See-all card pushes (Back)")
            back.tap(); sleep(1); shot("w3-03-back-to-see-all")
        }
        closeJourneyIfOpen(); sleep(1); shot("w3-04-closed")
        soft(pagerProfile.isHittable, "back on the pager")
    }

    func testW4CollectionAndClubs() throws {
        continueAfterFailure = true
        swipePager(times: 2); sleep(1); shot("w4-00-page")
        swipePager(times: 1); sleep(1); shot("w4-01-page")
        swipePager(times: 1); sleep(1); shot("w4-02-page")
    }

    func testW5Profile() throws {
        continueAfterFailure = true
        openProfile(); sleep(2); shot("w5-00-profile")
        soft(close.exists, "Profile is a journey with ✕")
        for i in 1...4 { app.swipeUp(); sleep(1); shot("w5-0\(i)-profile") }
    }

    func testW6DeepLinkWhileProfileOpen() throws {
        continueAfterFailure = true
        openProfile(); sleep(2); shot("w6-00-profile-open")
        XCUIDevice.shared.system.open(URL(string: "kuro://anime/117")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { springboard.buttons["Open"].tap() }
        sleep(5); shot("w6-01-after-link")
        soft(app.staticTexts["Cowboy Bebop"].firstMatch.exists, "link opened Cowboy Bebop")
        soft(!back.exists, "the link opened as a fresh journey (no Back)")
        closeJourneyIfOpen(); sleep(2); shot("w6-02-closed")
        soft(pagerProfile.isHittable, "✕ returns to the pager (Profile was collapsed first)")
    }

    func testW7MangaChain() throws {
        continueAfterFailure = true
        app.buttons["Search"].firstMatch.tap()
        if let manga = firstHittable(app.buttons.matching(NSPredicate(format: "label == 'Manga'")), timeout: 6) { manga.tap() }
        let field = app.textFields.firstMatch
        _ = field.waitForExistence(timeout: 8); field.tap(); sleep(1); field.typeText("Berserk")
        sleep(4); shot("w7-00-manga-results")
        guard let result = firstHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Berserk'"))) else { XCTFail("walk: no Berserk"); return }
        result.tap(); sleep(3); shot("w7-01-manga-detail")
        for i in 2...5 { app.swipeUp(); sleep(1); shot("w7-0\(i)-manga-scrolled") }
    }

    private func searchAndOpen(_ text: String, scope: String? = nil, prefix: String) -> Bool {
        app.buttons["Search"].firstMatch.tap()
        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 8) else { return false }
        field.tap(); sleep(1); field.typeText(text); sleep(3)
        if let scope {
            // The Search sheet's own scope row (below its field), not a page control behind the sheet.
            let row = app.buttons.matching(NSPredicate(format: "label == %@", scope)).allElementsBoundByIndex
                .filter { $0.frame.minY > 150 && $0.frame.minY < 230 && $0.frame.minX >= 0 }
            row.first?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(4)
        }
        guard let r = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).allElementsBoundByIndex
            .first(where: { $0.isHittable }) else { return false }
        // Tap the row's lower part: its top can sit under the sheet's pinned header.
        r.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap(); sleep(3); return true
    }

    func testW8MangaDeep() throws {
        continueAfterFailure = true
        XCUIDevice.shared.system.open(URL(string: "kuro://manga/5")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { springboard.buttons["Open"].tap() }
        soft(close.waitForExistence(timeout: 15), "kuro://manga/5 opens Berserk")
        sleep(3); shot("w8-00-berserk")
        app.swipeUp(); app.swipeUp(); sleep(1)
        if let guts = firstHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Guts'")), timeout: 6) {
            guts.tap(); sleep(3); shot("w8-01-character")
            soft(back.exists && close.exists, "character page pushed (Back + ✕)")
            app.swipeUp(); sleep(1); shot("w8-01b-character-scrolled")
            back.tap(); sleep(2)
        } else { XCTFail("walk: Guts not tappable") }
        if let anime = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Anime adaptation' OR label CONTAINS 'anime adaptation'")), timeout: 4) {
            anime.tap(); sleep(3); shot("w8-02-adaptation")
            soft(back.exists, "the adaptation opens pushed")
            back.tap(); sleep(2)
        } else { shot("w8-02-no-adaptation-button"); XCTFail("walk: 'Seen the anime?' adaptation card is not a button") }
        if let author = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Kentarou Miura'")), timeout: 4) {
            author.tap(); sleep(3); shot("w8-03-author")
            soft(back.exists, "author page pushed")
            app.swipeUp(); sleep(1); shot("w8-04-author-scrolled")
        } else { XCTFail("walk: author row not tappable") }
        close.tap(); sleep(2); shot("w8-05-closed")
        soft(pagerProfile.isHittable, "✕ from the author collapses Search too")
    }

    func testW9ProfileRows() throws {
        continueAfterFailure = true
        let rows = ["Your clubs", "Data sources and credits", "Contact us", "Import from AniList"]
        for (i, row) in rows.enumerated() {
            openProfile(); sleep(2)
            guard let b = firstHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)), timeout: 2) ?? {
                for _ in 0..<5 { app.swipeUp(); if let e = firstHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)), timeout: 1) { return e } }
                return nil }() else { XCTFail("walk: Profile row \(row) not found"); closeJourneyIfOpen(); continue }
            b.tap(); sleep(3); shot("w9-\(i)0-\(row.replacingOccurrences(of: " ", with: "-"))")
            let pushed = back.exists
            let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'Close' OR label == 'Done'")).firstMatch
            if pushed { back.tap() } else if cancel.exists { cancel.tap() } else { swipeSheetDown() }
            sleep(2); shot("w9-\(i)1-after-return")
            soft(close.exists, "\(row): returning lands back in Profile")
            closeJourneyIfOpen(); sleep(1)
        }
        // Show advanced (fold) and Open Collection (N11)
        openProfile(); sleep(2)
        for _ in 0..<5 { app.swipeUp() }
        if let adv = firstHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show advanced' OR label BEGINSWITH 'Advanced'")), timeout: 3) {
            adv.tap(); sleep(2); shot("w9-50-advanced-open")
        }
        closeJourneyIfOpen(); sleep(1)
        openProfile(); sleep(2)
        if let oc = firstHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open Collection'")), timeout: 3) {
            oc.tap(); sleep(3); shot("w9-60-open-collection")
        }
    }

    func testW10CollectionTool() throws {
        continueAfterFailure = true
        swipePager(times: 2); sleep(1)
        guard let row = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cowboy Bebop'")), timeout: 8) else { XCTFail("walk: Collection row"); return }
        shot("w10-00-collection"); row.tap(); sleep(3); shot("w10-01-collection-detail")
        soft(close.exists, "Collection item opens a journey")
        if let mark = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Watching'")), timeout: 4) {
            mark.tap(); sleep(2); shot("w10-02-status-mark")
            if let edit = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'list settings' OR label CONTAINS[c] 'Edit'")), timeout: 3) {
                edit.tap(); sleep(2); shot("w10-03-editor")
                if let x = firstHittable(app.buttons.matching(NSPredicate(format: "identifier == 'addToList.close' OR label == 'Cancel' OR label == 'Close'")), timeout: 3) { x.tap() }
                sleep(2); shot("w10-04-editor-closed")
                soft(app.staticTexts["Cowboy Bebop"].firstMatch.exists && close.exists, "tool closes back to the detail (N7)")
            } else { app.tap(); shot("w10-03-menu-no-editor") }
        }
        closeJourneyIfOpen(); sleep(1); shot("w10-05-closed")
    }

    func testW11TasteAndHome() throws {
        continueAfterFailure = true
        if let planned = firstHittable(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open Rascal'")), timeout: 6) {
            planned.tap(); sleep(3); shot("w11-00-planned-detail")
            soft(close.exists, "planned row opens a journey")
            swipeSheetDown(); sleep(2)
            soft(pagerProfile.isHittable, "swipe-down returns to Home")
        }
        app.buttons["Go to Taste"].firstMatch.tap(); sleep(3); shot("w11-01-taste")
        if let pick = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Open' OR label CONTAINS ' eps'")), timeout: 4) {
            pick.tap(); sleep(3); shot("w11-02-taste-pick")
            closeJourneyIfOpen(); sleep(1)
        }
    }

    func testW12EditorProbe() throws {
        continueAfterFailure = true
        app.buttons["Open Cowboy Bebop"].firstMatch.tap()
        _ = close.waitForExistence(timeout: 15); sleep(2)
        if let mark = firstHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Watching'")), timeout: 4) {
            mark.tap(); sleep(2); shot("w12-00-status-mark-open")
            // Undo the accidental +1 from the first Collection run: back to 0 of 26 through the editor.
            let less = app.buttons["minus"].firstMatch
            if less.exists, (app.staticTexts["1"].firstMatch.exists) { less.tap(); sleep(1) }
            shot("w12-01-progress-zero")
            app.buttons["Save"].firstMatch.tap(); sleep(3)
            shot("w12-02-saved")
            soft(app.staticTexts["Cowboy Bebop"].firstMatch.exists && close.exists, "Save closes the tool back to the detail (N7)")
        }
    }
}
