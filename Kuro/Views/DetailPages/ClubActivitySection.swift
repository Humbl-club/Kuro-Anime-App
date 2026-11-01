import KuroCore
import SwiftUI

// MARK: - Club Activity Section for Media Detail Views
// Shows club context for a media item: which clubs have it in a rail,
// aggregate member status counts, and (if sharing level allows) member details.
// Privacy is enforced server-side; this view renders whatever data is returned.

struct ClubActivitySection: View {
    let mediaId: Int
    let mediaType: String

    @Environment(IdentityStore.self) private var identity
    @Environment(ClubsStore.self) private var clubs
    @State private var showAddSheet = false

    private var activities: [ClubMediaActivity] {
        clubs.clubActivityForMedia(mediaId: mediaId, mediaType: mediaType)
    }

    var body: some View {
        let hasClubs = !clubs.myClubs.isEmpty
        let currentUserId = identity.currentUserId

        if hasClubs || !activities.isEmpty {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                EditorialLayout.divider()

                HStack(spacing: 10) {
                    Text(KuroLocale.text("Clubs", "Clubs"))
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundColor(.kuroBlack80)
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: 0)

                    if hasClubs {
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            showAddSheet = true
                        } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.kuroMicro(weight: .semibold))
                                    Text(KuroLocale.text("Add", "Hinzufügen"))
                                        .font(.kuroMeta(weight: .medium))
                                }
                            .foregroundColor(.kuroBlack80)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                Capsule()
                                    .stroke(Color.kuroBlack12, lineWidth: 0.8)
                                    .padding(.vertical, 4)
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(KuroPressStyle())
                        .accessibilityLabel(KuroLocale.text("Add to a club rail", "Zu einer Club-Leiste hinzufügen"))
                    }
                }

                if activities.isEmpty {
                    Text(KuroLocale.text(
                        "Add this to a club rail to share it with your club.",
                        "Füge den Titel einer Club-Leiste hinzu, um ihn mit deinem Club zu teilen."))
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroInkQuiet)
                } else {
                    ForEach(activities, id: \.club.id) { activity in
                        ClubActivityCard(activity: activity, currentUserId: currentUserId)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task {
                // If the user just opened detail pages, the clubs list might not be warm yet.
                if clubs.myClubs.isEmpty {
                    await clubs.refreshMyClubsIfStale()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddToClubRailSheet(mediaId: mediaId, mediaType: mediaType)
            }
        }
    }
}

// MARK: - Card per club

private struct ClubActivityCard: View {
    let activity: ClubMediaActivity
    let currentUserId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(activity.club.name)
                .font(.kuroBody(weight: .medium))
                .foregroundColor(.kuroBlack85)

            ForEach(activity.matchingItems, id: \.item.id) { match in
                ClubActivityItemRow(
                    item: match.item,
                    memberCount: activity.memberCount,
                    sharingLevel: activity.sharingLevel,
                    members: activity.members,
                    currentUserId: currentUserId
                )
            }
        }
    }
}

// MARK: - Row per rail item match

private struct ClubActivityItemRow: View {
    let item: ClubRailItem
    let memberCount: Int
    let sharingLevel: String
    let members: [ClubMember]
    let currentUserId: String?

    @State private var showMembers = false

