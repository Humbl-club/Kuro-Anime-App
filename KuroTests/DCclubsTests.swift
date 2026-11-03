import Foundation
import KuroCore
import Testing
@testable import Kuro

/// Pure rules of the Clubs lane of the Discover + Clubs redesign (spec
/// `docs/superpowers/specs/2026-11-03-discover-clubs-redesign-design.md` §7; this file holds what the
/// spec calls `ClubsRoomTests`): key visibility by role and rail lock, the add target, "You" by user
/// id, note-once placement, the This-week 7-day / Berlin grouping (nil dates under Earlier), the pace
/// numbers, poll copy, join dirtiness, the list room's order, meta and opening copy, and the one seal
/// and threshold for every club surface.
@Suite("Clubs lane: room rules")
@MainActor
struct DCclubsTests {
    // MARK: Fixtures

    private static func item(_ id: String, note: String? = nil, addedBy: String? = "u2", statuses: String = "null",
                             myProgress: Int? = nil, type: String = "ANIME") -> String {
        """
        {"id":"\(id)","media_type":"\(type)","media_id":\(id.count + 100),"sort_order":0,
         "note":\(note.map { "\"\($0)\"" } ?? "null"),"added_by":\(addedBy.map { "\"\($0)\"" } ?? "null"),
         "title_display":"T \(id)","cover_image_medium":null,"average_score":null,"year":null,"format":null,
         "episode_count":24,"chapter_count":null,"my_status":null,"my_progress":\(myProgress.map(String.init) ?? "null"),
         "my_rating":null,"member_status_counts":null,"member_statuses":\(statuses),"reactions":null,"my_reactions":null}
        """
    }

    private static func rail(_ id: String, locked: Bool, items: [String] = []) -> String {
        """
        {"id":"\(id)","title":"Rail \(id)","description":null,"is_locked":\(locked),"sort_order":0,"created_by":"u1",
         "items":[\(items.joined(separator: ","))]}
        """
    }

    private static func bundle(role: String, rails: [String], invite: String? = nil, members: String? = nil,
                               memberCount: Int = 4) throws -> ClubBundle {
        let membersJSON = members ?? """
        [{"user_id":"ME-1","display_name":"Max","role":"\(role)","sharing_level":"progress","joined_at":"2026-01-01T00:00:00Z"},
         {"user_id":"u2","display_name":"Mina","role":"member","sharing_level":"progress","joined_at":"2026-01-02T00:00:00Z"}]
        """
        let json = """
        {"club":{"id":"c","name":"C","description":null,"sharing_level":"progress","max_members":20,"is_archived":false,
                 "invite_code":\(invite.map { "\"\($0)\"" } ?? "null"),"created_at":"2026-01-01T00:00:00Z"},
         "members":\(membersJSON),"my_role":"\(role)","my_sharing_level":"progress",
         "rails":[\(rails.joined(separator: ","))],"polls":[],"member_count":\(memberCount)}
        """
        return try JSONDecoder().decode(ClubBundle.self, from: Data(json.utf8))
    }

