//
//  DSwidgetTests.swift
//  KuroTests
//
//  Widget UI lane (2026-11-03, item 9; spec §10, D13, D22). This is the spec's `WidgetContentTests`
//  suite (§19.3), filed under the lane's task name. Pure rules of the shared `KuroWidgetViews/`
//  content: row caps per family, the signed-out / empty / rows states, the queued caption, the
//  caught-up slot, an estimate never counting down, the eyebrow words, the small widget's unit split,
//  EN/DE copy and full-word VoiceOver labels. Plus source pins: the +1 is `Button(intent:)` only and
//  the shared content carries no `kuro://` literal.
//

import Foundation
import KuroCore
import KuroWidgetSupport
import Testing
import UIKit
import WidgetKit
@testable import Kuro

// MARK: - Fixtures

private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
/// Mon 3 Nov 2026, 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_793_707_200)

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? now
}

private func copy(_ german: Bool = false) -> ReleaseCopy {
    ReleaseCopy(now: now, german: german, locale: Locale(identifier: german ? "de_DE" : "en_GB"), timeZone: berlin)
}

private func scheduled(_ id: Int, kind: MediaKind = .anime, unit: Double = 8, at date: Date?, basis: ReleaseBasis,
                       precision: ReleasePrecision?, confidence: Double? = nil, source: String = "anilist",
                       title: String = "Frieren") -> ReleaseScheduleItem {
    ReleaseScheduleItem(medium: kind, mediaId: id, title: title, unitKind: kind == .anime ? .episode : .chapter,
                        unitNumber: unit, releaseAt: date, basis: basis, confidence: confidence, source: source,
                        precision: precision)
}

private func watching(_ id: Int, kind: MediaKind = .anime, title: String = "Frieren", progress: Int,
                      total: Int?, german: Bool = false) -> WidgetNowWatchingItem {
    WidgetNowWatchingItem(medium: kind, mediaId: id, title: title, progress: progress, total: total,
                          unitPrefix: WidgetSnapshotBuilder.unitPrefix(kind, german: german),
                          lifecycleId: "L\(id)", revision: 1, artworkURL: nil, thumbnail: nil,
                          deepLink: WidgetSnapshotBuilder.deepLink(MediaKey(kind: kind, id: id)))
}

private func snapshot(german: Bool = false, releases: [WidgetReleaseItem] = [],
                      nowWatching: [WidgetNowWatchingItem] = []) -> WidgetSnapshot {
    WidgetSnapshot(account: WidgetAccountHash(value: "a"), generatedAt: now, german: german,
                   releases: releases, nowWatching: nowWatching)
}

/// Eight confirmed instants on consecutive evenings (more than any family shows).
private func eightReleases(german: Bool = false) -> [WidgetReleaseItem] {
    (1...8).map { index in
        WidgetSnapshotBuilder.releaseItem(
            scheduled(index, unit: Double(index + 3), at: utc(2026, 11, 3 + index, 20, 30), basis: .confirmed,
                      precision: .instant, title: "Title \(index)"),
            copy: copy(german), metadata: nil, thumbnail: nil)
    }
}

// MARK: - Content rules

@MainActor
@Suite("Widget content (DSwidget): rows, states, keys and copy")
struct WidgetContentTests {
    @Test("row caps per family: Up next 1 / 3 / 6, Now watching 1 / 2 / 4")
    func rowCaps() {
        let snap = snapshot(releases: eightReleases(),
                            nowWatching: (1...6).map { watching($0, progress: 2, total: 12) })
        #expect(WidgetLayout.releases(snap, at: now, family: .systemSmall).count == 1)
        #expect(WidgetLayout.releases(snap, at: now, family: .systemMedium).count == 3)
        #expect(WidgetLayout.releases(snap, at: now, family: .systemLarge).count == 6)
        #expect(WidgetLayout.nowWatching(snap, family: .systemSmall).count == 1)
        #expect(WidgetLayout.nowWatching(snap, family: .systemMedium).count == 2)
        #expect(WidgetLayout.nowWatching(snap, family: .systemLarge).count == 4)
        // Soonest first, as the app wrote them.
        #expect(WidgetLayout.releases(snap, at: now, family: .systemMedium).map(\.mediaId) == [1, 2, 3])
    }

