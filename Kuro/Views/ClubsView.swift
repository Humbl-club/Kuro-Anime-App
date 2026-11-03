// MARK: - CLUBS VIEW (Main Clubs Page)
// Entry point for the Clubs section (pager page; also presented from Profile).
// Discover + Clubs redesign (spec §7.1–§7.2, §7.5): on Home's warm canvas, Home's opening row ("YOUR
// PRIVATE CLUBS · n" / "k with something new."), then one dark club room per club (`ClubRoomCard`,
// the same room as Home's and the club page's hero), newest activity first, then Home's invitation
// link rows (Start a club / Join a club) and Home's footer. A successful read with no clubs shows the
// room invitation; loading, offline and failed states are their own (`ClubsListRules`: a failed or
// offline read never shows the invitation).
//
// Data: `ClubsStore.refreshMyClubsIfStale()` on every visit (60 s window: revisiting the page does
// not refetch), a forced `fetchMyClubs()` on pull-to-refresh and Retry. Account scope: every async
// completion is checked against the captured `AccountActionScope` ticket.

import KuroCore
import SwiftUI
import UIKit

struct ClubsView: View {
    @Environment(ClubsStore.self) private var clubs
    @Environment(NetworkMonitor.self) private var networkMonitor
    /// Set while the pager is swiping: a swipe never opens a club (rulebook §7).
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    /// A club opens as a journey (navigation contract §1): pushed inside a journey, a new journey from
    /// the pager or from Profile's Clubs sheet (whose content installs its own presenter).
    @Environment(\.kuroRoutes) private var routes
    @State private var actionScope = AccountActionScope()

    @Binding var pendingJoinCode: String?

    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var joinPrefillCode = ""
    /// The club just created: opened once the create sheet has finished closing (presenting while a
    /// sheet is still leaving fails silently).
    @State private var createdClubId: String? = nil
    /// The club just joined: opened the same way once the join sheet has closed (spec D14).
    @State private var joinedClubId: String? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    /// The page's measured width (gutter and compact sizes; never the screen).
    @State private var containerWidth: CGFloat = 0

    init(pendingJoinCode: Binding<String?> = .constant(nil)) {
        _pendingJoinCode = pendingJoinCode
    }

    private var listState: ClubsListState {
        ClubsListRules.state(
            phase: clubs.myClubsPhase,
            hasClubs: !clubs.myClubs.isEmpty,
            isConnected: networkMonitor.isConnected
        )
    }

