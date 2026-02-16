// MARK: - CLUB DETAIL VIEW
// Three-tab detail view for a club: Rails, This Week, Polls.
// Uses segmented picker, @Observable pattern, KuroDesignSystem tokens throughout.

import SwiftUI
import PostgREST

struct ClubDetailView: View {
    let clubId: String

    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case rails = "RAILS"
        case thisWeek = "THIS WEEK"
        case polls = "POLLS"
        case chat = "CHAT"

        static var visibleCases: [Tab] {
            var tabs: [Tab] = [.rails, .thisWeek, .polls]
            if FeatureFlags.shared.isClubsChatV1Enabled {
                tabs.append(.chat)
            }
            return tabs
        }
    }

    @State private var selectedTab: Tab = .rails
    @State private var bundle: SupabaseService.ClubBundle? = nil
    @State private var isLoading = true
    @State private var errorText: String? = nil
    @State private var showSettings = false
    @State private var showCreateRail = false
    @State private var showCreatePoll = false
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var voteInFlightPollIds: Set<String> = []
    @State private var optimisticVoteByPollId: [String: String] = [:]
    @State private var optimisticVoteCountsByPollId: [String: [String: Int]] = [:]
    @State private var addToRailId: String? = nil

    private var clubsInteractionV2Enabled: Bool {
        FeatureFlags.shared.isClubsInteractionV2Enabled
    }

    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            if isLoading && bundle == nil {
                VStack(spacing: KuroDesignSpacing.md) {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.kuroBlack60)
                    Text("Loading club...")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack60)
                }
            } else if let errorText {
                VStack(spacing: KuroDesignSpacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.kuroBlack30)
                    Text(errorText)
                        .font(.kuroCaption())
                        .foregroundColor(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadBundle(force: true) }
                    }
                    .font(.kuroCaption(weight: .medium))
                    .foregroundColor(.black.opacity(0.70))
                }
                .padding(.horizontal, 20)
            } else if let bundle {
                clubContent(bundle)
            }

            if let toast {
                VStack {
                    Spacer()
                    KuroToast(toast: toast)
                        .padding(.horizontal, KuroDesignSpacing.md)
                        .padding(.bottom, 92)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(bundle?.club.name ?? "Club")
                    .font(.kuroNavigation(weight: .regular))
                    .tracking(1.5)
            }
            if bundle != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        showSettings = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.kuroBlack60)
                    }
                }
            }
        }
        .task {
            supabaseService.markClubSeen(clubId: clubId)
            await loadBundle()
            await supabaseService.subscribeToClubUpdates(clubId: clubId)
        }
        .onDisappear {
            Task { await supabaseService.unsubscribeFromClubUpdates() }
        }
        .refreshable {
            await loadBundle(force: true)
        }
        .sheet(isPresented: $showSettings) {
            if let bundle {
                ClubSettingsSheet(bundle: bundle, clubId: clubId) {
                    Task { await loadBundle(force: true) }
                }
                .environment(supabaseService)
            }
        }
        .sheet(isPresented: $showCreateRail) {
            CreateClubRailSheet(clubId: clubId) {
                showToast(.success, title: "Rail created", subtitle: nil)
                Task { await loadBundle(force: true) }
            }
            .environment(supabaseService)
        }
        .sheet(isPresented: $showCreatePoll) {
            CreateClubPollSheet(clubId: clubId) {
                showToast(.success, title: "Poll created", subtitle: nil)
                Task { await loadBundle(force: true) }
            }
            .environment(supabaseService)
        }
        .sheet(isPresented: Binding(
            get: { addToRailId != nil },
            set: { if !$0 { addToRailId = nil } }
        )) {
            if let railId = addToRailId {
                AddItemToRailSheet(railId: railId, clubId: clubId) {
                    showToast(.success, title: "Item added", subtitle: nil)
                    Task { await loadBundle(force: true) }
                }
                .environment(supabaseService)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func clubContent(_ bundle: SupabaseService.ClubBundle) -> some View {
        VStack(spacing: 0) {
            // Header info
            clubHeader(bundle)

            // Tab picker
            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.visibleCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, KuroDesignSpacing.sm)

            EditorialLayout.divider()

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.black.opacity(0.45))
                    Text("Refreshing...")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.45))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }

            // Tab content
            if selectedTab == .chat {
                ClubChatTab(clubId: clubId, bundle: bundle)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    switch selectedTab {
                    case .rails:
                        railsTab(bundle)
                    case .thisWeek:
                        thisWeekTab(bundle)
                    case .polls:
                        pollsTab(bundle)
                    case .chat:
                        EmptyView()
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 24)
                }
            }
        }
    }

    // MARK: - Header

    private func clubHeader(_ bundle: SupabaseService.ClubBundle) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: KuroDesignSpacing.sm) {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .regular))
                    Text("\(bundle.member_count)")
                        .font(.kuroMicro(weight: .medium))
                }
                .foregroundColor(.black.opacity(0.45))

                Text(bundle.club.sharing_level.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.black.opacity(0.45))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.6)
                    )

                if !bundle.polls.filter({ !$0.is_closed }).isEmpty {
                    HStack(spacing: 3) {
                        Circle().fill(Color.black.opacity(0.40)).frame(width: 5, height: 5)
                        Text("POLL")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.40))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, KuroDesignSpacing.sm)
    }

    // MARK: - Rails Tab

    @ViewBuilder
    private func railsTab(_ bundle: SupabaseService.ClubBundle) -> some View {
        if bundle.rails.isEmpty {
            VStack(spacing: KuroDesignSpacing.md) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.kuroBlack30)
                Text("No rails yet")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack30)
                if ["owner", "admin"].contains(bundle.my_role) {
                    Text("Create a rail to start curating together.")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.40))

                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        showCreateRail = true
                    } label: {
                        Text("CREATE RAIL")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.2)
                            .foregroundColor(.black.opacity(0.70))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .stroke(Color.black.opacity(0.20), lineWidth: 0.8)
                            )
                    }
                    .padding(.top, KuroDesignSpacing.sm)
                }
            }
            .padding(.top, KuroDesignSpacing.xxl)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if ["owner", "admin"].contains(bundle.my_role) {
                    HStack {
                        Spacer()
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            showCreateRail = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .medium))
                                Text("RAIL")
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                            }
                            .foregroundColor(.black.opacity(0.55))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.06))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, KuroDesignSpacing.sm)
                }

                // Milestone celebrations (all members completed)
                if FeatureFlags.shared.isClubsPaceSyncV1Enabled {
                    let milestones = bundle.rails.flatMap { rail in
                        rail.items.compactMap { item -> SupabaseService.ClubRailItem? in
                            guard bundle.member_count >= 3,
                                  let counts = item.member_status_counts,
                                  let completed = counts["COMPLETED"],
                                  completed >= bundle.member_count else { return nil }
                            return item
                        }
                    }
                    if !milestones.isEmpty {
                        VStack(spacing: KuroDesignSpacing.sm) {
                            ForEach(milestones) { item in
                                ClubMilestoneCard(item: item, memberCount: bundle.member_count)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, KuroDesignSpacing.sm)
                    }
                }

                LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.xl) {
                    ForEach(bundle.rails) { rail in
                        ClubRailSection(
                            rail: rail,
                            memberCount: bundle.member_count,
                            onAddItem: canAddToRail(rail, role: bundle.my_role) ? {
                                addToRailId = rail.id
                            } : nil
                        )
                    }
                }
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
        }
    }

    // MARK: - This Week Tab

    @ViewBuilder
    private func thisWeekTab(_ bundle: SupabaseService.ClubBundle) -> some View {
        let watchingItems = bundle.rails.flatMap { rail in
            rail.items.compactMap { item -> (rail: SupabaseService.ClubRail, item: SupabaseService.ClubRailItem)? in
                guard let status = item.my_status?.uppercased(),
                      status == "CURRENT" || status == "WATCHING" || status == "READING" else {
                    return nil
                }
                return (rail: rail, item: item)
            }
        }

        if watchingItems.isEmpty {
            VStack(spacing: KuroDesignSpacing.md) {
                Image(systemName: "tv")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.kuroBlack30)
                Text("Nobody watching anything this week")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack30)
            }
            .padding(.top, KuroDesignSpacing.xxl)
        } else {
            LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                ForEach(watchingItems, id: \.item.id) { entry in
                    ThisWeekRow(
                        item: entry.item,
                        railTitle: entry.rail.title,
                        memberCount: bundle.member_count,
                        sharingLevel: bundle.club.sharing_level
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, KuroDesignSpacing.md)
            .padding(.bottom, KuroDesignSpacing.xxl)
        }
    }

    // MARK: - Polls Tab

    @ViewBuilder
    private func pollsTab(_ bundle: SupabaseService.ClubBundle) -> some View {
        let openPolls = bundle.polls.filter { !$0.is_closed }
        let closedPolls = bundle.polls.filter { $0.is_closed }

        if bundle.polls.isEmpty {
            VStack(spacing: KuroDesignSpacing.md) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.kuroBlack30)
                Text("No polls yet")
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack30)
                if ["owner", "admin"].contains(bundle.my_role) {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        showCreatePoll = true
                    } label: {
                        Text("CREATE POLL")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.2)
                            .foregroundColor(.black.opacity(0.70))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .stroke(Color.black.opacity(0.20), lineWidth: 0.8)
                            )
                    }
                    .padding(.top, KuroDesignSpacing.sm)
                }
            }
            .padding(.top, KuroDesignSpacing.xxl)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if ["owner", "admin"].contains(bundle.my_role) {
                    HStack {
                        Spacer()
                        Button {
                            KuroAccessibility.impactHaptic(.light)
                            showCreatePoll = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .medium))
                                Text("POLL")
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                            }
                            .foregroundColor(.black.opacity(0.55))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.06))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, KuroDesignSpacing.sm)
                }

            LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                if !openPolls.isEmpty {
                    ForEach(openPolls) { poll in
                        ClubPollCard(
                            poll: poll,
                            myRole: bundle.my_role,
                            isSubmittingVote: clubsInteractionV2Enabled && voteInFlightPollIds.contains(poll.id),
                            optimisticMyVoteOptionId: clubsInteractionV2Enabled ? optimisticVoteByPollId[poll.id] : nil,
                            optimisticVoteCounts: clubsInteractionV2Enabled ? optimisticVoteCountsByPollId[poll.id] : nil,
                            onVote: { optionId in
                                Task {
                                    if clubsInteractionV2Enabled {
                                        await voteOnPoll(poll: poll, optionId: optionId)
                                    } else {
                                        try? await supabaseService.castVote(pollId: poll.id, optionId: optionId)
                                        KuroAccessibility.impactHaptic(.light)
                                        await loadBundle(force: true)
                                    }
                                }
                            }
                        )
                    }
                }

                if !closedPolls.isEmpty {
                    Text("CLOSED")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.6)
                        .foregroundColor(.kuroBlack30)
                        .padding(.top, KuroDesignSpacing.sm)

                    ForEach(closedPolls) { poll in
                        ClubPollCard(
                            poll: poll,
                            myRole: bundle.my_role,
                            isSubmittingVote: false,
                            optimisticMyVoteOptionId: nil,
                            optimisticVoteCounts: nil,
                            onVote: { _ in }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, KuroDesignSpacing.md)
            .padding(.bottom, KuroDesignSpacing.xxl)
            }
        }
    }

    // MARK: - Load

    private func loadBundle(force: Bool = false) async {
        isLoading = true
        errorText = nil
        do {
            bundle = try await supabaseService.fetchClubBundle(clubId: clubId, forceRefresh: force)
            optimisticVoteByPollId.removeAll()
            optimisticVoteCountsByPollId.removeAll()
        } catch {
            let msg = "\(error)"
            if msg.contains("NOT_A_MEMBER") {
                handleMembershipLoss()
            } else {
                errorText = "Could not load club data."
            }
        }
        isLoading = false
    }

    private func voteOnPoll(poll: SupabaseService.ClubPoll, optionId: String) async {
        guard !poll.is_closed else { return }
        guard poll.my_vote_option_id != optionId else { return }
        guard !voteInFlightPollIds.contains(poll.id) else { return }

        voteInFlightPollIds.insert(poll.id)
        let startedAt = supabaseService.beginInteractionTiming()
        supabaseService.trackInteractionEvent(
            "clubs_vote_tap",
            surface: "club_detail_polls",
            result: "attempt",
            extra: ["club_id": clubId]
        )

        // Optimistic vote state for instant visual response.
        var counts: [String: Int] = [:]
        for option in poll.options {
            counts[option.id] = option.vote_count
        }
        if let previous = poll.my_vote_option_id {
            counts[previous] = max(0, (counts[previous] ?? 0) - 1)
        }
        counts[optionId] = (counts[optionId] ?? 0) + 1
        optimisticVoteByPollId[poll.id] = optionId
        optimisticVoteCountsByPollId[poll.id] = counts
        KuroAccessibility.impactHaptic(.light)

        defer { voteInFlightPollIds.remove(poll.id) }

        do {
            try await supabaseService.castVote(pollId: poll.id, optionId: optionId)
            bundle = try await supabaseService.refreshClubBundle(clubId: clubId)
            optimisticVoteByPollId.removeAll()
            optimisticVoteCountsByPollId.removeAll()
            supabaseService.trackInteractionEvent(
                "clubs_vote_success",
                surface: "club_detail_polls",
                result: "ok",
                startedAt: startedAt,
                extra: ["club_id": clubId]
            )
            KuroAccessibility.successHaptic()
        } catch {
            optimisticVoteByPollId[poll.id] = nil
            optimisticVoteCountsByPollId[poll.id] = nil
            let msg = "\(error)"
            if msg.contains("NOT_A_MEMBER") {
                handleMembershipLoss()
            } else {
                showToast(.error, title: "Vote failed", subtitle: "Please try again.")
            }
            supabaseService.trackInteractionEvent(
                "clubs_vote_error",
                surface: "club_detail_polls",
                result: "error",
                startedAt: startedAt,
                extra: ["club_id": clubId]
            )
            KuroAccessibility.errorHaptic()
        }
    }

    private func showToast(_ kind: KuroToastState.Kind, title: String, subtitle: String?) {
        toastDismissTask?.cancel()
        withAnimation(KuroAnimation.fast) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(KuroAnimation.fast) { toast = nil }
        }
    }

    private func canAddToRail(_ rail: SupabaseService.ClubRail, role: String) -> Bool {
        if !rail.is_locked { return true }
        return ["owner", "admin"].contains(role)
    }

    private func handleMembershipLoss() {
        bundle = nil
        errorText = "You're no longer a member of this club."
        showToast(.error, title: "Access updated", subtitle: "You were removed from this club.")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        }
    }
}

