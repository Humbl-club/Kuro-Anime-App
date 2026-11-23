import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Club detail tabs
// Discover + Clubs redesign (spec §7.3.1–§7.3.3), on Home's warm paper:
// RAILS: each rail as a block with Home's in-feed sub-heading, its real description and a two-column
// grid of Also-watching tiles (cover, title, your progress, who else, the note link, the live reaction
// row), then "＋ Add a title to {rail}" when the viewer may add. Each note appears once (D11).
// THIS WEEK: the pace glance, Home's page heading, the week in Home's calendar-card grammar (day rows
// with covers, "You" for the viewer), then an "Earlier" fold (D12).
// POLLS: open polls as glance cards (You asked, the deadline, title options with a cover and a
// separate open target, votes and a percentage), the admins' "Ask the club." row, closed polls as
// quiet cards that open their results.
// Nothing here invents club voice: rails without a description show none.

// MARK: - Tab Bar

/// Home's switch rule on the tabs: 15 pt semibold −0.2 words 22 apart over a 1 pt
/// `HomeInk.switchHairline`, a 10 pt `kuroMuted` count after each word (zero omitted), the selected
/// word in ink with the 28 × 2 `switchMark` rule fading in place (never travelling). 44 pt targets.
struct JournalTabBar: View {
    @Binding var selectedTab: ClubDetailView.Tab
    var counts: [ClubDetailView.Tab: Int] = [:]
    var gutter: CGFloat = 20

    var body: some View {
        // Scrolls sideways only when the labels do not fit (largest text sizes, German); a trailing
        // fade then shows there is more.
        ScrollView(.horizontal, showsIndicators: false) {
            tabs
                .padding(.horizontal, gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .kuroTrailingOverflowFade()
        .kuroSwipeExclusionZone()
        .background(Color.kuroCanvasHome)
        .overlay(alignment: .bottom) {
            // Inset to the gutter like Home's switch rule; the pinned background stays full width.
            Rectangle().fill(HomeInk.switchHairline).frame(height: 1)
                .padding(.horizontal, gutter)
        }
    }

    private var tabs: some View {
        let german = KuroLocale.isGerman
        return HStack(spacing: 22) {
            ForEach(ClubDetailView.Tab.visibleCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                let count = counts[tab] ?? 0
                Button {
                    guard !isSelected else { return }
                    KuroAccessibility.selectionHaptic()
                    withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(tab.title)
                            .font(.kuroCustom(15, weight: .semibold, relativeTo: .subheadline, maxSize: 30))
                            .tracking(-0.2)
                            .foregroundStyle(isSelected ? Color.kuroInk : HomeInk.switchUnselected)
                        if count > 0 {
                            Text(verbatim: "\(count)")
                                .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                                .foregroundStyle(Color.kuroMuted)
                        }
                    }
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottomLeading) {
                        Rectangle()
                            .fill(HomeInk.switchMark)
                            .frame(width: 28, height: 2)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel(count > 0 ? "\(tab.title), \(tab.countLabel(count, german: german))" : tab.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - Shared tab parts

/// A tab's empty state with an optional invitation action (owners/admins).
private struct ClubTabEmptyState: View {
    let title: String
    let message: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var gutter: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            KuroStateView(.empty, title: title, message: message, layout: .inline)
            if let actionTitle, let action {
                KuroInkButton(actionTitle, role: .secondary, action: action)
            }
        }
        .padding(.horizontal, gutter)
        .padding(.top, KuroDesignSpacing.lg)
        .padding(.bottom, KuroDesignSpacing.xxl)
    }
}

/// A plain text action on paper: "＋ Add a title to Sunday watch", 13 pt medium, 44 pt target.
private struct ClubTextAction: View {
    let title: String
    var systemImage: String? = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.kuroCustom(12, weight: .medium, relativeTo: .footnote, maxSize: 22))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.kuroInk)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(title)
    }
}

/// Card metrics from the container (CLAUDE.md card sizing): never a hard-coded screen width.
nonisolated enum ClubRailCardMetrics {
    static func width(containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return 120 }
        return min(144, max(112, floor((containerWidth - 56) / 2.8)))
    }

    static func height(width: CGFloat) -> CGFloat {
        (width * 1.5).rounded()
    }
}

// MARK: - Rails Content

struct JournalRailsContent: View {
    let bundle: ClubBundle
    let containerWidth: CGFloat
    let showSharedAvailability: Bool
    let sharedProviders: ProviderAvailabilityStore.ClubSharedProvidersResponse?
    let isAvailableOnSharedServices: (Int, String) -> Bool
    let onToggleShared: () -> Void
    let onCreateRail: () -> Void
    let onAddToRail: (String) -> Void
    let onError: (String) -> Void
    let canAddToRail: (ClubRail, String) -> Bool
    let userStreamingServicesEmpty: Bool
    let isConnected: Bool
    var viewerId: String? = nil
    var gutter: CGFloat = 20
    var compact: Bool = false
    /// "{name}'s note ↑": scrolls to the hero's note card.
    var onScrollToNote: (() -> Void)? = nil
    @Environment(FeatureFlags.self) private var flags

    private var isAdmin: Bool { ClubRoomRules.isAdmin(role: bundle.my_role) }

