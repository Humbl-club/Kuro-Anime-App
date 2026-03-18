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
    @State private var sharedProviders: SupabaseService.ClubSharedProvidersResponse? = nil
    @State private var showSharedAvailability: Bool = false
    @State private var scrollOffset: CGFloat = 0

    private var clubsInteractionV2Enabled: Bool {
        FeatureFlags.shared.isClubsInteractionV2Enabled
    }

    private let heroHeight: CGFloat = 220

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
                journalContent(bundle)
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
        isLoading = true
        errorText = nil
        do {
            bundle = try await supabaseService.fetchClubBundle(clubId: clubId, forceRefresh: force)
            optimisticVoteByPollId.removeAll()
            optimisticVoteCountsByPollId.removeAll()
        } catch {
            #if DEBUG
            print("[ClubDetail] loadBundle failed: \(type(of: error)) — \(error)")
            #endif
            switch rpcErrorCode(from: error) {
            case .notAMember:
                handleMembershipLoss()
            case .clubNotFound:
                errorText = "This club no longer exists."
            default:
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
        errorText = "You're no longer a member of this club."
        showToast(.error, title: "Access updated", subtitle: "You were removed from this club.")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        }
    }
}

// Journal section components extracted to ClubDetailSections.swift
