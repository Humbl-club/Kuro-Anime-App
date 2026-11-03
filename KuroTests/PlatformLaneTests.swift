//
//  PlatformLaneTests.swift
//  KuroTests
//
//  Platform lane (2026-11-03, items 9 and 10): the Home Screen widget snapshot (built from the release
//  schedule with the certainty rules, account-scoped files cleared on sign-out / switch, kept for the
//  restored owner), the +1 hand-off queue drained through `LibraryActions` (idempotent per account /
//  title / target unit, caught-up guard, lifecycle check), and the release notification plan and its
//  commit (spec D14: only exact confirmed / announced times notify, at their moment; an announced day or
//  an estimate never; two per title, 48 cap; default off; the detail bell is a per-title override;
//  account switch clears; never a prompt outside the explicit toggle / bell).
//

import Foundation
import KuroCore
import KuroLibrary
import KuroWidgetSupport
import Testing
@testable import Kuro

// MARK: - Fixtures

@MainActor
final class RecordingWidgetReloader: WidgetTimelineReloading {
    private(set) var reloads = 0
    func reloadTimelines(ofKinds kinds: [String]) { reloads += 1 }
}

@MainActor
struct PlatformHarness {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    let backend: FakeLibraryBackend
    let notifications: FakeNotificationCenter
    let reloader: RecordingWidgetReloader
    let directory: URL
    let defaults: UserDefaults
    let service: AppGraph
    private let suiteName: String

    /// A graph over `directory` (a fresh one unless given) and `defaults` (fresh unless given): pass
    /// both from an earlier harness to model a relaunch of the same install.
    init(directory: URL? = nil, suiteName: String? = nil, backend: FakeLibraryBackend? = nil,
         notifications: FakeNotificationCenter? = nil) throws {
        let backend = backend ?? FakeLibraryBackend()
        let notifications = notifications ?? FakeNotificationCenter()
        let dir = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("kuro-platform-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = suiteName ?? "kuro.tests.platform.\(UUID().uuidString)"
        self.suiteName = suite
        self.directory = dir
        self.defaults = try #require(UserDefaults(suiteName: suite))
        self.backend = backend
        self.notifications = notifications
        let reloader = RecordingWidgetReloader()
        self.reloader = reloader
        service = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: notifications,
                                              libraryBackend: backend, widgetDirectory: dir, widgetReloader: reloader)
    }

    var widgets: WidgetSnapshotWriter { service.widgets }
    var store: WidgetSnapshotStore { WidgetSnapshotStore(directory: directory) }
    var queue: WidgetAdvanceQueue { WidgetAdvanceQueue(directory: directory) }
    var suite: String { suiteName }

    func signIn(_ userId: String = PlatformHarness.userA) async {
        await service.session.applySession(userId: userId, email: "\(userId)@example.com")
        await service.libraryActions.libraryRefreshTask?.value
    }

    func hash(_ userId: String) -> WidgetAccountHash { widgets.accountHash(for: userId) }

