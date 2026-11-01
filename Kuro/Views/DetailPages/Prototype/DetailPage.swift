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
// - The status mark folds in List settings (tap), Favourite, Verdict, Where to watch, Add to a club and
//   Share (spec §3b): nothing the live dock offered is removed.

/// The prototype's measured detail colours (PROTOTYPE_SPEC.md §4, detail tables).
enum DetailInk {
    static let eyebrow = Color(hex: "68776F")
    static let disclosure = Color(hex: "59685F")
    static let synopsis = Color(hex: "58635B")
    static let expectation = Color(hex: "56635B")
    static let clubRow = Color(hex: "526459")
    static let avatarFill = Color(hex: "D3DED3")
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

/// SF at a prototype size that still follows Dynamic Type (capped so AX sizes stay legible).
extension Font {
    static func detailSF(_ size: CGFloat, _ weight: Font.Weight = .regular,
                         relativeTo style: UIFont.TextStyle = .body) -> Font {
        .kuroCustom(size, weight: weight, relativeTo: style, maxSize: max(size * 2.2, 22))
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

/// A section heading: SF 17 w550, tracking −0.4 (18/−0.7 for "Seasons"), with an optional quiet note.
struct DetailSectionHeading: View {
    let title: String
    var size: CGFloat = 17
    var tracking: CGFloat = -0.4
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.detailSF(size, .medium, relativeTo: .title3))
                .tracking(tracking)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let note {
                Text(note)
                    .font(.detailSF(size >= 18 ? 10 : 9, relativeTo: .caption2))
                    .foregroundStyle(size >= 18 ? DetailInk.count : DetailInk.castNote)
            }
        }
    }
}

// MARK: - Hero

/// D1: the wide artwork fading into `deep`, then the band with kind kicker, title and status mark.
struct DetailHero<Mark: View>: View {
    let artworkURL: URL?
    let kicker: String
    let title: String
    let material: ArtworkMaterial
    @ViewBuilder let mark: () -> Mark
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            artwork
            heading
        }
        .background(
            LinearGradient(colors: [material.base.color, material.deep.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
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
        let stacked = dynamicTypeSize.isAccessibilitySize
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    titleBlock
                    mark()
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    titleBlock
                    Spacer(minLength: 0)
                    mark()
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(material.deep.color)
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

/// The hero's status mark ("○ Watching" / "Not in your list" + Add). Tapping it opens List settings
/// (the tracking editor, which also offers the status choice for an untracked title); its menu holds
/// Favourite, Verdict, Where to watch, Add to a club and Share.
struct DetailStatusMark: View {
    let entry: LibraryEntry?
    var kind: MediaKind = .anime
    let onListSettings: () -> Void
    let onFavourite: () -> Void
    let onVerdict: () -> Void
    let onProviders: () -> Void
    var onAddToClub: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    private var isTracked: Bool { entry != nil }
    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(DetailStatusCopy.actions(isTracked: isTracked), id: \.self) { action in
                    if handler(action) != nil {
                        // Removing a saved title drops its progress, notes and score: marked destructive.
                        Button(role: action == .favourite && isTracked ? .destructive : nil) {
                            handler(action)?()
                        } label: {
                            Label(DetailStatusCopy.actionTitle(action, isTracked: isTracked, kind: kind, german: german),
                                  systemImage: icon(action))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(DetailInk.statusInk, lineWidth: 1)
                        .frame(width: 5, height: 5)
                    Text(DetailStatusCopy.label(status: entry?.status, kind: kind, german: german))
                        .font(.detailSF(10, relativeTo: .caption1))
                        .foregroundStyle(DetailInk.statusInk)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.detailSF(7, .semibold, relativeTo: .caption2))
                        .foregroundStyle(DetailInk.statusInk.opacity(0.7))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            } primaryAction: {
                onListSettings()
            }
            .accessibilityLabel(DetailStatusCopy.label(status: entry?.status, kind: kind, german: german))
            .accessibilityHint(KuroLocale.text("Opens list settings. More actions in the menu.",
                                               "Öffnet die Listeneinstellungen. Weitere Aktionen im Menü."))
            .accessibilityActions {
                ForEach(DetailStatusCopy.actions(isTracked: isTracked), id: \.self) { action in
                    if let run = handler(action) {
                        Button(DetailStatusCopy.actionTitle(action, isTracked: isTracked, kind: kind, german: german), action: run)
                    }
                }
            }

            if !isTracked {
                Button(action: onListSettings) {
                    Text(KuroLocale.text("Add", "Hinzufügen"))
                        .font(.detailSF(11, .medium, relativeTo: .caption1))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityLabel(KuroLocale.text("Add to your list", "Zur Liste hinzufügen"))
            }
        }
        .fixedSize()
    }

    private func handler(_ action: DetailStatusAction) -> (() -> Void)? {
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

// MARK: - Close

/// The prototype's round close (44 pt, `base` fill, a soft white rim, white ×).
struct DetailCloseButton: View {
    let material: ArtworkMaterial
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: dismiss.callAsFunction) {
            Image(systemName: "xmark")
                .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 20))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(material.base.color, in: Circle())
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
            ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { _, name in
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.detailSF(size > 23 ? 9 : 8, relativeTo: .caption2))
                    .foregroundStyle(DetailInk.avatarInk)
                    .frame(width: size - 4, height: size - 4)
                    .background(DetailInk.avatarFill, in: Circle())
                    .overlay(Circle().strokeBorder(rim, lineWidth: 2).frame(width: size, height: size))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The page's transient line after +1, Undo or a failed write (prototype §3.4 toast).
struct DetailToastOverlay: ViewModifier {
    @Binding var toast: KuroToastState?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
