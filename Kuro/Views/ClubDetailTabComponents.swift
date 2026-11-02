import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Club detail tabs
// RAILS: each rail's titles as equal covers (width from the container), the rail's real description,
// member notes on light cards hidden until tapped, and a reactions menu per title.
// ACTIVE: member updates grouped by local day as hairline rows (dates via KuroLocale).
// POLLS: open polls first, closed polls after, 44 pt option rows.
// Nothing here invents club voice: rails without a description show none.

// MARK: - Tab Bar

struct JournalTabBar: View {
    @Binding var selectedTab: ClubDetailView.Tab
    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Scrolls sideways only when the labels do not fit (largest text sizes, German); a trailing
        // fade then shows there is more.
        ScrollView(.horizontal, showsIndicators: false) {
            tabs
                .padding(.horizontal, KuroDesignSpacing.padding)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .kuroTrailingOverflowFade()
        .background(Color.kuroCanvasPage)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 1)
        }
    }

    private var tabs: some View {
        HStack(spacing: KuroDesignSpacing.lg) {
            ForEach(ClubDetailView.Tab.visibleCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    guard !isSelected else { return }
                    KuroAccessibility.selectionHaptic()
                    withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: KuroDesignSpacing.sm) {
                        Text(tab.title)
                            .font(.kuroBody(weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroInkQuiet)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if isSelected {
                                if reduceMotion {
                                    // Reduce Motion: no travel between tabs, each word's own rule fades
                                    // (rulebook §8).
                                    Rectangle()
                                        .fill(Color.kuroInk)
                                        .frame(height: 2)
                                        .transition(.opacity)
                                } else {
                                    Rectangle()
                                        .fill(Color.kuroInk)
                                        .frame(height: 2)
                                        .matchedGeometryEffect(id: "tab_underline", in: tabNamespace)
                                }
                            }
                        }
                    }
                    .padding(.top, KuroDesignSpacing.md)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
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

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            KuroStateView(.empty, title: title, message: message, layout: .inline)
            if let actionTitle, let action {
                KuroInkButton(actionTitle, role: .secondary, action: action)
            }
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .padding(.top, KuroDesignSpacing.lg)
        .padding(.bottom, KuroDesignSpacing.xxl)
    }
}

