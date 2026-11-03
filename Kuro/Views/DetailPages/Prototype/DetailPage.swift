import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - The one detail page: shared chrome (prototype fidelity, Task 6)
// Reference: docs/prototype-fidelity/reference/ref-detail-anime-390.png, PROTOTYPE_SPEC.md §4 (Detail
// sheet, D1 Hero), LANE_AMENDMENTS.md 1-2.
// - Paper stays neutral (#f5f5f4 anime). The artwork material appears only as `base → deep` on the hero
//   band, the close control, the current season tile, the Up next key and the song panel, and as
//   `wash`/`edge` on the progress card and the Up next row.
// - Type is SF (system sans) at the prototype's sizes and tracking; the serif is used only where the
//   prototype uses Georgia ("Between us." on this page).
// - The status mark (spec §50): tapping "○ Watching" opens List settings; the mark's own menu (touch and
//   hold, and VoiceOver's actions) holds Favourite/Remove, Verdict, Where to watch, Add to a club and
//   Share. Nothing the live dock offered is removed, and no extra key sits beside the mark.
// - Motion: every disclosure, scroll jump and toast goes through `KuroMotion.detail(_:reduceMotion:)`,
//   so Reduce Motion and Low Power show the final frame.

/// The prototype's measured detail colours (PROTOTYPE_SPEC.md §4, detail tables).
enum DetailInk {
    static let eyebrow = Color(hex: "68776F")
    static let disclosure = Color(hex: "59685F")
    static let synopsis = Color(hex: "58635B")
    static let expectation = Color(hex: "56635B")
    static let clubRow = Color(hex: "526459")
    static let avatarFill = Color(hex: "D3DED3")
    /// `.tiny-people i:nth-child(1…3)`: the prototype's three member fills, cycled by index.
    static let avatarFills = ["D3DED3", "E2E3D7", "C8D4CE"]
    static let avatarInk = Color(hex: "3C5041")
    static let count = Color(hex: "727873")
    static let tileInk = Color(hex: "7B847E")
    static let tileBorder = Color(hex: "D9DEDB")
    static let tileFillBottom = Color(hex: "EEF1EE")
    static let thread = Color(hex: "BECBC0")
    static let threadStem = Color(hex: "718A78")
    static let progressLabel = Color(hex: "5A695F")
    static let progressCaption = Color(hex: "6B776D")
    static let track = Color(hex: "D7D9D7")
    static let rowRule = Color(hex: "344A39", opacity: Double(0x14) / 255)
    static let upNextKicker = Color(hex: "526D56")
    static let finished = Color(hex: "79847B")
    static let finishedState = Color(hex: "6C766E")
    static let moreLink = Color(hex: "495E50")
    static let sourceRule = Color(hex: "364B36", opacity: Double(0x20) / 255)
    static let bookInk = Color(hex: "516149")
    static let bookBorder = Color(hex: "B6C1AC")
    static let bookSpine = Color(hex: "D6DBCE")
    static let bookPage = Color(hex: "FAFAF0")
    static let author = Color(hex: "6C786A")
    static let note = Color(hex: "7A8576")
    static let soundInk = Color(hex: "F0F5F1")
    static let soundKicker = Color(hex: "B0C3B5")
    static let soundArtist = Color(hex: "B4C6BA")
    static let soundArrow = Color(hex: "C1D4C6")
    static let soundNote = Color(hex: "A9BEB0")
    static let castNote = Color(hex: "738076")
    static let portrait = Color(hex: "E3E8E2")
    static let creditRole = Color(hex: "69766C")
    static let creditRule = Color(hex: "26382E", opacity: Double(0x14) / 255)
    static let kicker = Color(hex: "C6CECA")
    static let statusInk = Color(hex: "DAE4DF")
}

extension KuroMotion {
    /// The page's animation, or nil (the final frame at once) under Reduce Motion or Low Power.
    static func detail(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        playsMotionNow(reduceMotion: reduceMotion) ? animation : nil
    }
}

