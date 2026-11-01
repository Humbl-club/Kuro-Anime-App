import SwiftUI

// MARK: - Provider links (detail pages)
// The watch/read provider presentation shared by the Anime and Manga action bars: the provider
// selection sheet with its explainer and link cards, and the provider brand mark. Which items a page
// shows is resolved by the ProviderAvailability owner as one `ProviderLinkSnapshot`
// (ProviderAvailabilityStore+DetailLinks.swift) from the pure builders in
// Kuro/Providers/ProviderLinkBuilders.swift; the views only render it.

struct ProviderSelectionSheet: View {
    let title: String
    let links: [ProviderSheetItem]
    let statusCaption: String?
    let onSelect: (ProviderSheetItem) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isVerifiedOnly: Bool {
        !links.isEmpty && links.allSatisfy(\.isVerified)
    }

    private var explainerTitle: String {
        if links.isEmpty { return "No legal links yet" }
        return isVerifiedOnly ? "Verified for this title" : "Catalog fallback"
    }

    private var explainerBody: String {
        if links.isEmpty { return "We do not have a legal provider link for this title yet." }
        return isVerifiedOnly
            ? "These providers are matched to this title directly. Language and subtitle options can still vary by region."
            : "These are legal catalog links from the provider directory. Title-specific availability may still vary by region."
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: KuroSpacing.lg) {
                    ProviderSelectionExplainerCard(
                        title: explainerTitle,
                        message: explainerBody,
                        linkCount: links.count,
                        isVerifiedOnly: isVerifiedOnly,
                        statusCaption: statusCaption
                    )

                    VStack(spacing: KuroSpacing.sm) {
                        ForEach(links) { link in
                            Button(action: {
                                onSelect(link)
                                dismiss()
                            }) {
                                ProviderSelectionLinkCard(link: link)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, ResponsiveLayout.padding())
                .padding(.top, KuroSpacing.md)
                .padding(.bottom, KuroSpacing.xl)
            }
            .background(Color.kuroBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.kuroMicro(weight: .medium))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ProviderSelectionExplainerCard: View {
    let title: String
    let message: String
    let linkCount: Int
    let isVerifiedOnly: Bool
    let statusCaption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isVerifiedOnly ? "checkmark.seal.fill" : "rectangle.stack.fill")
                    .font(.kuroCustom(12, weight: .semibold, maxSize: 19))
                    .foregroundColor(isVerifiedOnly ? .kuroBlack : .kuroBlack60)
                Text(title.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)
                Spacer(minLength: KuroSpacing.md)
                if linkCount > 0 {
                    Text("\(linkCount) \(linkCount == 1 ? "LINK" : "LINKS")")
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(.kuroBlack60)
                }
            }

            Text(message)
                .font(.kuroMicro(weight: .light))
                .foregroundColor(.kuroBlack60)
                .fixedSize(horizontal: false, vertical: true)

            if let statusCaption, !statusCaption.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.kuroCustom(10, weight: .semibold, maxSize: 16))
                        .foregroundColor(.kuroBlack30)
                    Text(statusCaption)
                        .font(.kuroMicro(weight: .medium))
                        .foregroundColor(.kuroBlack60)
                }
            }
        }
        .padding(KuroSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(Color.kuroBlack05)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.kuroBlack08, lineWidth: 0.8)
                )
        )
    }
}

private struct ProviderSelectionLinkCard: View {
    let link: ProviderSheetItem

    var body: some View {
        HStack(alignment: .top, spacing: KuroSpacing.md) {
            ProviderBrandMark(
                providerTitle: link.title,
                fallbackSystemImage: link.isVerified ? "play.fill" : "link",
                size: 42,
                isAvailable: true
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(link.title)
                        .font(.kuroBody(weight: .regular))
                        .foregroundColor(.kuroBlack)
                    Spacer(minLength: KuroSpacing.sm)
                    Text(link.badgeText.uppercased())
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(link.isVerified ? .kuroBlack : .kuroBlack60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(link.isVerified ? Color.kuroBlack08 : Color.kuroBlack05)
                        )
                }

                if let subtitle = link.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: KuroSpacing.md)

            VStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.kuroCustom(12, weight: .semibold, maxSize: 19))
                    .foregroundColor(.kuroBlack30)
                Text("OPEN")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(0.8)
                    .foregroundColor(.kuroBlack60)
            }
            .padding(.top, 2)
        }
        .padding(KuroSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(link.isVerified ? Color.kuroBackground : Color.kuroBlack04)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.kuroBlack08, lineWidth: 1)
                )
        )
    }
}

private struct ProviderBrandPalette {
    let label: String
    let background: Color
    let foreground: Color
}

private struct ProviderBrandMark: View {
    let providerTitle: String?
    let fallbackSystemImage: String
    let size: CGFloat
    let isAvailable: Bool

    private var palette: ProviderBrandPalette? {
        providerTitle.map(providerBrandPalette(for:))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette?.background ?? (isAvailable ? Color.kuroBlack08 : Color.kuroBlack05))
                .frame(minWidth: palette == nil ? size : 64, minHeight: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke((palette?.foreground ?? .kuroBlack30).opacity(0.14), lineWidth: 0.8)
                )

            if let palette {
                Text(palette.label)
                    .font(.kuroCustom(10, weight: .semibold, design: .rounded, maxSize: 16))
                    .tracking(0.2)
                    .foregroundColor(palette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.kuroCustom(14, weight: .semibold, maxSize: 22))
                    .foregroundColor(isAvailable ? .kuroBlack : .kuroBlack30)
            }
        }
    }
}

private func providerBrandPalette(for title: String) -> ProviderBrandPalette {
    let normalized = normalizedProviderKey(title)
    switch normalized {
    case "crunchyroll":
        return .init(label: "Crunchyroll", background: Color.orange.opacity(0.18), foreground: Color.orange)
    case "netflix":
        return .init(label: "Netflix", background: Color.red.opacity(0.16), foreground: Color.red)
    case "amazon prime video", "prime video":
        return .init(label: "Prime", background: Color.blue.opacity(0.16), foreground: Color.blue)
    case "hulu":
        return .init(label: "Hulu", background: Color.green.opacity(0.16), foreground: Color.green)
    case "youtube":
        return .init(label: "YouTube", background: Color.red.opacity(0.14), foreground: Color.red)
    case "disney plus", "disneyplus":
        return .init(label: "Disney+", background: Color.cyan.opacity(0.16), foreground: Color.blue)
    default:
        let letters = title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        return .init(
            label: letters.isEmpty ? "PL" : letters,
            background: Color.kuroBlack08,
            foreground: .kuroBlack80
        )
    }
}