/// Card metrics from the container (CLAUDE.md card sizing): never a hard-coded screen width.
nonisolated enum ClubRailCardMetrics {
    static func width(containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return 120 }
        return min(144, max(112, floor((containerWidth - 56) / 2.8)))
    }

    static func height(width: CGFloat) -> CGFloat {
        (width / 0.7).rounded()
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
    @Environment(FeatureFlags.self) private var flags

    private var isAdmin: Bool { ["owner", "admin"].contains(bundle.my_role) }

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
                } : nil
            )
            .disabled(!isConnected)
        } else {
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
                        .padding(.horizontal, KuroDesignSpacing.padding)
                        .padding(.top, KuroDesignSpacing.md)
                    }
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(bundle.rails.enumerated()), id: \.element.id) { index, rail in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.kuroHairline)
                                .frame(height: 1)
                                .padding(.horizontal, KuroDesignSpacing.padding)
                                .padding(.top, KuroDesignSpacing.lg)
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
                            } : nil
                        )
                    }
                }
                .padding(.top, KuroDesignSpacing.sm)
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
                    .foregroundStyle(Color.kuroInkQuiet)
                }
                if userStreamingServicesEmpty {
                    Text(KuroLocale.text("Set your services in Profile to compare.", "Gib deine Dienste im Profil an, um zu vergleichen."))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                }
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
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
    @Environment(FeatureFlags.self) private var flags

    private var cardWidth: CGFloat { ClubRailCardMetrics.width(containerWidth: containerWidth) }

    var body: some View {
        let german = KuroLocale.isGerman
        let notes = ClubRoomCopy.notes(in: rail, members: members)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.sm) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.sm) {
                        Text(rail.title)
                            .kuroRoleText(.title)
                            .foregroundStyle(Color.kuroInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if rail.is_locked {
                            Image(systemName: "lock")
                                .font(.kuroMeta())
                                .foregroundStyle(Color.kuroInkQuiet)
                                .accessibilityLabel(KuroLocale.text("Locked", "Gesperrt"))
                        }
                    }
                    Text(ClubRoomCopy.titleCount(rail.items.count, german: german))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onAddItem {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onAddItem()
                    } label: {
                        Image(systemName: "plus")
                            .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                            .foregroundStyle(Color.kuroInk)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.kuroCanvasQuiet))
                            .contentShape(Circle())
                    }
                    .buttonStyle(KuroPressStyle())
                    .accessibilityLabel(KuroLocale.text("Add a title to \(rail.title)", "Titel zu \(rail.title) hinzufügen"))
                }
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.top, KuroDesignSpacing.lg)

            if let desc = rail.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                Text(desc)
                    .font(.kuroBody(weight: .light))
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.sm)
            }

            if rail.items.isEmpty {
                KuroStateView(.empty, title: KuroLocale.text("Nothing here yet.", "Hier ist noch nichts."),
                              layout: .inline)
                    .padding(.horizontal, KuroDesignSpacing.padding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: KuroDesignSpacing.md) {
                        ForEach(rail.items) { item in
                            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                                JournalRailItemCard(item: item, cardWidth: cardWidth)
                                if flags.isClubsReactionsV1Enabled {
                                    ClubReactionMenu(item: item, onError: onError)
                                        .frame(width: cardWidth, alignment: .leading)
                                }
                            }
                            .opacity(itemOpacity?(item) ?? 1.0)
                            .kuroAnimation(KuroMotion.settle, value: itemOpacity?(item) ?? 1.0)
                        }

                        if let onAddItem {
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                onAddItem()
                            } label: {
                                RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                    .strokeBorder(Color.kuroHairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                    .frame(width: cardWidth, height: ClubRailCardMetrics.height(width: cardWidth))
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.kuroCustom(20, weight: .light, relativeTo: .title3, maxSize: 28))
                                            .foregroundStyle(Color.kuroInkSecondary)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(KuroPressStyle())
                            .accessibilityLabel(KuroLocale.text("Add a title to \(rail.title)", "Titel zu \(rail.title) hinzufügen"))
                        }
                    }
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.md)
                }
                .kuroSwipeExclusionZone()
            }

            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    ForEach(notes, id: \.itemId) { note in
                        ClubNoteCard(note: note.text, author: note.author, title: note.title)
                            .id(note.text) // an edited note starts hidden again
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroDesignSpacing.md)
            }
        }
    }
}

// MARK: - Rail Item Card

struct JournalRailItemCard: View {
    let item: ClubRailItem
    let cardWidth: CGFloat

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private var cardHeight: CGFloat { ClubRailCardMetrics.height(width: cardWidth) }

    private var mediaKind: MediaKind {
        item.media_type.uppercased() == "MANGA" ? .manga : .anime
    }

    private var libraryKey: MediaKey {
        MediaKey(kind: mediaKind, id: item.media_id)
    }

    private var isInCollection: Bool {
        library.isTracked(libraryKey)
    }

    private var progressText: String? {
        ClubRoomCopy.progress(item.my_progress, total: item.totalCount, isManga: mediaKind == .manga, german: KuroLocale.isGerman)
    }

    private var membersCurrentText: String? {
        guard let statuses = item.member_statuses, !statuses.isEmpty else { return nil }
        let current = statuses.filter { s in
            let st = s.status?.uppercased() ?? ""
            return st == "CURRENT" || st == "WATCHING" || st == "READING"
        }
        return ClubRoomCopy.membersCurrent(names: current.map(\.display_name), isManga: mediaKind == .manga, german: KuroLocale.isGerman)
    }