    private var gutter: CGFloat { ClubRoomLayout.gutter(containerWidth: containerWidth) }
    private var compact: Bool {
        ClubRoomLayout.isCompact(columnWidth: min(containerWidth, KuroReadableWidth.maxWidth) - gutter * 2)
    }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return ZStack {
            // One canvas with the header (spec G1, seam rule): Home's warm paper.
            Color.kuroCanvasHome.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                content(origin: origin)
                    .padding(.horizontal, gutter)
                    .padding(.top, ClubRoomLayout.top)
                    .padding(.bottom, KuroDesignSpacing.lg)
                    .kuroReadableWidth()
            }
            .refreshable {
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                await clubs.fetchMyClubs()
            }
            // Keep final rows clear of home-indicator chrome.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: KuroDesignSpacing.lg)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .task(id: origin) {
            guard let loadOrigin = actionScope.capture(session: clubs.accountSession) else { return }
            // Revisits inside the staleness window reuse what is on screen.
            await clubs.refreshMyClubsIfStale()
            guard actionScope.isCurrent(loadOrigin, session: clubs.accountSession) else { return }
            clubs.clearClubNotificationBadge()
        }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            consumePendingJoinCode()
        }
        .onDisappear {
            actionScope.deactivate()
            toastDismissTask?.cancel()
        }
        .onChange(of: pendingJoinCode) { _, _ in consumePendingJoinCode() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
                await clubs.refreshMyClubsIfStale()
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                await clubs.checkClubNotifications()
            }
        }
        .sheet(isPresented: $showCreateSheet, onDismiss: openCreatedClub) {
            CreateClubSheet { response in
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                createdClubId = response.club_id
                showToast(.success, title: KuroLocale.text("Club created", "Club erstellt"), subtitle: response.name)
            }
            .kuroLeavesJourney()
        }
        // N10: a deep link collapses this page's own sheets too.
        .kuroNavigationLayer("clubs.create", isPresented: $showCreateSheet)
        .sheet(isPresented: $showJoinSheet, onDismiss: {
            joinPrefillCode = ""
            openJoinedClub()
        }) {
            JoinClubSheet(initialCode: joinPrefillCode) { response in
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                joinedClubId = response.club_id
                showToast(.success, title: KuroLocale.text("You joined", "Du bist beigetreten"), subtitle: response.club_name)
            }
            .kuroLeavesJourney()
        }
        .kuroNavigationLayer("clubs.join", isPresented: $showJoinSheet)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(origin: AccountActionScope.Ticket?) -> some View {
        // One switch on the branded state (`ClubsListState.brandedState`, tested in RestyleLaneTests).
        switch listState.brandedState {
        case .loading:
            VStack(alignment: .leading, spacing: ClubRoomLayout.stack) {
                opening(kicker: ClubsEmptyCopy.kicker(german: KuroLocale.isGerman), headline: nil)
                ClubRoomSkeleton()
            }
        case .empty:
            ClubsInvitation(compact: compact, onCreate: openCreate, onJoin: openJoin)
        case .offline(hasContent: false):
            KuroStateView(.offline(hasCachedContent: false),
                          message: KuroLocale.text("Connect to see your clubs.", "Verbinde dich, um deine Clubs zu sehen."),
                          retry: { retry(origin: origin) })
                .frame(minHeight: 360)
        case .failed(hasContent: false):
            KuroErrorView(headline: KuroLocale.text("Couldn't load your clubs.", "Deine Clubs konnten nicht geladen werden."),
                          retry: { retry(origin: origin) })
                .frame(minHeight: 360)
        case .offline(hasContent: true):
            clubList(notice: .offline, origin: origin)
        case .failed(hasContent: true):
            clubList(notice: .failed, origin: origin)
        case nil:
            clubList(notice: nil, origin: origin)
        }
    }

    private func opening(kicker: String, headline: String?) -> some View {
        HomeOpeningLineView(kicker: kicker, headline: headline ?? "", compact: compact)
            .padding(.bottom, 6)
    }

    private func clubList(notice: ClubsListState.Notice?, origin: AccountActionScope.Ticket?) -> some View {
        let german = KuroLocale.isGerman
        let rows = ClubRoomRules.sortedForList(clubs.myClubs)
        let unread = rows.filter { clubs.hasUnseenActivity(club: $0) }.count
        let now = Date()
        return VStack(alignment: .leading, spacing: ClubRoomLayout.stack) {
            if notice == .offline {
                let band = ClubRoomCopy.offlineBand(german: german)
                ClubOfflineBand(lead: band.lead, rest: band.rest, retry: { retry(origin: origin) })
            }

            opening(kicker: ClubRoomCopy.listKicker(count: rows.count, german: german),
                    headline: ClubRoomCopy.listHeadline(unread: unread, german: german))

            if notice == .failed {
                KuroStateView(.failed(hasCachedContent: true), layout: .inline, retry: { retry(origin: origin) })
            }

            LazyVStack(spacing: ClubRoomLayout.roomGap) {
                ForEach(rows) { club in
                    let hasUnseen = clubs.hasUnseenActivity(club: club)
                    Button {
                        guard !suppressCardTaps else { return }
                        KuroAccessibility.impactHaptic(.light)
                        // Navigation contract: the club opens as a journey (pager) or is pushed (Profile's
                        // journey), never as a page-local sheet.
                        routes.openClub(club.id)
                    } label: {
                        ClubRoomCard(club: club, hasUnseen: hasUnseen, now: now)
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ClubsListCardRules.accessibilityLabel(
                        name: club.name,
                        memberCount: club.member_count,
                        sharingLevel: club.sharing_level,
                        hasUnseen: hasUnseen,
                        recentLine: ClubsListCardRules.recentLine(club.activity_preview, german: german),
                        german: german
                    ))
                    .accessibilityHint(KuroLocale.text("Opens the club", "Öffnet den Club"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { routes.openClub(club.id) }
                }
            }

            VStack(alignment: .leading, spacing: ClubRoomLayout.linkRowGap) {
                ClubLinkRow(kicker: KuroLocale.text("New", "Neu"),
                            title: KuroLocale.text("Start a club.", "Gründe einen Club."),
                            action: openCreate)
                ClubLinkRow(kicker: KuroLocale.text("Invite code", "Einladungscode"),
                            title: KuroLocale.text("Join a club.", "Tritt einem Club bei."),
                            action: openJoin)
            }
            .padding(.top, 16)

            HomeFooter()
        }
    }

    // MARK: - Actions

    private func openCreate() {
        KuroAccessibility.impactHaptic(.light)
        showCreateSheet = true
    }

    private func openJoin() {
        KuroAccessibility.impactHaptic(.light)
        showJoinSheet = true
    }

    /// The create sheet has closed: a club created there opens as its own journey (navigation
    /// contract: creating a club opens it). Cancel opens nothing.
    private func openCreatedClub() {
        guard let clubId = ClubCreationFollowUp.clubToOpen(created: createdClubId,
                                                           isCurrent: actionScope.capture(session: clubs.accountSession) != nil)
        else { createdClubId = nil; return }
        createdClubId = nil
        routes.openClub(clubId)
    }

    /// The join sheet has closed: the club just joined opens, the same way a created one does (D14).
    private func openJoinedClub() {
        guard let clubId = ClubCreationFollowUp.clubToOpen(created: joinedClubId,
                                                           isCurrent: actionScope.capture(session: clubs.accountSession) != nil)
        else { joinedClubId = nil; return }
        joinedClubId = nil
        routes.openClub(clubId)
    }

    private func retry(origin: AccountActionScope.Ticket?) {
        actionScope.launch(origin: origin, session: clubs.accountSession) { _ in
            await clubs.fetchMyClubs()
        }
    }

    /// Deep-link entry (kuro://join/<code>): open the join sheet prefilled, then clear the stash.
    private func consumePendingJoinCode() {
        guard let code = pendingJoinCode else { return }
        pendingJoinCode = nil
        joinPrefillCode = code
        showJoinSheet = true
        #if DEBUG
        print("[Clubs] Opened join sheet from deep link (code prefilled)")
        #endif
    }

    // MARK: - Toast helper

    private func showToast(_ kind: KuroToastState.Kind, title: String, subtitle: String?) {
        toastDismissTask?.cancel()
        withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
            toast = KuroToastState(kind: kind, title: title, subtitle: subtitle, actionTitle: nil, onAction: nil)
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(KuroMotion.resolve(KuroMotion.settle)) { toast = nil }
        }
    }
}

