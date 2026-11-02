//
//  ClubsLaneTests.swift
//  KuroTests
//
//  Clubs production pass (2026-11-01):
//  - the my-clubs read: honest phase, function-missing-only fallback, the page's staleness window
//    (revisits do not refetch) and its account scope;
//  - the pure list/detail rules the club views render from (a failed or offline read never shows
//    the "create your first club" invitation; membership answers are not failures with Retry);
//  - invite codes keep their case (the server compares exactly) and are found in pasted links;
//  - EN/DE copy never shows a server code; reactions keep their server keys.
//

import Testing
import Foundation
import KuroCore
import Supabase
import Synchronization
@testable import Kuro

// MARK: - Store: my-clubs read

@MainActor
@Suite("Clubs lane: my-clubs read", .timeLimit(.minutes(1)))
struct ClubsLaneStoreTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    @Test("PGRST202 (function missing) falls back to fetch_my_clubs_enriched exactly once and publishes its rows")
    func functionMissingFallsBackOnce() async throws {
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_my_clubs_loading":
                return ClubJSON.error(message: "Could not find the function", code: "PGRST202", status: 404)
            case "rpc/fetch_my_clubs_enriched":
                return ClubJSON.myClubs(["club-old"])
            default:
                return .emptyArray
            }
        }
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await harness.clubs.fetchMyClubs()
        #expect(harness.requests(to: "rpc/fetch_my_clubs_enriched").count == 1)
        #expect(harness.clubs.myClubs.map(\.id) == ["club-old"])
        if case .loaded = harness.clubs.myClubsPhase {} else {
            Issue.record("phase \(harness.clubs.myClubsPhase) is not loaded")
        }
        await harness.tearDown()
    }

    @Test("A server error or a transport failure never asks fetch_my_clubs_enriched, keeps the rows and records the failure")
    func otherFailuresDoNotFallBack() async throws {
        let calls = Mutex(0)
        let harness = try ClubsHarness { request in
            switch request.resource {
            case "rpc/fetch_my_clubs_loading":
                let n = calls.withLock { $0 += 1; return $0 }
                switch n {
                case 1: return ClubJSON.myClubs(["club-1"])
                case 2: return ClubJSON.error(message: "boom", code: "XX000", status: 500)
                case 3: return .failure(.notConnectedToInternet)
                default: return .failure(.timedOut)
                }
            case "rpc/fetch_my_clubs_enriched":
                return ClubJSON.myClubs(["club-wrong"])
            default:
                return .emptyArray
            }
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await clubs.fetchMyClubs()
        #expect(clubs.myClubs.map(\.id) == ["club-1"])

        await clubs.fetchMyClubs()
        #expect(clubs.myClubsPhase == .failed(transport: false))
        #expect(clubs.myClubs.map(\.id) == ["club-1"], "a failed read dropped the rows on screen")

        await clubs.fetchMyClubs()
        #expect(clubs.myClubsPhase == .failed(transport: true))
        #expect(clubs.myClubs.map(\.id) == ["club-1"])

        // A timeout while online is a failure, not "offline".
        await clubs.fetchMyClubs()
        #expect(clubs.myClubsPhase == .failed(transport: false))

        #expect(harness.requests(to: "rpc/fetch_my_clubs_enriched").isEmpty, "a non-missing-function failure fell back")
        await harness.tearDown()
    }

    @Test("refreshMyClubsIfStale: no request inside the window, a request after it, and a request for the next account")
    func stalenessWindowAndAccountScope() async throws {
        let harness = try ClubsHarness { request in
            request.resource == "rpc/fetch_my_clubs_loading" ? ClubJSON.myClubs(["club-1"]) : .emptyArray
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await clubs.refreshMyClubsIfStale()
        #expect(harness.requests(to: "rpc/fetch_my_clubs_loading").count == 1)

        // A revisit a moment later reuses what is on screen.
        await clubs.refreshMyClubsIfStale()
        await clubs.refreshMyClubsIfStale(now: Date().addingTimeInterval(ClubsStore.myClubsStaleness - 5))
        #expect(harness.requests(to: "rpc/fetch_my_clubs_loading").count == 1, "a page revisit inside the window refetched")

        // After the window: one fresh read.
        await clubs.refreshMyClubsIfStale(now: Date().addingTimeInterval(ClubsStore.myClubsStaleness + 5))
        #expect(harness.requests(to: "rpc/fetch_my_clubs_loading").count == 2)

        // The next account never inherits A's freshness.
        await harness.service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(clubs.myClubsPhase == .idle)
        #expect(clubs.myClubs.isEmpty)
        await clubs.refreshMyClubsIfStale()
        #expect(harness.requests(to: "rpc/fetch_my_clubs_loading").count == 3)
        await harness.tearDown()
    }

    @Test("A read answered after a disclosure reset never restores the old phase: the list keeps loading, never the invitation, until the reload answers")
    func supersededReadTouchesNothing() async throws {
        let gateA = StubGate()
        let gateB = StubGate()
        let calls = Mutex(0)
        let (reload, reloadArrived) = AsyncStream<Void>.makeStream()
        let (readAStream, readAArrived) = AsyncStream<Void>.makeStream()
        let harness = try ClubsHarness { request in
            guard request.resource == "rpc/fetch_my_clubs_loading" else { return .emptyArray }
            switch calls.withLock({ $0 += 1; return $0 }) {
            case 1: return ClubJSON.myClubs(["club-1"])
            case 2:
                readAArrived.yield()
                return ClubJSON.myClubs(["club-1"]).held(by: gateA)
            default:
                reloadArrived.yield()
                return ClubJSON.myClubs(["club-1"]).held(by: gateB)
            }
        }
        let clubs = harness.clubs
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await clubs.fetchMyClubs()
        #expect(clubs.myClubs.map(\.id) == ["club-1"])

        // Read A is in flight when a disclosure signal drops the rows and schedules the reload B.
        let readA = Task.immediate { @MainActor in await clubs.fetchMyClubs() }
        var readAArrivals = readAStream.makeAsyncIterator()
        _ = await readAArrivals.next()
        clubs.invalidateSharedDisclosure()
        var arrivals = reload.makeAsyncIterator()
        _ = await arrivals.next()

        gateA.open()
        await readA.value
        #expect(clubs.myClubsPhase.isLoading, "A restored a phase it no longer owns: \(clubs.myClubsPhase)")
        #expect(clubs.myClubs.isEmpty)
        #expect(ClubsListRules.state(phase: clubs.myClubsPhase, hasClubs: !clubs.myClubs.isEmpty, isConnected: true) == .loading)

        gateB.open()
        await clubs.disclosureReloadTask?.value
        #expect(clubs.myClubs.map(\.id) == ["club-1"])
        if case .loaded = clubs.myClubsPhase {} else { Issue.record("reload did not publish: \(clubs.myClubsPhase)") }
        await harness.tearDown()
    }

    @Test("fetchMyClubs always asks the server (writes and the disclosure reload rely on it)")
    func explicitFetchIgnoresWindow() async throws {
        let harness = try ClubsHarness { request in
            request.resource == "rpc/fetch_my_clubs_loading" ? ClubJSON.myClubs(["club-1"]) : .emptyArray
        }
        await harness.service.session.applySession(userId: Self.userA, email: "a@example.com")
        await harness.clubs.fetchMyClubs()
        await harness.clubs.fetchMyClubs()
        #expect(harness.requests(to: "rpc/fetch_my_clubs_loading").count == 2)
        await harness.tearDown()
    }
}

// MARK: - Pure rules

@Suite("Clubs lane: pure rules")
struct ClubsLaneRuleTests {
    // MARK: List states

    @Test("A failed or offline read with no clubs never shows the invitation")
    func failureIsNeverEmpty() {
        for connected in [true, false] {
            for transport in [true, false] {
                let state = ClubsListRules.state(phase: .failed(transport: transport), hasClubs: false, isConnected: connected)
                #expect(state != .empty)
                #expect(state == ((transport || !connected) ? .offline : .failed))
                let pending = ClubsListRules.state(phase: .loading(previous: .failed(transport: transport)),
                                                   hasClubs: false, isConnected: connected)
                #expect(pending != .empty)
            }
        }
        #expect(ClubsListRules.state(phase: .idle, hasClubs: false, isConnected: true) == .loading)
        #expect(ClubsListRules.state(phase: .idle, hasClubs: false, isConnected: false) == .offline)
        #expect(ClubsListRules.state(phase: .loading(previous: .idle), hasClubs: false, isConnected: true) == .loading)
    }

    @Test("Only a successful empty read is the invitation; clubs on screen stay with an inline notice")
    func emptyAndList() {
        let now = Date()
        #expect(ClubsListRules.state(phase: .loaded(at: now), hasClubs: false, isConnected: true) == .empty)
        #expect(ClubsListRules.state(phase: .loaded(at: now), hasClubs: true, isConnected: true) == .list(notice: nil))
        #expect(ClubsListRules.state(phase: .failed(transport: false), hasClubs: true, isConnected: true) == .list(notice: .failed))
        #expect(ClubsListRules.state(phase: .failed(transport: true), hasClubs: true, isConnected: true) == .list(notice: .offline))
        #expect(ClubsListRules.state(phase: .loading(previous: .loaded(at: now)), hasClubs: true, isConnected: true) == .list(notice: nil))
    }

    @Test("Staleness: idle and failed refresh, a fresh read does not, a read in flight is not repeated")
    func needsRefresh() {
        let now = Date()
        #expect(MyClubsPhase.needsRefresh(.idle, now: now, staleness: 60))
        #expect(MyClubsPhase.needsRefresh(.failed(transport: true), now: now, staleness: 60))
        #expect(!MyClubsPhase.needsRefresh(.loaded(at: now.addingTimeInterval(-30)), now: now, staleness: 60))
        #expect(MyClubsPhase.needsRefresh(.loaded(at: now.addingTimeInterval(-61)), now: now, staleness: 60))
        #expect(MyClubsPhase.needsRefresh(.loaded(at: now.addingTimeInterval(120)), now: now, staleness: 60), "a clock moved back counts as stale")
        #expect(!MyClubsPhase.needsRefresh(.loading(previous: .idle), now: now, staleness: 60))
        #expect(MyClubsPhase.loading(previous: .loading(previous: .failed(transport: false))).settled == .failed(transport: false))
    }

    // MARK: Fallback

    @Test("Fallback only on a missing function")
    func fallbackClassifier() {
        #expect(MyClubsReadFallback.shouldUseEnriched(after: PostgrestError(code: "PGRST202", message: "missing")))
        #expect(MyClubsReadFallback.shouldUseEnriched(after: PostgrestError(code: "42883", message: "undefined function")))
        #expect(!MyClubsReadFallback.shouldUseEnriched(after: PostgrestError(code: "XX000", message: "boom")))
        #expect(!MyClubsReadFallback.shouldUseEnriched(after: PostgrestError(message: "no code")))
        #expect(!MyClubsReadFallback.shouldUseEnriched(after: URLError(.notConnectedToInternet)))
        #expect(!MyClubsReadFallback.shouldUseEnriched(after: CancellationError()))
        #expect(!MyClubsReadFallback.shouldUseEnriched(after: ClubError.notAMember))
    }

    // MARK: Invite codes

    @Test("Invite codes keep their case and are found in links and messages")
    func inviteCodeNormalization() {
        #expect(ClubInviteCode.normalize("AbC12xYz") == "AbC12xYz")
        #expect(ClubInviteCode.normalize(" abc 12 xyz ") == "abc12xyz")
        #expect(ClubInviteCode.normalize("AbC12xYz99") == "AbC12xYz")
        #expect(ClubInviteCode.normalize("kuro://join/AbC12xYz") == "AbC12xYz")
        #expect(ClubInviteCode.normalize("Join my club \u{201C}Friday\u{201D} in Kuro: kuro://join/Qw3rTy12. Or enter the code Qw3rTy12 in the app.") == "Qw3rTy12")
        #expect(ClubInviteCode.normalize("Use this invite code to join: Zz9Yy8Xx") == "Zz9Yy8Xx")
        #expect(ClubInviteCode.normalize("ÄbC12xYz") == "bC12xYz", "non-ASCII letters are not code characters")
        #expect(ClubInviteCode.isValid("AbC12xYz"))
        #expect(!ClubInviteCode.isValid("AbC12xY"))
        #expect(!ClubInviteCode.isValid("AbC1-xYz"))
        #expect(ClubInviteCode.hint(for: "", german: false) == nil)
        #expect(ClubInviteCode.hint(for: "AbC12xY", german: false) == "1 more character.")
        #expect(ClubInviteCode.hint(for: "AbC", german: true) == "Noch 5 Zeichen.")
        #expect(ClubInviteCode.hint(for: "AbC12xYz", german: true) == nil)
    }

    // MARK: Copy

    @Test("Club copy never shows a server code or SDK text, in English or German")
    func copyHidesCodes() {
        let errors: [ClubError?] = [nil, .other(message: "DESCRIPTION_TOO_LONG: max 500 characters"), .descriptionTooLong,
                                     .invalidCode, .codeExpired, .notAMember, .duplicateItem, .uniqueViolation, .permissionDenied]
        for german in [false, true] {
            for error in errors {
                let lines = [
                    ClubCopy.joinError(error, german: german),
                    ClubCopy.createClubError(error, german: german),
                    ClubCopy.createRailError(error, german: german),
                    ClubCopy.createPollError(error, german: german),
                    ClubCopy.addRailItemError(error, german: german),
                ]
                for line in lines {
                    #expect(!line.contains("_"), "raw code in \(line)")
                    #expect(!line.isEmpty)
                    #expect(!line.contains("!"))
                }
            }
        }
        #expect(ClubCopy.addRailItemError(.uniqueViolation, german: false) == ClubCopy.addRailItemError(.duplicateItem, german: false))
    }

    @Test("Audience labels and counts are honest and localized")
    func cardCopy() {
        #expect(ClubsListCardRules.audienceLabel(sharingLevel: "private", german: false) == "Totals only")
        #expect(ClubsListCardRules.audienceLabel(sharingLevel: "PROGRESS", german: true) == "Fortschritt geteilt")
        #expect(ClubsListCardRules.memberCountText(1, german: true) == "1 Mitglied")
        #expect(ClubsListCardRules.memberCountText(5, german: false) == "5 members")
        #expect(ClubsListCardRules.memberCountText(nil, german: false) == nil, "an unknown count is omitted, never 0")
        #expect(ClubsListCardRules.recentLine("   ", german: false) == nil)
        #expect(ClubsListCardRules.memberInitials(sharingLevel: "private", memberNames: ["Ada"]).isEmpty)
        let label = ClubsListCardRules.accessibilityLabel(name: "Friday", memberCount: 3, sharingLevel: "status",
                                                          hasUnseen: true, recentLine: nil, german: false)
        #expect(label == "Friday, 3 members, Statuses shared, New activity")
    }

    @Test("Recent lines: the server's English prefixes are localized; unknown text never shows")
    func recentLineLocalized() {
        #expect(ClubsListCardRules.recentLine("Added: Frieren", german: false) == "Added Frieren")
        #expect(ClubsListCardRules.recentLine("Added: Frieren", german: true) == "Neu: Frieren")
        #expect(ClubsListCardRules.recentLine("Poll: Next pick?", german: true) == "Umfrage: Next pick?")
        #expect(ClubsListCardRules.recentLine("Vote on: Next pick?", german: false) == "Vote on Next pick?")
        #expect(ClubsListCardRules.recentLine("Vote on: Next pick?", german: true) == "Abstimmung: Next pick?")
        #expect(ClubsListCardRules.recentLine("Added: ", german: false) == nil)
        #expect(ClubsListCardRules.recentLine("Something new happened", german: true) == nil)
    }

    @Test("Leave copy: deletion only for a last member; a successor only from a complete member list")
    func leaveCopy() {
        func member(_ id: String, _ role: String, _ name: String?, _ joined: String) -> ClubMember {
            ClubMember(user_id: id, display_name: name, role: role, sharing_level: "status", joined_at: joined)
        }
        let me = member("me", "owner", "Me", "2026-01-01T00:00:00Z")
        let deleted = "You're the only member. The club will be deleted."
        let generic = "Another member will become the owner. You'll need a new invite code to rejoin."
        // 2-member club: the server lists only the caller.
        #expect(ClubLeaveCopy.message(clubName: "C", myRole: "owner", memberCount: 2, members: [me], german: false) == generic)
        // Private club of 5: the list is withheld too.
        #expect(ClubLeaveCopy.message(clubName: "C", myRole: "owner", memberCount: 5, members: [me], german: false) == generic)
        #expect(ClubLeaveCopy.message(clubName: "C", myRole: "owner", memberCount: 1, members: [me], german: false) == deleted)
        // Complete list: the oldest admin, else the oldest member.
        let full = [me,
                    member("b", "member", "Bo", "2026-01-02T00:00:00Z"),
                    member("c", "admin", "Cy", "2026-01-05T00:00:00Z")]
        #expect(ClubLeaveCopy.message(clubName: "C", myRole: "owner", memberCount: 3, members: full, german: false)
                == "Cy will become the owner. You'll need a new invite code to rejoin.")
        let noAdmin = [me, member("b", "member", "Bo", "2026-01-02T00:00:00Z"), member("d", "member", "Di", "2026-01-03T00:00:00Z")]
        #expect(ClubLeaveCopy.message(clubName: "C", myRole: "owner", memberCount: 3, members: noAdmin, german: true)
                == "Bo wird Inhaber:in des Clubs. Zum Wiederkommen brauchst du einen neuen Einladungscode.")
        #expect(ClubLeaveCopy.message(clubName: "C", myRole: "member", memberCount: 1, members: [], german: false)
                == "Leave C? You'll need a new invite code to rejoin.")
    }

    @Test("Only connectivity codes count as offline for the my-clubs read")
    func connectivityClassification() {
        #expect(MyClubsPhase.isConnectivityFailure(URLError(.notConnectedToInternet)))
        #expect(MyClubsPhase.isConnectivityFailure(URLError(.networkConnectionLost)))
        #expect(!MyClubsPhase.isConnectivityFailure(URLError(.timedOut)))
        #expect(!MyClubsPhase.isConnectivityFailure(URLError(.cannotConnectToHost)))
        #expect(!MyClubsPhase.isConnectivityFailure(URLError(.badServerResponse)))
        #expect(!MyClubsPhase.isConnectivityFailure(ClubError.other(message: "x")))
    }

    @Test("Form limits count Unicode code points like Postgres char_length")
    func serverLength() {
        #expect(ClubFormField.serverLength("  abc  ") == 3)
        // Family emoji: 1 grapheme, 7 code points (4 people + 3 joiners).
        #expect(ClubFormField.serverLength("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}") == 7)
        #expect(ClubFormField.serverLength("e\u{301}") == 2)
    }

    // MARK: Detail

    @Test("Detail issues: transport answers are retryable failures, membership answers are not")
    func detailIssues() {
        #expect(ClubDetailIssue.forLoadError(ClubError.other(message: "x"), isConnected: false) == .offline)
        #expect(ClubDetailIssue.forLoadError(URLError(.timedOut), isConnected: true) == .timedOut)
        #expect(ClubDetailIssue.forLoadError(URLError(.networkConnectionLost), isConnected: true) == .offline)
        #expect(ClubDetailIssue.forLoadError(ClubError.other(message: "x"), isConnected: true) == .failed)
        for issue in [ClubDetailIssue.removed, .notYetMember, .left, .clubGone] { #expect(issue.isMembership) }
        for issue in [ClubDetailIssue.offline, .timedOut, .failed] { #expect(!issue.isMembership) }
        #expect(ClubDetailIssue.offline.message(german: false, hasContent: true) == "Showing what you saw last.")
    }

    @Test("Activity prose is medium-correct in both languages")
    func activityProse() {
        let mangaStart = ClubActivityProse.parts(status: "READING", progress: nil, isManga: true, german: false)
        #expect(mangaStart.beforeTitle == " started reading ")
        let animeAt = ClubActivityProse.parts(status: "WATCHING", progress: 5, isManga: false, german: true)
        #expect(animeAt.beforeTitle == " ist bei Folge 5 von ")
        let done = ClubActivityProse.parts(status: "COMPLETED", progress: nil, isManga: false, german: true)
        #expect(done == ClubActivityProse.Parts(beforeTitle: " hat ", afterTitle: " beendet"))
    }

    @Test("Notes: only real, non-empty notes; the author is the disclosed member name or nobody")
    func notes() throws {
        let json = """
        {"club":{"id":"c","name":"C","description":null,"sharing_level":"status","max_members":20,"is_archived":false,"invite_code":null,"created_at":"2026-01-01T00:00:00Z"},
         "members":[{"user_id":"u1","display_name":"Mia","role":"owner","sharing_level":"status","joined_at":"2026-01-01T00:00:00Z"}],
         "my_role":"member","my_sharing_level":"status",
         "rails":[{"id":"r","title":"R","description":null,"is_locked":false,"sort_order":0,"created_by":"u1","items":[
           {"id":"i1","media_type":"ANIME","media_id":1,"sort_order":0,"note":"  ","added_by":"u1","title_display":"One","cover_image_medium":null,"average_score":null,"year":null,"format":null,"episode_count":null,"chapter_count":null,"my_status":null,"my_progress":null,"my_rating":null,"member_status_counts":null,"member_statuses":null,"reactions":null,"my_reactions":null},
           {"id":"i2","media_type":"MANGA","media_id":2,"sort_order":1,"note":"The ending hits.","added_by":"u1","title_display":"Two","cover_image_medium":null,"average_score":null,"year":null,"format":null,"episode_count":null,"chapter_count":null,"my_status":null,"my_progress":null,"my_rating":null,"member_status_counts":null,"member_statuses":null,"reactions":null,"my_reactions":null},
           {"id":"i3","media_type":"ANIME","media_id":3,"sort_order":2,"note":"Gone member","added_by":null,"title_display":"Three","cover_image_medium":null,"average_score":null,"year":null,"format":null,"episode_count":null,"chapter_count":null,"my_status":null,"my_progress":null,"my_rating":null,"member_status_counts":null,"member_statuses":null,"reactions":null,"my_reactions":null}]}],
         "polls":[],"member_count":3}
        """
        let bundle = try JSONDecoder().decode(ClubBundle.self, from: Data(json.utf8))
        let notes = ClubRoomCopy.notes(in: try #require(bundle.rails.first), members: bundle.members)
        #expect(notes.map(\.itemId) == ["i2", "i3"])
        #expect(notes.first?.author == "Mia")
        #expect(notes.last?.author == nil)
        #expect(ClubRoomCopy.firstNote(in: bundle)?.text == "The ending hits.")
        #expect(ClubRoomCopy.summary(memberCount: 3, railCount: 1, openPolls: 0, german: false) == "3 members · 1 rail")
        #expect(ClubRoomCopy.progress(3, total: 12, isManga: false, german: true) == "F. 3 von 12")
        #expect(ClubRoomCopy.progress(0, total: 12, isManga: true, german: false) == nil)
    }

    @Test("Rail cards size from the container within 112-144 pt")
    func cardMetrics() {
        #expect(ClubRailCardMetrics.width(containerWidth: 320) == 112)
        #expect(ClubRailCardMetrics.width(containerWidth: 390) == 119)
        #expect(ClubRailCardMetrics.width(containerWidth: 1024) == 144)
        #expect(ClubRailCardMetrics.height(width: 112) == 160)
    }

    @Test("Reactions keep the server keys and draw no emoji")
    func reactionGlyphs() {
        #expect(ClubReactionGlyph.keys == ["fire", "heart", "eyes", "100"])
        for key in ClubReactionGlyph.keys {
            let name = ClubReactionGlyph.spokenName(for: key, german: false)
            #expect(name.unicodeScalars.allSatisfy { $0.isASCII })
        }
        #expect(ClubReactionGlyph.symbol(for: "100") == nil)
        #expect(ClubReactionGlyph.symbol(for: "fire") == "flame")
    }
}
