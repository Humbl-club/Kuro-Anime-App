// Discover issue frames (spec D8, rulebook §14.5)
// Issue-style frames on the white page: the picture first, then the title, then at most one line.
// No glass, no score chips, no genre pills inside a frame. The lead frame keeps a full-width picture
// with a serif title and at most two short lines. Every text sits on the ink tokens.
//
// Interaction (rulebook §7): a frame opens the title through `routes.openMedia` on a deliberate tap
// that honours the pager's tap suppression; its context menu keeps Quick Add / Edit / Add to Club.
// Widths always come from the caller's container (no fixed screen width).

import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Browse entry

/// Where "Browse the catalogue" is offered (spec D2). Browse is a pager page in the live order;
/// only where the pager has none (series Home) do Discover and Search open it through the Browse
/// route. One rule for both surfaces, so they cannot drift apart.
enum DiscoverBrowseEntry {
    @MainActor
    static func isOffered(flags: FeatureFlags) -> Bool {
        !KuroMainView.Section
            .pagerOrder(tasteDeck: flags.tasteDeckV1Enabled, seriesHome: flags.seriesHomeNativeV1Enabled)
            .contains(.browse)
    }
}

// MARK: - Layout

/// Width rules for the Discover, Browse and Taste pages.
enum DiscoverLayout {
    /// Spacing between frames in a row or rail.
    static let frameSpacing: CGFloat = 12

    /// The outer gutter: 20 pt, 16 pt at a 320 pt content width (rulebook §5).
    static func gutter(for width: CGFloat) -> CGFloat {
        width <= 320 ? 16 : KuroDesignSpacing.padding
    }

    /// The width content is laid out in: the container, or the readable column on regular width.
    static func contentWidth(container: CGFloat, regularWidth: Bool) -> CGFloat {
        let width = max(0, container)
        return regularWidth ? min(width, KuroReadableWidth.maxWidth) : width
    }

