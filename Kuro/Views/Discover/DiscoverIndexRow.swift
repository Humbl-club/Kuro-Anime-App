import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Numbered index (Discover + Clubs redesign §6.2 items 7 and 13)
// Essential anime / Essential manga and Classics: the section heading with its purpose line (and the
// Essentials progress hook), five rows (three on the All issue: the shipped owner decision wins over
// the usability spec's drawn five), then "See all {n} ›". A row is Home's quiet row with its minimum height raised to 76: the curated
// number ("01", 13 pt medium mono, `kuroMuted`, a 22 pt column), the 40 × 60 cover (radius 2), the
// title (15 pt medium −0.2, two lines) over "{status} · {year} · {format} · {n} eps" (the Folio status
// word when the title is on the list, usability R2), then the leaf `TastePlanKey`
// (at least 96 pt wide, 84 compact), and a 0.5 pt `kuroHairline` under it. The number is the curated
// order, never a rank. At accessibility sizes the key moves under the title.

struct DiscoverIndexSection: View {
    let anchor: String
    let title: String
    let purpose: String?
    var newMarker: String? = nil
    /// The section's titles still on the page, in claim order (a hide refills from the reserve).
    let cards: [TasteCard]
    /// What "See all {n}" counts (after dedupe and hiding).
    let total: Int
    let column: CGFloat
    /// The Essentials progress hook (§5.9), under the purpose line.
    var hook: DiscoverProgressModel? = nil
    var hookIsManga = false
    /// Rows shown before "See all" (`DiscoverIssueLayout.indexRows(onAll:)`).
    var rowLimit: Int = DiscoverIssueLayout.indexRows
    let onSeeAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        let rows = Array(cards.prefix(rowLimit))
        let motion = KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: 0) {
            DiscoverSectionHeader(title: title, purpose: purpose, newMarker: newMarker, compact: compact)
                .padding(.bottom, purpose == nil ? DiscoverIssueLayout.headingToContent - 6 : 0)
            if let hook, hook.shows {
                DiscoverProgressHook(model: hook, manga: hookIsManga)
                    .padding(.bottom, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, card in
                DiscoverIndexRow(position: index + 1, card: card, compact: compact)
                    .transition(DiscoverCardMotion.transition(motion: motion))
            }
            if DiscoverIssueLayout.offersSeeAll(total: total, shown: rows.count) {
                DiscoverTextAction(title: DiscoverIssueCopy.seeAll(total, german: KuroLocale.isGerman),
                                   spoken: DiscoverIssueCopy.seeAllSpoken(total, section: title, german: KuroLocale.isGerman),
                                   action: onSeeAll)
                    .padding(.top, 4)
            }
        }
        .animation(motion ? KuroMotion.settle : nil, value: cards.map(\.id))
        .id(anchor)
    }
}

struct DiscoverIndexRow: View {
    let position: Int
    let card: TasteCard
    let compact: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(DiscoverPageFeedback.self) private var feedback: DiscoverPageFeedback?
    @Environment(\.discoverSection) private var section
    @Environment(\.discoverKindKicker) private var kindKicker
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var german: Bool { KuroLocale.isGerman }

    /// "{year} · {format} · {n} eps", led by the status word when the title is on the list (R2 mark).
    private var meta: String? {
        let facts = DiscoverIssueCopy.facts(kind: card.media.kind, year: card.media.year, formatRaw: card.media.formatRaw,
                                            episodes: card.media.episodes, chapters: card.media.chapters, length: true, german: german,
                                            kindShown: kindKicker)
        guard let entry = library.entry(for: card.key) else { return facts }
        let word = DiscoverIssueCopy.statusWord(entry.status, progress: entry.progress, kind: card.media.kind, german: german)
        return [word, facts].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let accessibility = dynamicTypeSize.isAccessibilitySize
        Group {
            if accessibility {
                VStack(alignment: .leading, spacing: 8) {
                    openButton
                    key.padding(.leading, 22 + 12)
                }
                .padding(.vertical, 10)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    openButton
                    DiscoverAtLeastWidth(minimum: DiscoverIssueLayout.indexKeyWidth(compact: compact),
                                         maximum: DiscoverIssueLayout.indexKeyMaxWidth(compact: compact)) { key }
                }
                .frame(minHeight: DiscoverIssueLayout.indexRowMinHeight)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.kuroHairline).frame(height: 0.5).accessibilityHidden(true)
        }
    }

    private var key: some View {
        DiscoverPlanKey(card: card, variant: .leaf, compact: true)
    }

    private var openButton: some View {
        let meta = meta
        let isNew = section?.newKeys.contains(card.key) ?? false
        return Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            feedback?.trackOpen(card.key, slot: section.map { DiscoverCardSlot(section: $0.id, position: position - 1) }, via: "card")
            routes.openMedia(MediaRoute(card.key))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(DiscoverIssueCopy.indexNumber(position))
                    .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 24))
                    .monospacedDigit()
                    .foregroundStyle(Color.kuroMuted)
                    .frame(width: 22, alignment: .leading)
                HomeArtwork(url: card.media.imageURL.flatMap { URL(string: $0) }, maxPixelSize: 160,
                            placeholder: HomeInk.posterFill)
                    .frame(width: 40, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(alignment: .topLeading) {
                        if isNew { DiscoverNewTab().scaleEffect(0.85, anchor: .topLeading).padding(-4) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    if kindKicker { DiscoverKindKicker(kind: card.media.kind) }
                    Text(KuroCardText.sanitizeTitleForCard(card.media.title))
                        .font(.kuroCustom(15, weight: .medium, relativeTo: .subheadline, maxSize: 30))
                        .tracking(-0.2)
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        // Two lines: a long status word ("Abgeschlossen", "Schaue ich · F. 5") never
                        // cuts the format and the episode count.
                        Text(meta)
                            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                            .foregroundStyle(Color.kuroMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text([DiscoverIssueCopy.indexSpoken(position, german: german),
                                  DiscoverCardSpoken.label(title: card.media.title, kind: card.media.kind,
                                                           kindKicker: kindKicker, line: meta, isNew: isNew)]
            .joined(separator: ", ")))
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .discoverMenu(for: DiscoverCardItem(card: card, position: position - 1))
    }
}
