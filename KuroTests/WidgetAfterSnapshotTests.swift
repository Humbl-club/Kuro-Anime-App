import Foundation
import KuroCore
import KuroWidgetSupport
import SwiftUI
import Testing
import UIKit
import WidgetKit
@testable import Kuro

/// "After" fixture renders of the Home Screen widgets (spec §10, §19.3; widget UI lane). The content
/// views live in `KuroWidgetViews/`, compiled into the app too (D22), so they render here exactly as
/// the extension draws them, inside a mimicked system container (#FFFEF8, radius 22, 16 pt content
/// margins) on a quiet wallpaper. No network: covers come from a temporary `thumbs/` folder seeded
/// from `tools/design-directions/assets/`; snapshots are built with the app's own
/// `WidgetSnapshotBuilder` and `ReleaseCopy`, so every line is the shipped wording.
///
/// JPEGs (quality 80, ≤ 603 px wide) go to `docs/details-songs-2026-11-03/after/widget-*.jpg` only with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; run it with `-only-testing:KuroTests/WidgetAfterSnapshotTests`.
/// Ordinary runs render into a temporary folder.
@Suite("Widget after renders", .serialized, .timeLimit(.minutes(5)))
@MainActor
struct WidgetAfterSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-ds-widget-after", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/details-songs-2026-11-03/after")
    }()

    /// 1.6 device pixels a point keeps the 370 pt large card at 592 px (≤ 603).
    private static let renderScale: CGFloat = 1.6

    private enum Size {
        static let small = CGSize(width: 158, height: 158)
        static let medium = CGSize(width: 338, height: 158)
        static let large = CGSize(width: 338, height: 354)
    }

    // MARK: Up next

    @Test("Up next: small, medium, large in EN and DE; estimate; no dates; signed out; placeholder")
    func upNext() async throws {
        let thumbs = try Self.seedThumbnails()
        defer { try? FileManager.default.removeItem(at: thumbs) }
        let base = Date()
        for german in [false, true] {
            let lang = german ? "de" : "en"
            let snap = Self.snapshot(german: german, base: base)
            for (family, size, name) in [(WidgetFamily.systemSmall, Size.small, "small"),
                                         (.systemMedium, Size.medium, "medium"),
                                         (.systemLarge, Size.large, "large")] {
                await render(NextReleaseWidgetContent(snapshot: snap, date: base, family: family),
                             size: size, thumbs: thumbs, name: "widget-next-\(name)-\(lang)")
            }
            let estimateOnly = Self.snapshot(german: german, base: base, releases: [Self.estimateRow(german: german, base: base)])
            await render(NextReleaseWidgetContent(snapshot: estimateOnly, date: base, family: .systemSmall),
                         size: Size.small, thumbs: thumbs, name: "widget-next-small-estimate-\(lang)")
            let dayOnly = Self.snapshot(german: german, base: base, releases: [Self.announcedDayRow(german: german, base: base)])
            await render(NextReleaseWidgetContent(snapshot: dayOnly, date: base, family: .systemSmall),
                         size: Size.small, thumbs: thumbs, name: "widget-next-small-day-\(lang)")
            let empty = Self.snapshot(german: german, base: base, releases: [], watching: [])
            await render(NextReleaseWidgetContent(snapshot: empty, date: base, family: .systemSmall),
                         size: Size.small, thumbs: thumbs, name: "widget-next-empty-small-\(lang)")
            await render(NextReleaseWidgetContent(snapshot: nil, date: base, family: .systemMedium, german: german),
                         size: Size.medium, thumbs: thumbs, name: "widget-next-signedout-medium-\(lang)")
        }
        await render(NextReleaseWidgetContent(snapshot: nil, date: base, family: .systemMedium).redacted(reason: .placeholder),
                     size: Size.medium, thumbs: thumbs, name: "widget-next-placeholder-medium")
    }

    // MARK: Now watching

    @Test("Now watching: small, medium, large in EN and DE; queued, caught up; nothing in progress; signed out; placeholder")
    func nowWatching() async throws {
        let thumbs = try Self.seedThumbnails()
        defer { try? FileManager.default.removeItem(at: thumbs) }
        let base = Date()
        for german in [false, true] {
            let lang = german ? "de" : "en"
            let snap = Self.queued(Self.snapshot(german: german, base: base))
            for (family, size, name) in [(WidgetFamily.systemSmall, Size.small, "small"),
                                         (.systemMedium, Size.medium, "medium"),
                                         (.systemLarge, Size.large, "large")] {
                await render(NowWatchingWidgetContent(snapshot: snap, date: base, family: family) { WidgetKeyFace(item: $0) },
                             size: size, thumbs: thumbs, name: "widget-now-\(name)-\(lang)")
            }
            // The small widget on a title that is not queued, and on a caught-up title.
            let plain = Self.snapshot(german: german, base: base, watching: Array(Self.watchingRows(german: german).dropFirst()))
            await render(NowWatchingWidgetContent(snapshot: plain, date: base, family: .systemSmall) { WidgetKeyFace(item: $0) },
                         size: Size.small, thumbs: thumbs, name: "widget-now-small-advance-\(lang)")
            let caught = Self.snapshot(german: german, base: base,
                                       watching: Self.watchingRows(german: german).filter(\.isCaughtUp))
            await render(NowWatchingWidgetContent(snapshot: caught, date: base, family: .systemSmall) { WidgetKeyFace(item: $0) },
                         size: Size.small, thumbs: thumbs, name: "widget-now-small-caughtup-\(lang)")
            let empty = Self.snapshot(german: german, base: base, watching: [])
            await render(NowWatchingWidgetContent(snapshot: empty, date: base, family: .systemMedium) { WidgetKeyFace(item: $0) },
                         size: Size.medium, thumbs: thumbs, name: "widget-now-empty-medium-\(lang)")
            await render(NowWatchingWidgetContent(snapshot: nil, date: base, family: .systemSmall, german: german) {
                WidgetKeyFace(item: $0)
            }, size: Size.small, thumbs: thumbs, name: "widget-now-signedout-small-\(lang)")
        }
        await render(NowWatchingWidgetContent(snapshot: nil, date: base, family: .systemMedium) { WidgetKeyFace(item: $0) }
            .redacted(reason: .placeholder), size: Size.medium, thumbs: thumbs, name: "widget-now-placeholder-medium")
    }

    // MARK: Fixtures

    private static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private static func copy(german: Bool, base: Date) -> ReleaseCopy {
        ReleaseCopy(now: base, german: german, locale: Locale(identifier: german ? "de_DE" : "en_GB"), timeZone: berlin)
    }

    private static func item(_ id: Int, kind: MediaKind, unit: Double, at date: Date?, basis: ReleaseBasis,
                             precision: ReleasePrecision?, confidence: Double? = nil, source: String,
                             title: String) -> ReleaseScheduleItem {
        ReleaseScheduleItem(medium: kind, mediaId: id, title: title, unitKind: kind == .anime ? .episode : .chapter,
                            unitNumber: unit, releaseAt: date, basis: basis, confidence: confidence, source: source,
                            precision: precision)
    }

    /// `days` after `base`'s Berlin day at `hour`:`minute` Berlin time (a confirmed / announced instant).
    private static func evening(_ days: Int, _ hour: Int, _ minute: Int, from base: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let start = calendar.startOfDay(for: base)
        let day = calendar.date(byAdding: .day, value: days, to: start) ?? base
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// The day `days` from `base`, at noon UTC (a day-precision row).
    private static func day(_ days: Int, from base: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let start = calendar.startOfDay(for: base)
        return calendar.date(byAdding: .day, value: days, to: start) ?? base
    }

    private static func schedule(base: Date) -> [ReleaseScheduleItem] {
        [
            item(101, kind: .anime, unit: 8, at: evening(2, 21, 30, from: base), basis: .confirmed,
                 precision: .instant, source: "anilist", title: "Frieren: Beyond Journey's End"),
            item(102, kind: .anime, unit: 30, at: evening(1, 17, 0, from: base), basis: .confirmed,
                 precision: .instant, source: "anilist", title: "The Apothecary Diaries"),
            item(201, kind: .manga, unit: 68, at: day(4, from: base), basis: .announced, precision: .day,
                 source: "mangaupdates", title: "Kagurabachi"),
            item(202, kind: .manga, unit: 1197, at: day(6, from: base), basis: .estimated, precision: .day,
                 confidence: 0.9, source: "kuro_estimate", title: "One Piece"),
            item(103, kind: .anime, unit: 9, at: evening(5, 23, 0, from: base), basis: .announced,
                 precision: .instant, source: "anilist", title: "Mushishi"),
            item(203, kind: .manga, unit: 20, at: day(28, from: base), basis: .announced, precision: .month,
                 source: "publisher", title: "Chainsaw Man"),
        ].sorted { ($0.releaseAt ?? .distantFuture) < ($1.releaseAt ?? .distantFuture) }
    }

    private static let thumbnailNames: [MediaKey: String] = [
        MediaKey(kind: .anime, id: 101): "anime-101-a.jpg", MediaKey(kind: .anime, id: 102): "anime-102-a.jpg",
        MediaKey(kind: .manga, id: 201): "manga-201-a.jpg", MediaKey(kind: .manga, id: 202): "manga-202-a.jpg",
        // Mushishi and Chainsaw Man have no cached cover: the branded tile shows.
        MediaKey(kind: .anime, id: 104): "anime-104-a.jpg", MediaKey(kind: .manga, id: 204): "manga-204-a.jpg",
    ]

    private static func watchingRows(german: Bool) -> [WidgetNowWatchingItem] {
        func row(_ key: MediaKey, title: String, progress: Int, total: Int?) -> WidgetNowWatchingItem {
            WidgetNowWatchingItem(medium: key.kind, mediaId: key.id, title: title, progress: progress, total: total,
                                  unitPrefix: WidgetSnapshotBuilder.unitPrefix(key.kind, german: german),
                                  lifecycleId: "L\(key.id)", revision: 3, artworkURL: nil,
                                  thumbnail: thumbnailNames[key], deepLink: WidgetSnapshotBuilder.deepLink(key))
        }
        return [
            row(MediaKey(kind: .anime, id: 101), title: "Frieren: Beyond Journey's End", progress: 6, total: 28),
            row(MediaKey(kind: .anime, id: 102), title: "The Apothecary Diaries", progress: 29, total: 48),
            row(MediaKey(kind: .anime, id: 104), title: "Dandadan", progress: 12, total: 12),
            row(MediaKey(kind: .manga, id: 202), title: "One Piece", progress: 1196, total: nil),
            row(MediaKey(kind: .manga, id: 204), title: "Vinland Saga", progress: 210, total: 220),
        ]
    }

    private static func snapshot(german: Bool, base: Date, releases: [WidgetReleaseItem]? = nil,
                                 watching: [WidgetNowWatchingItem]? = nil) -> WidgetSnapshot {
        let copy = copy(german: german, base: base)
        let rows = releases ?? schedule(base: base).filter { copy.isAhead($0) }.map {
            WidgetSnapshotBuilder.releaseItem($0, copy: copy, metadata: nil, thumbnail: thumbnailNames[$0.key])
        }
        return WidgetSnapshot(account: WidgetAccountHash(value: "fixture"), generatedAt: base, german: german,
                              releases: rows, nowWatching: watching ?? watchingRows(german: german))
    }

    private static func estimateRow(german: Bool, base: Date) -> WidgetReleaseItem {
        WidgetSnapshotBuilder.releaseItem(
            item(202, kind: .manga, unit: 1197, at: day(6, from: base), basis: .estimated, precision: .day,
                 confidence: 0.9, source: "kuro_estimate", title: "One Piece"),
            copy: copy(german: german, base: base), metadata: nil, thumbnail: thumbnailNames[MediaKey(kind: .manga, id: 202)])
    }

    private static func announcedDayRow(german: Bool, base: Date) -> WidgetReleaseItem {
        WidgetSnapshotBuilder.releaseItem(
            item(201, kind: .manga, unit: 68, at: day(4, from: base), basis: .announced, precision: .day,
                 source: "mangaupdates", title: "Kagurabachi"),
            copy: copy(german: german, base: base), metadata: nil, thumbnail: thumbnailNames[MediaKey(kind: .manga, id: 201)])
    }

    /// The first Now watching title with one +1 queued by the widget (the provider's overlay).
    private static func queued(_ snapshot: WidgetSnapshot) -> WidgetSnapshot {
        guard let first = snapshot.nowWatching.first,
              let request = first.advanceRequest(account: snapshot.account, now: snapshot.generatedAt) else { return snapshot }
        return snapshot.applyingPending([request])
    }

    /// A `thumbs/` folder with fixture covers (two titles are left without one on purpose).
    private static func seedThumbnails() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuro-ds-widget-thumbs-\(UUID().uuidString)", isDirectory: true)
        let store = WidgetSnapshotStore(directory: directory)
        try FileManager.default.createDirectory(at: store.thumbnailDirectory, withIntermediateDirectories: true)
        let sources = ["anime-101-a.jpg": "anime2.jpg", "anime-102-a.jpg": "anime1.jpg",
                       "manga-201-a.jpg": "manga1.jpg", "manga-202-a.jpg": "manga0.jpg"]
        for (name, file) in sources {
            let from = repo.appendingPathComponent("tools/design-directions/assets/\(file)")
            try FileManager.default.copyItem(at: from, to: store.thumbnailDirectory.appendingPathComponent(name))
        }
        return directory
    }

    // MARK: Rendering

    /// The widget card as the Home Screen shows it: the system container (canvas fill, radius 22,
    /// 16 pt content margins) on a 16 pt wallpaper border.
    private func render<V: View>(_ content: V, size: CGSize, thumbs: URL, name: String) async {
        let card = content
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetPalette.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 9, x: 0, y: 6)
            .padding(16)
            .background(LinearGradient(colors: [WidgetPalette.rgb(0x7D8A83), WidgetPalette.rgb(0x3D4741)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.widgetThumbnails, .directory(thumbs))
            .environment(\.colorScheme, .light)
        let outer = CGSize(width: size.width + 32, height: size.height + 32)
        let host = UIHostingController(rootView: card.frame(width: outer.width, height: outer.height))
        host.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: outer)
        window.rootViewController = host
        window.isHidden = false
        host.view.bounds = CGRect(origin: .zero, size: outer)
        host.view.backgroundColor = .white
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(350))
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.renderScale
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: outer, format: format).image { context in
            if !window.drawHierarchy(in: CGRect(origin: .zero, size: outer), afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
        #expect(image.size.width * image.scale <= 603, "\(name) is wider than 603 px")
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            Issue.record("\(name): JPEG encoding failed")
            return
        }
        do {
            try data.write(to: Self.outDir.appendingPathComponent("\(name).jpg"))
        } catch {
            Issue.record("\(name): write failed (\(error))")
        }
    }
}
