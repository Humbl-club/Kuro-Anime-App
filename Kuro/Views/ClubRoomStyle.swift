import SwiftUI

// MARK: - Club room style
// The prototype's club-room language (PROTOTYPE_SPEC §4 "Club room", §5 width changes), shared by the
// Clubs invitation (`ClubsView`), the club-detail room (hero, initial state, art strip) and Home's club
// room (`HomeClubRoom`), so a club keeps one room colour from Home and the invitation to its detail page.

/// The club room's monochrome gallery palette (2026-11-20 neutral charcoal pass).
enum ClubRoomPalette {
    static let room = Color(hex: "18181A")
    static let glow = Color(hex: "2C2C30")
    static let border = Color.white.opacity(0.12)
    static let text = Color(hex: "F7F7F8")
    static let kicker = Color.white.opacity(0.62)
    static let seal = Color.white.opacity(0.38)
    static let note = Color(hex: "FAFAFB")
    static let noteInk = Color(hex: "18181A")
    static let quiet = Color(hex: "F0F0F2")
    static let quietBorder = Color.black.opacity(0.10)
    static let quietInk = Color(hex: "4A4A4E")
    static let footer = Color.white.opacity(0.58)
    static let footerRule = Color.white.opacity(0.12)
    static let drop = Color.black.opacity(0.32)
    static let sealKnot = Color.white.opacity(0.85)
    static let memberInk = Color(hex: "18181A")
    static let memberRim = Color(hex: "18181A")
    static let memberFills: [Color] = [Color(hex: "ECECEF"), Color(hex: "D6D6DC"), Color(hex: "BABCBE")]
    static let noteBorder = Color.white.opacity(Double(0x88) / 255)
    static let noteShadow = Color.black.opacity(Double(0x22) / 255)
    static let noteMeta = Color(hex: "6B6B70")
    static let noteLink = Color(hex: "3A3A3E")
    static let noteArtShadow = Color.black.opacity(0.18)
    static let rowInk = Color(hex: "F4F4F6")
    static let rowSecondary = Color.white.opacity(0.66)
    static let key = Color(hex: "2A2A2E")
    static let keyInk = Color(hex: "FAFAFB")
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
/// `topCornerRadius` (the club page's full-bleed hero: square top, rounded foot) draws the same room on
/// an uneven shape; without it the room is the plain rounded rectangle Home has always drawn.
struct ClubRoomBackground: View {
    var cornerRadius: CGFloat = 24
    var topCornerRadius: CGFloat? = nil

    var body: some View {
        if let topCornerRadius {
            ClubRoomSurface(shape: UnevenRoundedRectangle(topLeadingRadius: topCornerRadius,
                                                          bottomLeadingRadius: cornerRadius,
                                                          bottomTrailingRadius: cornerRadius,
                                                          topTrailingRadius: topCornerRadius,
                                                          style: .continuous))
        } else {
            ClubRoomSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// The room's layers on any insettable shape (one recipe for the rounded room and the hero's foot).
private struct ClubRoomSurface<S: InsettableShape>: View {
    let shape: S

    var body: some View {
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

// MARK: - Seal & crests

/// Minimal geometric club emblems selectable when starting a club.
enum ClubCrest: String, CaseIterable, Identifiable, Sendable {
    case knot, torii, moon, diamond, flame, lantern

    var id: String { rawValue }

    func label(german: Bool) -> String {
        switch self {
        case .knot: return german ? "Siegel" : "Seal"
        case .torii: return german ? "Säule" : "Arch"
        case .moon: return german ? "Mond" : "Moon"
        case .diamond: return german ? "Karo" : "Diamond"
        case .flame: return german ? "Flamme" : "Flame"
        case .lantern: return german ? "Stern" : "Spark"
        }
    }

    var symbolName: String? {
        switch self {
        case .knot: return nil
        case .torii: return "building.columns"
        case .moon: return "moon.stars"
        case .diamond: return "suit.diamond"
        case .flame: return "flame"
        case .lantern: return "sparkles"
        }
    }
}

/// Device persistence for per-club crest emblems (`ClubCrest`).
enum ClubCrestStore {
    private static func storageKey(_ clubId: String) -> String {
        "kuro.club.crest.\(clubId.lowercased())"
    }

    static func crest(for clubId: String?, defaults: UserDefaults = .standard) -> ClubCrest {
        guard let clubId = clubId?.trimmingCharacters(in: .whitespacesAndNewlines), !clubId.isEmpty,
              let raw = defaults.string(forKey: storageKey(clubId)),
              let crest = ClubCrest(rawValue: raw) else {
            return .knot
        }
        return crest
    }

    static func setCrest(_ crest: ClubCrest, for clubId: String, defaults: UserDefaults = .standard) {
        let trimmed = clubId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(crest.rawValue, forKey: storageKey(trimmed))
    }
}

/// The club seal: 36 pt ring (30 on small phones) framing `ClubKnot` (default) or another chosen `ClubCrest`.
struct ClubSeal: View {
    let ring: CGFloat
    var crest: ClubCrest = .knot

    /// Measured on Home's room: 36 pt (G§14.2).
    static let regularRing: CGFloat = 36
    /// Measured on Home's room at 320: 30 pt.
    static let compactRing: CGFloat = 30

    static func ring(compact: Bool) -> CGFloat { compact ? compactRing : regularRing }

    var body: some View {
        ZStack {
            Circle().strokeBorder(ClubRoomPalette.seal, lineWidth: 1)
            if let symbol = crest.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: ring * 0.42, weight: .medium))
                    .foregroundStyle(ClubRoomPalette.sealKnot)
            } else {
                ClubKnot()
                    .stroke(ClubRoomPalette.sealKnot, lineWidth: 0.9 * 28 / 40)
                    .frame(width: ring * (28.0 / 36.0), height: ring * (28.0 / 36.0))
            }
        }
        .frame(width: ring, height: ring)
        .rotationEffect(crest == .knot ? .degrees(-12) : .zero)
    }
}

/// `M9 9h22v22H9zM14 14h12v12H14zM4 20h10M26 20h10M20 4v10M20 26v10` on a 40 × 40 grid.
struct ClubKnot: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 40
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.addRect(CGRect(origin: point(9, 9), size: CGSize(width: 22 * unit, height: 22 * unit)))
        path.addRect(CGRect(origin: point(14, 14), size: CGSize(width: 12 * unit, height: 12 * unit)))
        for (from, to) in [((4, 20), (14, 20)), ((26, 20), (36, 20)), ((20, 4), (20, 14)), ((20, 26), (20, 36))] {
            path.move(to: point(CGFloat(from.0), CGFloat(from.1)))
            path.addLine(to: point(CGFloat(to.0), CGFloat(to.1)))
        }
        return path
    }
}
