import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Entity rails and rows (details-songs spec §9, §5.1)
// Rails: 2 : 3 covers (radius 4) at the edge-peek width (`KuroRailPeek`), 14 pt apart, starting at the
// 24 pt gutter and bleeding to the column's edge with the gutter as trailing inset. The rail's ScrollView
// is never inside the page's horizontal padding. Rows: Home's quiet rows (40 × 60 cover, radius 2, gap 16,
// min 60, a 0.5 pt hairline). Every tap pushes through `\.kuroRoutes` (N5 pops back to an open page).

/// One work on an entity page.
struct EntityWorkItem: Identifiable {
    let media: Media
    let role: String?
    let id: String
}

/// A sideways rail of works (character "Appears in.", studio "Most loved.").
struct EntityWorkRail: View {
    let works: [EntityWorkItem]
    /// The page column's width (measured).
    let column: CGFloat

    var body: some View {
        let width = KuroRailPeek.cardWidth(visible: EntityPageLayout.railVisible(column: column))
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: KuroRailPeek.spacing) {
                ForEach(works) { work in
                    EntityWorkTile(media: work.media, width: width)
                }
            }
            .padding(.horizontal, EntityPageLayout.gutter)
        }
        // Clipped at the page column (the readable column on iPad): the rail bleeds to its edge, no further.
        .kuroSwipeExclusionZone()
    }
}