// MARK: - Club Rail Section

private struct ClubRailSection: View {
    let rail: SupabaseService.ClubRail
    let memberCount: Int
    var onAddItem: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            // Rail header
            HStack(spacing: 8) {
                Text(rail.title.uppercased())
                    .font(.kuroTitle(weight: .regular))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(1)

                if rail.is_locked {
                    Image(systemName: "lock.fill")
                        .font(.kuroMicro())
                        .foregroundColor(.kuroTextTertiary)
                }

                Spacer()

                if let onAddItem {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onAddItem()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black.opacity(0.55))
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            EditorialLayout.divider()
                .padding(.horizontal, 20)

            // Horizontal scroll of items
            if rail.items.isEmpty {
                Text("No items yet")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, KuroDesignSpacing.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(rail.items) { item in
                            VStack(spacing: 6) {
                                ClubRailItemCard(item: item, memberCount: memberCount)
                                if FeatureFlags.shared.isClubsReactionsV1Enabled {
                                    ClubReactionRow(item: item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .kuroSwipeExclusionZone()
            }
        }
    }
}

// MARK: - Club Rail Item Card

private struct ClubRailItemCard: View {
    let item: SupabaseService.ClubRailItem
    let memberCount: Int

    @State private var showDetail = false
    @State private var showAddToList = false
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private let cardWidth: CGFloat = 110
    private var cardHeight: CGFloat { cardWidth / 0.7 }

    private var mediaKind: MediaKind {
        item.media_type.uppercased() == "MANGA" ? .manga : .anime
    }

    private var mediaType: String {
        mediaKind.rawValue
    }

    private var isInCollection: Bool {
        supabaseService.isInCollection(mediaId: item.media_id, mediaType: mediaType)
    }

    private var aggregateText: String? {
        guard let counts = item.member_status_counts else { return nil }
        // _tracking_count = privacy-safe generic count
        if let tracking = counts["_tracking_count"], tracking > 0 {
            return "\(tracking) tracking"
        }
        let total = counts.values.reduce(0, +)
        if total == 0 { return nil }
        let completed = counts["COMPLETED"] ?? 0
        if completed > 0 {
            return "\(completed)/\(memberCount) done"
        }
        return "\(total)/\(memberCount) tracking"
    }

    private var statusColor: Color {
        // Monochrome to match editorial palette — no colored dots
        item.my_status != nil ? Color.black.opacity(0.55) : .clear
    }

    var body: some View {
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .top) {
                    KuroCachedAsyncImage(url: URL(string: item.cover_image_medium ?? ""), maxPixelSize: 300) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                        case .failure, .empty:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: cardWidth, height: cardHeight)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    // Badges
                    HStack(alignment: .top) {
                        // My status dot
                        if item.my_status != nil {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: statusColor.opacity(0.5), radius: 2, x: 0, y: 1)
                        }

                        Spacer()

                        if let score = item.average_score, score > 0 {
                            KuroScoreBadge(score: Double(score) / 10.0)
                        }
                    }
                    .padding(6)

                    // Aggregate pill at bottom
                    if let text = aggregateText {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(text)
                                    .font(.kuroMicro(weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(Color.black.opacity(0.70))
                                    )
                            }
                            .padding(6)
                        }
                        .frame(width: cardWidth, height: cardHeight)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title_display.uppercased())
                        .font(.system(size: 12, weight: .light, design: .serif))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundColor(.black.opacity(0.9))
                        .lineLimit(2)
                        .frame(height: 32, alignment: .top)

                    HStack(spacing: 4) {
                        if let year = item.year {
                            Text("\(year)")
                                .font(.system(size: 9, weight: .light))
                                .foregroundColor(.black.opacity(0.5))
                        }
                        if let format = item.format {
                            Text(format.lowercased())
                                .font(.system(size: 9, weight: .light))
                                .foregroundColor(.black.opacity(0.5))
                        }
                    }
                }
                .frame(width: cardWidth, alignment: .topLeading)
                .padding(.top, 10)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                supabaseService.toggleInCollection(mediaId: item.media_id, mediaType: mediaType)
            }) {
                Label(
                    isInCollection ? "Remove from List" : "Quick Add (Planned)",
                    systemImage: isInCollection ? "minus.circle" : "plus.circle"
                )
            }
        }
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: mediaKind, id: item.media_id)
        }
    }
}