    var body: some View {
        if bundle.rails.isEmpty {
            ClubTabEmptyState(
                title: KuroLocale.text("No rails yet.", "Noch keine Listen."),
                message: isAdmin
                    ? KuroLocale.text("Start a shared list for the club.", "Lege eine gemeinsame Liste für den Club an.")
                    : KuroLocale.text("Rails appear when an admin starts one.", "Listen erscheinen, sobald ein Admin eine anlegt."),
                actionTitle: isAdmin ? KuroLocale.text("Create a rail", "Liste anlegen") : nil,
                action: isAdmin ? {
                    KuroAccessibility.impactHaptic(.light)
                    onCreateRail()
                } : nil,
                gutter: gutter
            )
            .disabled(!isConnected)
        } else {
            let firstNoteItemId = ClubRoomCopy.firstNote(in: bundle)?.itemId
            VStack(alignment: .leading, spacing: 0) {
                streamingAvailabilityControls

                if flags.isClubsPaceSyncV1Enabled {
                    let milestones = bundle.rails.flatMap { rail in
                        rail.items.compactMap { item -> ClubRailItem? in
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
                                JournalMilestoneCard(item: item, memberCount: bundle.member_count)
                            }
                        }
                        .padding(.horizontal, gutter)
                        .padding(.top, KuroDesignSpacing.md)
                    }
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(bundle.rails.enumerated()), id: \.element.id) { index, rail in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.kuroHairline)
                                .frame(height: 0.5)
                                .padding(.horizontal, gutter)
                                .padding(.top, 16)
                        }

                        JournalRailSection(
                            rail: rail,
                            members: bundle.members,
                            containerWidth: containerWidth,
                            onAddItem: canAddToRail(rail, bundle.my_role) && isConnected ? {
                                onAddToRail(rail.id)
                            } : nil,
                            onError: onError,
                            itemOpacity: showSharedAvailability ? { item in
                                isAvailableOnSharedServices(item.media_id, item.media_type) ? 1.0 : 0.35
                            } : nil,
                            viewerId: viewerId,
                            firstNoteItemId: firstNoteItemId,
                            gutter: gutter,
                            compact: compact,
                            onScrollToNote: onScrollToNote
                        )
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
        }
    }

    @ViewBuilder
    private var streamingAvailabilityControls: some View {
        if flags.isStreamingAvailabilityV1Enabled, let sp = sharedProviders {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                if !sp.shared_services.isEmpty {
                    Button(action: onToggleShared) {
                        HStack(spacing: KuroDesignSpacing.sm) {
                            Image(systemName: showSharedAvailability ? "checkmark.square" : "square")
                                .font(.kuroMeta())
                            Text(KuroLocale.text("Only titles on our services", "Nur Titel bei unseren Diensten"))
                                .font(.kuroMeta(weight: .medium))
                        }
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KuroPressStyle())
                    .accessibilityAddTraits(showSharedAvailability ? [.isButton, .isSelected] : .isButton)
                }
                if sp.coverage_pct < 100 && sp.member_count_with_services > 0 {
                    Text(KuroLocale.text(
                        "\(sp.member_count_with_services) of \(sp.member_count_total) members set their services.",
                        "\(sp.member_count_with_services) von \(sp.member_count_total) Mitgliedern haben ihre Dienste angegeben."
                    ))
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroMuted)
                }
                if userStreamingServicesEmpty {
                    Text(KuroLocale.text("Set your services in Profile to compare.", "Gib deine Dienste im Profil an, um zu vergleichen."))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroMuted)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, KuroDesignSpacing.sm)
        }
    }
}

// MARK: - Rail Section

struct JournalRailSection: View {
    let rail: ClubRail
    let members: [ClubMember]
    let containerWidth: CGFloat
    var onAddItem: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil
    var itemOpacity: ((ClubRailItem) -> Double)? = nil
    var viewerId: String? = nil
    var firstNoteItemId: String? = nil
    var gutter: CGFloat = 20
    var compact: Bool = false
    var onScrollToNote: (() -> Void)? = nil
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleWidth: CGFloat = 0
    @State private var openNoteItemId: String? = nil
    @State private var revealedSpoilerIds: Set<String> = []

