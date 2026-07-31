import SwiftUI
import PostgREST

// MARK: - Journal Tab Bar

struct JournalTabBar: View {
    @Binding var selectedTab: ClubDetailView.Tab
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 24) {
            ForEach(ClubDetailView.Tab.visibleCases, id: \.self) { tab in
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    withAnimation(KuroAnimation.editorial) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.kuroCaption(weight: .medium))
                            .tracking(2.0)
                            .foregroundColor(selectedTab == tab ? .kuroBlack80 : .kuroTextTertiary)
                            .padding(.vertical, 12)

                        if selectedTab == tab {
                            Rectangle()
                                .fill(Color.kuroBlack80)
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "tab_underline", in: tabNamespace)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .background(Color.kuroBackground)
        .overlay(alignment: .bottom) {
            EditorialLayout.divider(thickness: 1.0, opacity: 0.06)
        }
    }
}

// MARK: - Club Detail Section Helpers

private struct ClubDetailSectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String?
    let trailing: AnyView?

    init(
        eyebrow: String,
        title: String,
        detail: String? = nil,
        trailing: AnyView? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.7)
                    .foregroundColor(.kuroBlack40)

                Spacer(minLength: 0)

                trailingView
            }

            Text(title)
                .font(.kuroTitle(weight: .regular))
                .foregroundColor(.kuroBlack80)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        if let trailing {
            trailing
        }
    }
}

private struct ClubDetailEmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.kuroCustom(22, weight: .light, relativeTo: .title3))
                .foregroundColor(.kuroBlack30)

            Text(title)
                .font(.kuroBody(weight: .light))
                .foregroundColor(.kuroBlack60)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.kuroCaption(weight: .light))
                .foregroundColor(.kuroBlack40)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle.uppercased())
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.kuroBlack80)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .stroke(Color.kuroBlack20, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ClubDetailSectionPill: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title.uppercased())
                .font(.kuroMicro(weight: .medium))
                .tracking(1.0)
        }
        .foregroundColor(isActive ? .kuroBlack80 : .kuroBlack40)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(isActive ? Color.kuroBlack08 : Color.kuroBlack04)
        )
    }
}

// MARK: - Journal Rails Content

struct JournalRailsContent: View {
    let bundle: SupabaseService.ClubBundle
    let showSharedAvailability: Bool
    let sharedProviders: SupabaseService.ClubSharedProvidersResponse?
    let isAvailableOnSharedServices: (Int, String) -> Bool
    let onToggleShared: () -> Void
    let onCreateRail: () -> Void
    let onAddToRail: (String) -> Void
    let onError: (String) -> Void
    let canAddToRail: (SupabaseService.ClubRail, String) -> Bool
    let userStreamingServicesEmpty: Bool
    let isConnected: Bool

