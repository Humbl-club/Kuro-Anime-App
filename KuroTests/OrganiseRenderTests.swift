//
//  OrganiseRenderTests.swift
//  KuroTests
//
//  W9: the organisation screens render at the largest Dynamic Type size in English and German, with a
//  non-zero height and no ambiguous layout, and every copy string exists in both languages.
//

import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

@MainActor
@Suite("Organise screens render", .serialized, .timeLimit(.minutes(2)))
struct OrganiseRenderTests {
    private typealias Item = CustomListsStoreTests.Item
    private static let width: CGFloat = 390
    private static let height: CGFloat = 844

    private static func scrollView(in view: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func visit(_ v: UIView) {
            if let scroll = v as? UIScrollView, scroll.contentSize.height > (best?.contentSize.height ?? 0) { best = scroll }
            v.subviews.forEach(visit)
        }
        visit(view)
        return best
    }

    /// Hosts `view` in a window of the foreground scene at the largest type size; returns its laid-out height.
    private static func render<V: View>(_ view: V) async throws -> (height: CGFloat, ambiguous: Bool) {
        let host = UIHostingController(rootView: view.dynamicTypeSize(.accessibility5).frame(width: width, height: height))
        host.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.isHidden = false
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var last: CGFloat = 0
        for attempt in 0..<12 {
            try await Task.sleep(for: .milliseconds(250))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let reading = max(scrollView(in: host.view)?.contentSize.height ?? 0,
                              host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            if attempt > 0, reading == last, reading > 0 { break }
            last = reading
        }
        let ambiguous = host.view.hasAmbiguousLayout
        window.isHidden = true
        return (last, ambiguous)
    }

    private func rigWithLists() async throws -> (rig: CustomListsStoreTests.Rig, list: UUID, items: [UUID]) {
        let meta = LibrarySourceMetadata(customLists: ["Imported"])
        let rig = try await CustomListsStoreTests.Rig(entries: [
            FakeLibraryBackend.entry(.anime, 1, sourceMetadata: meta), FakeLibraryBackend.entry(.anime, 2)])
        let list = UUID(), other = UUID()
        let items = [UUID(), UUID(), UUID()]
        let json = [
            CustomListsStoreTests.listJSON(list, "Comfort shelf with a rather long name", revision: 3, [
                Item(id: items[0], key: MediaKey(kind: .anime, id: 1), position: "1024"),
                Item(id: items[1], key: MediaKey(kind: .anime, id: 2), position: "2048"),
                Item(id: items[2], key: MediaKey(kind: .manga, id: 77), position: "3072")]),
            CustomListsStoreTests.listJSON(other, "Later", revision: 0, []),
        ].joined(separator: ",")
        rig.f.server.respond { request in
            request.resource == "rpc/custom_lists_v1" ? .json("[\(json)]") : .emptyArray
        }
        await rig.store.load()
        return (rig, list, items)
    }

    @Test("Your lists (two lists and the import offer) renders at the largest type size", arguments: [false, true])
    func listsIndexRenders(german: Bool) async throws {
        let (rig, _, _) = try await rigWithLists()
        defer { rig.f.tearDown() }
        let page = CustomListsJourneyPage(forcedGerman: german).environment(rig.store).environment(NetworkMonitor())
        let result = try await Self.render(page)
        #expect(result.height > 0 && !result.ambiguous, "german=\(german) height=\(result.height)")
    }

    @Test("One list (three titles, one no longer in the library, Arrange on, stale-move notice) renders", arguments: [false, true])
    func listPageRenders(german: Bool) async throws {
        let (rig, list, items) = try await rigWithLists()
        defer { rig.f.tearDown() }
        let account = try #require(rig.f.accountSession.current)
        let pending = CustomListPendingMove(listId: list, itemId: items[0], afterItemId: nil, beforeItemId: nil,
                                            account: account, isRetry: false)
        let page = CustomListJourneyPage(listId: list, forcedGerman: german, startsArranging: true, previewStaleMove: pending)
            .environment(rig.store).environment(NetworkMonitor())
        let result = try await Self.render(page)
        #expect(result.height > 0 && !result.ambiguous, "german=\(german) height=\(result.height)")
        #expect(!rig.store.isTracked(MediaKey(kind: .manga, id: 77)), "the manga row shows 'No longer in your library'")
    }

    @Test("The tags-and-lists sheet (three tags, two lists ticked) renders", arguments: [false, true])
    func organiseSheetRenders(german: Bool) async throws {
        let (rig, _, _) = try await rigWithLists()
        defer { rig.f.tearDown() }
        let tags = rig.f.tags()
        let both = [
            CustomListsStoreTests.listJSON(UUID(), "Comfort", revision: 1, [Item(id: UUID(), key: MediaKey(kind: .anime, id: 1), position: "1024")]),
            CustomListsStoreTests.listJSON(UUID(), "Weekend", revision: 1, [Item(id: UUID(), key: MediaKey(kind: .anime, id: 1), position: "1024")]),
            CustomListsStoreTests.listJSON(UUID(), "Later", revision: 0, []),
        ].joined(separator: ",")
        rig.f.server.respond { request in
            switch request.resource {
            case "rpc/library_tag_index_v1": return .json(#"[{"medium":"anime","media_id":1,"tags":["comfy","rewatch","slow burn"]}]"#)
            case "rpc/custom_lists_v1": return .json("[\(both)]")
            default: return .emptyArray
            }
        }
        await tags.load()
        await rig.store.load(force: true)
        let media = Media(id: 1, kind: .anime, title: "A fairly long anime title that wraps", imageURL: nil, year: "2024",
                          displayDescription: "", episodes: 12, chapters: nil, rating: nil, genres: nil, statusRaw: nil,
                          formatRaw: nil, popularityValue: nil, trendingValue: nil, createdAtValue: nil)
        let sheet = TitleOrganiseSheet(media: media, forcedGerman: german).environment(tags).environment(rig.store)
        let result = try await Self.render(sheet)
        #expect(result.height > 0 && !result.ambiguous, "german=\(german) height=\(result.height)")
    }

    @Test("The tag words (five tags) render and wrap nothing sideways", arguments: [false, true])
    func tagWordsRender(german: Bool) async throws {
        let words = FolioTagWords(tags: ["comfy", "rewatch", "slow burn", "cried at the end", "with friends"],
                                  selected: "comfy", gutter: 20) { _ in }
        let result = try await Self.render(words)
        #expect(result.height > 0 && !result.ambiguous)
    }

    @Test("Every copy string exists in English and German and differs between them")
    func copyIsTranslated() {
        let en = OrganiseCopy.allStrings(german: false), de = OrganiseCopy.allStrings(german: true)
        #expect(en.count == de.count && !en.isEmpty)
        #expect(de.allSatisfy { !$0.isEmpty })
        for (english, german) in zip(en, de) { #expect(english != german, "\(english) is not translated") }
        #expect(OrganiseCopy.string(.notInLibrary, german: true) == "Nicht mehr in deiner Bibliothek")
        #expect(OrganiseCopy.string(.notInLibrary, german: false) == "No longer in your library")
        #expect(OrganiseCopy.string(.tryAgain, german: false) == "Try again")
    }
}
