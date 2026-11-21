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
//   footer row       41 pt, 1 pt #ffffff0d top rule: one honest fact (the club members who wrote
//                    about it / New episode available / Up to date), else the row is omitted
// Card radius 5, shadow #19221b0a 0 1 2. At 320 pt (§5): foot padding 11, count 17, fact 9 pt.
// The artwork, the title and the key are three separate targets (never nested); the season tab is a
// fourth that opens the season overview.

/// Home's component inks: neutral monochrome on gallery white (2026-11-20; the prototype's sage
/// casts are retired). Statuses stay monochrome.
enum HomeInk {
    /// Opening kicker.
    static let kicker = Color(hex: "6B6B6B")
    /// Quiet card border.
    static let quietBorder = Color.black.opacity(0.09)
    /// Glance title and count.
    static let glanceInk = Color(hex: "18181A")
    /// Glance caption, count label and arrow.
    static let glanceMuted = Color(hex: "6B6B6B")
    /// Glance card fill.
    static let glanceFill = Color(hex: "FFFFFF")
    /// Glance border.
    static let glanceBorder = Color.black.opacity(0.09)
    /// Glance shadow.
    static let glanceShadow = Color.black.opacity(0.03)
    /// Season tab and S stamp face, and its ink.
    static let tabFace = Color(hex: "F4F4F5")
    static let tabInk = Color(hex: "18181A")
    /// Scene foot title; readout secondary; footer fact.
    static let footTitle = Color(hex: "FAFAFA")
    static let footSecondary = Color.white.opacity(0.78)
    static let footFact = Color.white.opacity(0.78)
    /// Scene scrub: track, trace.
    static let footTrack = Color.white.opacity(Double(0x1C) / 255)
    static let footTrace = Color.white.opacity(0.92)
    /// Caught-up key glyph on the scene foot, elsewhere.
    static let caughtUpOnArt = Color.white.opacity(0.7)
    static let caughtUpOnPaper = Color(hex: "7A7A7C")
    /// Also watching: unit, scrub track, trace, poster fill.
    static let tileUnit = Color(hex: "5C5C5E")
    static let tileTrack = Color.black.opacity(0.10)
    static let tileTrace = Color.kuroControlInk
    static let posterFill = Color(hex: "EDEDEF")
    /// Medium switch: unselected word, underline, hairline, the selected word's fill under its artwork.
    static let switchUnselected = Color(hex: "8E8E93")
    static let switchMark = Color(hex: "18181A")
    static let switchHairline = Color.black.opacity(0.12)
    static let switchUnlit = Color(hex: "18181A")
    /// Calendar heading summary.
    static let calendarSummary = Color(hex: "6B6B6B")
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

    /// Order (the prototype's second scene carries the club link in every reference state): real club
    /// names first, then a released unit not reached yet, then known caught up, else nothing. The
    /// opening line still counts every new unit, so a club line never hides one from the page.
    static func make(hasNew: Bool, knownCaughtUp: Bool, clubNames: [String], medium: MediaKind,
                     german: Bool = KuroLocale.isGerman) -> HomeSceneFact? {
        let names = clubNames.prefix(2)
        if !names.isEmpty { return .club(names: Array(names)) }
        if hasNew {
            switch (medium, german) {
            case (.anime, false): return .newUnit("New episode available")
            case (.anime, true): return .newUnit("Neue Folge verfügbar")
            case (.manga, false): return .newUnit("New chapter")
            case (.manga, true): return .newUnit("Neues Kapitel")
            }
        }
        if knownCaughtUp { return .upToDate(german ? "Auf dem neuesten Stand" : "Up to date") }
        return nil
    }

    /// "Mina + Jules".
    static func clubLine(_ names: [String]) -> String { names.joined(separator: " + ") }

