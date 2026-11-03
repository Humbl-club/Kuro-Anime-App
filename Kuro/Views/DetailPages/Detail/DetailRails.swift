import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Detail rails: the cast and More like this (details-songs spec §6.7, §6.8, §7.6, §5.1)
// Both rails use the edge peek (`KuroRailPeek`, 98 pt cards and a 30 pt slice at 390) and push their
// pages inside the journey (`\.kuroRoutes`, navigation contract N9 / N5). One element per card, the
// extra target (voice chip, Plan key) a sibling after it (§14.3).

// MARK: Cast

struct DetailCastRail: View {
    let members: [CastMember]
    /// Manga: square-cut portraits (radius 2) at the prototype's 0.6 saturation, and no voice chips.
    var bookish = false
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var visible: CGFloat = 0

    private var shown: [CastMember] { Self.shown(members) }

    /// The rail's cards (D8): MAIN and SUPPORTING, else BACKGROUND, at most 25. The page's section
    /// input counts this same list.
    static func shown(_ members: [CastMember]) -> [CastMember] {
        DetailCastRule.shown(members, role: \.role)
    }

    /// The manga page's characters (and fixture content) as cast members without a voice actor.
    static func members(_ characters: [(character: Character, role: String)]) -> [CastMember] {
        characters.map { CastMember(character: $0.character, role: $0.role, voiceActor: nil, language: nil) }
    }

