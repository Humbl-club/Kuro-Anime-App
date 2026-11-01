import KuroCore
import SwiftUI

// MARK: - Scene card (prototype Poster Home, PROTOTYPE_SPEC.md §4 "Scene card"; ref-home-busy-anime-390.png)
// One title in progress, the first two of the anime Home:
//   artwork window   full width, 350 × 107.7 at 390 (aspect 3.25), top corners 5, 1 pt #ffffff25 rim
//   season tab       #f3f4f4 face on the artwork's bottom-left (12 pt in), top corners 8: "SEASON"
//                    7 pt tracking .3 + the number 17 w550, #26372c. Omitted when the number is unknown.
//   material foot    the title's artwork material, 135° base → deep; 58 pt: title SF 17 w550
//                    tracking −0.35 #fafafa | 1 pt #ffffff24 rule | "Ep." 9 pt, count 19 w500, "/ 5"
//                    11 pt @ .8, 52 pt scrub (#ffffff1c track, #e9eeee trace) | raised light key
//   footer row       41 pt, 1 pt #ffffff0d top rule: one honest fact (New episode available / Up to
//                    date / the club members who wrote about it), else the row is omitted
// Card radius 5, shadow #19221b0a 0 1 2. At 320 pt (§5): foot padding 11, count 17, fact 9 pt.
// The artwork, the title and the key are three separate targets (never nested); the season tab is a
// fourth that opens the season overview.

/// The prototype's measured component inks (PROTOTYPE_SPEC.md §4). Statuses stay monochrome.
enum HomeInk {
    /// Opening kicker `#666c68`.
    static let kicker = Color(hex: "666C68")
    /// Quiet card border `#dce1dc`.
    static let quietBorder = Color(hex: "DCE1DC")
    /// Glance title and count `#303932`.
    static let glanceInk = Color(hex: "303932")
    /// Glance caption, count label and arrow `#687064`.
    static let glanceMuted = Color(hex: "687064")
    /// Glance card fill `#fffefa`.
    static let glanceFill = Color(hex: "FFFEFA")
    /// Glance border `#29312918`.
    static let glanceBorder = Color(hex: "293129", opacity: Double(0x18) / 255)
    /// Glance shadow `#29312905`.
    static let glanceShadow = Color(hex: "293129", opacity: Double(0x05) / 255)
    /// Season tab and S stamp face `#f3f4f4`, ink `#26372c`.
    static let tabFace = Color(hex: "F3F4F4")
    static let tabInk = Color(hex: "26372C")
    /// Scene foot title `#fafafa`; readout secondary `#dce3df`; footer fact `#dce2df`.
    static let footTitle = Color(hex: "FAFAFA")
    static let footSecondary = Color(hex: "DCE3DF")
    static let footFact = Color(hex: "DCE2DF")
    /// Scene scrub: track `#ffffff1c`, trace `#e9eeee`.
    static let footTrack = Color.white.opacity(Double(0x1C) / 255)
    static let footTrace = Color(hex: "E9EEEE")
    /// Caught-up key glyph on the scene foot `#b9c5c1`, elsewhere `#767b77` (`.step:disabled`).
    static let caughtUpOnArt = Color(hex: "B9C5C1")
    static let caughtUpOnPaper = Color(hex: "767B77")
    /// Also watching: unit `#5b635c`, scrub track `#d7d9d7`, trace `#626962`, poster fill `#e9e9e6`.
    static let tileUnit = Color(hex: "5B635C")
    static let tileTrack = Color(hex: "D7D9D7")
    static let tileTrace = Color(hex: "626962")
    static let posterFill = Color(hex: "E9E9E6")
    /// Medium switch: unselected word `#6e786f`, underline `#203027`, hairline `#20302744`, the
    /// selected word's fill under its artwork `#253a2a`.
    static let switchUnselected = Color(hex: "6E786F")
    static let switchMark = Color(hex: "203027")
    static let switchHairline = Color(hex: "203027", opacity: Double(0x44) / 255)
    static let switchUnlit = Color(hex: "253A2A")
}

