import SwiftUI

// MARK: - Club Activity Section for Media Detail Views
// Shows club context for a media item: which clubs have it in a rail,
// aggregate member status counts, and (if sharing level allows) member details.
// Privacy is enforced server-side; this view renders whatever data is returned.

struct ClubActivitySection: View {
    let mediaId: Int
    let mediaType: String

    @Environment(SupabaseService.self) private var supabaseService

    private var activities: [SupabaseService.ClubMediaActivity] {
        supabaseService.clubActivityForMedia(mediaId: mediaId, mediaType: mediaType)
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                EditorialLayout.divider()

                Text("CLUB ACTIVITY")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                ForEach(activities, id: \.club.id) { activity in
                    ClubActivityCard(activity: activity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Card per club

private struct ClubActivityCard: View {
    let activity: SupabaseService.ClubMediaActivity

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(activity.club.name)
                .font(.kuroBody(weight: .medium))
                .foregroundColor(.black.opacity(0.85))

            ForEach(activity.matchingItems, id: \.item.id) { match in
                ClubActivityItemRow(
                    item: match.item,
                    memberCount: activity.memberCount,
                    sharingLevel: activity.sharingLevel,
                    members: activity.members
                )
            }
        }
    }
}

// MARK: - Row per rail item match

private struct ClubActivityItemRow: View {
    let item: SupabaseService.ClubRailItem
    let memberCount: Int
    let sharingLevel: String
    let members: [SupabaseService.ClubMember]

    @State private var showMembers = false

    private var aggregateText: String {
        guard let counts = item.member_status_counts else { return "" }
        // Privacy: if server returned _tracking_count, use generic aggregate
        if let tracking = counts["_tracking_count"], tracking > 0 {
            return "\(tracking) tracking"
        }
        var parts: [String] = []
        let watching = (counts["CURRENT"] ?? 0) + (counts["WATCHING"] ?? 0) + (counts["READING"] ?? 0)
        let completed = counts["COMPLETED"] ?? 0
        let planning = (counts["PLANNING"] ?? 0) + (counts["PLANNED"] ?? 0)
        if watching > 0 { parts.append("\(watching) watching") }
        if completed > 0 { parts.append("\(completed) completed") }
        if planning > 0 { parts.append("\(planning) planning") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var canShowMemberDetail: Bool {
        sharingLevel != "private" && memberCount >= 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            if !aggregateText.isEmpty {
                Text(aggregateText)
                    .font(.kuroCaption())
                    .foregroundColor(.black.opacity(0.55))
            }

            if let myStatus = item.my_status {
                HStack(spacing: 6) {
                    Text("You:")
                        .font(.kuroCaption())
                        .foregroundColor(.black.opacity(0.55))
                    ClubStatusPill(status: myStatus)
                    if let progress = item.my_progress, progress > 0 {
                        let prefix = item.media_type.uppercased() == "ANIME" ? "Ep" : "Ch"
                        Text("\(prefix) \(progress)")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.45))
                    }
                }
            }

            if canShowMemberDetail, let statuses = item.member_statuses, !statuses.isEmpty {
                DisclosureGroup(isExpanded: $showMembers) {
                    ClubMemberStatusList(
                        statuses: statuses,
                        sharingLevel: sharingLevel,
                        mediaType: item.media_type
                    )
                } label: {
                    Text("Show members")
                        .font(.kuroCaption(weight: .medium))
                        .foregroundColor(.black.opacity(0.55))
                }
                .tint(.black.opacity(0.40))
            }
        }
    }
}

// MARK: - Status Pill

private struct ClubStatusPill: View {
    let status: String

    private var displayText: String {
        switch status.uppercased() {
        case "CURRENT", "WATCHING": return "Watching"
        case "READING": return "Reading"
        case "COMPLETED": return "Completed"
        case "PLANNING", "PLANNED": return "Planning"
        case "PAUSED", "ON_HOLD": return "Paused"
        case "DROPPED": return "Dropped"
        default: return status.capitalized
        }
    }

    var body: some View {
        Text(displayText)
            .font(.kuroCaption())
            .foregroundColor(.black.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.black.opacity(0.06))
            )
    }
}

// MARK: - Member Status List (inside disclosure)

private struct ClubMemberStatusList: View {
    let statuses: [SupabaseService.ClubRailItem.MemberItemStatus]
    let sharingLevel: String
    let mediaType: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(statuses, id: \.user_id) { ms in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(ms.user_id.prefix(2)).uppercased())
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.black.opacity(0.45))
                        )

                    if let status = ms.status {
                        ClubStatusPill(status: status)
                    } else {
                        Text("Not tracking")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.35))
                    }

                    Spacer()

                    if sharingLevel == "progress", let progress = ms.progress, progress > 0 {
                        let prefix = mediaType.uppercased() == "ANIME" ? "Ep" : "Ch"
                        Text("\(prefix) \(progress)")
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.45))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, KuroDesignSpacing.xs)
    }
}
