// MARK: - CLUB DETAIL VIEW
// Three-tab detail view for a club: Rails, Active, Polls.
// Journal editorial design: blurred mosaic hero, curator notes, prose activity, glass bottom bar.
// Uses @Observable pattern, KuroDesignSystem tokens throughout.

import SwiftUI
import PostgREST

// MARK: - Scroll Offset Preference Key

private struct ClubScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ClubDetailView: View {
    let clubId: String

    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case rails = "RAILS"
        case active = "ACTIVE"
        case polls = "POLLS"

        static var visibleCases: [Tab] {
            [.rails, .active, .polls]
        }
    }

    @State private var selectedTab: Tab = .rails
    @State private var bundle: SupabaseService.ClubBundle? = nil
    @State private var loadingBundle: SupabaseService.ClubBundleLoading? = nil
    @State private var loadPhase: ClubDetailLoadPhase = .idle
    @State private var showSettings = false
    @State private var showCreateRail = false
    @State private var showCreatePoll = false
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var voteInFlightPollIds: Set<String> = []
    @State private var optimisticVoteByPollId: [String: String] = [:]
    @State private var optimisticVoteCountsByPollId: [String: [String: Int]] = [:]
    @State private var addToRailId: String? = nil
    @State private var sharedProviders: SupabaseService.ClubSharedProvidersResponse? = nil
    @State private var showSharedAvailability: Bool = false
    @State private var scrollOffset: CGFloat = 0

    private var clubsInteractionV2Enabled: Bool {
        FeatureFlags.shared.isClubsInteractionV2Enabled
    }

    private let heroHeight: CGFloat = 220

    fileprivate enum ClubDetailLoadPhase: Equatable {
        case idle
        case loadingInitial
        case loaded
        case refreshing
        case failedInitial(message: String)
        case failedRefresh(message: String)

        var isRefreshing: Bool {
            if case .refreshing = self { return true }
            return false
        }

        var initialFailureMessage: String? {
            if case let .failedInitial(message) = self { return message }
            return nil
        }

        var refreshFailureMessage: String? {
            if case let .failedRefresh(message) = self { return message }
            return nil
        }
    }

    private func clubDetailErrorMessage(for error: Error) -> String {
        if !networkMonitor.isConnected {
            return "You're offline. Reconnect to load this club."
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The club request timed out. Please try again."
            case .networkConnectionLost:
                return "The connection dropped. Please try again."
            case .notConnectedToInternet:
                return "You're offline. Reconnect to load this club."
            default:
                break
            }
        }

        return "Could not load club data. Please try again."
    }

    var body: some View {
        ZStack {
            Color.kuroBackground.ignoresSafeArea()

            if let bundle {
                journalContent(bundle)
                    .overlay(alignment: .top) {
                        if let message = loadPhase.refreshFailureMessage {
                            ClubDetailRefreshBanner(
                                message: message,
                                isConnected: networkMonitor.isConnected,
                                onRetry: {
                                    Task { await loadBundle(force: true) }
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }
                    }
            } else {
                ClubDetailInitialState(
                    phase: loadPhase,
                    loadingBundle: loadingBundle,
                    isConnected: networkMonitor.isConnected,
                    onRetry: {
                        Task { await loadBundle(force: true) }
                    }
                )
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
        .toolbar(.hidden, for: .navigationBar)
        .task {
            supabaseService.markClubSeen(clubId: clubId)
            await loadBundle()
            await supabaseService.subscribeToClubUpdates(clubId: clubId)

            // Streaming: fetch shared providers + prefetch rail item providers
            if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
                sharedProviders = await supabaseService.fetchClubSharedProviders(clubId: clubId)
                if let bundle {
                    let allItems: [(mediaType: String, mediaId: Int)] = bundle.rails.flatMap { rail in
                        rail.items.map { (mediaType: $0.media_type, mediaId: $0.media_id) }
                    }
                    if !allItems.isEmpty {
                        supabaseService.prefetchProviders(items: allItems)
                    }
                }
            }
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

    // MARK: - Journal Content

    @ViewBuilder
    private func journalContent(_ bundle: SupabaseService.ClubBundle) -> some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top, 24)

            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Scroll offset sensor
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: ClubScrollOffsetPreferenceKey.self,
                                    value: proxy.frame(in: .named("club_detail_scroll")).minY
                                )
                        }
                        .frame(height: 0)

                        JournalHeroSection(
                            bundle: bundle,
                            heroHeight: heroHeight,
                            scrollOffset: scrollOffset,
                            containerWidth: geometry.size.width
                        )

                        JournalTabBar(selectedTab: $selectedTab)

                        if loadPhase.isRefreshing {
                            ClubDetailPendingStrip(
                                title: pendingRefreshTitle,
                                message: pendingRefreshMessage,
                                isConnected: networkMonitor.isConnected
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }

                        switch selectedTab {
                        case .rails:
                            JournalRailsContent(
                                bundle: bundle,
                                showSharedAvailability: showSharedAvailability,
                                sharedProviders: sharedProviders,
                                isAvailableOnSharedServices: isAvailableOnSharedServices,
                                onToggleShared: {
                                    KuroAccessibility.impactHaptic(.light)
                                    withAnimation(KuroAnimation.fast) {
                                        showSharedAvailability.toggle()
                                    }
                                },
                                onCreateRail: { showCreateRail = true },
                                onAddToRail: { railId in addToRailId = railId },
                                onError: { message in showToast(.error, title: message, subtitle: nil) },
                                canAddToRail: canAddToRail,
                                userStreamingServicesEmpty: supabaseService.userStreamingServices.isEmpty,
                                isConnected: networkMonitor.isConnected
                            )
                        case .active:
                            JournalActivityContent(
                                bundle: bundle
                            )
                        case .polls:
                            JournalPollsContent(
                                bundle: bundle,
                                clubsInteractionV2Enabled: clubsInteractionV2Enabled,
                                voteInFlightPollIds: voteInFlightPollIds,
                                optimisticVoteByPollId: optimisticVoteByPollId,
                                optimisticVoteCountsByPollId: optimisticVoteCountsByPollId,
                                onVote: { poll, optionId in
                                    Task {
                                        if clubsInteractionV2Enabled {
                                            await voteOnPoll(poll: poll, optionId: optionId)
                                        } else {
                                            do {
                                                try await supabaseService.castVote(pollId: poll.id, optionId: optionId)
                                                KuroAccessibility.impactHaptic(.light)
                                                await loadBundle(force: true)
                                            } catch {
                                                showToast(.error, title: "Vote failed", subtitle: "Please try again.")
                                                KuroAccessibility.errorHaptic()
                                            }
                                        }
                                    }
                                },
                                onCreatePoll: { showCreatePoll = true },
                                isConnected: networkMonitor.isConnected
                            )
                        }
                    }
                }
                .coordinateSpace(name: "club_detail_scroll")
                .onPreferenceChange(ClubScrollOffsetPreferenceKey.self) { v in
                    scrollOffset = v
                }
                .safeAreaInset(edge: .bottom) {
                    JournalBottomBar(
                        role: bundle.my_role,
                        isConnected: networkMonitor.isConnected,
                        onAdd: { addToRailId = bundle.rails.first?.id },
                        onInvite: { showSettings = true },
                        onPoll: { showCreatePoll = true }
                    )
                    .padding(.bottom, 8)
                }
                .ignoresSafeArea(edges: .top)

                // Status bar overlay
                JournalStatusBar(
                    clubName: bundle.club.name,
                    scrollOffset: scrollOffset,
                    heroHeight: heroHeight,
                    safeTop: safeTop,
                    onBack: { dismiss() },
                    onSettings: { showSettings = true }
                )
            }
        }
    }

    private var pendingRefreshTitle: String {
        switch selectedTab {
        case .rails:
            return "Refreshing rails"
        case .active:
            return "Refreshing activity"
        case .polls:
            return "Refreshing polls"
        }
    }

    private var pendingRefreshMessage: String {
        if !networkMonitor.isConnected {
            return "Waiting for a connection before the latest club changes can load."
        }
        switch selectedTab {
        case .rails:
            return "Pulling the latest rail changes and shared availability."
        case .active:
            return "Updating the club feed so progress stays in order."
        case .polls:
            return "Checking for new questions, votes, and poll closures."
        }
    }

    // MARK: - Shared availability helpers

    private var sharedServiceSlugs: Set<String> {
        guard let sp = sharedProviders else { return [] }
        return Set(sp.shared_services.map(\.slug))
    }

    private func isAvailableOnSharedServices(mediaId: Int, mediaType: String) -> Bool {
        let providers = supabaseService.providers(mediaId: mediaId, mediaType: mediaType)
        return providers.contains(where: { sharedServiceSlugs.contains($0.slug) })
    }

    // MARK: - Load

    private func loadBundle(force: Bool = false) async {
        let isInitialLoad = bundle == nil
        loadPhase = isInitialLoad ? .loadingInitial : .refreshing
        if isInitialLoad {
            Task { @MainActor in
                let snapshot = try? await supabaseService.fetchClubBundleLoading(clubId: clubId)
                guard bundle == nil else { return }
                loadingBundle = snapshot
            }
        }
        do {
            let fetched = try await supabaseService.fetchClubBundle(clubId: clubId, forceRefresh: force)
            bundle = fetched
            loadingBundle = nil
            optimisticVoteByPollId.removeAll()
            optimisticVoteCountsByPollId.removeAll()
            loadPhase = .loaded
        } catch {
            #if DEBUG
            print("[ClubDetail] loadBundle failed: \(type(of: error)) — \(error)")
            #endif
            switch rpcErrorCode(from: error) {
            case .notAMember:
                loadingBundle = nil
                handleMembershipLoss()
            case .clubNotFound:
                bundle = nil
                loadingBundle = nil
                loadPhase = .failedInitial(message: "This club no longer exists.")
            default:
                let message = clubDetailErrorMessage(for: error)
                loadPhase = bundle == nil
                    ? .failedInitial(message: message)
                    : .failedRefresh(message: message)
            }
        }
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
            switch rpcErrorCode(from: error) {
            case .notAMember:
                handleMembershipLoss()
            case .pollClosed:
                showToast(.error, title: "Poll closed", subtitle: "This poll is no longer accepting votes.")
            default:
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

    private enum ClubRPCErrorCode: String {
        case notAMember = "NOT_A_MEMBER"
        case clubNotFound = "CLUB_NOT_FOUND"
        case pollClosed = "POLL_CLOSED"
    }

    private func rpcErrorCode(from error: Error) -> ClubRPCErrorCode? {
        guard let pgError = error as? PostgrestError else { return nil }
        let candidates = [pgError.detail, pgError.hint, pgError.message]
        for raw in candidates {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let mapped = ClubRPCErrorCode(rawValue: normalized) { return mapped }
        }
        return nil
    }

    private func canAddToRail(_ rail: SupabaseService.ClubRail, role: String) -> Bool {
        if !rail.is_locked { return true }
        return ["owner", "admin"].contains(role)
    }

    private func handleMembershipLoss() {
        bundle = nil
        loadPhase = .failedInitial(message: "You're no longer a member of this club.")
        showToast(.error, title: "Access updated", subtitle: "You were removed from this club.")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        }
    }
}

