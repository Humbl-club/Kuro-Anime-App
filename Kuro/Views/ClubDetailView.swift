// MARK: - CLUB DETAIL VIEW
// Three-tab detail view for a club: Rails, Active, Polls.
// Journal editorial design: blurred mosaic hero, curator notes, prose activity, glass bottom bar.
// Uses @Observable pattern, KuroDesignSystem tokens throughout.

import KuroCore
import SwiftUI

// MARK: - Scroll Offset Preference Key

private struct ClubScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ClubDetailView: View {
    let clubId: String

    @Environment(ClubsStore.self) private var clubs
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(FeatureFlags.self) private var flags
    @Environment(InteractionTelemetry.self) private var interactionTelemetry
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case rails = "RAILS"
        case active = "ACTIVE"
        case polls = "POLLS"

        static var visibleCases: [Tab] {
            [.rails, .active, .polls]
        }
    }

    @State private var actionScope = AccountActionScope()
    @State private var selectedTab: Tab = .rails
    @State private var bundle: ClubBundle? = nil
    @State private var loadingBundle: ClubBundleLoading? = nil
    @State private var loadPhase: ClubDetailLoadPhase = .idle
    @State private var showSettings = false
    @State private var showCreateRail = false
    @State private var showCreatePoll = false
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var disclosureReloadTask: Task<Void, Never>?
    @State private var voteInFlightPollIds: Set<String> = []
    @State private var optimisticVoteByPollId: [String: String] = [:]
    @State private var optimisticVoteCountsByPollId: [String: [String: Int]] = [:]
    @State private var addToRailId: String? = nil
    @State private var sharedProviders: ProviderAvailabilityStore.ClubSharedProvidersResponse? = nil
    @State private var showSharedAvailability: Bool = false
    @State private var scrollOffset: CGFloat = 0
    /// Realtime and membership-loss decisions (`ClubDetailLifecycle`, pure and unit-tested).
    @State private var lifecycle = ClubDetailLifecycle()

    private var clubsInteractionV2Enabled: Bool {
        flags.isClubsInteractionV2Enabled
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
        let origin = actionScope.capture(session: clubs.accountSession)
        return ZStack {
            Color.kuroBackground.ignoresSafeArea()

            if let bundle {
                journalContent(bundle)
                    .overlay(alignment: .top) {
                        if let message = loadPhase.refreshFailureMessage {
                            ClubDetailRefreshBanner(
                                message: message,
                                isConnected: networkMonitor.isConnected,
                                onRetry: {
                                    actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
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
                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
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
        .task(id: origin) {
            guard let origin, actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            clubs.markClubSeen(clubId: clubId)
            await loadBundle(origin: origin)
            // Disappeared while loading, or the membership ended: never open this club's channel.
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            guard lifecycle.shouldSubscribe(taskCancelled: Task.isCancelled) else { return }
            await clubs.subscribeToClubUpdates(clubId: clubId)
            // Disappeared or lost the club while subscribing: close this club's channel (only its
            // own), unless the view is back on screen with the club (its new task owns the channel).
            let next = lifecycle.afterSubscribe(taskCancelled: Task.isCancelled)
            if next.stopsOwnChannel {
                clubs.realtime.stop(clubId: clubId)
            }
            guard next.continuesTask, actionScope.isCurrent(origin, session: clubs.accountSession) else { return }

            // Streaming: fetch shared providers + prefetch rail item providers
            if flags.isStreamingAvailabilityV1Enabled {
                let epoch = clubs.revocationEpoch(clubId)
                let shared = await availability.fetchClubSharedProviders(clubId: clubId)
                // Revoked meanwhile: keep nothing derived from the club's members.
                guard actionScope.isCurrent(origin, session: clubs.accountSession), clubs.revocationEpoch(clubId) == epoch else { return }
                sharedProviders = shared
                if let bundle {
                    let allItems: [(mediaType: String, mediaId: Int)] = bundle.rails.flatMap { rail in
                        rail.items.map { (mediaType: $0.media_type, mediaId: $0.media_id) }
                    }
                    if !allItems.isEmpty {
                        availability.prefetchProviders(items: allItems)
                    }
                }
            }
        }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            lifecycle.appeared()
        }
        .onDisappear {
            actionScope.deactivate()
            voteInFlightPollIds.removeAll()
            optimisticVoteByPollId.removeAll()
            optimisticVoteCountsByPollId.removeAll()
            toastDismissTask?.cancel()
            disclosureReloadTask?.cancel()
            disclosureReloadTask = nil
            // Close this club's channel only: another club's view may own the open one by now.
            if lifecycle.disappeared() {
                clubs.realtime.stop(clubId: clubId)
            }
        }
        .onChange(of: clubs.revocationEpoch(clubId)) { _, _ in
            handleClubRevoked()
        }
        .onChange(of: clubs.disclosureGeneration) { _, _ in
            // Drop private copies immediately, then revalidate. A peer's settings
            // change is not evidence that the viewer was removed from the club.
            dropClubState()
            disclosureReloadTask?.cancel()
            disclosureReloadTask = actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
        }
        .refreshable {
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            await loadBundle(force: true, origin: origin)
        }
        .sheet(isPresented: $showSettings) {
            if let bundle {
                ClubSettingsSheet(
                    bundle: bundle,
                    clubId: clubId,
                    onDismiss: {
                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
                    },
                    onLeaving: { leaving in
                        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                        lifecycle.leavingChanged(leaving)
                    }
                )
            }
        }
        .sheet(isPresented: $showCreateRail) {
            CreateClubRailSheet(clubId: clubId) {
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                showToast(.success, title: "Rail created", subtitle: nil)
                actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
            }
        }
        .sheet(isPresented: $showCreatePoll) {
            CreateClubPollSheet(clubId: clubId) {
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                showToast(.success, title: "Poll created", subtitle: nil)
                actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
            }
        }
        .sheet(isPresented: Binding(
            get: { addToRailId != nil },
            set: { if !$0 { addToRailId = nil } }
        )) {
            if let railId = addToRailId {
                AddItemToRailSheet(railId: railId, clubId: clubId) {
                    guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                    showToast(.success, title: "Item added", subtitle: nil)
                    actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
                }
            }
        }
        // The club sheet's own presentation context: rail items open their routes here.
        .routePresenter()
    }

    // MARK: - Journal Content

    @ViewBuilder
    private func journalContent(_ bundle: ClubBundle) -> some View {
        let origin = actionScope.capture(session: clubs.accountSession)
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
                                userStreamingServicesEmpty: availability.userStreamingServices.isEmpty,
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
                                    actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
                                        if clubsInteractionV2Enabled {
                                            await voteOnPoll(poll: poll, optionId: optionId, origin: ticket)
                                        } else {
                                            do {
                                                try await clubs.castVote(pollId: poll.id, optionId: optionId)
                                                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                                                KuroAccessibility.impactHaptic(.light)
                                                await loadBundle(force: true, origin: origin)
                                            } catch {
                                                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
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
        let providers = availability.providers(mediaId: mediaId, mediaType: mediaType)
        return providers.contains(where: { sharedServiceSlugs.contains($0.slug) })
    }

    // MARK: - Load

    private func loadBundle(force: Bool = false, origin: AccountActionScope.Ticket?) async {
        guard let origin, actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        // The membership ended on screen: the club is closing, nothing is loaded again.
        guard lifecycle.acceptsLoads else { return }
        let isInitialLoad = bundle == nil
        loadPhase = isInitialLoad ? .loadingInitial : .refreshing
        if isInitialLoad {
            let epoch = clubs.revocationEpoch(clubId)
            actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
                let snapshot = try? await clubs.fetchClubBundleLoading(clubId: clubId)
                guard actionScope.isCurrent(ticket, session: clubs.accountSession), bundle == nil, clubs.revocationEpoch(clubId) == epoch else { return }
                loadingBundle = snapshot
            }
        }
        do {
            // The store hands out the accepted newest snapshot only (F07: request order), so a load
            // that answers after a newer one cannot publish an older bundle here.
            let fetched = try await clubs.fetchClubBundle(clubId: clubId, forceRefresh: force)
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            bundle = fetched
            loadingBundle = nil
            optimisticVoteByPollId.removeAll()
            optimisticVoteCountsByPollId.removeAll()
            loadPhase = .loaded
        } catch {
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            #if DEBUG
            print("[ClubDetail] loadBundle failed: \(type(of: error)) — \(error)")
            #endif
            // Dropped by the store (account or membership changed while in flight, F04) or by the
            // view's own task: an obsolete completion publishes no error over newer state.
            if error is CancellationError {
                if loadPhase == .loadingInitial || loadPhase == .refreshing {
                    loadPhase = bundle == nil ? .idle : .loaded
                }
                return
            }
            // Revoked while loading (the store drops the answer): keep the membership notice.
            guard lifecycle.acceptsLoads else { return }
            switch error as? ClubError {
            case .notAMember?:
                loadingBundle = nil
                handleMembershipLoss()
            case .clubNotFound?:
                apply(lifecycle.clubGone())
            case .permissionDenied?:
                // Permission denied (SQLSTATE 42501): a membership loss without a code.
                loadingBundle = nil
                handleMembershipLoss()
            default:
                let message = clubDetailErrorMessage(for: error)
                loadPhase = bundle == nil
                    ? .failedInitial(message: message)
                    : .failedRefresh(message: message)
            }
        }
    }

    private func voteOnPoll(poll: ClubPoll, optionId: String, origin: AccountActionScope.Ticket) async {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        guard !poll.is_closed else { return }
        guard poll.my_vote_option_id != optionId else { return }
        guard !voteInFlightPollIds.contains(poll.id) else { return }

        voteInFlightPollIds.insert(poll.id)
        let startedAt = interactionTelemetry.beginInteractionTiming()
        interactionTelemetry.trackInteractionEvent(
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

        defer { if actionScope.isCurrent(origin, session: clubs.accountSession) { voteInFlightPollIds.remove(poll.id) } }

        do {
            try await clubs.castVote(pollId: poll.id, optionId: optionId)
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            let refreshed = try await clubs.refreshClubBundle(clubId: clubId)
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            bundle = refreshed
            optimisticVoteByPollId.removeAll()
            optimisticVoteCountsByPollId.removeAll()
            interactionTelemetry.trackInteractionEvent(
                "clubs_vote_success",
                surface: "club_detail_polls",
                result: "ok",
                startedAt: startedAt,
                extra: ["club_id": clubId]
            )
            KuroAccessibility.successHaptic()
        } catch is CancellationError {
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            // Dropped by the store (account or membership changed, F04): revert the optimistic vote
            // silently; no toast, no error event for a vote nobody current cast.
            optimisticVoteByPollId[poll.id] = nil
            optimisticVoteCountsByPollId[poll.id] = nil
        } catch {
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            optimisticVoteByPollId[poll.id] = nil
            optimisticVoteCountsByPollId[poll.id] = nil
            switch error as? ClubError {
            case .notAMember?:
                handleMembershipLoss()
            case .pollClosed?:
                showToast(.error, title: "Poll closed", subtitle: "This poll is no longer accepting votes.")
            default:
                showToast(.error, title: "Vote failed", subtitle: "Please try again.")
            }
            interactionTelemetry.trackInteractionEvent(
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
        guard let origin = actionScope.capture(session: clubs.accountSession) else { return }
        toastDismissTask?.cancel()
        withAnimation(KuroAnimation.fast) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            withAnimation(KuroAnimation.fast) { toast = nil }
        }
    }

    private func canAddToRail(_ rail: ClubRail, role: String) -> Bool {
        if !rail.is_locked { return true }
        return ["owner", "admin"].contains(role)
    }

    /// A club request answered with a membership loss.
    private func handleMembershipLoss() {
        // A loaded bundle means the user was a member and lost access;
        // no bundle (e.g. initial load via kuro://club/<uuid>) means they were never a member.
        apply(lifecycle.membershipLost(showsClub: bundle != nil))
    }

    /// `ClubsStore` revoked this club (the caller left it, was removed, or a club request answered
    /// with a membership loss). The store already dropped its own state; this drops the view's copies
    /// so nothing private stays on screen, then closes the club.
    private func handleClubRevoked() {
        apply(lifecycle.revoked(showsClub: bundle != nil))
    }

    /// Performs a `ClubDetailLifecycle` answer: drop the club's data, show the notice, dismiss.
    private func apply(_ response: ClubDetailLifecycle.LossResponse) {
        if response.dropsLocalState {
            dropClubState()
        }
        switch response.notice {
        case .removed:
            loadPhase = .failedInitial(message: "You're no longer a member of this club.")
            showToast(.error, title: "Access updated", subtitle: "You were removed from this club.")
        case .notYetMember:
            loadPhase = .failedInitial(message: "You're not a member of this club yet — ask for an invite.")
            showToast(.error, title: "Access updated", subtitle: "You're not a member of this club yet — ask for an invite.")
        case .left:
            loadPhase = .failedInitial(message: "You're no longer a member of this club.")
        case .clubGone:
            loadPhase = .failedInitial(message: "This club no longer exists.")
        case nil:
            break
        }
        if response.dismisses {
            let origin = actionScope.capture(session: clubs.accountSession)
            actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                dismiss()
            }
        }
    }

    /// Drops every local copy of the club's data (bundle, loading snapshot, optimistic votes, shared
    /// providers) and closes the sheets that render it. The rails' reaction rows live inside the
    /// bundle's content, so their optimistic reactions go with it.
    private func dropClubState() {
        bundle = nil
        loadingBundle = nil
        optimisticVoteByPollId.removeAll()
        optimisticVoteCountsByPollId.removeAll()
        sharedProviders = nil
        showSettings = false
        showCreateRail = false
        showCreatePoll = false
        addToRailId = nil
    }
}

private struct ClubDetailInitialState: View {
    let phase: ClubDetailView.ClubDetailLoadPhase
    let loadingBundle: ClubBundleLoading?
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
    let loadingBundle: ClubBundleLoading?
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
    let loadingBundle: ClubBundleLoading?
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

    private func heroMetaText(for bundle: ClubBundleLoading) -> String {
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
