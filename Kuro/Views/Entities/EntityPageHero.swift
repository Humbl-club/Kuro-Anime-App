import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Entity page blocks in Home's grammar (details-songs spec §9)
// The hero (portrait 96 × 144, radius 5, or the ink branded tile with initials; Home eyebrow; the
// prototype's 27 pt detail title; native name; one quiet facts line), the studio's cover line, the
// description fold and the glance cards. No serif caps, no circle crop, no black pills.

/// Character, staff and author hero.
struct EntityPageHero: View {
    let imageURL: String?
    let name: String
    let native: String?
    let eyebrow: String?
    let facts: [String]

    static let portrait = CGSize(width: 96, height: 144)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            EntityPortrait(imageURL: imageURL, name: name, width: Self.portrait.width, height: Self.portrait.height,
                           cornerRadius: 5)
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow)
                        .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 18))
                        .tracking(1.05)
                        .foregroundStyle(HomeInk.kicker)
                        .lineLimit(2)
                        .accessibilitySortPriority(0)
                }
                Text(name)
                    .font(.detailSF(27, .semibold, relativeTo: .title1))
                    .tracking(-1.1)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(3)
                if let native = native?.trimmingCharacters(in: .whitespacesAndNewlines), !native.isEmpty {
                    Text(native)
                        .font(.detailSF(13, relativeTo: .subheadline))
                        .foregroundStyle(Color.kuroMuted)
                        .accessibilitySortPriority(2)
                }
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(.detailSF(10, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .accessibilitySortPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // VoiceOver (spec §9.5): the name (a header) first, then the native name and the facts; the
            // eyebrow, which repeats the page's kind, last.
            .accessibilityElement(children: .contain)
        }
    }
}