    /// Columns for an equal-frame grid: as many `minimum`-wide frames as fit, never fewer than 2;
    /// exactly 2 at accessibility text sizes (rulebook §6), so large titles reflow instead of clipping.
    static func columnCount(
        for width: CGFloat,
        minimum: CGFloat = 150,
        spacing: CGFloat = frameSpacing,
        accessibilitySize: Bool = false
    ) -> Int {
        guard width > 0, minimum > 0, !accessibilitySize else { return 2 }
        return max(2, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }

    /// The frame width of a grid with `columns` columns across `width`.
    static func gridFrameWidth(for width: CGFloat, columns: Int, spacing: CGFloat = frameSpacing) -> CGFloat {
        let count = CGFloat(max(1, columns))
        return max(0, floor((width - spacing * (count - 1)) / count))
    }

    /// A rail frame's width (CLAUDE.md card formula; `large` gives fewer, larger faces).
    static func railFrameWidth(for width: CGFloat, large: Bool) -> CGFloat {
        if large {
            return min(170, max(132, floor((width - 56) / 2.35)))
        }
        return min(144, max(112, floor((width - 56) / 2.8)))
    }
}

// MARK: - Frame copy

/// The one line under a frame's title, EN/DE (pure, so tests can pin it).
nonisolated enum DiscoverFrameCopy {
    /// "Ep. 7 · 21:30" for a stated airing slot; otherwise year and length ("2019 · 12 eps"),
    /// falling back to the release status or format. Nothing is shown that the row does not state.
    static func line(
        kind: MediaKind,
        year: String,
        episodes: Int?,
        chapters: Int?,
        statusRaw: String?,
        formatRaw: String?,
        airing: DiscoverAiringSlot? = nil,
        german: Bool,
        locale: Locale,
        timeZone: TimeZone
    ) -> String? {
        if let airing {
            let time = timeText(airing.airingAt, locale: locale, timeZone: timeZone)
            if let episode = airing.episode, episode > 0 {
                return german ? "Folge \(episode) · \(time)" : "Ep. \(episode) · \(time)"
            }
            return time
        }
        var parts: [String] = []
        let digits = year.filter(\.isNumber)
        if digits.count >= 4 {
            parts.append(String(digits.prefix(4)))
        }
        if kind == .anime, let episodes, episodes > 0 {
            parts.append(german ? "\(episodes) \(episodes == 1 ? "Folge" : "Folgen")" : "\(episodes) \(episodes == 1 ? "ep" : "eps")")
        } else if kind == .manga, let chapters, chapters > 0 {
            parts.append(german ? "\(chapters) Kap." : "\(chapters) ch")
        } else if let status = statusRaw?.uppercased(), status == "RELEASING" {
            parts.append(german ? "Läuft" : (kind == .anime ? "Airing" : "Publishing"))
        } else if let format = formatRaw, !format.isEmpty {
            parts.append(formatName(format, german: german))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A clock time in the reader's locale and zone ("21:30", "9:30 PM").
    static func timeText(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// AniList format codes in reading form.
    static func formatName(_ raw: String, german: Bool) -> String {
        switch raw.uppercased() {
        case "TV": return "TV"
        case "TV_SHORT": return german ? "TV kurz" : "TV short"
        case "MOVIE": return german ? "Film" : "Movie"
        case "OVA": return "OVA"
        case "ONA": return "ONA"
        case "SPECIAL": return "Special"
        case "MUSIC": return german ? "Musik" : "Music"
        case "MANGA": return "Manga"
        case "NOVEL": return german ? "Roman" : "Novel"
        case "ONE_SHOT": return "One-shot"
        default: return raw.capitalized
        }
    }

    /// "2 in your clubs": the people who share a club with the reader and track the title.
    static func clubCount(_ count: Int, german: Bool) -> String {
        german ? "\(count) in deinen Clubs" : "\(count) in your clubs"
    }
}

// MARK: - Word picker (ink words with an underline mark)

/// Typographic choice words (rulebook §7 "Segmented status / filters"): the selected word is ink
/// with a short ink rule under it, the others quiet ink. Every word is a 44 pt target.
struct DiscoverWordPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var accessibilityLabel: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KuroDesignSpacing.lg) {
                ForEach(options, id: \.value) { option in
                    DiscoverWordButton(
                        title: option.title,
                        isSelected: selection == option.value
                    ) {
                        guard selection != option.value else { return }
                        KuroAccessibility.impactHaptic(.light)
                        selection = option.value
                    }
                }
            }
        }
        .kuroSwipeExclusionZone()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// One ink word with an underline mark (a single choice or a toggle).
struct DiscoverWordButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                Text(title)
                    .font(.kuroMeta(weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroInkQuiet)
                    .lineLimit(1)
                    .fixedSize()
                Rectangle()
                    .fill(isSelected ? Color.kuroInk : Color.clear)
                    .frame(width: 16, height: 1.5)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Frame

/// The issue frame: an equal cover, the title (at most two lines), one line.
struct DiscoverFrame: View {
    let media: any MediaDisplayable
    let width: CGFloat
    /// A stated airing slot (Airing today rail only).
    var airing: DiscoverAiringSlot? = nil

    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(FeatureFlags.self) private var flags
    @Environment(ClubsStore.self) private var clubs
    @Environment(SocialActivityStore.self) private var social
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    private var isSaved: Bool { library.isTracked(media.libraryKey) }

    private var line: String? {
        let german = KuroLocale.isGerman
        if airing == nil, flags.isSocialActivityV1Enabled {
            let count = social.friendCount(mediaId: media.id, mediaType: media.kind.rawValue.uppercased())
            if count > 0 { return DiscoverFrameCopy.clubCount(count, german: german) }
        }
        return DiscoverFrameCopy.line(
            kind: media.kind,
            year: media.year,
            episodes: media.episodes,
            chapters: media.chapters,
            statusRaw: media.statusRaw,
            formatRaw: media.formatRaw,
            airing: airing,
            german: german,
            locale: KuroLocale.locale,
            timeZone: KuroLocale.timeZone
        )
    }

    var body: some View {
        let line = line
        // A Button so the press state cancels on scroll/drag (rulebook §7).
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(media.libraryKey))
        } label: {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                DiscoverPicture(url: URL(string: media.imageURL ?? ""), maxPixelSize: 360)
                    .frame(width: width, height: floor(width / KuroCardMetrics.imageAspectRatio))
                    .clipShape(RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(KuroCardText.sanitizeTitleForCard(media.title))
                        .font(.kuroBody(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    if let line {
                        Text(line)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkQuiet)
                            .lineLimit(1)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([media.title, line].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(isSaved ? KuroLocale.text("On your list", "Auf deiner Liste") : "")
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            DiscoverFrameMenu(media: media, isSaved: isSaved, hasClubs: !clubs.myClubs.isEmpty)
        }
    }
}

/// The frame's context menu: Quick Add (Planned) / Remove, the list editor, Add to Club.
struct DiscoverFrameMenu: View {
    let media: any MediaDisplayable
    let isSaved: Bool
    let hasClubs: Bool

    @Environment(LibraryActions.self) private var libraryActions
    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            LibraryViewActions.toggleTracked(media.libraryKey, actions: libraryActions)
        } label: {
            Label(
                isSaved
                    ? KuroLocale.text("Remove from list", "Von der Liste entfernen")
                    : KuroLocale.text("Quick add (Planned)", "Schnell hinzufügen (Geplant)"),
                systemImage: isSaved ? "minus.circle" : "plus.circle"
            )
        }

        Button {
            KuroAccessibility.impactHaptic(.light)
            routes.presentTrackingEditor(TrackingEditorRequest(media: media))
        } label: {
            Label(
                isSaved
                    ? KuroLocale.text("Edit list entry", "Listeneintrag bearbeiten")
                    : KuroLocale.text("Add to list\u{2026}", "Zur Liste hinzufügen\u{2026}"),
                systemImage: "slider.horizontal.3"
            )
        }

        if hasClubs {
            Button {
                KuroAccessibility.impactHaptic(.light)
                routes.presentAddToClub(media.libraryKey)
            } label: {
                Label(KuroLocale.text("Add to club\u{2026}", "Zu einem Club hinzufügen\u{2026}"), systemImage: "person.2")
            }
        }
    }
}

/// Artwork with stable geometry: the image fills its frame (top-biased crop) and a missing or
/// failed image keeps the neutral missing-art field. Decorative for VoiceOver.
struct DiscoverPicture: View {
    let url: URL?
    var maxPixelSize: Int? = 360

    var body: some View {
        Color.kuroMissingArt
            .overlay(alignment: .top) {
                KuroCachedAsyncImage(url: url, maxPixelSize: maxPixelSize) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.kuroMissingArt
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Lead frame

/// The lead issue frame: a full-width picture, then a kicker, a serif title and at most two short
/// lines on white. Banner art keeps a wide crop; a cover is cropped from the top at 4:5.
struct DiscoverLeadFrame: View {
    let kicker: String?
    let title: String
    let line: String?
    let imageURL: URL?
    /// Banner art (wide) rather than a portrait cover.
    let isWideArt: Bool
    let route: MediaRoute
    let width: CGFloat

    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps
    @Environment(\.kuroRoutes) private var routes

    static func pictureHeight(width: CGFloat, isWideArt: Bool) -> CGFloat {
        isWideArt ? floor(width / 2.2) : min(floor(width * 1.25), 560)
    }

    var body: some View {
        // A Button so the press state cancels on scroll/drag (rulebook §7).
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(route)
        } label: {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                DiscoverPicture(url: imageURL, maxPixelSize: 1100)
                    .frame(width: width, height: Self.pictureHeight(width: width, isWideArt: isWideArt))
                    .clipShape(RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous))

                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    if let kicker, !kicker.isEmpty {
                        Text(kicker)
                            .kuroKicker()
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .kuroRoleText(.headline)
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let line, !line.isEmpty {
                        Text(line)
                            .font(.kuroBody(weight: .regular))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle(pressedScale: 0.985))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([kicker, title, line].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")))
        .accessibilityHint(KuroLocale.text("Opens details", "Öffnet die Details"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The lead frame's stable placeholder while the daily pick loads.
struct DiscoverLeadSkeleton: View {
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                .fill(Color.kuroBlack05)
                .frame(width: width, height: DiscoverLeadFrame.pictureHeight(width: width, isWideArt: true))
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.kuroBlack05)
                .frame(width: width * 0.6, height: 22)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.kuroBlack05)
                .frame(width: width * 0.85, height: 14)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Rail filter (Trending / Top rated)

/// A rail-level refinement over the loaded items (length or finished), shown as ink words.
nonisolated enum DiscoverRailFilter: String, CaseIterable, Hashable, Sendable {
    case all, short, long, finished

    func title(german: Bool) -> String {
        switch self {
        case .all: return german ? "Alle" : "All"
        case .short: return german ? "Kurz" : "Short"
        case .long: return german ? "Lang" : "Long"
        case .finished: return german ? "Abgeschlossen" : "Finished"
        }
    }

    func includes(episodes: Int?, statusRaw: String?) -> Bool {
        switch self {
        case .all: return true
        case .short: return (episodes ?? 0) > 0 && (episodes ?? 0) <= 13
        case .long: return (episodes ?? 0) > 50
        case .finished: return statusRaw == "FINISHED"
        }
    }
}

// MARK: - Sections

/// A horizontal rail of issue frames under a serif section header.
struct DiscoverRail<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]
    let containerWidth: CGFloat
    var onSeeAll: (() -> Void)? = nil
    var showsFilters: Bool = false
    var largeFrames: Bool = true
    /// Stated airing slots by id (Airing today).
    var airingSlots: [Int: DiscoverAiringSlot] = [:]

    @State private var filter: DiscoverRailFilter = .all

    private var shown: [Item] {
        items.filter { filter.includes(episodes: $0.episodes, statusRaw: $0.statusRaw) }
    }

    var body: some View {
        let gutter = DiscoverLayout.gutter(for: containerWidth)
        let frameWidth = DiscoverLayout.railFrameWidth(for: containerWidth, large: largeFrames)
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            DiscoverSectionHeading(title: title, onSeeAll: onSeeAll)
                .padding(.horizontal, gutter)

            if showsFilters {
                DiscoverWordPicker(
                    options: DiscoverRailFilter.allCases.map { ($0, $0.title(german: KuroLocale.isGerman)) },
                    selection: $filter,
                    accessibilityLabel: KuroLocale.text("Refine \(title)", "\(title) eingrenzen")
                )
                .contentMargins(.horizontal, gutter, for: .scrollContent)
            }

            if shown.isEmpty {
                KuroStateView(.empty,
                              title: KuroLocale.text("Nothing here for this choice.", "Für diese Auswahl gibt es hier nichts."),
                              layout: .inline)
                    .padding(.horizontal, gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DiscoverLayout.frameSpacing) {
                        ForEach(shown, id: \.id) { item in
                            DiscoverFrame(media: item, width: frameWidth, airing: airingSlots[item.id])
                        }
                    }
                    .padding(.horizontal, gutter)
                }
                .kuroSwipeExclusionZone()
            }
        }
    }
}

/// An equal-frame grid (columns derived from the width) under a serif section header.
struct DiscoverGridSection<Item: MediaDisplayable>: View {
    let title: String
    let items: [Item]
    let containerWidth: CGFloat
    var onSeeAll: (() -> Void)? = nil
    var showsFilters: Bool = false

    @State private var filter: DiscoverRailFilter = .all
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shown: [Item] {
        items.filter { filter.includes(episodes: $0.episodes, statusRaw: $0.statusRaw) }
    }

    var body: some View {
        let gutter = DiscoverLayout.gutter(for: containerWidth)
        let inner = max(0, containerWidth - gutter * 2)
        let columns = DiscoverLayout.columnCount(for: inner, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        let frameWidth = DiscoverLayout.gridFrameWidth(for: inner, columns: columns)
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            DiscoverSectionHeading(title: title, onSeeAll: onSeeAll)
                .padding(.horizontal, gutter)

            if showsFilters {
                DiscoverWordPicker(
                    options: DiscoverRailFilter.allCases.map { ($0, $0.title(german: KuroLocale.isGerman)) },
                    selection: $filter,
                    accessibilityLabel: KuroLocale.text("Refine \(title)", "\(title) eingrenzen")
                )
                .contentMargins(.horizontal, gutter, for: .scrollContent)
            }

            if shown.isEmpty {
                KuroStateView(.empty,
                              title: KuroLocale.text("Nothing here for this choice.", "Für diese Auswahl gibt es hier nichts."),
                              layout: .inline)
                    .padding(.horizontal, gutter)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(frameWidth), spacing: DiscoverLayout.frameSpacing, alignment: .top), count: columns),
                    alignment: .leading,
                    spacing: KuroDesignSpacing.lg
                ) {
                    ForEach(shown, id: \.id) { item in
                        DiscoverFrame(media: item, width: frameWidth)
                    }
                }
                .padding(.horizontal, gutter)
            }
        }
    }
}

/// The section heading: serif title (a VoiceOver header) with an optional "See all".
struct DiscoverSectionHeading: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        KuroSectionHeader(
            title,
            size: .title,
            actionTitle: onSeeAll == nil ? nil : KuroLocale.text("See all", "Alle ansehen"),
            action: onSeeAll.map { open in
                {
                    KuroAccessibility.impactHaptic(.light)
                    open()
                }
            }
        )
    }
}

/// First-paint placeholder: the lead frame and two rails at their real sizes.
struct DiscoverLoadingSkeleton: View {
    let containerWidth: CGFloat

