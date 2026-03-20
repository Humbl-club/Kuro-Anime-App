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

    private var buttonBackgroundOpacity: Double {
        0.14 + (Double(progress) * 0.78)
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
                .background(statusButtonBackground)
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
                .background(statusButtonBackground)
        }
        .accessibilityLabel("Settings")
    }

    private var statusButtonBackground: some View {
        Circle()
            .fill(progress > 0.45 ? Color.kuroWhite.opacity(buttonBackgroundOpacity) : Color.kuroBlack.opacity(0.22))
            .overlay(
                Circle()
                    .stroke(
                        progress > 0.45 ? Color.kuroBlack.opacity(0.05) : Color.kuroWhite.opacity(0.14),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(progress > 0.45 ? 0.05 : 0.12), radius: 10, x: 0, y: 4)
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
    private var openPollCount: Int { bundle.polls.filter { !$0.is_closed }.count }

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                heroMetaPill(title: bundle.club.sharing_level.uppercased(), systemImage: "person.3.sequence.fill")
                heroMetaPill(title: "\(bundle.member_count) MEMBERS", systemImage: "person.2.fill")
            }

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
                        .lineLimit(2)
                        .lineSpacing(2)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: -6) {
                    ForEach(Array(bundle.members.prefix(4).enumerated()), id: \.element.user_id) { _, member in
                        let initial = String((member.display_name ?? "?").prefix(1)).uppercased()
                        Circle()
                            .fill(Color.kuroWhite20)
                            .frame(width: 24, height: 24)
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

                Text(heroSummaryText)
                    .font(.kuroMicro(weight: .medium))
                    .tracking(0.6)
                    .foregroundColor(.kuroWhite60)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.kuroBlack.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.kuroWhite.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var heroSummaryText: String {
        var parts = ["\(bundle.rails.count) rail\(bundle.rails.count == 1 ? "" : "s")"]
        if openPollCount > 0 {
            parts.append("\(openPollCount) open poll\(openPollCount == 1 ? "" : "s")")
        } else if !bundle.polls.isEmpty {
            parts.append("\(bundle.polls.count) poll\(bundle.polls.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " • ")
    }

    private func heroMetaPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.0)
        }
        .foregroundColor(.kuroWhite80)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.kuroWhite.opacity(0.14))
        )
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
        .frame(maxWidth: isAdminOrOwner ? 220 : 160)
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