    var body: some View {
        let german = KuroLocale.isGerman
        let notes = ClubRoomCopy.notes(in: rail, members: members)
        let effectiveWidth = min(containerWidth > 0 ? containerWidth : 390, KuroReadableWidth.maxWidth)
        let cardWidth = ClubRailCardMetrics.width(containerWidth: effectiveWidth)
        let coverHeight = ClubRailCardMetrics.height(width: cardWidth)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                ClubSubHeading(title: rail.title,
                               count: ClubRoomCopy.titleCount(rail.items.count, german: german)
                                   + (rail.is_locked ? ClubRoomCopy.locked(german: german) : ""))
                if let onAddItem, !rail.items.isEmpty {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onAddItem()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(KuroLocale.text("Add", "Titel"))
                                .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 20))
                        }
                        .foregroundStyle(Color.kuroInk)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.76), in: Capsule())
                        .overlay(Capsule().strokeBorder(HomeInk.quietBorder, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .fixedSize()
                    .accessibilityLabel(ClubRoomCopy.addToRail(rail.title, german: german))
                }
            }

            if let desc = rail.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                Text(desc)
                    .font(.kuroCustom(11, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if rail.items.isEmpty {
                HomeQuietCard(text: KuroLocale.text("Nothing here yet.", "Hier ist noch nichts."))
                    .padding(.top, 12)
                if let onAddItem {
                    ClubTextAction(title: ClubRoomCopy.addToRail(rail.title, german: german)) {
                        KuroAccessibility.impactHaptic(.light)
                        onAddItem()
                    }
                    .padding(.top, 6)
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(rail.items) { item in
                        JournalRailTile(
                            item: item,
                            note: notes.first { $0.itemId == item.id },
                            placement: ClubRoomRules.notePlacement(itemId: item.id, note: item.note, firstNoteItemId: firstNoteItemId),
                            viewerId: viewerId,
                            members: members,
                            showsReactions: flags.isClubsReactionsV1Enabled,
                            cardWidth: nil,
                            coverHeight: nil,
                            isNoteOpen: openNoteItemId == item.id,
                            onToggleNote: { toggleNote(for: item.id) },
                            onError: onError,
                            onScrollToNote: onScrollToNote
                        )
                        .opacity(itemOpacity?(item) ?? 1.0)
                        .kuroAnimation(KuroMotion.settle, value: itemOpacity?(item) ?? 1.0)
                    }
                }
                .padding(.top, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: KuroRailPeek.spacing) {
                        ForEach(rail.items) { item in
                            JournalRailTile(
                                item: item,
                                note: notes.first { $0.itemId == item.id },
                                placement: ClubRoomRules.notePlacement(itemId: item.id, note: item.note, firstNoteItemId: firstNoteItemId),
                                viewerId: viewerId,
                                members: members,
                                showsReactions: flags.isClubsReactionsV1Enabled,
                                cardWidth: cardWidth,
                                coverHeight: coverHeight,
                                isNoteOpen: openNoteItemId == item.id,
                                onToggleNote: { toggleNote(for: item.id) },
                                onError: onError,
                                onScrollToNote: onScrollToNote
                            )
                            .opacity(itemOpacity?(item) ?? 1.0)
                            .kuroAnimation(KuroMotion.settle, value: itemOpacity?(item) ?? 1.0)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                }
                .scrollClipDisabled()
                .detailRailBleed(visible: $visibleWidth, gutter: gutter)
                .kuroSwipeExclusionZone()
                .padding(.top, 10)

                if let openId = openNoteItemId,
                   let activeItem = rail.items.first(where: { $0.id == openId }),
                   ClubRoomRules.notePlacement(itemId: activeItem.id, note: activeItem.note, firstNoteItemId: firstNoteItemId) == .inline,
                   let activeNote = notes.first(where: { $0.itemId == openId }),
                   !activeNote.text.isEmpty {
                    expandedNoteCard(item: activeItem, note: activeNote, text: activeNote.text, german: german)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, gutter)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func toggleNote(for itemId: String) {
        withAnimation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.settle : nil) {
            openNoteItemId = (openNoteItemId == itemId) ? nil : itemId
        }
    }

    private func expandedNoteCard(item: ClubRailItem, note: ClubRoomCopy.Note, text: String, german: Bool) -> some View {
        let parsed = ClubSpoilerGate.parse(
            note: text,
            serverIsSpoiler: item.is_spoiler,
            serverThroughUnit: item.spoiler_through_unit
        )
        let mask = revealedSpoilerIds.contains(item.id)
            ? nil
            : ClubSpoilerGate.maskReason(
                item: item,
                viewerStatus: item.my_status,
                viewerProgress: item.my_progress,
                german: german
            )
        let displayedText = parsed.cleanText.isEmpty ? text : parsed.cleanText

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(item.title_display) · \(note.author ?? KuroLocale.text("Member note", "Mitgliedsnotiz"))")
                    .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 18))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(HomeInk.kicker)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    toggleNote(for: item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.kuroMuted)
                        .frame(width: 44, height: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KuroLocale.text("Close note", "Notiz schließen"))
            }
            if let mask {
                JournalSpoilerNoteMask(reason: mask, compactFont: 11) {
                    KuroAccessibility.impactHaptic(.light)
                    withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
                        _ = revealedSpoilerIds.insert(item.id)
                    }
                }
            } else {
                Text(KuroLocale.text("“\(displayedText)”", "„\(displayedText)“"))
                    .font(.kuroEditorial(size: 16))
                    .tracking(-0.2)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(HomeInk.quietBorder, lineWidth: 1))
    }
}

// MARK: - Rail tile (Poster rail card / AX vertical row)

/// One rail title: sharp 2 : 3 poster cover (`cardWidth × coverHeight`), reserved 2-line title,
/// viewer's own progress ("You · Ep. 7 of 24"), who else, the note link (D11), and reactions.
struct JournalRailTile: View {
    let item: ClubRailItem
    let note: ClubRoomCopy.Note?
    let placement: ClubRoomRules.NotePlacement
    let viewerId: String?
    let members: [ClubMember]
    let showsReactions: Bool
    var cardWidth: CGFloat? = nil
    var coverHeight: CGFloat? = nil
    var isNoteOpen: Bool = false
    var onToggleNote: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil
    var onScrollToNote: (() -> Void)? = nil

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var german: Bool { KuroLocale.isGerman }
    private var mediaKind: MediaKind { item.media_type.uppercased() == "MANGA" ? .manga : .anime }
    private var libraryKey: MediaKey { MediaKey(kind: mediaKind, id: item.media_id) }
    private var isInCollection: Bool { library.isTracked(libraryKey) }

    private var progressText: String? {
        ClubRoomCopy.viewerProgress(item.my_progress, total: item.totalCount, isManga: mediaKind == .manga, german: german)
    }

    /// Who else: the members currently on it (the viewer excluded), else who added it.
    private var othersText: String? {
        let current = (item.member_statuses ?? []).filter { status in
            guard !ClubRoomRules.isViewer(status.user_id, viewerId: viewerId) else { return false }
            let st = status.status?.uppercased() ?? ""
            return st == "CURRENT" || st == "WATCHING" || st == "READING"
        }
        if let line = ClubRoomCopy.membersCurrent(names: current.map(\.display_name), isManga: mediaKind == .manga, german: german) {
            return line
        }
        guard let addedBy = item.added_by, !ClubRoomRules.isViewer(addedBy, viewerId: viewerId),
              let name = members.first(where: { $0.user_id == addedBy })?.display_name?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return ClubRoomCopy.addedBy(name, german: german)
    }

