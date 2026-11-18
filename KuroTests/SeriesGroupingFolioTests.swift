import Foundation
import KuroCore
import KuroLibrary
import SwiftUI
import Testing
@testable import Kuro

/// W6: the grouped Folio rows (pure mapping, fold state, selection, batch target, rendering).
@MainActor
@Suite struct SeriesGroupingFolioTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func folioItem(_ id: Int, _ status: ListStatus, _ progress: Int, total: Int?, minutes: Int) -> FolioItem {
        let media = Media(id: id, kind: .anime, title: "Title \(id)", imageURL: nil, year: "2024", displayDescription: "",
                          episodes: total, chapters: nil, rating: nil, genres: nil, statusRaw: nil, formatRaw: nil,
                          popularityValue: nil, trendingValue: nil, createdAtValue: nil)
        let entry = LibraryEntry(key: MediaKey(kind: .anime, id: id), rowId: id, status: status, progress: progress,
                                 createdAt: t0, updatedAt: t0.addingTimeInterval(TimeInterval(minutes * 60)))
        return FolioItem(media: media, entry: entry, progress: progress, next: nil, banner: nil)
    }

    static func membership(_ series: String, _ members: [(FolioItem, Int)]) -> [MediaKey: SeriesMembership] {
        Dictionary(uniqueKeysWithValues: members.map {
            ($0.0.key, SeriesMembership(seriesId: series, medium: .anime, sectionKind: .season, ordinal: $0.1,
                                        sortOrder: $0.1, sectionName: "S\($0.1)", isReviewed: true))
        })
    }

    static func group(_ series: String, _ items: [(FolioItem, Int)], feed: [FolioItem]) -> [FolioItem] {
        let m = membership(series, items)
        let rows = SeriesListGrouping.rows(items.map(\.0.entry), membership: m)
        let all = items.map(\.0)
        return FolioGrouping.items(feed: feed, index: SeriesListIndex(rows: rows),
                                   member: { key in all.first { $0.key == key } }, membership: m, german: false)
    }

    @Test func expandShowsEverySeasonWithOwnStatus() throws {
        let s1 = Self.folioItem(501, .completed, 12, total: 12, minutes: 30)   // re-rated last; S2 still decides
        let s2 = Self.folioItem(502, .current, 5, total: 12, minutes: 20)
        let s3 = Self.folioItem(503, .planning, 0, total: 13, minutes: 10)
        let items = Self.group("E", [(s1, 1), (s2, 2), (s3, 3)], feed: [s2])
        let group = try #require(items.first?.group)
        #expect(items.count == 1 && group.label == "S2 · 5/12")
        #expect(group.row.status == .current && group.row.anchor == s2.key)
        #expect(group.members.map(\.sectionLabel) == ["S1", "S2", "S3"])
        #expect(group.members.map(\.item.status) == [.completed, .watching, .planned])
        #expect(group.members.map { FolioPolicy.keyPhase(status: $0.item.entry.status, progress: $0.item.progress,
                                                         total: $0.item.total, needsChoice: false, isPending: false) }
                == [nil, .advance, nil])
        let folds = KuroFoldMemory()
        let open = folds.binding(page: "collection", section: FolioGrouping.foldSection(group))
        #expect(open.wrappedValue == false)
        open.wrappedValue = true
        #expect(folds.isExpanded(page: "collection", section: "series:anime:E"))
        #expect(FolioShelfChunks.split(ids: ["a", "series:anime:E", "c", "d", "e"], columns: 2, expanded: ["series:anime:E"])
                == [.grid(["a", "series:anime:E"]), .band("series:anime:E"), .grid(["c", "d", "e"])])
        #expect(FolioShelfChunks.split(ids: ["a", "b", "c"], columns: 2, expanded: []) == [.grid(["a", "b", "c"])])
    }

    @Test func groupAppearsOnceInItsGroupStatusStrip() throws {
        let s1 = Self.folioItem(511, .completed, 12, total: 12, minutes: 20)   // re-rated after S2
        let s2 = Self.folioItem(512, .current, 5, total: 12, minutes: 10)
        let m = Self.membership("D", [(s1, 1), (s2, 2)])
        let rows = SeriesListGrouping.rows([s1.entry, s2.entry], membership: m)
        let index = SeriesListIndex(rows: rows)
        let all = [s1, s2]
        let member: (MediaKey) -> FolioItem? = { key in all.first { $0.key == key } }
        let watching = FolioGrouping.items(feed: [s2], index: index, member: member, membership: m, german: false)
        let completed = FolioGrouping.items(feed: [s1], index: index, member: member, membership: m, german: false)
        #expect(watching.count == 1 && watching[0].group != nil)
        #expect(completed.isEmpty, "the finished season does not appear again in Completed")
        #expect(FolioGrouping.rowCounts(rows) == [.watching: 1])
    }

    @Test func groupRowActionsTargetOneNamedSeason() throws {
        let s1 = Self.folioItem(521, .completed, 12, total: 12, minutes: 0)
        let s2 = Self.folioItem(522, .current, 5, total: 12, minutes: 10)
        let item = try #require(Self.group("D", [(s1, 1), (s2, 2)], feed: [s2]).first)
        #expect(item.key == s2.key, "the display member is the anchor")
        #expect(FolioGroupCopy.menuEdit(section: "S2", german: false) == "Edit S2")
        #expect(FolioGroupCopy.menuEdit(section: "S2", german: true) == "S2 bearbeiten")
        #expect(FolioGroupCopy.menuRemove(section: "S2", german: false) == "Remove S2 from list")
        let ids = FolioGrouping.selectableIds(for: item)
        #expect(Set(ids) == Set([s1.id, s2.id]))
        #expect(!ids.contains("series:anime:D"))
    }

    @Test func groupAdvanceUsesTheActiveMembersOwnTotal() throws {
        let s1 = Self.folioItem(531, .completed, 24, total: 24, minutes: 0)
        let s2 = Self.folioItem(532, .current, 5, total: 12, minutes: 10)
        let s3 = Self.folioItem(533, .planning, 0, total: 13, minutes: 5)
        let group = try #require(Self.group("A", [(s1, 1), (s2, 2), (s3, 3)], feed: [s2]).first?.group)
        let request = try #require(FolioGrouping.advanceRequest(group: group))
        #expect(request.key == s2.key && request.cap == 12, "never 24 or 13")
        let unknown = Self.folioItem(532, .current, 5, total: nil, minutes: 10)
        let hidden = try #require(Self.group("A", [(s1, 1), (unknown, 2), (s3, 3)], feed: [unknown]).first?.group)
        #expect(FolioGrouping.advanceRequest(group: hidden) == nil, "unknown total: the key is hidden")
        let idle1 = Self.folioItem(541, .completed, 12, total: 12, minutes: 0)
        let idle2 = Self.folioItem(542, .planning, 0, total: 12, minutes: 10)
        let idle = try #require(Self.group("B", [(idle1, 1), (idle2, 2)], feed: [idle2]).first?.group)
        #expect(FolioGrouping.advanceRequest(group: idle) == nil, "no active season: no +1 on the row")
    }

    @Test func searchMatchesAnySeasonTitle() throws {
        let s1 = Self.folioItem(551, .completed, 12, total: 12, minutes: 0)
        let s2 = Self.folioItem(552, .current, 5, total: 12, minutes: 10)
        let item = try #require(Self.group("S", [(s1, 1), (s2, 2)], feed: [s2]).first)
        #expect(FolioGrouping.matches(item, query: "Title 551"))
        #expect(!FolioGrouping.matches(item, query: "nope"))
    }

    @Test func selectedSeasonOfGroupIsWrittenByBatch() async throws {
        let s1 = Self.folioItem(561, .completed, 12, total: 12, minutes: 0)
        let s2 = Self.folioItem(562, .current, 5, total: 12, minutes: 10)
        let item = try #require(Self.group("W", [(s1, 1), (s2, 2)], feed: [s2]).first)
        let keys = FolioGrouping.selectedKeys(items: [item], selected: [s1.id])
        #expect(keys == [s1.key])
        let h = try FacadeHarness(launchArguments: SeriesGroupingCollectionTests.on)
        h.backend.setRows([
            FakeLibraryBackend.entry(.anime, 561, rowId: 1, status: .completed, progress: 12),
            FakeLibraryBackend.entry(.anime, 562, rowId: 2, status: .current, progress: 5),
        ], for: FacadeHarness.userA)
        await h.signIn()
        let outcomes = await h.service.collection.applyBatchStatusChange(.dropped, to: keys, visibleFilter: nil) { edit, key, create in
            await h.service.libraryActions.apply(edit, to: key, createIfMissing: create)
        }
        #expect(outcomes.count == 1)
        let writes = h.backend.writeCalls
        #expect(writes.count == 1)
        if case .edit(_, let key, _)? = writes.first { #expect(key == s1.key) } else { Issue.record("expected one edit of S1: \(writes)") }
        await h.tearDown()
    }

    @Test func prepareRunsAgainWhenLibraryLoads() async throws {
        let ids = [571, 572]
        let h = try FacadeHarness(launchArguments: SeriesGroupingCollectionTests.on)
        h.backend.setRows(SeriesGroupingCollectionTests.threeSeasons(ids: ids), for: FacadeHarness.userA)
        h.server.respond(with: SeriesGroupingCollectionTests.responder(series: "R", ids: ids))
        await h.service.collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [])
        #expect(h.requests(to: "series_entry_spans").isEmpty, "before the account and its Library: nothing to read")
        await h.signIn()
        await h.service.collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [])
        #expect(h.requests(to: "series_entry_spans").count == 1)
        await h.service.collection.prepareSeriesGrouping(medium: .anime, loadedFeed: [])
        #expect(h.requests(to: "series_entry_spans").count == 1, "keys already checked cost no request")
        await h.tearDown()
    }

    @Test func groupRowRendersAtLargestTypeSize() throws {
        let s1 = Self.folioItem(581, .completed, 12, total: 12, minutes: 0)
        let s2 = Self.folioItem(582, .current, 5, total: 12, minutes: 10)
        let item = try #require(Self.group("T", [(s1, 1), (s2, 2)], feed: [s2]).first)
        let folds = KuroFoldMemory()
        folds.setExpanded(true, page: "collection", section: FolioGrouping.foldSection(try #require(item.group)))
        let actions = FolioRowActions(open: { _ in }, advance: { _ in }, edit: { _ in }, classify: { _ in },
                                      remove: { _ in }, toggleSelection: { _ in }, keyPhase: { _ in .advance })
        let view = FolioIndex(items: [item], width: 320, isSelecting: false, selectedKeys: [], actions: actions)
            .environment(\.kuroFoldMemory, folds)
            .environment(\.dynamicTypeSize, .accessibility3)
            .frame(width: 320)
        let host = UIHostingController(rootView: view)
        let height = host.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
        #expect(height > 0)
        let renderer = ImageRenderer(content: view)
        #expect(renderer.uiImage != nil)
        #expect(FolioGroupCopy.showSeasons(3, german: true) == "3 Staffeln zeigen")
        #expect(FolioGroupCopy.hideSeasons(german: true) == "Staffeln ausblenden")
        #expect(FolioGroupCopy.switchTitle(german: true) == "Staffeln bündeln")
    }
}
