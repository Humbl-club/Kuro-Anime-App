import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// Fixture renders for the final "map of every screen" (docs/overnight-2026-11-01/screenshots/final).
/// No network: every graph uses a nil client, a fake Library backend or an in-process stub endpoint.
/// Evidence only: setup problems are written to `fixture/NOTES.txt` instead of failing the run, and
/// the only expectations are that each written PNG exists.
@Suite("Screen map snapshots", .serialized, .timeLimit(.minutes(3)))
@MainActor
struct ScreenMapSnapshotTests {
    /// Committed evidence is rewritten only on purpose: run with `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`
    /// (xcodebuild passes it to the test host as `KURO_WRITE_SNAPSHOTS`). Ordinary runs render into a
    /// temporary folder so the working tree stays clean.
    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-screen-map", isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/overnight-2026-11-01/screenshots/final/fixture")
    }()

    private static let repo: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // MARK: Folio lists

    @Test("Folio lists: Index and Shelf, anime and manga, at 320/390/430")
    func folioLists() async throws {
        await Self.seedArtwork()
        let animeItems = Self.folioItems(.anime)
        let mangaItems = Self.folioItems(.manga)
        for width: CGFloat in [320, 390, 430] {
            for density in FolioDensity.allCases {
                await render(Self.folioPage(items: animeItems, medium: .anime, density: density, width: width),
                             width: width, name: "folio-anime-\(density.rawValue)-\(Int(width)).png", settle: 1_200)
                await render(Self.folioPage(items: mangaItems, medium: .manga, density: density, width: width),
                             width: width, name: "folio-manga-\(density.rawValue)-\(Int(width)).png", settle: 1_200)
            }
        }
        note("Folio: composed from the Folio components (KuroMediumSwitch, FolioStatusStrip, FolioControlsRow, FolioShelf/FolioIndex) with fixture Media + LibraryEntry rows; the full EditorialCollectionView needs the network feed RPC and writes density to the app's @AppStorage, so it was not hosted.")
    }

    // MARK: Profile

    @Test("Profile with a seeded Library, and ProfileListsPreview, at 390")
    func profile() async throws {
        await Self.seedArtwork()
        guard let defaults = Self.defaults("screenmap-profile") else { note("Profile: no UserDefaults suite; skipped"); return }
        let backend = FakeLibraryBackend()
        let entries = Self.libraryEntries()
        backend.setRows(entries, for: LifecycleFixtures.userA)
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter(),
                                                libraryBackend: backend)
        _ = await graph.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        try? await graph.library.refresh()
        if graph.library.loadState != .loaded { note("Profile: Library did not reach .loaded (\(graph.library.loadState))") }
        // Covers for the list rows (the preview read is a network RPC; mark it fresh so it is not re-read).
        let previews = Self.previews()
        graph.collection.listPreview = previews
        graph.collection.listPreviewFailed = false
        graph.collection.listPreviewLoadedAt = Date()

        await render(
            ProfileView()
                .environment(graph.library)
                .environment(graph.identity)
                .environment(graph.auth)
                .environment(graph.session)
                .environment(graph.collection)
                .environment(graph.releases)
                .environment(graph.availability)
                .environment(graph.clubs)
                .environment(graph.imports)
                .environment(graph.flags)
                .environment(graph.artworkMaterials),
            width: 390, height: 1900, name: "profile-seeded-390.png", settle: 1_200
        )

        await render(
            ScrollView {
                ProfileListsPreview(entries: entries, previews: previews, previewFailed: false,
                                    onOpen: { _ in }, onOpenCollection: {})
                    .padding(.horizontal, KuroDesignSpacing.padding)
            }
            .background(Color.kuroCanvasPage),
            width: 390, height: 900, name: "profile-lists-preview-390.png", settle: 1_200
        )
        await render(
            ScrollView {
                ProfileListsPreview(entries: entries, previews: [:], previewFailed: true,
                                    onOpen: { _ in }, onOpenCollection: {})
                    .padding(.horizontal, KuroDesignSpacing.padding)
            }
            .background(Color.kuroCanvasPage),
            width: 390, height: 700, name: "profile-lists-preview-failed-390.png"
        )
        await graph.session.endSession()
        defaults.removePersistentDomain(forName: "screenmap-profile")
    }

    // MARK: About, onboarding, auth

    @Test("Data sources, onboarding and auth")
    func aboutOnboardingAuth() async throws {
        await render(DataSourcesView().background(Color.kuroCanvasPage), width: 390, height: 1500,
                     name: "data-sources-390.png")

        guard let defaults = Self.defaults("screenmap-auth") else { note("Auth: no UserDefaults suite; skipped"); return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())

        await render(
            OnboardingView(onComplete: { _ in })
                .environment(graph.identity)
                .environment(graph.home)
                .environment(graph.flags),
            width: 390, height: 844, name: "onboarding-frame1-390.png", settle: 800
        )
        // Frames 2-3: Continue persists the medium. With no signed-in user and the series flag off it writes
        // only `kuro.folio.medium` to UserDefaults.standard (the app container), so the prior value is
        // restored afterwards. "Not now" writes nothing.
        let folioKey = "kuro.folio.medium"
        let priorMedium = UserDefaults.standard.object(forKey: folioKey)
        defer {
            if let priorMedium { UserDefaults.standard.set(priorMedium, forKey: folioKey) }
            else { UserDefaults.standard.removeObject(forKey: folioKey) }
        }
        let onboarding = OnboardingView(onComplete: { _ in })
            .environment(graph.identity)
            .environment(graph.home)
            .environment(graph.flags)
        let frame2 = await render(onboarding, width: 390, height: 844, name: "onboarding-frame2-390.png", settle: 900,
                                  prepare: { view in Self.activate(label: KuroLocale.text("Continue", "Weiter"), in: view) })
        let frame3 = await render(onboarding, width: 390, height: 844, name: "onboarding-frame3-390.png", settle: 900,
                                  prepare: { view in
                                      Self.activate(label: KuroLocale.text("Continue", "Weiter"), in: view)
                                  },
                                  then: { view in Self.activate(label: KuroLocale.text("Not now", "Später"), in: view) })
        if frame2 != true || frame3 != true {
            note("Onboarding: frames 2-3 could not be reached through accessibility activation (Continue / Not now); those PNGs may show an earlier frame.")
        }

        func auth() -> some View {
            AuthView()
                .environment(graph.identity)
                .environment(graph.session)
                .environment(graph.discovery)
        }
        for width: CGFloat in [390, 320] {
            await render(auth(), width: width, height: width == 320 ? 568 : 844,
                         name: "auth-welcome-\(Int(width)).png", settle: 800)

            // Sign-in form: a published neutral notice opens the form in Sign in mode (AuthView.takeAuthNotice).
            graph.identity.authNoticeMessage = KuroLocale.text("Check your email, then sign in.", "Prüfe deine E-Mails und melde dich dann an.")
            await render(auth(), width: width, height: width == 320 ? 568 : 844,
                         name: "auth-signin-\(Int(width)).png", settle: 1_600)

            // Sign-up form: "Get started" on the welcome, activated through accessibility (no persistence).
            let activated = await render(auth(), width: width, height: width == 320 ? 568 : 844,
                                         name: "auth-signup-\(Int(width)).png", settle: 1_600,
                                         prepare: { view in Self.activate(label: KuroLocale.text("Get started", "Los geht’s"), in: view) })
            if activated == false {
                note("Auth sign-up \(Int(width)): 'Get started' could not be activated through accessibility; the PNG shows the welcome instead (the form is only reachable via the DEBUG -AuthShowEmail launch argument).")
            }

            await render(
                AuthSetPasswordView()
                    .environment(graph.session)
                    .environment(graph.identity),
                width: width, height: width == 320 ? 568 : 844, name: "auth-set-password-\(Int(width)).png", settle: 800
            )
        }
        note("German: KuroLocale reads Locale.preferredLanguages and has no override hook; German variants of Profile and Auth sign-in were skipped (writing AppleLanguages would change the real app's preferences).")
        defaults.removePersistentDomain(forName: "screenmap-auth")
    }

    // MARK: Search, clubs

    @Test("Search idle and Clubs empty / failed at 390")
    func searchAndClubs() async throws {
        guard let defaults = Self.defaults("screenmap-search") else { note("Search: no UserDefaults suite; skipped"); return }
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        await render(
            EditorialSearchView()
                .environment(graph.banner)
                .environment(graph.search)
                .environment(graph.discovery)
                .environment(NetworkMonitor())
                .environment(graph.flags)
                .environment(graph.library)
                .environment(graph.libraryActions)
                .environment(graph.clubs)
                .environment(\.kuroRoutes, KuroRoutes.unhandled),
            width: 390, height: 844, name: "search-idle-390.png", settle: 1_000
        )

        // Signed out with no read yet: the list stays in its first-load skeleton (the view's load needs an account).
        await render(
            ClubsView()
                .environment(graph.clubs)
                .environment(NetworkMonitor()),
            width: 390, height: 844, name: "clubs-loading-390.png", settle: 1_200
        )
        // Failed: a nil client makes the clubs read fail (not a connectivity failure).
        await graph.clubs.fetchMyClubs()
        await render(
            ClubsView()
                .environment(graph.clubs)
                .environment(NetworkMonitor()),
            width: 390, height: 844, name: "clubs-failed-390.png", settle: 1_200
        )
        defaults.removePersistentDomain(forName: "screenmap-search")

        // Empty: an in-process stub endpoint answers every read with [].
        do {
            let harness = try ClubsHarness { _ in .emptyArray }
            _ = await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
            await harness.clubs.fetchMyClubs()
            await render(
                ClubsView()
                    .environment(harness.clubs)
                    .environment(NetworkMonitor()),
                width: 390, height: 844, name: "clubs-empty-390.png", settle: 1_200
            )
            await harness.tearDown()
        } catch {
            note("Clubs empty: stub harness could not be built (\(error)); skipped")
        }
    }

    // MARK: Shared states

    @Test("State views, theme songs and release lines on one sheet at 390")
    func sharedStates() async throws {
        let now = Date(timeIntervalSince1970: 1_791_979_200) // Wed 14 Oct 2026, 12:00 UTC
        func release(_ id: Int, unit: ReleaseUnitKind, number: Double, at: Date, basis: ReleaseBasis,
                     precision: ReleasePrecision?, confidence: Double? = nil, medium: MediaKind = .anime) -> ReleaseScheduleItem {
            ReleaseScheduleItem(medium: medium, mediaId: id, title: "T\(id)", unitKind: unit, unitNumber: number,
                                releaseAt: at, basis: basis, confidence: confidence, source: "anilist", precision: precision)
        }
        let releases = [
            release(1, unit: .episode, number: 7, at: now.addingTimeInterval(26 * 3600), basis: .confirmed, precision: .instant),
            release(2, unit: .volume, number: 115, at: Date(timeIntervalSince1970: 1_793_491_200), basis: .announced,
                    precision: .month, medium: .manga),
            release(3, unit: .chapter, number: 1197, at: now.addingTimeInterval(4 * 86_400), basis: .estimated,
                    precision: .day, confidence: 0.82, medium: .manga)
        ]
        let songs = [
            ThemeSong(kind: .opening, sequence: 1, title: "Kaikai Kitan", artist: "Eve", episodes: "1–13"),
            ThemeSong(kind: .ending, sequence: 1, title: "Lost in Paradise", artist: "ALI feat. AKLO", episodes: "1–13"),
            ThemeSong(kind: .opening, sequence: 2, title: "Hidden spoiler title", artist: "Artist", episodes: "14–24", isSpoiler: true)
        ]
        // Two sheets: one very tall bitmap exceeds the renderer's texture limit and draws black.
        let pages = VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Self.label("KuroStateView: page layout")
            ForEach(Array(Self.stateKinds.enumerated()), id: \.offset) { _, kind in
                KuroStateView(kind, retry: kind == .failed(hasCachedContent: false) ? {} : nil)
                    .frame(height: 176)
                    .overlay(Rectangle().stroke(Color.kuroHairline, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .padding(.vertical, KuroDesignSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.kuroCanvasPage)
        await render(pages, width: 390, height: 1_500, name: "shared-states-page-390.png")

        let sheet = ScrollView {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                Self.label("KuroStateView: inline layout")
                ForEach(Array(Self.stateKinds.enumerated()), id: \.offset) { _, kind in
                    KuroStateView(kind, layout: .inline, retry: kind == .failed(hasCachedContent: true) ? {} : nil)
                    Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                }
                Self.label("KuroThemeSongRow")
                ForEach(songs) { song in
                    KuroThemeSongRow(song)
                    Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                }
                Self.label("KuroReleaseLine: confirmed / announced / estimated")
                ForEach(releases) { item in
                    KuroReleaseLine(item, showsSource: true, now: now)
                    Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                }
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.vertical, KuroDesignSpacing.lg)
        }
        .background(Color.kuroCanvasPage)
        await render(sheet, width: 390, height: 1_500, name: "shared-states-inline-songs-releases-390.png")
    }

    // MARK: Rendering

    @discardableResult
    private func render<V: View>(_ view: V, width: CGFloat, height preferredHeight: CGFloat? = nil, name: String,
                                 settle: Int = 500, prepare: ((UIView) -> Bool)? = nil,
                                 then: ((UIView) -> Bool)? = nil) async -> Bool? {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            note("\(name): could not create the output folder (\(error))")
            return nil
        }
        let height = preferredHeight ?? width * 2.2
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = .white
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        var prepared: Bool?
        if let prepare {
            try? await Task.sleep(for: .milliseconds(400))
            host.view.layoutIfNeeded()
            prepared = prepare(host.view)
            if let then, prepared == true {
                try? await Task.sleep(for: .milliseconds(700))
                host.view.layoutIfNeeded()
                prepared = then(host.view)
            }
        }
        try? await Task.sleep(for: .milliseconds(settle))
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let url = Self.outDir.appendingPathComponent(name)
        guard let data = image.pngData() else {
            note("\(name): PNG encoding failed")
            return prepared
        }
        do {
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        } catch {
            note("\(name): write failed (\(error))")
        }
        return prepared
    }

    /// Finds the first accessibility element with `label` under `root` and activates it.
    private static func activate(label: String, in root: UIView) -> Bool {
        func find(_ element: NSObject, depth: Int) -> NSObject? {
            guard depth < 60 else { return nil }
            if element.accessibilityLabel == label { return element }
            if let children = element.accessibilityElements as? [NSObject] {
                for child in children { if let hit = find(child, depth: depth + 1) { return hit } }
            }
            let count = element.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count {
                    if let child = element.accessibilityElement(at: index) as? NSObject,
                       let hit = find(child, depth: depth + 1) { return hit }
                }
            }
            if let view = element as? UIView {
                for sub in view.subviews { if let hit = find(sub, depth: depth + 1) { return hit } }
            }
            return nil
        }
        guard let target = find(root, depth: 0) else { return false }
        return target.accessibilityActivate()
    }

    private func note(_ line: String) {
        let url = Self.outDir.appendingPathComponent("NOTES.txt")
        let text = line + "\n"
        // Idempotent across runs: the notes file is committed evidence.
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing.contains(line) { return }
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
            } else {
                try Data(text.utf8).write(to: url)
            }
        } catch {
            #if DEBUG
            print("ScreenMap note failed: \(error)")
            #endif
        }
    }

    // MARK: Fixtures

    private static let stateKinds: [KuroStateView.Kind] = [
        .loading, .empty, .offline(hasCachedContent: false), .offline(hasCachedContent: true),
        .failed(hasCachedContent: false), .failed(hasCachedContent: true), .denied
    ]

    private static func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.kuroInkQuiet)
            .padding(.top, KuroDesignSpacing.md)
    }

    private static func defaults(_ suite: String) -> UserDefaults? {
        UserDefaults(suiteName: suite)
    }

    private static let artFiles: [String] = ["anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg",
                                             "anime0-banner.jpg", "anime1-banner.jpg", "anime3-banner.jpg",
                                             "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg",
                                             "journal-anime-12-cover.jpg", "journal-anime-16-cover.jpg",
                                             "journal-manga-13-cover.jpg", "journal-manga-16-cover.jpg"]

    private static func artURL(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: artURL(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }

    private struct Row {
        let id: Int
        let title: String
        let art: String
        let status: ListStatus
        let progress: Int
        let total: Int?
        let verdict: Verdict?
    }

    private static let animeRows: [Row] = [
        Row(id: 1, title: "Attack on Titan", art: "anime0.jpg", status: .current, progress: 7, total: 25, verdict: nil),
        Row(id: 2, title: "Demon Slayer", art: "anime1.jpg", status: .current, progress: 4, total: 26, verdict: nil),
        Row(id: 3, title: "JUJUTSU KAISEN", art: "anime2.jpg", status: .current, progress: 24, total: 24, verdict: nil),
        Row(id: 4, title: "Die sehr lange Geschichte eines wandernden Schwertes im Herbst", art: "anime3.jpg",
            status: .current, progress: 1, total: nil, verdict: nil),
        Row(id: 5, title: "Mushishi", art: "journal-anime-12-cover.jpg", status: .planning, progress: 0, total: 26, verdict: nil),
        Row(id: 6, title: "Cowboy Bebop", art: "journal-anime-16-cover.jpg", status: .completed, progress: 26, total: 26,
            verdict: .masterpiece)
    ]

    private static let mangaRows: [Row] = [
        Row(id: 10, title: "Chainsaw Man", art: "manga0.jpg", status: .current, progress: 24, total: 120, verdict: nil),
        Row(id: 11, title: "Solo Leveling", art: "manga1.jpg", status: .current, progress: 8, total: 200, verdict: nil),
        Row(id: 12, title: "Berserk", art: "manga2.jpg", status: .current, progress: 0, total: nil, verdict: nil),
        Row(id: 13, title: "Vagabond", art: "manga3.jpg", status: .current, progress: 327, total: 327, verdict: nil),
        Row(id: 14, title: "Goodnight Punpun", art: "journal-manga-13-cover.jpg", status: .planning, progress: 0, total: 147, verdict: nil),
        Row(id: 15, title: "Monster", art: "journal-manga-16-cover.jpg", status: .completed, progress: 162, total: 162, verdict: .okay)
    ]

    private static func media(_ row: Row, kind: MediaKind) -> Media {
        Media(id: row.id, kind: kind, title: row.title, imageURL: artURL(row.art), year: "2020",
              displayDescription: "", episodes: kind == .anime ? row.total : nil,
              chapters: kind == .manga ? row.total : nil, rating: 8.4, genres: ["Drama"],
              statusRaw: "RELEASING", formatRaw: kind == .anime ? "TV" : "MANGA",
              popularityValue: nil, trendingValue: nil, createdAtValue: nil)
    }

    private static func entry(_ row: Row, kind: MediaKind) -> LibraryEntry {
        FakeLibraryBackend.entry(kind, row.id, rowId: row.id, status: row.status, progress: row.progress, verdict: row.verdict)
    }

    private static func libraryEntries() -> [LibraryEntry] {
        animeRows.map { entry($0, kind: .anime) } + mangaRows.map { entry($0, kind: .manga) }
    }

    private static func previews() -> [ListStatus: [Media]] {
        var result: [ListStatus: [Media]] = [:]
        for row in animeRows { result[row.status, default: []].append(media(row, kind: .anime)) }
        for row in mangaRows { result[row.status, default: []].append(media(row, kind: .manga)) }
        return result
    }

    /// The Watching rows of one medium (the list's default status), with one next-release line.
    private static func folioItems(_ kind: MediaKind) -> [FolioItem] {
        let rows = (kind == .anime ? animeRows : mangaRows).filter { $0.status == .current }
        return rows.enumerated().map { index, row in
            let next: ReleaseScheduleItem? = index == 0
                ? ReleaseScheduleItem(medium: kind, mediaId: row.id, title: row.title,
                                      unitKind: kind == .anime ? .episode : .chapter,
                                      unitNumber: Double(row.progress + 1),
                                      releaseAt: Date().addingTimeInterval(3 * 86_400), basis: .announced,
                                      source: "anilist", precision: .day)
                : nil
            return FolioItem(media: media(row, kind: kind), entry: entry(row, kind: kind), progress: row.progress,
                             next: next, banner: nil)
        }
    }

    private static func folioPage(items: [FolioItem], medium: MediaKind, density: FolioDensity, width: CGFloat) -> some View {
        let gutter = FolioPolicy.gutter(forWidth: width)
        let entries = libraryEntries()
        let actions = FolioRowActions(
            open: { _ in }, advance: { _ in }, edit: { _ in }, classify: { _ in }, remove: { _ in },
            toggleSelection: { _ in },
            keyPhase: { item in
                FolioPolicy.keyPhase(status: item.entry.status, progress: item.progress, total: item.total,
                                     needsChoice: false, isPending: false)
            }
        )
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                KuroMediumSwitch(selection: .constant(medium), size: .compact)
                    .padding(.horizontal, gutter)
                    .padding(.top, KuroDesignSpacing.sm)
                FolioStatusStrip(selection: .constant(.watching), counts: FolioPolicy.counts(entries, medium: medium),
                                 medium: medium, gutter: gutter)
                FolioControlsRow(density: .constant(density), sort: .constant(.recent), isSearching: false,
                                 isSelecting: false, canSelect: true, onToggleSearch: {}, onToggleSelect: {}, gutter: gutter)
                Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                    .padding(.horizontal, gutter)
                    .padding(.top, KuroDesignSpacing.xs)
                if density == .shelf {
                    FolioShelf(items: items, medium: medium, width: width, isSelecting: false, selectedKeys: [],
                               actions: actions)
                } else {
                    FolioIndex(items: items, width: width, isSelecting: false, selectedKeys: [], actions: actions)
                }
            }
        }
        .background(Color.kuroCanvasPage)
    }
}
