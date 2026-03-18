import SwiftUI
import PostgREST

// MARK: - Journal Status Bar

struct JournalStatusBar: View {
    let clubName: String
    let scrollOffset: CGFloat
    let heroHeight: CGFloat
    let safeTop: CGFloat
    let onBack: () -> Void
    let onSettings: () -> Void

    private var progress: CGFloat {
        min(1, max(0, (-scrollOffset - (heroHeight - 80)) / 40))
    }

    private var iconColor: Color {
        progress > 0.5 ? .kuroBlack80 : .kuroWhite
    }

    private var bgOpacity: Double {
        Double(progress) * 0.98
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.kuroWhite.opacity(bgOpacity)
                .frame(height: safeTop)

            statusBarContent

            if progress > 0.8 {
                EditorialLayout.divider(thickness: 1, opacity: 0.08 * Double(progress))
            }
        }
        .animation(KuroAnimation.fast, value: progress > 0.5)
    }

    private var statusBarContent: some View {
        HStack {
            backButton
            Spacer()
            titleLabel
            Spacer()
            settingsButton
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.kuroWhite.opacity(bgOpacity))
    }

    private var backButton: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.kuroBody(weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.kuroBlack.opacity(0.3 * (1 - Double(progress))))
                )
        }
        .accessibilityLabel("Back")
    }

    @ViewBuilder
    private var titleLabel: some View {
        if progress > 0.5 {
            Text(clubName)
                .font(.kuroNavigation(weight: .regular))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)
                .opacity(max(0, Double(progress - 0.5) * 2))
                .lineLimit(1)
        }
    }

    private var settingsButton: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            onSettings()
        } label: {
            Image(systemName: "ellipsis")
                .font(.kuroBody(weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.kuroBlack.opacity(0.3 * (1 - Double(progress))))
                )
        }
        .accessibilityLabel("Settings")
    }
}

// No color interpolation extension needed — using direct ternary in views.

// MARK: - Journal Hero Section

struct JournalHeroSection: View {
    let bundle: SupabaseService.ClubBundle
    let heroHeight: CGFloat
    let scrollOffset: CGFloat
    let containerWidth: CGFloat

    private var mosaicImageURLs: [URL] {
        bundle.rails
            .flatMap(\.items)
            .prefix(4)
            .compactMap { $0.cover_image_medium.flatMap(URL.init) }
    }

