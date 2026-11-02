import CoreGraphics
import KuroCore
import SwiftUI
import Testing
@testable import Kuro

/// Round-2 fidelity fixes for Home and first run: the Home +1 toast (PROTOTYPE_SPEC.md §3.4, §6), the
/// art-filled medium word's adaptive contrast floor (amendment 7), the story cards' catalogue premise
/// and banner, and the new-account Taste pick count.
@Suite("Home and first run, round 2")
@MainActor
struct HomeFirstRunRound2Tests {

    // MARK: Home +1 toast

    @Test("+1 toast copy is the prototype's, EN and DE")
    func progressToastCopy() {
        #expect(HomeProgressToastCopy.message(.saved, german: false) == "Progress saved.")
        #expect(HomeProgressToastCopy.message(.caughtUp, german: false) == "Caught up.")
        #expect(HomeProgressToastCopy.message(.undone, german: false) == "Undone.")
        #expect(HomeProgressToastCopy.message(.failed, german: false) == "Not saved. Your progress is unchanged.")
        #expect(HomeProgressToastCopy.message(.saved, german: true) == "Fortschritt gespeichert.")
        #expect(HomeProgressToastCopy.message(.caughtUp, german: true) == "Auf dem neuesten Stand.")
        #expect(HomeProgressToastCopy.message(.undone, german: true) == "Rückgängig gemacht.")
        #expect(HomeProgressToastCopy.message(.failed, german: true) == "Nicht gespeichert. Dein Fortschritt ist unverändert.")
    }

    @Test("A +1 that raised the count reads saved (or caught up); a failed save reads not saved; anything else shows nothing")
    func advanceResultRule() {
        #expect(HomeProgressToastCopy.advanceResult(before: 4, after: 5, caughtUpAfter: false, saveFailed: false) == .saved)
        #expect(HomeProgressToastCopy.advanceResult(before: 4, after: 5, caughtUpAfter: true, saveFailed: false) == .caughtUp)
        #expect(HomeProgressToastCopy.advanceResult(before: 4, after: 4, caughtUpAfter: false, saveFailed: true) == .failed)
        // "Choose the next episode on its page", a stale presentation, a refused advance: no toast.
        #expect(HomeProgressToastCopy.advanceResult(before: 4, after: 4, caughtUpAfter: false, saveFailed: false) == nil)
    }

    @Test("Undo reads undone only when the count is back where it was")
    func undoResultRule() {
        #expect(HomeProgressToastCopy.undoResult(before: 4, after: 4, manga: false) == .undone)
        #expect(HomeProgressToastCopy.undoResult(before: 4, after: 5, manga: false) == .undoFailed(position: 5, manga: false))
    }