// MARK: - This Week Row

private struct ThisWeekRow: View {
    let item: SupabaseService.ClubRailItem
    let railTitle: String
    let memberCount: Int
    var sharingLevel: String = "status"

    @State private var showDetail = false

    private var mediaKind: MediaKind {
        item.media_type.uppercased() == "MANGA" ? .manga : .anime
    }

    private var progressText: String {
        if let progress = item.my_progress, progress > 0 {
            let prefix = item.media_type.uppercased() == "ANIME" ? "EP" : "CH"
            return "\(prefix) \(progress)"
        }
        return ""
    }

    private var paceText: String? {
        guard FeatureFlags.shared.isClubsPaceSyncV1Enabled else { return nil }
        guard sharingLevel == "progress", memberCount >= 3 else { return nil }
        guard let statuses = item.member_statuses, !statuses.isEmpty else { return nil }
        guard let myProgress = item.my_progress else { return nil }

        let otherProgresses = statuses
            .filter { $0.progress != nil }
            .map { $0.progress! }
            .sorted()

        guard !otherProgresses.isEmpty else { return nil }

        let median: Int
        let count = otherProgresses.count
        if count % 2 == 0 {
            median = (otherProgresses[count / 2 - 1] + otherProgresses[count / 2]) / 2
        } else {
            median = otherProgresses[count / 2]
        }

        let diff = myProgress - median
        if diff == 0 { return "In sync" }
        let unit = item.media_type.uppercased() == "ANIME" ? "ep" : "ch"
        if diff < 0 { return "\(abs(diff)) \(unit) behind the group" }
        return "\(diff) \(unit) ahead"
    }