/// Layout rules shared by the scene card and the Also watching tile (pure).
enum HomeSceneMetrics {
    /// The +1 key's fixed column: a 44 pt target that the title never shares.
    static let keyColumn: CGFloat = 44
    /// The artwork window's aspect (350 × 107.7 at 390, 290 × 89.2 at 320).
    static let artworkAspect: CGFloat = 3.25
    /// Narrow phones (≤ 360 pt, the prototype's `@media(max-width:360px)`), read from the content column.
    static func isCompact(columnWidth: CGFloat) -> Bool {
        columnWidth > 0 && columnWidth <= KuroMediumSwitch.smallPhoneContainer
    }
    /// Scene titles wrap to two lines (three at accessibility sizes), then truncate.
    static func sceneTitleLines(accessibility: Bool) -> Int { accessibility ? 3 : 2 }
    /// Also watching titles wrap to three lines (four at accessibility sizes), then truncate.
    static func tileTitleLines(accessibility: Bool) -> Int { accessibility ? 4 : 3 }
    /// Also watching columns: two, one at accessibility sizes so the key never overlaps the title.
    static func alsoWatchingColumns(accessibility: Bool) -> Int { accessibility ? 1 : 2 }
    /// The scene foot stacks the readout and key under the title at accessibility sizes.
    static func stacksSceneFoot(accessibility: Bool) -> Bool { accessibility }
}

/// The season tab on a scene's artwork (and the "S2" stamp on a tile). Pure.
struct HomeSeasonTab: Equatable {
    /// "Season" / "Staffel", or nil for a film.
    let word: String?
    /// The ladder number ("2"), or "Film".
    let number: String

    /// Nil when the ladder number is unknown: Home never invents "Season 1".
    static func make(sectionOrdinal: Int?, sectionKind: String?, german: Bool = KuroLocale.isGerman) -> HomeSeasonTab? {
        if sectionKind == "film" { return HomeSeasonTab(word: nil, number: "Film") }
        guard let sectionOrdinal, sectionOrdinal > 0 else { return nil }
        return HomeSeasonTab(word: german ? "Staffel" : "Season", number: String(sectionOrdinal))
    }

    static func make(_ card: HomeCard, german: Bool = KuroLocale.isGerman) -> HomeSeasonTab? {
        make(sectionOrdinal: card.sectionOrdinal, sectionKind: card.sectionKind, german: german)
    }
}

/// The one honest fact under a scene (pure).
enum HomeSceneFact: Equatable {
    case newUnit(String)
    case upToDate(String)
    /// Club members (real display names) who wrote about this title.
    case club(names: [String])

    static func make(hasNew: Bool, knownCaughtUp: Bool, clubNames: [String], medium: MediaKind,
                     german: Bool = KuroLocale.isGerman) -> HomeSceneFact? {
        if hasNew {
            switch (medium, german) {
            case (.anime, false): return .newUnit("New episode available")
            case (.anime, true): return .newUnit("Neue Folge verfügbar")
            case (.manga, false): return .newUnit("New chapter")
            case (.manga, true): return .newUnit("Neues Kapitel")
            }
        }
        if knownCaughtUp { return .upToDate(german ? "Auf dem neuesten Stand" : "Up to date") }
        let names = clubNames.prefix(2)
        return names.isEmpty ? nil : .club(names: Array(names))
    }

    /// "Mina + Jules".
    static func clubLine(_ names: [String]) -> String { names.joined(separator: " + ") }
}

/// The readout beside a key: unit word, count, total, and how far along the scrub is (pure values).
struct HomeProgressReadout: Equatable {
    /// "Ep." / "Folge" / "Ch." / "Kap.", or the caught-up word.
    let unit: String
    let value: String
    /// The catalogue total, when known (scene card only shows it).
    let total: Int?
    let caughtUp: Bool
    /// 0…1 when the total is known; nil hides the scrub.
    let fraction: Double?
    /// The spoken readout ("Episode 4 of 26").
    let spoken: String
}

