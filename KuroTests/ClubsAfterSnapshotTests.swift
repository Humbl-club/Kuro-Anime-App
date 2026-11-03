import KuroCore
import KuroLibrary
import SwiftUI
import Testing
import UIKit
@testable import Kuro

/// "After" fixture renders for the Clubs lane of the Discover + Clubs redesign (spec
/// `docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md` §7, §12.2). No network: every
/// graph runs over the in-process stub PostgREST endpoint (`StubServer`). PNGs go to
/// `docs/discover-clubs-2026-11-03/after/` (only `club*.png` and `home-room-*.png`) and only with
/// `TEST_RUNNER_KURO_WRITE_SNAPSHOTS=1`; run it with `-only-testing:KuroTests/ClubsAfterSnapshotTests`
/// so no other suite rewrites its committed evidence. Ordinary runs render into a temporary folder.
///
/// `homeRoom` also takes `KURO_DC_ROOM_PREFIX` (default `home-room`): the lane rendered
/// `home-room-before-*` on the untouched sources, then `home-room-*` after the seal and threshold move
/// (spec §7.6: Home's pixels must not change), and compares the two byte for byte.
@Suite("Clubs after renders", .serialized, .timeLimit(.minutes(8)))
@MainActor
struct ClubsAfterSnapshotTests {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let outDir: URL = {
        guard ProcessInfo.processInfo.environment["KURO_WRITE_SNAPSHOTS"] == "1" else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("kuro-dc-clubs-after", isDirectory: true)
        }
        return repo.appendingPathComponent("docs/discover-clubs-2026-11-03/after")
    }()

    // MARK: Home room (consistency check)

    @Test("Home club room at 320, 390 and 430 (anime and manga)")
    func homeRoom() async throws {
        await Self.seedArtwork()
        let prefix = ProcessInfo.processInfo.environment["KURO_DC_ROOM_PREFIX"] ?? "home-room"
        let harness = try ClubsHarness(responder: { _ in .emptyArray })
        let now = try #require(ClubsStore.parseISO8601("2026-11-03T12:00:00Z"))
        let club = ClubSummary(id: "c1", name: "Sunday Club",
                               lastActivityAt: ClubsStore.parseISO8601("2026-11-03T09:00:00Z"),
                               memberNames: ["Mina", "Jules", "Ana"], memberCount: 5,
                               activityPreview: "Added: Mushishi", latestCover: Self.art("anime2.jpg"))
        let items = try JSONDecoder().decode([HomeClubItem].self, from: Data("""
        [{"comment_id":"n1","media_id":401,"media_type":"ANIME","spoiler_scope":"none",
          "text":"Episode 10 is the one. Watch it with the lights off.","display_name":"Mina","created_at":"2026-11-03T09:00:00Z"},
         {"comment_id":"n2","media_id":401,"media_type":"ANIME","spoiler_scope":"ending","text":null,
          "display_name":"Mina","created_at":"2026-11-03T08:00:00Z"}]
        """.utf8))
        let notes = items.map { HomeClubRoom.Note(item: $0, title: "Frieren: Beyond Journey's End", coverImage: Self.art("anime2.jpg")) }
        for medium in [MediaKind.anime, .manga] {
            for width in [CGFloat(320), 390, 430] {
                let gutter: CGFloat = width - 40 <= 330 ? 16 : 20
                let room = HomeClubRoom(club: club, notes: notes, otherClubCount: 1, medium: medium, now: now,
                                        onOpenClubs: {})
                    .padding(.horizontal, gutter - 3)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(medium == .manga ? Color.kuroCanvasHomeManga : Color.kuroCanvasHome)
                let window = Self.window(Self.inject(room, graph: harness.service, monitor: NetworkMonitor()),
                                         width: width, height: 620)
                try? await Task.sleep(for: .milliseconds(900))
                await capture(window, name: "\(prefix)-\(medium == .manga ? "manga" : "anime")-\(Int(width)).png")
                Self.close(window)
            }
        }
        await harness.tearDown()
    }

    // MARK: Clubs list

    @Test("Clubs list: rooms at 390, 320 and iPad; empty, loading, offline, failed")
    func clubsList() async throws {
        await Self.seedArtwork()
        let rows = Self.clubListRowsJSON()
        let harness = try ClubsHarness(responder: { request in
            (request.resource ?? "").hasPrefix("rpc/fetch_my_clubs") ? .json(rows) : .emptyArray
        })
        _ = await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        await harness.clubs.fetchMyClubs()
        for (width, height, suffix) in [(CGFloat(390), CGFloat(844), "top-390"), (390, 1_500, "full-390"),
                                        (320, 1_500, "full-320"), (834, 1_200, "ipad")] {
            // The iPad capture is a regular-width container, so the 680 readable column applies.
            let window = Self.window(Self.inject(ClubsView().environment(\.horizontalSizeClass, suffix == "ipad" ? .regular : .compact),
                                                 graph: harness.service, monitor: NetworkMonitor()),
                                     width: width, height: height)
            try? await Task.sleep(for: .milliseconds(1_500))
            await capture(window, name: "clubs-list-\(suffix).png")
            Self.close(window)
        }

        // Offline with clubs on screen: the quiet band.
        let offlineMonitor = NetworkMonitor()
        try? await Task.sleep(for: .milliseconds(300))
        offlineMonitor.isConnected = false
        let banded = Self.window(Self.inject(ClubsView(), graph: harness.service, monitor: offlineMonitor), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_400))
        offlineMonitor.isConnected = false
        try? await Task.sleep(for: .milliseconds(300))
        await capture(banded, name: "clubs-offline-with-content-390.png")
        Self.close(banded)

        // Create sheet (seal above the title), rendered directly.
        let create = Self.window(Self.inject(CreateClubSheet(onCreated: { _ in }), graph: harness.service,
                                             monitor: NetworkMonitor()), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_000))
        await capture(create, name: "club-create-sheet-390.png")
        Self.close(create)

        // Join sheet through its deep-link path (code prefilled).
        let join = Self.window(Self.inject(ClubsView(pendingJoinCode: .constant("AbC12xYz")), graph: harness.service,
                                           monitor: NetworkMonitor()), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(2_000))
        await capture(join, name: "club-join-sheet-prefilled-390.png")
        Self.close(join)
        await harness.tearDown()

        // Empty (a successful read with no clubs), 390 and 320.
        let empty = try ClubsHarness(responder: { _ in .emptyArray })
        _ = await empty.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        await empty.clubs.fetchMyClubs()
        for width in [CGFloat(390), 320] {
            let window = Self.window(Self.inject(ClubsView(), graph: empty.service, monitor: NetworkMonitor()), width: width, height: 844)
            try? await Task.sleep(for: .milliseconds(1_400))
            await capture(window, name: "clubs-empty-\(Int(width)).png")
            Self.close(window)
        }
        await empty.tearDown()

        // Loading (the read held back).
        let gate = StubGate()
        let loading = try ClubsHarness(responder: { _ in StubResponse.json("[]").held(by: gate) })
        _ = await loading.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        let loadingWindow = Self.window(Self.inject(ClubsView(), graph: loading.service, monitor: NetworkMonitor()), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_200))
        await capture(loadingWindow, name: "clubs-loading-390.png")
        Self.close(loadingWindow)
        gate.open()
        await loading.tearDown()

        // Offline first read.
        let offline = try ClubsHarness(responder: { _ in .failure(.notConnectedToInternet) })
        _ = await offline.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        let monitor = NetworkMonitor()
        try? await Task.sleep(for: .milliseconds(300))
        monitor.isConnected = false
        await offline.clubs.fetchMyClubs()
        let offlineWindow = Self.window(Self.inject(ClubsView(), graph: offline.service, monitor: monitor), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_400))
        monitor.isConnected = false
        try? await Task.sleep(for: .milliseconds(300))
        await capture(offlineWindow, name: "clubs-offline-390.png")
        Self.close(offlineWindow)
        await offline.tearDown()

        // Failed first read (a server error, connected).
        let failed = try ClubsHarness(responder: { _ in ClubJSON.error(message: "boom", code: "XX000", status: 500) })
        _ = await failed.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        await failed.clubs.fetchMyClubs()
        let failedWindow = Self.window(Self.inject(ClubsView(), graph: failed.service, monitor: NetworkMonitor()), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_400))
        await capture(failedWindow, name: "clubs-failed-390.png")
        Self.close(failedWindow)
        await failed.tearDown()
    }

    // MARK: Club page

    @Test("Club page as a journey: owner and member views, tabs, pinned bar, 320 and iPad")
    func clubPage() async throws {
        await Self.seedArtwork()
        let ownerBundle = Self.richClubBundleJSON(role: "owner")
        let harness = try ClubsHarness(responder: { request in
            request.resource == "rpc/fetch_club_bundle" ? .json(ownerBundle) : .emptyArray
        })
        _ = await harness.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")

        for (width, suffix) in [(CGFloat(390), "390"), (320, "320"), (834, "ipad")] {
            let host = JourneyHost(navigator: JourneyNavigator(root: .club(id: "c1")))
                .environment(\.horizontalSizeClass, suffix == "ipad" ? .regular : .compact)
            let window = Self.window(Self.inject(host, graph: harness.service, monitor: NetworkMonitor(), routes: false),
                                     width: width, height: 844)
            try? await Task.sleep(for: .milliseconds(2_200))
            await capture(window, name: "club-detail-top-\(suffix).png")
            if suffix == "390" {
                // Scrolled past the room: the compact paper bar with the tabs pinned under it.
                if let scroll = Self.scrollView(in: window) {
                    scroll.setContentOffset(CGPoint(x: 0, y: min(760, max(0, scroll.contentSize.height - scroll.bounds.height))),
                                            animated: false)
                }
                try? await Task.sleep(for: .milliseconds(900))
                await capture(window, name: "club-detail-rails-scrolled-390.png")
            }
            Self.close(window)
        }

        let tall = Self.window(Self.inject(JourneyHost(navigator: JourneyNavigator(root: .club(id: "c1"))), graph: harness.service,
                                           monitor: NetworkMonitor(), routes: false), width: 390, height: 2_600)
        try? await Task.sleep(for: .milliseconds(2_200))
        await capture(tall, name: "club-detail-rails-full-390.png", height: 1_500)
        Self.close(tall)
        for (tab, file) in [(ClubDetailView.Tab.active, "this-week"), (.polls, "polls")] {
            let window = Self.window(Self.inject(NavigationStack { ClubDetailView(clubId: "c1", initialTab: tab) },
                                                 graph: harness.service, monitor: NetworkMonitor()),
                                     width: 390, height: 1_900)
            try? await Task.sleep(for: .milliseconds(2_200))
            await capture(window, name: "club-detail-\(file)-full-390.png")
            Self.close(window)
        }

        // Offline with the club on screen: keys disabled.
        let offlineMonitor = NetworkMonitor()
        try? await Task.sleep(for: .milliseconds(300))
        let offline = Self.window(Self.inject(JourneyHost(navigator: JourneyNavigator(root: .club(id: "c1"))), graph: harness.service,
                                              monitor: offlineMonitor, routes: false), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(2_000))
        offlineMonitor.isConnected = false
        try? await Task.sleep(for: .milliseconds(500))
        await capture(offline, name: "club-detail-offline-keys-390.png")
        Self.close(offline)

        // Tools: invite, rail chooser, create rail and poll (seal above the title).
        let bundle = try JSONDecoder().decode(ClubBundle.self, from: Data(ownerBundle.utf8))
        let tools: [(String, AnyView)] = [
            ("club-invite-sheet-390.png", AnyView(ClubInviteSheet(clubName: bundle.club.name, code: "AbC12xYz"))),
            ("club-rail-chooser-sheet-390.png", AnyView(ClubRailChooserSheet(rails: ClubRoomRules.addableRails(bundle), onPick: { _ in }))),
            ("club-create-rail-sheet-390.png", AnyView(CreateClubRailSheet(clubId: "c1", onCreated: {}))),
            ("club-create-poll-sheet-390.png", AnyView(CreateClubPollSheet(clubId: "c1", onCreated: {})))
        ]
        for (name, view) in tools {
            let window = Self.window(Self.inject(view, graph: harness.service, monitor: NetworkMonitor()), width: 390, height: 844)
            try? await Task.sleep(for: .milliseconds(900))
            await capture(window, name: name)
            Self.close(window)
        }
        await harness.tearDown()

        // A member's view: no Invite or Ask; Add only for unlocked rails.
        let memberBundle = Self.richClubBundleJSON(role: "member")
        let member = try ClubsHarness(responder: { request in
            request.resource == "rpc/fetch_club_bundle" ? .json(memberBundle) : .emptyArray
        })
        _ = await member.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        let memberWindow = Self.window(Self.inject(JourneyHost(navigator: JourneyNavigator(root: .club(id: "c1"))),
                                                   graph: member.service, monitor: NetworkMonitor(), routes: false),
                                       width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(2_200))
        await capture(memberWindow, name: "club-detail-member-390.png")
        Self.close(memberWindow)
        await member.tearDown()

        // A quiet week (only older updates) and a duo club.
        for (label, json) in [("quiet-week", Self.richClubBundleJSON(role: "owner", ageDays: 12)),
                              ("duo", Self.duoClubBundleJSON())] {
            let h = try ClubsHarness(responder: { request in
                request.resource == "rpc/fetch_club_bundle" ? .json(json) : .emptyArray
            })
            _ = await h.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
            if label == "duo" {
                let rails = Self.window(Self.inject(JourneyHost(navigator: JourneyNavigator(root: .club(id: "c1"))), graph: h.service,
                                                    monitor: NetworkMonitor(), routes: false), width: 390, height: 1_100)
                try? await Task.sleep(for: .milliseconds(2_200))
                await capture(rails, name: "club-detail-duo-rails-390.png")
                Self.close(rails)
            }
            let window = Self.window(Self.inject(NavigationStack { ClubDetailView(clubId: "c1", initialTab: .active) },
                                                 graph: h.service, monitor: NetworkMonitor()), width: 390, height: 1_300)
            try? await Task.sleep(for: .milliseconds(2_200))
            await capture(window, name: "club-detail-this-week-\(label)-390.png")
            Self.close(window)
            await h.tearDown()
        }

        // Club page loading (the bundle held back) and failed.
        let gate = StubGate()
        let held = try ClubsHarness(responder: { request in
            request.resource == "rpc/fetch_club_bundle" ? StubResponse.json(ownerBundle).held(by: gate) : .emptyArray
        })
        _ = await held.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        let loading = Self.window(Self.inject(JourneyHost(navigator: JourneyNavigator(root: .club(id: "c1"))), graph: held.service,
                                              monitor: NetworkMonitor(), routes: false), width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(1_200))
        await capture(loading, name: "club-detail-loading-390.png")
        Self.close(loading)
        gate.open()
        await held.tearDown()

        let failing = try ClubsHarness(responder: { _ in ClubJSON.error(message: "boom", code: "XX000", status: 500) })
        _ = await failing.service.session.applySession(userId: LifecycleFixtures.userA, email: "reader@example.com")
        let failedWindow = Self.window(Self.inject(JourneyHost(navigator: JourneyNavigator(root: .club(id: "c1"))),
                                                   graph: failing.service, monitor: NetworkMonitor(), routes: false),
                                       width: 390, height: 844)
        try? await Task.sleep(for: .milliseconds(2_000))
        await capture(failedWindow, name: "club-detail-failed-390.png")
        Self.close(failedWindow)
        await failing.tearDown()
    }

    // MARK: Hosting

    private static func inject<V: View>(_ view: V, graph: AppGraph, monitor: NetworkMonitor, routes: Bool = true) -> AnyView {
        let base = view
            .environment(graph.identity)
            .environment(graph.auth)
            .environment(graph.session)
            .environment(graph.library)
            .environment(graph.libraryActions)
            .environment(graph.home)
            .environment(graph.catalog)
            .environment(graph.search)
            .environment(graph.discovery)
            .environment(graph.recommendations)
            .environment(graph.releases)
            .environment(graph.social)
            .environment(graph.availability)
            .environment(graph.clubs)
            .environment(graph.collection)
            .environment(graph.imports)
            .environment(graph.concierge)
            .environment(graph.taste)
            .environment(graph.deviceIntelligence)
            .environment(graph.support)
            .environment(graph.banner)
            .environment(graph.flags)
            .environment(graph.interactionTelemetry)
            .environment(graph.outboundLinks)
            .environment(graph.artworkMaterials)
            .environment(monitor)
            .environment(\.kuroFoldMemory, KuroFoldMemory())
        return routes ? AnyView(base.environment(\.kuroRoutes, KuroRoutes.unhandled)) : AnyView(base)
    }

    private static func window(_ view: AnyView, width: CGFloat, height: CGFloat) -> UIWindow {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        host.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.isHidden = false
        window.makeKey()
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.backgroundColor = .white
        host.view.layoutIfNeeded()
        return window
    }

    private static func close(_ window: UIWindow) {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
    }

    private func capture(_ window: UIWindow, name: String, height: CGFloat? = nil) async {
        do {
            try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
        } catch {
            Issue.record("Could not create \(Self.outDir.path): \(error)")
            return
        }
        window.layoutIfNeeded()
        let size = CGSize(width: window.bounds.width, height: min(height ?? window.bounds.height, window.bounds.height))
        guard let data = FixtureRaster.png(of: window, size: size, diagnosticScale: nil) else {
            Issue.record("\(name): PNG encoding failed")
            return
        }
        do { try data.write(to: Self.outDir.appendingPathComponent(name)) } catch { Issue.record("\(name): write failed (\(error))") }
    }

    private static func scrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var stack = [root]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.window != nil, !scroll.isHidden,
               scroll.contentSize.height > scroll.bounds.height,
               scroll.convert(scroll.bounds, to: nil).intersects(root.bounds) {
                if best == nil || scroll.contentSize.height > (best?.contentSize.height ?? 0) { best = scroll }
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }

    // MARK: Artwork

    private static let artFiles: [String] = [
        "anime0.jpg", "anime1.jpg", "anime2.jpg", "anime3.jpg", "manga0.jpg", "manga1.jpg", "manga2.jpg", "manga3.jpg",
        "journal-anime-12-cover.jpg", "journal-anime-16-cover.jpg", "journal-manga-13-cover.jpg"
    ]

    nonisolated static func art(_ file: String) -> String { "https://visual-fixture.invalid/" + file }

    private static func seedArtwork() async {
        for file in artFiles {
            guard let data = try? Data(contentsOf: repo.appendingPathComponent("tools/design-directions/assets/" + file)),
                  let url = URL(string: art(file)),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "image/jpeg"]) else { continue }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowedInMemoryOnly),
                for: URLRequest(url: url))
        }
    }

    // MARK: Club fixtures

    /// An ISO timestamp `days` days (plus `hours` hours) before now: "This week" filters on device time.
    nonisolated private static func ago(days: Double, hours: Double = 0) -> String {
        let date = Date().addingTimeInterval(-(days * 86_400 + hours * 3_600))
        return ISO8601DateFormatter().string(from: date)
    }

    nonisolated static func clubListRowsJSON() -> String {
        """
        [{"id":"c2","name":"Ink Readers","sharing_level":"status","is_archived":false,"created_at":"2026-02-01T00:00:00Z",
          "member_count":3,"rail_count":1,"poll_count":1,"last_activity_at":"\(ago(days: 5))","activity_preview":"Poll: Berserk or Vagabond next?",
          "cover_images":["\(art("manga2.jpg"))","\(art("manga3.jpg"))"],"member_names":["Cleo","Dev","Max"]},
         {"id":"c3","name":"Die sehr lange Freitagabend-Runde der Anime-Freunde","sharing_level":"private","is_archived":false,
          "created_at":"2026-03-01T00:00:00Z","member_count":2,"rail_count":0,"poll_count":0,"last_activity_at":null,
          "activity_preview":null,"cover_images":[],"member_names":["Lea","Max"]},
         {"id":"c1","name":"Sunday Club","sharing_level":"progress","is_archived":false,"created_at":"2026-01-01T00:00:00Z",
          "member_count":5,"rail_count":3,"poll_count":2,"last_activity_at":"\(ago(days: 0, hours: 3))","activity_preview":"Added: Frieren: Beyond Journey's End",
          "cover_images":["\(art("anime2.jpg"))","\(art("journal-anime-12-cover.jpg"))","\(art("anime0.jpg"))","\(art("manga0.jpg"))"],
          "member_names":["Mina","Jules","Ana","Ben"]}]
        """
    }

    /// The rich club. `ageDays` moves every member update that many days back (12 = a quiet week).
    nonisolated static func richClubBundleJSON(role: String, ageDays: Double = 0) -> String {
        let me = LifecycleFixtures.userA
        func item(_ id: String, _ type: String, _ mediaId: Int, _ title: String, _ cover: String, note: String? = nil,
                  addedBy: String = "m1", episodes: Int? = nil, chapters: Int? = nil, myStatus: String? = nil,
                  myProgress: Int? = nil, statuses: String = "null", counts: String = "null", reactions: String = "null",
                  mine: String = "null") -> String {
            let noteJSON = note.map { "\"\($0)\"" } ?? "null"
            return """
            {"id":"\(id)","media_type":"\(type)","media_id":\(mediaId),"sort_order":0,"note":\(noteJSON),"added_by":"\(addedBy)",
             "title_display":"\(title)","cover_image_medium":"\(art(cover))","average_score":86,"year":2023,"format":"TV",
             "episode_count":\(episodes.map(String.init) ?? "null"),"chapter_count":\(chapters.map(String.init) ?? "null"),
             "my_status":\(myStatus.map { "\"\($0)\"" } ?? "null"),"my_progress":\(myProgress.map(String.init) ?? "null"),
             "my_rating":null,"member_status_counts":\(counts),"member_statuses":\(statuses),"reactions":\(reactions),"my_reactions":\(mine)}
            """
        }
        let a = ageDays
        let frierenStatuses = """
        [{"user_id":"m1","display_name":"Mina","status":"CURRENT","progress":14,"updated_at":"\(ago(days: a, hours: 2))"},
         {"user_id":"m2","display_name":"Jules","status":"CURRENT","progress":9,"updated_at":"\(ago(days: a + 1, hours: 1))"},
         {"user_id":"\(me)","display_name":"Max","status":"CURRENT","progress":7,"updated_at":"\(ago(days: a, hours: 5))"},
         {"user_id":"m3","display_name":"Ana","status":"COMPLETED","progress":28,"updated_at":"\(ago(days: a + 2))"}]
        """
        let mushishiStatuses = """
        [{"user_id":"m2","display_name":"Jules","status":"PLANNING","progress":0,"updated_at":"\(ago(days: a + 4))"},
         {"user_id":"m4","display_name":"Ben","status":"CURRENT","progress":3,"updated_at":null}]
        """
        let csmStatuses = """
        [{"user_id":"m1","display_name":"Mina","status":"CURRENT","progress":88,"updated_at":"\(ago(days: a + 3))"},
         {"user_id":"m3","display_name":"Ana","status":"CURRENT","progress":120,"updated_at":"\(ago(days: a + 9))"}]
        """
        let watch = [
            item("i1", "ANIME", 401, "Frieren: Beyond Journey's End", "anime2.jpg",
                 note: "Episode 10 is the one. Watch it with the lights off.", episodes: 28, myStatus: "CURRENT", myProgress: 7,
                 statuses: frierenStatuses, counts: #"{"CURRENT":3,"COMPLETED":1}"#, reactions: #"{"fire":3,"heart":2}"#, mine: #"["fire"]"#),
            item("i2", "ANIME", 402, "Mushishi", "journal-anime-12-cover.jpg", note: "Best with rain outside.", addedBy: "m2",
                 episodes: 26, statuses: mushishiStatuses, reactions: #"{"eyes":1}"#),
            item("i3", "ANIME", 403, "Attack on Titan", "anime0.jpg", episodes: 25, myStatus: "COMPLETED", myProgress: 25),
            item("i4", "ANIME", 405, "Mob Psycho 100", "anime3.jpg", addedBy: "m3", episodes: 12)
        ].joined(separator: ",")
        let read = [
            item("i5", "MANGA", 501, "Chainsaw Man", "manga0.jpg", addedBy: "m3",
                 chapters: 120, myStatus: "CURRENT", myProgress: 61, statuses: csmStatuses, reactions: #"{"100":2}"#),
            item("i6", "MANGA", 504, "Vagabond", "manga3.jpg", chapters: 327),
            item("i7", "MANGA", 505, "Goodnight Punpun", "journal-manga-13-cover.jpg", addedBy: "m4", chapters: 147)
        ].joined(separator: ",")
        let invite = role == "member" ? "null" : "\"AbC12xYz\""
        return """
        {"club":{"id":"c1","name":"Sunday Club","description":"Five friends, one episode on Sundays, no spoilers before Monday.",
                 "sharing_level":"progress","max_members":20,"is_archived":false,"invite_code":\(invite),"created_at":"2026-01-01T00:00:00Z"},
         "members":[{"user_id":"\(me)","display_name":"Max","role":"\(role)","sharing_level":"progress","joined_at":"2026-01-01T00:00:00Z"},
                    {"user_id":"m1","display_name":"Mina","role":"\(role == "owner" ? "admin" : "owner")","sharing_level":"progress","joined_at":"2026-01-02T00:00:00Z"},
                    {"user_id":"m2","display_name":"Jules","role":"member","sharing_level":"progress","joined_at":"2026-01-03T00:00:00Z"},
                    {"user_id":"m3","display_name":"Ana","role":"member","sharing_level":"status","joined_at":"2026-01-04T00:00:00Z"},
                    {"user_id":"m4","display_name":"Ben","role":"member","sharing_level":"progress","joined_at":"2026-01-05T00:00:00Z"}],
         "my_role":"\(role)","my_sharing_level":"progress",
         "rails":[{"id":"r1","title":"Sunday watch","description":"One episode a week, together.","is_locked":false,"sort_order":0,
                   "created_by":"\(me)","items":[\(watch)]},
                  {"id":"r2","title":"Reading corner","description":null,"is_locked":true,"sort_order":1,"created_by":"m1","items":[\(read)]},
                  {"id":"r3","title":"Maybe later","description":null,"is_locked":false,"sort_order":2,"created_by":"m2","items":[]}],
         "polls":[{"id":"p1","question":"What do we start after Frieren?","is_closed":false,"closes_at":"2026-11-09T18:00:00Z",
                   "created_by":"\(me)","created_at":"2026-11-01T10:00:00Z",
                   "options":[{"id":"o1","label":"Mushishi","media_type":"ANIME","media_id":402,"sort_order":0,"vote_count":3},
                              {"id":"o2","label":"Mob Psycho 100","media_type":"ANIME","media_id":405,"sort_order":1,"vote_count":1},
                              {"id":"o3","label":"Something new","media_type":null,"media_id":null,"sort_order":2,"vote_count":0}],
                   "my_vote_option_id":"o1"},
                  {"id":"p3","question":"Sub or dub for Frieren?","is_closed":false,"closes_at":null,
                   "created_by":"m1","created_at":"2026-11-02T10:00:00Z",
                   "options":[{"id":"o6","label":"Sub","media_type":null,"media_id":null,"sort_order":0,"vote_count":2},
                              {"id":"o7","label":"Dub","media_type":null,"media_id":null,"sort_order":1,"vote_count":1}],
                   "my_vote_option_id":null},
                  {"id":"p2","question":"Sunday or Monday nights?","is_closed":true,"closes_at":"2026-10-20T18:00:00Z",
                   "created_by":"m1","created_at":"2026-10-10T10:00:00Z",
                   "options":[{"id":"o4","label":"Sunday","media_type":null,"media_id":null,"sort_order":0,"vote_count":4},
                              {"id":"o5","label":"Monday","media_type":null,"media_id":null,"sort_order":1,"vote_count":1}],
                   "my_vote_option_id":"o4"}],
         "member_count":5}
        """
    }

    /// Two members: the server withholds member statuses (k ≥ 3), so This week has the duo line.
    nonisolated static func duoClubBundleJSON() -> String {
        let me = LifecycleFixtures.userA
        return """
        {"club":{"id":"c1","name":"Ana & Max","description":null,"sharing_level":"status","max_members":20,"is_archived":false,
                 "invite_code":"Qw3rTy12","created_at":"2026-01-01T00:00:00Z"},
         "members":[{"user_id":"\(me)","display_name":"Max","role":"owner","sharing_level":"status","joined_at":"2026-01-01T00:00:00Z"}],
         "my_role":"owner","my_sharing_level":"status",
         "rails":[{"id":"r1","title":"Next up","description":null,"is_locked":false,"sort_order":0,"created_by":"\(me)",
                   "items":[{"id":"i1","media_type":"ANIME","media_id":401,"sort_order":0,"note":null,"added_by":"\(me)",
                             "title_display":"Frieren: Beyond Journey's End","cover_image_medium":"\(art("anime2.jpg"))",
                             "average_score":91,"year":2023,"format":"TV","episode_count":28,"chapter_count":null,
                             "my_status":null,"my_progress":null,"my_rating":null,"member_status_counts":null,
                             "member_statuses":null,"reactions":null,"my_reactions":null}]}],
         "polls":[],"member_count":2}
        """
    }
}
