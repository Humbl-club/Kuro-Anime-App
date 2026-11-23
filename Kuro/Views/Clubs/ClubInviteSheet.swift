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
    var clubId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        let german = KuroLocale.isGerman
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    screeningTicket(german: german)

                    HStack(spacing: 10) {
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

    private func screeningTicket(german: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ClubSeal(ring: ClubSeal.compactRing, crest: ClubCrestStore.crest(for: clubId))
                        .accessibilityHidden(true)
                    Text(KuroLocale.text("PRIVATE SCREENING PASS", "PRIVATER CLUB-PASS"))
                        .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 16))
                        .tracking(1.3)
                        .foregroundStyle(ClubRoomPalette.kicker)
                    Spacer(minLength: 8)
                }

                Text(clubName)
                    .font(.kuroEditorial(size: 24))
                    .foregroundStyle(ClubRoomPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)

            // Tear-off perforation with side ticket cutouts.
            ZStack {
                ClubTicketPerforation()
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                HStack {
                    Circle()
                        .fill(Color.kuroCanvasHome)
                        .frame(width: 16, height: 16)
                        .offset(x: -8)
                    Spacer()
                    Circle()
                        .fill(Color.kuroCanvasHome)
                        .frame(width: 16, height: 16)
                        .offset(x: 8)
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(KuroLocale.text("Invite code", "Einladungscode"))
                    .font(.kuroCustom(9, weight: .medium, relativeTo: .caption2, maxSize: 18))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(ClubRoomPalette.kicker)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: code)
                    .font(.kuroCustom(26, weight: .semibold, design: .monospaced, relativeTo: .title2, maxSize: 44))
                    .tracking(3.2)
                    .foregroundStyle(Color.white)
                    .textSelection(.enabled)
                    .accessibilityLabel(KuroLocale.text("Invite code", "Einladungscode"))
                    .accessibilityValue(code.map(String.init).joined(separator: " "))
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.kuroControlInk, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
    }
}

private struct ClubTicketPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Neutral light gallery key face: 44 pt, radius 10.
struct ClubPaperKeyFace: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .font(.kuroCustom(13, weight: .semibold, relativeTo: .footnote, maxSize: 26))
            .foregroundStyle(Color.kuroControlInk)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                shape.fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
            )
            .overlay(shape.strokeBorder(Color.kuroKeyRim, lineWidth: 1))
            .contentShape(shape)
    }
}