    private var aggregateText: String {
        guard let counts = item.member_status_counts else { return "" }
        if let tracking = counts["_tracking_count"], tracking > 0 {
            let notStarted = max(0, memberCount - tracking)
            // Tracking count represents members with any started progress/status.
            return KuroLocale.text("\(tracking) started \u{00B7} \(notStarted) not started",
                                   "\(tracking) begonnen \u{00B7} \(notStarted) noch nicht begonnen")
        }
        let german = KuroLocale.isGerman
        let kind: MediaKind = item.media_type.uppercased() == "MANGA" ? .manga : .anime
        var parts: [String] = []
        let watching = (counts["CURRENT"] ?? 0) + (counts["WATCHING"] ?? 0) + (counts["READING"] ?? 0)
        let completed = counts["COMPLETED"] ?? 0
        let planning = (counts["PLANNING"] ?? 0) + (counts["PLANNED"] ?? 0)
        let paused = (counts["PAUSED"] ?? 0) + (counts["ON_HOLD"] ?? 0)
        let dropped = counts["DROPPED"] ?? 0
        // "3 Watching" / "3 schauen": a count of members, so German uses the plural verb or participle.
        for (count, status) in [(watching, FolioStatus.watching), (completed, .completed), (planning, .planned),
                                (paused, .paused), (dropped, .dropped)] where count > 0 {
            parts.append(DetailCopy.statusCount(count, status: status, medium: kind, german: german))
        }
        let tracked = counts
            .filter { $0.key != "_tracking_count" }
            .reduce(0) { $0 + $1.value }
        let notStarted = max(0, memberCount - tracked)
        if notStarted > 0 { parts.append(KuroLocale.text("\(notStarted) not started", "\(notStarted) noch nicht begonnen")) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var canShowMemberDetail: Bool {
        sharingLevel != "private" && memberCount >= 3
    }

    /// Format progress with fraction when total is available.
    private func progressText(current: Int, total: Int?) -> String {
        let prefix = item.media_type.uppercased() == "ANIME"
            ? KuroLocale.text("Ep.", "F.")
            : KuroLocale.text("Ch.", "Kap.")
        if let total, total > 0 {
            return "\(prefix) \(current)/\(total)"
        }
        return "\(prefix) \(current)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            if !aggregateText.isEmpty {
                Text(aggregateText)
                    .font(.kuroCaption())
                    .foregroundColor(.kuroTextSecondary)
            }

            if let myStatus = item.my_status {
                HStack(spacing: 6) {
                    Text(KuroLocale.text("You:", "Du:"))
                        .font(.kuroCaption())
                        .foregroundColor(.kuroTextSecondary)
                    ClubStatusPill(status: myStatus, mediaType: item.media_type, perspective: .own)
                    if let progress = item.my_progress, progress > 0 {
                        Text(progressText(current: progress, total: item.totalCount))
                            .font(.kuroCaption())
                            .foregroundColor(.kuroInkQuiet)
                    }
                }
            }

            if canShowMemberDetail, !members.isEmpty {
                DisclosureGroup(isExpanded: $showMembers) {
                    ClubMemberStatusList(
                        statuses: item.member_statuses ?? [],
                        members: members,
                        currentUserId: currentUserId,
                        sharingLevel: sharingLevel,
                        mediaType: item.media_type,
                        totalCount: item.totalCount
                    )
                } label: {
                    Text(showMembers
                         ? KuroLocale.text("Hide members", "Mitglieder ausblenden")
                         : KuroLocale.text("\(members.count) members", "\(members.count) Mitglieder"))
                        .font(.kuroCaption(weight: .medium))
                        .foregroundColor(.kuroTextSecondary)
                }
                .tint(.kuroInkQuiet)
            }
        }
    }
}

// MARK: - Status Pill

private struct ClubStatusPill: View {
    let status: String
    let mediaType: String
    /// `.own` for the viewer's row ("Schaue ich"), `.other` for another member ("Schaut").
    let perspective: DetailCopy.Perspective

    /// The status word for the medium (EN/DE); an unknown value keeps its own text.
    private var displayText: String {
        let kind: MediaKind = mediaType.uppercased() == "MANGA" ? .manga : .anime
        return DetailCopy.listStatus(status, medium: kind, german: KuroLocale.isGerman, perspective: perspective)
            ?? status.capitalized
    }

    var body: some View {
        Text(displayText)
            .font(.kuroCaption())
            .foregroundColor(.kuroTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.kuroBlack06)
            )
    }
}

// MARK: - Member Status List (inside disclosure)

private struct ClubMemberStatusList: View {
    let statuses: [ClubRailItem.MemberItemStatus]
    let members: [ClubMember]
    let currentUserId: String?
    let sharingLevel: String
    let mediaType: String
    let totalCount: Int?

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let memberIndexById: [String: Int]
    private let roleById: [String: String]
    private let displayNameById: [String: String]
    private let statusByUserId: [String: ClubRailItem.MemberItemStatus]

    init(
        statuses: [ClubRailItem.MemberItemStatus],
        members: [ClubMember],
        currentUserId: String?,
        sharingLevel: String,
        mediaType: String,
        totalCount: Int?
    ) {
        self.statuses = statuses
        self.members = members
        self.currentUserId = currentUserId
        self.sharingLevel = sharingLevel
        self.mediaType = mediaType
        self.totalCount = totalCount

        let ordered = members.sorted { $0.joined_at < $1.joined_at }.map(\.user_id)
        var idxMap: [String: Int] = [:]
        for (idx, id) in ordered.enumerated() { idxMap[id] = idx + 1 }
        self.memberIndexById = idxMap

        var roleMap: [String: String] = [:]
        for m in members { roleMap[m.user_id] = m.role }
        self.roleById = roleMap

        var nameMap: [String: String] = [:]
        for m in members {
            let trimmed = m.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                nameMap[m.user_id] = trimmed
            }
        }
        self.displayNameById = nameMap