    private static func date(_ iso: String) throws -> Date { try #require(ClubDates.parse(iso)) }

    // MARK: Keys (D9, D10)

    @Test("Keys: a member sees only Add, and only with an unlocked rail")
    func memberKeys() throws {
        let open = try Self.bundle(role: "member", rails: [Self.rail("a", locked: false), Self.rail("b", locked: true)])
        #expect(ClubRoomRules.keys(role: open.my_role, rails: open.rails, hasInviteCode: open.club.invite_code != nil) == [.addTitle])
        #expect(ClubRoomRules.addTarget(rails: open.rails, role: open.my_role) == .rail("a"), "never a guessed rails.first")

        let lockedOnly = try Self.bundle(role: "member", rails: [Self.rail("b", locked: true)])
        #expect(ClubRoomRules.keys(role: "member", rails: lockedOnly.rails, hasInviteCode: false).isEmpty)
        #expect(ClubRoomRules.addTarget(rails: lockedOnly.rails, role: "member") == .none)

        let noRails = try Self.bundle(role: "member", rails: [])
        #expect(ClubRoomRules.keys(role: "member", rails: noRails.rails, hasInviteCode: false).isEmpty)
    }

    @Test("Keys: owners and admins get Add, Invite and Ask; Start a rail without rails")
    func adminKeys() throws {
        let rails = try Self.bundle(role: "admin", rails: [Self.rail("a", locked: true), Self.rail("b", locked: false)],
                                    invite: "AbC12xYz").rails
        #expect(ClubRoomRules.keys(role: "admin", rails: rails, hasInviteCode: true) == [.addTitle, .invite, .ask])
        #expect(ClubRoomRules.addTarget(rails: rails, role: "OWNER") == .chooser(["a", "b"]), "admins may add to locked rails")
        #expect(ClubRoomRules.keys(role: "owner", rails: [], hasInviteCode: true) == [.startRail, .invite, .ask])
        // Invite follows the code the server sent, not the role.
        #expect(ClubRoomRules.keys(role: "owner", rails: [], hasInviteCode: false) == [.startRail, .ask])
        #expect(ClubRoomCopy.keyTitle(.addTitle, german: true) == "Titel hinzufügen")
        #expect(ClubRoomCopy.keyTitle(.startRail, german: true) == "Liste anlegen")
        #expect(ClubRoomCopy.keyTitle(.invite, german: false) == "Invite")
        #expect(ClubRoomCopy.keyTitle(.ask, german: true) == "Fragen")
    }

    @Test("canAddToRail keeps the existing lock rule")
    func canAdd() throws {
        let rails = try Self.bundle(role: "member", rails: [Self.rail("a", locked: false), Self.rail("b", locked: true)]).rails
        #expect(ClubRoomRules.canAddToRail(rails[0], role: "member"))
        #expect(!ClubRoomRules.canAddToRail(rails[1], role: "member"))
        #expect(ClubRoomRules.canAddToRail(rails[1], role: "owner"))
        #expect(ClubRoomRules.canAddToRail(rails[1], role: "admin"))
    }

    // MARK: You (D13)

    @Test("The viewer is found by user id, case-insensitively, and left out of the others")
    func viewerExclusion() throws {
        let club = try Self.bundle(role: "member", rails: [])
        #expect(ClubRoomRules.isViewer("me-1", viewerId: "ME-1"))
        #expect(!ClubRoomRules.isViewer("u2", viewerId: "ME-1"))
        #expect(!ClubRoomRules.isViewer("u2", viewerId: nil))
        #expect(ClubRoomRules.otherMembers(club.members, viewerId: "me-1").map(\.user_id) == ["u2"])
        #expect(ClubRoomCopy.youAndMembers(memberCount: 5, german: false) == "You and 4 members")
        #expect(ClubRoomCopy.youAndMembers(memberCount: 2, german: true) == "Du und 1 Mitglied")
        #expect(ClubRoomCopy.viewerProgress(7, total: 24, isManga: false, german: false) == "You · Ep. 7 of 24")
        #expect(ClubRoomCopy.viewerProgress(7, total: 24, isManga: false, german: true) == "Du · F. 7 von 24")
        #expect(ClubRoomCopy.viewerProgress(0, total: 24, isManga: false, german: false) == nil)
    }

    // MARK: Notes (D11)

    @Test("Each note appears once: the first in rail order links up to the hero, others stay inline")
    func noteOnce() throws {
        let club = try Self.bundle(role: "member", rails: [
            Self.rail("a", locked: false, items: [Self.item("i1"), Self.item("i2", note: "First."), Self.item("i3", note: "Second.")]),
            Self.rail("b", locked: false, items: [Self.item("i4", note: "Third.")])
        ])
        let first = try #require(ClubRoomCopy.firstNote(in: club))
        #expect(first.itemId == "i2")
        let placements = club.rails.flatMap(\.items).map {
            ClubRoomRules.notePlacement(itemId: $0.id, note: $0.note, firstNoteItemId: first.itemId)
        }
        #expect(placements == [.none, .linkToHero, .inline, .inline])
        #expect(placements.filter { $0 == .linkToHero }.count == 1)
        #expect(ClubRoomRules.notePlacement(itemId: "x", note: "   ", firstNoteItemId: nil) == .none)
        #expect(ClubRoomCopy.noteLinkUp(author: "Mina", german: false) == "Mina’s note ↑")
        #expect(ClubRoomCopy.noteLinkUp(author: "Mina", german: true) == "Notiz von Mina ↑")
        #expect(ClubRoomCopy.noteInline(author: "Jules", german: true) == "Notiz von Jules · kann Spoiler enthalten")
    }

    // MARK: This week (D12)

    @Test("This week: the last 7 × 24 h by Berlin day; older and undated updates under Earlier")
    func weekPartition() throws {
        let statuses = """
        [{"user_id":"ME-1","display_name":"Max","status":"CURRENT","progress":4,"updated_at":"2026-11-03T08:00:00Z"},
         {"user_id":"u2","display_name":"Mina","status":"COMPLETED","progress":24,"updated_at":"2026-11-02T23:30:00Z"},
         {"user_id":"u3","display_name":"Jules","status":"CURRENT","progress":2,"updated_at":"2026-11-02T22:30:00Z"},
         {"user_id":"u4","display_name":"Ana","status":"CURRENT","progress":9,"updated_at":"2026-10-27T12:30:00Z"},
         {"user_id":"u5","display_name":"Ben","status":"CURRENT","progress":1,"updated_at":"2026-10-20T10:00:00Z"},
         {"user_id":"u6","display_name":"Cleo","status":"CURRENT","progress":1,"updated_at":null},
         {"user_id":"u7","display_name":"Dev","status":"CURRENT","progress":1,"updated_at":"not a date"}]
        """
        let club = try Self.bundle(role: "member", rails: [Self.rail("a", locked: false, items: [Self.item("i1", statuses: statuses)])])
        let now = try Self.date("2026-11-03T12:00:00Z")
        let entries = ClubWeekRules.entries(in: club, viewerId: "me-1")
        #expect(entries.count == 7, "nothing is dropped")
        #expect(entries.first?.isViewer == true)
        let split = ClubWeekRules.partition(entries, now: now)
        // 23:30 UTC on 2 Nov is 00:30 on 3 Nov in Berlin: the same Berlin day as the viewer's update.
        #expect(split.thisWeek.count == 3)
        #expect(split.thisWeek.map { $0.entries.map(\.userId) } == [["ME-1", "u2"], ["u3"], ["u4"]])
        #expect(split.thisWeekCount == 4)
        #expect(split.earlier.map { $0.entries.map(\.userId) } == [["u5"]])
        #expect(split.undated.map(\.userId) == ["u6", "u7"])
        #expect(split.earlierCount == 3)
        // The boundary: exactly 7 × 24 h old is Earlier.
        let edge = ClubWeekRules.partition(entries, now: try Self.date("2026-11-03T12:30:00Z"))
        #expect(edge.thisWeek.flatMap(\.entries).allSatisfy { $0.userId != "u4" })
    }

    @Test("This week copy: day labels, Berlin times, summary and the quiet week")
    func weekCopy() throws {
        let now = try Self.date("2026-11-03T12:00:00Z")
        let cal = ClubWeekRules.berlin
        #expect(ClubWeekCopy.dayLabel(cal.startOfDay(for: now), now: now, german: false) == "Today")
        #expect(ClubWeekCopy.dayLabel(try Self.date("2026-11-02T10:00:00Z"), now: now, german: true) == "Gestern")
        #expect(ClubWeekCopy.dayLabel(try Self.date("2026-10-29T10:00:00Z"), now: now, german: false) == "Thursday")
        #expect(ClubWeekCopy.time(try Self.date("2026-11-02T23:30:00Z")) == "00:30")
        #expect(ClubWeekCopy.summary(count: 5, since: ClubWeekRules.windowStart(now: now), german: false) == "5 updates since Tue 27 Oct")
        #expect(ClubWeekCopy.since(ClubWeekRules.windowStart(now: now), german: false) == "Since Tue 27 Oct")
        #expect(ClubWeekCopy.updates(1, german: true) == "1 Neuigkeit")
        #expect(ClubWeekCopy.showOlder(12, german: false) == "Show 12 older updates")
        #expect(ClubWeekCopy.quietWeek(since: ClubWeekRules.windowStart(now: now), german: false)
                == "Quiet week. Nobody has moved on since Tuesday.")
        #expect(ClubWeekCopy.quietWeek(since: ClubWeekRules.windowStart(now: now), german: true)
                == "Ruhige Woche. Seit Dienstag ist niemand weitergekommen.")
        let chip = ClubWeekCopy.chip(try Self.date("2026-11-03T08:00:00Z"), german: false)
        #expect(chip.day == "3" && chip.month.lowercased() == "nov")
    }

    @Test("This week lines: You for the viewer, the existing verbs without the title")
    func weekLines() {
        let you = ClubWeekCopy.line(subject: "Max", isViewer: true, status: "CURRENT", progress: 4, isManga: false, german: false)
        #expect(you.subject == "You" && you.predicate == "reached episode 4")
        let du = ClubWeekCopy.line(subject: "Max", isViewer: true, status: "CURRENT", progress: 4, isManga: false, german: true)
        #expect(du.subject == "Du" && du.predicate == "bist bei Folge 4")
        let ari = ClubWeekCopy.line(subject: "Ari", isViewer: false, status: "COMPLETED", progress: nil, isManga: false, german: false)
        #expect(ari.subject == "Ari" && ari.predicate == "finished it")
        let anon = ClubWeekCopy.line(subject: nil, isViewer: false, status: "PLANNING", progress: nil, isManga: true, german: false)
        #expect(anon.subject == "A member" && anon.predicate == "plans to read it")
    }

    // MARK: Pace

    @Test("Pace: the existing median rule, in glance numbers")
    func pace() throws {
        let statuses = """
        [{"user_id":"a","display_name":"A","status":"CURRENT","progress":10,"updated_at":null},
         {"user_id":"b","display_name":"B","status":"CURRENT","progress":12,"updated_at":null},
         {"user_id":"c","display_name":"C","status":"CURRENT","progress":4,"updated_at":null}]
        """
        let club = try Self.bundle(role: "member", rails: [Self.rail("a", locked: false, items: [
            Self.item("i1", statuses: statuses, myProgress: 7), Self.item("i2", statuses: statuses, myProgress: 11)
        ])])
        let items = club.rails[0].items
        #expect(ClubPaceRules.gap(items[0]) == ClubPaceRules.Gap(behind: 3, groupAt: 10))
        #expect(ClubPaceRules.gap(items[1]) == nil, "ahead of the median")
        let gap = ClubPaceRules.Gap(behind: 3, groupAt: 10)
        #expect(ClubPaceRules.title(gap, isManga: false, german: false) == "You're 3 episodes behind")
        #expect(ClubPaceRules.title(gap, isManga: false, german: true) == "Du bist 3 Folgen zurück")
        #expect(ClubPaceRules.caption(gap, rail: "Sunday watch", title: "Frieren", isManga: false, german: false)
                == "Sunday watch · the group is on Ep. 10 of Frieren")
        #expect(ClubPaceRules.applies(sharingLevel: "progress", memberCount: 3, enabled: true))
        #expect(!ClubPaceRules.applies(sharingLevel: "status", memberCount: 5, enabled: true))
        #expect(!ClubPaceRules.applies(sharingLevel: "progress", memberCount: 2, enabled: true))
        #expect(!ClubPaceRules.applies(sharingLevel: "progress", memberCount: 5, enabled: false))
    }

    // MARK: Polls

    @Test("Polls: You asked, the deadline only when set, and the closed summary")
    func polls() throws {
        let closes = try Self.date("2026-11-09T18:00:00Z")
        #expect(ClubPollCopy.kicker(askerName: "Max", isViewer: true, closesAt: closes, german: false) == "You asked · Closes Mon 9 Nov")
        #expect(ClubPollCopy.kicker(askerName: "Mina", isViewer: false, closesAt: nil, german: false) == "Mina asked")
        #expect(ClubPollCopy.kicker(askerName: "Mina", isViewer: false, closesAt: nil, german: true) == "Mina fragt")
        #expect(ClubPollCopy.kicker(askerName: nil, isViewer: false, closesAt: nil, german: false) == nil)
        let options = try JSONDecoder().decode([ClubPollOption].self, from: Data("""
        [{"id":"a","label":"Sub","media_type":null,"media_id":null,"sort_order":0,"vote_count":4},
         {"id":"b","label":"Dub","media_type":null,"media_id":null,"sort_order":1,"vote_count":1}]
        """.utf8))
        #expect(ClubPollCopy.closedSummary(askerName: "Mina", isViewer: false, question: "Sub or dub?", options: options, german: false)
                == "Mina asked: Sub or dub? · Sub won, 4 to 1")
        #expect(ClubPollCopy.closedSummary(askerName: "Mina", isViewer: false, question: "Sub or dub?", options: options, german: true)
                == "Mina fragte: Sub or dub? · Sub gewann, 4 zu 1")
        let tied = try JSONDecoder().decode([ClubPollOption].self, from: Data("""
        [{"id":"a","label":"A","media_type":null,"media_id":null,"sort_order":0,"vote_count":2},
         {"id":"b","label":"B","media_type":null,"media_id":null,"sort_order":1,"vote_count":2}]
        """.utf8))
        #expect(ClubPollCopy.closedSummary(askerName: nil, isViewer: true, question: "Q?", options: tied, german: false)
                == "You asked: Q? · Tied")
        #expect(ClubPollCopy.votes(1, german: false) == "1 vote")
        #expect(ClubPollCopy.votes(3, german: true) == "3 Stimmen")
    }

    // MARK: Join (D14)

    @Test("Join: a typed code is unsaved input; the untouched deep-link prefill is not")
    func joinDirty() {
        #expect(!ClubJoinRules.isDirty(code: "", initialCode: ""))
        #expect(ClubJoinRules.isDirty(code: "AbC", initialCode: ""))
        #expect(!ClubJoinRules.isDirty(code: "AbC12xYz", initialCode: "AbC12xYz"))
        #expect(ClubJoinRules.isDirty(code: "AbC12xY", initialCode: "AbC12xYz"))
        // Joining opens the club through the same rule as creating one.
        #expect(ClubCreationFollowUp.clubToOpen(created: "c7", isCurrent: true) == "c7")
        #expect(ClubCreationFollowUp.clubToOpen(created: "c7", isCurrent: false) == nil)
    }

    // MARK: List

    @Test("List: newest activity first, undated clubs last; meta and the opening line")
    func list() throws {
        let rows = try JSONDecoder().decode([ClubListRow].self, from: Data("""
        [{"id":"a","name":"A","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z",
          "member_count":3,"rail_count":1,"poll_count":0,"last_activity_at":null,"activity_preview":null,"cover_images":null,"member_names":null},
         {"id":"b","name":"B","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z",
          "member_count":3,"rail_count":1,"poll_count":0,"last_activity_at":"2026-10-01T00:00:00Z","activity_preview":null,"cover_images":null,"member_names":null},
         {"id":"c","name":"C","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z",
          "member_count":3,"rail_count":1,"poll_count":0,"last_activity_at":"2026-11-01T00:00:00.123Z","activity_preview":null,"cover_images":null,"member_names":null},
         {"id":"d","name":"D","sharing_level":"status","is_archived":false,"created_at":"2026-01-01T00:00:00Z",
          "member_count":3,"rail_count":1,"poll_count":0,"last_activity_at":null,"activity_preview":null,"cover_images":null,"member_names":null}]
        """.utf8))
        #expect(ClubRoomRules.sortedForList(rows).map(\.id) == ["c", "b", "a", "d"])
        #expect(ClubRoomCopy.listMeta(memberCount: 5, railCount: 3, pollCount: 2, german: false) == "5 members · 3 rails · 2 polls")
        #expect(ClubRoomCopy.listMeta(memberCount: 2, railCount: 0, pollCount: 0, german: false) == "2 members · no rails yet")
        #expect(ClubRoomCopy.listMeta(memberCount: 1, railCount: 1, pollCount: 1, german: true) == "1 Mitglied · 1 Liste · 1 Umfrage")
        #expect(ClubRoomCopy.listMeta(memberCount: nil, railCount: nil, pollCount: nil, german: false) == "",
                "unknown counts are left out, never shown as 0")
        #expect(ClubRoomCopy.listKicker(count: 3, german: false) == "Your private clubs · 3")
        #expect(ClubRoomCopy.listKicker(count: 3, german: true) == "Deine privaten Clubs · 3")
        #expect(ClubRoomCopy.listHeadline(unread: 2, german: false) == "2 with something new.")
        #expect(ClubRoomCopy.listHeadline(unread: 0, german: true) == "Alles gesehen.")
        #expect(ClubRoomCopy.heroKicker(sharingLevel: "progress", german: false) == "Your private club · Progress shared")
        #expect(ClubRoomCopy.heroKicker(sharingLevel: "private", german: true) == "Dein privater Club · Nur Summen")
        #expect(ClubsEmptyCopy.kicker(german: false) == "YOUR PRIVATE CLUBS")
        #expect(ClubsEmptyCopy.kicker(german: true) == "DEINE PRIVATEN CLUBS")
    }

    // MARK: Seal and threshold (D15)

    @Test("One seal (36 / 30) and one compact threshold (≤ 328) on every club surface")
    func sealAndThreshold() {
        #expect(ClubSeal.ring(compact: false) == 36)
        #expect(ClubSeal.ring(compact: true) == 30)
        #expect(HomeClubRoom.isCompact(width: ClubRoomMetrics.compactRoomWidth))
        #expect(!HomeClubRoom.isCompact(width: ClubRoomMetrics.compactRoomWidth + 1))
        #expect(!HomeClubRoom.isCompact(width: 0))
        // The room widths of 320 / 390 / 430 phones keep Home's answer from before the move.
        #expect(HomeClubRoom.isCompact(width: 294) && !HomeClubRoom.isCompact(width: 356) && !HomeClubRoom.isCompact(width: 396))
        #expect(ClubRoomLayout.isCompact(columnWidth: 280) && !ClubRoomLayout.isCompact(columnWidth: 350))
        #expect(ClubRoomLayout.gutter(containerWidth: 320) == 16 && ClubRoomLayout.gutter(containerWidth: 390) == 20)
    }

    // MARK: Invite

    @Test("Invite share text is the one Settings sends")
    func inviteText() {
        #expect(ClubInviteCopy.shareText(clubName: "Friday", code: "Qw3rTy12", german: false)
                == "Join my club \u{201C}Friday\u{201D} in Kuro: kuro://join/Qw3rTy12. Or enter the code Qw3rTy12 in the app.")
        #expect(ClubInviteCode.normalize(ClubInviteCopy.shareText(clubName: "Friday", code: "Qw3rTy12", german: true)) == "Qw3rTy12")
    }
}