    func tearDown(keepFiles: Bool = false) async {
        await service.session.endSession()
        guard !keepFiles else { return }
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A release row with explicit certainty.
private func release(_ id: Int, kind: MediaKind = .anime, unit: Double = 8, at date: Date?, basis: ReleaseBasis,
                     precision: ReleasePrecision?, confidence: Double? = nil, source: String = "anilist",
                     title: String = "Frieren") -> ReleaseScheduleItem {
    ReleaseScheduleItem(medium: kind, mediaId: id, title: title, unitKind: kind == .anime ? .episode : .chapter,
                        unitNumber: unit, releaseAt: date, basis: basis, confidence: confidence, source: source,
                        precision: precision)
}

private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .current
private let english = Locale(identifier: "en_GB")
private let german = Locale(identifier: "de_DE")
/// Mon 3 Nov 2026, 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_793_707_200)

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? now
}

private func copy(_ german: Bool = false, zone: TimeZone = berlin, at date: Date = now) -> ReleaseCopy {
    ReleaseCopy(now: date, german: german, locale: german ? Locale(identifier: "de_DE") : english, timeZone: zone)
}

/// Publishes `items` as the account's answered schedule (coverage set, so no read replaces it).
@MainActor
private func seedSchedule(_ h: PlatformHarness, _ items: [ReleaseScheduleItem]) {
    h.service.releases.schedule = items
    h.service.releases.scheduleCoverageByMedium = [.anime: .complete, .manga: .complete]
}

// MARK: - Snapshot building

@MainActor
@Suite("Platform: widget snapshot building")
struct WidgetSnapshotBuildingTests {
    @Test("a countdown target only for a confirmed instant; estimates labelled and never timed; windows never expire; day rows expire at local midnight")
    func certaintyRules() throws {
        let confirmed = release(1, at: utc(2026, 11, 7, 20, 30), basis: .confirmed, precision: .instant)
        let announcedDay = release(2, kind: .manga, unit: 68, at: utc(2026, 11, 12), basis: .announced, precision: .day,
                                   source: "mangaupdates", title: "Kagurabachi")
        let estimate = release(3, kind: .manga, unit: 1197, at: utc(2026, 11, 9), basis: .estimated, precision: .day,
                               confidence: 0.9, source: "kuro_estimate", title: "One Piece")
        let window = release(4, kind: .manga, unit: 115, at: utc(2026, 12, 1), basis: .announced, precision: .month,
                             source: "publisher", title: "Vol")
        let snapshot = WidgetSnapshotBuilder.build(
            account: WidgetAccountHash(value: "a"), now: now, copy: copy(),
            releases: [confirmed, announcedDay, estimate, window], tracked: [], metadata: [:], thumbnails: [:])
        let rows = Dictionary(uniqueKeysWithValues: snapshot.releases.map { ($0.mediaId, $0) })
        #expect(rows[1]?.countdownTarget == utc(2026, 11, 7, 20, 30))
        #expect(rows[1]?.expiresAt == utc(2026, 11, 7, 20, 30))
        #expect(rows[1]?.line.contains("21:30") == true, "the confirmed instant shows its local time: \(rows[1]?.line ?? "")")
        #expect(rows[2]?.countdownTarget == nil, "an announced day never gets a time")
        #expect(rows[2]?.line.contains(":") == false)
        // 12 Nov in Berlin: expires at 13 Nov 00:00 Berlin = 12 Nov 23:00 UTC.
        #expect(rows[2]?.expiresAt == utc(2026, 11, 12, 23))
        #expect(rows[3]?.countdownTarget == nil, "an estimate never gets a time")
        #expect(rows[3]?.isEstimate == true)
        #expect(rows[3]?.line.contains("expected") == true, "an estimate is labelled: \(rows[3]?.line ?? "")")
        #expect(rows[4]?.expiresAt == nil)
        #expect(rows[4]?.line == "Ch. 115 · December")
        #expect(snapshot.releases.allSatisfy { $0.deepLink?.scheme == "kuro" })
    }

    @Test("German rendering; passed and low-confidence rows are not written; at most eight releases")
    func germanAndBounds() {
        let passed = release(9, at: now.addingTimeInterval(-60), basis: .confirmed, precision: .instant)
        let weak = release(10, kind: .manga, at: utc(2026, 11, 9), basis: .estimated, precision: .day, confidence: 0.4,
                           source: "kuro_estimate")
        let many = (20..<40).map { release($0, at: now.addingTimeInterval(Double($0) * 3600), basis: .confirmed, precision: .instant) }
        let snapshot = WidgetSnapshotBuilder.build(account: WidgetAccountHash(value: "a"), now: now, copy: copy(true),
                                                   releases: [passed, weak] + many, tracked: [], metadata: [:], thumbnails: [:])
        #expect(snapshot.german)
        #expect(snapshot.releases.count == WidgetSnapshot.maxReleases)
        #expect(!snapshot.releases.contains { $0.mediaId == 9 || $0.mediaId == 10 })
        #expect(snapshot.releases.first?.unitLabel == "F. 8")
    }