    private var accessibilityText: String {
        [item.title_display, progressText, membersCurrentText].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        return Button {
            guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(libraryKey))
        } label: {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                Color.kuroMissingArt
                    .frame(width: cardWidth, height: cardHeight)
                    .overlay {
                        KuroCachedAsyncImage(url: URL(string: item.cover_image_medium ?? ""), maxPixelSize: 520) { phase in
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
                    .clipShape(RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title_display)
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)

                    if let progress = progressText {
                        Text(progress)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .lineLimit(1)
                    }

                    if let members = membersCurrentText {
                        Text(members)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkQuiet)
                            .lineLimit(2)
                    }
                }
                .frame(width: cardWidth, alignment: .topLeading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.985))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(KuroLocale.text("Opens the title.", "Öffnet den Titel."))
        .accessibilityAddTraits(.isButton)
        .contextMenu {
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
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate() }
    }
}

// MARK: - Activity Content

struct JournalActivityContent: View {
    let bundle: ClubBundle
    @Environment(FeatureFlags.self) private var flags

    struct ActivityEntry: Identifiable {
        let id: String
        let displayName: String
        let titleDisplay: String
        let status: String?
        let progress: Int?
        let mediaType: String
        let mediaId: Int
        let coverImage: String?
        let updatedAt: Date
        let episodeCount: Int?
        let chapterCount: Int?

        /// The title the entry is about (N9: the entry opens it).
        var mediaKey: MediaKey { ClubActivityTarget.key(mediaType: mediaType, mediaId: mediaId) }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = KuroLocale.locale
        f.timeZone = KuroLocale.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = KuroLocale.locale
        f.timeZone = KuroLocale.timeZone
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }

    private var entries: [ActivityEntry] {
        var result: [ActivityEntry] = []
        let fallbackName = KuroLocale.text("A member", "Ein Mitglied")
        for rail in bundle.rails {
            for item in rail.items {
                guard let statuses = item.member_statuses else { continue }
                for ms in statuses {
                    guard let dateStr = ms.updated_at else { continue }
                    guard let date = Self.isoFractional.date(from: dateStr) ?? Self.iso.date(from: dateStr) else { continue }
                    let name = ms.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    result.append(ActivityEntry(
                        id: "\(item.id)-\(ms.user_id)",
                        displayName: name.isEmpty ? fallbackName : name,
                        titleDisplay: item.title_display,
                        status: ms.status,
                        progress: ms.progress,
                        mediaType: item.media_type,
                        mediaId: item.media_id,
                        coverImage: item.cover_image_medium,
                        updatedAt: date,
                        episodeCount: item.episode_count,
                        chapterCount: item.chapter_count
                    ))
                }
            }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var groupedByDay: [(date: String, entries: [ActivityEntry])] {
        let formatter = dayFormatter
        var groups: [String: [ActivityEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            let key = formatter.string(from: entry.updatedAt)
            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(entry)
        }
        return order.compactMap { key in groups[key].map { (date: key, entries: $0) } }
    }

    var body: some View {
        if entries.isEmpty {
            // Duo clubs: the bundle withholds member_statuses below 3 members (k>=3 rule),
            // so say so honestly instead of implying activity is merely missing.
            let isDuo = bundle.member_count == 2
            ClubTabEmptyState(
                title: KuroLocale.text("No activity yet.", "Noch keine Aktivität."),
                message: isDuo
                    ? KuroLocale.text("Activity shows from 3 members. Invite one more friend.",
                                      "Aktivität erscheint ab 3 Mitgliedern. Lade noch jemanden ein.")
                    : KuroLocale.text("Updates appear here as members watch and read.",
                                      "Hier erscheint, was Mitglieder schauen und lesen.")
            )
        } else {
            let timeFormatter = timeFormatter
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedByDay, id: \.date) { group in
                    Text(group.date)
                        .kuroRoleText(.title)
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, KuroDesignSpacing.padding)
                        .padding(.top, KuroDesignSpacing.lg)
                        .padding(.bottom, KuroDesignSpacing.xs)

                    ForEach(group.entries) { entry in
                        JournalActivityEntry(
                            entry: entry,
                            timeText: timeFormatter.string(from: entry.updatedAt)
                        )
                    }
                }

                if flags.isClubsPaceSyncV1Enabled && bundle.club.sharing_level == "progress" && bundle.member_count >= 3 {
                    ForEach(paceBehindItems, id: \.id) { item in
                        JournalPaceBanner(item: item)
                            .padding(.horizontal, KuroDesignSpacing.padding)
                            .padding(.top, KuroDesignSpacing.md)
                    }
                }
            }
            .padding(.bottom, KuroDesignSpacing.xxl)
        }
    }

