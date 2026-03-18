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