    private var stretch: CGFloat { max(scrollOffset, 0) }
    private var parallax: CGFloat { min(scrollOffset, 0) * 0.32 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Blurred mosaic background
            mosaicGrid
                .blur(radius: 20)
                .scaleEffect(1.15)
                .brightness(-0.35)
                .frame(width: containerWidth, height: heroHeight + stretch)
                .clipped()
                .offset(y: parallax - stretch)

            // Grain texture
            Rectangle()
                .fill(Color.kuroWhite04)
                .blendMode(.overlay)
                .frame(width: containerWidth, height: heroHeight + stretch)
                .allowsHitTesting(false)
                .offset(y: parallax - stretch)

            // Bottom gradient
            LinearGradient(
                colors: [
                    Color.kuroBlack65,
                    Color.kuroBlack25,
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 140)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            // Top gradient
            LinearGradient(
                colors: [
                    Color.kuroBlack35,
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 70)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Content overlay
            heroContent
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: containerWidth, height: heroHeight)
        .clipped()
    }

    @ViewBuilder
    private var mosaicGrid: some View {
        let urls = mosaicImageURLs
        let columns = [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)]

        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index < urls.count {
                    KuroCachedAsyncImage(url: urls[index], maxPixelSize: 200) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                .clipped()
                        default:
                            Rectangle()
                                .fill(Color.kuroBlack30)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: (heroHeight + stretch) / 2)
                } else {
                    Rectangle()
                        .fill(Color.kuroBlack30)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: (heroHeight + stretch) / 2)
                }
            }
        }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bundle.club.name)
                .font(.kuroFeature(weight: .light))
                .italic()
                .foregroundColor(.kuroWhite)
                .lineLimit(2)

            if let desc = bundle.club.description, !desc.isEmpty {
                Text(desc)
                    .font(.kuroBody())
                    .italic()
                    .foregroundColor(.kuroWhite60)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                // Member avatars
                HStack(spacing: -6) {
                    ForEach(Array(bundle.members.prefix(4).enumerated()), id: \.element.user_id) { _, member in
                        let initial = String((member.display_name ?? "?").prefix(1)).uppercased()
                        Circle()
                            .fill(Color.kuroWhite20)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text(initial)
                                    .font(.kuroMicro(weight: .medium))
                                    .foregroundColor(.kuroWhite90)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.kuroWhite80, lineWidth: 1)
                            )
                    }
                }

                Text("\(bundle.member_count) members")
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroWhite55)

                // Sharing level pill
                Text(bundle.club.sharing_level.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(0.5)
                    .foregroundColor(.kuroWhite60)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.kuroWhite15)
                    )
            }
        }
    }
}

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
            railsPopulatedContent
        }
    }

    private var railsEmptyState: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            Image(systemName: "list.bullet.rectangle")
                .font(.kuroCustom(24, weight: .light, relativeTo: .title2))
                .foregroundColor(.kuroBlack30)
            Text("No rails yet")
                .font(.kuroBody(weight: .light))
                .foregroundColor(.kuroBlack30)
            if ["owner", "admin"].contains(bundle.my_role) {
                Text("Create a rail to start curating together.")
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroBlack40)

                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onCreateRail()
                } label: {
                    Text("CREATE RAIL")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.kuroBlack70)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .stroke(Color.kuroBlack20, lineWidth: 0.8)
                        )
                }
                .disabled(!isConnected)
                .padding(.top, KuroDesignSpacing.sm)
            }
        }
        .padding(.top, KuroDesignSpacing.xxl)
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

    @ViewBuilder
    private var streamingAvailabilityControls: some View {
        if FeatureFlags.shared.isStreamingAvailabilityV1Enabled {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let sp = sharedProviders, !sp.shared_services.isEmpty {
                        Button {
                            onToggleShared()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.tv")
                                    .font(.kuroCustom(10, weight: .regular, relativeTo: .caption1))
                                Text("SHARED")
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                            }
                            .foregroundColor(showSharedAvailability ? .kuroBlack : .kuroBlack40)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(showSharedAvailability ? Color.kuroBlack10 : Color.kuroBlack04)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, KuroDesignSpacing.sm)

                if let sp = sharedProviders {
                    if sp.coverage_pct < 100 && sp.member_count_with_services > 0 {
                        Text("\(sp.member_count_with_services) of \(sp.member_count_total) members set up services")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroTextTertiary)
                            .padding(.horizontal, 20)
                    }
                    if userStreamingServicesEmpty {
                        Text("Set your services in Profile to unlock shared availability.")
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroTextTertiary)
                            .padding(.horizontal, 20)
                    }
                }
            }
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
            activityList
        }
    }

    private var emptyState: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            Image(systemName: "book")
                .font(.kuroCustom(24, weight: .light, relativeTo: .title2))
                .foregroundColor(.kuroBlack30)
            Text("No activity yet")
                .font(.kuroBody(weight: .light))
                .foregroundColor(.kuroBlack30)
            Text("Activity appears as members update their progress.")
                .font(.kuroCaption(weight: .light))
                .foregroundColor(.kuroBlack40)
                .multilineTextAlignment(.center)
        }
        .padding(.top, KuroDesignSpacing.xxl)
        .padding(.horizontal, 20)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
            pollsList
        }
    }

    private var pollsEmptyState: some View {
        VStack(spacing: KuroDesignSpacing.md) {
            Image(systemName: "chart.bar")
                .font(.kuroCustom(24, weight: .light, relativeTo: .title2))
                .foregroundColor(.kuroBlack30)
            Text("No polls yet")
                .font(.kuroBody(weight: .light))
                .foregroundColor(.kuroBlack30)
            if ["owner", "admin"].contains(bundle.my_role) {
                Button {
                    KuroAccessibility.impactHaptic(.light)
                    onCreatePoll()
                } label: {
                    Text("ASK A QUESTION")
                        .font(.kuroCaption(weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.kuroBlack70)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .stroke(Color.kuroBlack20, lineWidth: 0.8)
                        )
                }
                .disabled(!isConnected)
                .padding(.top, KuroDesignSpacing.sm)
            }
        }
        .padding(.top, KuroDesignSpacing.xxl)
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
        .padding(.horizontal, 20)
        .padding(.top, 20)
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

// MARK: - Journal Bottom Bar

struct JournalBottomBar: View {
    let role: String
    let isConnected: Bool
    let onAdd: () -> Void
    let onInvite: () -> Void
    let onPoll: () -> Void

    private var isAdminOrOwner: Bool {
        ["owner", "admin"].contains(role)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isAdminOrOwner {
                bottomBarButton(icon: "plus", label: "Add to rail", action: onAdd)
                bottomBarDivider()
            }

            bottomBarButton(icon: "person.badge.plus", label: "Invite members", action: onInvite)

            if isAdminOrOwner {
                bottomBarDivider()
                bottomBarButton(icon: "chart.bar", label: "Create poll", action: onPoll)
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 20)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.kuroBlack06, lineWidth: 0.7)
                )
                .shadow(color: Color.kuroBlack14, radius: 22, x: 0, y: 12)
                .shadow(color: Color.kuroWhite55, radius: 1, x: 0, y: 1)
        )
        .opacity(isConnected ? 1.0 : 0.5)
        .disabled(!isConnected)
        .frame(maxWidth: 200)
    }

    private func bottomBarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.kuroCustom(18, weight: .regular, relativeTo: .title3))
                .foregroundColor(.kuroTextSecondary)
                .frame(width: 44, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func bottomBarDivider() -> some View {
        Rectangle()
            .fill(Color.kuroBlack08)
            .frame(width: 1, height: 20)
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

// MARK: - Add Item to Rail Sheet

struct AddItemToRailSheet: View {
    let railId: String
    let clubId: String
    let onAdded: () -> Void

    @Environment(SupabaseService.self) private var supabaseService
    @Environment(\.dismiss) private var dismiss

    enum MediaTab: String, CaseIterable {
        case anime = "ANIME"
        case manga = "MANGA"
    }

    @State private var selectedMedia: MediaTab = .anime
    @State private var searchText = ""
    @State private var animeResults: [AnimeCard] = []
    @State private var mangaResults: [MangaCard] = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Media type toggle
                Picker("Type", selection: $selectedMedia) {
                    ForEach(MediaTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, KuroDesignSpacing.sm)

                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.kuroCustom(14, weight: .regular, relativeTo: .body))
                        .foregroundColor(.kuroBlack35)
                    TextField("Search titles...", text: $searchText)
                        .font(.kuroBody(weight: .light))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                        .fill(Color.kuroBlack04)
                )
                .padding(.horizontal, 20)

                EditorialLayout.divider()
                    .padding(.top, KuroDesignSpacing.sm)

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.top, KuroDesignSpacing.sm)
                }

                // Results
                if isAdding {
                    VStack(spacing: KuroDesignSpacing.md) {
                        ProgressView()
                            .scaleEffect(0.9)
                            .tint(.kuroBlack60)
                        Text("Adding...")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroBlack60)
                    }
                    .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if isSearching && animeResults.isEmpty && mangaResults.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.kuroTextTertiary)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: KuroDesignSpacing.sm) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.kuroCustom(20, weight: .light, relativeTo: .title3))
                            .foregroundColor(.kuroBlack30)
                        Text("Type to search")
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroBlack30)
                    }
                    .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if selectedMedia == .anime && animeResults.isEmpty && !isSearching {
                    Text("No anime found")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack30)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else if selectedMedia == .manga && mangaResults.isEmpty && !isSearching {
                    Text("No manga found")
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroBlack30)
                        .padding(.top, KuroDesignSpacing.xxl)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if selectedMedia == .anime {
                                ForEach(animeResults) { card in
                                    RailSearchResultRow(
                                        title: card.title,
                                        imageURL: card.coverImageMedium,
                                        year: card.year,
                                        format: card.format
                                    ) {
                                        addItem(mediaType: "ANIME", mediaId: card.id)
                                    }
                                }
                            } else {
                                ForEach(mangaResults) { card in
                                    RailSearchResultRow(
                                        title: card.title,
                                        imageURL: card.coverImageMedium,
                                        year: card.year,
                                        format: card.format
                                    ) {
                                        addItem(mediaType: "MANGA", mediaId: card.id)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, KuroDesignSpacing.xxl)
                    }
                }
            }
            .background(Color.kuroBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADD ITEM")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.kuroBody(weight: .light))
                }
            }
            .onChange(of: searchText) { _, _ in
                debouncedSearch()
            }
            .onChange(of: selectedMedia) { _, _ in
                debouncedSearch()
            }
            .onDisappear {
                searchTask?.cancel()
                searchTask = nil
            }
        }
    }

    private func debouncedSearch() {
        searchTask?.cancel()
        errorMessage = nil
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            animeResults = []
            mangaResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        do {
            if selectedMedia == .anime {
                animeResults = try await supabaseService.fetchSearchAnimePage(
                    query: query, filters: nil, cursorRank: nil,
                    cursorPopularity: nil, cursorId: nil, limit: 20
                )
            } else {
                mangaResults = try await supabaseService.fetchSearchMangaPage(
                    query: query, filters: nil, cursorRank: nil,
                    cursorPopularity: nil, cursorId: nil, limit: 20
                )
            }
        } catch {
            if !Task.isCancelled {
                // Clear stale results so old rows aren't actionable
                if selectedMedia == .anime { animeResults = [] } else { mangaResults = [] }
                errorMessage = "Search failed. Check your connection and try again."
                #if DEBUG
                print("[ClubDetail] AddItemToRailSheet search: \(error)")
                #endif
            }
        }
        if !Task.isCancelled {
            isSearching = false
        }
    }

    private func addItem(mediaType: String, mediaId: Int) {
        guard !isAdding else { return }
        isAdding = true
        errorMessage = nil
        Task {
            do {
                _ = try await supabaseService.addRailItem(
                    railId: railId, mediaType: mediaType, mediaId: mediaId
                )
                KuroAccessibility.successHaptic()
                onAdded()
                dismiss()
            } catch let pgError as PostgrestError {
                // Decode structured RPC error fields (details/code/hint) from add_club_rail_item.
                errorMessage = Self.mapRailItemError(pgError)
                KuroAccessibility.errorHaptic()
                isAdding = false
            } catch {
                errorMessage = "Could not add item. Please try again."
                KuroAccessibility.errorHaptic()
                isAdding = false
            }
        }
    }

    private enum AddRailItemErrorCode: String {
        case duplicateItem = "DUPLICATE_ITEM"
        case notAMember = "NOT_A_MEMBER"
        case railLocked = "RAIL_LOCKED"
        case mediaNotFound = "MEDIA_NOT_FOUND"
        case invalidMediaType = "INVALID_MEDIA_TYPE"
        case unauthenticated = "UNAUTHENTICATED"
        case noteTooLong = "NOTE_TOO_LONG"
        case railNotFound = "RAIL_NOT_FOUND"
    }

    /// Maps a structured PostgrestError from add_club_rail_item RPC to a user-facing string.
    private static func mapRailItemError(_ error: PostgrestError) -> String {
        let detailsCode = error.detail.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let hintCode = error.hint.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let structuredCode =
            detailsCode.flatMap(AddRailItemErrorCode.init(rawValue:)) ??
            hintCode.flatMap(AddRailItemErrorCode.init(rawValue:))

        switch structuredCode {
        case .duplicateItem:
            return "This title is already in this rail."
        case .notAMember:
            return "You're no longer a member of this club."
        case .railLocked:
            return "This rail is locked. Only admins can add items."
        case .mediaNotFound:
            return "This title was not found in the catalog."
        case .invalidMediaType:
            return "Invalid media type."
        case .unauthenticated:
            return "Please sign in again to continue."
        case .noteTooLong:
            return "Note is too long. Keep it under 280 characters."
        case .railNotFound:
            return "This rail is no longer available."
        case nil:
            // Fallback to SQLSTATE for environments that haven't picked up structured detail codes yet.
            if error.code == "23505" {
                return "This title is already in this rail."
            }
            return "Could not add item. Please try again."
        }
    }
}