/// The scene card (dumb view: HomeView owns tracking, routes and account scope).
struct HomeSceneCard<Key: View>: View {
    let title: String
    let artURL: URL?
    let material: ArtworkMaterial
    let season: HomeSeasonTab?
    let readout: HomeProgressReadout
    let fact: HomeSceneFact?
    let compact: Bool
    let onOpen: () -> Void
    let onSeason: () -> Void
    let onClub: () -> Void
    @ViewBuilder let key: () -> Key

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Button(action: onOpen) {
                    Color.clear
                        .aspectRatio(HomeSceneMetrics.artworkAspect, contentMode: .fit)
                        .overlay { HomeArtwork(url: artURL, maxPixelSize: 1200, placeholder: material.base.color) }
                        .clipped()
                        .overlay {
                            // `::after`: a 1 pt light rim and a soft shade toward the foot.
                            ZStack {
                                LinearGradient(colors: [.clear, Color.black.opacity(0.18)],
                                               startPoint: .center, endPoint: .bottom)
                                UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
                                    .strokeBorder(Color.white.opacity(Double(0x25) / 255), lineWidth: 1)
                            }
                            .allowsHitTesting(false)
                        }
                        .homeEntrance()
                }
                .buttonStyle(HomeArtworkPressStyle())
                // The foot's title button carries "Open <title>"; VoiceOver hears it once.
                .accessibilityHidden(true)
                if let season { seasonTab(season) }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
            foot
            if let fact { factRow(fact) }
        }
        .background(
            LinearGradient(colors: [material.base.color, material.deep.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: Color(hex: "19221B", opacity: Double(0x0A) / 255), radius: 1, y: 1)
        .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion) ? KuroMotion.medium : nil, value: material)
    }

    // MARK: Parts

    private func seasonTab(_ tab: HomeSeasonTab) -> some View {
        Button(action: onSeason) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                if let word = tab.word {
                    Text(word)
                        .font(.kuroCustom(7, relativeTo: .caption2, maxSize: 14))
                        .tracking(0.3)
                        .textCase(.uppercase)
                }
                Text(tab.number)
                    .font(.kuroCustom(tab.word == nil ? 13 : 17, weight: .semibold, relativeTo: .headline, maxSize: 28))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(HomeInk.tabInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(HomeInk.tabFace, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
            .shadow(color: Color.white.opacity(Double(0x65) / 255), radius: 0, y: -1)
            .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .accessibilityLabel(KuroLocale.text("\(title), \(tab.word.map { "\($0) \(tab.number)" } ?? tab.number). Show seasons",
                                            "\(title), \(tab.word.map { "\($0) \(tab.number)" } ?? tab.number). Staffeln zeigen"))
    }

    private var titleButton: some View {
        Button(action: onOpen) {
            Text(title)
                .font(.kuroCustom(17, weight: .semibold, relativeTo: .headline, maxSize: 34))
                .tracking(-0.35)
                .foregroundStyle(HomeInk.footTitle)
                .multilineTextAlignment(.leading)
                .lineLimit(HomeSceneMetrics.sceneTitleLines(accessibility: dynamicTypeSize.isAccessibilitySize))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KuroLocale.text("Open \(title)", "\(title) öffnen"))
    }

    @ViewBuilder
    private var foot: some View {
        if HomeSceneMetrics.stacksSceneFoot(accessibility: dynamicTypeSize.isAccessibilitySize) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                titleButton
                HStack(spacing: KuroDesignSpacing.sm) {
                    HomeSceneReadoutView(readout: readout, compact: compact)
                    Spacer(minLength: KuroDesignSpacing.sm)
                    key().frame(width: HomeSceneMetrics.keyColumn)
                }
            }
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, KuroDesignSpacing.sm)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x18) / 255)).frame(height: 1) }
        } else {
            HStack(alignment: .center, spacing: compact ? 7 : 8) {
                titleButton
                HStack(spacing: 2) {
                    HomeSceneReadoutView(readout: readout, compact: compact)
                    key().frame(width: HomeSceneMetrics.keyColumn, height: 44)
                }
                .padding(.leading, compact ? 8 : 12)
                .frame(minHeight: 48)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(Double(0x24) / 255)).frame(width: 1, height: 48)
                }
                .fixedSize()
            }
            .padding(.leading, compact ? 11 : 14)
            .padding(.trailing, 10)
            .frame(minHeight: 58)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x18) / 255)).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func factRow(_ fact: HomeSceneFact) -> some View {
        Group {
            switch fact {
            case .newUnit(let text), .upToDate(let text):
                Text(text)
                    .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
                    .foregroundStyle(HomeInk.footFact)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            case .club(let names):
                Button(action: onClub) {
                    HStack(spacing: 5) {
                        Text(String(names.first?.first.map(String.init) ?? ""))
                            .font(.kuroCustom(8, relativeTo: .caption2, maxSize: 14))
                            .frame(width: 17, height: 17)
                            .background(Color.white.opacity(Double(0x14) / 255), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(Double(0x44) / 255), lineWidth: 1))
                            .accessibilityHidden(true)
                        Text(HomeSceneFact.clubLine(names))
                            .font(.kuroCustom(compact ? 9 : 10, relativeTo: .caption2, maxSize: 22))
                            .lineLimit(1)
                        Text("›").font(.kuroCustom(12, relativeTo: .caption1, maxSize: 22)).accessibilityHidden(true)
                    }
                    .foregroundStyle(HomeInk.footFact)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(KuroLocale.text("\(HomeSceneFact.clubLine(names)) wrote about \(title)",
                                                    "\(HomeSceneFact.clubLine(names)) haben über \(title) geschrieben"))
            }
        }
        .padding(.leading, compact ? 11 : 14)
        .padding(.trailing, compact ? 10 : 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x0D) / 255)).frame(height: 1) }
    }
}

