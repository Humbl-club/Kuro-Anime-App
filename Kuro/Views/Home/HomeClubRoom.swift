import KuroCore
import SwiftUI

// MARK: - Home club room (PROTOTYPE_SPEC.md §4 "Club room"; spec §5.1 item 9)
// The prototype's dark private-club card: seal, "YOUR PRIVATE CLUB", the club name (serif), member
// initials; a light note card (cover, name, time ago, the quote in serif, "{title} ›", and a spoiler
// line); activity rows; the footer "Shared stories. Your people. · N updates".
//
// Only real clubs and real notes (rulebook: no fabricated data):
// - The club is the account's club with the most recent real activity (`pick`); no club, no room.
// - Its name, members and latest activity come from `ClubsStore.myClubs` (`ClubSummary(row:)`).
// - Notes come from Home's club slice, which holds notes from anyone who shares *a* club with the
//   reader and carries no club id. Notes are shown only when the reader has exactly one club (so
//   every note comes from it); with several clubs the room shows its masthead, the club's own
//   activity and the footer, never notes (`roomNotes`). Display names are not unique and the
//   server lists at most four members, so matching names would misattribute notes. Follow-up: the
//   slice returns the shared club id per note, and Home matches on ids.
// - Verbs the data does not carry are not written: a note links "{title} ›" (never "Finished …"), a
//   spoiler note reads "{name}'s thought on the ending/story" from its real `spoiler_scope` and opens
//   the title (Home never receives spoiler text), and the club's activity line is read from its own
//   preview ("Added: …", "Poll: …", "Vote on: …").
// - "N updates" counts the rows shown; "+N other clubs ›" counts the reader's other clubs.
// - The activity row carries no artwork: the server's newest cover can belong to a different rail
//   item than its preview, so a cover beside the preview's title could be the wrong one.
// Embedded by `HomeView.clubSection` (Task 10): `ClubSummary` values from `ClubsStore.myClubs`
// (refreshed with `refreshMyClubsIfStale()`), `pick`, `presentation` (a failed clubs read with no club
// known draws `HomeClubRoomFailure`), notes from `roomNotes(...)` with Home's title/cover lookup, and
// `notesFailed` only when the reader has one club (with several no note is shown, so none failed).
// Colours and the room's drop come from `ClubRoomStyle.swift` (`ClubRoomPalette`, `ClubRoomBackground`).

/// One of the reader's clubs, as Home shows it. Built only from a real `ClubListRow`.
struct ClubSummary: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    /// The club's latest real activity (rail item, poll or vote), when the server reports one.
    let lastActivityAt: Date?
    /// Up to four member names, in join order (the server's "Member" stands in for a blank name).
    let memberNames: [String]
    let memberCount: Int?
    /// The server's activity line: "Added: <title>", "Poll: <question>", "Vote on: <question>".
    let activityPreview: String?
    /// The newest rail item *with* a cover. Not necessarily the preview's item, so the room never
    /// shows it beside the preview's title.
    let latestCover: String?

    init(id: String, name: String, lastActivityAt: Date?, memberNames: [String] = [], memberCount: Int? = nil,
         activityPreview: String? = nil, latestCover: String? = nil) {
        self.id = id
        self.name = name
        self.lastActivityAt = lastActivityAt
        self.memberNames = memberNames
        self.memberCount = memberCount
        self.activityPreview = activityPreview
        self.latestCover = latestCover
    }

    /// nil for an archived club or one without a name: Home never invents a club name.
    init?(row: ClubListRow) {
        let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !row.is_archived, !name.isEmpty else { return nil }
        self.init(id: row.id, name: name,
                  lastActivityAt: row.last_activity_at.flatMap(ClubsStore.parseISO8601),
                  memberNames: row.member_names ?? [], memberCount: row.member_count,
                  activityPreview: row.activity_preview, latestCover: row.cover_images?.first)
    }
}

struct HomeClubRoom: View {
    /// One note shown in the room, with the title Home resolved for it.
    struct Note: Equatable, Identifiable {
        let id: String
        let medium: MediaKind
        let mediaId: Int
        let author: String?
        /// The note's text; nil for a spoiler (Home never receives spoiler text).
        let text: String?
        /// "story" / "ending" for a spoiler note, nil otherwise.
        let spoilerScope: String?
        let createdAt: Date?
        let title: String?
        let coverImage: String?

