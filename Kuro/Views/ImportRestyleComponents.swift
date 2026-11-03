import SwiftUI

// MARK: - Import screens in Home's grammar (details-songs spec §13, D16)
// The shared pieces of the AniList import, the MAL file / source chooser, the review / match sheets and
// the import history. They change only the shells, fields, toggles and type: every caller passes its
// EXISTING strings and bindings unchanged (`ImportRestyleTests` pins the strings byte for byte).
//   page heading   eyebrow 9/1.05 `HomeInk.kicker` uppercase, then the title 24 semibold −0.85 ink and
//                  the description 13 pt #646B65 (G§4)
//   refine words   11 pt medium, ink / `kuroMuted`, a 16 × 1.5 ink rule, 44 pt (Discover's refine row)
//   glance field   #FFFEFA, radius 8, 1 pt #293129 @ 0x18, min 44, 14 pt; its label is the eyebrow
//   check rows     44 pt, an 18 pt tick box (radius 4; on: #303932 with a white 10 pt ✓; off: 1 pt
//                  #BFC4BD), the label 13 pt ink, two columns, 1 pt #E3E7E1 rules, inside the calendar
//                  card shell (#FAFCF9, radius 18, 1 pt #D8DDD9)
//   glance card    `HomeInk.glanceFill`, radius 8, 1 pt `glanceBorder`, padding 10/12 (G§8.1)

/// The import screens' measured inks (G§1, G§8.1, the calendar card).
enum ImportInk {
    static let description = Color(hex: "646B65")
    static let shellFill = Color(hex: "FAFCF9")
    static let shellBorder = Color(hex: "D8DDD9")
    static let checkOn = Color(hex: "303932")
    static let checkOff = Color(hex: "BFC4BD")
    static let rule = Color(hex: "E3E7E1")
    static let tagBorder = Color(hex: "4F5A52", opacity: 0.35)
    static let tagInk = Color(hex: "4F5A52")
}

/// Eyebrow (9 pt, 1.05 tracking, uppercase, `HomeInk.kicker`).
struct ImportEyebrow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
            .tracking(1.05)
            .textCase(.uppercase)
            .foregroundStyle(HomeInk.kicker)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The page heading: optional eyebrow, the title (a VoiceOver header) and the description.
struct ImportPageHeading: View {
    var eyebrow: String? = nil
    let title: String
    var description: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { ImportEyebrow(text: eyebrow) }
            Text(title)
                .font(.kuroCustom(24, weight: .semibold, relativeTo: .title2, maxSize: 40))
                .tracking(-0.85)
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 26))
                    .foregroundStyle(ImportInk.description)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }
}

/// One refine word (selected: ink with the 16 × 1.5 rule). With an action it is a 44 pt button.
struct ImportRefineWord: View {
    let title: String
    let isSelected: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                KuroAccessibility.impactHaptic(.light)
                action()
            } label: { face }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isStaticText] : .isStaticText)
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 22))
                .foregroundStyle(isSelected ? Color.kuroInk : Color.kuroMuted)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(isSelected ? Color.kuroInk : Color.clear)
                .frame(width: 16, height: 1.5)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The calendar-card shell around a form (#FAFCF9, radius 18, 1 pt #D8DDD9).
struct ImportCardShell<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ImportInk.shellFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ImportInk.shellBorder, lineWidth: 1))
    }
}

/// Home's glance card as a content shell (`HomeInk.glanceFill`, radius 8, 1 pt border).
struct ImportGlanceCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(HomeInk.glanceFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
            .shadow(color: HomeInk.glanceShadow, radius: 1, y: 1)
    }
}

/// The glance-style text field face (#FFFEFA, radius 8, 1 pt #293129 @ 0x18, min 44, 14 pt).
struct ImportGlanceFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.kuroCustom(14, relativeTo: .subheadline, maxSize: 28))
            .foregroundStyle(Color.kuroInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(HomeInk.glanceFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.glanceBorder, lineWidth: 1))
    }
}

extension View {
    func importGlanceField() -> some View { modifier(ImportGlanceFieldStyle()) }
}

/// One option of a check grid: its EXISTING label and the binding it toggles.
struct ImportCheckOption: Identifiable {
    let title: String
    let isOn: Binding<Bool>
    var id: String { title }
}

/// Check rows in two columns (one at accessibility sizes), 1 pt rules between rows. Several can be on.
struct ImportCheckGrid: View {
    let options: [ImportCheckOption]
    /// The VoiceOver hint each row carries (the shipped "Toggles this filter").
    var hint: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: options.count, by: columns).map { Array(options[$0..<min($0 + columns, options.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 16) {
                    ForEach(row) { option in
                        ImportCheckRow(title: option.title, isOn: option.isOn, hint: hint)
                    }
                    if row.count < columns { Color.clear.frame(maxWidth: .infinity, minHeight: 44) }
                }
                if index < rows.count - 1 {
                    Rectangle().fill(ImportInk.rule).frame(height: 1)
                }
            }
        }
    }
}

/// A check row: the label (13 pt ink) and the 18 pt tick box; a toggle for VoiceOver ("Completed, on").
struct ImportCheckRow: View {
    let title: String
    let isOn: Binding<Bool>
    var hint: String? = nil

    var body: some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 26))
                    .foregroundStyle(Color.kuroInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ImportTickBox(isOn: isOn.wrappedValue)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? KuroLocale.text("On", "An") : KuroLocale.text("Off", "Aus"))
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(hint ?? "")
    }
}

/// The 18 pt tick box (decorative: the row speaks).
struct ImportTickBox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                RoundedRectangle(cornerRadius: 4).fill(ImportInk.checkOn)
                Image(systemName: "checkmark")
                    .font(.kuroCustom(10, weight: .bold, relativeTo: .caption2, maxSize: 14))
                    .foregroundStyle(Color.white)
            } else {
                RoundedRectangle(cornerRadius: 4).strokeBorder(ImportInk.checkOff, lineWidth: 1)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// A hairline stamp for a fact (replaces the grey capsule pills): 9 pt, 1 pt border, radius 3.
struct ImportTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 18))
            .tracking(0.4)
            .foregroundStyle(ImportInk.tagInk)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ImportInk.tagBorder, lineWidth: 1))
    }
}

/// Quiet note under a form (10 pt muted).
struct ImportNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 22))
            .foregroundStyle(Color.kuroMuted)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The NEW eyebrow of the AniList import ("IMPORT · ANILIST" in both languages; uppercased by style).
nonisolated enum ImportRestyleCopy {
    static func aniListEyebrow(german: Bool) -> String { "Import · AniList" }
}