    private var othersText: String? {
        guard let counts = item.member_status_counts else { return nil }
        if let tracking = counts["_tracking_count"], tracking > 0 {
            return "\(tracking) also tracking"
        }
        let watching = (counts["CURRENT"] ?? 0) + (counts["WATCHING"] ?? 0) + (counts["READING"] ?? 0)
        let completed = counts["COMPLETED"] ?? 0
        if completed > 0 {
            return "\(completed) finished"
        }
        if watching > 0 {
            return "\(watching) watching"
        }
        return nil
    }

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        } label: {
            HStack(spacing: KuroDesignSpacing.md) {
                KuroCachedAsyncImage(url: URL(string: item.cover_image_medium ?? ""), maxPixelSize: 200) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 68)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 48, height: 68)
                    }
                }
                .frame(width: 48, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title_display)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(0.85))
                        .lineLimit(2)

                    if !progressText.isEmpty {
                        Text(progressText)
                            .font(.kuroCaption(weight: .medium))
                            .foregroundColor(.black.opacity(0.55))
                    }

                    if let pace = paceText {
                        Text(pace)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.45))
                    }

                    if let othersText {
                        Text(othersText)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.40))
                    }
                }

                Spacer()
            }
            .padding(.vertical, KuroDesignSpacing.xs)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: mediaKind, id: item.media_id)
        }
    }
}

// MARK: - Club Chat Tab

private struct ClubChatTab: View {
    let clubId: String
    let bundle: SupabaseService.ClubBundle

    @Environment(SupabaseService.self) private var supabaseService
    @State private var messages: [SupabaseService.ClubMessage] = []
    @State private var messageText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var hasMorePages = true
    @FocusState private var isInputFocused: Bool