        init(item: HomeClubItem, title: String?, coverImage: String?) {
            id = item.commentId
            medium = item.mediaType.lowercased() == "manga" ? .manga : .anime
            mediaId = item.mediaId
            let name = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            author = (name?.isEmpty ?? true) ? nil : name
            let scope = item.spoilerScope?.lowercased()
            spoilerScope = (scope == nil || scope == "none") ? nil : scope
            let body = item.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            text = spoilerScope == nil && !(body?.isEmpty ?? true) ? body : nil
            createdAt = item.createdAt.flatMap(ClubsStore.parseISO8601)
            let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = (cleanTitle?.isEmpty ?? true) ? nil : cleanTitle
            self.coverImage = coverImage
        }

        var isSpoiler: Bool { spoilerScope != nil }
    }

    /// What Home shows where the room goes.
    enum Presentation: Equatable {
        /// No club with real activity: nothing (never a stand-in club).
        case hidden
        /// The room for this club; `notesFailed` when the club notes could not be read.
        case room(ClubSummary, notesFailed: Bool)
        /// The clubs could not be read and none is known: a branded failure, never "no clubs".
        case failed
        /// The clubs could not be read because the device is offline and none is known.
        case offline
    }

    /// The club activity line, parsed from the server's preview.
    struct Activity: Equatable {
        enum Kind: Equatable { case added, poll, vote }
        let kind: Kind
        let subject: String
    }

    let club: ClubSummary
    let notes: [Note]
    let otherClubCount: Int
    let medium: MediaKind
    let now: Date
    let onOpenClubs: (() -> Void)?
    let notesFailed: Bool
    /// The notes failed because the device is offline (the offline wording, not "Couldn't load").
    let notesOffline: Bool
    let onRetry: (() -> Void)?

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The room's measured width; the prototype's small-phone rules apply at ≤ 360 pt phones.
    @State private var roomWidth: CGFloat = 0

    init(club: ClubSummary, notes: [Note], otherClubCount: Int = 0, medium: MediaKind,
         now: Date = Date(), notesFailed: Bool = false, notesOffline: Bool = false,
         onRetry: (() -> Void)? = nil, onOpenClubs: (() -> Void)? = nil) {
        self.club = club
        self.notes = notes
        self.otherClubCount = otherClubCount
        self.medium = medium
        self.now = now
        self.notesFailed = notesFailed
        self.notesOffline = notesOffline
        self.onRetry = onRetry
        self.onOpenClubs = onOpenClubs
    }

    // MARK: Pure rules

    /// The room, nothing, or a failure: a failed clubs read with no club known never reads as "no
    /// clubs" (rulebook §9). `clubsReadFailed` is `ClubsStore.myClubsPhase.settled == .failed`;
    /// `notesFailed` is Home's club slice in state "error". `offline` is a transport failure
    /// (`MyClubsPhase.failed(transport: true)`, or `NetworkMonitor.isConnected == false`): the
    /// failure then reads as offline, as `KuroBrandedState` separates it.
    static func presentation(picked: ClubSummary?, clubsReadFailed: Bool, notesFailed: Bool,
                             offline: Bool = false) -> Presentation {
        if let picked { return .room(picked, notesFailed: notesFailed) }
        guard clubsReadFailed else { return .hidden }
        return offline ? .offline : .failed
    }

    /// The club with the latest real activity; nil (the room hides) without clubs or without any
    /// dated activity. Ties keep the server's order.
    static func pick(clubs: [ClubSummary]) -> ClubSummary? {
        var best: ClubSummary?
        for club in clubs {
            guard let at = club.lastActivityAt else { continue }
            if let current = best?.lastActivityAt, current >= at { continue }
            best = club
        }
        return best
    }