    var body: some View {
        let gutter = DiscoverLayout.gutter(for: containerWidth)
        let frameWidth = DiscoverLayout.railFrameWidth(for: containerWidth, large: true)
        VStack(alignment: .leading, spacing: KuroDesignSpacing.xl) {
            DiscoverLeadSkeleton(width: max(0, containerWidth - gutter * 2))
                .padding(.horizontal, gutter)
            // The branded loading cue: the scrub line travelling under the lead frame.
            KuroScrubLine()
                .frame(maxWidth: 96)
                .padding(.horizontal, gutter)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.kuroBlack05)
                        .frame(width: 140, height: 18)
                        .padding(.horizontal, gutter)
                    HStack(alignment: .top, spacing: DiscoverLayout.frameSpacing) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                                RoundedRectangle(cornerRadius: KuroRadius.xs, style: .continuous)
                                    .fill(Color.kuroBlack05)
                                    .frame(width: frameWidth, height: floor(frameWidth / KuroCardMetrics.imageAspectRatio))
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.kuroBlack05)
                                    .frame(width: frameWidth * 0.8, height: 12)
                            }
                        }
                    }
                    .padding(.horizontal, gutter)
                    .frame(width: containerWidth, alignment: .leading)
                    .clipped()
                }
            }
        }
        .padding(.top, KuroDesignSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroLocale.text("Loading", "Wird geladen"))
    }
}