    private var currentUserId: String? {
        supabaseService.currentUserId
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: KuroDesignSpacing.sm) {
                        if hasMorePages && !isLoading {
                            Button("Load earlier messages") {
                                Task { await loadMore() }
                            }
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.45))
                            .padding(.vertical, KuroDesignSpacing.sm)
                        }

                        if isLoading && messages.isEmpty {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.black.opacity(0.45))
                                .padding(.vertical, KuroDesignSpacing.xl)
                        }

                        ForEach(messages) { msg in
                            ClubChatBubble(
                                message: msg,
                                isOwnMessage: msg.user_id == currentUserId,
                                members: bundle.members
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, KuroDesignSpacing.md)
                    .padding(.bottom, KuroDesignSpacing.sm)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            EditorialLayout.divider()

            // Input bar
            HStack(spacing: KuroDesignSpacing.sm) {
                TextField("Message...", text: $messageText, axis: .vertical)
                    .font(.kuroBody(weight: .light))
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onChange(of: messageText) { _, newValue in
                        if newValue.count > 280 {
                            messageText = String(newValue.prefix(280))
                        }
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(
                            canSend ? .black.opacity(0.80) : .black.opacity(0.20)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.kuroBackground)
        }
        .task {
            await loadMessages()
        }
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func loadMessages() async {
        isLoading = true
        do {
            messages = try await supabaseService.fetchClubMessages(clubId: clubId)
            hasMorePages = messages.count >= 50
        } catch {
            #if DEBUG
            print("❌ loadMessages: \(error)")
            #endif
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let oldest = messages.first else { return }
        do {
            let older = try await supabaseService.fetchClubMessages(
                clubId: clubId, limit: 50, before: oldest.created_at
            )
            if older.isEmpty {
                hasMorePages = false
            } else {
                messages.insert(contentsOf: older, at: 0)
                hasMorePages = older.count >= 50
            }
        } catch {
            #if DEBUG
            print("❌ loadMore: \(error)")
            #endif
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        messageText = ""

        // Optimistic local message
        let optimisticMsg = SupabaseService.ClubMessage(
            id: UUID().uuidString,
            user_id: currentUserId ?? "",
            display_name: nil,
            text: text,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        messages.append(optimisticMsg)

        Task {
            do {
                let resp = try await supabaseService.sendClubMessage(clubId: clubId, text: text)
                // Replace optimistic message with server response
                if let idx = messages.firstIndex(where: { $0.id == optimisticMsg.id }) {
                    messages[idx] = SupabaseService.ClubMessage(
                        id: resp.message_id,
                        user_id: currentUserId ?? "",
                        display_name: nil,
                        text: text,
                        created_at: resp.created_at
                    )
                }
            } catch {
                // Remove optimistic message on failure
                messages.removeAll { $0.id == optimisticMsg.id }
                KuroAccessibility.errorHaptic()
            }
            isSending = false
        }
    }
}

// MARK: - Club Chat Bubble

private struct ClubChatBubble: View {
    let message: SupabaseService.ClubMessage
    let isOwnMessage: Bool
    let members: [SupabaseService.ClubMember]

    private var displayName: String {
        if let name = message.display_name, !name.isEmpty { return name }
        if let member = members.first(where: { $0.user_id == message.user_id }),
           let name = member.display_name, !name.isEmpty {
            return name
        }
        return String(message.user_id.prefix(8))
    }

    private var initial: String {
        String(displayName.prefix(1)).uppercased()
    }

    private var relativeTime: String {
        guard let date = SupabaseService.parseISO8601(message.created_at) else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isOwnMessage {
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(initial)
                            .font(.kuroMicro(weight: .medium))
                            .foregroundColor(.black.opacity(0.55))
                    )
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 2) {
                if !isOwnMessage {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.kuroMicro(weight: .medium))
                            .foregroundColor(.black.opacity(0.50))
                        Text(relativeTime)
                            .font(.kuroMicro())
                            .foregroundColor(.black.opacity(0.30))
                    }
                }

                Text(message.text)
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.black.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(isOwnMessage ? 0.08 : 0.04))
                    )

                if isOwnMessage {
                    Text(relativeTime)
                        .font(.kuroMicro())
                        .foregroundColor(.black.opacity(0.30))
                }
            }

            if isOwnMessage {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwnMessage ? .trailing : .leading)
    }
}

// MARK: - Club Milestone Card

private struct ClubMilestoneCard: View {
    let item: SupabaseService.ClubRailItem
    let memberCount: Int

    var body: some View {
        KuroGlassCard(cornerRadius: KuroRadius.lg) {
            HStack(spacing: KuroDesignSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black.opacity(0.55))

                VStack(alignment: .leading, spacing: 2) {
                    Text("COMPLETED TOGETHER")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(.black.opacity(0.50))

                    Text("All \(memberCount) members finished \(item.title_display)")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.black.opacity(0.65))
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.horizontal, KuroDesignSpacing.md)
            .padding(.vertical, KuroDesignSpacing.sm)
        }
    }
}

// MARK: - Club Poll Card

private struct ClubPollCard: View {
    let poll: SupabaseService.ClubPoll
    let myRole: String
    let isSubmittingVote: Bool
    let optimisticMyVoteOptionId: String?
    let optimisticVoteCounts: [String: Int]?
    let onVote: (String) -> Void

    private var totalVotes: Int {
        if let optimisticVoteCounts {
            return optimisticVoteCounts.values.reduce(0, +)
        }
        return poll.options.reduce(0) { $0 + $1.vote_count }
    }

    private var hasVoted: Bool {
        (optimisticMyVoteOptionId ?? poll.my_vote_option_id) != nil
    }

