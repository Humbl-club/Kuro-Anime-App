import SwiftUI

// MARK: - Rail chooser (spec §7.4, D10)

/// "Add to which rail?": the rails the viewer may add to (locked rails only for admins, as
/// `ClubRoomRules.addableRails` decides), with their title count and a lock. Choosing one hands its id
/// back; the page then opens the existing add-item sheet for it.
struct ClubRailChooserSheet: View {
    let rails: [ClubRail]
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let german = KuroLocale.isGerman
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ClubPageHeading(title: ClubRoomCopy.chooserTitle(german: german))
                        .padding(.bottom, 14)
                    ForEach(rails) { rail in
                        Button {
                            KuroAccessibility.selectionHaptic()
                            onPick(rail.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rail.title)
                                        .font(.kuroCustom(15, weight: .medium, relativeTo: .subheadline, maxSize: 30))
                                        .tracking(-0.2)
                                        .foregroundStyle(Color.kuroInk)
                                        .multilineTextAlignment(.leading)
                                    Text(ClubRoomCopy.titleCount(rail.items.count, german: german)
                                         + (rail.is_locked ? ClubRoomCopy.locked(german: german) : ""))
                                        .font(.kuroCustom(10, relativeTo: .caption2, maxSize: 20))
                                        .foregroundStyle(Color.kuroMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if rail.is_locked {
                                    Image(systemName: "lock")
                                        .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 20))
                                        .foregroundStyle(Color.kuroMuted)
                                        .accessibilityHidden(true)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.kuroCustom(12, relativeTo: .footnote, maxSize: 20))
                                    .foregroundStyle(Color.kuroMuted)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 10)
                            .frame(minHeight: 60)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HomeContactStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, KuroDesignSpacing.xxl)
                .kuroReadableWidth()
            }
            .background(Color.kuroCanvasHome)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KuroLocale.text("Cancel", "Abbrechen")) { dismiss() }
                        .font(.kuroBody(weight: .regular))
                        .tint(Color.kuroInk)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}
