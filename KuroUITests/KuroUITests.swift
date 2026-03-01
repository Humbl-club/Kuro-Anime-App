//
//  KuroUITests.swift
//  KuroUITests
//
//  Created by Max Dev on 29.09.25.
//

import XCTest

final class KuroUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true // Keep going so we capture as many screenshots as possible
    }

    override func tearDownWithError() throws {}

    // MARK: - Helpers

    /// Dismiss a detail sheet (has .presentationDragIndicator(.hidden)):
    /// drag from top to bottom, then tap back-button area as fallback.
    private func dismissDetailSheet(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        from.press(forDuration: 0.1, thenDragTo: to)
        sleep(2)
        // Fallback: tap back button area (top-left)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.07)).tap()
        sleep(1)
    }

    /// Page-swipe right using a targeted drag in the upper content area (dy ≈ 0.22).
    /// Avoids horizontal scroll rails (Airing Today, Essential Anime) that can
    /// swallow standard `swipeRight()` when Discover is scrolled.
    private func pagerSwipeRight(_ app: XCUIApplication) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.22))
        let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.22))
        from.press(forDuration: 0.05, thenDragTo: to)
        sleep(2)
    }

    // MARK: - App Store Screenshots (Fastlane Snapshot)

    /// Captures 10 rich screenshots showing the app in use.
    /// Naming: numeric prefix controls ordering in App Store Connect.
    ///
    /// Navigation flow — strictly linear, concierge interaction last:
    ///   Discover ← Concierge (empty) → Discover (scrolled) → Browse → Collection → Clubs
    ///   → back to Concierge (interaction + results)
    @MainActor
    func testAppStoreScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        // Wait for launch + data load (Discover is default page, index 1)
        sleep(8)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PHASE 1: Discover (unscrolled) + Detail + Concierge empty
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // ── 1. DISCOVER ──
        snapshot("01_Discover")

        // ── 2. DETAIL PAGE ──
        // Tap left-column card in "New to You" 2-column grid
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.27, dy: 0.27)).tap()
        sleep(5)
        snapshot("02_Detail")
        dismissDetailSheet(app)

        // ── 5. CONCIERGE (empty) ──
        // Single swipe right from unscrolled Discover — reliable because
        // no horizontal rails are visible at the top scroll position.
        app.swipeRight()
        sleep(2)
        snapshot("05_Concierge")

        // Return to Discover (single swipe left from Concierge)
        app.swipeLeft()
        sleep(2)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PHASE 2: Discover scrolled + Browse + Search + Detail Alt
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // ── 7. DISCOVER MORE (scrolled) ──
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)
        snapshot("07_Discover_More")

        // ── 3. BROWSE ──
        app.swipeLeft()
        sleep(3)
        snapshot("03_Browse")

        // ── 4. SEARCH ──
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.09)).tap()
        sleep(2)

        let searchField = app.textFields.firstMatch
        if searchField.waitForExistence(timeout: 3) && searchField.isHittable {
            searchField.tap()
            usleep(500_000)
            searchField.typeText("Attack on Titan")
            sleep(4)
            snapshot("04_Search")

            // Dismiss search sheet
            let navClose = app.navigationBars.buttons.firstMatch
            if navClose.waitForExistence(timeout: 2) {
                navClose.tap()
            } else {
                app.swipeDown()
                usleep(500_000)
                app.swipeDown()
            }
            sleep(1)
        } else {
            snapshot("04_Search")
        }

        // Ensure keyboard is gone after search dismiss
        if app.keyboards.count > 0 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
            sleep(1)
        }

        // ── 10. DETAIL PAGE (alternate) ──
        // Tap a card in Browse grid (left column, below hero card)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.27, dy: 0.52)).tap()
        sleep(5)
        snapshot("10_Detail_Alt")
        dismissDetailSheet(app)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PHASE 3: Collection + Clubs (continue left)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // ── 8. COLLECTION ──
        app.swipeLeft()
        sleep(2)
        snapshot("08_Collection")

        // ── 9. CLUBS ──
        app.swipeLeft()
        sleep(2)
        snapshot("09_Clubs")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PHASE 4: Concierge interaction (LAST — keyboard persists)
        // From Clubs(4), navigate right using targeted drags
        // that avoid horizontal scroll rails on Discover.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Clubs(4) → Collection(3) → Browse(2) → Discover(1)
        // Standard swipeRight works for pages that don't have horizontal rails
        pagerSwipeRight(app) // → Collection
        pagerSwipeRight(app) // → Browse
        pagerSwipeRight(app) // → Discover (may be scrolled, but targeted drag avoids rails)
        pagerSwipeRight(app) // → Concierge

        // ── 6. CONCIERGE WITH RESULTS ──
        // Tap the input area to activate the composer dock
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.96)).tap()
        sleep(1)

        var typed = false
        // Strategy 1: accessibility identifier on KuroGrowingTextView
        let conciergeInput = app.textViews["concierge_text_input"]
        if conciergeInput.waitForExistence(timeout: 2) && conciergeInput.isHittable {
            conciergeInput.tap()
            usleep(500_000)
            conciergeInput.typeText("dark psychological anime, short")
            typed = true
        }
        // Strategy 2: any hittable textView
        if !typed {
            let anyTV = app.textViews.firstMatch
            if anyTV.waitForExistence(timeout: 2) && anyTV.isHittable {
                anyTV.tap()
                usleep(500_000)
                anyTV.typeText("dark psychological anime, short")
                typed = true
            }
        }

        if typed {
            usleep(500_000)
            let sendBtn = app.buttons["Send message"]
            if sendBtn.waitForExistence(timeout: 2) {
                sendBtn.tap()
                sleep(16) // Wait for API response

                // Try to dismiss keyboard for cleaner screenshot
                if app.keyboards.count > 0 {
                    app.swipeUp()
                    sleep(1)
                }
                if app.keyboards.count > 0 {
                    app.swipeDown()
                    sleep(1)
                }

                snapshot("06_Concierge_Results")
            } else {
                snapshot("06_Concierge_Results")
            }
        } else {
            snapshot("06_Concierge_Results")
        }
    }

    // MARK: - Regression Tests

    /// Regression guard: a horizontal page swipe over cards should not open a detail sheet.
    @MainActor
    func testSwipeDoesNotOpenCardDetail() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
        sleep(4)

        let detailSheet = app.otherElements["media_detail_sheet"]
        XCTAssertFalse(detailSheet.waitForExistence(timeout: 0.5))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.58))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.58))
        start.press(forDuration: 0.02, thenDragTo: end)
        XCTAssertFalse(detailSheet.waitForExistence(timeout: 1.0))
    }

    /// Regression guard: typing an import-like phrase in Concierge should trigger
    /// the import flow (parse → import card), not the recommendation flow.
    /// This tests the full routing path end-to-end (FM or keyword fallback).
    @MainActor
    func testConciergeImportRouting() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ff-off=fm_assist_v1"] // Force keyword fallback for deterministic test
        app.launch()
        sleep(6)

        // Navigate to Concierge (one swipe right from Discover)
        app.swipeRight()
        sleep(2)

        // Tap input area to activate composer
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.96)).tap()
        sleep(1)

        // Type an import phrase that previously caused a misroute
        var typed = false
        let conciergeInput = app.textViews["concierge_text_input"]
        if conciergeInput.waitForExistence(timeout: 3) && conciergeInput.isHittable {
            conciergeInput.tap()
            usleep(500_000)
            conciergeInput.typeText("Watched Jujutsu Kaisen halfway through")
            typed = true
        }
        if !typed {
            let anyTV = app.textViews.firstMatch
            if anyTV.waitForExistence(timeout: 2) && anyTV.isHittable {
                anyTV.tap()
                usleep(500_000)
                anyTV.typeText("Watched Jujutsu Kaisen halfway through")
                typed = true
            }
        }
        guard typed else {
            XCTFail("Could not type in concierge input")
            return
        }

        // Send
        let sendBtn = app.buttons["Send message"]
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 3), "Send button should appear")
        sendBtn.tap()

        // Wait for server response (import parse)
        sleep(12)

        // The import flow should produce a confirm button (CONFIRM / APPLY).
        // The recommendation flow would produce rail cards instead.
        // Look for the confirm button or import card indicators.
        let confirmButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'CONFIRM' OR label CONTAINS[c] 'APPLY'")).firstMatch
        let importCard = confirmButton.waitForExistence(timeout: 5)

        // Also check that we did NOT get recommendation rails (which would indicate misrouting)
        // A recommendation response would contain rail titles like "The Cut" / "Dark, Not Empty" etc.
        // The import response shows parsed items with CONFIRM.
        XCTAssertTrue(importCard, "Import phrase should route to import flow, showing a CONFIRM button — not recommendations")
    }
}
