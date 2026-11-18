//
//  TrackingEditorRenderTests.swift
//  KuroTests
//
//  F2.4: the tracking editor's repeat-count and date rows render, at the largest Dynamic Type size, in both
//  languages and for both media, without an empty or ambiguous layout. The copy table has an English and a
//  different German string for every key.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import SwiftUI
import UIKit
@testable import Kuro

@MainActor
@Suite("Tracking editor v2 renders", .serialized)
struct TrackingEditorRenderTests {
    private static let anime = Media(
        id: 42, kind: .anime, title: "A very long title that has to wrap across several lines at the largest size",
        imageURL: nil, year: "2024", displayDescription: "", episodes: 12, chapters: nil, rating: nil, genres: nil,
        statusRaw: nil, formatRaw: nil, popularityValue: nil, trendingValue: nil, createdAtValue: nil
    )
    private static let manga = Media(
        id: 43, kind: .manga, title: "Ein sehr langer Titel", imageURL: nil, year: "2023", displayDescription: "",
        episodes: nil, chapters: 80, rating: nil, genres: nil,
        statusRaw: nil, formatRaw: nil, popularityValue: nil, trendingValue: nil, createdAtValue: nil
    )

    /// The scrollable content of the editor for `entry`, laid out at the largest Dynamic Type size.
    private static func contentSize(media: Media, entry: LibraryEntry, german: Bool) async throws -> CGSize {
        let backend = FakeLibraryBackend()
        backend.setRows([entry], for: LifecycleFixtures.userA)
        let harness = try FacadeHarness(backend: backend)
        await harness.signIn()
        let graph = harness.service
        let sheet = AddToListSheet(media: media, forcedGerman: german)
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(NetworkMonitor())
            .dynamicTypeSize(.accessibility5)
        let width: CGFloat = 390
        let height: CGFloat = 844
        let host = UIHostingController(rootView: sheet.frame(width: width, height: height))
        host.safeAreaRegions = []
        // A window in the test host's foreground scene (a scene-less window does not draw).
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.isHidden = false
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        // The editor fills from the projection in a `.task`; let it run, then lay out again.
        // Under a loaded machine that can take long: measure until two readings 300 ms apart agree.
        var size = CGSize.zero
        for attempt in 0..<20 {
            try await Task.sleep(for: .milliseconds(300))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let reading = Self.largestScrollView(in: host.view)?.contentSize ?? .zero
            if attempt > 0, reading == size, reading.height > 0 { break }
            size = reading
        }
        window.isHidden = true
        await harness.tearDown()
        return size
    }

    @Test("Dates and repeat count render at the largest type in English and German, for an anime and a manga: the repeat row adds height and nothing overflows sideways",
          arguments: [true, false])
    func datesAndRepeatRenderAtLargestTypeInBothLanguages(german: Bool) async throws {
        for media in [Self.anime, Self.manga] {
            func entry(repeats: Int) -> LibraryEntry {
                var entry = FakeLibraryBackend.entry(media.kind, media.id, status: .current, progress: 3)
                entry.sourceMetadata = LibrarySourceMetadata(repeatCount: repeats, startedRaw: "2024-05", finishedRaw: "2024-07-14")
                return entry
            }
            let withRepeat = try await Self.contentSize(media: media, entry: entry(repeats: 2), german: german)
            let withoutRepeat = try await Self.contentSize(media: media, entry: entry(repeats: 0), german: german)
            #expect(withoutRepeat.height > 0, "\(media.kind) german=\(german): the editor has no height")
            // The repeat row is the only difference between the two editors: it must take real space (a row that
            // collapsed to nothing, or never rendered, would not).
            #expect(withRepeat.height - withoutRepeat.height >= 44,
                    "\(media.kind) german=\(german): the repeat row added \(withRepeat.height - withoutRepeat.height) pt")
            // Nothing is laid out wider than the 390 pt column, also at the largest type size.
            #expect(withRepeat.width <= 390.5 && withoutRepeat.width <= 390.5,
                    "\(media.kind) german=\(german): content is \(withRepeat.width) pt wide")
        }
    }

    @Test("Every copy key has a non-empty English string that differs from its German one")
    func copyIsTranslated() {
        let pairs: [(String, String)] = [
            (TrackingDateCopy.started(german: false), TrackingDateCopy.started(german: true)),
            (TrackingDateCopy.finished(german: false), TrackingDateCopy.finished(german: true)),
            (TrackingDateCopy.noDate(german: false), TrackingDateCopy.noDate(german: true)),
            (TrackingDateCopy.unknown(german: false), TrackingDateCopy.unknown(german: true)),
            (TrackingDateCopy.noMonth(german: false), TrackingDateCopy.noMonth(german: true)),
            (TrackingDateCopy.noDay(german: false), TrackingDateCopy.noDay(german: true)),
            (TrackingDateCopy.clear(german: false), TrackingDateCopy.clear(german: true)),
            (TrackingDateCopy.repeatCount(2, medium: .anime, german: false), TrackingDateCopy.repeatCount(2, medium: .anime, german: true)),
            (TrackingDateCopy.repeatCount(2, medium: .manga, german: false), TrackingDateCopy.repeatCount(2, medium: .manga, german: true)),
        ]
        for (english, german) in pairs {
            #expect(!english.isEmpty && !german.isEmpty)
            #expect(english != german, "\(english) is not translated")
        }
    }

    @Test("Dates read at their own precision in both languages")
    func displayKeepsPrecision() throws {
        let year = try #require(PartialDate(raw: "2024"))
        let month = try #require(PartialDate(raw: "2024-05"))
        let day = try #require(PartialDate(raw: "2024-05-07"))
        #expect(TrackingDateCopy.display(year, german: false) == "2024")
        #expect(TrackingDateCopy.display(month, german: true).contains("Mai"))
        #expect(TrackingDateCopy.display(month, german: true).contains("2024"))
        #expect(TrackingDateCopy.display(day, german: false).contains("7"))
        #expect(TrackingDateCopy.rowLabel("Started", month, german: false).hasPrefix("Started, "))
        #expect(TrackingDateCopy.rowLabel("Started", nil, german: false) == "Started, not set")
    }

    private static func largestScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var stack = [root]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > (best?.contentSize.height ?? 0) {
                best = scroll
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }
}
