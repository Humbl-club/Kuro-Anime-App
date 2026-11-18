//
//  ReleaseAlertOfferTests.swift
//  KuroTests
//
//  W3a (tracker gaps): the release alert offer shown with the save confirmation. Pure policy and copy,
//  the owner that raises the offer from the Library sink with on-device release data only (no new
//  request), accept through the detail bell's call, decline memory, account isolation.
//

import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

/// A graph over a stub server (so request counts are observable) and a fake Library backend.
@MainActor
private struct AlertOfferHarness {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    let server: StubServer
    let backend: FakeLibraryBackend
    let notifications: FakeNotificationCenter
    let defaults: UserDefaults
    let service: AppGraph
    let suiteName: String

    /// `airing`: the `user_airing_next` rows the stub answers (anime id, episode, seconds ahead).
    init(suiteName: String? = nil, backend: FakeLibraryBackend = FakeLibraryBackend(),
         permission: NotificationPermission = .notDetermined,
         airing: [(id: Int, episode: Int, ahead: TimeInterval)] = [(501, 5, 2 * 86_400)],
         responder: StubServer.Responder? = nil) throws {
        server = StubServer()
        self.backend = backend
        let suite = suiteName ?? "kuro.tests.alert-offer.\(UUID().uuidString)"
        self.suiteName = suite
        defaults = try #require(UserDefaults(suiteName: suite))
        let center = FakeNotificationCenter()
        center.permission = permission
        notifications = center
        let rows = airing
        server.respond(with: responder ?? { request in
            guard request.resource == "user_airing_next" else { return .emptyArray }
            let formatter = ISO8601DateFormatter()
            let body = rows.map { row in
                #"{"anime_id":\#(row.id),"title_english":"Frieren","next_episode_number":\#(row.episode),"next_airing_at":"\#(formatter.string(from: Date().addingTimeInterval(row.ahead)))"}"#
            }.joined(separator: ",")
            return .json("[\(body)]")
        })
        service = AppComposition.testingGraph(
            testingUserDefaults: defaults, notificationCenter: center,
            client: StubSupabase.makeClient(server: server), libraryBackend: backend)
    }

    func signIn(_ userId: String = AlertOfferHarness.userA) async {
        await service.session.applySession(userId: userId, email: "\(userId)@example.com")
        await service.libraryActions.libraryRefreshTask?.value
    }

    var context: AccountContext? { service.accountSession.current }

    func requests(to resource: String) -> [RecordedRequest] { server.requests.filter { $0.resource == resource } }

    func tearDown() async {
        await service.session.endSession()
        defaults.removePersistentDomain(forName: suiteName)
        server.shutDown()
    }
}

@MainActor
@Suite("Release alert offer", .serialized, .timeLimit(.minutes(1)))
struct ReleaseAlertOfferTests {
    // MARK: Task 1: per-account memory

    @Test func offerMemoryIsPerAccountAndDeletedWithTheAccount() async throws {
        let h = try AlertOfferHarness()
        await h.signIn(AlertOfferHarness.userA)
        let reminders = h.service.reminders
        let a = try #require(h.context)
        for id in 1...3 { reminders.noteAlertDeclined(MediaKey(kind: .anime, id: id), for: a) }
        #expect(reminders.declinedAlertKeys(for: a).count == 3)
        for id in 1...501 { reminders.noteAlertOffered(MediaKey(kind: .anime, id: id), for: a) }
        #expect(reminders.offeredAlertKeys(for: a).count == ReminderScheduler.alertOfferMemory)
        #expect(!reminders.offeredAlertKeys(for: a).contains(MediaKey(kind: .anime, id: 1)), "the oldest key stayed")
        #expect(reminders.offeredAlertKeys(for: a).contains(MediaKey(kind: .anime, id: 501)))

        await h.signIn(AlertOfferHarness.userB)
        let b = try #require(h.context)
        #expect(reminders.declinedAlertKeys(for: b).isEmpty && reminders.offeredAlertKeys(for: b).isEmpty)
        // A note made with A's stale context while B is current changes nothing for either account.
        reminders.noteAlertDeclined(MediaKey(kind: .anime, id: 99_999), for: a)
        reminders.noteAlertOffered(MediaKey(kind: .anime, id: 99_999), for: a)
        #expect(reminders.declinedAlertKeys(for: b).isEmpty && reminders.offeredAlertKeys(for: b).isEmpty)
        #expect(reminders.declinedAlertKeys(for: a).count == 3)
        #expect(!reminders.offeredAlertKeys(for: a).contains(MediaKey(kind: .anime, id: 99_999)))

        let lowerA = AlertOfferHarness.userA.lowercased()
        #expect(h.defaults.object(forKey: "com.kuro.releaseNotifications.offered.\(lowerA)") != nil)
        #expect(h.defaults.object(forKey: "com.kuro.releaseNotifications.offerDeclined.\(lowerA)") != nil)
        reminders.removeReleaseNotificationPreferences(userId: AlertOfferHarness.userA)
        #expect(h.defaults.object(forKey: "com.kuro.releaseNotifications.offered.\(lowerA)") == nil)
        #expect(h.defaults.object(forKey: "com.kuro.releaseNotifications.offerDeclined.\(lowerA)") == nil)
        await h.tearDown()
    }