/// A person's picture, or the ink branded tile with their initials (never a stock silhouette).
struct EntityPortrait: View {
    let imageURL: String?
    let name: String?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        let tile = KuroBrandedTile(kind: "", initials: KuroBrandedTile.initials(name), style: .ink, cornerRadius: cornerRadius)
        Group {
            if let raw = imageURL, !raw.isEmpty, let url = URL(string: raw) {
                KuroCachedAsyncImage(url: url, maxPixelSize: Int(max(width, height))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: tile
                    }
                }
            } else {
                tile
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A title's cover, or the paper branded tile ("Anime · TV" + the title).
struct EntityCover: View {
    let imageURL: String?
    let kind: String
    let title: String
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        let tile = KuroBrandedTile(kind: kind, title: title, style: .paper, cornerRadius: cornerRadius)
        Group {
            if let raw = imageURL, !raw.isEmpty, let url = URL(string: raw) {
                KuroCachedAsyncImage(url: url, maxPixelSize: Int(max(width, height))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: tile
                    }
                }
            } else {
                tile
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The tile's kind word: "Anime · TV", "Manga", "Light novel".
    static func kindWord(kind: MediaKind, formatRaw: String?, german: Bool) -> String {
        if kind == .manga {
            let format = EntityPageCopy.formatWord(formatRaw, german: german)
            return format == nil || format == "Manga" ? "Manga" : (format ?? "Manga")
        }
        guard let format = EntityPageCopy.formatWord(formatRaw, german: german) else { return "Anime" }
        return "Anime · \(format)"
    }
}

/// Home's cover line for a studio: the name (44 semibold −0.8, 34 compact, wraps), the 46 × 2 ink rule,
/// one fact line. No logo is invented.
struct EntityStudioHero: View {
    let name: String
    let facts: String?
    let column: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.detailSF(EntityPageLayout.studioNameSize(column: column), .semibold, relativeTo: .largeTitle))
                .tracking(-0.8)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(Color.kuroInk)
                .frame(width: 46, height: 2)
                .padding(.top, 14)
                .accessibilityHidden(true)
            if let facts, !facts.isEmpty {
                Text(facts)
                    .font(.detailSF(10, relativeTo: .footnote))
                    .foregroundStyle(Color.kuroMuted)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The description: 13/21 in the detail synopsis ink, four lines, then "Read more" (F1–F3).
struct EntityDescription: View {
    let text: String
    @Binding var isExpanded: Bool

    /// Shorter texts never need the fold.
    static func needsFold(_ text: String) -> Bool { text.count > 220 || text.components(separatedBy: "\n").count > 4 }

    var body: some View {
        let german = KuroLocale.isGerman
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.detailSF(13, relativeTo: .subheadline))
                .foregroundStyle(DetailInk.synopsis)
                .lineSpacing(5)
                .lineLimit(isExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
            if Self.needsFold(text) {
                KuroFoldButton(isExpanded: $isExpanded,
                               expandLabel: EntityPageCopy.readMore(german: german),
                               collapseLabel: EntityPageCopy.readLess(german: german)) { title, _ in
                    Text(title)
                        .font(.detailSF(11, .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Home's glance card shell: #FFFEFA, radius 8, a 1 pt glance border, padding 10/12.
struct EntityGlanceShell<Content: View>: View {
    var minHeight: CGFloat = 44
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(shape.fill(HomeInk.glanceFill).shadow(color: HomeInk.glanceShadow, radius: 1, x: 0, y: 1))
            .overlay(shape.strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
            .contentShape(shape)
    }
}

/// "In your list: Jujutsu Kaisen · Ep. 6 / 23 ›": pushes that title.
struct EntityInListLine: View {
    let media: Media
    let entry: LibraryEntry

    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        let german = KuroLocale.isGerman
        let total = media.kind == .manga ? media.chapters : media.episodes
        let detail = EntityPageCopy.progress(entry.progress, total: total, kind: media.kind, german: german)
            ?? DetailCopy.listStatus(entry.status.rawValue, medium: media.kind, german: german, perspective: .own)
        let line = EntityPageCopy.inYourList(title: KuroCardText.sanitizeTitleForCard(media.title), detail: detail, german: german)
        Button {
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(media.libraryKey))
        } label: {
            EntityGlanceShell {
                HStack(spacing: 8) {
                    Text(line)
                        .font(.detailSF(12, .medium, relativeTo: .footnote))
                        .foregroundStyle(HomeInk.glanceInk)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("›")
                        .font(.detailSF(15, relativeTo: .body))
                        .foregroundStyle(HomeInk.glanceMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityLabel(line)
    }
}

/// The studio's "In your list" glance: the tracked titles' thumbnails, a line, "›" to the first one.
struct EntityTrackedGlance: View {
    let works: [(media: Media, entry: LibraryEntry)]

    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        let german = KuroLocale.isGerman
        if let first = works.first {
            let total = first.media.kind == .manga ? first.media.chapters : first.media.episodes
            let status = DetailCopy.listStatus(first.entry.status.rawValue, medium: first.media.kind, german: german, perspective: .own)
            let parts = [KuroCardText.sanitizeTitleForCard(first.media.title), status,
                         EntityPageCopy.progress(first.entry.progress, total: total, kind: first.media.kind, german: german)]
                .compactMap { $0 }
            let line = parts.joined(separator: " · ")
            Button {
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(first.media.libraryKey))
            } label: {
                EntityGlanceShell(minHeight: 72) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(EntityPageCopy.inYourListTitle(german: german))
                                .font(.detailSF(14, .semibold, relativeTo: .subheadline))
                                .tracking(-0.3)
                                .foregroundStyle(HomeInk.glanceInk)
                            Text(line)
                                .font(.detailSF(10, relativeTo: .footnote))
                                .foregroundStyle(HomeInk.glanceMuted)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: -8) {
                            ForEach(Array(works.prefix(3).enumerated()), id: \.offset) { _, work in
                                EntityCover(imageURL: work.media.imageURL,
                                            kind: EntityCover.kindWord(kind: work.media.kind, formatRaw: work.media.formatRaw, german: german),
                                            title: work.media.title, width: 28, height: 42, cornerRadius: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(HomeInk.glanceFill, lineWidth: 1))
                            }
                        }
                        Text("›")
                            .font(.detailSF(15, relativeTo: .body))
                            .foregroundStyle(HomeInk.glanceMuted)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel("\(EntityPageCopy.inYourListTitle(german: german)): \(line)")
        }
    }
}