    var body: some View {
        KuroGlassCard(cornerRadius: KuroRadius.lg) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                HStack {
                    Text(poll.question)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(0.85))
                        .lineLimit(3)

                    Spacer()

                    if poll.is_closed {
                        Text("CLOSED")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(.black.opacity(0.40))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .stroke(Color.black.opacity(0.12), lineWidth: 0.6)
                            )
                    }
                }

                ForEach(poll.options) { option in
                    let renderedCount = optimisticVoteCounts?[option.id] ?? option.vote_count
                    ClubPollOptionRow(
                        option: option,
                        displayVoteCount: renderedCount,
                        totalVotes: totalVotes,
                        isMyVote: (optimisticMyVoteOptionId ?? poll.my_vote_option_id) == option.id,
                        hasVoted: hasVoted,
                        isClosed: poll.is_closed,
                        isSubmittingVote: isSubmittingVote,
                        onTap: {
                            guard !poll.is_closed else { return }
                            guard (optimisticMyVoteOptionId ?? poll.my_vote_option_id) != option.id else { return }
                            guard !isSubmittingVote else { return }
                            onVote(option.id)
                        }
                    )
                }

                if totalVotes > 0 {
                    Text("\(totalVotes) vote\(totalVotes == 1 ? "" : "s")")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                }
            }
            .padding(KuroDesignSpacing.md)
        }
    }
}

// MARK: - Poll Option Row

private struct ClubPollOptionRow: View {
    let option: SupabaseService.ClubPollOption
    let displayVoteCount: Int
    let totalVotes: Int
    let isMyVote: Bool
    let hasVoted: Bool
    let isClosed: Bool
    let isSubmittingVote: Bool
    let onTap: () -> Void

    private var fraction: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(displayVoteCount) / Double(totalVotes)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KuroDesignSpacing.sm) {
                // Radio dot
                Circle()
                    .fill(isMyVote ? Color.black : Color.clear)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(isMyVote ? 1.0 : 0.30), lineWidth: 1.2)
                    )

                Text(option.label)
                    .font(.kuroCaption(weight: isMyVote ? .medium : .light))
                    .foregroundColor(.black.opacity(0.80))
                    .lineLimit(2)

                Spacer()

                if hasVoted || isClosed {
                    Text("\(displayVoteCount)")
                        .font(.kuroMicro(weight: .medium))
                        .foregroundColor(.black.opacity(0.50))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                GeometryReader { geo in
                    if hasVoted || isClosed {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(isMyVote ? 0.08 : 0.03))
                            .frame(width: geo.size.width * fraction)
                            .animation(KuroAnimation.editorial, value: fraction)
                    }
                }
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .disabled(isClosed || isSubmittingVote)
    }
}

// MARK: - Club Reaction Row

private struct ClubReactionRow: View {
    let item: SupabaseService.ClubRailItem

    @Environment(SupabaseService.self) private var supabaseService
    @State private var optimisticReactions: [String: Int]?
    @State private var optimisticMyReactions: Set<String>?

    private static let emojis = ["fire", "heart", "eyes", "100"]
    private static let emojiDisplay: [String: String] = [
        "fire": "\u{1F525}", "heart": "\u{2764}\u{FE0F}", "eyes": "\u{1F440}", "100": "\u{1F4AF}"
    ]

    private var effectiveReactions: [String: Int] {
        optimisticReactions ?? item.reactions ?? [:]
    }

