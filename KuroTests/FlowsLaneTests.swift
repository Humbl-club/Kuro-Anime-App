//
//  FlowsLaneTests.swift
//  KuroTests
//
//  Overnight 2026-11-01 flows lane: the page the pager shows when the series flags hydrate after
//  launch (a start argument, a deep link or the user's own paging is never overridden).
//

import Testing
@testable import Kuro

@MainActor
@Suite("Flows lane: series Home auto-selection after flag hydration")
struct SeriesHomeAutoSelectionTests {
    typealias Section = KuroMainView.Section

    private let seriesOrder = Section.pagerOrder(tasteDeck: true, seriesHome: true)
    private let liveOrder = Section.pagerOrder(tasteDeck: true, seriesHome: false)

    @Test("Flags hydrate on before anything chose a page: Home")
    func untouchedLaunchGoesHome() {
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: true, current: .discover, order: seriesOrder, pageChosen: false) == .home)
    }

    @Test("Already on Home and untouched: stay")
    func alreadyHome() {
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: true, current: .home, order: seriesOrder, pageChosen: false) == nil)
    }

    @Test("A deep link or start argument chose Collection: hydration keeps it")
    func chosenPageIsKept() {
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: true, current: .collection, order: seriesOrder, pageChosen: true) == nil)
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: true, current: .discover, order: seriesOrder, pageChosen: true) == nil)
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: true, current: .clubs, order: seriesOrder, pageChosen: true) == nil)
    }

    @Test("A chosen page the series order lost (Browse) still falls back to Home")
    func lostPageFallsBackToHome() {
        #expect(!seriesOrder.contains(.browse))
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: true, current: .browse, order: seriesOrder, pageChosen: true) == .home)
    }

    @Test("Flag off: Home (not in the live order) falls back to Discover, any other page stays")
    func flagOff() {
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: false, current: .home, order: liveOrder, pageChosen: true) == .discover)
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: false, current: .home, order: liveOrder, pageChosen: false) == .discover)
        #expect(KuroMainView.pageAfterSeriesHomeChange(
            enabled: false, current: .collection, order: liveOrder, pageChosen: false) == nil)
    }
}
