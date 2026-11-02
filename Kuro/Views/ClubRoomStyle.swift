import SwiftUI

// MARK: - Club room style
// The prototype's club-room language (PROTOTYPE_SPEC §4 "Club room", §5 width changes), shared by the
// Clubs invitation (`ClubsView`), the club-detail room (hero, initial state, art strip) and Home's club
// room (`HomeClubRoom`), so a club keeps one room colour from Home and the invitation to its detail page.

/// The club room's colours. No foundation token carries them (`kuroRoom` is the older neutral
/// charcoal `#222222`).
enum ClubRoomPalette {
    static let room = Color(hex: "252B28")
    static let glow = Color(hex: "444A46")
    static let border = Color(hex: "535A55", opacity: Double(0x4C) / 255)
    static let text = Color(hex: "F0F4EF")
    static let kicker = Color(hex: "C0CBBB")
    static let seal = Color(hex: "899C8C")
    static let note = Color(hex: "F5F6EF")
    static let noteInk = Color(hex: "2E342C")
    static let quiet = Color(hex: "E9EDE2")
    static let quietBorder = Color(hex: "CCD4C3")
    static let quietInk = Color(hex: "59664E")
    static let footer = Color(hex: "B4C2A9")
    static let footerRule = Color(hex: "C5D2B8", opacity: Double(0x1C) / 255)
    /// The room's drop colour (`#10171066`).
    static let drop = Color(hex: "101710", opacity: Double(0x66) / 255)
    /// The seal's knot (`#d2dacd`).
    static let sealKnot = Color(hex: "D2DACD")
    /// Member initials: ink, the rim against the room, and the three positional fills
    /// (`.member-stack>span:nth-child(1|2|3)`).
    static let memberInk = Color(hex: "33412E")
    static let memberRim = Color(hex: "2F3730")
    static let memberFills: [Color] = [Color(hex: "D0D8CB"), Color(hex: "ADBBA6"), Color(hex: "899A82")]
    /// The light note card: its border, drop, the time-ago and "{title} ›" inks, and the cover's drop.
    static let noteBorder = Color.white.opacity(Double(0x88) / 255)
    static let noteShadow = Color.black.opacity(Double(0x22) / 255)
    static let noteMeta = Color(hex: "656E65")
    static let noteLink = Color(hex: "66705D")
    static let noteArtShadow = Color(hex: "252B26", opacity: Double(0x25) / 255)
    /// The room's own rows on the dark fill: first line and second line (also the failure copy).
    static let rowInk = Color(hex: "F1F5ED")
    static let rowSecondary = Color(hex: "C1CDB7")
    /// The manga leaf's solid key (`--mp-key`), used for the room's primary action.
    static let key = Color(hex: "2B342E")
    static let keyInk = Color(hex: "F8FAF7")
}

/// The room's metrics by its own width (PROTOTYPE_SPEC §5, 390 → 320). A room at most
/// `compactRoomWidth` wide (a 320 pt phone) tightens its padding, masthead gap, seal, headline and note
/// card; wider rooms keep the 390 values. Pure, pinned in RestyleLaneTests.
nonisolated struct ClubRoomMetrics: Equatable, Sendable {
    let horizontalPadding: CGFloat
    let mastheadGap: CGFloat
    let seal: CGFloat
    let headline: CGFloat
    let notePadding: CGFloat

    /// Rooms up to this width use the 320 metrics (the room is 280 pt at 320 and 350 pt at 390 with
    /// the page's 20 pt gutter; `KuroMediumSwitch.smallPhoneContainer` uses the same threshold).
    static let compactRoomWidth: CGFloat = 328

    static let regular = ClubRoomMetrics(horizontalPadding: 16, mastheadGap: 10, seal: 43, headline: 22, notePadding: 15)
    static let compact = ClubRoomMetrics(horizontalPadding: 12, mastheadGap: 8, seal: 36, headline: 19, notePadding: 13)

    /// An unmeasured room (`width` 0) keeps the regular metrics.
    static func forRoomWidth(_ width: CGFloat) -> ClubRoomMetrics {
        width > 0 && width <= compactRoomWidth ? .compact : .regular
    }
}

/// The dark room: `#252b28` under a radial `#444a46` glow from the top-left, a hairline border, the
/// inset top highlight, and the prototype's tight drop (`0 10px 20px -14px #10171066`): the negative
/// spread keeps it to a thin shade under the bottom edge, never a halo on the sides or top.
struct ClubRoomBackground: View {
    var cornerRadius: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(ClubRoomPalette.room)
            .overlay(
                RadialGradient(colors: [ClubRoomPalette.glow, ClubRoomPalette.glow.opacity(0)],
                               center: .topLeading, startRadius: 0, endRadius: 260)
                    .clipShape(shape)
            )
            .overlay(shape.strokeBorder(ClubRoomPalette.border, lineWidth: 1))
            .overlay(alignment: .top) {
                shape.stroke(Color.white.opacity(0x21 / 255.0), lineWidth: 1)
                    .mask(Rectangle().frame(height: 2).frame(maxHeight: .infinity, alignment: .top))
            }
            .background(
                // The spread of −14 pt: the drop's shape is inset 14 pt on every side, moved down 10 pt
                // and blurred, so only its lower edge shows below the room.
                shape.fill(ClubRoomPalette.drop)
                    .padding(14)
                    .offset(y: 10)
                    .blur(radius: 10)
            )
    }
}