    /// VoiceOver: "Mina wrote about Frieren"; German agrees with the number of names ("Mina hat",
    /// "Mina + Jules haben über Frieren geschrieben").
    static func clubSpoken(_ names: [String], title: String, german: Bool = KuroLocale.isGerman) -> String {
        let who = clubLine(names)
        guard german else { return "\(who) wrote about \(title)" }
        return "\(who) \(names.count == 1 ? "hat" : "haben") über \(title) geschrieben"
    }
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
    var zoomSourceID: String? = nil
    var nextRelease: ReleaseScheduleItem? = nil
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
                        .kuroZoomSource(zoomSourceID)
                        .overlay {
                            // `::after`: a 1 pt light rim and a soft shade toward the foot.
                            ZStack {
                                LinearGradient(colors: [.clear, Color.black.opacity(0.18)],
                                               startPoint: .center, endPoint: .bottom)
                                UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
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
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous))
            foot
            if let fact { factRow(fact) }
            if let nextRelease {
                releaseStrip(nextRelease)
            }
        }
        .background(
            LinearGradient(colors: [material.base.color, material.deep.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
            // The measured face: 31 pt tall (padding 7/8), the word and number centred in it.
            .frame(minHeight: 31)
            .fixedSize(horizontal: false, vertical: true)
            .background(HomeInk.tabFace, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
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
                // The progress control is a fixed 112 pt column (12 + readout + 2 + key), so a
                // caught-up readout never moves the divider; it grows only for larger text.
                .frame(minWidth: compact ? 104 : 112, minHeight: 48, alignment: .leading)
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
                .accessibilityLabel(HomeSceneFact.clubSpoken(names, title: title))
            }
        }
        .padding(.leading, compact ? 11 : 14)
        .padding(.trailing, compact ? 10 : 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x0D) / 255)).frame(height: 1) }
    }

    @ViewBuilder
    private func releaseStrip(_ item: ReleaseScheduleItem) -> some View {
        let copy = ReleaseCopy.current()
        if item.isDisplayable && copy.isAhead(item) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.kuroCustom(compact ? 8 : 9, weight: .medium, relativeTo: .caption2, maxSize: 16))
                    .foregroundStyle(HomeInk.footSecondary)
                    .accessibilityHidden(true)
                KuroReleaseLine(
                    item,
                    font: .kuroCustom(compact ? 9 : 10, weight: .medium, relativeTo: .caption2, maxSize: 20),
                    color: HomeInk.footFact,
                    liveCountdown: true
                )
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.leading, compact ? 11 : 14)
            .padding(.trailing, compact ? 10 : 12)
            .padding(.vertical, 3)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x0D) / 255)).frame(height: 1) }
        }
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
                // The caught-up word is long in German ("Auf dem neuesten Stand"): it wraps inside the
                // readout's column instead of widening the foot and squeezing the title.
                .lineLimit(readout.caughtUp ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: readout.caughtUp ? 54 : nil, alignment: .leading)
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
                        .monospacedDigit()
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
                let clamped = min(1, max(0, fraction))
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(track)
                    Capsule(style: .continuous).fill(trace)
                        .frame(width: clamped > 0 ? max(4, geo.size.width * clamped) : 0)
                }
            }
            .frame(height: 2.5)
            .animation(KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
                       ? .timingCurve(0.22, 0.8, 0.24, 1, duration: 0.28) : nil, value: fraction)
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 2.5).accessibilityHidden(true)
        }
    }
}

/// A caught-up key: the prototype's disabled `.step`, 44 × 44, not interactive.
struct HomeCaughtUpKey: View {
    let onArt: Bool
    let accessibilityText: String

    var body: some View {
        Image(systemName: "checkmark")
            .font(.kuroCustom(12, weight: .semibold, relativeTo: .body, maxSize: 20))
            .foregroundStyle(onArt ? HomeInk.caughtUpOnArt : HomeInk.caughtUpOnPaper)
            .frame(width: 44, height: 44)
            .background { ghostFace.accessibilityHidden(true) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityValue(KuroAdvanceCopy.caughtUpLabel(title: nil, german: KuroLocale.isGerman))
    }

    @ViewBuilder
    private var ghostFace: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if !onArt {
            shape
                .fill(Color.kuroControlFill)
                .overlay(shape.strokeBorder(Color.kuroKeyRim, lineWidth: 1))
                .frame(width: 34, height: 34)
        } else {
            ZStack {
                shape
                    .fill(Color.black)
                    .shadow(color: Color(hex: "142319", opacity: Double(0x12) / 255), radius: 1, y: 1)
                    .mask {
                        Rectangle().padding(-6)
                            .overlay { shape.blendMode(.destinationOut) }
                            .compositingGroup()
                    }
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(Double(0x35) / 255), .clear],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)),
                    lineWidth: 1)
            }
            .frame(width: 34, height: 34)
        }
    }
}

/// Remote artwork filling its frame; the material's base colour or soft wash until (or unless) it
/// loads, so thumbnails never flash blank white.
struct HomeArtwork: View {
    let url: URL?
    let maxPixelSize: Int
    let placeholder: Color
    var seedHex: String? = nil
    var usesMaterialWash: Bool = false

    @Environment(ArtworkMaterialStore.self) private var materials: ArtworkMaterialStore?

    private var resolvedPlaceholder: Color {
        guard seedHex != nil || usesMaterialWash else { return placeholder }
        if let materials {
            return materials.placeholderFill(for: url, seedHex: seedHex, fallback: placeholder)
        }
        if let seedHex, let rgb = KuroRGB(hex: seedHex) {
            return ArtworkMaterial(base: ArtworkMaterial.clamped(rgb), method: "seed-hex").wash.color
        }
        return placeholder
    }

    var body: some View {
        if let url {
            KuroCachedAsyncImage(url: url, maxPixelSize: maxPixelSize) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { resolvedPlaceholder }
            }
        } else {
            resolvedPlaceholder
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
