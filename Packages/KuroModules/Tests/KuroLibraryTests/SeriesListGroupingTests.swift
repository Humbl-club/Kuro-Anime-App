import Foundation
import KuroCore
import KuroLibrary
import Testing

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private let fixedLifecycle = UUID(uuidString: "11111111-2222-3333-4444-555555555555")

private func entry(_ id: Int, _ status: ListStatus, _ progress: Int, minutes: Int, kind: MediaKind = .anime) -> LibraryEntry {
    LibraryEntry(
        key: MediaKey(kind: kind, id: id), rowId: id, status: status, progress: progress,
        createdAt: t0, updatedAt: t0.addingTimeInterval(TimeInterval(minutes * 60)), revision: 1,
        lifecycleId: fixedLifecycle,
        sourceMetadata: LibrarySourceMetadata(scoreRaw: "8", customLists: ["fav"]))
}

private func member(_ series: String, ordinal: Int?, sort: Int, kind: SeriesMembership.SectionKind = .season,
                    reviewed: Bool = true, medium: MediaKind = .anime) -> SeriesMembership {
    SeriesMembership(seriesId: series, medium: medium, sectionKind: kind, ordinal: ordinal, sortOrder: sort,
                     sectionName: "n", isReviewed: reviewed)
}

private func library60() -> ([LibraryEntry], [MediaKey: SeriesMembership]) {
    let entries = (1...60).map { entry($0, ListStatus.allCases[$0 % 6], $0, minutes: $0) }
    let m = Dictionary(uniqueKeysWithValues: entries.filter { $0.key.id % 3 != 0 }.map {
        ($0.key, member("S\($0.key.id % 7)", ordinal: $0.key.id % 5 + 1, sort: $0.key.id)) })
    return (entries, m)
}

@Suite struct SeriesListGroupingTests {
    @Test func reviewedContinuityMembersShareOneRow() {
        let s1 = entry(101, .completed, 12, minutes: 0), s2 = entry(102, .current, 5, minutes: 10)
        let m = [s1.key: member("A", ordinal: 1, sort: 1), s2.key: member("A", ordinal: 2, sort: 2)]
        let rows = SeriesListGrouping.rows([s2, s1], membership: m)
        #expect(rows.count == 1)
        #expect(rows[0].id == .series(.anime, "A"))
        #expect(rows[0].members.map(\.key.id) == [101, 102])
        #expect(rows[0].advanceTarget == s2.key)
        #expect(rows[0].displayMember == s2.key)
        #expect(SeriesListGrouping.rowLabel(rows[0], membership: m, progress: 5, total: 12, german: false) == "S2 · 5/12")
        #expect(SeriesListGrouping.rowLabel(rows[0], membership: m, progress: 5, total: 12, german: true) == "St. 2 · 5/12")
        #expect(SeriesListGrouping.counts(rows) == [.current: 1])
    }

