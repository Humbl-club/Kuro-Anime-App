// AddToClubRailSheet: shared connected sheet that adds a title to a rail of one of the user's
// clubs (pick a club, load its rails, add). Moved verbatim from DetailPages/ClubActivitySection.swift
// (placement only; see docs/plans/2026-10-05-modular-architecture-large-file-review.md §9 item 3).
//
// Reads: ClubsStore (`myClubs`, `myClubsPhase`, `refreshMyClubsIfStale`, `fetchMyClubs` (Retry), `fetchClubBundle`, `addRailItem`,
// `refreshClubBundle`, `revocationEpoch`, remembered add-to-club id), FeatureFlags
// (`isClubsInteractionV2Enabled`), InteractionTelemetry (`clubs_add_to_rail_*` events) and
// `\.dismiss`. Uses `ClubSelectionRevocation` (ClubViewLifecycle.swift) and `ClubError`.
// Consumers (constructors): ClubActivitySection.swift (its ADD button sheet) and
// Routing/KuroRoutes.swift (`RouteDestinationView` for `.addToClub`, reached through
// `routes.presentAddToClub` from GridAnimeCard and KuroRefinedCard). Mentioned in comments by
// ClubViewLifecycle.swift, KuroTests/ClubsViewRulesTests.swift and KuroTests/RoutingTests.swift.

import KuroCore
import SwiftUI

// MARK: - Add to Club Rail Sheet

struct AddToClubRailSheet: View {
    let mediaId: Int
    let mediaType: String

    @Environment(\.dismiss) private var dismiss
    @Environment(InteractionTelemetry.self) private var interactionTelemetry
    @Environment(FeatureFlags.self) private var flags
    @Environment(ClubsStore.self) private var clubs
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var actionScope = AccountActionScope()
    @State private var selectedClubId: String? = nil
    @State private var bundle: ClubBundle? = nil
    @State private var isLoading = false
    @State private var errorText: String? = nil
    @State private var isSubmitting = false
    @State private var pendingRailId: String? = nil
    @State private var loadBundleTask: Task<Void, Never>? = nil
    /// The selected club's revocation epoch when it was selected (`ClubsStore.revocationEpoch`).
    @State private var selectedClubEpoch: Int? = nil
    /// The automatic pre-selection happens at most once per presentation (never after a revocation
    /// or a disclosure reload changes the club list).
    @State private var didAutoSelect = false

    private var clubsInteractionV2Enabled: Bool {
        flags.isClubsInteractionV2Enabled
    }

