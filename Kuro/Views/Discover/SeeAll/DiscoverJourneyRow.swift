import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - One See all / mood journey row (spec 2026-11-04 §5.4.5, §5.5.6)
// `DiscoverIndexRow`'s grammar without the number: Home's quiet row (min height 76), the 40 × 60 cover
// (radius 2), the title (15 pt medium −0.2, two lines) over "{year} · {format} · {n} eps" and, for a
// title on the list, its status word; then the leaf Plan key (≥ 96 pt, 84 compact) that stamps after
// the durable save. A 0.5 pt hairline under it. Tapping the row pushes the title inside the journey
// (N9, N5); long press is the Discover preview and menu (`discoverTitleMenu`), whose actions are also
// VoiceOver custom actions on the row. At accessibility sizes the key moves under the title.

struct DiscoverJourneyRow: View {
    let card: TasteCard
    /// The status word to show (the list's "mark" rule; nil: not on the list, or a "hide" list).
    let ownedStatus: ListStatus?
    let compact: Bool
    let menu: DiscoverMenuItem
    /// "ANIME" / "MANGA" over the title (mixed lists only, §5.11).
    var showsKind: Bool = false

    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(InteractionTelemetry.self) private var telemetry: InteractionTelemetry?

    private var german: Bool { KuroLocale.isGerman }

    private var meta: String? {
        var parts: [String] = []
        if let facts = DiscoverIssueCopy.facts(kind: card.media.kind, year: card.media.year, formatRaw: card.media.formatRaw,
                                               episodes: card.media.episodes, chapters: card.media.chapters,
                                               length: true, german: german) {
            parts.append(facts)
        }
        if let ownedStatus {
            parts.append(DiscoverMenuCopy.statusWord(ownedStatus, medium: card.media.kind, german: german))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    openButton
                    key.padding(.leading, 52)
                }
                .padding(.vertical, 10)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    openButton
                    DiscoverAtLeastWidth(minimum: DiscoverIssueLayout.indexKeyWidth(compact: compact)) { key }
                }
                .frame(minHeight: DiscoverIssueLayout.indexRowMinHeight)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 0.5).accessibilityHidden(true)
        }
    }

    private var key: some View {
        TastePlanKey(card: card, variant: .leaf, compact: true, stampsOnConfirm: true)
    }

    private var openButton: some View {
        let meta = meta
        return Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            telemetry?.trackInteractionEvent(
                "discover_open", surface: menu.surface, result: "opened",
                extra: DiscoverMenuTelemetry.titleExtra(section: menu.section, position: menu.position, key: card.key)
                    .merging(["via": "card"]) { _, new in new })
            routes.openMedia(MediaRoute(card.key))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                HomeArtwork(url: card.media.imageURL.flatMap { URL(string: $0) }, maxPixelSize: 160,
                            placeholder: HomeInk.posterFill)
                    .frame(width: 40, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                VStack(alignment: .leading, spacing: 3) {
                    if showsKind {
                        Text(DiscoverMenuCopy.kindKicker(card.media.kind))
                            .font(.kuroCustom(8, weight: .semibold, relativeTo: .caption2, maxSize: 16))
                            .tracking(1.05)
                            .foregroundStyle(Color.kuroMuted)
                    }
                    Text(KuroCardText.sanitizeTitleForCard(card.media.title))
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .subheadline, maxSize: 30))
                        .tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        Text(meta)
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(Color.kuroMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenLabel(meta: meta)))
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .discoverTitleMenu(menu)
    }

    private func spokenLabel(meta: String?) -> String {
        let title = showsKind ? DiscoverMenuCopy.kindPrefixed(card.media.title, kind: card.media.kind) : card.media.title
        return [title, meta].compactMap { $0 }.joined(separator: ", ")
    }
}
