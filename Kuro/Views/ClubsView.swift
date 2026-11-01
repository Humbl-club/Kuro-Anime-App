// MARK: - CLUBS VIEW (Main Clubs Page)
// Entry point for the Clubs section (pager page; also presented from Profile).
// Shows the caller's private clubs as inhabited cards (real rail artwork, serif name, member
// initials, one real recent line or nothing, an ink dot for unread), the Create / Join invitation
// when a successful read found no clubs, and honest loading / offline / failed states otherwise
// (`ClubsListRules`: a failed or offline read never shows the invitation).
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
    @State private var actionScope = AccountActionScope()

    @Binding var pendingJoinCode: String?

    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var joinPrefillCode = ""
    @State private var selectedClubId: String? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

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

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        return ZStack {
            Color.kuroCanvasPage.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                content(origin: origin)
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.md)
                    .padding(.bottom, KuroDesignSpacing.xxl)
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
        .sheet(isPresented: $showCreateSheet) {
            CreateClubSheet { response in
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                showToast(.success, title: KuroLocale.text("Club created", "Club erstellt"), subtitle: response.name)
            }
        }
        .sheet(isPresented: $showJoinSheet, onDismiss: { joinPrefillCode = "" }) {
            JoinClubSheet(initialCode: joinPrefillCode) { response in
                guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
                showToast(.success, title: KuroLocale.text("You joined", "Du bist beigetreten"), subtitle: response.club_name)
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedClubId != nil },
            set: { if !$0 { selectedClubId = nil } }
        )) {
            if let clubId = selectedClubId {
                NavigationStack {
                    ClubDetailView(clubId: clubId)
                        .id(clubId)
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(origin: AccountActionScope.Ticket?) -> some View {
        switch listState {
        case .loading:
            ClubsLoadingSkeleton()
        case .empty:
            ClubsInvitation(onCreate: openCreate, onJoin: openJoin)
                .padding(.top, KuroDesignSpacing.lg)
        case .offline:
            KuroStateView(.offline(hasCachedContent: false),
                          message: KuroLocale.text("Connect to see your clubs.", "Verbinde dich, um deine Clubs zu sehen."),
                          retry: { retry(origin: origin) })
                .frame(minHeight: 360)
        case .failed:
            KuroStateView(.failed(hasCachedContent: false),
                          title: KuroLocale.text("Couldn't load your clubs.", "Deine Clubs konnten nicht geladen werden."),
                          retry: { retry(origin: origin) })
                .frame(minHeight: 360)
        case let .list(notice):
            clubList(notice: notice, origin: origin)
        }
    }

    private func clubList(notice: ClubsListState.Notice?, origin: AccountActionScope.Ticket?) -> some View {
        let german = KuroLocale.isGerman
        return VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            KuroSectionHeader(KuroLocale.text("Your clubs.", "Deine Clubs."),
                              kicker: KuroLocale.text("Private", "Privat"))

            if let notice {
                KuroStateView(notice == .offline ? .offline(hasCachedContent: true) : .failed(hasCachedContent: true),
                              layout: .inline,
                              retry: { retry(origin: origin) })
            }

            LazyVStack(spacing: KuroDesignSpacing.md) {
                ForEach(clubs.myClubs) { club in
                    let hasUnseen = clubs.hasUnseenActivity(club: club)
                    Button {
                        guard !suppressCardTaps else { return }
                        KuroAccessibility.impactHaptic(.light)
                        selectedClubId = club.id
                    } label: {
                        ClubListCard(club: club, hasUnseen: hasUnseen)
                    }
                    .buttonStyle(KuroPressStyle(pressedScale: 0.985))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ClubsListCardRules.accessibilityLabel(
                        name: club.name,
                        memberCount: club.member_count,
                        sharingLevel: club.sharing_level,
                        hasUnseen: hasUnseen,
                        recentLine: ClubsListCardRules.recentLine(club.activity_preview, german: german),
                        german: german
                    ))
                    .accessibilityHint(KuroLocale.text("Opens the club.", "Öffnet den Club."))
                    .accessibilityAddTraits(.isButton)
                }
            }

            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                ClubInvitationAction(kicker: KuroLocale.text("New", "Neu"),
                                     title: KuroLocale.text("Start another club.", "Noch einen Club gründen."),
                                     action: openCreate)
                ClubInvitationAction(kicker: KuroLocale.text("Invite code", "Einladungscode"),
                                     title: KuroLocale.text("Join a club.", "Einem Club beitreten."),
                                     action: openJoin)
            }
            .padding(.top, KuroDesignSpacing.md)
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

// MARK: - Invitation (no clubs yet)

/// The empty state after a successful read: a cover line and two invitation actions (rulebook §7,
/// §14.7). Never shown for a failed or offline read.
private struct ClubsInvitation: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                Text(KuroLocale.text("Clubs", "Clubs"))
                    .kuroKicker()
                    .accessibilityHidden(true)

                Text(KuroLocale.text("Watch together.\nPrivate by design.", "Gemeinsam schauen.\nPrivat von Anfang an."))
                    .font(.kuroDisplay(weight: .light))
                    .tracking(-0.6)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Rectangle()
                    .fill(Color.kuroInk)
                    .frame(width: 40, height: 2)
                    .accessibilityHidden(true)

                Text(KuroLocale.text(
                    "A club is 2 to 20 friends you invite. Nothing in it is public.",
                    "Ein Club sind 2 bis 20 Freunde, die du einlädst. Nichts darin ist öffentlich."
                ))
                .font(.kuroBody(weight: .light))
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                ClubInvitationAction(kicker: KuroLocale.text("Create", "Gründen"),
                                     title: KuroLocale.text("Start a club.", "Einen Club gründen."),
                                     action: onCreate)
                ClubInvitationAction(kicker: KuroLocale.text("Invite code", "Einladungscode"),
                                     title: KuroLocale.text("Join with a code.", "Mit Code beitreten."),
                                     action: onJoin)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Invitation action (rulebook §7): kicker, a serif line, a full ink rule and an arrow. One target of
/// at least 44 pt.
struct ClubInvitationAction: View {
    let kicker: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                Text(kicker)
                    .kuroKicker()
                HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.md) {
                    Text(title)
                        .font(.kuroTitle(weight: .regular))
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.kuroMeta(weight: .regular))
                        .foregroundStyle(Color.kuroInk)
                }
                Rectangle()
                    .fill(Color.kuroInk)
                    .frame(height: 1)
                    .padding(.top, KuroDesignSpacing.xs)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Loading skeleton

/// Stable geometry while the first read is in flight: the card shape in quiet fills, no motion.
private struct ClubsLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                .fill(Color.kuroBlack05)
                .frame(width: 160, height: 26)
                .padding(.bottom, KuroDesignSpacing.sm)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { _ in
                            Color.kuroBlack05
                                .aspectRatio(0.7, contentMode: .fit)
                        }
                    }
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                            .fill(Color.kuroBlack05)
                            .frame(height: 20)
                            .frame(maxWidth: 200)
                        RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                            .fill(Color.kuroBlack05)
                            .frame(height: 12)
                            .frame(maxWidth: 140)
                    }
                    .padding(KuroDesignSpacing.md)
                }
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .strokeBorder(Color.kuroHairline, lineWidth: 1)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading your clubs", "Deine Clubs werden geladen"))
    }
}