// MARK: - Create, then open

/// What happens when the create-club (or join-club) sheet has closed (pure, NavclubsTests): the club
/// created or joined there opens, but only for the account that did it; a cancelled sheet opens nothing.
nonisolated enum ClubCreationFollowUp {
    static func clubToOpen(created clubId: String?, isCurrent: Bool) -> String? {
        guard isCurrent, let clubId, !clubId.isEmpty else { return nil }
        return clubId
    }
}

// MARK: - Invitation (no clubs yet)

/// The empty page after a successful read (spec §7.2), on the warm canvas: Home's opening row, then
/// the dark room with the club seal, "YOUR PRIVATE CLUB", the serif headline, the line, the solid room
/// key "Start a club", the quiet "Join with a code ›" row and the room footer; a quiet card says what
/// members can see; Home's footer. No sample club, member or note. Never shown for a failed or offline read.
private struct ClubsInvitation: View {
    let compact: Bool
    let onCreate: () -> Void
    let onJoin: () -> Void
    /// The room's own width, measured.
    @State private var roomWidth: CGFloat = 0

    var body: some View {
        let german = KuroLocale.isGerman
        let roomCompact = HomeClubRoom.isCompact(width: roomWidth)
        VStack(alignment: .leading, spacing: ClubRoomLayout.stack) {
            HomeOpeningLineView(kicker: ClubsEmptyCopy.kicker(german: german),
                                headline: ClubRoomCopy.emptyHeadline(german: german), compact: compact)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: roomCompact ? 8 : 10) {
                    ClubSeal(ring: ClubSeal.ring(compact: roomCompact))
                        .accessibilityHidden(true)
                    Text(KuroLocale.text("Your private club", "Dein privater Club"))
                        .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(ClubRoomPalette.kicker)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }

                Text(ClubsEmptyCopy.headline(german: german))
                    .font(.kuroEditorial(size: roomCompact ? 26 : 30))
                    .tracking(-0.9)
                    .lineSpacing(1)
                    .foregroundStyle(ClubRoomPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 18)

                Text(ClubsEmptyCopy.line(german: german))
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(ClubRoomPalette.rowSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                ClubRoomPrimaryButton(title: ClubsEmptyCopy.create(german: german), action: onCreate)
                    .padding(.top, 20)
                ClubRoomQuietRow(title: ClubsEmptyCopy.join(german: german), action: onJoin)
                    .padding(.top, 6)

                HStack(spacing: 10) {
                    Text(ClubsEmptyCopy.footer(german: german))
                    Spacer(minLength: 0)
                    Text(ClubsEmptyCopy.size(german: german))
                }
                .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 15))
                .foregroundStyle(ClubRoomPalette.footer)
                .padding(.top, 10)
                .padding(.horizontal, 2)
                .overlay(alignment: .top) { Rectangle().fill(ClubRoomPalette.footerRule).frame(height: 1) }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 22)
            .padding(.horizontal, roomCompact ? 12 : 18)
            .padding(.bottom, 12)
            .background(ClubRoomBackground(cornerRadius: 24))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)

            HomeQuietCard(text: ClubRoomCopy.sharingLevelsNote(german: german))

            HomeFooter()
        }
    }
}