    @Test("states: no snapshot is signed out; a snapshot without rows is empty; passed releases drop out")
    func states() {
        #expect(WidgetLayout.releaseState(nil, at: now) == .signedOut)
        #expect(WidgetLayout.nowWatchingState(nil) == .signedOut)
        let empty = snapshot()
        #expect(WidgetLayout.releaseState(empty, at: now) == .empty)
        #expect(WidgetLayout.nowWatchingState(empty) == .empty)
        let snap = snapshot(releases: Array(eightReleases().prefix(1)))
        #expect(WidgetLayout.releaseState(snap, at: now) == .rows)
        // After the only release's instant the widget's own timeline entry shows "No dates yet."
        #expect(WidgetLayout.releaseState(snap, at: utc(2026, 11, 4, 21)) == .empty)
        #expect(WidgetLayout.releases(snap, at: utc(2026, 11, 4, 21), family: .systemLarge).isEmpty)
    }

    @Test("an estimate never counts down; a confirmed instant does; an announced day and a window never do")
    func countdownOnlyForAllowedTimes() {
        let confirmed = WidgetSnapshotBuilder.releaseItem(
            scheduled(1, at: utc(2026, 11, 7, 20, 30), basis: .confirmed, precision: .instant),
            copy: copy(), metadata: nil, thumbnail: nil)
        let announcedDay = WidgetSnapshotBuilder.releaseItem(
            scheduled(2, kind: .manga, unit: 68, at: utc(2026, 11, 12), basis: .announced, precision: .day,
                      source: "mangaupdates", title: "Kagurabachi"),
            copy: copy(), metadata: nil, thumbnail: nil)
        let estimate = WidgetSnapshotBuilder.releaseItem(
            scheduled(3, kind: .manga, unit: 1197, at: utc(2026, 11, 9), basis: .estimated, precision: .day,
                      confidence: 0.9, source: "kuro_estimate", title: "One Piece"),
            copy: copy(), metadata: nil, thumbnail: nil)
        let window = WidgetSnapshotBuilder.releaseItem(
            scheduled(4, kind: .manga, unit: 115, at: utc(2026, 12, 1), basis: .announced, precision: .month,
                      source: "publisher", title: "Vol"),
            copy: copy(), metadata: nil, thumbnail: nil)
        #expect(WidgetLayout.countdownTarget(confirmed) == utc(2026, 11, 7, 20, 30))
        #expect(WidgetLayout.countdownTarget(announcedDay) == nil)
        #expect(WidgetLayout.countdownTarget(estimate) == nil)
        #expect(WidgetLayout.countdownTarget(window) == nil)
        #expect(estimate.isEstimate)
        #expect(estimate.line.contains("expected"), "the estimate's words come from ReleaseCopy: \(estimate.line)")
        // Belt and braces: a row marked estimate never counts down even with a target in the file.
        var forged = estimate
        forged.countdownTarget = utc(2026, 11, 9, 12)
        #expect(WidgetLayout.countdownTarget(forged) == nil)
    }

    @Test("key phases: advance, queued (after a +1 the app has not saved) and caught up")
    func keyPhases() {
        let item = watching(1, progress: 6, total: 23)
        #expect(WidgetLayout.keyPhase(item) == .advance)
        #expect(WidgetLayout.nextUnit(item) == 7)

        let snap = snapshot(nowWatching: [item])
        let request = WidgetAdvanceRequest(id: UUID(), account: snap.account, medium: .anime, mediaId: 1,
                                           targetUnit: 7, lifecycleId: "L1", total: 23, createdAt: now)
        let shown = snap.applyingPending([request])
        let queued = shown.nowWatching.first
        #expect(queued?.progress == 7, "the count shows the new value at once")
        #expect(queued.map(WidgetLayout.keyPhase) == .queued)
        #expect(queued.map(WidgetLayout.nextUnit) == 8, "a further tap marks the unit after the queued one")
        #expect(queued.map { WidgetLayout.rowLabel($0, german: false) } == "Frieren, episode 7 of 23, Saved when Kuro opens")
        #expect(queued.map { WidgetLayout.rowLabel($0, german: true) }
                == "Frieren, Folge 7 von 23, Wird gespeichert, wenn Kuro öffnet")