    private var effectiveMyReactions: Set<String> {
        optimisticMyReactions ?? Set(item.my_reactions ?? [])
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.emojis, id: \.self) { emoji in
                let count = effectiveReactions[emoji] ?? 0
                let isMine = effectiveMyReactions.contains(emoji)
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    toggleReaction(emoji: emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(Self.emojiDisplay[emoji] ?? emoji)
                            .font(.system(size: 11))
                        if count > 0 {
                            Text("\(count)")
                                .font(.kuroMicro(weight: .medium))
                                .foregroundColor(.black.opacity(0.55))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(isMine ? 0.10 : 0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 110, alignment: .leading)
    }

    private func toggleReaction(emoji: String) {
        let isMine = effectiveMyReactions.contains(emoji)
        var newReactions = effectiveReactions
        var newMy = effectiveMyReactions

        if isMine {
            newReactions[emoji] = max(0, (newReactions[emoji] ?? 0) - 1)
            if newReactions[emoji] == 0 { newReactions.removeValue(forKey: emoji) }
            newMy.remove(emoji)
        } else {
            newReactions[emoji] = (newReactions[emoji] ?? 0) + 1
            newMy.insert(emoji)
        }

        optimisticReactions = newReactions
        optimisticMyReactions = newMy

        Task {
            do {
                _ = try await supabaseService.toggleReaction(railItemId: item.id, emoji: emoji)
            } catch {
                optimisticReactions = nil
                optimisticMyReactions = nil
            }
        }
    }
}

// MARK: - Add Item to Rail Sheet

private struct AddItemToRailSheet: View {
    let railId: String
    let clubId: String
    let onAdded: () -> Void

    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss

    enum MediaTab: String, CaseIterable {
        case anime = "ANIME"
        case manga = "MANGA"
    }

    @State private var selectedMedia: MediaTab = .anime
    @State private var searchText = ""
    @State private var animeResults: [AnimeCard] = []
    @State private var mangaResults: [MangaCard] = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Media type toggle
                Picker("Type", selection: $selectedMedia) {
                    ForEach(MediaTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, KuroDesignSpacing.sm)

                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black.opacity(0.35))
                    TextField("Search titles...", text: $searchText)
                        .font(.kuroBody(weight: .light))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                )
                .padding(.horizontal, 20)

                EditorialLayout.divider()
                    .padding(.top, KuroDesignSpacing.sm)

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.top, KuroDesignSpacing.sm)
                }

                // Results
                if isAdding {
                    VStack(spacing: KuroDesignSpacing.md) {
                        ProgressView()
                            .scaleEffect(0.9)
                            .tint(.kuroBlack60)
                        Text("Adding...")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroBlack60)
                    }
                    .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if isSearching && animeResults.isEmpty && mangaResults.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.black.opacity(0.45))
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: KuroDesignSpacing.sm) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(.kuroBlack30)
                        Text("Type to search")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroBlack30)
                    }
                    .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if selectedMedia == .anime && animeResults.isEmpty && !isSearching {
                    Text("No anime found")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack30)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if selectedMedia == .manga && mangaResults.isEmpty && !isSearching {
                    Text("No manga found")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack30)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if selectedMedia == .anime {
                                ForEach(animeResults) { card in
                                    RailSearchResultRow(
                                        title: card.title,
                                        imageURL: card.coverImageMedium,
                                        year: card.year,
                                        format: card.format
                                    ) {
                                        addItem(mediaType: "ANIME", mediaId: card.id)
                                    }
                                }
                            } else {
                                ForEach(mangaResults) { card in
                                    RailSearchResultRow(
                                        title: card.title,
                                        imageURL: card.coverImageMedium,
                                        year: card.year,
                                        format: card.format
                                    ) {
                                        addItem(mediaType: "MANGA", mediaId: card.id)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, KuroDesignSpacing.xxl)
                    }
                }
            }
            .background(Color.kuroBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADD ITEM")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
            .onChange(of: searchText) { _, _ in
                debouncedSearch()
            }
            .onChange(of: selectedMedia) { _, _ in
                debouncedSearch()
            }
            .onDisappear {
                searchTask?.cancel()
                searchTask = nil
            }
        }
    }

    private func debouncedSearch() {
        searchTask?.cancel()
        errorMessage = nil
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            animeResults = []
            mangaResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        do {
            if selectedMedia == .anime {
                animeResults = try await supabaseService.fetchSearchAnimePage(
                    query: query, filters: nil, cursorRank: nil,
                    cursorPopularity: nil, cursorId: nil, limit: 20
                )
            } else {
                mangaResults = try await supabaseService.fetchSearchMangaPage(
                    query: query, filters: nil, cursorRank: nil,
                    cursorPopularity: nil, cursorId: nil, limit: 20
                )
            }
        } catch {
            if !Task.isCancelled {
                // Clear stale results so old rows aren't actionable
                if selectedMedia == .anime { animeResults = [] } else { mangaResults = [] }
                errorMessage = "Search failed. Check your connection and try again."
                #if DEBUG
                print("❌ AddItemToRailSheet search: \(error)")
                #endif
            }
        }
        if !Task.isCancelled {
            isSearching = false
        }
    }

    private func addItem(mediaType: String, mediaId: Int) {
        guard !isAdding else { return }
        isAdding = true
        errorMessage = nil
        Task {
            do {
                _ = try await supabaseService.addRailItem(
                    railId: railId, mediaType: mediaType, mediaId: mediaId
                )
                KuroAccessibility.successHaptic()
                onAdded()
                dismiss()
            } catch let pgError as PostgrestError {
                // Decode structured error from add_club_rail_item RPC
                errorMessage = Self.mapRailItemError(pgError.message)
                KuroAccessibility.errorHaptic()
                isAdding = false
            } catch {
                errorMessage = "Could not add item. Please try again."
                KuroAccessibility.errorHaptic()
                isAdding = false
            }
        }
    }

    /// Maps a PostgrestError message from the add_club_rail_item RPC to a user-facing string.
    private static func mapRailItemError(_ message: String) -> String {
        if message.hasPrefix("DUPLICATE_ITEM") {
            return "This title is already in this rail."
        } else if message.hasPrefix("NOT_A_MEMBER") {
            return "You're no longer a member of this club."
        } else if message.hasPrefix("RAIL_LOCKED") {
            return "This rail is locked. Only admins can add items."
        } else if message.hasPrefix("MEDIA_NOT_FOUND") {
            return "This title was not found in the catalog."
        } else if message.hasPrefix("INVALID_MEDIA_TYPE") {
            return "Invalid media type."
        } else {
            return "Could not add item. Please try again."
        }
    }
}

private struct RailSearchResultRow: View {
    let title: String
    let imageURL: String?
    let year: String
    let format: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                KuroCachedAsyncImage(url: URL(string: imageURL ?? ""), maxPixelSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 56)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 40, height: 56)
                    }
                }
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.black.opacity(0.85))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(year)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.black.opacity(0.45))
                        if let format, !format.isEmpty {
                            Text(format.lowercased())
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.black.opacity(0.45))
                        }
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.black.opacity(0.35))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Club Settings Sheet

private struct ClubSettingsSheet: View {
    let bundle: SupabaseService.ClubBundle
    let clubId: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService

