import SwiftUI
import UIKit

// MARK: - Invite tool (spec §7.4, D9)
// A tool over the club page for owners and admins (the server sends `invite_code` only to them): the
// kicker, the code in 24 pt mono, Copy / Copied and the system share sheet with the share text
// Settings sends (`ClubInviteCopy`). Grabber and Cancel; it leaves the journey (N7, N8). Settings
// keeps its own invite block.

struct ClubInviteSheet: View {
    let clubName: String
    let code: String

    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        let german = KuroLocale.isGerman
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(KuroLocale.text("Invite code", "Einladungscode"))
                        .font(.kuroCustom(9, relativeTo: .caption2, maxSize: 18))
                        .tracking(1.05)
                        .textCase(.uppercase)
                        .foregroundStyle(HomeInk.kicker)
                        .accessibilityAddTraits(.isHeader)

                    Text(verbatim: code)
                        .font(.kuroCustom(24, weight: .medium, design: .monospaced, relativeTo: .title2, maxSize: 44))
                        .tracking(3)
                        .foregroundStyle(Color.kuroInk)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                        .accessibilityLabel(KuroLocale.text("Invite code", "Einladungscode"))
                        .accessibilityValue(code.map(String.init).joined(separator: " "))

                    Text(clubName)
                        .font(.kuroEditorial(size: 17))
                        .foregroundStyle(Color.kuroMuted)
                        .padding(.top, 6)
                        .accessibilityHidden(true)

                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = code
                            KuroAccessibility.successHaptic()
                            withAnimation(KuroMotion.resolve(KuroMotion.settle)) { didCopy = true }
                            AccessibilityNotification.Announcement(KuroLocale.text("Code copied", "Code kopiert")).post()
                        } label: {
                            Label(didCopy ? KuroLocale.text("Copied", "Kopiert") : KuroLocale.text("Copy", "Kopieren"),
                                  systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .modifier(ClubPaperKeyFace())
                        }
                        .buttonStyle(HomeContactStyle())

                        ShareLink(
                            item: ClubInviteCopy.shareText(clubName: clubName, code: code, german: german),
                            subject: Text(ClubInviteCopy.shareSubject(clubName: clubName, german: german)),
                            message: Text(ClubInviteCopy.shareMessage(code: code, german: german))
                        ) {
                            Label(KuroLocale.text("Share the invite", "Einladung teilen"), systemImage: "square.and.arrow.up")
                                .modifier(ClubPaperKeyFace())
                        }
                        .buttonStyle(HomeContactStyle())
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, KuroDesignSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// The light paper key face (the `KuroKeyFace(.light)` recipe at full width): 44 pt, radius 7.
struct ClubPaperKeyFace: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        content
            .font(.kuroCustom(13, weight: .medium, relativeTo: .footnote, maxSize: 26))
            .foregroundStyle(Color(hex: "29352C"))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                shape.fill(LinearGradient(colors: [.kuroKeyLightTop, .kuroKeyLightBottom], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(hex: "142319", opacity: Double(0x12) / 255), radius: 0.5, y: 1)
            )
            .overlay(shape.strokeBorder(Color(hex: "202823", opacity: Double(0x26) / 255), lineWidth: 1))
            .contentShape(shape)
    }
}
