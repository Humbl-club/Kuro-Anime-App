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
}