    private var paceBehindItems: [ClubRailItem] {
        bundle.rails.flatMap(\.items).filter { item in
            guard let myProgress = item.my_progress,
                  let statuses = item.member_statuses, !statuses.isEmpty else { return false }
            let otherProgresses = statuses.compactMap(\.progress).sorted()
            guard !otherProgresses.isEmpty else { return false }
            let count = otherProgresses.count
            let median = count % 2 == 0
                ? (otherProgresses[count / 2 - 1] + otherProgresses[count / 2]) / 2
                : otherProgresses[count / 2]
            return myProgress < median
        }
    }
}

// MARK: - Activity Entry

/// Where a "This week" entry leads (pure, NavclubsTests): its title, by the rail item's media type
/// ("MANGA" in any case is manga; anything else is anime, as the rail cards read it).
nonisolated enum ClubActivityTarget {
    static func key(mediaType: String, mediaId: Int) -> MediaKey {
        MediaKey(kind: mediaType.uppercased() == "MANGA" ? .manga : .anime, id: mediaId)
    }
}

/// One member's update. Tapping it opens the title (pushed inside the club's journey, N9).
struct JournalActivityEntry: View {
    let entry: JournalActivityContent.ActivityEntry
    let timeText: String

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private var parts: ClubActivityProse.Parts {
        ClubActivityProse.parts(status: entry.status, progress: entry.progress,
                                isManga: entry.mediaType.uppercased() == "MANGA", german: KuroLocale.isGerman)
    }

    private var proseText: AttributedString {
        var result = AttributedString()

        var namePart = AttributedString(entry.displayName)
        namePart.font = .kuroBody(weight: .semibold)
        result.append(namePart)

        var before = AttributedString(parts.beforeTitle)
        before.font = .kuroBody(weight: .light)
        result.append(before)

        var titlePart = AttributedString(entry.titleDisplay)
        titlePart.font = .kuroBody(weight: .medium)
        result.append(titlePart)

        if !parts.afterTitle.isEmpty {
            var after = AttributedString(parts.afterTitle)
            after.font = .kuroBody(weight: .light)
            result.append(after)
        }
        return result
    }

    var body: some View {
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(entry.mediaKey))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.md) {
                Text(proseText)
                    .foregroundStyle(Color.kuroInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(timeText)
                    .font(.kuroMeta())
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroInkQuiet)
            }
            .padding(.vertical, KuroDesignSpacing.md)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.kuroHairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .padding(.horizontal, KuroDesignSpacing.padding)
        .accessibilityElement(children: .combine)
        .accessibilityHint(KuroLocale.text("Opens the title.", "Öffnet den Titel."))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Pace Banner

struct JournalPaceBanner: View {
    let item: ClubRailItem

    private var paceText: String? {
        guard let myProgress = item.my_progress,
              let statuses = item.member_statuses, !statuses.isEmpty else { return nil }
        let otherProgresses = statuses.compactMap(\.progress).sorted()
        guard !otherProgresses.isEmpty else { return nil }
        let count = otherProgresses.count
        let median = count % 2 == 0
            ? (otherProgresses[count / 2 - 1] + otherProgresses[count / 2]) / 2
            : otherProgresses[count / 2]
        let diff = median - myProgress
        guard diff > 0 else { return nil }
        let isManga = item.media_type.uppercased() == "MANGA"
        if KuroLocale.isGerman {
            let unit = isManga ? "Kapitel" : (diff == 1 ? "Folge" : "Folgen")
            return "Du liegst bei \(item.title_display) \(diff) \(unit) hinter der Gruppe."
        }
        let unit = isManga ? (diff == 1 ? "chapter" : "chapters") : (diff == 1 ? "episode" : "episodes")
        return "You're \(diff) \(unit) behind the group on \(item.title_display)."
    }

    var body: some View {
        if let paceText {
            Text(paceText)
                .font(.kuroBody(weight: .light))
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(KuroDesignSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .fill(Color.kuroCanvasQuiet)
                )
        }
    }
}