    @Test("Now Watching: watching/reading only, newest first, a title is required, totals and lifecycles carried")
    func nowWatchingRows() throws {
        let lifecycle = UUID()
        func row(_ kind: MediaKind, _ id: Int, _ status: ListStatus, _ minutes: Double, progress: Int = 3) -> WidgetTrackedTitle {
            WidgetTrackedTitle(key: MediaKey(kind: kind, id: id), status: status, progress: progress,
                               lifecycleId: id == 1 ? lifecycle : nil, revision: 5, updatedAt: now.addingTimeInterval(minutes * 60))
        }
        let tracked = [row(.anime, 1, .current, 1, progress: 7), row(.manga, 2, .repeating, 5), row(.anime, 3, .planning, 9),
                       row(.anime, 4, .completed, 9), row(.anime, 5, .current, 3)]
        let metadata: [MediaKey: WidgetTitleMetadata] = [
            MediaKey(kind: .anime, id: 1): WidgetTitleMetadata(title: "Frieren", total: 28, artworkURL: nil),
            MediaKey(kind: .manga, id: 2): WidgetTitleMetadata(title: "Blame!", total: nil, artworkURL: nil),
        ]
        let snapshot = WidgetSnapshotBuilder.build(account: WidgetAccountHash(value: "a"), now: now, copy: copy(true),
                                                   releases: [], tracked: tracked, metadata: metadata, thumbnails: [:])
        #expect(snapshot.nowWatching.map(\.mediaId) == [2, 1], "planned/completed excluded; title 5 has no name")
        let frieren = try #require(snapshot.nowWatching.last)
        #expect(frieren.progress == 7)
        #expect(frieren.total == 28)
        #expect(frieren.lifecycleId == lifecycle.uuidString)
        #expect(frieren.unitPrefix == "F. ")
        #expect(snapshot.nowWatching.first?.unitPrefix == "Kap. ")
        #expect(frieren.deepLink?.absoluteString == "kuro://anime/1")
    }
}

// MARK: - Account scope of the widget files

@MainActor
@Suite("Platform: widget files are account-scoped", .timeLimit(.minutes(1)))
struct WidgetAccountScopeTests {
    private func seedSnapshot(_ h: PlatformHarness, _ userId: String) async throws {
        seedSchedule(h, [release(1, at: Date().addingTimeInterval(86_400), basis: .confirmed, precision: .instant)])
        #expect(await h.widgets.writeNow())
        #expect(h.store.read()?.account == h.hash(userId))
    }

    @Test("sign-out removes the snapshot and every queued +1; an unchanged snapshot is not rewritten")
    func signOutClears() async throws {
        let h = try PlatformHarness()
        await h.signIn()
        try await seedSnapshot(h, PlatformHarness.userA)
        let reloadsAfterWrite = h.reloader.reloads
        #expect(await h.widgets.writeNow() == false, "the same content is not written twice")
        #expect(h.reloader.reloads == reloadsAfterWrite, "no timeline reload without a change")
        _ = h.queue.enqueue(WidgetAdvanceRequest(id: UUID(), account: h.hash(PlatformHarness.userA), medium: .anime,
                                                 mediaId: 1, targetUnit: 4, lifecycleId: nil, total: nil, createdAt: Date()))
        await h.service.session.endSession()
        #expect(h.store.read() == nil)
        #expect(h.queue.all().isEmpty)
        await h.tearDown()
    }

    @Test("a switch to another account drops the previous account's snapshot and requests, keeps the next account's")
    func switchClears() async throws {
        let h = try PlatformHarness()
        await h.signIn(PlatformHarness.userA)
        try await seedSnapshot(h, PlatformHarness.userA)
        let a = WidgetAdvanceRequest(id: UUID(), account: h.hash(PlatformHarness.userA), medium: .anime, mediaId: 1,
                                     targetUnit: 4, lifecycleId: nil, total: nil, createdAt: Date())
        let b = WidgetAdvanceRequest(id: UUID(), account: h.hash(PlatformHarness.userB), medium: .anime, mediaId: 1,
                                     targetUnit: 2, lifecycleId: nil, total: nil, createdAt: Date())
        _ = h.queue.enqueue(a)
        _ = h.queue.enqueue(b)
        await h.signIn(PlatformHarness.userB)
        #expect(h.store.read() == nil, "A's snapshot is readable after B signed in")
        #expect(h.queue.all().map(\.id) == [b.id])
        await h.tearDown()
    }

    @Test("a launch restore of the SAME account keeps its snapshot and queued +1 (applied after the Library loads)")
    func restoredOwnerKeepsFiles() async throws {
        let first = try PlatformHarness()
        await first.signIn()
        try await seedSnapshot(first, PlatformHarness.userA)
        _ = first.queue.enqueue(WidgetAdvanceRequest(id: UUID(), account: first.hash(PlatformHarness.userA), medium: .anime,
                                                     mediaId: 1, targetUnit: 4, lifecycleId: nil, total: nil, createdAt: Date()))
        // Relaunch: a new graph over the same install (directory + defaults), restored as the same user.
        let relaunch = try PlatformHarness(directory: first.directory, suiteName: first.suite)
        await relaunch.signIn()
        #expect(relaunch.store.read()?.account == relaunch.hash(PlatformHarness.userA))
        #expect(relaunch.queue.all().count == 1)
        await relaunch.tearDown()
    }

