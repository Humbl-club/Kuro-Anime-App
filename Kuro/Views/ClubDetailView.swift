// MARK: - CLUB DETAIL VIEW
// Three-tab detail view for a club: Rails · This week · Polls (the tab cases and raw values are fixed;
// labels are localized at display; the `.active` case reads "This week").
// Discover + Clubs redesign (spec §7.3): the hero is the club room (the same room as Home's and the
// Clubs list) with a rounded foot, the "You" ring and the one member note; under it, on Home's warm
// paper, the labelled keys (`ClubRoomRules.keys`: Add a title / Start a rail / Invite / Ask) and the
// tabs in Home's switch grammar, pinned under the compact bar once the room has scrolled away.
// Loading, offline, failed and membership states are distinct (`ClubDetailIssue`).
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
    /// The viewer's user id ("You" in the hero, the tiles, This week and polls; D13).
    @Environment(IdentityStore.self) private var identity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            case .active: return KuroLocale.text("This week", "Diese Woche")
            case .polls: return KuroLocale.text("Polls", "Umfragen")
            }
        }
    }

    @State private var actionScope = AccountActionScope()
    @State private var selectedTab: Tab

    /// `initialTab` opens the page on another tab (fixture renders); the app always starts on Rails.
    init(clubId: String, initialTab: Tab = .rails) {
        self.clubId = clubId
        _selectedTab = State(initialValue: initialTab)
    }
    @State private var bundle: ClubBundle? = nil
    @State private var loadingBundle: ClubBundleLoading? = nil
    @State private var loadPhase: ClubDetailLoadPhase = .idle
    @State private var showSettings = false
    @State private var showCreateRail = false
    @State private var showCreatePoll = false
    /// The invite tool (owners and admins; D9).
    @State private var showInvite = false
    /// "Add to which rail?" (several eligible rails; D10), and the rail it handed back.
    @State private var showRailChooser = false
    @State private var chosenRailId: String? = nil
    /// The tab bar's top in the page's space: once it meets the compact bar, a pinned copy shows (H1).
    @State private var tabBarTop: CGFloat = .greatestFiniteMagnitude
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
            // One canvas with the header and Home (spec G1).
            Color.kuroCanvasHome.ignoresSafeArea()

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
        .sheet(isPresented: $showInvite) {
            if let bundle, let code = bundle.club.invite_code {
                ClubInviteSheet(clubName: bundle.club.name, code: code)
                    .kuroLeavesJourney()
            }
        }
        .kuroNavigationLayer("club.invite", isPresented: $showInvite)
        .sheet(isPresented: $showRailChooser, onDismiss: {
            // The chooser has closed: open the add-item tool for the rail it handed back.
            if let chosenRailId { addToRailId = chosenRailId }
            chosenRailId = nil
        }) {
            if let bundle {
                ClubRailChooserSheet(rails: ClubRoomRules.addableRails(bundle)) { railId in
                    chosenRailId = railId
                }
                .kuroLeavesJourney()
            }
        }
        .kuroNavigationLayer("club.railChooser", isPresented: $showRailChooser)
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
            let width = geometry.size.width
            let gutter = ClubRoomLayout.gutter(containerWidth: width)
            let compact = ClubRoomLayout.isCompact(columnWidth: min(width, KuroReadableWidth.maxWidth) - gutter * 2)
            let viewerId = identity.currentUserId
            let keys = ClubRoomRules.keys(role: bundle.my_role, rails: bundle.rails,
                                          hasInviteCode: bundle.club.invite_code != nil)
            let counts = tabCounts(bundle, viewerId: viewerId)
            let pinned = tabBarTop <= KuroJourneyChrome.barHeight

            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            JournalHeroSection(bundle: bundle, viewerId: viewerId,
                                               topInset: safeTop + KuroJourneyChrome.barHeight + 4, compact: compact)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }

                            VStack(spacing: 0) {
                                if !keys.isEmpty {
                                    ClubKeyRow(keys: keys, compact: compact, isConnected: networkMonitor.isConnected) { key in
                                        perform(key, bundle: bundle)
                                    }
                                    .padding(.horizontal, compact ? 12 : 18)
                                    .padding(.top, 14)
                                    .padding(.bottom, 4)
                                }

                                JournalTabBar(selectedTab: $selectedTab, counts: counts, gutter: gutter)
                                    .padding(.top, 10)
                                    .onGeometryChange(for: CGFloat.self) {
                                        $0.frame(in: .named(Self.pageSpace)).minY
                                    } action: { tabBarTop = $0 }

                                if let issue = loadPhase.refreshIssue {
                                    ClubDetailRefreshNotice(
                                        issue: issue,
                                        onRetry: {
                                            actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await loadBundle(force: true, origin: ticket) }
                                        }
                                    )
                                    .padding(.horizontal, gutter)
                                    .padding(.top, KuroDesignSpacing.md)
                                }

                                switch selectedTab {
                                case .rails:
                                    JournalRailsContent(
                                        bundle: bundle,
                                        containerWidth: min(width, KuroReadableWidth.maxWidth),
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
                                        canAddToRail: ClubRoomRules.canAddToRail,
                                        userStreamingServicesEmpty: availability.userStreamingServices.isEmpty,
                                        isConnected: networkMonitor.isConnected,
                                        viewerId: viewerId,
                                        gutter: gutter,
                                        compact: compact,
                                        onScrollToNote: {
                                            // The first note lives in the hero card (D11): scroll up to it.
                                            withAnimation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil) {
                                                proxy.scrollTo(JournalHeroSection.noteAnchor, anchor: .center)
                                            }
                                        }
                                    )
                                case .active:
                                    JournalActivityContent(bundle: bundle, viewerId: viewerId, now: Date(),
                                                           gutter: gutter, compact: compact)
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
                                        isConnected: networkMonitor.isConnected,
                                        viewerId: viewerId,
                                        gutter: gutter
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
                    .ignoresSafeArea(edges: .top)
                }

                // The tabs pinned under the compact bar once the room has scrolled away (H1): a copy
                // drawn on the canvas, bound to the same selection; VoiceOver keeps the in-flow tabs.
                if pinned {
                    JournalTabBar(selectedTab: $selectedTab, counts: counts, gutter: gutter)
                        .kuroReadableWidth()
                        .frame(maxWidth: .infinity)
                        .background(Color.kuroCanvasHome)
                        .padding(.top, KuroJourneyChrome.barHeight)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }

                // The journey chrome: back (pushed), settings, ✕ and the shrinking compact bar.
                JournalStatusBar(
                    clubName: bundle.club.name,
                    progress: collapse,
                    onSettings: { showSettings = true }
                )
            }
            .coordinateSpace(.named(Self.pageSpace))
        }
    }

    /// The page's coordinate space (the tab bar's pin point is measured in it).
    private static let pageSpace = "club.page"

    /// The counts after the tab words: rails, this week's updates, open polls (zero omitted by the bar).
    private func tabCounts(_ bundle: ClubBundle, viewerId: String?) -> [Tab: Int] {
        let week = ClubWeekRules.partition(ClubWeekRules.entries(in: bundle, viewerId: viewerId), now: Date())
        return [.rails: bundle.rails.count, .active: week.thisWeekCount, .polls: bundle.polls.filter { !$0.is_closed }.count]
    }

    /// A labelled key (D9, D10): each opens a real tool and never dead-taps.
    private func perform(_ key: ClubRoomRules.Key, bundle: ClubBundle) {
        switch key {
        case .addTitle:
            switch ClubRoomRules.addTarget(rails: bundle.rails, role: bundle.my_role) {
            case .rail(let railId): addToRailId = railId
            case .chooser: showRailChooser = true
            case .none: break
            }
        case .startRail: showCreateRail = true
        case .invite: if bundle.club.invite_code != nil { showInvite = true }
        case .ask: showCreatePoll = true
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
        showInvite = false
        showRailChooser = false
        chosenRailId = nil
        addToRailId = nil
    }
}

