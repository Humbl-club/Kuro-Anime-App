import SwiftUI

// MARK: - "Voiced by" glance card (details-songs spec §9.1, item 4)
// One Home glance card per Japanese voice actor: eyebrow "JAPANESE VOICE", a 34 pt disc (photo or ink
// initials), the name 14 semibold −0.3, "Voice actor · {n} roles in Kuro" (the count part only once it is
// known), "›". Tap pushes the staff page; Back (or N5 from the staff page's role row) returns here.

struct EntityVoiceCard: View {
    let staff: Staff
    /// nil while the person's roles load (the count part is left out).
    let roleCount: Int?

    @Environment(\.kuroRoutes) private var routes
    @Environment(\.kuroSuppressCardTaps) private var suppressCardTaps

    var body: some View {
        let german = KuroLocale.isGerman
        let name = staff.nameFull ?? DetailCopy.unknown(german: german)
        let line = EntityPageCopy.voiceActorLine(roles: roleCount, german: german)
        Button {
            guard !suppressCardTaps else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openStaff(staff)
        } label: {
            EntityGlanceShell(minHeight: 60) {
                HStack(spacing: 12) {
                    EntityPortrait(imageURL: staff.imageLarge, name: name, width: 34, height: 34, cornerRadius: 17)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EntityPageCopy.japaneseVoice(german: german))
                            .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 18))
                            .tracking(1.05)
                            .foregroundStyle(HomeInk.kicker)
                        Text(name)
                            .font(.detailSF(14, .semibold, relativeTo: .subheadline))
                            .tracking(-0.3)
                            .foregroundStyle(HomeInk.glanceInk)
                            .lineLimit(2)
                        Text(line)
                            .font(.detailSF(10, relativeTo: .footnote))
                            .foregroundStyle(HomeInk.glanceMuted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("›")
                        .font(.detailSF(15, relativeTo: .body))
                        .foregroundStyle(HomeInk.glanceMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(HomeContactStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(EntityPageCopy.japaneseVoice(german: german).capitalized), \(line)")
        .accessibilityAddTraits(.isButton)
    }
}
