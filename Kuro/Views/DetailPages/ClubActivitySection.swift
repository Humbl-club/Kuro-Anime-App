import SwiftUI

// MARK: - Club Activity Section for Media Detail Views
// Shows club context for a media item: which clubs have it in a rail,
// aggregate member status counts, and (if sharing level allows) member details.
// Privacy is enforced server-side; this view renders whatever data is returned.

struct ClubActivitySection: View {
    let mediaId: Int
    let mediaType: String

    @Environment(SupabaseService.self) private var supabaseService
    @State private var showAddSheet = false

    private var activities: [SupabaseService.ClubMediaActivity] {
        supabaseService.clubActivityForMedia(mediaId: mediaId, mediaType: mediaType)
    }

    var body: some View {
        let hasClubs = !supabaseService.myClubs.isEmpty
        let currentUserId = supabaseService.currentUserId

        if hasClubs || !activities.isEmpty {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                EditorialLayout.divider()

                HStack(spacing: 10) {
                    Text("CLUBS")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroBlack80)

                    Spacer(minLength: 0)

                    if hasClubs {
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            showAddSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("ADD")
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.4)
                            }
                            .foregroundColor(.black.opacity(0.78))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if activities.isEmpty {
                    Text("Add this to a club rail to watch together. No feeds, just shared rails.")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.50))
                } else {
                    ForEach(activities, id: \.club.id) { activity in
                        ClubActivityCard(activity: activity, currentUserId: currentUserId)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task {
                // If the user just opened detail pages, the clubs list might not be warm yet.
                if supabaseService.myClubs.isEmpty {
                    await supabaseService.fetchMyClubs()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddToClubRailSheet(mediaId: mediaId, mediaType: mediaType)
                    .environment(supabaseService)
            }
        }
    }
}

// MARK: - Card per club

private struct ClubActivityCard: View {
    let activity: SupabaseService.ClubMediaActivity
    let currentUserId: String?

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
                    members: activity.members,
                    currentUserId: currentUserId
                )
            }
        }
    }
}

// MARK: - Add to Club Rail Sheet

private struct AddToClubRailSheet: View {
    let mediaId: Int
    let mediaType: String

    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService

    @State private var selectedClubId: String? = nil
    @State private var bundle: SupabaseService.ClubBundle? = nil
    @State private var isLoading = false
    @State private var errorText: String? = nil
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    Text("ADD TO CLUB")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(2.4)
                        .foregroundColor(.black.opacity(0.60))
                        .padding(.top, KuroDesignSpacing.md)

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("Choose a club")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.black.opacity(0.55))

                        ForEach(supabaseService.myClubs.filter { !$0.is_archived }) { club in
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                selectClub(club.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(club.name)
                                        .font(.kuroBody(weight: .light))
                                        .foregroundColor(.black.opacity(0.85))
                                        .lineLimit(1)

                                    Spacer(minLength: 0)

                                    if selectedClubId == club.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.black.opacity(0.55))
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.black.opacity(0.25))
                                    }
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    EditorialLayout.divider()

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("Choose a rail")
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.black.opacity(0.55))

                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.9).tint(.black.opacity(0.45))
                                Text("Loading rails...")
                                    .font(.kuroCaption(weight: .light))
                                    .foregroundColor(.black.opacity(0.45))
                            }
                            .padding(.vertical, 6)
                        } else if let errorText {
                            Text(errorText)
                                .font(.kuroCaption())
                                .foregroundColor(.red.opacity(0.85))
                        } else if let bundle {
                            if bundle.rails.isEmpty {
                                Text("No rails yet. Ask an admin to create one.")
                                    .font(.kuroCaption(weight: .light))
                                    .foregroundColor(.black.opacity(0.45))
                            } else {
                                ForEach(bundle.rails) { rail in
                                    let canAdd = !(rail.is_locked && !["owner", "admin"].contains(bundle.my_role))

                                    Button {
                                        guard canAdd, !isSubmitting else { return }
                                        KuroAccessibility.impactHaptic(.light)
                                        Task { await addToRail(railId: rail.id, clubId: bundle.club.id) }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Text(rail.title)
                                                .font(.kuroBody(weight: .light))
                                                .foregroundColor(.black.opacity(canAdd ? 0.85 : 0.30))
                                                .lineLimit(1)

                                            Spacer(minLength: 0)

                                            if rail.is_locked {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 11, weight: .regular))
                                                    .foregroundColor(.black.opacity(0.25))
                                            }

                                            Image(systemName: "plus")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.black.opacity(canAdd ? 0.55 : 0.20))
                                        }
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!canAdd || isSubmitting)
                                }
                            }
                        } else {
                            Text("Pick a club to see its rails.")
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.black.opacity(0.45))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
            .background(Color.kuroBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
        }
        .task {
            if supabaseService.myClubs.isEmpty {
                await supabaseService.fetchMyClubs()
            }
        }
    }

    private func selectClub(_ clubId: String) {
        selectedClubId = clubId
        bundle = nil
        errorText = nil
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                bundle = try await supabaseService.fetchClubBundle(clubId: clubId, forceRefresh: true)
            } catch {
                errorText = "Could not load rails."
            }
        }
    }

    private func addToRail(railId: String, clubId: String) async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await supabaseService.addRailItem(
                railId: railId,
                mediaType: mediaType.uppercased(),
                mediaId: mediaId
            )
            // Refresh the club bundle so the club view and activity cache update quickly.
            _ = try? await supabaseService.fetchClubBundle(clubId: clubId, forceRefresh: true)
            KuroAccessibility.successHaptic()
            dismiss()
        } catch {
            KuroAccessibility.errorHaptic()
            errorText = "Could not add to rail."
        }
    }
}

