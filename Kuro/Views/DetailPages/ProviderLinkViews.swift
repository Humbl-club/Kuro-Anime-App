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
        if links.isEmpty { return KuroLocale.text("No legal links yet", "Noch keine legalen Links") }
        return isVerifiedOnly
            ? KuroLocale.text("Matched to this title", "Zu diesem Titel passend")
            : KuroLocale.text("From the provider's catalogue", "Aus dem Katalog des Anbieters")
    }

    private var explainerBody: String {
        if links.isEmpty {
            return KuroLocale.text("There's no legal link for this title yet.", "Für diesen Titel gibt es noch keinen legalen Link.")
        }
        return isVerifiedOnly
            ? KuroLocale.text(
                "These providers carry this title. Language and subtitles may vary by region.",
                "Diese Anbieter führen den Titel. Sprache und Untertitel können je nach Region abweichen.")
            : KuroLocale.text(
                "Legal links from each provider's catalogue. Whether this title is there may vary by region.",
                "Legale Links aus den Katalogen der Anbieter. Ob der Titel dort verfügbar ist, kann je nach Region abweichen.")
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
                            .buttonStyle(KuroPressStyle())
                            .accessibilityLabel(link.accessibilityLabel)
                        }
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroSpacing.md)
                .padding(.bottom, KuroSpacing.xl)
            }
            .background(Color.kuroBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DetailSheetCloseButton { dismiss() }
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
                Text(title)
                    .font(.kuroMeta(weight: .medium))
                    .foregroundColor(.kuroBlack80)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: KuroSpacing.md)
                if linkCount > 0 {
                    Text(linkCount == 1
                         ? KuroLocale.text("1 link", "1 Link")
                         : KuroLocale.text("\(linkCount) links", "\(linkCount) Links"))
                        .font(.kuroMeta())
                        .foregroundColor(.kuroBlack60)
                }
            }

            Text(message)
                .font(.kuroMeta(weight: .light))
                .foregroundColor(.kuroBlack60)
                .fixedSize(horizontal: false, vertical: true)

            if let statusCaption, !statusCaption.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.kuroCustom(10, weight: .semibold, maxSize: 16))
                        .foregroundColor(.kuroInkQuiet)
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
                    Text(link.badgeText)
                        .font(.kuroCaption(weight: .medium))
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
                    .foregroundColor(.kuroInkQuiet)
                Text(KuroLocale.text("Open", "Öffnen"))
                    .font(.kuroCaption(weight: .medium))
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

/// A provider's short name for its chip; brand colours are not used (monochrome, rulebook §13.2).
private func providerChipLabel(for title: String) -> String {
    switch normalizedProviderKey(title) {
    case "crunchyroll": return "Crunchyroll"
    case "netflix": return "Netflix"
    case "amazon prime video", "prime video": return "Prime"
    case "hulu": return "Hulu"
    case "youtube": return "YouTube"
    case "disney plus", "disneyplus": return "Disney+"
    default:
        let letters = title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        return letters
    }
}

/// The provider chip: a neutral quiet-canvas tile with the provider's name in ink (no brand palette),
/// or a symbol when the title gives no letters.
private struct ProviderBrandMark: View {
    let providerTitle: String?
    let fallbackSystemImage: String
    let size: CGFloat
    let isAvailable: Bool

    private var label: String? {
        guard let providerTitle else { return nil }
        let label = providerChipLabel(for: providerTitle)
        return label.isEmpty ? nil : label
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                .fill(Color.kuroCanvasQuiet)
                .frame(minWidth: label == nil ? size : 64, minHeight: size)
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.md, style: .continuous)
                        .stroke(Color.kuroBlack08, lineWidth: 0.8)
                )

            if let label {
                Text(label)
                    .font(.kuroCaption(weight: .semibold))
                    .foregroundColor(.kuroInk)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.kuroCustom(14, weight: .semibold, maxSize: 22))
                    .foregroundColor(isAvailable ? .kuroInk : .kuroInkQuiet)
            }
        }
        .accessibilityHidden(true)
    }
}