    var body: some View {
        let german = KuroLocale.isGerman
        let cards = shown
        let width = KuroRailPeek.cardWidth(visible: visible)
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeading(title: KuroLocale.text("The characters.", "Die Figuren."),
                                 note: DetailCastRule.note(count: cards.count,
                                                           hasVoices: !bookish && cards.contains { $0.voiceActor != nil },
                                                           german: german))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: KuroRailPeek.spacing) {
                    ForEach(cards) { member in
                        card(member, width: width, german: german)
                    }
                }
                .padding(.top, 5)
                .padding(.bottom, 7)
            }
            .scrollClipDisabled()
            .detailRailBleed(visible: $visible)
            .padding(.top, 13)
        }
        .padding(.top, 30)
    }

    private func card(_ member: CastMember, width: CGFloat, german: Bool) -> some View {
        let name = member.character.nameFull?.detailNonEmpty ?? DetailCopy.unknown(german: german)
        let role = DetailCastRule.roleWord(member.role, german: german)
        let radius: CGFloat = bookish ? 2 : 5
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                // Pushed inside the journey (N9); Back returns here.
                routes.openPage(DetailNavigation.characterPage(member.character))
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(width: width, height: KuroRailPeek.coverHeight(width: width))
                        .overlay {
                            if let url = member.character.imageLarge.flatMap(AnimeDetailPage.webURL) {
                                KuroCachedAsyncImage(url: url, maxPixelSize: 300) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill().saturation(bookish ? 0.6 : 1)
                                    } else {
                                        KuroBrandedTile(kind: KuroLocale.text("Character", "Figur"), title: name, cornerRadius: radius)
                                    }
                                }
                            } else {
                                KuroBrandedTile(kind: KuroLocale.text("Character", "Figur"), title: name, cornerRadius: radius)
                            }
                        }
                        .background(HomeInk.posterFill)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.black.opacity(Double(0x11) / 255), lineWidth: 1))
                    Text(name)
                        .font(.detailSF(12, .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroInk)
                        // Two lines reserved, so the key / voice rows share one baseline across the rail.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2, reservesSpace: !dynamicTypeSize.isAccessibilitySize)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    if let role {
                        Text(role)
                            .font(.detailSF(9, relativeTo: .caption2))
                            .foregroundStyle(Color.kuroMuted)
                            .padding(.top, 2)
                    }
                }
                .frame(width: width, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DetailCastRule.spokenCard(name: name, role: role))
            .accessibilityAddTraits(.isButton)

            if !bookish, let voice = member.voiceActor, let voiceName = voice.nameFull?.detailNonEmpty {
                Button {
                    routes.openPage(DetailNavigation.voicePage(voice))
                } label: {
                    HStack(spacing: 6) {
                        voiceDisc(voice, name: voiceName)
                        Text(voiceName)
                            .font(.detailSF(10, relativeTo: .caption1))
                            .foregroundStyle(Color(hex: "5A695F"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .frame(width: width, alignment: .leading)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityLabel(DetailCastRule.spokenVoice(name: voiceName, character: name, german: german))
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func voiceDisc(_ staff: Staff, name: String) -> some View {
        Color.clear
            .frame(width: 20, height: 20)
            .overlay {
                if let url = staff.imageLarge.flatMap(AnimeDetailPage.webURL) {
                    KuroCachedAsyncImage(url: url, maxPixelSize: 80) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { KuroBrandedTile(kind: "", initials: KuroBrandedTile.initials(name), style: .ink, cornerRadius: 10) }
                    }
                } else {
                    KuroBrandedTile(kind: "", initials: KuroBrandedTile.initials(name), style: .ink, cornerRadius: 10)
                }
            }
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

// MARK: More like this

struct DetailMoreLikeThis: View {
    let items: [SimilarTitle]
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var visible: CGFloat = 0

    var body: some View {
        let german = KuroLocale.isGerman
        let width = KuroRailPeek.cardWidth(visible: visible)
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeading(title: DetailMoreLikeThisRule.heading(german: german),
                                 note: DetailMoreLikeThisRule.note(german: german))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: KuroRailPeek.spacing) {
                    ForEach(items) { item in
                        card(item, width: width, german: german)
                    }
                }
                .padding(.top, 5)
                .padding(.bottom, 7)
            }
            .scrollClipDisabled()
            .detailRailBleed(visible: $visible)
            .padding(.top, 13)
        }
        .padding(.top, 30)
    }

    private func card(_ item: SimilarTitle, width: CGFloat, german: Bool) -> some View {
        let display = item.display
        let line = DetailMoreLikeThisRule.cardLine(year: display.year, format: display.formatRaw, kind: item.key.kind, german: german)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                routes.openPage(DetailNavigation.similarPage(item.key))
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(width: width, height: KuroRailPeek.coverHeight(width: width))
                        .overlay {
                            if let url = display.imageURL.flatMap(AnimeDetailPage.webURL) {
                                KuroCachedAsyncImage(url: url, maxPixelSize: 320) { phase in
                                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                                    else { KuroBrandedTile(kind: Self.kindWord(item.key.kind, german: german), title: display.title) }
                                }
                            } else {
                                KuroBrandedTile(kind: Self.kindWord(item.key.kind, german: german), title: display.title)
                            }
                        }
                        .background(HomeInk.posterFill)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(display.title)
                        .font(.detailSF(12, .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.kuroInk)
                        // Two lines reserved, so the key / voice rows share one baseline across the rail.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2, reservesSpace: !dynamicTypeSize.isAccessibilitySize)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    if let line {
                        Text(line)
                            .font(.detailSF(10, relativeTo: .caption1))
                            .foregroundStyle(Color.kuroMuted)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .frame(width: width, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(KuroPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([display.title, line?.replacingOccurrences(of: " · ", with: ", ")].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)

            TastePlanKey(card: TasteCard(media: Self.media(display)), variant: .leaf, compact: true)
                .frame(width: width)
        }
        .frame(width: width, alignment: .topLeading)
    }

    static func kindWord(_ kind: MediaKind, german: Bool) -> String { kind == .manga ? "Manga" : "Anime" }

    /// The card projection as Taste's `Media` (the Plan key's card; never presented as a detail).
    static func media(_ display: any MediaDisplayable) -> Media {
        Media(id: display.id, kind: display.kind, title: display.title, imageURL: display.imageURL, year: display.year,
              displayDescription: display.displayDescription, episodes: display.episodes, chapters: display.chapters,
              rating: display.rating, genres: display.genres, statusRaw: display.statusRaw, formatRaw: display.formatRaw,
              popularityValue: display.popularityValue, trendingValue: display.trendingValue,
              createdAtValue: display.createdAtValue)
    }
}