    private var eligibleClubs: [ClubListRow] {
        clubs.myClubs.filter { !$0.is_archived }
    }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    ClubSheetTitle(kicker: KuroLocale.text("Clubs", "Clubs"),
                                   title: KuroLocale.text("Add to a club.", "Zu einem Club hinzufügen."))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(KuroLocale.text("Club", "Club"))
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, KuroDesignSpacing.xs)

                        clubChoices(origin: origin)
                    }

                    Rectangle().fill(Color.kuroHairline).frame(height: 1)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(KuroLocale.text("Rail", "Liste"))
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, KuroDesignSpacing.xs)

                        railChoices(origin: origin)
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
                .kuroReadableWidth()
            }
            .background(Color.kuroCanvasPage)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: KuroDesignSpacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { dismiss() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .onAppear { actionScope.activate(session: clubs.accountSession) }
        .task(id: origin) {
            guard let origin, actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            // Reuses a read from the last minute; a failed or missing read asks again.
            await clubs.refreshMyClubsIfStale()
            autoSelectIfNeeded(origin: origin)
        }
        .onChange(of: eligibleClubs.map(\.id)) { _, _ in
            // `refreshMyClubsIfStale()` returns at once while another caller's read is in flight
            // (opened from a detail page that just started one): pick when that read lands.
            autoSelectIfNeeded(origin: actionScope.capture(session: clubs.accountSession))
        }
        .onDisappear {
            actionScope.deactivate()
            isSubmitting = false
            isLoading = false
            loadBundleTask?.cancel()
        }
        .onChange(of: selectedClubId.map { clubs.revocationEpoch($0) }) { _, epoch in
            // Fires on a club switch too; only a change of the selected club's own epoch is a revocation.
            guard ClubSelectionRevocation.isRevocation(current: epoch, captured: selectedClubEpoch),
                  let epoch else { return }
            selectedClubRevoked(epoch: epoch)
        }
    }

    // MARK: - Club choices

    @ViewBuilder
    private func clubChoices(origin: AccountActionScope.Ticket?) -> some View {
        // "Not in a club" is decided from all clubs; archived-only is its own honest line.
        let state = ClubsListRules.state(phase: clubs.myClubsPhase, hasClubs: !clubs.myClubs.isEmpty,
                                         isConnected: networkMonitor.isConnected)
        switch state {
        case .loading:
            KuroStateView(.loading, title: KuroLocale.text("Loading your clubs.", "Deine Clubs werden geladen."), layout: .inline)
        case .empty:
            KuroStateView(.empty,
                          title: KuroLocale.text("You're not in a club yet.", "Du bist noch in keinem Club."),
                          message: KuroLocale.text("Start or join one on the Clubs page.", "Gründe oder finde einen auf der Clubs-Seite."),
                          layout: .inline)
        case .offline:
            KuroStateView(.offline(hasCachedContent: false), layout: .inline, retry: { retryClubs(origin: origin) })
        case .failed:
            KuroStateView(.failed(hasCachedContent: false),
                          title: KuroLocale.text("Couldn't load your clubs.", "Deine Clubs konnten nicht geladen werden."),
                          layout: .inline,
                          retry: { retryClubs(origin: origin) })
        case let .list(notice):
            if let notice {
                // The last refresh failed: the clubs stay with the reason and Retry (as ClubsView).
                KuroStateView(notice == .offline ? .offline(hasCachedContent: true) : .failed(hasCachedContent: true),
                              layout: .inline,
                              retry: { retryClubs(origin: origin) })
            }
            if eligibleClubs.isEmpty {
                KuroStateView(.empty,
                              title: KuroLocale.text("Your clubs are archived.", "Deine Clubs sind archiviert."),
                              message: KuroLocale.text("Start or join one on the Clubs page.", "Gründe oder finde einen auf der Clubs-Seite."),
                              layout: .inline)
            }
            ForEach(eligibleClubs) { club in
                let isSelected = selectedClubId == club.id
                Button {
                    KuroAccessibility.selectionHaptic()
                    selectClub(club.id, origin: origin)
                } label: {
                    HStack(spacing: KuroDesignSpacing.md) {
                        Text(club.name)
                            .font(.kuroBody(weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "checkmark")
                            .font(.kuroMeta(weight: .semibold))
                            .foregroundStyle(Color.kuroInk)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle(pressedScale: 0.99))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.kuroHairline).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Rail choices

    @ViewBuilder
    private func railChoices(origin: AccountActionScope.Ticket?) -> some View {
        if isLoading {
            KuroStateView(.loading, title: KuroLocale.text("Loading rails.", "Listen werden geladen."), layout: .inline)
        } else if let bundle {
            if let errorText {
                // A failed add keeps the rails on screen with the reason above them.
                ClubInlineError(text: errorText)
                    .padding(.vertical, KuroDesignSpacing.sm)
            }
            if bundle.rails.isEmpty {
                KuroStateView(.empty,
                              title: KuroLocale.text("No rails yet.", "Noch keine Listen."),
                              message: KuroLocale.text("Ask an admin to start one.", "Bitte einen Admin, eine anzulegen."),
                              layout: .inline)
            } else {
                ForEach(bundle.rails) { rail in
                    let canAdd = !(rail.is_locked && !["owner", "admin"].contains(bundle.my_role))
                    let isPending = clubsInteractionV2Enabled && pendingRailId == rail.id

                    Button {
                        guard canAdd, !isSubmitting else { return }
                        KuroAccessibility.impactHaptic(.light)
                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await addToRail(railId: rail.id, clubId: bundle.club.id, origin: ticket) }
                    } label: {
                        HStack(spacing: KuroDesignSpacing.md) {
                            Text(rail.title)
                                .font(.kuroBody(weight: .regular))
                                .foregroundStyle(canAdd ? Color.kuroInk : Color.kuroInkQuiet)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if rail.is_locked {
                                Image(systemName: "lock")
                                    .font(.kuroMeta())
                                    .foregroundStyle(Color.kuroInkQuiet)
                                    .accessibilityHidden(true)
                            }

                            if isPending && isSubmitting {
                                KuroBusyMark(width: 20)
                            } else {
                                Image(systemName: isPending ? "checkmark" : "plus")
                                    .font(.kuroMeta(weight: .semibold))
                                    .foregroundStyle(canAdd ? Color.kuroInk : Color.kuroInkQuiet)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KuroPressStyle(pressedScale: 0.99))
                    .disabled(!canAdd || isSubmitting)
                    .accessibilityLabel(rail.is_locked
                        ? KuroLocale.text("\(rail.title), locked", "\(rail.title), gesperrt")
                        : rail.title)
                    .accessibilityHint(canAdd ? KuroLocale.text("Adds the title to this rail.", "Fügt den Titel dieser Liste hinzu.") : "")
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.kuroHairline).frame(height: 1)
                    }
                }
            }
        } else if let errorText {
            ClubInlineError(text: errorText)
                .padding(.vertical, KuroDesignSpacing.sm)
        } else {
            Text(KuroLocale.text("Pick a club to see its rails.", "Wähle einen Club, um seine Listen zu sehen."))
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
                .padding(.vertical, KuroDesignSpacing.sm)
        }
    }

    /// clubs_interaction_v2: pre-select the remembered club, else the first eligible one, once there
    /// are clubs and nothing is selected yet.
    private func autoSelectIfNeeded(origin: AccountActionScope.Ticket?) {
        guard clubsInteractionV2Enabled, actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        let eligible = eligibleClubs
        guard !didAutoSelect, selectedClubId == nil, !eligible.isEmpty else { return }
        didAutoSelect = true
        if let remembered = clubs.rememberedAddToClubId(),
           eligible.contains(where: { $0.id == remembered }) {
            selectClub(remembered, origin: origin)
        } else if let first = eligible.first?.id {
            selectClub(first, origin: origin)
        }
    }

    private func retryClubs(origin: AccountActionScope.Ticket?) {
        actionScope.launch(origin: origin, session: clubs.accountSession) { _ in
            await clubs.fetchMyClubs()
        }
    }

    private func selectClub(_ clubId: String, origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        selectedClubId = clubId
        selectedClubEpoch = clubs.revocationEpoch(clubId)
        if clubsInteractionV2Enabled {
            clubs.setRememberedAddToClubId(clubId)
        }
        loadBundleTask?.cancel()
        bundle = nil
        errorText = nil
        isLoading = true
        isSubmitting = false
        pendingRailId = nil

        loadBundleTask = actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
            defer {
                // Ignore stale/cancelled completions so a newer request owns loading state.
                if actionScope.isCurrent(ticket, session: clubs.accountSession), selectedClubId == clubId {
                    isLoading = false
                }
            }
            do {
                let fetched = try await clubs.fetchClubBundle(clubId: clubId, forceRefresh: true)
                guard actionScope.isCurrent(ticket, session: clubs.accountSession), selectedClubId == clubId else { return }
                bundle = fetched
            } catch {
                guard actionScope.isCurrent(ticket, session: clubs.accountSession), selectedClubId == clubId else { return }
                guard !(error is CancellationError) else { return }
                errorText = KuroLocale.text("Couldn't load the rails. Pick the club again to retry.", "Die Listen konnten nicht geladen werden. Wähle den Club erneut, um es noch einmal zu versuchen.")
            }
        }
    }

    /// The selected club was revoked (left, removed or deleted) while the sheet is open: drop its
    /// rails and stop its load, as for a NOT_A_MEMBER answer.
    private func selectedClubRevoked(epoch: Int) {
        selectedClubEpoch = epoch
        loadBundleTask?.cancel()
        bundle = nil
        isLoading = false
        pendingRailId = nil
        errorText = KuroLocale.text("You're no longer a member of this club.", "Du bist nicht mehr Mitglied dieses Clubs.")
    }

    private func addToRail(railId: String, clubId: String, origin: AccountActionScope.Ticket) async {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        pendingRailId = clubsInteractionV2Enabled ? railId : nil
        let startedAt = interactionTelemetry.beginInteractionTiming()
        interactionTelemetry.trackInteractionEvent(
            "clubs_add_to_rail_tap",
            surface: "club_activity_add_sheet",
            result: "attempt",
            extra: ["club_id": clubId]
        )
        defer { if actionScope.isCurrent(origin, session: clubs.accountSession) { isSubmitting = false } }
        do {
            _ = try await clubs.addRailItem(
                railId: railId,
                mediaType: mediaType.uppercased(),
                mediaId: mediaId
            )
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            // Refresh the club bundle so the club view and activity cache update quickly.
            _ = try? await clubs.refreshClubBundle(clubId: clubId)
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            interactionTelemetry.trackInteractionEvent(
                "clubs_add_to_rail_success",
                surface: "club_activity_add_sheet",
                result: "ok",
                startedAt: startedAt,
                extra: ["club_id": clubId]
            )
            KuroAccessibility.successHaptic()
            dismiss()
        } catch {
            guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            KuroAccessibility.errorHaptic()
            if (error as? ClubError) == .notAMember {
                errorText = KuroLocale.text("You're no longer a member of this club.", "Du bist nicht mehr Mitglied dieses Clubs.")
                bundle = nil
            } else if !(error is CancellationError) {
                errorText = ClubCopy.addRailItemError(error as? ClubError, german: KuroLocale.isGerman)
            }
            pendingRailId = nil
            interactionTelemetry.trackInteractionEvent(
                "clubs_add_to_rail_error",
                surface: "club_activity_add_sheet",
                result: "error",
                startedAt: startedAt,
                extra: ["club_id": clubId]
            )
        }
    }
}