/// "Ep." over "4 / 5" over the scrub, white on the material foot.
struct HomeSceneReadoutView: View {
    let readout: HomeProgressReadout
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(readout.unit)
                .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                .foregroundStyle(HomeInk.footSecondary)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(readout.value)
                    .font(.kuroCustom(compact ? 17 : 19, weight: .medium, relativeTo: .title3, maxSize: 34))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .kuroCountRoll(value: readout.value)
                if let total = readout.total {
                    Text(" / \(total)")
                        .font(.kuroCustom(11, relativeTo: .caption1, maxSize: 20))
                        .foregroundStyle(HomeInk.footSecondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            HomeScrub(fraction: readout.fraction, track: HomeInk.footTrack, trace: HomeInk.footTrace)
                .frame(width: 52)
        }
        .frame(minWidth: 52, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.spoken)
    }
}

/// The prototype's 1 pt progress scrub; the trace widens over 280 ms `(.22,.8,.24,1)`, still under
/// Reduce Motion or Low Power. Hidden (no track) when the total is unknown.
struct HomeScrub: View {
    let fraction: Double?
    let track: Color
    let trace: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let fraction {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(track)
                    Rectangle().fill(trace)
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 1)
            .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
                       ? .timingCurve(0.22, 0.8, 0.24, 1, duration: 0.28) : nil, value: fraction)
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 1).accessibilityHidden(true)
        }
    }
}

/// A caught-up key: the prototype's disabled `.step` (no face, a quiet ✓), 44 × 44, not interactive.
struct HomeCaughtUpKey: View {
    let onArt: Bool
    let accessibilityText: String

    var body: some View {
        Image(systemName: "checkmark")
            .font(.kuroCustom(14, weight: .regular, relativeTo: .body, maxSize: 22))
            .foregroundStyle(onArt ? HomeInk.caughtUpOnArt : HomeInk.caughtUpOnPaper)
            .frame(width: 44, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityValue(KuroLocale.text("Caught up", "Auf dem neuesten Stand"))
    }
}

/// Remote artwork filling its frame; the material's base colour until (or unless) it loads, so the
/// window never flashes white.
struct HomeArtwork: View {
    let url: URL?
    let maxPixelSize: Int
    let placeholder: Color

    var body: some View {
        if let url {
            KuroCachedAsyncImage(url: url, maxPixelSize: maxPixelSize) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { placeholder }
            }
        } else {
            placeholder
        }
    }
}

/// Pressed artwork: `scale(.987)` and brightness .92 (§3.3), 120 ms; still under Reduce Motion.
struct HomeArtworkPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.987 : 1)
            .animation(reduceMotion ? nil : KuroMotion.contact, value: configuration.isPressed)
    }
}

/// The anime section entrance (§3.2): artwork rises from opacity .8 / 9 pt over 380 ms
/// `(.2,.75,.25,1)`, once per mount (Home remounts per medium). Reduce Motion and Low Power show the
/// final frame.
private struct HomeEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    func body(content: Content) -> some View {
        let plays = KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
        content
            .opacity(settled || !plays ? 1 : 0.8)
            .offset(y: settled || !plays ? 0 : 9)
            .onAppear {
                guard !settled else { return }
                if plays {
                    withAnimation(.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.38)) { settled = true }
                } else {
                    settled = true
                }
            }
    }
}

extension View {
    func homeEntrance() -> some View { modifier(HomeEntranceModifier()) }
}