// MARK: - Initial state (no bundle yet)

/// Before the club is shown (spec §7.5): the hero room drawn with what the cheap loading snapshot
/// already knows (name, counts) or with skeleton blocks (seal, name bar, member row), then two tile
/// skeletons while loading, or one honest state: offline, failed (with Retry) or a membership notice
/// (no Retry, nothing of the club on screen). Back (when pushed) and ✕ are always reachable (the chrome
/// over this state).
private struct ClubDetailInitialState: View {
    let phase: ClubDetailView.ClubDetailLoadPhase
    let loadingBundle: ClubBundleLoading?
    let isConnected: Bool
    let onRetry: () -> Void

    private var skeletonBlock: Color { ClubRoomPalette.text.opacity(KuroSkeleton.blockInkOpacity) }
    private var skeletonDeep: Color { ClubRoomPalette.text.opacity(KuroSkeleton.deepBlockInkOpacity) }

    var body: some View {
        let german = KuroLocale.isGerman
        GeometryReader { geometry in
        // The room runs under the top safe area, as the loaded hero does.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Room for the journey chrome (back / ✕), drawn over this state by `ClubDetailView`.
                    Color.clear
                        .frame(height: geometry.safeAreaInsets.top + KuroJourneyChrome.barHeight)
                        .accessibilityHidden(true)

                    if let issue = phase.initialIssue, issue.isMembership {
                        // A membership notice keeps nothing of the club on screen.
                        EmptyView()
                    } else {
                        HStack(spacing: 10) {
                            ClubSeal(ring: ClubSeal.regularRing)
                                .accessibilityHidden(true)
                            if loadingBundle == nil {
                                Capsule().fill(skeletonBlock).frame(width: 120, height: 7)
                            }
                            Spacer(minLength: 0)
                        }
                        if let loadingBundle {
                            Text(loadingBundle.club.name)
                                .font(.kuroEditorial(size: 30)).tracking(-0.9)
                                .foregroundStyle(ClubRoomPalette.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 14)
                            Text(ClubRoomCopy.summary(memberCount: loadingBundle.member_count,
                                                      railCount: loadingBundle.rail_count ?? 0,
                                                      openPolls: 0,
                                                      german: german))
                                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                                .foregroundStyle(ClubRoomPalette.rowSecondary)
                                .padding(.top, 13)
                        } else {
                            Capsule().fill(skeletonDeep).frame(width: 200, height: 24)
                                .padding(.top, 16)
                                .accessibilityHidden(true)
                            HStack(spacing: 8) {
                                Circle().fill(skeletonBlock).frame(width: 24, height: 24)
                                Capsule().fill(skeletonBlock).frame(width: 140, height: 9)
                            }
                            .padding(.top, 14)
                            .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
                .kuroReadableWidth()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ClubRoomBackground(cornerRadius: 24, topCornerRadius: 0))

                stateView(german: german)
                    .frame(minHeight: 280)
                    .padding(.horizontal, 20)
                    .kuroReadableWidth()
            }
        }
        .ignoresSafeArea(edges: .top)
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
            // Two tile skeletons in the rails' grammar, then the branded scrub line.
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(alignment: .top, spacing: 9) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.kuroInk.opacity(KuroSkeleton.blockInkOpacity))
                                .frame(width: 44, height: 66)
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule().fill(Color.kuroInk.opacity(KuroSkeleton.deepBlockInkOpacity)).frame(height: 10)
                                Capsule().fill(Color.kuroInk.opacity(KuroSkeleton.blockInkOpacity)).frame(width: 56, height: 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(loadingBundle.map { KuroLocale.text("Opening \($0.club.name).", "\($0.club.name) wird geöffnet.") }
                    ?? KuroLocale.text("Opening the club.", "Der Club wird geöffnet."))
                KuroScrubLine().frame(maxWidth: 96)
                if !isConnected {
                    Text(KuroLocale.text("Waiting for a connection.", "Warte auf eine Verbindung."))
                        .font(.kuroCustom(11, relativeTo: .footnote, maxSize: 24))
                        .foregroundStyle(Color.kuroMuted)
                }
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