// MARK: - Club card

/// One club, inhabited by the real artwork of its latest rail titles.
private struct ClubListCard: View {
    let club: ClubListRow
    let hasUnseen: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var coverURLs: [URL] {
        (club.cover_images ?? []).prefix(4).compactMap(URL.init(string:))
    }

    private var initials: [String] {
        ClubsListCardRules.memberInitials(sharingLevel: club.sharing_level, memberNames: club.member_names)
    }

    private var relativeTime: String? {
        guard let raw = club.last_activity_at, let date = ClubsStore.parseISO8601(raw) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = KuroLocale.locale
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var metaLine: String {
        let german = KuroLocale.isGerman
        var parts = [ClubsListCardRules.audienceLabel(sharingLevel: club.sharing_level, german: german)]
        if let members = ClubsListCardRules.memberCountText(club.member_count, german: german) {
            parts.append(members)
        }
        if let relativeTime { parts.append(relativeTime) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClubArtStrip(urls: coverURLs, monogram: String(club.name.prefix(1)))

            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.sm) {
                    Text(club.name)
                        .font(.kuroHeadline(weight: .light))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hasUnseen {
                        Circle()
                            .fill(Color.kuroInk)
                            .frame(width: 8, height: 8)
                    }
                }

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: KuroDesignSpacing.sm))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: KuroDesignSpacing.sm))
                layout {
                    if !initials.isEmpty {
                        ClubInitialsRow(initials: initials, total: club.member_count)
                    }
                    Text(metaLine)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let line = ClubsListCardRules.recentLine(club.activity_preview, german: KuroLocale.isGerman) {
                    Text(line)
                        .font(.kuroBody(weight: .light))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(KuroDesignSpacing.md)
        }
        .background(Color.kuroCanvasPage)
        .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .strokeBorder(Color.kuroHairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))
    }
}

