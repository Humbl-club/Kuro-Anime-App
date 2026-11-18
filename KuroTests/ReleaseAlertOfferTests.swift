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
import SwiftUI
import Testing
import UIKit
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

    /// One save through the Library, then the follow-up work the sink started.
    @discardableResult
    func save(_ id: Int, kind: MediaKind = .anime, status: ListStatus = .current) async -> Bool {
        let outcome = await service.libraryActions.apply(LibraryEdit(status: .set(status)),
                                                         to: MediaKey(kind: kind, id: id), createIfMissing: status)
        await service.releases.libraryChangeTask?.value
        await service.releases.alertOfferTask?.value
        return outcome.error == nil
    }

    /// A `media_release_schedule_v1` answer with one exact confirmed episode.
    static func mediaScheduleResponder(id: Int, episode: Int = 5, ahead: TimeInterval = 2 * 86_400) -> StubServer.Responder {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(ahead))
        return { request in
            guard request.resource == "rpc/media_release_schedule_v1" else { return .emptyArray }
            return .json(#"[{"medium":"anime","media_id":\#(id),"title":"Frieren","unit_kind":"episode","unit_number":\#(episode),"release_at":"\#(at)","basis":"confirmed","source":"anilist","release_precision":"instant"}]"#)
        }
    }

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

    // MARK: Task 3: the owner raises the offer after a save (no new request)

    @Test func offerShownAfterSavingAiringTitleWithExactNextRelease() async throws {
        let h = try AlertOfferHarness(responder: AlertOfferHarness.mediaScheduleResponder(id: 501))
        await h.signIn()
        let releases = h.service.releases
        // The detail page left the media-schedule cache; user_airing_next answers [] here, so only the cache can know.
        #expect(await releases.mediaSchedule(kind: .anime, id: 501).count == 1)
        #expect(await h.save(501))
        let offer = try #require(releases.pendingAlertOffer)
        #expect(offer.key == MediaKey(kind: .anime, id: 501))
        #expect(ReleaseAlertOfferCopy.prompt(offer.item, german: false) == "Notify me when episode 5 airs")
        #expect(h.notifications.authorizationRequests == 0)
        await h.tearDown()
    }

    @Test func offerAppearsAfterExistingUpcomingRefresh() async throws {
        let h = try AlertOfferHarness()
        await h.signIn()
        let before = h.server.requests.count
        #expect(await h.save(501))
        let releases = h.service.releases
        #expect(releases.pendingAlertOffer?.key == MediaKey(kind: .anime, id: 501))
        let sent = h.server.requests.dropFirst(before).compactMap(\.resource)
        #expect(sent.sorted() == ["rpc/collection_feed_page", "user_airing_next"], "the save sent \(sent)")
        await h.tearDown()

        // A title the stub has no airing for: no offer, the same pre-existing requests (the Collection sink's feed
        // page and the one upcoming read); the offer adds none.
        let other = try AlertOfferHarness(airing: [(999, 1, 86_400)])
        await other.signIn()
        let otherBefore = other.server.requests.count
        #expect(await other.save(501))
        #expect(other.service.releases.pendingAlertOffer == nil)
        let otherSent = other.server.requests.dropFirst(otherBefore).compactMap(\.resource)
        #expect(otherSent.sorted() == ["rpc/collection_feed_page", "user_airing_next"], "the save sent \(otherSent)")
        await other.tearDown()
    }

    @Test func mangaReadingTitleWithExactChapterTimeOffers() async throws {
        let h = try AlertOfferHarness()
        await h.signIn()
        let releases = h.service.releases
        releases.schedule = [ReleaseScheduleItem(medium: .manga, mediaId: 2, title: "Kagurabachi", unitKind: .chapter, unitNumber: 68,
                                                 releaseAt: Date().addingTimeInterval(3 * 86_400), basis: .confirmed, source: "mangadex",
                                                 precision: .instant)]
        releases.scheduleCoverageByMedium = [.anime: .complete, .manga: .complete]
        #expect(await h.save(2, kind: .manga))
        #expect(releases.pendingAlertOffer?.key == MediaKey(kind: .manga, id: 2))
        await h.tearDown()
    }

    @Test func noOfferForRefreshImportOrBatch() async throws {
        let backend = FakeLibraryBackend()
        backend.setRows([FakeLibraryBackend.entry(.anime, 504, rowId: 504, status: .planning, progress: 0)], for: AlertOfferHarness.userA)
        let h = try AlertOfferHarness(backend: backend, airing: [(501, 5, 2 * 86_400), (502, 3, 2 * 86_400), (503, 7, 2 * 86_400), (504, 1, 2 * 86_400)])
        await h.signIn()
        let releases = h.service.releases
        let context = try #require(h.context)
        // A server-side change (realtime / import / launch) re-reads the Library and never calls the sinks.
        backend.setRows([FakeLibraryBackend.entry(.anime, 501, rowId: 501, status: .current, progress: 1),
                         FakeLibraryBackend.entry(.anime, 504, rowId: 504, status: .planning, progress: 0)],
                        for: AlertOfferHarness.userA)
        await h.service.libraryActions.libraryChangedServerSide(for: context).value
        await releases.alertOfferTask?.value
        #expect(releases.pendingAlertOffer == nil)
        // A batch (Folio) runs suppressed.
        await releases.withAlertOffersSuppressed {
            _ = await h.save(502)
            _ = await h.save(503)
        }
        #expect(releases.pendingAlertOffer == nil)
        // The widget's queued +1 on a planning entry runs suppressed too.
        let advanced = await h.service.libraryActions.advanceQueuedProgress(MediaKey(kind: .anime, id: 504), to: 1, lifecycleId: nil, cap: nil)
        await releases.alertOfferTask?.value
        #expect(advanced == .applied)
        #expect(releases.pendingAlertOffer == nil)
        // A plain save afterwards (suppression ended) offers. 502 was suppressed, so it is still unoffered.
        #expect(await h.save(502, status: .paused))
        releases.pendingAlertOffer = nil
        #expect(await h.save(502, status: .current))
        #expect(releases.pendingAlertOffer?.key == MediaKey(kind: .anime, id: 502))
        await h.tearDown()
    }

    @Test func offerShownOncePerTitle() async throws {
        let suite = "kuro.tests.alert-offer.once.\(UUID().uuidString)"
        let h = try AlertOfferHarness(suiteName: suite)
        await h.signIn()
        let releases = h.service.releases
        #expect(await h.save(501))
        let offer = try #require(releases.pendingAlertOffer)
        let host = UUID()
        releases.alertOfferPresented(offer.id, by: host)
        releases.expireAlertOffer(offer.id, by: UUID())
        #expect(releases.pendingAlertOffer?.id == offer.id, "a host that is not bound expired the offer")
        releases.expireAlertOffer(offer.id, by: host)
        #expect(releases.pendingAlertOffer == nil)
        let context = try #require(h.context)
        #expect(h.service.reminders.declinedAlertKeys(for: context).isEmpty, "an expired hold counted as a decline")
        #expect(h.service.reminders.offeredAlertKeys(for: context) == [MediaKey(kind: .anime, id: 501)])
        // Paused, then Watching again: no second offer (offered memory).
        #expect(await h.save(501, status: .paused))
        #expect(await h.save(501, status: .current))
        #expect(releases.pendingAlertOffer == nil)
        // A relaunch over the same defaults keeps the memory.
        let relaunched = try AlertOfferHarness(suiteName: suite)
        await relaunched.signIn()
        #expect(await relaunched.save(501))
        #expect(relaunched.service.releases.pendingAlertOffer == nil)
        await relaunched.tearDown()
        await h.tearDown()
    }

    // MARK: Task 4: accept through the bell, decline, account isolation

    /// Answers the account schedule and the upcoming read with one exact episode per id (2 days ahead).
    private static func scheduleResponder(ids: [Int]) -> StubServer.Responder {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86_400))
        return { request in
            switch request.resource {
            case "rpc/user_release_schedule_v1":
                let rows = ids.map { #"{"medium":"anime","media_id":\#($0),"title":"Frieren","unit_kind":"episode","unit_number":5,"release_at":"\#(at)","basis":"confirmed","source":"anilist","release_precision":"instant"}"# }
                return .json("[\(rows.joined(separator: ","))]")
            case "user_airing_next":
                let rows = ids.map { #"{"anime_id":\#($0),"title_english":"Frieren","next_episode_number":5,"next_airing_at":"\#(at)"}"# }
                return .json("[\(rows.joined(separator: ","))]")
            default: return .emptyArray
            }
        }
    }

    @Test func notifyMeUsesBellToggleOnly() async throws {
        let h = try AlertOfferHarness(responder: Self.scheduleResponder(ids: [501]))
        await h.signIn()
        let releases = h.service.releases
        // setReleaseNotification loads the account schedule only while coverage is empty, and the planner reads
        // `schedule`, not the media cache or upcomingAirings: so coverage must be empty here and the stub answers it.
        #expect(releases.scheduleCoverageByMedium.isEmpty)
        #expect(await h.save(501))
        let offer = try #require(releases.pendingAlertOffer)
        #expect(h.notifications.authorizationRequests == 0)
        h.notifications.promptAnswer = .authorized
        let result = await releases.acceptAlertOffer(offer.id)
        #expect(result == .enabled)
        #expect(h.notifications.authorizationRequests == 1)
        #expect(h.notifications.prompts == 1)
        #expect(releases.allowedReleaseNotificationKeys == [MediaKey(kind: .anime, id: 501)])
        #expect(!releases.releaseNotificationsEnabled)
        let context = try #require(h.context)
        #expect(h.service.reminders.releaseNotificationPreference(for: context) == nil, "the Profile toggle was touched")
        #expect(releases.pendingAlertOffer == nil)
        #expect(h.notifications.pending == ["release-anime-501-episode-5"])
        #expect(await releases.acceptAlertOffer(offer.id) == nil)
        #expect(h.notifications.authorizationRequests == 1)
        await h.tearDown()
    }

    @Test func threeDeclinesStopOffersForTheAccount() async throws {
        let h = try AlertOfferHarness(responder: Self.scheduleResponder(ids: [501, 502, 503, 504]))
        await h.signIn()
        let releases = h.service.releases
        for id in [501, 502, 503] {
            #expect(await h.save(id))
            let offer = try #require(releases.pendingAlertOffer, "no offer for \(id)")
            #expect(offer.key == MediaKey(kind: .anime, id: id))
            releases.declineAlertOffer(offer.id)
            #expect(releases.pendingAlertOffer == nil)
        }
        let context = try #require(h.context)
        #expect(h.service.reminders.declinedAlertKeys(for: context).count == 3)
        #expect(await h.save(504))
        #expect(releases.pendingAlertOffer == nil)
        h.notifications.promptAnswer = .authorized
        #expect(await releases.setReleaseNotificationsEnabled(true) == .enabled, "the Profile toggle stopped working")
        await h.tearDown()
    }

    @Test func offerStateIsClearedOnAccountSwitch() async throws {
        let h = try AlertOfferHarness(responder: Self.scheduleResponder(ids: [501, 502, 503, 504, 506]))
        await h.signIn(AlertOfferHarness.userA)
        let releases = h.service.releases
        for id in [501, 502, 503] {
            #expect(await h.save(id))
            releases.declineAlertOffer(try #require(releases.pendingAlertOffer).id)
        }
        let contextA = try #require(h.context)
        await h.signIn(AlertOfferHarness.userB)
        #expect(await h.save(504))
        let offer = try #require(releases.pendingAlertOffer, "account B has no offer although B declined nothing")
        #expect(offer.key == MediaKey(kind: .anime, id: 504))
        let staleId = offer.id
        await h.signIn(AlertOfferHarness.userA)
        #expect(releases.pendingAlertOffer == nil)
        #expect(await releases.acceptAlertOffer(staleId) == nil)
        #expect(h.notifications.authorizationRequests == 0)
        let current = try #require(h.context)
        #expect(current.userId.lowercased() == contextA.userId.lowercased())
        #expect(h.service.reminders.allowedReleaseNotificationKeys(for: current).isEmpty)
        #expect(await h.save(506))
        #expect(releases.pendingAlertOffer == nil, "A's three declines did not survive the switch")
        await h.tearDown()
    }

    // MARK: Task 5: one slot, drawn by the visible page only

    @Test func slotPolicyFollowsPagerSelectionAndTopmostLayer() {
        let journey = ObjectIdentifier(JourneyNavigator(root: .media(MediaRoute(kind: .anime, id: 501))))
        let taste = OfferHost(id: UUID(), section: .taste, layer: .pager)
        let discover = OfferHost(id: UUID(), section: .discover, layer: .pager)
        let collection = OfferHost(id: UUID(), section: .collection, layer: .pager)
        let detail = OfferHost(id: UUID(), section: nil, layer: .journey(journey, top: "media:anime:501"))
        let under = OfferHost(id: UUID(), section: nil, layer: .journey(journey, top: "media:anime:7"))
        let hosts = [taste, discover, collection, detail, under]
        typealias Policy = ReleaseAlertOfferSlotPolicy
        #expect(Policy.presenter(selectedSection: .discover, topmostLayer: .pager, hosts: hosts) == discover.id,
                "attach order decided (collection attached last)")
        #expect(Policy.presenter(selectedSection: .collection, topmostLayer: .pager, hosts: hosts) == collection.id)
        #expect(Policy.presenter(selectedSection: .clubs, topmostLayer: .pager, hosts: hosts) == nil)
        #expect(Policy.presenter(selectedSection: nil, topmostLayer: .pager, hosts: hosts) == nil)
        #expect(Policy.presenter(selectedSection: .discover, topmostLayer: .journey(journey, top: "media:anime:501"), hosts: hosts) == detail.id)
        #expect(Policy.presenter(selectedSection: .discover, topmostLayer: .journey(journey, top: "media:anime:9"), hosts: hosts) == nil)
        #expect(Policy.presenter(selectedSection: .discover, topmostLayer: .blocked, hosts: hosts) == nil)
    }

    @Test func topmostLayerFollowsTheRootCoordinator() async throws {
        let navigation = KuroNavigationCoordinator(dismissalDelay: .zero)
        #expect(navigation.offerTopmostLayer == .pager)

        navigation.collapseThenOpen(.media(MediaRoute(kind: .anime, id: 501)))
        try await Task.sleep(for: .milliseconds(50))
        let root = try #require(navigation.journey)
        #expect(navigation.offerTopmostLayer == .journey(ObjectIdentifier(root), top: "media:anime:501"))
        root.tool = .addToClub(MediaKey(kind: .anime, id: 501))
        #expect(navigation.offerTopmostLayer == .blocked)
        root.tool = nil
        #expect(navigation.offerTopmostLayer == .journey(ObjectIdentifier(root), top: "media:anime:501"))

        // A header sheet with a journey: blocked while the root journey is also open, its own top page otherwise.
        let revision = navigation.layerRevision
        navigation.registerLayer("search#1", kind: .sheet, isPresented: { true }, close: {})
        #expect(navigation.layerRevision > revision)
        let searchJourney = JourneyNavigator(root: ShellJourneyPages.search())
        navigation.attachJourney(searchJourney, toLayer: "search")
        #expect(navigation.offerTopmostLayer == .blocked, "two page-level presentations: never guess")
        navigation.slot.presented = nil
        #expect(navigation.offerTopmostLayer == .journey(ObjectIdentifier(searchJourney), top: "custom:search"))
        navigation.unregisterLayer("search#1")

        // A page-level sheet without a journey, and a cover, block.
        navigation.registerLayer("collection.import#1", kind: .sheet, isPresented: { true }, close: {})
        #expect(navigation.offerTopmostLayer == .blocked)
        navigation.unregisterLayer("collection.import#1")
        navigation.registerLayer("onboarding#1", kind: .cover, isPresented: { true }, close: {})
        #expect(navigation.offerTopmostLayer == .blocked)
        let before = navigation.layerRevision
        navigation.layerDidChange()
        navigation.unregisterLayer("onboarding#1")
        #expect(navigation.layerRevision >= before + 2)
        #expect(navigation.offerTopmostLayer == .pager)
    }

    @Test func offerFollowsTheVisiblePageNotAttachOrder() async throws {
        let h = try AlertOfferHarness(airing: [(501, 5, 2 * 86_400), (502, 3, 2 * 86_400), (503, 7, 2 * 86_400)])
        await h.signIn()
        let releases = h.service.releases
        let navigation = KuroNavigationCoordinator(dismissalDelay: .zero)
        navigation.pagerSelection = .discover
        let home = UUID(), discover = UUID(), collection = UUID()
        // The pager mounts the selected page +- 1 and every visited page; Collection attached last.
        navigation.attachOfferHost(OfferHost(id: home, section: .home, layer: .pager))
        navigation.attachOfferHost(OfferHost(id: discover, section: .discover, layer: .pager))
        navigation.attachOfferHost(OfferHost(id: collection, section: .collection, layer: .pager))
        #expect(navigation.offerHosts.count >= 2)

        #expect(await h.save(501))
        #expect(navigation.isOfferPresenter(discover))
        #expect(!navigation.isOfferPresenter(home) && !navigation.isOfferPresenter(collection))
        for host in [home, discover, collection] where navigation.isOfferPresenter(host) {
            if let offer = releases.alertOffer(forPresenter: host) { releases.alertOfferPresented(offer.id, by: host) }
        }
        let context = try #require(h.context)
        #expect(h.service.reminders.offeredAlertKeys(for: context) == [MediaKey(kind: .anime, id: 501)])
        #expect(releases.alertOffer(forPresenter: home) == nil, "an offer bound to Discover was handed to another host")
        #expect(releases.alertOffer(forPresenter: discover) != nil)

        // Nobody can draw an offer for 31 s (Clubs has no host): it lapses, counted as neither offered nor declined.
        navigation.pagerSelection = .clubs
        #expect(await h.save(502))
        let second = try #require(releases.pendingAlertOffer)
        #expect(second.key == MediaKey(kind: .anime, id: 502))
        let later = Date().addingTimeInterval(31)
        for host in [home, discover, collection] { #expect(releases.alertOffer(forPresenter: host, now: later) == nil) }
        #expect(releases.pendingAlertOffer == nil)
        #expect(!h.service.reminders.offeredAlertKeys(for: context).contains(MediaKey(kind: .anime, id: 502)))
        #expect(h.service.reminders.declinedAlertKeys(for: context).isEmpty)

        // A journey over the pager hides every pager host and an unbound host cannot expire the offer.
        navigation.pagerSelection = .discover
        #expect(await h.save(503))
        let third = try #require(releases.pendingAlertOffer)
        navigation.collapseThenOpen(.media(MediaRoute(kind: .anime, id: 7)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!navigation.isOfferPresenter(discover) && !navigation.isOfferPresenter(home) && !navigation.isOfferPresenter(collection))
        releases.expireAlertOffer(third.id, by: discover)
        #expect(releases.pendingAlertOffer?.id == third.id)
        await h.tearDown()
    }

    @Test func offerRowFitsGermanAtLargestCappedType() throws {
        let row = ReleaseAlertOfferRow(prompt: ReleaseAlertOfferCopy.prompt(Self.row(number: 12), german: true),
                                       leadsWithSaved: true, german: true, onNotify: {}, onNotNow: {})
        let host = UIHostingController(rootView: row.dynamicTypeSize(.accessibility3).frame(width: 320))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 900)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        let size = host.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        #expect(size.width <= 320, "the row is wider than the screen: \(size)")
        #expect(size.height > 88, "both buttons and the text stack: \(size)")
        // Prompt and both buttons are real text, never an ellipsis.
        #expect(ReleaseAlertOfferCopy.notifyMe(german: true) == "Benachrichtigen" && ReleaseAlertOfferCopy.notNow(german: true) == "Nicht jetzt")
        window.isHidden = true
        window.rootViewController = nil
    }
}