/// Cover, title (12 medium, two lines), "Anime · 2020", and the viewer's status word when tracked.
struct EntityWorkTile: View {
    let media: Media
    let width: CGFloat

    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        let title = KuroCardText.sanitizeTitleForCard(media.title)
        let line = EntityPageCopy.mediumYear(kind: media.kind, year: media.year, german: german)
        let status = library.entry(for: media.libraryKey).flatMap {
            DetailCopy.listStatus($0.status.rawValue, medium: media.kind, german: german, perspective: .own)
        }
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(media.libraryKey))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                EntityCover(imageURL: media.imageURL,
                            kind: EntityCover.kindWord(kind: media.kind, formatRaw: media.formatRaw, german: german),
                            title: title, width: width, height: KuroRailPeek.coverHeight(width: width))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.detailSF(12, .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line)
                        .font(.detailSF(10, relativeTo: .caption1))
                        .foregroundStyle(Color.kuroMuted)
                        .lineLimit(1)
                    if let status {
                        Text(status)
                            .font(.detailSF(9, relativeTo: .caption2))
                            .foregroundStyle(Color.kuroMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, line, status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// "Characters you know.": portraits of the characters a person voiced in titles on the viewer's lists.
struct EntityCharacterRail: View {
    let roles: [VoiceRole]
    let column: CGFloat

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let width = KuroRailPeek.cardWidth(visible: EntityPageLayout.railVisible(column: column))
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: KuroRailPeek.spacing) {
                ForEach(roles) { role in
                    let name = role.character.nameFull ?? ""
                    let title = KuroCardText.sanitizeTitleForCard(role.anime.displayTitle)
                    Button {
                        guard !suppressCardTaps else { return }
                        KuroAccessibility.impactHaptic(.light)
                        routes.openCharacter(role.character)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            EntityPortrait(imageURL: role.character.imageLarge, name: name, width: width,
                                           height: KuroRailPeek.coverHeight(width: width), cornerRadius: 4)
                            Text(name)
                                .font(.detailSF(12, .medium, relativeTo: .footnote))
                                .foregroundStyle(Color.kuroInk)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(title)
                                .font(.detailSF(10, relativeTo: .caption1))
                                .foregroundStyle(Color.kuroMuted)
                                .lineLimit(2)
                        }
                        .frame(width: width, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name), \(title)")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, EntityPageLayout.gutter)
        }
        // Clipped at the page column (the readable column on iPad): the rail bleeds to its edge, no further.
        .kuroSwipeExclusionZone()
    }
}

/// A voice role (staff "Roles."): two targets. The cover opens the anime; the text opens the character.
struct EntityRoleRow: View {
    let role: VoiceRole

    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        let title = KuroCardText.sanitizeTitleForCard(role.anime.displayTitle)
        let name = role.character.nameFull ?? DetailCopy.unknown(german: german)
        let line = EntityPageCopy.roleLine(title: title, role: role.role, year: role.anime.year, german: german)
        let status = library.entry(for: role.anime.key).flatMap {
            DetailCopy.listStatus($0.status.rawValue, medium: .anime, german: german, perspective: .own)
        }
        HStack(spacing: 16) {
            Button {
                guard !suppressCardTaps else { return }
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(role.anime.key))
            } label: {
                EntityCover(imageURL: role.anime.coverImageLarge,
                            kind: EntityCover.kindWord(kind: .anime, formatRaw: role.anime.format, german: german),
                            title: title, width: 40, height: 60, cornerRadius: 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)

            Button {
                guard !suppressCardTaps else { return }
                KuroAccessibility.impactHaptic(.light)
                routes.openCharacter(role.character)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.detailSF(15, .medium, relativeTo: .body))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(2)
                        Text(line)
                            .font(.detailSF(10, relativeTo: .caption1))
                            .foregroundStyle(Color.kuroMuted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let status {
                        Text(status)
                            .font(.detailSF(9, relativeTo: .caption2))
                            .foregroundStyle(Color.kuroMuted)
                    }
                }
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([name, line, status].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
    }
}

/// A work as a quiet row (staff and author "Works.", a studio year): year numeral, cover, title,
/// "TV · Director", the status word when tracked.
struct EntityWorkRow: View {
    let media: Media
    let role: String?
    /// The leading year numeral reads as a chronological index, so it is drawn only under the Year sort;
    /// under Rating or Era the year moves into the meta line ("Manga · Art · 1989").
    var yearColumn = true

    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        let title = KuroCardText.sanitizeTitleForCard(media.title)
        let year = EntityPageCopy.knownYear(media.year)
        let baseLine = EntityPageCopy.workLine(formatRaw: media.formatRaw, kind: media.kind, role: role, german: german)
        let line = yearColumn ? baseLine : ([baseLine] + [year.map(String.init)].compactMap { $0 }).joined(separator: " · ")
        let status = library.entry(for: media.libraryKey).flatMap {
            DetailCopy.listStatus($0.status.rawValue, medium: media.kind, german: german, perspective: .own)
        }
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(media.libraryKey))
        } label: {
            HStack(spacing: 16) {
                if yearColumn {
                    Text(year.map(String.init) ?? "")
                        .font(.detailSF(13, relativeTo: .footnote).monospacedDigit())
                        .foregroundStyle(Color.kuroMuted)
                        .frame(width: 38, alignment: .leading)
                }
                EntityCover(imageURL: media.imageURL,
                            kind: EntityCover.kindWord(kind: media.kind, formatRaw: media.formatRaw, german: german),
                            title: title, width: 40, height: 60, cornerRadius: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.detailSF(15, .medium, relativeTo: .body))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                    Text(line)
                        .font(.detailSF(10, relativeTo: .caption1))
                        .foregroundStyle(Color.kuroMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let status {
                    Text(status)
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(Color.kuroMuted)
                }
            }
            .frame(minHeight: 60)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, yearColumn ? year.map(String.init) : nil, line, status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// A studio's "By year." index row: the year, then the titles. Up to three titles are separate full-width
/// rows (each wraps to two lines inside the column and keeps its "›"); a busier year is one button that
/// pushes that year's works, its "· N more" count kept outside the truncated titles so it always shows.
struct EntityYearRow: View {
    let group: EntityYearGroup
    let studioName: String

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(String(group.year))
                .font(.detailSF(13, relativeTo: .footnote).monospacedDigit())
                .foregroundStyle(Color.kuroMuted)
                .frame(width: 38, alignment: .leading)
                .accessibilityHidden(!group.isInline)
            if group.isInline {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.works.enumerated()), id: \.offset) { _, media in
                        let title = KuroCardText.sanitizeTitleForCard(media.title)
                        Button {
                            guard !suppressCardTaps else { return }
                            KuroAccessibility.impactHaptic(.light)
                            routes.openMedia(MediaRoute(media.libraryKey))
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(title)
                                    .font(.detailSF(13, .medium, relativeTo: .footnote))
                                    .foregroundStyle(Color.kuroInk)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                chevron
                            }
                            .padding(.vertical, 6)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HomeContactStyle())
                        .accessibilityLabel("\(title), \(group.year)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let titles = group.works.prefix(EntityYearGroup.inlineTitles).map { KuroCardText.sanitizeTitleForCard($0.title) }
                let more = group.works.count - titles.count
                let moreText = EntityPageCopy.moreInYear(more, german: german)
                let text = titles.joined(separator: " · ")
                Button {
                    guard !suppressCardTaps else { return }
                    KuroAccessibility.impactHaptic(.light)
                    routes.openPage(EntityYearPage.page(studioName: studioName, group: group))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(text)
                            .font(.detailSF(13, .medium, relativeTo: .footnote))
                            .foregroundStyle(Color.kuroInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(moreText)
                            .font(.detailSF(11, relativeTo: .caption1))
                            .foregroundStyle(Color.kuroMuted)
                            .fixedSize()
                        chevron
                    }
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel("\(group.year): \(text) · \(moreText)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
    }

    private var chevron: some View {
        Text("›")
            .font(.detailSF(15, relativeTo: .body))
            .foregroundStyle(Color.kuroMuted)
            .accessibilityHidden(true)
    }
}

/// One year of a studio's works as a journey page (pushed from "By year.").
enum EntityYearPage {
    static func id(studioName: String, year: Int) -> String { "studio-year:\(studioName):\(year)" }

    static func page(studioName: String, group: EntityYearGroup) -> JourneyPage {
        let title = EntityPageCopy.yearPageTitle(studio: studioName, year: group.year)
        return .seeAll(AnyJourneyPage(id: id(studioName: studioName, year: group.year), title: title) {
            EntityYearWorksView(title: title, works: group.works)
        })
    }
}

private struct EntityYearWorksView: View {
    let title: String
    let works: [Media]
    @State private var collapse: CGFloat = 0

    var body: some View {
        KuroJourneyAwareStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.detailSF(27, .semibold, relativeTo: .title1))
                        .tracking(-1.1)
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 16)
                    ForEach(Array(works.enumerated()), id: \.offset) { _, media in
                        EntityWorkRow(media: media, role: nil)
                    }
                }
                .padding(.horizontal, EntityPageLayout.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kuroReadableWidth()
                .padding(.top, KuroJourneyChrome.barHeight + 12)
                .padding(.bottom, 40)
            }
            .kuroCollapseTracking($collapse, start: 24, distance: 60)
            .background(Color.kuroPaper)
            .kuroJourneyChrome(title: title, collapseProgress: collapse)
        }
        .routePresenter()
    }
}