/// Up to four equal portrait covers on the club's room surface. Empty slots stay room-dark (never
/// another title's art); with no art at all the room shows the club's monogram.
struct ClubArtStrip: View {
    let urls: [URL]
    let monogram: String
    var maxPixelSize: Int = 320

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Color.clear
                    .aspectRatio(0.7, contentMode: .fit)
                    .overlay {
                        if index < urls.count {
                            KuroCachedAsyncImage(url: urls[index], maxPixelSize: maxPixelSize) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    Color.kuroMissingArt
                                }
                            }
                        }
                    }
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.kuroRoom)
        .overlay {
            if urls.isEmpty {
                Text(monogram.uppercased())
                    .font(.kuroDisplay(weight: .light))
                    .foregroundStyle(Color.kuroRoomTextSecondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Member initials as small ink circles (never for private clubs: `ClubsListCardRules`).
struct ClubInitialsRow: View {
    let initials: [String]
    let total: Int?
    var onRoom: Bool = false

    var body: some View {
        let shown = Array(initials.prefix(4))
        let overflow = max(0, (total ?? shown.count) - shown.count)
        HStack(spacing: -6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, initial in
                bubble(Text(initial))
            }
            if overflow > 0 {
                bubble(Text(verbatim: "+\(overflow)"))
            }
        }
        .accessibilityHidden(true)
    }

    private func bubble(_ text: Text) -> some View {
        text
            .font(.kuroCustom(11, weight: .semibold, relativeTo: .caption1, maxSize: 18))
            .foregroundStyle(onRoom ? Color.kuroRoomText : Color.kuroInk)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 2)
            .background(Circle().fill(onRoom ? Color.kuroRoom : Color.kuroCanvasQuiet))
            .overlay(Circle().strokeBorder(onRoom ? Color.kuroRoomTextSecondary : Color.kuroCanvasPage, lineWidth: 1.5))
    }
}

// MARK: - Create Club Sheet

private struct CreateClubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()

    @State private var name = ""
    @State private var description = ""
    @State private var sharingLevel = "status"
    @State private var isSubmitting = false
    @State private var errorText: String? = nil
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, description }

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
                                   title: KuroLocale.text("Start a club.", "Gründe einen Club."))

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
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { dismiss() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            focus = .name
        }
        .onDisappear { actionScope.deactivate(); isSubmitting = false }
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
    @FocusState private var codeFocused: Bool

    let onJoined: (JoinClubResponse) -> Void

    init(initialCode: String = "", onJoined: @escaping (JoinClubResponse) -> Void) {
        _inviteCode = State(initialValue: ClubInviteCode.normalize(initialCode))
        self.onJoined = onJoined
    }

    private var isValid: Bool { ClubInviteCode.isValid(inviteCode) }

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
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { dismiss() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .onAppear {
            actionScope.activate(session: clubs.accountSession)
            if inviteCode.isEmpty { codeFocused = true }
        }
        .onDisappear { actionScope.deactivate(); isSubmitting = false }
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
