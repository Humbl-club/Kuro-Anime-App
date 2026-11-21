import SwiftUI

// MARK: - Airing today glance (Discover + Clubs redesign §6.2 item 4; Home grammar G§8.1)
// Home's glance-card anatomy, drawn here because `HomeComingUpGlance` is bound to `HomeGlanceSummary`:
// `HomeInk.glanceFill` #FFFEFA, radius 8, 1 pt `glanceBorder`, the near-invisible drop, padding 10/12
// (10/10 compact), min height 72. Title 14 semibold −0.3 over a 10 pt caption (two lines, so the next slot's time is never cut); three 27 × 38 thumbs
// (34 tall compact) overlapping by 7, hidden at accessibility sizes; the count (21 pt mono) over its
// 8 pt label; a "›" because the card opens the Airing today journey. The whole card is one button.

struct DiscoverGlanceCard: View {
    let title: String
    let caption: String?
    let thumbs: [URL?]
    let count: Int
    let countLabel: String
    let compact: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            action()
        } label: {
            HStack(alignment: .center, spacing: compact ? 8 : 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Circle()
                            .fill(Color.kuroControlInk)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.kuroCustom(14, weight: .semibold, relativeTo: .subheadline, maxSize: 28))
                            .tracking(-0.3)
                            .foregroundStyle(HomeInk.glanceInk)
                    }
                    if let caption {
                        Text(caption)
                            .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
                            .foregroundStyle(HomeInk.glanceMuted)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !thumbs.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: -7) {
                        ForEach(Array(thumbs.prefix(3).enumerated()), id: \.offset) { _, url in
                            HomeArtwork(url: url, maxPixelSize: 160, placeholder: HomeInk.posterFill)
                                .frame(width: 27, height: compact ? 34 : 38)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white, lineWidth: 1))
                                .shadow(color: Color.black.opacity(0.10), radius: 1, y: 1)
                        }
                    }
                    .padding(.trailing, 2)
                    .accessibilityHidden(true)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(count)")
                        .font(.kuroCustom(21, relativeTo: .title3, maxSize: 36))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(HomeInk.glanceInk)
                    Text(countLabel)
                        .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 16))
                        .foregroundStyle(HomeInk.glanceMuted)
                        .lineLimit(1)
                }
                .frame(minWidth: 39, alignment: .trailing)
                Text("›")
                    .font(.kuroCustom(16, relativeTo: .body, maxSize: 26))
                    .foregroundStyle(HomeInk.glanceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.kuroKeyRim, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, caption, "\(count) \(countLabel)"].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(KuroLocale.text("Opens the list", "Öffnet die Liste"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