    /// The notes that may appear under `club`, newest first. Only when the reader has exactly this
    /// one club: the slice then holds notes from its members only (`shares_club_at_least` skips
    /// archived clubs). With several clubs the slice cannot say which club a note came from (no club
    /// id; names are not unique), so no note is shown rather than a possibly false attribution.
    static func roomNotes(_ items: [HomeClubItem], club: ClubSummary, clubCount: Int) -> [HomeClubItem] {
        guard clubCount <= 1 else { return [] }
        return items.enumerated().sorted { lhs, rhs in
            let l = lhs.element.createdAt.flatMap(ClubsStore.parseISO8601)
            let r = rhs.element.createdAt.flatMap(ClubsStore.parseISO8601)
            switch (l, r) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// "Added: Frieren" → added "Frieren"; nil for an empty or unknown preview.
    static func activity(from preview: String?) -> Activity? {
        guard let preview = preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty else { return nil }
        let prefixes: [(String, Activity.Kind)] = [("Added:", .added), ("Poll:", .poll), ("Vote on:", .vote)]
        for (prefix, kind) in prefixes where preview.hasPrefix(prefix) {
            let subject = preview.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return subject.isEmpty ? nil : Activity(kind: kind, subject: subject)
        }
        return nil
    }

    /// "2h ago" / "vor 2 Std."; nil without a date or for a date in the future.
    static func timeAgo(_ date: Date?, now: Date, german: Bool) -> String? {
        guard let date else { return nil }
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 0 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return german ? "gerade eben" : "just now" }
        if minutes < 60 { return german ? "vor \(minutes) Min." : "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return german ? "vor \(hours) Std." : "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return german ? (days == 1 ? "vor 1 Tag" : "vor \(days) Tagen") : "\(days)d ago" }
        let weeks = days / 7
        return german ? (weeks == 1 ? "vor 1 Woche" : "vor \(weeks) Wochen") : "\(weeks)w ago"
    }

    /// "Mina's thought on the ending" / "Minas Gedanke zum Ende"; without a name, "A thought on …".
    static func spoilerLine(author: String?, scope: String, german: Bool) -> String {
        let ending = scope == "ending"
        guard let author else {
            if german { return ending ? "Ein Gedanke zum Ende" : "Ein Gedanke zur Geschichte" }
            return ending ? "A thought on the ending" : "A thought on the story"
        }
        if german {
            let genitive = author.hasSuffix("s") || author.hasSuffix("x") || author.hasSuffix("z") ? author + "’" : author + "s"
            return ending ? "\(genitive) Gedanke zum Ende" : "\(genitive) Gedanke zur Geschichte"
        }
        return ending ? "\(author)’s thought on the ending" : "\(author)’s thought on the story"
    }

    /// Up to three initials for the member stack.
    static func initials(_ names: [String]) -> [String] {
        names.prefix(3).compactMap { name in
            name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
        }
    }

    /// How the notes are laid out: the newest note leads the light card; a spoiler by the same
    /// person on the same title joins it as its spoiler line (as the prototype pairs them); up to
    /// two further notes become rows.
    static func layout(_ notes: [Note]) -> (lead: Note?, leadSpoiler: Note?, rows: [Note]) {
        guard let lead = notes.first else { return (nil, nil, []) }
        var rest = Array(notes.dropFirst())
        var spoiler: Note?
        if !lead.isSpoiler, let author = lead.author,
           let index = rest.firstIndex(where: { $0.isSpoiler && $0.author == author
               && $0.mediaId == lead.mediaId && $0.medium == lead.medium }) {
            spoiler = rest.remove(at: index)
        }
        return (lead, spoiler, Array(rest.prefix(2)))
    }

    /// The updates the room shows: the lead card, its further note rows and the club's activity.
    static func updateCount(notes: [Note], activity: Activity?) -> Int {
        let parts = layout(notes)
        return (parts.lead == nil ? 0 : 1) + parts.rows.count + (activity == nil ? 0 : 1)
    }

    // MARK: View

    private var german: Bool { KuroLocale.isGerman }
    private var radius: CGFloat { medium == .manga ? 13 : 24 }
    private var noteRadius: CGFloat { medium == .manga ? 3 : 14 }
    /// The note's cover (manga `.club-title-art img` 1, anime 3).
    private var noteArtRadius: CGFloat { medium == .manga ? 1 : 3 }
    private var activity: Activity? { Self.activity(from: club.activityPreview) }
    private var narrow: Bool { dynamicTypeSize.isAccessibilitySize }
    /// The prototype's `@media(max-width:360px)` room (PROTOTYPE_SPEC.md §5): the room is 356 pt at
    /// 390 and about 296 pt at 320.
    private var compact: Bool { HomeClubRoom.isCompact(width: roomWidth) }

    /// Small-phone room at or below `ClubRoomMetrics.compactRoomWidth` (pure; the one club-room
    /// threshold, spec D15).
    static func isCompact(width: CGFloat) -> Bool { width > 0 && width <= ClubRoomMetrics.compactRoomWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
                .padding(.bottom, 19)
            let parts = Self.layout(notes)
            if let lead = parts.lead {
                noteCard(lead, spoiler: parts.leadSpoiler)
            }
            ForEach(parts.rows) { note in
                noteRow(note)
            }
            if notesFailed && notes.isEmpty {
                HomeClubRoomFailureLine(kind: notesOffline ? .offline : .failed(
                    headline: KuroLocale.text("Couldn't load club notes.", "Club-Notizen konnten nicht geladen werden.")),
                                        onRetry: onRetry)
            }
            if let activity {
                activityRow(activity)
            }
            footer
        }
        .padding(.top, 20)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ClubRoomBackground(cornerRadius: radius) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
        .accessibilityElement(children: .contain)
    }