    var body: some View {
        if bundle.rails.isEmpty {
            railsEmptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                railsPopulatedContent
            }
        }
    }

    private var railsEmptyState: some View {
        ClubDetailEmptyStateCard(
            icon: "list.bullet.rectangle",
            title: "No rails yet",
            message: ["owner", "admin"].contains(bundle.my_role)
                ? "Create a rail to start curating together."
                : "Rails appear when the club starts collecting titles.",
            actionTitle: ["owner", "admin"].contains(bundle.my_role) ? "Create rail" : nil,
            action: ["owner", "admin"].contains(bundle.my_role) ? {
                KuroAccessibility.impactHaptic(.light)
                onCreateRail()
            } : nil
        )
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var railsPopulatedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Streaming availability controls
            streamingAvailabilityControls

            // Milestone celebrations
            if FeatureFlags.shared.isClubsPaceSyncV1Enabled {
                let milestones = bundle.rails.flatMap { rail in
                    rail.items.compactMap { item -> SupabaseService.ClubRailItem? in
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
                    .padding(.horizontal, 20)
                    .padding(.top, KuroDesignSpacing.sm)
                }
            }

            // Rail sections
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(bundle.rails.enumerated()), id: \.element.id) { index, rail in
                    if index > 0 {
                        EditorialLayout.divider(thickness: 1.0, opacity: 0.08)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }

                    JournalRailSection(
                        rail: rail,
                        memberCount: bundle.member_count,
                        curatorNote: curatorNote(for: rail, index: index),
                        onAddItem: canAddToRail(rail, bundle.my_role) ? {
                            onAddToRail(rail.id)
                        } : nil,
                        onError: onError,
                        itemOpacity: showSharedAvailability ? { item in
                            isAvailableOnSharedServices(item.media_id, item.media_type) ? 1.0 : 0.35
                        } : nil
                    )
                }
            }
            .padding(.top, KuroDesignSpacing.md)
            .padding(.bottom, KuroDesignSpacing.xxl)
        }
    }

    private var sectionHeader: some View {
        ClubDetailSectionHeader(
            eyebrow: "Rails",
            title: "Curated stacks",
            detail: "Shared availability and reactions stay grouped around each rail.",
            trailing: AnyView(
                ClubDetailSectionPill(
                    title: "\(bundle.rails.count)",
                    systemImage: "list.bullet.rectangle",
                    isActive: !bundle.rails.isEmpty
                )
            )
        )
    }

    @ViewBuilder
    private var streamingAvailabilityControls: some View {
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let sp = sharedProviders, !sp.shared_services.isEmpty {
                        Button {
                            onToggleShared()
                        } label: {
                            ClubDetailSectionPill(
                                title: showSharedAvailability ? "Shared on" : "Shared off",
                                systemImage: "play.tv",
                                isActive: showSharedAvailability
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                if let sp = sharedProviders {
                    if sp.coverage_pct < 100 && sp.member_count_with_services > 0 {
                        Text("\(sp.member_count_with_services) of \(sp.member_count_total) members set up services")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroTextTertiary)
                    }
                    if userStreamingServicesEmpty {
                        Text("Set your services in Profile to unlock shared availability.")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroTextTertiary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private func curatorNote(for rail: SupabaseService.ClubRail, index: Int) -> String? {
        // Use rail description if available, otherwise generate editorial notes
        if let desc = rail.description, !desc.isEmpty {
            return desc
        }
        // Default editorial notes based on position
        switch index {
        case 0: return "What we're watching right now"
        case 1: return "On the list for later"
        case 2: return "The ones that started it all"
        default: return nil
        }
    }
}

// MARK: - Journal Rail Section

struct JournalRailSection: View {
    let rail: SupabaseService.ClubRail
    let memberCount: Int
    let curatorNote: String?
    var onAddItem: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil
    var itemOpacity: ((SupabaseService.ClubRailItem) -> Double)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Curator note
            if let note = curatorNote {
                Text(note)
                    .font(.kuroBody())
                    .italic()
                    .foregroundColor(.kuroTextSecondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
            }

            // Rail header
            HStack(spacing: 8) {
                Text(rail.title.uppercased())
                    .font(.kuroTitle(weight: .regular))
                    .foregroundColor(.kuroBlack80)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                if rail.is_locked {
                    Image(systemName: "lock.fill")
                        .font(.kuroMicro())
                        .foregroundColor(.kuroTextTertiary)
                }

                Spacer()

                Text("\(rail.items.count) TITLES")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroTextTertiary)

                if let onAddItem {
                    Button {
                        KuroAccessibility.impactHaptic(.light)
                        onAddItem()
                    } label: {
                        Image(systemName: "plus")
                            .font(.kuroCustom(13, weight: .medium, relativeTo: .caption1))
                            .foregroundColor(.kuroTextSecondary)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(Color.kuroBlack06)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            // Horizontal scroll of items
            if rail.items.isEmpty {
                Text("No items yet")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, KuroDesignSpacing.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(rail.items) { item in
                            VStack(spacing: 6) {
                                JournalRailItemCard(item: item, memberCount: memberCount)
                                if FeatureFlags.shared.isClubsReactionsV1Enabled {
                                    let hasAnyReaction: Bool = {
                                        let counts = item.reactions ?? [:]
                                        let mine = item.my_reactions ?? []
                                        return counts.values.contains(where: { $0 > 0 }) || !mine.isEmpty
                                    }()
                                    if hasAnyReaction {
                                        ClubReactionRow(item: item, onError: onError)
                                    } else {
                                        ClubReactionRowCompact(item: item, onError: onError)
                                    }
                                }
                            }
                            .opacity(itemOpacity?(item) ?? 1.0)
                            .animation(KuroAnimation.fast, value: itemOpacity?(item) ?? 1.0)
                        }

                        // Add card
                        if let onAddItem {
                            Button {
                                KuroAccessibility.impactHaptic(.light)
                                onAddItem()
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                                        .strokeBorder(
                                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                        )
                                        .foregroundColor(.kuroBlack10)
                                        .frame(width: 120, height: 170)
                                        .overlay(
                                            VStack(spacing: 6) {
                                                Image(systemName: "plus")
                                                    .font(.kuroCustom(20, weight: .light, relativeTo: .title3))
                                                    .foregroundColor(.kuroTextTertiary)
                                                Text("ADD")
                                                    .font(.kuroMicro(weight: .medium))
                                                    .tracking(1.5)
                                                    .foregroundColor(.kuroTextTertiary)
                                            }
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add item to rail")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .kuroSwipeExclusionZone()
            }
        }
    }
}

// MARK: - Journal Rail Item Card

struct JournalRailItemCard: View {
    let item: SupabaseService.ClubRailItem
    let memberCount: Int

    @State private var showDetail = false
    @State private var showAddToList = false
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    private let cardWidth: CGFloat = 120
    private let cardHeight: CGFloat = 170

    private var mediaKind: MediaKind {
        item.media_type.uppercased() == "MANGA" ? .manga : .anime
    }

    private var mediaType: String {
        mediaKind.rawValue
    }

    private var isInCollection: Bool {
        supabaseService.isInCollection(mediaId: item.media_id, mediaType: mediaType)
    }

    private var progressText: String? {
        guard let progress = item.my_progress, progress > 0 else { return nil }
        let prefix = item.media_type.uppercased() == "ANIME" ? "EP" : "CH"
        let total = item.media_type.uppercased() == "ANIME" ? item.episode_count : item.chapter_count
        if let total, total > 0 {
            return "\(prefix) \(progress) OF \(total)"
        }
        return "\(prefix) \(progress)"
    }

    private var membersWatchingText: String? {
        guard let statuses = item.member_statuses, !statuses.isEmpty else { return nil }
        let watching = statuses.filter { s in
            let st = s.status?.uppercased() ?? ""
            return st == "CURRENT" || st == "WATCHING" || st == "READING"
        }
        guard !watching.isEmpty else { return nil }
        let names = watching.prefix(2).compactMap { $0.display_name }
        if names.isEmpty { return "\(watching.count) watching" }
        if watching.count <= 2 {
            return names.joined(separator: ", ") + " watching"
        }
        return names.joined(separator: ", ") + " +\(watching.count - 2)"
    }

    var body: some View {
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Poster
                KuroCachedAsyncImage(url: URL(string: item.cover_image_medium ?? ""), maxPixelSize: 520) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                    case .failure, .empty:
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .fill(Color.kuroBlack06)
                            .frame(width: cardWidth, height: cardHeight)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous))

                // Title
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title_display.uppercased())
                        .font(.kuroCustom(13, weight: .light, design: .serif, relativeTo: .caption1))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundColor(.kuroBlack80)
                        .lineLimit(2)
                        .frame(height: 34, alignment: .top)

                    if let progress = progressText {
                        Text(progress)
                            .font(.kuroMicro(weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(.kuroTextTertiary)
                    }

                    if let members = membersWatchingText {
                        Text(members)
                            .font(.kuroCustom(8, weight: .regular, relativeTo: .caption2))
                            .foregroundColor(.kuroTextTertiary)
                    }
                }
                .frame(width: cardWidth, alignment: .topLeading)
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: {
                KuroAccessibility.impactHaptic(.light)
                supabaseService.toggleInCollection(mediaId: item.media_id, mediaType: mediaType)
            }) {
                Label(
                    isInCollection ? "Remove from List" : "Quick Add (Planned)",
                    systemImage: isInCollection ? "minus.circle" : "plus.circle"
                )
            }
        }
        .sheet(isPresented: $showDetail) {
            MediaDetailSheet(kind: mediaKind, id: item.media_id)
        }
    }
}

// MARK: - Journal Activity Content

struct JournalActivityContent: View {
    let bundle: SupabaseService.ClubBundle

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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var entries: [ActivityEntry] {
        var result: [ActivityEntry] = []
        for rail in bundle.rails {
            for item in rail.items {
                guard let statuses = item.member_statuses else { continue }
                for ms in statuses {
                    guard let dateStr = ms.updated_at else { continue }
                    guard let date = Self.isoFractional.date(from: dateStr) ?? Self.iso.date(from: dateStr) else { continue }
                    let name = ms.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? String(ms.user_id.prefix(6))
                    result.append(ActivityEntry(
                        id: "\(item.id)-\(ms.user_id)",
                        displayName: name.isEmpty ? String(ms.user_id.prefix(6)) : name,
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
        let allEntries = entries
        var groups: [String: [ActivityEntry]] = [:]
        var order: [String] = []
        for entry in allEntries {
            let key = Self.dayFormatter.string(from: entry.updatedAt)
            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(entry)
        }
        return order.map { (date: $0, entries: groups[$0]!) }
    }

    var body: some View {
        if entries.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                activityList
            }
        }
    }

    private var emptyState: some View {
        // Duo clubs: the bundle withholds member_statuses below 3 members (k>=3 rule),
        // so say so honestly instead of implying activity is merely missing.
        let isDuo = bundle.member_count == 2
        return ClubDetailEmptyStateCard(
            icon: isDuo ? "person.2" : "book",
            title: "No activity yet",
            message: isDuo
                ? "Activity unlocks at 3 members — invite one more friend."
                : "Activity appears as members update their progress.",
            actionTitle: nil,
            action: nil
        )
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var activityList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groupedByDay.enumerated()), id: \.element.date) { dayIndex, group in
                // Day header
                Text(group.date)
                    .font(.kuroBody())
                    .italic()
                    .foregroundColor(.kuroBlack80)
                    .padding(.horizontal, 20)
                    .padding(.top, dayIndex == 0 ? 16 : 20)
                    .padding(.bottom, 10)

                ForEach(group.entries) { entry in
                    JournalActivityEntry(
                        entry: entry,
                        timeText: Self.timeFormatter.string(from: entry.updatedAt)
                    )
                }
            }

            // Pace banners
            if FeatureFlags.shared.isClubsPaceSyncV1Enabled && bundle.club.sharing_level == "progress" && bundle.member_count >= 3 {
                ForEach(paceBehindItems, id: \.id) { item in
                    JournalPaceBanner(item: item)
                        .padding(.horizontal, 20)
                        .padding(.top, KuroDesignSpacing.md)
                }
            }
        }
        .padding(.bottom, KuroDesignSpacing.xxl)
    }

    private var sectionHeader: some View {
        ClubDetailSectionHeader(
            eyebrow: "Active",
            title: "Recent activity",
            detail: "Progress updates appear in time order so the feed stays easy to scan.",
            trailing: AnyView(
                ClubDetailSectionPill(
                    title: "\(entries.count)",
                    systemImage: "clock.arrow.circlepath",
                    isActive: !entries.isEmpty
                )
            )
        )
    }

    private var paceBehindItems: [SupabaseService.ClubRailItem] {
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

// MARK: - Journal Activity Entry

struct JournalActivityEntry: View {
    let entry: JournalActivityContent.ActivityEntry
    let timeText: String

    private var proseText: AttributedString {
        var result = AttributedString()

        // Bold name
        var namePart = AttributedString(entry.displayName)
        namePart.font = .kuroCustom(15, weight: .semibold)
        result.append(namePart)

        // Action text
        let statusUpper = entry.status?.uppercased() ?? ""
        let unit = entry.mediaType.uppercased() == "ANIME" ? "episode" : "chapter"

        var actionText: String
        switch statusUpper {
        case "COMPLETED":
            actionText = " finished "
        case "CURRENT", "WATCHING", "READING":
            if let progress = entry.progress, progress > 0 {
                actionText = " reached \(unit) \(progress) of "
            } else {
                actionText = " started watching "
            }
        case "PAUSED":
            actionText = " paused "
        case "DROPPED":
            actionText = " dropped "
        case "PLANNING", "PLANNED":
            actionText = " added "
        default:
            actionText = " updated "
        }

        var actionPart = AttributedString(actionText)
        actionPart.font = .kuroCustom(15, weight: .light)
        result.append(actionPart)

        // Italic title
        var titlePart = AttributedString(entry.titleDisplay)
        titlePart.font = .kuroCustom(15, weight: .light, design: .serif).italic()
        result.append(titlePart)

        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            Circle()
                .fill(Color.kuroBlack08)
                .frame(width: 22, height: 22)
                .overlay(
                    Text(String(entry.displayName.prefix(1)).uppercased())
                        .font(.kuroCustom(9, weight: .medium, design: .serif, relativeTo: .caption2))
                        .foregroundColor(.kuroTextSecondary)
                )

            // Prose
            Text(proseText)
                .foregroundColor(.kuroBlack80)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Time
            Text(timeText)
                .font(.kuroMicro())
                .foregroundColor(.kuroTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }
}

// MARK: - Journal Pace Banner

struct JournalPaceBanner: View {
    let item: SupabaseService.ClubRailItem

    private var paceText: String {
        guard let myProgress = item.my_progress,
              let statuses = item.member_statuses, !statuses.isEmpty else { return "" }
        let otherProgresses = statuses.compactMap(\.progress).sorted()
        guard !otherProgresses.isEmpty else { return "" }
        let count = otherProgresses.count
        let median = count % 2 == 0
            ? (otherProgresses[count / 2 - 1] + otherProgresses[count / 2]) / 2
            : otherProgresses[count / 2]
        let diff = median - myProgress
        let unit = item.media_type.uppercased() == "ANIME" ? "episode" : "chapter"
        let plural = diff == 1 ? "" : "s"
        return "You're \(diff) \(unit)\(plural) behind the group on \(item.title_display)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(paceText)
                .font(.kuroBody())
                .italic()
                .foregroundColor(.kuroTextSecondary)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                .fill(Color.kuroBlack04)
        )
    }
}

// MARK: - Journal Milestone Card

struct JournalMilestoneCard: View {
    let item: SupabaseService.ClubRailItem
    let memberCount: Int

    var body: some View {
        VStack(spacing: KuroDesignSpacing.sm) {
            // Decorative rule
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.kuroBlack80)
                    .frame(width: 40, height: 2)
                Circle()
                    .fill(Color.kuroBlack80)
                    .frame(width: 4, height: 4)
                Rectangle()
                    .fill(Color.kuroBlack80)
                    .frame(width: 40, height: 2)
            }

            Text("All \(memberCount) members finished \(item.title_display)")
                .font(.kuroBody())
                .italic()
                .foregroundColor(.kuroBlack80)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text("COMPLETED TOGETHER")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KuroDesignSpacing.md)
    }
}

// MARK: - Journal Polls Content

struct JournalPollsContent: View {
    let bundle: SupabaseService.ClubBundle
    let clubsInteractionV2Enabled: Bool
    let voteInFlightPollIds: Set<String>
    let optimisticVoteByPollId: [String: String]
    let optimisticVoteCountsByPollId: [String: [String: Int]]
    let onVote: (SupabaseService.ClubPoll, String) -> Void
    let onCreatePoll: () -> Void
    let isConnected: Bool

    private var openPolls: [SupabaseService.ClubPoll] {
        bundle.polls.filter { !$0.is_closed }
    }

    private var closedPolls: [SupabaseService.ClubPoll] {
        bundle.polls.filter { $0.is_closed }
    }

    var body: some View {
        if bundle.polls.isEmpty {
            pollsEmptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                pollsList
            }
        }
    }

    private var pollsEmptyState: some View {
        ClubDetailEmptyStateCard(
            icon: "chart.bar",
            title: "No polls yet",
            message: "Questions and votes will appear here once the club starts asking them.",
            actionTitle: ["owner", "admin"].contains(bundle.my_role) ? "Ask a question" : nil,
            action: ["owner", "admin"].contains(bundle.my_role) ? {
                KuroAccessibility.impactHaptic(.light)
                onCreatePoll()
            } : nil
        )
        .disabled(!isConnected)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var pollsList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(openPolls.enumerated()), id: \.element.id) { index, poll in
                if index > 0 {
                    EditorialLayout.divider(thickness: 1.0, opacity: 0.06)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }

                JournalPollCard(
                    poll: poll,
                    members: bundle.members,
                    isSubmittingVote: clubsInteractionV2Enabled && voteInFlightPollIds.contains(poll.id),
                    optimisticMyVoteOptionId: clubsInteractionV2Enabled ? optimisticVoteByPollId[poll.id] : nil,
                    optimisticVoteCounts: clubsInteractionV2Enabled ? optimisticVoteCountsByPollId[poll.id] : nil,
                    onVote: { optionId in onVote(poll, optionId) }
                )
                .accessibilityElement(children: .combine)
            }

            if !closedPolls.isEmpty {
                Text("CLOSED")
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack30)
                    .padding(.horizontal, 20)
                    .padding(.top, KuroDesignSpacing.lg)
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
                    .opacity(0.5)
                    .accessibilityElement(children: .combine)
                }
            }

            // Create poll card
            if ["owner", "admin"].contains(bundle.my_role) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onCreatePoll()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.kuroCustom(20, weight: .light, relativeTo: .title3))
                            .foregroundColor(.kuroTextTertiary)
                        Text("ASK A QUESTION")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.5)
                            .foregroundColor(.kuroTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                            .foregroundColor(.kuroBlack10)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isConnected)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .padding(.top, KuroDesignSpacing.md)
        .padding(.bottom, KuroDesignSpacing.xxl)
    }

    private var sectionHeader: some View {
        ClubDetailSectionHeader(
            eyebrow: "Polls",
            title: "Club questions",
            detail: "Open polls stay up top, closed polls recede, and new questions sit at the end.",
            trailing: AnyView(
                ClubDetailSectionPill(
                    title: "\(openPolls.count)",
                    systemImage: "chart.bar",
                    isActive: !bundle.polls.isEmpty
                )
            )
        )
    }
}