struct RailSearchResultRow: View {
    let title: String
    let imageURL: String?
    let year: String
    let format: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                KuroCachedAsyncImage(url: URL(string: imageURL ?? ""), maxPixelSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 56)
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.kuroBlack06)
                            .frame(width: 40, height: 56)
                    }
                }
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.kuroBlack85)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(year)
                            .font(.kuroCaption(weight: .light))
                            .foregroundColor(.kuroTextTertiary)
                        if let format, !format.isEmpty {
                            Text(format.lowercased())
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroTextTertiary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.kuroCustom(20, weight: .light, relativeTo: .title3))
                    .foregroundColor(.kuroBlack35)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Club Settings Sheet

struct ClubSettingsSheet: View {
    let bundle: SupabaseService.ClubBundle
    let clubId: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseService.self) private var supabaseService

    @State private var isLeaving = false
    @State private var showLeaveConfirm = false
    @State private var leaveConfirmMessage = ""
    @State private var leaveErrorText: String? = nil

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                    // Club Info
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("CLUB INFO")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.kuroBlack30)
                            .accessibilityAddTraits(.isHeader)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(bundle.club.name)
                                .font(.kuroHeadline(weight: .light))
                                .foregroundColor(.kuroBlack80)

                            if let desc = bundle.club.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.kuroBody(weight: .light))
                                    .foregroundColor(.kuroBlack60)
                            }

                            HStack(spacing: 12) {
                                Label("\(bundle.member_count) members", systemImage: "person.2")
                                    .font(.kuroCaption(weight: .light))
                                    .foregroundColor(.kuroBlack60)

                                Text(bundle.club.sharing_level.uppercased())
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                                    .foregroundColor(.kuroBlack60)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().stroke(Color.kuroBlack12, lineWidth: 0.6)
                                    )
                            }

                            Text(sharingLevelDescription)
                                .font(.kuroCaption(weight: .light))
                                .foregroundColor(.kuroBlack30)
                        }
                    }

                    EditorialLayout.divider()

                    // Invite Code (owner/admin only)
                    if let code = bundle.club.invite_code {
                        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                            Text("INVITE CODE")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                                .foregroundColor(.kuroBlack30)
                                .accessibilityAddTraits(.isHeader)

                            HStack(spacing: 12) {
                                Text(code)
                                    .font(.kuroCustom(20, weight: .medium, design: .monospaced, relativeTo: .title3))
                                    .tracking(2.0)
                                    .foregroundColor(.kuroBlack80)

                                Button {
                                    UIPasteboard.general.string = code
                                    KuroAccessibility.successHaptic()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.kuroCustom(14, weight: .regular, relativeTo: .body))
                                        .foregroundColor(.kuroBlack60)
                                }
                                .buttonStyle(.plain)
                            }

                            ShareLink(
                                item: "Join my club \"\(bundle.club.name)\" on Kuro! Enter invite code: \(code)",
                                subject: Text("Join \(bundle.club.name) on Kuro"),
                                message: Text("Use this invite code to join: \(code)")
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.kuroCustom(13, weight: .regular, relativeTo: .caption1))
                                    Text("SHARE INVITE")
                                        .font(.kuroCaption(weight: .medium))
                                        .tracking(1.6)
                                }
                                .foregroundColor(.kuroBlack80)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                        .stroke(Color.kuroBlack15, lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        EditorialLayout.divider()
                    }

                    // Members
                    VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                        Text("MEMBERS")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.kuroBlack30)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(Array(bundle.members.enumerated()), id: \.element.user_id) { index, member in
                            let label = memberDisplayName(member, index: index)
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.kuroBlack06)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Text(String(label.prefix(1)).uppercased())
                                            .font(.kuroMicro(weight: .medium))
                                            .foregroundColor(.kuroBlack60)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(label)
                                            .font(.kuroCaption(weight: .medium))
                                            .foregroundColor(.kuroBlack80)

                                        if member.user_id == supabaseService.currentUserId {
                                            Text("YOU")
                                                .font(.kuroMicro(weight: .medium))
                                                .tracking(1.0)
                                                .foregroundColor(.kuroBlack45)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule().stroke(Color.kuroBlack10, lineWidth: 0.6)
                                                )
                                        }
                                    }

                                    Text(joinedLabel(member.joined_at))
                                        .font(.kuroMicro())
                                        .foregroundColor(.kuroBlack30)
                                }

                                Spacer()

                                Text(member.role.uppercased())
                                    .font(.kuroMicro(weight: .medium))
                                    .tracking(1.0)
                                    .foregroundColor(member.role == "owner" ? .kuroBlack80 : .kuroTextTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().stroke(
                                            member.role == "owner" ? Color.kuroBlack20 : Color.kuroBlack08,
                                            lineWidth: 0.6
                                        )
                                    )
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    EditorialLayout.divider()

                    // Leave Club
                    if let leaveErrorText {
                        Text(leaveErrorText)
                            .font(.kuroCaption())
                            .foregroundColor(.red.opacity(0.85))
                    }

                    Button {
                        leaveConfirmMessage = computeLeaveMessage()
                        showLeaveConfirm = true
                    } label: {
                        HStack(spacing: 10) {
                            if isLeaving {
                                ProgressView().scaleEffect(0.8).tint(.red.opacity(0.85))
                            }
                            Text("LEAVE CLUB")
                                .font(.kuroCaption(weight: .medium))
                                .tracking(1.6)
                        }
                        .foregroundColor(.red.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: KuroRadius.sm, style: .continuous)
                                .stroke(Color.red.opacity(0.25), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLeaving)
                    .alert("Leave Club?", isPresented: $showLeaveConfirm) {
                        Button("Leave", role: .destructive) { leaveClub() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text(leaveConfirmMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, KuroDesignSpacing.md)
                .padding(.bottom, KuroDesignSpacing.xxl)
            }
            .background(Color.kuroBackground)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.kuroNavigation(weight: .regular))
                        .tracking(1.5)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .font(.kuroBody(weight: .light))
                }
            }
        }
    }

    private var sharingLevelDescription: String {
        switch bundle.club.sharing_level {
        case "private": return "Only aggregates. Members can't see each other's data."
        case "status": return "Members can see watch/read status but not progress numbers."
        case "progress": return "Members can see full progress, status, and ratings."
        default: return ""
        }
    }

    private func computeLeaveMessage() -> String {
        guard bundle.my_role == "owner" else {
            return "Leave \(bundle.club.name)? You'll need a new invite code to rejoin."
        }
        // Owner leaving: check for successor
        let others = bundle.members.filter { $0.role != "owner" }
        if others.isEmpty {
            return "You're the only member. This club will be deleted."
        }
        // Promote oldest admin, else oldest member
        let admins = others.filter { $0.role == "admin" }.sorted { $0.joined_at < $1.joined_at }
        if let successor = admins.first {
            return "Ownership will transfer to member \(String(successor.user_id.prefix(8)))... You'll need a new invite code to rejoin."
        }
        let sorted = others.sorted { $0.joined_at < $1.joined_at }
        if let successor = sorted.first {
            return "Ownership will transfer to member \(String(successor.user_id.prefix(8)))... You'll need a new invite code to rejoin."
        }
        return "You'll need a new invite code to rejoin."
    }

    private func leaveClub() {
        isLeaving = true
        leaveErrorText = nil
        Task {
            do {
                try await supabaseService.leaveClub(clubId: clubId)
                KuroAccessibility.successHaptic()
                dismiss()
            } catch {
                if leaveErrorCode(from: error) == .notAMember {
                    leaveErrorText = "You're no longer a member of this club."
                } else {
                    leaveErrorText = "Could not leave club. Please try again."
                }
                KuroAccessibility.errorHaptic()
            }
            isLeaving = false
        }
    }

    private enum LeaveErrorCode: String {
        case notAMember = "NOT_A_MEMBER"
    }

    private func leaveErrorCode(from error: Error) -> LeaveErrorCode? {
        guard let pgError = error as? PostgrestError else { return nil }
        let candidates = [pgError.detail, pgError.hint, pgError.message]
        for raw in candidates {
            guard let raw else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let token = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let mapped = LeaveErrorCode(rawValue: normalized) { return mapped }
        }
        return nil
    }

    private func memberDisplayName(_ member: SupabaseService.ClubMember, index: Int) -> String {
        let trimmed = member.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        // Stable short identifier from UUID (consistent across sessions)
        let compact = member.user_id.replacingOccurrences(of: "-", with: "")
        let short = String(compact.prefix(6))
        return short.isEmpty ? "Unknown" : short
    }

    private func joinedLabel(_ raw: String) -> String {
        guard let date = Self.isoWithFractional.date(from: raw) ?? Self.iso.date(from: raw) else {
            return "Joined recently"
        }
        return "Joined \(Self.relFormatter.localizedString(for: date, relativeTo: Date()))"
    }
}