        let caughtUp = watching(2, progress: 12, total: 12)
        #expect(WidgetLayout.keyPhase(caughtUp) == .caughtUp)
        #expect(WidgetLayout.rowLabel(caughtUp, german: false) == "Frieren, episode 12 of 12, Caught up")
        #expect(WidgetLayout.rowLabel(caughtUp, german: true) == "Frieren, Folge 12 von 12, Auf dem neuesten Stand")

        // Without a known total a title is never caught up.
        #expect(WidgetLayout.keyPhase(watching(3, kind: .manga, progress: 1197, total: nil)) == .advance)
    }

    @Test("VoiceOver uses full words, never Ep. / F. / Ch. / Kap.")
    func fullWordLabels() {
        let english = [watching(1, progress: 6, total: 23), watching(2, kind: .manga, progress: 68, total: nil)]
        let german = [watching(1, progress: 6, total: 23, german: true),
                      watching(2, kind: .manga, progress: 68, total: nil, german: true)]
        #expect(WidgetLayout.rowLabel(english[0], german: false) == "Frieren, episode 6 of 23")
        #expect(WidgetLayout.rowLabel(english[1], german: false) == "Frieren, chapter 68")
        #expect(WidgetLayout.rowLabel(german[0], german: true) == "Frieren, Folge 6 von 23")
        #expect(WidgetLayout.rowLabel(german[1], german: true) == "Frieren, Kapitel 68")
        for label in (english + german).flatMap({ [WidgetLayout.rowLabel($0, german: false),
                                                     WidgetLayout.rowLabel($0, german: true)] }) {
            for short in ["Ep.", "F.", "Ch.", "Kap."] {
                #expect(!label.contains(short), "\(label) contains \(short)")
            }
        }
        #expect(WidgetCopy.markLabel(.anime, next: 7, german: false) == "Mark episode 7 watched")
        #expect(WidgetCopy.markLabel(.anime, next: 7, german: true) == "Folge 7 als gesehen markieren")
        #expect(WidgetCopy.markLabel(.manga, next: 69, german: false) == "Mark chapter 69 read")
        #expect(WidgetCopy.markLabel(.manga, next: 69, german: true) == "Kapitel 69 als gelesen markieren")

        let release = WidgetSnapshotBuilder.releaseItem(
            scheduled(1, at: utc(2026, 11, 7, 20, 30), basis: .confirmed, precision: .instant),
            copy: copy(), metadata: nil, thumbnail: nil)
        let label = WidgetCopy.releaseRowLabel(title: release.title, accessibilityLine: release.accessibilityLine)
        #expect(label.hasPrefix("Frieren, "))
        #expect(!label.contains("Ep."), "the release row reads ReleaseCopy's spoken line: \(label)")
    }

    @Test("signed-out, empty and caption copy is the spec's EN/DE wording")
    func copyStrings() {
        #expect(WidgetCopy.signedOut(false) == "Open Kuro to see what's next.")
        #expect(WidgetCopy.signedOut(true) == "Öffne Kuro, um zu sehen, was als Nächstes kommt.")
        #expect(WidgetCopy.noDates(false) == "No dates yet.")
        #expect(WidgetCopy.noDates(true) == "Noch keine Termine.")
        #expect(WidgetCopy.nothingInProgress(false) == "Nothing in progress.")
        #expect(WidgetCopy.nothingInProgress(true) == "Gerade nichts angefangen.")
        #expect(WidgetCopy.savedWhenKuroOpens(false) == "Saved when Kuro opens")
        #expect(WidgetCopy.savedWhenKuroOpens(true) == "Wird gespeichert, wenn Kuro öffnet")
        #expect(WidgetCopy.estimate(false) == "Estimate")
        #expect(WidgetCopy.estimate(true) == "Schätzung")
        #expect(WidgetCopy.caughtUp(true) == "Auf dem neuesten Stand")
        #expect(WidgetCopy.nextEpisode(true) == "Nächste Folge")
        #expect(WidgetCopy.nextChapter(true) == "Nächstes Kapitel")
        // "NOW WATCHING" is Home's existing kicker, copied verbatim.
        #expect(WidgetCopy.nowWatching(false) == HomeOpeningLine.kicker(newAccount: false, medium: .anime, german: false))
        #expect(WidgetCopy.nowWatching(true) == HomeOpeningLine.kicker(newAccount: false, medium: .anime, german: true))
        #expect(WidgetCopy.nowReading(true) == HomeOpeningLine.kicker(newAccount: false, medium: .manga, german: true))
        // Every chrome string has its own German.
        let pairs: [(String, String)] = [
            (WidgetCopy.upNext(false), WidgetCopy.upNext(true)),
            (WidgetCopy.nextPrefix(false), WidgetCopy.nextPrefix(true)),
            (WidgetCopy.upNextDescription(false), WidgetCopy.upNextDescription(true)),
            (WidgetCopy.nowWatchingDescription(false), WidgetCopy.nowWatchingDescription(true)),
            (WidgetCopy.nextVolume(false), WidgetCopy.nextVolume(true)),
        ]
        for (en, de) in pairs { #expect(en != de, "\(en) has no German") }
    }

    @Test("the language follows the snapshot; without one, the device's first language")
    func language() {
        #expect(WidgetLayout.german(snapshot(german: true), preferred: false))
        #expect(!WidgetLayout.german(snapshot(german: false), preferred: true))
        #expect(WidgetLayout.german(nil, preferred: true))
        #expect(WidgetCopy.preferredGerman(["de-DE", "en-GB"]))
        #expect(WidgetCopy.preferredGerman(["de"]))
        #expect(!WidgetCopy.preferredGerman(["en-GB", "de-DE"]))
        #expect(!WidgetCopy.preferredGerman([]))
        // The system countdown speaks ReleaseCopy's locales.
        #expect(WidgetLayout.locale(german: true).identifier == "de_DE")
        #expect(WidgetLayout.locale(german: false).identifier == "en_GB")
    }

    @Test("eyebrows: one kind names it, mixed kinds say Up next, all-manga Now watching says Now reading")
    func eyebrows() {
        let anime = WidgetSnapshotBuilder.releaseItem(
            scheduled(1, at: utc(2026, 11, 7, 20, 30), basis: .confirmed, precision: .instant),
            copy: copy(), metadata: nil, thumbnail: nil)
        let manga = WidgetSnapshotBuilder.releaseItem(
            scheduled(2, kind: .manga, unit: 68, at: utc(2026, 11, 12), basis: .announced, precision: .day),
            copy: copy(), metadata: nil, thumbnail: nil)
        var volume = manga
        volume.unitLabel = "Vol. 115"
        #expect(WidgetLayout.releaseEyebrow([anime], german: false) == "Next episode")
        #expect(WidgetLayout.releaseEyebrow([manga], german: true) == "Nächstes Kapitel")
        #expect(WidgetLayout.releaseEyebrow([volume], german: false) == "Next volume")
        #expect(WidgetLayout.releaseEyebrow([anime, manga], german: false) == "Up next")
        #expect(WidgetLayout.releaseEyebrow([], german: true) == "Als Nächstes")
        #expect(WidgetLayout.nowWatchingEyebrow([watching(1, kind: .manga, progress: 1, total: nil)], german: false)
                == "Now reading")
        #expect(WidgetLayout.nowWatchingEyebrow([watching(1, progress: 1, total: nil),
                                                 watching(2, kind: .manga, progress: 1, total: nil)], german: false)
                == "Now watching")
    }

    @Test("small widget readout: the unit label splits into a word and a number")
    func unitParts() {
        #expect(WidgetLayout.unitParts("Ep. 8") == ("Ep.", "8"))
        #expect(WidgetLayout.unitParts("Kap. 1197") == ("Kap.", "1197"))
        #expect(WidgetLayout.unitParts("F. 12.5") == ("F.", "12.5"))
        #expect(WidgetLayout.unitParts("Staffel 2") == ("Staffel", "2"))
        #expect(WidgetLayout.unitParts("Next episode") == ("Next episode", nil))
        #expect(WidgetLayout.unitParts("Nächste Folge") == ("Nächste Folge", nil))
        #expect(WidgetLayout.unitParts("12") == ("", "12"))
        #expect(WidgetLayout.unitPrefix(watching(1, progress: 1, total: nil, german: true)) == "F.")
    }

    @Test("a Now watching row borrows its title's next release line from the snapshot")
    func nextReleaseLine() {
        let release = WidgetSnapshotBuilder.releaseItem(
            scheduled(1, at: utc(2026, 11, 7, 20, 30), basis: .confirmed, precision: .instant),
            copy: copy(), metadata: nil, thumbnail: nil)
        let snap = snapshot(releases: [release], nowWatching: [watching(1, progress: 7, total: 28),
                                                               watching(2, progress: 1, total: nil)])
        #expect(WidgetLayout.nextReleaseLine(for: snap.nowWatching[0], in: snap, at: now, german: false)
                == "Next · \(release.line)")
        #expect(WidgetLayout.nextReleaseLine(for: snap.nowWatching[1], in: snap, at: now, german: false) == nil)
        // A passed release no longer lends its line.
        #expect(WidgetLayout.nextReleaseLine(for: snap.nowWatching[0], in: snap, at: utc(2026, 11, 8), german: false) == nil)
        let germanSnap = snapshot(german: true, releases: [release], nowWatching: snap.nowWatching)
        #expect(WidgetLayout.nextReleaseLine(for: germanSnap.nowWatching[0], in: germanSnap, at: now, german: true)?
            .hasPrefix("Als Nächstes · ") == true)
    }

    @Test("thumbnails are read from the cache only and a name cannot leave thumbs/")
    func thumbnails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuro-dswidget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let pixel = try #require(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 6)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
        }.jpegData(compressionQuality: 0.8))
        #expect(store.writeThumbnail(pixel, named: "anime-1-abc.jpg"))
        let source = WidgetThumbnailSource.directory(directory)
        #expect(source.image(named: "anime-1-abc.jpg") != nil)
        #expect(source.image(named: "../snapshot.json") == nil)
        #expect(source.image(named: nil) == nil)
        #expect(source.image(named: "missing.jpg") == nil)
        #expect(WidgetThumbnailSource.none.image(named: "anime-1-abc.jpg") == nil)
    }

    @Test("source pins: the +1 is Button(intent:) only; the widget content links no kuro:// literal and fetches nothing")
    func sourcePins() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let wrapper = try String(contentsOf: repo.appendingPathComponent("KuroWidgets/KuroWidgetViews.swift"), encoding: .utf8)
        #expect(wrapper.contains("Button(intent: AdvanceProgressIntent(item: item))"))
        #expect(!wrapper.contains("Link("), "the extension wrapper adds no link of its own")
        let folder = repo.appendingPathComponent("KuroWidgetViews")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 7)
        for file in files {
            // Code only: comments may name what the file must not do.
            let text = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            #expect(!text.contains("kuro://"), "\(file) must not build a kuro:// URL (links come from the snapshot)")
            #expect(!text.contains("URLSession"), "\(file) must not fetch")
            #expect(!text.contains("AsyncImage"), "\(file) must not fetch")
            #expect(!text.contains("ProgressView("), "\(file): branded states only")
            #expect(!text.contains("KuroLocale"), "\(file) cannot link the app's KuroLocale")
        }
    }
}