    // MARK: Task 2: pure policy and copy

    nonisolated static let now = Date(timeIntervalSince1970: 1_793_707_200)
    nonisolated static let key = MediaKey(kind: .anime, id: 501)

    nonisolated static func row(_ unitKind: ReleaseUnitKind = .episode, number: Double? = 5, at: Date? = now.addingTimeInterval(3 * 86_400),
                    basis: ReleaseBasis = .confirmed, precision: ReleasePrecision? = .instant,
                    kind: MediaKind = .anime, id: Int = 501, confidence: Double? = nil, isPast: Bool = false) -> ReleaseScheduleItem {
        ReleaseScheduleItem(medium: kind, mediaId: id, title: "Frieren", unitKind: unitKind, unitNumber: number, releaseAt: at,
                            basis: basis, confidence: confidence, source: "anilist", isPast: isPast, precision: precision)
    }

    nonisolated static func base(next: ReleaseScheduleItem? = row()) -> ReleaseAlertOfferPolicy.Input {
        .init(previousStatus: nil, status: .current, next: next, toggleOn: false, permission: .notDetermined,
              allowed: [], muted: [], offered: [], declined: [], suppressed: false)
    }

    @Test func noOfferForEstimatesDaysOrFinishedTitles() {
        let now = Self.now, key = Self.key
        func offers(_ input: ReleaseAlertOfferPolicy.Input) -> Bool { ReleaseAlertOfferPolicy.shouldOffer(input, key: key, now: now) }
        #expect(offers(Self.base()), "control")
        #expect(!offers(Self.base(next: Self.row(basis: .estimated, precision: .instant, confidence: 0.9))))
        #expect(!offers(Self.base(next: Self.row(basis: .announced, precision: .day))))
        #expect(!offers(Self.base(next: Self.row(basis: .announced, precision: .month))))
        #expect(!offers(Self.base(next: Self.row(at: now.addingTimeInterval(-60), isPast: true))))
        #expect(!offers(Self.base(next: Self.row(at: now.addingTimeInterval(30)))), "under the 60 s minimum lead")
        #expect(!offers(Self.base(next: nil)))
        #expect(!offers(Self.base(next: Self.row(id: 502))), "another title's row")
        var finished = Self.base()
        finished.status = .completed
        #expect(!offers(finished))
        finished.status = .dropped
        #expect(!offers(finished))
    }

    @Test func noOfferForPlanningOrUntrackedStatuses() {
        let now = Self.now, key = Self.key
        func offers(prev: ListStatus?, _ status: ListStatus?) -> Bool {
            var input = Self.base()
            input.previousStatus = prev
            input.status = status
            return ReleaseAlertOfferPolicy.shouldOffer(input, key: key, now: now)
        }
        #expect(!offers(prev: nil, .planning))
        #expect(!offers(prev: nil, .paused))
        #expect(!offers(prev: nil, nil))
        #expect(offers(prev: nil, .repeating))
        #expect(!offers(prev: .current, .current), "an edit of an already watched title")
        #expect(offers(prev: .planning, .current))
    }

    @Test func noOfferWhenPermissionDenied() {
        var input = Self.base()
        input.permission = .denied
        #expect(!ReleaseAlertOfferPolicy.shouldOffer(input, key: Self.key, now: Self.now))
        input.permission = .authorized
        #expect(ReleaseAlertOfferPolicy.shouldOffer(input, key: Self.key, now: Self.now))
        input.permission = .notDetermined
        #expect(ReleaseAlertOfferPolicy.shouldOffer(input, key: Self.key, now: Self.now))
    }