private struct ClubDetailInitialState: View {
    let phase: ClubDetailView.ClubDetailLoadPhase
    let loadingBundle: SupabaseService.ClubBundleLoading?
    let isConnected: Bool
    let onRetry: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                ClubDetailInitialHeader(
                    loadingBundle: loadingBundle,
                    isConnected: isConnected,
                    isFailure: phase.initialFailureMessage != nil
                )

                ClubDetailInitialSkeleton(loadingBundle: loadingBundle)

                if let message = phase.initialFailureMessage {
                    ClubDetailStatusCard(
                        eyebrow: "INITIAL LOAD",
                        title: loadingBundle.map { "Could not load \($0.club.name)" } ?? "Could not load club",
                        message: message,
                        systemImage: isConnected ? "exclamationmark.triangle" : "wifi.slash",
                        metadata: metadataPills,
                        actionTitle: "Retry",
                        onAction: onRetry
                    )
                } else {
                    ClubDetailStatusCard(
                        eyebrow: "INITIAL LOAD",
                        title: loadingBundle.map { "Loading \($0.club.name)" } ?? "Loading club",
                        message: loadingMessage(isConnected: isConnected),
                        systemImage: isConnected ? "sparkles" : "wifi.slash",
                        metadata: metadataPills,
                        actionTitle: nil,
                        onAction: nil
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(phase.initialFailureMessage == nil ? "Loading club" : "Could not load club")
    }

    private func loadingMessage(isConnected: Bool) -> String {
        if !isConnected {
            return "You're offline. Reconnect to load this club."
        }
        if let preview = loadingBundle?.activity_preview, !preview.isEmpty {
            return preview
        }
        return "Building the journal surface now."
    }

    private var metadataPills: [String] {
        guard let loadingBundle else { return [] }
        var values = ["\(loadingBundle.member_count) members"]
        if let railCount = loadingBundle.rail_count {
            values.append("\(railCount) rails")
        }
        if let pollCount = loadingBundle.poll_count {
            values.append("\(pollCount) polls")
        }
        return values
    }
}

private struct ClubDetailInitialHeader: View {
    let loadingBundle: SupabaseService.ClubBundleLoading?
    let isConnected: Bool
    let isFailure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("CLUB JOURNAL")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.0)
                    .foregroundColor(.kuroBlack40)