    @Test("a failed offline launch restore keeps the owner's snapshot and queued +1; a restore after which the SDK holds no session removes them")
    func failedRestore() async throws {
        let first = try PlatformHarness()
        await first.signIn()
        try await seedSnapshot(first, PlatformHarness.userA)
        _ = first.queue.enqueue(WidgetAdvanceRequest(id: UUID(), account: first.hash(PlatformHarness.userA), medium: .anime,
                                                     mediaId: 1, targetUnit: 4, lifecycleId: nil, total: nil, createdAt: Date()))
        // Relaunch offline: the restore fails, the SDK still holds A's session.
        let offline = try PlatformHarness(directory: first.directory, suiteName: first.suite)
        await offline.service.session.endSessionAfterFailedRestore(storedSessionUserId: PlatformHarness.userA)
        #expect(offline.store.read()?.account == offline.hash(PlatformHarness.userA), "a failed offline restore wiped the widget")
        #expect(offline.queue.all().count == 1, "a tap made while Kuro was closed was lost")
        // Relaunch again: the SDK dropped the session, nobody owns the files.
        let revoked = try PlatformHarness(directory: first.directory, suiteName: first.suite)
        await revoked.service.session.endSessionAfterFailedRestore(storedSessionUserId: nil)
        #expect(revoked.store.read() == nil)
        #expect(revoked.queue.all().isEmpty)
        await revoked.tearDown()
    }

    @Test("account deletion removes that account's snapshot and requests")
    func deletionClears() async throws {
        let h = try PlatformHarness()
        await h.signIn()
        try await seedSnapshot(h, PlatformHarness.userA)
        try await h.widgets.removeDeletedAccountData(userId: PlatformHarness.userA)
        #expect(h.store.read() == nil)
        await h.tearDown()
    }
}

// MARK: - +1 hand-off: drain through LibraryActions

@MainActor
@Suite("Platform: widget +1 is applied by the app", .timeLimit(.minutes(1)))
struct WidgetIntentDrainTests {
    private func harness(progress: Int = 7, lifecycle: UUID? = nil) async throws -> PlatformHarness {
        let backend = FakeLibraryBackend()
        var entry = FakeLibraryBackend.entry(.anime, 42, rowId: 42, status: .current, progress: progress)
        entry.lifecycleId = lifecycle
        backend.setRows([entry], for: PlatformHarness.userA)
        let h = try PlatformHarness(backend: backend)
        await h.signIn()
        return h
    }

    private func request(_ h: PlatformHarness, target: Int, user: String = PlatformHarness.userA,
                         lifecycle: String? = nil, total: Int? = 12) -> WidgetAdvanceRequest {
        WidgetAdvanceRequest(id: UUID(), account: h.hash(user), medium: .anime, mediaId: 42, targetUnit: target,
                             lifecycleId: lifecycle, total: total, createdAt: Date())
    }

    private func progress(_ h: PlatformHarness) -> Int? {
        h.service.library.entry(for: MediaKey(kind: .anime, id: 42))?.progress
    }

    @Test("queued taps apply in order through the Library; a double tap queues once; the queue empties")
    func appliesInOrder() async throws {
        let h = try await harness()
        #expect(h.queue.enqueue(request(h, target: 8)) == .queued)
        #expect(h.queue.enqueue(request(h, target: 8)) == .duplicate)
        #expect(h.queue.enqueue(request(h, target: 9)) == .queued)
        let report = await h.widgets.drainQueuedAdvances()
        #expect(report.applied == 2)
        #expect(progress(h) == 9)
        #expect(h.queue.all().isEmpty)
        #expect(h.backend.writeCalls.count == 2, "one Library write per +1")
        await h.tearDown()
    }

    @Test("idempotent: a replayed request for a position already reached is dropped without a write")
    func replayIsNoOp() async throws {
        let h = try await harness(progress: 9)
        _ = h.queue.enqueue(request(h, target: 8))
        _ = h.queue.enqueue(request(h, target: 9))
        let report = await h.widgets.drainQueuedAdvances()
        #expect(report.applied == 0 && report.dropped == 2)
        #expect(progress(h) == 9)
        #expect(h.backend.writeCalls.isEmpty)
        await h.tearDown()
    }

    @Test("the caught-up guard refuses a +1 past the total; another lifecycle is stale")
    func guards() async throws {
        let lifecycle = UUID()
        let h = try await harness(progress: 12, lifecycle: lifecycle)
        // Well-formed for the queue (target 13 with an unknown total) but the app's cap says 12.
        let outcome = await h.service.libraryActions.advanceQueuedProgress(MediaKey(kind: .anime, id: 42), to: 13,
                                                                            lifecycleId: lifecycle, cap: 12)
        #expect(outcome == .refused)
        _ = h.queue.enqueue(request(h, target: 13, lifecycle: UUID().uuidString, total: nil))
        let report = await h.widgets.drainQueuedAdvances()
        #expect(report.dropped == 1 && report.applied == 0)
        #expect(progress(h) == 12)
        #expect(h.backend.writeCalls.isEmpty)
        await h.tearDown()
    }

