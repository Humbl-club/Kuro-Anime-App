//
//  BrandedStateTests.swift
//  KuroTests
//
//  Prototype-fidelity Task 3: the branded state family (spec §5.4). `KuroBrandedState.resolve` is
//  the one rule that decides whether a surface shows its content, a loading state, an offline or
//  error state, or the empty invitation. Review Focus 5: offline with a cached library keeps the
//  content (plus the offline band); a cold offline launch shows the offline state with Try again.
//  Also pins the EN/DE copy and the motion gate (Reduce Motion and Low Power show the final frame).
//

import CoreGraphics
import KuroCore
import SwiftUI
import Testing
import UIKit
@testable import Kuro

@Suite("Branded states (loading, error, offline, empty)")
struct BrandedStateTests {
    // MARK: resolve

    @Test("offline with content keeps the content and adds the offline band")
    func offlineWithContentKeepsContent() {
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: true, isOffline: true, failed: false)
                == .offline(hasContent: true))
    }

    @Test("a cold offline launch is offline without content")
    func coldOfflineIsOfflineWithoutContent() {
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: false, isOffline: true, failed: false)
                == .offline(hasContent: false))
        // Still loading when the connection drops: offline (with Try again), never an endless loader.
        #expect(KuroBrandedState.resolve(isLoading: true, hasContent: false, isOffline: true, failed: false)
                == .offline(hasContent: false))
    }

    @Test("content wins over loading: no overlay")
    func contentWinsOverLoading() {
        #expect(KuroBrandedState.resolve(isLoading: true, hasContent: true, isOffline: false, failed: false) == nil)
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: true, isOffline: false, failed: false) == nil)
    }

    @Test("a failed read without content is failed without content")
    func failedWithoutContent() {
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: false, isOffline: false, failed: true)
                == .failed(hasContent: false))
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: true, isOffline: false, failed: true)
                == .failed(hasContent: true))
    }

    @Test("offline is named before a failure (the failure is usually the lost connection)")
    func offlineBeatsFailed() {
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: false, isOffline: true, failed: true)
                == .offline(hasContent: false))
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: true, isOffline: true, failed: true)
                == .offline(hasContent: true))
    }

    @Test("loading without content is loading; nothing at all is empty")
    func loadingAndEmpty() {
        #expect(KuroBrandedState.resolve(isLoading: true, hasContent: false, isOffline: false, failed: false) == .loading)
        #expect(KuroBrandedState.resolve(isLoading: false, hasContent: false, isOffline: false, failed: false) == .empty)
    }

    // MARK: copy pins

    @Test("KuroErrorView's default retry label is EN \"Try again\" / DE \"Erneut versuchen\"")
    func retryCopy() {
        #expect(KuroBrandedCopy.retryTitle(german: false) == "Try again")
        #expect(KuroBrandedCopy.retryTitle(german: true) == "Erneut versuchen")
    }

    @Test("offline lines: with content and without")
    func offlineCopy() {
        #expect(KuroBrandedCopy.offlineLine(hasContent: true, german: false) == "You're offline. Showing what you saw last.")
        #expect(KuroBrandedCopy.offlineLine(hasContent: false, german: false) == "Connect to load this.")
        #expect(KuroBrandedCopy.offlineLine(hasContent: true, german: true) == "Du bist offline. Du siehst den letzten Stand.")
        #expect(KuroBrandedCopy.offlineLine(hasContent: false, german: true) == "Verbinde dich, um das zu laden.")
    }

    @Test("every state's copy ships in EN and DE and avoids internal words")
    func copyIsBilingualAndPlain() {
        let forbidden = ["verified", "approved", "fallback", "server"]
        let lines = [
            KuroBrandedCopy.loadingLabel(german: false), KuroBrandedCopy.loadingLabel(german: true),
            KuroBrandedCopy.errorHeadline(german: false), KuroBrandedCopy.errorHeadline(german: true),
            KuroBrandedCopy.errorMessage(german: false), KuroBrandedCopy.errorMessage(german: true),
            KuroBrandedCopy.offlineHeadline(german: false), KuroBrandedCopy.offlineHeadline(german: true),
            KuroBrandedCopy.emptyHeadline(german: false), KuroBrandedCopy.emptyHeadline(german: true),
        ]
        for line in lines {
            #expect(!line.isEmpty)
            for word in forbidden { #expect(!line.lowercased().contains(word), "\(line)") }
        }
        #expect(KuroBrandedCopy.loadingLabel(german: false) != KuroBrandedCopy.loadingLabel(german: true))
        #expect(KuroBrandedCopy.errorHeadline(german: false) != KuroBrandedCopy.errorHeadline(german: true))
    }

    // MARK: motion gate

    @Test("Reduce Motion or Low Power shows the composed final frame")
    func motionGate() {
        #expect(KuroMotion.playsMotion(reduceMotion: false, lowPower: false))
        #expect(!KuroMotion.playsMotion(reduceMotion: true, lowPower: false))
        #expect(!KuroMotion.playsMotion(reduceMotion: false, lowPower: true))
        #expect(!KuroMotion.playsMotion(reduceMotion: true, lowPower: true))
    }

    // MARK: ridge stroke

    @Test("the traced mountain ridge is normalized and runs left to right")
    func ridgeIsNormalized() {
        let points = KuroRidge.points
        #expect(points.count >= 24)
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 1)
        for point in points {
            #expect((0...1).contains(point.x) && (0...1).contains(point.y))
        }
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.x < $1.x })
    }

    // MARK: header neighbour link

    @Test("Home shows \"‹ Taste\" and Taste shows \"Home ›\" only when both pages are in the pager")
    @MainActor
    func headerNeighbourLink() {
        let order: [KuroMainView.Section] = [.taste, .home, .discover, .collection, .clubs]
        #expect(KuroHeaderNeighbour.link(for: .home, order: order) == .taste)
        #expect(KuroHeaderNeighbour.link(for: .taste, order: order) == .home)
        #expect(KuroHeaderNeighbour.link(for: .discover, order: order) == nil)
        let liveOrder: [KuroMainView.Section] = [.taste, .discover, .browse, .collection, .clubs]
        #expect(KuroHeaderNeighbour.link(for: .taste, order: liveOrder) == nil)
        #expect(KuroHeaderNeighbour.title(to: .taste, german: false) == "‹ Taste")
        #expect(KuroHeaderNeighbour.title(to: .home, german: false) == "Home ›")
        #expect(KuroHeaderNeighbour.title(to: .taste, german: true) == "‹ Geschmack")
        #expect(KuroHeaderNeighbour.title(to: .home, german: true) == "Start ›")
    }

    @Test("the header keeps KURO at the default text size from 320 pt, in English and German")
    @MainActor
    func headerKeepsWordmark() {
        let english = ["Taste", "Home", "Discover", "Collection", "Clubs"]
        let german = ["Geschmack", "Start", "Entdecken", "Sammlung", "Clubs"]
        for width: CGFloat in [320, 375, 390, 430] {
            let row = width - 44
            let en = KuroHeaderRowLayout.resolve(rowWidth: row, pageNames: english, neighbourTitle: "‹ Taste")
            #expect(en.showsWordmark && en.showsNeighbour, "EN \(width): \(en)")
            let de = KuroHeaderRowLayout.resolve(rowWidth: row, pageNames: german, neighbourTitle: "‹ Geschmack")
            #expect(de.showsWordmark, "DE \(width): \(de)")
            // The link steps aside before the wordmark does (only the narrowest German row needs it).
            #expect(de.showsNeighbour || width < 375, "DE \(width): \(de)")
            let plain = KuroHeaderRowLayout.resolve(rowWidth: row, pageNames: german, neighbourTitle: nil)
            #expect(plain.showsWordmark && !plain.showsNeighbour, "DE \(width) without link: \(plain)")
        }
    }

    // MARK: review fixes (Task 3 follow-up)

    @Test("Try again is offered for every state but loading, including a full-page empty state")
    func emptyPageKeepsRetry() {
        #expect(KuroStateView.showsRetry(kind: .empty, hasRetry: true))
        #expect(KuroStateView.showsRetry(kind: .failed(hasCachedContent: false), hasRetry: true))
        #expect(KuroStateView.showsRetry(kind: .offline(hasCachedContent: true), hasRetry: true))
        #expect(KuroStateView.showsRetry(kind: .denied, hasRetry: true))
        #expect(!KuroStateView.showsRetry(kind: .loading, hasRetry: true))
        #expect(!KuroStateView.showsRetry(kind: .empty, hasRetry: false))
    }

    @Test("a loading state shows the caller's words under the scrub line; no words, no caption")
    func loadingCaption() {
        #expect(KuroLoadingView.caption(for: "Searching the catalogue.") == "Searching the catalogue.")
        #expect(KuroLoadingView.caption(for: "  ") == nil)
        #expect(KuroLoadingView.caption(for: nil) == nil)
    }

    @Test("KuroErrorView without a message says the plain default sentence")
    @MainActor
    func errorViewDefaultsMessage() {
        #expect(KuroErrorView().message == KuroBrandedCopy.errorMessage(german: KuroLocale.isGerman))
        #expect(KuroErrorView(message: "Check your clubs.").message == "Check your clubs.")
    }

    @Test("the header never shows the link without the wordmark, and the page name stays on screen at AX sizes")
    @MainActor
    func headerAccessibilitySizes() {
        let german = ["Geschmack", "Start", "Entdecken", "Sammlung", "Clubs"]
        let english = ["Taste", "Home", "Discover", "Collection", "Clubs"]
        let sizes: [UIContentSizeCategory] = [.large, .extraExtraExtraLarge, .accessibilityMedium,
                                              .accessibilityExtraLarge, .accessibilityExtraExtraExtraLarge]
        for size in sizes {
            let traits = UITraitCollection(preferredContentSizeCategory: size)
            for row: CGFloat in [276, 331, 346, 386] {
                for (names, link) in [(german, "‹ Geschmack"), (english, "‹ Taste")] {
                    let layout = KuroHeaderRowLayout.resolve(rowWidth: row, pageNames: names, neighbourTitle: link, traits: traits)
                    #expect(layout.showsWordmark || !layout.showsNeighbour, "\(size.rawValue) \(row): \(layout)")
                    let metrics = KuroHeaderRowLayout.metrics(rowWidth: row, pageNames: names, traits: traits)
                    // The centre's left edge: centred in the row, moved left by the shift.
                    let leftEdge = (row - metrics.centreWidth) / 2 - layout.centreShift
                    #expect(leftEdge >= 0 || metrics.centreWidth > row, "\(size.rawValue) \(row): left edge \(leftEdge)")
                }
            }
        }
        // AX5 on a 320 pt phone in German: the link and the wordmark step aside, the name stays whole.
        let ax5 = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let narrow = KuroHeaderRowLayout.resolve(rowWidth: 276, pageNames: german, neighbourTitle: "‹ Geschmack", traits: ax5)
        #expect(!narrow.showsNeighbour)
        // The nil-traits path keeps the default-size behaviour pinned by `headerKeepsWordmark`.
        let standard = UITraitCollection(preferredContentSizeCategory: .large)
        let pinned = KuroHeaderRowLayout.resolve(rowWidth: 346, pageNames: english, neighbourTitle: "‹ Taste", traits: standard)
        #expect(pinned.showsWordmark && pinned.showsNeighbour)
    }

    @Test("the warm Home canvas is on Home, Taste, Discover and Clubs; manga Home takes its own canvas")
    @MainActor
    func pageCanvas() {
        #expect(KuroMainView.Section.home.canvas(mangaHome: false) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.taste.canvas(mangaHome: false) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.taste.canvas(mangaHome: true) == Color.kuroCanvasHome)
        // Taste follows its own medium (amendment 8), with the same tokens Taste paints.
        #expect(KuroMainView.Section.taste.canvas(mangaHome: false, mangaTaste: true) == Color.kuroCanvasHomeManga)
        #expect(KuroMainView.Section.taste.canvas(mangaHome: false, mangaTaste: true) == TastePageContent.canvas(for: .manga))
        #expect(KuroMainView.Section.home.canvas(mangaHome: false, mangaTaste: true) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.home.canvas(mangaHome: true) == Color.kuroCanvasHomeManga)
        // Discover and Clubs share Home's warm canvas (Discover + Clubs redesign D3); the Manga issue takes the manga canvas.
        #expect(KuroMainView.Section.discover.canvas(mangaHome: true) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.discover.canvas(mangaHome: false, mangaDiscover: true) == Color.kuroCanvasHomeManga)
        #expect(KuroMainView.Section.clubs.canvas(mangaHome: true) == Color.kuroCanvasHome)
        #expect(KuroMainView.Section.collection.canvas(mangaHome: false) == Color.kuroBackground)
    }

    @Test("the medium switch words are 36 pt, 30 pt on phones ≤ 360 pt, and 24 pt compact")
    @MainActor
    func mediumSwitchWordSize() {
        // The switch's row is the phone less its gutters: 390 → 350, 375 → 343, 360 → 328, 320 → 288.
        #expect(KuroMediumSwitch.wordSize(for: .large, containerWidth: 350) == 36)
        #expect(KuroMediumSwitch.wordSize(for: .large, containerWidth: 343) == 36)
        #expect(KuroMediumSwitch.wordSize(for: .large, containerWidth: 328) == 30)
        #expect(KuroMediumSwitch.wordSize(for: .large, containerWidth: 288) == 30)
        #expect(KuroMediumSwitch.wordSize(for: .large, containerWidth: 0) == 36, "unmeasured: the 390 size")
        #expect(KuroMediumSwitch.wordSize(for: .compact, containerWidth: 390) == 24)
    }

    @Test("display roles never render thin: light weights left over from the serif ramp take the role's weight")
    @MainActor
    func displayRolesIgnoreLightWeights() {
        #expect(KuroTypeRole.displayWeight(.ultraLight, roleDefault: .semibold) == .semibold)
        #expect(KuroTypeRole.displayWeight(.thin, roleDefault: .heavy) == .heavy)
        #expect(KuroTypeRole.displayWeight(.light, roleDefault: .semibold) == .semibold)
        #expect(KuroTypeRole.displayWeight(.regular, roleDefault: .semibold) == .regular)
        #expect(KuroTypeRole.displayWeight(.bold, roleDefault: .semibold) == .bold)
    }

    @Test("the ink key is the prototype's dark gradient for keys without artwork (e.g. Folio)")
    @MainActor
    func inkKeyFace() {
        let ink = KuroKeyFace(style: .ink)
        #expect(ink.top == Color.kuroKeyDarkTop)
        #expect(ink.bottom == Color.kuroKeyDarkBottom)
        #expect(ink.size == 34 && ink.radius == 7)
        let leaf = KuroKeyFace(style: .dark)
        #expect(leaf.size == 40 && leaf.radius == 6, "the manga leaf key keeps its solid face")
    }
}