                Capsule(style: .continuous)
                    .fill(isFailure ? Color.kuroBlack10 : Color.kuroBlack06)
                    .frame(width: 1, height: 14)

                Text(stateLabel)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(.kuroBlack40)
            }

            Text(headerTitle)
                .font(.kuroTitle(weight: .regular))
                .foregroundColor(.kuroBlack80)

            Text(headerMessage)
                .font(.kuroCaption(weight: .light))
                .foregroundColor(.kuroTextTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateLabel: String {
        if isFailure { return "Needs attention" }
        return isConnected ? "Preparing surface" : "Waiting for network"
    }

    private var headerTitle: String {
        if let loadingBundle {
            return loadingBundle.club.name
        }
        return "Club detail"
    }

    private var headerMessage: String {
        if let preview = loadingBundle?.activity_preview, !preview.isEmpty {
            return preview
        }
        if !isConnected {
            return "The saved shell is ready. The full club surface will continue once the connection returns."
        }
        return "Assembling the club overview, rails, recent activity, and poll state."
    }
}

private struct ClubDetailInitialSkeleton: View {
    let loadingBundle: SupabaseService.ClubBundleLoading?
    private let cardCount = 3

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 218)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let loadingBundle {
                                Text(loadingBundle.club.sharing_level.uppercased())
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.4)
                                    .foregroundColor(.kuroWhite60)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.kuroBlack35)
                                    )

                                Text(loadingBundle.club.name)
                                    .font(.kuroFeature(weight: .light))
                                    .italic()
                                    .foregroundColor(.kuroWhite)
                                    .lineLimit(2)

                                Text(heroMetaText(for: loadingBundle))
                                    .font(.kuroMicro(weight: .medium))
                                    .foregroundColor(.kuroWhite60)
                            } else {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.black.opacity(0.10))
                                    .frame(width: 116, height: 12)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 210, height: 26)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.black.opacity(0.07))
                                    .frame(width: 156, height: 12)
                            }
                        }
                        .padding(18)
                    }
                    .kuroShimmer()

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 72, height: 26)
                            .kuroShimmer()
                    }
                }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(height: 52)
                    .overlay {
                        HStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )
                    .kuroShimmer()
            }

            VStack(spacing: 12) {
                ForEach(0..<cardCount, id: \.self) { index in
                    ClubDetailSkeletonCard(index: index)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func heroMetaText(for bundle: SupabaseService.ClubBundleLoading) -> String {
        let members = bundle.member_count
        let rails = bundle.rail_count ?? 0
        let polls = bundle.poll_count ?? 0
        return "\(members) members • \(rails) rails • \(polls) polls"
    }
}

private struct ClubDetailSkeletonCard: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 92, height: 10)
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 36, height: 10)
            }

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black.opacity(0.10))
                .frame(width: index == 0 ? 180 : 140, height: 16)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black.opacity(0.07))
                .frame(width: index == 2 ? 210 : 170, height: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        .kuroShimmer()
    }
}

