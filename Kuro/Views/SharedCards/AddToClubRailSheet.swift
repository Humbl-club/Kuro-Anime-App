// AddToClubRailSheet: shared connected sheet that adds a title to a rail of one of the user's
// clubs (pick a club, load its rails, add). Moved verbatim from DetailPages/ClubActivitySection.swift
// (placement only; see docs/plans/2026-10-05-modular-architecture-large-file-review.md §9 item 3).
//
// Reads: ClubsStore (`myClubs`, `fetchMyClubs`, `fetchClubBundle`, `addRailItem`,
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

    private var clubsInteractionV2Enabled: Bool {
        flags.isClubsInteractionV2Enabled
    }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return NavigationStack {
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

                        ForEach(clubs.myClubs.filter { !$0.is_archived }) { club in
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                selectClub(club.id, origin: origin)
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
                                        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in await addToRail(railId: rail.id, clubId: bundle.club.id, origin: ticket) }
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
        .onAppear { actionScope.activate(session: clubs.accountSession) }
        .task(id: origin) {
            guard let origin, actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            if clubs.myClubs.isEmpty {
                await clubs.fetchMyClubs()
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
            }
            if clubsInteractionV2Enabled {
                let eligible = clubs.myClubs.filter { !$0.is_archived }
                guard selectedClubId == nil, !eligible.isEmpty else { return }
                if let remembered = clubs.rememberedAddToClubId(),
                   eligible.contains(where: { $0.id == remembered }) {
                    selectClub(remembered, origin: origin)
                } else if let first = eligible.first?.id {
                    selectClub(first, origin: origin)
                }
            }
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
                errorText = "Could not load rails."
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
        errorText = "You're no longer a member of this club."
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
                errorText = "You're no longer a member of this club."
                bundle = nil
            } else {
                errorText = "Could not add to rail."
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