    private var accessibilityText: String {
        [item.title_display, progressText, othersText].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        Group {
            if let cardWidth, let coverHeight {
                posterCard(width: cardWidth, height: coverHeight, origin: origin)
            } else {
                verticalRow(origin: origin)
            }
        }
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate() }
    }

    private func posterCard(width: CGFloat, height: CGFloat, origin: AccountActionScope.Ticket?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open(origin: origin)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    cover(width: width, height: height)
                    Text(item.title_display)
                        .font(.kuroCustom(12.5, weight: .medium, relativeTo: .footnote, maxSize: 26))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    if let progressText {
                        Text(progressText)
                            .font(.kuroCustom(10, weight: .medium, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(1)
                            .padding(.top, 3)
                    } else if let othersText {
                        Text(othersText)
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(HomeInk.tileUnit)
                            .lineLimit(1)
                            .padding(.top, 3)
                    }
                    if progressText != nil, let othersText {
                        Text(othersText)
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(HomeInk.tileUnit)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }
                .frame(width: width, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeArtworkPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(KuroLocale.text("Opens the title.", "Öffnet den Titel."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(origin: origin) }
            .contextMenu { cardContextMenu }

            if placement != .none || showsReactions {
                VStack(alignment: .leading, spacing: 2) {
                    noteLink(inlineTextExpanded: false)
                    if showsReactions {
                        ClubReactionMenu(item: item, onError: onError)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func verticalRow(origin: AccountActionScope.Ticket?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                open(origin: origin)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    cover(width: 60, height: 90)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title_display)
                            .font(.kuroCustom(14, weight: .medium, relativeTo: .subheadline, maxSize: 28))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let progressText {
                            Text(progressText)
                                .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                                .foregroundStyle(Color.kuroInk)
                        }
                        if let othersText {
                            Text(othersText)
                                .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 22))
                                .foregroundStyle(HomeInk.tileUnit)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeArtworkPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(KuroLocale.text("Opens the title.", "Öffnet den Titel."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(origin: origin) }
            .contextMenu { cardContextMenu }

            noteLink(inlineTextExpanded: true)
            if showsReactions {
                ClubReactionMenu(item: item, onError: onError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        Button(action: {
            guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
            KuroAccessibility.impactHaptic(.light)
            LibraryViewActions.toggleTracked(libraryKey, actions: libraryActions)
        }) {
            Label(
                isInCollection
                    ? KuroLocale.text("Remove from list", "Von der Liste entfernen")
                    : (mediaKind == .manga ? KuroLocale.text("Plan to read", "Vormerken") : KuroLocale.text("Plan to watch", "Vormerken")),
                systemImage: isInCollection ? "minus.circle" : "plus.circle"
            )
        }
    }

    private func open(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        guard !suppressCardTaps else { return }
        KuroAccessibility.impactHaptic(.light)
        routes.openMedia(MediaRoute(libraryKey))
    }

    private func cover(width: CGFloat, height: CGFloat) -> some View {
        let kindWord = mediaKind == .manga ? "Manga" : "Anime"
        return Color.clear
            .frame(width: width, height: height)
            .overlay {
                if let raw = item.cover_image_medium, let url = URL(string: raw), !raw.isEmpty {
                    KuroCachedAsyncImage(url: url, maxPixelSize: 360) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { KuroBrandedTile(kind: kindWord, title: item.title_display, cornerRadius: 5) }
                    }
                } else {
                    KuroBrandedTile(kind: kindWord, title: item.title_display, cornerRadius: 5)
                }
            }
            .background(HomeInk.posterFill)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: Color(hex: "222222", opacity: Double(0x18) / 255), radius: 2, y: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func noteLink(inlineTextExpanded: Bool) -> some View {
        switch placement {
        case .none:
            EmptyView()
        case .linkToHero:
            Button {
                KuroAccessibility.impactHaptic(.light)
                onScrollToNote?()
            } label: {
                Text(ClubRoomCopy.noteLinkUp(author: note?.author, german: german))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(Color.kuroInk)
                    .underline(color: Color.kuroInk.opacity(0.25))
                    .frame(minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityHint(KuroLocale.text("Shows the note at the top of the club.", "Zeigt die Notiz oben im Club."))
        case .inline:
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onToggleNote?()
                } label: {
                    let chevron = Text(Image(systemName: isNoteOpen ? "chevron.up" : "chevron.down"))
                        .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 14))
                    let words = Text(ClubRoomCopy.noteInline(author: note?.author, german: german))
                        .underline(color: Color.kuroInk.opacity(0.25))
                    Text("\(words)\u{00A0}\(chevron)")
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .lineLimit(inlineTextExpanded ? 3 : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel(isNoteOpen
                    ? ClubRoomCopy.noteInline(author: note?.author, german: german)
                    : KuroLocale.text("Note by \(note?.author ?? "a member"), may contain spoilers. Double tap to read.",
                                      "Notiz von \(note?.author ?? "einem Mitglied"), kann spoilern. Zum Lesen doppeltippen."))
                .accessibilityValue(KuroFold.accessibilityValue(expanded: isNoteOpen, german: german))
                if inlineTextExpanded, isNoteOpen, let text = note?.text {
                    JournalInlineSpoilerNote(item: item, rawText: text, german: german)
                }
            }
            .id(note?.text ?? "")
        }
    }
}

// MARK: - Milestone Card

struct JournalMilestoneCard: View {
    let item: ClubRailItem
    let memberCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(KuroLocale.text("Finished together", "Gemeinsam beendet"))
                .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(HomeInk.kicker)
            Text(KuroLocale.text("All \(memberCount) members finished \(item.title_display).",
                                 "Alle \(memberCount) Mitglieder haben \(item.title_display) beendet."))
                .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HomeInk.quietBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct JournalSpoilerNoteMask: View {
    let reason: String
    let compactFont: CGFloat
    let onReveal: () -> Void

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.kuroMuted)
                Text(reason)
                    .font(.kuroCustom(compactFont, weight: .medium, relativeTo: .caption1, maxSize: 20))
                    .foregroundStyle(Color.kuroInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(Color.black.opacity(0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(HomeInk.quietBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct JournalInlineSpoilerNote: View {
    let item: ClubRailItem
    let rawText: String
    let german: Bool
    @State private var revealed = false

    var body: some View {
        let parsed = ClubSpoilerGate.parse(
            note: rawText,
            serverIsSpoiler: item.is_spoiler,
            serverThroughUnit: item.spoiler_through_unit
        )
        let mask = revealed
            ? nil
            : ClubSpoilerGate.maskReason(
                item: item,
                viewerStatus: item.my_status,
                viewerProgress: item.my_progress,
                german: german
            )
        let displayedText = parsed.cleanText.isEmpty ? rawText : parsed.cleanText

        if let mask {
            JournalSpoilerNoteMask(reason: mask, compactFont: 11) {
                KuroAccessibility.impactHaptic(.light)
                withAnimation(KuroMotion.resolve(KuroMotion.settle)) {
                    revealed = true
                }
            }
        } else {
            Text(KuroLocale.text("“\(displayedText)”", "„\(displayedText)“"))
                .font(.kuroEditorial(size: 15))
                .tracking(-0.2)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }
}

// MARK: - This week (spec §7.3.2, D12)

struct JournalActivityContent: View {
    let bundle: ClubBundle
    var viewerId: String? = nil
    var now: Date = Date()
    var gutter: CGFloat = 20
    var compact: Bool = false
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.kuroRoutes) private var routes
    @State private var earlierOpen = false

    private var german: Bool { KuroLocale.isGerman }

    /// Items the viewer is behind on (the existing pace rule), with the gap and their rail.
    private var paceItems: [(item: ClubRailItem, rail: ClubRail, gap: ClubPaceRules.Gap)] {
        guard ClubPaceRules.applies(sharingLevel: bundle.club.sharing_level, memberCount: bundle.member_count,
                                    enabled: flags.isClubsPaceSyncV1Enabled) else { return [] }
        return bundle.rails.flatMap { rail in
            rail.items.compactMap { item in ClubPaceRules.gap(item).map { (item, rail, $0) } }
        }
    }

    var body: some View {
        let entries = ClubWeekRules.entries(in: bundle, viewerId: viewerId)
        let split = ClubWeekRules.partition(entries, now: now)
        let since = ClubWeekRules.windowStart(now: now)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(paceItems, id: \.item.id) { pace in
                paceGlance(pace.item, rail: pace.rail, gap: pace.gap)
                    .padding(.bottom, 12)
            }

            if entries.isEmpty {
                ClubPageHeading(title: ClubWeekCopy.heading(german: german), compact: compact)
                    .padding(.bottom, 17)
                // Duo clubs: the bundle withholds member_statuses below 3 members (k>=3 rule).
                HomeQuietCard(text: bundle.member_count < 3
                    ? KuroLocale.text("Activity shows from 3 members. Invite one more friend.",
                                      "Aktivität erscheint ab 3 Mitgliedern. Lade noch jemanden ein.")
                    : KuroLocale.text("Updates appear here as members watch and read.",
                                      "Hier erscheint, was Mitglieder schauen und lesen."))
            } else {
                ClubPageHeading(title: ClubWeekCopy.heading(german: german),
                                summary: split.thisWeekCount > 0
                                    ? ClubWeekCopy.summary(count: split.thisWeekCount, since: since, german: german)
                                    : ClubWeekCopy.since(since, german: german),
                                compact: compact)
                    .padding(.bottom, 17)

                if split.thisWeek.isEmpty {
                    HomeQuietCard(text: ClubWeekCopy.quietWeek(since: since, german: german))
                } else {
                    ClubWeekCard(days: split.thisWeek, undated: [], now: now, openFirst: true)
                }

                if split.earlierCount > 0 {
                    earlierFold(count: split.earlierCount)
                        .padding(.top, 12)
                    if earlierOpen {
                        ClubWeekCard(days: split.earlier, undated: split.undated, now: now, openFirst: false)
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(KuroLocale.text("Shared stories. Your people.", "Geteilte Geschichten. Deine Leute."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("KURO")
                    .fontWeight(.bold)
                    .tracking(2)
                    .accessibilityHidden(true)
            }
            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
            .foregroundStyle(Color.kuroMuted)
            .padding(.vertical, 28)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, gutter)
        .padding(.top, 16)
        .padding(.bottom, KuroDesignSpacing.lg)
    }

    // MARK: Pace glance (Home's glance-card grammar)

    private func paceGlance(_ item: ClubRailItem, rail: ClubRail, gap: ClubPaceRules.Gap) -> some View {
        let isManga = item.media_type.uppercased() == "MANGA"
        return Button {
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(ClubActivityTarget.key(mediaType: item.media_type, mediaId: item.media_id)))
        } label: {
            HStack(alignment: .center, spacing: compact ? 8 : 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ClubPaceRules.title(gap, isManga: isManga, german: german))
                        .font(.kuroCustom(14, weight: .semibold, relativeTo: .subheadline, maxSize: 28))
                        .tracking(-0.3)
                        .foregroundStyle(HomeInk.glanceInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ClubPaceRules.caption(gap, rail: rail.title, title: item.title_display, isManga: isManga, german: german))
                        .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
                        .foregroundStyle(HomeInk.glanceMuted)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: "\(gap.behind)")
                        .font(.kuroCustom(21, relativeTo: .title3, maxSize: 36).monospacedDigit())
                        .tracking(-0.6)
                        .foregroundStyle(HomeInk.glanceInk)
                    Text(ClubPaceRules.countLabel(german: german))
                        .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 16))
                        .foregroundStyle(HomeInk.glanceMuted)
                }
                .frame(minWidth: 39, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 20))
                    .foregroundStyle(HomeInk.glanceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(minHeight: 72)
            .background(HomeInk.glanceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
            .shadow(color: HomeInk.glanceShadow, radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(KuroLocale.text("Opens the title.", "Öffnet den Titel."))
    }

    // MARK: Earlier fold (Home's "Show N more" pill)

    private func earlierFold(count: Int) -> some View {
        KuroFoldButton(isExpanded: $earlierOpen,
                       expandLabel: ClubWeekCopy.earlier(german: german) + ", " + ClubWeekCopy.showOlder(count, german: german),
                       collapseLabel: ClubWeekCopy.earlier(german: german) + ", " + ClubWeekCopy.hideOlder(german: german)) { _, expanded in
            HStack(spacing: 8) {
                Text(ClubWeekCopy.earlier(german: german))
                    .font(.kuroCustom(12, weight: .semibold, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroInk)
                Spacer(minLength: 8)
                Text(expanded ? ClubWeekCopy.hideOlder(german: german) : ClubWeekCopy.showOlder(count, german: german))
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                    .foregroundStyle(Color(hex: "68736A"))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 16))
                    .foregroundStyle(Color(hex: "68736A"))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(hex: "F6F8F4"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: "D9E0D7"), lineWidth: 1))
        }
    }
}

// MARK: - This week entries

/// Where a "This week" entry leads (pure, NavclubsTests): its title, by the rail item's media type
/// ("MANGA" in any case is manga; anything else is anime, as the rail cards read it).
nonisolated enum ClubActivityTarget {
    static func key(mediaType: String, mediaId: Int) -> MediaKey {
        MediaKey(kind: mediaType.uppercased() == "MANGA" ? .manga : .anime, id: mediaId)
    }
}


// MARK: - Polls Content (spec §7.3.3)

struct JournalPollsContent: View {
    let bundle: ClubBundle
    let clubsInteractionV2Enabled: Bool
    let voteInFlightPollIds: Set<String>
    let optimisticVoteByPollId: [String: String]
    let optimisticVoteCountsByPollId: [String: [String: Int]]
    let onVote: (ClubPoll, String) -> Void
    let onCreatePoll: () -> Void
    let isConnected: Bool
    var viewerId: String? = nil
    var gutter: CGFloat = 20

    @State private var openClosedPollIds: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var german: Bool { KuroLocale.isGerman }
    private var isAdmin: Bool { ClubRoomRules.isAdmin(role: bundle.my_role) }
    private var openPolls: [ClubPoll] { bundle.polls.filter { !$0.is_closed } }
    private var closedPolls: [ClubPoll] { bundle.polls.filter { $0.is_closed } }

    var body: some View {
        if bundle.polls.isEmpty {
            ClubTabEmptyState(
                title: KuroLocale.text("No polls yet.", "Noch keine Umfragen."),
                message: isAdmin
                    ? KuroLocale.text("Ask the club what to watch or read next.", "Frag den Club, was ihr als Nächstes schaut oder lest.")
                    : KuroLocale.text("Polls appear here when an admin asks one.", "Umfragen erscheinen hier, sobald ein Admin eine startet."),
                actionTitle: isAdmin ? KuroLocale.text("Ask a question", "Eine Frage stellen") : nil,
                action: isAdmin ? {
                    KuroAccessibility.impactHaptic(.light)
                    onCreatePoll()
                } : nil,
                gutter: gutter
            )
            .disabled(!isConnected)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(openPolls) { poll in
                    JournalPollCard(
                        poll: poll,
                        bundle: bundle,
                        viewerId: viewerId,
                        isSubmittingVote: clubsInteractionV2Enabled && voteInFlightPollIds.contains(poll.id),
                        optimisticMyVoteOptionId: clubsInteractionV2Enabled ? optimisticVoteByPollId[poll.id] : nil,
                        optimisticVoteCounts: clubsInteractionV2Enabled ? optimisticVoteCountsByPollId[poll.id] : nil,
                        onVote: { optionId in onVote(poll, optionId) }
                    )
                }

                if isAdmin {
                    ClubLinkRow(kicker: ClubPollCopy.askLinkKicker(german: german),
                                title: ClubPollCopy.askLinkTitle(german: german),
                                action: onCreatePoll)
                        .disabled(!isConnected)
                        .opacity(isConnected ? 1 : 0.45)
                        .padding(.top, 10)
                }

                if !closedPolls.isEmpty {
                    ClubSubHeading(title: KuroLocale.text("Closed", "Geschlossen"), count: "\(closedPolls.count)")
                        .padding(.top, 18)
                    ForEach(closedPolls) { poll in
                        closedPoll(poll)
                    }
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, 16)
            .padding(.bottom, KuroDesignSpacing.xxl)
        }
    }

    private func askerName(_ poll: ClubPoll) -> String? {
        bundle.members.first { $0.user_id == poll.created_by }?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A closed poll as a quiet card; tapping opens its results inline (read only).
    @ViewBuilder
    private func closedPoll(_ poll: ClubPoll) -> some View {
        let isOpen = openClosedPollIds.contains(poll.id)
        let summary = ClubPollCopy.closedSummary(askerName: askerName(poll),
                                                 isViewer: ClubRoomRules.isViewer(poll.created_by, viewerId: viewerId),
                                                 question: poll.question, options: poll.options, german: german)
        Button {
            KuroAccessibility.selectionHaptic()
            withAnimation(KuroFold.animation(reduceMotion: reduceMotion)) {
                if isOpen { openClosedPollIds.remove(poll.id) } else { openClosedPollIds.insert(poll.id) }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary)
                    .font(.kuroCustom(11, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 16))
                    .foregroundStyle(Color.kuroMuted)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HomeInk.quietBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityValue(KuroFold.accessibilityValue(expanded: isOpen, german: german))
        if isOpen {
            JournalPollCard(poll: poll, bundle: bundle, viewerId: viewerId, isSubmittingVote: false,
                            optimisticMyVoteOptionId: nil, optimisticVoteCounts: nil, onVote: { _ in })
                .transition(.opacity)
        }
    }
}

// MARK: - Poll Card (glance-card grammar)

struct JournalPollCard: View {
    let poll: ClubPoll
    let bundle: ClubBundle
    let viewerId: String?
    let isSubmittingVote: Bool
    let optimisticMyVoteOptionId: String?
    let optimisticVoteCounts: [String: Int]?
    let onVote: (String) -> Void

    private var german: Bool { KuroLocale.isGerman }

    private var totalVotes: Int {
        if let optimisticVoteCounts { return optimisticVoteCounts.values.reduce(0, +) }
        return poll.options.reduce(0) { $0 + $1.vote_count }
    }

    private var myVoteId: String? { optimisticMyVoteOptionId ?? poll.my_vote_option_id }
    private var hasVoted: Bool { myVoteId != nil }

    private var kicker: String? {
        let name = bundle.members.first { $0.user_id == poll.created_by }?.display_name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ClubPollCopy.kicker(askerName: name, isViewer: ClubRoomRules.isViewer(poll.created_by, viewerId: viewerId),
                                   closesAt: poll.is_closed ? nil : poll.closes_at.flatMap(ClubDates.parse), german: german)
    }

    /// The rail item for a title option (its cover and its route); nil for a plain option.
    private func railItem(for option: ClubPollOption) -> ClubRailItem? {
        guard let type = option.media_type, let id = option.media_id else { return nil }
        return bundle.rails.lazy.flatMap(\.items).first { $0.media_id == id && $0.media_type.uppercased() == type.uppercased() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let kicker {
                    Text(kicker)
                        .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                        .tracking(1.05)
                        .textCase(.uppercase)
                        .foregroundStyle(HomeInk.kicker)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if totalVotes > 0 {
                    Text(ClubPollCopy.votes(totalVotes, german: german))
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(HomeInk.glanceMuted)
                }
            }
            Text(poll.question)
                .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 34))
                .tracking(-0.35)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, kicker == nil ? 0 : 4)
                .padding(.bottom, 8)

            ForEach(poll.options) { option in
                let count = optimisticVoteCounts?[option.id] ?? option.vote_count
                JournalPollOptionRow(
                    option: option,
                    railItem: railItem(for: option),
                    displayVoteCount: count,
                    totalVotes: totalVotes,
                    isMyVote: myVoteId == option.id,
                    showsResults: hasVoted || poll.is_closed,
                    isClosed: poll.is_closed,
                    isSubmittingVote: isSubmittingVote,
                    onVote: {
                        guard !poll.is_closed else { return }
                        guard myVoteId != option.id else { return }
                        guard !isSubmittingVote else { return }
                        onVote(option.id)
                    }
                )
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeInk.glanceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
        .shadow(color: HomeInk.glanceShadow, radius: 1, y: 1)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Poll Option Row

/// One option: a 27 × 38 cover when the option is a title in the club's rails (else the same indent),
/// the label ("{label} ›" is its own button that opens the title), the votes and percentage once
/// results show (after voting or when closed, as before), a 3 pt bar, and a separate 44 pt vote target.
struct JournalPollOptionRow: View {
    let option: ClubPollOption
    let railItem: ClubRailItem?
    let displayVoteCount: Int
    let totalVotes: Int
    let isMyVote: Bool
    let showsResults: Bool
    let isClosed: Bool
    let isSubmittingVote: Bool
    let onVote: () -> Void

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var german: Bool { KuroLocale.isGerman }

    private var fraction: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(displayVoteCount) / Double(totalVotes)
    }

    private var percentageText: String {
        guard totalVotes > 0 else { return "" }
        return fraction.formatted(.percent.precision(.fractionLength(0)).locale(KuroLocale.locale))
    }

    private var votesLine: String {
        ClubPollCopy.votes(displayVoteCount, german: german) + (isMyVote ? ClubPollCopy.yours(german: german) : "")
    }

    private var titleKey: MediaKey? {
        guard let type = option.media_type, let id = option.media_id else { return nil }
        return ClubActivityTarget.key(mediaType: type, mediaId: id)
    }

    private var voteAccessibility: String {
        var parts = [KuroLocale.text("Vote for \(option.label)", "Für \(option.label) stimmen")]
        if showsResults {
            parts.append(ClubPollCopy.votes(displayVoteCount, german: german))
            if totalVotes > 0 { parts.append(percentageText) }
        }
        if isMyVote { parts.append(KuroLocale.text("your vote", "deine Stimme")) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let railItem {
                    HomeCalendarArt(raw: railItem.cover_image_medium)
                        .frame(width: ClubRoomLayout.thumb.width, height: ClubRoomLayout.thumb.height)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                } else {
                    Color.clear.frame(width: ClubRoomLayout.thumb.width, height: 1)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsResults, totalVotes > 0 {
                        Text(percentageText)
                            .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 24).monospacedDigit())
                            .foregroundStyle(Color.kuroInk)
                            .accessibilityHidden(true)
                    }
                }
                if showsResults {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: "E3E7E1")).frame(height: 3)
                            Capsule()
                                .fill(isMyVote ? Color.kuroInk : Color.kuroMuted)
                                .frame(width: geo.size.width * fraction, height: 3)
                        }
                    }
                    .frame(height: 3)
                    .kuroAnimation(KuroMotion.settle, value: fraction)
                    .accessibilityHidden(true)
                    Text(votesLine)
                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                        .foregroundStyle(HomeInk.glanceMuted)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onVote) {
                ZStack {
                    Circle()
                        .strokeBorder(isMyVote ? Color.kuroInk : Color(hex: "9AA19A"), lineWidth: 1.2)
                        .background(Circle().fill(isMyVote ? Color.kuroInk : Color.clear))
                    if isMyVote {
                        Image(systemName: "checkmark")
                            .font(.kuroCustom(10, weight: .semibold, relativeTo: .caption2, maxSize: 16))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .disabled(isClosed || isSubmittingVote)
            .accessibilityLabel(voteAccessibility)
            .accessibilityAddTraits(isMyVote ? [.isButton, .isSelected] : .isButton)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 58)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: "E3E7E1")).frame(height: 1) }
    }

    @ViewBuilder
    private var label: some View {
        let text = Text(option.label)
            .font(.kuroCustom(13, weight: isMyVote ? .semibold : .medium, relativeTo: .footnote, maxSize: 26))
            .foregroundStyle(Color.kuroInk)
        if let titleKey {
            Button {
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(titleKey))
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    text.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text("›")
                        .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 26))
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel(KuroLocale.text("Open \(option.label)", "\(option.label) öffnen"))
        } else {
            text
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Reactions

/// A title's reactions as one 44 pt control: a quiet summary of the counts (ink SF Symbols, no
/// emoji) that opens a menu to add or remove your reaction. Optimistic; reverted on failure.
struct ClubReactionMenu: View {
    let item: ClubRailItem
    var onError: ((String) -> Void)? = nil

    @Environment(ClubsStore.self) private var clubs
    @State private var actionScope = AccountActionScope()
    @State private var optimisticReactions: [String: Int]?
    @State private var optimisticMyReactions: Set<String>?

    private var effectiveReactions: [String: Int] {
        optimisticReactions ?? item.reactions ?? [:]
    }

    private var effectiveMyReactions: Set<String> {
        optimisticMyReactions ?? Set(item.my_reactions ?? [])
    }

    private var summaryKeys: [String] {
        ClubReactionGlyph.keys.filter { (effectiveReactions[$0] ?? 0) > 0 }
    }

    private var accessibilityText: String {
        let german = KuroLocale.isGerman
        guard !summaryKeys.isEmpty else { return german ? "Reagieren" : "React" }
        let counts = summaryKeys.map { "\(ClubReactionGlyph.spokenName(for: $0, german: german)) \(effectiveReactions[$0] ?? 0)" }
        return (german ? "Reaktionen: " : "Reactions: ") + counts.joined(separator: ", ")
    }

    var body: some View {
        let origin = actionScope.capture(session: clubs.accountSession)
        let german = KuroLocale.isGerman
        return Menu {
            ForEach(ClubReactionGlyph.keys, id: \.self) { key in
                let count = effectiveReactions[key] ?? 0
                let isMine = effectiveMyReactions.contains(key)
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    toggleReaction(emoji: key, origin: origin)
                } label: {
                    let name = ClubReactionGlyph.spokenName(for: key, german: german)
                    let title = count > 0 ? "\(name) · \(count)" : name
                    if isMine {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Label(title, systemImage: ClubReactionGlyph.symbol(for: key) ?? "number")
                    }
                }
            }
        } label: {
            // The live reaction row as 20 pt monochrome chips (status-pill ink on black @ .06), one
            // 44 pt target that opens the menu.
            HStack(spacing: 5) {
                ForEach(summaryKeys, id: \.self) { key in
                    HStack(spacing: 3) {
                        if let symbol = ClubReactionGlyph.symbol(for: key) {
                            Image(systemName: effectiveMyReactions.contains(key) ? (ClubReactionGlyph.selectedSymbol(for: key) ?? symbol) : symbol)
                        } else {
                            Text(verbatim: "100")
                                .fontWeight(effectiveMyReactions.contains(key) ? .bold : .regular)
                        }
                        Text(verbatim: "\(effectiveReactions[key] ?? 0)")
                            .monospacedDigit()
                    }
                    .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 18))
                    .foregroundStyle(Color.kuroInk.opacity(effectiveMyReactions.contains(key) ? 0.85 : 0.55))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.kuroInk.opacity(effectiveMyReactions.contains(key) ? 0.1 : 0.06)))
                }
                Image(systemName: summaryKeys.isEmpty ? "face.smiling" : "plus")
                    .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 16))
                    .foregroundStyle(Color.kuroInk.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.kuroInk.opacity(0.06)))
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(KuroLocale.text("Opens the reactions.", "Öffnet die Reaktionen."))
        .onAppear { actionScope.activate(session: clubs.accountSession) }
        .onDisappear {
            actionScope.deactivate()
            optimisticReactions = nil
            optimisticMyReactions = nil
        }
    }

    private func toggleReaction(emoji: String, origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: clubs.accountSession) else { return }
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

        actionScope.launch(origin: origin, session: clubs.accountSession) { ticket in
            do {
                _ = try await clubs.toggleReaction(railItemId: item.id, emoji: emoji)
            } catch {
                guard actionScope.isCurrent(ticket, session: clubs.accountSession) else { return }
                optimisticReactions = nil
                optimisticMyReactions = nil
                guard !(error is CancellationError) else { return }
                KuroAccessibility.errorHaptic()
                onError?(KuroLocale.text("Reaction not saved", "Reaktion nicht gespeichert"))
            }
        }
    }
}