// MARK: - Milestone Card

struct JournalMilestoneCard: View {
    let item: ClubRailItem
    let memberCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
            Text(KuroLocale.text("Finished together", "Gemeinsam beendet"))
                .kuroKicker()
            Text(KuroLocale.text("All \(memberCount) members finished \(item.title_display).",
                                 "Alle \(memberCount) Mitglieder haben \(item.title_display) beendet."))
                .kuroRoleText(.title)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Color.kuroInk)
                .frame(width: 40, height: 2)
                .padding(.top, KuroDesignSpacing.xs)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, KuroDesignSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Polls Content

struct JournalPollsContent: View {
    let bundle: ClubBundle
    let clubsInteractionV2Enabled: Bool
    let voteInFlightPollIds: Set<String>
    let optimisticVoteByPollId: [String: String]
    let optimisticVoteCountsByPollId: [String: [String: Int]]
    let onVote: (ClubPoll, String) -> Void
    let onCreatePoll: () -> Void
    let isConnected: Bool

    private var isAdmin: Bool { ["owner", "admin"].contains(bundle.my_role) }

    private var openPolls: [ClubPoll] {
        bundle.polls.filter { !$0.is_closed }
    }

    private var closedPolls: [ClubPoll] {
        bundle.polls.filter { $0.is_closed }
    }

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
                } : nil
            )
            .disabled(!isConnected)
        } else {
            LazyVStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                ForEach(openPolls) { poll in
                    JournalPollCard(
                        poll: poll,
                        members: bundle.members,
                        isSubmittingVote: clubsInteractionV2Enabled && voteInFlightPollIds.contains(poll.id),
                        optimisticMyVoteOptionId: clubsInteractionV2Enabled ? optimisticVoteByPollId[poll.id] : nil,
                        optimisticVoteCounts: clubsInteractionV2Enabled ? optimisticVoteCountsByPollId[poll.id] : nil,
                        onVote: { optionId in onVote(poll, optionId) }
                    )
                }

                if !closedPolls.isEmpty {
                    Text(KuroLocale.text("Closed", "Geschlossen"))
                        .kuroRoleText(.title)
                        .foregroundStyle(Color.kuroInk)
                        .padding(.horizontal, KuroDesignSpacing.padding)
                        .padding(.top, KuroDesignSpacing.md)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(closedPolls) { poll in
                        JournalPollCard(
                            poll: poll,
                            members: bundle.members,
                            isSubmittingVote: false,
                            optimisticMyVoteOptionId: nil,
                            optimisticVoteCounts: nil,
                            onVote: { _ in }
                        )
                    }
                }

                if isAdmin {
                    KuroInkButton(KuroLocale.text("Ask a question", "Eine Frage stellen"), role: .secondary) {
                        onCreatePoll()
                    }
                    .disabled(!isConnected)
                    .padding(.horizontal, KuroDesignSpacing.padding)
                    .padding(.top, KuroDesignSpacing.sm)
                }
            }
            .padding(.top, KuroDesignSpacing.md)
            .padding(.bottom, KuroDesignSpacing.xxl)
        }
    }
}

// MARK: - Poll Card

struct JournalPollCard: View {
    let poll: ClubPoll
    let members: [ClubMember]
    let isSubmittingVote: Bool
    let optimisticMyVoteOptionId: String?
    let optimisticVoteCounts: [String: Int]?
    let onVote: (String) -> Void

    private var totalVotes: Int {
        if let optimisticVoteCounts {
            return optimisticVoteCounts.values.reduce(0, +)
        }
        return poll.options.reduce(0) { $0 + $1.vote_count }
    }

    private var myVoteId: String? { optimisticMyVoteOptionId ?? poll.my_vote_option_id }

    private var hasVoted: Bool { myVoteId != nil }

    private var askerLine: String? {
        let name = members.first { $0.user_id == poll.created_by }?.display_name?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return KuroLocale.text("\(name) asks", "\(name) fragt")
    }

