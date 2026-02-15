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
                                        .font(.kuroMicro(weight: .semibold))
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
    @State private var pendingRailId: String? = nil
    @State private var loadBundleTask: Task<Void, Never>? = nil

    private var clubsInteractionV2Enabled: Bool {
        FeatureFlags.shared.isClubsInteractionV2Enabled
    }

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
                                            .font(.kuroCaption(weight: .semibold))
                                            .foregroundColor(.black.opacity(0.55))
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.kuroCaption(weight: .regular))
                                            .foregroundColor(.kuroTextTertiary)
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
                                                    .font(.kuroMicro(weight: .regular))
                                                    .foregroundColor(.kuroTextTertiary)
                                            }

                                            if clubsInteractionV2Enabled && pendingRailId == rail.id && isSubmitting {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .tint(.black.opacity(0.55))
                                            } else if clubsInteractionV2Enabled && pendingRailId == rail.id {
                                                Image(systemName: "checkmark")
                                                    .font(.kuroCaption(weight: .semibold))
                                                    .foregroundColor(.black.opacity(0.55))
                                            } else {
                                                Image(systemName: "plus")
                                                    .font(.kuroCaption(weight: .semibold))
                                                    .foregroundColor(.black.opacity(canAdd ? 0.55 : 0.20))
                                            }
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
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
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
            if clubsInteractionV2Enabled {
                let eligible = supabaseService.myClubs.filter { !$0.is_archived }
                guard selectedClubId == nil, !eligible.isEmpty else { return }
                if let remembered = supabaseService.rememberedAddToClubId(),
                   eligible.contains(where: { $0.id == remembered }) {
                    selectClub(remembered)
                } else if let first = eligible.first?.id {
                    selectClub(first)
                }
            }
        }
        .onDisappear {
            loadBundleTask?.cancel()
        }
    }

    private func selectClub(_ clubId: String) {
        selectedClubId = clubId
        if clubsInteractionV2Enabled {
            supabaseService.setRememberedAddToClubId(clubId)
        }
        loadBundleTask?.cancel()
        bundle = nil
        errorText = nil
        isLoading = true
        isSubmitting = false
        pendingRailId = nil

        loadBundleTask = Task {
            defer {
                // Ignore stale/cancelled completions so a newer request owns loading state.
                if !Task.isCancelled, selectedClubId == clubId {
                    isLoading = false
                }
            }
            do {
                let fetched = try await supabaseService.fetchClubBundle(clubId: clubId, forceRefresh: true)
                guard !Task.isCancelled, selectedClubId == clubId else { return }
                bundle = fetched
            } catch {
                guard !Task.isCancelled, selectedClubId == clubId else { return }
                errorText = "Could not load rails."
            }
        }
    }

    private func addToRail(railId: String, clubId: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        pendingRailId = clubsInteractionV2Enabled ? railId : nil
        let startedAt = supabaseService.beginInteractionTiming()
        supabaseService.trackInteractionEvent(
            "clubs_add_to_rail_tap",
            surface: "club_activity_add_sheet",
            result: "attempt",
            extra: ["club_id": clubId]
        )
        defer { isSubmitting = false }
        do {
            _ = try await supabaseService.addRailItem(
                railId: railId,
                mediaType: mediaType.uppercased(),
                mediaId: mediaId
            )
            // Refresh the club bundle so the club view and activity cache update quickly.
            _ = try? await supabaseService.refreshClubBundle(clubId: clubId)
            supabaseService.trackInteractionEvent(
                "clubs_add_to_rail_success",
                surface: "club_activity_add_sheet",
                result: "ok",
                startedAt: startedAt,
                extra: ["club_id": clubId]
            )
            KuroAccessibility.successHaptic()
            dismiss()
        } catch {
            KuroAccessibility.errorHaptic()
            let msg = "\(error)"
            if msg.contains("NOT_A_MEMBER") {
                errorText = "You're no longer a member of this club."
                bundle = nil
            } else {
                errorText = "Could not add to rail."
            }
            pendingRailId = nil
            supabaseService.trackInteractionEvent(
                "clubs_add_to_rail_error",
                surface: "club_activity_add_sheet",
                result: "error",
                startedAt: startedAt,
                extra: ["club_id": clubId]
            )
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
        if let tracking = counts["_tracking_count"], tracking > 0 {
            let notStarted = max(0, memberCount - tracking)
            if notStarted > 0 {
                return "\(tracking) tracking \u{00B7} \(notStarted) not started"
            }
            return "\(tracking) tracking"
        }
        var parts: [String] = []
        let watching = (counts["CURRENT"] ?? 0) + (counts["WATCHING"] ?? 0) + (counts["READING"] ?? 0)
        let completed = counts["COMPLETED"] ?? 0
        let planning = (counts["PLANNING"] ?? 0) + (counts["PLANNED"] ?? 0)
        let paused = (counts["PAUSED"] ?? 0) + (counts["ON_HOLD"] ?? 0)
        let dropped = counts["DROPPED"] ?? 0
        if watching > 0 { parts.append("\(watching) watching") }
        if completed > 0 { parts.append("\(completed) completed") }
        if planning > 0 { parts.append("\(planning) planning") }
        if paused > 0 { parts.append("\(paused) paused") }
        if dropped > 0 { parts.append("\(dropped) dropped") }
        let tracked = counts
            .filter { $0.key != "_tracking_count" }
            .reduce(0) { $0 + $1.value }
        let notStarted = max(0, memberCount - tracked)
        if notStarted > 0 { parts.append("\(notStarted) not started") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var canShowMemberDetail: Bool {
        sharingLevel != "private" && memberCount >= 3
    }

    /// Format progress with fraction when total is available.
    private func progressText(current: Int, total: Int?) -> String {
        let prefix = item.media_type.uppercased() == "ANIME" ? "Ep" : "Ch"
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
                    .foregroundColor(.black.opacity(0.55))
            }

            if let myStatus = item.my_status {
                HStack(spacing: 6) {
                    Text("You:")
                        .font(.kuroCaption())
                        .foregroundColor(.black.opacity(0.55))
                    ClubStatusPill(status: myStatus)
                    if let progress = item.my_progress, progress > 0 {
                        Text(progressText(current: progress, total: item.totalCount))
                            .font(.kuroCaption())
                            .foregroundColor(.black.opacity(0.45))
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
                    Text(showMembers ? "Hide members" : "\(members.count) members")
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
    private let statusByUserId: [String: SupabaseService.ClubRailItem.MemberItemStatus]

    init(
        statuses: [SupabaseService.ClubRailItem.MemberItemStatus],
        members: [SupabaseService.ClubMember],
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

        var statusMap: [String: SupabaseService.ClubRailItem.MemberItemStatus] = [:]
        for s in statuses {
            statusMap[s.user_id] = s
        }
        self.statusByUserId = statusMap
    }

    private func memberLabel(_ userId: String) -> String? {
        if let currentUserId, userId == currentUserId { return "You" }
        if let displayName = displayNameById[userId] { return displayName }
        if let role = roleById[userId], role.lowercased() != "member" {
            return role.capitalized
        }
        return nil
    }

    private func memberInitial(_ label: String?, userId: String) -> String {
        if let label, !label.isEmpty, let first = label.first {
            return String(first).uppercased()
        }
        let compact = userId.replacingOccurrences(of: "-", with: "")
        let suffix = compact.suffix(2).uppercased()
        return suffix.isEmpty ? "?" : suffix
    }

    /// Whether the member updated their list entry within the last 7 days.
    private func isActive(_ ms: SupabaseService.ClubRailItem.MemberItemStatus) -> Bool {
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
    private func progressFraction(_ ms: SupabaseService.ClubRailItem.MemberItemStatus) -> Double? {
        guard sharingLevel == "progress",
              let progress = ms.progress, progress > 0,
              let total = totalCount, total > 0 else { return nil }
        return min(1.0, Double(progress) / Double(total))
    }

    /// Format progress text with fraction.
    private func progressText(_ progress: Int) -> String {
        let prefix = mediaType.uppercased() == "ANIME" ? "Ep" : "Ch"
        if let total = totalCount, total > 0 {
            return "\(prefix) \(progress)/\(total)"
        }
        return "\(prefix) \(progress)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            let merged = members.map { member -> SupabaseService.ClubRailItem.MemberItemStatus in
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
                            .foregroundColor(.black.opacity(0.50))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: KuroRadius.xs)
                                    .fill(Color.black.opacity(0.06))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                if let label {
                                    Text(label)
                                        .font(.kuroCaption(weight: .medium))
                                        .foregroundColor(.black.opacity(0.70))
                                }

                                if let role = roleById[ms.user_id]?.uppercased(), role != "MEMBER" {
                                    Text(role)
                                        .font(.kuroMicro(weight: .medium))
                                        .tracking(1.0)
                                        .foregroundColor(.kuroTextTertiary)
                                }

                                if active && !isMe {
                                    Circle()
                                        .fill(Color.black.opacity(0.30))
                                        .frame(width: 4, height: 4)
                                }
                            }

                            HStack(spacing: 6) {
                                if let status = ms.status {
                                    ClubStatusPill(status: status)
                                } else {
                                    Text("Not started")
                                        .font(.kuroCaption())
                                        .foregroundColor(.kuroTextTertiary)
                                }

                                if sharingLevel == "progress",
                                   let progress = ms.progress, progress > 0 {
                                    Text(progressText(progress))
                                        .font(.kuroCaption())
                                        .foregroundColor(.black.opacity(0.40))
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
                                    .fill(Color.black.opacity(0.06))
                                    .frame(height: 2)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.black.opacity(0.25))
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