/// SF at a prototype size that still follows Dynamic Type (capped so AX sizes stay legible).
extension Font {
    static func detailSF(_ size: CGFloat, _ weight: Font.Weight = .regular,
                         relativeTo style: UIFont.TextStyle = .body) -> Font {
        .kuroCustom(size, weight: weight, relativeTo: style, maxSize: max(size * 2.2, 22))
    }
}

extension Font {
    /// Georgia, where the prototype sets Georgia (LANE_AMENDMENTS 1): the manga title, hook, "Your
    /// bookmark", chapter numbers (italic), "Seen the anime?" and "Between us.". Scales with Dynamic Type
    /// like `kuroCustom` (capped at 1.75×). The shared `kuroEditorial` token stays the system serif.
    static func detailGeorgia(_ size: CGFloat, italic: Bool = false, relativeTo style: UIFont.TextStyle? = nil) -> Font {
        let textStyle: UIFont.TextStyle
        if let style { textStyle = style } else {
            switch size {
            case 28...: textStyle = .title1
            case 22..<28: textStyle = .title2
            case 17..<22: textStyle = .title3
            default: textStyle = .body
            }
        }
        let scaled = min(KuroTypeScale.current.scaled(size, relativeTo: textStyle), size * 1.75)
        return .custom(italic ? "Georgia-Italic" : "Georgia", fixedSize: scaled)
    }
}

extension View {
    /// Pads one line of SF text to the prototype's CSS line height (SwiftUI sets the font's own line
    /// height, a few points shorter), so rows reach their measured heights. Scales with the type size.
    func detailLineHeight(_ lineHeight: CGFloat, size: CGFloat, relativeTo style: UIFont.TextStyle = .body) -> some View {
        let scaled = min(KuroTypeScale.current.scaled(size, relativeTo: style), max(size * 2.2, 22))
        let natural = UIFont.systemFont(ofSize: scaled).lineHeight
        let pad = max(0, (lineHeight / size * scaled - natural) / 2)
        return padding(.vertical, pad)
    }
}

/// The detail's small uppercase eyebrow ("SEASON 2", "THE ORIGINAL STORY").
struct DetailEyebrow: View {
    let text: String
    var size: CGFloat = 8
    var tracking: CGFloat = 1.4

    var body: some View {
        Text(text.uppercased())
            .font(.detailSF(size, .semibold, relativeTo: .caption2))
            .tracking(tracking)
            .foregroundStyle(DetailInk.eyebrow)
    }
}

/// A section heading: SF 17 w550 (semibold, the nearest weight), tracking −0.4 (18/−0.7 for "Seasons"),
/// with an optional quiet note.
struct DetailSectionHeading: View {
    let title: String
    var size: CGFloat = 17
    var tracking: CGFloat = -0.4
    var note: String? = nil

    var body: some View {
        // Large type: the note goes under the title instead of breaking the title inside a word.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                heading.fixedSize()
                Spacer(minLength: 8)
                noteText
            }
            VStack(alignment: .leading, spacing: 4) {
                heading.fixedSize(horizontal: false, vertical: true)
                noteText
            }
        }
    }

    private var heading: some View {
        Text(title)
            .font(.detailSF(size, .semibold, relativeTo: .title3))
            .tracking(tracking)
            .foregroundStyle(Color.kuroInk)
            // 17/23.8 and 18/25.2 as measured.
            .detailLineHeight(size * 1.4, size: size, relativeTo: .title3)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var noteText: some View {
        if let note {
            Text(note)
                .font(.detailSF(size >= 18 ? 10 : 9, relativeTo: .caption2))
                .foregroundStyle(size >= 18 ? DetailInk.count : DetailInk.castNote)
        }
    }
}

// MARK: - Hero