// MARK: - Journal Poll Card

struct JournalPollCard: View {
    let poll: SupabaseService.ClubPoll
    let members: [SupabaseService.ClubMember]
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

    private var hasVoted: Bool {
        (optimisticMyVoteOptionId ?? poll.my_vote_option_id) != nil
    }

    private var askerInitial: String {
        let member = members.first { $0.user_id == poll.created_by }
        let name = member?.display_name ?? ""
        return String(name.prefix(1)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            // Asker label
            Text("\(askerInitial.isEmpty ? "?" : askerInitial) ASKED")
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroTextTertiary)

            // Question
            HStack {
                Text(poll.question)
                    .font(.kuroTitle())
                    .italic()
                    .foregroundColor(.kuroBlack80)
                    .lineLimit(3)

                Spacer()

                if poll.is_closed {
                    Text("CLOSED")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(.kuroBlack40)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .stroke(Color.kuroBlack12, lineWidth: 0.6)
                        )
                }
            }

            // Options
            ForEach(poll.options) { option in
                let renderedCount = optimisticVoteCounts?[option.id] ?? option.vote_count
                JournalPollOptionRow(
                    option: option,
                    displayVoteCount: renderedCount,
                    totalVotes: totalVotes,
                    isMyVote: (optimisticMyVoteOptionId ?? poll.my_vote_option_id) == option.id,
                    hasVoted: hasVoted,
                    isClosed: poll.is_closed,
                    isSubmittingVote: isSubmittingVote,
                    onTap: {
                        guard !poll.is_closed else { return }
                        guard (optimisticMyVoteOptionId ?? poll.my_vote_option_id) != option.id else { return }
                        guard !isSubmittingVote else { return }
                        onVote(option.id)
                    }
                )
            }