    @State private var isLeaving = false
    @State private var showLeaveConfirm = false
    @State private var leaveConfirmMessage = ""

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    // Club Info
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("CLUB INFO")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.kuroBlack30)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(bundle.club.name)
                                .font(.kuroHeadline(weight: .light))
                                .foregroundColor(.kuroBlack80)

                            if let desc = bundle.club.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.kuroBody(weight: .light))
                                    .foregroundColor(.kuroBlack60)
                            }

                            HStack(spacing: 12) {
                                Label("\(bundle.member_count) members", systemImage: "person.2")
                                    .font(.kuroCaption(weight: .light))
                                    .foregroundColor(.kuroBlack60)

                                Text(bundle.club.sharing_level.uppercased())
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                                    .foregroundColor(.kuroBlack60)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.6)
                                    )
                            }

                            Text(sharingLevelDescription)
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroBlack30)
                        }
                    }

                    EditorialLayout.divider()

                    // Invite Code (owner/admin only)
                    if let code = bundle.club.invite_code {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            Text("INVITE CODE")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                                .foregroundColor(.kuroBlack30)

                            HStack(spacing: 12) {
                                Text(code)
                                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                                    .tracking(2.0)
                                    .foregroundColor(.kuroBlack80)

                                Button {
                                    UIPasteboard.general.string = code
                                    KuroAccessibility.successHaptic()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.kuroBlack60)
                                }
                                .buttonStyle(.plain)
                            }

                            ShareLink(
                                item: "Join my club \"\(bundle.club.name)\" on Kuro! Enter invite code: \(code)",
                                subject: Text("Join \(bundle.club.name) on Kuro"),
                                message: Text("Use this invite code to join: \(code)")
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .regular))
                                    Text("SHARE INVITE")
                                        .font(.kuroCaption(weight: .medium))
                                        .tracking(1.6)
                                }
                                .foregroundColor(.kuroBlack80)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                        .stroke(Color.black.opacity(0.15), lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        EditorialLayout.divider()
                    }

                    // Members
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("MEMBERS")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.kuroBlack30)

                        ForEach(Array(bundle.members.enumerated()), id: \.element.user_id) { index, member in
                            let label = memberDisplayName(member, index: index)
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.black.opacity(0.06))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Text(String(label.prefix(1)).uppercased())
                                            .font(.kuroMicro(weight: .medium))
                                            .foregroundColor(.kuroBlack60)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(label)
                                            .font(.kuroCaption(weight: .medium))
                                            .foregroundColor(.kuroBlack80)

                                        if member.user_id == supabaseService.currentUserId {
                                            Text("YOU")
                                                .font(.kuroMicro(weight: .medium))
                                                .tracking(1.0)
                                                .foregroundColor(.black.opacity(0.50))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule().stroke(Color.black.opacity(0.10), lineWidth: 0.6)
                                                )
                                        }
                                    }

                                    Text(joinedLabel(member.joined_at))
                                        .font(.kuroMicro())
                                        .foregroundColor(.kuroBlack30)
                                }

                                Spacer()

                                Text(member.role.uppercased())
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                                    .foregroundColor(member.role == "owner" ? .black.opacity(0.80) : .black.opacity(0.45))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().stroke(
                                            Color.black.opacity(member.role == "owner" ? 0.20 : 0.08),
                                            lineWidth: 0.6
                                        )
                                    )
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    EditorialLayout.divider()

                    // Leave Club
                    Button {
                        leaveConfirmMessage = computeLeaveMessage()
                        showLeaveConfirm = true
                    } label: {
                        HStack(spacing: 10) {
                            if isLeaving {
                                ProgressView().scaleEffect(0.8).tint(.red.opacity(0.85))
                            }
                            Text("LEAVE CLUB")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                        }
                        .foregroundColor(.red.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                .stroke(Color.red.opacity(0.25), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLeaving)
                    .alert("Leave Club?", isPresented: $showLeaveConfirm) {
                        Button("Leave", role: .destructive) { leaveClub() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text(leaveConfirmMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
            .background(Color.kuroBackground)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.kuroBody(weight: .light))
                }
            }
        }
    }

    private var sharingLevelDescription: String {
        switch bundle.club.sharing_level {
        case "private": return "Only aggregates. Members can't see each other's data."
        case "status": return "Members can see watch/read status but not progress numbers."
        case "progress": return "Members can see full progress, status, and ratings."
        default: return ""
        }
    }

    private func computeLeaveMessage() -> String {
        guard bundle.my_role == "owner" else {
            return "Leave \(bundle.club.name)? You'll need a new invite code to rejoin."
        }
        // Owner leaving: check for successor
        let others = bundle.members.filter { $0.role != "owner" }
        if others.isEmpty {
            return "You're the only member. This club will be deleted."
        }
        // Promote oldest admin, else oldest member
        let admins = others.filter { $0.role == "admin" }.sorted { $0.joined_at < $1.joined_at }
        if let successor = admins.first {
            return "Ownership will transfer to member \(String(successor.user_id.prefix(8)))... You'll need a new invite code to rejoin."
        }
        let sorted = others.sorted { $0.joined_at < $1.joined_at }
        if let successor = sorted.first {
            return "Ownership will transfer to member \(String(successor.user_id.prefix(8)))... You'll need a new invite code to rejoin."
        }
        return "You'll need a new invite code to rejoin."
    }

    private func leaveClub() {
        isLeaving = true
        Task {
            do {
                try await supabaseService.leaveClub(clubId: clubId)
                KuroAccessibility.successHaptic()
                dismiss()
            } catch {
                KuroAccessibility.errorHaptic()
            }
            isLeaving = false
        }
    }

    private func memberDisplayName(_ member: SupabaseService.ClubMember, index: Int) -> String {
        let trimmed = member.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        // Stable short identifier from UUID (consistent across sessions)
        let compact = member.user_id.replacingOccurrences(of: "-", with: "")
        let short = String(compact.prefix(6))
        return short.isEmpty ? "Member" : short
    }

    private func joinedLabel(_ raw: String) -> String {
        guard let date = Self.isoWithFractional.date(from: raw) ?? Self.iso.date(from: raw) else {
            return "Joined recently"
        }
        return "Joined \(Self.relFormatter.localizedString(for: date, relativeTo: Date()))"
    }
}