    private var votesText: String? {
        guard totalVotes > 0 else { return nil }
        return KuroLocale.isGerman
            ? (totalVotes == 1 ? "1 Stimme" : "\(totalVotes) Stimmen")
            : (totalVotes == 1 ? "1 vote" : "\(totalVotes) votes")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            if askerLine != nil || poll.is_closed {
                HStack(spacing: KuroDesignSpacing.sm) {
                    if let askerLine {
                        Text(askerLine)
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInkQuiet)
                    }
                    if poll.is_closed {
                        Text(KuroLocale.text("Closed", "Geschlossen"))
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInkQuiet)
                    }
                }
            }

            Text(poll.question)
                .kuroRoleText(.title)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(poll.options) { option in
                    let renderedCount = optimisticVoteCounts?[option.id] ?? option.vote_count
                    JournalPollOptionRow(
                        option: option,
                        displayVoteCount: renderedCount,
                        totalVotes: totalVotes,
                        isMyVote: myVoteId == option.id,
                        hasVoted: hasVoted,
                        isClosed: poll.is_closed,
                        isSubmittingVote: isSubmittingVote,
                        onTap: {
                            guard !poll.is_closed else { return }
                            guard myVoteId != option.id else { return }
                            guard !isSubmittingVote else { return }
                            onVote(option.id)
                        }
                    )
                }
            }

            if let votesText {
                Text(votesText)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkQuiet)
            }
        }
        .padding(KuroDesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(Color.kuroCanvasPage)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .strokeBorder(Color.kuroHairline, lineWidth: 1)
        )
        .padding(.horizontal, KuroDesignSpacing.padding)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Poll Option Row

struct JournalPollOptionRow: View {
    let option: ClubPollOption
    let displayVoteCount: Int
    let totalVotes: Int
    let isMyVote: Bool
    let hasVoted: Bool
    let isClosed: Bool
    let isSubmittingVote: Bool
    let onTap: () -> Void

    private var fraction: Double {
        guard totalVotes > 0 else { return 0 }
        return Double(displayVoteCount) / Double(totalVotes)
    }

    private var showsResults: Bool { hasVoted || isClosed }

    private var percentageText: String {
        guard totalVotes > 0 else { return "" }
        return fraction.formatted(.percent.precision(.fractionLength(0)).locale(KuroLocale.locale))
    }

    private var accessibilityText: String {
        var parts = [option.label]
        if showsResults, totalVotes > 0 { parts.append(percentageText) }
        if isMyVote { parts.append(KuroLocale.text("your vote", "deine Stimme")) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.sm) {
                    Image(systemName: isMyVote ? "checkmark.circle.fill" : "circle")
                        .font(.kuroMeta())
                        .foregroundStyle(isMyVote ? Color.kuroInk : Color.kuroInkQuiet)
                    Text(option.label)
                        .font(.kuroBody(weight: isMyVote ? .semibold : .regular))
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsResults {
                        Text(percentageText)
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .monospacedDigit()
                    }
                }

                if showsResults {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.kuroHairline).frame(height: 3)
                            Capsule()
                                .fill(isMyVote ? Color.kuroInk : Color.kuroInkQuiet)
                                .frame(width: geo.size.width * fraction, height: 3)
                        }
                    }
                    .frame(height: 3)
                    .kuroAnimation(KuroMotion.settle, value: fraction)
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, KuroDesignSpacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.99))
        .disabled(isClosed || isSubmittingVote)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isMyVote ? [.isButton, .isSelected] : .isButton)
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
            HStack(spacing: KuroDesignSpacing.sm) {
                if summaryKeys.isEmpty {
                    Image(systemName: "face.smiling")
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                } else {
                    ForEach(summaryKeys, id: \.self) { key in
                        HStack(spacing: 2) {
                            if let symbol = ClubReactionGlyph.symbol(for: key) {
                                Image(systemName: effectiveMyReactions.contains(key) ? (ClubReactionGlyph.selectedSymbol(for: key) ?? symbol) : symbol)
                            } else {
                                Text(verbatim: "100")
                                    .fontWeight(effectiveMyReactions.contains(key) ? .bold : .regular)
                            }
                            Text(verbatim: "\(effectiveReactions[key] ?? 0)")
                                .monospacedDigit()
                        }
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                    }
                }
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