    @Test("another account's request is never applied; an untracked title's request is dropped")
    func accountAndMembership() async throws {
        let h = try await harness()
        let foreign = request(h, target: 8, user: PlatformHarness.userB)
        _ = h.queue.enqueue(foreign)
        var untracked = request(h, target: 1)
        untracked = WidgetAdvanceRequest(id: untracked.id, account: untracked.account, medium: .anime, mediaId: 777,
                                         targetUnit: 1, lifecycleId: nil, total: nil, createdAt: Date())
        _ = h.queue.enqueue(untracked)
        let report = await h.widgets.drainQueuedAdvances()
        #expect(report.applied == 0 && report.dropped == 1)
        #expect(progress(h) == 7)
        #expect(h.queue.all().map(\.id) == [foreign.id], "B's request waits for B (the switch would clear it)")
        await h.tearDown()
    }

    @Test("the extension-side check queues only the next unit of a title in the current snapshot")
    func extensionSideValidation() throws {
        let account = WidgetAccountHash(value: "a")
        let item = WidgetNowWatchingItem(medium: .anime, mediaId: 42, title: "Frieren", progress: 7, total: 12,
                                         unitPrefix: "Ep. ", lifecycleId: nil, revision: nil, artworkURL: nil,
                                         thumbnail: nil, deepLink: nil)
        let snapshot = WidgetSnapshot(account: account, generatedAt: now, german: false, releases: [], nowWatching: [item])
        let queued = [try #require(item.advanceRequest(account: account, now: now))]
        // After one queued tap the widget shows 8, so the next tap must name 9.
        let shown = snapshot.applyingPending(queued)
        #expect(shown.nowWatching.first?.progress == 8)
        #expect(shown.nowWatching.first?.advanceRequest(account: account, now: now)?.targetUnit == 9)
        #expect(snapshot.applyingPending(queued).nowWatching.first?.isQueued == true)
        #expect(WidgetSnapshot(account: account, generatedAt: now, german: false, releases: [], nowWatching: [])
            .applyingPending(queued).nowWatching.isEmpty, "no title, no request")
    }
}

// MARK: - Release notification plan

@MainActor
@Suite("Platform: release notification rules")
struct ReleaseNotificationPlanTests {
    private let following: Set<MediaKey> = [MediaKey(kind: .anime, id: 1), MediaKey(kind: .manga, id: 2),
                                            MediaKey(kind: .manga, id: 3), MediaKey(kind: .manga, id: 4),
                                            MediaKey(kind: .anime, id: 5)]

    private func plan(_ items: [ReleaseScheduleItem], zone: TimeZone = berlin, german: Bool = false,
                      muted: Set<MediaKey> = [], limit: Int = ReleaseNotificationPlanner.maxPending) -> [PlannedReleaseNotification] {
        ReleaseNotificationPlanner.plan(items: items, following: following, muted: muted, now: now, german: german,
                                        locale: german ? Locale(identifier: "de_DE") : english, timeZone: zone, limit: limit)
    }

    @Test("estimates never notify; month/quarter/year windows and undated rows never notify")
    func exclusions() {
        let items = [
            release(2, kind: .manga, unit: 1197, at: utc(2026, 11, 9), basis: .estimated, precision: .day, confidence: 0.95, source: "kuro_estimate"),
            release(3, kind: .manga, unit: 115, at: utc(2026, 12, 1), basis: .announced, precision: .month, source: "publisher"),
            release(4, kind: .manga, unit: 5, at: utc(2027, 1, 1), basis: .announced, precision: .quarter, source: "publisher"),
            release(5, kind: .anime, unit: 1, at: nil, basis: .announced, precision: .day),
        ]
        #expect(plan(items).isEmpty)
    }

