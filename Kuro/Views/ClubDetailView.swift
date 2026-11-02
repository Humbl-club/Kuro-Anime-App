// MARK: - CLUB DETAIL VIEW
// Three-tab detail view for a club: RAILS, ACTIVE, POLLS (the tab cases and raw values are fixed;
// labels are localized at display).
// The club's identity surface is the prototype's club room (`ClubRoomPalette.room`) with real rail artwork, the
// audience line, member initials and one spoiler-hidden member note; tab content sits on the white
// page. Loading, offline, failed and membership states are distinct (`ClubDetailIssue`).
// Uses @Observable owners via @Environment, KuroDesignSystem tokens throughout.

import KuroCore
import SwiftUI

// Navigation (contract docs/superpowers/specs/2026-11-02-navigation-contract-design.md): the club is a
// journey page (`JourneyPage.club`, built by `JourneyHost`). Its status bar is the journey chrome:
// back when pushed, settings and ✕ always (✕ collapses the whole journey), the paper compact bar fading
// in as the room scrolls away (`KuroCollapse`). The system bar is hidden, so edge swipe-back is restored
// with `KuroInteractivePopEnabler` (N2). Rail items and "This week" entries push their title inside the
// journey through `\.kuroRoutes`; settings, new rail, new poll and add-a-title are tool sheets over this
// page (N7) that leave the journey (`.kuroLeavesJourney()`).

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

        /// The tab's display label (EN/DE); `rawValue` stays the stable identifier.
        var title: String {
            switch self {
            case .rails: return KuroLocale.text("Rails", "Listen")
            case .active: return KuroLocale.text("Active", "Aktivität")
            case .polls: return KuroLocale.text("Polls", "Umfragen")
            }
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
    /// The shrinking header's progress (0 = the room, 1 = the compact bar).
    @State private var collapse: CGFloat = 0
    @State private var heroHeight: CGFloat = 320
    /// Realtime and membership-loss decisions (`ClubDetailLifecycle`, pure and unit-tested).
    @State private var lifecycle = ClubDetailLifecycle()

    private var clubsInteractionV2Enabled: Bool {
        flags.isClubsInteractionV2Enabled
    }

    fileprivate enum ClubDetailLoadPhase: Equatable {
        case idle
        case loadingInitial
        case loaded
        case refreshing
        case failedInitial(ClubDetailIssue)
        case failedRefresh(ClubDetailIssue)

        var initialIssue: ClubDetailIssue? {
            if case let .failedInitial(issue) = self { return issue }
            return nil
        }

        var refreshIssue: ClubDetailIssue? {
            if case let .failedRefresh(issue) = self { return issue }
            return nil
        }
    }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return ZStack {
            Color.kuroCanvasPage.ignoresSafeArea()

            if let bundle {
                journalContent(bundle)
            } else {
                ClubDetailInitialState(
                    phase: loadPhase,
                    loadingBundle: loadingBundle,
                    isConnected: networkMonitor.isConnected,
                    onRetry: {
                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
                    }
                )
                .overlay(alignment: .top) {
                    // Back (pushed) and ✕ stay reachable before the club is shown.
                    JournalStatusBar(clubName: loadingBundle?.club.name ?? "", progress: 0, onSettings: nil)
                }
            }

            if let toast {
                VStack {
                    Spacer()
                    KuroToast(toast: toast)
                        .padding(.horizontal, KuroDesignSpacing.md)
                        .padding(.bottom, 92)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        // The chrome replaces the system bar; edge swipe-back stays on (N2).
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .background(KuroInteractivePopEnabler())
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
        // H4: not on a journey's first page (pull-down dismisses the club there); pushed clubs refresh.
        .kuroJourneyRefreshable {
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
                .kuroLeavesJourney()
            }
        }
        // N10: a deep link to this club (already on top) keeps the journey and closes these tools.
        .kuroNavigationLayer("club.settings", isPresented: $showSettings)
        .sheet(isPresented: $showCreateRail) {
            CreateClubRailSheet(clubId: clubId) {
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                showToast(.success, title: KuroLocale.text("Rail created", "Liste angelegt"), subtitle: nil)
                actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
            }
            .kuroLeavesJourney()
        }
        .kuroNavigationLayer("club.createRail", isPresented: $showCreateRail)
        .sheet(isPresented: $showCreatePoll) {
            CreateClubPollSheet(clubId: clubId) {
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                showToast(.success, title: KuroLocale.text("Poll started", "Umfrage gestartet"), subtitle: nil)
                actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
            }
            .kuroLeavesJourney()
        }
        .kuroNavigationLayer("club.createPoll", isPresented: $showCreatePoll)
        .sheet(isPresented: Binding(
            get: { addToRailId != nil },
            set: { if !$0 { addToRailId = nil } }
        )) {
            if let railId = addToRailId {
                AddItemToRailSheet(railId: railId, clubId: clubId) {
                    guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                    showToast(.success, title: KuroLocale.text("Added", "Hinzugefügt"), subtitle: nil)
                    actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
                }
                .kuroLeavesJourney()
            }
        }
        .kuroNavigationLayer("club.addItem", item: $addToRailId)
        // Inside a journey this forwards: rail items and "This week" entries push their title onto the
        // journey's stack. Outside one (previews, snapshot tests) it presents as before.
        .routePresenter()
        // VoiceOver escape: Back when pushed, ✕ on the journey's first page (N1/N3).
        .kuroJourneyEscape()
    }

    // MARK: - Journal Content

    @ViewBuilder
    private func journalContent(_ bundle: ClubBundle) -> some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top, KuroDesignSpacing.lg)

            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        JournalHeroSection(bundle: bundle, topInset: safeTop + 60)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }

                        VStack(spacing: 0) {
                            JournalTabBar(selectedTab: $selectedTab)

                            if let issue = loadPhase.refreshIssue {
                                ClubDetailRefreshNotice(
                                    issue: issue,
                                    onRetry: {
                                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
                                    }
                                )
                                .padding(.horizontal, KuroDesignSpacing.padding)
                                .padding(.top, KuroDesignSpacing.md)
                            }

                            switch selectedTab {
                            case .rails:
                                JournalRailsContent(
                                    bundle: bundle,
                                    containerWidth: min(geometry.size.width, KuroReadableWidth.maxWidth),
                                    showSharedAvailability: showSharedAvailability,
                                    sharedProviders: sharedProviders,
                                    isAvailableOnSharedServices: isAvailableOnSharedServices,
                                    onToggleShared: {
                                        KuroAccessibility.impactHaptic(.light)
                                        withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
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
                                                    showToast(.error,
                                                              title: KuroLocale.text("Vote not saved", "Stimme nicht gespeichert"),
                                                              subtitle: KuroLocale.text("Try again.", "Versuch es noch einmal."))
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
                        .kuroReadableWidth()
                    }
                }
                // H1/H3: the compact bar follows the scroll offset (no jump).
                .kuroCollapseTracking($collapse,
                                      start: ClubChromeRules.collapseStart(heroHeight: heroHeight),
                                      distance: ClubChromeRules.collapseDistance)
                .safeAreaInset(edge: .bottom) {
                    JournalBottomBar(
                        role: bundle.my_role,
                        isConnected: networkMonitor.isConnected,
                        onAdd: { addToRailId = bundle.rails.first?.id },
                        onInvite: { showSettings = true },
                        onPoll: { showCreatePoll = true }
                    )
                    .padding(.bottom, KuroDesignSpacing.sm)
                }
                .ignoresSafeArea(edges: .top)

                // The journey chrome: back (pushed), settings, ✕ and the shrinking compact bar.
                JournalStatusBar(
                    clubName: bundle.club.name,
                    progress: collapse,
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
                let issue = ClubDetailIssue.forLoadError(error, isConnected: networkMonitor.isConnected)
                loadPhase = bundle == nil ? .failedInitial(issue) : .failedRefresh(issue)
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
                showToast(.error,
                          title: KuroLocale.text("Poll closed", "Umfrage geschlossen"),
                          subtitle: KuroLocale.text("This poll no longer takes votes.", "Diese Umfrage nimmt keine Stimmen mehr an."))
            default:
                showToast(.error,
                          title: KuroLocale.text("Vote not saved", "Stimme nicht gespeichert"),
                          subtitle: KuroLocale.text("Try again.", "Versuch es noch einmal."))
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
        withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            withAnimation(KuroMotion.resolve(KuroMotion.settle)) { toast = nil }
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
            loadPhase = .failedInitial(.removed)
            showToast(.error,
                      title: KuroLocale.text("Access updated", "Zugriff geändert"),
                      subtitle: KuroLocale.text("You were removed from this club.", "Du wurdest aus diesem Club entfernt."))
        case .notYetMember:
            loadPhase = .failedInitial(.notYetMember)
            showToast(.error,
                      title: KuroLocale.text("Not a member yet", "Noch kein Mitglied"),
                      subtitle: KuroLocale.text("Ask a member for an invite.", "Bitte ein Mitglied um eine Einladung."))
        case .left:
            loadPhase = .failedInitial(.left)
        case .clubGone:
            loadPhase = .failedInitial(.clubGone)
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

// MARK: - Initial state (no bundle yet)

/// Before the club is shown: the room with what the cheap loading snapshot already knows (name,
/// counts, artwork), then one honest state: loading, offline, failed (with Retry) or a membership
/// notice (no Retry). Back (when pushed) and ✕ are always reachable (the chrome over this state).
private struct ClubDetailInitialState: View {
    let phase: ClubDetailView.ClubDetailLoadPhase
    let loadingBundle: ClubBundleLoading?
    let isConnected: Bool
    let onRetry: () -> Void

    private var coverURLs: [URL] {
        (loadingBundle?.rails ?? [])
            .flatMap(\.items)
            .compactMap { $0.cover_image_medium.flatMap(URL.init(string:)) }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        let german = KuroLocale.isGerman
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                    // Room for the journey chrome (back / ✕), drawn over this state by `ClubDetailView`.
                    Color.clear
                        .frame(height: 44)
                        .accessibilityHidden(true)

                    if let issue = phase.initialIssue, issue.isMembership {
                        // A membership notice keeps nothing of the club on screen.
                        EmptyView()
                    } else {
                        ClubArtStrip(urls: coverURLs,
                                     monogram: String((loadingBundle?.club.name ?? "").prefix(1)),
                                     maxPixelSize: 360)
                            .clipShape(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous))

                        if let loadingBundle {
                            Text(loadingBundle.club.name)
                                .font(.kuroEditorial(size: 30)).tracking(-0.6)
                                .foregroundStyle(Color.kuroRoomText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            Text(ClubRoomCopy.summary(memberCount: loadingBundle.member_count,
                                                      railCount: loadingBundle.rail_count ?? 0,
                                                      openPolls: 0,
                                                      german: german))
                                .font(.kuroMeta())
                                .foregroundStyle(Color.kuroRoomTextSecondary)
                        } else {
                            RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                                .fill(Color.kuroWhite15)
                                .frame(height: 30)
                                .frame(maxWidth: 220)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.lg)
                .kuroReadableWidth()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ClubRoomPalette.room)

                stateView(german: german)
                    .frame(minHeight: 280)
                    .kuroReadableWidth()
            }
        }
    }

    @ViewBuilder
    private func stateView(german: Bool) -> some View {
        if let issue = phase.initialIssue {
            switch issue.brandedState {
            case .failed:
                KuroErrorView(headline: issue.title(german: german),
                              message: issue.message(german: german, hasContent: false),
                              retry: onRetry)
            case .offline:
                KuroStateView(.offline(hasCachedContent: false),
                              title: issue.title(german: german),
                              message: issue.message(german: german, hasContent: false),
                              retry: onRetry)
            case .loading, .empty, nil:
                KuroStateView(.denied,
                              title: issue.title(german: german),
                              message: issue.message(german: german, hasContent: false))
            }
        } else {
            KuroStateView(.loading,
                          title: loadingBundle.map { KuroLocale.text("Opening \($0.club.name).", "\($0.club.name) wird geöffnet.") }
                              ?? KuroLocale.text("Opening the club.", "Der Club wird geöffnet."),
                          message: isConnected ? nil : KuroLocale.text("Waiting for a connection.", "Warte auf eine Verbindung."))
        }
    }
}

// MARK: - Refresh notice (bundle on screen)

/// A refresh failed while the club is on screen: what is shown stays, with one line and Retry.
private struct ClubDetailRefreshNotice: View {
    let issue: ClubDetailIssue
    let onRetry: () -> Void

    var body: some View {
        let german = KuroLocale.isGerman
        HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(issue == .offline ? "Offline." : KuroLocale.text("Couldn't refresh.", "Konnte nicht aktualisiert werden."))
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                if let message = issue.message(german: german, hasContent: true) {
                    Text(message)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRetry) {
                Text(KuroStateCopy.retryTitle(german: german))
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                    .underline()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle())
        }
        .padding(.horizontal, KuroDesignSpacing.md)
        .padding(.vertical, KuroDesignSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(Color.kuroCanvasQuiet)
        )
        .accessibilityElement(children: .contain)
    }
}
