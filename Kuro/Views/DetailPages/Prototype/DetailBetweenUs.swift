import KuroCore
import SwiftUI

// MARK: - "Between us." (D11; PROTOTYPE_SPEC.md §4 D11, ref-detail-anime-390.png)
// The prototype's club card: cover beside "YOUR CLUBS · PRIVATE", the serif "Between us." (one of the
// prototype's Georgia headings, LANE_AMENDMENTS.md 1), member initials and names, then the members'
// notes, spoiler reveal and "Leave a thought". The notes, reactions, compose, edit and delete stay in
// `FriendsActivitySection` (its friend-scope and cancellation lifecycle is privacy-critical and is not
// re-implemented here); this card only draws the chrome around it. Hidden outside clubs.

struct DetailBetweenUs: View {
    let mediaType: String
    let mediaId: Int
    let coverURL: URL?
    /// Reports the members tracking this title (the page's club presence row reads the same answer).
    var onRoster: ([SocialActivityStore.FriendTitleActivity]) -> Void = { _ in }
    /// Fixture renders only.
    var preview: SocialActivityStore.FriendActivityResponse? = nil
    /// Manga: the prototype's folio card (`#e7e9db→#f3f2e7`, radius 5/19/5/5, hard `2 3 #d8dfce` shadow).
    var bookish = false

    @Environment(ClubsStore.self) private var clubs
    @State private var roster: [SocialActivityStore.FriendTitleActivity] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let cardTop = Color(hex: "E8EEE6")
    private static let cardBottom = Color(hex: "EFF2E9")
    private static let glow = Color(hex: "DCE6D5", opacity: Double(0x9C) / 255)
    private static let border = Color(hex: "C4D0C5")
    private static let headTop = Color(hex: "DBE3D5")
    private static let headBottom = Color(hex: "EAF0E4")
    private static let names = Color(hex: "61725D")
    private static let rim = Color(hex: "E5ECDF")

    static func rosterNames(_ roster: [SocialActivityStore.FriendTitleActivity]) -> [String] {
        roster.compactMap { $0.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        if !clubs.myClubs.isEmpty {
            let shape = bookish
                ? UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5,
                                         bottomTrailingRadius: 5, topTrailingRadius: 19, style: .continuous)
                : UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 8,
                                         bottomTrailingRadius: 8, topTrailingRadius: 22, style: .continuous)
            VStack(alignment: .leading, spacing: 0) {
                heading
                FriendsActivitySection(mediaId: mediaId, mediaType: mediaType, editorial: true, showsHeading: false,
                                       onRoster: { list in
                                           roster = list
                                           onRoster(list)
                                       }, preview: preview)
                    .padding(.horizontal, 20)
                    .padding(.top, 13)
                    .padding(.bottom, 13)
            }
            .background {
                ZStack {
                    if bookish {
                        LinearGradient(colors: [Color(hex: "E7E9DB"), Color(hex: "F3F2E7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        LinearGradient(colors: [Self.cardTop, Self.cardBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                        RadialGradient(colors: [Self.glow, .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Self.border, lineWidth: 1))
            .background {
                // Manga: the folio's hard offset shadow; anime: the soft lift.
                if bookish { shape.fill(Color(hex: "D8DFCE")).offset(x: 2, y: 3) }
            }
            .shadow(color: bookish ? .clear : Color(hex: "2B463B", opacity: Double(0x06) / 255), radius: 6, x: 0, y: 5)
            .padding(.horizontal, -6)
        }
    }

    private var heading: some View {
        let compact = dynamicTypeSize.isAccessibilitySize
        let names = Self.rosterNames(roster)
        return HStack(alignment: .center, spacing: 19) {
            if !compact {
                Color.clear
                    .frame(width: 105)
                    .frame(minHeight: 154)
                    .overlay {
                        if let coverURL {
                            KuroCachedAsyncImage(url: coverURL, maxPixelSize: 400) { phase in
                                if case .success(let image) = phase { image.resizable().scaledToFill() }
                                else { Color.clear }
                            }
                        }
                    }
                    .clipped()
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                DetailEyebrow(text: KuroLocale.text("Your clubs · private", "Deine Clubs · privat"), size: 7, tracking: 1.2)
                Text(KuroLocale.text("Between us.", "Unter uns."))
                    .font(.kuroEditorial(size: 28))
                    .tracking(-0.9)
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .padding(.bottom, names.isEmpty ? 0 : 16)
                    .accessibilityAddTraits(.isHeader)
                if !names.isEmpty {
                    DetailAvatars(names: names, size: 22, rim: Self.rim)
                    Text(names.prefix(3).joined(separator: ", "))
                        .font(.detailSF(9, relativeTo: .caption2))
                        .foregroundStyle(Self.names)
                        .lineLimit(2)
                        .padding(.top, 6)
                }
            }
            .padding(.vertical, 18)
            .padding(.trailing, 16)
            .padding(.leading, compact ? 20 : 0)
            Spacer(minLength: 0)
        }
        .background(LinearGradient(colors: bookish ? [Color(hex: "DCDFCB"), Color(hex: "EFEFDF")] : [Self.headTop, Self.headBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .accessibilityElement(children: .combine)
    }
}