    @Test("isEligible: instant + confirmed yes; announced day no; estimate no; past no (spec §20)")
    func eligibility() {
        let soon = Date().addingTimeInterval(3 * 86_400)
        #expect(ReleaseNotificationPlanner.isEligible(release(1, at: soon, basis: .confirmed, precision: .instant), now: Date()))
        #expect(ReleaseNotificationPlanner.isEligible(release(1, at: soon, basis: .announced, precision: .instant), now: Date()))
        #expect(!ReleaseNotificationPlanner.isEligible(release(2, kind: .manga, at: soon, basis: .announced, precision: .day), now: Date()))
        #expect(!ReleaseNotificationPlanner.isEligible(release(1, at: soon, basis: .estimated, precision: .instant), now: Date()))
        #expect(!ReleaseNotificationPlanner.isEligible(release(1, at: Date().addingTimeInterval(-3600), basis: .confirmed,
                                                               precision: .instant), now: Date()))
        #expect(!ReleaseNotificationPlanner.isEligible(release(1, at: Date().addingTimeInterval(30), basis: .confirmed,
                                                               precision: .instant), now: Date()), "inside the 60 s lead")
    }

    @Test("an instant notifies once at its moment (no 1 h reminder); an announced day never notifies")
    func precisionHandling() throws {
        let instant = release(1, kind: .anime, at: utc(2026, 11, 7, 20, 30), basis: .confirmed, precision: .instant)
        let day = release(2, kind: .manga, unit: 68, at: utc(2026, 11, 12), basis: .announced, precision: .day, source: "mangaupdates",
                          title: "Kagurabachi")
        let planned = plan([day, instant])
        #expect(planned.map(\.key.id) == [1], "an announced day notified")
        let first = try #require(planned.first)
        #expect(first.fireDate == utc(2026, 11, 7, 20, 30))
        #expect(first.body == "Episode 8 just aired.", "\(first.body)")
        #expect(first.title == "Frieren")
        #expect(first.userInfo["kuro_link"] == "kuro://anime/1")
    }

    @Test("copy follows spec §11.3 in EN and DE (episode, chapter, volume, no number)")
    func reminderCopy() throws {
        let episode = release(1, kind: .anime, at: utc(2026, 11, 7, 20, 30), basis: .confirmed, precision: .instant)
        let chapter = release(2, kind: .manga, unit: 68, at: utc(2026, 11, 8, 3), basis: .announced, precision: .instant, source: "mangadex")
        #expect(plan([episode], german: true).first?.body == "Folge 8 wurde gerade ausgestrahlt.")
        #expect(ReleaseReminderCopy.body(chapter, german: false) == "Chapter 68 is out.")
        #expect(ReleaseReminderCopy.body(chapter, german: true) == "Kapitel 68 ist erschienen.")
        let volume = ReleaseScheduleItem(medium: .manga, mediaId: 3, title: "T", unitKind: .volume, unitNumber: 12,
                                         releaseAt: utc(2026, 11, 9, 3), basis: .confirmed, confidence: nil, source: "publisher",
                                         precision: .instant)
        #expect(ReleaseReminderCopy.body(volume, german: false) == "Volume 12 is out.")
        #expect(ReleaseReminderCopy.body(volume, german: true) == "Band 12 ist erschienen.")
        let unnumbered = ReleaseScheduleItem(medium: .anime, mediaId: 1, title: "T", unitKind: .episode, unitNumber: nil,
                                             releaseAt: utc(2026, 11, 9, 3), basis: .confirmed, confidence: nil, source: "anilist",
                                             precision: .instant)
        #expect(ReleaseReminderCopy.body(unnumbered, german: false) == "A new episode just aired.")
        #expect(ReleaseReminderCopy.body(unnumbered, german: true) == "Eine neue Folge wurde gerade ausgestrahlt.")
    }

    @Test("only followed, unmuted titles; past moments skipped; two per title; at most 48, soonest first; stable ids")
    func followCapAndIds() {
        let unfollowed = release(99, kind: .anime, at: utc(2026, 11, 5, 12), basis: .confirmed, precision: .instant)
        let past = release(1, kind: .anime, at: now.addingTimeInterval(-3600), basis: .confirmed, precision: .instant)
        #expect(plan([unfollowed, past]).isEmpty)
        #expect(plan([release(1, kind: .anime, at: utc(2026, 11, 7, 20), basis: .confirmed, precision: .instant)],
                     muted: [MediaKey(kind: .anime, id: 1)]).isEmpty, "a muted title is silent")
        let many = (0..<100).map { n in
            release(2, kind: .manga, unit: Double(n), at: now.addingTimeInterval(Double(100 - n) * 3600), basis: .confirmed,
                    precision: .instant, source: "mangadex")
        }
        let perTitle = plan(many)
        #expect(perTitle.map(\.id) == ["release-manga-2-chapter-99", "release-manga-2-chapter-98"], "next two per title")
        let titles = (1...80).map { n in
            release(n, kind: .anime, at: now.addingTimeInterval(Double(n) * 3600), basis: .confirmed, precision: .instant)
        }
        let capped = ReleaseNotificationPlanner.plan(items: titles, following: Set(titles.map(\.key)), muted: [], now: now,
                                                     german: false, locale: english, timeZone: berlin)
        #expect(capped.count == ReleaseNotificationPlanner.planLimit)
        #expect(capped == capped.sorted { $0.fireDate < $1.fireDate })
        #expect(Set(capped.map(\.id)).count == capped.count)
        let anilist = release(1, kind: .anime, at: utc(2026, 11, 7, 20), basis: .confirmed, precision: .instant)
        #expect(ReleaseNotificationPlanner.identifier(anilist) == "release-anime-1-episode-8",
                "no plan id uses the retired airing- prefix")
    }

    @Test("notification links accept only a title journey")
    func linkValidation() {
        #expect(ReleaseNotificationLink.validatedURL(userInfo: ["kuro_link": "kuro://manga/2"], identifier: "x")?.absoluteString
                == "kuro://manga/2")
        #expect(ReleaseNotificationLink.validatedURL(userInfo: ["kuro_link": "kuro://auth/callback#access_token=x"], identifier: "x") == nil)
        #expect(ReleaseNotificationLink.validatedURL(userInfo: ["kuro_link": "https://evil.example/anime/2"], identifier: "x") == nil)
        #expect(ReleaseNotificationLink.validatedURL(userInfo: ["kuro_link": "kuro://anime/2?prompt=x"], identifier: "x") == nil)
        #expect(ReleaseNotificationLink.validatedURL(userInfo: [:], identifier: "airing-77-1h")?.absoluteString == "kuro://anime/77")
        #expect(ReleaseNotificationLink.validatedURL(userInfo: [:], identifier: "release-manga-2-chapter-5") == nil)
    }
}