    @Test func unreviewedRelationsStayOwnRows() {
        let a = entry(201, .completed, 12, minutes: 0), b = entry(202, .current, 3, minutes: 5)
        #expect(SeriesListGrouping.rows([b, a], membership: [:]).map(\.id) == [.entry(b.key), .entry(a.key)])
        let unreviewed = [a.key: member("B", ordinal: 1, sort: 1, reviewed: false),
                          b.key: member("B", ordinal: 2, sort: 2, reviewed: false)]
        #expect(SeriesListGrouping.rows([b, a], membership: unreviewed).count == 2)
        #expect(SeriesMembership.isReviewed(continuity: "singleton", groupingState: "approved", sectionState: "approved",
                                            seriesMedium: "anime", spanMedium: "anime") == false)
    }

    @Test func onlyVerifiedApprovedSameMediumMembershipJoins() {
        #expect(SeriesMembership.isReviewed(continuity: "verified", groupingState: "approved", sectionState: "approved",
                                            seriesMedium: "anime", spanMedium: "anime"))
        #expect(!SeriesMembership.isReviewed(continuity: "disputed", groupingState: "approved", sectionState: "approved",
                                             seriesMedium: "anime", spanMedium: "anime"))
        #expect(!SeriesMembership.isReviewed(continuity: "verified", groupingState: "proposed", sectionState: "approved",
                                             seriesMedium: "anime", spanMedium: "anime"))
        #expect(!SeriesMembership.isReviewed(continuity: "verified", groupingState: "approved", sectionState: "superseded",
                                             seriesMedium: "anime", spanMedium: "anime"))
        #expect(!SeriesMembership.isReviewed(continuity: "verified", groupingState: "approved", sectionState: "approved",
                                             seriesMedium: "anime", spanMedium: "manga"))
        let a = entry(1, .current, 1, minutes: 0, kind: .manga), b = entry(2, .current, 1, minutes: 1, kind: .manga)
        let m = [a.key: member("X", ordinal: 1, sort: 1, medium: .anime), b.key: member("X", ordinal: 2, sort: 2, medium: .anime)]
        #expect(SeriesListGrouping.rows([a, b], membership: m).count == 2)
    }

    @Test func sectionLabelComesOnlyFromReviewedOrdinal() {
        #expect(SeriesListGrouping.sectionLabel(member("A", ordinal: nil, sort: 1), german: false) == nil)
        #expect(SeriesListGrouping.sectionLabel(member("A", ordinal: nil, sort: 1, kind: .film), german: false) == "Film")
        #expect(SeriesListGrouping.sectionLabel(member("A", ordinal: nil, sort: 1, kind: .extra), german: true) == "Extra")
        let row = SeriesListGrouping.rows([entry(1, .current, 0, minutes: 0)], membership: [:])[0]
        #expect(SeriesListGrouping.rowLabel(row, membership: [:], progress: 0, total: nil, german: false) == nil)
        #expect(SeriesGrouping.ordinal(fromCalendarSeason: "SPRING") == nil)
    }

    @Test func activeMemberDecidesGroupStatus() throws {
        let s1 = entry(1, .completed, 12, minutes: 20), s2 = entry(2, .current, 5, minutes: 10)
        let m = [s1.key: member("A", ordinal: 1, sort: 1), s2.key: member("A", ordinal: 2, sort: 2)]
        let row = try #require(SeriesListGrouping.rows([s1, s2], membership: m).first)
        #expect(row.status == .current && row.anchor == s2.key && row.advanceTarget == s2.key && row.displayMember == s2.key)
        let s3 = entry(3, .planning, 0, minutes: 30)
        var m3 = m
        m3[s3.key] = member("A", ordinal: 3, sort: 3)
        let row3 = try #require(SeriesListGrouping.rows([s3, s1, s2], membership: m3).first)
        #expect(row3.status == .current && row3.anchor == s2.key)
        let r1 = entry(1, .repeating, 12, minutes: 5), c2 = entry(2, .current, 5, minutes: 10)
        let rr = try #require(SeriesListGrouping.rows([c2, r1], membership: m).first)
        #expect(rr.anchor == c2.key)
        let r1late = entry(1, .repeating, 12, minutes: 15)
        let rl = try #require(SeriesListGrouping.rows([r1late, c2], membership: m).first)
        #expect(rl.anchor == r1late.key && rl.status == .repeating)
    }

    @Test func groupStatusFallsBackWithoutActiveMember() throws {
        func row(_ a: LibraryEntry, _ b: LibraryEntry) throws -> SeriesListRow {
            let m = [a.key: member("A", ordinal: 1, sort: 1), b.key: member("A", ordinal: 2, sort: 2)]
            return try #require(SeriesListGrouping.rows([a, b], membership: m).first)
        }
        let a = try row(entry(1, .planning, 0, minutes: 0), entry(2, .planning, 0, minutes: 10))
        #expect(a.status == .planning && a.anchor.id == 2 && a.advanceTarget == nil)
        let b = try row(entry(1, .completed, 12, minutes: 20), entry(2, .planning, 0, minutes: 10))
        #expect(b.status == .completed && b.anchor.id == 1)
        let c = try row(entry(1, .completed, 12, minutes: 0), entry(2, .planning, 0, minutes: 10))
        #expect(c.status == .planning && c.anchor.id == 2)
        let d1 = try row(entry(1, .paused, 3, minutes: 10), entry(2, .dropped, 3, minutes: 10))
        let d2 = try row(entry(1, .paused, 3, minutes: 10), entry(2, .dropped, 3, minutes: 10))
        #expect(d1.anchor == d2.anchor && d1.status == d2.status && d1.status == .dropped)
    }

    @Test @MainActor func advanceTargetsActiveMember() async throws {
        try await withHarness { h in
            h.signIn(Fixture.userA)
            let s1 = Fixture.entry(MediaKey(kind: .anime, id: 301), rowId: 1, status: .completed, progress: 12, updatedAt: Fixture.earlier)
            let s2 = Fixture.entry(MediaKey(kind: .anime, id: 302), rowId: 2, status: .current, progress: 5, updatedAt: Fixture.now)
            try await h.load([s1, s2])
            let m = [s1.key: member("C", ordinal: 1, sort: 1), s2.key: member("C", ordinal: 2, sort: 2)]
            let row = try #require(SeriesListGrouping.rows(h.store.allEntries, membership: m).first)
            let target = try #require(row.advanceTarget)
            #expect(target == s2.key)
            let pending = Task { await h.store.apply(LibraryEdit(progress: .set(6)), to: target) }
            let call = try await h.nextCall()
            #expect(call.request == .edit(LibraryEdit(progress: .set(6)), createIfMissing: nil, baseRevision: nil))
            call.answer(.write(LibraryWriteResult(entry: Fixture.entry(s2.key, rowId: 2, status: .current, progress: 6, updatedAt: Fixture.now), created: false)))
            _ = await pending.value
            #expect(h.store.entry(for: s2.key)?.progress == 6)
            #expect(h.store.entry(for: s1.key) == s1)
        }
    }

    @Test func groupingTwoThousandEntriesWithinBudget() {
        let statuses = ListStatus.allCases
        let entries = (1...2_000).map { entry($0, statuses[$0 % statuses.count], $0 % 20, minutes: $0) }
        var m: [MediaKey: SeriesMembership] = [:]
        for id in 1...1_200 {
            m[MediaKey(kind: .anime, id: id)] = member("S\((id - 1) / 3)", ordinal: (id - 1) % 3 + 1, sort: id)
        }
        _ = SeriesListGrouping.rows(entries, membership: m)
        let clock = ContinuousClock()
        var samples: [Duration] = []
        var rows: [SeriesListRow] = []
        for _ in 0..<7 { samples.append(clock.measure { rows = SeriesListGrouping.rows(entries, membership: m) }) }
        let median = samples.sorted()[3]
        #expect(rows.count == 800 + 400)
        if let path = ProcessInfo.processInfo.environment["KURO_W6_BASELINE_OUT"] {
            let ms = samples.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000 }
            let text = "samples_ms=\(ms.map { String(format: "%.3f", $0) }.joined(separator: ","))\n"
                + "median_ms=\(String(format: "%.3f", Double(median.components.attoseconds) / 1e15))\n"
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #if DEBUG
        #expect(median <= SeriesListGrouping.proposedBudget * 10, "debug guard; the gate runs -c release")
        #else
        #expect(median <= SeriesListGrouping.proposedBudget, "median \(median)")
        #endif
    }

    @Test func advanceTargetIsAlwaysTheAnchor() {
        let (entries, m) = library60()
        for row in SeriesListGrouping.rows(entries, membership: m) {
            #expect(row.advanceTarget == nil || row.advanceTarget == row.anchor)
            #expect(row.status == row.members.first { $0.key == row.anchor }?.status)
        }
    }

    @Test func groupingNeverChangesEntries() {
        let (entries, m) = library60()
        let before = entries
        let rows = SeriesListGrouping.rows(entries, membership: m)
        #expect(rows.count < entries.count)
        let flat = SeriesListGrouping.ungrouped(rows)
        #expect(Set(flat.map(\.key)) == Set(before.map(\.key)))
        #expect(flat.count == before.count)
        for original in before { #expect(flat.first { $0.key == original.key } == original) }
        #expect(SeriesListGrouping.rows(entries, membership: m, enabled: false).flatMap(\.members) == before)
        #expect(entries == before)
    }
}