    @Test("The toast's Undo acts once, only for the title Home advanced last, and the toast leaves by itself")
    func progressToastController() async throws {
        let account = AccountContext(userId: "a", generation: 1)
        let undo = HomeProgressToasts.Undo(medium: "anime", mediaId: 7, lifecycleId: "L", before: 4, after: 5,
                                           account: account)
        let toasts = HomeProgressToasts(holdSeconds: 0.05, assistiveTechnologyRunning: { false })
        toasts.show("Progress saved.", undo: undo)
        #expect(toasts.toast?.message == "Progress saved.")
        #expect(toasts.toast?.undo == undo)
        // Undo is offered only while it would act (HomeStore.undo ignores any other title).
        #expect(HomeProgressToasts.undoApplies(undo, lastKey: MediaKey(kind: .anime, id: 7), lastLifecycle: "L"))
        #expect(!HomeProgressToasts.undoApplies(undo, lastKey: MediaKey(kind: .anime, id: 8), lastLifecycle: "L"))
        #expect(!HomeProgressToasts.undoApplies(undo, lastKey: MediaKey(kind: .manga, id: 7), lastLifecycle: "L"))
        #expect(!HomeProgressToasts.undoApplies(undo, lastKey: MediaKey(kind: .anime, id: 7), lastLifecycle: "M"))
        #expect(toasts.takeUndo() == undo)
        #expect(toasts.toast == nil)
        #expect(toasts.takeUndo() == nil, "Undo acts once.")
        toasts.show("Caught up.", undo: nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(toasts.toast == nil, "The toast leaves after its hold.")
        toasts.show("Undone.", undo: nil)
        toasts.dismiss()
        #expect(toasts.toast == nil)
    }

    // MARK: Medium word fill (amendment 7)

    @Test("The art keeps its colour: only art lighter than the target is darkened, uniformly")
    func artWordMultiplier() {
        // Dark art passes through untouched.
        #expect(HomeMediumWordInk.artMultiplier(meanLuma: 0.25) == 1)
        #expect(HomeMediumWordInk.artMultiplier(meanLuma: HomeMediumWordInk.targetLuma) == 1)
        // Pale art is scaled down to the target mean (a uniform factor keeps the hue).
        let pale = 0.8
        let factor = HomeMediumWordInk.artMultiplier(meanLuma: pale)
        #expect(abs(pale * factor - HomeMediumWordInk.targetLuma) < 0.0001)
        // The target keeps the selected word at least as dark as the unselected word (#6e786f).
        let unselectedLuma = 0.299 * HomeMediumWordInk.unselected.r + 0.587 * HomeMediumWordInk.unselected.g
            + 0.114 * HomeMediumWordInk.unselected.b
        #expect(HomeMediumWordInk.targetLuma < unselectedLuma)
        // The highlight ceiling is lighter than the target (it trims only highlights) and darker
        // than the canvas by a clear margin.
        let ceiling = HomeMediumWordInk.highlightCeiling
        let ceilingLuma = 0.299 * ceiling.r + 0.587 * ceiling.g + 0.114 * ceiling.b
        #expect(ceilingLuma > HomeMediumWordInk.targetLuma && ceilingLuma < 0.7)
        // Unknown luminance (no image): no change.
        #expect(HomeMediumWordInk.artMultiplier(meanLuma: nil) == 1)
    }

    @Test("Mean luma reads the band of the art the word shows")
    func artWordMeanLuma() throws {
        // A 30 x 90 portrait image: white top and bottom thirds, black middle third. A 3:1 word
        // shows a centred 30 x 10 band, which is black.
        let width = 30, height = 90
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 30..<60 { for x in 0..<width { let i = (y * width + x) * 4; pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0 } }
        let image = try #require(pixels.withUnsafeMutableBytes { raw -> CGImage? in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            return context?.makeImage()
        })
        let band = try #require(HomeMediumWordInk.meanLuma(of: image, wordAspect: 3))
        #expect(band < 0.05)
        let whole = try #require(HomeMediumWordInk.meanLuma(of: image, wordAspect: 1.0 / 3.0))
        #expect(whole > 0.6 && whole < 0.7)
    }

    // MARK: Story cards: catalogue premise and banner

    @Test("A catalogue read adds the premise and the banner a card is missing, never replacing real data")
    func cardHydration() {
        let media = Media(id: 15, kind: .anime, title: "Your Name.", imageURL: "c", year: "2016", displayDescription: "",
                          episodes: nil, chapters: nil, rating: nil, genres: nil, statusRaw: nil, formatRaw: "MOVIE",
                          popularityValue: nil, trendingValue: nil, createdAtValue: nil)
        let bare = TasteCard(media: media)
        let filled = bare.hydrated(banner: "b", synopsis: "Two strangers wake up in each other's lives. Then more.")
        #expect(filled.bannerURL == "b")
        #expect(filled.premise == "Two strangers wake up in each other's lives.")
        // The catalogue's placeholder is never a premise.
        #expect(bare.hydrated(banner: nil, synopsis: "No description available").premise == nil)
        // Existing data stays.
        let own = TasteCard(media: media, bannerURL: "own", premise: "Own line.")
        let kept = own.hydrated(banner: "other", synopsis: "Other line.")
        #expect(kept.bannerURL == "own")
        #expect(kept.premise == "Own line.")
    }

    @Test("A slow catalogue read never holds the cards: the wait ends at its limit, the read keeps going")
    func catalogueWaitIsBounded() async {
        let quick = Task { 1 }
        #expect(await TasteCardDetails.finishes(quick, within: .seconds(1)))
        let slow = Task { () -> Int in
            try? await Task.sleep(for: .milliseconds(400))
            return 2
        }
        let start = ContinuousClock.now
        #expect(await !TasteCardDetails.finishes(slow, within: .milliseconds(50)))
        #expect(ContinuousClock.now - start < .milliseconds(350))
        #expect(await slow.value == 2, "The read itself is not cancelled; its result fills in later.")
    }

    // MARK: New-account Taste

    @Test("New-account Taste shows the reference's two cards; a busy account keeps its four")
    func newAccountTastePickCount() {
        #expect(TastePicksCopy.visibleCount(newAccount: true) == 2)
        #expect(TastePicksCopy.visibleCount(newAccount: false) == 4)
    }
}