/// The Clubs invitation's copy (EN, DE). Pure, pinned in RestyleLaneTests.
nonisolated enum ClubsEmptyCopy {
    static func kicker(german: Bool) -> String { german ? "DEINE PRIVATEN CLUBS" : "YOUR PRIVATE CLUBS" }
    static func headline(german: Bool) -> String {
        german ? "Gemeinsam schauen.\nPrivat von Anfang an." : "Watch together.\nPrivate by design."
    }
    static func line(german: Bool) -> String {
        german ? "Ein Club sind 2 bis 20 Freunde, die du einlädst. Nichts darin ist öffentlich."
               : "A club is 2 to 20 friends you invite. Nothing in it is public."
    }
    static func create(german: Bool) -> String { german ? "Einen Club gründen" : "Start a club" }
    static func join(german: Bool) -> String { german ? "Mit Code beitreten" : "Join with a code" }
    static func footer(german: Bool) -> String { german ? "Geteilte Geschichten. Deine Leute." : "Shared stories. Your people." }
    static func size(german: Bool) -> String { german ? "2–20 Personen" : "2–20 people" }
}

/// The room's primary key: the solid dark room key (`ClubRoomPalette.key`), light ink, centred label.
private struct ClubRoomPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.kuroCustom(13, weight: .medium, relativeTo: .subheadline, maxSize: 26))
                .multilineTextAlignment(.center)
                .foregroundStyle(ClubRoomPalette.text)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "36413A"), ClubRoomPalette.key], startPoint: .top, endPoint: .bottom))
                )
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(hex: "5B665E"), lineWidth: 1))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(Double(0x22) / 255), lineWidth: 1)
                        .mask(Rectangle().frame(height: 2).frame(maxHeight: .infinity, alignment: .top))
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(title)
    }
}

/// The room's quiet row: 12 pt `rowSecondary` text and "›", 44 pt.
private struct ClubRoomQuietRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 24))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                Text("›")
                    .font(.kuroCustom(17, relativeTo: .body, maxSize: 28))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(ClubRoomPalette.rowSecondary)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Create Club Sheet