/// D1: the wide artwork fading into `deep`, then the band with kind kicker, title and status mark.
/// Details-songs §6.2 (additive): the band is Home's scene foot, with two optional fact rows under the
/// title (the facts line, then the next-release row with its bell) and Home's season tab on the art's
/// bottom-left edge. VoiceOver reads the hero in order: title, mark, facts, next row, bell, tab.
struct DetailHero<Mark: View>: View {
    let artworkURL: URL?
    let kicker: String
    let title: String
    let material: ArtworkMaterial
    var facts: [DetailFacts.Part] = []
    var nextRow: AnyView? = nil
    var seasonTab: AnyView? = nil
    @ViewBuilder let mark: () -> Mark
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(artworkURL: URL?, kicker: String, title: String, material: ArtworkMaterial,
         facts: [DetailFacts.Part] = [], nextRow: AnyView? = nil, seasonTab: AnyView? = nil,
         @ViewBuilder mark: @escaping () -> Mark) {
        self.artworkURL = artworkURL
        self.kicker = kicker
        self.title = title
        self.material = material
        self.facts = facts
        self.nextRow = nextRow
        self.seasonTab = seasonTab
        self.mark = mark
    }

    var body: some View {
        VStack(spacing: 0) {
            artwork
                .overlay(alignment: .bottomLeading) {
                    if let seasonTab {
                        // Read after the bell (§6.11): the tab is visually first but secondary.
                        seasonTab.accessibilitySortPriority(-1)
                    }
                }
            heading
        }
        .background(
            LinearGradient(colors: [material.base.color, material.deep.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .accessibilityElement(children: .contain)
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(354.0 / 150.6, contentMode: .fit)
            .overlay {
                if let artworkURL {
                    KuroCachedAsyncImage(url: artworkURL, maxPixelSize: 1400) { phase in
                        if case .success(let image) = phase {
                            // The prototype's `object-position: 50% 18%`: a portrait cover shows its upper
                            // part (faces), not the middle.
                            GeometryReader { frame in
                                Color.clear.overlay(alignment: .top) {
                                    image.resizable().scaledToFill()
                                        .alignmentGuide(.top) { d in max(0, d.height - frame.size.height) * 0.18 }
                                }
                            }
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .overlay {
                // The prototype's ::after: transparent for the top half, then into `deep`.
                LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                       .init(color: material.deep.color, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            if !facts.isEmpty {
                DetailFactsLine(parts: facts)
                    .padding(.top, 10)
            }
            if let nextRow {
                nextRow.padding(.top, facts.isEmpty ? 10 : 12)
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(material.deep.color)
    }

    private var titleRow: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    titleBlock
                    mark()
                }
            } else {
                // Side by side while the title keeps at least 140 pt beside the mark; otherwise the mark
                // goes under the title (the prototype's ≤360 single column, and long German marks).
                ViewThatFits(in: .horizontal) {
                    // The prototype's grid centres the mark on the title's (last) line.
                    HStack(alignment: .bottom, spacing: 12) {
                        titleBlock
                            .frame(minWidth: 140, idealWidth: 140, maxWidth: .infinity, alignment: .leading)
                        mark()
                            .padding(.bottom, 8)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        titleBlock
                        mark()
                    }
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker.uppercased())
                .font(.detailSF(8, relativeTo: .caption2))
                .tracking(1.7)
                .foregroundStyle(DetailInk.kicker)
            Text(title)
                .font(.detailSF(27, .semibold, relativeTo: .title1))
                .tracking(-1.1)
                .foregroundStyle(Color.white)
                // Review focus 1: two lines, then truncate (never under the status mark).
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .layoutPriority(1)
    }
}

// MARK: - Status mark

/// The hero's status mark ("○ Watching" / "Not in your list" + Add), spec §50: a tap on the mark opens
/// List settings (the tracking editor, which also offers the status choice for an untracked title); the
/// mark's own menu (touch and hold) holds Favourite/Remove, Verdict, Where to watch, Add to a club and
/// Share, and VoiceOver gets the same actions as custom actions. No separate key sits beside it.
struct DetailStatusMark: View {
    let entry: LibraryEntry?
    var kind: MediaKind = .anime
    let onListSettings: () -> Void
    let onFavourite: () -> Void
    let onVerdict: () -> Void
    let onProviders: () -> Void
    var onAddToClub: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    /// `.onArt` on the anime's dark band; `.onPaper` on the manga's light folio band.
    var tone: DetailMarkTone = .onArt

    /// The prototype's 5 pt ring, scaled with the label so it never shrinks beside large type.
    @ScaledMetric(relativeTo: .caption) private var ring: CGFloat = 5

    private var isTracked: Bool { entry != nil }
    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        // German untracked ("Nicht in deiner Liste" + "Hinzufügen") is wider than a narrow hero column:
        // Add then drops under the mark instead of clipping.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                markMenu
                addButton.padding(.leading, 10)
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 4) {
                markMenu
                addButton
            }
            .fixedSize()
        }
    }

    /// The mark's actions besides List settings (its own tap), in menu order.
    private var menuActions: [DetailStatusAction] {
        DetailStatusCopy.actions(isTracked: isTracked).filter { $0 != .listSettings }
    }

    /// The mark's minimum touch height.
    static let targetHeight: CGFloat = 44

    /// The visible mark: ring and status word, at its own 14 pt line.
    private var markFace: some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(tone.ink, lineWidth: 1)
                .frame(width: min(ring, 12), height: min(ring, 12))
            Text(DetailStatusCopy.label(status: entry?.status, kind: kind, german: german))
                .font(.detailSF(10, relativeTo: .caption1))
                .foregroundStyle(tone.ink)
                .lineLimit(1)
        }
    }

    /// The band lays out the mark at its own line height (an invisible copy of the face holds the
    /// place), and the menu sits over it in an overlay at its own 44 pt frame. The overlay adds no
    /// layout height, and the menu's frame (UIKit-backed or not) is the full 44 pt target, centred on
    /// the mark, so the touch area never depends on negative padding.
    private var markMenu: some View {
        markFace
            .hidden()
            .accessibilityHidden(true)
            .overlay { markMenuControl.fixedSize() }
    }

    private var markMenuControl: some View {
        Menu {
            ForEach(menuActions, id: \.self) { action in
                if handler(action) != nil {
                    // Removing a saved title drops its progress, notes and score: marked destructive
                    // (and the page asks first, with Undo after).
                    Button(role: action == .favourite && isTracked ? .destructive : nil) {
                        handler(action)?()
                    } label: {
                        Label(DetailStatusCopy.actionTitle(action, isTracked: isTracked, kind: kind, german: german),
                              systemImage: icon(action))
                    }
                }
            }
        } label: {
            markFace
                .frame(minWidth: 44, minHeight: Self.targetHeight)
                .contentShape(Rectangle())
        } primaryAction: {
            onListSettings()
        }
        .menuStyle(.button)
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(DetailStatusCopy.label(status: entry?.status, kind: kind, german: german))
        .accessibilityHint(isTracked
                           ? KuroLocale.text("Opens list settings. Touch and hold for more actions.",
                                             "Öffnet die Listeneinstellungen. Gedrückt halten für weitere Aktionen.")
                           : KuroLocale.text("Opens the status choice. Touch and hold for more actions.",
                                             "Öffnet die Statusauswahl. Gedrückt halten für weitere Aktionen."))
        .accessibilityActions {
            ForEach(menuActions, id: \.self) { action in
                if let run = handler(action) {
                    Button(DetailStatusCopy.actionTitle(action, isTracked: isTracked, kind: kind, german: german), action: run)
                }
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
            if !isTracked {
                Button(action: onListSettings) {
                    Text(KuroLocale.text("Add", "Hinzufügen"))
                        .font(.detailSF(11, .medium, relativeTo: .caption1))
                        .foregroundStyle(tone.addInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .overlay(Capsule().strokeBorder(tone.addInk.opacity(0.45), lineWidth: 1))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
                .padding(.vertical, -8)
                .accessibilityLabel(KuroLocale.text("Add to your list", "Zur Liste hinzufügen"))
            }
    }

    /// The closure each action runs (internal for the wiring test); nil only for an optional action
    /// the page did not pass.
    func handler(_ action: DetailStatusAction) -> (() -> Void)? {
        switch action {
        case .listSettings: return onListSettings
        case .favourite: return onFavourite
        case .verdict: return onVerdict
        case .providers: return onProviders
        case .addToClub: return onAddToClub
        case .share: return onShare
        }
    }

    private func icon(_ action: DetailStatusAction) -> String {
        switch action {
        case .listSettings: return isTracked ? "slider.horizontal.3" : "plus"
        case .favourite: return isTracked ? "heart.fill" : "heart"
        case .verdict: return "tag"
        case .providers: return "play"
        case .addToClub: return "person.2"
        case .share: return "square.and.arrow.up"
        }
    }
}

/// The status mark's ink: light on the anime's material band, folio green on the manga's paper band.
enum DetailMarkTone: Equatable, Sendable {
    case onArt, onPaper

    var ink: Color { self == .onArt ? DetailInk.statusInk : Color(hex: "626B5A") }
    var addInk: Color { self == .onArt ? Color.white : Color.kuroInk }
}

// MARK: - Close

/// The prototype's round close (44 pt, `base` fill, a soft white rim, white ×).
struct DetailCloseButton: View {
    /// nil on the loader's loading and failed states (a neutral paper key, no artwork yet).
    let material: ArtworkMaterial?
    /// The manga sheet's close is paper (`#edeedf`, 94 %) with a folio-green ×.
    var fill: Color? = nil
    var ink: Color = .white
    @Environment(\.dismiss) private var dismiss
    /// Inside a journey ✕ closes the whole journey (navigation contract N3), never just one level.
    @Environment(\.kuroJourney) private var journey

    var body: some View {
        Button(action: { if let journey { journey.closeOrDismiss { dismiss() } } else { dismiss() } }) {
            Image(systemName: "xmark")
                .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 20))
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background(fill ?? material?.base.color ?? Color(hex: "EDEEEC"), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0x45 / 255.0), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(KuroLocale.text("Close details", "Details schließen"))
        .padding(.top, 12)
        .padding(.trailing, 12)
    }
}

// MARK: - Club avatars

/// Overlapping initials (prototype `.tiny-people`): 25 pt circles, 2 pt paper rim, −4 pt overlap.
struct DetailAvatars: View {
    let names: [String]
    var size: CGFloat = 25
    var rim: Color = Color(hex: "F4F5F0")

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { index, name in
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    // A fixed size: the discs are decorative (hidden from VoiceOver), and a scaled initial
                    // would spill out of a fixed circle at accessibility sizes.
                    .font(.system(size: size > 23 ? 9 : 8))
                    .foregroundStyle(DetailInk.avatarInk)
                    .frame(width: size - 4, height: size - 4)
                    .background(Color(hex: Self.fillHex(index)), in: Circle())
                    .overlay(Circle().strokeBorder(rim, lineWidth: 2).frame(width: size, height: size))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    /// The member fill at `index` (the prototype cycles three tints).
    static func fillHex(_ index: Int) -> String {
        DetailInk.avatarFills[((index % DetailInk.avatarFills.count) + DetailInk.avatarFills.count) % DetailInk.avatarFills.count]
    }
}

/// The page's transient line after +1, Undo or a failed write (prototype §3.4 toast).
struct DetailToastOverlay: ViewModifier {
    @Binding var toast: KuroToastState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 12)
                    // Reduce Motion / Low Power: a fade, no slide.
                    .transition(KuroMotion.playsMotionNow(reduceMotion: reduceMotion)
                                ? .move(edge: .bottom).combined(with: .opacity) : .opacity)
            }
        }
    }
}