// MARK: - Release notification commit (device side)

@MainActor
@Suite("Platform: release notifications on the device", .timeLimit(.minutes(1)))
struct ReleaseNotificationDeviceTests {
    private func followedHarness(permission: NotificationPermission) async throws -> PlatformHarness {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.manga, 2, rowId: 2, status: .current, progress: 60)], for: PlatformHarness.userA)
        let notifications = FakeNotificationCenter()
        notifications.permission = permission
        let h = try PlatformHarness(backend: backend, notifications: notifications)
        await h.signIn()
        seedSchedule(h, [release(2, kind: .manga, unit: 68, at: Date().addingTimeInterval(3 * 86_400), basis: .confirmed,
                                 precision: .instant, source: "mangadex", title: "Kagurabachi")])
        return h
    }

    @Test("nothing prompts automatically; the explicit toggle asks once, then schedules")
    func explicitPermission() async throws {
        let h = try await followedHarness(permission: .notDetermined)
        let releases = h.service.releases
        await releases.refreshReleaseNotifications()
        #expect(!releases.releaseNotificationsEnabled)
        #expect(await releases.syncReleaseNotificationsNow() == .notAuthorized)
        #expect(h.notifications.prompts == 0, "an automatic path prompted")
        h.notifications.promptAnswer = .authorized
        #expect(await releases.setReleaseNotificationsEnabled(true) == .enabled)
        #expect(h.notifications.prompts == 1)
        #expect(h.notifications.pending == ["release-manga-2-chapter-68"])
        #expect(h.notifications.userInfoById["release-manga-2-chapter-68"]?["kuro_link"] == "kuro://manga/2")
        await h.tearDown()
    }

    @Test("a declined prompt changes nothing; turning off removes every pending reminder")
    func declineAndOff() async throws {
        let h = try await followedHarness(permission: .notDetermined)
        let releases = h.service.releases
        h.notifications.promptAnswer = .denied
        #expect(await releases.setReleaseNotificationsEnabled(true) == .permissionDenied)
        #expect(h.notifications.pending.isEmpty)
        h.notifications.permission = .authorized
        #expect(await releases.setReleaseNotificationsEnabled(true) == .enabled)
        h.notifications.pending.append("airing-9-1h")
        #expect(await releases.setReleaseNotificationsEnabled(false) == .disabled)
        #expect(h.notifications.pending.isEmpty)
        // Off is remembered: the airing path schedules nothing either.
        let context = try #require(h.service.accountSession.current)
        #expect(await h.service.reminders.scheduleAiringNotifications(
            airing: .init(anime_id: 9, title_english: "X", title_romaji: nil, next_episode_number: 2,
                          next_airing_at: Date().addingTimeInterval(7200)), context: context) == .notAuthorized)
        await h.tearDown()
    }

    @Test("default off: an account that already allows notifications gets nothing until it turns them on")
    func defaultOff() async throws {
        let h = try await followedHarness(permission: .authorized)
        let releases = h.service.releases
        await releases.refreshReleaseNotifications()
        #expect(!releases.releaseNotificationsEnabled)
        #expect(!releases.releaseNotificationsOn(for: MediaKey(kind: .manga, id: 2)))
        #expect(h.notifications.pending.isEmpty)
        #expect(h.notifications.prompts == 0)
        await h.tearDown()
    }

    @Test("the detail bell is a per-title override: on asks once, schedules only that title, leaves the toggle off")
    func bellOverride() async throws {
        let h = try await followedHarness(permission: .notDetermined)
        let releases = h.service.releases
        let key = MediaKey(kind: .manga, id: 2)
        h.notifications.promptAnswer = .denied
        #expect(await releases.setReleaseNotification(true, for: key) == .permissionDenied)
        #expect(h.notifications.pending.isEmpty)
        h.notifications.promptAnswer = .authorized
        h.notifications.permission = .notDetermined
        #expect(await releases.setReleaseNotification(true, for: key) == .enabled)
        #expect(!releases.releaseNotificationsEnabled, "the bell turned the Profile toggle on")
        #expect(releases.releaseNotificationsOn(for: key))
        #expect(h.notifications.pending == ["release-manga-2-chapter-68"])
        #expect(await releases.setReleaseNotification(false, for: key) == .disabled)
        #expect(!releases.releaseNotificationsOn(for: key))
        #expect(h.notifications.pending.isEmpty, "the muted title's notification stayed pending")
        await h.tearDown()
    }

    @Test("the retired airing reminders are removed once on first run")
    func legacyAiringRetired() async throws {
        let h = try await followedHarness(permission: .authorized)
        h.notifications.pending = ["airing-1-start", "airing-1-1h", "other-x"]
        await h.service.releases.refreshReleaseNotifications()
        #expect(h.notifications.pending == ["other-x"])
        h.notifications.pending.append("airing-2-start")
        await h.service.releases.refreshReleaseNotifications()
        #expect(h.notifications.pending.contains("airing-2-start"), "the one-time cleanup ran twice")
        await h.tearDown()
    }

    @Test("the 64 budget counts device reminders Kuro does not own; stale release ids are removed")
    func budgetAndStale() async throws {
        let h = try await followedHarness(permission: .authorized)
        let context = try #require(h.service.accountSession.current)
        h.service.reminders.setReleaseNotificationPreference(true, for: context)
        h.notifications.pending = (0..<60).map { "other-\($0)" } + ["release-manga-2-chapter-1"]
        let plan = (0..<10).map { n in
            PlannedReleaseNotification(id: "release-manga-2-chapter-\(100 + n)", key: MediaKey(kind: .manga, id: 2),
                                       title: "T", body: "B", fireDate: Date().addingTimeInterval(Double(n + 1) * 3600), userInfo: [:])
        }
        #expect(await h.service.reminders.syncReleaseNotifications(plan, context: context) == .synced(scheduled: 4))
        #expect(h.notifications.pending.count == 64)
        #expect(!h.notifications.pending.contains("release-manga-2-chapter-1"), "a stale release id stays pending")
        await h.tearDown()
    }

    @Test("sign-out and an account switch remove the release notifications")
    func accountTransitionsClear() async throws {
        let h = try await followedHarness(permission: .authorized)
        let releases = h.service.releases
        #expect(await releases.setReleaseNotificationsEnabled(true) == .enabled)
        #expect(!h.notifications.pending.isEmpty)
        await h.signIn(PlatformHarness.userB)
        #expect(h.notifications.pending.isEmpty, "A's notifications survived the switch")
        #expect(!releases.releaseNotificationsEnabled, "A's toggle state leaked into B")
        await h.signIn(PlatformHarness.userA)
        seedSchedule(h, [release(2, kind: .manga, unit: 69, at: Date().addingTimeInterval(4 * 86_400), basis: .confirmed,
                                 precision: .instant, source: "mangadex")])
        await releases.refreshReleaseNotifications()
        #expect(releases.releaseNotificationsEnabled, "A's own choice is remembered for A")
        #expect(!h.notifications.pending.isEmpty)
        await h.service.session.endSession()
        #expect(h.notifications.pending.isEmpty, "notifications survived sign-out")
        await h.tearDown()
    }
}