// MARK: - Row per rail item match

private struct ClubActivityItemRow: View {
    let item: SupabaseService.ClubRailItem
    let memberCount: Int
    let sharingLevel: String
    let members: [SupabaseService.ClubMember]
    let currentUserId: String?

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
                        members: members,
                        currentUserId: currentUserId,
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
    let members: [SupabaseService.ClubMember]
    let currentUserId: String?
    let sharingLevel: String
    let mediaType: String

    private var memberIndexById: [String: Int] {
        // Stable ordering for consistent labels: join order, then user_id fallback.
        let ordered = members.sorted { $0.joined_at < $1.joined_at }.map(\.user_id)
        var out: [String: Int] = [:]
        for (idx, id) in ordered.enumerated() { out[id] = idx + 1 }
        return out
    }

    private var roleById: [String: String] {
        var out: [String: String] = [:]
        for m in members { out[m.user_id] = m.role }
        return out
    }

    private func memberLabel(_ userId: String) -> String {
        if let currentUserId, userId == currentUserId { return "You" }
        if let idx = memberIndexById[userId] { return "Member \(idx)" }
        // Fallback: should be rare (e.g. server returned a status for a user not present in members list).
        // Keep it anonymous but stable-ish for debugging.
        return "Member \(String(userId.suffix(4)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let sorted = statuses.sorted { a, b in
                if let currentUserId {
                    let aIsMe = a.user_id == currentUserId
                    let bIsMe = b.user_id == currentUserId
                    if aIsMe != bIsMe { return aIsMe }
                }
                return (memberIndexById[a.user_id] ?? 9999) < (memberIndexById[b.user_id] ?? 9999)
            }
            ForEach(sorted, id: \.user_id) { ms in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Group {
                                if let idx = memberIndexById[ms.user_id] {
                                    Text(String(idx))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.40))
                                        .monospacedDigit()
                                } else {
                                    Circle()
                                        .fill(Color.black.opacity(0.10))
                                        .frame(width: 6, height: 6)
                                }
                            }
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(memberLabel(ms.user_id))
                                .font(.kuroCaption(weight: .medium))
                                .foregroundColor(.black.opacity(0.55))

                            if let role = roleById[ms.user_id]?.uppercased(), role != "MEMBER" {
                                Text(role)
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.2)
                                    .foregroundColor(.black.opacity(0.40))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.black.opacity(0.05)))
                            }
                        }

                        if let status = ms.status {
                            ClubStatusPill(status: status)
                        } else {
                            Text("Not started")
                                .font(.kuroCaption())
                                .foregroundColor(.black.opacity(0.35))
                        }
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