    // MARK: Masthead

    private var masthead: some View {
        Button { routes.openClub(club.id) } label: {
            HStack(alignment: .center, spacing: compact ? 8 : 10) {
                ClubSeal(ring: ClubSeal.ring(compact: compact))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(KuroLocale.text("Your private club", "Dein privater Club"))
                        .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(ClubRoomPalette.kicker)
                    Text(club.name)
                        .font(.kuroEditorial(size: compact ? 19 : 22))
                        .tracking(-0.6)
                        .foregroundStyle(ClubRoomPalette.text)
                        .lineLimit(narrow ? 3 : 1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !narrow {
                    memberStack
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityHint(KuroLocale.text("Opens the club", "Öffnet den Club"))
    }

    private var memberStack: some View {
        HStack(spacing: -6) {
            ForEach(Array(Self.initials(club.memberNames).enumerated()), id: \.offset) { index, letter in
                Text(letter)
                    .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 12))
                    .foregroundStyle(ClubRoomPalette.memberInk)
                    .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
                    .background(Circle().fill(Self.memberFills[index % Self.memberFills.count]))
                    .overlay(Circle().strokeBorder(ClubRoomPalette.memberRim, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(memberSpoken)
    }

    /// The member initials are shaded by position (`.member-stack>span:nth-child(2|3)`).
    static let memberFills: [Color] = ClubRoomPalette.memberFills

    private var memberSpoken: String {
        let count = club.memberCount ?? club.memberNames.count
        return count == 1 ? KuroLocale.text("1 member", "1 Mitglied")
                          : KuroLocale.text("\(count) members", "\(count) Mitglieder")
    }

    // MARK: Note card

    private func noteCard(_ note: Note, spoiler: Note?) -> some View {
        let shape = RoundedRectangle(cornerRadius: noteRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            Button { open(note) } label: {
                HStack(alignment: .top, spacing: compact ? 11 : 13) {
                    HomeCalendarArt(raw: note.coverImage)
                        .frame(width: narrow ? 40 : (compact ? 48 : 60), height: narrow ? 60 : (compact ? 72 : 90))
                        .clipShape(RoundedRectangle(cornerRadius: noteArtRadius, style: .continuous))
                        .shadow(color: ClubRoomPalette.noteArtShadow, radius: 3, y: 3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(note.author ?? KuroLocale.text("A club member", "Ein Clubmitglied"))
                                .font(.kuroCustom(compact ? 10 : 11, weight: .semibold, relativeTo: .caption1, maxSize: 22))
                                .foregroundStyle(ClubRoomPalette.noteInk)
                            Spacer(minLength: 6)
                            if let ago = Self.timeAgo(note.createdAt, now: now, german: german) {
                                Text(ago)
                                    .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 20))
                                    .foregroundStyle(ClubRoomPalette.noteMeta)
                            }
                        }
                        if let text = note.text {
                            Text(KuroLocale.text("“\(text)”", "„\(text)“"))
                                .font(.kuroEditorial(size: compact ? 16 : 18))
                                .tracking(-0.3)
                                .lineSpacing(3)
                                .foregroundStyle(ClubRoomPalette.noteInk)
                                .multilineTextAlignment(.leading)
                                .lineLimit(narrow ? nil : 4)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }
                        if let title = note.title {
                            Text("\(title) ›")
                                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                                .foregroundStyle(ClubRoomPalette.noteLink)
                                .lineLimit(2)
                                // `.club-title`: a 44 pt box with 8 pt top padding.
                                .padding(.top, 8)
                                .frame(minHeight: 44, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(KuroLocale.text("Opens this title", "Öffnet diesen Titel"))
            if let scope = note.spoilerScope {
                spoilerLine(note, scope: scope)
            } else if let spoiler, let scope = spoiler.spoilerScope {
                spoilerLine(spoiler, scope: scope)
            }
        }
        // CSS padding 15 (13) inside a 1 pt border; `strokeBorder` draws inside the padding, so +1.
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(ClubRoomPalette.note)
                .shadow(color: ClubRoomPalette.noteShadow, radius: 3.5, y: 3)
        }
        .overlay(shape.strokeBorder(ClubRoomPalette.noteBorder, lineWidth: 1))
    }

    /// A spoiler note: its line opens the title, where the reader can choose to reveal it.
    private func spoilerLine(_ note: Note, scope: String) -> some View {
        Button { open(note) } label: {
            HStack(spacing: 10) {
                Text(Self.spoilerLine(author: note.author, scope: scope, german: german))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(ClubRoomPalette.quietInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.kuroCustom(12, weight: .regular, relativeTo: .footnote, maxSize: 20))
                    .foregroundStyle(ClubRoomPalette.quietInk)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(minHeight: 46)
            .background(ClubRoomPalette.quiet, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClubRoomPalette.quietBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityHint(KuroLocale.text("Contains spoilers. Opens the title, where you can choose to read it.",
                                           "Enthält Spoiler. Öffnet den Titel, dort kannst du ihn lesen."))
    }

    // MARK: Rows

    private func noteRow(_ note: Note) -> some View {
        let who = note.author ?? KuroLocale.text("A club member", "Ein Clubmitglied")
        let line = note.isSpoiler
            ? Self.spoilerLine(author: note.author, scope: note.spoilerScope ?? "story", german: german)
            : KuroLocale.text("\(who) shared a thought", "\(who) hat einen Gedanken geteilt")
        return Button { open(note) } label: {
            secondaryRow(art: note.coverImage, first: line, second: note.title)
        }
        .buttonStyle(HomeContactStyle())
    }

    private func activityRow(_ activity: Activity) -> some View {
        let first: String
        switch activity.kind {
        case .added: first = KuroLocale.text("New in the club", "Neu im Club")
        case .poll: first = KuroLocale.text("New poll", "Neue Umfrage")
        case .vote: first = KuroLocale.text("New vote", "Neue Stimme")
        }
        return Button { routes.openClub(club.id) } label: {
            // No artwork: `latestCover` may belong to another rail item than the preview's title.
            secondaryRow(art: nil, first: first, second: activity.subject)
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityHint(KuroLocale.text("Opens the club", "Öffnet den Club"))
    }

    private func secondaryRow(art: String?, first: String, second: String?) -> some View {
        HStack(spacing: 10) {
            if let art {
                HomeCalendarArt(raw: art)
                    .frame(width: 30, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: noteArtRadius, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(first)
                    .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                    .foregroundStyle(ClubRoomPalette.rowInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let second {
                    Text(second)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(ClubRoomPalette.rowSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 20))
                .foregroundStyle(ClubRoomPalette.rowInk)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 2)
        .frame(minHeight: 70)
        .padding(.top, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        let updates = Self.updateCount(notes: notes, activity: activity)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(KuroLocale.text("Shared stories. Your people.", "Geteilte Geschichten. Deine Leute."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if updates > 0 {
                    Text(updates == 1 ? KuroLocale.text("1 update", "1 Neuigkeit")
                                      : KuroLocale.text("\(updates) updates", "\(updates) Neuigkeiten"))
                }
            }
            .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 16))
            .foregroundStyle(ClubRoomPalette.footer)
            .padding(.top, 10)
            .padding(.horizontal, 2)
            if otherClubCount > 0, let onOpenClubs {
                Button(action: onOpenClubs) {
                    Text(otherClubCount == 1 ? KuroLocale.text("+1 other club ›", "+1 weiterer Club ›")
                                             : KuroLocale.text("+\(otherClubCount) other clubs ›",
                                                               "+\(otherClubCount) weitere Clubs ›"))
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(ClubRoomPalette.rowSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(ClubRoomPalette.footerRule).frame(height: 1) }
    }

    private func open(_ note: Note) {
        routes.openMedia(MediaRoute(kind: note.medium, id: note.mediaId))
    }
}

// `ClubSeal` and `ClubKnot` live in `ClubRoomStyle.swift` (one seal for every club surface, spec D15).

/// The room's failure: the dark room shell with the branded failure line (spec §5.4), used when the
/// clubs could not be read (`HomeClubRoom.Presentation.failed` / `.offline`).
struct HomeClubRoomFailure: View {
    let medium: MediaKind
    let offline: Bool
    let onRetry: (() -> Void)?

    init(medium: MediaKind, offline: Bool = false, onRetry: (() -> Void)? = nil) {
        self.medium = medium
        self.offline = offline
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(KuroLocale.text("Your private club", "Dein privater Club"))
                .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(ClubRoomPalette.kicker)
            HomeClubRoomFailureLine(kind: offline ? .offline : .failed(
                headline: KuroLocale.text("Couldn't load your clubs.", "Deine Clubs konnten nicht geladen werden.")),
                                    onRetry: onRetry)
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ClubRoomBackground(cornerRadius: medium == .manga ? 13 : 24) }
        .accessibilityElement(children: .contain)
    }
}

/// The branded error/offline family (`KuroErrorView` / `KuroOfflineView`) in the room's light ink:
/// the ridge stroke, an SF headline, one plain sentence, and an ink-rule "Try again →". The
/// foundation's `KuroRidgeStroke` is drawn in `kuroInk`, which disappears on the dark room, so the
/// ridge shape is stroked here in #C1CDB7 (drawn once for a failure, held still offline).
struct HomeClubRoomFailureLine: View {
    enum Kind: Equatable {
        case failed(headline: String)
        case offline
    }

    let kind: Kind
    let onRetry: (() -> Void)?

    @State private var drawn: CGFloat = 0

    /// The headline and sentence for a kind (pure; the copy is `KuroBrandedCopy`'s).
    static func copy(_ kind: Kind, german: Bool) -> (headline: String, message: String) {
        switch kind {
        case .failed(let headline): return (headline, KuroBrandedCopy.errorMessage(german: german))
        case .offline: return (KuroBrandedCopy.offlineHeadline(german: german),
                               KuroBrandedCopy.offlineLine(hasContent: false, german: german))
        }
    }

    var body: some View {
        let text = Self.copy(kind, german: KuroLocale.isGerman)
        VStack(alignment: .leading, spacing: 8) {
            KuroMotionAllowance { plays in
                KuroRidgeShape()
                    .trim(from: 0, to: (kind != .offline && plays) ? drawn : 1)
                    .stroke(ClubRoomPalette.rowSecondary, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .onAppear {
                        guard drawn < 1 else { return }
                        if kind != .offline && plays { withAnimation(KuroMotion.ease(1.2)) { drawn = 1 } } else { drawn = 1 }
                    }
            }
            .frame(width: 72, height: 18)
            .accessibilityHidden(true)
            Text(text.headline)
                .font(.kuroCustom(15, weight: .semibold, relativeTo: .headline, maxSize: 30))
                .tracking(-0.3)
                .foregroundStyle(ClubRoomPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(text.message)
                .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 22))
                .foregroundStyle(ClubRoomPalette.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                Button(action: onRetry) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(KuroBrandedCopy.retryTitle(german: KuroLocale.isGerman) + " →")
                            .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                            .foregroundStyle(ClubRoomPalette.rowInk)
                        Rectangle().fill(ClubRoomPalette.rowInk.opacity(0.6)).frame(height: 1)
                    }
                    .fixedSize()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