struct CreateClubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()

    @State private var name = ""
    @State private var description = ""
    @State private var sharingLevel = ClubFormRules.defaultSharingLevel
    @State private var isSubmitting = false
    @State private var errorText: String? = nil
    @State private var confirmDiscard = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, description }

    private var isDirty: Bool {
        ClubFormRules.createClubIsDirty(name: name, description: description, sharingLevel: sharingLevel)
    }

    static let nameLimit = 80
    static let descriptionLimit = 500

    let onCreated: (CreateClubResponse) -> Void

    private let sharingLevels = ["private", "status", "progress"]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool {
        !trimmedName.isEmpty
            && ClubFormField.serverLength(trimmedName) <= Self.nameLimit
            && ClubFormField.serverLength(trimmedDescription) <= Self.descriptionLimit
    }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        let german = KuroLocale.isGerman
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    ClubSheetTitle(kicker: KuroLocale.text("New club", "Neuer Club"),
                                   title: KuroLocale.text("Start a club.", "Gründe einen Club."),
                                   showsSeal: true)

                    ClubFormField(label: KuroLocale.text("Name", "Name"),
                                  prompt: KuroLocale.text("Friday anime night", "Anime-Abend am Freitag"),
                                  text: $name,
                                  limit: Self.nameLimit)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .description }

                    ClubFormField(label: KuroLocale.text("Description (optional)", "Beschreibung (optional)"),
                                  prompt: KuroLocale.text("What's this club about?", "Worum geht es in diesem Club?"),
                                  text: $description,
                                  limit: Self.descriptionLimit,
                                  axis: .vertical)
                        .focused($focus, equals: .description)

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text(KuroLocale.text("What members see", "Was Mitglieder sehen"))
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 0) {
                            ForEach(sharingLevels, id: \.self) { level in
                                ClubChoiceRow(
                                    title: ClubsListCardRules.audienceLabel(sharingLevel: level, german: german),
                                    detail: ClubCopy.sharingDescription(level, german: german),
                                    isSelected: sharingLevel == level
                                ) {
                                    KuroAccessibility.selectionHaptic()
                                    sharingLevel = level
                                }
                                if level != sharingLevels.last {
                                    Rectangle().fill(Color.kuroHairline).frame(height: 1)
                                }
                            }
                        }
                    }

                    if let errorText {
                        ClubInlineError(text: errorText)
                    }

                    KuroInkButton(KuroLocale.text("Create club", "Club erstellen"), isLoading: isSubmitting) {
                        submit(origin: origin)
                    }
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
                .kuroReadableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.kuroCanvasPage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { cancel() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .kuroDiscardGuard(isDirty: isDirty, isBusy: isSubmitting, isConfirming: $confirmDiscard) { dismiss() }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            focus = .name
        }
        .onDisappear { actionScope.deactivate(); isSubmitting = false }
    }

    /// Cancel (N7): a clean form closes; unsaved input asks "Discard changes?" first.
    private func cancel() {
        switch KuroDiscardGuard.cancelStep(isDirty: isDirty) {
        case .close: dismiss()
        case .confirm: confirmDiscard = true
        }
    }

    private func submit(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        guard canSubmit, !isSubmitting else { return }
        let trimmed = trimmedName
        let desc = trimmedDescription
        let sharing = sharingLevel
        isSubmitting = true
        errorText = nil
        focus = nil

        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
            do {
                let resp = try await clubs.createClub(
                    name: trimmed,
                    description: desc.isEmpty ? nil : desc,
                    sharingLevel: sharing
                )
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                KuroAccessibility.successHaptic()
                onCreated(resp)
                dismiss()
            } catch {
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                if error is CancellationError { isSubmitting = false; return }
                let message = ClubCopy.createClubError(error as? ClubError, german: KuroLocale.isGerman)
                errorText = message
                AccessibilityNotification.Announcement(message).post()
                KuroAccessibility.errorHaptic()
            }
            if actionScope.isCurrent(ticket, session: clubs.accountSession) { isSubmitting = false }
        }
    }
}

// MARK: - Join Club Sheet

