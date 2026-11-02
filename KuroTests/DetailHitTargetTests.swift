//
//  DetailHitTargetTests.swift
//  KuroTests
//
//  The hero's status mark lays out at its own 14 pt line but must take touches across 44 pt
//  (FIDELITY_REVIEW, Detail pathway: "Status mark hit area"). The mark's menu sits in an overlay at its
//  own 44 pt frame; this test hosts the mark in a real window and asks UIKit's hit test, which is the
//  path a finger takes, how tall the band that reaches the mark is. The menu is UIKit-backed, so the
//  probe sees it as its own view. Pure SwiftUI controls (the credit rows) are not visible to this probe:
//  the hosting view answers every point for them, so their contentShape targets stay unprobed here.
//

import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

@MainActor
@Suite("Detail hit targets", .serialized)
struct DetailHitTargetTests {

    @Test("The status mark takes touches across 44 pt while laying out at its 14 pt line",
          arguments: [DetailMarkTone.onArt, DetailMarkTone.onPaper])
    func statusMarkTarget(tone: DetailMarkTone) async throws {
        let entry = FakeLibraryBackend.entry(.anime, 1, rowId: 1, status: .current, progress: 3)
        let mark = DetailStatusMark(entry: entry, kind: .anime, onListSettings: {}, onFavourite: {},
                                    onVerdict: {}, onProviders: {}, tone: tone)
        let size = CGSize(width: 300, height: 240)
        let host = UIHostingController(rootView: ZStack { mark }.frame(width: size.width, height: size.height))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()

        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let target = window.hitTest(centre, with: nil)
        #expect(target != nil)
        // The contiguous band, through the mark's centre, whose touches reach the same view as the centre.
        func reaches(_ y: CGFloat) -> Bool {
            window.hitTest(CGPoint(x: centre.x, y: y), with: nil) === target
        }
        var top = centre.y
        while top > 0, reaches(top - 1) { top -= 1 }
        var bottom = centre.y
        while bottom < size.height - 1, reaches(bottom + 1) { bottom += 1 }
        let band = bottom - top + 1
        let classes = Set(stride(from: 0, to: size.height, by: 4).compactMap {
            window.hitTest(CGPoint(x: centre.x, y: $0), with: nil).map { String(describing: type(of: $0)) }
        })
        // ≥ 44 pt (the HIG minimum) and not the whole host (the band must belong to the mark).
        #expect(band >= DetailStatusMark.targetHeight - 1, "band \(band) pt, top \(top), bottom \(bottom), views \(classes)")
        #expect(band < size.height / 2, "the band covers the host, so the test cannot see the mark: \(classes)")
    }
}