private struct ClubDetailStatusCard: View {
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String
    let metadata: [String]
    let actionTitle: String?
    let onAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(eyebrow)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.0)
                    .foregroundColor(.kuroBlack40)

                Spacer(minLength: 0)

                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.kuroBlack60)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.kuroBlack04)
                    )
            }

            Text(title)
                .font(.kuroHeadline(weight: .ultraLight))
                .foregroundColor(.kuroBlack)

            Text(message)
                .font(.kuroBody(weight: .light))
                .foregroundColor(.kuroBlack60)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if !metadata.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(metadata, id: \.self) { item in
                            Text(item.uppercased())
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.0)
                                .foregroundColor(.kuroBlack60)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.kuroBlack04)
                                )
                        }
                    }
                }
                .scrollDisabled(true)
            }

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle.uppercased())
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.8)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

private struct ClubDetailRefreshBanner: View {
    let message: String
    let isConnected: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isConnected ? "arrow.clockwise.circle.fill" : "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.kuroBlack60)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.kuroBlack04)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(isConnected ? "Refresh delayed" : "Offline")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(.kuroBlack80)

                Text(message)
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroBlack70)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(.kuroBlack)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.kuroBlack04)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 5)
    }
}

private struct ClubDetailPendingStrip: View {
    let title: String
    let message: String
    let isConnected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .scaleEffect(0.78)
                .tint(.kuroBlack60)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.kuroBlack04)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.4)
                    .foregroundColor(.kuroBlack60)

                Text(message)
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroBlack70)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(isConnected ? "LIVE" : "PAUSED")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.2)
                .foregroundColor(.kuroBlack40)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.kuroBlack04)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

// Journal section components extracted to ClubDetailSections.swift