private struct JoinClubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()

    @State private var inviteCode: String
    @State private var isSubmitting = false
    @State private var errorText: String? = nil
    @State private var confirmDiscard = false
    @FocusState private var codeFocused: Bool

    /// The deep-link prefill: an untouched prefilled sheet is not unsaved input (N7).
    private let initialCode: String
    let onJoined: (JoinClubResponse) -> Void

    init(initialCode: String = "", onJoined: @escaping (JoinClubResponse) -> Void) {
        _inviteCode = State(initialValue: ClubInviteCode.normalize(initialCode))
        self.initialCode = initialCode
        self.onJoined = onJoined
    }

    private var isValid: Bool { ClubInviteCode.isValid(inviteCode) }
    private var isDirty: Bool { ClubJoinRules.isDirty(code: inviteCode, initialCode: initialCode) }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        let german = KuroLocale.isGerman
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    ClubSheetTitle(kicker: KuroLocale.text("Invite code", "Einladungscode"),
                                   title: KuroLocale.text("Join a club.", "Tritt einem Club bei."))

                    Text(KuroLocale.text(
                        "Enter the 8-character code a member shared with you. Upper and lower case matter.",
                        "Gib den 8-stelligen Code ein, den dir ein Mitglied geschickt hat. Groß- und Kleinschreibung zählt."
                    ))
                    .font(.kuroBody(weight: .light))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        TextField(
                            "",
                            text: $inviteCode,
                            prompt: Text(verbatim: "AbC12xYz").foregroundStyle(Color.kuroInkQuiet)
                        )
                        .font(.kuroCustom(24, weight: .medium, design: .monospaced, relativeTo: .title2, maxSize: 44))
                        .tracking(3)
                        .foregroundStyle(Color.kuroInk)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .focused($codeFocused)
                        .onSubmit { submit(origin: origin) }
                        .padding(.horizontal, KuroDesignSpacing.md)
                        .frame(minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                                .fill(Color.kuroCanvasQuiet)
                        )
                        .accessibilityLabel(KuroLocale.text("Invite code", "Einladungscode"))
                        .onChange(of: inviteCode) { _, newValue in
                            let normalized = ClubInviteCode.normalize(newValue)
                            if normalized != newValue { inviteCode = normalized }
                            if errorText != nil { errorText = nil }
                        }

                        HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
                            Text(ClubInviteCode.hint(for: inviteCode, german: german)
                                 ?? KuroLocale.text("8 letters and numbers.", "8 Buchstaben und Ziffern."))
                                .font(.kuroMeta())
                                .foregroundStyle(Color.kuroInkSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            PasteButton(payloadType: String.self) { strings in
                                guard let first = strings.first else { return }
                                Task { @MainActor in
                                    inviteCode = ClubInviteCode.normalize(first)
                                    errorText = nil
                                }
                            }
                            .buttonBorderShape(.capsule)
                            .labelStyle(.titleAndIcon)
                            .tint(Color.kuroInk)
                            .frame(minHeight: 44)
                        }
                    }

                    if let errorText {
                        ClubInlineError(text: errorText)
                    }

                    KuroInkButton(KuroLocale.text("Join club", "Club beitreten"), isLoading: isSubmitting) {
                        submit(origin: origin)
                    }
                    .disabled(!isValid)
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
                .kuroReadableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.kuroCanvasPage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { cancel() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .presentationDragIndicator(.visible)
        // N7: once a code is typed, swipe-down is blocked and Cancel asks first (spec §7.4).
        .kuroDiscardGuard(isDirty: isDirty, isBusy: isSubmitting, isConfirming: $confirmDiscard) { dismiss() }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            if inviteCode.isEmpty { codeFocused = true }
        }
        .onDisappear { actionScope.deactivate(); isSubmitting = false }
    }

    /// Cancel (N7): a clean (or untouched prefilled) form closes; a typed code asks first.
    private func cancel() {
        switch KuroDiscardGuard.cancelStep(isDirty: isDirty) {
        case .close: dismiss()
        case .confirm: confirmDiscard = true
        }
    }

    private func submit(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
        let code = inviteCode
        guard ClubInviteCode.isValid(code), !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        codeFocused = false

        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
            do {
                let resp = try await clubs.joinClub(inviteCode: code)
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                KuroAccessibility.successHaptic()
                onJoined(resp)
                dismiss()
            } catch {
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                if error is CancellationError { isSubmitting = false; return }
                let message = ClubCopy.joinError(error as? ClubError, german: KuroLocale.isGerman)
                errorText = message
                AccessibilityNotification.Announcement(message).post()
                KuroAccessibility.errorHaptic()
            }
            if actionScope.isCurrent(ticket, session: clubs.accountSession) { isSubmitting = false }
        }
    }
}