        var statusMap: [String: ClubRailItem.MemberItemStatus] = [:]
        for s in statuses {
            statusMap[s.user_id] = s
        }
        self.statusByUserId = statusMap
    }

    /// A club role as a word ("Owner" / "Inhaber"); other roles keep their own text.
    static func roleWord(_ role: String) -> String {
        switch role.lowercased() {
        case "owner": return KuroLocale.text("Owner", "Inhaber")
        case "admin": return KuroLocale.text("Admin", "Admin")
        default: return role.capitalized
        }
    }

    private func memberLabel(_ userId: String) -> String {
        if let currentUserId, userId == currentUserId { return KuroLocale.text("You", "Du") }
        if let displayName = displayNameById[userId] { return displayName }
        if let role = roleById[userId], role.lowercased() != "member" {
            return Self.roleWord(role)
        }
        // Stable short identifier from UUID (consistent across sessions)
        let compact = userId.replacingOccurrences(of: "-", with: "")
        let short = String(compact.prefix(6))
        return short.isEmpty ? DetailCopy.unknown(german: KuroLocale.isGerman) : short
    }

    private func memberInitial(_ label: String, userId: String) -> String {
        if !label.isEmpty, let first = label.first {
            return String(first).uppercased()
        }
        let compact = userId.replacingOccurrences(of: "-", with: "")
        let suffix = compact.suffix(2).uppercased()
        return suffix.isEmpty ? "?" : suffix
    }

    /// Whether the member updated their list entry within the last 7 days.
    private func isActive(_ ms: ClubRailItem.MemberItemStatus) -> Bool {
        guard let raw = ms.updated_at else { return false }
        guard let date =
            Self.isoFormatterWithFractionalSeconds.date(from: raw) ??
            Self.isoFormatter.date(from: raw)
        else {
            return false
        }
        return date.timeIntervalSinceNow > -7 * 24 * 3600
    }

    /// Progress fraction (0...1) for the progress bar. Returns nil if no progress data.
    private func progressFraction(_ ms: ClubRailItem.MemberItemStatus) -> Double? {
        guard sharingLevel == "progress",
              let progress = ms.progress, progress > 0,
              let total = totalCount, total > 0 else { return nil }
        return min(1.0, Double(progress) / Double(total))
    }

    /// Format progress text with fraction.
    private func progressText(_ progress: Int) -> String {
        let prefix = mediaType.uppercased() == "ANIME"
            ? KuroLocale.text("Ep.", "F.")
            : KuroLocale.text("Ch.", "Kap.")
        if let total = totalCount, total > 0 {
            return "\(prefix) \(progress)/\(total)"
        }
        return "\(prefix) \(progress)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            let merged = members.map { member -> ClubRailItem.MemberItemStatus in
                if let existing = statusByUserId[member.user_id] {
                    return existing
                }
                return .init(
                    user_id: member.user_id,
                    display_name: member.display_name,
                    status: nil,
                    progress: nil,
                    updated_at: nil
                )
            }

            let sorted = merged.sorted { a, b in
                if let currentUserId {
                    let aIsMe = a.user_id == currentUserId
                    let bIsMe = b.user_id == currentUserId
                    if aIsMe != bIsMe { return aIsMe }
                }
                // Active members first, then by join order
                let aActive = isActive(a)
                let bActive = isActive(b)
                if aActive != bActive { return aActive }
                return (memberIndexById[a.user_id] ?? 9999) < (memberIndexById[b.user_id] ?? 9999)
            }
            ForEach(sorted, id: \.user_id) { ms in
                let active = isActive(ms)
                let isMe = currentUserId != nil && ms.user_id == currentUserId
                let rowOpacity: Double = (active || isMe) ? 1.0 : 0.5

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        // Editorial avatar: initial letter in a rounded rect
                        let label = memberLabel(ms.user_id)
                        let initial = memberInitial(label, userId: ms.user_id)

                        Text(initial)
                            .font(.kuroMicro(weight: .semibold))
                            .foregroundColor(.kuroInkQuiet)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.xs)
                                    .fill(Color.kuroBlack06)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(label)
                                    .font(.kuroCaption(weight: .medium))
                                    .foregroundColor(.kuroBlack70)

                                if let role = roleById[ms.user_id]?.uppercased(),
                                   role != "MEMBER",
                                   displayNameById[ms.user_id] != nil {
                                    Text(Self.roleWord(role).uppercased())
                                        .font(.kuroMicro(weight: .medium))
                                        .tracking(1.0)
                                        .foregroundColor(.kuroTextTertiary)
                                }

                                if active && !isMe {
                                    Circle()
                                        .fill(Color.kuroBlack30)
                                        .frame(width: 4, height: 4)
                                }
                            }

                            HStack(spacing: 6) {
                                if let status = ms.status {
                                    ClubStatusPill(status: status, mediaType: mediaType, perspective: isMe ? .own : .other)
                                } else {
                                    Text(KuroLocale.text("Not started", "Noch nicht begonnen"))
                                        .font(.kuroCaption())
                                        .foregroundColor(.kuroTextTertiary)
                                }

                                if sharingLevel == "progress",
                                   let progress = ms.progress, progress > 0 {
                                    Text(progressText(progress))
                                        .font(.kuroCaption())
                                        .foregroundColor(.kuroInkQuiet)
                                        .monospacedDigit()
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    // Progress bar for active watchers with known total
                    if let fraction = progressFraction(ms), fraction > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.kuroBlack06)
                                    .frame(height: 2)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.kuroBlack25)
                                    .frame(width: geo.size.width * fraction, height: 2)
                            }
                        }
                        .frame(height: 2)
                        .padding(.leading, 30)
                    }
                }
                .opacity(rowOpacity)
                .padding(.vertical, 2)
            }
        }
        .padding(.top, KuroDesignSpacing.xs)
    }
}