    @Test func overridesToggleDeclinesAndSuppressionStopTheOffer() {
        let now = Self.now, key = Self.key
        func offers(_ change: (inout ReleaseAlertOfferPolicy.Input) -> Void) -> Bool {
            var input = Self.base()
            change(&input)
            return ReleaseAlertOfferPolicy.shouldOffer(input, key: key, now: now)
        }
        let others: [MediaKey] = [MediaKey(kind: .anime, id: 1), MediaKey(kind: .anime, id: 2), MediaKey(kind: .anime, id: 3)]
        #expect(!offers { $0.toggleOn = true })
        #expect(!offers { $0.allowed = [key] })
        #expect(!offers { $0.muted = [key] })
        #expect(!offers { $0.offered = [key] })
        #expect(offers { $0.declined = Set(others.prefix(2)) })
        #expect(!offers { $0.declined = Set(others) })
        #expect(!offers { $0.suppressed = true })
    }

    @Test func offerImpliesPlannerWouldNotify() {
        let now = Self.now
        let units: [ReleaseUnitKind] = [.episode, .chapter, .volume, .season]
        let bases: [ReleaseBasis] = [.confirmed, .announced, .estimated]
        let precisions: [ReleasePrecision?] = [.instant, .day, .month, nil]
        let leads: [TimeInterval] = [-3_600, 30, 90, 7_200, 3 * 86_400]
        var offered = 0, combos = 0
        for unit in units { for basis in bases { for precision in precisions { for lead in leads {
            combos += 1
            let item = Self.row(unit, number: 7, at: now.addingTimeInterval(lead), basis: basis, precision: precision, confidence: 0.9)
            let input = Self.base(next: item)
            guard ReleaseAlertOfferPolicy.shouldOffer(input, key: Self.key, now: now) else { continue }
            offered += 1
            let plan = ReleaseNotificationPlanner.plan(
                items: [item], following: [Self.key], muted: [], now: now, german: false,
                locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC") ?? .current)
            #expect(plan.count == 1, "offered but the planner would not notify: \(item)")
        } } } }
        #expect(combos >= 40 && offered > 0, "\(combos) combinations, \(offered) offered")
    }

    @Test func promptCopyIsEnglishAndGerman() {
        #expect(ReleaseAlertOfferCopy.prompt(Self.row(), german: false) == "Notify me when episode 5 airs")
        #expect(ReleaseAlertOfferCopy.prompt(Self.row(), german: true) == "Benachrichtigen, wenn Folge 5 läuft")
        let chapter = Self.row(.chapter, number: 120, kind: .manga, id: 2)
        #expect(ReleaseAlertOfferCopy.prompt(chapter, german: false) == "Notify me when chapter 120 is out")
        #expect(ReleaseAlertOfferCopy.prompt(chapter, german: true) == "Benachrichtigen, wenn Kapitel 120 erscheint")
        let volume = Self.row(.volume, number: 3, kind: .manga, id: 2)
        #expect(ReleaseAlertOfferCopy.prompt(volume, german: false) == "Notify me when volume 3 is out")
        #expect(ReleaseAlertOfferCopy.prompt(volume, german: true) == "Benachrichtigen, wenn Band 3 erscheint")
        let none = Self.row(.episode, number: nil)
        #expect(ReleaseAlertOfferCopy.prompt(none, german: false) == "Notify me when the next episode airs")
        #expect(ReleaseAlertOfferCopy.prompt(none, german: true) == "Benachrichtigen, wenn die nächste Folge läuft")
        #expect(ReleaseAlertOfferCopy.notifyMe(german: true) == "Benachrichtigen" && ReleaseAlertOfferCopy.notNow(german: true) == "Nicht jetzt")
        #expect(ReleaseAlertOfferCopy.saved(german: false) == "Saved." && ReleaseAlertOfferCopy.saved(german: true) == "Gespeichert.")
    }

    @Test func unseenOfferLapsesWithoutCountingAsOffered() {
        let t = Self.now
        let offer = ReleaseAlertOffer(id: UUID(), key: Self.key, item: Self.row(), accountUserId: "a", createdAt: t)
        #expect(!ReleaseAlertOfferPolicy.hasLapsed(offer, boundHost: nil, now: t.addingTimeInterval(29)))
        #expect(ReleaseAlertOfferPolicy.hasLapsed(offer, boundHost: nil, now: t.addingTimeInterval(31)))
        #expect(!ReleaseAlertOfferPolicy.hasLapsed(offer, boundHost: UUID(), now: t.addingTimeInterval(300)))
    }
}