            if totalVotes > 0 {
                Text("\(totalVotes) vote\(totalVotes == 1 ? "" : "s")")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroTextTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - Journal Poll Option Row

struct JournalPollOptionRow: View {
    let option: SupabaseService.ClubPollOption
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

    private var percentageText: String {
        guard totalVotes > 0 else { return "" }
        return "\(Int(fraction * 100))%"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                HStack {
                    HStack(spacing: 5) {
                        if isMyVote {
                            Circle()
                                .fill(Color.kuroBlack80)
                                .frame(width: 5, height: 5)
                        }
                        Text(option.label)
                            .font(.kuroCaption())
                            .foregroundColor(.kuroTextSecondary)
                    }

                    Spacer()

                    if hasVoted || isClosed {
                        Text(percentageText)
                            .font(.kuroMicro(weight: .medium))
                            .foregroundColor(.kuroTextTertiary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .fill((hasVoted || isClosed) && isMyVote ? Color.kuroBlack04 : Color.clear)
                )

                // Fill bar
                if hasVoted || isClosed {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.kuroBlack06)
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(isMyVote ? Color.kuroBlack80 : Color.kuroBlack30)
                                .frame(width: geo.size.width * fraction, height: 3)
                                .animation(KuroAnimation.editorial, value: fraction)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isClosed || isSubmittingVote)
    }
}

// MARK: - Club Reaction Row

struct ClubReactionRow: View {
    let item: SupabaseService.ClubRailItem
    var onError: ((String) -> Void)? = nil

    @Environment(SupabaseService.self) private var supabaseService
    @State private var optimisticReactions: [String: Int]?
    @State private var optimisticMyReactions: Set<String>?

    private static let emojis = ["fire", "heart", "eyes", "100"]
    private static let emojiDisplay: [String: String] = [
        "fire": "\u{1F525}", "heart": "\u{2764}\u{FE0F}", "eyes": "\u{1F440}", "100": "\u{1F4AF}"
    ]

    private var effectiveReactions: [String: Int] {
        optimisticReactions ?? item.reactions ?? [:]
    }

    private var effectiveMyReactions: Set<String> {
        optimisticMyReactions ?? Set(item.my_reactions ?? [])
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.emojis, id: \.self) { emoji in
                let count = effectiveReactions[emoji] ?? 0
                let isMine = effectiveMyReactions.contains(emoji)
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    toggleReaction(emoji: emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(Self.emojiDisplay[emoji] ?? emoji)
                            .font(.kuroCustom(11, relativeTo: .caption1))
                        if count > 0 {
                            Text("\(count)")
                                .font(.kuroMicro(weight: .medium))
                                .foregroundColor(.kuroTextSecondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isMine ? Color.kuroBlack10 : Color.kuroBlack04)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(emoji), \(count) reaction\(count == 1 ? "" : "s")\(isMine ? ", reacted" : "")")
            }
        }
        .frame(width: 120, alignment: .leading)
    }

    private func toggleReaction(emoji: String) {
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

        Task {
            do {
                _ = try await supabaseService.toggleReaction(railItemId: item.id, emoji: emoji)
            } catch {
                optimisticReactions = nil
                optimisticMyReactions = nil
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                onError?("Couldn't update reaction")
            }
        }
    }
}

// MARK: - Club Reaction Row Compact (collapsed trigger for unreacted items)

struct ClubReactionRowCompact: View {
    let item: SupabaseService.ClubRailItem
    var onError: ((String) -> Void)? = nil
    @State private var expanded = false

    var body: some View {
        if expanded {
            ClubReactionRow(item: item, onError: onError)
        } else {
            Button {
                KuroAccessibility.impactHaptic(.light)
                withAnimation(KuroAnimation.fast) { expanded = true }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.kuroCustom(12, weight: .light, relativeTo: .caption1))
                    .foregroundColor(.kuroBlack30)
                    .padding(6)
                    .background(Capsule().fill(Color.kuroBlack04))
            }
            .buttonStyle(.plain)
            .frame(width: 120, alignment: .leading)
            .accessibilityLabel("Add a reaction")
        }
    }
}
