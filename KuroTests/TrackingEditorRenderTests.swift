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

    private static func completed(_ media: Media) -> LibraryEntry {
        var entry = FakeLibraryBackend.entry(media.kind, media.id, status: .completed, progress: 12)
        entry.sourceMetadata = LibrarySourceMetadata(repeatCount: 2, startedRaw: "2024-05", finishedRaw: "2024-07-14")
        return entry
    }

    @Test("Dates and repeat count render at the largest type in English and German, for an anime and a manga",
          arguments: [true, false])
    func datesAndRepeatRenderAtLargestTypeInBothLanguages(german: Bool) async throws {
        for media in [Self.anime, Self.manga] {
            let backend = FakeLibraryBackend()
            backend.setRows([Self.completed(media)], for: LifecycleFixtures.userA)
            let harness = try FacadeHarness(backend: backend)
            await harness.signIn()
            let graph = harness.service
            #expect(graph.library.entry(for: media.libraryKey)?.startedOn?.raw == "2024-05")

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
            try await Task.sleep(for: .milliseconds(300))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let scroll = Self.largestScrollView(in: host.view)
            let content = scroll?.contentSize.height ?? 0
            #expect(content > 0, "\(media.kind) german=\(german): the editor has no height")
            #expect(!host.view.hasAmbiguousLayout, "\(media.kind) german=\(german): ambiguous layout")

            window.isHidden = true
            await harness.tearDown()
        }
    }

    @Test("Every copy key has a non-empty English string that differs from its German one")
    func copyIsTranslated() {
        let pairs: [(String, String)] = [
            (TrackingDateCopy.started(german: false), TrackingDateCopy.started(german: true)),
            (TrackingDateCopy.finished(german: false), TrackingDateCopy.finished(german: true)),
            (TrackingDateCopy.noDate(german: false), TrackingDateCopy.noDate(german: true)),
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
